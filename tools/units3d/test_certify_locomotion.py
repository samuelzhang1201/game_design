"""Hand-computed fixtures for the per-arm locomotion certifier (no Godot)."""
import base64
import copy
import hashlib
import json
import math
import unittest

import numpy as np

import certify_locomotion as cert

PHASES = [0.0, .25, .5, .75, 1.0]
HOLD = 'STANDBY'
R = math.hypot(.1, .1)  # xz radius of sole vertex b


def enc(array, dtype):
    return base64.b64encode(np.asarray(array, dtype=dtype).tobytes()).decode()


def move(x=0., y=0., z=0., yaw=0.):
    c, s = math.cos(yaw), math.sin(yaw)  # rows of Godot Basis(UP, yaw) | origin
    return [[c, 0, s, x], [0, 1, 0, y], [-s, 0, c, z]]


# Bones: 0 root, 1 foot_l, 2 foot_r. MARCH is a loop: the left sole stands for
# phases 0..0.5 (0.3 mm up, inside the 0.5 mm band, drifting 0.01 m per quarter in
# the world), the right only at 0.75 (0.4 mm up). Each pivot keeps the left sole
# 4 mm below the seat, counter-rotating 180 degrees over the clip; the right foot
# hangs 30 mm up and touches down (0.35 mm) once, at phase 0.5.
MARCH = {0.0: (0, .0003, 0, .04), .25: (0, .0003, -.24, .04), .5: (0, .0003, -.48, .04),
         .75: (0, .05, -.24, .0004), 1.0: (0, .0003, 0, .04)}
MARCH[cert.LOOP_END] = MARCH[1.0]


def pose(clip, phase):
    if clip == HOLD:  # standing still in MARCH's phase-0 pose
        return pose('MARCH', 0.0)
    if clip == 'MARCH':
        _, yl, zl, yr = MARCH[phase]
        return [move(), move(y=yl, z=zl), move(y=yr)]
    sign = 1 if clip == 'PIVOT_RIGHT' else -1
    return [move(), move(y=-.004, yaw=sign * math.pi * phase), move(y=PIVOT_TOUCH[0] if phase == .5 else .03)]


PIVOT_TOUCH = [.00035]  # the pivot's right-foot touchdown height (a test may lift it)


def sample(clip, phase, bones=None, provider=False):
    return {'clip': clip, 'phase': phase, 'time_s': phase, 'turn_udeg': None, 'provider': provider,
            'globals_f64': enc(bones or pose(clip, phase), '<f8')}


def fixture(root_vertex_y=.5):
    eye = np.eye(4).tolist()
    # a, b: left sole; c, d: right sole; e: head; f (root), g (right foot): a short
    # skin edge, half a metre up so it never touches the ground.
    vertices = [[-.1, 0, 0], [-.1, 0, .1], [.1, 0, 0], [.1, 0, .1], [0, 1, 0], [0, root_vertex_y, 0], [.01, .5, 0]]
    bones = [[1, 0], [1, 0], [2, 0], [2, 0], [0, 0], [0, 0], [2, 0]]
    weights = [[1, 0]] * 7
    return {'godot': {}, 'skeleton_to_model': eye,
            'bones': [{'name': n, 'parent': -1, 'global_rest': eye} for n in ('root', 'foot_l', 'foot_r')],
            'meshes': [{'name': 'body', 'skin': [{'bone': i, 'name': '', 'pose': eye} for i in range(3)],
                        'surfaces': [{'vertices_f32': enc(vertices, '<f4'), 'bones_i32': enc(bones, '<i4'),
                                      'weights_f32': enc(weights, '<f4'),
                                      'indices_i32': enc([[0, 1, 4], [2, 3, 4], [5, 6, 4]], '<i4')}]}],
            'clips': {c: {'length_s': 1.0, 'key_times': [0.0, 1.0], 'loop_mode': int(c != 'PIVOT_LEFT' and c != 'PIVOT_RIGHT')}
                      for c in cert.CLIPS + [HOLD]},
            'samples': [sample(c, p) for c in cert.CLIPS + [HOLD] for p in PHASES]
            + [sample('MARCH', cert.LOOP_END)]}



