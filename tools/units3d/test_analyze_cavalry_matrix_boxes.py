"""Exact hand-computed rectangle controls; no native capture or frozen report load."""
import copy
from fractions import Fraction as Q
from pathlib import Path
import unittest

try:
    import analyze_cavalry_matrix_boxes as boxes
except ModuleNotFoundError:
    boxes = None


def rows(*values):
    return tuple(tuple((Q(x[0]), Q(x[1])) if isinstance(x, tuple) else (Q(x), Q(x))
                       for x in row) for row in values)


class RectangleTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(boxes, 'new exact rectangle sidecar is missing')

    def check(self, d1, d2, domain, status, mode=None):
        answer = boxes.solve_rectangle(tuple(map(Q, d1)), tuple(map(Q, d2)), domain)
        self.assertEqual(answer['status'], status)
        if mode:
            self.assertEqual(answer['mode'], mode)
        boxes.replay_rectangle(tuple(map(Q, d1)), tuple(map(Q, d2)), domain, answer)
        return answer

    def test_parallel_witness_is_an_explicit_exact_assignment(self):
        domain = rows((1, 1), (0, (-1, 1)), (0, 0))
        answer = self.check([1, 0], [0, 1], domain, 'REFERENCE_BOX_DEGENERATE', 'finite_lambda')
        self.assertEqual(answer['lambda'], [1, 1])
        self.assertEqual(answer['assignment'][1][1], [0, 1])

    def test_independent_xy_quarter_bound_is_nondegenerate(self):
        domain = rows((1, (Q(-1, 2), Q(1, 2))), ((Q(-1, 2), Q(1, 2)), 1), (0, 0))
        answer = self.check([1, 0], [0, 1], domain, 'REFERENCE_BOX_NONDEGENERATE')
        self.assertEqual(len(answer['cells']), 2)
        self.assertEqual(answer['breakpoints'], [[0, 1]])

    def test_projective_zero_edge_required_without_finite_lambda(self):
        domain = rows(((0, 1), 0), (0, 1), (0, 0))
        answer = self.check([1, 0], [0, 1], domain, 'REFERENCE_BOX_DEGENERATE', 'zero_edge')
        self.assertEqual(answer['assignment'][0][0], [0, 1])
        self.assertEqual(answer['edges'][1], [[0, 1], [1, 1], [0, 1]])

    def test_breakpoint_singleton_two_is_preserved(self):
        answer = self.check([1], [2], rows((1,), (1,), (0,)), 'REFERENCE_BOX_DEGENERATE', 'finite_lambda')
        self.assertEqual(answer['lambda'], [2, 1])

    def test_unequal_weight_translation_residue_is_not_normalized(self):
        answer = self.check([Q(7, 8), Q(-1, 8), 0], [0, 0, 1],
            rows((1, (0, 7), 0), (0, 0, 1), (0, 0, 0)), 'REFERENCE_BOX_DEGENERATE', 'zero_edge')
        self.assertEqual(answer['assignment'][0][1], [7, 1])

    def test_zero_coefficients_all_zero_edge_and_negative_tail(self):
        self.check([0], [1], rows(((-2, 3),), ((-4, -1),), ((0, 0),)),
                   'REFERENCE_BOX_DEGENERATE', 'zero_edge')
        answer = self.check([1], [-3], rows(((-2, -1),), (0,), (0,)),
                            'REFERENCE_BOX_DEGENERATE', 'finite_lambda')
        self.assertEqual(answer['lambda'], [-3, 1])
        self.check([], [], rows((), (), ()), 'REFERENCE_BOX_DEGENERATE', 'zero_edge')

    def test_positive_unbounded_tail_and_zero_slope(self):
        answer = self.check([1, 0], [0, 1], rows((1, (2, 3)), (0, 0), (0, 0)),
                            'REFERENCE_BOX_DEGENERATE', 'finite_lambda')
        self.assertEqual(answer['lambda'], [2, 1])
        self.check([1, 0], [0, 1], rows((1, 0), (0, 1), (0, 0)), 'REFERENCE_BOX_NONDEGENERATE')

    def test_exact_float_endpoints_are_never_integer_rounded(self):
        domain = rows((1, (Q.from_float(.1), Q.from_float(.1))), (0, 0), (0, 0))
        answer = self.check([1, 0], [0, 1], domain, 'REFERENCE_BOX_DEGENERATE')
        self.assertEqual(answer['lambda'], [3602879701896397, 36028797018963968])

    def test_hostile_sat_assignment_lambda_cross_and_zero_mode_fail(self):
        d1, d2 = (Q(1), Q(0)), (Q(0), Q(1))
        domain = rows((1, 1), (0, (-1, 1)), (0, 0))
        answer = boxes.solve_rectangle(d1, d2, domain)
        changes = [lambda a: a['assignment'][1].__setitem__(1, [2, 1]),
                   lambda a: a.__setitem__('lambda', [0, 1]),
                   lambda a: a['edges'][0].__setitem__(0, [0, 1]),
                   lambda a: a.__setitem__('mode', 'zero_edge'),
                   lambda a: a['assignment'].pop(),
                   lambda a: a.__setitem__('status', 'PASS')]
        for change in changes:
            bad = copy.deepcopy(answer); change(bad)
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                boxes.replay_rectangle(d1, d2, domain, bad)

    def test_hostile_unsat_missing_cells_breakpoints_ranges_or_affines_fail(self):
        d1, d2 = (Q(1), Q(0)), (Q(0), Q(1))
        domain = rows((1, (Q(-1, 2), Q(1, 2))), ((Q(-1, 2), Q(1, 2)), 1), (0, 0))
        answer = boxes.solve_rectangle(d1, d2, domain)
        changes = [lambda a: a['cells'].pop(), lambda a: a['breakpoints'].clear(),
                   lambda a: a['zero_edge_ranges'][0].__setitem__(0, [0, 1]),
                   lambda a: a['cells'][0]['inequalities'][0].__setitem__(0, [999, 1]),
                   lambda a: a['cells'][0].__setitem__('cell', [None, None]),
                   lambda a: a.__setitem__('zero_edge_infeasible', False)]
        for change in changes:
            bad = copy.deepcopy(answer); change(bad)
            with self.subTest(change=change), self.assertRaises(ValueError):
                boxes.replay_rectangle(d1, d2, domain, bad)

    def test_bad_domain_and_noncanonical_rationals_fail(self):
        for d1, d2, domain in [([1], [1, 2], rows((1,), (1,), (1,))),
                              ([1], [1], rows(((2, 1),), (1,), (1,)))]:
            with self.assertRaises(ValueError):
                boxes.solve_rectangle(d1, d2, domain)
        answer = boxes.solve_rectangle((Q(1),), (Q(2),), rows((1,), (1,), (0,)))
        answer['lambda'] = [4, 2]
        with self.assertRaises(ValueError):
            boxes.replay_rectangle((Q(1),), (Q(2),), rows((1,), (1,), (0,)), answer)

