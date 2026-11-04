"""Hand-computed and hostile cases for the offline phase fit (no Godot)."""
import copy
from fractions import Fraction as Q
import math
import json
import os
from unittest.mock import patch
import tempfile
import unittest
import struct
from pathlib import Path

import numpy as np

import check_cavalry_march_capture as capture
import cavalry_march_phase as phase


class PhaseTests(unittest.TestCase):
    def atlas(self):
        return phase.make_atlas([Q(0), Q(1, 2), Q(1)], [Q(0), Q(1), Q(3)], 'a'*64, .5)

    def test_pr229_inverse_fixtures_and_one_sided_derivative(self):
        atlas = self.atlas()
        self.assertEqual(phase.sample(atlas, 0, Q(1, 4), Q(3, 2)), (0, Q(3, 4), Q(1, 4)))
        self.assertEqual(phase.sample(atlas, 0, Q(1, 4), Q(3)), (1, Q(1, 4), Q(1, 2)))
        self.assertEqual(phase.sample(atlas, 0, Q(3, 4), Q(1)), (1, Q(0), Q(1, 2)))
        self.assertEqual(phase.sample(atlas, 0, Q(1, 2), Q(0)), (0, Q(1, 2), Q(1, 4)))
        self.assertFalse(phase.compatible(atlas, Q(1, 4), Q(3, 4), Q(1, 2)))
        self.assertTrue(phase.compatible(atlas, Q(1, 4), Q(3, 4), Q(3, 2)))

    def test_many_cycles_tiny_distance_and_partition_invariance(self):
        atlas = self.atlas()
        self.assertEqual(phase.sample(atlas, 7, Q(1, 4), Q(3)*10**12)[:2], (10**12+7, Q(1, 4)))
        a = phase.sample(atlas, 0, Q(1, 4), Q(1, 10**12))
        self.assertGreater(a[1], Q(1, 4))
        direct = phase.sample(atlas, 0, Q(1, 4), Q(7, 2))
        first = phase.sample(atlas, 0, Q(1, 4), Q(1))
        self.assertEqual(phase.sample(atlas, first[0], first[1], Q(5, 2)), direct)

    def test_malformed_atlas_rejects_atomically(self):
        for key, value in [('version', 2), ('input_sha256', 'bad'), ('clip_seconds', float('nan'))]:
            bad = self.atlas(); bad[key] = value
            with self.assertRaises(ValueError):
                phase.validate_atlas(bad)
        for change in [{'distance_num': 0}, {'phase_den': -1}, {'phase_num': True},
                       {'phase_num': 2, 'phase_den': 4}, {'extra': 1}, {'phase_num': 2**53}]:
            bad = self.atlas(); bad['knots'][1].update(change)
            with self.assertRaises(ValueError):
                phase.validate_atlas(bad)
        for cycle, p, d in [(-1, Q(0), Q(0)), (0, Q(1), Q(0)), (0, Q(0), Q(-1))]:
            with self.assertRaises(ValueError):
                phase.sample(self.atlas(), cycle, p, d)

    def test_inner_and_outer_sqrt_intervals_are_not_interchanged(self):
        # Units here are integers. sqrt(5**2-3**2) is exactly 4.
        self.assertEqual(phase.allowed_distance(5, 3, 3, -10, -10, inner=True), (6, 14))
        self.assertEqual(phase.allowed_distance(5, 3, 3, -10, -10, inner=False), (6, 14))
        self.assertEqual(phase.allowed_distance(5, 0, 3, -11, -9, inner=True), (7, 13))
        self.assertEqual(phase.allowed_distance(5, 0, 3, -11, -9, inner=False), (4, 16))
        self.assertIsNone(phase.allowed_distance(2, 3, 4, -10, -9, inner=False))
        # Inner failure from uncertainty is not an impossibility proof.
        self.assertIsNone(phase.allowed_distance(2, -3, 3, -10, -9, inner=True))
        self.assertIsNotNone(phase.allowed_distance(2, -3, 3, -10, -9, inner=False))

    def test_pr229_incompatible_simultaneous_hooves_finite_E(self):
        # Grid=100: d in [.18,.22] and [.28,.32], at E=.02.
        rows = [(0, 1, 0, 0, -20, -20), (0, 1, 0, 0, -30, -30)]
        self.assertIsNone(phase.feasible(2, rows, 2, [1], inner=False))
        self.assertIsNotNone(phase.feasible(2, rows, 5, [1], inner=True))

    def test_difference_constraints_detect_nonlocal_negative_cycle(self):
        rows = [(0, 1, 0, 0, -10, -10), (1, 2, 0, 0, -10, -10),
                (0, 2, 0, 0, -25, -25)]
        self.assertIsNone(phase.feasible(3, rows, 0, [1, 1], inner=False))
        self.assertEqual(phase.feasible(3, rows[:2], 0, [1, 1], inner=True), [0, 10, 20])

    def test_endpoint_obstruction_applies_to_every_scalar_map(self):
        result = phase.endpoint_floor([Q(3, 100), Q(4, 100), Q(-1)])
        self.assertEqual(result['entry_drift_xz'], (Q(3, 100), Q(3, 100)))
        self.assertEqual(result['free_anchor_xz'], (Q(3, 200), Q(3, 200)))
        self.assertEqual(result['entry_drift_xyz'], (Q(1, 20), Q(1, 20)))

    def test_exact_raw_mixed_skin_and_carried_birth_anchor(self):
        identity = np.eye(4)
        bind = [identity.copy(), identity.copy()]
        globals_ = [identity.copy(), identity.copy()]; globals_[1][0, 3] = .04
        p = phase.exact_vertex([0, 0, 0], [0, 1, 0, 0], [.75, .25, 0, 0], globals_, bind)
        self.assertEqual(p[0], Q(.04)/4)
        # Original birth differs, despite identical current hoof frame/pose.
        self.assertEqual(p[0]-Q(0), Q(.04)/4)
        self.assertEqual(p[0]-p[0], 0)
        self.assertEqual((p[0]-Q(.1))-(Q(0)-Q(.1)), p[0])
        p = phase.exact_vertex([2, 0, 0], [0, 1, 0, 0], [.5, .25, 0, 0], globals_, bind)
        self.assertEqual(p[0], Q(3, 2)+Q(.04)/4)

    def test_search_box_includes_epsilon_early_key_and_terminal_seam(self):
        track = {'type': 1, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0]}, {'time': .5, 'value': [1, 0, 0]},
            {'time': 1., 'value': [0, 0, 0]}]}
        for lo, hi in [(0., 1.), (.499989999, .500000001), (.99998, 1.)]:
            box = phase.track_span_box(track, lo, hi, 1., {}, phase.Budget())
            for t in np.linspace(lo, hi, 101):
                self.assertTrue(box.contains(capture.native_track_box(track, float(t), 1., {}).lo).all())

    def test_continuous_slerp_exhaustion_records_actual_float32_state_domain(self):
        track = {'type': 2, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0, 1]}, {'time': 1., 'value': [0, 0, 1, 0]}]}
        with self.assertRaises(phase.Unclosed) as caught:
            phase.track_span_box(track, 0., .5, 1., capture.system_math(), phase.Budget(weight_values=2))
        self.assertGreater(caught.exception.detail['required_weight_values'], 2)
        self.assertIn('weight_bits', caught.exception.detail)

    def test_continuous_slerp_small_float_domain_contains_native_points(self):
        track = {'type': 2, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0, 1]}, {'time': 1., 'value': [0, 0, 1, 0]}]}
        lo = float(np.float32(.5)); hi = float(np.nextafter(np.float32(.5), np.float32(1)))
        functions = capture.system_math()
        box = phase.track_span_box(track, lo, hi, 1., functions, phase.Budget(weight_values=100))
        for t in np.linspace(lo, hi, 9):
            self.assertTrue(box.contains(capture.native_track_box(track, float(t), 1., functions).lo).all())

    def test_continuous_full_fk_and_raw_skin_linear_hand_case(self):
        native = {'length': 1., 'bones': [{'name': 'root', 'parent': -1, 'default_position': [0, 0, 0],
                  'rest': np.eye(4)[:3].ravel().tolist(), 'default_rotation': [0, 0, 0, 1],
                  'default_scale': [1, 1, 1]}], 'tracks': [{'path': 'Rig:root', 'type': 1,
                  'interpolation': 1, 'keys': [{'time': 0., 'value': [0, 0, 0]},
                                               {'time': 1., 'value': [2, 0, 0]}]}]}
        surface = {'vertices': [[2, 0, 0]], 'joints': [[0, 0, 0, 0]], 'weights': [[.75, 0, 0, 0]]}
        box = phase.surface_span_box(native, surface, [np.eye(4)], 0., 1., {}, phase.Budget())
        self.assertTrue(box.contains([[1.5, 0, 0]]).all())
        self.assertTrue(box.contains([[3, 0, 0]]).all())
        self.assertLess(float(box.hi[0, 0]), 3.001)

    def test_uncertain_mixer_norm_reports_the_actual_quaternion_box(self):
        f = capture.Float32Box
        with self.assertRaises(phase.Unclosed) as caught:
            phase.mixer_span_box([0, 0, 0, 1], f([-1, -1, -1, -1], [1, 1, 1, 1]))
        self.assertEqual(caught.exception.detail['reason'], 'mixer_quaternion_norm_contains_zero')
        self.assertLessEqual(caught.exception.detail['norm_squared_interval'][0], 0)
        self.assertIn('quaternion_interval', caught.exception.detail)

    def test_quaternion_sign_branch_does_not_create_a_zero_basis(self):
        f = capture.Float32Box
        q = f([-1, 0, 0, -1e-8], [-1, 0, 0, 1e-8])
        mixed = phase.mixer_span_box([0, 0, 0, 1], q)
        box = phase.basis_span_box(f([0, 0, 0]), mixed, [1, 1, 1])
        for w in [-1e-8, 0, 1e-8]:
            matrix = capture.trs([0, 0, 0], [-1, 0, 0, w], [1, 1, 1])[:3]
            self.assertTrue(box.contains(matrix).all())

    def test_closed_subset_metrics_keep_birth_drift_and_full_gear(self):
        f = capture.Float32Box
        closed = [{'seconds': [0., .5], 'vertex_bounds': f([[0, 0, 0], [4, 0, 0]])}]
        patches = {'hoof': {'native_sole_vertices': [0]}}
        records, diameter, world = phase.closed_metrics(closed, self.atlas(), patches,
            {'hoof': (Q(0), Q(1))}, {'hoof': f([[0, 0, 0]])}, np.array([True, False]), 2.)
        self.assertGreaterEqual(records[0]['entry_drift_upper_m']['hoof'], 3.)
        self.assertGreaterEqual(records[0]['all_mesh_sphere_upper_model_m'], 4.)
        self.assertLess(records[0]['body_sphere_upper_model_m'], .001)
        self.assertGreaterEqual(diameter['hoof'], 3.)
        self.assertIsNotNone(world)

    def test_near_linear_slerp_threshold_uses_rounded_subtraction(self):
        c = float(np.float32(1)-np.float32(1e-5))
        track = {'type': 2, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0, 1]},
            {'time': 1., 'value': [math.sqrt(1-c*c), 0, 0, c]}]}
        lo, hi = .5, float(np.nextafter(np.float32(.5), np.float32(1)))
        functions = capture.system_math()
        box = phase.track_span_box(track, lo, hi, 1., functions, phase.Budget(weight_values=100))
        self.assertTrue(box.contains(capture.native_track_box(track, lo, 1., functions).lo).all())

    def test_partition_cannot_drop_an_unclosed_span_or_double_count_it(self):
        closed = [{'seconds': [0., .25]}]
        pending = [{'seconds': [.25, 1.]}]
        phase.verify_partition(closed, pending, 1.)
        for bad in [[{'seconds': [.3, 1.]}], [{'seconds': [.2, 1.]}], []]:
            with self.assertRaises(ValueError):
                phase.verify_partition(closed, bad, 1.)

    def test_native_capture_violation_retains_its_exact_box_as_unknown(self):
        boxes = [{'seconds': [0., .5]}, {'seconds': [.5, 1.]}]
        comparison = [{'seconds': .25, 'violated_boxes': [{'seconds': [0., .5], 'vertex_components': [[7, 2]]}]}]
        closed, failed = phase.reject_captured_boxes(boxes, comparison)
        self.assertEqual(closed, [boxes[1]])
        self.assertEqual(failed[0]['seconds'], [0., .5])
        self.assertEqual(failed[0]['native_captures'][0]['vertex_components'], [[7, 2]])
        phase.verify_partition(closed, failed, 1.)

    def test_diagnostic_report_rejects_success_claim_or_changed_coefficients(self):
        report = {'version': 1, 'status': 'DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY', 'atlas': self.atlas(),
                  'claims': {'success_dependency': False, 'verified_physical_candidate': False,
                             'policy_E': None, 'phase_runtime_unblocked': False, 'surface_unblocked': False,
                             'contact_certificate': False, 'original_12_gates_preserved': True},
                  'continuous_native': {'closed_boxes': [], 'unclosed_boxes': [{'seconds': [0., .5]}]},
                  'missing_physical_context': [{'missing_input': 'actual terrain'}]}
        report['atlas_sha256'] = phase.canonical_digest(report['atlas'])
        phase.validate_diagnostic(report)
        for key in ['success_dependency', 'verified_physical_candidate', 'surface_unblocked']:
            bad = copy.deepcopy(report); bad['claims'][key] = True
            with self.assertRaises(ValueError):
                phase.validate_diagnostic(bad)
        bad = copy.deepcopy(report); bad['atlas']['knots'][1]['distance_num'] += 1
        with self.assertRaises(ValueError):
            phase.validate_diagnostic(bad)

    def test_triangle_area_and_flip_are_checked_without_ground_substitution(self):
        f = capture.Float32Box
        triangle = f([[[0, 0, 0], [1, 0, 0], [0, 0, 1]]])
        result = phase.triangle_shape(triangle, triangle)
        self.assertEqual(result['unclosed_area_or_orientation'], [])
        self.assertGreater(result['min_twice_area_lower_m2'], .99)
        flipped = f([[[0, 0, 0], [0, 0, 1], [1, 0, 0]]])
        self.assertEqual(phase.triangle_shape(flipped, triangle)['opposite_orientation'], [0])
        collapsed = f([[[0, 0, 0], [0, 0, 0], [0, 0, 0]]])
        self.assertEqual(phase.triangle_shape(collapsed, triangle)['unclosed_area_or_orientation'], [0])

    def test_input_binding_rejects_tamper_without_relabelling_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'native.json'; p.write_text('{"x":1}')
            digest = capture.sha256(p); p.write_text('{"x":2}')
            with self.assertRaises(ValueError):
                capture.read_bound(p, digest)