CONFIG = {'arm': 'fixture', 'feet': {'l': ['foot_l'], 'r': ['foot_r']}, 'patch_band_m': .001,
          'forward': [0, 0, 1], 'stride_m': 1.0, 'turn_q': 400_000, 'radius_m': 731,
          'hold_clip': HOLD, 'march_stop_phases': [0.0], 'march_start_phases': [0.0], 'hold_phases': '*',
          'boundaries': [['MARCH', '*', 'PIVOT_LEFT', 0.0]]}
SCALE = {'k': 25.0, 'simulation_scale': 1000.0, 'lift_model_m': .001}


class Bounds(unittest.TestCase):
    def test_ruled_per_arm_bounds(self):
        # owner-rulings-2026-11-10.md R-A: ceil(0.60e6 / k), ceil(0.05e6 / k)
        for k, contact, seam in [(26.3519187631584, 22769, 1898), (21.0718843818879, 28474, 2373),
                                 (20.4973086159768, 29273, 2440), (20.4518119986627, 29338, 2445)]:
            self.assertEqual(cert.bounds_um(k), {'contact': contact, 'seam': seam})
        self.assertEqual(cert.bounds_um(25.0), {'contact': 24000, 'seam': 2000})

    def test_micrometres_round_up(self):
        self.assertEqual(cert.um(.0011), 1100)
        self.assertEqual(cert.um(.00110001), 1101)
        self.assertEqual(cert.um(0.0), 0)


class MarchTravel(unittest.TestCase):
    def test_phase_map_by_hand(self):
        # the cavalry contract's synthetic f: (0,0), (.5,1), (1,3); F(z) = floor(z) 3 + f(frac z)
        f = cert.march_travel([[0, 0], [.5, 1], [1, 3]], 9.0)
        self.assertAlmostEqual(f(.25), .5)
        self.assertAlmostEqual(f(.75), 2.0)
        self.assertAlmostEqual(f(1.75), 5.0)
        self.assertAlmostEqual(f(1.0), 3.0)

    def test_no_map_is_the_constant_stride(self):
        self.assertAlmostEqual(cert.march_travel(None, 2.0)(1.25), 2.5)

    def test_a_map_must_rise_from_zero_to_one(self):
        for bad in ([[0, 0], [.5, 1], [.9, 3]], [[0, 0], [.5, 2], [1, 1]], [[.1, 0], [1, 3]]):
            with self.assertRaises(ValueError):
                cert.march_travel(bad, 1.0)

    def test_cavalry_reads_its_army_art_map(self):
        m = cert.army_phase_map('cavalry')
        self.assertEqual(m[0], [0.0, 0.0])
        self.assertEqual(m[-1][0], 1.0)
        self.assertIsNone(cert.army_phase_map('infantry'))


class Turns(unittest.TestCase):
    def test_tie_wrap_and_microdegree(self):
        self.assertEqual(cert.shortest(0, 180_000_000), 180_000_000)
        self.assertEqual(cert.shortest(180_000_000, 0), 180_000_000)  # tie turns positive both ways
        self.assertEqual(cert.shortest(359_000_000, 1_000_000), 2_000_000)
        self.assertEqual(cert.shortest(1_000_000, 359_000_000), -2_000_000)
        self.assertEqual((cert.shortest(0, 1), cert.shortest(1, 0)), (1, -1))
        grid = {g['name']: g['turn_udeg'] for g in cert.turn_grid()}
        self.assertEqual(grid['180 tie reversed'], 180_000_000)
        self.assertEqual(grid['-179.999999'], -179_999_999)
        self.assertEqual(cert.clip_for(180_000_000), 'PIVOT_RIGHT')
        self.assertEqual(cert.clip_for(-1), 'PIVOT_LEFT')
        self.assertNotIn(0, grid.values())

    def test_duration_is_bodymotion_ceiling(self):
        # cf04c-locomotion-contract: 359 -> 1 is 2_000_000 udeg, 2_223 quanta (ceil 2222.2)
        self.assertEqual(cert.duration_q(2_000_000, 400_000), 2223)
        self.assertEqual(cert.duration_q(-1, 400_000), 1)
        self.assertEqual(cert.duration_q(180_000_000, 400_000), 200_000)


