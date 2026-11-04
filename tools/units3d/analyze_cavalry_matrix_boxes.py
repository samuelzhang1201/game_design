"""Exact independent-real matrix-rectangle diagnostic, never a native pose proof.

Only analyze/verify CLI and tests call this sidecar. No producer hooks, native
acquisition, physical acceptance or new geometry. Certificates use reduced
rational numbers; closed lambda cells cover both tails and every breakpoint.
"""
import argparse
import ast
from collections import Counter
from fractions import Fraction as Q
import hashlib
import json
import math
from pathlib import Path
import sys


DEGENERATE = 'REFERENCE_BOX_DEGENERATE'
NONDEGENERATE = 'REFERENCE_BOX_NONDEGENERATE'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def exact(value):
    require(type(value) in (int, float, Q) and (type(value) is not float or math.isfinite(value)),
            'Nonfinite or malformed exact value')
    return Q(value)


def packed(value):
    if isinstance(value, Q):
        return [value.numerator, value.denominator]
    if isinstance(value, (tuple, list)):
        return [packed(x) for x in value]
    if isinstance(value, dict):
        return {k: packed(v) for k, v in value.items()}
    return value


def fraction(value):
    require(type(value) is list and len(value) == 2 and all(type(x) is int for x in value)
            and value[1] > 0 and math.gcd(*value) == 1, 'Noncanonical rational')
    return Q(*value)


