"""The cavalry piece, MODELLED BY HAND in Blender (owner 2026-09-25: the
Hunyuan3D knight is replaced; design "Z-Image C", references in
assets/imagegen/out/cavalry_c_sheet/, made by tools/units3d/gen_cavalry_sheet.py — both deleted 2026-09-30).

  blender -b --factory-startup --python tools/units3d/model_cavalry.py
  # or inside a running Blender (the Blender MCP):
  exec(open(".../tools/units3d/model_cavalry.py").read(), {"__name__": "live"})

A fifteenth-century knight in a fluted plate harness and armet on a dark
charcoal warhorse under a green saddle cloth with a brass-studded border,
a green heater shield with a white pale on his left arm and a lance upright
in his right hand. Everything is built from design points in METRES (horse
16 hands at the withers), so the rig, the weights and the model all read
the same numbers:

  * lofted tubes (`loft`) for the horse, the rider, the tack and the lance,
    the horse's coat and the rider's harness fused by a voxel remesh and
    collapsed to a budget, so the joins are organic and the mesh is one
    closed skin that bone heat can solve;
  * ONE material over one 2048 atlas painted here with numpy (the coat's
    dapples, brushed steel, leather, wool, brass, wood, hair, the shield's
    field) plus its metallic-roughness twin — one draw call per piece;
  * one armature for horse and rider, the coat and the harness weighted by
    heat over their OWN bones, what lies on them (cloth, straps, plates)
    copying their weights, the rigid pieces (hooves, saddle, helmet, lance,
    shield) pinned whole to one bone;
  * GARRISON (loop), MARCH (a four-beat walk, loop) and ATTACK (the lance
    comes down to the couch and the horse surges), through make_units.py's
    world-axis pose helpers;
  * no base (owner 2026-09-27: 撤除所有底座).

Writes assets/3D/units/cavalry/cavalry.glb and its entry in units3d.json. Live, it
builds into its own scene `cavalry_c` and leaves every other scene alone.
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, Matrix

HERE = "/Users/samuelzhang/game_design/tools/units3d"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import importlib
import unit_common
import make_units
importlib.reload(unit_common)
importlib.reload(make_units)
from make_units import apply_pose, make_action, stash, gait, FPS
from unit_common import OUT, glb_path, log, tri_count

NAME = "cavalry"
SCENE = "cavalry_c"
OY = -0.18                 # the design frame's horse is centred here, nose +Y
VOXEL = 0.011
BUDGET = {"coat": 8000, "harness": 3400}
ATLAS = 2048

# ------------------------------------------------------------ the atlas ----
# (u0, v0, du, dv) in 512 px cells of the 2048 atlas.
TILES = {
    "coat":   (0, 0, 2, 2),
    "steel":  (2, 0, 2, 1),
    "leather": (2, 1, 1, 1),
    "cloth":  (3, 1, 1, 1),
    "brass":  (0, 2, 1, 1),
    "wood":   (1, 2, 1, 1),
    "hair":   (2, 2, 1, 1),
    "hoof":   (3, 2, 1, 1),
    "shield": (0, 3, 1, 1),
}
INSET_PX = 14


def V(x, y, z):
    return Vector((x, y + OY, z))


# -------------------------------------------------------------- scene ----

def fresh_scene():
    if bpy.app.background:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        return bpy.context.scene
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = sc
    for ob in list(sc.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    # only what an earlier run of THIS script made: never anyone else's orphans
    mine = lambda d: d.name.startswith(("cav_", NAME, "base_iron", "base_gold")) or (
        isinstance(d, bpy.types.Action) and d.name.split(".")[0] in ("GARRISON", "MARCH", "ATTACK")
        and d.users <= 1)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials,
                 bpy.data.images, bpy.data.actions):
        for d in [d for d in coll if mine(d)]:
            coll.remove(d)
    return sc


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


# ---------------------------------------------------------------- loft ----

def loft(name, pts, radii, segs=12, side=Vector((1, 0, 0)), caps=(True, True), part="steel"):
    """A tube through `pts` whose ring i is an ellipse of half axes
    radii[i] = (a across `side`, b across the other normal). UVs run round
    the ring and along the length, per loop, so there is no seam split."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    n = len(pts)
    rings, vs = [], [0.0]
    for i in range(1, n):
        vs.append(vs[-1] + (pts[i] - pts[i - 1]).length)
    total = vs[-1] or 1.0
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        s = side - side.dot(t) * t
        if s.length < 1e-6:
            s = Vector((0, 1, 0)) - Vector((0, 1, 0)).dot(t) * t
        s.normalize()
        u = s.cross(t)
        a, b = radii[i]
        rings.append([bm.verts.new(p + s * (a * math.cos(2 * math.pi * j / segs))
                                   + u * (b * math.sin(2 * math.pi * j / segs)))
                      for j in range(segs)])
    for i in range(n - 1):
        for j in range(segs):
            j1 = (j + 1) % segs
            f = bm.faces.new((rings[i][j], rings[i][j1], rings[i + 1][j1], rings[i + 1][j]))
            for loop, (uu, vv) in zip(f.loops, ((j, i), (j + 1, i), (j + 1, i + 1), (j, i + 1))):
                loop[uvl].uv = (uu / segs, vs[vv] / total)
    for end, cap in ((0, caps[0]), (n - 1, caps[1])):
        if not cap:
            continue
        c = bm.verts.new(pts[end])
        for j in range(segs):
            j1 = (j + 1) % segs
            quad = (rings[end][j], rings[end][j1], c) if end else (rings[end][j1], rings[end][j], c)
            f = bm.faces.new(quad)
            for loop in f.loops:
                loop[uvl].uv = (0.5, 0.0 if end == 0 else 1.0)
    return to_object(bm, name, part)


def to_object(bm, name, part):
    me = bpy.data.meshes.new("cav_" + name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new("cav_" + name, me))
    ob["part"] = part
    return ob