class Pieces(unittest.TestCase):
    def test_raw_weights_are_not_normalized(self):
        m = np.repeat(np.eye(4)[None], 2, axis=0)
        m[:, 0, 3] = [2, 4]
        out = cert.skin(np.array([[1., 0, 0]]), np.array([[0, 1]]), np.array([[.25, .5]]), m)
        np.testing.assert_allclose(out, [[3.25, 0, 0]], atol=0)  # .25*3 + .5*5
        for bad in ([[float('nan'), .5]], [[-.1, .5]]):
            with self.assertRaises(ValueError):
                cert.skin(np.array([[1., 0, 0]]), np.array([[0, 1]]), np.array(bad), m)

    def test_rot_y_is_godot_basis(self):
        out = cert.rot_y(np.array([[1., 0, 0]]), math.pi / 2)
        np.testing.assert_allclose(out, [[0, 0, -1]], atol=1e-15)  # Basis(UP, 90deg) * +X = -Z

    def test_stance_runs_lowest_band_and_loop_merge(self):
        heights = {'l': [0, 0, 5, 5, 0], 'r': [5, 5, 0, 0, 5]}
        runs = cert.stance_runs(heights, PHASES, ('lowest', 1), 'l', loop=True)
        self.assertEqual(runs, [[4, 0, 1]])
        self.assertEqual(cert.stance_runs(heights, PHASES, ('lowest', 1), 'l', loop=False), [[0, 1], [4]])
        self.assertEqual(cert.stance_runs(heights, PHASES, ('lowest', 2), 'r', loop=False), [[0, 1, 2, 3, 4]])
        self.assertEqual(cert.stance_runs(heights, PHASES, ('band', 5), 'r', loop=False), [[0, 1, 2, 3, 4]])
        self.assertEqual(cert.stance_runs(heights, PHASES, ('band', 4.9), 'r', loop=True), [[2, 3]])

    def test_planting_band_is_per_foot_and_inherited_from_native_march(self):
        # Metres. Lower-foot runs (no loop): l at 0..1 (min 1.0 mm) and at 4 (0.2 mm),
        # r at 2..3 (min 2.26 mm). Per foot: H_l = 1.0 mm -> b_l 1.5 mm; H_r = 2.26 mm
        # (the infantry case) -> b_r 2.76 mm.
        heights = {'l': [.0010, .0012, .0080, .0090, .0002], 'r': [.0050, .0060, .00226, .0030, .0040]}
        bands = cert.planting_band(heights, PHASES, loop=False)
        self.assertAlmostEqual(bands['l'][0], .0010, places=12)
        self.assertAlmostEqual(bands['l'][1], .0015, places=12)
        self.assertAlmostEqual(bands['r'][0], .00226, places=12)
        self.assertAlmostEqual(bands['r'][1], .00276, places=12)
        # Looping, l's runs 4 and 0..1 are ONE stance (min 0.2 mm): b_l = 0.7 mm.
        self.assertAlmostEqual(cert.planting_band(heights, PHASES, loop=True)['l'][1], .0007, places=12)
        # Stances under the plane (l to -1 mm, r to -2 mm): both bands are the 0.5 mm floor.
        low = {'l': [0, -.001, .01, .01, 0], 'r': [.01, .01, -.002, 0, .01]}
        self.assertEqual(cert.planting_band(low, PHASES, loop=True), {'l': (-.001, .0005), 'r': (-.002, .0005)})
        # Four hooves: a stance is among the lower two; c's lowest is 1 mm, d's 2 mm.
        hooves = {'a': [0, 0, 9, 9], 'b': [0, 0, 9, 9], 'c': [9, 9, .001, .003], 'd': [9, 9, .002, .002]}
        got = cert.planting_band(hooves, PHASES[:4], loop=False)
        self.assertEqual({f: round(h, 6) for f, (h, _) in got.items()}, {'a': 0, 'b': 0, 'c': .001, 'd': .002})
        with self.assertRaises(ValueError):  # a foot that never stands has no band to inherit
            cert.planting_band({'l': [0, 0], 'r': [1, 1]}, [0, .5], loop=False)

    def test_a_vertex_belongs_to_its_dominant_bone(self):
        # binds map slots to skeleton bones 7, 3, 5. Vertex 0: 0.6 on bone 7 -> 7.
        # Vertex 1: 0.5 / 0.5 on bones 7 and 3 -> the tie goes to the lower index, 3.
        # Vertex 2: 0.25 on 5, 0.75 on 3 -> 3.
        binds = [(7, None), (3, None), (5, None)]
        joints = np.array([[0, 1], [0, 1], [2, 1]])
        weights = np.array([[.6, .4], [.5, .5], [.25, .75]])
        self.assertEqual(cert.dominant_bones(joints, weights, binds).tolist(), [7, 3, 3])
        # Weights are summed per bone: .3 + .3 on bone 7 (two slots) beat .4 on bone 3.
        # A vertex with no weight belongs to no bone.
        self.assertEqual(cert.dominant_bones(np.array([[0, 0, 1], [0, 1, 2]]),
                                             np.array([[.3, .3, .4], [0, 0, 0]]), binds).tolist(), [7, -1])

    def test_a_bone_under_two_feet_is_rejected(self):
        with self.assertRaises(ValueError):
            cert.measure(fixture(), dict(CONFIG, feet={'l': ['foot_l'], 'r': ['foot_r', 'foot_l']}), SCALE)

    def test_margin_adds_before_rounding(self):
        w = cert.Worst()
        w.offer(.0101, 'a')
        w.offer(.0100, 'b')
        w.widen(.0005)
        self.assertEqual(w.report(10600), {'sampled_um': 10100, 'margin_um': 500, 'total_um': 10600,
                                           'bound_um': 10600, 'pass': True, 'witness': 'a'})
        self.assertFalse(w.report(10599)['pass'])

    def test_coverage_names_a_missing_quarter(self):
        dump = {'clips': {'MARCH': {'length_s': 2.0, 'key_times': [0.0, 1.0, 2.0], 'loop_mode': 1}},
                'samples': [{'clip': 'MARCH', 'phase': i / cert.UNIFORM} for i in range(cert.UNIFORM + 1)]}
        dump['samples'] += [{'clip': 'MARCH', 'phase': p} for p in (.125, .375, .625, .875, .7)]
        self.assertEqual(cert.check_coverage(dump, [.7]), [])
        self.assertEqual(cert.check_coverage(dump, [.71]), [{'clip': 'MARCH', 'turn_udeg': None, 'phase': .71}])
        dump['samples'] = [s for s in dump['samples'] if s['phase'] != .125]
        self.assertEqual(cert.check_coverage(dump, [])[0]['phase'], .125)

    def test_dependency_closure_of_the_archer_scene(self):
        files = cert.closure(['scenes/models/units/archers.tscn'])
        for rel in ('assets/3D/units/archers/archers.glb', 'assets/3D/units/archers/archers.glb.import',
                    'tools/units3d/archer_arp/pivot_import.gd', 'assets/3D/units/archers/archers_bow.res'):
            self.assertIn(rel, files)
        self.assertFalse(any(f.startswith('.godot/') for f in files))

    def test_dependency_closure_of_the_infantry_provider(self):
        # map3d_infantry_pivot.gd ends a comment sentence with a res:// path and a full stop.
        files = cert.closure(['scripts/map3d/map3d_infantry_locomotion.gd'])
        for rel in ('scripts/map3d/map3d_infantry_pivot.gd', 'scripts/map3d/guide/infantry_pivot.md',
                    'assets/3D/units/infantry/infantry_pivot_plan.json'):
            self.assertIn(rel, files)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.report = cert.measure(fixture(), CONFIG, SCALE)

    def test_penetration_with_velocity_margin(self):
        # lowest vertex: pivot sole at -0.004, ground at -0.001 -> 3 mm deep;
        # largest one-step height change: left sole 0.0003 <-> 0.05 = 49.7 mm.
        pen = self.report['penetration']
        self.assertEqual((pen['sampled_um'], pen['margin_um'], pen['total_um']), (3000, 49700, 52700))
        self.assertEqual(pen['bound_um'], 24000)
        self.assertFalse(pen['pass'])
        self.assertIn(pen['witness']['clip'], ('PIVOT_LEFT', 'PIVOT_RIGHT'))

    def test_hover_on_the_seated_plane(self):
        hov = self.report['hover']  # right MARCH stance 0.4 mm; no stance height changes within a stance
        self.assertEqual((hov['sampled_um'], hov['margin_um'], hov['total_um'], hov['pass']), (400, 0, 400, True))
        self.assertEqual((hov['witness']['clip'], hov['witness']['foot']), ('MARCH', 'r'))

    def test_slide_worst_is_the_microdegree_pivot(self):
        # Net planted yaw (pi - theta) p; theta = 1 microdegree. Chord at p = 1 is
        # 2 R sin(a/2). The pivot's own margin is twice one quarter step's chord of
        # a planted sole vertex, 2 x 2 R sin(pi/8) (the right sole touching down at
        # the 180 tie); the pooled margin is MARCH's, twice its coarse lift-off step.
        a = math.pi - math.radians(1e-6)
        sld = self.report['slide']
        pivot = sld['by_clip']['PIVOT_RIGHT']
        self.assertEqual(sld['sampled_um'], cert.um(2 * R * math.sin(a / 2)))
        self.assertEqual(pivot['sampled_um'], sld['sampled_um'])
        self.assertEqual(pivot['margin_um'], cert.um(4 * R * math.sin(math.pi / 8)))
        self.assertEqual(sld['margin_um'], 980000)
        self.assertEqual(abs(sld['witness']['turn_udeg']), 1)
        self.assertEqual(sld['witness']['phase'], 1.0)
        self.assertFalse(sld['pass'])

    def test_march_slide_crosses_the_loop_seam(self):
        # The left stance LOOP_END, 1.0, 0, .25, .5 is ONE stance: world z = zl + stride
        # * (phase + cycle) = 0.999999, 1.00, 1.00, 1.01, 1.02 -> 20.001 mm. The margin
        # is twice the largest entry/exit step: lift-off .5 -> .75 moves sole a from
        # z .02 to .51 (0.49 m), so 0.98 m.
        sld = self.report['slide']['by_clip']['MARCH']
        self.assertEqual((sld['sampled_um'], sld['margin_um'], sld['total_um']), (20001, 980000, 1000001))
        self.assertEqual((sld['witness']['touchdown_phase'], sld['witness']['phase']), (cert.LOOP_END, .5))
        self.assertFalse(sld['pass'])

    def test_seams_are_the_full_required_list(self):
        seams = {(tuple(x['witness']['from'][:1]), tuple(x['witness']['to'][:1])): [] for x in
                 self.report['seam']['boundaries']}
        for x in self.report['seam']['boundaries']:
            seams[(tuple(x['witness']['from'][:1]), tuple(x['witness']['to'][:1]))].append(x)
        # loop seam (last pose before the wrap) + per pivot: stop, start, hold -> pivot,
        # pivot -> hold; then stop and start to the hold; then the extra sweep.
        self.assertEqual(len(self.report['seam']['boundaries']), 1 + 2 * 4 + 2 + 1)
        self.assertEqual(self.report['seam']['boundaries'][0]['witness']['from'], ['MARCH', cert.LOOP_END])
        self.assertEqual(self.report['seam']['boundaries'][0]['total_um'], 0)
        for pivot in ('PIVOT_LEFT', 'PIVOT_RIGHT'):
            self.assertEqual(seams[(('MARCH',), (pivot,))][0]['total_um'], 10000)  # right foot 0.04 -> 0.03
            # Pivot end: the left sole turned half round; b (-.1, .0003, .1) vs (.1, -.004, -.1).
            end = cert.um(math.sqrt(.2 ** 2 + .0043 ** 2 + .2 ** 2))
            self.assertEqual([x['sampled_um'] for x in seams[((pivot,), ('MARCH',))]], [end])
            self.assertEqual([x['sampled_um'] for x in seams[((pivot,), (HOLD,))]], [end])
            # The hold stands in MARCH 0's pose at every phase: its sweep has no margin.
            hold = seams[((HOLD,), (pivot,))][0]
            self.assertEqual((hold['sampled_um'], hold['margin_um']), (10000, 0))
        self.assertEqual([x['total_um'] for x in seams[(('MARCH',), (HOLD,))]], [0])
        self.assertEqual([x['total_um'] for x in seams[((HOLD,), ('MARCH',))]], [0])
        # A cut from any MARCH phase: worst at 0.5 (z 0.48, y 0.0043); margin = the
        # largest MARCH step, 0.5 -> 0.75: dz 0.24, dy 0.0497.
        cut = self.report['seam']['boundaries'][-1]
        self.assertEqual(cut['witness']['from'], ['MARCH', .5])
        self.assertEqual(cut['sampled_um'], cert.um(math.hypot(.48, .0043)))
        self.assertEqual(cut['margin_um'], cert.um(math.hypot(.24, .0497)))
        self.assertEqual(self.report['seam']['total_um'], cut['total_um'])
        self.assertEqual(self.report['seam']['bound_um'], 2000)
        self.assertFalse(self.report['seam']['pass'])

    def test_config_cannot_drop_a_required_seam(self):
        config = dict(CONFIG, boundaries=[])
        self.assertEqual(len(cert.measure(fixture(), config, SCALE)['seam']['boundaries']), 11)
        for bad in [dict(CONFIG, march_start_phases='*'), dict(CONFIG, march_stop_phases=[]),
                    dict(CONFIG, hold_phases=[1.5])]:
            with self.assertRaises(ValueError):
                cert.measure(fixture(), bad, SCALE)
        config = dict(CONFIG, hold_phases=[0.0], march_stop_phases='*')
        self.assertEqual(cert.required_boundaries(config)[1], ['MARCH', '*', 'PIVOT_LEFT', 0.0])

    def test_march_hold_at_the_admitted_phase(self):
        # Stop, start and hold only at MARCH 0: the held pose IS MARCH 0 (stopped in)
        # or the pivot's end (turned into), so no seam is added beyond the loop seam
        # and stop/start per pivot.
        config = dict(CONFIG, hold_clip='MARCH', hold_phases=[0.0], boundaries=[])
        report = cert.measure(fixture(), config, SCALE)
        self.assertEqual(len(report['seam']['boundaries']), 5)
        self.assertEqual(cert.required_boundaries(config), [['MARCH', cert.LOOP_END, 'MARCH', 0.0]] + [
            b for p in ('PIVOT_LEFT', 'PIVOT_RIGHT') for b in (['MARCH', 0.0, p, 0.0], [p, 1.0, 'MARCH', 0.0])])
        for bad in [dict(config, hold_phases='*'), dict(config, hold_phases=[.5])]:
            with self.assertRaises(ValueError):
                cert.required_boundaries(bad)
        # Stop at 0, start at 0.5: a unit that turned holds MARCH 0.5 and may turn
        # again, so MARCH(0.5) -> PIVOT(0) is required although 0.5 is no stop phase.
        seams = cert.required_boundaries(dict(config, march_start_phases=[.5], hold_phases=[.5]))
        for pivot in ('PIVOT_LEFT', 'PIVOT_RIGHT'):
            self.assertIn(['MARCH', .5, pivot, 0.0], seams)
            self.assertIn([pivot, 1.0, 'MARCH', .5], seams)
            self.assertNotIn([pivot, 1.0, 'MARCH', 0.0], seams)  # a pivot never ends into the 0 hold

    def test_a_separate_hold_clip_uses_its_own_phase(self):
        config = dict(CONFIG, hold_phases=[.25], boundaries=[])
        seams = cert.required_boundaries(config)
        self.assertIn(['PIVOT_LEFT', 1.0, HOLD, .25], seams)
        self.assertIn(['MARCH', 0.0, HOLD, .25], seams)
        self.assertNotIn(['MARCH', 0.0, HOLD, 0.0], seams)

    def test_a_foot_that_never_stands_fails(self):
        self.assertTrue(self.report['stance']['pass'])
        PIVOT_TOUCH[0] = .03  # the pivot's right foot never comes within the 0.9 mm band
        try:
            report = cert.measure(fixture(), CONFIG, SCALE)
        finally:
            PIVOT_TOUCH[0] = .00035
        self.assertEqual(report['stance']['missing'],
                         [{'clip': c, 'turn_udeg': None, 'foot': 'r', 'reason': 'no stance'}
                          for c in ('PIVOT_LEFT', 'PIVOT_RIGHT')])
        self.assertFalse(report['pass'])

    def test_a_vertex_of_no_foot_is_never_planted(self):
        # Root-bound vertex f put on the ground: it rides the body 1.5 stride per
        # cycle through the band, but belongs to no foot, so slide ignores it; only
        # penetration (whole mesh) sees it.
        report = cert.measure(fixture(root_vertex_y=0.0), CONFIG, SCALE)
        self.assertEqual(report['slide']['by_clip']['MARCH']['sampled_um'], 20001)
        self.assertEqual(report['slide']['sampled_um'], self.report['slide']['sampled_um'])

    def test_the_band_follows_the_native_march(self):
        # Lift every MARCH stance 1 mm: H = 1.4 mm, b = 1.9 mm, and the soles are
        # still planted, so the MARCH stance slide is still measured.
        saved = dict(MARCH)
        try:
            for phase, (x, yl, zl, yr) in saved.items():
                MARCH[phase] = (x, yl + .001 if yl < .001 else yl, zl, yr + .001 if yr < .001 else yr)
            report = cert.measure(fixture(), CONFIG, SCALE)
        finally:
            MARCH.update(saved)
        feet = report['planting_band']['feet']  # each foot lifted 1 mm: l 1.3 -> 1.8 mm, r 1.4 -> 1.9 mm
        self.assertAlmostEqual(feet['l']['band_m'], .0018, places=12)
        self.assertAlmostEqual(feet['r']['band_m'], .0019, places=12)
        self.assertTrue(report['stance']['pass'])
        self.assertEqual(report['slide']['by_clip']['MARCH']['sampled_um'], 20001)

    def test_envelope_against_the_footprint(self):
        env = self.report['envelope']  # sole a at z -0.48: r = hypot(.1, .48); margin 0.24 step
        self.assertEqual((env['radius_model_um'], env['margin_um']), (cert.um(math.hypot(.1, .48)), 240000))
        self.assertEqual(env['radius_simulation_m'], math.ceil((math.hypot(.1, .48) + .24) * 1000))
        self.assertEqual(env['radius_simulation_m'], 731)
        self.assertTrue(env['pass'])
        config = dict(CONFIG, radius_m=730)
        self.assertFalse(cert.measure(fixture(), config, SCALE)['envelope']['pass'])

    def test_native_skin_flags_are_never_introduced(self):
        skin = self.report['skin']
        self.assertEqual((skin['flagged_pairs_introduced'], skin['pass']), (0, True))

    def test_turn_grid_durations_recorded(self):
        grid = {g['name']: g for g in self.report['turn_grid']}
        self.assertEqual(grid['359 to 1 wrap']['duration_q'], 2223)
        self.assertEqual(grid['180 tie']['clip'], 'PIVOT_RIGHT')
        self.assertFalse(self.report['pass'])

    def test_slide_is_reported_per_clip(self):
        by = self.report['slide']['by_clip']
        self.assertEqual(sorted(by), ['MARCH', 'PIVOT_LEFT', 'PIVOT_RIGHT'])
        self.assertEqual(by['MARCH']['total_um'], 1000001)
        self.assertEqual(by['PIVOT_LEFT']['sampled_um'], by['PIVOT_RIGHT']['sampled_um'])  # mirror clips
        feet = self.report['planting_band']['feet']  # native MARCH stances: l at 0.3 mm, r at 0.4 mm
        self.assertAlmostEqual(feet['l']['H_m'], .0003, places=12)
        self.assertAlmostEqual(feet['l']['band_m'], .0008, places=12)
        self.assertAlmostEqual(feet['r']['H_m'], .0004, places=12)
        self.assertAlmostEqual(feet['r']['band_m'], .0009, places=12)
        self.assertEqual(self.report['slide']['band_m'], {f: feet[f]['band_m'] for f in 'lr'})
        self.assertEqual(self.report['planting_band']['inherited_from'], 'shipped native MARCH')