def digest(value):
    return hashlib.sha256(json.dumps(packed(value), sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode()).hexdigest()


def domain_values(d1, d2, rows):
    d1, d2 = tuple(map(exact, d1)), tuple(map(exact, d2))
    require(len(d1) == len(d2) <= 48 and len(rows) == 3, 'Malformed rectangle cardinality')
    require(all(len(row) == len(d1) for row in rows), 'Missing row variable')
    require(all(len(pair) == 2 for row in rows for pair in row), 'Malformed rectangle interval')
    rows = tuple(tuple(tuple(map(exact, pair)) for pair in row) for row in rows)
    require(all(lo <= hi for row in rows for lo, hi in row), 'Reversed rectangle')
    return d1, d2, rows


def row_range(coefficients, row):
    return (sum((min(c*lo, c*hi) for c, (lo, hi) in zip(coefficients, row)), Q()),
            sum((max(c*lo, c*hi) for c, (lo, hi) in zip(coefficients, row)), Q()))


def breakpoints(d1, d2):
    return sorted({b/a for a, b in zip(d1, d2) if a})


def lambda_cells(points):
    endpoints = [None, *points, None]
    return list(zip(endpoints, endpoints[1:]))


def interior(cell):
    lo, hi = cell
    return Q() if lo is hi is None else hi-1 if lo is None else lo+1 if hi is None else (lo+hi)/2


def cell_inequalities(d1, d2, rows, cell):
    sample = interior(cell)
    positive = [b-sample*a >= 0 for a, b in zip(d1, d2)]
    result = []
    for row in rows:
        lower = [lo if sign else hi for (lo, hi), sign in zip(row, positive)]
        upper = [hi if sign else lo for (lo, hi), sign in zip(row, positive)]
        result.extend([(sum((b*t for b, t in zip(d2, lower)), Q()),
                        -sum((a*t for a, t in zip(d1, lower)), Q())),
                       (-sum((b*t for b, t in zip(d2, upper)), Q()),
                        sum((a*t for a, t in zip(d1, upper)), Q()))])
    return result


def clip(cell, inequalities):
    lo, hi = cell
    for constant, slope in inequalities:
        if slope == 0:
            if constant > 0:
                return None
        elif slope > 0:
            bound = -constant/slope
            hi = bound if hi is None else min(hi, bound)
        else:
            bound = -constant/slope
            lo = bound if lo is None else max(lo, bound)
        if lo is not None and hi is not None and lo > hi:
            return None
    return lo, hi


def assignment(coefficients, rows):
    answer = []
    for row in rows:
        values = [lo if c > 0 else hi if c < 0 else (lo+hi)/2
                  for c, (lo, hi) in zip(coefficients, row)]
        remaining = -sum((c*t for c, t in zip(coefficients, values)), Q())
        require(remaining >= 0, 'Witness lower range positive')
        for i, (c, (lo, hi)) in enumerate(zip(coefficients, row)):
            if c:
                increase = min(remaining, abs(c)*(hi-lo))
                values[i] += increase/c
                remaining -= increase
        require(remaining == 0, 'Witness upper range negative')
        answer.append(values)
    return answer


def edge_values(coefficients, values):
    return [sum((c*t for c, t in zip(coefficients, row)), Q()) for row in values]


def witness(d1, d2, rows, coefficients, mode, value):
    values = assignment(coefficients, rows)
    edges = [edge_values(d1, values), edge_values(d2, values)]
    a, b = edges
    require(all(lo <= t <= hi for row, domain in zip(values, rows) for t, (lo, hi) in zip(row, domain))
            and all(a[i]*b[j]-a[j]*b[i] == 0 for i, j in ((1, 2), (2, 0), (0, 1))),
            'Constructed witness bound/cross failed')
    return packed({'status': DEGENERATE, 'mode': mode, 'lambda': value,
                   'assignment': values, 'edges': edges})


def solve_rectangle(d1, d2, rows):
    d1, d2, rows = domain_values(d1, d2, rows)
    ranges = [row_range(d1, row) for row in rows]
    if all(lo <= 0 <= hi for lo, hi in ranges):
        return witness(d1, d2, rows, d1, 'zero_edge', None)
    points = breakpoints(d1, d2)
    cells = []
    for cell in lambda_cells(points):
        inequalities = cell_inequalities(d1, d2, rows, cell)
        feasible = clip(cell, inequalities)
        if feasible is not None:
            lo, hi = feasible
            value = max(Q(), lo) if lo is not None else Q()
            if hi is not None:
                value = min(value, hi)
            return witness(d1, d2, rows, tuple(b-value*a for a, b in zip(d1, d2)), 'finite_lambda', value)
        cells.append({'cell': cell, 'inequalities': inequalities})
    return packed({'status': NONDEGENERATE, 'zero_edge_ranges': ranges, 'zero_edge_infeasible': True,
                   'breakpoints': points, 'cells': cells})


def replay_rectangle(d1, d2, rows, proof):
    """Independent SAT substitution or all-real-line halfspace contradiction.

    Replay does not call the solver, its range, cell, clip or witness helpers.
    """
    d1, d2, rows = domain_values(d1, d2, rows)
    require(type(proof) is dict, 'Malformed rectangle proof')
    if proof.get('status') == DEGENERATE:
        require(set(proof) == {'status', 'mode', 'lambda', 'assignment', 'edges'}, 'Witness schema')
        values = proof['assignment']
        require(type(values) is list and len(values) == 3 and all(len(row) == len(d1) for row in values),
                'Missing witness row/variable')
        values = [[fraction(t) for t in row] for row in values]
        require(all(lo <= t <= hi for row, domain in zip(values, rows)
                    for t, (lo, hi) in zip(row, domain)), 'Witness outside original rectangle')
        edges = [[sum((c*t for c, t in zip(coefficients, row)), Q()) for row in values]
                 for coefficients in (d1, d2)]
        require(type(proof['edges']) is list and len(proof['edges']) == 2
                and all(type(e) is list and len(e) == 3 for e in proof['edges'])
                and [[fraction(v) for v in e] for e in proof['edges']] == edges,
                'Reconstructed witness edges differ')
        a, b = edges
        require(all(a[i]*b[j]-a[j]*b[i] == 0 for i, j in ((1, 2), (2, 0), (0, 1))),
                'Reconstructed cross is nonzero')
        if proof['mode'] == 'zero_edge':
            require(proof['lambda'] is None and a == [0, 0, 0], 'Invalid projective zero-edge witness')
        else:
            require(proof['mode'] == 'finite_lambda', 'Unsupported witness mode')
            value = fraction(proof['lambda'])
            require(all(y == value*x for x, y in zip(a, b)), 'Exact lambda equation failed')
        return
    require(proof.get('status') == NONDEGENERATE and set(proof) ==
            {'status', 'zero_edge_ranges', 'zero_edge_infeasible', 'breakpoints', 'cells'}, 'Nondegenerate schema')
    ranges = [(sum((c*(lo if c >= 0 else hi) for c, (lo, hi) in zip(d1, row)), Q()),
               sum((c*(hi if c >= 0 else lo) for c, (lo, hi) in zip(d1, row)), Q())) for row in rows]
    require([[fraction(v) for v in row] for row in proof['zero_edge_ranges']] == [list(row) for row in ranges]
            and proof['zero_edge_infeasible'] is True
            and any(lo > 0 or hi < 0 for lo, hi in ranges), 'Missing/inaccurate zero-edge exclusion')
    points = sorted(set(b/a for a, b in zip(d1, d2) if a != 0))
    require([fraction(v) for v in proof['breakpoints']] == points and len(proof['cells']) == len(points)+1,
            'Missing breakpoint/cell coverage')
    for i, saved in enumerate(proof['cells']):
        left = None if i == 0 else points[i-1]
        right = None if i == len(points) else points[i]
        require(set(saved) == {'cell', 'inequalities'}
                and [None if v is None else fraction(v) for v in saved['cell']] == [left, right],
                'Cell boundary/tail gap')
        sample = (left+right)/2 if left is not None and right is not None else (
            right-1 if right is not None else left+1 if left is not None else Q())
        inequalities = []
        for row in rows:
            low_constant = low_slope = high_constant = high_slope = Q()
            for a, b, (lo, hi) in zip(d1, d2, row):
                if b-sample*a < 0:
                    lo, hi = hi, lo
                low_constant += b*lo; low_slope -= a*lo
                high_constant -= b*hi; high_slope += a*hi
            inequalities.extend([(low_constant, low_slope), (high_constant, high_slope)])
        require([[fraction(v) for v in row] for row in saved['inequalities']] == [list(row) for row in inequalities],
                'Cell affine inequality differs')
        lower = ([left] if left is not None else [])+[-c/s for c, s in inequalities if s < 0]
        upper = ([right] if right is not None else [])+[-c/s for c, s in inequalities if s > 0]
        impossible = any(c > 0 for c, s in inequalities if s == 0)
        impossible |= bool(lower and upper and max(lower) > min(upper))
        require(impossible, 'Fake nondegenerate proof: surviving closed lambda cell')


STEP = 'CAV-CONTACT-MATRIX-BOX-OBSTRUCTIONS'
PREDECESSOR = 'CAV-CONTACT-PHASE-NORMAL-PROJECTION'
REPORT_SHA = 'e7137a7ccfbd1559b8f2736565e4f7eafff6acff2f8afc5e85b517ad0f32c04c'
REPORT_BYTES = 498049055
RECEIPT_SHA = '9bb49daf0da931fdb167690328da88c301b8e1097b3e58920e769078418572ed'
REMAINING_SHA = 'a6dcf6bd48b442ee355aaa181aa676d2db8d7b9893fb6add393a8e8d5eefbbbd'
REVIEWED_HEAD = '205b6f2c6bfabaa26472b1f5fdedfaefe08ddcc9'
MERGE_HEAD = '6429e8f6ade732fb169922e2869bb58690be3b03'
HELPER_SHA = 'a8678036793b5588b99e9a43fa825283bd41d80b75bf20a28cfbb1d51c41eec9'
ATLAS_SHA = '1a404021b32f6c8f2ed91408a27e2894c18e82200150be91365db907c380e17e'
SHAPE_METHOD = 'shared-native-skin-signed-homogeneous-wedge-with-ordered-lbs-residual-v1'
PARENT = [0.2666666805744171, 0.29999001192092895]
HELPER_KEY = 'tools/units3d/cavalry_march_phase.py'
HISTORY = ('baseline_accounting', 'previous_operation_accounting', 'previous_norm_accounting',
           'previous_shape_accounting')
MEANING = ('Rational points in independent REAL rounded-matrix rectangles and zero-error allowances only. '
           'May violate binary32 discreteness, FK, quaternion, shared-parent or time correlations. '
           'Neither an executable native pose nor actual degeneration/inversion/contact/physical impossibility. '
           'NONDEGENERATE excludes reference degeneracy only, gives no quantitative native area lower bound. '
           'No birth criterion is solved. Original slip and all missing physical context remain.')


def load_coefficient_helper(path):
    source = path.read_bytes()
    require(hashlib.sha256(source).hexdigest() == HELPER_SHA, 'Stale accepted helper source')
    tree = ast.parse(source, filename=str(path))
    function = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                    and node.name == 'triangle_coefficients')
    # Execute only the hash-pinned pure helper, never the module/native runner.
    function.decorator_list = []
    namespace = {'Q': Q, 'rational': exact}
    exec(compile(ast.Module(body=[function], type_ignores=[]), str(path), 'exec'), namespace)
    return namespace['triangle_coefficients']


