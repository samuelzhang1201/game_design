"""The courier's rig, its two actions and the stride (courier_build.py's second half).

The skeleton uses the cavalry's bone names, so the game's helpers need nothing new:
  * the HORSE bones carry `cavalry_scan.rig_spec`'s names (root, horse_body, neck_1,
    neck_2, head_h, tail_1..3, fore_upper/lower/hoof_l|r, hind_upper/gaskin/lower/hoof_l|r),
    placed on the Tripo horse by tripo.horse_spec;
  * the RIDER bones carry make_units' mounted names (hips, spine, chest, neck, head,
    clavicle_/upperarm_/forearm_/hand_/thigh_/shin_/foot_ r and l);
  * `pole` rides the off hand and carries `pennon_1` / `pennon_2` along the flag;
    `case` hangs on the saddle.

Actions (make_units' `make_action` / `stash` / `gait`), keyed as FK from `NEUTRAL` (the
Tripo horse's raised foreleg straightened) and then baked through two IK chains - both
legs to their stirrups - so a rider who rises, pitches and rocks keeps his feet in the
irons; the helper bones are dropped after the bake. The weights are tripo.weigh's.
"""
import bpy, math, os, sys
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
UNITS = os.path.dirname(HERE)            # tools/units3d: the cavalry's rig and weight helpers
for p in (HERE, UNITS):
    if p not in sys.path:
        sys.path.insert(0, p)
import model_cavalry as mc               # heat, copy_weights, rigid, activate, export_glb
mu = mc.make_units                       # build_armature, make_action, stash, gait, apply_pose

NAME = "courier"
FPS = 24                  # the clips' frame rate (the scene's, which the glTF exporter times by)
GALLOP_FRAMES = 24        # one stride of the gallop, a loop
IDLE_FRAMES = 72          # the standing loop
CAVALRY_LENGTH = 2.60     # cavalry_scan.rig_spec's leg-top heights were set on this horse
# the transverse gallop: where in the loop each hoof lands (near = left) and the share of
# the loop each leg is in the air; the last landing is followed by the suspension
FOOTFALL = {("hind", "l"): 0.00, ("hind", "r"): 0.12, ("fore", "l"): 0.30, ("fore", "r"): 0.42}
GALLOP_SWING = 0.66
IK_BONES = ("ik_foot_r", "ik_foot_l")
REINS = "l"               # the near fist holds the reins (the off hand the staff)
TAIL_STREAM = 0.4         # how far the tail streams out in the gallop: it covers a notch in the rump the model never textured
HIND_SWING = 22.0         # the hind legs' swing from the hip, degrees each way: the rump and the trailing leg are one shell
NEUTRAL = {}              # tripo.neutral_pose: every key starts from it


def with_neutral(pose):
    out = dict(pose)
    for b, e in NEUTRAL.items():
        have = dict(out.get(b, {}))
        have["rot"] = list(e.get("rot", [])) + list(have.get("rot", []))
        out[b] = have
    return out


# ------------------------------------------------------------------ helpers

def activate(ob):
    mc.activate(ob)


def rigid(ob, bone):
    mc.rigid(ob, bone)


def set_weights(ob, table):
    """table: vertex index -> {bone: weight} (normalised here)."""
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    groups = {}
    for vi, ws in table.items():
        tot = sum(ws.values()) or 1.0
        for b, w in ws.items():
            if w <= 1e-4:
                continue
            g = groups.get(b) or ob.vertex_groups.new(name=b)
            groups[b] = g
            g.add([vi], w / tot, "REPLACE")



HORSE = {"horse_body", "neck_1", "neck_2", "head_h", "tail_1", "tail_2", "tail_3"} | {
    "fore_%s_%s" % (j, n) for j in ("upper", "lower", "hoof") for n in "lr"} | {
    "hind_%s_%s" % (j, n) for j in ("upper", "gaskin", "lower", "hoof") for n in "lr"}
RIDER = {"hips", "spine", "chest", "neck", "head"} | {
    p + s for p in ("clavicle_", "upperarm_", "forearm_", "hand_", "thigh_", "shin_", "foot_") for s in "rl"}


# ----------------------------------------------------------------- actions

