#!/usr/bin/env python3
"""Coupled infantry pivot author mapping and its skin/contact audit (LOCO-INF-CLIP).

The mapping writes Map3DInfantryPivot.sample_transition inputs; pivot_solve.gd solves them and
pivot.py bakes the canonical pair. Coupling: both legs leave for, and hold, ONE native MARCH frame
(NEUTRAL_PHASE), so the crotch skin weighted to both thighs only ever sees a native left/right
thigh pair; independent per-leg templates tore it (feasibility contract: 45 introduced pairs).
A held foot lands under that frame's hip, its sole posed flat (FOOT_PHASES) on the seated plane.
The last step starts at LAST_STEP so its blend toward the exit never leads native MARCH there.
Native poses are exact Godot AnimationPlayer captures (pivot_native.gd), never interpolated here.
The mesh, binds and template come from the installed infantry.glb (installed_model: BASELINE is a
pivot_native.gd capture with "baseline"); the frozen knight is only the port self-check's input.
NEUTRAL_PHASE, FOOT_PHASES and the micrometre bounds are the installed MARCH's (2026-11-16 short-sword
soldier, tools/units3d/infantry_arp/README.md): re-derive them when MARCH or the model changes.

  pivot_mapping.py request BASELINE OUT [NATIVE...]    native MARCH phases the build still needs (pivot_native.gd input)
  pivot_mapping.py build BASELINE NATIVE OUT           canonical +/-90 pair (pivot_solve.gd input)
  pivot_mapping.py audit BASELINE NATIVE INPUTS RESULTS   R-B skin gate + R-A contact; exit 1 on failure
  pivot_mapping.py plan BASELINE NATIVE OUT            the runtime plan (infantry_pivot_plan.json)
  pivot_mapping.py fixture OUT NAME=PATH...            pack sources losslessly (test fixture format)
  pivot_mapping.py --self-check                        uncoupled parameters reproduce the frozen references exactly
  pivot_mapping.py --arm ARM <command> ...             another body on the infantry's rig contract (ARMS; default infantry)

Gates (owner rulings 2026-11-10): an edge flags when length > 4 x native-entry AND > .03 m; a
flag fails unless native MARCH at the same body phase is flagged (R-B). Penetration, stance hover
and slide <= CONTACT_UM, seam <= SEAM_UM model micrometres (R-A, infantry). Heights are from the
seated plane, model y = 0 (Map3DUnitRig seats the origin there); the rendered ground is the seat
lift below it, so penetration from y = 0 is the stricter reading. Hover is the LOWEST vertex of the
planted sole patch (does the sole touch), slide is that patch's ground-projected drift.
"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import test_pivot_feasibility as frozen  # noqa: E402

# The MARCH passing frame where the thighs are most nearly parallel (7.1 deg), the left sole planted.
NEUTRAL_PHASE = 182 / 420
LAST_STEP = .88
# Native frames whose sole patch is flattest while planted (boot within 0.5 mm of the plane):
# a held foot's pose. Left 181/420 (patch spread 7.0 mm), right 396/420 (3.7 mm).
FOOT_PHASES = (181 / 420, 396 / 420)
SEATED_PLANE_Y = 0.0
UNCOUPLED = {'neutral': (10 / 35, 0.0), 'foot': (10 / 35, 0.0), 'plane': None, 'last_step': .84}
COUPLED = {'neutral': (NEUTRAL_PHASE, NEUTRAL_PHASE), 'foot': FOOT_PHASES, 'plane': SEATED_PLANE_Y,
           'last_step': LAST_STEP}
# entry == exit of both shipped clips: the right sole flat (0.2 mm) and the left boot just lifted
# (8 mm; the pack walk is a guarded shuffle, its thighs never nearer than 13.8 deg on this side),
# the hold pose of the certificate's consumer requirement
CANONICAL_PHASE = 8 / 420
# R-A: ceil(world bound / k * 1e6), k = 25.8437 world m per model m (cf01 measurements, size 0.62)
CONTACT_UM = 23217
SEAM_UM = 1935
GLB = Path(__file__).resolve().parents[3] / 'assets/3D/units/infantry/infantry.glb'
# Another body on the same rig contract (`inf_rig`, the same pack walk) overrides what its own MARCH
# and scale give; `use(arm)` binds the module to it. The heavy infantry's plate soldier
# (2026-11-20): on a 420-phase scan of its MARCH the infantry's phases sit on the same events
# (8/420: right boot 0.6 mm, left lifted 14 mm, thighs 15.8 deg; 182/420: thighs 11.3 deg, their
# least is 11.0 at 179; soles flattest-planted 181/420 at 6.8 mm and 396/420 at 3.5 mm), so it
# keeps them and the consumer's stop / start / hold phase is the infantry's; its bounds are
# ceil(world bound / k * 1e6) at k = 26.4330 (rest height 1.5992 m at size 0.62).
# The axemen's hand-axe soldier (2026-11-23) is the infantry's body and pack walk with another
# weapon: its 420-phase MARCH capture matches the infantry's leg bones to 2e-7 m and its rest
# height is the same 1.636 m, so it keeps every infantry value.
ARMS = {'infantry': {}, 'heavy_infantry': {'CONTACT_UM': 22699, 'SEAM_UM': 1892}, 'axemen': {}}


def use(arm):
    """Bind the module's parameters and GLB to `arm`."""
    global GLB
    globals().update(ARMS[arm])
    GLB = Path(__file__).resolve().parents[3] / f'assets/3D/units/{arm}/{arm}.glb'
