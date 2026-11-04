"""Small exact controls only; never load the real scientific inputs."""
import copy
from fractions import Fraction as Q
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).with_name('bound_cavalry_skin_conditioning.py')
if PATH.exists():
    spec = importlib.util.spec_from_file_location('conditioning', PATH)
    proof = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(proof)
else:
    proof = None


def diagonal(values):
    return tuple(tuple(Q(values[i] if i == j else 0) for j in range(3)) for i in range(3))


def binary32(value, mode, output_ftz):
    value = Q(value)
    if not value: return value
    sign = 1 if value > 0 else -1; v = abs(value)
    exponent = v.numerator.bit_length()-v.denominator.bit_length()
    exponent -= v < Q(2)**exponent
    unit = Q(2)**max(exponent-23, -149)
    scaled = v/unit; integer = scaled.numerator//scaled.denominator; remainder = scaled-integer
    increase = ((mode == 'up' and sign > 0) or (mode == 'down' and sign < 0)) and bool(remainder)
    if mode == 'nearest': increase = remainder > Q(1, 2) or remainder == Q(1, 2) and integer % 2 == 1
    rounded = sign*(integer+increase)*unit
    return Q(0) if output_ftz and abs(rounded) < Q(2)**-126 else rounded


def native_basis(q, scale, mode, input_ftz, output_ftz, contraction):
    tiny = Q(2)**-126
    flush = lambda x: Q(0) if input_ftz and abs(x) < tiny else x
    rnd = lambda x: binary32(x, mode, output_ftz)
    mul = lambda x, y: rnd(flush(x)*flush(y))
    add = lambda x, y: rnd(flush(x)+flush(y))
    fma = lambda x, y, z: rnd(flush(x)*flush(y)+flush(z))
    def dot(a, b):
        if contraction == 0: v = fma(a[0], b[0], mul(a[1], b[1]))
        elif contraction == 1: v = fma(a[1], b[1], mul(a[0], b[0]))
        else: v = add(mul(a[0], b[0]), mul(a[1], b[1]))
        for i in range(2, len(a)):
            v = fma(a[i], b[i], v) if contraction is not None else add(v, mul(a[i], b[i]))
        return v
    s = rnd(Q(2)/flush(dot(q, q)))
    x, y, z, w = q; xs, ys, zs = [mul(v, s) for v in q[:3]]
    def pair(a, b, c, d, sign=1):
        if contraction == 0: return fma(a, b, sign*mul(c, d))
        if contraction == 1: return fma(sign*c, d, mul(a, b))
        return add(mul(a, b), sign*mul(c, d))
    rows = ((add(1, -pair(y, ys, z, zs)), pair(x, ys, w, zs, -1), pair(x, zs, w, ys)),
            (pair(x, ys, w, zs), add(1, -pair(x, xs, z, zs)), pair(y, zs, w, xs, -1)),
            (pair(x, zs, w, ys, -1), pair(y, zs, w, xs), add(1, -pair(x, xs, y, ys))))
    return tuple(tuple(dot(row, [scale[j] if k == j else Q(0) for k in range(3)])
        for j in range(3)) for row in rows)


def small_packet():
    rel = proof.accepted()
    def flat(scale, origin):
        return [scale, 0, 0, origin, 0, 1, 0, 0, 0, 0, 1, 0]
    native = {'bones': [{'name': name, 'parent': i-1, 'default_position': [origin, 0, 0],
        'default_rotation': [0, 0, 0, 2], 'rest_rotation': [0, 0, 0, 1],
        'default_scale': [scale, 1, 1], 'rest': flat(scale, origin)}
        for i, (name, scale, origin) in enumerate((('parent', 1, 10), ('child', 2, 3)))],
        'skin': [{'name': name, 'resolved_bone': i, 'pose': flat(1, 0)}
                 for i, name in enumerate(('parent', 'child'))], 'tracks': [], 'length': .5}
    context = {'seconds': [0., .25], 'source_sha256': 'a'*64}
    return {'native': native, 'contexts': {rel.digest(context): context}, 'pairs': [[0, 1]], 'jobs': {}}


