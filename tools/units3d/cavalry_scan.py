"""The cavalry piece from two CC0 museum scans (owner 2026-09-25, route A:
"CC0 素材改造", keep design "Z-Image C"; the lofted model_cavalry.py was
ruled "太丑太简陋"; and "最终要适合在游戏里使用，太高的多边形面也没意义").

  # inside the owner's running Blender (Blender MCP), scene `cavalry_c`:
  exec(open(".../tools/units3d/cavalry_scan.py").read(), {"__name__": "live"})
  # or headless:
  blender -b --factory-startup --python tools/units3d/cavalry_scan.py

Sources, both CC0-1.0 (credit not required), downloaded from Sketchfab into
assets/units3d/ai_src/cc0/ (git-ignored, .gdignore'd):
  * cleveland_armor/ — Cleveland Museum of Art 1964.88 "Armor for Man and
    Horse": the KNIGHT and his hands are taken from it (the scan is 123
    loose shells; RIDER_PARTS are the rider's, found by position and checked
    by eye). Its barded horse, saddle and lance are NOT used.
  * hunt_horse/ — The Hunt Museum "Horse Outside": a painted statue of a
    standing horse; its SHAPE is used (the paint is not), the grass slab is
    cut off, it is turned to face +Y and scaled to 2.45 m nose to tail.

Then design C is put on it: a dark charcoal dappled coat with black points,
mane and tail and a white star (painted procedurally, baked), a brown war
saddle, a dark green saddle cloth over the hindquarters with a brass border,
a breast strap with a brass boss, a bridle and reins, a green heater shield
with a white pale on his left arm and a lance in his right hand — the tack
laid on the horse by ray casts against its own surface.

Game budget: the horse is collapsed to HORSE_TRIS, the knight to RIDER_TRIS;
their scan detail survives as a baked tangent normal map. ONE material over
a 2048 atlas (albedo, normal, metallic-roughness): the horse's half, the
knight's half, and 512 px tiles for the tack. The rig, the three actions,
and the export are model_cavalry.py's, bone for bone. No base (owner
2026-09-27: 撤除所有底座): the hooves stand on z = 0, on the map itself.
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = "/Users/samuelzhang/game_design/tools/units3d"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import importlib
import model_cavalry as mc
importlib.reload(mc)
from unit_common import OUT, log, tri_count

SRC = "/Users/samuelzhang/game_design/assets/units3d/ai_src/cc0/"
NAME = mc.NAME
HORSE_TRIS = 7000
RIDER_TRIS = 5600
HORSE_LENGTH = 2.60        # nose to tail; the knight was fitted on this size
ATLAS = 2048
BAKE_MARGIN = 6
# Cleveland shells that are the rider (index = order of loose parts as the
# glTF imports; its horse, barding, saddle, stirrups and lance are left out).
RIDER_PARTS = {8, 9, 12, 16, 24, 28, 40, 41, 43, 52, 54, 57, 59, 60, 61, 62, 65, 66, 67, 68,
               71, 72, 73, 79, 80, 81, 82, 83, 90, 91, 92, 93, 94, 97, 98, 99, 100, 104, 106}
RIDER_SHIFT = Vector((0.0, 0.10, 0.10))     # Cleveland's seat onto this horse's back
# The atlas: (u0, v0, du, dv) in 512 px cells.
TILES = {"horse": (0, 0, 2, 2), "rider": (2, 0, 2, 2),
         "leather": (0, 2, 1, 1), "cloth": (1, 2, 1, 1), "brass": (2, 2, 1, 1), "wood": (3, 2, 1, 1),
         "steel": (0, 3, 1, 1), "shield": (1, 3, 1, 1)}
mc.TILES.update(TILES)
# model_cavalry.paint_atlas also paints its coat, hair and hoof: park them on
# cells this atlas never copies, or they overwrite the brass and the wood.
mc.TILES.update({"coat": (2, 0, 2, 2), "hair": (2, 3, 1, 1), "hoof": (3, 3, 1, 1)})


# ------------------------------------------------------------ sources ----

def import_gltf(path):
    sc = bpy.context.scene
    before = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in sc.objects if o not in before]


def world_bmesh(objs):
    bm = bmesh.new()
    for o in objs:
        if o.type != "MESH":
            continue
        t = bmesh.new()
        t.from_mesh(o.data)
        t.transform(o.matrix_world)
        me = bpy.data.meshes.new("cav_tmp")
        t.to_mesh(me)
        t.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    return bm


def loose_parts(bm):
    bm.verts.ensure_lookup_table()
    seen, parts = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x.index)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        parts.append(comp)
    return parts


def principal_yaw(pts):
    mx = sum(p.x for p in pts) / len(pts)
    my = sum(p.y for p in pts) / len(pts)
    cxx = sum((p.x - mx) ** 2 for p in pts)
    cyy = sum((p.y - my) ** 2 for p in pts)
    cxy = sum((p.x - mx) * (p.y - my) for p in pts)
    a = 0.5 * math.atan2(2 * cxy, cxx - cyy)
    return Vector((math.cos(a), math.sin(a), 0.0)), Vector((mx, my, 0.0))


def hoof_centre(bm):
    """The middle of the four hooves, which is where the piece stands."""
    low = [v.co.xy.copy() for v in bm.verts if v.co.z < 0.08]
    groups = []
    for c in low:
        for g in groups:
            if (g[0] / g[1] - c).length < 0.18:
                g[0] += c
                g[1] += 1
                break
        else:
            groups.append([c.copy(), 1])
    hooves = [g[0] / g[1] for g in groups if g[1] > 20]
    ys = [h.y for h in hooves]
    return (min(ys) + max(ys)) / 2.0, hooves


def horse_source():
    objs = import_gltf(SRC + "hunt_horse/scene.gltf")
    bm = world_bmesh(objs)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    # The export comes in three chunks whose seams share positions but not
    # vertices: weld them, or "keep the biggest piece" drops half the horse.
    z0 = min(v.co.z for v in bm.verts)
    hz = max(v.co.z for v in bm.verts) - z0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00042 * hz)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z0 + 0.0624 * hz],
                     context="VERTS")                      # the grass slab: its top is 6.2% up
    parts = loose_parts(bm)
    big = max(len(p) for p in parts)
    keep = {i for p in parts if len(p) > 0.02 * big for i in p}
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
    # stand it up: hooves on z = 0, the barrel's long axis on Y, the head at +Y, 2.45 m long
    zmin = min(v.co.z for v in bm.verts)
    bm.transform(Matrix.Translation((0, 0, -zmin)))
    h = max(v.co.z for v in bm.verts)
    body = [v.co for v in bm.verts if 0.44 * h < v.co.z < 0.72 * h]      # the barrel
    d, m = principal_yaw(body)
    top = max(bm.verts, key=lambda v: v.co.z).co
    if (top - m).dot(d) < 0:
        d = -d
    bm.transform(Matrix.Rotation(math.pi / 2 - math.atan2(d.y, d.x), 4, "Z") @ Matrix.Translation(-m))
    length = max(v.co.y for v in bm.verts) - min(v.co.y for v in bm.verts)
    bm.transform(Matrix.Scale(HORSE_LENGTH / length, 4))
    mid, _ = hoof_centre(bm)
    barrel = [v.co.x for v in bm.verts if 0.95 < v.co.z < 1.5]
    bm.transform(Matrix.Translation((-sum(barrel) / len(barrel), -mid, 0)))
    me = bpy.data.meshes.new("cav_horse_high")
    bm.to_mesh(me)
    bm.free()
    for layer in list(me.uv_layers):
        me.uv_layers.remove(layer)
    return mc.link(bpy.data.objects.new("cav_horse_high", me))


def rider_source():
    objs = import_gltf(SRC + "cleveland_armor/scene.gltf")
    scan = max((o for o in objs if o.type == "MESH"), key=lambda o: len(o.data.polygons))
    mat = scan.data.materials[0]
    bm = bmesh.new()
    bm.from_mesh(scan.data)
    bm.transform(scan.matrix_world)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    parts = loose_parts(bm)
    ground = min(v.co.z for v in bm.verts)
    bm.verts.ensure_lookup_table()
    # its own horse's four legs set the frame: the shells that reach the floor
    legs = []
    for p in parts:
        zs = [bm.verts[i].co.z for i in p]
        if min(zs) < ground + 0.02 and len(p) > 1500:
            legs.append(sum((bm.verts[i].co for i in p), Vector()) / len(p))
    d, m = principal_yaw(legs)
    heads = [bm.verts[i].co for p in parts for i in p
             if ground + 1.3 < bm.verts[i].co.z < ground + 1.9 and (bm.verts[i].co - m).xy.dot(d.xy) > 0.5]
    if len(heads) < 50:
        d = -d
    frame = Matrix.Translation(RIDER_SHIFT) @ Matrix.Rotation(math.pi / 2 - math.atan2(d.y, d.x), 4, "Z") \
        @ Matrix.Translation((-m.x, -m.y, -ground))
    keep = {i for k, p in enumerate(parts) if k in RIDER_PARTS for i in p}
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
    bm.transform(frame)
    me = bpy.data.meshes.new("cav_rider_high")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return mc.link(bpy.data.objects.new("cav_rider_high", me))


# ------------------------------------------------------------- probing ----

class Surface:
    """Ray casts against the horse, for laying tack on it."""

    def __init__(self, ob):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        self.tree = BVHTree.FromBMesh(bm)
        self.co = [v.co.copy() for v in bm.verts]
        bm.free()

    def hit(self, origin, target):
        d = (target - origin)
        loc, nor, _, _ = self.tree.ray_cast(origin, d.normalized(), d.length)
        return (loc, nor) if loc is not None else (None, None)

    def top(self, y, half=0.05):
        zs = [c.z for c in self.co if abs(c.x) < half and abs(c.y - y) < 0.03]
        return max(zs) if zs else None

    def side(self, y, z):
        loc, _ = self.hit(Vector((2.0, y, z)), Vector((0, y, z)))
        return loc.x if loc is not None else None


# ------------------------------------------------------------ the rig ----

def leg_chain(surf, hoof, levels):
    """Centroids of one leg's slices, walking up from its hoof."""
    at = Vector((hoof.x, hoof.y))
    out = [Vector((hoof.x, hoof.y, 0.02))]
    for z in levels:
        sl = [c for c in surf.co if abs(c.z - z) < 0.015 and (c.xy - at).length < 0.13]
        if sl:
            at = sum((c.xy for c in sl), Vector((0, 0))) / len(sl)
        out.append(Vector((at.x, at.y, z)))
    return out