SOLE_PATCH_M = .005
ROOT = 'root.x'


def load_frozen(fixture=frozen.FIXTURE):
    data = json.loads(Path(fixture).read_text())
    keep = ['native_import_probe/baseline-native.json', 'round1_actual_march/native-march.json',
            'round1_arc_combined/inputs.json']
    return {k: json.loads(frozen.decode_source(data['sources'][k], frozen.HASHES[k])) for k in keep}


class Model:
    """Native mesh, binds and every captured native MARCH pose (exact float-hex lookup).

    `baseline` holds `surfaces` and `binds` (pivot_native.gd with "baseline"), `templates` the
    sample_transition cases whose rest, legs and contact binds the builds copy, `natives` the
    MARCH captures. The frozen knight (frozen_model) serves only the port self-check; the
    installed infantry is installed_model()."""

    def __init__(self, baseline, templates, natives=()):
        s = baseline['surfaces'][0]
        binds = baseline['binds']
        self.names = [b['name'] for b in binds]
        self.ib = np.array([b['pose'] for b in binds])
        self.v = np.c_[np.array(s['vertices']), np.ones(len(s['vertices']))]
        self.j = np.array(s['bones']).reshape(-1, 4)
        self.w = np.array(s['weights']).reshape(-1, 4)
        tri = np.array(s['indices']).reshape(-1, 3)
        edges = {tuple(sorted(e)) for a, b, c in tri for e in ((a, b), (b, c), (c, a))}
        self.edges = np.array(sorted(edges))
        self.templates = templates
        self.samples = {}
        for native in natives:
            for x in native['samples']:
                self.samples[x['id']] = x['global_bones']

    def native(self, phase):
        key = float(phase).hex()
        if key not in self.samples:
            raise KeyError(f'native MARCH phase {phase!r} ({key}) was not captured')
        return {k: np.array(v) for k, v in self.samples[key].items()}

    def points(self, g):
        m = np.array([np.asarray(g[n]) @ self.ib[k] for k, n in enumerate(self.names)])
        return np.einsum('vk,vkij,vj->vi', self.w, m[self.j], self.v)[:, :3]

    def lengths(self, p):
        return np.linalg.norm(p[self.edges[:, 0]] - p[self.edges[:, 1]], axis=1)

    def owned(self, leg):
        ks = [self.names.index(leg['ankle']), self.names.index(leg['toe'])]
        return np.sum(np.where(np.isin(self.j, ks), self.w, 0), axis=1) / self.w.sum(axis=1) > .5

    def minima(self, g, legs):
        p = self.points(g)
        return [float(p[self.owned(leg), 1].min()) for leg in legs]


def frozen_model(captures=()):
    """The retired knight's frozen feasibility capture: only the uncoupled port self-check uses it."""
    data = load_frozen()
    return Model(data['native_import_probe/baseline-native.json'], data['round1_arc_combined/inputs.json']['cases'],
                 [data['round1_actual_march/native-march.json'], *captures])


