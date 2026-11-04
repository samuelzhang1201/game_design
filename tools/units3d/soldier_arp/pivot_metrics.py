#!/usr/bin/env python3
"""Measure frozen native skin and explicit physical contacts; never certify motion.

Stdlib only. Exit 0 means report generated/MATCH, including adverse measurements.
Missing physical evidence stays PENDING. --contact-input is an external, hashed
measurement input, never a policy/certificate or a fitted animated ground plane.
"""
import argparse
import base64
from contextlib import ExitStack
import hashlib
import json
import math
from pathlib import Path
import struct
import sqlite3
import sys
import tempfile
import zlib

import test_pivot_feasibility as frozen

FIXTURE_SHA256 = 'e1f2a783bff16aa3371823d5844c195634ac7ae0d9be21fd0692a9e1aceb10c5'
require = frozen.require


def number(x):
    return type(x) in (int, float) and math.isfinite(x)


def vector(v):
    require(isinstance(v, (list, tuple)) and len(v) == 3 and all(number(x) for x in v), 'invalid vector')


def matrix(m):
    require(isinstance(m, list) and len(m) == 4 and all(isinstance(r, list) and len(r) == 4
            and all(number(x) for x in r) for r in m), 'invalid matrix')
    require(m[3] == [0, 0, 0, 1], 'non-affine matrix')


