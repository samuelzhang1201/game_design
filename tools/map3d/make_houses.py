"""Generate the 3D map's house meshes (spec 2026-09-20 §2, remade 2026-09-21
for the owner's "more accomplished, on-palette" ruling and the 400 m closest
zoom; remade AGAIN 2026-09-21 for the owner's "房屋布局ok了，但是建模太丑了" —
layout and counts are settled, this pass is only about making each mesh read
as a handsome built object instead of flat-shaded primitives).

  blender -b --factory-startup --python tools/map3d/make_houses.py

Reads data/screens/map3d/map3d_houses.csv and writes one glTF per type into
assets/3D/buildings/, plus houses.json. Every mesh stands ON its origin
(min y = 0, centred on its footprint) and faces +Z, because
Map3DLayerHouses places it with a yaw and sinks it by map3d_house_sink_m —
a mesh that carries its own base plate or offset would defeat both.

Low poly on purpose: at the owner's 400 m closest zoom (2026-09-21 ruling,
was 800 m) a house is 17-35 px, where the silhouette, the eave shadow and
the roof colour are what read — never windows or doors as DETAIL. What v3
got wrong was not the shapes but the SURFACES: perfectly sharp 90-degree
corners, zero-thickness roof planes, no openings at all. This pass adds,
in order of payoff (v4 audit):

  1. A small bevel (bevel_solid) along every hard edge of every primitive —
     the single biggest change from "primitive" to "object", because it is
     what lets a highlight run along an arris at all.
  2. Roof THICKNESS: prism_roof / pyramid_roof / shed_roof no longer taper
     to a knife edge at the eave — each carries a genuine fascia band
     (`fascia`, 10-20 cm) between the wall top and the sloped surface,
     built as a proper closed skirt+cap, not a flat plane.
  3. Recessed openings (`opening`): thin dark "void"-material boxes let a
     few centimetres into a wall's face — a door and a couple of windows —
     with no frames or mullions, cheap enough to read as rhythm at 17-35 px.
  4. A little CAD-imperfection: every main roof's ridge sags a few
     centimetres to one side (`prism_roof`'s `sag`), on top of the chimneys
     and dormers that were already off-centre.
  5. Timber framing (`timber_frame`): corner posts, a mid rail and two
     studs standing 4-5 cm proud of the wall in a dark "beam" material —
     applied only to the daub/plaster types (the three cottages and
     townhouse_a/b), never to a stone wall.
  6. A stone plinth (`stone_plinth`): a course wider than the wall standing
     ON the ground at its own base — never a floating tray — for the
     grander, stone-walled types (townhouse_c, workshop, the four
     landmarks). It reuses the "beam" material slot (a type never wants
     both timber framing and a plinth), tinted house_wall_stone instead of
     house_beam.

Each mesh therefore carries up to FOUR material slots — wall, roof, beam,
void, always in that order, "beam"/"void" present only when that type
actually uses them (tests/map3d/test_map3d_houses_meshes.gd asserts no
fixed slot count, only that every mesh has at least one surface, so this is
compatible with the existing suite).

Each of the 14 types keeps its own plan (a rectangle, an L, a T, a nave with
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

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TABLE = os.path.join(ROOT, "data", "screens", "map3d", "map3d_houses.csv")
OUT = os.path.join(ROOT, "assets", "3D", "buildings")
PALETTE = os.path.join(ROOT, "data", "screens", "ui", "terrain_palette.csv")

# Types with a daub/plaster wall get real timber framing; the grander,
# stone-walled types get a plinth instead (a type never wants both — a
# building doesn't stand on a dressed course AND wear exposed timber).
TIMBER_TYPES = {"cottage_a", "cottage_b", "cottage_c", "townhouse_a", "townhouse_b"}
PLINTH_TYPES = {"townhouse_c", "workshop", "chapel", "church", "church_tower", "palace"}

BEVEL_WIDTH = 0.05
BEVEL_SEGMENTS = 1
FASCIA = 0.16


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

def bevel_solid(ob, width=BEVEL_WIDTH, segments=BEVEL_SEGMENTS):
    """A small chamfer along every edge of an already-closed solid — the
    single biggest change from "primitive" to "object" at 17-35 px, because
    it is the only thing that lets a highlight catch an arris at all (spec
    item 1). Runs on the primitive's OWN mesh, before it joins any other
    part, so each piece stays independently watertight; `clamp_overlap`
    makes this safe even on the script's thin decorative pieces (a step
    tread, a parapet finger) by shrinking the offset locally rather than
    self-intersecting. Beveling a closed solid's edges never moves a flat
    face's own plane, only cuts its corners, so it cannot change the
    mesh's bounding box (join_and_normalise's fp/ht fit is unaffected) and
    never lifts a bottom face off z=0 (a horizontal face's bevel inset
    stays IN that same plane, only the vertical side shifts) — confirmed by
    hand before wiring this in, and re-confirmed every run by
    test_every_mesh_stands_on_its_origin_at_the_claimed_size."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    # bmesh.ops.bevel needs OUTWARD-consistent winding to know which side is
    # "outside" — every primitive here is hand-authored (a roof's gable-end
    # triangle vs. its hip-end triangle, a shed's five closing faces) without
    # tracking that by eye, same as join_and_normalise's own comment further
    # down explains. Skipping this recalc left every non-box primitive
    # riddled with open boundary edges after its bevel (measured: a bare
    # shed_roof went from 0 open edges to 16 the moment bevel_solid touched
    # it) — bevel does not tolerate a mixed-winding input the way
    # normals_make_consistent, run afterward at the whole-mesh join, was
    # already relied on to do.
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=width, offset_type="OFFSET",
                     segments=segments, profile=0.55, affect="EDGES", clamp_overlap=True)
    bm.to_mesh(ob.data)
    ob.data.update()
    bm.free()
    return ob


