#!/usr/bin/env python3
"""Synthetic checks; --full also runs the frozen full native reproduction twice."""
import base64
import copy
import hashlib
import io
import json
import math
import resource
import time
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

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

    def test_b_errors_precede_new_dispatch_and_surface_checks(self):
        raw, cases = raw_control()
        raw['header']['surfaces'][0]['kind'] = 'unknown'
        with self.assertRaisesRegex(ValueError, '^duplicate/unsupported raw surface$'):
            metric.validate_raw_observation(raw, cases)
        with self.assertRaisesRegex(ValueError, '^unknown/missing raw schema fields$'):
            metric.evaluate({'round1_arc_combined/inputs.json': {'cases': cases}}, raw_observation={})

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


def native_control(m=None, scale=1., units=1.):
    raw, cases = raw_control(m, scale, units)
    h = raw['header']
    h['surface_mode'] = 'native_queries'
    ref = h['inputs']['terrain']
    h['surfaces'] = [{'id': 'plane', 'kind': 'terrain_raw',
        'domain': {'xz_min': [-10., -10.], 'xz_max': [10., 10.]}, 'provenance': dict(ref),
        'resources': {'before': dict(ref), 'after': dict(ref)}, 'terrain_transform': I,
        'region': 'synthetic', 'lod': 'synthetic', 'method': 'synthetic-oracle', 'method_version': '1',
        'parameters': dict(ref), 'selection': {'height': 'raw', 'normal': 'raw', 'sea_level': None, 'override_id': None}}]
    bounds = h['uncertainty']
    bounds['height_lipschitz'] = dict(bounds['normal'])
    bounds['normal_lipschitz'] = dict(bounds['normal'], unit='1/m')
    h['uncertainty'] = {'synthetic': bounds}
    return raw, cases


def oracle(request, height=0., normal=(0., 1., 0.)):
    scalar = lambda value: {'precision': 'binary64', 'bits': struct.pack('>d', value).hex()}
    n = None if normal is None else {'precision': 'binary64', 'bits': [struct.pack('>d', x).hex() for x in normal]}
    h = None if height is None else scalar(height)
    return {'request': copy.deepcopy(request), 'status': 'OK' if height is not None else 'HOLE',
            'raw_height': h, 'raw_normal': n, 'used_height': h, 'used_normal': n,
            'height_surface_id': request['surface_id'], 'normal_surface_id': request['surface_id'],
            'height_method': request['method'], 'normal_method': request['method'],
            'capture_id': '0', 'uncertainty_id': 'synthetic',
            'reason': None if height is not None and normal is not None else 'synthetic unavailable'}


