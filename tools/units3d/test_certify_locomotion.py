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
# phases 0..0.5 (2 mm up, drifting 0.01 m per quarter in the world), the right
# only at 0.75 (1 mm up). Each pivot keeps the left sole 4 mm below the seat,
# counter-rotating 180 degrees over the clip; the right foot hangs 30 mm up.
MARCH = {0.0: (0, .002, 0, .04), .25: (0, .002, -.24, .04), .5: (0, .002, -.48, .04),
         .75: (0, .05, -.24, .001), 1.0: (0, .002, 0, .04)}
MARCH[cert.LOOP_END] = MARCH[1.0]


def pose(clip, phase):
    if clip == HOLD:  # standing still in MARCH's phase-0 pose
        return pose('MARCH', 0.0)
    if clip == 'MARCH':
        _, yl, zl, yr = MARCH[phase]
        return [move(), move(y=yl, z=zl), move(y=yr)]
    sign = 1 if clip == 'PIVOT_RIGHT' else -1
    # the right foot touches down (1.5 mm up) once, at phase 0.5
    return [move(), move(y=-.004, yaw=sign * math.pi * phase), move(y=.0015 if phase == .5 else .03)]


def sample(clip, phase, bones=None, provider=False):
    return {'clip': clip, 'phase': phase, 'time_s': phase, 'turn_udeg': None, 'provider': provider,
            'globals_f64': enc(bones or pose(clip, phase), '<f8')}


def fixture():
    eye = np.eye(4).tolist()
    # a, b: left sole; c, d: right sole; e: head; f (root), g (right foot): a short seam edge.
    vertices = [[-.1, 0, 0], [-.1, 0, .1], [.1, 0, 0], [.1, 0, .1], [0, 1, 0], [0, 0, 0], [.01, 0, 0]]
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


PIVOT_STANCE = {'l': [[0, 1]], 'r': [[.5, .5]]}


