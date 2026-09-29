"""The courier's rig, its two actions and the stride (courier_build.py's second half).

The skeleton is the cavalry's, so the game's helpers need nothing new:
  * the HORSE bones are `cavalry_scan.rig_spec`'s, laid on the same Hunt Museum scan by
    its own surface probes (the leg tops' fixed heights scaled from the cavalry's 2.60 m
    horse to this one's 2.45 m);
  * the RIDER bones carry make_units' mounted names (hips, spine, chest, neck, head,
    clavicle_/upperarm_/forearm_/hand_/thigh_/shin_/foot_ r and l), laid on the joints the
    v3 build posed the base-mesh body on (`PJ`) — a courier sits where the knight did not;
  * `pole` stands on the saddle (the pick's pole sits in a bucket on the flap) and carries
    `pennon_1` / `pennon_2` along the flag's fly; `case` hangs on the saddle.

Weights, part by part (the joined model carries a `part_id` per vertex from texture_v3):
bone heat for the horse (cavalry_scan's `mc.heat`, over the horse's bones only) and the
rider's body (over his), with the by-distance fallback; the head, boots, bands and
clothes by distance to their own bones; the fists, eyes, hat and feather rigid; the tack
rigid to the horse's body; the bridle copied from the horse and handed to the fist
toward the reins' end; the mane and tail by distance to the neck, head and tail; the flag
along its fly between the pole and the two pennon bones.

Actions (make_units' `make_action` / `stash` / `gait`), keyed as FK and then baked
through three IK chains — both legs to their stirrups and the left arm to the pole — so
a rider who rises, pitches and rocks keeps his feet in the irons and his fist on the
staff; the helper bones are dropped after the bake.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import scan_horse                       # puts tools/units3d on the path, imports cavalry_scan
cs = scan_horse.cs
mc = cs.mc
mu = mc.make_units

NAME = "courier"
FPS = 24                  # the clips' frame rate (the scene's, which the glTF exporter times by)
GALLOP_FRAMES = 24        # one stride of the gallop, a loop
IDLE_FRAMES = 72          # the standing loop
CAVALRY_LENGTH = 2.60     # cavalry_scan.rig_spec's leg-top heights were set on this horse
# the transverse gallop: where in the loop each hoof lands (near = left) and the share of
# the loop each leg is in the air; the last landing is followed by the suspension
FOOTFALL = {("hind", "l"): 0.00, ("hind", "r"): 0.12, ("fore", "l"): 0.30, ("fore", "r"): 0.42}
GALLOP_SWING = 0.66
PENNON_FLY = 0.52         # props_v3.pennon's FL: the flag's length along its fly
IK_BONES = ("ik_foot_r", "ik_foot_l", "ik_hand_l")


# ------------------------------------------------------------------ helpers

def _v(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def activate(ob):
    mc.activate(ob)


def split_parts(ob, order):
    """One object per `part_id` (vertex groups and UVs kept), named after texture_v3's parts."""
    ids = np.empty(len(ob.data.vertices), np.int64)
    ob.data.attributes["part_id"].data.foreach_get("value", ids)
    out = {}
    for pid, name in enumerate(order):
        if not (ids == pid).any():
            continue
        o = ob.copy()
        o.data = ob.data.copy()
        o.name = o.data.name = "part_" + name
        bpy.context.scene.collection.objects.link(o)
        bm = bmesh.new(); bm.from_mesh(o.data)
        lay = bm.verts.layers.int.get("part_id")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v[lay] != pid], context="VERTS")
        bm.to_mesh(o.data); bm.free()
        out[name] = o
    bpy.data.objects.remove(ob, do_unlink=True)
    return out


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (p - a.lerp(b, t)).length


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


# ---------------------------------------------------------------- the spec

def pennon_frame(butt, top, d):
    d = np.asarray(d, float)
    fly0 = np.array((0.0, -1.0, 0.0)) - d * (d @ np.array((0.0, -1.0, 0.0)))
    return fly0 / np.linalg.norm(fly0)