class NativeMetricTest(unittest.TestCase):
    def setup_native(self, m=None, scale=1., units=1.):
        raw, cases = native_control(m, scale, units)
        self.assertTrue(hasattr(metric, 'native_request'), 'C native requests missing')
        return raw, cases, metric.validate_raw_observation(raw, cases)

    def measure(self, p, a=(0., 0., 0.), height=0., normal=(0., 1., 0.), anchor_normal=(0., 1., 0.), state=None):
        if state is None:
            _, _, state = self.setup_native()
        req = metric.native_request(state, 0, 0, .5, .25.hex(), 'mapped', 0, p)
        patch = dict(state['header']['cases'][0]['patches'][0], anchors=[list(a)])
        ar = metric.native_request(state, 1, 0, None, None, None, 0, list(a), patch)
        return metric.native_measure(p, req, oracle(req, height, normal), ar,
                                     oracle(ar, a[1], anchor_normal), state)

    def test_hand_planar_slopes_fixed_anchor_ridge_and_hole(self):
        result = self.measure([.003, -.002, 0.])
        self.assertAlmostEqual(result['vertical_world_m'], -.002)
        self.assertAlmostEqual(result['signed_world_m'], -.002)
        self.assertAlmostEqual(result['slip_world_m'], .003)
        self.assertAlmostEqual(result['error_model_um'], 3000.)
        result = self.measure([1., .9, 0.], (-1., 0., 0.), 1., (-1., 1., 0.))
        self.assertAlmostEqual(result['vertical_world_m'], -.1)
        self.assertAlmostEqual(result['signed_world_m'], -.1/math.sqrt(2))
        self.assertAlmostEqual(result['slip_world_m'], 2.)
        result = self.measure([-.5, -.1, 0.], (-1., 0., 0.))
        self.assertAlmostEqual(result['signed_world_m'], -.1)
        self.assertAlmostEqual(result['slip_world_m'], .5)
        for height, normal in [(0., None), (None, None), (0., (0., 0., 0.)), (0., (0., -1., 0.))]:
            result = self.measure([0., -.1, 0.], height=height, normal=normal)
            self.assertEqual(result['coverage'], 'UNCOVERED')
            self.assertIsNone(result['upper_bound_model_um'])
            self.assertEqual(result['vertical_world_m'], None if height is None else -.1)

    def test_uncertainty_unknown_fail_placement_and_footprint(self):
        raw, cases, state = self.setup_native()
        b = raw['header']['uncertainty']['synthetic']
        b['position']['value'] = .0001
        b['height']['value'] = .0002
        b['anchor']['value'] = .0001
        state = metric.validate_raw_observation(raw, cases)
        result = self.measure([.003, -.002, 0.], state=state)
        self.assertEqual(math.ceil(result['upper_bound_model_um']), 3201)
        self.assertEqual(metric.budget_status(result['upper_bound_model_um'], 0., {'contact_um': 3200}), 'FAIL')
        self.assertEqual(metric.budget_status(result['upper_bound_model_um'], 0., {'contact_um': 3201}), 'WITHIN_FINITE_SAMPLES')
        b['height_lipschitz'].update(value=None, reason='no neighbourhood proof')
        result = self.measure([.003, -.002, 0.], state=metric.validate_raw_observation(raw, cases))
        self.assertIsNone(result['upper_bound_model_um'])
        m = copy.deepcopy(I); m[0][1] = .01
        _, _, state = self.setup_native(m)
        result = self.measure([.003, -.002, 0.], state=state)
        self.assertIsNone(result['error_model_um'])
        self.assertIsNone(result['upper_bound_model_um'])
        for p in ([10., 0., 0.], [math.nextafter(10., 0.), 0., 0.]):
            self.assertEqual(self.measure(p)['coverage'], 'UNCOVERED')

    def test_unproven_vertex_and_anchor_neighbourhoods_have_no_bounds(self):
        for x, error in ((11., 0.), (9.999, .01)):
            with self.subTest(x=x, error=error):
                raw, cases = native_control()
                raw['header']['uncertainty']['synthetic']['position']['value'] = error
                state = metric.validate_raw_observation(raw, cases)
                value = self.measure([x, -.1, 0.], state=state)
                self.assertEqual(value['vertical_world_m'], -.1)
                self.assertEqual(value['signed_world_m'], -.1)
                self.assertIsNone(value['vertical_interval_world_m'])
                self.assertIsNone(value['signed_interval_world_m'])
                self.assertIn('surface_domain', value['unknown_terms'])
                self.assertIsNone(value['upper_bound_model_um'])
                # Slip uses the independently captured anchor normal, not the vertex normal.
                self.assertIsNotNone(value['slip_interval_world_m'])
                raw['header']['uncertainty']['synthetic']['anchor']['value'] = error
                state = metric.validate_raw_observation(raw, cases)
                value = self.measure([0., -.1, 0.], a=[x, 0., 0.], state=state)
                self.assertEqual(value['slip_world_m'], x)
                self.assertIsNone(value['slip_interval_world_m'])
                self.assertIn('anchor:surface_domain', value['unknown_terms'])
                self.assertIsNotNone(value['vertical_interval_world_m'])
                self.assertIsNotNone(value['signed_interval_world_m'])

    def test_placement_guard_crossing_invalidates_dependent_bounds(self):
        raw, cases = native_control()
        raw['header']['surfaces'][0]['domain']['xz_max'][0] = 1.+8e-14
        state = metric.validate_raw_observation(raw, cases)
        p = [1., -.1, 0.]
        req = metric.native_request(state, 0, 0, .5, .25.hex(), 'mapped', 0, p)
        self.assertTrue(metric.native_sample(oracle(req), req, state)['covered'])
        value = self.measure(p, state=state)
        self.assertEqual(value['vertical_world_m'], -.1)
        self.assertEqual(value['coverage'], 'UNCOVERED')
        self.assertIsNone(value['vertical_interval_world_m'])
        self.assertIsNone(value['signed_interval_world_m'])
        self.assertIn('surface_domain', value['unknown_terms'])
        raw['header']['surfaces'][0]['domain']['xz_max'][0] = 1.+2e-14
        state = metric.validate_raw_observation(raw, cases)
        value = self.measure([0., -.1, 0.], a=[1., 0., 0.], state=state)
        self.assertIsNone(value['slip_interval_world_m'])
        self.assertIn('anchor:surface_domain', value['unknown_terms'])
        self.assertIsNotNone(value['vertical_interval_world_m'])

    def test_normalization_handles_extreme_finite_raw_normals(self):
        for size in (1e-320, 1.5e308):
            result = self.measure([1., .9, 0.], (-1., 0., 0.), 1., (-size, size, 0.))
            self.assertAlmostEqual(result['signed_world_m'], -.1/math.sqrt(2), places=14)
            self.assertEqual(result['coverage'], 'COMPLETE_FINITE')

    def test_scale_units_and_requeried_rotated_surface(self):
        for scale, units in [(1., 1.), (2., 1.), (200., .01)]:
            m = [[scale*x if r < 3 else x for x in row] for r, row in enumerate(I)]
            _, _, state = self.setup_native(m, scale, units)
            result = self.measure([.003, -.002, 0.], state=state)
            self.assertAlmostEqual(result['error_model_um'], 3000.)
            self.assertAlmostEqual(result['slip_world_m'], .003*scale*units)
        # Rotating points AND querying the rotated plane keeps normal/slip error.
        t = math.sqrt(.5)
        m = [[t, -t, 0., 0.], [t, t, 0., 0.], [0., 0., 1., 0.], [0., 0., 0., 1.]]
        _, _, state = self.setup_native(m)
        result = self.measure([.003, -.002, 0.], height=.005*t, normal=(-t, t, 0.),
                              anchor_normal=(-t, t, 0.), state=state)
        self.assertAlmostEqual(result['error_model_um'], 3000.)
        self.assertAlmostEqual(result['signed_world_m'], -.002)

    def test_sea_holes_mixed_surfaces_and_producer_hashes_stay_adverse(self):
        raw, cases, _ = self.setup_native()
        surface = raw['header']['surfaces'][0]
        surface['kind'] = 'sea_clamped'
        surface['selection'].update(height='max_raw_sea', normal='branch', sea_level=0.)
        state = metric.validate_raw_observation(raw, cases)
        request = metric.native_request(state, 0, 0, .5, .25.hex(), 'mapped', 0, [0., -.1, 0.])
        response = oracle(request)
        response['raw_height'] = {'precision': 'binary32', 'bits': '7fc00000'}
        response['status'], response['reason'] = 'HOLE', 'native terrain hole; runtime used sea'
        sample = metric.native_sample(response, request, state)
        self.assertFalse(sample['covered'])
        self.assertIsNone(sample['height_error'])
        self.assertIsNone(sample['normal_error'])
        self.assertIn('surface_unavailable', sample['missing'])
        response['status'], response['reason'] = 'OK', None
        with self.assertRaisesRegex(ValueError, 'nonfinite raw observation requires unavailable status'):
            metric.native_sample(response, request, state)
        response = oracle(request)
        response['raw_height'] = None
        with self.assertRaisesRegex(ValueError, 'missing unavailable query reason'):
            metric.native_sample(response, request, state)
        response = oracle(request, 0., (-1., 1., 0.))
        response['used_normal'] = {'precision': 'binary64', 'bits': [struct.pack('>d', x).hex() for x in (0., 1., 0.)]}
        sample = metric.native_sample(response, request, state)
        self.assertFalse(sample['covered'], 'switch normal is ambiguous')
        self.assertIsNone(sample['normal_error'])
        self.assertIsNotNone(sample['height_error'])
        self.assertIn('surface_switch_normal', sample['missing'])
        measured = metric.native_measure([0., -.1, 0.], request, response, request, response, state)
        self.assertEqual(measured['signed_world_m'], -.1)
        self.assertIsNone(measured['signed_interval_world_m'])
        self.assertIsNone(measured['slip_interval_world_m'])
        self.assertIsNotNone(measured['vertical_interval_world_m'])
        raw['header']['uncertainty']['synthetic']['height']['value'] = .01
        state = metric.validate_raw_observation(raw, cases)
        for height, crosses in ((.005, True), (.1, False)):
            sample = metric.native_sample(oracle(request, height, (-1., 1., 0.)), request, state)
            self.assertEqual(sample['normal_error'] is None, crosses)
            self.assertIsNotNone(sample['height_error'])
        raw['header']['surfaces'][0]['resources']['after']['sha256'] = 'a'*64
        with self.assertRaises(ValueError):
            metric.validate_raw_observation(raw, cases)

    def test_neighbourhood_lipschitz_and_unknown_vertical_separation(self):
        raw, cases, _ = self.setup_native()
        b = raw['header']['uncertainty']['synthetic']
        b['position']['value'] = .01
        b['height_lipschitz']['value'] = 2.
        b['normal_lipschitz']['value'] = .5
        state = metric.validate_raw_observation(raw, cases)
        request = metric.native_request(state, 0, 0, .5, .25.hex(), 'mapped', 0, [1.+2**-24, .9, 0.])
        sample = metric.native_sample(oracle(request), request, state)
        self.assertGreater(sample['height_error'], .02)
        self.assertGreater(sample['normal_error'], .005)
        b['normal'].update(value=None, reason='unbounded normal')
        state = metric.validate_raw_observation(raw, cases)
        result = self.measure([1., .9, 0.], state=state)
        self.assertEqual(result['vertical_world_m'], .9)
        self.assertIsNotNone(result['vertical_interval_world_m'])
        self.assertIsNone(result['signed_interval_world_m'])
        self.assertIsNone(result['upper_bound_model_um'])

    def test_raw_words_rounding_and_echo_tampering(self):
        _, _, state = self.setup_native()
        req = metric.native_request(state, 0, 0, .5, .25.hex(), 'source', 0, [1.+2**-24, 0., -0.])
        self.assertEqual(req['query_xz_f32'], ['3f800000', '00000000'])
        self.assertEqual(req['intended_xz_f64'], ['3ff0000010000000', '0000000000000000'])
        self.assertEqual(req['phase_hex'], .5.hex())
        for key, value in [('ordinal', 1), ('phase_hex', 0.0.hex()), ('source_phase_id', 0.0.hex()),
                           ('surface_sha256', 'f'*64), ('query_xz_f32', ['3f800001', '80000000'])]:
            response = oracle(req)
            response['request'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                metric.native_sample(response, req, state)
        response = oracle(req)
        response['normal_surface_id'] = 'sea'
        self.assertFalse(metric.native_sample(response, req, state)['covered'])
        response = oracle(req); response['used_height']['bits'] = struct.pack('>d', 2.).hex()
        # raw_height and used_height are independently mutable in real JSON.
        response['raw_height'] = {'precision': 'binary64', 'bits': struct.pack('>d', 0.).hex()}
        with self.assertRaises(ValueError):
            metric.native_sample(response, req, state)
        with self.assertRaises((ValueError, OverflowError)):
            metric.native_request(state, 0, 0, .5, .25.hex(), 'source', 0, [1e50, 0., 0.])


class NativeRunTest(unittest.TestCase):
    def run_requests(self, state, path):
        points = {label: [[1., .9, 0.]] for label in ('source', 'reference', 'mapped')}
        with metric.NativeRun(state, 1, query_output=path) as run:
            for phase in (0., .5, 1.):
                run.frame(points, 0, phase, float(phase/2).hex())
            return run.finish()

    def test_full_order_anchors_outgoing_and_stream_binding(self):
        self.assertTrue(hasattr(metric, 'NativeRun'), 'C native stream integration missing')
        raw, cases = native_control()
        raw['header']['cases'][0]['patches'] = [
            dict(raw['header']['cases'][0]['patches'][0], id='old', end=.5, anchors=[[-1., 0., 0.]]),
            dict(raw['header']['cases'][0]['patches'][0], id='new', start=.5, anchors=[[1., 1., 0.]])]
        state = metric.validate_raw_observation(raw, cases)
        with tempfile.TemporaryDirectory() as tmp:
            q, r = Path(tmp)/'queries', Path(tmp)/'responses'
            report = self.run_requests(state, q)
            self.assertEqual(report['vertex_count'], 9)
            self.assertEqual(report['anchor_count'], 2)
            with q.open('rb') as source:
                stream = metric.QueryStream(source, 'requests', metric.query_header(state))
                requests = list(stream)
            self.assertEqual([x['variant'] for x in requests[:6]], ['source', 'reference', 'mapped']*2)
            self.assertEqual([x['anchor_id'] for x in requests[9:]], ['old', 'new'])
            self.assertEqual(requests[9]['interval_hex'], [0.0.hex(), .5.hex()])
            responses = [oracle(req, 1. if struct.unpack('>d', bytes.fromhex(req['position_f64'][0]))[0] > 0 else 0.,
                                (-1., 1., 0.) if struct.unpack('>d', bytes.fromhex(req['position_f64'][0]))[0] > 0 else (0., 1., 0.))
                         for req in requests]
            header = dict(metric.query_header(state), request_stream_sha256=stream.footer['stream_sha256'])
            with r.open('wb') as output:
                metric.write_query_stream(output, 'responses', header, responses)
            points = {label: [[1., .9, 0.]] for label in ('source', 'reference', 'mapped')}
            with metric.NativeRun(state, 1, query_responses=r) as run:
                frames = [run.frame(points, 0, phase, float(phase/2).hex()) for phase in (0., .5, 1.)]
                result = run.finish()
            self.assertEqual(result['vertex_count'], 9)
            self.assertEqual(result['anchor_count'], 2)
            self.assertEqual(result['uncertainty_status'], 'BOUNDED')
            self.assertEqual(result['unknown_terms'], [])
            mid = frames[1]['mapped']
            self.assertAlmostEqual(mid['exit_patches'][0]['max_slip_world_m'], 2.)
            self.assertEqual(mid['patches'][0]['id'], 'new')
            self.assertEqual(mid['exit_patches'][0]['anchor_requests'], {'first_ordinal': 9, 'row_count': 1})
            self.assertEqual(mid['patches'][0]['anchor_requests'], {'first_ordinal': 10, 'row_count': 1})
            self.assertEqual(frames[-1]['mapped']['exit_patches'][0]['id'], 'new')
            self.assertAlmostEqual(mid['whole_mesh_min_signed_world_m'], -.1/math.sqrt(2))
            self.assertEqual(mid['patches'][0]['budget_status'], 'PENDING')
            # Full stream digest recomputation cannot excuse identity changes.
            responses[0]['request']['phase_hex'] = .25.hex()
            with r.open('wb') as output:
                metric.write_query_stream(output, 'responses', header, responses)
            with self.assertRaises(ValueError), metric.NativeRun(state, 1, query_responses=r) as run:
                run.frame(points, 0, 0., 0.0.hex())

    def test_same_vertex_differences_coverage_and_budget_fail_closed(self):
        raw, cases = native_control()
        ref = raw['header']['inputs']['terrain']
        raw['header']['budget'] = {'contact_um': 10000000, 'authority': 'synthetic threshold only', 'source_sha256': ref['sha256']}
        points = {'source': [[1., .9, 0.], [1., .2, 0.]],
                  'reference': [[1., .9, 0.], [1., .2, 0.]],
                  'mapped': [[1., .3, 0.], [1., 1., 0.]]}
        with tempfile.TemporaryDirectory() as tmp:
            q, r = Path(tmp)/'q', Path(tmp)/'r'
            for mode in ('finite', 'hole', 'unknown', 'placement_fail'):
                observation = copy.deepcopy(raw)
                if mode == 'unknown':
                    observation['header']['uncertainty']['synthetic']['normal'].update(value=None, reason='missing bound')
                if mode == 'placement_fail':
                    placement = observation['header']['placement']
                    placement['matrix'][0][1] = .01
                    placement['matrix_bits'][0][1] = struct.pack('>d', .01).hex()
                state = metric.validate_raw_observation(observation, cases)
                with metric.NativeRun(state, 2, query_output=q) as run:
                    for phase in (0., .5, 1.):
                        run.frame(points, 0, phase, float(phase/2).hex())
                    run.finish()
                with q.open('rb') as source:
                    reader = metric.QueryStream(source, 'requests', metric.query_header(state))
                    requests = list(reader)
                responses = [oracle(req, None if mode == 'hole' and req['role'] == 'vertex' and req['vertex_id'] == 1 else 0.) for req in requests]
                with r.open('wb') as output:
                    metric.write_query_stream(output, 'responses', dict(metric.query_header(state), request_stream_sha256=reader.footer['stream_sha256']), responses)
                with metric.NativeRun(state, 2, query_responses=r) as run:
                    frames = [run.frame(points, 0, phase, float(phase/2).hex()) for phase in (0., .5, 1.)]
                    run.finish()
                measured = frames[0]['mapped']
                self.assertEqual(measured['patches'][0]['budget_status'],
                    {'finite': 'WITHIN_FINITE_SAMPLES', 'hole': 'PENDING', 'unknown': 'PENDING', 'placement_fail': 'INELIGIBLE_PLACEMENT'}[mode])
                if mode == 'finite':
                    diff = measured['source_relative_world_m']['vertical']
                    self.assertAlmostEqual(diff['min'], -.6)
                    self.assertAlmostEqual(diff['max'], .8)
                    self.assertEqual([diff['min_vertex'], diff['max_vertex']], [0, 1])
                    self.assertIsNotNone(measured['extrema_intervals_world_m']['vertical'])
                if mode == 'hole':
                    self.assertEqual(measured['coverage']['uncovered_vertices'], 1)
                    self.assertIsNone(measured['extrema_intervals_world_m']['vertical'])
                # Response header digest must match regeneration, even if all rows match.
                bad_header = dict(metric.query_header(state), request_stream_sha256='a'*64)
                with r.open('wb') as output:
                    metric.write_query_stream(output, 'responses', bad_header, responses)
                with self.assertRaises(ValueError), metric.NativeRun(state, 2, query_responses=r) as run:
                    for phase in (0., .5, 1.):
                        run.frame(points, 0, phase, float(phase/2).hex())
                    run.finish()

    def test_unproven_domain_propagates_to_extrema_and_run_uncertainty(self):
        with tempfile.TemporaryDirectory() as tmp:
            q, r = Path(tmp)/'q', Path(tmp)/'r'
            for role in ('vertex', 'anchor'):
                raw, cases = native_control()
                raw['header']['uncertainty']['synthetic'][
                    'position' if role == 'vertex' else 'anchor']['value'] = .01
                if role == 'anchor':
                    raw['header']['cases'][0]['patches'][0]['anchors'] = [[9.999, 0., 0.]]
                state = metric.validate_raw_observation(raw, cases)
                points = {label: [[9.999 if role == 'vertex' else 0., -.1, 0.]]
                          for label in ('source', 'reference', 'mapped')}
                with metric.NativeRun(state, 1, query_output=q) as run:
                    for phase in (0., .5, 1.):
                        run.frame(points, 0, phase, float(phase/2).hex())
                    run.finish()
                with q.open('rb') as source:
                    reader = metric.QueryStream(source, 'requests', metric.query_header(state))
                    responses = [oracle(req) for req in reader]
                with r.open('wb') as output:
                    metric.write_query_stream(output, 'responses', dict(metric.query_header(state),
                        request_stream_sha256=reader.footer['stream_sha256']), responses)
                with metric.NativeRun(state, 1, query_responses=r) as run:
                    frames = [run.frame(points, 0, phase, float(phase/2).hex()) for phase in (0., .5, 1.)]
                    result = run.finish()
                self.assertEqual(result.get('uncertainty_status'), 'UNKNOWN')
                term = 'surface_domain' if role == 'vertex' else 'anchor:surface_domain'
                self.assertIn(term, result['unknown_terms'])
                self.assertIn('native uncertainty: '+term, result['blockers'])
                for frame in frames:
                    for value in frame.values():
                        self.assertEqual(value['whole_mesh_min_signed_world_m'], -.1)
                        self.assertEqual(value['coverage']['status'], 'UNCOVERED')
                        for interval in value['extrema_intervals_world_m'].values():
                            if role == 'vertex':
                                self.assertIsNone(interval)
                            else:
                                self.assertIsNotNone(interval)
                        for patch in value['patches']+value['exit_patches']:
                            self.assertIsNone(patch['upper_bound_model_um'])

    def test_manifest_preserves_ineligible_placement_with_supplied_budget(self):
        m = copy.deepcopy(I); m[0][1] = .01
        raw, cases = native_control(m)
        raw['header']['budget'] = {'contact_um': 10**9, 'authority': 'synthetic threshold only',
                                  'source_sha256': raw['header']['inputs']['terrain']['sha256']}
        state = metric.validate_raw_observation(raw, cases)
        with tempfile.TemporaryDirectory() as tmp:
            report = self.run_requests(state, Path(tmp)/'queries')
        self.assertEqual(report.get('budget_status'), 'INELIGIBLE_PLACEMENT')

    def test_truncated_input_does_not_publish_request_output(self):
        self.assertTrue(hasattr(metric, 'NativeRun'), 'C native stream integration missing')
        raw, cases = native_control(); state = metric.validate_raw_observation(raw, cases)
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)/'queries'
            target.write_bytes(b'previous evidence')
            with self.assertRaises(ValueError), metric.NativeRun(state, 1, query_output=target) as run:
                run.finish()
            self.assertEqual(target.read_bytes(), b'previous evidence')


