"""Generate the 3D map's house meshes (spec 2026-09-20 §2, remade 2026-09-21
for the owner's "more accomplished, on-palette" ruling and the 400 m closest
zoom).

  blender -b --factory-startup --python tools/map3d/make_houses.py

Reads data/map3d_houses.csv and writes one glTF per type into
assets/map3d_houses/, plus houses.json. Every mesh stands ON its origin
(min y = 0, centred on its footprint) and faces +Z, because
Map3DLayerHouses places it with a yaw and sinks it by map3d_house_sink_m —
a mesh that carries its own base plate or offset would defeat both.

Low poly on purpose: at the owner's 400 m closest zoom (2026-09-21 ruling,
was 800 m) a house is 17-35 px, where the silhouette, the eave shadow and
the roof colour are what read — never windows or doors.

Each of the 14 types gets its OWN plan (a rectangle, an L, a T, a nave with
a crossing) built from a small kit of primitives — box, a ridged roof prism
(gable when its ridge runs the full length, hipped when it does not), a
single-slope "catslide" wedge for lean-tos, and a square pyramid roof for
towers and spires — so a cluster of different types never repeats one
shape. Landmarks (chapel, church, church_tower, palace) are given real
height and a distinctive top (a bellcote, a crossing tower, a tapered
spire, twin corner towers) so they still dominate their settlement at the
closer zoom.
"""
import csv
import json
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TABLE = os.path.join(ROOT, "data", "map3d_houses.csv")
OUT = os.path.join(ROOT, "assets", "map3d_houses")
PALETTE = os.path.join(ROOT, "data", "terrain_palette.csv")


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb_linear(s):
    """The palette's hexes are sRGB (project convention); Blender's
    Principled BSDF Base Color input is linear, so every colour handed to
    it must be converted or it renders lifted (measured: #C8BCA6 sRGB
    (0.784, 0.737, 0.651) came back through Godot's import as
    (0.898, 0.874, 0.827) — an almost-white wall)."""
    return tuple(srgb_to_linear(c) for c in hex_rgb(s))


def load_palette():
    """Values come back LINEAR — the only place a palette hex reaches the
    Principled BSDF (via material() below), so the conversion happens once,
    here, rather than at each call site."""
    out = {}
    with open(PALETTE) as f:
        for r in csv.DictReader(f):
            key = r.get("key") or r.get("name")
            col = r.get("color") or r.get("colour") or r.get("hex")
            if key and col and col.startswith("#"):
                out[key] = hex_rgb_linear(col)
    return out


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.2
    return mat


# ---------------------------------------------------------------- primitives

def box(name, w, d, h, z=0.0):
    # primitive_cube_add(size=1.0) already spans +/-0.5 (a full 1.0 edge), so
    # the scale that makes it w x d x h is (w, d, h), not their halves — the
    # w/2 form silently produced a half-size box floating off the ground.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, z + h / 2))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (w, d, h)
    bpy.ops.object.transform_apply(scale=True)
    return ob


def _mesh_object(name, verts, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return ob


def prism_roof(name, w, d, h, z, overhang=0.4, ridge_frac=1.0, axis="y"):
    """A roof over a w x d wall, ridge line rising to height h above z. With
    `axis` "y" the ridge runs the length of d (gable ends face +-y); "x"
    runs it the length of w (gable ends face +-x) — the caller picks
    whichever of w/d is the building's longer dimension, so the ridge
    always sits the way a real roof would. `ridge_frac` < 1 draws the ridge
    shorter than the base, hipping the ends in (0 is a full pyramid hip);
    at 1 it is a plain gable, the silhouette that separates a house from a
    box at 17-35 px."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    base = [(-w2, -d2, z), (w2, -d2, z), (w2, d2, z), (-w2, d2, z)]
    if axis == "y":
        rd = d2 * ridge_frac
        verts = base + [(0.0, -rd, z + h), (0.0, rd, z + h)]
        faces = [(0, 1, 4), (2, 3, 5), (1, 2, 5, 4), (3, 0, 4, 5), (0, 3, 2, 1)]
    else:
        rw = w2 * ridge_frac
        verts = base + [(-rw, 0.0, z + h), (rw, 0.0, z + h)]
        faces = [(3, 0, 4), (1, 2, 5), (0, 1, 5, 4), (2, 3, 4, 5), (0, 3, 2, 1)]
    ob = _mesh_object(name, verts, faces)
    return ob


def pyramid_roof(name, size, h, z, overhang=0.3):
    """A square hipped roof rising to a single apex — a tower cap or a
    spire's stage."""
    s2 = size / 2 + overhang
    verts = [(-s2, -s2, z), (s2, -s2, z), (s2, s2, z), (-s2, s2, z), (0, 0, z + h)]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)]
    return _mesh_object(name, verts, faces)