class VertexSlide(unittest.TestCase):
    """The per-vertex rule (ruling 2026-11-11), by hand: three vertices, five samples."""

    def test_roll_is_not_slide_and_skating_is(self):
        band = cert.STANCE_BAND_M
        up = .01
        # heel h: down at 0..1, then lifts and travels (not planted, not counted).
        # toe t: touches down at sample 2 at x = .05 and stays put (roll: 0).
        # skate s: down 0..3 while drifting 0, 1, 2 mm, then lifts: slide 2 mm.
        # The margin is twice the largest entry/exit step: s lifting off 3 -> 4 moves
        # 98 mm (the heel's lift-off 1 -> 2 moves 30 mm), so 196 mm.
        heights = np.array([[0, up, 0], [0, up, 0], [up, 0, 0], [up, 0, 0], [up, 0, up]], dtype=float)
        x = np.array([[0, .05, .2], [0, .05, .2], [.03, .05, .201], [.06, .05, .202], [.09, .05, .3]])
        xz = np.stack([x, np.zeros_like(x)], axis=2)
        value, margin, witness = cert.vertex_slide(heights, xz, band)
        self.assertAlmostEqual(value, .002, places=12)
        self.assertAlmostEqual(margin, .196, places=12)
        self.assertEqual(witness, (3, 2, 0))  # sample 3, vertex s, touched down at 0
        # a vertex that leaves and re-enters the band is anchored afresh (slide 0;
        # its largest out-and-back step, 0.5, gives the margin 1.0)
        heights = np.array([[0], [up], [0]], dtype=float)
        xz = np.array([[[0, 0]], [[.5, 0]], [[.007, 0]]], dtype=float)
        self.assertEqual(cert.vertex_slide(heights, xz, band)[:2], (0.0, 1.0))
        # exactly at the band edge is planted
        heights = np.array([[band], [band]])
        xz = np.array([[[0, 0]], [[0, .003]]], dtype=float)
        self.assertAlmostEqual(cert.vertex_slide(heights, xz, band)[0], .003, places=12)