class QueryStreamTest(unittest.TestCase):
    def test_bounded_roundtrip_counts_and_empty(self):
        self.assertTrue(hasattr(metric, 'write_query_stream'), 'C bounded stream writer missing')
        for count in (0, 1, 4097):
            out = io.BytesIO()
            header = {'observation_header_sha256': 'a'*64, 'fixture_sha256': metric.FIXTURE_SHA256,
                      'surface_manifest_sha256': 'b'*64, 'evidence': {}}
            footer = metric.write_query_stream(out, 'requests', header,
                                               ({'ordinal': i} for i in range(count)))
            reader = metric.QueryStream(io.BytesIO(out.getvalue()), 'requests', header)
            self.assertEqual(list(reader), [{'ordinal': i} for i in range(count)])
            self.assertEqual(reader.footer, footer)
            self.assertEqual(footer['row_count'], count)
            self.assertEqual(footer['chunk_count'], (count+4095)//4096)
            self.assertEqual(reader.file_sha256, hashlib.sha256(out.getvalue()).hexdigest())

    def test_byte_cap_canonical_rows_footer_and_restart(self):
        header = {'observation_header_sha256': 'a'*64, 'fixture_sha256': metric.FIXTURE_SHA256,
                  'surface_manifest_sha256': 'b'*64, 'evidence': {}}
        out = io.BytesIO()
        footer = metric.write_query_stream(out, 'requests', header,
            ({'ordinal': i, 'payload': 'x'*(9*1024*1024)} for i in range(2)))
        self.assertEqual(footer['chunk_count'], 2)
        reader = metric.QueryStream(io.BytesIO(out.getvalue()), 'requests', header)
        self.assertEqual(sum(1 for _ in reader), 2)
        with self.assertRaises(ValueError):
            list(reader)
        writer = metric.QueryWriter(io.BytesIO(), 'requests', header)
        writer.finish()
        with self.assertRaises(ValueError):
            writer.add({'ordinal': 0})
        for data in (b'{"ordinal": 0}\n', b'{"ordinal":0,"ordinal":0}\n', b'{"ordinal":1}\n',
                     b'{"ordinal":0}\n{"ordinal":0}\n', b'{"ordinal":NaN}\n'):
            chunk = {'chunk_index': 0, 'first_ordinal': 0, 'row_count': data.count(b'\n'),
                     'decoded_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                     'data_base64': base64.b64encode(zlib.compress(data)).decode()}
            fake = metric.stream_prefix('requests', header)+b'"chunks":[\n'+metric.compact(chunk)+b'\n'
            fake += b'],"footer":'+metric.compact({'chunk_count': 1, 'row_count': data.count(b'\n'),
                       'decoded_bytes': len(data), 'stream_sha256': hashlib.sha256(data).hexdigest()})+b'}\n'
            with self.subTest(data=data), self.assertRaises(ValueError):
                list(metric.QueryStream(io.BytesIO(fake), 'requests', header))

    def test_stream_rejects_tamper_truncation_restart_limits_and_noncanonical(self):
        self.assertTrue(hasattr(metric, 'write_query_stream'), 'C bounded stream writer missing')
        header = {'observation_header_sha256': 'a'*64, 'fixture_sha256': metric.FIXTURE_SHA256,
                  'surface_manifest_sha256': 'b'*64, 'evidence': {}}
        out = io.BytesIO()
        metric.write_query_stream(out, 'requests', header, ({'ordinal': i} for i in range(2)))
        raw = out.getvalue()
        lines = raw.splitlines(keepends=True)
        # Digests are recomputed too: integrity alone cannot excuse malformed rows/ordering.
        def changed_chunk(field, value):
            chunk = json.loads(lines[2].rstrip(b',\n'))
            chunk[field] = value
            return b''.join(lines[:2]+[metric.compact(chunk)+b'\n']+lines[3:])
        mutations = [raw[:-2], raw+raw, raw.replace(b'"row_count":2', b'"row_count":3'),
                     changed_chunk('chunk_index', 1), changed_chunk('first_ordinal', 1),
                     changed_chunk('row_count', 4097), changed_chunk('decoded_bytes', 16*1024*1024+1),
                     changed_chunk('data_base64', base64.b64encode(zlib.compress(b'x'*(16*1024*1024+1))).decode()),
                     changed_chunk('data_base64', json.loads(lines[2])['data_base64']+'!!!!'),
                     changed_chunk('data_base64', base64.b64encode(zlib.compress(b'{"ordinal":0}\n')+b'trailing').decode()),
                     b' '* (32*1024*1024+1)+b'\n', raw.replace(b'"ordinal"', b'"ordinal"', 1)]
        mutations.pop()  # The unchanged control must remain accepted.
        for value in mutations:
            with self.subTest(size=len(value)), self.assertRaises((ValueError, KeyError, TypeError, zlib.error)):
                list(metric.QueryStream(io.BytesIO(value), 'requests', header))


def native_full_check():
    """Execute the entire finite geometry and transport workload; never native terrain proof."""
    started = time.monotonic()
    data = metric.load_frozen()
    cases = data['round1_arc_combined/inputs.json']['cases']
    raw, _ = native_control()
    prototype = raw['header']['cases'][0]
    raw['header']['cases'] = []
    for case in cases:
        op = case['op']
        row = copy.deepcopy(prototype)
        row.update(turn_udeg=op['turn_udeg'], duration_q=op['duration_q'],
                   entry_phase_id=float(op['march_entry_phase']).hex(), exit_phase_id=float(op['march_exit_phase']).hex(),
                   phase_ids=[float(u).hex() for u in case['phases']])
        raw['header']['cases'].append(row)
    state = metric.validate_raw_observation(raw, cases)
    root = Path('.superpowers')
    root.mkdir(exist_ok=True)
    path = root/'pivot-native-requests.json'
    rss_unit = 1 if sys.platform == 'darwin' else 1024
    baseline_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*rss_unit
    print('NATIVE_FULL generating all 81,432,000 vertex requests, five independent synthetic anchors, and every frozen edge', flush=True)
    report = metric.evaluate(data, raw_observation=raw, query_output=path)
    generated_at = time.monotonic()
    native = report['raw_observation']['native_queries']
    assert native['vertex_count'] == 81432000 and native['anchor_count'] == 5
    assert native['row_count'] == 81432005 and native['frame_count'] == 1300
    assert report['absolute_edge_phase_flags'] == {'source': 652, 'reference': 563, 'mapped': 471}
    assert report['introduced_edge_phase_flags'] == {'reference': 103, 'mapped': 45, 'mapping_only': 1}
    assert report['whole_mesh_sha256'] == {
        'source': 'c7b8a5f208c69d0c30b32098a1e4f1c36906b85826d48d8290a9357fc5d8df7e',
        'reference': '086193886028a3d2f0ec7814dde4c0f523beda0da31d50c5fb320fc960b57954',
        'mapped': '94540ff4eb6ff5a616ec699a814cfda2cee56ae8d4070bceeeba816f97815651'}
    assert report['raw_observation']['measurement_status'] == 'PENDING_RESPONSES'
    assert report['raw_observation']['budget_status'] == 'PENDING'
    assert report['coverage']['edges'] == 33427 and len(report['frames']) == 1300
    assert report['source_endpoint_edge23264']['flagged']
    assert report['raw_observation']['coverage']['active_patches']['expected'] == 3900
    assert report['raw_observation']['coverage']['outgoing_patches']['expected'] == 15
    print('NATIVE_FULL generation complete; validating every serialized request and footer', flush=True)
    with path.open('rb') as source:
        stream = metric.QueryStream(source, 'requests', metric.query_header(state))
        count = sum(1 for _ in stream)
    assert count == 81432005 and stream.footer == native['footer']
    assert stream.file_sha256 == native['request_file_sha256']
    assert hashlib.sha256(frozen.FIXTURE.read_bytes()).hexdigest() == metric.FIXTURE_SHA256
    peak_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*rss_unit
    # Frozen inputs are resident already; extra request memory must not grow with 81M rows.
    assert peak_rss-baseline_rss < 256*1024*1024, (baseline_rss, peak_rss)
    summary = {'vertex_count': 81432000, 'anchor_count': 5, 'rows': count, 'edges_per_frame': 33427,
        'frames_per_variant': 1300, 'generation_seconds': generated_at-started,
        'read_seconds': time.monotonic()-generated_at, 'baseline_peak_rss_bytes': baseline_rss,
        'peak_rss_bytes': peak_rss, 'encoded_bytes': path.stat().st_size, **native,
        'fixture_sha256': metric.FIXTURE_SHA256, 'whole_mesh_sha256': report['whole_mesh_sha256'],
        'scope': 'complete frozen geometry/request transport; synthetic header, no native terrain observation'}
    (root/'pivot-native-full-summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True))
    (root/'pivot-native-metrics-report.json').write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
    print('NATIVE_FULL_MATCH '+json.dumps(summary, sort_keys=True), flush=True)


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
    native_full = '--native-full' in sys.argv
    if native_full:
        sys.argv.remove('--native-full')
    full = '--full' in sys.argv
    if full:
        sys.argv.remove('--full')
    suite = unittest.main(exit=False)
    if not suite.result.wasSuccessful():
        sys.exit(1)
    if full:
        full_check()
    if native_full:
        native_full_check()
