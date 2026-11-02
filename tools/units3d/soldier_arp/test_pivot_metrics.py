#!/usr/bin/env python3
"""Synthetic checks; --full also runs the frozen full native reproduction twice."""
import copy
import hashlib
import json
import math
from pathlib import Path
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


def full_check():
    before = hashlib.sha256(frozen.FIXTURE.read_bytes()).hexdigest()
    outputs = []
    for _ in range(2):
        run = subprocess.run([sys.executable, str(Path(metric.__file__))], capture_output=True, text=True, check=True)
        outputs.append(run.stdout)
    assert outputs[0] == outputs[1], 'nondeterministic output'
    assert hashlib.sha256(frozen.FIXTURE.read_bytes()).hexdigest() == before
    report = json.loads(outputs[0])
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