def inverse_basis(m):
    matrix(m)
    a, b, c = [r[:3] for r in m[:3]]
    cross = lambda u, v: [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    cof = [cross(b, c), cross(c, a), cross(a, b)]
    det = sum(a[k] * cof[0][k] for k in range(3))
    require(number(det) and det > 0, 'non-positive/singular basis')
    return [[cof[c][r] / det for c in range(3)] for r in range(3)]


def point(m, p):
    return [sum(m[r][k]*p[k] for k in range(3)) + m[r][3] for r in range(3)]


def plane_frame(origin, normal, transform):
    vector(origin)
    vector(normal)
    inv = inverse_basis(transform)
    n = [sum(inv[c][r]*normal[c] for c in range(3)) for r in range(3)]
    length = math.hypot(*n)
    require(number(length) and length > 0, 'invalid normal')
    return point(transform, origin), [x / length for x in n]


def contact(anchor, position, origin, normal, scale, unit_m):
    for v in [anchor, position, origin, normal]:
        vector(v)
    require(number(scale) and scale > 0 and number(unit_m) and unit_m > 0, 'invalid scale/units')
    length = math.hypot(*normal)
    require(number(length) and length > 0, 'invalid normal')
    n = [x / length for x in normal]
    signed = sum((position[k]-origin[k])*n[k] for k in range(3))
    delta = [position[k]-anchor[k] for k in range(3)]
    dn = sum(delta[k]*n[k] for k in range(3))
    slip = math.hypot(*(delta[k]-dn*n[k] for k in range(3)))
    # Outward guard for double arithmetic; capture/terrain uncertainty is separate input.
    guard = 256 * math.ulp(max(1., *(abs(x) for v in [anchor, position, origin] for x in v)))
    require(all(number(x) for x in [signed, slip, guard]), 'nonfinite contact result')
    return {'signed_world_m': signed*unit_m, 'penetration_world_m': max(0., -signed)*unit_m,
            'hover_world_m': max(0., signed)*unit_m, 'slip_world_m': slip*unit_m,
            'signed_model_um': signed/scale*1e6, 'slip_model_um': slip/scale*1e6,
            'roundoff_model_um': guard/scale*1e6}


def provenance(p):
    require(isinstance(p, dict) and isinstance(p.get('source'), str) and p['source'].strip()
            and isinstance(p.get('sha256'), str) and len(p['sha256']) == 64
            and all(c in '0123456789abcdef' for c in p['sha256']), 'missing provenance')


def validate_contact_input(evidence, cases):
    if evidence is None:
        return ['physical ground/placement', 'material stance intervals', 'external contact budget']
    provenance(evidence['provenance'])
    m, scale = evidence['placement'], evidence['original_scale']
    inverse_basis(m)
    require(number(scale) and scale > 0, 'invalid original scale')
    for r in range(3):
        for c in range(3):
            value = sum(m[k][r]*m[k][c] for k in range(3))
            require(abs(value - (scale*scale if r == c else 0)) <= 1e-10*scale*scale,
                    'placement differs from original uniform scale')
    require(number(evidence['world_unit_m']) and evidence['world_unit_m'] > 0, 'invalid world units')
    require(number(evidence['numeric_error_model_m']) and evidence['numeric_error_model_m'] >= 0,
            'invalid capture/terrain numeric error bound')
    return validate_material_cases(evidence, cases)


def validate_material_cases(evidence, cases):
    missing = []
    rows = evidence['cases']
    require(len(rows) == len(cases), 'physical case coverage missing')
    for row, case in zip(rows, cases):
        require(row['turn_udeg'] == case['op']['turn_udeg'], 'physical case order/turn mismatch')
        ground = row['ground']
        vector(ground['origin'])
        vector(ground['normal'])
        require(number(math.hypot(*ground['normal'])) and math.hypot(*ground['normal']) > 0, 'invalid ground normal')
        ids = set()
        for patch in row['patches']:
            require(isinstance(patch['id'], str) and patch['id'] and patch['id'] not in ids, 'duplicate/invalid patch')
            ids.add(patch['id'])
            require(patch['kind'] in ['stance', 'swing', 'toe'], 'invalid interval kind')
            start, end = patch['start'], patch['end']
            require(number(start) and number(end) and 0 <= start < end <= 1, 'invalid interval')
            require(start in case['phases'] and end in case['phases'], 'uncaptured interval endpoint')
            vertices = patch['vertices']
            require(vertices and len(set(vertices)) == len(vertices) and all(type(v) is int and 0 <= v < 20880
                    for v in vertices), 'invalid material vertices')
            require(len(patch['anchors']) == len(vertices), 'missing physical world anchors')
            for anchor in patch['anchors']:
                vector(anchor)
            for other in row['patches']:
                if other is not patch and set(vertices) & set(other['vertices']):
                    require(max(start, other['start']) >= min(end, other['end']), 'overlapping material intervals')
        require(row['patches'], 'missing material intervals')
        covered = 0.
        for patch in sorted(row['patches'], key=lambda p: p['start']):
            if patch['start'] > covered:
                missing.append(f"case {row['turn_udeg']}: missing material intervals {covered}..{patch['start']}")
            covered = max(covered, patch['end'])
        if covered < 1:
            missing.append(f"case {row['turn_udeg']}: missing material intervals {covered}..1.0")
    budget = evidence.get('budget')
    if budget is not None:
        require(type(budget['contact_um']) is int and budget['contact_um'] >= 0, 'invalid contact budget')
        provenance({'source': budget.get('authority'), 'sha256': budget.get('source_sha256')})
    return missing + ([] if budget is not None else ['external contact budget'])


def budget_status(error_um, guard_um, budget):
    if budget is None:
        return 'PENDING'
    return 'WITHIN_FINITE_SAMPLES' if math.ceil(error_um + guard_um) <= budget['contact_um'] else 'FAIL'



def exact_keys(value, keys):
    require(isinstance(value, dict) and set(value) == set(keys.split()), 'unknown/missing raw schema fields')


def compact(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def decode_raw_observation(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate raw JSON key')
            result[key] = value
        return result
    def finite(text):
        value = float(text)
        require(math.isfinite(value), 'nonfinite raw JSON number')
        return value
    def invalid(text):
        raise ValueError('nonfinite raw JSON number: ' + text)
    result = json.loads(raw, object_pairs_hook=pairs, parse_float=finite, parse_constant=invalid)
    require(isinstance(result, dict), 'raw observation must be an object')
    return result


STREAM_ROWS = 4096
STREAM_DECODED = 16 * 1024 * 1024
STREAM_LINE = 32 * 1024 * 1024
RAW_SCHEMA = 'infantry-pivot-raw-observation/v1'


def stream_prefix(kind, header):
    require(kind in ('requests', 'responses'), 'invalid query stream kind')
    keys = 'observation_header_sha256 fixture_sha256 surface_manifest_sha256 evidence'
    if kind == 'responses':
        keys += ' request_stream_sha256'
    exact_keys(header, keys)
    require(isinstance(header['evidence'], dict), 'invalid query evidence')
    for name, payload in header['evidence'].items():
        require(isinstance(name, str) and name, 'invalid query evidence name')
        exact_keys(payload, 'sha256 data_base64')
        require(hashlib.sha256(base64.b64decode(payload['data_base64'], validate=True)).hexdigest() == payload['sha256'],
                'query evidence bytes mismatch')
    for key, value in header.items():
        if key != 'evidence':
            provenance({'source': key, 'sha256': value})
    return compact({'schema': RAW_SCHEMA, 'kind': kind, 'header': header})[:-1] + b',\n'


class QueryWriter:
    def __init__(self, output, kind, header):
        self.output, self.kind = output, kind
        self.count = self.total_bytes = self.chunks = self.chunk_rows = 0
        self.digest, self.file_digest = hashlib.sha256(), hashlib.sha256()
        self.pending = bytearray()
        self.finished = False
        self.write(stream_prefix(kind, header))
        self.write(b'"chunks":[\n')

    def write(self, data):
        self.output.write(data)
        self.file_digest.update(data)

    def flush(self):
        data = bytes(self.pending)
        chunk = {'chunk_index': self.chunks, 'first_ordinal': self.count-self.chunk_rows, 'row_count': self.chunk_rows,
                 'decoded_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                 'data_base64': base64.b64encode(zlib.compress(data)).decode('ascii')}
        line = (b',' if self.chunks else b'') + compact(chunk) + b'\n'
        require(len(line) <= STREAM_LINE, 'encoded query chunk exceeds limit')
        self.write(line)
        self.digest.update(data)
        self.total_bytes += len(data)
        self.chunks += 1
        self.pending.clear()
        self.chunk_rows = 0

    def add(self, row):
        require(not self.finished, 'query writer cannot restart')
        ordinal = row['request']['ordinal'] if self.kind == 'responses' else row['ordinal']
        require(type(ordinal) is int and ordinal == self.count, 'query row ordinal mismatch')
        data = compact(row) + b'\n'
        require(len(data) <= STREAM_DECODED, 'query row exceeds decoded limit')
        if self.chunk_rows and (self.chunk_rows == STREAM_ROWS or len(self.pending)+len(data) > STREAM_DECODED):
            self.flush()
        self.pending.extend(data)
        self.chunk_rows += 1
        self.count += 1

    def finish(self):
        require(not self.finished, 'query writer cannot restart')
        if self.chunk_rows:
            self.flush()
        self.finished = True
        footer = {'chunk_count': self.chunks, 'row_count': self.count, 'decoded_bytes': self.total_bytes,
                  'stream_sha256': self.digest.hexdigest()}
        self.write(b'],"footer":' + compact(footer) + b'}\n')
        return footer


def write_query_stream(output, kind, header, rows):
    writer = QueryWriter(output, kind, header)
    for row in rows:
        writer.add(row)
    return writer.finish()


class QueryStream:
    """Bounded, exact-byte reader. Completion/hash properties exist only after EOF."""
    def __init__(self, source, kind, header):
        self.source, self.kind = source, kind
        self.file_digest = hashlib.sha256()
        require(self.line() == stream_prefix(kind, header), 'query stream header mismatch')
        require(self.line() == b'"chunks":[\n', 'missing query chunks')
        self.started = False

    def line(self):
        data = self.source.readline(STREAM_LINE+1)
        require(data and len(data) <= STREAM_LINE and data.endswith(b'\n'), 'truncated/oversize query stream line')
        self.file_digest.update(data)
        return data

    def __iter__(self):
        require(not self.started, 'query stream cannot restart')
        self.started = True
        count = total_bytes = chunks = 0
        digest = hashlib.sha256()
        while True:
            line = self.line()
            if line.startswith(b'],"footer":'):
                footer = {'chunk_count': chunks, 'row_count': count, 'decoded_bytes': total_bytes,
                          'stream_sha256': digest.hexdigest()}
                require(line == b'],"footer":' + compact(footer) + b'}\n', 'query stream footer mismatch')
                require(self.source.read(1) == b'', 'trailing query stream bytes')
                self.footer, self.file_sha256 = footer, self.file_digest.hexdigest()
                return
            prefix = b',' if chunks else b''
            require(line.startswith(prefix), 'query chunk separator mismatch')
            chunk = decode_raw_observation(line[len(prefix):])
            exact_keys(chunk, 'chunk_index first_ordinal row_count decoded_bytes sha256 data_base64')
            require(line == prefix+compact(chunk)+b'\n', 'noncanonical query chunk bytes')
            require(all(type(chunk[k]) is int for k in ('chunk_index', 'first_ordinal', 'row_count', 'decoded_bytes')),
                    'invalid query chunk counts')
            require(chunk['chunk_index'] == chunks and chunk['first_ordinal'] == count,
                    'query chunk order/restart mismatch')
            require(0 < chunk['row_count'] <= STREAM_ROWS and 0 < chunk['decoded_bytes'] <= STREAM_DECODED,
                    'query chunk limits exceeded')
            compressed = base64.b64decode(chunk['data_base64'], validate=True)
            require(base64.b64encode(compressed).decode() == chunk['data_base64'], 'noncanonical base64')
            decoder = zlib.decompressobj()
            decoded = decoder.decompress(compressed, chunk['decoded_bytes']+1)
            require(len(decoded) == chunk['decoded_bytes'] and decoder.eof and not decoder.unused_data
                    and not decoder.unconsumed_tail, 'query decompression excess/trailing/truncated stream')
            require(hashlib.sha256(decoded).hexdigest() == chunk['sha256'], 'query chunk digest mismatch')
            require(decoded.endswith(b'\n') and decoded.count(b'\n') == chunk['row_count'], 'query chunk row count mismatch')
            digest.update(decoded)
            for data in decoded.splitlines(keepends=True):
                row = decode_raw_observation(data)
                require(data == compact(row)+b'\n', 'noncanonical query row bytes')
                ordinal = row['request']['ordinal'] if self.kind == 'responses' else row['ordinal']
                require(type(ordinal) is int and ordinal == count, 'query row ordinal mismatch')
                count += 1
                yield row
            chunks += 1
            total_bytes += len(decoded)


def raw_uniformity(m, scale):
    inverse_basis(m)
    require(number(scale) and scale > 0, 'invalid original scale')
    gram = [[sum(m[k][r]*m[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
    residuals = [[abs(gram[r][c] - (scale*scale if r == c else 0)) for c in range(3)] for r in range(3)]
    threshold = 1e-10*scale*scale
    require(number(threshold) and threshold > 0 and all(number(x) for row in residuals for x in row),
            'nonfinite/underflow Gram comparison')
    worst = max(((r, c) for r in range(3) for c in range(3)), key=lambda rc: residuals[rc[0]][rc[1]])
    return {'status': 'PREDICATE_SATISFIED' if all(x <= threshold for row in residuals for x in row) else 'FAIL',
            'gram': gram, 'residuals': residuals, 'original_scale': scale, 'threshold': threshold,
            'worst_indices': list(worst)}


def raw_word(word, precision):
    require(precision in ['binary32', 'binary64'], 'unknown raw scalar precision')
    size, fmt = (8, '>f') if precision == 'binary32' else (16, '>d')
    require(isinstance(word, str) and len(word) == size and all(c in '0123456789abcdef' for c in word),
            'invalid raw IEEE word')
    value = struct.unpack(fmt, bytes.fromhex(word))[0]
    require(number(value), 'nonfinite raw IEEE word')
    return value


def validate_raw_observation(observation, cases):
    """Validate the additive wire modes; hashes bind bytes, never authority/truth."""
    exact_keys(observation, 'schema kind header chunks footer')
    require(observation['schema'] == 'infantry-pivot-raw-observation/v1' and observation['kind'] == 'observation',
            'unknown raw observation schema/kind')
    require(observation['chunks'] == [] and observation['footer'] == {
        'chunk_count': 0, 'row_count': 0, 'decoded_bytes': 0, 'stream_sha256': hashlib.sha256(b'').hexdigest()},
        'observation must have empty stream')
    h = observation['header']
    exact_keys(h, 'surface_mode provenance inputs placement frame cases surfaces uncertainty budget evidence')
    require(h['surface_mode'] in ('fixed_plane', 'native_queries'), 'unsupported raw surface mode')
    native_mode = h['surface_mode'] == 'native_queries'
    require(isinstance(h['evidence'], dict), 'missing raw evidence payloads')
    hashes = set()
    for name, payload in h['evidence'].items():
        require(isinstance(name, str) and name, 'invalid evidence name')
        exact_keys(payload, 'sha256 data_base64')
        data = base64.b64decode(payload['data_base64'], validate=True)
        require(hashlib.sha256(data).hexdigest() == payload['sha256'], 'raw evidence bytes changed')
        hashes.add(payload['sha256'])
    def reference(ref):
        exact_keys(ref, 'source sha256')
        provenance(ref)
        require(ref['sha256'] in hashes, 'missing raw provenance payload bytes')
    provenance_fields = 'source sha256 capture_tool capture_version engine_build terrain_build capture_frame capture_time'
    exact_keys(h['provenance'], provenance_fields)
    provenance(h['provenance'])
    require(h['provenance']['sha256'] in hashes, 'missing raw provenance payload bytes')
    require(all(isinstance(h['provenance'][k], str) and h['provenance'][k].strip()
                for k in provenance_fields.split()), 'missing raw capture identity')
    inputs = h['inputs']
    exact_keys(inputs, 'fixture_sha256 source_sha256 native installed placement terrain')
    require(inputs['fixture_sha256'] == FIXTURE_SHA256 and inputs['source_sha256'] == frozen.HASHES,
            'raw frozen input identity mismatch')
    for name in ['native', 'installed', 'placement', 'terrain']:
        exact_keys(inputs[name], 'source sha256')
        reference(inputs[name])
    placement = h['placement']
    exact_keys(placement, 'matrix original_scale world_unit_m precision scale_precision matrix_bits scale_bits construction_inputs unavailable_reason')
    m, scale, units = [placement[k] for k in ['matrix', 'original_scale', 'world_unit_m']]
    uniformity = raw_uniformity(m, scale)
    require(number(units) and units > 0 and number(scale*units) and scale*units > 0, 'invalid world units')
    words = placement['matrix_bits']
    require(isinstance(words, list) and len(words) == 4 and all(isinstance(r, list) and len(r) == 4 for r in words),
            'missing raw matrix bits')
    for values, bits in zip(m, words):
        for value, word in zip(values, bits):
            decoded = raw_word(word, placement['precision'])
            require(struct.pack('>d', value) == struct.pack('>d', decoded), 'raw matrix bits/value mismatch')
    require(struct.pack('>d', scale) == struct.pack('>d', raw_word(placement['scale_bits'], placement['scale_precision'])),
            'raw scale bits/value mismatch')
    if placement['construction_inputs'] is None:
        require(isinstance(placement['unavailable_reason'], str) and placement['unavailable_reason'].strip(),
                'missing original construction input reason')
    else:
        exact_keys(placement['construction_inputs'], 'source sha256')
        reference(placement['construction_inputs'])
        require(placement['unavailable_reason'] is None, 'conflicting construction provenance')
    frame = h['frame']
    exact_keys(frame, 'units coordinate_frame up height_query_chart terrain_transform provenance')
    require(frame['units'] == 'world_coordinate_units' and isinstance(frame['coordinate_frame'], str)
            and frame['coordinate_frame'] and frame['up'] == [0, 1, 0]
            and frame['height_query_chart'] == 'world_xz_y_up', 'unsupported raw frame/chart')
    inverse_basis(frame['terrain_transform'])
    reference(frame['provenance'])
    surfaces = {}
    for surface in h['surfaces']:
        if native_mode:
            validate_native_surface(surface, reference, frame)
            sid = surface['id']
            require(isinstance(sid, str) and sid and sid not in surfaces, 'duplicate/unsupported raw surface')
        else:
            exact_keys(surface, 'id kind origin normal domain provenance')
            sid = surface['id']
            require(isinstance(sid, str) and sid and sid not in surfaces and surface['kind'] == 'fixed_plane',
                    'duplicate/unsupported raw surface')
            vector(surface['origin'])
            vector(surface['normal'])
            require(number(math.hypot(*surface['normal'])) and math.hypot(*surface['normal']) > 0
                    and surface['normal'][1] > 0, 'invalid upward plane normal')
        domain = surface['domain']
        exact_keys(domain, 'xz_min xz_max')
        require(all(isinstance(domain[k], list) and len(domain[k]) == 2 and all(number(x) for x in domain[k])
                    for k in domain) and all(domain['xz_min'][k] < domain['xz_max'][k] for k in range(2)),
                'invalid fixed-plane domain')
        reference(surface['provenance'])
        surfaces[sid] = surface
    require(len(h['cases']) == len(cases), 'raw case coverage missing')
    legacy_rows = []
    for row, case in zip(h['cases'], cases):
        exact_keys(row, 'turn_udeg duration_q entry_phase_id exit_phase_id phase_ids surface_id provenance patches')
        require(type(row['turn_udeg']) is int and type(row['duration_q']) is int
                and row['turn_udeg'] == case['op']['turn_udeg'] and row['duration_q'] == case['op']['duration_q']
                and row['entry_phase_id'] == float(case['op']['march_entry_phase']).hex()
                and row['exit_phase_id'] == float(case['op']['march_exit_phase']).hex()
                and row['phase_ids'] == [float(u).hex() for u in case['phases']], 'raw case/phase identity mismatch')
        reference(row['provenance'])
        require(row['surface_id'] in surfaces, 'missing raw surface')
        surface = surfaces[row['surface_id']]
        for patch in row['patches']:
            exact_keys(patch, 'id kind start end vertices anchors provenance')
            reference(patch['provenance'])
        legacy_rows.append({'turn_udeg': row['turn_udeg'], 'patches': row['patches'],
                            'ground': {'origin': [0., 0., 0.] if native_mode else surface['origin'],
                                       'normal': [0., 1., 0.] if native_mode else surface['normal']}})
    missing = validate_material_cases({'cases': legacy_rows, 'budget': h['budget']}, cases)
    for row in h['cases']:
        vertices = sorted({v for p in row['patches'] for v in p['vertices']})
        for vertex in vertices:
            covered = 0.
            for patch in sorted((p for p in row['patches'] if vertex in p['vertices']),
                                key=lambda p: p['start']):
                if patch['start'] > covered:
                    missing.append(f"case {row['turn_udeg']} vertex {vertex}: missing material intervals {covered}..{patch['start']}")
                covered = max(covered, patch['end'])
            if covered < 1:
                missing.append(f"case {row['turn_udeg']} vertex {vertex}: missing material intervals {covered}..1.0")
    unknown = []
    if native_mode:
        require(isinstance(h['uncertainty'], dict) and h['uncertainty'], 'missing native uncertainty records')
        for identity, terms in h['uncertainty'].items():
            require(isinstance(identity, str) and identity, 'invalid uncertainty ID')
            exact_keys(terms, 'position height normal query_coordinate anchor height_lipschitz normal_lipschitz')
            for name, bound in terms.items():
                exact_keys(bound, 'value unit derivation sha256 reason')
                unit = 'dimensionless' if name in ('normal', 'height_lipschitz') else '1/m' if name == 'normal_lipschitz' else 'm'
                require(bound['unit'] == unit, 'raw uncertainty units mismatch')
                require(isinstance(bound['derivation'], str) and bound['derivation'].strip(), 'missing uncertainty derivation')
                if bound['value'] is None:
                    require(isinstance(bound['reason'], str) and bound['reason'].strip(), 'missing unknown uncertainty reason')
                    unknown.append(identity + ':' + name)
                else:
                    require(number(bound['value']) and bound['value'] >= 0 and bound['reason'] is None, 'invalid uncertainty bound')
                    reference({'source': bound['derivation'], 'sha256': bound['sha256']})
                    if bound['value'] == 0:
                        require(h['provenance']['source'] == 'synthetic' and bound['derivation'] == 'exact synthetic',
                                'zero uncertainty requires exact synthetic evidence')
    else:
        exact_keys(h['uncertainty'], 'position height normal query_coordinate anchor')
        for name, bound in h['uncertainty'].items():
            exact_keys(bound, 'value unit derivation sha256 reason')
            require(bound['unit'] == ('dimensionless' if name == 'normal' else 'm'), 'raw uncertainty units mismatch')
            require(isinstance(bound['derivation'], str) and bound['derivation'].strip(), 'missing uncertainty derivation')
            if bound['value'] is None:
                require(isinstance(bound['reason'], str) and bound['reason'].strip(), 'missing unknown uncertainty reason')
                unknown.append(name)
            else:
                require(number(bound['value']) and bound['value'] >= 0 and bound['reason'] is None, 'invalid uncertainty bound')
                reference({'source': bound['derivation'], 'sha256': bound['sha256']})
                if bound['value'] == 0:
                    require(h['provenance']['source'] == 'synthetic' and bound['derivation'] == 'exact synthetic',
                            'zero uncertainty requires exact synthetic evidence')
    if h['budget'] is not None:
        exact_keys(h['budget'], 'contact_um authority source_sha256')
        reference({'source': h['budget']['authority'], 'sha256': h['budget']['source_sha256']})
    blockers = missing + ['uncertainty: ' + name for name in unknown]
    if uniformity['status'] == 'FAIL':
        blockers.append('strict placement uniformity FAIL')
    if placement['construction_inputs'] is None:
        blockers.append('original construction inputs unavailable')
    blockers += ['continuous contact/domain proof', 'rendered surface proof', 'independent provenance/authority review']
    return {'header': h, 'placement_uniformity': uniformity, 'surfaces': surfaces,
            'uncertainty_status': 'UNKNOWN' if unknown else 'BOUNDED', 'blockers': blockers,
            'material_gaps': missing, 'observation_header_sha256': hashlib.sha256(compact(h)).hexdigest()}



def validate_native_surface(surface, reference, frame):
    """C surfaces bind resource snapshots and a declared selection, not a terrain emulator.

    Native uncertainty maps IDs to the five B contributors plus height_lipschitz
    (dimensionless) and normal_lipschitz (1/m), justified over the surface domain.
    Normal bounds apply to normalized normals; normalization roundoff is additional.
    Resources before/after must bind the same bytes. Parameters and domain provenance
    bind native method, region/LOD, switch boundaries and their proof obligations.
    """
    exact_keys(surface, 'id kind domain provenance resources terrain_transform region lod method method_version parameters selection')
    require(surface['kind'] in ('terrain_raw', 'sea_clamped', 'height_override', 'rendered_lod'), 'unknown native surface kind')
    exact_keys(surface['resources'], 'before after')
    for ref in surface['resources'].values():
        reference(ref)
    require(surface['resources']['before']['sha256'] == surface['resources']['after']['sha256'],
            'surface resource changed during capture')
    inverse_basis(surface['terrain_transform'])
    require(compact(surface['terrain_transform']) == compact(frame['terrain_transform']), 'surface transform mismatch')
    for key in ('region', 'lod', 'method', 'method_version'):
        require(isinstance(surface[key], str) and surface[key].strip(), 'missing native surface method/region/LOD')
    reference(surface['parameters'])
    selection = surface['selection']
    exact_keys(selection, 'height normal sea_level override_id')
    modes = {'terrain_raw': ('raw', 'raw'), 'sea_clamped': ('max_raw_sea', 'branch'),
             'height_override': ('override', 'override'), 'rendered_lod': ('rendered', 'rendered')}
    require((selection['height'], selection['normal']) == modes[surface['kind']], 'surface selection mismatch')
    if surface['kind'] == 'sea_clamped':
        require(number(selection['sea_level']), 'missing sea level')
    else:
        require(selection['sea_level'] is None, 'unexpected sea level')
    if surface['kind'] == 'height_override':
        reference(selection['override_id'])
    else:
        require(selection['override_id'] is None, 'unexpected height override')


def native_request(state, ordinal, ci, phase, source_id, variant, vertex, p, patch=None):
    h = state['header']
    row = h['cases'][ci]
    surface = state['surfaces'][row['surface_id']]
    position = point(h['placement']['matrix'], p) if patch is None else list(p)
    vector(position)
    bits = [struct.pack('>d', x).hex() for x in position]
    xz = [bits[0], bits[2]]
    query = [struct.pack('>f', position[k]).hex() for k in (0, 2)]
    for word in query:
        raw_word(word, 'binary32')
    return {'ordinal': ordinal, 'case_index': ci, 'turn_udeg': row['turn_udeg'], 'duration_q': row['duration_q'],
            'phase_hex': None if patch is not None else float(phase).hex(), 'source_phase_id': source_id,
            'variant': variant, 'vertex_id': vertex, 'anchor_id': None if patch is None else patch['id'],
            'role': 'vertex' if patch is None else 'anchor',
            'interval_hex': None if patch is None else [float(patch[k]).hex() for k in ('start', 'end')],
            'position_f64': bits, 'intended_xz_f64': xz, 'query_xz_f32': query,
            'surface_id': surface['id'], 'surface_sha256': hashlib.sha256(compact(surface)).hexdigest(),
            'method': surface['method'], 'method_version': surface['method_version']}


def sample_value(record, normal=False, raw=False):
    if record is None:
        return None
    exact_keys(record, 'precision bits')
    words = record['bits'] if normal else [record['bits']]
    require(isinstance(words, list) and len(words) == (3 if normal else 1), 'invalid sampled scalar/vector')
    result = []
    for word in words:
        precision = record['precision']
        require(precision in ('binary32', 'binary64'), 'unknown sampled precision')
        width, fmt = (8, '>f') if precision == 'binary32' else (16, '>d')
        require(isinstance(word, str) and len(word) == width and all(c in '0123456789abcdef' for c in word),
                'invalid sampled IEEE word')
        value = struct.unpack(fmt, bytes.fromhex(word))[0]
        require(raw or number(value), 'nonfinite used surface value')
        result.append(value)
    return result if normal else result[0]


def native_sample(response, request, state, placement_guard=0.):
    exact_keys(response, 'request status raw_height raw_normal used_height used_normal height_surface_id normal_surface_id height_method normal_method capture_id uncertainty_id reason')
    require(compact(response['request']) == compact(request), 'native query echoed identity mismatch')
    require(response['status'] in ('OK', 'HOLE', 'UNAVAILABLE'), 'invalid native query status')
    require(response['capture_id'] == state['header']['provenance']['capture_frame'], 'native capture identity mismatch')
    require(response['uncertainty_id'] in state['header']['uncertainty'], 'unknown native uncertainty identity')
    raw_h = sample_value(response['raw_height'], raw=True)
    raw_n = sample_value(response['raw_normal'], normal=True, raw=True)
    require(response['status'] != 'OK' or ((raw_h is None or number(raw_h))
            and (raw_n is None or all(number(x) for x in raw_n))),
            'nonfinite raw observation requires unavailable status')
    height = sample_value(response['used_height'])
    normal = sample_value(response['used_normal'], normal=True)
    if response['status'] != 'OK' or height is None or normal is None or raw_h is None or raw_n is None:
        require(isinstance(response['reason'], str) and response['reason'].strip(), 'missing unavailable query reason')
    else:
        require(response['reason'] is None, 'conflicting native query reason')
    surface = state['surfaces'][request['surface_id']]
    same_height = response['height_surface_id'] == surface['id'] and response['height_method'] == surface['method']
    same_normal = response['normal_surface_id'] == surface['id'] and response['normal_method'] == surface['method']
    if surface['kind'] == 'sea_clamped':
        sea = surface['selection']['sea_level']
        expected_height = max(raw_h, sea) if raw_h is not None and number(raw_h) else sea
        expected_normal = raw_n if raw_h is not None and number(raw_h) and raw_h > sea else [0., 1., 0.]
    else:
        expected_height, expected_normal = raw_h, raw_n
    if height is not None:
        require(expected_height is not None and number(expected_height)
                and struct.pack('>d', height) == struct.pack('>d', expected_height), 'used height violates surface selection')
    if normal is not None:
        require(expected_normal is not None and all(number(x) for x in expected_normal)
                and all(struct.pack('>d', x) == struct.pack('>d', y) for x, y in zip(normal, expected_normal)),
                'used normal violates surface selection')
    if not same_height:
        height = None
    magnitude = max(map(abs, normal)) if normal is not None else 0.
    normal_roundoff = 0.
    if not same_normal or magnitude == 0 or normal[1] <= 0:
        normal = None
    else:
        # Scale first: tiny/huge finite raw normals must not corrupt normalization.
        scaled = [x/magnitude for x in normal]
        nlen = math.hypot(*scaled)
        normal = [x/nlen for x in scaled]
        if sum(x != 0 for x in scaled) > 1:
            normal_roundoff = 256*math.ulp(1.)
        if normal[1] <= 0:
            normal = None
    p = [raw_word(x, 'binary64') for x in request['position_f64']]
    query = [raw_word(x, 'binary32') for x in request['query_xz_f32']]
    units = state['header']['placement']['world_unit_m']
    rounding = math.hypot(query[0]-p[0], query[1]-p[2])*units
    bounds = {k: v['value'] for k, v in state['header']['uncertainty'][response['uncertainty_id']].items()}
    ep = bounds['anchor' if request['role'] == 'anchor' else 'position']
    guard = 256*math.ulp(max(1., *(abs(x) for x in p), *(abs(x) for x in query)))*units+placement_guard
    radius = None if ep is None or bounds['query_coordinate'] is None else math.nextafter(ep+rounding+bounds['query_coordinate']+guard, math.inf)
    domain_ok = radius is not None
    if domain_ok:
        radius_units = math.nextafter(radius/units, math.inf)
        for j, axis in enumerate((0, 2)):
            domain_ok &= (surface['domain']['xz_min'][j] <= math.nextafter(p[axis]-radius_units, -math.inf)
                          and math.nextafter(p[axis]+radius_units, math.inf) <= surface['domain']['xz_max'][j])
    missing = [k for k, v in bounds.items() if v is None]
    available = response['status'] == 'OK' and raw_h is not None and number(raw_h)
    if not domain_ok:
        missing.append('surface_domain')
    if not available:
        missing.append('surface_unavailable')
    if height is None:
        missing.append('height_sample')
    if normal is None or raw_n is None:
        missing.append('normal_sample')
    eh = en = eq = None
    if domain_ok and available:
        if height is not None and bounds['height'] is not None and bounds['height_lipschitz'] is not None:
            eh = math.nextafter(bounds['height']+bounds['height_lipschitz']*radius, math.inf)
            eq = math.nextafter(math.hypot(radius, eh), math.inf)
        if normal is not None and raw_n is not None and bounds['normal'] is not None and bounds['normal_lipschitz'] is not None:
            en = math.nextafter(bounds['normal']+bounds['normal_lipschitz']*radius+normal_roundoff, math.inf)
    switch = (surface['kind'] == 'sea_clamped' and available and raw_n != [0., 1., 0.]
              and (eh is None or abs(raw_h-surface['selection']['sea_level'])*units <= eh))
    if switch:
        en = None
        missing.append('surface_switch_normal')
    require(all(x is None or number(x) for x in (eh, en, eq)), 'nonfinite propagated query uncertainty')
    covered = domain_ok and eh is not None and en is not None
    return {'height': height, 'normal': normal, 'covered': bool(covered), 'domain_covered': bool(domain_ok),
            'position_error': ep, 'height_error': eh, 'normal_error': en, 'ground_error': eq,
            'rounding_xz_world_m': rounding, 'query_xz_f32': request['query_xz_f32'],
            'missing': missing}


def native_measure(model_point, request, response, anchor_request, anchor_response, state):
    p = [raw_word(x, 'binary64') for x in request['position_f64']]
    a = [raw_word(x, 'binary64') for x in anchor_request['position_f64']] if anchor_request is not None else p
    placement = state['header']['placement']
    scale, units, m = placement['original_scale'], placement['world_unit_m'], placement['matrix']
    placement_guard = max(64*math.ulp(max(1., sum(abs(m[r][k]*model_point[k]) for k in range(3))+abs(m[r][3])))
                          for r in range(3))*4*units
    guard = 256*math.ulp(max(1., *(abs(x) for x in p+a), abs(sample_value(response['used_height']) or 0.)))*units+placement_guard
    # Prove the expanded footprint before using either Lipschitz bound.
    sample = native_sample(response, request, state, guard)
    anchor_sample = native_sample(anchor_response, anchor_request, state) if anchor_request is not None else None
    v = (p[1]-sample['height'])*units if sample['height'] is not None else None
    d = v*sample['normal'][1] if v is not None and sample['normal'] is not None else None
    slip = None
    if anchor_sample is not None and anchor_sample['normal'] is not None:
        delta = [(p[k]-a[k])*units for k in range(3)]
        n = anchor_sample['normal']
        projection = sum(delta[k]*n[k] for k in range(3))
        slip = math.hypot(*(delta[k]-projection*n[k] for k in range(3)))
    covered = sample['covered']
    if anchor_sample is not None:
        covered &= anchor_sample['covered']
    ed = ev = es = None
    if sample['height_error'] is not None and v is not None:
        ev = sample['position_error']+sample['height_error']
    if sample['ground_error'] is not None and sample['normal_error'] is not None and d is not None:
        ep, eq, en = sample['position_error'], sample['ground_error'], sample['normal_error']
        ed = ep+eq+(abs(v)+ep+eq)*en
    if sample['position_error'] is not None and anchor_sample is not None and anchor_sample['normal_error'] is not None and slip is not None:
        ep, ea, ena = sample['position_error'], anchor_sample['position_error'], anchor_sample['normal_error']
        es = ep+ea+(2*ena+ena*ena)*(math.dist(p, a)*units+ep+ea)
    guard += 256*math.ulp(max(1., abs(v or 0.), abs(d or 0.), abs(slip or 0.), ed or 0., ev or 0., es or 0.))
    uniform = state['placement_uniformity']['status'] == 'PREDICATE_SATISFIED'
    error = max(abs(d), slip) if d is not None and slip is not None else None
    upper = None
    if uniform and covered and ed is not None and es is not None:
        upper = math.nextafter((max(abs(d)+ed, slip+es)+guard)/(scale*units)*1e6, math.inf)
    interval = lambda value, uncertainty: None if value is None or uncertainty is None else [
        math.nextafter(value-uncertainty-guard, -math.inf), math.nextafter(value+uncertainty+guard, math.inf)]
    result = {'vertical_world_m': v, 'signed_world_m': d, 'slip_world_m': slip,
              'vertical_penetration_world_m': None if v is None else max(0., -v),
              'vertical_hover_world_m': None if v is None else max(0., v),
              'penetration_world_m': None if d is None else max(0., -d),
              'hover_world_m': None if d is None else max(0., d),
              'vertical_interval_world_m': interval(v, ev), 'signed_interval_world_m': interval(d, ed),
              'slip_interval_world_m': interval(slip, es),
              'error_model_um': error/(scale*units)*1e6 if uniform and error is not None else None,
              'nominal_scale_model_um': error/(scale*units)*1e6 if not uniform and error is not None else None,
              'upper_bound_model_um': upper, 'numeric_guard_world_m': guard,
              'coverage': 'COMPLETE_FINITE' if covered else 'UNCOVERED',
              'query_rounding_xz_world_m': sample['rounding_xz_world_m'],
              'unknown_terms': sample['missing'] + ([] if anchor_sample is None else ['anchor:'+x for x in anchor_sample['missing']])}
    for value in result.values():
        if isinstance(value, float):
            require(number(value), 'nonfinite native measurement')
        elif isinstance(value, list) and value and isinstance(value[0], float):
            require(all(number(x) for x in value), 'nonfinite native interval')
    return result


def query_header(state):
    return {'observation_header_sha256': state['observation_header_sha256'], 'fixture_sha256': FIXTURE_SHA256,
            'surface_manifest_sha256': hashlib.sha256(compact(state['header']['surfaces'])).hexdigest(), 'evidence': {}}


def update_difference(summary, value, source, vertex):
    if value is None or source is None:
        return
    difference = value-source
    require(number(difference), 'nonfinite source-relative observation')
    summary['valid_pairs'] += 1
    for op in ('min', 'max'):
        if summary[op] is None or (difference < summary[op] if op == 'min' else difference > summary[op]):
            summary[op], summary[op+'_vertex'] = difference, vertex


class NativeRun:
    """Vertex requests in case/phase/variant/vertex order, then all fixed anchors.

    Responses are checked twice using the same open file: a bounded integrity pass
    indexes anchors on disk, then regeneration verifies every echoed identity. No
    report is published before both streams and all geometry gates finish. Per-frame
    uncovered identity sets are exact transcript ordinal spans plus counts/digests,
    not unbounded in-memory lists; patch results retain extrema and worst identities.
    """
    def __init__(self, state, vertex_count, *, query_output=None, query_responses=None):
        require((query_output is None) != (query_responses is None), 'native queries need exactly one output or response path')
        self.state, self.vertex_count = state, vertex_count
        self.output_path, self.response_path = query_output, query_responses
        self.frames = [(ci, phase) for ci, row in enumerate(state['header']['cases']) for phase in row['phase_ids']]
        self.expected_vertices = len(self.frames)*3*vertex_count
        self.anchors = {}
        self.anchor_order = []
        ordinal = self.expected_vertices
        for ci, row in enumerate(state['header']['cases']):
            for patch in row['patches']:
                for vertex, a in zip(patch['vertices'], patch['anchors']):
                    require(vertex < vertex_count, 'material vertex outside measured mesh')
                    self.anchors[(ci, patch['id'], vertex)] = (ordinal, patch, a)
                    self.anchor_order.append((ci, patch['id'], vertex))
                    ordinal += 1
        self.expected_rows = ordinal
        self.count = self.frame_index = 0
        self.request_digest = hashlib.sha256()
        self.stack = ExitStack()
        self.writer = None
        self.finished = False
        self.unknown_terms = set()

    def __enter__(self):
        try:
            tmp = Path(self.stack.enter_context(tempfile.TemporaryDirectory(
                prefix='.pivot-query-', dir=self.output_path.parent if self.output_path is not None else None)))
            if self.output_path is not None:
                self.staging = tmp/'requests.json'
                self.output = self.stack.enter_context(self.staging.open('wb'))
                self.writer = QueryWriter(self.output, 'requests', query_header(self.state))
            else:
                self.db = sqlite3.connect(tmp/'anchors.sqlite')
                self.stack.callback(self.db.close)
                self.db.execute('PRAGMA cache_size=-2048')
                self.db.execute('CREATE TABLE anchors (ordinal INTEGER PRIMARY KEY, response BLOB NOT NULL)')
                self.source = self.stack.enter_context(self.response_path.open('rb'))
                first = self.source.readline(STREAM_LINE+1)
                require(len(first) <= STREAM_LINE and first.endswith(b',\n'), 'invalid native response header')
                outer = decode_raw_observation(first[:-2]+b'}')
                header = dict(query_header(self.state), request_stream_sha256=outer['header']['request_stream_sha256'],
                              evidence=outer['header']['evidence'])
                self.source.seek(0)
                stream = QueryStream(self.source, 'responses', header)
                anchors = 0
                for response in stream:
                    req = response['request']
                    require(req['ordinal'] < self.expected_rows, 'extra native response')
                    if req['role'] == 'anchor':
                        anchors += 1
                        require(anchors <= len(self.anchor_order), 'extra native anchor response')
                        self.db.execute('INSERT INTO anchors VALUES (?, ?)', (req['ordinal'], compact(response)))
                require(stream.footer['row_count'] == self.expected_rows, 'missing native response rows')
                require(anchors == len(self.anchor_order), 'missing native anchors')
                self.db.commit()
                self.response_sha256 = stream.file_sha256
                self.response_header = header
                self.source.seek(0)
                self.reader = QueryStream(self.source, 'responses', header)
                self.responses = iter(self.reader)
            return self
        except BaseException:
            self.stack.close()
            raise

    def __exit__(self, kind, value, traceback):
        try:
            if kind is None:
                require(self.finished, 'native query run unfinished')
                if self.writer is not None:
                    self.output.close()
                    self.staging.replace(self.output_path)
        finally:
            self.stack.close()

    def anchor(self, ci, patch_id, vertex):
        ordinal, patch, position = self.anchors[(ci, patch_id, vertex)]
        req = native_request(self.state, ordinal, ci, None, None, None, vertex, position, patch)
        row = self.db.execute('SELECT response FROM anchors WHERE ordinal=?', (ordinal,)).fetchone()
        require(row is not None, 'native anchor identity missing')
        response = decode_raw_observation(row[0])
        native_sample(response, req, self.state)
        return req, response

    def consume(self, request):
        require(request['ordinal'] == self.count, 'request generation order mismatch')
        self.count += 1
        if self.writer is not None:
            self.writer.add(request)
            return None
        self.request_digest.update(compact(request)+b'\n')
        try:
            response = next(self.responses)
        except StopIteration:
            raise ValueError('missing native response') from None
        return response

    def frame(self, points, ci, phase, source_id):
        require(self.frame_index < len(self.frames) and self.frames[self.frame_index] == (ci, float(phase).hex()),
                'native frame order/coverage mismatch')
        require(tuple(points) == ('source', 'reference', 'mapped') and all(len(p) == self.vertex_count for p in points.values()),
                'native variant/vertex coverage mismatch')
        self.frame_index += 1
        out = {}
        source_values, source_patches = [], {}
        row = self.state['header']['cases'][ci]
        entry, exit_ = float.fromhex(row['entry_phase_id']), float.fromhex(row['exit_phase_id'])
        distance = 1. if entry == exit_ else (exit_-entry) % 1.
        native_phase = entry if phase == 0 else exit_ if phase == 1 else (entry+distance*phase) % 1.
        require(source_id == float(native_phase).hex(), 'uncaptured native source request identity')
        patches = [p for p in row['patches'] if p['start'] <= phase < p['end'] or phase == p['end']]
        for label, positions in points.items():
            first_ordinal = self.count
            whole = {key: None for key in ('min_signed', 'max_signed', 'min_vertical', 'max_vertical')}
            worst = dict.fromkeys(whole)
            valid = 0
            intervals = {name: [] for name in ('signed', 'vertical')}
            interval_known = dict.fromkeys(intervals, True)
            differences = {name: {'min': None, 'max': None, 'min_vertex': None, 'max_vertex': None, 'valid_pairs': 0}
                           for name in ('signed', 'vertical')}
            uncovered_digest = hashlib.sha256()
            aggregates = {p['id']: {'id': p['id'], 'kind': p['kind'], 'count': 0, 'valid': 0,
                'anchor_requests': {'first_ordinal': self.anchors[(ci, p['id'], p['vertices'][0])][0],
                                    'row_count': len(p['vertices'])},
                'max_slip_world_m': None, 'max_error_model_um': None, 'upper_bound_model_um': None,
                'min_signed_world_m': None, 'max_signed_world_m': None, 'min_vertical_world_m': None,
                'max_vertical_world_m': None, 'worst_vertices': {}, 'measurement_digest': hashlib.sha256(),
                'all_upper_known': True, 'source_relative': {name: {'min': None, 'max': None, 'min_vertex': None, 'max_vertex': None, 'valid_pairs': 0}
                    for name in ('signed', 'vertical', 'slip')}} for p in patches}
            for vertex, p in enumerate(positions):
                req = native_request(self.state, self.count, ci, phase, source_id, label, vertex, p)
                response = self.consume(req)
                if self.writer is not None:
                    continue
                value = native_measure(p, req, response, None, None, self.state)
                self.unknown_terms.update(value['unknown_terms'])
                covered = value['coverage'] == 'COMPLETE_FINITE'
                valid += covered
                if not covered:
                    uncovered_digest.update(struct.pack('>Q', req['ordinal']))
                if label == 'source':
                    source_values.append({k: value[k+'_world_m'] for k in ('signed', 'vertical')})
                for name, field in (('signed', 'signed_world_m'), ('vertical', 'vertical_world_m')):
                    interval = value[name+'_interval_world_m']
                    interval_known[name] &= interval is not None
                    if interval is not None:
                        if not intervals[name]:
                            intervals[name] = [interval[:], interval[:]]
                        else:
                            intervals[name][0] = [min(a, b) for a, b in zip(intervals[name][0], interval)]
                            intervals[name][1] = [max(a, b) for a, b in zip(intervals[name][1], interval)]
                    if label != 'source':
                        update_difference(differences[name], value[field], source_values[vertex][name], vertex)
                    if value[field] is not None:
                        for operation in ('min', 'max'):
                            key = operation+'_'+name
                            old = whole[key]
                            if old is None or (value[field] < old if operation == 'min' else value[field] > old):
                                whole[key], worst[key] = value[field], vertex
                for patch in patches:
                    if vertex not in patch['vertices']:
                        continue
                    ar, answer = self.anchor(ci, patch['id'], vertex)
                    measured = native_measure(p, req, response, ar, answer, self.state)
                    self.unknown_terms.update(measured['unknown_terms'])
                    agg = aggregates[patch['id']]
                    if label == 'source':
                        source_patches[(patch['id'], vertex)] = {k: measured[k+'_world_m'] for k in ('signed', 'vertical', 'slip')}
                    else:
                        original = source_patches[(patch['id'], vertex)]
                        for name in ('signed', 'vertical', 'slip'):
                            update_difference(agg['source_relative'][name], measured[name+'_world_m'], original[name], vertex)
                    agg['count'] += 1
                    agg['valid'] += measured['coverage'] == 'COMPLETE_FINITE'
                    agg['measurement_digest'].update(compact({'vertex_id': vertex, 'measurement': measured})+b'\n')
                    agg['all_upper_known'] &= measured['upper_bound_model_um'] is not None
                    for field, source in (('max_slip_world_m', 'slip_world_m'), ('max_error_model_um', 'error_model_um'),
                        ('upper_bound_model_um', 'upper_bound_model_um'), ('min_signed_world_m', 'signed_world_m'),
                        ('max_signed_world_m', 'signed_world_m'), ('min_vertical_world_m', 'vertical_world_m'),
                        ('max_vertical_world_m', 'vertical_world_m')):
                        x, old = measured[source], agg[field]
                        if x is not None and (old is None or (x < old if field.startswith('min_') else x > old)):
                            agg[field], agg['worst_vertices'][field] = x, vertex
            if self.writer is not None:
                continue
            active, outgoing = [], []
            for patch in patches:
                agg = aggregates[patch['id']]
                agg['measurement_sha256'] = agg.pop('measurement_digest').hexdigest()
                if not agg.pop('all_upper_known'):
                    agg['upper_bound_model_um'] = None
                budget = self.state['header']['budget']
                status = 'PENDING'
                if patch['kind'] == 'swing':
                    status = 'SWING_NO_STANCE_VERDICT'
                elif budget is not None and self.state['placement_uniformity']['status'] == 'FAIL':
                    status = 'INELIGIBLE_PLACEMENT'
                elif budget is not None and valid == self.vertex_count and agg['valid'] == agg['count'] and not self.state['material_gaps'] and agg['upper_bound_model_um'] is not None:
                    status = budget_status(agg['upper_bound_model_um'], 0., budget)
                agg['budget_status'] = status
                if patch['start'] <= phase < patch['end'] or phase == patch['end'] == 1:
                    active.append(agg)
                if phase == patch['end']:
                    outgoing.append(agg)
            coverage = {'expected_vertices': self.vertex_count, 'received_vertices': self.vertex_count,
                        'valid_vertices': valid, 'uncovered_vertices': self.vertex_count-valid,
                        'first_vertex_ordinal': first_ordinal, 'last_vertex_ordinal': self.count-1,
                        'uncovered_ordinal_sha256': uncovered_digest.hexdigest(),
                        'identity_source': 'bound response stream; SHA256 of big-endian uint64 uncovered ordinals',
                        'status': 'COMPLETE_FINITE' if valid == self.vertex_count else 'UNCOVERED'}
            for role, values in (('active_patches', active), ('outgoing_patches', outgoing)):
                valid_patches = sum(p['valid'] == p['count'] for p in values)
                coverage[role] = {'expected': len(values), 'received': len(values), 'valid': valid_patches,
                                  'uncovered': len(values)-valid_patches,
                                  'uncovered_ids': [p['id'] for p in values if p['valid'] != p['count']]}
            # Anchor coverage is counted once at stream completion, not once per frame/variant.
            coverage['anchors'] = dict.fromkeys(('expected', 'received', 'valid', 'uncovered'), 0)
            if any(coverage[role]['uncovered'] for role in ('active_patches', 'outgoing_patches')):
                coverage['status'] = 'UNCOVERED'
            out[label] = {'whole_mesh_'+key+'_world_m': x for key, x in whole.items()}
            out[label].update(whole_mesh_penetration_world_m=None if whole['min_signed'] is None else max(0., -whole['min_signed']),
                              whole_mesh_vertical_penetration_world_m=None if whole['min_vertical'] is None else max(0., -whole['min_vertical']),
                              worst_vertices=worst, patches=active, exit_patches=outgoing, coverage=coverage,
                              extrema_intervals_world_m={name: intervals[name] if interval_known[name] else None for name in intervals},
                              source_relative_world_m=None if label == 'source' else differences)
        return out

    def finish(self):
        require(not self.finished and self.frame_index == len(self.frames) and self.count == self.expected_vertices,
                'incomplete/restarted native frame enumeration')
        valid_anchors = 0
        uncovered = hashlib.sha256()
        for ci, patch_id, vertex in self.anchor_order:
            ordinal, patch, a = self.anchors[(ci, patch_id, vertex)]
            request = native_request(self.state, ordinal, ci, None, None, None, vertex, a, patch)
            response = self.consume(request)
            if self.writer is None:
                sample = native_sample(response, request, self.state)
                self.unknown_terms.update('anchor:'+term for term in sample['missing'])
                ok = sample['covered']
                valid_anchors += ok
                if not ok:
                    uncovered.update(struct.pack('>Q', ordinal))
        require(self.count == self.expected_rows, 'incomplete native logical enumeration')
        if self.writer is not None:
            footer = self.writer.finish()
            result = {'request_stream_sha256': footer['stream_sha256'], 'request_file_sha256': self.writer.file_digest.hexdigest(),
                      'footer': footer, 'measurement_status': 'PENDING_RESPONSES',
                      'budget_status': 'INELIGIBLE_PLACEMENT' if self.state['header']['budget'] is not None
                          and self.state['placement_uniformity']['status'] == 'FAIL' else 'PENDING'}
        else:
            require(next(self.responses, None) is None, 'extra native response')
            require(self.reader.file_sha256 == self.response_sha256, 'native response file changed during evaluation')
            require(self.request_digest.hexdigest() == self.response_header['request_stream_sha256'], 'regenerated request digest mismatch')
            result = {'request_stream_sha256': self.request_digest.hexdigest(), 'response_file_sha256': self.response_sha256,
                      'response_footer': self.reader.footer, 'measurement_status': 'GENERATED',
                      'uncertainty_status': 'UNKNOWN' if self.unknown_terms else self.state['uncertainty_status'],
                      'unknown_terms': sorted(self.unknown_terms),
                      'blockers': ['native uncertainty: '+term for term in sorted(self.unknown_terms)],
                      'anchors': {'expected': len(self.anchor_order), 'received': len(self.anchor_order),
                                  'valid': valid_anchors, 'uncovered': len(self.anchor_order)-valid_anchors,
                                  'first_ordinal': self.expected_vertices, 'uncovered_ordinal_sha256': uncovered.hexdigest()}}
        self.finished = True
        return dict(result, vertex_count=self.expected_vertices, anchor_count=len(self.anchor_order),
                    row_count=self.count, frame_count=self.frame_index, continuous_domain='PENDING', rendered_surface='PENDING')


def raw_patch_coverage(row, phase, anchor_covered, vertex_covered):
    result = {}
    for role in ['anchors', 'active_patches', 'outgoing_patches']:
        identities, valid = [], []
        for patch in row['patches']:
            if role == 'active_patches' and not (patch['start'] <= phase < patch['end'] or phase == 1 and patch['end'] == 1):
                continue
            if role == 'outgoing_patches' and phase != patch['end']:
                continue
            if role == 'anchors':
                for vertex, anchor in zip(patch['vertices'], patch['anchors']):
                    identities.append({'patch_id': patch['id'], 'vertex_id': vertex})
                    valid.append(anchor_covered(anchor))
            else:
                identities.append(patch['id'])
                valid.append(all(anchor_covered(anchor) and vertex_covered[vertex]
                                 for vertex, anchor in zip(patch['vertices'], patch['anchors'])))
        result[role] = {'expected': len(identities), 'received': len(identities), 'valid': sum(valid),
                        'uncovered': len(valid)-sum(valid),
                        'uncovered_ids': [identity for identity, ok in zip(identities, valid) if not ok]}
    return result

def raw_physical_metrics(points_by_label, state, case_index, phase):
    h = state['header']
    row, placement = h['cases'][case_index], h['placement']
    m, scale, units = [placement[k] for k in ['matrix', 'original_scale', 'world_unit_m']]
    surface = state['surfaces'][row['surface_id']]
    origin, normal = surface['origin'], surface['normal']
    length = math.hypot(*normal)
    n = [x/length for x in normal]
    uniform = state['placement_uniformity']['status'] == 'PREDICATE_SATISFIED'
    bounds = {name: term['value'] for name, term in h['uncertainty'].items()}
    def radius(*names):
        if any(bounds[name] is None for name in names):
            return None
        total_m = math.nextafter(sum(bounds[name] for name in names), math.inf)
        return math.nextafter(total_m/units, math.inf)
    position_radius = radius('position', 'query_coordinate')
    anchor_radius = radius('anchor', 'query_coordinate')
    def covered(p, error, model_point=None):
        if error is None or not number(error):
            return False
        for k, axis in enumerate([0, 2]):
            low, high = surface['domain']['xz_min'][k], surface['domain']['xz_max'][k]
            guard = 256*math.ulp(max(1., abs(p[axis]), abs(low), abs(high)))
            if model_point is not None:
                magnitude = sum(abs(m[axis][j]*model_point[j]) for j in range(3)) + abs(m[axis][3])
                guard += 64*math.ulp(max(1., magnitude))*4
            spread = math.nextafter(error+guard, math.inf)
            if not (low <= math.nextafter(p[axis]-spread, -math.inf)
                    and math.nextafter(p[axis]+spread, math.inf) <= high):
                return False
        return True
    def anchor_covered(anchor):
        return covered(anchor, anchor_radius)
    def measure(p, a, model_point, position_covered):
        result = contact(a, p, origin, normal, scale, units)
        height = origin[1] - ((p[0]-origin[0])*n[0] + (p[2]-origin[2])*n[2])/n[1]
        vertical = (p[1]-height)*units
        error = max(abs(result['signed_world_m']), result['slip_world_m'])
        placement_guard = max(64*math.ulp(max(1., sum(abs(m[r][k]*model_point[k]) for k in range(3)) + abs(m[r][3])))
                              for r in range(3))*4*units
        guard = result.pop('roundoff_model_um')*scale*units/1e6 + placement_guard
        # Fixed-plane reduction retains the legacy total arithmetic guard.
        known = state['uncertainty_status'] == 'BOUNDED'
        upper = None
        if known:
            ep, eh, en, eq, ea = [bounds[k] for k in ['position', 'height', 'normal', 'query_coordinate', 'anchor']]
            slope = math.hypot(n[0], n[2])/n[1]
            eq = math.hypot(eq, eh + slope*(eq+ep))
            pq = abs(vertical)
            ed = ep + eq + (pq + ep + eq)*en
            eslip = ep + ea + (2*en+en*en)*(math.dist(p, a)*units+ep+ea)
            upper = max(abs(result['signed_world_m'])+ed, result['slip_world_m']+eslip)
            if any(bounds.values()):
                guard += 256*math.ulp(max(1., upper, ep, eq, ea, ed, eslip))
        result.pop('signed_model_um')
        result.pop('slip_model_um')
        result.update(vertical_world_m=vertical, vertical_penetration_world_m=max(0., -vertical),
                      vertical_hover_world_m=max(0., vertical), error_model_um=error/(scale*units)*1e6 if uniform else None,
                      nominal_scale_model_um=None if uniform else error/(scale*units)*1e6,
                      upper_bound_model_um=(upper+guard)/(scale*units)*1e6 if uniform and known and position_covered and anchor_covered(a) else None,
                      numeric_guard_world_m=guard, coverage='COMPLETE_FINITE' if position_covered and anchor_covered(a) else 'UNCOVERED')
        require(all(value is None or not isinstance(value, float) or number(value) for value in result.values()),
                'nonfinite raw physical result')
        return result
    out = {}
    for label, points in points_by_label.items():
        world = [point(m, p) for p in points]
        require(world and all(all(number(x) for x in p) for p in world), 'nonfinite raw placed points')
        separations = [sum((p[k]-origin[k])*n[k] for k in range(3))*units for p in world]
        vertex_covered = [covered(p, position_radius, model_point) for p, model_point in zip(world, points)]
        uncovered = [i for i, ok in enumerate(vertex_covered) if not ok]
        patches, exits = [], []
        for patch in row['patches']:
            active = patch['start'] <= phase < patch['end'] or phase == 1 and patch['end'] == 1
            exiting = phase == patch['end']
            if not active and not exiting:
                continue
            values = [measure(world[v], a, points[v], vertex_covered[v]) for v, a in zip(patch['vertices'], patch['anchors'])]
            status = 'PENDING'
            if patch['kind'] == 'swing':
                status = 'SWING_NO_STANCE_VERDICT'
            elif h['budget'] is not None and not uniform:
                status = 'INELIGIBLE_PLACEMENT'
            elif h['budget'] is not None and not uncovered and not state['material_gaps'] and all(
                    v['coverage'] == 'COMPLETE_FINITE' and v['upper_bound_model_um'] is not None for v in values):
                status = 'WITHIN_FINITE_SAMPLES' if math.ceil(max(v['upper_bound_model_um'] for v in values)) <= h['budget']['contact_um'] else 'FAIL'
            measured = {'id': patch['id'], 'kind': patch['kind'], 'vertices': patch['vertices'],
                        'measurements': values, 'budget_status': status}
            if active:
                patches.append(measured)
            if exiting:
                exits.append(measured)
        patch_coverage = raw_patch_coverage(row, phase, anchor_covered, vertex_covered)
        incomplete = bool(uncovered) or any(value['uncovered'] for value in patch_coverage.values())
        worst = min(range(len(world)), key=lambda i: separations[i])
        out[label] = {'whole_mesh_min_signed_world_m': separations[worst],
                      'whole_mesh_max_signed_world_m': max(separations),
                      'whole_mesh_penetration_world_m': max(0., -separations[worst]),
                      'worst_penetration_vertex': worst, 'patches': patches, 'exit_patches': exits,
                      'coverage': {'expected_vertices': len(world), 'received_vertices': len(world),
                                   'valid_vertices': sum(vertex_covered),
                                   'uncovered_vertex_ids': uncovered, 'uncovered_vertices': len(uncovered),
                                   'status': 'UNCOVERED' if incomplete else 'COMPLETE_FINITE',
                                   **patch_coverage}}
    if 'source' in out:
        out['introduced_vs_source_world_m'] = {label: [[v['signed_world_m']-s['signed_world_m'],
                    v['slip_world_m']-s['slip_world_m']] for p, q in zip(out[label]['patches'], out['source']['patches'])
                    for v, s in zip(p['measurements'], q['measurements'])]
                    for label in out if label != 'source'}
    return out

def load_frozen(path=frozen.FIXTURE):
    require(hashlib.sha256(path.read_bytes()).hexdigest() == FIXTURE_SHA256, 'fixture bytes changed')
    return frozen.load_fixture(path)


def deform(skin, globals_):
    require(set(skin.names) <= set(globals_), 'missing skin bone')
    for m in globals_.values():
        matrix(m)
    for bind in skin.binds:
        matrix(bind['pose'])
    result = skin.points(globals_)
    require(all(all(number(x) for x in p) for p in result), 'nonfinite deformation')
    return result


def edge_metrics(skin, points, entry):
    lengths = skin.lengths(points)
    flags = [i for i, (x, base) in enumerate(zip(lengths, entry)) if frozen.exceeds(x, base)]
    worst = max(range(len(lengths)), key=lambda i: lengths[i] - entry[i])
    return {'flag_ids': flags, 'worst_extension_edge': worst, 'worst_extension_m': lengths[worst]-entry[worst],
            'worst_length_m': lengths[worst]}, lengths


def physical_metrics(points_by_label, evidence, row, phase):
    m, scale, units = evidence['placement'], evidence['original_scale'], evidence['world_unit_m']
    ground = row['ground']
    origin, normal = ground['origin'], ground['normal']
    nlen = math.hypot(*normal)
    n = [x/nlen for x in normal]
    out = {}
    for label, points in points_by_label.items():
        world = [point(m, p) for p in points]
        separation = [sum((p[k]-origin[k])*n[k] for k in range(3)) for p in world]
        worst = min(range(len(world)), key=lambda i: separation[i])
        patches, exits = [], []
        for patch in row['patches']:
            # Shared boundary belongs to the next interval; phase 1 belongs to the last.
            active = patch['start'] <= phase < patch['end'] or phase == patch['end'] == 1
            exiting = phase == patch['end']
            if not active and not exiting:
                continue
            values = [contact(a, world[v], origin, n, scale, units) for v, a in zip(patch['vertices'], patch['anchors'])]
            error = max(max(abs(v['signed_model_um']), v['slip_model_um']) for v in values)
            placement_guard = max(64 * math.ulp(max(1., sum(abs(m[r][k]*points[v][k]) for k in range(3)) + abs(m[r][3])))
                                  for v in patch['vertices'] for r in range(3)) * 4 / scale * 1e6
            guard = placement_guard + max(v['roundoff_model_um'] for v in values) + evidence['numeric_error_model_m']*1e6
            require(number(guard), 'nonfinite numeric guard')
            measured = {'id': patch['id'], 'kind': patch['kind'], 'vertices': patch['vertices'],
                            'measurements': values, 'max_error_model_um': error,
                            'numeric_guard_model_um': guard, 'placement_roundoff_model_um': placement_guard,
                            'budget': budget_status(error, guard, evidence.get('budget')) if patch['kind'] != 'swing' else 'SWING_NO_STANCE_VERDICT'}
            if active:
                patches.append(measured)
            if exiting:
                exits.append(measured)
        out[label] = {'whole_mesh_min_signed_world_m': min(separation)*units,
                      'whole_mesh_max_signed_world_m': max(separation)*units,
                      'whole_mesh_penetration_world_m': max(0., -min(separation))*units,
                      'worst_penetration_vertex': worst, 'patches': patches, 'exit_patches': exits}
    out['introduced_vs_source_model_um'] = {
        label: [[v['signed_model_um']-s['signed_model_um'], v['slip_model_um']-s['slip_model_um']]
                for p, q in zip(out[label]['patches'], out['source']['patches'])
                for v, s in zip(p['measurements'], q['measurements'])]
        for label in ['reference', 'mapped']}
    return out


def evaluate(data, evidence=None, *, raw_observation=None, query_output=None, query_responses=None):
    require(evidence is None or raw_observation is None, 'contact modes are mutually exclusive')
    state = validate_raw_observation(raw_observation, data['round1_arc_combined/inputs.json']['cases']) if raw_observation is not None else None
    if state is not None and state['header']['surface_mode'] == 'native_queries':
        with NativeRun(state, 20880, query_output=query_output, query_responses=query_responses) as run:
            return _evaluate(data, evidence, raw_observation=raw_observation, native_run=run)
    require(query_output is None and query_responses is None, 'query paths require native_queries mode')
    return _evaluate(data, evidence, raw_observation=raw_observation)


def _evaluate(data, evidence=None, *, raw_observation=None, native_run=None):
    cases = data['round1_arc_combined/inputs.json']['cases']
    require(evidence is None or raw_observation is None, 'contact modes are mutually exclusive')
    raw_state = native_run.state if native_run is not None else validate_raw_observation(raw_observation, cases) if raw_observation is not None else None
    missing = raw_state['blockers'] if raw_state is not None else validate_contact_input(evidence, cases)
    reproduction = frozen.replay(data)  # Keep accepted223's entire corruption/arithmetic/attribution gate.
    skin = frozen.Skin(data['native_import_probe/baseline-native.json'])
    require(len(skin.edges) == 33427, 'edge coverage changed')
    native = data['round1_actual_march/native-march.json']
    samples = {s['id']: s for s in native['samples']}
    digest = {label: hashlib.sha256() for label in ['source', 'reference', 'mapped']}
    frames, endpoints, boundaries, helper = [], [], [], []
    raw_counts = {role: dict.fromkeys(['expected', 'received', 'valid', 'uncovered'], 0)
                  for role in ['vertices', 'anchors', 'active_patches', 'outgoing_patches']}
    raw_budgets = set()
    totals = dict.fromkeys(digest, 0)
    introduced = {'reference': 0, 'mapped': 0, 'mapping_only': 0}
    endpoint_witness = None
    for ci, (case, result) in enumerate(zip(cases, data['round1_arc_combined/results.json']['cases'])):
        parents = {b['name']: b['parent'] for b in case['rest']['bones']}
        entry, exit_ = [case['op'][k] for k in ['march_entry_phase', 'march_exit_phase']]
        def source_globals(phase):
            key = float(phase).hex()
            require(key in samples, 'uncaptured source phase; no interpolation')
            return samples[key]['global_bones']
        entry_lengths = skin.lengths(deform(skin, source_globals(entry)))
        turn = case['op']['turn_udeg']
        helper.append({'turn_udeg': turn, 'captured_failures': result['failures'], 'captured_frames': len(result['frames'])})
        previous, first, last = None, None, None
        for u, reference, frame in zip(case['phases'], case['reference_poses'], result['frames']):
            distance = 1. if entry == exit_ else (exit_ - entry) % 1.
            phase = entry if u == 0 else exit_ if u == 1 else (entry + distance*u) % 1.
            g = {'source': source_globals(phase), 'reference': frozen.globals_of(reference, parents),
                 'mapped': frozen.globals_of(frame['pose'], parents)}
            points = {label: deform(skin, pose) for label, pose in g.items()}
            metrics, flags = {}, {}
            for label, p in points.items():
                digest[label].update(b''.join(struct.pack('<3d', *v) for v in p))
                metrics[label], lengths = edge_metrics(skin, p, entry_lengths)
                if label == 'source':
                    source_lengths = lengths
                else:
                    metrics[label]['max_abs_length_delta_vs_source_m'] = max(abs(a-b) for a, b in zip(lengths, source_lengths))
                flags[label] = set(metrics[label]['flag_ids'])
                totals[label] += len(flags[label])
            for label in ['reference', 'mapped']:
                introduced[label] += len(flags[label] - flags['source'])
            introduced['mapping_only'] += len(flags['mapped'] - flags['source'] - flags['reference'])
            row = {'turn_udeg': turn, 'phase': u, 'source_phase_id': float(phase).hex(), 'edges': metrics,
                   'introduced': {label: sorted(flags[label] - flags['source']) for label in ['reference', 'mapped']}}
            if raw_state is not None:
                row['raw_physical'] = (native_run.frame(points, ci, u, float(phase).hex()) if native_run is not None
                                       else raw_physical_metrics(points, raw_state, ci, u))
                for label in points if row['raw_physical'] else []:
                    measured = row['raw_physical'][label]
                    coverage = measured['coverage']
                    for key in raw_counts['vertices']:
                        raw_counts['vertices'][key] += coverage[key + '_vertices']
                    for role in ['anchors', 'active_patches', 'outgoing_patches']:
                        for key in raw_counts[role]:
                            raw_counts[role][key] += coverage[role][key]
                    raw_budgets.update(p['budget_status'] for p in measured['patches'] + measured['exit_patches'])
            if evidence is not None:
                row['physical'] = physical_metrics(points, evidence, evidence['cases'][ci], u)
            if u in [0, 1]:
                endpoint = {'turn_udeg': turn, 'phase': u, 'skin_residual_m': {}, 'global_component_residual': {}}
                for label in ['reference', 'mapped']:
                    endpoint['skin_residual_m'][label] = max(math.dist(a, b) for a, b in zip(points[label], points['source']))
                    endpoint['global_component_residual'][label] = max(abs(g[label][name][r][c]-g['source'][name][r][c])
                        for name in skin.names for r in range(4) for c in range(4))
                endpoints.append(endpoint)
                if u == 1 and turn == 90000000:
                    a, b = skin.edges[23264]
                    length = math.dist(points['source'][a], points['source'][b])
                    endpoint_witness = {'edge_id': 23264, 'entry_m': entry_lengths[23264], 'source_exit_m': length,
                                        'flagged': frozen.exceeds(length, entry_lengths[23264])}
            if previous is not None:
                du = u - previous[0]
                require(du > 0, 'non-increasing phases')
                jumps = {label: max(math.dist(a, b) for a, b in zip(points[label], previous[1][label])) for label in points}
                residual = {label: max(math.dist([a[k]-b[k] for k in range(3)], [s[k]-t[k] for k in range(3)])
                    for a, b, s, t in zip(points[label], previous[1][label], points['source'], previous[1]['source']))
                    for label in ['reference', 'mapped']}
                segment = {'from': previous[0], 'to': u, 'max_displacement_m': jumps,
                           'max_displacement_residual_vs_source_m': residual,
                           'max_velocity_residual_vs_source_m_per_substep': {label: x/(du*case['op']['duration_q']/1e6) for label, x in residual.items()}}
                if first is None:
                    first = segment
                last = segment
            previous = (u, points)
            frames.append(row)
        boundaries.append({'turn_udeg': turn, 'duration_q': case['op']['duration_q'], 'entry_segment': first, 'exit_segment': last,
                           'derivative_continuity': 'PENDING: finite one-sided secants are not a derivative bound'})
    require(totals['mapped'] == reproduction['edge_phase_flags'] and introduced['mapped'] == 45
            and introduced['mapping_only'] == 1 and len(frames) == 1300, 'all-frame attribution mismatch')
    require(digest['mapped'].hexdigest() == reproduction['whole_mapped_mesh_sha256'], 'mapped mesh differs from accepted replay')
    report = {'format': 'infantry-pivot-metrics-v1', 'fixture_sha256': FIXTURE_SHA256, 'source_sha256': frozen.HASHES,
            'reproduction': reproduction, 'motion_acceptance': 'FAIL/PENDING', 'authority_decision': 'PENDING',
            'coverage': {'vertices_per_frame': 20880, 'packed_influences_per_vertex': 4, 'binds': 69,
                         'edges': len(skin.edges), 'frames_per_variant': len(frames), 'native_sample_ids': len(samples),
                         'contact': 'PENDING' if evidence is None else 'FINITE_PLANAR_SAMPLES_ONLY',
                         'missing': missing + ['continuous parameter/contact/envelope bounds', 'external MARCH boundary derivatives',
                                              'original rejected-helper per-sample trace', 'actual terrain/window/FPS acceptance',
                                              'independent material/terrain provenance validation']},
            'helper': {'combined_capture': helper, 'earlier_uncorrected_rejections': 'PENDING: unbundled rejection traces; never excluded from coverage'},
            'absolute_edge_phase_flags': totals, 'introduced_edge_phase_flags': introduced,
            'whole_mesh_sha256': {k: v.hexdigest() for k, v in digest.items()},
            'source_endpoint_edge23264': endpoint_witness, 'endpoints': endpoints, 'boundaries': boundaries, 'frames': frames}

    if raw_state is not None:
        native_summary = native_run.finish() if native_run is not None else None
        if native_summary is not None and 'anchors' in native_summary:
            raw_state['uncertainty_status'] = native_summary['uncertainty_status']
            raw_state['blockers'].extend(native_summary['blockers'])
            for key in raw_counts['anchors']:
                raw_counts['anchors'][key] = native_summary['anchors'][key]
        uncovered = any(counts['uncovered'] for counts in raw_counts.values())
        if raw_state['header']['budget'] is None:
            raw_budget = 'PENDING'
        elif raw_state['placement_uniformity']['status'] == 'FAIL':
            raw_budget = 'INELIGIBLE_PLACEMENT'
        elif uncovered or raw_state['uncertainty_status'] == 'UNKNOWN' or raw_state['material_gaps']:
            raw_budget = 'PENDING'
        elif 'FAIL' in raw_budgets:
            raw_budget = 'FAIL'
        elif 'PENDING' in raw_budgets or not raw_budgets:
            raw_budget = 'PENDING'
        else:
            raw_budget = 'WITHIN_FINITE_SAMPLES' if 'WITHIN_FINITE_SAMPLES' in raw_budgets else 'SWING_NO_STANCE_VERDICT'
        if uncovered:
            raw_state['blockers'].append('native finite coverage incomplete' if native_run is not None else 'fixed-plane finite coverage incomplete')
        report['raw_observation'] = {'schema_status': 'VALID', 'measurement_status': 'PARTIAL' if uncovered else 'GENERATED',
            'coverage': dict(raw_counts, status='UNCOVERED' if uncovered else 'COMPLETE_FINITE'), 'budget_status': raw_budget,
            'placement_uniformity': raw_state['placement_uniformity'],
            'uncertainty_status': raw_state['uncertainty_status'], 'blockers': raw_state['blockers'],
            'observation_header_sha256': raw_state['observation_header_sha256'], 'header': raw_state['header'],
            'motion_acceptance': 'FAIL/PENDING', 'continuous_domain': 'PENDING', 'rendered_surface': 'PENDING'}
        if native_summary is not None:
            report['raw_observation']['native_queries'] = native_summary
            native_summary['measurement_status'] = report['raw_observation']['measurement_status']
            if native_run.writer is not None:
                report['raw_observation'].update(measurement_status='PENDING_RESPONSES', budget_status=native_summary['budget_status'])
                native_summary['measurement_status'] = 'PENDING_RESPONSES'
                for role in raw_counts.values():
                    role['valid'] = role['received'] = 0
                raw_counts['vertices'].update(expected=native_summary['vertex_count'], uncovered=native_summary['vertex_count'])
                raw_counts['anchors'].update(expected=native_summary['anchor_count'], uncovered=native_summary['anchor_count'])
                for role in ('active_patches', 'outgoing_patches'):
                    count = sum(3*sum((p['start'] <= float.fromhex(phase) < p['end'] or float.fromhex(phase) == p['end'] == 1)
                                     if role == 'active_patches' else float.fromhex(phase) == p['end'] for p in r['patches'])
                                for r in raw_state['header']['cases'] for phase in r['phase_ids'])
                    raw_counts[role].update(expected=count, uncovered=count)
                report['raw_observation']['coverage'].update(raw_counts, status='UNCOVERED')
                report['raw_observation']['blockers'].append('native query responses missing')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=frozen.FIXTURE)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--contact-input', type=Path)
    modes.add_argument('--raw-observation', type=Path)
    queries = parser.add_mutually_exclusive_group()
    queries.add_argument('--query-output', type=Path)
    queries.add_argument('--query-responses', type=Path)
    args = parser.parse_args()
    require(not (args.query_output or args.query_responses) or args.raw_observation is not None, 'query paths require raw observation')
    if args.query_output is not None:
        require(args.query_output.resolve() not in {p.resolve() for p in (args.fixture, args.raw_observation) if p is not None}, 'query output overwrites input')
    contact_raw = args.contact_input.read_bytes() if args.contact_input else None
    evidence = json.loads(contact_raw) if contact_raw is not None else None
    raw = args.raw_observation.read_bytes() if args.raw_observation else None
    observation = decode_raw_observation(raw) if raw is not None else None
    if observation is not None:
        require(observation.get('schema') == 'infantry-pivot-raw-observation/v1', 'unknown raw observation schema')
    report = evaluate(load_frozen(args.fixture), evidence, raw_observation=observation,
                      query_output=args.query_output, query_responses=args.query_responses)
    if raw is not None:
        report['raw_observation_sha256'] = hashlib.sha256(raw).hexdigest()
    report['contact_input_sha256'] = hashlib.sha256(contact_raw).hexdigest() if contact_raw is not None else None
    print(json.dumps(report, sort_keys=True, indent=2, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, IndexError, OSError, zlib.error, sqlite3.Error, OverflowError) as error:
        print(f'METRIC_ERROR: {error}; motion acceptance NOT PASSED', file=sys.stderr)
        sys.exit(1)