def raw_coefficients(proof, helper):
    require(proof['method'] == SHAPE_METHOD and len(proof['vertex_ids']) == 3
            and all(type(v) is int and v >= 0 for v in proof['vertex_ids'])
            and len(set(proof['vertex_ids'])) == 3, 'Malformed face/vertex identity')
    raw = proof['raw_vertices_joints_weights']
    require(len(raw) == 3 and all(len(v) == 3 for v in raw), 'Missing raw triangle')
    for position, joints, weights in raw:
        require(len(position) == 3 and len(joints) == len(weights) == 4
                and all(type(j) is int and j >= 0 for j in joints), 'Malformed native influence slot')
        tuple(map(exact, position))
        require(all(exact(w) >= 0 for w in weights), 'Negative raw native weight')
    require(1 <= len(proof['branches']) == len(proof['shared_transform_certificates']) <= 2
            and len(set(proof['shared_transform_certificates'])) == len(proof['branches']),
            'Missing/duplicate terminal branch')
    coefficients = helper(tuple(tuple(tuple(v) for v in row) for row in raw))
    require(proof['edge_coefficients'] == packed([[{'bind_index': j, 'homogeneous': h}
            for j, h in edge] for edge in coefficients]), 'Raw signed homogeneous coefficient mismatch')
    maps = [dict(edge) for edge in coefficients]
    variables = sorted({(j, k) for edge in coefficients for j, h in edge for k, c in enumerate(h) if c})
    require(len(variables) <= 48, 'Raw 3x4x4 variable bound exceeded')
    edges = [tuple(mapping.get(j, (Q(),)*4)[k] for j, k in variables) for mapping in maps]
    return variables, *edges


def matrix_domain(key, identity):
    require(digest(identity) == key and set(identity) == {'method', 'seconds', 'source_sha256', 'matrix_interval'}
            and identity['method'] == SHAPE_METHOD, 'Stale/malformed matrix context')
    require(len(identity['seconds']) == 2 and exact(identity['seconds'][0]) <= exact(identity['seconds'][1]),
            'Malformed matrix time interval')
    require(type(identity['source_sha256']) is str and len(identity['source_sha256']) == 64,
            'Malformed raw/bind source digest')
    bounds = identity['matrix_interval']
    require(len(bounds) == 2 and len(bounds[0]) == len(bounds[1]) > 0
            and all(len(matrix) == 3 and all(len(row) == 4 for row in matrix) for side in bounds for matrix in side),
            'Malformed full 3x4 matrix rectangle')
    lo, hi = [tuple(tuple(tuple(map(exact, row)) for row in matrix) for matrix in side) for side in bounds]
    require(all(x <= y for a, b in zip(lo, hi) for c, d in zip(a, b) for x, y in zip(c, d)),
            'Reversed full matrix interval')
    return lo, hi


def check_zero_error(branch, centered):
    residuals = [[fraction(v) for v in row] for row in branch['vertex_native_residual_absolute']]
    require(len(residuals) == 3 and all(len(row) == 3 and min(row) >= 0 for row in residuals),
            'Invalid symmetric native vertex error allowance')
    require(len(branch['edges']) == 2, 'Missing native edge error')
    for e, edge in enumerate(branch['edges']):
        errors = [fraction(v) for v in edge['native_residual_absolute']]
        require(errors == [residuals[0][a]+residuals[e+1][a] for a in range(3)],
                'Edge error allowance differs from vertex errors')
    interval = centered['residual_cross_interval']
    require(len(interval) == 2 and all(len(side) == 3 for side in interval)
            and all(exact(a) <= 0 <= exact(b) for a, b in zip(*interval)),
            'Zero cross-error not admitted by accepted allowance')