class CorrelatedTriangleTests(unittest.TestCase):
    def surface(self, vertices=None, weights=None, joints=None):
        return {'vertices': vertices or [[0., 0., 0.], [1., 0., 0.], [0., 1., 0.]],
                'joints': joints or [[0, 0, 0, 0]]*3,
                'weights': weights or [[1., 0., 0., 0.]]*3}

    def span(self, surface, translation=(-10., 10.)):
        native = {'length': 1., 'bones': [{'name': 'root', 'parent': -1,
            'default_position': [0, 0, 0], 'rest': np.eye(4)[:3].ravel().tolist(),
            'default_rotation': [0, 0, 0, 1], 'default_scale': [1, 1, 1]}],
            'tracks': [{'path': 'Rig:root', 'type': 1, 'interpolation': 1, 'keys': [
                {'time': 0., 'value': [translation[0], 0, 0]},
                {'time': 1., 'value': [translation[1], 0, 0]}]}]}
        return phase.surface_span_box(native, surface, [np.eye(4)], 0., .99999, {}, phase.Budget())

    def test_shared_translation_closes_integrated_shape_where_vertex_boxes_cannot(self):
        # Losing a common transform before edge subtraction recreates this failure.
        box = self.span(self.surface())
        atlas = phase.make_atlas([Q(0), Q(1)], [Q(0), Q(1)], '0'*64, 1.)
        patches = {'hoof': {'native_sole_vertices': [0, 1, 2],
            'native_triangles': [[0, 1, 2]], 'native_sole_triangles': [7]}}
        records, _, _ = phase.closed_metrics([{'seconds': [0., .99999], 'vertex_bounds': box}],
            atlas, patches, {'hoof': (Q(0), Q(1))}, {'hoof': self.span(self.surface(), (0., 0.))},
            np.ones(3, dtype=bool), 1.)
        shape = records[0]['triangle_shape']['hoof']
        self.assertEqual(shape['unclosed_area_or_orientation'], [])
        self.assertGreater(shape['min_twice_area_lower_m2'], .99)
        self.assertEqual(phase.triangle_shape(box[np.array([[0, 1, 2]])],
            capture.Float32Box([self.surface()['vertices']]))['unclosed_area_or_orientation'], [0])

    def test_unequal_raw_weights_retain_translation_and_actual_collapse(self):
        surface = self.surface(weights=[[.9, 0, 0, 0], [1., 0, 0, 0], [1., 0, 0, 0]])
        box = self.span(surface, (-11., -9.))
        self.assertTrue(hasattr(box, 'skin_contexts'), 'shared native skin context is missing')
        proof = phase.correlated_triangle(box, surface, [0, 1, 2])
        self.assertLessEqual(proof['twice_area_interval'][0], 0)
        self.assertNotEqual(proof['edge_coefficients'][0][0]['homogeneous'][3], 0)
        # x1-x0=1 + (1-.9)*T vanishes at T=-1/(1-.9).
        self.assertLess(proof['edges'][0]['interval'][0][0], 0)
        self.assertGreater(proof['edges'][0]['interval'][1][0], 0)


    def test_native_rounding_residual_and_stale_matrix_certificate_cannot_be_dropped(self):
        box = self.span(self.surface())
        proof = phase.correlated_triangle(box, self.surface(), [0, 1, 2])
        self.assertTrue(all(e > 0 for row in proof['branches'][0]['vertex_native_residual_absolute'] for e in row))
        # A certificate must bind its values, rather than alias the mutable arrays.
        box.skin_contexts[0]['transforms'].lo[0, 0, 0] = 0.
        with self.assertRaisesRegex(ValueError, 'Stale shared skin'):
            phase.correlated_triangle(box, self.surface(), [0, 1, 2])

    def test_duplicate_slots_and_nonunit_factors_keep_exact_coefficients(self):
        surface = self.surface(weights=[[.25, .5, 0, 0]]*3)
        proof = phase.correlated_triangle(self.span(surface), surface, [0, 1, 2])
        self.assertEqual(proof['edge_coefficients'][0], [{'bind_index': 0,
            'homogeneous': (Q(3, 4), Q(0), Q(0), Q(0))}])
        self.assertGreater(proof['twice_area_interval'][0], .56)
        self.assertLess(proof['twice_area_interval'][1], .57)
        altered = copy.deepcopy(surface); altered['weights'][1] = [.25, .4, 0, 0]
        with self.assertRaisesRegex(ValueError, 'Source/bind/raw'):
            phase.correlated_triangle(self.span(surface), altered, [0, 1, 2])

    def test_collinear_thin_reversed_and_rotated_faces_keep_original_metric(self):
        for height, nondegenerate in [(0., False), (1e-3, True)]:
            surface = self.surface(vertices=[[0, 0, 0], [1, 0, 0], [0, height, 0]])
            box = self.span(surface, (0., 0.))
            shape = phase.correlated_shape(box, box, [[0, 1, 2]])
            self.assertEqual(not shape['unclosed_area_or_orientation'], nondegenerate)
        surface = self.surface(); now = self.span(surface, (0., 0.))
        reversed_ = self.surface(vertices=[[0, 0, 0], [0, 1, 0], [1, 0, 0]])
        shape = phase.correlated_shape(self.span(reversed_, (0., 0.)), now, [[0, 1, 2]])
        self.assertEqual(shape['opposite_orientation'], [0])
        # A rigid 180-degree rotation preserves area but reverses this fixed dot.
        rotated = self.surface(vertices=[[0, 0, 0], [-1, 0, 0], [0, 1, 0]])
        shape = phase.correlated_shape(self.span(rotated, (0., 0.)), now, [[0, 1, 2]])
        self.assertGreater(shape['min_twice_area_lower_m2'], .99)
        self.assertEqual(shape['opposite_orientation'], [0])


    def test_certificate_replay_rejects_dropped_error_influences_and_forged_correlation(self):
        box = self.span(self.surface())
        proof = phase.json_value(phase.correlated_triangle(box, self.surface(), [0, 1, 2]))
        certificates = {c['sha256']: phase.json_value(c['identity']) for c in box.skin_contexts}
        self.assertTrue(hasattr(phase, 'validate_shape_certificate'), 'shape proof replay is missing')
        phase.validate_shape_certificate(proof, certificates)
        mutations = [lambda p: p['branches'][0]['vertex_native_residual_absolute'][0].__setitem__(0, [0, 1]),
            lambda p: p['edge_coefficients'][0][0]['homogeneous'].__setitem__(0, [0, 1]),
            lambda p: p['raw_vertices_joints_weights'][0][2].__setitem__(0, 0.),
            lambda p: p['shared_transform_certificates'].__setitem__(0, '0'*64),
            lambda p: p['cross_interval'][0].__setitem__(2, .5),
            lambda p: p['twice_area_interval'].__setitem__(0, 2.)]
        for mutate in mutations:
            bad = copy.deepcopy(proof); mutate(bad)
            with self.subTest(mutation=mutations.index(mutate)), self.assertRaises(ValueError):
                phase.validate_shape_certificate(bad, certificates)


    def test_ftz_input_loss_is_bounded_before_large_vertex_multiplication(self):
        surface = self.surface(vertices=[[2.**20, 0, 0], [0, 1, 0], [0, 0, 1]])
        transforms = np.eye(4)[:3].reshape(1, 3, 4)
        transforms[0, 0, 0] = 2.**-127
        context = phase.skin_context(capture.Float32Box(transforms), surface, [np.eye(4)], 0., 0.)
        # A subnormal matrix operand can flush to zero before multiplying 2^20.
        self.assertGreaterEqual(phase.skin_vertex_residual(context, 0)[0], Q(2)**-107)


    def test_actual_cross_refutation_catches_changed_native_vertex(self):
        surface = self.surface(); box = self.span(surface, (0., 0.))
        proof = phase.correlated_triangle(box, surface, [0, 1, 2])
        self.assertTrue(hasattr(phase, 'shape_refutation'), 'actual cross refutation is missing')
        self.assertEqual(phase.shape_refutation([proof], surface['vertices'], [[0, 1, 2]]), [])
        self.assertEqual(phase.shape_refutation([proof], [[0, 0, 0], [2, 0, 0], [0, 1, 0]], [[0, 1, 2]]), [0])


    def test_mixed_bind_coefficients_keep_parent_translation_dependencies_and_native_rounding(self):
        surface = self.surface(weights=[[.75, .25, 0, 0], [.5, .5, 0, 0], [.25, .75, 0, 0]],
            joints=[[0, 1, 0, 0]]*3)
        transforms = np.tile(np.eye(4)[:3], (2, 1, 1)); transforms[1, 2, 3] = 1.
        lo, hi = transforms.copy(), transforms.copy(); lo[:, 0, 3] = -10.; hi[:, 0, 3] = 10.
        ctx = phase.skin_context(capture.Float32Box(lo, hi), surface, [np.eye(4)]*2, 0., 1.)
        box = phase.SkinSpan(capture.Float32Box(np.zeros((3, 3))), [ctx])
        proof = phase.correlated_triangle(box, surface, [0, 1, 2])
        self.assertEqual([r['homogeneous'][3] for r in proof['edge_coefficients'][0]], [Q(-1, 4), Q(1, 4)])
        for translation in [-10., .1, 10.]:
            actual = transforms.astype(np.float32); actual[:, 0, 3] = translation
            points = []
            for vertex, joints, weights in zip(surface['vertices'], surface['joints'], surface['weights']):
                value = np.zeros(3, dtype=np.float32)
                for joint, weight in zip(joints, weights):
                    matrix = actual[joint]; v = np.asarray(vertex, dtype=np.float32)
                    point = matrix[:, 0]*v[0]
                    point = point+matrix[:, 1]*v[1]; point = point+matrix[:, 2]*v[2]
                    point = point+matrix[:, 3]
                    value = value+point*np.float32(weight)
                points.append(value)
            self.assertEqual(phase.shape_refutation([proof], points, [[0, 1, 2]]), [])
        self.assertTrue(capture.Float32Box(*proof['cross_interval']).contains([-.25, -.5, 1.]).all())