def rig_spec(surf):
    _, hooves = hoof_centre_from(surf)
    fore = sorted([h for h in hooves if h.y > 0], key=lambda h: h.x)
    hind = sorted([h for h in hooves if h.y < 0], key=lambda h: h.x)
    b = [("root", None, Vector((0, 0, 0)), Vector((0, 0.3, 0)))]
    back_rear, back_front = surf.top(-0.55), surf.top(0.45)
    b.append(("horse_body", "root", Vector((0, -0.55, back_rear - 0.30)), Vector((0, 0.45, back_front - 0.30))))
    ys = [c.y for c in surf.co]
    nose = max(surf.co, key=lambda c: c.y)
    poll = max((c for c in surf.co if c.y > nose.y - 0.55), key=lambda c: c.z)
    wither = Vector((0, 0.50, surf.top(0.50) - 0.22))
    mid = (wither + Vector((0, poll.y - 0.08, poll.z - 0.12))) / 2 + Vector((0, 0.03, 0.05))
    b += [("neck_1", "horse_body", wither, mid),
          ("neck_2", "neck_1", mid, Vector((0, poll.y - 0.08, poll.z - 0.12))),
          ("head_h", "neck_2", Vector((0, poll.y - 0.08, poll.z - 0.12)), Vector((0, nose.y - 0.08, nose.z)))]
    rear = min(ys)
    tail_top = Vector((0, rear + 0.10, surf.top(rear + 0.10) - 0.04))
    tail = [c for c in surf.co if c.y < rear + 0.18 and abs(c.x) < 0.12]
    tail_low = min(tail, key=lambda c: c.z)
    t1 = tail_top.lerp(tail_low, 0.33) + Vector((0, -0.05, 0))
    t2 = tail_top.lerp(tail_low, 0.66) + Vector((0, -0.04, 0))
    b += [("tail_1", "horse_body", tail_top, t1), ("tail_2", "tail_1", t1, t2),
          ("tail_3", "tail_2", t2, Vector((tail_low.x * 0, tail_low.y, tail_low.z)))]
    for n, h in (("l", fore[0]), ("r", fore[-1])):
        c = leg_chain(surf, h, (0.22, 0.56, 0.85))
        top = Vector((c[3].x, c[3].y - 0.04, 1.22))
        b += [("fore_upper_" + n, "horse_body", top, c[2]),
              ("fore_lower_" + n, "fore_upper_" + n, c[2], c[1]),
              ("fore_hoof_" + n, "fore_lower_" + n, c[1], c[0])]
    for n, h in (("l", hind[0]), ("r", hind[-1])):
        c = leg_chain(surf, h, (0.22, 0.52, 0.88))
        top = Vector((c[3].x, c[3].y - 0.10, 1.28))
        b += [("hind_upper_" + n, "horse_body", top, c[3]),
              ("hind_gaskin_" + n, "hind_upper_" + n, c[3], c[2]),
              ("hind_lower_" + n, "hind_gaskin_" + n, c[2], c[1]),
              ("hind_hoof_" + n, "hind_lower_" + n, c[1], c[0])]
    s = RIDER_SHIFT
    P = lambda x, y, z: Vector((x, y, z)) + s          # Cleveland's own seat frame
    b += [("hips", "horse_body", P(0, 0.02, 1.58), P(0, 0.0, 1.82)),
          ("spine", "hips", P(0, 0.0, 1.82), P(0, 0.0, 2.00)),
          ("chest", "spine", P(0, 0.0, 2.00), P(0, 0.02, 2.22)),
          ("neck", "chest", P(0, 0.02, 2.22), P(0, 0.08, 2.30)),
          ("head", "neck", P(0, 0.08, 2.30), P(0, 0.10, 2.52))]
    for n, sx in (("r", 1.0), ("l", -1.0)):
        sh = P(sx * 0.20, 0.0, 2.12)
        el = P(sx * (0.26 if n == "r" else 0.30), 0.12, 1.86)
        ha = grip_point() if n == "r" else P(-0.24, 0.33, 1.75)
        hip = P(sx * 0.10, 0.02, 1.60)
        kn = P(sx * 0.30, 0.30, 1.42)
        an = P(sx * 0.36, 0.22, 1.02)
        to = P(sx * 0.40, 0.50, 0.93)
        b += [("clavicle_" + n, "chest", P(sx * 0.03, 0.0, 2.15), sh),
              ("upperarm_" + n, "clavicle_" + n, sh, el),
              ("forearm_" + n, "upperarm_" + n, el, ha),
              ("hand_" + n, "forearm_" + n, ha, ha + (ha - el).normalized() * 0.08),
              ("thigh_" + n, "hips", hip, kn), ("shin_" + n, "thigh_" + n, kn, an),
              ("foot_" + n, "shin_" + n, an, to)]
    grip = grip_point()
    b += [("lance", "hand_r", grip, grip + (LANCE_TIP - LANCE_BUTT).normalized() * 0.3),
          ("shield", "forearm_l", SHIELD_C - Vector((0, 0, 0.1)), SHIELD_C + Vector((0, 0, 0.1)))]
    return b