def box(name, w, d, h, z=0.0, bevel=True):
    # primitive_cube_add(size=1.0) already spans +/-0.5 (a full 1.0 edge), so
    # the scale that makes it w x d x h is (w, d, h), not their halves — the
    # w/2 form silently produced a half-size box floating off the ground.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, z + h / 2))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (w, d, h)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        bevel_solid(ob)
    return ob


def _mesh_object(name, verts, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return ob


def prism_roof(name, w, d, h, z, overhang=0.4, ridge_frac=1.0, axis="y", fascia=FASCIA,
               sag=0.0, bevel=True):
    """A roof over a w x d wall, ridge line rising to height h above z, now
    a genuine solid with a fascia band (spec item 2): the eave no longer
    tapers to a knife edge where the underside meets the slope — a vertical
    band `fascia` deep stands between the wall top (z) and the sloped
    surface, closed by its own lower cap. `sag` drops ONE ridge end by a
    few centimetres (item 4: a real ridge is never dead level). With
    `axis` "y" the ridge runs the length of d (gable ends face +-y); "x"
    runs it the length of w (gable ends face +-x). `ridge_frac` < 1 draws
    the ridge shorter than the base, hipping the ends in (0 is a full
    pyramid hip); at 1 it is a plain gable."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    zb = z - fascia
    bot = [(-w2, -d2, zb), (w2, -d2, zb), (w2, d2, zb), (-w2, d2, zb)]
    top = [(-w2, -d2, z), (w2, -d2, z), (w2, d2, z), (-w2, d2, z)]
    if axis == "y":
        rd = d2 * ridge_frac
        ridge = [(0.0, -rd, z + h), (0.0, rd, z + h - sag)]
        gable_faces = [(4, 5, 8), (6, 7, 9)]
        slope_faces = [(5, 6, 9, 8), (7, 4, 8, 9)]
    else:
        rw = w2 * ridge_frac
        ridge = [(-rw, 0.0, z + h), (rw, 0.0, z + h - sag)]
        gable_faces = [(7, 4, 8), (5, 6, 9)]
        slope_faces = [(4, 5, 9, 8), (6, 7, 8, 9)]
    verts = bot + top + ridge
    faces = ([(0, 1, 2, 3), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
              + gable_faces + slope_faces)
    ob = _mesh_object(name, verts, faces)
    if bevel:
        bevel_solid(ob)
    return ob


def pyramid_roof(name, size, h, z, overhang=0.3, fascia=FASCIA, bevel=True):
    """A square hipped roof rising to a single apex — a tower cap or a
    spire's stage — with the same fascia skirt as prism_roof (item 2)."""
    s2 = size / 2 + overhang
    zb = z - fascia
    bot = [(-s2, -s2, zb), (s2, -s2, zb), (s2, s2, zb), (-s2, s2, zb)]
    top = [(-s2, -s2, z), (s2, -s2, z), (s2, s2, z), (-s2, s2, z)]
    verts = bot + top + [(0, 0, z + h)]
    faces = [(0, 1, 2, 3), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7),
             (4, 5, 8), (5, 6, 8), (6, 7, 8), (7, 4, 8)]
    ob = _mesh_object(name, verts, faces)
    if bevel:
        bevel_solid(ob)
    return ob


def shed_roof(name, w, d, h, z, overhang=0.3, axis="y", sign=1, fascia=FASCIA, bevel=True):
    """A single-slope "catslide" solid: the high side already stood full
    height h (a real vertical wall, closed on every face — the fix for
    cottage_b's lean-to that used to render white with no roof of its own
    to catch the light); the LOW side used to taper to a knife edge where
    its flat underside met the slope at the same height z — item 2 gives it
    a fascia skirt down to z - fascia, same idiom as prism_roof/
    pyramid_roof. `axis` picks which pair of edges rises; `sign` picks
    which one is high."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    if axis == "y":
        lo_y, hi_y = (-d2, d2) if sign > 0 else (d2, -d2)
        v0, v1 = (-w2, lo_y, z), (w2, lo_y, z)
        v2, v3 = (w2, hi_y, z), (-w2, hi_y, z)
        v4, v5 = (w2, hi_y, z + h), (-w2, hi_y, z + h)
        v6, v7 = (-w2, lo_y, z - fascia), (w2, lo_y, z - fascia)
    else:
        lo_x, hi_x = (-w2, w2) if sign > 0 else (w2, -w2)
        v0, v1 = (lo_x, -d2, z), (lo_x, d2, z)
        v2, v3 = (hi_x, d2, z), (hi_x, -d2, z)
        v4, v5 = (hi_x, d2, z + h), (hi_x, -d2, z + h)
        v6, v7 = (lo_x, -d2, z - fascia), (lo_x, d2, z - fascia)
    verts = [v0, v1, v2, v3, v4, v5, v6, v7]
    faces = [(6, 7, 2, 3), (0, 1, 7, 6), (0, 1, 4, 5), (3, 2, 4, 5), (6, 0, 5, 3), (7, 1, 4, 2)]
    ob = _mesh_object(name, verts, faces)
    if bevel:
        bevel_solid(ob)
    return ob


def chimney(name, x, y, z, h, w=0.55):
    ob = box(name, w, w, h, z)
    ob.location.x = x
    ob.location.y = y
    return ob


def roof_height_at(x, y, w, d, roof_h, wall_h, overhang, axis, ridge_frac=1.0):
    """The exterior roof surface's height directly above world (x, y) —
    a simple gable/hip taper (the hip ends' own inward slope along the
    ridge is ignored, which only ever makes this an UNDER-estimate near a
    hip corner, so the margin chimney_clearing adds still holds). Exists
    so a chimney can be sized to clear the roof it actually breaks through,
    rather than the ridge's own global peak — an off-centre chimney whose
    height was only ever checked against `ht` used to end up fully buried
    inside the roof's own solid, invisible from outside (v4 audit: true of
    every "house"-role type except the three townhouses, whose chimneys
    happened to reach exactly ht)."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    if axis == "x":
        t = min(abs(y) / d2, 1.0) if d2 > 0 else 0.0
    else:
        t = min(abs(x) / w2, 1.0) if w2 > 0 else 0.0
    return wall_h + roof_h * (1.0 - t)