def env(u, a, b):
    """0 outside [a, b], a smooth hump inside."""
    if u <= a or u >= b:
        return 0.0
    return math.sin(math.pi * (u - a) / (b - a)) ** 2


def gallop_pose(u):
    s = lambda ph: math.sin(2 * math.pi * (u - ph))
    bounce = 0.5 + 0.5 * math.cos(2 * math.pi * (u - 0.88))        # high in the suspension
    pose = {"root": {"loc": (0, 0, 0.05 * bounce)},
            "horse_body": {"rot": [("x", 1.5 * s(0.10))]},
            "neck_1": {"rot": [("x", -8.0 * s(0.20))]},
            "neck_2": {"rot": [("x", -5.0 * s(0.25))]},
            "head_h": {"rot": [("x", 6.0 * s(0.28))]},
            # the tail streams out behind and flutters
            "tail_1": {"rot": [("x", (-32.0 + 4.0 * s(0.1)) * TAIL_STREAM), ("y", 5.0 * s(0.3))]},
            "tail_2": {"rot": [("x", (-14.0 + 5.0 * s(0.2)) * TAIL_STREAM), ("y", 7.0 * s(0.4))]},
            "tail_3": {"rot": [("x", (-8.0 + 6.0 * s(0.3)) * TAIL_STREAM), ("y", 9.0 * s(0.5))]},
            # the rider up in the irons, pitched ~15 deg forward, rocking against the horse
            "hips": {"loc": (0, 0.035, 0.06 + 0.012 * s(0.60))},
            "spine": {"rot": [("x", -8.0 - 2.5 * s(0.10))]},
            "chest": {"rot": [("x", -9.0 - 1.5 * s(0.15))]},
            "neck": {"rot": [("x", 5.0)]},
            "head": {"rot": [("x", 11.0 + 2.0 * s(0.15))]},
            "upperarm_" + REINS: {"rot": [("x", 5.0 * s(0.30))]},
            "forearm_" + REINS: {"rot": [("x", 4.0 * s(0.35))]},
            # the pennon streams, the case bounces a frame behind the saddle
            "pennon_1": {"rot": [("z", 10.0 * math.sin(4 * math.pi * u))]},
            "pennon_2": {"rot": [("z", 16.0 * math.sin(4 * math.pi * u - 1.0))]},
            "case": {"rot": [("x", -10.0 * (0.5 + 0.5 * math.cos(2 * math.pi * (u - 0.88 - 1.0 / GALLOP_FRAMES))) + 3.0)]}}
    for (kind, n), land in FOOTFALL.items():
        a, bf = mu.gait(u - land, GALLOP_SWING)
        if kind == "fore":
            pose["fore_upper_" + n] = {"rot": [("x", a * 32.0)]}
            pose["fore_lower_" + n] = {"rot": [("x", bf * 42.0)]}
            pose["fore_hoof_" + n] = {"rot": [("x", bf * 26.0)]}
        else:
            pose["hind_upper_" + n] = {"rot": [("x", a * HIND_SWING)]}
            pose["hind_gaskin_" + n] = {"rot": [("x", -bf * 16.0)]}
            pose["hind_lower_" + n] = {"rot": [("x", bf * 30.0)]}
            pose["hind_hoof_" + n] = {"rot": [("x", bf * 22.0)]}
    return pose


def idle_pose(u):
    shift = math.sin(2 * math.pi * u)
    rest_l, rest_r = max(0.0, shift), max(0.0, -shift)
    swish = env(u, 0.30, 0.55) * math.sin(2 * math.pi * (u - 0.30) / 0.25 * 1.5)
    return {"horse_body": {"rot": [("y", 1.4 * shift)]},
            "hind_upper_l": {"rot": [("x", 2.0 * rest_l)]}, "hind_lower_l": {"rot": [("x", -7.0 * rest_l)]},
            "hind_hoof_l": {"rot": [("x", -12.0 * rest_l)]},
            "hind_upper_r": {"rot": [("x", 2.0 * rest_r)]}, "hind_lower_r": {"rot": [("x", -7.0 * rest_r)]},
            "hind_hoof_r": {"rot": [("x", -12.0 * rest_r)]},
            "tail_1": {"rot": [("z", 16.0 * swish)]}, "tail_2": {"rot": [("z", 20.0 * swish)]},
            "tail_3": {"rot": [("z", 24.0 * swish)]},
            "neck_1": {"rot": [("x", -6.0 * env(u, 0.62, 0.82))]},
            "neck_2": {"rot": [("x", -4.0 * env(u, 0.63, 0.83))]},
            "head_h": {"rot": [("x", -9.0 * env(u, 0.64, 0.84))]},
            "head": {"rot": [("z", 28.0 * env(u, 0.08, 0.52))]},
            "chest": {"rot": [("x", 1.0 * math.sin(4 * math.pi * u))]},
            "pennon_1": {"rot": [("z", 4.0 * math.sin(4 * math.pi * u))]},
            "pennon_2": {"rot": [("z", 7.0 * math.sin(4 * math.pi * u - 0.8))]}}