def hoof_centre_from(surf):
    class _BM:
        pass
    groups = []
    for c in (c.xy for c in surf.co if c.z < 0.08):
        for g in groups:
            if (g[0] / g[1] - c).length < 0.18:
                g[0] += c
                g[1] += 1
                break
        else:
            groups.append([c.copy(), 1])
    hooves = [g[0] / g[1] for g in groups if g[1] > 20]
    return 0.0, hooves


def build_rig(spec):
    arm_data = bpy.data.armatures.new(NAME + "_rig")
    arm = mc.link(bpy.data.objects.new(NAME + "_rig", arm_data))
    mc.activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, parent, head, tail in spec:
        e = arm_data.edit_bones.new(name)
        e.head, e.tail, e.roll = head, tail, 0.0
        if parent:
            e.parent = made[parent]
            e.use_connect = (made[parent].tail - e.head).length < 1e-6
        made[name] = e
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# -------------------------------------------------------------- tack ----
# Set from the knight: the lance's butt rests by his right stirrup, his right
# hand grips it; the shield hangs on his left forearm.
LANCE_BUTT = Vector((0.28, 0.44, 0.93)) + RIDER_SHIFT
LANCE_TIP = LANCE_BUTT + Vector((-0.057, 0.079, 0.995)).normalized() * 2.30
SHIELD_C = Vector((-0.40, 0.23, 1.80)) + RIDER_SHIFT   # outboard of the left forearm's middle
RIGHT_HAND_Z = 1.86 + RIDER_SHIFT.z


