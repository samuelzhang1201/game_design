"""Sword + shield on the ARP knight: a fixed fist on both hands, socket bones fitted to the fist.

exec() inside the owner's Blender with soldier_knight_arp.blend open, then call the functions.
Socket frame (same contract as soldier_ue5/weapons.py and a Godot BoneAttachment3D): origin in the
fist's hole, +Y out of the thumb side (toward the blade tip / the shield's top), +Z toward the
knuckles (the sword's edge plane; the shield's face).
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

FINGERS = ("index", "middle", "ring", "pinky")
GRIP_SOURCE = ("IDLE", 1)   # the Mixamo sword-and-shield fist, the same in IDLE/SLASH/ATTACK
SOCKETS = {".r": "cc_weapon.r", ".l": "cc_weapon.l"}


def _finger_controls(side):
    return ["c_%s%d%s" % (f, i, side) for f in FINGERS + ("thumb",) for i in (1, 2, 3)]


def _curves(action):
    return [fc for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags for fc in bag.fcurves], \
        [bag for layer in action.layers for strip in layer.strips for bag in strip.channelbags]


def fix_grip(actions):
    """Key every finger control to the source fist for each clip's whole range (one key each end)."""
    src = bpy.data.actions[GRIP_SOURCE[0]]
    curves, _ = _curves(src)
    pose = {}
    for fc in curves:
        bone = fc.data_path.split('"')[1] if '"' in fc.data_path else ""
        if any(bone == c for side in SOCKETS for c in _finger_controls(side)):
            pose[(fc.data_path, fc.array_index)] = fc.evaluate(GRIP_SOURCE[1])
    for name in actions:
        act = bpy.data.actions[name]
        f0, f1 = act.frame_range
        curves, bags = _curves(act)
        bag = bags[0]
        for fc in [fc for fc in curves if (fc.data_path, fc.array_index) in pose]:
            bag.fcurves.remove(fc)
        for (path, idx), v in pose.items():
            fc = bag.fcurves.new(path, index=idx, group_name=path.split('"')[1])
            fc.keyframe_points.insert(f0, v); fc.keyframe_points.insert(f1, v)
    return len(pose)


def _circle_center(P):
    P = np.array(P); c = P.mean(0)
    _, _, Vt = np.linalg.svd(P - c); e1, e2 = Vt[0], Vt[1]
    Q = np.c_[(P - c) @ e1, (P - c) @ e2]
    x = np.linalg.lstsq(np.c_[2 * Q, np.ones(len(Q))], (Q ** 2).sum(1), rcond=None)[0]
    return c + x[0] * e1 + x[1] * e2, float(np.sqrt(x[2] + x[0] ** 2 + x[1] ** 2))


def fist_frame(rig, side):
    """The fist's hole in hand-bone space, from circles through each finger's joints."""
    pb = rig.pose.bones
    hinv = pb["hand" + side].matrix.inverted()
    centres, radii = [], []
    for f in FINGERS:
        b1, b3 = pb[f + "1" + side], pb["c_%s3%s" % (f, side)]
        pts = [hinv @ b1.head, hinv @ pb["c_%s2%s" % (f, side)].head, hinv @ b3.head, hinv @ b3.tail]
        c, r = _circle_center([tuple(p) for p in pts]); centres.append(c); radii.append(r)
    cs = np.array(centres); m = cs.mean(0)
    y = np.linalg.svd(cs - m)[2][0]
    if np.dot(y, cs[0] - cs[-1]) < 0:          # pinky -> index: out of the thumb side
        y = -y
    # +Z: the way the fist punches — wrist (hand head, the bone origin) to the knuckles (finger roots)
    k = np.mean([np.array(hinv @ pb[f + "1" + side].head) for f in FINGERS], 0)
    z = k - y * np.dot(k, y); z /= np.linalg.norm(z)
    x = np.cross(y, z)
    M = Matrix(np.c_[x, y, z, m].tolist() + [[0, 0, 0, 1]])
    return M, radii


def make_sockets(rig):
    """cc_weapon.* bones, children of hand.*, at the fist frame (evaluated in the gripped pose)."""
    frames = {side: fist_frame(rig, side)[0] for side in SOCKETS}
    rest = {side: rig.data.bones["hand" + side].matrix_local.copy() for side in SOCKETS}
    bpy.context.view_layer.objects.active = rig
    mirror, rig.data.use_mirror_x = rig.data.use_mirror_x, False   # ARP edits mirrored: .l overwrote .r
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for side, name in SOCKETS.items():
        b = eb.get(name) or eb.new(name)
        b.length = 0.1
        b.matrix = rest[side] @ frames[side]
        b.parent = eb["hand" + side]
        b.use_deform = False
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.data.use_mirror_x = mirror


def world_offset(rig, action, bone, axis, deg):
    """Turn `bone` about its head by `deg` around a WORLD axis on every frame of `action`
    (one key per frame, as ARP bakes), so the gear clears the legs without re-authoring the clip."""
    scn = bpy.context.scene
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    pb = rig.pose.bones[bone]
    f0, f1 = map(int, action.frame_range)
    for f in range(f0, f1 + 1):
        scn.frame_set(f)
        # axis: a world vector, or a bone name = that bone's own direction this frame (a twist)
        ax = axis if not isinstance(axis, str) else (
            rig.matrix_world.to_3x3() @ rig.pose.bones[axis].vector).normalized()
        R = rig.matrix_world.inverted().to_3x3() @ Matrix.Rotation(math.radians(deg), 3, ax)
        M = pb.matrix.copy()
        N = (R @ M.to_3x3()).to_4x4(); N.translation = M.translation
        pb.matrix = N
        bpy.context.view_layer.update()
        pb.keyframe_insert("rotation_quaternion" if pb.rotation_mode == "QUATERNION" else "rotation_euler",
                           frame=f, group=bone)


# The walk's own arm swing, kept hanging: a few degrees out at the shoulder, the forearm brought
# back in at the elbow (owner: the forearm flaring out looked ugly; the clip's own forearm is
# ~12 degrees out), the forearms turned so the shield hangs flat outside the left leg and the
# blade lies outside the right with its point raised. The least turns that clear all 36 frames
# (grid search: abduction x elbow x forearm turn x wrist pitch). Applied in this order.
WALK_CARRY = (("c_arm_fk.l", (0, -1, 0), 6), ("c_forearm_fk.l", (0, -1, 0), -10),
              ("c_hand_fk.l", "forearm.l", -40),
              ("c_arm_fk.r", (0, 1, 0), 8), ("c_forearm_fk.r", (0, 1, 0), -10),
              ("c_hand_fk.r", "forearm.r", 40), ("c_hand_fk.r", (1, 0, 0), 40))


def mount(rig, obj, socket, offset=Matrix.Identity(4)):
    """Parent obj to the socket bone so its canonical frame sits on the socket's head."""
    bpy.context.view_layer.update()
    obj.parent = rig; obj.parent_type = "BONE"; obj.parent_bone = socket
    obj.matrix_world = rig.matrix_world @ rig.pose.bones[socket].matrix @ offset
