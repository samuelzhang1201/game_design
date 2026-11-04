"""Necessary native Skin metric bounds only; no area, birth or physical closure.

For the actual rounded nonzero quaternion q, R(q) uses 2/(q.q), so R^T R=I
without a unit-quaternion assumption. The error graph follows the pinned native
constructor, then its diagonal Basis product. Weyl/triangle inequalities transport
these bounds through the actual rounded FK and true-bind products.

Writing K=[q_xyz]_cross gives K^3=-|q_xyz|^2 K and
R=I+2/n*(q_w K+K^2). Thus R^T R=I+(4/n-4*n/n^2)K^2=I.
For any unit v, ||Av|| differs from ||R D v|| by at most ||A-R D||_F.
Likewise ||fl(P A)v|| >= L_P L_A-||fl(P A)-P A||_F. A fixed
bind's determinant fallback follows from sigma_min=|det B|/(sigma_1 sigma_2)
and sigma_1 sigma_2<=||B||_F^2. Zero lower bounds confer no positive authority.
"""
from fractions import Fraction as Q
from functools import lru_cache
import hashlib
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELATIVE_SHA = 'd141a909f66b92739b438b744e091c4aec2f8ce10f2f8eec79cca1d4fdeee873'


@lru_cache(maxsize=1)
def accepted():
    path = ROOT/'tools/units3d/bound_cavalry_relative_skin.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != RELATIVE_SHA:
        raise ValueError('Accepted relative Skin source changed')
    spec = importlib.util.spec_from_file_location('_conditioning_relative', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(value, message):
    if not value: raise ValueError(message)


def exact(value): return accepted().exact(value)


@lru_cache(maxsize=1)
def upward():
    rel = accepted()
    namespace = rel.pure_functions(rel.source_bytes(ROOT/'tools/units3d/royal_native_arithmetic/prove.py', rel.SCALAR_SHA),
        ['floor_log2', 'up'], {'F': Q, 'require': require})
    return namespace['up']


def matrix3(value):
    require(len(value) == 3 and all(len(row) == 3 for row in value), 'Expected linear3x3')
    return tuple(tuple(map(exact, row)) for row in value)


def reference_rotation(q):
    require(len(q) == 4, 'Expected quaternion4')
    x, y, z, w = map(exact, q)
    n = x*x+y*y+z*z+w*w
    require(n > 0, 'Nonpositive exact quaternion norm')
    s = 2/n
    return ((1-s*(y*y+z*z), s*(x*y-w*z), s*(x*z+w*y)),
            (s*(x*y+w*z), 1-s*(x*x+z*z), s*(y*z-w*x)),
            (s*(x*z-w*y), s*(y*z+w*x), 1-s*(x*x+y*y)))


def outward(bounds):
    """Use the accepted rational sqrt grid; rounding down may yield UNPROVED."""
    lo, hi = map(exact, bounds)
    require(0 <= lo <= hi, 'Invalid singular-value interval')
    grid = accepted().range_authority().GRID
    a, b = lo*grid, hi*grid
    return Q(a.numerator//a.denominator, grid), Q(-(-b.numerator//b.denominator), grid)


def local_bounds(scale, error):
    scale = tuple(map(exact, scale)); error = exact(error)
    require(len(scale) == 3 and error >= 0, 'Invalid scale/error')
    return outward((max(Q(0), min(map(abs, scale))-error), max(map(abs, scale))+error))


def product_bounds(parent, local, error):
    lp, up = map(exact, parent); ll, ul = map(exact, local); error = exact(error)
    require(0 <= lp <= up and 0 <= ll <= ul and error >= 0, 'Invalid product metric/error')
    return outward((max(Q(0), lp*ll-error), up*ul+error))


def frobenius_upper(value):
    value = matrix3(value)
    return accepted().range_authority().sqrt_bounds(sum(v*v for row in value for v in row))[1]


def bind_conditioning(value):
    b = matrix3(value)
    gram = tuple(tuple(sum(b[k][i]*b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    rows = [(gram[i][i]-sum(abs(gram[i][j]) for j in range(3) if i != j),
             gram[i][i]+sum(abs(gram[i][j]) for j in range(3) if i != j)) for i in range(3)]
    lower, upper = min(v[0] for v in rows), max(v[1] for v in rows)
    det = sum(b[0][j]*(b[1][(j+1)%3]*b[2][(j+2)%3]-b[1][(j+2)%3]*b[2][(j+1)%3]) for j in range(3))
    squared = sum(v*v for row in b for v in row)
    sqrt = accepted().range_authority().sqrt_bounds
    lo = sqrt(lower)[0] if lower > 0 else abs(det)/squared if squared else Q(0)
    return {'matrix': b, 'gram': gram, 'gershgorin_squared': (lower, upper),
            'determinant': det, 'frobenius_squared': squared, 'bounds': outward((lo, sqrt(upper)[1]))}


def basis_error(components, norm, scale):
    """Absolute native error relative to R(q)D, including all FMA/FTZ variants.

    A scalar node stores a reference magnitude m and absolute error e. Products
    propagate m_x e_y+m_y e_x+e_x e_y; input flushing adds tiny*(M_x+M_y).
    Adds include two input flushes. Rounding allowances include every direction
    and output FTZ. Omitting an intermediate rounding through FMA is covered by
    these nonnegative allowances and the final add's full-magnitude allowance.
    """
    rel = accepted(); authority = rel.rounding_authority(); tiny = authority.minnormal(24)
    require(len(components) == 4 and len(scale) == 3, 'Basis input cardinality')
    components = tuple(tuple(map(exact, pair)) for pair in components)
    require(all(len(pair) == 2 and pair[0] <= pair[1] for pair in components), 'Invalid quaternion component interval')
    supplied_norm = tuple(map(exact, norm))
    require(len(supplied_norm) == 2 and 0 < supplied_norm[0] <= supplied_norm[1], 'Nonpositive quaternion denominator authority')
    component_norm = (sum(0 if lo <= 0 <= hi else min(abs(lo), abs(hi))**2 for lo, hi in components),
                      sum(max(abs(lo), abs(hi))**2 for lo, hi in components))
    nlo, nhi = max(supplied_norm[0], component_norm[0]), min(supplied_norm[1], component_norm[1])
    require(0 < nlo <= nhi, 'Inconsistent quaternion norm authority')
    mags = tuple(max(map(abs, pair)) for pair in components)
    dot_rounding = authority.roundoff_sum([v*v for v in mags])
    dot_flush = tiny*(2*sum(mags)+6)
    dot_error = upward()(dot_rounding+dot_flush)
    hlo, hhi = nlo-dot_error, nhi+dot_error
    require(hlo >= tiny, 'Native denominator can be zero or input-flushed; STOP')
    reciprocal_rounding = authority.rnd(2/hlo, 24)
    reciprocal_error = upward()(2*dot_error/(hlo*nlo)+reciprocal_rounding)
    graph = []
    def node(name, magnitude, error):
        magnitude, error = upward()(magnitude), upward()(error)
        graph.append({'node': name, 'reference_magnitude': magnitude, 'absolute_error': error})
        return magnitude, error
    def mul(name, a, b):
        m, e = a; n, f = b
        error = m*f+n*e+e*f+tiny*(m+e+n+f)+authority.rnd((m+e)*(n+f), 24)
        return node(name, m*n, error)
    def add(name, a, b):
        m, e = a; n, f = b
        return node(name, m+n, e+f+2*tiny+authority.rnd(m+e+n+f, 24))
    q = [(m, Q(0)) for m in mags]
    s = node('s=2/h', 2/nlo, reciprocal_error)
    xs, ys, zs = [mul(name, q[i], s) for i, name in enumerate(('xs', 'ys', 'zs'))]
    wx, wy, wz = [mul(name, q[3], v) for name, v in zip(('wx', 'wy', 'wz'), (xs, ys, zs))]
    xx, xy, xz = [mul(name, q[0], v) for name, v in zip(('xx', 'xy', 'xz'), (xs, ys, zs))]
    yy, yz, zz = mul('yy', q[1], ys), mul('yz', q[1], zs), mul('zz', q[2], zs)
    one = (Q(1), Q(0))
    entries = ((add('00', one, add('yy+zz', yy, zz)), add('01', xy, wz), add('02', xz, wy)),
               (add('10', xy, wz), add('11', one, add('xx+zz', xx, zz)), add('12', yz, wx)),
               (add('20', xz, wy), add('21', yz, wx), add('22', one, add('xx+yy', xx, yy))))
    rotation_errors = tuple(tuple(v[1] for v in row) for row in entries)
    rotation_box = [[(-1-e, 1+e) for e in row]+[(Q(0), Q(0))] for row in rotation_errors]
    rotation_box.append([(Q(0), Q(0))]*3+[(Q(1), Q(1))])
    scale = tuple(map(exact, scale))
    diagonal = tuple(tuple(Q(scale[i] if i == j else 0) for j in range(4)) for i in range(3))+((Q(0), Q(0), Q(0), Q(1)),)
    scale_graph = rel.native_product_error(rotation_box, rel.point_box(diagonal), authority)
    errors = tuple(tuple(upward()(rotation_errors[i][j]*abs(scale[j])+scale_graph['absolute'][i][j])
                         for j in range(3)) for i in range(3))
    epsilon = frobenius_upper(errors)
    return {'components': components, 'supplied_norm_squared': supplied_norm, 'norm_squared': (nlo, nhi),
            'scale': scale, 'dot_rounding': dot_rounding, 'dot_input_flush': dot_flush,
            'rounded_denominator': (hlo, hhi), 'reciprocal_error': reciprocal_error,
            'nodes': graph, 'scale_product_graph': scale_graph, 'entrywise_error': errors,
            'frobenius_error': epsilon, 'bounds': local_bounds(scale, epsilon),
            'primitive_counts': {'multiply': 43, 'add': 33, 'divide': 1}}


def local_context(native, seconds, ranges, budget):
    """The accepted pure local replay, retaining each actual Basis input branch."""
    rel = accepted(); lo, hi = seconds
    require(0 <= lo <= hi <= native['length'], 'Unadmitted native phase')
    f = ranges.native.Float32Box
    def forbidden(*args): raise ValueError('Unaccepted live libm replay')
    functions = {name: forbidden for name in ('sin', 'sinf', 'acosf')}
    tracks = {}
    for track in native['tracks']:
        key = (track['path'].split(':')[-1], track['type'])
        require(key not in tracks and track['type'] in (1, 2) and track['enabled'] is True
            and track['compressed'] is False and track['loop_wrap'] is True
            and track['interpolation'] in (0, 1), 'Unsupported native track/search/scale branch')
        tracks[key] = ranges.track_span_box(track, lo, hi, native['length'], functions, budget)
    locals_, metrics, certificates = [], [], []
    for bone in native['bones']:
        position, rotation = f(bone['default_position']), f(bone['default_rotation'])
        if (bone['name'], 1) in tracks:
            rest = f(ranges.native.matrix(bone['rest'])[:3, 3])
            position = rest+(tracks[bone['name'], 1]-rest)
        if (bone['name'], 2) in tracks:
            rotation = ranges.mixer_span_box(bone['rest_rotation'], tracks[bone['name'], 2])
        local = ranges.basis_span_box(position, rotation, bone['default_scale'])
        locals_.append([[(exact(float(local.lo[i, j])), exact(float(local.hi[i, j])))
                         for j in range(4)] for i in range(3)]+[[(Q(0), Q(0))]*3+[(Q(1), Q(1))]])
        scale = tuple(exact(float(v)) for v in f(bone['default_scale']).lo)
        if isinstance(rotation, ranges.QuaternionSpan):
            rotation.validate(); branches = rotation.branches
            certs = [{**b.certificate, 'basis_rounded_norm_squared': ranges.rounded_norm(b, 'basis')[0]} for b in branches]
            budget.norm_records[lo, hi, bone['name']] = certs
            certificates.append({'seconds': seconds, 'bone': bone['name'], 'branches': ranges.json_value(certs)})
        else:
            branches = [None]
        records = []
        for branch in branches:
            q = rotation if branch is None else branch.box
            components = tuple((exact(float(a)), exact(float(b))) for a, b in zip(q.lo, q.hi))
            if branch is None:
                require(all(a == b for a, b in components), 'Missing correlated quaternion branch authority')
                norm = (sum(a*a for a, b in components),)*2
                identity = {'default_rotation': rel.digest(components)}
            else:
                branch.validate(); norm = branch.norm_squared
                identity = {'accepted_branch': branch.binding, 'certificate_sha256': rel.digest(ranges.json_value(branch.certificate))}
            proof = basis_error(components, norm, scale)
            records.append({'branch': identity, 'components': components, 'norm': proof['norm_squared'],
                'denominator': proof['rounded_denominator'], 'scale': scale,
                'entrywise_error': proof['entrywise_error'], 'error': proof['frobenius_error'],
                'bounds': proof['bounds'], 'graph_sha256': rel.digest(proof)})
        metrics.append(records)
    return locals_, metrics, certificates


def product_record(a, b):
    rel = accepted(); graph = rel.native_product_error(a, b, rel.rounding_authority())
    return {'source_nodes': graph['source_nodes'], 'domain_sha256': rel.digest([a, b]),
            'graph_sha256': rel.digest(graph),
            'error': frobenius_upper([row[:3] for row in graph['absolute'][:3]])}


def context_records(packet, scalar):
    rel = accepted(); ranges = rel.range_authority(); native = packet['native']
    require(0 < len(packet['contexts']) <= 47 and 0 < len(native['bones']) <= 53, 'Context/bone cap differs')
    binds = {i: rel.native_bind(native['skin'][i]) for pair in packet['pairs'] for i in pair}
    for pair in packet['pairs']: rel.resolved_pair(native, pair)
    fixed = packet.get('fixed_binds')
    if fixed is None: fixed = {i: bind_conditioning([row[:3] for row in bind[:3]]) for i, bind in binds.items()}
    if 'relative' in packet:
        require(set(packet['relative']['domains']) == set(packet['contexts']), 'Missing incoming relative context')
    budget = ranges.Budget(arithmetic=scalar)
    for context_id, source in sorted(packet['contexts'].items()):
        require(rel.digest(source) == context_id, 'Changed original context/time/source identity')
        locals_, metrics, certificates = local_context(native, source['seconds'], ranges, budget)
        globals_ = rel.global_context(native, locals_, rel.rounding_authority())
        incoming = packet.get('relative', {}).get('domains', {}).get(context_id)
        if incoming is not None:
            require(incoming['locals'] == rel.packed(locals_) and incoming['globals'] == rel.packed(globals_)
                and incoming['local_certificates'] == certificates, 'Accepted local/FK/branch replay differs')
        bones = []
        for i, (bone, branches) in enumerate(zip(native['bones'], metrics)):
            parent = bone['parent']
            require(type(parent) is int and -1 <= parent < i, 'Changed native FK hierarchy')
            local = (min(v['bounds'][0] for v in branches), max(v['bounds'][1] for v in branches))
            product = None if parent < 0 else product_record(globals_[parent], locals_[i])
            bounds = local if parent < 0 else product_bounds(bones[parent]['bounds'], local, product['error'])
            bones.append({'bone': i, 'name': bone['name'], 'parent': parent, 'local': branches,
                'product': product, 'bounds': bounds, 'status': 'POSITIVE_NECESSARY_METRIC' if bounds[0] > 0 else 'UNPROVED'})
        skin = {}
        for index, bind in sorted(binds.items()):
            bone = native['skin'][index]['resolved_bone']
            require(type(bone) is int and 0 <= bone < len(native['bones'])
                and native['skin'][index]['name'] == native['bones'][bone]['name'], 'Changed true bind mapping')
            product = product_record(globals_[bone], rel.point_box(bind))
            bounds = product_bounds(bones[bone]['bounds'], fixed[index]['bounds'], product['error'])
            skin[str(index)] = {'bone': bone, 'bind_sha256': rel.digest(bind), 'fixed_bind_sha256': rel.digest(fixed[index]),
                'bind_bounds': fixed[index]['bounds'],
                'product': product, 'bounds': bounds, 'status': 'POSITIVE_NECESSARY_METRIC' if bounds[0] > 0 else 'UNPROVED'}
        yield context_id, {'seconds': source['seconds'], 'source_sha256': source['source_sha256'],
            'range_sha256': rel.digest([locals_, globals_, certificates]), 'bones': bones, 'skin': skin}
    rel.check_range_budget(native, budget, scalar, ranges)


def compile_contexts(packet, scalar): return dict(context_records(packet, scalar))


def replay_contexts(packet, records, scalar, statistics=None):
    """Cold reconstruction from source, not a call to the certificate compiler."""
    require(set(records) == set(packet['contexts']), 'Missing original/child/birth context')
    for context_id, fresh in context_records(packet, scalar):
        require(accepted().packed(fresh) == accepted().packed(records[context_id]),
                'Native branch/scale/denominator/FK/bind/spectral proof differs: '+context_id)
        if statistics is not None:
            for key, value in accepted().exact_proof_sizes(fresh, {}).items():
                statistics[key] = statistics.get(key, 0)+value if key == 'fraction_count' else max(statistics.get(key, 0), value)
    return True


RELATIVE_RESULT_SHA = '5ef7cbe0440f5e2b0e243b3089aca4b881c230bebefe793bb7402e377f5fb349'
RELATIVE_RECEIPT_SHA = '9b0667d7d3bb25152be9a6f497297366fe1ead471ccd8e62acf6615a85be0b47'
MAX_OUTPUT = 16*1024*1024
MAX_RSS = 2*1024**3
BINDS = [4, 5, 8, 9, 43, 44, 48, 49]


def resources():
    import resource, sys
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    rss *= 1 if sys.platform == 'darwin' else 1024
    require(rss <= MAX_RSS, 'Operational2GiB RSS cap exceeded')
    return rss


def input_inventory(value):
    counts = {'nodes': 0, 'maximum_integer_bits': 0, 'floats': 0}
    def visit(item):
        counts['nodes'] += 1
        if type(item) is int:
            bits = abs(item).bit_length()
            counts['maximum_integer_bits'] = max(counts['maximum_integer_bits'], bits)
        elif type(item) is float:
            require(math.isfinite(item), 'Nonfinite input endpoint'); counts['floats'] += 1
        elif isinstance(item, dict):
            for child in item.values(): visit(child)
        elif isinstance(item, list):
            for child in item: visit(child)
        else: require(item is None or type(item) in (str, bool), 'Unsupported frozen input scalar')
    visit(value)
    return counts


def read_json(path, pin, watched, size=None):
    rel = accepted(); path = Path(path).resolve(); before = rel.signature(path)
    require(size is None or before[2] == size, 'Changed frozen input size')
    with path.open('rb') as stream:
        require(hashlib.file_digest(stream, 'sha256').hexdigest() == pin, 'Changed frozen input hash')
    with path.open() as stream: value = json.load(stream)
    require(rel.signature(path) == before, 'Input changed during cold hash/parse')
    watched.append((path, before)); resources()
    return value


def write_json(path, value, watched):
    rel = accepted(); path = Path(path).resolve()
    require(path not in {p for p, _ in watched}, 'Output would replace frozen input')
    path.parent.mkdir(parents=True, exist_ok=True); total = 0
    with path.open('x') as stream:
        for part in json.JSONEncoder(sort_keys=True, separators=(',', ':'), allow_nan=False).iterencode(rel.packed(value)):
            total += len(part.encode()); require(total <= MAX_OUTPUT, 'Operational16MiB output cap exceeded')
            stream.write(part)
    with path.open('rb') as stream: pin = hashlib.file_digest(stream, 'sha256').hexdigest()
    with path.open() as stream:
        require(json.load(stream) == rel.packed(value), 'Output complete reread comparison differs')
    resources()
    return pin


def coverage(packet, relative):
    rel = accepted(); authority = packet['authority']; previous = packet['previous']
    require(set(relative['domains']) == set(packet['contexts']) and set(relative['audits']) == set(packet['jobs']),
            'Missing accepted context/job')
    require(len(authority['source_certificates']) == 8342 and len(packet['jobs']) == 2910, 'Source certificate/job denominator differs')
    require(len(authority['all806_input_bindings']) == 806 and len(packet['native']['bones']) == 53, 'Binding/skeleton denominator differs')
    require(len(packet['contexts']) == 47 and packet['pairs'] == rel.PAIRS, 'Original47/four-pair domain differs')
    require(sum(b['parent'] >= 0 for b in packet['native']['bones']) == 52, 'Original FK count differs')
    contexts = set(packet['contexts']); sources = {}; jobs = {}
    for source_id, source in sorted(authority['source_certificates'].items()):
        require(source['source_sha256'] == source_id and 1 <= len(source['branches']) <= 2, 'Changed source/branch identity')
        links = []
        for i, branch in enumerate(source['branches']):
            require(branch['branch_index'] == i and branch['context_sha256'] in contexts, 'Missing source branch context')
            links.append(branch['context_sha256'])
        sources[source_id] = links
    require({c for links in sources.values() for c in links} == contexts, 'Unmapped source context')
    pairs = {str(p)+':'+str(c) for p, c in rel.PAIRS}
    for context_id, record in relative['domains'].items():
        require(set(record['relations']) == pairs, 'Missing relative group/child relation')
        for p, c in rel.PAIRS:
            pair = record['relations'][str(p)+':'+str(c)]
            require([pair[k] for k in ('parent_bind', 'child_bind', 'parent_bone', 'child_bone')]
                    == [p, c, p, c], 'Accepted native relative lineage changed')
    for job_id, job in sorted(packet['jobs'].items()):
        source = job['certificate_sha256']; context = job['shared_transform_sha256']; group = sorted({j for j, _ in job['variables']})
        require(source in sources and sources[source][job['branch_index']] == context and set(group) <= set(BINDS), 'Missing source/job/bind join')
        audit = relative['audits'][job_id]
        require(audit['source_sha256'] == source and audit['context_sha256'] == context and audit['bind_group'] == group
            and audit['old_status'] == job['proof']['status'], 'Changed historical job audit')
        jobs[job_id] = {'source': source, 'context': context, 'binds': group, 'old_status': audit['old_status'],
                       'point_audit': audit['audit']['status']}
    targets = {}
    for key, total, closed, unknown in [('area_targets', 7760, 5046, 2714), ('birth_targets', 2797, 1985, 812)]:
        rows = authority['targets'][key]
        require(len(rows) == total and sum(t['outcome'] == 'CLOSED' for t in rows) == closed
            and sum(t['outcome'] == 'UNKNOWN' for t in rows) == unknown, 'Changed original area/birth accounting')
        targets[key] = [rel.digest(row) for row in rows]
    history = authority['history']
    for name, coordinates, shapes in [('baseline_accounting', 69, 18), ('previous_operation_accounting', 19, 3028),
            ('previous_norm_accounting', 18, 3677), ('previous_shape_accounting', None, 2797)]:
        require((coordinates is None or len(history[name]['coordinate_boxes']) == coordinates)
            and len(history[name]['shape_cases']) == shapes, 'Lost historical case denominator')
    require(len(authority['targets']['children']) == 2 and len(authority['birth_roles']) == 4
        and len(authority['row_headers']) == 42 and authority['counts']['unknown_birth_obligations'] == 812, 'Missing child/birth/row denominator')
    claims = previous['accepted']['claims']
    require(claims['policy_E'] is None and claims['original_12_gates_preserved'] is True
        and all(v is False for k, v in claims.items() if k not in ('policy_E', 'original_12_gates_preserved')), 'Original claim boundary changed')
    summary = relative['summary']
    require(summary['contexts'] == 47 and summary['relations'] == 188 and summary['jobs'] == 2910
        and summary['new_area_closures'] == summary['new_birth_closures'] == 0
        and summary['E'] is None and summary['physical_acceptance'] is False, 'Changed accepted necessary-only boundary')
    return {'sources': sources, 'jobs': jobs, 'targets': targets, 'all806_bindings': authority['all806_input_bindings'],
        'children_sha256': rel.digest(authority['targets']['children']), 'history_sha256': rel.digest(history),
        'source_usage_sha256': rel.digest(authority['typed_context_usages']),
        'birth_roles_sha256': rel.digest(authority['birth_roles']), 'terminal_zero_sha256': rel.digest(authority['terminal_zero_area_usages']),
        'source_links_sha256': rel.digest([authority['area_source_links'], authority['birth_source_links']]),
        'target_dispositions_sha256': rel.digest([previous['area_dispositions'], previous['birth_dispositions']]),
        'parent_children_alternative_counts': previous['summary']['area_classifications'],
        'old_point_audit_counts': summary['audit_statuses'], 'original_12_gates_preserved': True,
        'old_area': {'CLOSED': 5046, 'UNKNOWN': 2714}, 'old_birth': {'CLOSED': 1985, 'UNKNOWN': 812}}


def load_packet(control, watched):
    from types import SimpleNamespace
    rel = accepted(); locations = {row['role']: row for row in control['inputs']}
    require(set(rel.PINS) <= set(locations), 'Missing accepted input locator; STOP')
    for role, pin in rel.PINS.items(): require(locations[role]['sha256'] == pin, 'Changed accepted input pin')
    args = SimpleNamespace(**{role: Path(locations[role]['path']) for role in rel.PINS}, bundle_root=control['bundle_root'])
    packet = rel.load_inputs(args); watched.extend(packet['watched']); resources()
    inventory = {'authority': input_inventory(packet['authority']), 'previous': input_inventory(packet['previous'])}
    location = locations['relative_receipt']
    receipt = read_json(location['path'], RELATIVE_RECEIPT_SHA, watched, 6611)
    require(location['sha256'] == RELATIVE_RECEIPT_SHA and receipt['accepted'] is True and receipt['merged'] is True
        and receipt['head'] == 'd0a5135f62681d13c797ae3f954b1541b02558c0'
        and receipt['merge_sha'] == '80ecdc2dd7ff9a8b3fcf36d54c2a24345a3c9e57'
        and receipt['actual_current_HEAD_CI_all12_success'] is True, 'Missing accepted270 authority')
    # Release the large saved scalar arrays before decoding the incoming domain.
    keep = {'source_certificates', 'all806_input_bindings', 'targets', 'history', 'birth_roles', 'row_headers', 'counts',
            'typed_context_usages', 'terminal_zero_area_usages', 'area_source_links', 'birth_source_links', 'input_binding'}
    for key in list(packet['authority']):
        if key not in keep: del packet['authority'][key]
    location = locations['relative_result']
    require(location['sha256'] == RELATIVE_RESULT_SHA, 'Changed accepted relative-domain pin')
    relative = read_json(location['path'], RELATIVE_RESULT_SHA, watched, 142437591)
    inventory['relative'] = input_inventory(relative)
    require(relative['kind'] == 'NECESSARY_RELATIVE_SKIN_DOMAIN_SAVED_POINT_AUDIT_ONLY' and relative['version'] == 1
        and relative['input_pins'] == rel.PINS and relative['source_sha256'] == RELATIVE_SHA, 'Accepted relative-domain source/format changed')
    mapping = coverage(packet, relative)
    packet['platform_math'] = packet['authority']['input_binding']['platform_math']
    del packet['authority']; packet['relative'] = relative
    packet['fixed_binds'] = {i: bind_conditioning([row[:3] for row in rel.native_bind(packet['native']['skin'][i])[:3]]) for i in BINDS}
    return packet, mapping, inventory


def finite_plan(packet):
    rel = accepted(); native = packet['native']
    branch_bound = 47*8*sum(len(t['keys']) for t in native['tracks'] if t['type'] == 2)
    return {'contexts': 47, 'bones': 53, 'local_global_records': 2491, 'FK_products': 2444,
        'skin_products': 376, 'fixed_bind_certificates': 8, 'relations': 188, 'jobs': 2910,
        'source_certificates': 8342, 'unknown_birth': 812, 'bindings': 806,
        'basis_primitive_nodes_per_branch': {'multiply': 43, 'add': 33, 'divide': 1},
        'affine_primitive_nodes_per_product': {'multiply': 36, 'add': 27},
        'quaternion_branch_bound': branch_bound, 'default_branch_bound': 2491,
        'existing_limits': rel.range_authority().LIMITS, 'max_rss_bytes': MAX_RSS, 'max_output_bytes': MAX_OUTPUT,
        'risk': 'Cold source/profile/scalar replay and exact rational proof must fit one original300s; no forecast or positive bound guaranteed.'}


def main():
    import argparse, os, datetime
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('compile', 'verify'))
    parser.add_argument('--control', type=Path, required=True); parser.add_argument('--control-sha256', required=True)
    parser.add_argument('--out', type=Path, required=True); parser.add_argument('--result', type=Path)
    args = parser.parse_args(); watched = []
    print(json.dumps({'pid': os.getpid(), 'parent_pid': os.getppid(), 'command': args.command,
        'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}), flush=True)
    try:
        control = read_json(args.control, args.control_sha256, watched)
        require(control['step_id'] == 'CAV-CONTACT-NATIVE-SKIN-CONDITIONING', 'Wrong control scope')
        import subprocess
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        require(head == control['head'] and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip(),
                'Frozen HEAD/clean checkout changed')
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', '80ecdc2dd7ff9a8b3fcf36d54c2a24345a3c9e57', head], cwd=ROOT).returncode == 0,
                'Accepted270 merge is not an ancestor')
        for row in control['sources']:
            path = Path(row['path']).resolve(); before = accepted().signature(path)
            accepted().source_bytes(path, row['sha256']); watched.append((path, before))
        require(any(Path(r['path']).resolve() == Path(__file__).resolve() for r in control['sources']), 'Missing producer/verifier source binding')
        packet, mapping, inventory = load_packet(control, watched); plan = finite_plan(packet)
        ranges = accepted().range_authority()
        scalar = ranges.ScalarAuthority(packet['scalar_capture'], packet['scalar_receipt'], packet['native'], packet['platform_math'])
        scalar.binding.update(capture_file_sha256=accepted().PINS['arithmetic_capture'], receipt_file_sha256=accepted().PINS['arithmetic_receipt'])
        binding = {'kind': 'NECESSARY_NATIVE_SKIN_CONDITIONING_ONLY', 'version': 1,
            'source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'control_sha256': args.control_sha256, 'input_pins': {r['role']: r['sha256'] for r in control['inputs']},
            'plan': plan, 'mapping': mapping, 'input_inventory': inventory,
            'fixed_bind_certificates': {str(i): value for i, value in packet['fixed_binds'].items()}}
        if args.command == 'compile':
            contexts = compile_contexts(packet, scalar)
        else:
            require(args.result is not None, 'Missing incoming conditioning result')
            path = args.result.resolve(); before = accepted().signature(path)
            require(before[2] <= MAX_OUTPUT, 'Incoming result exceeds16MiB')
            with path.open() as stream: incoming = json.load(stream)
            watched.append((path, before)); require(accepted().signature(path) == before, 'Incoming result changed')
            for key, value in binding.items(): require(incoming[key] == accepted().packed(value), 'Changed source/coverage/control: '+key)
            contexts = incoming['contexts']; replay_sizes = {}
            replay_contexts(packet, contexts, scalar, replay_sizes)
        status_counts = {'POSITIVE_NECESSARY_METRIC': 0, 'UNPROVED': 0}
        for context in contexts.values():
            for record in context['skin'].values(): status_counts[record['status']] += 1
        summary = {'skin_metric_statuses': status_counts, 'new_area_closures': 0, 'new_birth_closures': 0,
            'E': None, 'physical_acceptance': False, 'CERT': False, 'original_12_gates_preserved': True}
        branch_count = sum(len(b['local']) for c in contexts.values() for b in c['bones'])
        summary['actual_counts'] = {'local_global_records': sum(len(c['bones']) for c in contexts.values()),
            'FK_products': sum(b['parent'] >= 0 for c in contexts.values() for b in c['bones']),
            'skin_products': sum(len(c['skin']) for c in contexts.values()), 'Basis_branch_evaluations': branch_count,
            'Basis_source_node_visits': {'multiply': 43*branch_count, 'add': 33*branch_count, 'divide': branch_count},
            'FK_Skin_source_node_visits': {'multiply': 36*(2444+376), 'add': 27*(2444+376)}}
        require([summary['actual_counts'][k] for k in ('local_global_records', 'FK_products', 'skin_products')] == [2491, 2444, 376]
            and branch_count <= plan['quaternion_branch_bound']+plan['default_branch_bound'], 'Actual finite proof denominator/cap differs')
        sizes = accepted().exact_proof_sizes(contexts, {}) if args.command == 'compile' else replay_sizes
        if args.command == 'compile':
            result = {**binding, 'contexts': contexts, 'summary': summary, 'proof_sizes': sizes, 'scalar_work': dict(scalar.work)}
        else:
            require(incoming['summary'] == summary and incoming['scalar_work'] == dict(scalar.work)
                    and incoming['proof_sizes'] == sizes, 'Changed summary/scalar work/rational sizes')
            with args.result.open('rb') as stream: result_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
            result = {'status': 'WHOLE_NATIVE_SKIN_METRIC_REPLAYED_NO_GEOMETRIC_CLOSURE', 'summary': summary,
                'control_sha256': args.control_sha256, 'result_sha256': result_sha}
        accepted().unchanged(watched); pin = write_json(args.out, result, watched); accepted().unchanged(watched)
        print(json.dumps({'sha256': pin, 'summary': summary, 'max_rss_bytes': resources()}), flush=True)
        return 0
    except (ValueError, KeyError, IndexError, OSError, MemoryError, TypeError, OverflowError) as error:
        print(json.dumps({'status': 'STOP_NO_AUTHORITY_OR_RESOURCE', 'reason': str(error)}), flush=True)
        return 2


if __name__ == '__main__': raise SystemExit(main())
