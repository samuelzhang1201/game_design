"""GARRISON for the Tripo knight: the owner's Tripo clip, carried onto the game rig.

The guard is the owner's own Tripo animation (owner 2026-10-13: 驻防的动作我这里有了) — "士兵单膝跪地，
左手持盾，右手持矛戒备", a crouched guard on the same 65-bone Mixamo skeleton as the game's knight —
with the shield and spear fitted in assets/3D/units/model_wip/knight_kneel_guard.blend (owner, in
turn: 左手持盾，右手架矛 / 矛靠上盾牌边缘，指向视线前方，手腕弯曲的角度再小一点 / 盾牌稍微降低一点，露出士兵的眼睛 / 完美):

* the shield's frame follows Spine2, its place the left fist (IK'd 12 cm down so the visor shows);
* the spear rests on the shield's inner edge (a damped track to `ShieldRest`, an empty on the
  shield) from the right fist, aimed with the head's gaze (44 deg to his left, 8 deg up);
* the right hand on IK to a target turned about the shaft for the straightest wrist (0.4-3 deg),
  the elbow tucked behind the right side (pole -135).

Run in the owner's Blender, two steps, each on its own file:

    K = {}; exec(open("/Users/samuelzhang/game_design/tools/units3d/infantry_knight/kneel_guard.py").read(), K)
    K["record"]()   # with knight_kneel_guard.blend open: every bone's pose and the props' frames -> JSON
    K["apply"]()    # with knight_spear_shield_game.blend open: GARRISON keyed on inf_rig, NLA track

The two skeletons are identical (rest rotation and head offsets 0 after the game's 180 deg turn and
x1.0499 scale), so each bone's armature-space pose is carried exactly: rotation turned 180 deg about
Z, translation turned and scaled by the game rig's 1.8 x 1.0499. The props ride their own bones in
the game (`spear` under RightHand, `shield` under LeftForeArm), so their poses are solved from the
props' frames: the spear's (butt, shaft axis, blade) and the shield's (centre, face, wide end),
read off the meshes by PCA in both files.
"""
import json
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

JSON = "/tmp/knight_kneel_guard.json"
GAME_SCALE = 1.8 * 1.0499          # the game rig's data scale (inf_rig, export frame)
KNEEL_OBJ_SCALE = 1.8              # Knight_Rig's object scale in the kneel file


def _frame4(r, p):
    m = Matrix(r).to_4x4()
    m.translation = p
    return m


def record(path=JSON):
    rig = bpy.data.objects["Knight_Rig"]
    sc = bpy.context.scene
    sp = bpy.data.objects["Spear"]
    sh = bpy.data.objects["Shield"]
    pts = np.array([tuple(v.co) for v in sp.data.vertices])
    c = pts.mean(0)
    _u, _s, vt = np.linalg.svd(pts - c, full_matrices=False)
    s = Vector(vt[0]) if vt[0][2] > 0 else -Vector(vt[0])
    butt = Vector(c) + s * float(((pts - c) @ np.array(s)).min())
    b = Vector(vt[1])
    b = (b - b.dot(s) * s).normalized()

    def frame(o, axis, side, pt):
        r = o.matrix_world.to_3x3()
        a = (r @ axis).normalized()
        sd = r @ side
        sd = (sd - sd.dot(a) * a).normalized()
        return Matrix((sd, a.cross(sd), a)).transposed(), o.matrix_world @ pt

    rec = {"spear": [], "shield": [], "rest": {}, "pose": {pb.name: [] for pb in rig.pose.bones}}
    for bone in rig.data.bones:
        rec["rest"][bone.name] = [list(r) for r in bone.matrix_local]
    for f in range(sc.frame_start, sc.frame_end + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        for pb in rig.pose.bones:
            rec["pose"][pb.name].append([list(r) for r in pb.matrix])
        # the shield's own frame: +X across, +Z to the wide edge, -Y its face; centre at z 0.49
        for key, o, axis, side, pt in (("spear", sp, s, b, butt),
                                       ("shield", sh, Vector((0, 0, 1)), Vector((1, 0, 0)), Vector((0, 0, 0.49)))):
            r, p = frame(o, axis, side, pt)
            rec[key].append({"R": [list(x) for x in r], "p": list(p)})
    json.dump(rec, open(path, "w"))
    return len(rec["spear"])


def _rest_frames(rig, kn):
    def pts(name):
        gi = kn.vertex_groups[name].index
        return np.array([tuple(v.co) for v in kn.data.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)])

    p = pts("spear")
    c = p.mean(0)
    _u, _s, vt = np.linalg.svd(p - c, full_matrices=False)
    s = Vector(vt[0]) if vt[0][2] > 0 else -Vector(vt[0])
    butt = Vector(c) + s * float(((p - c) @ np.array(s)).min())
    b = Vector(vt[1])
    b = (b - b.dot(s) * s).normalized()
    f_sp = _frame4(Matrix((b, s.cross(b), s)).transposed(), butt)

    p = pts("shield")
    c = p.mean(0)
    _u, _s, vt = np.linalg.svd(p - c, full_matrices=False)
    d, w, f = Vector(vt[0]), Vector(vt[1]), Vector(vt[2])
    fa = rig.data.bones["LeftForeArm"]
    off = Vector(c) - fa.head_local
    ax = (fa.tail_local - fa.head_local).normalized()
    off -= off.dot(ax) * ax
    if f.dot(off) < 0:          # the face is the side away from the forearm it hangs on
        f = -f
    td = (p - c) @ np.array(d)
    tw = (p - c) @ np.array(w)
    if np.ptp(tw[td < td.min() + 0.15]) > np.ptp(tw[td > td.max() - 0.15]):
        d = -d                  # +d runs to the wide edge
    tf = (p - c) @ np.array(f)
    centre = (Vector(c) + d * float((td.min() + td.max()) / 2) + w * float((tw.min() + tw.max()) / 2)
              + f * float((tf.min() + tf.max()) / 2))
    back = -f
    f_sh = _frame4(Matrix((back.cross(d), back, d)).transposed(), centre)
    return f_sp, f_sh