def chimney_clearing(name, x, y, w, d, roof_h, wall_h, overhang, axis, ridge_frac=1.0,
                      clear=0.4, stack=1.0):
    """A chimney at (x, y) sized so its top stands `clear` metres above the
    roof surface it actually breaks through at that position, with `stack`
    metres of it showing above that clearance line (the base is buried in
    the wall/roof solid regardless, so only how far it starts BELOW the
    clearance line matters for how anchored it reads)."""
    top = roof_height_at(x, y, w, d, roof_h, wall_h, overhang, axis, ridge_frac) + clear
    return chimney(name, x, y, top - stack, stack)


def move(ob, x=0.0, y=0.0):
    ob.location.x += x
    ob.location.y += y
    return ob


def ridge_trim(name, w, d, ridge_frac, h, z, axis="y"):
    """A thin cresting strip along a roof's own ridge — cheap (one box) but
    it draws the ridge as a hard line rather than a soft meeting of two
    planes, and it takes the roof's own colour, not the wall's. Its TOP
    sits exactly at the ridge (z + h), never above it: the old z + h - 0.06
    origin with a 0.26 box height poked 0.20 m past every roof it dressed,
    which is what inflated `tall` past the declared height_m on nearly
    every type carrying one (2026-09-21 audit)."""
    if axis == "y":
        return box(name, 0.32, d * ridge_frac + 0.3, 0.26, z + h - 0.26)
    return box(name, w * ridge_frac + 0.3, 0.32, 0.26, z + h - 0.26)


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


def opening(name, w, h, z, axis, sign, offset, wall_half, depth=0.14, embed=-0.02):
    """A dark rectangle let into a wall's flat face — no frame, no
    mullions, just a "void"-material box that reads as a door or a window
    at 17-35 px (spec item 3). There is no boolean cut here (booleans are
    exactly the operation this file's own watertight test warns against),
    so the wall behind stays a plain, unbroken solid; a POSITIVE `embed`
    (the geometric ideal — the void's outer face sitting behind the wall's
    own surface) is therefore INVISIBLE, sealed behind the wall's opaque
    skin with nothing to show it through (2026-09-21 audit: every door and
    window rendered as nothing at all, confirmed by a neon debug material
    that still never appeared). The default is instead slightly NEGATIVE —
    the void's outer face stands a couple of centimetres PROUD of the
    wall, too little to be seen as a bump but enough to be the frontmost
    surface there rather than an occluded one — which is what actually
    delivers the "recessed dark quad" READ the spec asks for. `axis`/`sign`
    name the face exactly as shed_roof's catslide does; `offset` is the
    position along the OTHER horizontal axis; `wall_half` is that wall's
    own half-extent along `axis`."""
    if axis == "y":
        ob = box(name, w, depth, h, z, bevel=False)
        ob.location.y = sign * (wall_half - embed - depth / 2)
        ob.location.x = offset
    else:
        ob = box(name, depth, w, h, z, bevel=False)
        ob.location.x = sign * (wall_half - embed - depth / 2)
        ob.location.y = offset
    return ob


def face_strip(name, span, thickness, height, axis, sign, wall_half, z, proud=0.05, bevel=False):
    """A thin box laid flush against a wall face and standing `proud` of it
    by a few centimetres — a timber rail, or (via the caller's own
    material list) a differently-proportioned accent. Mirrors opening()'s
    axis/sign convention but points outward instead of recessing in."""
    if axis == "y":
        ob = box(name, span, thickness, height, z, bevel=bevel)
        ob.location.y = sign * (wall_half + proud - thickness / 2)
    else:
        ob = box(name, thickness, span, height, z, bevel=bevel)
        ob.location.x = sign * (wall_half + proud - thickness / 2)
    return ob


def timber_frame(w, d, wall_h, proud=0.07, post_w=0.16, rail_h=0.12):
    """Corner posts standing at the wall's own corners, a mid rail on the
    front and back, and two studs on the front — every piece proud of the
    wall by a few centimetres, in the "beam" material: the difference
    between a rendered box and a genuinely timber-framed building (spec
    item 5). Applied only to the daub/plaster types (TIMBER_TYPES); left
    off the stone-walled ones, which wear a plinth instead."""
    frame = []
    half_w, half_d = w / 2, d / 2
    for i, (sx, sy) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        p = box("post%d" % i, post_w, post_w, wall_h, bevel=False)
        p.location.x = sx * (half_w - post_w / 2 + proud)
        p.location.y = sy * (half_d - post_w / 2 + proud)
        frame.append(p)
    rail_z = wall_h * 0.42
    frame.append(face_strip("rail_f", w * 0.92, rail_h, rail_h, "y", -1, half_d, rail_z, proud))
    frame.append(face_strip("rail_b", w * 0.92, rail_h, rail_h, "y", 1, half_d, rail_z, proud))
    stud_w = 0.09
    stud_h = wall_h * 0.7
    for i, t in enumerate((-0.26, 0.26)):
        stud = box("stud%d" % i, stud_w, stud_w, stud_h, bevel=False)
        stud.location.x = t * w
        stud.location.y = -(half_d + proud - stud_w / 2)
        frame.append(stud)
    return frame