CONFIG = {'arm': 'fixture', 'feet': {'l': ['foot_l'], 'r': ['foot_r']}, 'patch_band_m': .001,
          'forward': [0, 0, 1], 'stride_m': 1.0, 'turn_q': 400_000, 'radius_m': 731,
          'stance': {'MARCH': 'lowest:1', 'PIVOT_LEFT': PIVOT_STANCE, 'PIVOT_RIGHT': PIVOT_STANCE},
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

    def test_stance_runs_lowest_and_loop_merge(self):
        heights = {'l': [0, 0, 5, 5, 0], 'r': [5, 5, 0, 0, 5]}
        runs = cert.stance_runs(heights, PHASES, 'lowest:1', 'l', loop=True)
        self.assertEqual(runs, [[4, 0, 1]])
        self.assertEqual(cert.stance_runs(heights, PHASES, 'lowest:1', 'l', loop=False), [[0, 1], [4]])
        self.assertEqual(cert.stance_runs(heights, PHASES, {'l': [[.25, .75]]}, 'l', loop=False), [[1, 2, 3]])
        self.assertEqual(cert.stance_runs(heights, PHASES, 'lowest:2', 'r', loop=False), [[0, 1, 2, 3, 4]])

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


class Fixture(unittest.TestCase):
    def setUp(self):
        self.report = cert.measure(fixture(), CONFIG, SCALE)

    def test_penetration_with_velocity_margin(self):
        # lowest vertex: pivot sole at -0.004, ground at -0.001 -> 3 mm deep;
        # largest one-step height change: left sole 0.002 <-> 0.05 = 48 mm.
        pen = self.report['penetration']
        self.assertEqual((pen['sampled_um'], pen['margin_um'], pen['total_um']), (3000, 48000, 51000))
        self.assertEqual(pen['bound_um'], 24000)
        self.assertFalse(pen['pass'])
        self.assertIn(pen['witness']['clip'], ('PIVOT_LEFT', 'PIVOT_RIGHT'))

    def test_hover_on_the_seated_plane(self):
        hov = self.report['hover']  # left MARCH stance 2 mm; stance heights never change
        self.assertEqual((hov['sampled_um'], hov['margin_um'], hov['total_um'], hov['pass']), (2000, 0, 2000, True))
        self.assertEqual((hov['witness']['clip'], hov['witness']['foot']), ('MARCH', 'l'))

    def test_slide_worst_is_the_microdegree_pivot(self):
        # Net planted yaw (pi - theta) p; theta = 1 microdegree. Chord at p = 1 is
        # 2 R sin(a/2); the margin is one quarter step's chord, 2 R sin(a/8).
        a = math.pi - math.radians(1e-6)
        sld = self.report['slide']
        self.assertEqual(sld['sampled_um'], cert.um(2 * R * math.sin(a / 2)))
        self.assertEqual(sld['margin_um'], cert.um(2 * R * math.sin(a / 8)))
        self.assertEqual(sld['total_um'], cert.um(2 * R * math.sin(a / 2) + 2 * R * math.sin(a / 8)))
        self.assertEqual(abs(sld['witness']['turn_udeg']), 1)
        self.assertEqual(sld['witness']['phase'], 1.0)
        self.assertFalse(sld['pass'])

    def test_march_stance_crosses_the_loop_seam(self):
        # Left stance [LOOP_END, 1.0, 0, .25, .5] as ONE stance: world z = zl + stride *
        # (phase + cycle) = 0.999999, 1.00, 1.00, 1.01, 1.02 -> 20.001 mm from touchdown;
        # the largest step is 10 mm.
        config = copy.deepcopy(CONFIG)
        config['stance'].update({'PIVOT_LEFT': {}, 'PIVOT_RIGHT': {}})
        sld = cert.measure(fixture(), config, SCALE)['slide']
        self.assertEqual((sld['sampled_um'], sld['margin_um'], sld['total_um']), (20001, 10000, 30001))
        self.assertEqual((sld['witness']['touchdown_phase'], sld['witness']['phase']), (cert.LOOP_END, .5))
        self.assertFalse(sld['pass'])  # 30000 > contact_um 24000

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
            # Pivot end: the left sole turned half round; b (-.1, .002, .1) vs (.1, -.004, -.1).
            end = cert.um(math.sqrt(.2 ** 2 + .006 ** 2 + .2 ** 2))
            self.assertEqual([x['sampled_um'] for x in seams[((pivot,), ('MARCH',))]], [end])
            self.assertEqual([x['sampled_um'] for x in seams[((pivot,), (HOLD,))]], [end])
            # The hold stands in MARCH 0's pose at every phase: its sweep has no margin.
            hold = seams[((HOLD,), (pivot,))][0]
            self.assertEqual((hold['sampled_um'], hold['margin_um']), (10000, 0))
        self.assertEqual([x['total_um'] for x in seams[(('MARCH',), (HOLD,))]], [0])
        self.assertEqual([x['total_um'] for x in seams[((HOLD,), ('MARCH',))]], [0])
        # A cut from any MARCH phase: worst at 0.5 (z 0.48, y 0.006); margin = the
        # largest MARCH step, 0.5 -> 0.75: dz 0.24, dy 0.048.
        cut = self.report['seam']['boundaries'][-1]
        self.assertEqual(cut['witness']['from'], ['MARCH', .5])
        self.assertEqual(cut['sampled_um'], cert.um(math.hypot(.48, .006)))
        self.assertEqual(cut['margin_um'], cert.um(math.hypot(.24, .048)))
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

    def test_a_foot_that_never_stands_fails(self):
        self.assertTrue(self.report['stance']['pass'])
        config = copy.deepcopy(CONFIG)
        config['stance']['PIVOT_LEFT'] = {}
        report = cert.measure(fixture(), config, SCALE)
        self.assertFalse(report['stance']['pass'])
        self.assertEqual(report['stance']['missing'], [{'clip': 'PIVOT_LEFT', 'turn_udeg': None, 'foot': 'l'},
                                                       {'clip': 'PIVOT_LEFT', 'turn_udeg': None, 'foot': 'r'}])
        self.assertFalse(report['pass'])

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

    def test_contact_bound_reached_exactly(self):
        # One-sample pivot stances slide 0, so the MARCH stance (30001) is the worst
        # slide; a bound of exactly 30001 passes it.
        config = copy.deepcopy(CONFIG)
        config['stance']['PIVOT_LEFT'] = config['stance']['PIVOT_RIGHT'] = {'l': [[0, 0]], 'r': [[.5, .5]]}
        report = cert.measure(fixture(), config, {**SCALE, 'k': .6e6 / 30001})  # contact_um 30001
        self.assertEqual(report['bounds_um']['contact'], 30001)
        self.assertEqual(report['slide']['total_um'], 30001)
        self.assertTrue(report['slide']['pass'])


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
        config = {'arm': 'infantry', 'turn_q': 400_000, 'radius_m': 927}
        body = cert.certificate(config, report, {}, {}, 'c' * 64, {'godot': {}, 'clips': {}})
        loco = body.pop('locomotion_certificate')
        self.assertEqual(loco, {'digest': body['payload_sha256'], 'turn_q': 400_000, 'contact_um': 22769,
                                'radius_m': 927, 'clips': ['PIVOT_LEFT', 'PIVOT_RIGHT', 'MARCH'],
                                'all_turns': True})
        digest = body.pop('payload_sha256')
        body.pop('digest_rule')
        self.assertEqual(hashlib.sha256(json.dumps(body, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
                         digest)
        failed = cert.certificate(config, dict(report, **{'pass': False}), {}, {}, 'c' * 64, {'godot': {}, 'clips': {}})
        self.assertIsNone(failed['locomotion_certificate'])
        self.assertEqual(failed['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