def apply(path=JSON):
    rec = json.load(open(path))
    rig = bpy.data.objects["inf_rig"]
    kn = bpy.data.objects["infantry"]
    ad = rig.animation_data
    rz = Matrix.Rotation(math.pi, 3, 'Z')
    k = GAME_SCALE
    kw = GAME_SCALE / KNEEL_OBJ_SCALE

    def gname(n):
        g = n.replace("mixamorig:", "")
        return "head" if g == "Head" else g

    def conv(rows):
        m = Matrix(rows)
        return Matrix.Translation(rz @ (m.translation * k)) @ (rz @ m.to_3x3().normalized()).to_4x4()

    f_sp, f_sh = _rest_frames(rig, kn)
    rest = {"spear": f_sp, "shield": f_sh}
    b_rest = {n: rig.data.bones[n].matrix_local.copy() for n in ("spear", "shield")}
    if bpy.data.actions.get("GARRISON"):
        bpy.data.actions.remove(bpy.data.actions["GARRISON"])
    tr = ad.nla_tracks.get("GARRISON")
    if tr:
        ad.nla_tracks.remove(tr)
    act = bpy.data.actions.new("GARRISON")
    act.use_fake_user = True
    ad.action = act
    ad.action_slot = act.slots.new('OBJECT', rig.name)
    order = []

    def walk(bone):
        order.append(bone.name)
        for ch in bone.children:
            walk(ch)

    walk(rig.data.bones["Hips"])
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    n = len(rec["spear"])
    for i in range(n):
        want = {gname(name): conv(v[i]) for name, v in rec["pose"].items()}
        for key in ("spear", "shield"):
            r = rec[key][i]
            fg = _frame4(rz @ Matrix(r["R"]), rz @ (Vector(r["p"]) * kw))
            want[key] = fg @ rest[key].inverted() @ b_rest[key]
        for name in order:
            bone = rig.data.bones[name]
            pb = rig.pose.bones[name]
            m = want[name]
            if bone.parent:
                rel = bone.parent.matrix_local.inverted() @ bone.matrix_local
                local = rel.inverted() @ want[bone.parent.name].inverted() @ m
            else:
                local = bone.matrix_local.inverted() @ m
            loc, rot, _sc = local.decompose()
            pb.location, pb.rotation_quaternion, pb.scale = loc, rot, (1, 1, 1)
            pb.keyframe_insert("location", frame=i)
            pb.keyframe_insert("rotation_quaternion", frame=i)
    ad.action = None
    tr = ad.nla_tracks.new()
    tr.name = "GARRISON"
    strip = tr.strips.new("GARRISON", 0, act)
    strip.action_slot = act.slots[0]
    tr.mute = True
    return n
