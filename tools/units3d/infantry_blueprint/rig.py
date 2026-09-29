"""RIG the blueprint man-at-arms (owner 2026-09-28: 我还要一个行进的动作).
Every generated piece (mirror applied) is copied into the collection
`Infantry` as one full mesh, skinned to `inf_rig`: a plate is RIGID on the
bone of its part, a plate across a joint (couter, poleyn) is shared between
the two bones by where each vertex lies, and the body underneath is weighted
to its two nearest bones by distance. The generated sources stay (hidden) in
`Armour` / base_body, so the model can still be rebuilt and re-rigged.
    exec(open(".../rig.py").read(), {})
"""
import bpy, math
from mathutils import Vector, Matrix

HERE = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
BASE = {"BUILD": False}
exec(open(HERE + "base_mesh.py").read(), BASE)
S, EL, W = BASE["S"], BASE["EL"], BASE["W"]
D2 = (W - EL).normalized()
HIP = Vector((0.100, -0.010, 0.900))
KNEE = Vector((0.124, -0.020, 0.480))
ANKLE = Vector((0.132, 0.000, 0.120))
TOE = Vector((0.135, -0.170, 0.030))


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def mx(v):
    return Vector((-v.x, v.y, v.z))


def bone_table():
    B = [("hips", None, Vector((0, -0.01, 0.90)), Vector((0, -0.01, 1.00))),
         ("spine", "hips", Vector((0, -0.01, 1.00)), Vector((0, -0.01, 1.18))),
         ("chest", "spine", Vector((0, -0.01, 1.18)), Vector((0, -0.01, 1.46))),
         ("neck", "chest", Vector((0, -0.01, 1.46)), Vector((0, -0.01, 1.56))),
         ("head", "neck", Vector((0, -0.01, 1.56)), Vector((0, -0.01, 1.80)))]
    for sd, f in (("L", lambda v: v), ("R", mx)):
        B += [("clavicle." + sd, "chest", f(Vector((0.03, 0.0, 1.44))), f(S)),
              ("upperarm." + sd, "clavicle." + sd, f(S), f(EL)),
              ("forearm." + sd, "upperarm." + sd, f(EL), f(W)),
              ("hand." + sd, "forearm." + sd, f(W), f(W + D2 * 0.17)),
              ("thigh." + sd, "hips", f(HIP), f(KNEE)),
              ("shin." + sd, "thigh." + sd, f(KNEE), f(ANKLE)),
              ("foot." + sd, "shin." + sd, f(ANKLE), f(TOE))]
    # the spear rides its own bone under the right hand, so it can slide in the fist
    g = mx(W + D2 * 0.058)
    B.append(("spear", "hand.R", g, g + Vector((0, -0.3, 0))))
    # the cloak: three chains of three down its back, so it can stream and swing (owner 2026-09-29: 走路的时候披风要飘动)
    J = cloak_joints()
    for side, joints in (J or {}).items():
        parent = "chest"
        for k in range(len(joints) - 1):
            nm = "cloak.%s.%d" % (side, k + 1)
            B.append((nm, parent, joints[k], joints[k + 1]))
            parent = nm
    return B


CLOAK_X = {"C": 0.0, "L": 0.13, "R": -0.13}
CLOAK_Z = (1.44, 1.13, 0.84, 0.545)
_CJ = {}