def check_relaxed_witness(proof, job):
    if proof['status'] != DEGENERATE:
        return
    edges = [[fraction(v) for v in edge] for edge in proof['edges']]
    require(all(exact(lo) <= v <= exact(hi) for edge, interval in zip(edges, job['native_edge_intervals'])
                for v, lo, hi in zip(edge, *interval)), 'Zero-error witness violates accepted edge enclosure')
    require(all(exact(lo) <= 0 <= exact(hi) for interval in job['native_cross_intervals']
                for lo, hi in zip(*interval)), 'Zero-error witness violates accepted cross enclosure')


def face_key(target):
    return target['hoof'], target['native_triangle_id'], target['original_local_triangle_index']


def target_key(target):
    return tuple(target['seconds']), *face_key(target)


def classify_alternatives(parent, children):
    groups = [parent] if children is None else [parent, *children]
    require((children is None or len(children) == 2) and all(group and all(
        status in (DEGENERATE, NONDEGENERATE) for status in group) for group in groups),
        'Missing/unresolved branch or child alternative')
    obstructed = DEGENERATE in parent
    if children is None:
        return 'UNREFINED_RECTANGLE_OBSTRUCTED' if obstructed else 'REFERENCE_BOX_NONDEGENERATE'
    child_obstruction = any(DEGENERATE in group for group in children)
    if obstructed and child_obstruction:
        return 'ALL_CURRENT_RECTANGLE_ALTERNATIVES_OBSTRUCTED'
    if obstructed:
        return 'PARENT_OBSTRUCTED_CHILD_COVER_NONDEGENERATE'
    if child_obstruction:
        return 'PARENT_NONDEGENERATE_CHILD_COVER_OBSTRUCTED'
    return 'REFERENCE_BOX_NONDEGENERATE'


def signature(path):
    s = path.stat()
    return s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def bound_json(path, expected_sha, expected_size=None):
    before = signature(path)
    require(expected_size is None or before[2] == expected_size, 'Frozen input size mismatch')
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == expected_sha, 'Stale/unaccepted frozen input hash')
    value = json.loads(raw)
    require(signature(path) == before, 'Frozen input changed while loading')
    return value, before


def validate_atlas_binding(atlas_sha256, computed_packet_sha256):
    require(atlas_sha256 == ATLAS_SHA and computed_packet_sha256 == ATLAS_SHA,
            'Frozen report current atlas binding mismatch')


def load_packet(args):
    receipt, receipt_stat = bound_json(args.receipt, RECEIPT_SHA)
    require(receipt['accepted'] is True and receipt['merged'] is True and receipt['step_id'] == PREDECESSOR
            and receipt['head'] == REVIEWED_HEAD and receipt['merge_sha'] == MERGE_HEAD
            and receipt['actual_current_HEAD_CI_all12_success'] is True and receipt['ci_run_id'] == 41884930105
            and receipt['reviewer_product_edits'] is False and receipt['final_report_sha256'] == REPORT_SHA
            and receipt['exact_remaining_targets']['sha256'] == REMAINING_SHA
            and receipt['E'] is None and receipt['physical_acceptance'] is False, 'Acceptance receipt custody mismatch')
    report, report_stat = bound_json(args.report, REPORT_SHA, REPORT_BYTES)
    remaining, remaining_stat = bound_json(args.remaining, REMAINING_SHA)
    require(report['version'] == 9 and report['step_id'] == PREDECESSOR
            and report['status'] == 'DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY',
            'Frozen report identity/status mismatch')
    validate_atlas_binding(report['atlas']['input_sha256'], digest(report['atlas_input_packet']))
    bindings = report['inputs']
    require(len(bindings) == 806 and bindings[HELPER_KEY] == HELPER_SHA
            and len(report['accepted263_input_bindings']) == 805
            and set(bindings) == set(report['accepted263_input_bindings']) | {'projection_baseline_report'}
            and all(type(k) is str and type(v) is str and len(v) == 64 and all(c in '0123456789abcdef' for c in v)
                    for k, v in bindings.items()), 'Complete 806-name binding custody mismatch')
    changed = {k for k, v in report['accepted263_input_bindings'].items() if bindings[k] != v}
    require(changed <= {HELPER_KEY, 'tools/units3d/test_cavalry_march_phase.py'}, 'Changed accepted nonalgorithm input')
    claims = report['claims']
    require(claims['policy_E'] is None and claims['original_12_gates_preserved'] is True
            and all(v is False for k, v in claims.items() if k not in ('policy_E', 'original_12_gates_preserved')),
            'Diagnostic cannot grant physical/native/CERT acceptance')
    helper_stat = signature(args.helper_source)
    helper = load_coefficient_helper(args.helper_source)
    watched = [(args.report, report_stat), (args.receipt, receipt_stat), (args.remaining, remaining_stat),
               (args.helper_source, helper_stat)]
    return report, receipt, remaining, helper, watched


def unchanged(watched):
    require(all(signature(path) == stamp for path, stamp in watched), 'Input changed during analysis/replay')


def index_targets(targets):
    result = {target_key(t): t for t in targets}
    require(len(result) == len(targets), 'Duplicate full target identity')
    return result