class ShapeRefinementTests(unittest.TestCase):
    def parent_children(self):
        # n=(1,2t,0), then n=(2-2t,1,0); each closed half has area^2 >= 1.
        def proof(cross, area):
            return {'cross_interval': cross, 'twice_area_interval': area}
        parent_proof = proof([[0., 0., 0.], [1., 1., 0.]], [0., 2.])
        anchor = {'original_birth': 'unchanged support start'}
        def row(seconds, current, dot):
            return {'seconds': seconds, 'triangle_area': {'hoof': {'native_triangle_ids': [7],
                'certificates': [current], 'unclosed_area': [0] if current['twice_area_interval'][0] <= 0 else []}},
                'triangle_shape': {'hoof': {'native_triangle_ids': [7], 'certificates': [
                    {'current': current, 'birth': anchor, 'orientation_interval': dot}],
                    'unclosed_area_or_orientation': [0] if min(current['twice_area_interval'][0], dot[0]) <= 0 else []}}}
        parent = row([0., 1.], parent_proof, [0., 2.])
        children = [row([0., .5], proof([[1., 0., 0.], [1., 1., 0.]], [1., 2.]), [1., 2.]),
                    row([.5, 1.], proof([[0., 1., 0.], [1., 1., 0.]], [1., 2.]), [1., 2.])]
        return parent, children

    def test_childwise_minimum_keeps_area_and_original_birth_dot(self):
        parent, children = self.parent_children()
        for child in children:
            lo, hi = child['triangle_area']['hoof']['certificates'][0]['cross_interval']
            exact_area_squared_lower = sum(Q(0) if a <= 0 <= b else min(Q(a)**2, Q(b)**2) for a, b in zip(lo, hi))
            self.assertEqual(exact_area_squared_lower, 1)
            self.assertEqual(sum(Q(a) for a in lo[:2]), 1)  # original n_birth=(1,1,0)
        result = phase.aggregate_refined_shape(parent, children)
        self.assertEqual(result['area_targets'][0]['child_lower_bounds'], [1., 1.])
        self.assertEqual(result['area_targets'][0]['lower_bound'], 1.)
        self.assertEqual(result['birth_targets'][0]['dot_lower_bound'], 1.)
        self.assertEqual(result['birth_targets'][0]['outcome'], 'CLOSED')
        self.assertEqual(parent['triangle_area']['hoof']['certificates'][0]['twice_area_interval'][0], 0.)

    def test_zero_shared_midpoint_or_nonpositive_dot_cannot_close(self):
        for area, dot in [(0., 1.), (1., 0.), (1., -1.)]:
            parent, children = self.parent_children()
            children[1]['triangle_area']['hoof']['certificates'][0]['twice_area_interval'][0] = area
            children[1]['triangle_shape']['hoof']['certificates'][0]['orientation_interval'][0] = dot
            result = phase.aggregate_refined_shape(parent, children)
            self.assertEqual(result['birth_targets'][0]['outcome'], 'UNKNOWN')

    def test_exact_closed_partition_and_original_anchor_face_required(self):
        for mutate in [lambda c: c.pop(), lambda c: c[0]['seconds'].__setitem__(1, .4),
                lambda c: c[1]['seconds'].__setitem__(0, .4),
                lambda c: c[1]['triangle_shape']['hoof']['certificates'][0].update(birth={'new': 'anchor'}),
                lambda c: c[1]['triangle_area']['hoof'].update(native_triangle_ids=[8])]:
            parent, children = self.parent_children(); mutate(children)
            with self.assertRaises(ValueError):
                phase.aggregate_refined_shape(parent, children)

    def test_failed_child_retains_unknown_and_original_closed_fallback(self):
        parent, children = self.parent_children()
        children[1] = {'seconds': [.5, 1.], 'reason': 'normalization_unclosed'}
        result = phase.aggregate_refined_shape(parent, children)
        self.assertEqual(result['birth_targets'][0]['outcome'], 'UNKNOWN')
        self.assertIn('normalization_unclosed', result['birth_targets'][0]['reasons'])
        parent['triangle_area']['hoof']['certificates'][0]['twice_area_interval'][0] = .25
        parent['triangle_shape']['hoof']['certificates'][0]['orientation_interval'][0] = .5
        result = phase.aggregate_refined_shape(parent, children)
        self.assertEqual(result['area_targets'][0]['lower_bound'], .25)
        self.assertEqual(result['birth_targets'][0]['outcome'], 'CLOSED')

    def test_two_enclosures_share_counters_including_failed_work(self):
        surface = CorrelatedTriangleTests().surface()
        native = {'length': 1., 'bones': [{'name': 'root', 'parent': -1,
            'default_position': [0, 0, 0], 'rest': np.eye(4)[:3].ravel().tolist(),
            'default_rotation': [0, 0, 0, 1], 'default_scale': [1, 1, 1]}], 'tracks': []}
        patches = {'hoof': {'native_sole_vertices': [0, 1, 2], 'native_triangles': [[0, 1, 2]], 'native_sole_triangles': [7]}}
        f = phase.surface_span_box
        birth = f(native, surface, [np.eye(4)], 0., 0., {}, phase.Budget())
        a, b = phase.REFINEMENT_PARENT
        box = f(native, surface, [np.eye(4)], a, b, {}, phase.Budget())
        proof = phase.correlated_triangle(box, surface, [0, 1, 2])
        parent = {'seconds': [a, b], 'triangle_area': {'hoof': {'native_triangle_ids': [7], 'certificates': [proof]}},
            'triangle_shape': {'hoof': {**phase.correlated_shape(box, birth, [[0, 1, 2]]), 'native_triangle_ids': [7]}}}
        from types import SimpleNamespace
        for fail in (False, True):
            budget = phase.Budget(used=1118, arithmetic=SimpleNamespace(work={'basic_interval_operations': 10}))
            used = {'attempts': 40, 'refinement_splits': 0, 'proposal_evaluations': 323,
                'float32_weight_values': 1118, 'independent_track_evaluations': 120,
                'scalar_composition': {'basic_interval_operations': 10}, 'quaternion_norm': {},
                'correlated_triangles': {'cross_refutation_faces': 0}}
            calls = []
            def enclosure(c, s, binds, lo, hi, funcs, shared):
                self.assertIs(shared, budget); calls.append([lo, hi])
                shared.used += 1; shared.arithmetic.work['basic_interval_operations'] += 2
                if fail and len(calls) == 1:
                    raise phase.Unclosed('test_nonpositive_denominator')
                return f(c, s, binds, lo, hi, funcs, shared)
            matrices = {}
            with patch.object(phase, 'surface_span_box', enclosure):
                result = phase.refine_selected_shape(native, surface, [np.eye(4)], {}, budget, used,
                    parent, patches, {'hoof': birth}, [], matrices)
            self.assertEqual(calls, [[a, (a+b)/2], [(a+b)/2, b]])
            self.assertEqual((used['attempts'], used['refinement_splits']), (42, 1))
            self.assertEqual(used['proposal_evaluations'], 326 if fail else 329)
            self.assertEqual(used['float32_weight_values'], 1120)
            self.assertEqual(used['scalar_composition']['basic_interval_operations'], 14)
            self.assertEqual(result['work_before']['proposal_evaluations'], 323)
            self.assertEqual(used['correlated_triangles']['child_area_targets'], 1 if fail else 2)
            self.assertEqual(used['correlated_triangles']['child_birth_orientation_targets'], 1 if fail else 2)
            if not fail:
                for child in result['children']:
                    self.assertEqual(child['triangle_shape']['hoof']['certificates'][0]['birth'],
                                     parent['triangle_shape']['hoof']['certificates'][0]['birth'])
            # No budget is reset or enclosure attempted once the shared limit cannot fit both children.
            with patch.object(phase, 'surface_span_box', side_effect=AssertionError('must not evaluate')):
                used['attempts'] = phase.LIMITS['continuous_boxes']-1
                with self.assertRaisesRegex(ValueError, 'shared budget exhausted'):
                    phase.refine_selected_shape(native, surface, [np.eye(4)], {}, budget, used,
                        parent, patches, {'hoof': birth}, [], matrices)

    def test_raw_weights_face_and_missing_child_certificate_cannot_be_aggregated(self):
        for mutation in [lambda p: p.update(raw_vertices_joints_weights=[['altered']]),
                lambda p: p.update(vertex_ids=[2, 1, 0]), lambda p: p.clear()]:
            parent, children = self.parent_children()
            mutation(children[1]['triangle_area']['hoof']['certificates'][0])
            with self.assertRaises((ValueError, KeyError)):
                phase.aggregate_refined_shape(parent, children)

    def test_partial_refinement_mode_fails_before_opening_accepted_inputs(self):
        with patch.object(phase, 'load_inputs', side_effect=AssertionError('must not load native')):
            with self.assertRaisesRegex(ValueError, 'Shape refinement requires accepted arithmetic mode'):
                phase.build(Path('/unused'), triangle_baseline_report=Path('/unused'))