def keys(fn, frames, step):
    out = []
    for f in range(1, frames + 2, step):
        u = (f - 1) / frames
        out.append((f, fn(u % 1.0)))
    if out[-1][0] != frames + 1:
        out.append((frames + 1, fn(0.0)))
    return out


def ik_constraints(arm, on):
    for n in "rl":
        pb = arm.pose.bones["shin_" + n]
        if on:
            c = pb.constraints.new("IK")
            c.name = "ik"
            c.target, c.subtarget = arm, "ik_foot_" + n
            c.chain_count = 2
            c.use_tail = True
        else:
            for c in list(pb.constraints):
                pb.constraints.remove(c)


def bake(arm, fk, name):
    sc = bpy.context.scene
    ad = arm.animation_data
    ad.action = fk
    if getattr(fk, "slots", None):
        try:
            ad.action_slot = fk.slots[0]
        except Exception:
            pass
    f0, f1 = [int(x) for x in fk.frame_range]
    activate(arm)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=False, visual_keying=True,
                     clear_constraints=False, use_current_action=False, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    act = ad.action
    act.name = name
    act.use_fake_user = True
    ad.action = None
    return act


def drop_helpers(arm, acts):
    for act in acts:
        for fc in list(mu.action_fcurves(act)):
            if any('"%s"' % b in fc.data_path for b in IK_BONES):
                owner = fc.id_data
                removed = False
                for layer in getattr(act, "layers", ()):
                    for strip in getattr(layer, "strips", ()):
                        for bagx in getattr(strip, "channelbags", ()):
                            if fc in list(bagx.fcurves):
                                bagx.fcurves.remove(fc)
                                removed = True
                if not removed and hasattr(act, "fcurves"):
                    act.fcurves.remove(fc)
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    for b in IK_BONES:
        e = arm.data.edit_bones.get(b)
        if e:
            arm.data.edit_bones.remove(e)
    bpy.ops.object.mode_set(mode="OBJECT")