class Provider(unittest.TestCase):
    def test_introduced_and_inherited_skin_flags(self):
        # Edge f-g: entry (MARCH 0) length hypot(.01, .04) = 41.2 mm; flag above
        # 4x = 164.9 mm and 30 mm. Provider MARCH 0.5 lifts the right foot 0.5 m.
        dump = fixture()
        provided = [sample('MARCH', p, provider=True) for p in PHASES + [cert.LOOP_END]]
        for g in cert.turn_grid():  # the provider poses every grid turn like the native seek
            clip = cert.clip_for(g['turn_udeg'])
            provided += [dict(sample(clip, p, provider=True), turn_udeg=g['turn_udeg']) for p in PHASES]
        lifted = pose('MARCH', .5)
        lifted[2] = move(y=.5)
        provided[2] = sample('MARCH', .5, lifted, provider=True)
        dump['samples'] += provided
        config = dict(CONFIG, provider='x.gd', boundaries=[])
        skin = cert.measure(copy.deepcopy(dump), config, SCALE)['skin']
        self.assertEqual((skin['flagged_pairs_introduced'], skin['pass']), (1, False))
        self.assertEqual(skin['introduced_witnesses'][0]['edge'], [5, 6])
        self.assertEqual(skin['introduced_witnesses'][0]['phase'], .5)
        self.assertFalse(cert.measure(copy.deepcopy(dump), config, SCALE)['seam']['pass'])  # no boundary
        # The same stretch in the native seek is inherited, not introduced.
        dump['samples'] = [sample('MARCH', .5, lifted) if s['clip'] == 'MARCH' and s['phase'] == .5
                           and not s['provider'] else s for s in dump['samples']]
        skin = cert.measure(dump, config, SCALE)['skin']
        self.assertEqual((skin['flagged_pairs_introduced'], skin['flagged_pairs_inherited']), (0, 1))