class FiniteAcosTests(unittest.TestCase):
    @staticmethod
    def directed(x, precision, upper):
        # Independent IEEE normal-number rounding by integer significand division.
        exponent = x.numerator.bit_length()-x.denominator.bit_length()
        if x < Q(2)**exponent:
            exponent -= 1
        unit = Q(2)**(exponent-precision+1)
        significand = x/unit
        n, remainder = divmod(significand.numerator, significand.denominator)
        return (n+bool(upper and remainder))*unit

    @classmethod
    def walk(cls, cosine, coefficients):
        t = 1-cosine
        point = lambda x: (x, x)
        def rounded(pair, precision=53):
            return cls.directed(pair[0], precision, False), cls.directed(pair[1], precision, True)
        def fma(a, b, c):
            values = [x*y+z for x in a for y in b for z in c]
            return rounded((min(values), max(values)))
        # Independent finer integer sqrt bracket, then actual directed binary64 grid.
        denominator = 2**160
        n = math.isqrt(t.numerator*denominator**2//t.denominator)
        root = rounded((Q(n, denominator), Q(n+1, denominator)))
        a, b, d = [fma(point(t), point(coefficients[i]), point(coefficients[i+1])) for i in (0, 2, 4)]
        square = rounded(point(t*t))
        h = fma(square, fma(square, a, b), d)
        product = rounded((root[0]*h[0], root[1]*h[1]))
        return rounded(product, 24)

    def test_six_exact_words_control_flow_sqrt_and_all_direction_results(self):
        profile = phase.scalar.MAC_PROFILE['acosf']
        coefficients = [Q(x) for x in struct.unpack('<6d', bytes.fromhex(profile['code'])[-48:])]
        expected_t = [2038333, 2038332, 2038331, 1988572, 1988571, 1988570]
        words = [w for group in phase.ACOS_WORDS.values() for w in group]
        for word, numerator in zip(words, expected_t):
            r = phase.finite_acos_constant(profile, word, {})
            c = Q(int(word, 16)&0x7fffff | 0x800000, 2**24)
            self.assertEqual(r['input_rational'], c)
            self.assertEqual(r['sterbenz_t'], Q(numerator, 2**24))
            self.assertTrue(Q(1, 2) < c < 1)
            lo, hi = r['sqrt_rational_bracket']
            self.assertTrue(lo*lo <= 1-c <= hi*hi)
            self.assertLessEqual(hi-lo, Q(1, 2**96))
            independent = self.walk(c, coefficients)
            self.assertLessEqual(r['omega_interval'][0], independent[0])
            self.assertGreaterEqual(r['omega_interval'][1], independent[1])
            self.assertTrue(0 < r['omega_interval'][0] < r['omega_interval'][1] < Q(1, 2))
            self.assertEqual([n['pc'] for n in r['nodes']],
                ['0xbb98', '0xbb9c', '0xbba0', '0xbba4', '0xbba8', '0xbbac', '0xbbb0', '0xbbc8', '0xbbcc'])
            # A host value is a refutation control only.
            observed = Q(np.float32(math.acos(float(c))).item())
            self.assertLessEqual(r['omega_interval'][0], observed)
            self.assertGreaterEqual(r['omega_interval'][1], observed)

    def test_actual_aarch64_branch_targets_and_fma_register_equations(self):
        profile = phase.scalar.MAC_PROFILE['acosf']
        def instruction(pc):
            return int.from_bytes(phase.scalar.read_memory(profile, pc, 4), 'little')
        # B.cond uses the existing NZCV flags; intervening FMOV/LDR do not set them.
        for pc, condition, target in [(0xbb4c, 5, 0xbc24), (0xbb58, 12, 0xbb7c), (0xbbb8, 12, 0xbbc8)]:
            word = instruction(pc)
            self.assertEqual(word & 0xff000010, 0x54000000)
            self.assertEqual(word & 15, condition)
            displacement = (word >> 5) & 0x7ffff
            if displacement & 0x40000:
                displacement -= 0x80000
            self.assertEqual(pc+4*displacement, target)
        # FMADD Dd,Dn,Dm,Da: one rounding, no intermediate product rounding.
        for pc, registers in [(0xbb9c, (3, 1, 2, 3)), (0xbba0, (5, 1, 4, 5)),
                              (0xbba4, (7, 1, 6, 7)), (0xbbac, (5, 2, 3, 5)), (0xbbb0, (7, 2, 5, 7))]:
            word = instruction(pc)
            self.assertEqual(word & 0xffe08000, 0x1f400000)
            self.assertEqual((word & 31, (word >> 5) & 31, (word >> 16) & 31, (word >> 10) & 31), registers)
        # ADR X0 loads the six binary64 constants at PC + signed imm21.
        word = instruction(0xbb88)
        displacement = ((word >> 5) & 0x7ffff)*4+((word >> 29) & 3)
        self.assertEqual(0xbb88+displacement, 0xbc90)

    def test_fused_rounding_and_directed_conversion_hand_cases(self):
        # Exact FMA cancels to 2^-104; a separately rounded product loses it.
        a, b, c = 1+Q(1, 2**52), 1+Q(1, 2**52), -(1+Q(1, 2**51))
        exact = a*b+c
        self.assertEqual(exact, Q(1, 2**104))
        self.assertEqual(self.directed(exact, 53, False), exact)
        self.assertEqual(self.directed(a*b, 53, False)+c, 0)
        for precision in (24, 53):
            midpoint = 1+Q(1, 2**precision)
            self.assertEqual(self.directed(midpoint, precision, False), 1)
            self.assertEqual(self.directed(midpoint, precision, True), 1+Q(1, 2**(precision-1)))
        # Constant-polynomial hand case: ((2*t+3)*t^2+(4*t+5))*t^2+(6*t+7), t=1/4.
        t = Q(1, 4)
        exact = ((2*t+3)*t*t+(4*t+5))*t*t+(6*t+7)
        self.assertEqual(exact, Q(4551, 512))
        root = phase.sqrt_bounds(Q(1, 4), 2**96)
        self.assertEqual(root, (Q(1, 2), Q(1, 2)))

    def test_foreign_word_branch_coefficient_format_and_profile_reject(self):
        profile = phase.scalar.MAC_PROFILE['acosf']
        with self.assertRaisesRegex(ValueError, 'Uncovered acos constant'):
            phase.finite_acos_constant(profile, '3f60e5c2', {})
        for offset in (0x28, 0x50, 0x6c, 0x98, 0x9c, 0x160):
            changed = copy.deepcopy(profile)
            raw = bytearray.fromhex(changed['code']); raw[offset] ^= 1
            changed['code'] = raw.hex()
            with self.assertRaisesRegex(ValueError, 'profile mismatch'):
                phase.finite_acos_constant(changed, '3f60e5c3', {})
        changed = dict(profile, entry_offset=0)
        with self.assertRaisesRegex(ValueError, 'profile mismatch'):
            phase.finite_acos_constant(changed, '3f60e5c3', {})


class SlerpRangeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from royal_native_arithmetic.test_prove import fixture
        from royal_native_arithmetic import prove
        cls.capture = fixture()
        cls.receipt = prove.prove(cls.capture)
        cls.native = {'engine_executable_sha256': cls.receipt['engine_sha256'],
                      'engine': cls.capture['engine']['version'],
                      'runtime': {'double_precision': False}}
        cls.platform = {'functions': {name: {'image': '/usr/lib/system/libsystem_m.dylib',
                        'mach_o_uuid': prove.MAC_ID} for name in ('sin', 'sinf', 'acosf')}}

    def authority(self):
        self.assertTrue(hasattr(phase, 'ScalarAuthority'), 'Missing receipt-backed interval authority')
        return phase.ScalarAuthority(self.capture, self.receipt, self.native, self.platform)

    def test_sine_endpoint_range_has_exact_hand_bracket_and_native_error(self):
        authority = self.authority()
        lo, hi = authority.sine((Q(1, 2), Q(1, 2)), 'sin')
        # sin(1/2) lies strictly between these independent decimal bounds.
        self.assertLess(lo, Q('0.4794255386042029'))
        self.assertGreater(hi, Q('0.4794255386042031'))
        zero = authority.sine((Q(0), Q(0)), 'sinf')
        self.assertEqual(zero, (-Q(1, 2**22), Q(1, 2**22)))
        with self.assertRaisesRegex(phase.Unclosed, 'sine_argument_domain'):
            authority.sine((Q(-1, 2), Q(1, 2)+Q(1, 2**52)), 'sin')

    def test_receipt_identity_code_domain_and_zero_error_are_not_trusted(self):
        self.authority()
        for target, key, value in [('receipt', 'engine_sha256', 'a'*64),
                ('receipt', 'verifier_sha256', 'a'*64), ('capture', 'schema', 'other')]:
            c, r = copy.deepcopy(self.capture), copy.deepcopy(self.receipt)
            (r if target == 'receipt' else c)[key] = value
            with self.assertRaises(ValueError):
                phase.ScalarAuthority(c, r, self.native, self.platform)
        for mutate in [lambda r: r['theorems']['sin'].update(outward_absolute_error='0'),
                       lambda r: r['theorems']['acosf'].update(domain=['0', '1'])]:
            r = copy.deepcopy(self.receipt); mutate(r)
            with self.assertRaises(ValueError):
                phase.ScalarAuthority(self.capture, r, self.native, self.platform)
        c = copy.deepcopy(self.capture); c['native']['imports'][0][0]['code'] = '00'
        with self.assertRaises(ValueError):
            phase.ScalarAuthority(c, self.receipt, self.native, self.platform)
        bad_native = copy.deepcopy(self.native); bad_native['engine_executable_sha256'] = 'b'*64
        with self.assertRaises(ValueError):
            phase.ScalarAuthority(self.capture, self.receipt, bad_native, self.platform)
        bad_platform = copy.deepcopy(self.platform); bad_platform['functions']['sin']['mach_o_uuid'] = 'other'
        with self.assertRaises(ValueError):
            phase.ScalarAuthority(self.capture, self.receipt, self.native, bad_platform)

    def test_full_weight_range_and_overshoot_close_without_spending_weight_enumeration(self):
        authority = self.authority()
        track = {'path': 'Rig:root', 'type': 2, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0, 1]},
            {'time': .5, 'value': [0, 0, math.sin(.2), math.cos(.2)]}]}
        budget = phase.Budget(weight_values=0, arithmetic=authority)
        box = phase.track_span_box(track, 0., .5, .5, capture.system_math(), budget)
        self.assertEqual(budget.used, 0)
        for t in np.linspace(0, .5, 33):
            self.assertTrue(box.contains(capture.native_track_box(track, float(t), .5, capture.system_math()).lo).all())
        a, b = map(capture.Float32Box, [track['keys'][0]['value'], track['keys'][1]['value']])
        for weights in [(-.00031, .0001), (.9999, 1.00031), (.5, .50000012)]:
            w = capture.Float32Box.outward(*weights)
            interval = authority.slerp(a, b, w, 'test', 0)
            if weights == (.5, .50000012):
                self.assertLess(float(np.max(interval.hi-interval.lo)), .001)
            for value in [w.lo, (w.lo+w.hi)/2, w.hi]:
                oracle = capture.slerp_box(a, b, np.float32(value), capture.system_math())
                self.assertTrue(interval.contains(oracle.lo).all() and interval.contains(oracle.hi).all())
        self.assertGreater(authority.work['weight_interval_compositions'], 0)
        branch = authority.domains['Rig:root:0']['branches'][0]
        self.assertGreater(branch['denominator_interval'][0], Q(19, 100))
        self.assertLess(branch['denominator_interval'][1], Q(21, 100))

    def test_proof_exact_point_uses_scalar_composition_and_keeps_legacy_fit_separate(self):
        authority = self.authority()
        track = {'path': 'Rig:root', 'type': 2, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0, 1]},
            {'time': .5, 'value': [0, 0, math.sin(.2), math.cos(.2)]}]}
        functions = capture.system_math()
        legacy = phase.track_span_box(track, 0., 0., .5, functions, phase.Budget())
        self.assertLess(float(legacy.hi[3]-legacy.lo[3]), 1e-6)
        budget = phase.Budget(weight_values=0, arithmetic=authority)
        with patch.object(capture, 'native_track_box', side_effect=AssertionError('unproved point replay')):
            box = phase.track_span_box(track, 0., 0., .5, functions, budget)
        # At weight0 double sin(omega)/sinf(omega) cannot use an exact-identity shortcut.
        self.assertLess(float(box.lo[3]), .99999)
        self.assertGreater(float(box.hi[3]), 1.00001)
        self.assertEqual(budget.used, 0)
        self.assertGreater(authority.work['weight_interval_compositions'], 0)
        track['keys'][1]['value'] = [0, 0, .4794, .8785]
        with self.assertRaisesRegex(phase.Unclosed, 'acos_constant_authority_missing'):
            phase.track_span_box(track, 0., 0., .5, functions, budget)

    def test_scalar_track_certificate_preserves_sign_key_weight_and_both_hamilton_errors(self):
        authority = self.authority(); f = capture.Float32Box
        functions = capture.system_math()
        for cosine in [.95, -.95, .999999]:
            a, b = f([0, 0, 0, 1]), f([0, 0, math.sqrt(1-cosine*cosine), cosine])
            span = authority.slerp(a, b, f(-.0003, 1.0003), 'root', 7)
            self.assertIsInstance(span, phase.QuaternionSpan)
            for branch in span.branches:
                self.assertEqual(branch.certificate['identity']['track'], 'root')
                self.assertEqual(branch.certificate['identity']['key_index'], 7)
                self.assertEqual(branch.certificate['weight'], (Q(f(-.0003).lo.item()), Q(f(1.0003).lo.item())))
            mixed = phase.mixer_span_box([.1, 0, 0, 2], span)
            box = phase.basis_span_box(f([0, 0, 0]), mixed, [1, 1, 1])
            for w in np.linspace(-.0003, 1.0003, 11):
                oracle = capture.slerp_box(a, b, np.float32(w), functions)
                self.assertTrue(span.contains(oracle.lo).all() and span.contains(oracle.hi).all())
                self.assertTrue(np.isfinite(box.lo).all())
            for branch in mixed.branches:
                self.assertEqual(len(branch.certificate['hamilton_roundoff']), 2)
                self.assertGreater(phase.rounded_norm(branch, 'basis')[0][0], 0)

    def test_neighboring_key_union_keeps_certificates_until_basis(self):
        track = {'path': 'Rig:joint', 'type': 2, 'interpolation': 1, 'keys': [
            {'time': 0., 'value': [0, 0, 0, 1]},
            {'time': .5, 'value': [0, 0, .1, -.995]},
            {'time': 1., 'value': [0, 0, .2, -.98]}]}
        span = phase.track_span_box(track, .49999, .50001, 1., capture.system_math(),
                                    phase.Budget(arithmetic=self.authority()))
        self.assertEqual({b.certificate['identity']['key_index'] for b in span.branches}, {0, 1})
        self.assertEqual({b.certificate['identity']['negative'] for b in span.branches}, {False, True})
        result = phase.basis_span_box(capture.Float32Box([0, 0, 0]),
            phase.mixer_span_box([0, 0, 0, 1], span), [1, 1, 1])
        for t in np.linspace(.49999, .50001, 17):
            q = capture.native_track_box(track, float(t), 1., capture.system_math())
            for point in [q.lo, q.hi]:
                self.assertTrue(result.contains(capture.trs([0, 0, 0], point, [1, 1, 1])[:3]).all())

    def test_outside_acos_domain_never_calls_an_ideal_or_point_replacement(self):
        authority = self.authority()
        f = capture.Float32Box
        with self.assertRaisesRegex(phase.Unclosed, 'acos_constant_authority_missing') as caught:
            authority.slerp(f([0, 0, 0, 1]), f([0, 0, .4794, .8785]), f(0, 1), 'HindHoof.L', 7)
        self.assertEqual(caught.exception.detail['key_index'], 7)
        self.assertLess(caught.exception.detail['cosine_interval'][0], .9)
        self.assertTrue(caught.exception.detail['dot_states'])

    def test_denominator_zero_and_incomplete_shape_accounting_cannot_close(self):
        self.authority()
        with self.assertRaisesRegex(phase.Unclosed, 'denominator_contains_zero'):
            phase.interval_quotient((Q(0), Q(1)), (Q(-1), Q(1)), 24)
        old = {'continuous_native': {'unclosed_boxes': [], 'closed_boxes': [
            {'seconds': [0., 1.], 'triangle_shape': {'hoof': {
                'native_triangle_ids': [8], 'unclosed_area_or_orientation': [0]}}}]}}
        with self.assertRaisesRegex(ValueError, 'shape interval not completely accounted'):
            phase.baseline_accounting(old, [], [])

    def test_proof_mode_requires_complete_inputs_before_native_loading(self):
        with patch.object(phase, 'load_inputs', side_effect=AssertionError('must reject first')):
            with self.assertRaisesRegex(ValueError, 'Arithmetic capture, receipt and baseline required together'):
                phase.build(Path('/review'), arithmetic_capture=Path('/capture'))

    def test_baseline_accounting_preserves_every_old_unknown_and_shape_face(self):
        self.assertTrue(hasattr(phase, 'baseline_accounting'), 'Missing prior unknown accounting')
        old = {'continuous_native': {'unclosed_boxes': [{'seconds': [0., .5], 'reason': 'weight_budget'}],
            'closed_boxes': [{'seconds': [.5, 1.], 'triangle_shape': {'hoof': {
                'native_triangle_ids': [8, 9], 'unclosed_area_or_orientation': [1]}}}]}}
        current = [{'seconds': [0., .25], 'triangle_shape': {}},
                   {'seconds': [.5, 1.], 'triangle_shape': {'hoof': {
                    'native_triangle_ids': [8, 9], 'unclosed_area_or_orientation': [1]}}}]
        unknown = [{'seconds': [.25, .5], 'reason': 'denominator'}]
        result = phase.baseline_accounting(old, current, unknown)
        self.assertEqual(result['coordinate_boxes'][0]['closed_seconds'], [[0., .25]])
        self.assertEqual(result['coordinate_boxes'][0]['unclosed_seconds'], [[.25, .5]])
        self.assertEqual(result['shape_cases'][0]['native_triangle_id'], 9)
        self.assertEqual(result['shape_cases'][0]['outcome'], 'UNKNOWN')
        current[-1]['triangle_shape']['hoof']['unclosed_area_or_orientation'] = []
        self.assertEqual(phase.baseline_accounting(old, current, unknown)['shape_cases'][0]['outcome'], 'CLOSED')

    def test_affine_antipodal_sign_threshold_and_subnormal_rounding(self):
        authority = self.authority(); f = capture.Float32Box
        for target in [[0, 0, 0, 1], [0, 0, 0, -1]]:
            result = authority.slerp(f([0, 0, 0, 1]), f(target), f(-.0003, 1.0003), 'affine', 0)
            self.assertTrue(result.contains([0, 0, 0, 1]).all())
        c = np.float32(1)-np.float32(1e-5)
        for cosine in [np.nextafter(c, np.float32(0)), c, np.nextafter(c, np.float32(1))]:
            a, b = f([0, 0, 0, 1]), f([math.sqrt(1-float(cosine)**2), 0, 0, cosine])
            result = authority.slerp(a, b, f(.4999, .5001), 'threshold', float(cosine))
            oracle = capture.slerp_box(a, b, np.float32(.5), capture.system_math())
            self.assertTrue(result.contains(oracle.lo).all() and result.contains(oracle.hi).all())
        double = phase.interval_product((Q(1, 3), Q(1, 3)), (Q(1), Q(1)), 53)
        single = phase.interval_product((Q(1, 3), Q(1, 3)), (Q(1), Q(1)), 24)
        self.assertLess(double[1]-double[0], Q(1, 10**15))
        self.assertGreater(single[1]-single[0], Q(1, 10**8))
        lo, hi = phase.rounded_interval(Q(1, 2**149), Q(1, 2**149), 24)
        self.assertLessEqual(lo, 0); self.assertGreaterEqual(hi, Q(1, 2**149))


