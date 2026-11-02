"""Independent hand cases and hostile inputs for the native capture verifier."""
import copy
import math
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np

import check_cavalry_march_capture as capture


class CaptureTests(unittest.TestCase):
    def test_outward_float32_operations_include_fused_and_separate_rounding(self):
        f = capture.Float32Box
        halfway = f(2**24) + f(1)
        self.assertTrue(halfway.contains([2**24, 2**24 + 2]).all())
        # Separate multiply/add yields zero; one fused operation retains -2^-46.
        cancellation = f(1 + 2**-23) * f(1 - 2**-23) - f(1)
        self.assertTrue(cancellation.contains([0, -2**-46]).all())
        self.assertTrue((f(1) / f(3)).contains(np.float32(1 / 3)))
        self.assertTrue(f(2).sqrt().contains(np.float32(math.sqrt(2))))
        with self.assertRaises(ValueError):
            f(1) / f(0)
        with self.assertRaises(ValueError):
            f(float('nan'))

    def test_operation_boxes_enclose_hand_computed_basis_and_affine_product(self):
        f = capture.Float32Box
        transform = capture.basis_box([3, 4, 5], [0, 0, 0, 1], [2, 3, 4])
        expected = np.array([[2, 0, 0, 3], [0, 3, 0, 4], [0, 0, 4, 5]])
        self.assertTrue(transform.contains(expected).all())
        product = capture.affine_box(transform, f([[1, 0, 0, 1], [0, 1, 0, 2], [0, 0, 1, 3]]))
        expected[:, 3] = [5, 10, 17]
        self.assertTrue(product.contains(expected).all())
        self.assertFalse(product.contains(expected + 1).all())

    def test_native_slerp_and_import_endpoint_operations_are_separate(self):
        functions = capture.system_math()
        track = {'keys': [{'time': 0., 'value': [0, 0, 0, 1]}, {'time': 1., 'value': [0, 0, -1, 0]}],
                 'type': 2, 'interpolation': 1}
        midpoint = capture.native_track_box(track, .5, 1., functions)
        self.assertTrue(midpoint.contains([0, 0, -math.sqrt(.5), math.sqrt(.5)]).all())
        raw = {'times': [0., 1.], 'values': [[0, 0, 0, .99999994]] * 2, 'step': False}
        endpoint = capture.imported_key_box(raw, 1., True, functions)
        self.assertTrue(endpoint.contains([0, 0, 0, 1]).all())

    def test_operation_audit_rejects_corrupted_skin_output(self):
        identity = np.eye(4)[:3].ravel().tolist()
        native = {'bones': [{'parent': -1}], 'tracks': [], 'length': 1.}
        sample = {'time': 0., 'track_values': [], 'locals': [identity], 'globals': [identity],
                  'pose_components': [{'position': [0, 0, 0], 'rotation': [0, 0, 0, 1], 'scale': [1, 1, 1]}],
                  'skinned_skeleton_local': [[[.75, 0, 0]]]}
        surface = {'vertices': [[1, 0, 0]], 'joints': [[0, 0, 0, 0]], 'weights': [[.75, 0, 0, 0]]}
        result = capture.operation_enclosures(native, sample, surface, [np.eye(4)], {})
        self.assertTrue(all(v['outside_components'] == 0 for v in result.values()))
        sample['skinned_skeleton_local'][0][0][0] = .751
        result = capture.operation_enclosures(native, sample, surface, [np.eye(4)], {})
        self.assertEqual(result['bind_and_cpu_lbs']['outside_components'], 1)

    def test_mixed_skin_preserves_material_weights_and_affine_bind(self):
        transforms = np.repeat(np.eye(4)[None], 2, axis=0)
        transforms[1, 0, 3] = .04
        surface = {"vertices": [[0, 0, 0]], "joints": [[0, 1, 0, 0]],
                   "weights": [[.75, .25, 0, 0]]}
        np.testing.assert_allclose(capture.skin(surface, transforms), [[.01, 0, 0]])
        surface["weights"] = [[.5, .25, 0, 0]]
        surface["vertices"] = [[2, 0, 0]]
        np.testing.assert_allclose(capture.skin(surface, transforms), [[1.51, 0, 0]])

    def test_import_quantization_is_not_native_renormalization(self):
        result = capture.import_weights([[.75, .25, 0, 0]])
        expected = np.array([[49151 / 65535, 16383 / 65535, 0, 0]], dtype=np.float32)
        np.testing.assert_array_equal(result, expected)
        self.assertLess(float(result.sum()), 1)

    def test_quaternion_short_arc_and_sign_equivalence(self):
        q = [0, 0, math.sqrt(.5), math.sqrt(.5)]
        a = capture.interpolate([0, 1], [[0, 0, 0, 1], q], .5, rotation=True)
        b = capture.interpolate([0, 1], [[0, 0, 0, 1], [-x for x in q]], .5, rotation=True)
        np.testing.assert_allclose(a, [0, 0, math.sin(math.pi / 8), math.cos(math.pi / 8)])
        np.testing.assert_allclose(a, b)

    def test_interpolation_rejects_bad_keys_and_preserves_step_boundary(self):
        self.assertEqual(capture.interpolate([0, 1], [[2], [4]], 1, step=True).tolist(), [4])
        for times, values in [([0, 0], [[2], [4]]), ([0, 1], [[2], [float('nan')]])]:
            with self.assertRaises(ValueError):
                capture.interpolate(times, values, .5)

    def test_oriented_triangle_bijection_preserves_duplicate_seam_vertices(self):
        raw = {"vertices": [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 0]],
               "uv": [[0, 0], [1, 0], [0, 1], [1, 1]],
               "joints": [[0, 0, 0, 0]] * 4,
               "weights": [[1, 0, 0, 0]] * 4, "indices": [0, 1, 2, 3, 2, 1]}
        native = copy.deepcopy(raw)
        native["indices"] = [2, 1, 0, 1, 2, 3]  # glTF CCW -> Godot CW.
        mapping = capture.topology(raw, native)
        self.assertEqual(mapping["native_to_raw"], [0, 1, 2, 3])
        self.assertEqual(mapping["triangles"], 2)
        for bad in ([2, 1, 0], [0, 1, 2, 1, 2, 3], [2, 1, 0, 2, 1, 0]):
            native["indices"] = bad
            with self.assertRaises(ValueError):
                capture.topology(raw, native)

    def test_capture_payload_hash_is_verified_before_parsing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.json'
            path.write_text('{"version":1}')
            digest = capture.sha256(path)
            self.assertEqual(capture.read_bound(path, digest), {"version": 1})
            path.write_text('{"version":2}')
            with self.assertRaises(ValueError):
                capture.read_bound(path, digest)

    def test_same_position_uv_skin_duplicates_are_resolved_by_incident_triangles(self):
        raw = {"vertices": [[0, 0, 0], [0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]],
               "uv": [[0, 0]] * 5, "joints": [[0, 0, 0, 0]] * 5,
               "weights": [[1, 0, 0, 0]] * 5, "indices": [0, 2, 3, 1, 2, 4]}
        native = copy.deepcopy(raw)
        native['indices'] = [3, 2, 1, 4, 2, 0]
        self.assertEqual(capture.topology(raw, native)['native_to_raw'], [1, 0, 2, 3, 4])

    def test_renormalized_native_weights_are_rejected(self):
        raw = {"vertices": [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
               "uv": [[0, 0]] * 3, "joints": [[0, 1, 0, 0]] * 3,
               "weights": [[.75, .25, 0, 0]] * 3, "indices": [0, 1, 2]}
        native = copy.deepcopy(raw)
        native['indices'] = [2, 1, 0]
        with self.assertRaisesRegex(ValueError, 'attribute mismatch'):
            capture.topology(raw, native)

    def test_source_corner_provenance_and_complete_underside_reject_fake_patch(self):
        source = {'vertices': [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                  'triangles': [[0, 2, 1]], 'parts': [22, 22, 22],
                  'triangle_uv': [[[0, 0], [0, 1], [1, 0]]],
                  'matrix_world': np.eye(4).tolist()}
        raw = {'vertices': [[0, 0, 0], [1, 0, 0], [0, 0, -1]],
               'uv': [[0, 1], [1, 1], [0, 0]], 'indices': [0, 2, 1]}
        result = capture.source_parts(raw, source)
        self.assertEqual(result, [22, 22, 22])
        patch = capture.sole_patch(raw, result, 22)
        self.assertEqual(patch['sole_triangles'], [0])
        self.assertEqual(patch['sole_vertices'], [0, 1, 2])
        fake = copy.deepcopy(patch)
        fake['sole_vertices'] = [0]
        with self.assertRaises(ValueError):
            capture.validate_patch(raw, result, 22, fake)
        source['triangle_uv'][0][0] = [.25, .25]
        with self.assertRaises(ValueError):
            capture.source_parts(raw, source)

    def test_source_provenance_rejects_flipped_or_missing_triangle(self):
        source = {'vertices': [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                  'triangles': [[0, 2, 1]], 'parts': [22, 22, 22],
                  'triangle_uv': [[[0, 0], [0, 1], [1, 0]]],
                  'matrix_world': np.eye(4).tolist()}
        raw = {'vertices': [[0, 0, 0], [1, 0, 0], [0, 0, -1]],
               'uv': [[0, 1], [1, 1], [0, 0]], 'indices': [0, 1, 2]}
        with self.assertRaises(ValueError):
            capture.source_parts(raw, source)

    def test_native_approximate_key_search_has_early_seam_and_extrapolation(self):
        # Pinned Godot _find chooses the .25 key early; the *next* slope is 8.
        got = capture.interpolate([0, .25, .5], [[0], [1], [3]], .25 - .000005,
                                  native_length=.5)
        self.assertAlmostEqual(got[0], 1 - .000005 * 8, places=10)
        seam = capture.interpolate([0, .25, .5], [[0], [1], [3]], .5 - .000005,
                                   native_length=.5)
        self.assertEqual(seam.tolist(), [3])

    def test_bad_endpoint_quaternion_and_nonfinite_skin_reject(self):
        with self.assertRaises(ValueError):
            capture.interpolate([0], [[0, 0, 0, 0]], 0, rotation=True)
        base = {'vertices': [[0, 0, 0]], 'weights': [[1, 0, 0, 0]], 'joints': [[0, 0, 0, 0]]}
        for field, value in [('vertices', [[float('nan'), 0, 0]]), ('weights', [[-1, 2, 0, 0]]),
                             ('joints', [[.5, 0, 0, 0]]), ('joints', [[2, 0, 0, 0]])]:
            bad = copy.deepcopy(base)
            bad[field] = value
            with self.assertRaises(ValueError):
                capture.skin(bad, np.eye(4)[None])

    def test_accessor_checks_view_bounds_stride_and_nonfinite_values(self):
        document = {'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': 2, 'type': 'SCALAR'}],
                    'bufferViews': [{'buffer': 0, 'byteLength': 8}]}
        binary = struct.pack('<2f', 1, 2)
        self.assertEqual(capture.accessor(document, binary, 0).tolist(), [[1], [2]])
        for edit in [{'byteLength': 4}, {'byteStride': 8}, {'buffer': 1}]:
            bad = copy.deepcopy(document)
            bad['bufferViews'][0].update(edit)
            with self.assertRaises(ValueError):
                capture.accessor(bad, binary, 0)
        with self.assertRaises(ValueError):
            capture.accessor(document, struct.pack('<2f', 1, float('inf')), 0)

    def test_forward_kinematics_preserves_parent_and_affine_scale(self):
        parent, child = np.eye(4), np.eye(4)
        parent[0, 0], parent[0, 3], child[0, 3] = 2, 3, 4
        result = capture.forward_kinematics([{'parent': -1}, {'parent': 0}], [parent, child])
        self.assertEqual(result[1, 0, 3], 11)
        with self.assertRaises(ValueError):
            capture.forward_kinematics([{'parent': 0}], [parent])

    def test_existing_probe_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            sentinel = path / 'existing.txt'
            sentinel.write_text('keep')
            with self.assertRaises(ValueError):
                capture.prepare(path)
            self.assertEqual(sentinel.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
