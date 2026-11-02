#!/usr/bin/env python3
"""Synthetic checks; --full also runs the frozen full native reproduction twice."""
import base64
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import test_pivot_feasibility as frozen
try:
    import pivot_metrics as metric
except ModuleNotFoundError:
    metric = None

I = [[float(r == c) for c in range(4)] for r in range(4)]


class MetricsTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(metric, 'metric adapter must exist')

    def test_packed_weights_and_two_vertex_edge(self):
        geo = {'surfaces': [{'vertices': [[1., 2., 3.], [3., 2., 3.]] * 10440,
                'bones': [0, 1, 0, 0] * 20880, 'weights': [.2, .3, 0., 0.] * 20880,
                'indices': [0, 1, 2]}],
               'binds': [{'name': str(i), 'pose': I} for i in range(69)]}
        skin = frozen.Skin(geo)
        g = {str(i): copy.deepcopy(I) for i in range(69)}
        g['1'][0][3] = 2
        before = copy.deepcopy(geo)
        p = metric.deform(skin, g)
        for actual, wanted in zip(p[:2], [(1.1, 1., 1.5), (2.1, 1., 1.5)]):
            for x, y in zip(actual, wanted):
                self.assertAlmostEqual(x, y)
        self.assertAlmostEqual(math.dist(*p[:2]), 1.)
        self.assertEqual(geo, before)
        for x, expected in [(0., .5), (1., .8), (2., 1.1)]:
            g['1'][0][3] = x
            self.assertAlmostEqual(metric.deform(skin, g)[0][0], expected)

    def test_strict_and_boundaries(self):
        for length, entry, wanted in [(.03, .001, False), (.04, .01, False),
                (math.nextafter(.03, math.inf), .001, True),
                (math.nextafter(.04, math.inf), .01, True), (.031, .01, False)]:
            self.assertEqual(frozen.exceeds(length, entry), wanted)

    def test_contact_and_common_transform_units(self):
        a, b, origin, normal = [0., 0., 0.], [.003, -.002, 0.], [0., 0., 0.], [0., 1., 0.]
        for scale, unit_m in [(1., 1.), (2., 1.), (2., .01)]:
            # Rotate +90 about Z, scale, translate both physical plane and points.
            t = [[0., -scale, 0., 5.], [scale, 0., 0., -3.], [0., 0., scale, 7.], [0., 0., 0., 1.]]
            o, n = metric.plane_frame(origin, normal, t)
            got = metric.contact(metric.point(t, a), metric.point(t, b), o, n, scale, unit_m)
            self.assertAlmostEqual(got['slip_world_m'], .003 * scale * unit_m)
            self.assertAlmostEqual(got['penetration_world_m'], .002 * scale * unit_m)
            self.assertAlmostEqual(got['slip_model_um'], 3000.)
            self.assertAlmostEqual(got['signed_model_um'], -2000.)
            self.assertEqual(got['hover_world_m'], 0.)
            self.assertGreater(got['roundoff_model_um'], 0.)
        changed = metric.contact(a, [.004, .001, 0.], origin, normal, 1., 1.)
        self.assertAlmostEqual(changed['slip_model_um'], 4000.)
        self.assertAlmostEqual(changed['hover_world_m'], .001)
        self.assertEqual(changed['penetration_world_m'], 0.)

    def test_inverse_transpose(self):
        t = copy.deepcopy(I)
        t[0][0], t[1][1] = 2., 3.
        _, n = metric.plane_frame([0., 0., 0.], [1., 1., 0.], t)
        self.assertAlmostEqual(n[0] / n[1], 1.5)
        p = metric.point(t, [1., -1., 0.])
        self.assertAlmostEqual(sum(p[k] * n[k] for k in range(3)), 0.)

    def test_validation_and_missing_authority(self):
        self.assertEqual(metric.validate_contact_input(None, []), ['physical ground/placement', 'material stance intervals', 'external contact budget'])
        cases = [{'op': {'turn_udeg': 1}, 'phases': [0., .5, 1.]}]
        evidence = {'provenance': {'source': 'synthetic-test-only', 'sha256': 'a'*64},
            'placement': I, 'original_scale': 1., 'world_unit_m': 1., 'numeric_error_model_m': 0.,
            'cases': [{'turn_udeg': 1, 'ground': {'origin': [0., 0., 0.], 'normal': [0., 1., 0.]},
                       'patches': [{'id': 'sole', 'kind': 'stance', 'start': 0., 'end': 1., 'vertices': [0, 1], 'anchors': [[0., 0., 0.], [1., 0., 0.]]}]}]}
        self.assertEqual(metric.validate_contact_input(evidence, cases), ['external contact budget'])
        gap = copy.deepcopy(evidence)
        gap['cases'][0]['patches'][0]['start'] = .5
        self.assertIn('case 1: missing material intervals 0.0..0.5', metric.validate_contact_input(gap, cases))
        for mutate in [lambda d: d.update(provenance={}),
                       lambda d: d.update(original_scale=2.),
                       lambda d: d['cases'][0]['ground'].update(normal=[0., 0., 0.]),
                       lambda d: d['cases'][0]['patches'][0].update(vertices=[20880]),
                       lambda d: d['cases'][0]['patches'].append(copy.deepcopy(d['cases'][0]['patches'][0])),
                       lambda d: d.update(budget={'contact_um': 5000}),
                       lambda d: d.update(numeric_error_model_m=-1.)]:
            bad = copy.deepcopy(evidence)
            mutate(bad)
            with self.assertRaises(ValueError):
                metric.validate_contact_input(bad, cases)
        evidence['budget'] = {'contact_um': 5000, 'authority': 'synthetic-test-only', 'source_sha256': 'b'*64}
        self.assertEqual(metric.validate_contact_input(evidence, cases), [])
        self.assertEqual(metric.budget_status(5000., .1, evidence['budget']), 'FAIL')
        self.assertEqual(metric.budget_status(4999., .1, evidence['budget']), 'WITHIN_FINITE_SAMPLES')
        self.assertEqual(metric.budget_status(1., 0., None), 'PENDING')

    def test_fixed_material_contact_and_absolute_penetration(self):
        evidence = {'placement': I, 'original_scale': 1., 'world_unit_m': 1.,
                    'numeric_error_model_m': 0.}
        row = {'ground': {'origin': [0., 0., 0.], 'normal': [0., 1., 0.]},
               'patches': [{'id': 'a', 'kind': 'stance', 'start': 0., 'end': .5,
                            'vertices': [0], 'anchors': [[0., 0., 0.]]},
                           {'id': 'b', 'kind': 'toe', 'start': .5, 'end': 1.,
                            'vertices': [0], 'anchors': [[0., 0., 0.]]}]}
        points = {'source': [[0., 0., 0.], [0., -.01, 0.]],
                  'reference': [[.001, -.001, 0.], [0., -.02, 0.]],
                  'mapped': [[.003, -.002, 0.], [0., -.03, 0.]]}
        before = copy.deepcopy((points, evidence, row))
        for phase, patch in [(0., 'a'), (.5, 'b'), (1., 'b')]:
            got = metric.physical_metrics(points, evidence, row, phase)
            m = got['mapped']
            self.assertEqual(m['patches'][0]['id'], patch)
            self.assertEqual([p['id'] for p in m['exit_patches']], ['a'] if phase == .5 else ['b'] if phase == 1 else [])
            self.assertAlmostEqual(m['whole_mesh_penetration_world_m'], .03)
            self.assertAlmostEqual(m['patches'][0]['max_error_model_um'], 3000.)
            self.assertGreater(m['patches'][0]['placement_roundoff_model_um'], 0.)
            self.assertEqual(m['patches'][0]['budget'], 'PENDING')
            self.assertEqual(got['introduced_vs_source_model_um']['mapped'], [[-2000., 3000.]])
        self.assertEqual((points, evidence, row), before)

    def test_malformed_matrices(self):
        for t in [[], [[float('nan')]*4]*4, [[0.]*4]*4]:
            with self.assertRaises(ValueError):
                metric.plane_frame([0., 0., 0.], [0., 1., 0.], t)
        for normal in [[0., 0., 0.], [1.7e308]*3]:
            with self.assertRaises(ValueError):
                metric.contact([0., 0., 0.], [0., 0., 0.], [0., 0., 0.], normal, 1., 1.)

    def test_fixture_corruption(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.json'
            path.write_bytes(frozen.FIXTURE.read_bytes() + b' ')
            with self.assertRaisesRegex(ValueError, 'fixture bytes'):
                metric.load_frozen(path)
            path.write_text('{')
            run = subprocess.run([sys.executable, str(Path(metric.__file__)), '--fixture', str(path)], capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('NOT PASSED', run.stderr)


def raw_control(m=None, scale=1., units=1.):
    """Explicit synthetic evidence, never relabelled as native captured bits."""
    m = copy.deepcopy(I if m is None else m)
    payload = b'exact synthetic fixed plane and independently prescribed anchors'
    sha = hashlib.sha256(payload).hexdigest()
    ref = {'source': 'synthetic', 'sha256': sha}
    bound = lambda value: {'value': value, 'unit': 'm', 'derivation': 'exact synthetic',
                           'sha256': sha, 'reason': None}
    cases = [{'op': {'turn_udeg': 1, 'duration_q': 1000000,
                      'march_entry_phase': 0., 'march_exit_phase': .5}, 'phases': [0., .5, 1.]}]
    header = {'surface_mode': 'fixed_plane',
        'provenance': dict(ref, capture_tool='synthetic', capture_version='1', engine_build='synthetic',
                           terrain_build='synthetic', capture_frame='0', capture_time='0'),
        'inputs': {'fixture_sha256': metric.FIXTURE_SHA256, 'source_sha256': frozen.HASHES,
                   'native': dict(ref), 'installed': dict(ref), 'placement': dict(ref), 'terrain': dict(ref)},
        'placement': {'matrix': m, 'original_scale': scale, 'world_unit_m': units,
                      'precision': 'binary64', 'scale_precision': 'binary64', 'matrix_bits': [[struct.pack('>d', x).hex() for x in r] for r in m],
                      'scale_bits': struct.pack('>d', scale).hex(),
                      'construction_inputs': dict(ref), 'unavailable_reason': None},
        'frame': {'units': 'world_coordinate_units', 'coordinate_frame': 'synthetic-world',
                  'up': [0., 1., 0.], 'height_query_chart': 'world_xz_y_up',
                  'terrain_transform': I, 'provenance': dict(ref)},
        'cases': [{'turn_udeg': 1, 'duration_q': 1000000, 'entry_phase_id': 0.0.hex(),
                   'exit_phase_id': .5.hex(), 'phase_ids': [u.hex() for u in [0., .5, 1.]],
                   'surface_id': 'plane', 'provenance': dict(ref),
                   'patches': [{'id': 'sole', 'kind': 'stance', 'start': 0., 'end': 1.,
                                'vertices': [0], 'anchors': [[0., 0., 0.]], 'provenance': dict(ref)}]}],
        'surfaces': [{'id': 'plane', 'kind': 'fixed_plane', 'origin': [0., 0., 0.], 'normal': [0., 1., 0.],
                      'domain': {'xz_min': [-10., -10.], 'xz_max': [10., 10.]}, 'provenance': dict(ref)}],
        'uncertainty': {name: bound(0.) for name in ['position', 'height', 'normal', 'query_coordinate', 'anchor']},
        'budget': None, 'evidence': {'synthetic': {'sha256': sha, 'data_base64': base64.b64encode(payload).decode()}}}
    header['uncertainty']['normal']['unit'] = 'dimensionless'
    empty = {'chunk_count': 0, 'row_count': 0, 'decoded_bytes': 0,
             'stream_sha256': hashlib.sha256(b'').hexdigest()}
    return {'schema': 'infantry-pivot-raw-observation/v1', 'kind': 'observation',
            'header': header, 'chunks': [], 'footer': empty}, cases


class RawMetricsTest(unittest.TestCase):
    def test_raw_planar_arithmetic_units_and_immutability(self):
        self.assertTrue(hasattr(metric, 'validate_raw_observation'), 'raw dispatch must exist')
        for scale, units in [(1., 1.), (2., 1.), (200., .01)]:
            m = copy.deepcopy(I)
            for k in range(3):
                m[k][k] = scale
            raw, cases = raw_control(m, scale, units)
            before = copy.deepcopy(raw)
            state = metric.validate_raw_observation(raw, cases)
            points = {label: [[.003, -.002, 0.], [0., -.01, 0.]] for label in ['source', 'reference', 'mapped']}
            result = metric.raw_physical_metrics(points, state, 0, .5)['mapped']
            value = result['patches'][0]['measurements'][0]
            self.assertAlmostEqual(value['signed_world_m'], -.002*scale*units)
            self.assertAlmostEqual(value['vertical_world_m'], -.002*scale*units)
            self.assertAlmostEqual(value['slip_world_m'], .003*scale*units)
            self.assertAlmostEqual(value['error_model_um'], 3000.)
            self.assertAlmostEqual(result['whole_mesh_penetration_world_m'], .01*scale*units)
            self.assertEqual(result['patches'][0]['budget_status'], 'PENDING')
            self.assertEqual(state['placement_uniformity']['status'], 'PREDICATE_SATISFIED')
            self.assertEqual(raw, before)

    def test_shear_reports_world_but_never_certifies_nominal_scale(self):
        m = copy.deepcopy(I)
        m[0][1] = .01
        raw, cases = raw_control(m)
        raw['header']['budget'] = {'contact_um': 10**12, 'authority': 'synthetic',
                                   'source_sha256': next(iter(raw['header']['evidence'].values()))['sha256']}
        state = metric.validate_raw_observation(raw, cases)
        self.assertEqual(state['placement_uniformity']['status'], 'FAIL')
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, .5)['mapped']['patches'][0]
        self.assertEqual(result['budget_status'], 'INELIGIBLE_PLACEMENT')
        value = result['measurements'][0]
        self.assertAlmostEqual(value['slip_world_m'], .00298)
        self.assertIsNone(value['error_model_um'])
        self.assertIsNone(value['upper_bound_model_um'])
        self.assertAlmostEqual(value['nominal_scale_model_um'], 2980.)

    def test_unknown_uncertainty_and_absent_budget_are_not_zero(self):
        raw, cases = raw_control()
        raw['header']['uncertainty']['height'].update(value=None, reason='unknown physical bound')
        state = metric.validate_raw_observation(raw, cases)
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, .5)['mapped']['patches'][0]
        self.assertEqual(state['uncertainty_status'], 'UNKNOWN')
        self.assertIsNone(result['measurements'][0]['upper_bound_model_um'])
        self.assertEqual(result['budget_status'], 'PENDING')
        self.assertIn('uncertainty: height', state['blockers'])
        self.assertIn('external contact budget', state['blockers'])

    def test_raw_integrity_negatives(self):
        mutations = [lambda x: x.update(schema='unknown'), lambda x: x.update(extra=1),
            lambda x: x['header'].update(surface_mode='native_queries'),
            lambda x: x['header'].update(provenance={}),
            lambda x: x['header']['placement']['matrix'][0].__setitem__(0, -1.),
            lambda x: x['header']['placement']['matrix'][0].__setitem__(0, 0.),
            lambda x: x['header']['placement']['matrix'][0].__setitem__(0, float('nan')),
            lambda x: x['header']['placement']['matrix_bits'][0].__setitem__(0, '0000000000000000'),
            lambda x: x['header']['placement'].update(matrix_bits=None),
            lambda x: x['header']['evidence']['synthetic'].update(data_base64='YQ=='),
            lambda x: x['header']['cases'][0].update(duration_q=2),
            lambda x: x['header']['cases'][0].update(phase_ids=[]),
            lambda x: x['footer'].update(row_count=1)]
        for mutate in mutations:
            raw, cases = raw_control()
            mutate(raw)
            with self.assertRaises((ValueError, KeyError, TypeError)):
                metric.validate_raw_observation(raw, cases)
        for text in [b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":1e999}', b'null', b'[]']:
            with self.assertRaises(ValueError):
                metric.decode_raw_observation(text)

    def test_gram_exact_threshold_and_nearby_matrices(self):
        # Off-diagonal dot product is exactly x; threshold is the legacy operand.
        threshold = 1e-10*1.*1.
        for x, status in [(math.nextafter(threshold, 0.), 'PREDICATE_SATISFIED'),
                          (threshold, 'PREDICATE_SATISFIED'),
                          (math.nextafter(threshold, math.inf), 'FAIL')]:
            m = copy.deepcopy(I)
            m[0][1] = x
            result = metric.raw_uniformity(m, 1.)
            self.assertEqual(result['threshold'], threshold)
            self.assertEqual(result['residuals'][0][1], x)
            self.assertEqual(result['status'], status)
            self.assertEqual(result['gram'][0][1].hex(), x.hex())

    def test_raw_rigid_transform_and_material_boundary(self):
        raw, cases = raw_control()
        m = [[0., 0., 2., 5.], [0., 2., 0., -3.], [-2., 0., 0., 7.], [0., 0., 0., 1.]]
        raw, cases = raw_control(m, 2.)
        h = raw['header']
        h['surfaces'][0]['origin'] = [5., -3., 7.]
        patch = h['cases'][0]['patches'][0]
        patch['anchors'] = [[5., -3., 7.]]
        patch['end'] = .5
        second = copy.deepcopy(patch)
        second.update(id='toe', kind='toe', start=.5, end=1., anchors=[[5., -3., 8.]])
        h['cases'][0]['patches'].append(second)
        state = metric.validate_raw_observation(raw, cases)
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, .5)['mapped']
        self.assertEqual(result['patches'][0]['id'], 'toe')
        self.assertEqual(result['exit_patches'][0]['id'], 'sole')
        self.assertAlmostEqual(result['exit_patches'][0]['measurements'][0]['error_model_um'], 3000.)
        self.assertAlmostEqual(result['patches'][0]['measurements'][0]['slip_world_m'], 1.006)
        self.assertEqual(result['coverage']['anchors']['expected'], 2)

    def test_original_decimal_observation_stays_adverse_and_lacks_native_bits(self):
        # Frozen observation extract SHA256 d1c389d2878939f2748f1f13aa8739b757150d238068ba56aa06bb5916c89499.
        # Decimal observations only: these are NOT newly reconstructed native bits.
        m = [[-25.321369171142578, -1.0859295129776, -.1312253475189209, -1597.8409423828125],
             [-1.0859289169311523, 24.592130661010742, 6.034578323364258, 816.972900390625],
             [-.1312297135591507, 6.034578323364258, -24.615745544433594, 3584.627197265625],
             [0, 0, 0, 1]]
        scale = 25.34498405456543
        result = metric.raw_uniformity(m, scale)
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual(result['worst_indices'], [2, 2])
        self.assertEqual(result['residuals'][2][2]/(scale*scale), 1.0525859445735615e-7)
        with self.assertRaisesRegex(ValueError, 'placement differs from original uniform scale'):
            metric.validate_contact_input({'placement': m, 'original_scale': scale,
                'provenance': {'source': 'original decimal observation', 'sha256': 'd1c389d2878939f2748f1f13aa8739b757150d238068ba56aa06bb5916c89499'}}, [])
        raw, cases = raw_control()
        raw['header']['placement'].update(matrix=m, original_scale=scale, matrix_bits=None, scale_bits=None)
        with self.assertRaisesRegex(ValueError, 'missing raw matrix bits'):
            metric.validate_raw_observation(raw, cases)

    def test_literal_native_words_fail_raw_uniformity_without_physical_claim(self):
        # New frozen native observation, not a repair/backfill of the old decimal extract.
        witness = {'observation_sha256': '15dc1688a4dc82fe1160bf5207c596d89d73c227c0172c7af8bd22121e4ce4ff',
            'capture_sha256': '1b3e2a70ba0e47ddd0a3fe6fe9785ac794ac522b3f7444d6eb54ce5957e90fc7',
            'engine': '4.7.2/ed1daf0bf001b61586d9930840f2f1394092c079', 'frame': 119,
            'matrix_words_le': [['2a92cac1', 'bdff8abf', 'f05f06be', 'e9bac7c4'],
                                ['b8ff8abf', 'afbcc441', '441bc140', '443e4c44'],
                                ['156106be', '441bc140', '0cedc4c1', '090a6045']],
            'scale_vector_variant_hex': '0900000087c2ca4188c2ca4188c2ca41',
            'reported_scale_f64_le': '000000e050583940',
            'affine_row': 'structural constants, not independently captured memory',
            'construction': 'Original seat_at terrain samples/intermediate normal/rounding UNKNOWN'}
        words = [[bytes.fromhex(word)[::-1].hex() for word in row] for row in witness['matrix_words_le']]
        words.append(['00000000', '00000000', '00000000', '3f800000'])
        m = [[struct.unpack('>f', bytes.fromhex(word))[0] for word in row] for row in words]
        scale = struct.unpack('<d', bytes.fromhex(witness['reported_scale_f64_le']))[0]
        self.assertEqual(scale, 25.34498405456543)
        self.assertNotEqual(scale, 26.351918763158388)  # retained seat k cannot replace reported scale
        raw, cases = raw_control(m, scale)
        h = raw['header']
        h['placement'].update(precision='binary32', matrix_bits=words, scale_precision='binary64',
            scale_bits='40395850e0000000',
            construction_inputs=None, unavailable_reason=witness['construction'])
        payload = json.dumps(witness, sort_keys=True, separators=(',', ':')).encode()
        h['evidence']['native_witness'] = {'sha256': hashlib.sha256(payload).hexdigest(),
                                          'data_base64': base64.b64encode(payload).decode()}
        for term in h['uncertainty'].values():
            term.update(value=None, reason='synthetic surface plus native placement is no physical error proof')
        state = metric.validate_raw_observation(raw, cases)
        self.assertEqual(state['placement_uniformity']['status'], 'FAIL')
        self.assertEqual(state['uncertainty_status'], 'UNKNOWN')
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, .5)['mapped']['patches'][0]
        self.assertEqual(result['budget_status'], 'PENDING')
        self.assertIsNone(result['measurements'][0]['error_model_um'])
        self.assertIsNone(result['measurements'][0]['upper_bound_model_um'])
        self.assertGreater(result['measurements'][0]['slip_world_m'], 3900.)
        with self.assertRaisesRegex(ValueError, 'placement differs from original uniform scale'):
            metric.validate_contact_input({'placement': m, 'original_scale': scale,
                'provenance': {'source': 'native observation', 'sha256': witness['observation_sha256']}}, [])

    def test_bounds_outgoing_and_uncovered_plane(self):
        raw, cases = raw_control()
        h = raw['header']
        sha = h['provenance']['sha256']
        h['budget'] = {'contact_um': 3200, 'authority': 'synthetic', 'source_sha256': sha}
        h['uncertainty']['position']['value'] = .0001
        h['uncertainty']['height']['value'] = .0002
        h['uncertainty']['anchor']['value'] = .0001
        state = metric.validate_raw_observation(raw, cases)
        for budget, expected in [(3200, 'FAIL'), (3201, 'WITHIN_FINITE_SAMPLES')]:
            h['budget']['contact_um'] = budget
            result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, 1.)['mapped']
            self.assertEqual(result['patches'][0]['budget_status'], expected)
            self.assertEqual(result['exit_patches'], result['patches'])
            upper = result['patches'][0]['measurements'][0]['upper_bound_model_um']
            self.assertGreater(upper, 3200.)
            self.assertLessEqual(upper, 3201.)
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.], [20., -.01, 0.]]}, state, 0, .5)['mapped']
        self.assertEqual(result['coverage']['uncovered_vertex_ids'], [1])
        self.assertEqual(result['patches'][0]['budget_status'], 'PENDING')
        self.assertAlmostEqual(result['whole_mesh_penetration_world_m'], .01)
        h['surfaces'][0]['domain']['xz_max'][0] = .001
        state = metric.validate_raw_observation(raw, cases)
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, 1.)['mapped']
        self.assertEqual(result['coverage']['active_patches']['uncovered_ids'], ['sole'])
        self.assertEqual(result['coverage']['outgoing_patches']['valid'], 0)
        self.assertEqual(result['coverage']['anchors']['valid'], 1)

    def test_uncertainty_neighbourhood_must_stay_in_proven_plane(self):
        for units in [1., .01, 100.]:
            for contributor in ['position', 'query_coordinate', 'anchor']:
                raw, cases = raw_control(units=units)
                h = raw['header']
                h['budget'] = {'contact_um': 10**12, 'authority': 'synthetic',
                               'source_sha256': h['provenance']['sha256']}
                h['uncertainty'][contributor]['value'] = .01
                h['surfaces'][0]['domain'] = {'xz_min': [-1./units, -1./units],
                                             'xz_max': [.003/units, 1./units]}
                if contributor == 'anchor':
                    h['cases'][0]['patches'][0]['anchors'] = [[.0025/units, 0., 0.]]
                state = metric.validate_raw_observation(raw, cases)
                x = .001 if contributor == 'anchor' else .003
                result = metric.raw_physical_metrics({'mapped': [[x/units, -.002/units, 0.]]}, state, 0, 1.)['mapped']
                patch = result['patches'][0]
                self.assertEqual(patch['budget_status'], 'PENDING', (units, contributor))
                self.assertIsNone(patch['measurements'][0]['upper_bound_model_um'])
                self.assertEqual(patch['measurements'][0]['coverage'], 'UNCOVERED')
                self.assertEqual(result['coverage']['status'], 'UNCOVERED')
                self.assertEqual(result['coverage']['active_patches']['uncovered_ids'], ['sole'])
                self.assertEqual(result['coverage']['outgoing_patches']['uncovered_ids'], ['sole'])
                self.assertAlmostEqual(patch['measurements'][0]['signed_world_m'], -.002)
                if contributor == 'anchor':
                    self.assertEqual(result['coverage']['valid_vertices'], 1)
                    self.assertEqual(result['coverage']['anchors']['valid'], 0)
                else:
                    self.assertEqual(result['coverage']['valid_vertices'], 0)
                # The same justified bounds are usable strictly inside the proven domain.
                h['surfaces'][0]['domain']['xz_max'][0] = 1./units
                interior = metric.raw_physical_metrics({'mapped': [[x/units, -.002/units, 0.]]}, state, 0, 1.)['mapped']
                self.assertEqual(interior['patches'][0]['budget_status'], 'WITHIN_FINITE_SAMPLES')
                self.assertIsNotNone(interior['patches'][0]['measurements'][0]['upper_bound_model_um'])

    def test_unknown_xz_bounds_and_roundoff_cannot_prove_domain_coverage(self):
        for contributor in ['position', 'query_coordinate', 'anchor']:
            raw, cases = raw_control()
            raw['header']['uncertainty'][contributor].update(value=None, reason='unknown neighbourhood')
            state = metric.validate_raw_observation(raw, cases)
            result = metric.raw_physical_metrics({'mapped': [[.001, -.002, 0.]]}, state, 0, 1.)['mapped']
            self.assertEqual(result['coverage']['active_patches']['valid'], 0)
            self.assertEqual(result['coverage']['outgoing_patches']['valid'], 0)
            self.assertIsNone(result['patches'][0]['measurements'][0]['upper_bound_model_um'])
        raw, cases = raw_control()
        raw['header']['surfaces'][0]['domain']['xz_max'][0] = .003
        state = metric.validate_raw_observation(raw, cases)
        result = metric.raw_physical_metrics({'mapped': [[.003, -.002, 0.]]}, state, 0, .5)['mapped']
        self.assertEqual(result['coverage']['uncovered_vertex_ids'], [0])
        # A cancelled matrix product still needs its absolute-product placement guard.
        m = copy.deepcopy(I)
        m[0][0], m[0][1] = 1e10, -1e10
        raw, cases = raw_control(m)
        raw['header']['surfaces'][0]['domain'] = {'xz_min': [-.0005, -10.], 'xz_max': [.0005, 10.]}
        state = metric.validate_raw_observation(raw, cases)
        result = metric.raw_physical_metrics({'mapped': [[1., 1., 0.]]}, state, 0, .5)['mapped']
        self.assertEqual(result['coverage']['uncovered_vertex_ids'], [0])

    def test_cli_modes_are_explicit_and_exclusive(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'raw.json'
            path.write_text('{"schema":"unknown"}')
            for flags in [['--raw-observation', str(path)],
                          ['--raw-observation', str(path), '--contact-input', str(path)]]:
                run = subprocess.run([sys.executable, metric.__file__, *flags], capture_output=True, text=True)
                self.assertNotEqual(run.returncode, 0)
                self.assertEqual(run.stdout, '')
            self.assertIn('--raw-observation', subprocess.run([sys.executable, metric.__file__, '--help'],
                          capture_output=True, text=True).stdout)


def full_check():
    before = hashlib.sha256(frozen.FIXTURE.read_bytes()).hexdigest()
    outputs = []
    for _ in range(2):
        run = subprocess.run([sys.executable, str(Path(metric.__file__))], capture_output=True, text=True, check=True)
        outputs.append(run.stdout)
    assert outputs[0] == outputs[1], 'nondeterministic output'
    assert hashlib.sha256(frozen.FIXTURE.read_bytes()).hexdigest() == before
    report = json.loads(outputs[0])
    assert hashlib.sha256(outputs[0].encode()).hexdigest() == 'f8b140e7ff4346f11efa6c0e64634f6e110331fe9b26050b21ee26a08f8bfece', 'legacy output bytes changed'
    assert report['absolute_edge_phase_flags'] == {'source': 652, 'reference': 563, 'mapped': 471}
    assert report['introduced_edge_phase_flags'] == {'reference': 103, 'mapped': 45, 'mapping_only': 1}
    assert report['whole_mesh_sha256'] == {
        'source': 'c7b8a5f208c69d0c30b32098a1e4f1c36906b85826d48d8290a9357fc5d8df7e',
        'reference': '086193886028a3d2f0ec7814dde4c0f523beda0da31d50c5fb320fc960b57954',
        'mapped': '94540ff4eb6ff5a616ec699a814cfda2cee56ae8d4070bceeeba816f97815651'}
    assert report['reproduction']['edge_phase_flags'] == 471
    assert report['reproduction']['introduced'] == 45
    assert report['reproduction']['mapping_only_crossings'] == 1
    assert len(report['frames']) == 1300
    assert report['coverage']['edges'] == 33427
    assert report['motion_acceptance'] == 'FAIL/PENDING'
    assert report['coverage']['contact'] == 'PENDING'
    assert report['source_endpoint_edge23264']['flagged']
    assert all(set(r['edges']) == {'source', 'reference', 'mapped'} for r in report['frames'])
    for label in ['source', 'reference', 'mapped']:
        assert len(report['whole_mesh_sha256'][label]) == 64
    Path('.superpowers/pivot-metrics-report.json').write_text(outputs[0])
    print('FULL_MATCH twice; fixture unchanged; report SHA256=' + hashlib.sha256(outputs[0].encode()).hexdigest())


if __name__ == '__main__':
    full = '--full' in sys.argv
    if full:
        sys.argv.remove('--full')
    suite = unittest.main(exit=False)
    if not suite.result.wasSuccessful():
        sys.exit(1)
    if full:
        full_check()