class QuaternionNormTests(unittest.TestCase):
    def test_shared_parameter_half_bound_survives_mixer_and_second_basis_norm(self):
        # Removing the shared weight makes the [0,1]^2 rectangle contain zero.
        span = phase.affine_quaternion([1, 0, 0, 0], [0, 1, 0, 0],
            (Q(0), Q(1)), (Q(0),)*4, {'track': 'hand', 'key_index': 0})
        self.assertEqual(span.branches[0].norm_squared, (Q(1, 2), Q(1)))
        self.assertTrue((span.lo <= 0).all() and (span.hi >= 0).all())
        mixed = phase.mixer_span_box([0, 0, 0, 1], span)
        self.assertGreater(mixed.branches[0].certificate['mixer_rounded_norm_squared'][0], 0)
        self.assertGreater(mixed.branches[0].norm_squared[0], 0)
        basis = phase.basis_span_box(capture.Float32Box([0, 0, 0]), mixed, [1, 1, 1])
        for u in np.linspace(0, 1, 17):
            self.assertTrue(basis.contains(capture.trs([0, 0, 0], [1-u, u, 0, 0], [1, 1, 1])[:3]).all())

    def test_genuine_zero_is_unknown_and_nonunit_rest_is_not_assumed_unit(self):
        zero = phase.affine_quaternion([-1, 1, 0, 0], [1, -1, 0, 0],
            (Q(0), Q(1)), (Q(0),)*4, {'track': 'zero'})
        with self.assertRaises(phase.Unclosed):
            phase.mixer_span_box([0, 0, 0, 1], zero)
        constant = phase.affine_quaternion([0, 0, 0, 2], [0, 0, 0, 2],
            (Q(-1, 100), Q(101, 100)), (Q(0),)*4, {'track': 'scaled'})
        self.assertEqual(constant.branches[0].norm_squared, (Q(4), Q(4)))
        mixed = phase.mixer_span_box([0, 0, 0, 3], constant)
        cert = mixed.branches[0].certificate
        self.assertEqual(cert['rest_squared_norm'], Q(9))
        self.assertLess(cert['mixer_real_norm_squared'][0], 324)
        self.assertGreater(cert['mixer_real_norm_squared'][1], 324)
        self.assertLess(mixed.branches[0].norm_squared[0], 1)
        self.assertGreater(mixed.branches[0].norm_squared[1], 1)

    def test_corrupt_missing_or_inconsistent_certificate_cannot_emit_pose(self):
        span = phase.affine_quaternion([1, 0, 0, 0], [0, 1, 0, 0],
            (Q(0), Q(1)), (Q(0),)*4, {'track': 'hand'})
        for mutation in [lambda b: b.certificate.update(norm_squared=(Q(1), Q(1))),
                         lambda b: b.certificate['identity'].update(track='changed'),
                         lambda b: b.certificate.update(weight=(Q(1), Q(1))),
                         lambda b: b.box.lo.fill(2)]:
            bad = copy.deepcopy(span); mutation(bad.branches[0])
            with self.assertRaises(ValueError):
                phase.mixer_span_box([0, 0, 0, 1], bad)
        bad = copy.deepcopy(span); bad.branches = ()
        with self.assertRaises(ValueError):
            phase.mixer_span_box([0, 0, 0, 1], bad)
        with self.assertRaises(ValueError):
            phase.affine_quaternion([float('nan'), 0, 0, 0], [0, 1, 0, 0],
                (Q(0), Q(1)), (Q(0),)*4, {})

    def test_inconsistent_component_and_removed_rounding_proof_reject(self):
        f = capture.Float32Box
        with self.assertRaisesRegex(ValueError, 'Inconsistent quaternion norm/component'):
            phase.affine_quaternion([1, 0, 0, 0], [0, 1, 0, 0],
                (Q(0), Q(1)), (Q(0),)*4, {}, f([0, 0, 0, 0]))
        span = phase.affine_quaternion([0, 0, 0, 1], [0, 0, 0, 1],
            (Q(0), Q(1)), (Q(0),)*4, {})
        mixed = phase.mixer_span_box([0, 0, 0, 1], span)
        for mutation in [lambda c: c.update(hamilton_roundoff=[]),
                         lambda c: c.update(mixer_dot_error=Q(0)),
                         lambda c: c.update(normalization_radial_error=Q(0)),
                         lambda c: c.update(gram=(Q(0), Q(0), Q(0)))]:
            bad = copy.deepcopy(mixed); mutation(bad.branches[0].certificate)
            with self.assertRaises(ValueError):
                phase.basis_span_box(f([0, 0, 0]), bad, [1, 1, 1])

    def test_machine_residual_changes_norm_bound_and_ftz_zero_stays_unknown(self):
        a, b, w = [1, 0, 0, 0], [0, 1, 0, 0], (Q(0), Q(1))
        exact = phase.affine_quaternion(a, b, w, (Q(0),)*4, {})
        perturbed = phase.affine_quaternion(a, b, w, (Q(1, 100),)*4, {})
        self.assertLess(perturbed.branches[0].norm_squared[0], exact.branches[0].norm_squared[0])
        tiny = phase.affine_quaternion([0, 0, 0, 2**-140], [0, 0, 0, 2**-140],
            w, (Q(2)**-126,)*4, {})
        with self.assertRaises(phase.Unclosed):
            phase.mixer_span_box([0, 0, 0, 1], tiny)


