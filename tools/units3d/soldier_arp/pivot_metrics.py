#!/usr/bin/env python3
"""Measure frozen native skin and explicit physical contacts; never certify motion.

Stdlib only. Exit 0 means report generated/MATCH, including adverse measurements.
Missing physical evidence stays PENDING. --contact-input is an external, hashed
measurement input, never a policy/certificate or a fitted animated ground plane.
"""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
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
    """B wire fields are explicit below; evidence references bind embedded exact bytes.

    Only fixed-plane observations are supported here. Native streams belong to C.
    No supplied provenance string authenticates a physical/authority claim.
    """
    exact_keys(observation, 'schema kind header chunks footer')
    require(observation['schema'] == 'infantry-pivot-raw-observation/v1' and observation['kind'] == 'observation',
            'unknown raw observation schema/kind')
    require(observation['chunks'] == [] and observation['footer'] == {
        'chunk_count': 0, 'row_count': 0, 'decoded_bytes': 0, 'stream_sha256': hashlib.sha256(b'').hexdigest()},
        'observation must have empty stream')
    h = observation['header']
    exact_keys(h, 'surface_mode provenance inputs placement frame cases surfaces uncertainty budget evidence')
    require(h['surface_mode'] == 'fixed_plane', 'unsupported raw surface mode')
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
                            'ground': {'origin': surface['origin'], 'normal': surface['normal']}})
    missing = validate_material_cases({'cases': legacy_rows, 'budget': h['budget']}, cases)
    for row in h['cases']:
        vertices = sorted({v for p in row['patches'] if p['kind'] != 'swing' for v in p['vertices']})
        for vertex in vertices:
            covered = 0.
            for patch in sorted((p for p in row['patches'] if vertex in p['vertices'] and p['kind'] != 'swing'),
                                key=lambda p: p['start']):
                if patch['start'] > covered:
                    missing.append(f"case {row['turn_udeg']} vertex {vertex}: missing stance {covered}..{patch['start']}")
                covered = max(covered, patch['end'])
            if covered < 1:
                missing.append(f"case {row['turn_udeg']} vertex {vertex}: missing stance {covered}..1.0")
    unknown = []
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



def raw_patch_coverage(row, phase, covered):
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
                    valid.append(covered(anchor))
            else:
                identities.append(patch['id'])
                valid.append(all(covered(anchor) for anchor in patch['anchors']))
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
    def covered(p):
        return all(surface['domain']['xz_min'][k] <= p[axis] <= surface['domain']['xz_max'][k]
                   for k, axis in enumerate([0, 2]))
    def measure(p, a, model_point):
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
                      upper_bound_model_um=(upper+guard)/(scale*units)*1e6 if uniform and known and covered(p) and covered(a) else None,
                      numeric_guard_world_m=guard, coverage='COMPLETE_FINITE' if covered(p) and covered(a) else 'UNCOVERED')
        require(all(value is None or not isinstance(value, float) or number(value) for value in result.values()),
                'nonfinite raw physical result')
        return result
    out = {}
    for label, points in points_by_label.items():
        world = [point(m, p) for p in points]
        require(world and all(all(number(x) for x in p) for p in world), 'nonfinite raw placed points')
        separations = [sum((p[k]-origin[k])*n[k] for k in range(3))*units for p in world]
        uncovered = [i for i, p in enumerate(world) if not covered(p)]
        patches, exits = [], []
        for patch in row['patches']:
            active = patch['start'] <= phase < patch['end'] or phase == 1 and patch['end'] == 1
            exiting = phase == patch['end']
            if not active and not exiting:
                continue
            values = [measure(world[v], a, points[v]) for v, a in zip(patch['vertices'], patch['anchors'])]
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
        worst = min(range(len(world)), key=lambda i: separations[i])
        out[label] = {'whole_mesh_min_signed_world_m': separations[worst],
                      'whole_mesh_max_signed_world_m': max(separations),
                      'whole_mesh_penetration_world_m': max(0., -separations[worst]),
                      'worst_penetration_vertex': worst, 'patches': patches, 'exit_patches': exits,
                      'coverage': {'expected_vertices': len(world), 'received_vertices': len(world),
                                   'valid_vertices': sum(covered(p) for p in world),
                                   'uncovered_vertex_ids': uncovered, 'uncovered_vertices': len(uncovered),
                                   'status': 'UNCOVERED' if uncovered else 'COMPLETE_FINITE',
                                   **raw_patch_coverage(row, phase, covered)}}
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


def evaluate(data, evidence=None, *, raw_observation=None):
    cases = data['round1_arc_combined/inputs.json']['cases']
    require(evidence is None or raw_observation is None, 'contact modes are mutually exclusive')
    raw_state = validate_raw_observation(raw_observation, cases) if raw_observation is not None else None
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
                row['raw_physical'] = raw_physical_metrics(points, raw_state, ci, u)
                for label in points:
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
            raw_state['blockers'].append('fixed-plane finite coverage incomplete')
        report['raw_observation'] = {'schema_status': 'VALID', 'measurement_status': 'PARTIAL' if uncovered else 'GENERATED',
            'coverage': dict(raw_counts, status='UNCOVERED' if uncovered else 'COMPLETE_FINITE'), 'budget_status': raw_budget,
            'placement_uniformity': raw_state['placement_uniformity'],
            'uncertainty_status': raw_state['uncertainty_status'], 'blockers': raw_state['blockers'],
            'observation_header_sha256': raw_state['observation_header_sha256'], 'header': raw_state['header'],
            'motion_acceptance': 'FAIL/PENDING', 'continuous_domain': 'PENDING', 'rendered_surface': 'PENDING'}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=frozen.FIXTURE)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--contact-input', type=Path)
    modes.add_argument('--raw-observation', type=Path)
    args = parser.parse_args()
    contact_raw = args.contact_input.read_bytes() if args.contact_input else None
    evidence = json.loads(contact_raw) if contact_raw is not None else None
    raw = args.raw_observation.read_bytes() if args.raw_observation else None
    observation = decode_raw_observation(raw) if raw is not None else None
    if observation is not None:
        require(observation.get('schema') == 'infantry-pivot-raw-observation/v1', 'unknown raw observation schema')
    report = evaluate(load_frozen(args.fixture), evidence, raw_observation=observation)
    if raw is not None:
        report['raw_observation_sha256'] = hashlib.sha256(raw).hexdigest()
    report['contact_input_sha256'] = hashlib.sha256(contact_raw).hexdigest() if contact_raw is not None else None
    print(json.dumps(report, sort_keys=True, indent=2, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, IndexError, OSError, zlib.error, OverflowError) as error:
        print(f'METRIC_ERROR: {error}; motion acceptance NOT PASSED', file=sys.stderr)
        sys.exit(1)