def sphere(name, centre, radii, part, cut_z=None, segs=16, rings=8):
    """An ellipsoid; `cut_z` (a share of its height, -1..1) keeps only what is
    above it — a pauldron is the top of one."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, calc_uvs=True)
    if cut_z is not None:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut_z - 1e-4], context="VERTS")
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + centre
    ob = to_object(bm, name, part)
    if cut_z is not None:
        solid(ob, 0.008)
    return ob


def solid(ob, thick):
    m = ob.modifiers.new("solid", "SOLIDIFY")
    m.thickness = thick
    m.offset = -1.0
    apply_mods(ob)


def apply_mods(ob):
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def mirror_pts(pts):
    return [Vector((-p.x, p.y, p.z)) for p in pts]


# ---------------------------------------------------------- the horse ----
# (y, zc, half height, half width) along the barrel, design frame.
BODY = [(-0.91, 1.32, 0.06, 0.06), (-0.87, 1.32, 0.19, 0.17), (-0.80, 1.32, 0.27, 0.25),
        (-0.70, 1.30, 0.33, 0.30), (-0.55, 1.28, 0.35, 0.32), (-0.35, 1.23, 0.37, 0.33),
        (-0.10, 1.20, 0.38, 0.34), (0.15, 1.21, 0.40, 0.34), (0.38, 1.25, 0.41, 0.31),
        (0.58, 1.27, 0.36, 0.27), (0.74, 1.27, 0.28, 0.22), (0.84, 1.27, 0.17, 0.15),
        (0.90, 1.27, 0.05, 0.05)]
NECK = [(0.50, 1.40, 0.24, 0.40), (0.70, 1.64, 0.19, 0.31), (0.86, 1.82, 0.145, 0.22),
        (0.98, 1.95, 0.115, 0.16)]
HEAD = [(0.97, 2.02, 0.10, 0.11), (1.02, 1.99, 0.112, 0.135), (1.09, 1.89, 0.125, 0.17),
        (1.19, 1.73, 0.10, 0.125), (1.29, 1.57, 0.085, 0.10), (1.35, 1.48, 0.075, 0.085),
        (1.385, 1.43, 0.045, 0.045)]
FORE_X, HIND_X = 0.19, 0.18
FORE = [(0.58, 1.20, 0.15), (0.60, 0.98, 0.12), (0.61, 0.80, 0.095), (0.62, 0.64, 0.07),
        (0.625, 0.56, 0.066), (0.63, 0.40, 0.05), (0.645, 0.22, 0.056), (0.66, 0.14, 0.048),
        (0.68, 0.09, 0.05)]
HIND = [(-0.50, 1.25, 0.22), (-0.47, 1.02, 0.19), (-0.49, 0.86, 0.14), (-0.55, 0.70, 0.10),
        (-0.62, 0.53, 0.07), (-0.60, 0.36, 0.05), (-0.585, 0.22, 0.056), (-0.57, 0.14, 0.048),
        (-0.56, 0.09, 0.05)]
TAIL = [(-0.86, 1.47, 0.07), (-0.94, 1.37, 0.10), (-0.99, 1.17, 0.14), (-1.01, 0.92, 0.15),
        (-0.99, 0.70, 0.11), (-0.97, 0.57, 0.03)]


def body_ring(y):
    """The barrel's ring at y, interpolated: (zc, half height, half width)."""
    if y <= BODY[0][0]:
        return BODY[0][1:]
    for (y0, *r0), (y1, *r1) in zip(BODY, BODY[1:]):
        if y <= y1:
            t = (y - y0) / (y1 - y0)
            return tuple(a + (b - a) * t for a, b in zip(r0, r1))
    return BODY[-1][1:]


def half_width_at(y, z):
    zc, hh, hw = body_ring(y)
    k = max(0.0, 1.0 - ((z - zc) / hh) ** 2)
    return hw * math.sqrt(k)


def horse():
    parts = []
    parts.append(loft("barrel", [V(0, y, zc) for y, zc, _, _ in BODY],
                      [(hw, hh) for _, _, hh, hw in BODY], segs=20, part="coat"))
    neck = NECK + HEAD
    parts.append(loft("neck", [V(0, y, z) for y, z, _, _ in neck],
                      [(a, b) for _, _, a, b in neck], segs=20, part="coat"))
    for s in (1, -1):
        parts.append(loft("fore_%d" % s, [V(s * FORE_X, y, z) for y, z, _ in FORE],
                          [(r * 0.8, r * 1.1) for _, _, r in FORE], segs=14, part="coat"))
        parts.append(loft("hind_%d" % s, [V(s * HIND_X, y, z) for y, z, _ in HIND],
                          [(r * 0.8, r * 1.1) for _, _, r in HIND], segs=14, part="coat"))
        parts.append(loft("ear_%d" % s, [V(s * 0.055, 0.985, 2.04), V(s * 0.065, 0.975, 2.13),
                                          V(s * 0.07, 0.965, 2.19)],
                          [(0.032, 0.022), (0.022, 0.016), (0.004, 0.004)], segs=8, part="coat"))
    coat = fuse(parts, "coat", BUDGET["coat"])

    extra = []
    tail = loft("tail", [V(0, y, z) for y, z, _ in TAIL], [(r * 0.75, r) for _, _, r in TAIL],
                segs=14, part="hair")
    extra.append(tail)
    # The mane lies along the crest, falling to the off side.
    crest = []
    for (y, z, a, b), (y2, z2, _, _) in zip(NECK + HEAD[:2], (NECK + HEAD[:2])[1:] + [(1.03, 2.02, 0, 0)]):
        t = Vector((0, y2 - y, z2 - z)).normalized()
        up = Vector((0, -t.z, t.y))
        crest.append(V(0.03, y, z) + up * (b * 0.92))
    extra.append(loft("mane", crest, [(0.035, 0.06)] * (len(crest) - 1) + [(0.02, 0.03)],
                      segs=8, part="hair"))
    for s in (1, -1):
        eye = sphere("eye_%d" % s, V(s * 0.122, 1.10, 1.905), (0.018, 0.026, 0.02), "hair", segs=10, rings=6)
        eye["bone"] = "head_h"
        extra.append(eye)
        for key, (y, z) in (("fore", (0.68, 0.09)), ("hind", (-0.56, 0.09))):
            x = s * (FORE_X if key == "fore" else HIND_X)
            h = loft("hoof_%s_%d" % (key, s), [V(x, y, z), V(x, y + 0.01, 0.045), V(x, y + 0.02, 0.0)],
                     [(0.046, 0.052), (0.054, 0.062), (0.06, 0.07)], segs=12, part="hoof")
            h["bone"] = "%s_hoof_%s" % (key, "r" if s > 0 else "l")
            extra.append(h)
    return coat, tail, extra


def fuse(parts, name, budget):
    """Union the parts into ONE closed skin (voxel remesh), soften it, and
    collapse it to `budget` triangles."""
    activate(parts[0])
    for p in parts[1:]:
        p.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = "cav_" + name
    ob["part"] = parts[0]["part"]
    m = ob.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = VOXEL
    m.adaptivity = 0.0
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 4
    apply_mods(ob)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    d = ob.modifiers.new("decimate", "DECIMATE")
    d.ratio = min(1.0, budget / max(1, tris))
    apply_mods(ob)
    unwrap(ob)
    bpy.ops.object.shade_smooth()
    return ob


def unwrap(ob):
    # Named HERE: a Blender whose UI translates new data names (the owner's is
    # Chinese) would call smart_project's layer something else, and a join of
    # two differently named UV layers leaves half the pieces at (0, 0).
    if not ob.data.uv_layers:
        ob.data.uv_layers.new(name="UVMap")
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------- the tack ----