class BindingTests(unittest.TestCase):
    def test_partial_new_mode_fails_before_legacy_or_accepted_reads(self):
        for manifest, bundle in [(Path('/new'), None), (None, Path('/bundle'))]:
            with patch.object(capture, 'read_bound', side_effect=AssertionError('legacy read')):
                with self.assertRaisesRegex(ValueError, 'together'):
                    phase.load_inputs(Path('/receipt'), native_manifest=manifest, bundle_root=bundle)

    def test_new_mode_requires_receipt_and_calls_existing_acceptance_boundary(self):
        with patch.object(phase.reacquired, 'load_accepted', side_effect=ValueError('authoritative rejection')) as load:
            with self.assertRaisesRegex(ValueError, 'authoritative rejection'):
                phase.load_inputs(Path('/receipt'), native_manifest=Path('/manifest'), bundle_root=Path('/bundle'))
            load.assert_called_once_with(Path('/manifest'), Path('/bundle'), Path('/receipt'))
        with self.assertRaisesRegex(ValueError, 'receipt required'):
            phase.load_inputs(None, native_manifest=Path('/manifest'), bundle_root=Path('/bundle'))

    def report(self):
        atlas = PhaseTests().atlas()
        binding = {'kind': 'native-reacquired-v1', 'version': 1, 'manifest_sha256': 'b'*64,
                   'body_sha256': 'c'*64, 'role_sha256': {'native': 'd'*64},
                   'algorithm_sha256': {'algorithm': 'e'*64}}
        packet = {'input_binding': binding, 'data_sha256': 'f'*64}
        atlas['input_sha256'] = phase.canonical_digest(packet)
        return {'version': 2, 'step_id': 'CAV-CONTACT-PHASE-INPUT-BINDING',
                'status': 'DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY',
                'input_binding': binding, 'atlas_input_packet': packet,
                'inputs': {'manifest': 'b'*64, 'verdict_body': 'c'*64, 'role:native': 'd'*64, 'algorithm': 'e'*64},
                'atlas': atlas, 'atlas_sha256': phase.canonical_digest(atlas),
                'claims': {'success_dependency': False, 'verified_physical_candidate': False,
                           'policy_E': None, 'phase_runtime_unblocked': False, 'surface_unblocked': False,
                           'contact_certificate': False, 'original_12_gates_preserved': True},
                'continuous_native': {'closed_boxes': [], 'unclosed_boxes': [{'seconds': [0., .5]}]},
                'missing_physical_context': [{'missing_input': 'actual terrain'}]}

    def test_versioned_provenance_rejects_mixed_versions_and_stale_atlas(self):
        phase.validate_diagnostic(self.report())
        mutations = [lambda r: r.update(version=1), lambda r: r.update(version=3),
                     lambda r: r['input_binding'].update(version=2),
                     lambda r: r['input_binding'].update(kind='legacy'),
                     lambda r: r['inputs'].update(manifest='a'*64),
                     lambda r: r['inputs'].update(verdict_body='a'*64),
                     lambda r: r['inputs'].update({'role:native': 'a'*64}),
                     lambda r: r['inputs'].update(algorithm='a'*64),
                     lambda r: r['atlas_input_packet'].update(data_sha256='a'*64),
                     lambda r: r['input_binding'].update(body_sha256='a'*64)]
        for mutate in mutations:
            bad = copy.deepcopy(self.report()); mutate(bad)
            with self.subTest(mutation=mutations.index(mutate)), self.assertRaises(ValueError):
                phase.validate_diagnostic(bad)

    def test_cli_partial_flags_and_mode_mismatch_do_not_publish(self):
        import sys
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/'report.json'
            for flags in [['--native-manifest', '/manifest'], ['--bundle-root', '/bundle']]:
                with patch.object(sys, 'argv', ['phase', 'build', '--review-record', '/receipt', '--out', str(out), *flags]):
                    with patch.object(phase, 'build', side_effect=AssertionError('must reject first')):
                        self.assertEqual(phase.main(), 1)
                self.assertFalse(out.exists())
            out.write_text(json.dumps(self.report()))
            with patch.object(sys, 'argv', ['phase', 'verify', str(out), '--review-record', '/receipt']):
                with patch.object(phase, 'build', side_effect=AssertionError('must reject first')):
                    self.assertEqual(phase.main(), 1)

    def test_unavailable_acceptance_evidence_rejects_without_partial_report(self):
        import subprocess
        import sys
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/'out.json'
            with patch.object(sys, 'argv', ['phase', 'build', '--out', str(out), '--review-record', '/receipt',
                                           '--native-manifest', '/manifest', '--bundle-root', '/bundle']):
                with patch.object(phase.reacquired, 'load_accepted', side_effect=subprocess.CalledProcessError(1, 'gh')):
                    self.assertEqual(phase.main(), 1)
            self.assertFalse(out.exists())


@unittest.skipUnless(os.environ.get('CAV_PHASE_BUNDLE') and os.environ.get('CAV_PHASE_RECEIPT')
                     and os.environ.get('CAV_PHASE_SECOND_BUNDLE'), 'explicit accepted custody inputs required')
class AcceptedBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = phase.ROOT/'docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-native-reacquired.json'
        cls.receipt = Path(os.environ['CAV_PHASE_RECEIPT'])
        cls.bundles = [Path(os.environ[k]) for k in ('CAV_PHASE_BUNDLE', 'CAV_PHASE_SECOND_BUNDLE')]
        import builtins
        import io
        original_open, original_io_open = builtins.open, io.open
        def guard(opener):
            def checked(file, *args, **kwargs):
                text = str(file)
                if any(fragment in text for fragment in ['/acquisition-20261104-01/',
                    '/cluster-loco-clip-cavalry/', '/cavalry-contact-native/game_design/',
                    '/cluster-loco-cert-cavalry/game_design/']):
                    raise AssertionError('Legacy data file opened: '+text)
                return opener(file, *args, **kwargs)
            return checked
        with patch.object(builtins, 'open', guard(original_open)), patch.object(io, 'open', guard(original_io_open)):
            cls.loaded = [phase.load_inputs(cls.receipt, native_manifest=cls.manifest, bundle_root=b) for b in cls.bundles]

    def test_real_accepted_copies_have_identical_binding_and_scientific_data(self):
        a, b = self.loaded
        self.assertEqual(a[-1]['binding'], b[-1]['binding'])
        self.assertNotEqual(a[-1]['locations'], b[-1]['locations'])
        for i in (1, 2, 3, 4, 5, 7):
            self.assertEqual(phase.canonical_digest(a[i]), phase.canonical_digest(b[i]))
        self.assertEqual(len(a[1]['sample_times_seconds']), 154)
        self.assertEqual(a[-1]['binding']['role_sha256']['samples'], capture.sha256(a[-1]['roles']['samples']))
        self.assertNotEqual(a[-1]['binding']['manifest_sha256'], phase.MANIFEST_SHA)

    def test_actual_legacy_mode_remains_unavailable_without_fallback(self):
        with self.assertRaises((OSError, ValueError)):
            phase.load_inputs(self.receipt)

    def test_new_mode_keeps_actual_platform_and_installed_source_guards(self):
        accepted = {'manifest': self.loaded[0][0], 'native': self.loaded[0][1],
                    'accounting': {'patches': self.loaded[0][4]},
                    'component_result': {'numerical_accounting': {
                        'platform_math': self.loaded[0][-1]['binding']['platform_math']}}}
        with patch.object(phase.reacquired, 'load_accepted', return_value=accepted):
            with patch.object(capture, 'math_runtime_identity', return_value={'functions': {}, 'platform': 'other'}):
                with self.assertRaisesRegex(ValueError, 'platform math mismatch'):
                    phase.load_inputs(self.receipt, native_manifest=self.manifest, bundle_root=self.bundles[0])
            bad = copy.deepcopy(accepted)
            bad['native']['skin'][0]['resolved_bone'] = 52
            with patch.object(phase.reacquired, 'load_accepted', return_value=bad):
                with self.assertRaisesRegex(ValueError, 'bind mapping'):
                    phase.load_inputs(self.receipt, native_manifest=self.manifest, bundle_root=self.bundles[0])

    def test_unknown_manifest_version_and_component_overclaim_reject_before_replay(self):
        accepted = copy.deepcopy(self.loaded[0][0])
        mutations = [lambda m: m.update(version=2), lambda m: m.update(step_id='other'),
                     lambda m: m['claims'].update(physical_contact=True),
                     lambda m: m['claims'].update(phase_candidate=True),
                     lambda m: m['claims'].update(CERT=True)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'manifest.json'
            for mutate in mutations:
                bad = copy.deepcopy(accepted); mutate(bad); path.write_text(json.dumps(bad))
                with patch.object(phase.reacquired, 'portable_replay', side_effect=AssertionError('must reject first')):
                    with self.assertRaises(ValueError):
                        phase.load_inputs(self.receipt, native_manifest=path, bundle_root=self.bundles[0])

    def test_legacy_fixture_preserves_genuine_legacy_validation_branch(self):
        # Synthetic complete legacy fixture, never a fabricated acceptance of missing historical bytes.
        manifest, native, _, _, patches, _, _, witness, _ = self.loaded[0]
        legacy = {'inputs': {f'/fixture/input-{i}': '0'*64 for i in range(294)},
                  'capture_directory': '/fixture/capture', 'accounting_payload': '/fixture/accounting.json',
                  'frozen_paths': {'witness': '/fixture/witness.json'},
                  'numerical_accounting': {'platform_math': manifest['component_result']['numerical_accounting']['platform_math']}}
        actions = phase.ROOT/'tools/units3d/cavalry_rig/actions.py'
        legacy['inputs'].update({'/fixture/capture/native.json': '1'*64, '/fixture/accounting.json': '2'*64,
                                 '/fixture/witness.json': '3'*64, str(actions): capture.sha256(actions)})
        review = {'accepted': True, 'manifest_sha256': phase.MANIFEST_SHA, 'pr': {'state': 'MERGED'},
                  'review_session_id': '01a19ca8-5995-7bb2-b666-b3fbf29fb47d'}
        payloads = {str(phase.MANIFEST): legacy, '/fixture/review.json': review,
                    '/fixture/capture/native.json': native, '/fixture/accounting.json': {'patches': patches},
                    '/fixture/witness.json': witness}
        original_sha = capture.sha256
        def fixture_sha(path):
            text = str(path)
            if text in legacy['inputs']: return legacy['inputs'][text]
            if text == '/fixture/round2.md': return phase.VERDICT_SHA
            if text == '/fixture/accepted234-disposition.md':
                return 'f54da8c9105721029a0aed93dad6ecf2341ebf87cd55ec239401f6c3113db4ad'
            return original_sha(path)
        with patch.object(capture, 'read_bound', side_effect=lambda p, digest: copy.deepcopy(payloads[str(p)])), \
             patch.object(capture, 'sha256', side_effect=fixture_sha), \
             patch.object(phase.reacquired, 'load_accepted', side_effect=AssertionError('fresh fallback')):
            result = phase.load_inputs(Path('/fixture/review.json'))
            self.assertIsNone(result[-1])
            self.assertEqual(phase.canonical_digest(result[1]), phase.canonical_digest(native))
            review['accepted'] = False
            with self.assertRaisesRegex(ValueError, 'anatomical verdict'):
                phase.load_inputs(Path('/fixture/review.json'))

    def test_receipt_corruption_and_unavailable_evidence_use_original_boundary(self):
        import subprocess
        manifest = self.loaded[0][0]
        record = phase.reacquired.read_json(self.receipt)
        published = copy.deepcopy(record['comment'])
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory)/'receipt.json'
            variants = [{'accepted': True}]
            for key, value in [('producer_head', 'a'*40), ('manifest_sha256', 'a'*64),
                               ('bundle_sha256', 'a'*64), ('review_session_id', 'other'),
                               ('implementation_session_id', 'other'), ('continuous_contact_certified', True)]:
                bad = copy.deepcopy(record); bad['binding'][key] = value; variants.append(bad)
            for key, value in [('body', 'changed'), ('id', 1), ('node_id', 'other')]:
                bad = copy.deepcopy(record); bad['comment'][key] = value; variants.append(bad)
            # Reuse only the unchanged expensive numerical result; receipt/registry validation really executes.
            with patch.object(phase.reacquired, 'portable_replay', return_value=manifest['component_result']):
                with patch.object(phase.reacquired, 'fetch_github', return_value=published):
                    for i, bad in enumerate(variants):
                        receipt.write_text(json.dumps(bad))
                        with self.subTest(variant=i), self.assertRaises((ValueError, KeyError)):
                            phase.load_inputs(receipt, native_manifest=self.manifest, bundle_root=self.bundles[0])
                with patch.object(phase.reacquired, 'fetch_github', side_effect=subprocess.CalledProcessError(1, 'gh')):
                    with self.assertRaises(subprocess.CalledProcessError):
                        phase.load_inputs(self.receipt, native_manifest=self.manifest, bundle_root=self.bundles[0])
                original = phase.reacquired.read_json
                def unavailable_registry(path):
                    if Path(path).name == 'codex-handoffs.json':
                        raise OSError('registry unavailable')
                    return original(path)
                with patch.object(phase.reacquired, 'read_json', side_effect=unavailable_registry):
                    with self.assertRaisesRegex(OSError, 'registry unavailable'):
                        phase.load_inputs(self.receipt, native_manifest=self.manifest, bundle_root=self.bundles[0])


@unittest.skipUnless(all(os.environ.get(k) for k in ('CAV_PHASE_BUNDLE', 'CAV_ARITHMETIC_CAPTURE',
                    'CAV_ARITHMETIC_RECEIPT')), 'explicit accepted native/scalar custody inputs required')
class AcceptedScalarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = phase.reacquired.read_json(phase.ROOT/'docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-native-reacquired.json')
        roles = phase.reacquired.check_index(Path(os.environ['CAV_PHASE_BUNDLE']), cls.manifest['bundle_index'], cls.manifest['bundle_sha256'])
        cls.native = phase.reacquired.read_json(roles['native'])
        cls.scalar_capture = phase.reacquired.read_json(Path(os.environ['CAV_ARITHMETIC_CAPTURE']))
        cls.scalar_receipt = phase.reacquired.read_json(Path(os.environ['CAV_ARITHMETIC_RECEIPT']))

    def authority(self):
        return phase.ScalarAuthority(self.scalar_capture, self.scalar_receipt, self.native,
            self.manifest['component_result']['numerical_accounting']['platform_math'])

    def test_actual_six_states_bind_keys_and_reject_stale_hull_and_proofs(self):
        authority = self.authority(); authority.prepare(self.native)
        self.assertEqual(set(authority.constant_records), {w for words in phase.ACOS_WORDS.values() for w in words})
        for identity, words in phase.ACOS_WORDS.items():
            track = next(t for t in self.native['tracks'] if t['path'] == identity[0])
            a, b = [capture.Float32Box(k['value']) for k in track['keys'][identity[1]:identity[1]+2]]
            domain = authority.key_domain(a, b, *identity)
            self.assertEqual(len(domain['branches'][0]['constant_proof_sha256']), 3)
            foreign = authority.key_domain(a, b, 'foreign', identity[1])
            self.assertEqual(foreign['branches'][0]['unknown'], 'acos_constant_authority_missing')
            foreign_key = authority.key_domain(a, b, identity[0], identity[1]+1)
            self.assertEqual(foreign_key['branches'][0]['unknown'], 'acos_constant_authority_missing')
            saved = copy.deepcopy(domain['branches'][0]['omega_interval'])
            domain['branches'][0]['omega_interval'][0] = Q(0)
            with self.assertRaisesRegex(ValueError, 'domain cache'):
                authority.key_domain(a, b, *identity)
            domain['branches'][0]['omega_interval'] = saved
            r = authority.constant_records[words[0]]
            original = r['assumptions']; r['assumptions'] = 'nearest only'
            with self.assertRaisesRegex(ValueError, 'proof cache'):
                authority.key_domain(a, b, *identity)
            r['assumptions'] = original

    def test_final_report_rejects_corrupted_finite_proofs_and_preserves_old_cases(self):
        report_path = os.environ.get('CAV_ACOS_REPORT')
        if not report_path:
            self.skipTest('explicit new finite-acos report required')
        report = json.loads(Path(report_path).read_text())
        phase.validate_diagnostic(report)
        for mutation in [lambda p: p.update(input_word='3f60e5c2'),
                         lambda p: p.update(profile='foreign'),
                         lambda p: p['binding'].update(capture_sha256='0'*64),
                         lambda p: p['binding'].update(engine_sha256='0'*64),
                         lambda p: p.update(coefficient_bytes='00'),
                         lambda p: p.update(assumptions='nearest only; omit FTZ'),
                         lambda p: p['nodes'][0].update(rounded_interval=[[0, 1], [0, 1]]),
                         lambda p: p['nodes'][-2].update(rounded_interval=[[0, 1], [0, 1]]),
                         lambda p: p['nodes'][-1].update(rounded_interval=[[0, 1], [0, 1]]),
                         lambda p: p.update(key_index=99),
                         lambda p: p.update(consumer_algorithm_sha256='0'*64),
                         lambda p: p.update(sha256='0'*64)]:
            proof = copy.deepcopy(report['continuous_native']['finite_acos_constants'][0]); mutation(proof)
            changed = {**report, 'continuous_native': {**report['continuous_native'],
                'finite_acos_constants': [proof]+report['continuous_native']['finite_acos_constants'][1:]}}
            with self.assertRaises(ValueError):
                phase.validate_diagnostic(changed)
        for proofs in [report['continuous_native']['finite_acos_constants'][1:],
                       [report['continuous_native']['finite_acos_constants'][0]]*6]:
            changed = {**report, 'continuous_native': {**report['continuous_native'], 'finite_acos_constants': proofs}}
            with self.assertRaises(ValueError):
                phase.validate_diagnostic(changed)
        self.assertEqual(len(report['accepted256_input_bindings']), 801)
        self.assertEqual(len(report['inputs']), 802)
        for key, coordinates, shapes in [('baseline_accounting', 69, 18),
                                         ('previous_operation_accounting', 19, 3028), ('previous_norm_accounting', 18, 3677)]:
            self.assertEqual(len(report[key]['coordinate_boxes']), coordinates)
            self.assertEqual(len(report[key]['shape_cases']), shapes)
        self.assertTrue(all(t.get('vertices') == 21175 for t in report['acos_target_replays'] if t['outcome'] == 'COORDINATE_CLOSED'))
        self.assertTrue(all(t.get('reason') != 'acos_constant_authority_missing' for t in report['acos_target_replays']))
        self.assertEqual(len(report['norm_target_replays']), 8)
        self.assertTrue(all(t['outcome'] == 'COORDINATE_CLOSED' for t in report['norm_target_replays']))

    def test_sign_changed_source_keys_cannot_reuse_six_constant_authority(self):
        changed = copy.deepcopy(self.native)
        for track in changed['tracks']:
            identity = (track['path'], 7)
            if identity in phase.ACOS_WORDS:
                for key in track['keys'][7:9]:
                    key['value'] = [-v for v in key['value']]
                authority = phase.ScalarAuthority(self.scalar_capture, self.scalar_receipt, changed,
                    self.manifest['component_result']['numerical_accounting']['platform_math'])
                a, b = [capture.Float32Box(k['value']) for k in track['keys'][7:9]]
                with self.assertRaisesRegex(phase.Unclosed, 'acos_constant_authority_missing'):
                    authority.slerp(a, b, capture.Float32Box(.5), *identity)
                return
        self.fail('Missing actual finite key set')

    def test_eight_frozen_norm_failures_replay_full_raw_geometry_with_positive_denominators(self):
        baseline_path = os.environ.get('CAV_NORM_BASELINE')
        if not baseline_path:
            self.skipTest('explicit accepted255 report required')
        old = capture.read_bound(Path(baseline_path), phase.NORM_BASELINE_SHA)
        targets = [r for r in old['continuous_native']['unclosed_boxes']
                   if r['reason'] == 'mixer_quaternion_norm_contains_zero']
        self.assertEqual(len(targets), 8)
        authority = self.authority(); authority.prepare(self.native)
        surface = dict(self.native['surfaces'][0])
        surface['joints'] = np.asarray(surface['joints']).reshape(-1, 4)
        surface['weights'] = np.asarray(surface['weights']).reshape(-1, 4)
        binds = [capture.matrix(b['pose']) for b in self.native['skin']]
        budget = phase.Budget(arithmetic=authority)
        outcomes = []
        for target in targets:
            lo, hi = target['seconds']
            try:
                result = phase.surface_span_box(self.native, surface, binds, lo, hi, capture.system_math(), budget)
            except phase.Unclosed as error:
                self.assertNotIn('norm', error.detail['reason'])
                outcomes.append(error.detail['reason'])
            else:
                self.assertEqual(result.lo.shape, (21175, 3))
                for t in np.linspace(lo, hi, 5):
                    self.assertTrue(result.contains(phase.sampled_points(self.native, surface, binds, float(t))).all())
                outcomes.append('CLOSED')
            records = budget.norm_records[lo, hi, target['bone']]
            for record in records:
                self.assertGreater(record['mixer_rounded_norm_squared'][0], 0)
                self.assertGreater(record['basis_rounded_norm_squared'][0], 0)
                self.assertEqual(len(record['hamilton_roundoff']), 2)
        self.assertEqual(len(outcomes), 8)

    def test_actual_terminal_wrap_contains_receipt_backed_zero_without_point_replay(self):
        authority = self.authority(); authority.prepare(self.native)
        surface = dict(self.native['surfaces'][0])
        surface['joints'] = np.asarray(surface['joints']).reshape(-1, 4)
        surface['weights'] = np.asarray(surface['weights']).reshape(-1, 4)
        binds = [capture.matrix(b['pose']) for b in self.native['skin']]
        functions = capture.system_math()
        budget = phase.Budget(weight_values=0, arithmetic=authority)
        with patch.object(capture, 'native_track_box', side_effect=AssertionError('unproved terminal point replay')):
            zero = phase.surface_span_box(self.native, surface, binds, 0., 0., functions, budget)
            terminal = phase.surface_span_box(self.native, surface, binds,
                self.native['native_search_boundaries_seconds'][-1], self.native['length'], functions, budget)
        self.assertEqual(len(terminal.lo), 21175)
        self.assertTrue(terminal.contains(zero.lo).all() and terminal.contains(zero.hi).all())
        self.assertEqual(budget.used, 0)

    def test_all_actual_key_pairs_match_bounded_weight_oracle_with_six_finite_constants(self):
        # This refutation check does not replace the continuous Taylor/error proof.
        native = self.native; authority = self.authority()
        authority.prepare(native)
        self.assertEqual(len(authority.domains), 553)
        self.assertEqual(sum(len(r['dot_states']) for r in authority.domains.values()), 2496)
        unknown = set(); checks = 0; f = capture.Float32Box; functions = capture.system_math()
        for track in native['tracks']:
            if track['type'] != 2:
                continue
            for i, (a, b) in enumerate(zip(track['keys'], track['keys'][1:])):
                q, r = f(a['value']), f(b['value'])
                for weight in (-.00030001, .5, 1.0003001):
                    low = np.float32(weight); high = np.nextafter(low, np.float32(np.inf))
                    try:
                        box = authority.slerp(q, r, f(low, high), track['path'], i)
                    except phase.Unclosed as error:
                        self.assertEqual(error.detail['reason'], 'acos_constant_authority_missing')
                        unknown.add((track['path'].split(':')[-1], i))
                        continue
                    for value in (low, high):
                        oracle = capture.slerp_box(q, r, value, functions)
                        self.assertTrue(box.contains(oracle.lo).all() and box.contains(oracle.hi).all(), (track['path'], i, weight))
                        checks += 1
        self.assertEqual(unknown, set())
        self.assertEqual(checks, 3318)
        self.assertEqual(len(authority.constant_records), 6)