class Certificate(unittest.TestCase):
    def test_digest_binding(self):
        report = {'pass': True, 'bounds_um': {'contact': 22769, 'seam': 1898}}
        config = {'arm': 'infantry', 'turn_q': 400_000, 'radius_m': 927, 'hold_clip': 'MARCH',
                  'march_stop_phases': [0.0], 'march_start_phases': [0.0], 'hold_phases': [0.0]}
        body = cert.certificate(config, report, {}, {}, 'c' * 64, {'godot': {}, 'clips': {}})
        loco = body.pop('locomotion_certificate')
        self.assertEqual(loco, {'digest': body['payload_sha256'], 'turn_q': 400_000, 'contact_um': 22769,
                                'radius_m': 927, 'clips': ['PIVOT_LEFT', 'PIVOT_RIGHT', 'MARCH'],
                                'all_turns': True})
        digest = body.pop('payload_sha256')
        body.pop('digest_rule')
        self.assertEqual(hashlib.sha256(json.dumps(body, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
                         digest)
        self.assertEqual({k: v for k, v in body['consumer_requirements'].items() if k != 'rule'},
                         {'hold_clip': 'MARCH', 'march_stop_phases': [0.0], 'march_start_phases': [0.0],
                          'hold_phases': [0.0]})
        self.assertIn('resumes at the phase it holds', body['consumer_requirements']['rule'])
        failed = cert.certificate(config, dict(report, **{'pass': False}), {}, {}, 'c' * 64, {'godot': {}, 'clips': {}})
        self.assertIsNone(failed['locomotion_certificate'])
        self.assertEqual(failed['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