def stone_plinth(w, d, wall_h, extra=0.14):
    """A dressed-stone base COURSE, wider than the wall above it, standing
    ON the ground at its own base (z=0) — part of the building, not a
    floating tray (the owner's standing prohibition: spec item 6). Used on
    the grander, stone-walled types via PLINTH_TYPES; sized so `extra` stays
    under every one of those types' own roof overhang, so the plinth never
    becomes the mesh's widest point and skews join_and_normalise's fit."""
    h = max(0.35, min(0.7, wall_h * 0.15))
    return box("plinth", w + extra * 2, d + extra * 2, h, 0.0)


# --------------------------------------------------------------- 14 builders
# Every builder returns (walls, roofs, beams, voids); `fp`/`ht` are the CSV's
# declared footprint (longest side) and total height, used as the seed for
# the type's own proportions — join_and_normalise then fits the built plan
# to those numbers exactly (see its docstring for why that is a fix, not
# just a convenience). `beams` carries timber framing OR a stone plinth
# (never both) and `voids` carries recessed doors/windows; either list may
# be empty.

def build_cottage_a(fp, ht):
    """A one-room thatched cottage: a plain steep gable, one off-centre
    chimney breaking the ridge, and a small porch canopy over the door.
    The commonest building, so the plainest."""
    wall_h = ht * 0.58
    roof_h = ht - wall_h
    w, d = fp * 0.86, fp * 0.60
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.45, axis="x", sag=0.06)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    roofs.append(chimney_clearing("chimney", w * 0.24, -d * 0.30, w, d, roof_h, wall_h, 0.45, "x"))
    # The porch's high (wall) end sits FLUSH with the eave (top = wall_h,
    # not wall_h + 0.3) and embeds only 0.1 m into the wall (2026-09-21
    # audit: the old +0.3 rise poked the porch's tall end above the wall
    # top into open air the roof's own gable slope didn't reach either —
    # nothing there to explain it — while the old y offset (pd * 0.3, less
    # than the porch's own half-depth-plus-overhang) buried 0.42 m of the
    # wedge inside the wall's opaque solid, a real self-intersection that
    # rendered as a dark gash on the wall face).
    pw, pd = w * 0.30, d * 0.32
    porch_h = wall_h * 0.62
    porch_overhang = 0.15
    porch = shed_roof("porch", pw, pd, wall_h - porch_h, porch_h, overhang=porch_overhang, axis="y", sign=-1)
    move(porch, y=-(d * 0.5 + pd * 0.5 + porch_overhang - 0.1))
    roofs.append(porch)
    beams = timber_frame(w, d, wall_h)
    voids = [
        opening("door", w * 0.15, wall_h * 0.55, 0.0, "y", -1, 0.0, d / 2),
        opening("window0", w * 0.13, wall_h * 0.30, wall_h * 0.42, "x", 1, d * 0.15, w / 2),
    ]
    return walls, roofs, beams, voids


def build_cottage_b(fp, ht):
    """A thatched cottage with an L-shaped lean-to: a genuine second wing,
    roofed with its own catslide climbing into the main gable — the fix for
    the lean-to that used to be a bare, unroofed box."""
    wall_h = ht * 0.58
    roof_h = ht - wall_h
    w, d = fp * 0.62, fp * 0.56
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.4, axis="x", sag=-0.05)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    lw, ld, lh = fp * 0.34, d * 0.82, wall_h * 0.60
    lean = box("lean", lw, ld, lh)
    move(lean, x=w * 0.5 + lw * 0.5 - 0.2)
    walls.append(lean)
    rise = (wall_h - lh) + (ht - wall_h) * 0.4
    lroof = shed_roof("lean_roof", lw, ld, rise, lh, overhang=0.3, axis="x", sign=-1)
    move(lroof, x=lean.location.x)
    roofs.append(lroof)
    roofs.append(chimney_clearing("chimney", -w * 0.28, -d * 0.25, w, d, roof_h, wall_h, 0.4, "x"))
    beams = timber_frame(w, d, wall_h)
    voids = [
        opening("door", w * 0.16, wall_h * 0.55, 0.0, "y", -1, w * 0.10, d / 2),
        opening("window0", w * 0.14, wall_h * 0.28, wall_h * 0.42, "y", -1, -w * 0.28, d / 2),
    ]
    return walls, roofs, beams, voids


def build_cottage_c(fp, ht):
    """The smallest cottage: near-square, fully hipped roof (no gable
    walls at all) — the shape that reads as a hut beside cottage_a's and
    cottage_b's gables."""
    wall_h = ht * 0.56
    roof_h = ht - wall_h
    w, d = fp * 0.92, fp * 0.78
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.4, ridge_frac=0.3, axis="x", sag=0.04)]
    roofs.append(ridge_trim("ridge", w, d, 0.3, roof_h, wall_h, axis="x"))
    roofs.append(chimney_clearing("chimney", -w * 0.22, -d * 0.20, w, d, roof_h, wall_h, 0.4, "x", ridge_frac=0.3))
    beams = timber_frame(w, d, wall_h)
    voids = [opening("door", w * 0.16, wall_h * 0.55, 0.0, "y", -1, 0.0, d / 2)]
    return walls, roofs, beams, voids


