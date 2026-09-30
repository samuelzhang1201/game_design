"""The Tripo cavalry's four clips (tripo.py builds the rig they drive). Run in the owner's
Blender after tripo.join():

    A = {"__file__": ".../animate.py", "T": T}; exec(open(A["__file__"]).read(), A)
    A["animate"]()      # cavalry_MARCH, cavalry_STANDBY, cavalry_GARRISON, cavalry_ATTACK

Every key starts from the REST pose (make_units.make_action leaves a bone a key does not
name where the last key put it), keyed at 30 fps like the scanned cavalry's clips.

  * MARCH and ATTACK are model_cavalry's, number for number (owner 2026-09-27: 行进动作设计
    幅度再大一点，人和马都要有动作), minus its shield: the shield rides the back now.
  * STANDBY is new (owner 2026-09-30: 加 STANDBY): the horse at rest shifting its weight
    between its hind legs, a swish, a nod; the rider breathing and looking about; the lance
    upright, the shield on his back.
  * GARRISON is ON GUARD (owner 2026-09-27) with the shield TAKEN TO THE ARM (owner
    2026-09-30: 用第一种 -- the shield leaves the back for the near arm, raised before him):
    the lance couched forward, the `shield` bone keyed in pose space onto a frame before his
    left side that turns with his chest, the near arm reaching it by IK; the neck sways.
    The swap itself is the runtime's MARCH/STANDBY <-> GARRISON blend.
"""
import bpy, math, sys
import numpy as np
from mathutils import Vector, Matrix, Quaternion

UNITS = "/Users/samuelzhang/game_design/tools/units3d/"
if UNITS not in sys.path:
    sys.path.insert(0, UNITS)
import make_units as mu

NAME = "cavalry"
FPS = 30
MARCH_FRAMES, MARCH_BEATS = 49, 16
STANDBY_FRAMES = 121
GARRISON_FRAMES = 121

# the guard: where the shield stands in front of him (rest coordinates, turned with the chest)
GUARD_CENTRE = Vector((-0.31, 0.19, 1.92))      # before his near side, its top at the chin
GUARD_OUT = Vector((-0.55, 0.83, 0.06))         # its face turned to the front-left
GUARD_LEAN = 0.12                               # its top leans back toward him
GRIP_IN = 0.075                                 # the near fist this far behind the face
GUARD_ARM_R = {"lance": {"rot": [("x", -72.0)]},
               "upperarm_r": {"rot": [("x", -18.0)]}, "forearm_r": {"rot": [("x", 8.0)]}}


def arm():
    return bpy.data.objects["cavalry_rig"]


def reset(a):
    for pb in a.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))


def pose(a, entries):
    reset(a)
    mu.apply_pose(a, entries)
    bpy.context.view_layer.update()


def key(a, frame):
    mu.key_all(a, frame)


def new_action(a, name):
    ad = a.animation_data or a.animation_data_create()
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    return act


def finish(a, act):
    for fc in mu.action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
    a.animation_data.action = None
    return act


def clip(a, name, keys, after=None):
    """keys: [(frame, pose dict)], numbered from 1 as model_cavalry's; keyed from frame 0 (the
    courier's lesson: a clip keyed from 1 starts at 1/FPS and holds its first pose a frame,
    a hitch at every loop). `after(a, frame)` runs on each posed key before it is keyed."""
    act = new_action(a, NAME + "_" + name)
    for frame, entries in keys:
        pose(a, entries)
        if after:
            after(a, frame - 1)
        key(a, frame - 1)
    return finish(a, act)


def merge(*poses):
    out = {}
    for p in poses:
        for bone, e in p.items():
            have = out.setdefault(bone, {})
            if "rot" in e:
                have["rot"] = list(have.get("rot", [])) + list(e["rot"])
            if "loc" in e:
                have["loc"] = e["loc"]
    return out


# ----------------------------------------------------------------- MARCH ----