def rig_spec(surf, PJ, pole, case_c):
    k = scan_horse.cs.HORSE_LENGTH / CAVALRY_LENGTH
    horse = []
    for name, parent, head, tail in cs.rig_spec(surf):
        if name == "root" or name in HORSE:
            if name.startswith(("fore_upper_", "hind_upper_")):
                head = Vector((head.x, head.y, head.z * k))
            horse.append((name, parent, head, tail))
    J = lambda key: Vector(PJ[key][:])
    b = list(horse)
    b += [("hips", "horse_body", J("pelvis:h"), J("pelvis:t")),
          ("spine", "hips", J("spine:h"), J("spine:t")),
          ("chest", "spine", J("chest:h"), J("chest:t")),
          ("neck", "chest", J("neck:h"), J("neck:t")),
          ("head", "neck", J("head:h"), J("head:t"))]
    for n, s in (("r", ".R"), ("l", ".L")):
        b += [("clavicle_" + n, "chest", J("clavicle" + s + ":h"), J("clavicle" + s + ":t")),
              ("upperarm_" + n, "clavicle_" + n, J("upper_arm" + s + ":h"), J("upper_arm" + s + ":t")),
              ("forearm_" + n, "upperarm_" + n, J("forearm" + s + ":h"), J("forearm" + s + ":t")),
              ("hand_" + n, "forearm_" + n, J("hand" + s + ":h"), J("hand" + s + ":t")),
              ("thigh_" + n, "hips", J("thigh" + s + ":h"), J("thigh" + s + ":t")),
              ("shin_" + n, "thigh_" + n, J("shin" + s + ":h"), J("shin" + s + ":t")),
              ("foot_" + n, "shin_" + n, J("foot" + s + ":h"), J("foot" + s + ":t"))]
    butt, top, d = [np.asarray(x, float) for x in pole]
    d = d / np.linalg.norm(d)
    fly = pennon_frame(butt, top, d)
    hoist = top - d * 0.22
    b += [("pole", "horse_body", _v(butt), _v(butt + d * 0.6)),
          ("pennon_1", "pole", _v(hoist), _v(hoist + fly * PENNON_FLY * 0.5)),
          ("pennon_2", "pennon_1", _v(hoist + fly * PENNON_FLY * 0.5), _v(hoist + fly * PENNON_FLY)),
          ("case", "horse_body", _v(np.asarray(case_c) + (0, 0, 0.10)), _v(np.asarray(case_c) - (0, 0, 0.06)))]
    # IK helpers (dropped after the bake): the stirrups on the saddle, the grip on the pole
    for n, s in (("r", ".R"), ("l", ".L")):
        a = J("shin" + s + ":t")
        b.append(("ik_foot_" + n, "horse_body", a, a + Vector((0, 0.08, 0))))
    w = J("forearm.L:t")
    b.append(("ik_hand_l", "pole", w, w + Vector((0, 0.08, 0))))
    return b


HORSE = {"horse_body", "neck_1", "neck_2", "head_h", "tail_1", "tail_2", "tail_3"} | {
    "fore_%s_%s" % (j, n) for j in ("upper", "lower", "hoof") for n in "lr"} | {
    "hind_%s_%s" % (j, n) for j in ("upper", "gaskin", "lower", "hoof") for n in "lr"}
RIDER = {"hips", "spine", "chest", "neck", "head"} | {
    p + s for p in ("clavicle_", "upperarm_", "forearm_", "hand_", "thigh_", "shin_", "foot_") for s in "rl"}


# ----------------------------------------------------------------- weights