def tack():
    out = []
    # The saddle: a padded seat on the back, a tall cantle and pommel, flaps.
    seat = []
    for y in (-0.22, -0.12, 0.0, 0.12, 0.24, 0.30):
        zc, hh, hw = body_ring(y)
        seat.append((y, zc + hh + 0.035))
    out.append(loft("seat", [V(0, y, z) for y, z in seat],
                    [(0.20, 0.05)] * len(seat), segs=14, part="leather"))
    top = seat[0][1]
    out.append(loft("cantle", [V(-0.15, -0.20, top + 0.02), V(0, -0.225, top + 0.13), V(0.15, -0.20, top + 0.02)],
                    [(0.025, 0.045), (0.025, 0.055), (0.025, 0.045)], segs=8, side=Vector((0, 1, 0)), part="leather"))
    front = seat[-1][1]
    out.append(loft("pommel", [V(-0.13, 0.29, front + 0.01), V(0, 0.315, front + 0.11), V(0.13, 0.29, front + 0.01)],
                    [(0.025, 0.04), (0.025, 0.05), (0.025, 0.04)], segs=8, side=Vector((0, 1, 0)), part="leather"))
    for piece in out:
        piece["bone"] = "horse_body"

    # The saddle cloth: the barrel's own rings from the saddle back over the
    # croup, standing proud of the coat, hanging plumb below the widest line.
    rows, ys = [], [0.18 - 0.0425 * i for i in range(24)]
    ys = [y for y in ys if y >= -0.84]
    hem = lambda y: 1.00 + max(0.0, -0.45 - y) * 0.45
    for y in ys:
        zc, hh, hw = body_ring(y)
        hw, hh = hw + 0.028, hh + 0.028
        side = []
        for k in range(10):                       # over the top to the widest line
            th = math.pi / 2 * (1 - k / 9)
            side.append((hw * math.cos(th), zc + hh * math.sin(th)))
        z = zc
        while z - 0.05 > hem(y):                  # then plumb down to the hem
            z -= 0.05
            side.append((hw, z))
        side.append((hw, hem(y)))
        rows.append((y, side))
    width = min(len(r[1]) for r in rows)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = []
    for y, side in rows:
        pts = [(-x, z) for x, z in reversed(side[:width])] + [(x, z) for x, z in side[1:width]]
        grid.append([bm.verts.new(V(x, y, z)) for x, z in pts])
    for i in range(len(grid) - 1):
        for j in range(len(grid[i]) - 1):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            for loop, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uvl].uv = (b / (len(grid[0]) - 1), a / (len(grid) - 1))
    edges = [[g[0].co.copy() for g in grid], [g[-1].co.copy() for g in grid],
             [v.co.copy() for v in grid[0]], [v.co.copy() for v in grid[-1]]]
    cloth = to_object(bm, "cloth", "cloth")
    solid(cloth, 0.012)
    cloth["copy"] = "coat"
    out.append(cloth)
    # Its brass-studded border, along the hems and both ends.
    for k, pts in enumerate(edges):
        b = loft("border_%d" % k, pts, [(0.016, 0.016)] * len(pts), segs=6, part="brass")
        b["copy"] = "coat"
        out.append(b)

    # The breast strap round the chest, and its round brass boss.
    strap = []
    for s in (-1, 1):
        ys_ = [0.30, 0.50, 0.66, 0.78, 0.845]
        side = [V(s * (half_width_at(y, 1.24) + 0.018), y, 1.24 + (0.06 if y == 0.30 else 0.0)) for y in ys_]
        strap += side if s > 0 else list(reversed(side))
    strap.insert(len(strap) // 2, V(0, 0.905, 1.235))
    b = loft("breast", strap, [(0.012, 0.03)] * len(strap), segs=6, side=Vector((0, 0, 1)), part="leather")
    b["copy"] = "coat"
    out.append(b)
    boss = sphere("boss", V(0, 0.915, 1.235), (0.045, 0.02, 0.045), "brass", segs=12, rings=6)
    boss["copy"] = "coat"
    out.append(boss)

    # The bridle: noseband, headpiece, cheek straps; the reins to his hand.
    def around(y, z, a, b, grow, name, n=12):
        pts = []
        head = [(y0, z0) for y0, z0, _, _ in HEAD]
        # the head's local direction at (y, z)
        t = Vector((0, 0.55, -0.83)).normalized()
        u = Vector((0, -t.z, t.y))
        for j in range(n + 1):
            th = 2 * math.pi * j / n
            pts.append(V(0, y, z) + Vector((1, 0, 0)) * ((a + grow) * math.cos(th)) + u * ((b + grow) * math.sin(th)))
        return loft(name, pts, [(0.008, 0.012)] * len(pts), segs=5, caps=(False, False), part="leather")
    nose = around(1.26, 1.61, 0.078, 0.093, 0.012, "noseband")
    brow = around(1.03, 1.97, 0.100, 0.12, 0.012, "headpiece")
    out += [nose, brow]
    for s in (1, -1):
        out.append(loft("cheek_%d" % s, [V(s * 0.115, 1.04, 1.95), V(s * 0.10, 1.16, 1.76), V(s * 0.09, 1.26, 1.60)],
                        [(0.008, 0.012)] * 3, segs=5, part="leather"))
        out.append(loft("rein_%d" % s, [V(s * 0.085, 1.30, 1.57), V(s * 0.12, 1.00, 1.55), V(s * 0.10, 0.70, 1.66),
                                        V(-0.10 + s * 0.02, 0.44, 1.76), V(-0.14, 0.36, 1.80)],
                        [(0.007, 0.007)] * 5, segs=5, part="leather"))
    for piece in out:
        if "bone" not in piece and "copy" not in piece:
            piece["copy"] = "coat"

    # Stirrups and their leathers, pinned to the saddle.
    for s in (1, -1):
        x = s * 0.36
        st = loft("leather_%d" % s, [V(s * (half_width_at(0.10, 1.50) + 0.03), 0.10, 1.52), V(x, 0.18, 1.02)],
                  [(0.008, 0.02)] * 2, segs=5, part="leather")
        ring = []
        for j in range(13):
            th = math.pi * 2 * j / 12
            ring.append(V(x, 0.18 + 0.07 * math.cos(th), 0.965 + 0.05 * math.sin(th)))
        irons = loft("stirrup_%d" % s, ring, [(0.008, 0.008)] * len(ring), segs=5, caps=(False, False), part="steel")
        for p in (st, irons):
            p["bone"] = "horse_body"
            out.append(p)
    return out


# --------------------------------------------------------- the rider ----
TORSO = [(0, 0.00, 1.62, 0.16, 0.13), (0, 0.00, 1.72, 0.185, 0.145), (0, 0.01, 1.86, 0.17, 0.13),
         (0, 0.03, 2.00, 0.21, 0.165), (0, 0.02, 2.12, 0.235, 0.15), (0, 0.0, 2.20, 0.21, 0.125),
         (0, 0.0, 2.26, 0.085, 0.075), (0, 0.005, 2.31, 0.065, 0.065)]
HELM = [(0, 0.01, 2.29, 0.09, 0.10), (0, 0.012, 2.36, 0.112, 0.122), (0, 0.012, 2.46, 0.117, 0.127),
        (0, 0.005, 2.55, 0.10, 0.11), (0, -0.005, 2.61, 0.06, 0.07), (0, -0.008, 2.635, 0.015, 0.015)]
ARM_R = [(0.22, 0.0, 2.17, 0.08), (0.265, 0.03, 2.07, 0.064), (0.29, 0.08, 1.92, 0.058),
         (0.305, 0.18, 1.95, 0.052), (0.32, 0.27, 1.98, 0.046)]
ARM_L = [(-0.22, 0.0, 2.17, 0.08), (-0.265, 0.02, 2.06, 0.064), (-0.29, 0.05, 1.92, 0.058),
         (-0.225, 0.17, 1.86, 0.052), (-0.16, 0.29, 1.815, 0.046)]
LEG = [(0.10, 0.0, 1.68, 0.10), (0.21, 0.10, 1.57, 0.094), (0.32, 0.22, 1.43, 0.078),
       (0.345, 0.19, 1.25, 0.062), (0.355, 0.15, 1.05, 0.052), (0.36, 0.13, 0.985, 0.05),
       (0.36, 0.24, 0.965, 0.044), (0.36, 0.34, 0.96, 0.028), (0.36, 0.40, 0.962, 0.008)]
HAND_R, HAND_L = (0.32, 0.30, 1.98), (-0.145, 0.31, 1.805)
LANCE_X, LANCE_Y = 0.325, 0.30


def rider():
    parts = []
    parts.append(loft("torso", [V(x, y, z) for x, y, z, _, _ in TORSO],
                      [(a, b) for *_, a, b in TORSO], segs=16, part="steel"))
    parts.append(loft("helm", [V(x, y, z) for x, y, z, _, _ in HELM],
                      [(a, b) for *_, a, b in HELM], segs=16, part="steel"))
    for arm in (ARM_R, ARM_L):
        parts.append(loft("arm", [V(x, y, z) for x, y, z, _ in arm], [(r, r) for *_, r in arm], segs=10))
    for s in (1, -1):
        parts.append(loft("leg", [V(s * x, y, z) for x, y, z, _ in LEG], [(r, r * 1.1) for *_, r in LEG], segs=10))
    body = fuse(parts, "harness", BUDGET["harness"])

    plates = []
    # the armet's pointed visor, its sight, and a low comb over the skull
    plates.append(loft("visor", [V(0, 0.07, 2.425), V(0, 0.125, 2.425), V(0, 0.168, 2.415)],
                       [(0.105, 0.062), (0.075, 0.042), (0.018, 0.018)], segs=12, side=Vector((1, 0, 0))))
    arc = [math.radians(a) for a in range(-55, 56, 11)]
    sight = loft("sight", [V(0.119 * math.sin(a), 0.012 + 0.129 * math.cos(a), 2.498) for a in arc],
                 [(0.004, 0.008)] * len(arc), segs=6, part="hair")
    plates.append(sight)
    plates.append(loft("comb", [V(0, 0.12, 2.50), V(0, 0.06, 2.60), V(0, -0.03, 2.645), V(0, -0.11, 2.57)],
                       [(0.008, 0.018)] * 4, segs=6))
    for piece in plates:
        piece["bone"] = "head"
    gorget = loft("gorget", [V(0, 0.0, 2.24), V(0, 0.0, 2.29)], [(0.10, 0.09), (0.085, 0.078)], segs=16)
    gorget["copy"] = "harness"
    plates.append(gorget)
    for s, bone in ((1, "r"), (-1, "l")):
        # pauldrons of three lames, couters, poleyns, gauntlets, tassets
        for k, (dz, r) in enumerate(((0.0, 1.0), (-0.035, 1.06), (-0.07, 1.1))):
            p = sphere("pauldron_%s%d" % (bone, k), V(s * 0.235, 0.0, 2.18 + dz),
                       (0.135 * r, 0.14 * r, 0.10 * r), "steel", cut_z=-0.15, segs=12, rings=6)
            p["copy"] = "harness"
            plates.append(p)
        arm = ARM_R if s > 0 else ARM_L
        c = sphere("couter_%s" % bone, V(*arm[2][:3]) + Vector((s * 0.02, -0.02, 0)), (0.055, 0.055, 0.055), "steel")
        c["copy"] = "harness"
        plates.append(c)
        knee = LEG[2]
        pk = sphere("poleyn_%s" % bone, V(s * (knee[0] + 0.01), knee[1] + 0.03, knee[2]), (0.066, 0.06, 0.07), "steel")
        pk["copy"] = "harness"
        plates.append(pk)
        hand = HAND_R if s > 0 else HAND_L
        g = sphere("gauntlet_%s" % bone, V(*hand), (0.05, 0.055, 0.05), "steel")
        g["bone"] = "hand_" + bone
        plates.append(g)
        wrist = arm[-1]
        cuff = loft("cuff_%s" % bone, [V(*wrist[:3]) - (V(*hand) - V(*wrist[:3])) * 0.8, V(*wrist[:3])],
                    [(0.05, 0.05), (0.06, 0.06)], segs=10)
        cuff["copy"] = "harness"
        plates.append(cuff)
    ridge = loft("ridge", [V(0, 0.155, 1.84), V(0, 0.192, 1.99), V(0, 0.17, 2.14)],
                 [(0.012, 0.012)] * 3, segs=6)
    ridge["copy"] = "harness"
    plates.append(ridge)
    for k, z in enumerate((1.82, 1.745, 1.67)):
        lame = loft("fauld_%d" % k, [V(0, 0.012, z + 0.03), V(0, 0.02, z - 0.03)],
                    [(0.172 + 0.012 * k, 0.137 + 0.012 * k), (0.182 + 0.012 * k, 0.147 + 0.012 * k)],
                    segs=16)
        lame["copy"] = "harness"
        plates.append(lame)
    tassets = loft("tassets", [V(0, 0.01, 1.76), V(0, 0.03, 1.64)], [(0.18, 0.145), (0.215, 0.17)], segs=16)
    tassets["copy"] = "harness"
    belt = loft("belt", [V(0, 0.01, 1.79), V(0, 0.01, 1.765)], [(0.168, 0.133), (0.172, 0.137)], segs=16, part="leather")
    belt["copy"] = "harness"
    plates += [tassets, belt]
    return body, plates


# ------------------------------------------------------ lance, shield ----

def lance():
    out = []
    shaft = [(1.10, 0.030), (1.30, 0.033), (1.90, 0.033), (2.60, 0.028), (3.02, 0.022)]
    out.append(loft("shaft", [V(LANCE_X, LANCE_Y, z) for z, _ in shaft], [(r, r) for _, r in shaft],
                    segs=8, part="wood"))
    out.append(loft("grip", [V(LANCE_X, LANCE_Y, 1.86), V(LANCE_X, LANCE_Y, 2.10)],
                    [(0.037, 0.037)] * 2, segs=8, part="leather"))
    out.append(loft("collar", [V(LANCE_X, LANCE_Y, 2.99), V(LANCE_X, LANCE_Y, 3.05)],
                    [(0.03, 0.03), (0.026, 0.026)], segs=8, part="brass"))
    head = [(3.05, 0.018, 0.018), (3.12, 0.046, 0.011), (3.24, 0.03, 0.008), (3.34, 0.002, 0.002)]
    out.append(loft("head", [V(LANCE_X, LANCE_Y, z) for z, _, _ in head], [(a, b) for _, a, b in head],
                    segs=8, side=Vector((0, 1, 0))))
    for p in out:
        p["bone"] = "lance"
    return out


SHIELD_OUTLINE = [(0.23, 0.30), (0.235, 0.12), (0.22, -0.04), (0.17, -0.18), (0.095, -0.285), (0.0, -0.345)]


def shield():
    """A heater, curved a little round the arm, the field planar-mapped so
    its painted white pale runs down the middle."""
    half = SHIELD_OUTLINE        # right side, top corner to point; the top edge arches
    ring = [(w, h) for w, h in half] + [(-w, h) for w, h in reversed(half[:-1])] + \
           [(-0.23 + 0.46 * k / 8, 0.30 + 0.02 * math.sin(math.pi * k / 8)) for k in range(1, 8)]
    centre = V(-0.325, 0.25, 1.87)
    wdir = Vector((0.30, 0.954, 0.0)).normalized()
    ndir = Vector((-wdir.y, wdir.x, 0.0))
    ndir = -ndir if ndir.x > 0 else ndir               # outward, to the near side
    hdir = Vector((0, 0, 1))
    tilt = Matrix.Rotation(math.radians(-8), 3, wdir)   # its top leans back a little
    hdir, ndir = tilt @ hdir, tilt @ ndir

    def at(w, h, d):
        return centre + wdir * w + hdir * h + ndir * (d - 0.9 * w * w)

    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    front = [bm.verts.new(at(w, h, 0.012)) for w, h in ring]
    back = [bm.verts.new(at(w, h, -0.012)) for w, h in ring]
    cf = bm.verts.new(at(0, 0, 0.012))
    cb = bm.verts.new(at(0, 0, -0.012))
    n = len(ring)
    uv = lambda w, h: ((w + 0.25) / 0.5, (h + 0.36) / 0.70)
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((front[i], front[j], cf))
        for loop, (w, h) in zip(f.loops, (ring[i], ring[j], (0, 0))):
            loop[uvl].uv = uv(w, h)
        f = bm.faces.new((back[j], back[i], cb))
        for loop, (w, h) in zip(f.loops, (ring[j], ring[i], (0, 0))):
            loop[uvl].uv = uv(w, h)
        f = bm.faces.new((front[j], front[i], back[i], back[j]))
        for loop in f.loops:
            loop[uvl].uv = (0.02, 0.5)
    face = to_object(bm, "shield_face", "shield")
    rim = loft("shield_rim", [at(w, h, 0.0) for w, h in ring + ring[:1]], [(0.014, 0.018)] * (n + 1),
               segs=6, caps=(False, False), part="steel")
    boss = sphere("shield_boss", at(0, 0.02, 0.012), (0.07, 0.07, 0.07), "steel", cut_z=0.0)
    # the boss is a dome facing out: turn it from +Z onto the shield's normal
    rot = Vector((0, 0, 1)).rotation_difference(ndir).to_matrix().to_4x4()
    c = at(0, 0.02, 0.012)
    boss.data.transform(Matrix.Translation(c) @ rot @ Matrix.Translation(-c))
    out = [face, rim, boss]
    for p in out:
        p["bone"] = "shield"
    return out


# ------------------------------------------------------------ the rig ----

def rig_spec():
    b = [("root", None, V(0, 0, 0), V(0, 0.3, 0)),
         ("horse_body", "root", V(0, -0.55, 1.30), V(0, 0.45, 1.36)),
         ("neck_1", "horse_body", V(0, 0.50, 1.42), V(0, 0.78, 1.71)),
         ("neck_2", "neck_1", V(0, 0.78, 1.71), V(0, 0.99, 1.97)),
         ("head_h", "neck_2", V(0, 0.99, 1.97), V(0, 1.35, 1.47)),
         ("tail_1", "horse_body", V(0, -0.84, 1.46), V(0, -0.97, 1.28)),
         ("tail_2", "tail_1", V(0, -0.97, 1.28), V(0, -1.01, 0.95)),
         ("tail_3", "tail_2", V(0, -1.01, 0.95), V(0, -0.97, 0.58))]
    for s, n in ((1, "r"), (-1, "l")):
        fx, hx = s * FORE_X, s * HIND_X
        b += [("fore_upper_" + n, "horse_body", V(fx, 0.58, 1.22), V(fx, 0.62, 0.58)),
              ("fore_lower_" + n, "fore_upper_" + n, V(fx, 0.62, 0.58), V(fx, 0.645, 0.22)),
              ("fore_hoof_" + n, "fore_lower_" + n, V(fx, 0.645, 0.22), V(fx, 0.69, 0.02)),
              ("hind_upper_" + n, "horse_body", V(hx, -0.50, 1.26), V(hx, -0.47, 0.88)),
              ("hind_gaskin_" + n, "hind_upper_" + n, V(hx, -0.47, 0.88), V(hx, -0.62, 0.52)),
              ("hind_lower_" + n, "hind_gaskin_" + n, V(hx, -0.62, 0.52), V(hx, -0.585, 0.22)),
              ("hind_hoof_" + n, "hind_lower_" + n, V(hx, -0.585, 0.22), V(hx, -0.555, 0.02))]
    b += [("hips", "horse_body", V(0, 0, 1.66), V(0, 0, 1.86)),
          ("spine", "hips", V(0, 0, 1.86), V(0, 0.015, 2.02)),
          ("chest", "spine", V(0, 0.015, 2.02), V(0, 0, 2.24)),
          ("neck", "chest", V(0, 0, 2.24), V(0, 0.005, 2.32)),
          ("head", "neck", V(0, 0.005, 2.32), V(0, 0, 2.62))]
    for s, n in ((1, "r"), (-1, "l")):
        arm = ARM_R if s > 0 else ARM_L
        hand = HAND_R if s > 0 else HAND_L
        b += [("clavicle_" + n, "chest", V(s * 0.03, 0, 2.20), V(*arm[0][:3])),
              ("upperarm_" + n, "clavicle_" + n, V(*arm[0][:3]), V(*arm[2][:3])),
              ("forearm_" + n, "upperarm_" + n, V(*arm[2][:3]), V(*hand)),
              ("hand_" + n, "forearm_" + n, V(*hand), V(*hand) + Vector((0, 0.08, 0))),
              ("thigh_" + n, "hips", V(s * LEG[0][0], *LEG[0][1:3]), V(s * LEG[2][0], *LEG[2][1:3])),
              ("shin_" + n, "thigh_" + n, V(s * LEG[2][0], *LEG[2][1:3]), V(s * LEG[5][0], *LEG[5][1:3])),
              ("foot_" + n, "shin_" + n, V(s * LEG[5][0], *LEG[5][1:3]), V(s * LEG[8][0], *LEG[8][1:3]))]
    b += [("lance", "hand_r", V(LANCE_X, LANCE_Y, 1.98), V(LANCE_X, LANCE_Y, 2.30)),
          ("shield", "forearm_l", V(-0.325, 0.25, 1.78), V(-0.325, 0.25, 1.98))]
    return b


HORSE_BONES = lambda arm: {b.name for b in arm.data.bones if b.name.startswith(
    ("horse_", "neck_", "head_h", "tail_", "fore_", "hind_"))}
RIDER_BONES = lambda arm: {b.name for b in arm.data.bones if b.name in (
    "hips", "spine", "chest", "neck", "head") or b.name.startswith(
    ("clavicle_", "upperarm_", "forearm_", "hand_", "thigh_", "shin_", "foot_"))}


def build_rig():
    arm_data = bpy.data.armatures.new(NAME + "_rig")
    arm = link(bpy.data.objects.new(NAME + "_rig", arm_data))
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, parent, head, tail in rig_spec():
        e = arm_data.edit_bones.new(name)
        e.head, e.tail, e.roll = head, tail, 0.0
        if parent:
            e.parent = made[parent]
            e.use_connect = (made[parent].tail - e.head).length < 1e-6
        made[name] = e
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def heat(ob, arm, bones):
    """Bone heat over `bones` only (the others stop deforming for the solve),
    falling back to weighting by distance to those bones' segments."""
    keep = {b.name: b.use_deform for b in arm.data.bones}
    for b in arm.data.bones:
        b.use_deform = b.name in bones
    activate(arm)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    for o in (ob,):
        o.select_set(True)
    arm.select_set(True)
    how = "heat"
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    except RuntimeError as exc:
        log("heat refused on %s: %s" % (ob.name, exc))
    for b in arm.data.bones:
        b.use_deform = keep[b.name]
    bare = bare_share(ob, bones)
    if bare > 0.01:
        log("heat left %.1f%% of %s bare — by distance" % (bare * 100, ob.name))
        by_distance(ob, arm, bones)
        how = "distance"
    for m in list(ob.modifiers):
        if m.type == "ARMATURE":
            ob.modifiers.remove(m)
    ob.parent = None
    return how


def bare_share(ob, bones):
    idx = {g.index: g.name for g in ob.vertex_groups}
    bare = sum(1 for v in ob.data.vertices
               if not any(g.weight > 1e-4 and idx.get(g.group) in bones for g in v.groups))
    return bare / max(1, len(ob.data.vertices))


def by_distance(ob, arm, bones, power=5.0, k=3):
    import numpy as np
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
    order = np.argsort(d, axis=0)[:k]
    w = 1.0 / np.power(np.take_along_axis(d, order, axis=0) + 1e-4, power)
    w /= w.sum(axis=0, keepdims=True)
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    groups = {name: ob.vertex_groups.new(name=name) for name, _, _ in segs}
    for slot in range(k):
        for vi in range(n):
            if w[slot, vi] > 1e-3:
                groups[segs[order[slot, vi]][0]].add([vi], float(w[slot, vi]), "ADD")


def rigid(ob, bone):
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    ob.vertex_groups.new(name=bone).add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")


def copy_weights(ob, src):
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    m = ob.modifiers.new("copy", "DATA_TRANSFER")
    m.object = src
    m.use_vert_data = True
    m.data_types_verts = {"VGROUP_WEIGHTS"}
    m.vert_mapping = "POLYINTERP_NEAREST"
    m.layers_vgroup_select_src = "ALL"
    m.layers_vgroup_select_dst = "NAME"
    activate(ob)
    bpy.ops.object.datalayout_transfer(modifier=m.name)
    bpy.ops.object.modifier_apply(modifier=m.name)


# ---------------------------------------------------------- the atlas ----

def paint_atlas():
    import numpy as np
    rng = np.random.default_rng(20260925)

    def up(a, h, w):
        ys = np.linspace(0, a.shape[0] - 1, h)
        xs = np.linspace(0, a.shape[1] - 1, w)
        y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
        y1, x1 = np.minimum(y0 + 1, a.shape[0] - 1), np.minimum(x0 + 1, a.shape[1] - 1)
        fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
        return (a[y0][:, x0] * (1 - fy) * (1 - fx) + a[y1][:, x0] * fy * (1 - fx)
                + a[y0][:, x1] * (1 - fy) * fx + a[y1][:, x1] * fy * fx)

    def fbm(h, w, base=4, octaves=5, stretch=(1, 1)):
        out = np.zeros((h, w))
        amp, tot = 1.0, 0.0
        for o in range(octaves):
            n = base * 2 ** o
            out += up(rng.random((max(2, n // stretch[0]), max(2, n // stretch[1]))), h, w) * amp
            tot += amp
            amp *= 0.55
        return out / tot - 0.5

    col = np.zeros((ATLAS, ATLAS, 3))
    mr = np.zeros((ATLAS, ATLAS, 3))
    mr[..., 0] = 1.0
    cell = ATLAS // 4

    def fill(key, rgb, rough, metal, fn=None):
        u0, v0, du, dv = TILES[key]
        h, w = dv * cell, du * cell
        c = np.ones((h, w, 3)) * np.array(rgb, float)
        if fn is not None:
            c = fn(c, h, w)
        col[v0 * cell:v0 * cell + h, u0 * cell:u0 * cell + w] = np.clip(c, 0, 255)
        r = rough + fbm(h, w, 6, 3) * 0.12
        mr[v0 * cell:v0 * cell + h, u0 * cell:u0 * cell + w, 1] = np.clip(r, 0.05, 1) * 255
        mr[v0 * cell:v0 * cell + h, u0 * cell:u0 * cell + w, 2] = metal * 255

    def coat(c, h, w):
        # dapples: pale rings round dark hearts (Worley), fine hair over all
        pts = rng.random((260, 2)) * [h, w]
        yy, xx = np.mgrid[0:h, 0:w]
        dmin = np.full((h, w), 1e9)
        for py, px in pts:
            dy = np.minimum(abs(yy - py), h - abs(yy - py))
            dx = np.minimum(abs(xx - px), w - abs(xx - px))
            dmin = np.minimum(dmin, np.hypot(dy, dx))
        r = 30.0
        t = np.clip((dmin / r - 0.30) / 0.45, 0, 1)
        spot = 1 - t * t * (3 - 2 * t)             # a pale round spot, soft at its edge
        c += spot[..., None] * np.array([14, 14, 16])
        c += fbm(h, w, 8, 4)[..., None] * 18
        c += fbm(h, w, 64, 2, (1, 8))[..., None] * 10
        return c

    def brushed(c, h, w):
        return c + fbm(h, w, 6, 4)[..., None] * 26 + fbm(h, w, 96, 2, (1, 16))[..., None] * 18

    def grain(c, h, w):
        return c + fbm(h, w, 10, 5)[..., None] * 30 + (rng.random((h, w)) - 0.5)[..., None] * 10

    def wool(c, h, w):
        yy, xx = np.mgrid[0:h, 0:w]
        weave = (np.sin(xx * 1.4) * np.sin(yy * 1.4))[..., None] * 5
        return c + weave + fbm(h, w, 8, 4)[..., None] * 22

    def streaks(c, h, w):
        return c + fbm(h, w, 64, 3, (1, 12))[..., None] * 34 + fbm(h, w, 4, 3)[..., None] * 10

    def field(c, h, w):
        uu = (np.arange(w) + 0.5) / w
        # the shield's planar UV spans 0.5 of width around its middle
        pale = (abs(uu - 0.5) < 0.062)[None, :, None]
        c = np.where(pale, np.array([226, 222, 206], float), np.array([34, 112, 58], float))
        return c + fbm(h, w, 6, 4)[..., None] * 18

    fill("coat", (40, 40, 44), 0.62, 0.0, coat)
    fill("steel", (128, 132, 138), 0.22, 1.0, brushed)
    fill("leather", (96, 54, 28), 0.62, 0.0, grain)
    fill("cloth", (30, 82, 44), 0.92, 0.0, wool)
    fill("brass", (184, 142, 62), 0.36, 1.0, grain)
    fill("wood", (126, 84, 48), 0.70, 0.0, streaks)
    fill("hair", (20, 20, 22), 0.55, 0.0, streaks)
    fill("hoof", (48, 45, 42), 0.70, 0.0, grain)
    fill("shield", (34, 112, 58), 0.50, 0.0, field)

    def image(name, arr, colour):
        img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
        img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        rgba = np.concatenate([arr / 255.0, np.ones((ATLAS, ATLAS, 1))], axis=2).astype(np.float32)
        img.pixels.foreach_set(rgba.ravel())
        img.pack()
        return img
    return image(NAME + "_atlas", col, True), image(NAME + "_atlas_mr", mr, False)


def atlas_material(col, mr):
    mat = bpy.data.materials.new(NAME + "_atlas")
    mat.use_nodes = True
    mat.use_backface_culling = True     # every piece is closed or solidified: one side is enough
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = col
    tm = nt.nodes.new("ShaderNodeTexImage")
    tm.image = mr
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def into_tile(ob):
    u0, v0, du, dv = TILES[ob["part"]]
    uv = ob.data.uv_layers.active.data
    us = [d.uv[0] for d in uv]
    vs = [d.uv[1] for d in uv]
    lo_u, hi_u, lo_v, hi_v = min(us), max(us), min(vs), max(vs)
    inset = INSET_PX / ATLAS
    for d in uv:
        nu = (d.uv[0] - lo_u) / max(hi_u - lo_u, 1e-6)
        nv = (d.uv[1] - lo_v) / max(hi_v - lo_v, 1e-6)
        d.uv = (u0 / 4 + inset + nu * (du / 4 - 2 * inset), v0 / 4 + inset + nv * (dv / 4 - 2 * inset))


# ------------------------------------------------------------ actions ----

def _merge(*poses):
    """Poses joined bone by bone: a bone in several has its turns chained."""
    out = {}
    for pose in poses:
        for bone, entry in pose.items():
            have = out.setdefault(bone, {})
            if "rot" in entry:
                have["rot"] = list(have.get("rot", [])) + list(entry["rot"])
            if "loc" in entry:
                have["loc"] = entry["loc"]
    return out


def actions(arm):
    neutral = {}
    # GARRISON stands ON GUARD (owner 2026-09-27: 骑士把盾牌竖起挡在身前，长矛改为
    # 指向向前，马匹也轻微晃动一下脖颈): the shield raised square in front of him,
    # the lance couched forward as in ATTACK's surge but a touch higher, held
    # through every key; the horse's neck sways gently side to side.
    guard = {"lance": {"rot": [("x", -72.0)]},
             "upperarm_r": {"rot": [("x", -18.0)]}, "forearm_r": {"rot": [("x", 8.0)]},
             "upperarm_l": {"rot": [("x", 30.0), ("z", -40.0)]},
             "forearm_l": {"rot": [("z", -75.0)]}, "shield": {"rot": [("z", 20.0)]}}

    def sway(k):
        return {"neck_1": {"rot": [("z", 5.0 * k)]}, "neck_2": {"rot": [("z", 4.0 * k)]},
                "head_h": {"rot": [("z", 6.0 * k)]}}

    garrison = [
        (1, _merge(guard)),
        (31, _merge(guard, sway(1.0), {"horse_body": {"rot": [("x", 0.8)]}, "neck_1": {"rot": [("x", -3.0)]},
              "neck_2": {"rot": [("x", -2.0)]}, "head_h": {"rot": [("x", 5.0)]},
              "tail_1": {"rot": [("y", 6.0)]}, "tail_2": {"rot": [("y", 8.0)]},
              "chest": {"rot": [("x", -1.5)]}, "head": {"rot": [("z", 8.0)]}})),
        (61, _merge(guard, {"neck_1": {"rot": [("x", 2.0)]}, "head_h": {"rot": [("x", -4.0)]},
              "tail_1": {"rot": [("y", -5.0)]}, "tail_2": {"rot": [("y", -7.0)]},
              "hind_upper_l": {"rot": [("x", 3.0)]}, "hind_lower_l": {"rot": [("x", -8.0)]},
              "hind_hoof_l": {"rot": [("x", -10.0)]},
              "hips": {"rot": [("x", 1.0)]}, "head": {"rot": [("z", -4.0), ("x", -3.0)]}})),
        (91, _merge(guard, sway(-1.0), {"horse_body": {"rot": [("x", -0.6)]}, "neck_2": {"rot": [("x", 2.5)]},
              "head_h": {"rot": [("x", 3.0)]}, "tail_1": {"rot": [("y", 5.0)]},
              "chest": {"rot": [("x", 1.2)]}, "head": {"rot": [("z", -9.0)]}})),
        (121, _merge(guard)),
    ]

    # MARCH is BIG (owner 2026-09-27: 行进动作设计幅度再大一点，人和马都要有动作):
    # a long stride, a head that nods into every step, and a rider who rocks
    # with the horse — seat, back, shoulders and helmet — rather than riding
    # it like a statue. Read at map size, a small walk is no walk at all.
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

    legs = [("hind", "l", 0.00), ("fore", "l", 0.25), ("hind", "r", 0.50), ("fore", "r", 0.75)]
    march = []
    frames, beats = 49, 16
    for i in range(beats + 1):
        u = i / beats
        pose = horse_step(u)
        for kind, n, ph in legs:
            a, b = gait(u + ph)
            if kind == "fore":
                pose["fore_upper_" + n] = {"rot": [("x", a * 24.0)]}
                pose["fore_lower_" + n] = {"rot": [("x", b * 34.0)]}
                pose["fore_hoof_" + n] = {"rot": [("x", b * 18.0)]}
            else:
                pose["hind_upper_" + n] = {"rot": [("x", a * 20.0)]}
                pose["hind_gaskin_" + n] = {"rot": [("x", -b * 12.0)]}
                pose["hind_lower_" + n] = {"rot": [("x", b * 24.0)]}
                pose["hind_hoof_" + n] = {"rot": [("x", b * 18.0)]}
        march.append((1 + round(u * (frames - 1)), pose))

    def charge(body, fore_u, fore_l, lance_x, arm_r, lean, surge, neck):
        pose = {"root": {"loc": (0, surge, 0)},
                "horse_body": {"rot": [("x", body)]},
                "neck_1": {"rot": [("x", neck)]}, "head_h": {"rot": [("x", -neck * 0.6)]},
                "tail_1": {"rot": [("x", -body * 0.8)]},
                "lance": {"rot": [("x", lance_x)]},
                "upperarm_r": {"rot": [("x", arm_r)]}, "forearm_r": {"rot": [("x", -arm_r * 0.5)]},
                "hips": {"rot": [("x", lean * 0.3)]}, "spine": {"rot": [("x", lean * 0.4)]},
                "chest": {"rot": [("x", lean * 0.3)]}, "shield": {"rot": [("z", lean * 0.3)]}}
        for n in ("r", "l"):
            pose["hind_upper_" + n] = {"rot": [("x", -body)]}
            pose["fore_upper_" + n] = {"rot": [("x", fore_u)]}
            pose["fore_lower_" + n] = {"rot": [("x", fore_l)]}
            pose["fore_hoof_" + n] = {"rot": [("x", fore_l * 0.5)]}
        return pose

    attack = [
        (1, neutral),
        (14, charge(-3.0, 4.0, -6.0, -35.0, -10.0, 4.0, -0.04, -3.0)),      # gather, the lance dips
        (30, charge(14.0, 38.0, -70.0, -86.0, -22.0, -14.0, 0.10, 8.0)),    # the surge, lance couched
        (44, charge(8.0, 20.0, -40.0, -88.0, -24.0, -16.0, 0.30, 5.0)),     # the strike
        (60, charge(2.0, 4.0, -8.0, -60.0, -12.0, -6.0, 0.12, 1.0)),
        (76, neutral),
    ]
    # The ACTIONS are named cavalry_*, unique in any file (a live file may hold
    # the infantry's "ATTACK"); the glTF clips take the NLA TRACKS' names.
    return [make_action(arm, NAME + "_GARRISON", garrison), make_action(arm, NAME + "_MARCH", march),
            make_action(arm, NAME + "_ATTACK", attack)]


def export_glb(objs, path):
    """make_units.export, but one glTF animation per NLA TRACK of this rig:
    ACTIONS mode takes EVERY action in the file whose bones match, and a
    live file's infantry ATTACK (hips, spine, chest...) matches the rider."""
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_yup=True, export_apply=False,
        export_image_format="JPEG", export_jpeg_quality=92,
        export_animations=True, export_animation_mode="NLA_TRACKS",
        export_frame_range=False, export_optimize_animation_size=False,
        export_anim_single_armature=True)


# -------------------------------------------------------------- build ----

def build(write=True):
    fresh_scene()
    coat, tail, horse_extra = horse()
    harness, plates = rider()
    pieces = tack() + plates + lance() + shield()
    arm = build_rig()
    how = {"coat": heat(coat, arm, HORSE_BONES(arm)),
           "harness": heat(harness, arm, RIDER_BONES(arm)),
           "tail": heat(tail, arm, {"tail_1", "tail_2", "tail_3", "horse_body"})}
    src = {"coat": coat, "harness": harness}
    for p in horse_extra + pieces:
        if p is tail:
            continue
        if "bone" in p:
            rigid(p, p["bone"])
        else:
            copy_weights(p, src[p.get("copy", "coat")])
    everything = [coat, harness] + horse_extra + pieces
    for p in everything:
        if not p.data.uv_layers:
            unwrap(p)
        into_tile(p)
        activate(p)
        if p["part"] == "hair":             # the tail and the mane are soft all over
            bpy.ops.object.shade_smooth()
        elif p["part"] != "coat":
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50))
    col, mr = paint_atlas()
    mat = atlas_material(col, mr)
    activate(coat)
    for p in everything[1:]:
        p.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = NAME
    ob.data.name = NAME
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for poly in ob.data.polygons:
        poly.material_index = 0
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    ob.parent = arm

    acts = actions(arm)
    stash(arm, acts)
    for track in arm.animation_data.nla_tracks:
        track.name = track.name[len(NAME) + 1:]
    tris = tri_count(ob)
    log("cavalry: %d tris, %d bones, weights %s" % (tris, len(arm.data.bones), how))
    out_dir = os.environ.get("CAV_OUT", OUT)
    if write:
        path = glb_path(out_dir, NAME)
        export_glb([arm, ob], path)
        if out_dir != OUT:          # a trial build: the manifest is the shipped model's
            log("wrote " + path)
            return arm, ob
        mpath = os.path.join(OUT, "units3d.json")
        manifest = json.load(open(mpath))
        top = max(v.co.z for v in ob.data.vertices)
        manifest[NAME] = {
            "label": "Knight", "kind": "mounted", "height_m": round(top, 3),
            "source": "hand-modelled (tools/units3d/model_cavalry.py)",
            "tris": tris, "bones": len(arm.data.bones), "weights": how,
            "actions": {a.name[len(NAME) + 1:]: [int(a.frame_range[0]), int(a.frame_range[1])] for a in acts},
            "fps": FPS,
        }
        with open(mpath, "w") as f:
            json.dump(manifest, f, indent=1, sort_keys=True)
            f.write("\n")
        log("wrote " + path)
    return arm, ob


if __name__ in ("__main__", "live"):
    build()