def mapping_fixture():
    contexts = {f'{i:064x}': {} for i in range(47)}
    sources = {f'{i+100:064x}': {'source_sha256': f'{i+100:064x}',
        'branches': [{'branch_index': 0, 'context_sha256': f'{i%47:064x}'}]} for i in range(8342)}
    jobs = {str(i): {'certificate_sha256': f'{i+100:064x}', 'shared_transform_sha256': f'{i%47:064x}',
        'branch_index': 0, 'variables': [[4, 0], [5, 0]], 'proof': {'status': 'REFERENCE_BOX_DEGENERATE'}} for i in range(2910)}
    targets = {'area_targets': [{'outcome': 'CLOSED' if i < 5046 else 'UNKNOWN', 'id': i} for i in range(7760)],
        'birth_targets': [{'outcome': 'CLOSED' if i < 1985 else 'UNKNOWN', 'id': i} for i in range(2797)], 'children': [{}, {}]}
    history = {k: {'coordinate_boxes': [0]*c, 'shape_cases': [0]*s} for k, c, s in
        (('baseline_accounting', 69, 18), ('previous_operation_accounting', 19, 3028),
         ('previous_norm_accounting', 18, 3677), ('previous_shape_accounting', 0, 2797))}
    authority = {'source_certificates': sources, 'all806_input_bindings': {str(i): str(i) for i in range(806)},
        'targets': targets, 'history': history, 'birth_roles': dict.fromkeys('abcd', {}), 'row_headers': [{}]*42,
        'counts': {'unknown_birth_obligations': 812}, 'typed_context_usages': [], 'terminal_zero_area_usages': [],
        'area_source_links': [], 'birth_source_links': []}
    packet = {'authority': authority, 'previous': {'accepted': {'claims': {'policy_E': None, 'original_12_gates_preserved': True,
        'physical': False}}, 'summary': {'area_classifications': {'parent_with_two_children': 1}}, 'area_dispositions': [], 'birth_dispositions': []},
        'native': {'bones': [{'parent': i-1} for i in range(53)]}, 'contexts': contexts, 'pairs': proof.accepted().PAIRS, 'jobs': jobs}
    relative = {'domains': {c: {'relations': {str(p)+':'+str(k): {'parent_bind': p, 'child_bind': k,
        'parent_bone': p, 'child_bone': k} for p, k in packet['pairs']}} for c in contexts},
        'audits': {i: {'source_sha256': v['certificate_sha256'], 'context_sha256': v['shared_transform_sha256'],
        'bind_group': [4, 5], 'old_status': v['proof']['status'], 'audit': {'status': 'THIS_WITNESS_EXCLUDED_BY_NATIVE_RELATION'}} for i, v in jobs.items()},
        'summary': {'contexts': 47, 'relations': 188, 'jobs': 2910, 'new_area_closures': 0, 'new_birth_closures': 0,
        'E': None, 'physical_acceptance': False, 'audit_statuses': {'THIS_WITNESS_EXCLUDED_BY_NATIVE_RELATION': 2910}}}
    return packet, relative


class ConditioningTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(proof, 'Conditioning sidecar has not been implemented')

    def test_nonunit_reference_is_orthogonal_without_assuming_norm_one(self):
        self.assertEqual(proof.reference_rotation((0, 0, 0, 2)), diagonal((1, 1, 1)))
        for q in ((1, 2, 3, 4), (Q(1, 8), -2, 0, 3)):
            r = proof.reference_rotation(q)
            self.assertEqual(tuple(tuple(sum(r[k][i]*r[k][j] for k in range(3))
                for j in range(3)) for i in range(3)), diagonal((1, 1, 1)))
        with self.assertRaises(ValueError): proof.reference_rotation((0, 0, 0, 0))

    def test_hand_computed_local_fk_and_skin_inequalities(self):
        self.assertEqual(proof.local_bounds((2, 3, 4), 0), (Q(2), Q(4)))
        self.assertEqual(proof.product_bounds((1, 3), (2, 4), 0), (Q(2), Q(12)))
        local = proof.local_bounds((2, 3, 4), Q(1, 4))
        child = proof.product_bounds((1, 3), local, Q(1, 8))
        self.assertEqual(child, (Q(13, 8), Q(103, 8)))
        self.assertEqual(proof.product_bounds(child, (Q(1, 2), 2), Q(1, 16)),
                         (Q(3, 4), Q(413, 16)))

    def test_true_bind_gram_and_determinant_fallback(self):
        shear = ((1, 1, 0), (0, 1, 0), (0, 0, 1))
        cert = proof.bind_conditioning(shear)
        self.assertEqual(cert['gershgorin_squared'][0], 0)
        self.assertEqual(cert['determinant'], 1)
        self.assertEqual(cert['frobenius_squared'], 4)
        self.assertEqual(cert['bounds'][0], Q(1, 4))
        self.assertEqual(proof.bind_conditioning(diagonal((Q(1, 2), 1, 2)))['bounds'], (Q(1, 2), Q(2)))

    def test_zero_scale_singular_bind_and_overwhelming_error_are_unproved(self):
        self.assertEqual(proof.local_bounds((0, 1, 1), 0)[0], 0)
        self.assertEqual(proof.local_bounds((1, 1, 1), 2)[0], 0)
        self.assertEqual(proof.bind_conditioning(diagonal((0, 1, 1)))['bounds'][0], 0)
        self.assertEqual(proof.product_bounds((1, 1), (1, 1), 2)[0], 0)
        for bad in (-1, float('nan'), True):
            with self.assertRaises(ValueError): proof.local_bounds((1, 1, 1), bad)

    def test_native_basis_graph_has_exact_source_primitive_counts(self):
        record = proof.basis_error([(Q(v), Q(v)) for v in (0, 0, 0, 2)], (4, 4), (2, 3, 4))
        self.assertEqual(record['primitive_counts'], {'multiply': 43, 'add': 33, 'divide': 1})
        self.assertEqual(record['norm_squared'], (4, 4))
        self.assertGreater(record['bounds'][0], 0)
        self.assertLessEqual(record['bounds'][0], 2)
        self.assertGreaterEqual(record['bounds'][1], 4)
        self.assertEqual(len(record['entrywise_error']), 3)

    def test_nonpositive_denominator_and_invalid_norm_fail_closed(self):
        for norm in ((0, 1), (-1, 1), (2, 1), (5, 5)):
            with self.assertRaises(ValueError):
                proof.basis_error([(Q(v), Q(v)) for v in (0, 0, 0, 2)], norm, (1, 1, 1))
        with self.assertRaises(ValueError):
            proof.basis_error([(Q(2)**-127, Q(2)**-127)]*4,
                              (Q(2)**-252, Q(2)**-252), (1, 1, 1))

    def test_independent_ieee_constructor_oracle_all_modes_fma_and_ftz(self):
        fixtures = ((Q(0), Q(0), Q(0), Q(2)), (Q(1, 2), Q(-3, 4), Q(1, 8), Q(2)),
                    (Q(2)**-127, Q(0), Q(0), Q(2)**-20))
        scale = (Q(2), Q(-3), Q(4))
        for q in fixtures:
            n = sum(v*v for v in q)
            cert = proof.basis_error([(v, v) for v in q], (n, n), scale)
            reference = proof.reference_rotation(q)
            for mode in ('nearest', 'zero', 'up', 'down'):
                for input_ftz in (False, True):
                    for output_ftz in (False, True):
                        for contraction in (None, 0, 1):
                            native = native_basis(q, scale, mode, input_ftz, output_ftz, contraction)
                            for i in range(3):
                                for j in range(3):
                                    self.assertLessEqual(abs(native[i][j]-reference[i][j]*scale[j]), cert['entrywise_error'][i][j])

    def test_small_full_skeleton_metric_lineage_and_independent_replay(self):
        packet = small_packet()
        result = proof.compile_contexts(packet, object())
        self.assertEqual(len(result), 1)
        record = next(iter(result.values()))
        self.assertEqual(len(record['bones']), 2)
        self.assertEqual(len(record['skin']), 2)
        self.assertTrue(all(v['bounds'][0] > 0 for v in record['skin'].values()))
        from unittest.mock import patch
        with patch.object(proof, 'compile_contexts', side_effect=AssertionError('Compiler called in replay')):
            self.assertTrue(proof.replay_contexts(packet, result, object()))

    def test_replay_rejects_missing_bone_bind_branch_and_forged_positive(self):
        packet = small_packet(); result = proof.compile_contexts(packet, object())
        for field in ('bones', 'skin'):
            changed = copy.deepcopy(result); record = next(iter(changed.values()))
            if field == 'bones': record[field].pop()
            else: record[field].pop('1')
            with self.assertRaises(ValueError): proof.replay_contexts(packet, changed, object())
        for field in ('branch', 'denominator', 'scale', 'error', 'bounds', 'parent'):
            changed = copy.deepcopy(result); bone = next(iter(changed.values()))['bones'][1]
            if field == 'parent': bone['parent'] = -1
            elif field == 'bounds': bone['bounds'] = (Q(100), Q(100))
            elif field == 'error': bone['product']['error'] = Q(0)
            else: bone['local'][0][field] = 'forged'
            with self.assertRaises(ValueError): proof.replay_contexts(packet, changed, object())

    def test_changed_hierarchy_context_scale_bind_and_source_reject(self):
        packet = small_packet(); result = proof.compile_contexts(packet, object())
        for field in ('hierarchy', 'context', 'scale', 'bind'):
            changed = copy.deepcopy(packet)
            if field == 'hierarchy': changed['native']['bones'][1]['parent'] = -1
            elif field == 'context': next(iter(changed['contexts'].values()))['seconds'][1] = .3
            elif field == 'scale': changed['native']['bones'][1]['default_scale'][0] = 3
            else: changed['native']['skin'][1]['pose'][0] = 2
            with self.assertRaises(ValueError): proof.replay_contexts(changed, result, object())

    def test_key_branches_and_zero_metric_remain_explicit(self):
        packet = small_packet()
        packet['native']['tracks'] = [{'path': 'Skeleton:'+b['name'], 'type': 2,
            'keys': [{'time': 0., 'value': [0, 0, 0, 1]}], 'interpolation': 1,
            'loop_wrap': True, 'enabled': True, 'compressed': False} for b in packet['native']['bones']]
        result = proof.compile_contexts(packet, object())
        self.assertTrue(all('accepted_branch' in b['local'][0]['branch'] for b in next(iter(result.values()))['bones']))
        self.assertTrue(proof.replay_contexts(packet, result, object()))
        packet = small_packet(); packet['native']['bones'][1]['default_scale'][0] = 0
        result = proof.compile_contexts(packet, object())
        self.assertEqual(next(iter(result.values()))['skin']['1']['status'], 'UNPROVED')

    def test_source_custody_integer_size_and_output_guards(self):
        import hashlib, tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'input.json'; path.write_text('{"a":1}')
            pin = hashlib.sha256(path.read_bytes()).hexdigest(); watched = []
            self.assertEqual(proof.read_json(path, pin, watched, 7), {'a': 1})
            with self.assertRaises(ValueError): proof.read_json(path, '0'*64, [], 7)
            with self.assertRaises(ValueError): proof.read_json(path, pin, [], 6)
            with self.assertRaises(ValueError): proof.write_json(path, {}, watched)
            out = Path(directory)/'out.json'
            proof.write_json(out, {'bounds': [Q(1, 2), Q(2)]}, watched)
            with self.assertRaises(FileExistsError): proof.write_json(out, {}, watched)
        for value in (float('nan'), float('inf'), 2**2253):
            with self.assertRaises(ValueError): proof.input_inventory({'bad': value})
        self.assertEqual(proof.input_inventory({'a': [1, .5]})['maximum_integer_bits'], 1)

    def test_serialized_metric_replay_rejects_forged_positive_and_extra_context(self):
        import json
        packet = small_packet(); result = proof.compile_contexts(packet, object())
        serialized = json.loads(json.dumps(proof.accepted().packed(result)))
        self.assertTrue(proof.replay_contexts(packet, serialized, object()))
        altered = copy.deepcopy(serialized); next(iter(altered.values()))['skin']['1']['bounds'] = [[100, 1], [100, 1]]
        with self.assertRaises(ValueError): proof.replay_contexts(packet, altered, object())
        altered = copy.deepcopy(serialized); altered['0'*64] = next(iter(altered.values()))
        with self.assertRaises(ValueError): proof.replay_contexts(packet, altered, object())

    def test_complete_synthetic_mapping_preserves_all_denominators(self):
        packet, relative = mapping_fixture(); result = proof.coverage(packet, relative)
        self.assertEqual(len(result['sources']), 8342)
        self.assertEqual(len(result['jobs']), 2910)
        self.assertEqual(len(result['targets']['area_targets']), 7760)
        self.assertEqual(len(result['targets']['birth_targets']), 2797)
        self.assertEqual(result['old_area'], {'CLOSED': 5046, 'UNKNOWN': 2714})
        self.assertTrue(result['original_12_gates_preserved'])
        for field in ('context', 'source', 'job', 'relation', 'child', 'birth', 'history', 'binding'):
            changed = copy.deepcopy(packet); other = copy.deepcopy(relative)
            if field == 'context': other['domains'].pop(next(iter(other['domains'])))
            elif field == 'source': changed['authority']['source_certificates'].pop(next(iter(changed['authority']['source_certificates'])))
            elif field == 'job': other['audits'].pop('0')
            elif field == 'relation': next(iter(other['domains'].values()))['relations'].pop('4:5')
            elif field == 'child': changed['authority']['targets']['children'].pop()
            elif field == 'birth': changed['authority']['targets']['birth_targets'].pop()
            elif field == 'history': changed['authority']['history']['previous_norm_accounting']['shape_cases'].pop()
            else: changed['authority']['all806_input_bindings'].pop('0')
            with self.assertRaises(ValueError): proof.coverage(changed, other)

    def test_fresh_rational_size_replay_and_resource_caps(self):
        packet = small_packet(); result = proof.compile_contexts(packet, object()); sizes = {}
        proof.replay_contexts(packet, result, object(), sizes)
        self.assertEqual(sizes, proof.accepted().exact_proof_sizes(result, {}))
        from unittest.mock import patch
        from types import SimpleNamespace
        with patch('resource.getrusage', return_value=SimpleNamespace(ru_maxrss=2**40)):
            with self.assertRaises(ValueError): proof.resources()

    def test_tiny_component_times_large_scale_flush_is_covered(self):
        q = (Q(2)**-127, Q(0), Q(0), Q(1)); scale = (Q(2)**90,)*3
        n = sum(v*v for v in q); ref = proof.reference_rotation(q)
        record = proof.basis_error([(v, v) for v in q], (n, n), scale)
        actual = native_basis(q, scale, 'nearest', True, False, None)
        self.assertGreater(abs(actual[1][2]-ref[1][2]*scale[2]), Q(2)**-126)
        self.assertLessEqual(abs(actual[1][2]-ref[1][2]*scale[2]), record['entrywise_error'][1][2])


if __name__ == '__main__': unittest.main()