def shed_roof(name, w, d, h, z, overhang=0.3, axis="y", sign=1):
    """A single-slope "catslide" solid: flat at z on the low side, rising to
    z + h on the high side, closed on every face so it never exposes a bare
    flat wall-coloured top (the cause of cottage_b's lean-to rendering
    white — it had no roof of its own to catch the light at an angle).
    `axis` picks which pair of edges rises; `sign` picks which one is high."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    if axis == "y":
        lo_y, hi_y = (-d2, d2) if sign > 0 else (d2, -d2)
        v0, v1 = (-w2, lo_y, z), (w2, lo_y, z)
        v2, v3 = (w2, hi_y, z), (-w2, hi_y, z)
        v4, v5 = (w2, hi_y, z + h), (-w2, hi_y, z + h)
    else:
        lo_x, hi_x = (-w2, w2) if sign > 0 else (w2, -w2)
        v0, v1 = (lo_x, -d2, z), (lo_x, d2, z)
        v2, v3 = (hi_x, d2, z), (hi_x, -d2, z)
        v4, v5 = (hi_x, d2, z + h), (hi_x, -d2, z + h)
    verts = [v0, v1, v2, v3, v4, v5]
    faces = [(0, 1, 2, 3), (3, 2, 4, 5), (0, 1, 4, 5), (0, 3, 5), (1, 2, 4)]
    return _mesh_object(name, verts, faces)


def chimney(name, x, y, z, h, w=0.55):
    ob = box(name, w, w, h, z)
    ob.location.x = x
    ob.location.y = y
    return ob


def move(ob, x=0.0, y=0.0):
    ob.location.x += x
    ob.location.y += y
    return ob


def ridge_trim(name, w, d, ridge_frac, h, z, axis="y"):
    """A thin cresting strip along a roof's own ridge — cheap (one box) but
    it draws the ridge as a hard line rather than a soft meeting of two
    planes, and it takes the roof's own colour, not the wall's."""
    if axis == "y":
        return box(name, 0.32, d * ridge_frac + 0.3, 0.26, z + h - 0.06)
    return box(name, w * ridge_frac + 0.3, 0.32, 0.26, z + h - 0.06)


def buttress(name, x, y, w, d, h, z=0.0):
    """A thin corner pier standing slightly proud of a tower's own wall —
    the masonry accent that keeps a landmark's tower from reading as a
    plain box."""
    ob = box(name, w, d, h, z)
    ob.location.x = x
    ob.location.y = y
    return ob


def tower_buttresses(walls, cx, cy, tower_w, h, inset=0.35, w=0.5, name_prefix="but"):
    """Four corner piers around a square tower centred at (cx, cy)."""
    half = tower_w / 2 - inset
    for i, (sx, sy) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        walls.append(buttress("%s%d" % (name_prefix, i), cx + sx * half, cy + sy * half,
                               w, w, h * 0.82))


# --------------------------------------------------------------- 14 builders
# Every builder returns (walls, roofs); `fp`/`ht` are the CSV's declared
# footprint (longest side) and total height, used as the seed for the
# type's own proportions — join_and_normalise then fits the built plan to
# those numbers exactly (see its docstring for why that is a fix, not just
# a convenience).

def build_cottage_a(fp, ht):
    """A one-room thatched cottage: a plain steep gable, one off-centre
    chimney breaking the ridge, and a small porch canopy over the door.
    The commonest building, so the plainest."""
    wall_h = ht * 0.58
    roof_h = ht - wall_h
    w, d = fp * 0.86, fp * 0.60
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.45, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    walls.append(chimney("chimney", w * 0.24, d * 0.30, wall_h * 0.55, ht * 0.30))
    pw, pd = w * 0.30, d * 0.32
    porch_h = wall_h * 0.62
    porch = shed_roof("porch", pw, pd, wall_h - porch_h + 0.3, porch_h, overhang=0.15, axis="y", sign=-1)
    move(porch, y=-d * 0.5 - pd * 0.3)
    roofs.append(porch)
    return walls, roofs


def build_cottage_b(fp, ht):
    """A thatched cottage with an L-shaped lean-to: a genuine second wing,
    roofed with its own catslide climbing into the main gable — the fix for
    the lean-to that used to be a bare, unroofed box."""
    wall_h = ht * 0.58
    roof_h = ht - wall_h
    w, d = fp * 0.76, fp * 0.56
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.4, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    lw, ld, lh = fp * 0.46, d * 0.82, wall_h * 0.60
    lean = box("lean", lw, ld, lh)
    move(lean, x=w * 0.5 + lw * 0.5 - 0.2)
    walls.append(lean)
    rise = (wall_h - lh) + (ht - wall_h) * 0.4
    lroof = shed_roof("lean_roof", lw, ld, rise, lh, overhang=0.3, axis="x", sign=-1)
    move(lroof, x=lean.location.x)
    roofs.append(lroof)
    walls.append(chimney("chimney", -w * 0.28, -d * 0.25, wall_h * 0.6, ht * 0.26))
    return walls, roofs


def build_cottage_c(fp, ht):
    """The smallest cottage: near-square, fully hipped roof (no gable
    walls at all) — the shape that reads as a hut beside cottage_a's and
    cottage_b's gables."""
    wall_h = ht * 0.56
    roof_h = ht - wall_h
    w, d = fp * 0.92, fp * 0.78
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.4, ridge_frac=0.3, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 0.3, roof_h, wall_h, axis="x"))
    walls.append(chimney("chimney", -w * 0.22, d * 0.20, wall_h * 0.6, ht * 0.24))
    return walls, roofs