def build_inventory(report, remaining, helper):
    """Read accepted identities without rerunning or wrapping accepted science."""
    overlay = report['normal_projection']
    require(len(overlay['area_targets']) == 7760 and len(overlay['birth_targets']) == 2797
            and len(overlay['children']) == 2, 'Wrong full target denominator/child count')
    for kind, total, closed, unknown in [('area_targets', 7760, 5046, 2714), ('birth_targets', 2797, 1985, 812)]:
        targets = overlay[kind]
        index_targets(targets)
        require(len(targets) == total and sum(t['outcome'] == 'CLOSED' for t in targets) == closed
                and sum(t['outcome'] == 'UNKNOWN' for t in targets) == unknown
                and digest([t for t in targets if t['outcome'] == 'UNKNOWN']) == digest(remaining[kind]),
                'Missing/stale remaining inventory or changed accepted outcomes')
    for name, coordinates, shapes in zip(HISTORY, [69, 19, 18, None], [18, 3028, 3677, 2797]):
        value = report[name]
        require((coordinates is None or len(value['coordinate_boxes']) == coordinates)
                and len(value['shape_cases']) == shapes,
                'Lost original historical denominator')
    require(tuple(report['work_used'][k] for k in ('attempts', 'refinement_splits', 'proposal_evaluations',
                                                  'float32_weight_values')) == (42, 1, 329, 1118),
            'Original acquisition/work changed')
    rows = report['continuous_native']['closed_boxes']
    refinement = report['shape_refinement']
    require(len(rows) == 40 and not report['continuous_native']['unclosed_boxes']
            and refinement['parent_seconds'] == PARENT and len(refinement['children']) == 2,
            'Original span/refinement inventory mismatch')
    a, b = PARENT; mid = (a+b)/2
    require([r['seconds'] for r in refinement['children']] == [[a, mid], [mid, b]]
            and [r['seconds'] for r in overlay['children']] == [[a, mid], [mid, b]], 'Child partition changed')
    patches = report['shape_proof']['full_material_patches']
    require(sum(len(p['native_sole_triangles']) for p in patches.values()) == 194
            and len({f for p in patches.values() for f in p['native_sole_triangles']}) == 194,
            'Lost/duplicate original material face')
    matrices = report['shape_proof']['shared_skin_certificates']
    # Each context is checked once, but every face/branch join below is checked.
    domains = {key: matrix_domain(key, identity) for key, identity in matrices.items()}
    originals, area_sources, birth_sources = {}, {}, {}
    for row in [*rows, *refinement['children']]:
        require('reason' not in row and set(row['triangle_area']) == set(patches), 'Missing child/hoof source')
        for hoof, area in row['triangle_area'].items():
            patch = patches[hoof]
            require(area['native_triangle_ids'] == patch['native_sole_triangles']
                    and len(area['certificates']) == len(area['native_triangle_ids']), 'Source face census changed')
            for i, (face, original) in enumerate(zip(area['native_triangle_ids'], area['certificates'])):
                key = (tuple(row['seconds']), hoof, face, i)
                require(original['vertex_ids'] == patch['native_triangles'][i], 'Source vertex/winding identity changed')
                sha = digest(original)
                originals[sha] = original
                area_sources[key] = sha
                times = [matrices[d]['seconds'] for d in original['shared_transform_certificates']]
                require(times[0] == row['seconds'] and (len(times) == 1 or
                    (len(times) == 2 and row['seconds'][1] == report['atlas']['clip_seconds'] and times[1] == [0., 0.])),
                    'Missing/reordered direct-terminal/player-zero branch')
        for hoof, shape in row['triangle_shape'].items():
            require(shape['native_triangle_ids'] == patches[hoof]['native_sole_triangles']
                    and len(shape['certificates']) == len(shape['native_triangle_ids']), 'Birth face census changed')
            for i, (face, anchor) in enumerate(zip(shape['native_triangle_ids'], shape['certificates'])):
                key = (tuple(row['seconds']), hoof, face, i)
                require(digest(anchor['current']) == area_sources[key]
                        and anchor['birth']['vertex_ids'] == patches[hoof]['native_triangles'][i],
                        'Birth/current source identity mismatch')
                birth_sha = digest(anchor['birth'])
                originals[birth_sha] = anchor['birth']
                birth_sources[key] = birth_sha
    require(set(originals) == set(report['centered_wedge']['certificates'])
            == set(overlay['certificates']), 'Missing accepted source/anchor certificate')
    for target in overlay['area_targets']:
        require(area_sources.get(target_key(target)) == target['current_sha256'], 'Area target/source join differs')
    for target in overlay['birth_targets']:
        require(area_sources.get(target_key(target)) == target['current_sha256']
                and birth_sources.get(target_key(target)) == target['original_birth_sha256'],
                'Birth target/source/anchor join differs')
    children = []
    for child in overlay['children']:
        amap, bmap = index_targets(child['area_targets']), index_targets(child['birth_targets'])
        require(len(amap) == 194 and len(bmap) == 148, 'Missing child area/birth denominator')
        for key, target in amap.items():
            require(area_sources.get(key) == target['current_sha256'] and target['seconds'] == child['seconds'],
                    'Child area identity differs')
        for key, target in bmap.items():
            require(birth_sources.get(key) == target['original_birth_sha256']
                    and area_sources.get(key) == target['current_sha256'], 'Child anchor identity differs')
        children.append(({face_key(t): t for t in amap.values()}, {face_key(t): t for t in bmap.values()}))
    jobs, links = {}, {}
    def add(target):
        sha = target['current_sha256']; proof = originals[sha]
        variables, d1, d2 = raw_coefficients(proof, helper)
        centered = report['centered_wedge']['certificates'][sha]
        projected = overlay['certificates'][sha]
        require(len(centered['branches']) == len(projected['branches']) == len(proof['branches']),
                'Missing accepted branch alternative')
        ids = []
        for i, (context_sha, branch) in enumerate(zip(proof['shared_transform_certificates'], proof['branches'])):
            center = centered['branches'][i]; projection = projected['branches'][i]
            require(center['shared_transform_sha256'] == projection['shared_transform_sha256'] == context_sha
                    and center['native_residual_sha256'] == projection['native_residual_sha256'] == digest(branch),
                    'Stale residual/context branch identity')
            check_zero_error(branch, center)
            lo, hi = domains[context_sha]
            require(all(0 <= j < len(lo) for _, joints, _ in proof['raw_vertices_joints_weights'] for j in joints),
                    'Raw influence missing bind matrix')
            rectangle = tuple(tuple((lo[j][axis][k], hi[j][axis][k]) for j, k in variables) for axis in range(3))
            jid = digest([sha, i, context_sha]); ids.append(jid)
            if jid not in jobs:
                jobs[jid] = {'certificate_sha256': sha, 'branch_index': i, 'shared_transform_sha256': context_sha,
                             'variables': variables, 'd1': d1, 'd2': d2, 'rows': rectangle,
                             'native_edge_intervals': [e['interval'] for e in branch['edges']],
                             'native_cross_intervals': [proof['cross_interval'], center['native_centered_cross_interval']],
                             'zero_error_allowance_sha256': digest([branch, center['residual_cross_interval']])}
        return ids
    for t in remaining['area_targets']:
        parent_ids = add(t)
        child_ids = None
        if t['seconds'] == PARENT:
            child_targets = [maps[0].get(face_key(t)) for maps in children]
            require(all(child_targets), 'Missing required child face')
            for child in child_targets:
                raw_parent, raw_child = originals[t['current_sha256']], originals[child['current_sha256']]
                require(all(raw_parent[k] == raw_child[k] for k in
                    ('vertex_ids', 'raw_vertices_joints_weights', 'edge_coefficients')), 'Child raw face changed')
            child_ids = [add(child) for child in child_targets]
        links[target_key(t)] = {'parent': parent_ids, 'children': child_ids}
    return jobs, links, domains