def build_townhouse_a(fp, ht):
    """A narrow gable-fronted townhouse: the street gable is a crow-stepped
    parapet climbing to a point at the ridge, not an open eave — the shape
    that tells it apart from a cottage's plain gable at a glance, and from
    townhouse_b's jetty and townhouse_c's dormer."""
    wall_h = ht * 0.60
    roof_h = ht - wall_h
    w, d = fp * 0.55, fp - 0.5
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.25, sag=0.05)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="y"))
    steps = 5
    step_w = w / steps
    for i in range(steps):
        t = abs((i + 0.5) / steps - 0.5) * 2.0
        step_h = wall_h + roof_h * (1.0 - t)
        block = box("parapet%d" % i, step_w * 0.92, 0.34, step_h, bevel=False)
        move(block, x=-w / 2 + step_w * (i + 0.5), y=-d * 0.5 - 0.05)
        walls.append(block)
    roofs.append(chimney_clearing("chimney", w * 0.28, -d * 0.30, w, d, roof_h, wall_h, 0.25, "y"))
    beams = timber_frame(w, d, wall_h)
    voids = [
        opening("door", w * 0.20, wall_h * 0.5, 0.0, "y", -1, 0.0, d / 2),
        opening("window0", w * 0.22, wall_h * 0.26, wall_h * 0.62, "y", -1, 0.0, d / 2),
    ]
    return walls, roofs, beams, voids


def build_townhouse_b(fp, ht):
    """A jettied corner house reached by its own outside stair: the upper
    floor still overhangs on every side, but a canted ramp now climbs the
    ground floor's east end to the jetty's door — an entrance no other
    type wears, so it is not just townhouse_a with a wider eave."""
    wall_h = ht * 0.55
    ground_h = wall_h * 0.60
    w = fp * 0.58
    jd = fp - 0.8
    d = jd / 1.05
    walls = [box("ground", w, d, ground_h)]
    jw, jetty_h = w * 1.16, wall_h * 0.4
    jetty = box("jetty", jw, jd, jetty_h, ground_h)
    walls.append(jetty)
    roof_h = ht - wall_h
    roofs = [prism_roof("roof", jw, jd, roof_h, wall_h, overhang=0.4, ridge_frac=0.55, sag=-0.06)]
    roofs.append(ridge_trim("ridge", jw, jd, 0.55, roof_h, wall_h, axis="y"))
    roofs.append(chimney_clearing("chimney", -jw * 0.26, jd * 0.28, jw, jd, roof_h, wall_h, 0.4, "y", ridge_frac=0.55))
    # Three flat treads climbing to the door, not a single sloped wedge
    # plus a floating rail (2026-09-21 audit): the wedge's own diagonal
    # face read as an unparseable dark mass at 17-35 px, and a rail this
    # thin tucked partly under the jetty's cantilever added clutter no
    # camera angle could resolve into "a stair." Flat boxes stacked in a
    # tread stay entirely below the jetty's own z range (they only ever
    # touch its flat underside at ground_h, never cross it) even where
    # they sit under its horizontal overhang, so nothing here interpenetrates.
    steps_n = 3
    tread = w * 0.09
    step_w = d * 0.30
    x0 = w * 0.5 - 0.08
    for i in range(steps_n):
        sh = ground_h * (steps_n - i) / steps_n
        step = box("step%d" % i, tread, step_w, sh, bevel=False)
        move(step, x=x0 + tread * (i + 0.5), y=-d * 0.15)
        walls.append(step)
    # timber_frame's own wall_h drives rail height and stud length; the
    # jetty is the visible timbered storey (the ground floor reads as
    # stone-footed), so its own thickness stands in for "wall_h" here.
    beams = timber_frame(jw, jd, jetty_h)
    for b in beams:
        b.location.z += ground_h
    voids = [
        opening("door", w * 0.20, jetty_h * 0.85, ground_h + jetty_h * 0.08, "x", 1, -d * 0.15, w / 2),
        opening("window0", jw * 0.16, jetty_h * 0.5, ground_h + jetty_h * 0.3, "y", -1, 0.0, jd / 2),
    ]
    return walls, roofs, beams, voids


def build_townhouse_c(fp, ht):
    """The tall merchant's house: steepest, narrowest townhouse, with an
    attic dormer breaking one roof slope and an off-centre chimney — the
    tallest of the three, so the roofline needs the most incident."""
    wall_h = ht * 0.66
    roof_h = ht - wall_h
    w, d = fp * 0.52, fp - 0.6
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.3, sag=0.05)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="y"))
    dw, dd, dh = w * 0.34, d * 0.22, ht * 0.13
    dz = wall_h + (ht - wall_h) * 0.3
    dormer = box("dormer", dw, dd, dh, dz)
    move(dormer, y=-d * 0.16)
    walls.append(dormer)
    droof = prism_roof("dormer_roof", dw, dd, dh * 0.6, dz + dh, overhang=0.12)
    move(droof, y=-d * 0.16)
    roofs.append(droof)
    roofs.append(chimney_clearing("chimney", -w * 0.30, d * 0.32, w, d, roof_h, wall_h, 0.3, "y"))
    # a small ground-floor oriel on the front wall, opposite the roof's
    # dormer — a partial bay, unlike townhouse_b's full-width jetty.
    ow, od, oh = w * 0.30, 0.35, wall_h * 0.42
    oriel = box("oriel", ow, od, oh, wall_h * 0.30)
    move(oriel, y=-d * 0.5 - od * 0.5 + 0.05)
    walls.append(oriel)
    # a rectangular hip, not a square pyramid_roof: a square cap sized off
    # ow (the oriel's WIDTH) swung far past od (its shallow depth) and
    # over-filled the mesh's own footprint on that axis. ridge_frac is a
    # hair above 0, not exactly 0 (2026-09-21 audit): at exactly 0 the
    # ridge's two endpoints collapse onto the SAME point, which degenerates
    # two of prism_roof's quad faces into zero-area slivers and left one
    # edge's winding ambiguous between its neighbours — caught by the new
    # watertight/winding test, invisible at this size but worth doing right.
    # bevel=False here (2026-09-21 v4 audit): beveling a roof already this
    # tiny (ridge_frac 0.08, fascia 0.05) collapsed a couple of its edges
    # to zero length — two vertices bevel meant to separate landed on the
    # same point — which read as a same-winding conflict on the SAME edge
    # in the exported mesh (test_every_mesh_is_watertight_and_consistently_wound).
    # Invisible at this size either way, so skipping it costs nothing.
    oriel_roof = prism_roof("oriel_roof", ow, od, wall_h * 0.12, wall_h * 0.30 + oh,
                             overhang=0.05, ridge_frac=0.08, axis="x", fascia=0.05, bevel=False)
    move(oriel_roof, y=oriel.location.y)
    roofs.append(oriel_roof)
    beams = [stone_plinth(w, d, wall_h)]
    voids = [
        opening("door", w * 0.18, wall_h * 0.4, 0.0, "y", -1, w * 0.26, d / 2),
        opening("window0", w * 0.16, wall_h * 0.22, wall_h * 0.55, "y", 1, 0.0, d / 2),
    ]
    return walls, roofs, beams, voids


