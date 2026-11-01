#!/usr/bin/env python3
"""Measure frozen native skin and explicit physical contacts; never certify motion.

Stdlib only. Exit 0 means report generated/MATCH, including adverse measurements.
Missing physical evidence stays PENDING. --contact-input is an external, hashed
measurement input, never a policy/certificate or a fitted animated ground plane.
"""
import argparse
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


def evaluate(data, evidence=None):
    cases = data['round1_arc_combined/inputs.json']['cases']
    missing = validate_contact_input(evidence, cases)
    reproduction = frozen.replay(data)  # Keep accepted223's entire corruption/arithmetic/attribution gate.
    skin = frozen.Skin(data['native_import_probe/baseline-native.json'])
    require(len(skin.edges) == 33427, 'edge coverage changed')
    native = data['round1_actual_march/native-march.json']
    samples = {s['id']: s for s in native['samples']}
    digest = {label: hashlib.sha256() for label in ['source', 'reference', 'mapped']}
    frames, endpoints, boundaries, helper = [], [], [], []
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
    return {'format': 'infantry-pivot-metrics-v1', 'fixture_sha256': FIXTURE_SHA256, 'source_sha256': frozen.HASHES,
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=frozen.FIXTURE)
    parser.add_argument('--contact-input', type=Path)
    args = parser.parse_args()
    contact_raw = args.contact_input.read_bytes() if args.contact_input else None
    evidence = json.loads(contact_raw) if contact_raw is not None else None
    report = evaluate(load_frozen(args.fixture), evidence)
    report['contact_input_sha256'] = hashlib.sha256(contact_raw).hexdigest() if contact_raw is not None else None
    print(json.dumps(report, sort_keys=True, indent=2, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, IndexError, OSError, zlib.error, OverflowError) as error:
        print(f'METRIC_ERROR: {error}; motion acceptance NOT PASSED', file=sys.stderr)
        sys.exit(1)