def build_townhouse_a(fp, ht):
    """A two-storey tiled house, narrow gable-end to the street, a tall
    chimney at the ridge's near end."""
    wall_h = ht * 0.62
    roof_h = ht - wall_h
    w, d = fp * 0.62, fp * 0.78
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.35)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="y"))
    walls.append(chimney("chimney", w * 0.30, -d * 0.34, ht * 0.84, ht * 0.24))
    return walls, roofs


def build_townhouse_b(fp, ht):
    """A tiled house with a jettied upper floor overhanging the ground
    floor on every side, and a half-hipped roof over the jetty."""
    wall_h = ht * 0.55
    ground_h = wall_h * 0.60
    w, d = fp * 0.58, fp * 0.74
    walls = [box("ground", w, d, ground_h)]
    jw, jd, jetty_h = w * 1.16, d * 1.05, wall_h * 0.4
    jetty = box("jetty", jw, jd, jetty_h, ground_h)
    walls.append(jetty)
    roof_h = ht - wall_h
    roofs = [prism_roof("roof", jw, jd, roof_h, wall_h, overhang=0.4, ridge_frac=0.55)]
    roofs.append(ridge_trim("ridge", jw, jd, 0.55, roof_h, wall_h, axis="y"))
    walls.append(chimney("chimney", -jw * 0.26, jd * 0.28, ht * 0.8, ht * 0.24))
    return walls, roofs


def build_townhouse_c(fp, ht):
    """The tall merchant's house: steepest, narrowest townhouse, with an
    attic dormer breaking one roof slope and an off-centre chimney — the
    tallest of the three, so the roofline needs the most incident."""
    wall_h = ht * 0.66
    roof_h = ht - wall_h
    w, d = fp * 0.52, fp * 0.80
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.3)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="y"))
    dw, dd, dh = w * 0.34, d * 0.22, ht * 0.13
    dz = wall_h + (ht - wall_h) * 0.3
    dormer = box("dormer", dw, dd, dh, dz)
    move(dormer, y=-d * 0.16)
    walls.append(dormer)
    droof = prism_roof("dormer_roof", dw, dd, dh * 0.6, dz + dh, overhang=0.12)
    move(droof, y=-d * 0.16)
    roofs.append(droof)
    walls.append(chimney("chimney", -w * 0.30, d * 0.32, ht * 0.86, ht * 0.20))
    return walls, roofs