def horse_step(u):
    nod = math.sin(2 * math.pi * u)
    beat = math.sin(4 * math.pi * u)
    return {"root": {"loc": (0, 0, abs(beat) * 0.045)},
            "horse_body": {"rot": [("x", nod * 2.2), ("y", nod * 1.8)]},
            "neck_1": {"rot": [("x", nod * 6.0), ("z", nod * 2.0)]},
            "neck_2": {"rot": [("x", nod * 4.5)]},
            "head_h": {"rot": [("x", -nod * 7.0)]},
            "tail_1": {"rot": [("y", nod * 10.0)]}, "tail_2": {"rot": [("y", nod * 9.0)]},
            "hips": {"rot": [("x", -beat * 4.5), ("y", -nod * 3.5)]},
            "spine": {"rot": [("x", beat * 3.0)]},
            "chest": {"rot": [("x", beat * 2.5), ("y", nod * 2.5)]},
            "head": {"rot": [("x", -beat * 3.0), ("z", nod * 4.0)]},
            "upperarm_l": {"rot": [("x", beat * 4.0)]},
            "upperarm_r": {"rot": [("x", -beat * 3.0)]},
            "forearm_r": {"rot": [("x", nod * 4.0)]}}


def march_keys():
    legs = [("hind", "l", 0.00), ("fore", "l", 0.25), ("hind", "r", 0.50), ("fore", "r", 0.75)]
    out = []
    for i in range(MARCH_BEATS + 1):
        u = i / MARCH_BEATS
        p = horse_step(u)
        for kind, n, ph in legs:
            a_, b_ = mu.gait(u + ph)
            if kind == "fore":
                p["fore_upper_" + n] = {"rot": [("x", a_ * 24.0)]}
                p["fore_lower_" + n] = {"rot": [("x", b_ * 34.0)]}
                p["fore_hoof_" + n] = {"rot": [("x", b_ * 18.0)]}
            else:
                p["hind_upper_" + n] = {"rot": [("x", a_ * 20.0)]}
                p["hind_gaskin_" + n] = {"rot": [("x", -b_ * 12.0)]}
                p["hind_lower_" + n] = {"rot": [("x", b_ * 24.0)]}
                p["hind_hoof_" + n] = {"rot": [("x", b_ * 18.0)]}
        out.append((1 + round(u * (MARCH_FRAMES - 1)), p))
    return out


# ---------------------------------------------------------------- ATTACK ----

def charge(body, fore_u, fore_l, lance_x, arm_r, lean, surge, neck):
    p = {"root": {"loc": (0, surge, 0)},
         "horse_body": {"rot": [("x", body)]},
         "neck_1": {"rot": [("x", neck)]}, "head_h": {"rot": [("x", -neck * 0.6)]},
         "tail_1": {"rot": [("x", -body * 0.8)]},
         "lance": {"rot": [("x", lance_x)]},
         "upperarm_r": {"rot": [("x", arm_r)]}, "forearm_r": {"rot": [("x", -arm_r * 0.5)]},
         "hips": {"rot": [("x", lean * 0.3)]}, "spine": {"rot": [("x", lean * 0.4)]},
         "chest": {"rot": [("x", lean * 0.3)]}}
    for n in ("r", "l"):
        p["hind_upper_" + n] = {"rot": [("x", -body)]}
        p["fore_upper_" + n] = {"rot": [("x", fore_u)]}
        p["fore_lower_" + n] = {"rot": [("x", fore_l)]}
        p["fore_hoof_" + n] = {"rot": [("x", fore_l * 0.5)]}
    return p


# the lance's turns are model_cavalry's LESS LANCE_REST: this lance leans 9.5 deg forward at
# rest (the scanned one stood upright), and the old numbers drove its tip into the ground
LANCE_REST = 12.0