def work_plan(jobs, links):
    entries = []
    for jid, job in sorted(jobs.items()):
        m = len(job['d1']); count = len(breakpoints(job['d1'], job['d2']))
        require(count <= m <= 48, 'Breakpoint/variable plan bound')
        entries.append({'job_id': jid, 'm': m, 'breakpoints': count, 'closed_cells': count+1,
                        'zero_plus_cell_row_term_visits_bound': 3*m*(count+2),
                        'witness_construction_row_term_visits_bound': 12*m,
                        'sat_replay_row_term_visits_bound': 12*m,
                        'unsat_replay_row_term_visits_bound': 3*m*(count+2)})
    parent_branches = sum(len(link['parent']) for link in links.values())
    child_branches = sum(len(group) for link in links.values() if link['children'] is not None
                         for group in link['children'])
    require(len(jobs) <= parent_branches+child_branches, 'Unaccounted unique context/face job')
    return {'unique_face_context_jobs': len(jobs), 'original_unknown_targets': len(links),
            'original_target_branch_counts': dict(sorted(Counter(len(link['parent']) for link in links.values()).items())),
            'parent_branch_visits': parent_branches, 'child_branch_visits': child_branches,
            'refined_unknown_parent_faces': sum(link['children'] is not None for link in links.values()),
            'all_original_unknown_parents_single_branch': all(len(link['parent']) == 1 for link in links.values()),
            'entries': entries,
            'bounds': {key: sum(row[key] for row in entries) for key in
                       ('zero_plus_cell_row_term_visits_bound', 'witness_construction_row_term_visits_bound',
                        'sat_replay_row_term_visits_bound', 'unsat_replay_row_term_visits_bound')},
            'counting': 'One row-term visit handles its paired extrema/affine contributions (up to four multiply-adds). '
                        'Construction/replay separately bounded. Exact arithmetic bit growth and wall time are not predicted.'}


def accepted_inventory(report):
    overlay = report['normal_projection']
    return {'input_bindings': report['inputs'], 'area_targets': overlay['area_targets'],
            'birth_targets': overlay['birth_targets'], 'children': overlay['children'],
            'history': {k: report[k] for k in HISTORY}, 'claims': report['claims'],
            'source_support_constraints': report['source_support_constraints'],
            'full_geometry': report['full_geometry'], 'missing_physical_context': report['missing_physical_context'],
            'finite_endpoint_necessary_conditions': report['finite_endpoint_necessary_conditions'],
            'fit': report['fit'], 'acquisition_work': report['work_used'],
            'preserved_report_field_sha256': {k: digest(report[k]) for k in
                ('input_binding', 'atlas', 'accepted_anatomy', 'metric_bounds', 'dense_native_comparison')}}


def job_identity(job):
    return {k: packed(job[k]) for k in ('certificate_sha256', 'branch_index', 'shared_transform_sha256',
                                      'variables', 'zero_error_allowance_sha256')}