def by_distance(ob, arm, bones, power=5.0, k=3):
    """model_cavalry.by_distance (nearest bone segments, distance to the fifth), for any
    number of bones (its k=3 needs three)."""
    segs = [(b.name, np.array(b.head_local), np.array(b.tail_local)) for b in arm.data.bones if b.name in bones]
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    d = np.empty((len(segs), n))
    for i, (_, a, b) in enumerate(segs):
        ab = b - a
        t = np.clip(((co - a) @ ab) / max(float(ab @ ab), 1e-9), 0, 1)
        d[i] = np.linalg.norm(co - (a + t[:, None] * ab), axis=1)
    k = min(k, len(segs))
    order = np.argsort(d, axis=0)[:k]
    w = 1.0 / np.power(np.take_along_axis(d, order, axis=0) + 1e-4, power)
    w /= w.sum(axis=0, keepdims=True)
    tab = {}
    for vi in range(n):
        tab[vi] = {segs[order[s_, vi]][0]: float(w[s_, vi]) for s_ in range(k) if w[s_, vi] > 1e-3}
    set_weights(ob, tab)


def weigh(parts, arm, pole, case_c, head):
    how = {}
    horse = parts["horse"]
    how["horse"] = mc.heat(horse, arm, HORSE)
    how["rider"] = mc.heat(parts["rider"], arm, RIDER)
    by_distance(parts["rider_head"], arm, ("neck", "head"))
    for key in ("rider_boots", "boot_bands"):
        if key in parts:
            by_distance(parts[key], arm, ("shin_r", "foot_r", "shin_l", "foot_l"))
    for key in ("clothes", "clothes_trim"):
        if key in parts:
            by_distance(parts[key], arm, ("hips", "spine", "chest", "neck", "clavicle_r", "clavicle_l",
                                          "upperarm_r", "upperarm_l", "forearm_r", "forearm_l",
                                          "thigh_r", "thigh_l"))
    # the fists: each whole to its own hand
    hands = parts["rider_hands"]
    hb = {n: arm.data.bones["hand_" + n] for n in "rl"}
    tab = {}
    for v in hands.data.vertices:
        n = min("rl", key=lambda n: seg_dist(v.co, hb[n].head_local, hb[n].tail_local))
        tab[v.index] = {"hand_" + n: 1.0}
    set_weights(hands, tab)
    rigid(parts["horse_eyes"], "head_h")
    rigid(parts["tack"], "horse_body")
    # the bridle as the horse under it, handed over to the fist along the reins' last 30 cm
    br = parts["bridle"]
    mc.copy_weights(br, horse)
    hr = arm.data.bones["hand_r"].head_local
    idx = {g.index: g.name for g in br.vertex_groups}
    tab = {}
    for v in br.data.vertices:
        ws = {idx[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
        f = max(0.0, min(1.0, (0.30 - (v.co - hr).length) / 0.20))
        if f > 0:
            ws = {b: w * (1 - f) for b, w in ws.items()}
            ws["hand_r"] = ws.get("hand_r", 0.0) + f
        tab[v.index] = ws or {"head_h": 1.0}
    set_weights(br, tab)
    by_distance(parts["horse_hair"], arm, ("horse_body", "neck_1", "neck_2", "head_h", "tail_1", "tail_2", "tail_3"))
    # props by loose part: hat and feather to the head, the staff (pole, bucket, finial) to
    # the pole, the flag along its fly, the case to its bone, the strap between case and hips
    butt, top, d = [np.asarray(x, float) for x in pole]
    d = d / np.linalg.norm(d)
    fly = pennon_frame(butt, top, d)
    hoist = top - d * 0.22
    hd = arm.data.bones["head"]

    def along_flag(co):
        """Hoist edge on the pole, the middle on pennon_1, the fly's end on pennon_2."""
        u = max(0.0, float((np.asarray(co) - hoist) @ fly)) / PENNON_FLY
        if u < 0.35:
            t = u / 0.35
            return {"pole": 1 - t, "pennon_1": t}
        if u < 0.8:
            t = (u - 0.35) / 0.45
            return {"pennon_1": 1 - t, "pennon_2": t}
        return {"pennon_2": 1.0}

    def radial(co):
        r = np.asarray(co) - butt
        return float(np.linalg.norm(r - d * (r @ d)))

    pr = parts["props"]
    bm = bmesh.new(); bm.from_mesh(pr.data)
    loose = cs.loose_parts(bm)
    bm.free()
    co = [v.co.copy() for v in pr.data.vertices]
    tab = {}
    kinds = {}
    for comp in loose:
        c = sum((co[i] for i in comp), Vector()) / len(comp)
        rmax = max(radial(co[i]) for i in comp)
        if seg_dist(c, hd.head_local, hd.tail_local) < 0.30 and c.z > hd.head_local.z - 0.08:
            kind = "head"
        elif rmax < 0.07:
            kind = "pole"
        elif c.z > 2.3:
            kind = "flag"
        elif (c - _v(case_c)).length < 0.20:
            kind = "case"
        else:
            kind = "strap"
        kinds[kind] = kinds.get(kind, 0) + 1
        for i in comp:
            if kind == "flag":
                tab[i] = along_flag(co[i])
            elif kind == "strap":
                cb, hb_ = arm.data.bones["case"], arm.data.bones["hips"]
                dc = seg_dist(co[i], cb.head_local, cb.tail_local)
                dh = seg_dist(co[i], hb_.head_local, hb_.tail_local)
                tab[i] = {"case": 1.0 / (dc + 1e-3) ** 3, "hips": 1.0 / (dh + 1e-3) ** 3}
            else:
                tab[i] = {kind: 1.0}
    set_weights(pr, tab)
    print("PROPS loose parts", kinds)
    if "props_crowns" in parts:
        cr = parts["props_crowns"]
        set_weights(cr, {v.index: along_flag(v.co) for v in cr.data.vertices})
    return how


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
            "tail_1": {"rot": [("x", -32.0 + 4.0 * s(0.1)), ("y", 5.0 * s(0.3))]},
            "tail_2": {"rot": [("x", -14.0 + 5.0 * s(0.2)), ("y", 7.0 * s(0.4))]},
            "tail_3": {"rot": [("x", -8.0 + 6.0 * s(0.3)), ("y", 9.0 * s(0.5))]},
            # the rider up in the irons, pitched ~15 deg forward, rocking against the horse
            "hips": {"loc": (0, 0.035, 0.06 + 0.012 * s(0.60))},
            "spine": {"rot": [("x", -8.0 - 2.5 * s(0.10))]},
            "chest": {"rot": [("x", -9.0 - 1.5 * s(0.15))]},
            "neck": {"rot": [("x", 5.0)]},
            "head": {"rot": [("x", 11.0 + 2.0 * s(0.15))]},
            "upperarm_r": {"rot": [("x", 5.0 * s(0.30))]},
            "forearm_r": {"rot": [("x", 4.0 * s(0.35))]},
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
            pose["hind_upper_" + n] = {"rot": [("x", a * 25.0)]}
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
    pb = arm.pose.bones["forearm_l"]
    if on:
        c = pb.constraints.new("IK")
        c.name = "ik"
        c.target, c.subtarget = arm, "ik_hand_l"
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
    mu.apply_pose(arm, {})
    bpy.context.view_layer.update()
    hoof = lambda leg: arm.matrix_world @ arm.pose.bones[leg[0] + "_hoof_" + leg[1]].tail
    rest = {leg: hoof(leg).z for leg in FOOTFALL}
    pivot = arm.pose.bones["horse_body"].head.y
    reach = sum(hoof(leg).y for leg in FOOTFALL if leg[0] == "fore") / 2 - pivot
    frames = list(range(1, GALLOP_FRAMES + 1))
    poses, lift = {}, {"hind": {}, "fore": {}}
    for f in frames:
        u = (f - 1) / GALLOP_FRAMES
        pose = gallop_pose(u)
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
    fk_i = mu.make_action(arm, NAME + "_IDLE_fk", zero(keys(idle_pose, IDLE_FRAMES, 2)))
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