def cloak_joints():
    """Each chain's joints just inside the cloak's back, read off the built cloak (mirror applied)."""
    if "j" in _CJ:
        return _CJ["j"]
    ob = bpy.data.objects.get("cloak")
    if not ob:
        return None
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    vs = [ob.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    out = {}
    for side, x in CLOAK_X.items():
        js = []
        for z in CLOAK_Z:
            near = [v for v in vs if abs(v.x - x) < 0.05 and abs(v.z - z) < 0.05] or \
                sorted(vs, key=lambda v: (v.x - x) ** 2 + (v.z - z) ** 2)[:6]
            js.append(Vector((x, max(v.y for v in near) - 0.012, z)))
        out[side] = js
    _CJ["j"] = out
    return out


def cloak_weights(co, sd):
    """The collar on the chest (the shoulders a little on the arms, which swing under it);
    below it the three chains, shared across by x and along by the joints."""
    z = co.z
    w_arm = 0.35 * sstep(0.10, 0.19, abs(co.x)) * sstep(1.22, 1.32, z) * sstep(1.47, 1.40, z)
    top = sstep(1.38, 1.46, z)
    ws = {"chest": top * (1 - w_arm), "upperarm." + sd: top * w_arm}
    a = abs(co.x) / CLOAK_X["L"]
    lat = {"C": max(0.0, 1 - a), sd: min(1.0, a)}
    u = (CLOAK_Z[0] - z) / (CLOAK_Z[0] - CLOAK_Z[-1]) * 3.0
    u = min(max(u, 0.5), 2.5)
    along = {k: max(0.0, 1 - abs(u - (k - 0.5))) for k in (1, 2, 3)}
    tot = sum(along.values())
    for side, wl in lat.items():
        for k, wk in along.items():
            if wl * wk > 0:
                nm = "cloak.%s.%d" % (side, k)
                ws[nm] = ws.get(nm, 0.0) + (1 - top) * wl * wk / tot
    return ws


def build_rig():
    old = bpy.data.objects.get("inf_rig")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    arm = bpy.data.armatures.new("inf_rig")
    ob = bpy.data.objects.new("inf_rig", arm)
    coll().objects.link(ob)
    arm.display_type = "STICK"
    ob.show_in_front = True
    bpy.context.view_layer.objects.active = ob
    wins = bpy.context.window_manager.windows
    ov = dict(window=wins[0], screen=wins[0].screen) if len(wins) else {}     # headless: no window
    with bpy.context.temp_override(active_object=ob, object=ob, **ov):
        bpy.ops.object.mode_set(mode="EDIT")
        eb = {}
        for name, parent, h, t in bone_table():
            b = arm.edit_bones.new(name)
            b.head, b.tail = h, t
            b.roll = 0.0
            if parent:
                b.parent = eb[parent]
                b.use_connect = (eb[parent].tail - h).length < 1e-4
            eb[name] = b
        bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def coll():
    c = bpy.data.collections.get("Infantry")
    if not c:
        c = bpy.data.collections.new("Infantry")
        bpy.context.scene.collection.children.link(c)
    return c


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def body_weights(co):
    sd = "L" if co.x >= 0 else "R"
    cands = [(n, h, t) for n, _, h, t in bone_table() if (n.endswith("." + sd) or "." not in n) and n != "spear"]
    ds = sorted(((seg_dist(co, h, t), n) for n, h, t in cands))[:2]
    ws = {n: 1.0 / (d ** 4 + 1e-7) for d, n in ds}
    tot = sum(ws.values())
    return {n: w / tot for n, w in ws.items()}


def plate_weights(name, co):
    """Which bone(s) a plate's vertex rides."""
    sd = "L" if co.x >= 0 else "R"
    z = co.z
    if name.startswith("rivets_"):
        return plate_weights(name[len("rivets_"):], co)
    if name in ("belt", "belt_buckle"):
        w = sstep(1.07, 1.00, z)
        return {"hips": 0.7, "spine": 0.3}
    if name == "neck_rope":
        return {"chest": 1.0}
    if name == "mail_skirt":
        w = 0.8 * sstep(0.95, 0.70, z) * sstep(0.0, 0.05, abs(co.x)) * (1 - 0.7 * sstep(0.02, 0.10, co.y))   # its back stays under the cloak
        return {"hips": 1 - w, "thigh." + sd: w}
    if name == "spear":
        return {"spear": 1.0}
    if name == "shield":
        return {"forearm.L": 1.0}
    if name == "cloak":
        return cloak_weights(co, sd)
    if name.startswith("knee_strap_"):
        return plate_weights("poleyn", co)
    if name in ("helmet", "visor", "bevor", "visor_pivot", "visor_breaths"):
        return {"head": 1.0}
    if name == "gorget_0":
        return {"neck": 1.0}
    if name == "gorget_1":
        return {"chest": 0.6, "neck": 0.4}
    if name in ("breastplate", "backplate", "plackart"):
        w = sstep(1.08, 1.26, z)
        return {"chest": w, "spine": 1 - w}
    if name.startswith("fauld_"):
        k = int(name[-1])
        if k == 0:
            w = sstep(1.07, 1.00, z)
            return {"hips": w, "spine": 1 - w}
        wt = {1: 0.0, 2: 0.06, 3: 0.14, 4: 0.22}[k] * sstep(0.03, 0.09, abs(co.x)) * sstep(0.10, 0.0, co.y)
        return {"hips": 1 - wt, "thigh." + sd: wt}
    if name.startswith("tasset_"):
        wt = 0.40 if name.endswith("0") else 0.55
        return {"hips": 1 - wt, "thigh." + sd: wt}
    if name == "pauldron":
        w = sstep(1.37, 1.27, z)
        return {"clavicle." + sd: 1 - w, "upperarm." + sd: w}
    if name == "besagew":
        return {"clavicle." + sd: 1.0}
    if name.startswith("pauldron_lame") or name == "rerebrace":
        return {"upperarm." + sd: 1.0}
    if name in ("couter", "couter_wing"):
        el = EL if sd == "L" else mx(EL)
        d = ((S - EL).normalized() * -1 + D2).normalized()
        if sd == "R":
            d = mx(d)
        w = sstep(-0.035, 0.035, (co - el).dot(d))
        if name == "couter_wing":
            w = 0.5
        return {"upperarm." + sd: 1 - w, "forearm." + sd: w}
    if name.startswith("vambrace"):
        return {"forearm." + sd: 1.0}
    if name == "gauntlet":
        w0 = W if sd == "L" else mx(W)
        d = D2 if sd == "L" else mx(D2)
        w = sstep(-0.03, 0.02, (co - w0).dot(d))
        return {"forearm." + sd: 1 - w, "hand." + sd: w}
    if name == "cuisse":
        return {"thigh." + sd: 1.0}
    if name in ("poleyn", "poleyn_wing"):
        w = sstep(0.515, 0.445, z)
        return {"thigh." + sd: 1 - w, "shin." + sd: w}
    if name == "greave":
        return {"shin." + sd: 1.0}
    if name == "sabaton":
        w = 0.5 * sstep(0.11, 0.16, z)
        return {"foot." + sd: 1 - w, "shin." + sd: w}
    return None


def skin_copies(rig):
    for o in list(coll().objects):
        if o.type == "MESH":
            me = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.meshes.remove(me)
    base = bpy.data.objects["base_body"]
    base.modifiers["Subdivision"].levels = 0            # the game mesh is the low one
    dg = bpy.context.evaluated_depsgraph_get()
    srcs = [base] + list(bpy.data.collections["Armour"].objects)
    total = 0
    for src in srcs:
        me = bpy.data.meshes.new_from_object(src.evaluated_get(dg))
        me.name = "inf_" + src.name
        ob = bpy.data.objects.new("inf_" + src.name, me)
        coll().objects.link(ob)
        groups = {}
        for v in me.vertices:
            ws = body_weights(v.co) if src is base else plate_weights(src.name, v.co)
            for bn, w in ws.items():
                if w <= 1e-4:
                    continue
                g = groups.get(bn) or ob.vertex_groups.new(name=bn)
                groups[bn] = g
                g.add([v.index], w, "REPLACE")
        m = ob.modifiers.new("Armature", "ARMATURE")
        m.object = rig
        ob.parent = rig
        total += sum(len(p.vertices) - 2 for p in me.polygons)
    for o in [base] + list(bpy.data.collections["Armour"].objects):
        o.hide_set(True)
    print("skinned %d pieces, %d tris" % (len(srcs), total))


rig = build_rig()
skin_copies(rig)