def build_longhouse(fp, ht):
    """The genuinely long, low hall, its byre a perpendicular wing at one
    end (a T plan) under its own cross-gable, a half-hipped main roof."""
    wall_h = ht * 0.52
    roof_h = ht - wall_h
    w, d = fp * 0.94, fp * 0.20
    walls = [box("hall", w, d, wall_h)]
    roofs = [prism_roof("hall_roof", w, d, roof_h, wall_h, overhang=0.4, ridge_frac=0.75,
                         axis="x", sag=0.07)]
    roofs.append(ridge_trim("ridge", w, d, 0.75, roof_h, wall_h, axis="x"))
    bw, bd, bh = fp * 0.22, fp * 0.30, wall_h * 0.85
    byre = box("byre_wing", bw, bd, bh)
    move(byre, x=w * 0.5 - bw * 0.4, y=d * 0.5 + bd * 0.32)
    walls.append(byre)
    # byre_roof is narrower and pushed further out than the wing it sits on
    # (2026-09-21 audit): hall_roof is a solid prism, not a shell, so its
    # hip taper at this end still stands taller than byre_roof everywhere
    # the wing's own footprint reaches back toward the hall — centering a
    # same-size roof on the wing let it cross straight through hall_roof's
    # sloped hip face, which rendered as a black gash where the two
    # sloped surfaces met edge-on. The roof instead starts exactly where
    # hall_roof's own footprint ends (plus a hair's clearance), covering
    # only the wing's visible, un-embedded portion; the wing's near end
    # stays roofless because it already sits under the hall's own eaves.
    hall_roof_edge = d * 0.5 + 0.4
    wing_far = byre.location.y + bd * 0.5
    broof_overhang = 0.3
    broof_near = hall_roof_edge + 0.05
    broof_far = wing_far + broof_overhang
    broof_y = (broof_near + broof_far) * 0.5
    broof_half = (broof_far - broof_near) * 0.5
    broof_d = 2.0 * (broof_half - broof_overhang)
    broof = prism_roof("byre_roof", bw, broof_d, (ht - wall_h) * 0.75, bh, overhang=broof_overhang)
    move(broof, x=byre.location.x, y=broof_y)
    roofs.append(broof)
    roofs.append(chimney_clearing("chimney", -w * 0.32, -d * 0.30, w, d, roof_h, wall_h, 0.4, "x", ridge_frac=0.75))
    voids = [
        opening("door", w * 0.10, wall_h * 0.55, 0.0, "x", -1, 0.0, d / 2),
        opening("window0", w * 0.08, wall_h * 0.26, wall_h * 0.5, "x", -1, d * 0.6, d / 2),
    ]
    return walls, roofs, [], voids


def build_workshop(fp, ht):
    """A workshop with an open front: a squarish working block under a
    broad-ridged roof, and a lower, wall-less canopy bay projecting out
    front for the open working face."""
    wall_h = ht * 0.60
    roof_h = ht - wall_h
    # d is solved so the canopy's own overhang, not the main roof's, sets
    # the y-extent at exactly footprint_m (2026-09-21 audit: the canopy
    # used to swing past the block's own roof and over-fill the footprint
    # by 7-9%, which join_and_normalise then had to shrink back down).
    w, d = fp * 0.66, (fp - 0.65) / 1.451
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.3, axis="x", sag=0.05)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    roofs.append(chimney_clearing("chimney", w * 0.32, d * 0.30, w, d, roof_h, wall_h, 0.3, "x"))
    cw, cd = w * 0.88, d * 0.55
    canopy_h = wall_h * 0.66
    canopy_rise = (wall_h - canopy_h) + 0.4
    canopy = shed_roof("canopy", cw, cd, canopy_rise, canopy_h, overhang=0.35, axis="y", sign=-1)
    move(canopy, y=-d * 0.5 - cd * 0.32)
    roofs.append(canopy)
    beams = [stone_plinth(w, d, wall_h)]
    voids = [opening("window0", w * 0.16, wall_h * 0.28, wall_h * 0.5, "y", 1, 0.0, d / 2)]
    return walls, roofs, beams, voids


def build_barn(fp, ht):
    """Low and wide, a shallow-pitched gable (barns pitch far shallower
    than a cottage) and a little ridge cupola/vent breaking the roofline."""
    wall_h = ht * 0.48
    roof_h = ht - wall_h
    w, d = fp * 0.92, fp * 0.52
    walls = [box("wall", w, d, wall_h)]
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.55, axis="x", sag=0.06)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    cw = w * 0.10
    cupola_z = ht * 0.80
    cupola = box("cupola", cw, cw, ht * 0.10, cupola_z)
    walls.append(cupola)
    roofs.append(pyramid_roof("cupola_roof", cw, ht * 0.10, cupola_z + ht * 0.10, overhang=0.08))
    voids = [opening("door", d * 0.42, wall_h * 0.72, 0.0, "x", -1, 0.0, w / 2, depth=0.16)]
    return walls, roofs, [], voids