def build_longhouse(fp, ht):
    """The genuinely long, low hall, its byre a perpendicular wing at one
    end (a T plan) under its own cross-gable, a half-hipped main roof."""
    wall_h = ht * 0.52
    roof_h = ht - wall_h
    w, d = fp * 0.94, fp * 0.20
    walls = [box("hall", w, d, wall_h)]
    roofs = [prism_roof("hall_roof", w, d, roof_h, wall_h, overhang=0.4, ridge_frac=0.75, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 0.75, roof_h, wall_h, axis="x"))
    bw, bd, bh = fp * 0.22, fp * 0.30, wall_h * 0.85
    byre = box("byre_wing", bw, bd, bh)
    move(byre, x=w * 0.5 - bw * 0.4, y=d * 0.5 + bd * 0.32)
    walls.append(byre)
    broof = prism_roof("byre_roof", bw, bd, (ht - wall_h) * 0.75, bh, overhang=0.35)
    move(broof, x=byre.location.x, y=byre.location.y)
    roofs.append(broof)
    walls.append(chimney("chimney", -w * 0.32, 0.0, wall_h * 0.6, ht * 0.2))
    return walls, roofs


def build_workshop(fp, ht):
    """A workshop with an open front: a squarish working block under a
    broad-ridged roof, and a lower, wall-less canopy bay projecting out
    front for the open working face."""
    wall_h = ht * 0.60
    roof_h = ht - wall_h
    w, d = fp * 0.66, fp * 0.60
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.3, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    walls.append(chimney("chimney", w * 0.32, d * 0.30, wall_h * 0.6, ht * 0.24))
    cw, cd = w * 0.88, d * 0.55
    canopy_h = wall_h * 0.66
    canopy_rise = (wall_h - canopy_h) + 0.4
    canopy = shed_roof("canopy", cw, cd, canopy_rise, canopy_h, overhang=0.35, axis="y", sign=-1)
    move(canopy, y=-d * 0.5 - cd * 0.32)
    roofs.append(canopy)
    return walls, roofs


def build_barn(fp, ht):
    """Low and wide, a shallow-pitched gable (barns pitch far shallower
    than a cottage) and a little ridge cupola/vent breaking the roofline."""
    wall_h = ht * 0.48
    roof_h = ht - wall_h
    w, d = fp * 0.92, fp * 0.52
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.55, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    cw = w * 0.10
    cupola_z = ht * 0.84
    cupola = box("cupola", cw, cw, ht * 0.12, cupola_z)
    walls.append(cupola)
    roofs.append(pyramid_roof("cupola_roof", cw, ht * 0.10, cupola_z + ht * 0.12, overhang=0.08))
    return walls, roofs


def build_byre(fp, ht):
    """A low byre with an attached pen along one side (an L plan), the
    pen's own catslide roof lower than the byre's own gable."""
    wall_h = ht * 0.62
    roof_h = ht - wall_h
    w, d = fp * 0.82, fp * 0.52
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.5, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    pw, pd, ph = w * 0.5, d * 0.9, wall_h * 0.55
    pen = box("pen", pw, pd, ph)
    move(pen, y=d * 0.5 + pd * 0.34)
    walls.append(pen)
    proof = shed_roof("pen_roof", pw, pd, (wall_h - ph) + 0.3, ph, overhang=0.35, axis="y", sign=-1)
    move(proof, y=pen.location.y)
    roofs.append(proof)
    return walls, roofs


def build_chapel(fp, ht):
    """The village's landmark: a tall narrow nave and a thin bellcote
    screen wall rising clear of the ridge at one gable end, capped with its
    own small spire — the cheapest way to be unmistakably not a house."""
    nave_h = ht * 0.46
    w, d = fp * 0.48, fp * 0.86
    walls = [box("nave", w, d, nave_h)]
    roof_h = ht * 0.30
    roofs = [prism_roof("nave_roof", w, d, roof_h, nave_h, overhang=0.35)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, nave_h, axis="y"))
    bw, bd, bh = w * 0.55, 0.5, ht - (nave_h + roof_h * 0.55)
    bellcote = box("bellcote", bw, bd, bh, nave_h + roof_h * 0.55)
    move(bellcote, y=-d * 0.5 + 0.35)
    walls.append(bellcote)
    cap = pyramid_roof("bell_cap", bw * 0.85, ht * 0.09, nave_h + roof_h * 0.55 + bh, overhang=0.05)
    move(cap, y=bellcote.location.y)
    roofs.append(cap)
    return walls, roofs