class BindingKernelTests(unittest.TestCase):
    def test_pinned_helper_keeps_duplicate_slots_and_fourth_coordinate(self):
        helper = boxes.load_coefficient_helper(Path(__file__).with_name('cavalry_march_phase.py'))
        raw = (((0., 0., 0.), (0, 0, 0, 0), (.5, .25, .125, 0.)),
               ((1., 0., 0.), (0, 0, 0, 0), (.5, .5, 0., 0.)),
               ((0., 1., 0.), (0, 0, 0, 0), (1., 0., 0., 0.)))
        coeff = helper(raw)
        self.assertEqual(coeff[0], ((0, (Q(1), Q(0), Q(0), Q(1, 8))),))
        self.assertEqual(coeff[1], ((0, (Q(0), Q(1), Q(0), Q(1, 8))),))

    def test_stale_helper_fails_before_execution(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'helper.py'
            path.write_text('raise RuntimeError("must not execute")')
            with self.assertRaisesRegex(ValueError, 'helper source'):
                boxes.load_coefficient_helper(path)

    def test_invalid_raw_coefficients_context_and_residual_reject(self):
        helper = boxes.load_coefficient_helper(Path(__file__).with_name('cavalry_march_phase.py'))
        raw = [[[0., 0., 0.], [0, 0, 0, 0], [1., 0., 0., 0.]],
               [[1., 0., 0.], [0, 0, 0, 0], [1., 0., 0., 0.]],
               [[0., 1., 0.], [0, 0, 0, 0], [1., 0., 0., 0.]]]
        coeff = helper(tuple(tuple(tuple(x) for x in row) for row in raw))
        proof = {'method': boxes.SHAPE_METHOD, 'vertex_ids': [0, 1, 2],
                 'raw_vertices_joints_weights': raw,
                 'edge_coefficients': boxes.packed([[{'bind_index': j, 'homogeneous': h} for j, h in edge] for edge in coeff]),
                 'shared_transform_certificates': ['a'*64], 'branches': [{}]}
        self.assertEqual(boxes.raw_coefficients(proof, helper)[0], [(0, 0), (0, 1)])
        for change in [lambda p: p['raw_vertices_joints_weights'][0][2].__setitem__(0, -1),
                       lambda p: p['edge_coefficients'][0][0]['homogeneous'].__setitem__(3, [1, 1]),
                       lambda p: p['shared_transform_certificates'].clear(),
                       lambda p: p['vertex_ids'].__setitem__(0, True)]:
            bad = copy.deepcopy(proof); change(bad)
            with self.assertRaises(ValueError):
                boxes.raw_coefficients(bad, helper)
        identity = {'method': boxes.SHAPE_METHOD, 'seconds': [0., 1.], 'source_sha256': 'b'*64,
                    'matrix_interval': [[[[0.]*4 for _ in range(3)]], [[[1.]*4 for _ in range(3)]]]}
        boxes.matrix_domain(boxes.digest(identity), identity)
        bad = copy.deepcopy(identity); bad['matrix_interval'][0][0][0][0] = 2.
        with self.assertRaises(ValueError):
            boxes.matrix_domain(boxes.digest(bad), bad)
        with self.assertRaises(ValueError):
            boxes.matrix_domain('c'*64, identity)
        branch = {'vertex_native_residual_absolute': [[[1, 8]]*3 for _ in range(3)],
                  'edges': [{'native_residual_absolute': [[1, 4]]*3} for _ in range(2)]}
        centered = {'residual_cross_interval': [[-1.]*3, [1.]*3]}
        boxes.check_zero_error(branch, centered)
        bad = copy.deepcopy(branch); bad['edges'][0]['native_residual_absolute'][0] = [-1, 1]
        with self.assertRaises(ValueError):
            boxes.check_zero_error(bad, centered)
        with self.assertRaises(ValueError):
            boxes.check_zero_error(branch, {'residual_cross_interval': [[.1]*3, [1.]*3]})

    def test_target_join_and_parent_child_alternatives_do_not_drop_branches(self):
        t = {'seconds': [0., 1.], 'hoof': 'h', 'native_triangle_id': 7, 'original_local_triangle_index': 2}
        u = dict(t, seconds=[0., .5])
        v = dict(t, seconds=[.5, 1.])
        self.assertNotEqual(boxes.target_key(t), boxes.target_key(u))
        self.assertEqual(boxes.face_key(t), boxes.face_key(v))
        self.assertEqual(boxes.classify_alternatives([DEG := boxes.DEGENERATE],
            [[boxes.NONDEGENERATE], [DEG]]), 'ALL_CURRENT_RECTANGLE_ALTERNATIVES_OBSTRUCTED')
        self.assertEqual(boxes.classify_alternatives([DEG], [[boxes.NONDEGENERATE], [boxes.NONDEGENERATE]]),
                         'PARENT_OBSTRUCTED_CHILD_COVER_NONDEGENERATE')
        self.assertEqual(boxes.classify_alternatives([boxes.NONDEGENERATE], [[DEG], [DEG]]),
                         'PARENT_NONDEGENERATE_CHILD_COVER_OBSTRUCTED')
        self.assertEqual(boxes.classify_alternatives([DEG], None), 'UNREFINED_RECTANGLE_OBSTRUCTED')
        with self.assertRaises(ValueError):
            boxes.classify_alternatives([DEG], [[DEG]])
        with self.assertRaises(ValueError):
            boxes.classify_alternatives([], None)
        with self.assertRaises(ValueError):
            boxes.classify_alternatives(['PASS'], None)


class CompletenessTests(unittest.TestCase):
    def test_two_row_determinant_corner_oracle(self):
        from itertools import product
        intervals = [(Q(-1), Q(0)), (Q(-1, 2), Q(1, 2)), (Q(1), Q(1)), (Q(1), Q(2))]
        for ax, bx, ay, by in product(intervals, repeat=4):
            domain = rows((ax, bx), (ay, by), (0, 0))
            corners = [a*b-c*d for a, b, c, d in product(ax, by, ay, bx)]
            expected = boxes.DEGENERATE if min(corners) <= 0 <= max(corners) else boxes.NONDEGENERATE
            proof = boxes.solve_rectangle((Q(1), Q(0)), (Q(0), Q(1)), domain)
            self.assertEqual(proof['status'], expected, (ax, bx, ay, by))
            boxes.replay_rectangle((Q(1), Q(0)), (Q(0), Q(1)), domain, proof)

    def test_boolean_rationals_are_not_integer_certificates(self):
        domain = rows((1,), (1,), (0,))
        proof = boxes.solve_rectangle((Q(1),), (Q(2),), domain)
        proof['edges'][0][0] = [True, 1]
        with self.assertRaises(ValueError):
            boxes.replay_rectangle((Q(1),), (Q(2),), domain, proof)
        domain = rows((1, 0), (0, 1), (0, 0))
        proof = boxes.solve_rectangle((Q(1), Q(0)), (Q(0), Q(1)), domain)
        proof['breakpoints'] = [[False, 1]]
        with self.assertRaises(ValueError):
            boxes.replay_rectangle((Q(1), Q(0)), (Q(0), Q(1)), domain, proof)

    def test_deterministic_work_plan_counts_all_parent_and_child_branches(self):
        job = {'d1': (Q(1), Q(0)), 'd2': (Q(0), Q(1))}
        jobs = {'a': job, 'b': job, 'c': job, 'd': job}
        links = {'t': {'parent': ['a', 'b'], 'children': [['c'], ['d']]}}
        plan = boxes.work_plan(jobs, links)
        self.assertEqual(plan['unique_face_context_jobs'], 4)
        self.assertEqual(plan['parent_branch_visits'], 2)
        self.assertEqual(plan['child_branch_visits'], 2)
        self.assertFalse(plan['all_original_unknown_parents_single_branch'])
        self.assertEqual(plan['bounds']['zero_plus_cell_row_term_visits_bound'], 4*3*2*3)

    def test_malformed_report_receipt_and_full_denominator_fail_closed(self):
        import argparse
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'bad.json'; path.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'hash'):
                boxes.bound_json(path, boxes.REPORT_SHA)
            with self.assertRaisesRegex(ValueError, 'size'):
                boxes.bound_json(path, boxes.REPORT_SHA, boxes.REPORT_BYTES)
            args = argparse.Namespace(receipt=path)
            with self.assertRaisesRegex(ValueError, 'hash'):
                boxes.load_packet(args)
        with self.assertRaisesRegex(ValueError, 'denominator'):
            boxes.build_inventory({'normal_projection': {'area_targets': [], 'birth_targets': [], 'children': []}}, {}, None)

    def test_evidence_output_is_exclusive_and_duplicate_json_is_rejected(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'proof.json'
            boxes.write_new(path, {'failure': 'preserve'})
            with self.assertRaises(FileExistsError):
                boxes.write_new(path, {'success': True})
            self.assertIn('preserve', path.read_text())
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            boxes.no_duplicates([('status', 'UNKNOWN'), ('status', 'PASS')])


class RelaxationAllowanceTests(unittest.TestCase):
    def test_zero_error_edges_and_cross_remain_inside_accepted_allowances(self):
        proof = boxes.solve_rectangle((Q(1),), (Q(2),), rows((1,), (1,), (0,)))
        job = {'native_edge_intervals': [[[0., 0., 0.], [2., 2., 0.]],
                                        [[0., 0., 0.], [3., 3., 0.]]],
               'native_cross_intervals': [[[-1., -1., -1.], [1., 1., 1.]]]}
        boxes.check_relaxed_witness(proof, job)
        bad = copy.deepcopy(job); bad['native_edge_intervals'][0][0][0] = 1.5
        with self.assertRaises(ValueError):
            boxes.check_relaxed_witness(proof, bad)
        bad = copy.deepcopy(job); bad['native_cross_intervals'][0][0][0] = .1
        with self.assertRaises(ValueError):
            boxes.check_relaxed_witness(proof, bad)


class AcceptedAtlasGuardTests(unittest.TestCase):
    def test_exact_current_atlas_pair_is_required(self):
        # Actual accepted-v9 metadata, independently hash-checked in diagnostic49677.
        current = '1a404021b32f6c8f2ed91408a27e2894c18e82200150be91365db907c380e17e'
        predecessor = '764ba340905bd7f9f7cccec88564b294e9aeaa3e227f0b3206d5d8fa788c9405'
        boxes.validate_atlas_binding(current, current)
        for atlas, packet in [(predecessor, predecessor), (current, predecessor),
                              (predecessor, current), ('bad', current), (current, None)]:
            with self.subTest(atlas=atlas, packet=packet), self.assertRaises(ValueError):
                boxes.validate_atlas_binding(atlas, packet)


if __name__ == '__main__':
    unittest.main()