def build_byre(fp, ht):
    """An open-fronted cattle byre: a solid back wall and two deep side
    piers under one broad, shallow roof, the whole front left open between
    them — a genuine void in the silhouette, not cottage_b's lean-to idiom
    turned onto the other axis."""
    wall_h = ht * 0.62
    roof_h = ht - wall_h
    w, d = fp - 1.1, fp * 0.50
    back_d = d * 0.18
    back = box("back", w, back_d, wall_h)
    move(back, y=d * 0.5 - back_d * 0.5)
    walls = [back]
    pier_w, pier_d = w * 0.14, d * 0.9
    for i, sx in enumerate((-1, 1)):
        pier = box("pier%d" % i, pier_w, pier_d, wall_h)
        move(pier, x=sx * (w * 0.5 - pier_w * 0.5))
        walls.append(pier)
    roofs = [prism_roof("roof", w, d, roof_h, wall_h, overhang=0.55, axis="x", sag=-0.05)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, wall_h, axis="x"))
    voids = [opening("window0", w * 0.14, wall_h * 0.24, wall_h * 0.55, "y", 1, 0.0, back.location.y + back_d / 2)]
    return walls, roofs, [], voids


def build_chapel(fp, ht):
    """The village's landmark: a tall narrow nave and a thin bellcote
    screen wall rising clear of the ridge at one gable end, capped with its
    own small spire — the cheapest way to be unmistakably not a house."""
    nave_h = ht * 0.46
    w, d = fp * 0.48, fp - 0.7
    walls = [box("nave", w, d, nave_h)]
    roof_h = ht * 0.30
    roofs = [prism_roof("nave_roof", w, d, roof_h, nave_h, overhang=0.35, sag=0.05)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, roof_h, nave_h, axis="y"))
    bell_z = nave_h + roof_h * 0.55
    cap_h = ht * 0.09
    bw, bd, bh = w * 0.55, 0.5, ht - bell_z - cap_h
    bellcote = box("bellcote", bw, bd, bh, bell_z)
    move(bellcote, y=-d * 0.5 + 0.35)
    walls.append(bellcote)
    # the cap's own SIZE stays independent of bw (the bellcote's visual
    # width): sized off bw it used to swing wide enough to poke past the
    # nave roof's own overhang on the gable side, which is what inflated
    # the whole mesh's measured span past its declared footprint_m.
    cap = pyramid_roof("bell_cap", w * 0.26, cap_h, bell_z + bh, overhang=0.05)
    move(cap, y=bellcote.location.y)
    roofs.append(cap)
    beams = [stone_plinth(w, d, nave_h)]
    voids = [
        opening("door", w * 0.22, nave_h * 0.5, 0.0, "y", -1, 0.0, d / 2),
        opening("window0", w * 0.20, nave_h * 0.4, nave_h * 0.4, "x", 1, d * 0.2, w / 2),
    ]
    return walls, roofs, beams, voids


def build_church(fp, ht):
    """A town's and a fort's landmark: a cruciform plan — nave, a
    perpendicular transept, and a crossing tower with a pyramidal cap at
    their meeting point — grander than the chapel, shorter than
    church_tower."""
    nave_h = ht * 0.40
    w, d = fp * 0.40, fp - 0.7
    walls = [box("nave", w, d, nave_h)]
    roofs = [prism_roof("nave_roof", w, d, ht * 0.22, nave_h, overhang=0.35, sag=0.06)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, ht * 0.22, nave_h, axis="y"))
    tw, td = fp * 0.60, fp * 0.26
    transept_h = nave_h * 0.9
    walls.append(box("transept", tw, td, transept_h))
    roofs.append(prism_roof("transept_roof", tw, td, ht * 0.16, transept_h, overhang=0.3, axis="x"))
    tower_w = fp * 0.24
    tower_h = ht * 0.72
    walls.append(box("tower", tower_w, tower_w, tower_h))
    tower_buttresses(walls, 0.0, 0.0, tower_w, tower_h)
    roofs.append(pyramid_roof("tower_roof", tower_w, ht * 0.28, tower_h, overhang=0.12))
    beams = [stone_plinth(w, d, nave_h)]
    voids = [opening("door", w * 0.24, nave_h * 0.48, 0.0, "y", -1, 0.0, d / 2)]
    return walls, roofs, beams, voids


def build_church_tower(fp, ht):
    """A city's landmark: a long nave beside a genuinely tall tower with a
    two-stage tapered spire — the silhouette that has to read over
    everything else at 17-35 px. The nave is real mass, not padding: at
    footprint_m 22 the tower's own authored plan (5.7 m square under a
    15.4 m shaft) already accounts for barely half that box, so a nave
    short enough to leave the rest empty forced join_and_normalise to
    stretch the WHOLE mesh sideways to reach 22 m, squashing the tower's
    own aspect out of shape (2026-09-21 audit) — the nave now supplies the
    length the footprint already promises instead."""
    nave_h = ht * 0.20
    w, d = fp * 0.83, fp * 0.30
    walls = [box("nave", w, d, nave_h)]
    roofs = [prism_roof("nave_roof", w, d, nave_h * 0.6, nave_h, overhang=0.3, axis="x", sag=0.04)]
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
    # bevel=False (2026-09-21 v4 audit): same zero-length-edge failure as
    # townhouse_c's oriel_roof, on this spire's tiny cap.
    spire2 = pyramid_roof("spire2", spire2_w, spire2_h, tower_h + spire1_h, overhang=0.03,
                           fascia=0.08, bevel=False)
    move(spire2, x=tower.location.x)
    roofs.append(spire2)
    beams = [stone_plinth(w, d, nave_h)]
    voids = [opening("door", w * 0.16, nave_h * 0.7, 0.0, "x", -1, 0.0, d / 2)]
    return walls, roofs, beams, voids