def _trs(node):
    x, y, z, w = np.asarray(node.get('rotation', (0, 0, 0, 1)), float) / np.linalg.norm(node.get('rotation', (0, 0, 0, 1)))
    m = np.eye(4)
    m[:3, :3] = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                          [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]) @ np.diag(node.get('scale', (1, 1, 1)))
    m[:3, 3] = node.get('translation', (0, 0, 0))
    return m


def installed_template(glb, baseline):
    """The installed GLB's sample_transition template: rest = its glTF joint nodes under inf_rig
    (parents first), the two legs, and contact binds whose markers sit at the bind boot's sole
    patch (sole: the patch centroid; toe: the centroid of its toe-weighted part), axes level."""
    import pivot  # noqa: E402 (sibling module)
    data, _ = pivot._read(glb)
    nodes = data['nodes']
    joints = {data['nodes'][i]['name'] for i in data['skins'][0]['joints']}
    bones = []

    def visit(i, parent):
        n = nodes[i]
        if n['name'] == 'inf_rig' or n['name'] in joints:
            bones.append({'name': n['name'], 'parent': parent, 'local': _trs(n)})
            for c in n.get('children', []):
                visit(c, n['name'])
    visit(next(i for i, n in enumerate(nodes) if n.get('name') == 'inf_rig'), '')
    rest = {}
    for b in bones:
        rest[b['name']] = (rest[b['parent']] if b['parent'] else np.eye(4)) @ b['local']
    model = Model(baseline, [], [])
    p = model.points(rest)
    legs, contacts = [], {}
    for side in ('.l', '.r'):
        leg = {'hip': 'thigh_twist' + side, 'knee': 'leg_stretch' + side, 'ankle': 'foot' + side,
               'toe': 'toes_01' + side, 'min_knee_rad': 0.0, 'max_knee_rad': math.pi,
               'followers': {'thigh_stretch' + side: 'hip', 'leg_twist' + side: 'knee'}}
        h, k, a = (rest[leg[n]][:3, 3] for n in ('hip', 'knee', 'ankle'))
        axis = (a - h) / np.linalg.norm(a - h)
        bend = (k - h) - axis * np.dot(k - h, axis)
        leg['pole'] = bend / np.linalg.norm(bend)  # the rest knee's bend (native mode reads only its validity)
        own = model.owned(leg)
        patch = own & (model.v[:, 1] <= model.v[own, 1].min() + SOLE_PATCH_M)
        toe = patch & (model.j[np.arange(len(model.j)), model.w.argmax(axis=1)] == model.names.index(leg['toe']))
        if toe.sum() < 3:
            toe = patch & (p[:, 2] <= np.quantile(p[patch, 2], .25))  # the patch's front quarter (-Z forward)
        binds = {}
        for key, bone, sel in (('sole_bind', leg['ankle'], patch), ('toe_bind', leg['toe'], toe)):
            marker = np.eye(4)
            marker[:3, 3] = p[sel].mean(axis=0)
            binds[key] = np.linalg.inv(rest[bone]) @ marker
        legs.append(leg)
        contacts[leg['hip']] = binds
    return {'rest': {'bones': bones, 'legs': legs}, 'contacts': {'legs': contacts},
            'transition': {'entry_pose': {'inf_rig': bones[0]['local']}},
            'source_glb_sha256': hashlib.sha256(Path(glb).read_bytes()).hexdigest()}


def proper(m):
    u, _, v = np.linalg.svd(m[:3, :3])
    return u @ v


def _quaternion(m):
    k = np.array([[m[0, 0]-m[1, 1]-m[2, 2], m[0, 1]+m[1, 0], m[0, 2]+m[2, 0], m[2, 1]-m[1, 2]],
                  [m[0, 1]+m[1, 0], m[1, 1]-m[0, 0]-m[2, 2], m[1, 2]+m[2, 1], m[0, 2]-m[2, 0]],
                  [m[0, 2]+m[2, 0], m[1, 2]+m[2, 1], m[2, 2]-m[0, 0]-m[1, 1], m[1, 0]-m[0, 1]],
                  [m[2, 1]-m[1, 2], m[0, 2]-m[2, 0], m[1, 0]-m[0, 1], m[0, 0]+m[1, 1]+m[2, 2]]]) / 3
    return np.linalg.eigh(k)[1][:, -1]


