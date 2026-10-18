"""Clear the blade and the shield out of the body: per-frame wrist + shoulder corrections.

exec() in the owner's Blender after equip.py. clear(clip) solves on <CLIP>_raw (made on the first
run) and writes <CLIP> once from it, so runs never stack. Per holding arm and frame, a correction
V = (wrist flex, wrist deviation, shoulder about the chest's X, shoulder about its Z), relative to
the raw pose, is searched: the wrist grid first, the shoulder on top when the wrist cannot clear it.
Cost = polygon overlaps (body without the held hand and forearm, and the other gear at its own
correction) + degrees turned + change from the previous frame + every degree of wrist bend past
WRIST_BEND. V is smoothed in time; frames still clipping get a small local search, and so on.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

D = math.radians
WRIST = [D(d) for d in (-40, -20, 0, 20, 40)]
SHOULDER = [D(d) for d in (-45, -30, -15, 0, 15, 30, 45)]
LOCAL = [D(d) for d in (-15, 0, 15)]
COST_WRIST, COST_SHOULDER, COST_CHANGE, COST_BEND = 0.15, 0.1, 0.05, 1.0   # overlaps per degree
WRIST_BEND = 70.0          # degrees between hand and forearm a wrist may reach
SIGMA = 1.5                # frames
SIDES = {".r": "Sword", ".l": "Shield"}


def _local_tris(obj):
    me = obj.data
    me.calc_loop_triangles()
    return np.array([tuple(v.co) for v in me.vertices]), [tuple(t.vertices) for t in me.loop_triangles]


def _tree(M, co, tris):
    pts = (np.c_[co, np.ones(len(co))] @ np.array(M).T)[:, :3]
    return BVHTree.FromPolygons([Vector(p) for p in pts], tris)


def _rot(frame3, a, b):
    return frame3 @ (Matrix.Rotation(a, 3, "X") @ Matrix.Rotation(b, 3, "Z")) @ frame3.inverted()


def _about(pivot, R):
    return Matrix.Translation(pivot) @ R.to_4x4() @ Matrix.Translation(-pivot)


class _Frame:
    """Everything a candidate needs at one frame of the RAW clip."""

    def __init__(self, rig, body, gear):
        W = rig.matrix_world
        pb = rig.pose.bones
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        me = ev.to_mesh()
        M = body.matrix_world
        self.body = BVHTree.FromPolygons([M @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        ev.to_mesh_clear()
        self.gear = {s: gear[s].matrix_world.copy() for s in SIDES}
        self.arm = {}
        for s in SIDES:
            hand = W @ pb["hand" + s].matrix
            fore = (W.to_3x3() @ pb["forearm" + s].vector).normalized()
            hv = (W.to_3x3() @ pb["hand" + s].vector).normalized()
            chest = (W @ pb["spine_02.x"].matrix).to_3x3().normalized()
            self.arm[s] = (hand.translation.copy(), hand.to_3x3().normalized(),
                           (W @ pb["arm" + s].matrix).translation.copy(), chest, fore, hv)

    def transform(self, side, v):
        wp, wf, sp, sf, fore, hv = self.arm[side]
        S = _rot(sf, v[2], v[3])
        T = _about(sp, S) @ _about(wp, _rot(wf, v[0], v[1]))
        # the wrist bend after the turn: the forearm turns with the shoulder, the hand with both
        bend = math.degrees((S @ _rot(wf, v[0], v[1]) @ hv).angle(S @ fore))
        return T, bend


def _overlaps(fr, side, v, other_v, geo, skip):
    T, bend = fr.transform(side, v)
    tg = _tree(T @ fr.gear[side], *geo[side])
    other = [s for s in SIDES if s != side][0]
    To, _ = fr.transform(other, other_v)
    to = _tree(To @ fr.gear[other], *geo[other])
    n = sum(1 for a, b in tg.overlap(fr.body) if b not in skip[side]) + len(tg.overlap(to))
    return n, bend


def _cost(n, bend, v, prev):
    deg = np.degrees(np.abs(v))
    return (n + COST_WRIST * deg[:2].sum() + COST_SHOULDER * deg[2:].sum()
            + COST_CHANGE * np.degrees(np.abs(v - prev)).sum() + COST_BEND * max(0.0, bend - WRIST_BEND))


def _search(fr, side, centre, other_v, geo, skip, prev, wrist, shoulder):
    best = None
    for a in wrist:
        for b in wrist:
            v = centre + np.array([a, b, 0, 0])
            n, bend = _overlaps(fr, side, v, other_v, geo, skip)
            c = _cost(n, bend, v, prev)
            if best is None or c < best[0]:
                best = (c, n, v)
    if best[1]:
        w = best[2]
        for a in shoulder:
            for b in shoulder:
                v = w + np.array([0, 0, a, b])
                n, bend = _overlaps(fr, side, v, other_v, geo, skip)
                c = _cost(n, bend, v, prev)
                if c < best[0]:
                    best = (c, n, v)
    return best


def _smooth(V, sigma=SIGMA):
    k = np.exp(-0.5 * (np.arange(-5, 6) / sigma) ** 2); k /= k.sum()
    return np.stack([np.convolve(np.pad(V[:, i], 5, mode="edge"), k, "valid") for i in range(4)], 1)


def solve(clip, rounds=4):
    exec(open("/Users/samuelzhang/game_design/tools/units3d/soldier_arp/check_gear.py").read(), globals())
    rig, body = bpy.data.objects["rig"], bpy.data.objects["Soldier_body"]
    gear = {s: bpy.data.objects[n] for s, n in SIDES.items()}
    raw = bpy.data.actions.get(clip + "_raw")
    if raw is None:
        raw = bpy.data.actions[clip].copy(); raw.name = clip + "_raw"; raw.use_fake_user = True
    rig.animation_data.action = raw
    rig.animation_data.action_slot = raw.slots[0]
    f0, f1 = map(int, raw.frame_range)
    geo = {s: _local_tris(g) for s, g in gear.items()}
    skip = {s: _held_polys(body, s) for s in SIDES}
    frames = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        frames.append(_Frame(rig, body, gear))
    V = {s: np.zeros((len(frames), 4)) for s in SIDES}
    zero = np.zeros(4)
    log = []
    for rnd in range(rounds):
        hits = 0
        for side in SIDES:
            other = [s for s in SIDES if s != side][0]
            prev = V[side][0].copy()
            for i, fr in enumerate(frames):
                n, _ = _overlaps(fr, side, V[side][i], V[other][i], geo, skip)
                if n:
                    hits += 1
                    grid = (WRIST, SHOULDER) if rnd == 0 else (LOCAL, LOCAL)
                    # after the first round, stay close to both neighbours, not only the previous one
                    near = prev if rnd == 0 or i + 1 == len(frames) else (prev + V[side][i + 1]) / 2
                    V[side][i] = _search(fr, side, V[side][i], V[other][i], geo, skip, near, *grid)[2]
                prev = V[side][i]
            if rnd < rounds - 1:
                V[side] = _smooth(V[side])
        log.append(hits)
        if not hits:
            break
    # a last light smoothing, taken only on the frames it leaves no worse
    for side in SIDES:
        other = [s for s in SIDES if s != side][0]
        S = _smooth(V[side], 1.0)
        for i, fr in enumerate(frames):
            if (_overlaps(fr, side, S[i], V[other][i], geo, skip)[0]
                    <= _overlaps(fr, side, V[side][i], V[other][i], geo, skip)[0]):
                V[side][i] = S[i]
    _write(clip, raw, V)
    return log


def _key(pb, R):
    M = pb.matrix.copy()
    N = (R @ M.to_3x3()).to_4x4(); N.translation = M.translation
    prev = pb.rotation_euler.copy()
    pb.matrix = N
    bpy.context.view_layer.update()
    pb.rotation_euler = pb.matrix_basis.to_euler("XYZ", prev)
    pb.keyframe_insert("rotation_euler", frame=bpy.context.scene.frame_current, group=pb.name)


def _write(clip, raw, V):
    rig = bpy.data.objects["rig"]
    old = bpy.data.actions.get(clip)
    if old is not None:
        bpy.data.actions.remove(old)
    act = raw.copy(); act.name = clip; act.use_fake_user = True
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    f0 = int(act.frame_range[0])
    Wi = rig.matrix_world.inverted().to_3x3()
    pb = rig.pose.bones
    for i in range(len(V[".r"])):
        bpy.context.scene.frame_set(f0 + i)
        for side in SIDES:
            v = V[side][i]
            if abs(v[2]) + abs(v[3]) > 1e-5:      # the shoulder first: it carries the wrist frame
                chest = (rig.matrix_world @ pb["spine_02.x"].matrix).to_3x3().normalized()
                _key(pb["c_arm_fk" + side], Wi @ _rot(chest, v[2], v[3]) @ Wi.inverted())
            if abs(v[0]) + abs(v[1]) > 1e-5:
                hand = (rig.matrix_world @ pb["hand" + side].matrix).to_3x3().normalized()
                _key(pb["c_hand_fk" + side], Wi @ _rot(hand, v[0], v[1]) @ Wi.inverted())


def report(clip):
    """Per side: largest arm turn vs raw, largest wrist bend (and raw), largest per-frame jump."""
    rig, scn = bpy.data.objects["rig"], bpy.context.scene
    pb = rig.pose.bones

    def series(name, side):
        a = bpy.data.actions[name]
        rig.animation_data.action = a
        rig.animation_data.action_slot = a.slots[0]
        f0, f1 = map(int, a.frame_range)
        out = []
        for f in range(f0, f1 + 1):
            scn.frame_set(f)
            out.append((pb["arm" + side].matrix.to_quaternion(), pb["hand" + side].matrix.to_quaternion(),
                        math.degrees(pb["hand" + side].vector.angle(pb["forearm" + side].vector))))
        return out

    def ang(q1, q2):
        d = math.degrees(q1.rotation_difference(q2).angle)
        return min(d, 360 - d)

    res = {}
    for side in SIDES:
        fix, raw = series(clip, side), series(clip + "_raw", side)
        turn = [ang(x[0], y[0]) for x, y in zip(fix, raw)]
        hand = [ang(x[1], y[1]) for x, y in zip(fix, raw)]
        res[side] = dict(arm_turn=round(max(turn)), hand_turn=round(max(hand)),
                         wrist=round(max(x[2] for x in fix)), wrist_raw=round(max(x[2] for x in raw)),
                         jump=round(max(abs(a - b) for a, b in zip(hand[1:], hand[:-1]))))
    a = bpy.data.actions[clip]
    rig.animation_data.action = a
    rig.animation_data.action_slot = a.slots[0]
    return res