def build_church(fp, ht):
    """A town's and a fort's landmark: a cruciform plan — nave, a
    perpendicular transept, and a crossing tower with a pyramidal cap at
    their meeting point — grander than the chapel, shorter than
    church_tower."""
    nave_h = ht * 0.40
    w, d = fp * 0.40, fp * 0.86
    walls = [box("nave", w, d, nave_h)]
    roofs = [prism_roof("nave_roof", w, d, ht * 0.22, nave_h, overhang=0.35)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, ht * 0.22, nave_h, axis="y"))
    tw, td = fp * 0.60, fp * 0.26
    transept_h = nave_h * 0.9
    walls.append(box("transept", tw, td, transept_h))
    roofs.append(prism_roof("transept_roof", tw, td, ht * 0.16, transept_h, overhang=0.3, axis="x"))
    tower_w = fp * 0.24
    tower_h = ht * 0.62
    walls.append(box("tower", tower_w, tower_w, tower_h))
    tower_buttresses(walls, 0.0, 0.0, tower_w, tower_h)
    roofs.append(pyramid_roof("tower_roof", tower_w, ht * 0.20, tower_h, overhang=0.12))
    return walls, roofs


def build_church_tower(fp, ht):
    """A city's landmark: a small nave beside a genuinely tall tower with a
    two-stage tapered spire — the silhouette that has to read over
    everything else at 17-35 px."""
    nave_h = ht * 0.20
    w, d = fp * 0.5, fp * 0.30
    walls = [box("nave", w, d, nave_h)]
    roofs = [prism_roof("nave_roof", w, d, nave_h * 0.6, nave_h, overhang=0.3, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, nave_h * 0.6, nave_h, axis="x"))
    tower_w = fp * 0.26
    tower_h = ht * 0.64
    tower = box("tower", tower_w, tower_w, tower_h)
    move(tower, x=-w * 0.5 - tower_w * 0.15)
    walls.append(tower)
    tower_buttresses(walls, tower.location.x, tower.location.y, tower_w, tower_h)
    spire1_h = ht * 0.11
    spire1 = pyramid_roof("spire1", tower_w, spire1_h, tower_h, overhang=0.12)
    move(spire1, x=tower.location.x)
    roofs.append(spire1)
    spire2_w = tower_w * 0.5
    spire2_h = ht - tower_h - spire1_h
    spire2 = pyramid_roof("spire2", spire2_w, spire2_h, tower_h + spire1_h, overhang=0.03)
    move(spire2, x=tower.location.x)
    roofs.append(spire2)
    return walls, roofs


def build_palace(fp, ht):
    """The capital's landmark: a broad hall with a pedimented portico
    projecting from the front and twin corner towers, each hipped — the
    widest, grandest plan of the fourteen."""
    w, d = fp * 0.80, fp * 0.40
    wall_h = ht * 0.5
    walls = [box("hall", w, d, wall_h)]
    roofs = [prism_roof("hall_roof", w, d, ht * 0.16, wall_h, overhang=0.55, axis="x")]
    roofs.append(ridge_trim("ridge", w, d, 1.0, ht * 0.16, wall_h, axis="x"))
    pw, pd, ph = w * 0.20, d * 0.55, wall_h * 0.86
    portico = box("portico", pw, pd, ph)
    move(portico, y=-d * 0.5 - pd * 0.4)
    walls.append(portico)
    proof = prism_roof("portico_roof", pw, pd, ht * 0.12, ph, overhang=0.22)
    move(proof, y=portico.location.y)
    roofs.append(proof)
    tower_w = d * 0.55
    tower_h = ht * 0.78
    for sx in (-1, 1):
        tw_ob = box("wing%d" % sx, tower_w, tower_w, tower_h)
        move(tw_ob, x=sx * w * 0.5)
        walls.append(tw_ob)
        tower_buttresses(walls, tw_ob.location.x, tw_ob.location.y, tower_w, tower_h,
                          name_prefix="but%d" % sx)
        cap = pyramid_roof("cap%d" % sx, tower_w, ht * 0.16, tower_h, overhang=0.15)
        move(cap, x=sx * w * 0.5)
        roofs.append(cap)
    return walls, roofs