def build_palace(fp, ht):
    """The capital's landmark: a broad hall with a pedimented portico
    projecting from the front and twin corner towers, each hipped — the
    widest, grandest plan of the fourteen."""
    w, d = fp * 0.80, fp * 0.40
    wall_h = ht * 0.5
    walls = [box("hall", w, d, wall_h)]
    roofs = [prism_roof("hall_roof", w, d, ht * 0.16, wall_h, overhang=0.55, axis="x", sag=0.06)]
    roofs.append(ridge_trim("ridge", w, d, 1.0, ht * 0.16, wall_h, axis="x"))
    pw, pd, ph = w * 0.20, d * 0.55, wall_h * 0.86
    portico = box("portico", pw, pd, ph)
    move(portico, y=-d * 0.5 - pd * 0.4)
    walls.append(portico)
    proof = prism_roof("portico_roof", pw, pd, ht * 0.12, ph, overhang=0.22)
    move(proof, y=portico.location.y)
    roofs.append(proof)
    tower_w = d * 0.55
    tower_h = ht * 0.82
    for sx in (-1, 1):
        tw_ob = box("wing%d" % sx, tower_w, tower_w, tower_h)
        move(tw_ob, x=sx * w * 0.5)
        walls.append(tw_ob)
        tower_buttresses(walls, tw_ob.location.x, tw_ob.location.y, tower_w, tower_h,
                          name_prefix="but%d" % sx)
        cap = pyramid_roof("cap%d" % sx, tower_w, ht * 0.18, tower_h, overhang=0.15)
        move(cap, x=sx * w * 0.5)
        roofs.append(cap)
    beams = [stone_plinth(w, d, wall_h)]
    voids = [
        opening("door", pw * 0.55, ph * 0.6, 0.0, "y", -1, 0.0, portico.location.y + pd / 2),
        opening("window0", w * 0.10, wall_h * 0.3, wall_h * 0.45, "y", -1, w * 0.30, d / 2),
        opening("window1", w * 0.10, wall_h * 0.3, wall_h * 0.45, "y", -1, -w * 0.30, d / 2),
    ]
    return walls, roofs, beams, voids


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
    total height including the roof. Returns (walls, roofs, beams, voids)."""
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
    # and it is a global, one-shot fix for the whole merged mesh. Bevel and
    # the fascia/plinth/opening/timber additions are all authored (or, for
    # bevel, solved by Blender's own operator) BEFORE this point per-piece,
    # so this recalculation only ever has to reconcile independently
    # watertight, overlapping solids — never an already-broken mesh.
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
    # Diagnostic only (2026-09-21 audit): s_xy/s_z close to 1.0 means the
    # authored plan already filled its declared footprint_m/height_m box, so
    # normalise barely has to touch it; far from 1.0 means one axis is being
    # stretched to reach the box the OTHER axis already fills, which is the
    # distortion this audit exists to catch.
    print("make_houses: %-12s span=%.2f tall=%.2f s_xy=%.3f s_z=%.3f ratio=%.3f" %
          (name, span, tall, s_xy, s_z, s_xy / s_z if s_z else float("inf")))
    return ob


def self_check(ob):
    """A fast, in-process echo of the GUT suite's own manifold/winding
    census (tests/map3d/test_map3d_houses_meshes.gd), so a bad mesh shows
    up in this script's own console instead of only after a full Godot
    test run. Warns, does not abort — the real gate is the GUT test."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    open_edges = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    non_manifold = sum(1 for e in bm.edges if len(e.link_faces) not in (1, 2))
    bad_winding = sum(1 for e in bm.edges if len(e.link_faces) == 2 and not e.is_contiguous)
    bm.free()
    if open_edges or bad_winding or non_manifold:
        print("make_houses: WARNING %s open=%d non_manifold=%d bad_winding=%d" %
              (ob.name, open_edges, non_manifold, bad_winding))
    return open_edges == 0 and bad_winding == 0


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
    default_wall = tuple(srgb_to_linear(c) for c in (0.78, 0.74, 0.65))
    default_roof = tuple(srgb_to_linear(c) for c in (0.55, 0.35, 0.27))
    default_beam = tuple(srgb_to_linear(c) for c in (0.24, 0.16, 0.11))
    default_void = tuple(srgb_to_linear(c) for c in (0.09, 0.08, 0.07))
    manifest = {}
    with open(TABLE) as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        t = r["type"]
        fp, ht = float(r["footprint_m"]), float(r["height_m"])
        clear()
        walls, roofs, beams, voids = build(t, fp, ht)
        # Each row picks its own wall colour (2026-09-21: every wall used to
        # be the same "house_wall" cream regardless of type, which at
        # 17-35 px throws away half the visible pixels' worth of variety —
        # roughly as much as the 5 roof colours buy).
        wall_key = r.get("wall") or "house_wall"
        wall_mat = material("wall", palette.get(wall_key, default_wall))
        roof_mat = material("roof", palette.get(r["roof"], default_roof))
        for o in walls:
            o.data.materials.append(wall_mat)
        for o in roofs:
            o.data.materials.append(roof_mat)
        objs = list(walls) + list(roofs)
        if beams:
            beam_key = "house_beam" if t in TIMBER_TYPES else "house_wall_stone"
            beam_mat = material("beam", palette.get(beam_key, default_beam))
            for o in beams:
                o.data.materials.append(beam_mat)
            objs += list(beams)
        if voids:
            void_mat = material("void", palette.get("house_void", default_void))
            for o in voids:
                o.data.materials.append(void_mat)
            objs += list(voids)
        ob = join_and_normalise(t, objs, fp, ht)
        self_check(ob)
        os.makedirs(os.path.join(OUT, t), exist_ok=True)
        path = os.path.join(OUT, t, t + ".glb")
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
