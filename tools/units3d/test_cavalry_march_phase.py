"""Hand-computed and hostile cases for the offline phase fit (no Godot)."""
import copy
from fractions import Fraction as Q
import math
import json
import os
from unittest.mock import patch
import tempfile
import unittest
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


if __name__ == '__main__':
    unittest.main()