def attack_keys():
    L = LANCE_REST
    return [(1, {}),
            (14, charge(-3.0, 4.0, -6.0, -35.0 + L, -10.0, 4.0, -0.04, -3.0)),     # gather, the lance dips
            (30, charge(14.0, 38.0, -70.0, -86.0 + L, -22.0, -14.0, 0.10, 8.0)),   # the surge, lance couched
            (44, charge(8.0, 20.0, -40.0, -88.0 + L, -24.0, -16.0, 0.30, 5.0)),    # the strike
            (60, charge(2.0, 4.0, -8.0, -60.0 + L, -12.0, -6.0, 0.12, 1.0)),
            (76, {})]


# --------------------------------------------------------------- STANDBY ----

def env(u, a_, b_):
    if u <= a_ or u >= b_:
        return 0.0
    return math.sin(math.pi * (u - a_) / (b_ - a_)) ** 2


def standby_pose(u):
    shift = math.sin(2 * math.pi * u)
    rest_l, rest_r = max(0.0, shift), max(0.0, -shift)
    swish = env(u, 0.30, 0.55) * math.sin(2 * math.pi * (u - 0.30) / 0.25 * 1.5)
    breath = math.sin(4 * math.pi * u)
    return {"horse_body": {"rot": [("y", 1.2 * shift)]},
            "hind_upper_l": {"rot": [("x", 2.0 * rest_l)]}, "hind_lower_l": {"rot": [("x", -7.0 * rest_l)]},
            "hind_hoof_l": {"rot": [("x", -12.0 * rest_l)]},
            "hind_upper_r": {"rot": [("x", 2.0 * rest_r)]}, "hind_lower_r": {"rot": [("x", -7.0 * rest_r)]},
            "hind_hoof_r": {"rot": [("x", -12.0 * rest_r)]},
            "tail_1": {"rot": [("z", 16.0 * swish)]}, "tail_2": {"rot": [("z", 20.0 * swish)]},
            "tail_3": {"rot": [("z", 24.0 * swish)]},
            "neck_1": {"rot": [("x", 6.0 * env(u, 0.62, 0.84))]},
            "neck_2": {"rot": [("x", 4.0 * env(u, 0.63, 0.85))]},
            "head_h": {"rot": [("x", 8.0 * env(u, 0.64, 0.86)), ("z", 5.0 * shift)]},
            "chest": {"rot": [("x", 1.2 * breath)]},
            "spine": {"rot": [("x", 0.6 * breath)]},
            "head": {"rot": [("z", 24.0 * env(u, 0.08, 0.50) - 14.0 * env(u, 0.55, 0.85))]},
            "upperarm_r": {"rot": [("x", 1.0 * breath)]}}


def standby_keys():
    return [(1 + round(u * (STANDBY_FRAMES - 1)), standby_pose(u % 1.0))
            for u in [i / 16 for i in range(17)]]


# -------------------------------------------------------------- GARRISON ----

def _shield_frames(T):
    """The shield's frame at rest on the back and on guard (rest coordinates): columns
    (across, down, in) -- a right-handed frame, `in` toward the rider -- and the origin
    at the shield bone's middle."""
    down = Vector((0, -math.sin(math.radians(T["SHIELD_BACK_DEG"])), -math.cos(math.radians(T["SHIELD_BACK_DEG"]))))
    across = Vector((1, 0, 0))
    out = across.cross(down).normalized()
    if out.y > 0:
        out = -out
    centre = T["SHIELD_TOP"] + down * (T["SHIELD_H"] * 0.45)
    rest = _frame(across, down, -out, centre)
    o = GUARD_OUT.normalized()
    d = Vector((0, GUARD_LEAN, -1.0))
    d = (d - o * d.dot(o)).normalized()
    i = -o
    a_ = d.cross(i)
    guard = _frame(a_, d, i, GUARD_CENTRE)
    return rest, guard