def grounded_gallop(arm):
    """GALLOP keys with the body carried on its legs. The hind hooves in stance set the
    height of the rear (the root) and the fore hooves in stance the height of the front
    (a pitch of the horse's body, which turns about its rear end): each is the lift that
    puts the LOWEST hoof of that pair back on the ground, so no hoof sinks and none
    floats. Frames with no hoof of a pair down are eased between their neighbours, and
    the suspension (no hoof down at all) is lifted by the leap."""
    stance = 1.0 - GALLOP_SWING
    mu.apply_pose(arm, NEUTRAL)
    bpy.context.view_layer.update()
    hoof = lambda leg: arm.matrix_world @ arm.pose.bones[leg[0] + "_hoof_" + leg[1]].tail
    # every hoof down is set on the GROUND: the lowest hoof of the standing (neutral) pose
    ground = min(hoof(leg).z for leg in FOOTFALL)
    rest = {leg: ground for leg in FOOTFALL}
    pivot = arm.pose.bones["horse_body"].head.y
    reach = sum(hoof(leg).y for leg in FOOTFALL if leg[0] == "fore") / 2 - pivot
    frames = list(range(1, GALLOP_FRAMES + 1))
    poses, lift = {}, {"hind": {}, "fore": {}}
    for f in frames:
        u = (f - 1) / GALLOP_FRAMES
        pose = with_neutral(gallop_pose(u))
        pose.pop("root", None)
        poses[f] = pose
        mu.apply_pose(arm, pose)
        bpy.context.view_layer.update()
        for end in ("hind", "fore"):
            down = [leg for leg, land in FOOTFALL.items() if leg[0] == end and ((u - land) % 1.0) < stance]
            if down:
                lift[end][f] = max(hoof(leg).z - rest[leg] for leg in down) * -1.0
    airborne = [f for f in frames if f not in lift["hind"] and f not in lift["fore"]]

    def filled(series):
        known = sorted(series)
        out = {}
        for f in frames:
            if f in series:
                out[f] = series[f]
                continue
            a = max([k for k in known if k < f], default=known[-1] - GALLOP_FRAMES)
            b = min([k for k in known if k > f], default=known[0] + GALLOP_FRAMES)
            ca, cb = series[(a - 1) % GALLOP_FRAMES + 1], series[(b - 1) % GALLOP_FRAMES + 1]
            out[f] = ca + (cb - ca) * (f - a) / (b - a)
        return out
    h, fo = filled(lift["hind"]), filled(lift["fore"])
    leap = {f: 0.0 for f in frames}
    if airborne:
        a0, a1 = airborne[0] - 1, airborne[-1] + 1
        for f in airborne:
            leap[f] = 0.07 * math.sin(math.pi * (f - a0) / (a1 - a0))
    out = []
    for f in frames + [GALLOP_FRAMES + 1]:
        g = (f - 1) % GALLOP_FRAMES + 1
        pose = dict(poses[g])
        pose["root"] = {"loc": (0, 0, h[g] + leap[g])}
        pitch = math.degrees(math.atan2(fo[g] - h[g], reach))
        body = dict(pose.get("horse_body", {}))
        body["rot"] = list(body.get("rot", [])) + [("x", pitch)]
        pose["horse_body"] = body
        out.append((f, pose))
    mu.apply_pose(arm, {})
    print("GALLOP rear lift %.3f..%.3f  front %.3f..%.3f  airborne frames %s" % (
        min(h.values()), max(h.values()), min(fo.values()), max(fo.values()), airborne))
    return out


def actions(arm):
    bpy.context.scene.render.fps = FPS
    # keyed from frame 0: the glTF clip then runs 0..N/FPS exactly (a clip keyed from frame
    # 1 starts at 1/FPS and holds its first pose a frame, a hitch at every loop)
    zero = lambda ks: [(f - 1, p) for f, p in ks]
    fk_g = mu.make_action(arm, NAME + "_GALLOP_fk", zero(grounded_gallop(arm)))
    fk_i = mu.make_action(arm, NAME + "_IDLE_fk", zero(keys(lambda u: with_neutral(idle_pose(u)), IDLE_FRAMES, 2)))
    ik_constraints(arm, True)
    gallop = bake(arm, fk_g, NAME + "_GALLOP")
    idle = bake(arm, fk_i, NAME + "_IDLE")
    ik_constraints(arm, False)
    for a in (fk_g, fk_i):
        bpy.data.actions.remove(a)
    return [gallop, idle]


def stride_m(arm, gallop):
    """How far the near hind hoof's contact point moves back through its stance, over the
    share of the loop that stance takes: the ground one GALLOP loop covers."""
    ad = arm.animation_data
    ad.action = gallop
    if getattr(gallop, "slots", None):
        try:
            ad.action_slot = gallop.slots[0]
        except Exception:
            pass
    sc = bpy.context.scene
    stance = 1.0 - GALLOP_SWING
    land = FOOTFALL[("hind", "l")]
    f_in = round(land * GALLOP_FRAMES)                  # the clip is keyed from frame 0
    f_out = round((land + stance) * GALLOP_FRAMES)
    ys = {}
    for f in (f_in, f_out):
        sc.frame_set(f)
        pb = arm.pose.bones["hind_hoof_l"]
        ys[f] = (arm.matrix_world @ pb.tail).y
    sweep = ys[f_in] - ys[f_out]
    frac = (f_out - f_in) / GALLOP_FRAMES
    ad.action = None
    sc.frame_set(0)
    return sweep / frac, sweep, frac