@unittest.skipUnless(os.environ.get('CAV_TRIANGLE_REPORT'), 'explicit new correlated triangle report required')
class AcceptedTriangleReportTests(unittest.TestCase):
    def test_actual_all_face_spans_birth_targets_history_and_negative_gates(self):
        report = json.loads(Path(os.environ['CAV_TRIANGLE_REPORT']).read_text())
        phase.validate_diagnostic(report)
        self.assertEqual(report['version'], 6)
        self.assertEqual(len(report['inputs']), 803)
        self.assertEqual(len(report['accepted257_input_bindings']), 802)
        rows = report['continuous_native']['closed_boxes']
        self.assertEqual(len(rows), 40)
        areas = [p for row in rows for area in row['triangle_area'].values() for p in area['certificates']]
        self.assertEqual(len(areas), 7760)
        self.assertGreater(sum(p['twice_area_interval'][0] > 0 for p in areas), 0)
        cases = report['previous_shape_accounting']['shape_cases']
        self.assertEqual(len(cases), 2797)
        self.assertGreater(sum(c['outcome'] == 'CLOSED' for c in cases), 0)
        for key, coordinates, shapes in [('baseline_accounting', 69, 18),
                ('previous_operation_accounting', 19, 3028), ('previous_norm_accounting', 18, 3677)]:
            self.assertEqual(len(report[key]['coordinate_boxes']), coordinates)
            self.assertEqual(len(report[key]['shape_cases']), shapes)
        self.assertIsNone(report['claims']['policy_E'])
        self.assertFalse(report['claims']['success_dependency'])
        # Local certificate replay tests all residual/wedge mutations cheaply;
        # these report mutations catch coverage and predecessor/gate bypasses.
        for mutate in [lambda r: r.update(version=5),
                lambda r: r['inputs'].update(shape_baseline_report='0'*64),
                lambda r: r['claims'].update(surface_unblocked=True),
                lambda r: r['shape_proof'].update(method='independent-boxes'),
                lambda r: r['previous_shape_accounting']['shape_cases'].pop(),
                lambda r: rows[0]['triangle_area'].pop(next(iter(rows[0]['triangle_area'])))]:
            # Restore only touched containers; avoid copying the large immutable report.
            original_version = report['version']; original_inputs = dict(report['inputs'])
            original_claims = dict(report['claims']); original_shape = dict(report['shape_proof'])
            original_cases = list(report['previous_shape_accounting']['shape_cases'])
            original_area = dict(rows[0]['triangle_area'])
            mutate(report)
            with self.assertRaises((ValueError, KeyError)):
                phase.validate_diagnostic(report)
            report['version'] = original_version; report['inputs'] = original_inputs
            report['claims'] = original_claims; report['shape_proof'] = original_shape
            report['previous_shape_accounting']['shape_cases'] = original_cases
            rows[0]['triangle_area'] = original_area



@unittest.skipUnless(os.environ.get('CAV_REFINEMENT_REPORT') and os.environ.get('CAV_TRIANGLE_REPORT'),
                     'explicit final refinement and accepted258 reports required')
class AcceptedShapeRefinementTests(unittest.TestCase):
    def test_original_inventory_both_children_bindings_histories_and_negative_controls(self):
        report = json.loads(Path(os.environ['CAV_REFINEMENT_REPORT']).read_text())
        baseline = capture.read_bound(Path(os.environ['CAV_TRIANGLE_REPORT']), phase.TRIANGLE_BASELINE_SHA)
        phase.validate_refined_shape(report)
        self.assertEqual(report['version'], 7)
        self.assertEqual(len(report['inputs']), 804)
        self.assertEqual(report['accepted258_input_bindings'], baseline['inputs'])
        rows = report['continuous_native']['closed_boxes']
        self.assertEqual(rows, baseline['continuous_native']['closed_boxes'])
        self.assertEqual(sum(len(a['certificates']) for r in rows for a in r['triangle_area'].values()), 7760)
        self.assertEqual(sum(len(s['certificates']) for r in rows for s in r['triangle_shape'].values()), 2797)
        for key in ('baseline_accounting', 'previous_operation_accounting', 'previous_norm_accounting',
                'previous_shape_accounting', 'source_support_constraints', 'accepted_anatomy', 'fit',
                'finite_endpoint_necessary_conditions', 'full_geometry', 'metric_bounds', 'claims', 'missing_physical_context'):
            self.assertEqual(report[key], baseline[key], key)
        self.assertEqual(report['atlas']['knots'], baseline['atlas']['knots'])
        self.assertEqual(report['work_budget_declared_before_fit'], baseline['work_budget_declared_before_fit'])
        refinement = report['shape_refinement']
        self.assertEqual(refinement['work_before'], baseline['work_used'])
        self.assertEqual(len(refinement['area_targets']), 194)
        self.assertEqual(len(refinement['birth_targets']), 148)
        for child in refinement['children']:
            self.assertNotIn('reason', child)
            self.assertEqual(sum(len(a['certificates']) for a in child['triangle_area'].values()), 194)
            self.assertEqual(sum(len(a['certificates']) for a in child['triangle_shape'].values()), 148)
        for key in ('area_targets', 'birth_targets'):
            self.assertTrue(all(c['outcome'] == 'CLOSED' for c in refinement[key] if c['before'] == 'CLOSED'))
        for key in ('attempts', 'refinement_splits', 'proposal_evaluations'):
            old = report['work_used'][key]; report['work_used'][key] = 0
            with self.assertRaises(ValueError):
                phase.validate_refined_shape(report)
            report['work_used'][key] = old
        child = refinement['children'][0]
        hoof = next(iter(child['triangle_area']))
        proof = child['triangle_area'][hoof]['certificates'][0]
        matrices = report['shape_proof']['shared_skin_certificates']
        identity = matrices[proof['shared_transform_certificates'][0]]
        old = identity['source_sha256']; identity['source_sha256'] = '0'*64
        with self.assertRaises(ValueError):
            phase.validate_refined_shape(report)
        with self.assertRaises(ValueError):
            phase.validate_shape_certificate(proof, matrices)
        identity['source_sha256'] = old
        before = refinement['area_targets'][0]['outcome']
        refinement['area_targets'][0]['outcome'] = 'FORGED'
        with self.assertRaises(ValueError):
            phase.validate_refined_shape(report)
        refinement['area_targets'][0]['outcome'] = before


if __name__ == '__main__':
    unittest.main()