def dispositions(remaining, links, proofs, child_rows):
    areas = []
    for t in remaining['area_targets']:
        linked = links[target_key(t)]
        parent = [proofs[j]['proof']['status'] for j in linked['parent']]
        children = None if linked['children'] is None else [[proofs[j]['proof']['status'] for j in group]
                                                          for group in linked['children']]
        areas.append({'target': t, 'parent_jobs': linked['parent'], 'child_jobs': linked['children'],
                      'parent_obstruction': DEGENERATE in parent,
                      'child_cover_obstruction': None if children is None else any(DEGENERATE in g for g in children),
                      'classification': classify_alternatives(parent, children)})
    by_area = {target_key(row['target']): row for row in areas}
    child_births = [{face_key(t): t for t in row['birth_targets']} for row in child_rows]
    births = []
    for t in remaining['birth_targets']:
        area = by_area.get(target_key(t))
        is_area_unknown = 'area_interval_contains_zero' in t['reasons']
        require((area is not None) == is_area_unknown, 'Birth/area unknown cross-link differs')
        child_targets = [child.get(face_key(t)) for child in child_births] if t['seconds'] == PARENT else None
        require(child_targets is None or (len(child_targets) == 2 and all(child_targets)
                and all(child['original_birth_sha256'] == t['original_birth_sha256'] for child in child_targets)),
                'Missing/changed original birth child mapping')
        births.append({'target': t, 'birth_status': 'UNRESOLVED_ORIGINAL_BIRTH_CRITERION',
                       'area_classification': area['classification'] if area else 'ACCEPTED_POSITIVE_AREA_DOT_UNRESOLVED',
                       'original_child_targets': child_targets,
                       'parent_jobs': area['parent_jobs'] if area else [],
                       'child_jobs': area['child_jobs'] if area else None})
    require(sum(row['area_classification'] == 'ACCEPTED_POSITIVE_AREA_DOT_UNRESOLVED' for row in births) == 119
            and sum('area_interval_contains_zero' in row['target']['reasons'] for row in births) == 693,
            'Full 812 birth unknown split changed')
    return areas, births


def counts_by_targets(targets):
    # Span keys retain exact binary endpoint values; epsilon is the accepted <1e-4s search cell.
    return {'targets': len(targets),
            'by_hoof': dict(sorted(Counter(t['hoof'] for t in targets).items())),
            'by_face': dict(sorted(Counter(f"{t['hoof']}:{t['native_triangle_id']}:{t['original_local_triangle_index']}"
                                           for t in targets).items())),
            'by_span': dict(sorted(Counter(json.dumps(t['seconds'], separators=(',', ':')) for t in targets).items())),
            'distinct_faces': len({face_key(t) for t in targets}),
            'spans': len({tuple(t['seconds']) for t in targets}),
            'narrow_epsilon_targets': sum(exact(t['seconds'][1])-exact(t['seconds'][0]) < Q(1, 10000)
                                         for t in targets)}


def summary(areas, births, proofs):
    area_targets = [row['target'] for row in areas]
    birth_targets = [row['target'] for row in births]
    result = {'accepted_area_counts': {'CLOSED': 5046, 'UNKNOWN': 2714},
              'accepted_birth_counts': {'CLOSED': 1985, 'UNKNOWN': 812},
              'unknown_area_inventory': counts_by_targets(area_targets),
              'unknown_birth_inventory': counts_by_targets(birth_targets),
              'area_classifications': dict(sorted(Counter(row['classification'] for row in areas).items())),
              'birth_area_classifications': dict(sorted(Counter(row['area_classification'] for row in births).items())),
              'branch_classifications': dict(sorted(Counter(p['proof']['status'] for p in proofs.values()).items())),
              'by_area_classification': {name: counts_by_targets([row['target'] for row in areas if row['classification'] == name])
                                         for name in sorted({row['classification'] for row in areas})},
              'birth_proved_negative_dot_upper': sum(t['dot_interval'][1] < 0 for t in birth_targets),
              'unresolved_jobs': 0, 'new_area_closures': 0, 'new_birth_closures': 0}
    a, b = result['unknown_area_inventory'], result['unknown_birth_inventory']
    require((a['targets'], a['distinct_faces'], a['spans'], a['narrow_epsilon_targets']) == (2714, 194, 36, 204)
            and (b['targets'], b['distinct_faces'], b['spans'], b['narrow_epsilon_targets']) == (812, 165, 18, 29)
            and result['birth_proved_negative_dot_upper'] == 0, 'Remaining face/span/epsilon denominator differs')
    return result


def provenance():
    here = Path(__file__).resolve()
    return {'accepted_report_sha256': REPORT_SHA, 'accepted_report_bytes': REPORT_BYTES,
            'accepted_receipt_sha256': RECEIPT_SHA, 'remaining_sha256': REMAINING_SHA,
            'reviewed_head': REVIEWED_HEAD, 'accepted_merge_head': MERGE_HEAD,
            'accepted_helper_source_sha256': HELPER_SHA,
            'sidecar_source_sha256': hashlib.sha256(here.read_bytes()).hexdigest(),
            'test_source_sha256': hashlib.sha256(here.with_name('test_analyze_cavalry_matrix_boxes.py').read_bytes()).hexdigest()}


def analyze(report, remaining, jobs, links, plan):
    proofs = {}
    for jid, job in sorted(jobs.items()):
        proof = solve_rectangle(job['d1'], job['d2'], job['rows'])
        check_relaxed_witness(proof, job)
        proofs[jid] = {**job_identity(job), 'unused_matrix_entries': 'exact_interval_midpoint',
                       'zero_error_assignment': 'all_vertex_edge_and_cross_errors_zero_in_relaxation', 'proof': proof}
    areas, births = dispositions(remaining, links, proofs, report['normal_projection']['children'])
    return {'version': 1, 'step_id': STEP, 'status': 'COMPLETE_REFERENCE_RELAXATION_DIAGNOSTIC_ONLY',
            'provenance': provenance(), 'meaning': MEANING,
            'accepted': accepted_inventory(report), 'work_plan': plan, 'certificates': proofs,
            'area_dispositions': areas, 'birth_dispositions': births, 'summary': summary(areas, births, proofs)}