def _frame(a_, d, i, origin):
    m = Matrix.Identity(4)
    for r in range(3):
        m[r][0], m[r][1], m[r][2], m[r][3] = a_[r], d[r], i[r], origin[r]
    return m


def _chest_delta(a):
    pb = a.pose.bones["chest"]
    return pb.matrix @ pb.bone.matrix_local.inverted()


def _ik_left(a, wrist):
    """The near arm's upper and fore bones turned so the forearm's end reaches `wrist`
    (armature space): an IK constraint, evaluated, its result written back as plain
    rotations, the constraint removed."""
    fb = a.pose.bones["forearm_l"]
    tgt = bpy.data.objects.get("cav_ik_target") or bpy.data.objects.new("cav_ik_target", None)
    if tgt.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(tgt)
    tgt.location = a.matrix_world @ wrist
    c = fb.constraints.new("IK")
    c.target = tgt
    c.chain_count = 2
    bpy.context.view_layer.update()
    mats = {n: a.pose.bones[n].matrix.copy() for n in ("upperarm_l", "forearm_l", "hand_l")}
    fb.constraints.remove(c)
    for n in ("upperarm_l", "forearm_l", "hand_l"):
        a.pose.bones[n].matrix = mats[n]
        bpy.context.view_layer.update()
    bpy.data.objects.remove(tgt, do_unlink=True)


def guard_after(T):
    rest, guard = _shield_frames(T)

    def after(a, frame):
        dc = _chest_delta(a)
        g = dc @ guard
        sb = a.pose.bones["shield"]
        sb.matrix = g @ rest.inverted() @ sb.bone.matrix_local
        bpy.context.view_layer.update()
        grip = g @ Vector((0.0, 0.05, GRIP_IN))
        fore = a.pose.bones["forearm_l"]
        hand_len = (fore.bone.tail_local - fore.bone.head_local).length * 0 + \
            (a.data.bones["hand_l"].tail_local - a.data.bones["hand_l"].head_local).length
        wrist = grip - (g.to_3x3() @ Vector((1, 0, 0))) * hand_len * 0.6
        _ik_left(a, wrist)
    return after


def sway(k):
    return {"neck_1": {"rot": [("z", 5.0 * k)]}, "neck_2": {"rot": [("z", 4.0 * k)]},
            "head_h": {"rot": [("z", 6.0 * k)]}}


def garrison_keys():
    g = GUARD_ARM_R
    return [(1, merge(g)),
            (31, merge(g, sway(1.0), {"horse_body": {"rot": [("x", 0.8)]}, "neck_1": {"rot": [("x", -3.0)]},
                                      "neck_2": {"rot": [("x", -2.0)]}, "head_h": {"rot": [("x", 5.0)]},
                                      "tail_1": {"rot": [("y", 6.0)]}, "tail_2": {"rot": [("y", 8.0)]},
                                      "chest": {"rot": [("x", -1.5)]}, "head": {"rot": [("z", 8.0)]}})),
            (61, merge(g, {"neck_1": {"rot": [("x", 2.0)]}, "head_h": {"rot": [("x", -4.0)]},
                           "tail_1": {"rot": [("y", -5.0)]}, "tail_2": {"rot": [("y", -7.0)]},
                           "hind_upper_l": {"rot": [("x", 3.0)]}, "hind_lower_l": {"rot": [("x", -8.0)]},
                           "hind_hoof_l": {"rot": [("x", -10.0)]},
                           "hips": {"rot": [("x", 1.0)]}, "head": {"rot": [("z", -4.0), ("x", -3.0)]}})),
            (91, merge(g, sway(-1.0), {"horse_body": {"rot": [("x", -0.6)]}, "neck_2": {"rot": [("x", 2.5)]},
                                       "head_h": {"rot": [("x", 3.0)]}, "tail_1": {"rot": [("y", 5.0)]},
                                       "chest": {"rot": [("x", 1.2)]}, "head": {"rot": [("z", -9.0)]}})),
            (121, merge(g))]


