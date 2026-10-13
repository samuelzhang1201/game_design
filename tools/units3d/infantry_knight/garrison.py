"""GARRISON for the Tripo knight (the infantry piece): the guard of tools/guide/unit_figures.md.

Run in the owner's Blender on assets/3D/units/model_wip/knight_spear_shield_game.blend (rig
`inf_rig`, +Y forward, the knight's left at -X, clips MARCH / STANDBY baked):

    G = {}; exec(open("/Users/samuelzhang/game_design/tools/units3d/infantry_knight/garrison.py").read(), G)
    G["build"]()

It keys the body (hips, spine, neck, head, the STANDBY fists), puts legs and arms on two-bone IK to
targets, copies the spear and shield bones from targets the hands hold, bakes it all with visual
keying into GARRISON, removes every helper and stashes the clip on its NLA track. Every number is
`P`; pass `P={...}` in the exec globals to override.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

_P = {
    "frames": 96,               # the loop: 4 s at 24 fps, a breath at its middle
    "hips_drop": 0.23,          # m below the rest hips
    "hips_back": 0.02,
    "breath_drop": 0.012,       # m lower at the breath
    "hips_twist": -25.0,        # deg about Z: the left side leads
    "hips_lean": -9.0,          # deg about X: forward
    "spine_twist": -8.0, "spine_lean": -5.0,
    "spine2_twist": -4.0, "spine2_lean": -4.0,
    "breath_lean": -1.0,
    "neck_turn": -15.0,         # the neck half way back; the head faces +Y, level
    "foot_l": (-0.17, 0.41, 0.076, 10.0),    # ankle x, y, z, toe yaw deg
    "foot_r": (0.22, -0.55, 0.076, -40.0),
    "knee_l": (-0.20, 0.62, 0.45), "knee_r": (0.18, 0.0, 0.42),
    "elbow_r_dir": (0.55, -0.25, -0.8),      # from the fist toward the right elbow, squared to the shaft
    "forearm_m": 0.28,
    "elbow_l": (-0.36, 0.18, 1.02),
    "grip_from_head": (0.22, -0.03, 0.11),   # the spear's grip from the head bone: level with the eyes
    "spear_yaw": 40.0,          # deg the tip turns in across the body: aimed at the camera a level spear
                                #   foreshortens to an upright stick and reads as STANDBY (critic, 0 / 25 / 40 bracketed)
    "spear_pitch": 0.0,         # deg, + tip down
    "grip_from_butt": 1.1,      # m along the shaft
    "fist_offset": (0.0, 0.0945, -0.028),    # the shaft through the fist, in the hand's frame
    "shield_top_over_neck": 0.10,            # m: the shield's top edge at the chin
    "shield_from_chest": (-0.12, 0.40),      # x, y from the Spine2 head
    "hand_l_from_shield": (0.04, -0.17, 0.06),
}


def _frame(x, y, z):
    return Matrix((x, y, z)).transposed()


def _group_pca(ob, name):
    gi = ob.vertex_groups[name].index
    pts = np.array([tuple(v.co) for v in ob.data.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)])
    c = pts.mean(0)
    _u, _s, vt = np.linalg.svd(pts - c, full_matrices=False)
    t = (pts - c) @ vt[0]
    return pts, Vector(c), [Vector(v) for v in vt], float(t.min()), float(t.max())


def build(P=None):
    p = dict(_P)
    p.update(P or globals().get("P", {}) or {})
    rig = bpy.data.objects["inf_rig"]
    kn = bpy.data.objects["infantry"]
    sc = bpy.context.scene
    ad = rig.animation_data
    col = rig.users_collection[0]
    rig.hide_set(False)
    upd = bpy.context.view_layer.update
    n_f = int(p["frames"])

    # the fists of STANDBY
    st = bpy.data.actions["STANDBY"]
    ad.action = st
    ad.action_slot = st.slots[0]
    sc.frame_set(0)
    fingers = [pb.name for pb in rig.pose.bones if any(k in pb.name for k in ("Thumb", "Index", "Middle", "Ring", "Pinky"))]
    fist = {n: rig.pose.bones[n].rotation_quaternion.copy() for n in fingers}

    for name in ("GARRISON", "GARRISON_src"):
        if bpy.data.actions.get(name):
            bpy.data.actions.remove(bpy.data.actions[name])
    tr = ad.nla_tracks.get("GARRISON")
    if tr:
        ad.nla_tracks.remove(tr)
    src = bpy.data.actions.new("GARRISON_src")
    ad.action = src
    ad.action_slot = src.slots.new('OBJECT', rig.name) if len(src.slots) == 0 else src.slots[0]

    def rot_world(name, r):
        upd()
        pb = rig.pose.bones[name]
        m = pb.matrix.copy()
        h = m.translation.copy()
        pb.matrix = Matrix.Translation(h) @ r.to_4x4() @ Matrix.Translation(-h) @ m

    def set_world_rot(name, r3):
        upd()
        pb = rig.pose.bones[name]
        h = pb.matrix.translation.copy()
        pb.matrix = Matrix.Translation(h) @ (r3 @ rig.data.bones[name].matrix_local.to_3x3()).to_4x4()

    def rz(d):
        return Matrix.Rotation(math.radians(d), 3, 'Z')

    def rx(d):
        return Matrix.Rotation(math.radians(d), 3, 'X')

    def pose(breath):
        for pb in rig.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
        upd()
        hips = rig.pose.bones["Hips"]
        m = hips.matrix.copy()
        r = rz(p["hips_twist"]) @ rx(p["hips_lean"])
        to = m.translation + Vector((0, -p["hips_back"], -p["hips_drop"] - p["breath_drop"] * breath))
        nm = Matrix.Translation(to) @ r.to_4x4() @ Matrix.Translation(-m.translation) @ m
        nm.translation = to
        hips.matrix = nm
        rot_world("Spine", rz(p["spine_twist"]) @ rx(p["spine_lean"] + p["breath_lean"] * breath))
        rot_world("Spine2", rz(p["spine2_twist"]) @ rx(p["spine2_lean"] + p["breath_lean"] * breath))
        set_world_rot("Neck", rz(p["neck_turn"]))
        set_world_rot("head", rz(0.0))
        for n, q in fist.items():
            rig.pose.bones[n].rotation_quaternion = q
        upd()

    keyed = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "head"] + fingers
    for f, b in ((0, 0.0), (n_f // 2, 1.0), (n_f, 0.0)):
        sc.frame_set(f)
        pose(b)
        for n in keyed:
            pb = rig.pose.bones[n]
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n == "Hips":
                pb.keyframe_insert("location", frame=f)
    sc.frame_set(0)
    upd()

    def emp(name, m, bone=None, obj=None, size=0.05):
        e = bpy.data.objects.get(name) or bpy.data.objects.new(name, None)
        if e.name not in col.objects:
            col.objects.link(e)
        e.empty_display_type = 'ARROWS'
        e.empty_display_size = size
        e.parent = None
        e.matrix_world = m
        if bone:
            e.parent, e.parent_type, e.parent_bone = rig, 'BONE', bone
        elif obj:
            e.parent, e.parent_type = obj, 'OBJECT'
        upd()
        e.matrix_world = m
        upd()
        return e

    def foot_m(side, spec):
        b = rig.data.bones[side + "Foot"]
        return Matrix.Translation(spec[:3]) @ (rz(spec[3]) @ b.matrix_local.to_3x3()).to_4x4()

    head = rig.pose.bones["head"].head.copy()
    neck = rig.pose.bones["Neck"].head.copy()
    chest = rig.pose.bones["Spine2"].head.copy()

    targets = {
        "G_FootL": emp("G_FootL", foot_m("Left", p["foot_l"]), obj=rig),
        "G_FootR": emp("G_FootR", foot_m("Right", p["foot_r"]), obj=rig),
        "G_KneeL": emp("G_KneeL", Matrix.Translation(Vector(p["knee_l"]) + Vector((0, 0.3, 0.05))), obj=rig),
        "G_KneeR": emp("G_KneeR", Matrix.Translation(Vector(p["knee_r"]) + Vector((0.15, 0.6, 0.08))), obj=rig),
    }
    # the spear: overhand, level with the eyes, tip in across the body by spear_yaw
    grip = head + Vector(p["grip_from_head"])
    yaw, pitch = math.radians(p["spear_yaw"]), math.radians(p["spear_pitch"])
    sdir = Vector((-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), -math.sin(pitch))).normalized()
    # the right elbow squared to the shaft, so the fist sits on a straight wrist
    w = Vector(p["elbow_r_dir"])
    w = (w - w.dot(sdir) * sdir).normalized()
    elbow_r = grip + w * p["forearm_m"]
    targets["G_HandR"] = emp("G_HandR", Matrix.Translation(grip), bone="Spine2")
    targets["G_ElbowR"] = emp("G_ElbowR", Matrix.Translation(elbow_r + w * 0.3), bone="Spine2")
    # the shield: upright before the chest, face +Y, wide edge up, top at the chin
    _pts, c_sh, vt_sh, _a, _b = _group_pca(kn, "shield")
    d = vt_sh[0]
    f = -vt_sh[2]
    fa = rig.data.bones["LeftForeArm"]
    off = c_sh - fa.head_local
    ax = (fa.tail_local - fa.head_local).normalized()
    off -= off.dot(ax) * ax
    if f.dot(off) < 0:
        f = -f
    d = (d - d.dot(f) * f).normalized()
    # the wide end: the end of the long axis where the shield is wider
    pts = _pts
    t = (pts - np.array(c_sh)) @ np.array(d)
    w = (pts - np.array(c_sh)) @ np.array(d.cross(f))
    if np.ptp(w[t < t.min() + 0.15]) > np.ptp(w[t > t.max() - 0.15]):
        d = -d
    half = float(max(-t.min(), t.max()))
    f2, d2 = Vector((0, 1, 0)), Vector((0, 0, 1))
    r_sh = _frame(f2, d2, f2.cross(d2)) @ _frame(f, d, f.cross(d)).transposed()
    top = neck.z + p["shield_top_over_neck"]
    c2 = Vector((chest.x + p["shield_from_chest"][0], chest.y + p["shield_from_chest"][1], top - half))
    m_sh = Matrix.Translation(c2) @ r_sh.to_4x4() @ Matrix.Translation(-c_sh) @ rig.data.bones["shield"].matrix_local
    yl = Vector((0.8, 0.4, 0)).normalized()
    xl = Vector((0, 0, 1))
    hl = c2 + Vector(p["hand_l_from_shield"])
    targets["G_HandL"] = emp("G_HandL", Matrix.Translation(hl) @ _frame(xl, yl, xl.cross(yl)).to_4x4(), bone="Spine2")
    targets["G_ElbowL"] = emp("G_ElbowL", Matrix.Translation(Vector(p["elbow_l"]) + Vector((-0.3, -0.1, -0.1))), bone="Spine2")
    targets["G_Shield"] = emp("G_Shield", m_sh, obj=targets["G_HandL"], size=0.1)
    # the spear bone's target
    _pts2, c_sp, vt_sp, tmin, _tmax = _group_pca(kn, "spear")
    s = vt_sp[0] if vt_sp[0].z > 0 else -vt_sp[0]
    tmin = min(float(((_pts2 - np.array(c_sp)) @ np.array(s)).min()), 0.0)
    b = (vt_sp[1] - vt_sp[1].dot(s) * s).normalized()
    butt = c_sp + s * tmin
    b2 = Vector((0, 0, 1)).cross(sdir).normalized()
    r_sp = _frame(sdir, b2, sdir.cross(b2)) @ _frame(s, b, s.cross(b)).transposed()
    m_sp = Matrix.Translation(grip - sdir * p["grip_from_butt"]) @ r_sp.to_4x4() @ Matrix.Translation(-butt) @ rig.data.bones["spear"].matrix_local
    targets["G_Spear"] = emp("G_Spear", m_sp, obj=targets["G_HandR"], size=0.1)

    def clear(pb):
        for cc in list(pb.constraints):
            pb.constraints.remove(cc)

    for side, ft, kn_, ht, el in (("Left", "G_FootL", "G_KneeL", "G_HandL", "G_ElbowL"),
                                  ("Right", "G_FootR", "G_KneeR", "G_HandR", "G_ElbowR")):
        pb = rig.pose.bones[side + "Leg"]
        clear(pb)
        ik = pb.constraints.new('IK')
        ik.target, ik.pole_target, ik.chain_count = targets[ft], targets[kn_], 2
        pb = rig.pose.bones[side + "Foot"]
        clear(pb)
        pb.constraints.new('COPY_ROTATION').target = targets[ft]
        pb = rig.pose.bones[side + "ForeArm"]
        clear(pb)
        ik = pb.constraints.new('IK')
        ik.target, ik.pole_target, ik.chain_count = targets[ht], targets[el], 2
        pb = rig.pose.bones[side + "Hand"]
        clear(pb)
        pb.constraints.new('COPY_ROTATION').target = targets[ht]
    for part in ("spear", "shield"):
        pb = rig.pose.bones[part]
        clear(pb)
        pb.constraints.new('COPY_TRANSFORMS').target = targets["G_" + part.capitalize()]
    upd()

    want = {"LeftLeg": p["knee_l"], "RightLeg": p["knee_r"], "RightForeArm": tuple(elbow_r), "LeftForeArm": p["elbow_l"]}
    for bn, wv in want.items():
        ik = rig.pose.bones[bn].constraints[0]
        best = None
        for a in range(-180, 180, 10):
            ik.pole_angle = math.radians(a)
            upd()
            dd = (rig.pose.bones[bn].head - Vector(wv)).length
            if best is None or dd < best[0]:
                best = (dd, a)
        ik.pole_angle = math.radians(best[1])
        upd()

    # the fist turns about the shaft to the wrist's straightest (the thumb toward the butt)
    off_f = Vector(p["fist_offset"])
    x = sdir
    for _ in range(8):
        upd()
        e = rig.pose.bones["RightForeArm"].head
        h = rig.pose.bones["RightHand"].head
        u = (h - e).normalized()
        y = (u - u.dot(x) * x).normalized()
        r = _frame(x, y, x.cross(y))
        targets["G_HandR"].matrix_world = Matrix.Translation(grip - r @ off_f) @ r.to_4x4()
        upd()
        targets["G_Spear"].matrix_world = m_sp
    upd()

    # bake, then strip every helper
    bpy.context.view_layer.objects.active = rig
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=0, frame_end=n_f, step=1, only_selected=False, visual_keying=True,
                     clear_constraints=False, use_current_action=False, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    act = ad.action
    act.name = "GARRISON"
    act.use_fake_user = True
    for pb in rig.pose.bones:
        for cc in list(pb.constraints):
            pb.constraints.remove(cc)
    for e in targets.values():
        bpy.data.objects.remove(e)
    bpy.data.actions.remove(src)
    tr = ad.nla_tracks.new()
    tr.name = "GARRISON"
    strip = tr.strips.new("GARRISON", 0, act)
    strip.action_slot = act.slots[0]
    tr.mute = True
    sc.frame_start, sc.frame_end = 0, n_f
    return act