def grip_point():
    """Where his right fist closes on the lance: the axis at the fist's height."""
    d = (LANCE_TIP - LANCE_BUTT).normalized()
    return LANCE_BUTT + d * ((RIGHT_HAND_Z - LANCE_BUTT.z) / d.z)


def tack(surf):
    out = []
    # saddle: a padded seat following the back, cantle and pommel
    ys = [-0.20, -0.10, 0.0, 0.10, 0.20, 0.30, 0.38]
    seat = [Vector((0, y, surf.top(y) + 0.035)) for y in ys]
    s = mc.loft("seat", seat, [(0.21, 0.05)] * len(seat), segs=14, part="leather")
    out.append(s)
    t0, t1 = seat[0], seat[-1]
    out.append(mc.loft("cantle", [t0 + Vector((-0.15, 0.0, 0.02)), t0 + Vector((0, -0.025, 0.14)), t0 + Vector((0.15, 0.0, 0.02))],
                       [(0.025, 0.045), (0.025, 0.055), (0.025, 0.045)], segs=8, side=Vector((0, 1, 0)), part="leather"))
    out.append(mc.loft("pommel", [t1 + Vector((-0.13, 0, 0.01)), t1 + Vector((0, 0.025, 0.12)), t1 + Vector((0.13, 0, 0.01))],
                       [(0.025, 0.04), (0.025, 0.05), (0.025, 0.04)], segs=8, side=Vector((0, 1, 0)), part="leather"))
    for p in out:
        p["bone"] = "horse_body"

    # the saddle cloth: rings round the hindquarters cast onto the coat,
    # standing proud of it, hanging plumb below the widest line
    rows = []
    y = 0.10
    while y > -0.84:
        zc = surf.top(y) - 0.30
        arc = []
        for k in range(23):                       # from the near side over the top to the far
            th = math.radians(180 - 180 * k / 22)
            loc, nor = surf.hit(Vector((0, y, zc)) + Vector((math.cos(th), 0, math.sin(th))) * 1.5, Vector((0, y, zc)))
            if loc is not None:
                arc.append(loc + nor * 0.03)
        lo = arc.index(min(arc, key=lambda p: p.x))
        hi = arc.index(max(arc, key=lambda p: p.x))
        arc = arc[lo:hi + 1]
        hem = 1.02 + max(0.0, -0.40 - y) * 0.35
        drop = lambda p: [Vector((p.x, y, z)) for z in _steps(p.z, hem)]
        ring = list(reversed(drop(arc[0]))) + arc + drop(arc[-1])
        rows.append(_resample(ring, 31))
        y -= 0.045
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = [[bm.verts.new(p) for p in r] for r in rows]
    W = len(grid[0])
    for i in range(len(grid) - 1):
        for j in range(W - 1):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            for loop, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uvl].uv = (b / (W - 1), a / (len(grid) - 1))
    edges = [[g[0].co.copy() for g in grid], [g[-1].co.copy() for g in grid],
             [v.co.copy() for v in grid[0]], [v.co.copy() for v in grid[-1]]]
    cloth = mc.to_object(bm, "cloth", "cloth")
    mc.solid(cloth, 0.012)
    out.append(cloth)
    for k, pts in enumerate(edges):
        out.append(mc.loft("border_%d" % k, pts, [(0.016, 0.016)] * len(pts), segs=6, part="brass"))

    # the breast strap, round the chest at the point of the shoulder
    zb = 1.22
    front = surf.hit(Vector((0, 3.0, zb)), Vector((0, 0, zb)))[0]
    strap = []
    for sgn in (-1, 1):
        side = []
        for yy in (0.30, 0.45, 0.58, front.y - 0.10):
            loc, nor = surf.hit(Vector((sgn * 2.0, yy, zb)), Vector((0, yy, zb)))
            if loc is None:
                continue
            p = loc + nor * 0.015
            side.append(p + Vector((0, 0, 0.08 if yy == 0.30 else 0.0)))
        strap += side if sgn > 0 else list(reversed(side))
    strap.insert(len(strap) // 2, front + Vector((0, 0.015, 0)))
    out.append(mc.loft("breast", strap, [(0.012, 0.03)] * len(strap), segs=6, side=Vector((0, 0, 1)), part="leather"))
    out.append(mc.sphere("boss", front + Vector((0, 0.03, 0)), (0.045, 0.02, 0.045), "brass", segs=12, rings=6))

    # the bridle: loops round the head, cast onto it
    nose = max(surf.co, key=lambda c: c.y)
    poll = max((c for c in surf.co if c.y > nose.y - 0.55), key=lambda c: c.z)
    axis = (nose - poll).normalized()
    side = Vector((1, 0, 0))
    up = side.cross(axis)

    def loop_at(t, grow, name):
        """A strap round the head: the head's own cross-section there (its
        convex hull in the plane across the head), grown by `grow`."""
        ctr = poll.lerp(nose, t)
        near = [c for c in surf.co if abs((c - ctr).dot(axis)) < 0.012 and (c - ctr).length < 0.22
                and c.z < poll.z - 0.04]                         # not the ears
        pts2 = sorted({(round((c - ctr).dot(side), 4), round((c - ctr).dot(up), 4)) for c in near})
        hull = _hull(pts2)
        cx = sum(p[0] for p in hull) / len(hull)
        cy = sum(p[1] for p in hull) / len(hull)
        ring = []
        for x, y in hull:
            d = Vector((x - cx, y - cy))
            d = d * ((d.length + grow) / max(d.length, 1e-6))
            ring.append(ctr + side * (cx + d.x) + up * (cy + d.y))
        ring = _resample(ring + ring[:1], 15)
        return mc.loft(name, ring, [(0.008, 0.013)] * len(ring), segs=5, caps=(False, False), part="leather"), ring
    nb, npts = loop_at(0.72, 0.010, "noseband")
    hb, hpts = loop_at(0.12, 0.012, "headpiece")
    out += [nb, hb]
    for sgn in (1, -1):
        a = max(hpts, key=lambda p: sgn * p.x)
        c = max(npts, key=lambda p: sgn * p.x - 0.3 * p.dot(up))
        out.append(mc.loft("cheek_%d" % sgn, [a, a.lerp(c, 0.5) + Vector((sgn * 0.01, 0, 0)), c],
                           [(0.008, 0.012)] * 3, segs=5, part="leather"))
        hand = Vector((-0.24, 0.40, 1.74)) + RIDER_SHIFT
        out.append(mc.loft("rein_%d" % sgn, [c, c.lerp(hand, 0.35) - Vector((0, 0, 0.08)),
                                             c.lerp(hand, 0.7) - Vector((0, 0, 0.05)), hand],
                           [(0.007, 0.007)] * 4, segs=5, part="leather"))
    for p in out:
        if "bone" not in p:
            p["copy"] = "horse"

    # stirrups under his feet, pinned to the saddle
    for sgn in (1, -1):
        foot = Vector((sgn * 0.38, 0.42, 0.93)) + RIDER_SHIFT      # under the scan's sabatons
        top = Vector((sgn * (abs(surf.side(0.12, 1.45) or 0.3) + 0.03), 0.12, 1.47))
        st = mc.loft("leather_%d" % sgn, [top, foot + Vector((0, 0, 0.06))], [(0.008, 0.02)] * 2, segs=5, part="leather")
        ring = [foot + Vector((0, 0.07 * math.cos(math.pi * 2 * j / 12), 0.05 * math.sin(math.pi * 2 * j / 12)))
                for j in range(13)]
        irons = mc.loft("stirrup_%d" % sgn, ring, [(0.008, 0.008)] * 13, segs=5, caps=(False, False), part="steel")
        for p in (st, irons):
            p["bone"] = "horse_body"
            out.append(p)
    return out


def _hull(pts):
    """Andrew's monotone chain: the convex hull of 2D points, in order."""
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _steps(z, hem, step=0.05):
    out = []
    while z - step > hem:
        z -= step
        out.append(z)
    return out + [hem]


def _resample(pts, n):
    """`pts` as a polyline, re-cut into n points evenly along its length."""
    acc = [0.0]
    for a, b in zip(pts, pts[1:]):
        acc.append(acc[-1] + (b - a).length)
    out = []
    for k in range(n):
        t = acc[-1] * k / (n - 1)
        i = max(j for j in range(len(acc)) if acc[j] <= t + 1e-9)
        i = min(i, len(pts) - 2)
        f = (t - acc[i]) / max(acc[i + 1] - acc[i], 1e-9)
        out.append(pts[i].lerp(pts[i + 1], min(1.0, f)))
    return out


def lance():
    d = (LANCE_TIP - LANCE_BUTT).normalized()
    L = (LANCE_TIP - LANCE_BUTT).length
    at = lambda t: LANCE_BUTT + d * (L * t)
    side = d.orthogonal().normalized()
    out = [mc.loft("shaft", [at(0), at(0.08), at(0.45), at(0.9)], [(0.028, 0.028), (0.034, 0.034), (0.03, 0.03), (0.021, 0.021)],
                   segs=8, part="wood"),
           mc.loft("vamplate", [at(0.47), at(0.50), at(0.505)], [(0.033, 0.033), (0.07, 0.07), (0.034, 0.034)], segs=12, part="steel"),
           mc.loft("collar", [at(0.895), at(0.915)], [(0.027, 0.027), (0.024, 0.024)], segs=8, part="brass"),
           mc.loft("head", [at(0.915), at(0.94), at(0.975), at(1.0)], [(0.018, 0.018), (0.042, 0.010), (0.026, 0.007), (0.002, 0.002)],
                   segs=8, side=side, part="steel")]
    for p in out:
        p["bone"] = "lance"
    return out


def shield():
    """model_cavalry's heater, hung on this knight's left forearm."""
    saved = (mc.V, mc.OY)
    try:
        mc.OY = 0.0
        mc.V = lambda x, y, z: Vector((x, y, z))
        pieces = mc.shield()
    finally:
        mc.V, mc.OY = saved
    # model_cavalry places it at its own knight's forearm: move it onto this one
    here = Vector((-0.325, 0.25, 1.87))
    boss = next(p for p in pieces if p.name.endswith("boss"))
    c = sum((v.co for v in boss.data.vertices), Vector()) / len(boss.data.vertices)
    boss.data.transform(Matrix.Translation(c) @ Matrix.Scale(0.65, 4) @ Matrix.Translation(-c))
    for p in pieces:
        p.data.transform(Matrix.Translation(SHIELD_C - here))
        p["bone"] = "shield"
    return pieces


# ------------------------------------------------------------ baking ----

def coat_material(high, surf):
    """The coat, painted in object space and baked: charcoal with soft pale
    dapples, black points below the knees, black mane and tail, dark horn,
    a white star. The regions are a colour attribute on the scan."""
    me = high.data
    attr = me.color_attributes.new("marks", "FLOAT_COLOR", "POINT")
    nose = max(surf.co, key=lambda c: c.y)
    poll = max((c for c in surf.co if c.y > nose.y - 0.55), key=lambda c: c.z)
    brow = poll.lerp(nose, 0.25)
    face = Vector((1, 0, 0)).cross((nose - poll).normalized())          # out of the forehead
    star, _ = surf.hit(brow + face * 0.6, brow)
    star = star or brow
    rear = min(c.y for c in surf.co)
    for i, v in enumerate(me.vertices):
        c = v.co
        points = max(0.0, min(1.0, (0.62 - c.z) / 0.25))           # black legs
        hoof = 1.0 if c.z < 0.085 else 0.0
        ty = surf_top_cached(surf, c.y)
        tail = 1.0 if (c.y < rear + 0.16 and (ty is None or c.z < ty - 0.06)) else 0.0
        mane = 0.0
        if 0.45 < c.y < poll.y and abs(c.x) < 0.07:
            t = surf_top_cached(surf, c.y)
            if t is not None and c.z > t - 0.06:
                mane = 1.0
        starm = 1.0 if (c - star).length < 0.035 else 0.0
        attr.data[i].color = (max(points, tail, mane), hoof, starm, 1.0)
    mat = bpy.data.materials.new("cav_coat_bake")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 17.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = (0.030, 0.031, 0.034, 1)   # the dapple, a shade paler
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = (0.016, 0.017, 0.019, 1)   # charcoal
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 40.0
    attrn = nt.nodes.new("ShaderNodeAttribute")
    attrn.attribute_name = "marks"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    black = nt.nodes.new("ShaderNodeMix")
    black.data_type = "RGBA"
    black.inputs["B"].default_value = (0.012, 0.012, 0.013, 1)
    horn = nt.nodes.new("ShaderNodeMix")
    horn.data_type = "RGBA"
    horn.inputs["B"].default_value = (0.035, 0.030, 0.026, 1)
    white = nt.nodes.new("ShaderNodeMix")
    white.data_type = "RGBA"
    white.inputs["B"].default_value = (0.75, 0.74, 0.70, 1)
    grain = nt.nodes.new("ShaderNodeMix")
    grain.data_type = "RGBA"
    grain.blend_type = "MULTIPLY"
    grain.inputs["Factor"].default_value = 0.25
    L = nt.links.new
    L(tc.outputs["Object"], vor.inputs["Vector"])
    L(vor.outputs["Distance"], ramp.inputs["Fac"])
    L(tc.outputs["Object"], noise.inputs["Vector"])
    L(ramp.outputs["Color"], grain.inputs["A"])
    L(noise.outputs["Color"], grain.inputs["B"])
    L(attrn.outputs["Color"], sep.inputs["Color"])
    L(grain.outputs["Result"], black.inputs["A"])
    L(sep.outputs["Red"], black.inputs["Factor"])
    L(black.outputs["Result"], horn.inputs["A"])
    L(sep.outputs["Green"], horn.inputs["Factor"])
    L(horn.outputs["Result"], white.inputs["A"])
    L(sep.outputs["Blue"], white.inputs["Factor"])
    L(white.outputs["Result"], em.inputs["Color"])
    L(em.outputs["Emission"], outn.inputs["Surface"])
    me.materials.clear()
    me.materials.append(mat)


_TOPS = {}


def surf_top_cached(surf, y):
    k = round(y, 2)
    if k not in _TOPS:
        _TOPS[k] = surf.top(k)
    return _TOPS[k]


def emit_material_from(mat, channel):
    """A copy of a glTF material that EMITS its base colour or its
    metallic-roughness texture, for an EMIT bake that no light can touch."""
    tex = None
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            name = n.image.name.lower()
            if channel == "albedo" and ("basecolor" in name or "base_color" in name or "diffuse" in name):
                tex = n.image
            if channel == "mr" and "metallic" in name:
                tex = n.image
    em = bpy.data.materials.new("cav_emit_" + channel)
    em.use_nodes = True
    nt = em.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = tex
    nt.links.new(t.outputs["Color"], e.inputs["Color"])
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return em


def new_image(name, colour, fill):
    img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.generated_color = fill
    return img


def bake_into(low, high, image, kind):
    """Bake `high` onto `low`'s UVs into `image` (selected-to-active), leaving
    every pixel outside low's islands as it was."""
    sc = bpy.context.scene
    mat = low.data.materials[0]
    nt = mat.node_tree
    # One node per target image, never re-pointed: re-pointing one node
    # between bakes left the third bake writing into the second's image.
    key = "bake_" + image.name
    node = nt.nodes.get(key)
    if node is None:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.name = key
        node.image = image
    for n in nt.nodes:
        n.select = False
    node.select = True
    nt.nodes.active = node
    mc.activate(low)
    high.select_set(True)
    bpy.context.view_layer.objects.active = low
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.03
    sc.render.bake.max_ray_distance = 0.08
    sc.render.bake.margin = BAKE_MARGIN
    sc.render.bake.use_clear = False
    sc.render.bake.target = "IMAGE_TEXTURES"
    if kind == "NORMAL":
        sc.render.bake.normal_space = "TANGENT"
    bpy.ops.object.bake(type=kind)


def reduce(high, name, tris, part):
    low = high.copy()
    low.data = high.data.copy()
    low.name = low.data.name = "cav_" + name
    mc.link(low)
    for layer in list(low.data.uv_layers):
        low.data.uv_layers.remove(layer)
    for a in list(low.data.color_attributes):
        low.data.color_attributes.remove(a)
    d = low.modifiers.new("decimate", "DECIMATE")
    d.ratio = min(1.0, tris / max(1, len(high.data.polygons)))
    mc.apply_mods(low)
    mc.unwrap(low)
    low["part"] = part
    mc.into_tile(low)
    mc.activate(low)
    bpy.ops.object.shade_smooth()
    return low


def atlas_images():
    col = new_image(NAME + "_atlas", True, (0.5, 0.5, 0.5, 1))
    nor = new_image(NAME + "_atlas_n", False, (0.5, 0.5, 1.0, 1))
    mr = new_image(NAME + "_atlas_mr", False, (1.0, 0.6, 0.0, 1))
    return col, nor, mr


def paint_tiles(col, mr):
    """model_cavalry's numpy tiles for the tack (and the horse's roughness)."""
    import numpy as np
    ccol, cmr = mc.paint_atlas()
    a = np.array(ccol.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    b = np.array(mr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    m = np.array(cmr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    cell = ATLAS // 4
    for key in ("leather", "cloth", "brass", "wood", "steel", "shield"):
        u0, v0, du, dv = TILES[key]
        ys, xs = slice(v0 * cell, (v0 + dv) * cell), slice(u0 * cell, (u0 + du) * cell)
        c[ys, xs] = a[ys, xs]
        b[ys, xs] = m[ys, xs]
    u0, v0, du, dv = TILES["horse"]
    b[v0 * cell:(v0 + dv) * cell, u0 * cell:(u0 + du) * cell] = (1.0, 0.62, 0.0, 1.0)
    col.pixels.foreach_set(c.ravel())
    mr.pixels.foreach_set(b.ravel())
    bpy.data.images.remove(ccol)
    bpy.data.images.remove(cmr)


def atlas_material(col, nor, mr):
    mat = bpy.data.materials.new(NAME + "_atlas")
    mat.use_nodes = True
    mat.use_backface_culling = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = col
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nor
    nm = nt.nodes.new("ShaderNodeNormalMap")
    tm = nt.nodes.new("ShaderNodeTexImage")
    tm.image = mr
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def rider_weights(low, arm):
    """Plate is rigid: each loose shell of the knight follows ONE bone, the
    one nearest its centre."""
    bones = [b for b in arm.data.bones if b.name in mc.RIDER_BONES(arm)]
    bm = bmesh.new()
    bm.from_mesh(low.data)
    parts = loose_parts(bm)
    bm.free()
    for g in list(low.vertex_groups):
        low.vertex_groups.remove(g)
    groups = {}
    co = [v.co for v in low.data.vertices]
    for p in parts:
        c = sum((co[i] for i in p), Vector()) / len(p)

        def dist(b):
            a, e = b.head_local, b.tail_local
            t = max(0.0, min(1.0, (c - a).dot(e - a) / max((e - a).length_squared, 1e-9)))
            return (c - a.lerp(e, t)).length
        best = min(bones, key=dist)
        g = groups.get(best.name) or low.vertex_groups.new(name=best.name)
        groups[best.name] = g
        g.add(p, 1.0, "REPLACE")


# -------------------------------------------------------------- build ----

def build(write=True):
    sc = mc.fresh_scene()
    colls = (bpy.data.materials, bpy.data.images, bpy.data.meshes, bpy.data.textures)
    before = {id(c): {d.name for d in c} for c in colls}
    horse_high = horse_source()
    rider_high = rider_source()
    surf = Surface(horse_high)
    horse_low = reduce(horse_high, "horse", HORSE_TRIS, "horse")
    rider_low = reduce(rider_high, "rider", RIDER_TRIS, "rider")
    pieces = tack(surf) + lance() + shield()
    for p in pieces:
        if not p.data.uv_layers:
            mc.unwrap(p)
        mc.into_tile(p)
        mc.activate(p)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50))

    # the atlas: tiles painted, then the two scans baked into their halves
    col, nor, mr = atlas_images()
    paint_tiles(col, mr)
    mat = atlas_material(col, nor, mr)
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.cycles.device = "GPU"
    coat_material(horse_high, surf)
    for low in (horse_low, rider_low):
        low.data.materials.clear()
        low.data.materials.append(mat)
    bake_into(horse_low, horse_high, col, "EMIT")
    bake_into(horse_low, horse_high, nor, "NORMAL")
    scan_mat = rider_high.data.materials[0]
    rider_high.data.materials[0] = emit_material_from(scan_mat, "albedo")
    bake_into(rider_low, rider_high, col, "EMIT")
    rider_high.data.materials[0] = emit_material_from(scan_mat, "mr")
    bake_into(rider_low, rider_high, mr, "EMIT")
    bake_into(rider_low, rider_high, nor, "NORMAL")
    for img in (col, nor, mr):
        img.pack()
    nt = mat.node_tree
    for n in [n for n in nt.nodes if n.name.startswith("bake_")]:
        nt.nodes.remove(n)

    # the rig and the weights
    arm = build_rig(rig_spec(surf))
    how = {"horse": mc.heat(horse_low, arm, mc.HORSE_BONES(arm))}
    rider_weights(rider_low, arm)
    for p in pieces:
        if "bone" in p:
            mc.rigid(p, p["bone"])
        else:
            mc.copy_weights(p, horse_low)
    everything = [horse_low, rider_low] + pieces
    mc.activate(horse_low)
    for p in everything[1:]:
        p.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = ob.data.name = NAME
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for poly in ob.data.polygons:
        poly.material_index = 0
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    ob.parent = arm
    for o in (horse_high, rider_high):
        o.hide_set(True)
        o.hide_render = True

    for c in colls:        # what importing the scans left behind, and only that
        for d in [d for d in c if d.name not in before[id(c)] and d.users == 0]:
            c.remove(d)

    acts = mc.actions(arm)
    mc.stash(arm, acts)
    for track in arm.animation_data.nla_tracks:
        track.name = track.name[len(NAME) + 1:]
    tris = tri_count(ob)
    log("cavalry (scans): %d tris, %d bones, horse weights %s" % (tris, len(arm.data.bones), how["horse"]))
    if write:
        out_dir = os.environ.get("CAV_OUT", OUT)
        path = os.path.join(out_dir, NAME + ".glb")
        mc.export_glb([arm, ob], path)
        if out_dir == OUT:
            mpath = os.path.join(OUT, "units3d.json")
            manifest = json.load(open(mpath))
            manifest[NAME] = {
                "label": "Knight", "kind": "mounted",
                "height_m": round(max(v.co.z for v in ob.data.vertices), 3),
                "source": "CC0 scans (Cleveland Museum of Art 1964.88 knight, Hunt Museum horse) + design C tack, tools/units3d/cavalry_scan.py",
                "tris": tris, "bones": len(arm.data.bones), "weights": how,
                "actions": {a.name[len(NAME) + 1:]: [int(a.frame_range[0]), int(a.frame_range[1])] for a in acts},
                "fps": mc.FPS,
            }
            with open(mpath, "w") as f:
                json.dump(manifest, f, indent=1, sort_keys=True)
                f.write("\n")
        log("wrote " + path)
    blend = os.environ.get("CAV_BLEND")
    if blend and bpy.app.background:
        save_blend(arm, ob, acts, blend)
    return arm, ob


def save_blend(arm, ob, acts, path):
    """A .blend to open by hand: the piece alone (the scans dropped), the
    GARRISON loop playing, the timeline set to it."""
    for name in ("cav_horse_high", "cav_rider_high"):
        o = bpy.data.objects.get(name)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    garrison = next(a for a in acts if a.name.endswith("GARRISON"))
    ad = arm.animation_data
    ad.action = garrison
    if getattr(garrison, "slots", None):
        try:
            ad.action_slot = garrison.slots[0]
        except Exception:
            pass
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = [int(f) for f in garrison.frame_range]
    sc.render.fps = mc.FPS
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
        e.identifier for e in type(sc.render).bl_rna.properties["engine"].enum_items] else sc.render.engine
    bpy.ops.outliner.orphans_purge(do_recursive=True)     # a factory file: only this build's data
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    log("saved " + path)


if __name__ in ("__main__", "live"):
    build()