BUILDERS = {
    "cottage_a": build_cottage_a,
    "cottage_b": build_cottage_b,
    "cottage_c": build_cottage_c,
    "townhouse_a": build_townhouse_a,
    "townhouse_b": build_townhouse_b,
    "townhouse_c": build_townhouse_c,
    "longhouse": build_longhouse,
    "workshop": build_workshop,
    "barn": build_barn,
    "byre": build_byre,
    "chapel": build_chapel,
    "church": build_church,
    "church_tower": build_church_tower,
    "palace": build_palace,
}


def build(type_name, fp, ht):
    """One house. `fp` is the footprint's longest side in metres, `ht` the
    total height including the roof."""
    fn = BUILDERS.get(type_name)
    if fn is None:
        raise SystemExit("make_houses: no builder for type %r" % type_name)
    return fn(fp, ht)


def join_and_normalise(name, objs, fp, ht):
    """One object at the origin, min z = 0, fit EXACTLY to its footprint
    and height. The two are scaled INDEPENDENTLY (xy together, z on its
    own) rather than uniformly by min(footprint_ratio, height_ratio):
    a uniform scale let the taller ratio win and left every mesh 12-25%
    narrower than its declared footprint (townhouse_c 8.50 m against an
    11.00 m claim), which is also what the bake's overlap spacing reads,
    so buildings sat as if up to a quarter wider than they really were."""
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Faces were authored without tracking outward winding by hand (a roof's
    # gable-end triangle vs. its hip-end triangle, a shed's five closing
    # faces) — Blender's own solver is more reliable than doing that by eye,
    # and it is a global, one-shot fix for the whole merged mesh.
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for v in ob.data.vertices:
        lo = Vector((min(lo[i], v.co[i]) for i in range(3)))
        hi = Vector((max(hi[i], v.co[i]) for i in range(3)))
    mid = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in ob.data.vertices:
        v.co -= mid
    span = max(hi.x - lo.x, hi.y - lo.y)
    tall = hi.z - lo.z
    s_xy = fp / span if span > 0 else 1.0
    s_z = ht / tall if tall > 0 else 1.0
    for v in ob.data.vertices:
        v.co.x *= s_xy
        v.co.y *= s_xy
        v.co.z *= s_z
    return ob


def export(ob, path):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                              use_selection=True, export_yup=True,
                              export_apply=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    palette = load_palette()
    wall_rgb = palette.get("house_wall", tuple(srgb_to_linear(c) for c in (0.78, 0.74, 0.65)))
    manifest = {}
    with open(TABLE) as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        t = r["type"]
        fp, ht = float(r["footprint_m"]), float(r["height_m"])
        clear()
        walls, roofs = build(t, fp, ht)
        wall_mat = material("wall", wall_rgb)
        roof_mat = material("roof", palette.get(r["roof"], tuple(srgb_to_linear(c) for c in (0.55, 0.35, 0.27))))
        for o in walls:
            o.data.materials.append(wall_mat)
        for o in roofs:
            o.data.materials.append(roof_mat)
        ob = join_and_normalise(t, walls + roofs, fp, ht)
        path = os.path.join(OUT, t + ".glb")
        export(ob, path)
        # len(polygons) is Blender's FACE count (a quad counts as 1), but the
        # glTF exporter triangulates on export — an n-vertex polygon becomes
        # n - 2 triangles, so sum that rather than the raw face count.
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        manifest[t] = {"footprint_m": fp, "height_m": ht, "tris": tris}
        print("make_houses: %s -> %s (%d faces, %d tris)" % (t, path, len(ob.data.polygons), tris))
    with open(os.path.join(OUT, "houses.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("make_houses: %d types" % len(manifest))


main()