def verify_sidecar(sidecar, report, remaining, jobs, links, plan):
    require(set(sidecar) == {'version', 'step_id', 'status', 'provenance', 'meaning', 'accepted', 'work_plan',
            'certificates', 'area_dispositions', 'birth_dispositions', 'summary'}
            and sidecar['version'] == 1 and sidecar['step_id'] == STEP
            and sidecar['status'] == 'COMPLETE_REFERENCE_RELAXATION_DIAGNOSTIC_ONLY'
            and sidecar['meaning'] == MEANING and sidecar['provenance'] == provenance(),
            'Sidecar schema/source/provenance/meaning differs')
    require(digest(sidecar['accepted']) == digest(accepted_inventory(report))
            and digest(sidecar['work_plan']) == digest(plan), 'Changed binding/denominator/closed bound/history/work plan')
    proofs = sidecar['certificates']
    require(set(proofs) == set(jobs), 'Missing/extra branch/child job certificate')
    for jid, job in sorted(jobs.items()):
        certificate = proofs[jid]
        expected = {**job_identity(job), 'unused_matrix_entries': 'exact_interval_midpoint',
                    'zero_error_assignment': 'all_vertex_edge_and_cross_errors_zero_in_relaxation'}
        require(set(certificate) == set(expected) | {'proof'}
                and digest({k: certificate[k] for k in expected}) == digest(expected),
                'Changed branch/variable/zero-error witness binding')
        replay_rectangle(job['d1'], job['d2'], job['rows'], certificate['proof'])
        check_relaxed_witness(certificate['proof'], job)
        # Unlisted entries have this exact rational midpoint in the complete matrix assignment.
        # Their domains were validated once above; lo <= (lo+hi)/2 <= hi for every finite entry.
    areas, births = dispositions(remaining, links, proofs, report['normal_projection']['children'])
    require(digest(sidecar['area_dispositions']) == digest(areas)
            and digest(sidecar['birth_dispositions']) == digest(births)
            and digest(sidecar['summary']) == digest(summary(areas, births, proofs)),
            'Full disposition/child/anchor/count replay differs')


def write_new(path, value):
    with path.open('x') as output:
        json.dump(value, output, sort_keys=True, separators=(',', ':'), allow_nan=False)
        output.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('analyze', 'verify'))
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--remaining', type=Path, required=True)
    parser.add_argument('--helper-source', type=Path, default=Path(__file__).with_name('cavalry_march_phase.py'))
    parser.add_argument('--out', type=Path, required=True, help='New sidecar (analyze) or new replay receipt (verify)')
    parser.add_argument('--sidecar', type=Path, help='Complete sidecar to replay; verify only')
    parser.add_argument('--plan-out', type=Path, required=True, help='New deterministic preflight plan, written before solving/replay')
    args = parser.parse_args()
    require((args.command == 'verify') == (args.sidecar is not None), 'Verify requires exactly one sidecar')
    inputs = [args.report, args.receipt, args.remaining, args.helper_source, Path(__file__),
              Path(__file__).with_name('test_analyze_cavalry_matrix_boxes.py')]
    if args.sidecar is not None:
        inputs.append(args.sidecar)
    resolved = [path.resolve() for path in inputs]
    require(args.out.resolve() not in resolved and args.plan_out.resolve() not in resolved
            and args.out.resolve() != args.plan_out.resolve() and not args.out.exists() and not args.plan_out.exists(),
            'Output collision or existing evidence would be overwritten')
    code_stamps = [(path, signature(path)) for path in inputs[4:]]
    report, receipt, remaining, helper, watched = load_packet(args)
    watched.extend(code_stamps)
    jobs, links, domains = build_inventory(report, remaining, helper)
    plan = work_plan(jobs, links)
    write_new(args.plan_out, {'step_id': STEP, 'provenance': provenance(), 'work_plan': plan})
    print(json.dumps({'phase': 'complete_inventory_preflight', 'jobs': len(jobs),
                      'bounds': plan['bounds'], 'parent_branch_counts': plan['original_target_branch_counts']}), flush=True)
    if args.command == 'analyze':
        result = analyze(report, remaining, jobs, links, plan)
    else:
        stamp = signature(args.sidecar)
        raw = args.sidecar.read_bytes()
        sidecar_sha = hashlib.sha256(raw).hexdigest()
        sidecar = json.loads(raw, object_pairs_hook=no_duplicates)
        watched.append((args.sidecar, stamp))
        verify_sidecar(sidecar, report, remaining, jobs, links, plan)
        result = {'step_id': STEP, 'status': 'COMPLETE_INDEPENDENT_EXACT_REPLAY',
                  'sidecar_sha256': sidecar_sha, 'provenance': provenance(), 'summary': sidecar['summary'],
                  'physical_acceptance': False, 'E': None}
    unchanged(watched)
    write_new(args.out, result)
    unchanged(watched)
    print(json.dumps({'phase': 'complete', 'status': result['status'], 'output': str(args.out),
                      'physical_acceptance': False, 'E': None}), flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, IndexError, OSError, OverflowError) as error:
        print(f'UNRESOLVED: {type(error).__name__}: {error}', file=sys.stderr, flush=True)
        sys.exit(1)