# ------------------------------------------------------------------- all ----

def animate():
    T = globals()["T"]
    a = arm()
    for pb in a.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    acts = [clip(a, "MARCH", march_keys()),
            clip(a, "STANDBY", standby_keys()),
            clip(a, "GARRISON", garrison_keys(), guard_after(T)),
            clip(a, "ATTACK", attack_keys())]
    reset(a)
    bpy.context.view_layer.update()
    return {x.name: [int(x.frame_range[0]), int(x.frame_range[1])] for x in acts}


def show(name, frame):
    """Put an action on the rig at a frame, for a look."""
    a = arm()
    a.animation_data.action = bpy.data.actions[NAME + "_" + name]
    bpy.context.scene.frame_set(frame)


# ---------------------------------------------------------------- export ----

def stride_m(a, act):
    """Model metres one MARCH loop carries the piece (army_art.csv `stride_m`): the speed a
    planted hind hoof slides back (the loop is walked in place) x the loop's length."""
    ad = a.animation_data
    ad.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    sc = bpy.context.scene
    speeds = []
    for n in ("l", "r"):
        pts = []
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            pts.append((a.matrix_world @ a.pose.bones["hind_hoof_" + n].tail).copy())
        low = min(p.z for p in pts)
        for p, q in zip(pts, pts[1:]):
            if p.z < low + 0.01 and q.z < low + 0.01:
                speeds.append(abs(q.y - p.y))
    ad.action = None
    speeds.sort()
    v = speeds[len(speeds) // 2] if speeds else 0.0
    return v * (f1 - f0)


def export(out_dir):
    """cavalry.glb (+Y forward, one glTF animation per NLA track: MARCH, STANDBY, GARRISON,
    ATTACK) and the `cavalry` entry of units3d.json."""
    import json, os
    import model_cavalry as mc
    a = arm()
    ob = bpy.data.objects["cavalry"]
    acts = [bpy.data.actions[NAME + "_" + n] for n in ("MARCH", "STANDBY", "GARRISON", "ATTACK")]
    stride = stride_m(a, acts[0])
    ad = a.animation_data
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    mu.stash(a, acts)
    for track in ad.nla_tracks:
        track.name = track.name[len(NAME) + 1:]
        for s_ in track.strips:
            s_.name = track.name
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 0, max(int(x.frame_range[1]) for x in acts)
    reset(a)
    # a HIDDEN object cannot be selected, and the exporter writes the selection: a hidden
    # rig once went out as a bare mesh with no skeleton and no clips
    for o in (a, ob):
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_select = False
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > 20000:
        raise SystemExit("%d tris is over the 20,000 budget" % tris)
    path = os.path.join(out_dir, "cavalry", "cavalry.glb")
    mc.export_glb([a, ob], path)
    if not (a.select_get() and ob.select_get()):
        raise SystemExit("the rig or the mesh was not selected for the export")
    mpath = os.path.join(out_dir, "units3d.json")
    manifest = json.load(open(mpath))
    manifest["cavalry"] = {
        "label": "Knight", "kind": "mounted",
        "height_m": round(max(v.co.z for v in ob.data.vertices), 3),
        "source": "Tripo 3D (owner, paid plan) from tripo_kit/zimage_threequarter_s1.png; "
                  "tools/units3d/cavalry_tripo/",
        "tris": tris, "bones": len(a.data.bones), "weights": {"horse": "heat", "rider": "rigid"},
        "actions": {x.name[len(NAME) + 1:]: [int(x.frame_range[0]), int(x.frame_range[1])] for x in acts},
        "stride_m": round(stride, 3), "fps": FPS,
    }
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    return {"path": path, "tris": tris, "bones": len(a.data.bones), "stride_m": round(stride, 3),
            "height_m": manifest["cavalry"]["height_m"], "actions": manifest["cavalry"]["actions"]}