def _matrix(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def slerp(a, z, u):
    if u == 0:
        return a.copy()
    if u == 1:
        return z.copy()
    a, z = _quaternion(a), _quaternion(z)
    dot = float(np.dot(a, z))
    if dot < 0:
        z, dot = -z, -dot
    if dot > .9995:
        q = (1-u)*a + u*z
    else:
        t = np.arccos(np.clip(dot, -1, 1))
        q = (np.sin((1-u)*t)*a + np.sin(u*t)*z) / np.sin(t)
    return _matrix(q)


def blend(a, z, u):
    """Polar rotation slerps, the native affine residual and translation lerp."""
    if u == 0:
        return a.copy()
    if u == 1:
        return z.copy()
    ar, zr = proper(a), proper(z)
    m = np.eye(4)
    m[:3, :3] = slerp(ar, zr, u) @ ((1-u)*(ar.T @ a[:3, :3]) + u*(zr.T @ z[:3, :3]))
    m[:3, 3] = (1-u)*a[:3, 3] + u*z[:3, 3]
    assert np.linalg.det(m[:3, :3]) > 0
    return m


def rotate(deg):
    t = np.deg2rad(deg)
    return np.array([[np.cos(t), 0, np.sin(t)], [0, 1, 0], [-np.sin(t), 0, np.cos(t)]])


def body_phase(entry, exit_, u):
    distance = 1.0 if entry == exit_ else (exit_ - entry) % 1.0
    return entry if u == 0 else exit_ if u == 1 else (entry + distance*u) % 1.0


def events(lowe, lowx, last_step):
    """Seven alternating steps, the higher entry foot first, then a final step onto the exit."""
    first, final_support = int(np.argmax(lowe)), int(np.argmin(lowx))
    other = 1 - first
    ev = [(first, 0., .12), (other, .12, .24), (first, .24, .36), (other, .36, .48), (first, .48, .60),
          (other, .60, .72), (first, .72, .84)]
    ev += [(other, .84, .9), (first, .9, 1.)] if final_support == other else [(other, last_step, 1.)]
    return first, final_support, ev


def knots(ev):
    return sorted({a + (z-a)*k/16 for _, a, z in ev for k in range(17)})


def native_locals(model, phase, template):
    root = np.asarray(template['transition']['entry_pose']['inf_rig'])
    g = dict(model.native(phase), inf_rig=root)
    return {b['name']: root.copy() if not b['parent'] else np.linalg.inv(g[b['parent']]) @ g[b['name']]
            for b in template['rest']['bones']}


def build_case(model, template, op, phases, neutral, last_step, foot, plane):
    """One sample_transition case: references in native parent locals plus a contact plan."""
    f = {'rest': copy.deepcopy(template['rest']), 'op': dict(op), 'source_glb_sha256': template['source_glb_sha256']}
    entry, exit_ = op['march_entry_phase'], op['march_exit_phase']
    ge, gx = model.native(entry), model.native(exit_)
    legs = f['rest']['legs']
    lowe, lowx = model.minima(ge, legs), model.minima(gx, legs)
    first, final_support, ev = events(lowe, lowx, last_step)
    f['phases'] = knots(ev) if phases is None else list(phases)
    ground = min(lowe) if plane is None else plane  # where a held boot minimum lands
    pose = {li: model.native(neutral[li]) for li in (0, 1)}
    flat = {li: model.native(foot[li]) for li in (0, 1)}
    low = {li: model.minima(flat[li], legs)[li] for li in (0, 1)}
    frames = []
    for u in f['phases']:
        bp = body_phase(entry, exit_, u)
        local, g, desired = native_locals(model, bp, template), model.native(bp), {}
        for li, leg in enumerate(legs):
            swings = [(a, z) for side, a, z in ev if side == li]
            (fa, fz), (la, lz) = swings[0], swings[-1]
            if u < fz:
                q = min(1., max(0., (u-fa)/(fz-fa)))
                e, start, finish = q*q*(3-2*q), ge, pose[li]
            elif u > la:
                q = min(1., max(0., (u-la)/(lz-la)))
                e, start, finish = q*q*(3-2*q), pose[li], gx
            else:
                e, start, finish = 0., pose[li], pose[li]
            for n in [leg['hip'], leg['knee'], leg['ankle'], leg['toe'], *leg['followers']]:
                desired[n] = g[ROOT] @ blend(np.linalg.inv(start[ROOT]) @ start[n],
                                             np.linalg.inv(finish[ROOT]) @ finish[n], e)
            if 0. < e < 1.:
                # Linear joint chords shorten a free leg: keep the interpolated native segment lengths.
                anchors = [leg['hip'], leg['knee'], leg['ankle'], leg['toe']]
                old = {n: desired[n][:3, 3].copy() for n in anchors}
                ws, wf = g[ROOT] @ np.linalg.inv(start[ROOT]), g[ROOT] @ np.linalg.inv(finish[ROOT])
                for prox, dist in [(leg['hip'], leg['knee']), (leg['knee'], leg['ankle'])]:
                    sa = (ws @ start[dist])[:3, 3] - (ws @ start[prox])[:3, 3]
                    sz = (wf @ finish[dist])[:3, 3] - (wf @ finish[prox])[:3, 3]
                    length = (1-e)*np.linalg.norm(sa) + e*np.linalg.norm(sz)
                    d = old[dist] - old[prox]
                    assert np.linalg.norm(d) > 1e-5
                    desired[dist][:3, 3] = desired[prox][:3, 3] + length*d/np.linalg.norm(d)
                desired[leg['toe']][:3, 3] += desired[leg['ankle']][:3, 3] - old[leg['ankle']]
                for follower, role in leg['followers'].items():
                    desired[follower][:3, 3] += desired[leg[role]][:3, 3] - old[leg[role]]
        rebuilt, refs = {}, {}
        for bone in f['rest']['bones']:
            n = bone['name']
            parent = np.eye(4) if not bone['parent'] else rebuilt[bone['parent']]
            refs[n] = np.linalg.inv(parent) @ desired[n] if n in desired else local[n]
            rebuilt[n] = parent @ refs[n]
        frames.append(refs)
    for end, phase in [(0, entry), (-1, exit_)]:
        native = native_locals(model, phase, template)
        assert max(float(np.abs(frames[end][n] - native[n]).max()) for n in native) < 1e-10, 'endpoint drift'
    f['reference_poses'] = frames
    f['pose'] = frames[0]
    f['transition'] = {'entry_pose': frames[0], 'exit_pose': frames[-1]}
    plan = []
    for li, leg in enumerate(legs):
        binds = template['contacts']['legs'][leg['hip']]
        sb, tb = np.array(binds['sole_bind']), np.array(binds['toe_bind'])
        se, sx = ge[leg['ankle']] @ sb, gx[leg['ankle']] @ sb
        te, tx = ge[leg['toe']] @ tb, gx[leg['toe']] @ tb
        swings = []
        for si, (a, z) in enumerate([(a, z) for side, a, z in ev if side == li]):
            last = si == len(swings_of(ev, li)) - 1
            mid = flat[li]
            sm, tm = mid[leg['ankle']] @ sb, mid[leg['toe']] @ tb
            gs, gt = (sx, tx) if last else (sm, tm)
            place = gs[:3, 3].copy()
            if not last:  # under the coupled frame's hip, flat on its own midstance sole
                offset = mid[leg['ankle']][:3, :3] @ sb[:3, 3]
                place[[0, 2]] = pose[li][leg['hip']][:3, 3][[0, 2]] + offset[[0, 2]]
            place[1] = sx[1, 3] if last else ground + sm[1, 3] - low[li]
            swings.append({'t0': a, 't1': z, 'future': 1. if last else min(1., z+.06), 'place': place,
                           'sole': proper(gs), 'toe': proper(gt)})
        plan.append({'hip': leg['hip'], 'sole_bind': binds['sole_bind'], 'toe_bind': binds['toe_bind'],
                     'point': se[:3, 3].copy(), 'sole': proper(se), 'toe': proper(te), 'swings': swings})
    contacts = expand(plan, op['turn_udeg'])
    f['contacts'] = {'march_entry_phase': entry, 'march_exit_phase': exit_, 'legs': contacts}
    f['plan'] = plan
    f['author_mapping'] = {'neutral_phases': list(neutral), 'foot_phases': list(foot), 'plane_y': plane, 'last_step': last_step, 'first_free_leg': legs[first]['hip'],
                           'final_support_leg': legs[final_support]['hip'], 'floor_model_y': ground}
    return f


def swings_of(ev, li):
    return [(a, z) for side, a, z in ev if side == li]


def expand(plan, turn_udeg):
    """The contact intervals of a turn: the turn-free plan's held targets rotated by
    -turn x (the swing's end + .06), swung on a smoothstep with a lift. Mirrored by
    Map3DInfantryLocomotion (GDScript) for any turn at runtime."""
    turn = turn_udeg / 1e6
    lift = .05*min(1., abs(turn)/90)
    out = {}
    for leg in plan:
        point, sr, tr, cursor, iv = leg['point'], leg['sole'], leg['toe'], 0., []

        def add(a, z, kind, p0, p1, s0, s1, t0, t1):
            iv.append({'t0': a, 't1': z, 'kind': kind, 'point_from': p0, 'point_to': p1,
                       'sole_from': s0, 'sole_to': s1, 'toe_from': t0, 'toe_to': t1})
        for sw in leg['swings']:
            a, z = sw['t0'], sw['t1']
            if cursor < a:
                add(cursor, a, 'stance', point, point, sr, sr, tr, tr)
            r = rotate(-turn*sw['future'])
            target, rs, rt = r @ sw['place'], r @ sw['sole'], r @ sw['toe']
            pp, ps, pt = point, sr, tr
            for k in range(1, 17):
                s = k/16
                e = s*s*(3-2*s)
                p0 = point*(1-e) + target*e
                p0[1] += lift*np.sin(np.pi*s)**2
                ss, tt = slerp(sr, rs, e), slerp(tr, rt, e)
                add(a + (z-a)*(k-1)/16, z if k == 16 else a + (z-a)*k/16, 'swing', pp, p0, ps, ss, pt, tt)
                pp, ps, pt = p0, ss, tt
            point, sr, tr, cursor = target, rs, rt, z
        if cursor < 1:
            add(cursor, 1., 'stance', point, point, sr, sr, tr, tr)
        out[leg['hip']] = {'sole_bind': leg['sole_bind'], 'toe_bind': leg['toe_bind'], 'intervals': iv}
    return out


def canonical_ops():
    return [{'duration_q': 200000, 'phase': 0.0, 'yaw0_udeg': 359000000, 'turn_udeg': turn,
             'current_yaw_udeg': 359000000.0, 'march_entry_phase': CANONICAL_PHASE,
             'march_exit_phase': CANONICAL_PHASE} for turn in (90000000, -90000000)]


def build(model, witness=False, params=COUPLED):
    """The canonical pair; witness=True rebuilds the template cases (the frozen knight's five)."""
    if witness:
        return [build_case(model, t, t['op'], t['phases'], params['neutral'], params['last_step'],
                           params['foot'], params['plane']) for t in model.templates]
    return [build_case(model, model.templates[0], op, None, params['neutral'], params['last_step'],
                       params['foot'], params['plane']) for op in canonical_ops()]


def installed_model(baseline, natives=(), glb=None):
    """The installed infantry: BASELINE's skin and mesh, the GLB's template, and the captures
    (BASELINE's own samples first)."""
    return Model(baseline, [installed_template(glb or GLB, baseline)], [baseline, *natives])


def requested_phases(model):
    """Every native phase a coupled build reads that the frozen capture lacks."""
    need = set()
    if float(CANONICAL_PHASE).hex() not in model.samples:
        return [CANONICAL_PHASE]  # capture the entry first: which foot steps first depends on it
    for op in canonical_ops():
        ge = model.native(op['march_entry_phase'])
        legs = model.templates[0]['rest']['legs']
        _, _, ev = events(model.minima(ge, legs), model.minima(ge, legs), LAST_STEP)
        need.update(body_phase(op['march_entry_phase'], op['march_exit_phase'], u) for u in knots(ev))
    need.update([CANONICAL_PHASE, NEUTRAL_PHASE, *FOOT_PHASES])
    return sorted(p for p in need if float(p).hex() not in model.samples)


def encode(x):
    if isinstance(x, np.ndarray):
        return x.tolist()
    if isinstance(x, dict):
        return {k: encode(v) for k, v in x.items()}
    if isinstance(x, list):
        return [encode(v) for v in x]
    return float(x) if isinstance(x, np.floating) else x


def _globals(model, local, parents):
    out = {}

    def visit(n):
        if n not in out:
            p = parents[n]
            out[n] = visit(p) @ np.asarray(local[n]) if p else np.asarray(local[n])
        return out[n]
    for n in local:
        visit(n)
    return out


def flagged(length, entry):
    return (length > 4*entry) & (length > .03)


def audit(model, cases, results):
    """R-B skin flags against same-phase native, R-A contact and seam, per case."""
    report = []
    for case, result in zip(cases, results['cases']):
        assert case['op']['turn_udeg'] == result['turn_udeg'] and not result['failures'], 'helper failure'
        # Godot's JSON round trip may move a phase by one ulp; the case phase stays authoritative.
        assert len(result['frames']) == len(case['phases']) and all(
            abs(f['phase'] - u) < 1e-15 for f, u in zip(result['frames'], case['phases'])), 'frame/phase mismatch'
        parents = {b['name']: b['parent'] for b in case['rest']['bones']}
        legs = case['rest']['legs']
        entry, exit_ = case['op']['march_entry_phase'], case['op']['march_exit_phase']
        turn = case['op']['turn_udeg'] / 1e6
        pe, px = model.points(model.native(entry)), model.points(model.native(exit_))
        l0 = model.lengths(pe)
        floor = SEATED_PLANE_Y
        bind_y = model.v[:, 1]
        patch = []
        for leg in legs:
            own = model.owned(leg)
            patch.append(own & (bind_y <= bind_y[own].min() + SOLE_PATCH_M))
        stance = {li: [(iv['t0'], iv['t1']) for iv in case['contacts']['legs'][leg['hip']]['intervals']
                       if iv['kind'] == 'stance'] for li, leg in enumerate(legs)}
        flags = inherited = introduced = mapping_only = 0
        worst, first_bad = 0.0, []
        penetration = hover = slide = 0.0
        anchors = {}
        seam = 0.0
        for u, frame, reference in zip(case['phases'], result['frames'], case['reference_poses']):
            p = model.points(_globals(model, frame['pose'], parents))
            lengths = model.lengths(p)
            native_flag = flagged(model.lengths(model.points(model.native(body_phase(entry, exit_, u)))), l0)
            bad = flagged(lengths, l0)
            new = bad & ~native_flag
            flags += int(bad.sum())
            inherited += int((bad & native_flag).sum())
            if new.any():
                ref = flagged(model.lengths(model.points(_globals(model, reference, parents))), l0)
                introduced += int(new.sum())
                mapping_only += int((new & ~ref).sum())
                first_bad += [(u, int(k)) for k in np.nonzero(new)[0]][:3]
            worst = max(worst, float(np.max(lengths[~native_flag] / np.maximum(4*l0[~native_flag], .03))))
            penetration = max(penetration, floor - float(p[:, 1].min()))
            q = p @ rotate(-turn*u).T  # current model -> entry model (the world frame of planted feet)
            for li in (0, 1):
                for t0, t1 in stance[li]:
                    if t0 <= u <= t1:
                        hover = max(hover, float(q[patch[li], 1].min()) - floor)
                        key = (li, t0)
                        anchors.setdefault(key, q[patch[li]][:, [0, 2]])
                        slide = max(slide, float(np.linalg.norm(q[patch[li]][:, [0, 2]] - anchors[key], axis=1).max()))
            if u in (0.0, 1.0):
                seam = max(seam, float(np.linalg.norm(p - (pe if u == 0.0 else px), axis=1).max()))
        um = {k: math.ceil(v*1e6) if v > 0 else 0 for k, v in
              [('penetration', penetration), ('hover', hover), ('slide', slide), ('seam', seam)]}
        ok = (introduced == 0 and max(um['penetration'], um['hover'], um['slide']) <= CONTACT_UM
              and um['seam'] <= SEAM_UM)
        report.append({'turn_udeg': case['op']['turn_udeg'], 'march_entry_phase': entry, 'march_exit_phase': exit_,
                       'frames': len(result['frames']), 'skin': {'flags': flags, 'inherited_native': inherited,
                       'introduced': introduced, 'mapping_only': mapping_only, 'first_introduced': first_bad,
                       'worst_non_native_gate_ratio': round(worst, 6)},
                       'contact_um': um, 'sole_patch_vertices': [int(x.sum()) for x in patch], 'pass': ok})
    return report


def self_check(model):
    """The uncoupled parameters must rebuild the frozen witness references and contacts exactly."""
    for template, case in zip(model.templates, build(model, witness=True, params=UNCOUPLED)):
        for ref, mine in zip(template['reference_poses'], case['reference_poses']):
            # Exact on one BLAS; another platform's SVD/eigh/matmul may differ in the last bits.
            assert max(float(np.abs(np.array(ref[n]) - mine[n]).max()) for n in ref) < 1e-12, 'reference port'
        for hip, c in template['contacts']['legs'].items():
            assert len(c['intervals']) == len(case['contacts']['legs'][hip]['intervals'])
            for a, b in zip(c['intervals'], case['contacts']['legs'][hip]['intervals']):
                for k in ['point_from', 'point_to', 'sole_from', 'sole_to', 'toe_from', 'toe_to']:
                    assert float(np.abs(np.array(a[k]) - b[k]).max()) < 1e-12, 'contact port'
    assert events([0, 1], [1, 0], .88)[2][-1] == (0, .88, 1.)
    assert not flagged(np.array([.03]), np.array([.001]))[0] and flagged(np.array([.040001]), np.array([.01]))[0]


def pack(out, sources):
    """The lossless fixture container test_pivot_mapping.py reads: name -> sha256, bytes, zlib+base64."""
    import base64
    import zlib
    data = {}
    for name, path in sources.items():
        raw = Path(path).read_bytes()
        data[name] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
                      'zlib_base64': base64.b64encode(zlib.compress(raw, 9)).decode()}
    Path(out).write_text(json.dumps({'format': 'infantry-pivot-mapping-v2', 'sources': data}, indent=1) + '\n')
    return {k: v['sha256'] for k, v in data.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--self-check', action='store_true')
    parser.add_argument('--arm', choices=sorted(ARMS), default='infantry')
    sub = parser.add_subparsers(dest='command')
    r = sub.add_parser('request')
    r.add_argument('baseline', type=Path)
    r.add_argument('out', type=Path)
    r.add_argument('natives', type=Path, nargs='*')
    for name in ('build', 'plan'):
        b = sub.add_parser(name)
        b.add_argument('baseline', type=Path)
        b.add_argument('native', type=Path)
        b.add_argument('out', type=Path)
    a = sub.add_parser('audit')
    a.add_argument('baseline', type=Path)
    a.add_argument('native', type=Path)
    a.add_argument('inputs', type=Path)
    a.add_argument('results', type=Path)
    f = sub.add_parser('fixture')
    f.add_argument('out', type=Path)
    f.add_argument('sources', nargs='+')
    args = parser.parse_args()
    use(args.arm)
    if args.self_check:
        self_check(frozen_model())
        print('PIVOT_MAPPING_SELF_CHECK_MATCH')
        return
    if args.command == 'fixture':
        print(json.dumps(pack(args.out, dict(s.split('=', 1) for s in args.sources)), indent=1))
        return
    if args.command is None:
        parser.print_help()
        return
    natives = [json.loads(n.read_text()) for n in ([args.native] if getattr(args, 'native', None) else
                                                   getattr(args, 'natives', []))]
    model = installed_model(json.loads(args.baseline.read_text()), natives)
    if args.command == 'request':
        phases = requested_phases(model)
        args.out.write_text(json.dumps({'clip': 'MARCH', 'samples': [{'id': float(p).hex(), 'phase': p} for p in phases]}))
        print('phases', len(phases))
    elif args.command == 'build':
        cases = build(model)
        text = json.dumps({'cases': encode(cases)})
        args.out.write_text(text)
        print('cases', len(cases), 'frames', sum(len(c['phases']) for c in cases),
              'sha256', hashlib.sha256(text.encode()).hexdigest())
    elif args.command == 'plan':
        case = build(model)[0]
        legs = [{'hip': g['hip'], 'sole_bind': g['sole_bind'], 'toe_bind': g['toe_bind'], 'point': g['point'],
                 'sole': g['sole'][:3, :3], 'toe': g['toe'][:3, :3], 'swings': g['swings']} for g in case['plan']]
        payload = {'note': 'generated by tools/units3d/soldier_arp/pivot_mapping.py plan; do not edit',
                   'march_phase': CANONICAL_PHASE, 'rest': case['rest'], 'legs': legs}
        args.out.write_text(json.dumps(encode(payload), separators=(',', ':')) + '\n')
        print('plan', args.out)
    elif args.command == 'audit':
        cases = json.loads(args.inputs.read_text())['cases']
        report = audit(model, cases, json.loads(args.results.read_text()))
        print(json.dumps(report, indent=1))
        sys.exit(0 if all(r['pass'] for r in report) else 1)


if __name__ == '__main__':
    main()
