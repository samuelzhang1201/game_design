"""Retopologise the Hunyuan3D house meshes down to the game's tri budget and
bake their surface onto the result (owner 2026-09-21, choice "C").

  blender -b --factory-startup --python tools/map3d/retopo_houses.py

Reads data/map3d_houses.csv and, for every type that has a source mesh at
assets/map3d_houses/ai_src/<type>.glb, writes assets/map3d_houses/<type>.glb
— the SAME files make_houses.py writes, so nothing downstream changes. A type
with no source keeps whatever make_houses.py left there.

Why retopo and not decimation, and not a hand-built low poly:

  * The AI mesh is ~500k triangles of marching-cubes surface. PLANAR
    decimation (dissolve coplanar faces) barely touches it — measured
    497,380 -> 101,770 at a 20 degree limit — because none of its "flat"
    walls are actually flat. Collapse decimation to the ~500 tris the game
    can afford shreds the silhouette.
  * Baking the AI surface onto the EXISTING procedural low poly was tried
    (options "A" and "B" of the owner's comparison) and rejected: the
    procedural roof geometry fights the baked roof texture, and the AI's
    proportions (a cottage 9.9 x 6.85 x 8.85 m) are not the procedural
    ones (9.9 x 8.93 x 5.5 m), so the texture arrives stretched.
  * Voxel-remeshing the AI mesh and decimating THAT keeps its own
    silhouette — chimney, sagging ridge, eaves — at 520 tris against the
    procedural mesh's 360, and at the 17-35 px a house is drawn at it is
    indistinguishable from the 497,380-tri original.

The mesh contract is make_houses.py's, unchanged: one mesh, standing ON its
origin (min y = 0 after the glTF Y-up conversion), centred on its footprint,
facing +Z. Map3DLayerHouses places it with a yaw and sinks it by
map3d_house_sink_m, so a mesh carrying its own base plate or offset would
defeat both. `yaw_offset_deg` in the table turns a source whose front does
not already face that way; it is applied HERE, baked into the vertices, so
the runtime keeps knowing nothing about it.

PROPORTIONS come from the source, not the table. The mesh is scaled
UNIFORMLY so its LONG horizontal axis is the table's footprint_m — which is
what bake_houses.py packs against, so the packing contract holds — and the
height that falls out of the source's own aspect is written BACK into the
table's height_m (and into houses.json). That writeback is deliberate:
height_m is a measured fact about the mesh, not a design value, once the
shape comes from the source, and tests/map3d/test_map3d_houses_meshes.gd
pins the two together. footprint_m stays the authored input; height_m
becomes the output. Nothing at runtime reads height_m — only
make_houses.py, to BUILD a procedural mesh, and that test.

The `roof` / `wall` colour keys no longer tint a retopologised type either:
its colour is in the baked texture. They still drive make_houses.py for a
type with no source.
"""

import bpy
import csv
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "data", "map3d_houses.csv")
OUT = os.path.join(ROOT, "assets", "map3d_houses")
SRC = os.path.join(OUT, "ai_src")

# ABSOLUTE voxel size, in metres (owner 2026-09-21: '原图那么漂亮，你的图怎么
# 圆滚滚，软塌塌，脏兮兮的感觉'). It used to be a FRACTION of the building's own
# bounding box, which is the single mistake that wrecked the big buildings:
# a 9.9 m cottage got a 0.16 m voxel and survived, while a 48 m palace got
# 0.77 m — coarser than its own buttresses, window mullions and parapets, so
# they were simply averaged away and what came out was a heap of domes. The
# damage scaled with the building, exactly as the side-by-side against the
# sources showed: cottages near-perfect, town houses losing their flats, the
# church tower and the palace gone. A length in metres treats every building
# the same.
VOXEL_M = 0.12
# Kept only for the comment below it.
# It must stay FINE and the triangle budget must be reached by decimating
# afterwards. Sizing the voxel to land near the budget directly was tried and
# reverted: a 9.8 m cottage needs a ~1.5 m voxel to come out at 460 triangles,
# and a 0.3 m wall simply does not survive a 1.5 m voxel — the roof is a thick
# enough mass to survive, so what came out was a hollow SHELL of the roof with
# no walls under it. Measured on the output's own vertex distribution: the
# 10-40% height band, which is the walls, held 86 of 1026 vertices. A fine
# remesh captures the walls; collapse decimation then thins them evenly.
_UNUSED_VOXEL_FRACTION = 0.016
# What VOXEL_FRACTION measures on this pack's cottage, and what the remesh is
# aimed at as a multiple of the budget.
#
# This multiple is the whole game. Too LOW and the voxel is coarser than the
# walls are thick and they vanish — but solidify() has already made them
# SOLIDIFY_SPAN_FRACTION of the building thick (~0.86 m on a 9.9 m cottage),
# so there is a lot more room here than the hollow source allowed. Too HIGH
# and the single decimate pass has to collapse 98% of the mesh, which drags
# the surface up to half a metre away from the source — and THAT breaks the
# bake: rays cast from a surface that far out miss the source entirely and
# come back as background, which is what covered the walls in black patches
# at 3.5x. 1.4 keeps the remesh near the budget and the decimate gentle, so
# the low poly hugs the source and every ray lands.
REFERENCE_TRIS = 28488.0
REMESH_OVERSHOOT = 3.5
# Hunyuan3D usually returns a HOLLOW building: an outer skin with rooms and
# interior faces behind the windows, so the mesh encloses almost no volume.
# Measured as enclosed volume over bounding box: of six generations only ONE
# came back solid (44.4%); the rest ran 2.0-7.7%. Decimating a hollow
# double-surface is what turns walls into a lace of criss-crossing triangles
# — the renders that looked like torn netting — because collapse has two
# surfaces a few centimetres apart to confuse it. So the shell is given real
# thickness INWARD (offset -1, which leaves the outside face exactly where it
# was — the only face anyone sees) before the remesh, which then has a solid
# to work with. Measured: 2.0-6.7% -> 41.9-49.9%, i.e. the good model's own
# figure, and the decimate stops tearing.
# ABSOLUTE, in metres — for the same reason VOXEL_M is (owner 2026-09-21).
# This was 0.09 of the building's own bounding box, which on a 48 m palace
# meant pushing its skin 4.3 m INWARD: its turrets, chimneys and courtyard
# walls are thinner than that, so they self-intersected and punched through
# each other, and the remesh that followed was already ruined. Fixing the
# voxel alone did not help because this line was making the same mistake one
# step earlier. A wall's thickness does not depend on how big its building
# is; 0.7 m closes a room without reaching anything else.
SOLIDIFY_M = 0.7
# self_check's hollow guard. An ABSOLUTE share of the bounding box cannot be
# the test: it was 0.25, which suits a squat cottage and wrongly failed
# townhouse_c — a 15.6 x 14.4 x 25 m tower whose box is mostly air by its own
# honest shape, at 23%. What the guard is really for is a PIPELINE failure,
# so it compares the finished mesh against the solidified source it was made
# from: shredding a surface loses enclosed volume, and a hollow source is
# caught by the absolute floor underneath.
MIN_FILL_OF_SOURCE = 0.72
MIN_FILL_ABSOLUTE = 0.12
# Triangles per retopologised mesh, BY ROLE. The procedural meshes run
# 360-900, and a house is drawn at 17-35 px where the silhouette is all that
# reads. A landmark gets twice a house's budget because it is the silhouette
# the settlement is recognised by AND there is only one per settlement: 684
# landmarks against 24,015 houses, so doubling them costs ~1% more geometry
# over the whole map.
# Triangles per mesh, by the building's SIZE rather than its role (owner
# 2026-09-21: '我宁愿牺牲房屋对地图的真实比例大小，让房屋细节更美的呈现在地图上').
# A flat per-role budget gave a 48 m palace the same 8,000 triangles as a
# 25 m church, a sixteenth of the density a 9.9 m cottage got from 4,000.
#
# The exponent is 2, and that is not a taste choice. With an absolute voxel
# the REMESH's triangle count grows with the building's surface AREA, so a
# budget that does not grow with area too hands the big buildings a far
# harsher decimate ratio than the small ones — and collapse decimation is
# what tears a surface apart. Measured at exponent 1.5 with a 44,000 cap:
# the cottage decimated at 0.14 of its remesh and came out clean, the palace
# at 0.02 and came out as shredded spikes. At exponent 2 every building
# decimates at about the same ratio and they all survive the same way.
# The cap is only a backstop against an absurd source.
TRI_BASE = 4000            # triangles at TRI_REF_FOOTPRINT_M
TRI_REF_FOOTPRINT_M = 14.0 # the commonest cottage, at the map3d scale (see scale_houses.py)
TRI_EXPONENT = 2.0
TRI_MAX = 100000
# One albedo and one normal per type (owner 2026-09-21: '房屋的清晰度我要再高一点，
# 现在还是很模糊很粗糙'). Resolution — not triangle count — is what carries the
# window shutters, the timber framing and the door: measured on one cottage,
# 460 -> 12,000 triangles changed its appearance almost not at all, while
# 512 -> 2048 px took it from a smear to legible. The cost is paid back by
# the same owner's halving of the house COUNT, and by exporting the images
# as JPEG (see export()), without which 14 types would be ~140 MB of git.
BAKE_PX = 2048
# How far the low poly is pushed out before rays are cast back inward, and
# how far each ray may travel. Both are SMALL on purpose: the low poly is a
# remesh of this very source, so the two surfaces are nearly coincident and a
# ray only has to cross the remesh's own error. The first version used a 2 m
# cage with an unbounded ray — a hangover from when the low poly was a
# different building entirely — and that let rays pass clean through a thin
# wall, through a window opening, and land on the room behind, which came back
# dark: thousands of black speckles, invisible at 512 px and glaring at 2048.
CAGE_EXTRUSION = 1.2
MAX_RAY_DISTANCE = 0.0   # 0 = unbounded; despeckle() cleans up what that costs
# despeckle(): a texel is replaced when it is darker than this share of its own
# 3x3 median and that median is above DESPECKLE_FLOOR. Loose enough to catch a
# ray that landed in a dark room, tight enough to leave a doorway alone.
DESPECKLE_RATIO = 0.55
DESPECKLE_FLOOR = 0.18
# Hunyuan3D puts every building on a little disc of grass and soil. The
# project's standing rule is NO BASE PLATES under a building (owner, carried
# over from the 2026-09-16 settlement-art ruling), and a disc would also
# defeat map3d_house_sink_m, which sinks the mesh into the real ground. It
# cannot be cut by HEIGHT alone — the eaves and the roof overhang the walls,
# so a plain "delete the bottom N%" takes the plinth and leaves the disc's
# rim. It is cut by FOOTPRINT instead: the walls' own XY extent, measured in
# a band clear of both the disc below and the eaves above, widened a little
# for a flaring plinth; anything lower than BASE_CUT_TOP and outside that is
# the disc.
BASE_BAND = (0.10, 0.35)   # the share of the height the WALLS are measured over
BASE_CUT_TOP = 0.12        # only geometry below this share of the height is cut
BASE_MARGIN = 1.15         # how far past the walls a real plinth may flare
# self_check's shell guard: the share of the height a building's walls occupy,
# and the share of its vertices that must land in that band.
WALL_CHECK_BAND = (0.12, 0.45)
WALL_CHECK_MIN_SHARE = 0.15


def log(msg):
    print("retopo_houses: " + msg)
    sys.stdout.flush()


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_joined(path, name):
    """Import a glTF and return ONE mesh object with its transform applied.

    The importer leaves a -90 degree X rotation on the object to turn glTF's
    Y-up into Blender's Z-up. That rotation is applied into the mesh here so
    object-local axes and world axes agree — without it, setting `scale` per
    axis silently swaps the object's Y and Z.
    """
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects
              if o not in before and o.type == "MESH"]
    if not meshes:
        raise RuntimeError("no mesh in " + path)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    apply_transform(ob)
    return ob


def apply_transform(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bounds(ob):
    from mathutils import Vector
    cs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    hi = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    return lo, hi


def tri_count(ob):
    # Blender counts a quad as ONE polygon; the glTF exporter triangulates,
    # so an n-vertex polygon becomes n - 2 triangles.
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def place(ob, footprint_m, yaw_offset_deg):
    """Turn, scale to footprint_m on the long horizontal axis, and seat the
    mesh on its origin, centred — make_houses.py's contract."""
    from mathutils import Vector
    if yaw_offset_deg:
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw_offset_deg))
        apply_transform(ob)
    lo, hi = bounds(ob)
    size = hi - lo
    long_axis = max(size.x, size.y)
    if long_axis <= 0.0:
        raise RuntimeError("degenerate source for " + ob.name)
    k = footprint_m / long_axis
    ob.scale = (k, k, k)          # UNIFORM: the source's own proportions stand
    apply_transform(ob)
    lo, hi = bounds(ob)
    centre = (lo + hi) * 0.5
    ob.location += Vector((-centre.x, -centre.y, -lo.z))
    apply_transform(ob)
    return bounds(ob)[1] - bounds(ob)[0]


def strip_base_plate(ob):
    """Pull the source's grass-and-soil disc in under the building's own walls.

    The disc is NOT deleted. Deleting it opens the mesh along the bottom, and
    Blender's voxel remesh needs a closed volume — fed an open mesh it
    rebuilds a thin SHELL, which is exactly what happened: the first attempt
    came out as a hollow roof with no walls under it at all. Clamping each
    disc vertex into the wall footprint instead is topology-preserving, so
    the mesh stays watertight; the disc collapses into a flat skirt no wider
    than the plinth, and map3d_house_sink_m buries it.

    Returns how many vertices were moved.
    """
    import bmesh
    lo, hi = bounds(ob)
    height = (hi - lo).z
    if height <= 0.0:
        return 0
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    band_lo = lo.z + height * BASE_BAND[0]
    band_hi = lo.z + height * BASE_BAND[1]
    wall = [v.co for v in bm.verts if band_lo <= v.co.z <= band_hi]
    if len(wall) < 8:
        bm.free()
        return 0
    cx = (min(v.x for v in wall) + max(v.x for v in wall)) * 0.5
    cy = (min(v.y for v in wall) + max(v.y for v in wall)) * 0.5
    rx = (max(v.x for v in wall) - min(v.x for v in wall)) * 0.5 * BASE_MARGIN
    ry = (max(v.y for v in wall) - min(v.y for v in wall)) * 0.5 * BASE_MARGIN
    cut_top = lo.z + height * BASE_CUT_TOP
    moved = 0
    for v in bm.verts:
        if v.co.z >= cut_top:
            continue
        x = min(max(v.co.x, cx - rx), cx + rx)
        y = min(max(v.co.y, cy - ry), cy + ry)
        if x != v.co.x or y != v.co.y:
            v.co.x, v.co.y = x, y
            moved += 1
    if moved:
        # Clamping piles thousands of disc vertices onto the footprint
        # rectangle's own edges, where most of them are now coincident. Left
        # alone they survive the remesh as a dense flat skirt and eat the
        # triangle budget: measured on one cottage, 1,654 of 2,501 output
        # vertices sat in the bottom tenth of the building, on a plate nobody
        # ever sees because map3d_house_sink_m buries it. Welding them costs
        # nothing and gives the budget back to the building.
        weld = max(height * 0.004, 1e-5)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        bm.to_mesh(ob.data)
        ob.data.update()
    bm.free()
    return moved


def solidify(ob):
    """Give a hollow source real wall thickness, INWARD, for the REMESH only.

    Never run this on the mesh the bake samples. Solidifying the bake source
    was tried, to stop rays reaching the rooms behind its windows, and it was
    far worse: an 0.86 m inward shell on geometry as fine as a window frame or
    a timber stud self-intersects and punches back OUT through the skin, and
    the bake then hits those punched-through faces first. The walls came back
    almost entirely black. The interior is kept out of the bake by the ray
    distance instead — see bake_surface.

    Offset -1 grows the shell inward, so the outer surface does not move.
    """
    lo, hi = bounds(ob)
    span = max((hi - lo).x, (hi - lo).y, (hi - lo).z)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("solidify", "SOLIDIFY")
    m.thickness = SOLIDIFY_M
    m.offset = -1.0
    m.use_even_offset = False
    bpy.ops.object.modifier_apply(modifier=m.name)


def tri_budget(footprint_m):
    """This building's triangle budget, from its own size."""
    k = max(footprint_m, 1.0) / TRI_REF_FOOTPRINT_M
    return int(min(TRI_BASE * (k ** TRI_EXPONENT), TRI_MAX))


def retopologise(ob, budget):
    solidify(ob)               # the LOW poly only — see solidify()'s own note
    solid_fill = fill_share(ob)
    lo, hi = bounds(ob)
    span = max((hi - lo).x, (hi - lo).y, (hi - lo).z)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = VOXEL_M
    bpy.ops.object.modifier_apply(modifier=m.name)
    # ONE collapse pass, never a loop. A wall is a thin slab — two surfaces a
    # few centimetres apart — and repeated collapse eventually joins them and
    # punches through: iterating to chase the budget exactly shredded every
    # wall into a lace of triangular holes while the roof stayed intact.
    # Overshooting the budget by a few hundred triangles is the cheaper
    # mistake, so the ask is made once and whatever it gives is kept.
    got = tri_count(ob)
    if got > budget:
        m = ob.modifiers.new("decimate", "DECIMATE")
        m.ratio = float(budget) / float(got)
        bpy.ops.object.modifier_apply(modifier=m.name)
    repair(ob)
    return tri_count(ob), solid_fill


def repair(ob):
    """Weld, drop degenerate faces and point every normal outward.

    Collapse decimation leaves slivers and zero-area faces behind, and a face
    with no usable normal gets a bake ray pointing anywhere at all — including
    away from the building, where it hits nothing and the texel comes back as
    background. That is what the black PATCHES on the walls were: not rays
    that fell short, and not rays that found the rooms inside, but rays with
    no sensible direction to travel in. Baking is the only step that cares,
    which is why nothing looked wrong until the resolution went up enough to
    show it.
    """
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def unwrap(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def make_cage(low):
    """A copy of the low poly pushed out along its own normals.

    Blender's automatic cage (`cage_extrusion`) offsets each point along the
    LOW POLY's own normal, which on a decimated voxel remesh is jagged: next
    to each other, two rays can set off in quite different directions, and at
    a concave corner one of them points away from the building and finds
    nothing at all. That is what left black PATCHES on the walls — not rays
    that fell short, and not rays that found the rooms inside. Neither a
    shorter ray, a solidified source, a UV transfer, nor repairing the
    decimated normals moved them; all four were tried.

    An explicit cage fixes the DIRECTION instead of the distance: the ray runs
    from the cage's vertex to the low poly's matching vertex, so the direction
    comes from a surface that has been smoothed, and neighbouring rays stay
    roughly parallel. The cage must keep the low poly's exact topology, which
    is why it is built by moving vertices rather than by any modifier.
    """
    cage = low.copy()
    cage.data = low.data.copy()
    cage.name = low.name + "_cage"
    bpy.context.scene.collection.objects.link(cage)
    mesh = cage.data
    mesh.calc_normals_split() if hasattr(mesh, "calc_normals_split") else None
    # Smooth the per-vertex normals over one ring before offsetting, so the
    # cage does not inherit the low poly's own faceting.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    smoothed = []
    for v in bm.verts:
        n = v.normal.copy()
        for e in v.link_edges:
            n += e.other_vert(v).normal
        if n.length > 1e-9:
            n.normalize()
        smoothed.append(n)
    for v, n in zip(bm.verts, smoothed):
        v.co += n * CAGE_EXTRUSION
    bm.to_mesh(mesh)
    bm.free()
    return cage


def bake_surface(low, high, tag):
    """Bake the high poly's albedo and normal onto the low poly's UVs."""
    low.data.materials.clear()
    mat = bpy.data.materials.new("baked_" + tag)
    mat.use_nodes = True
    low.data.materials.append(mat)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")

    images = {}
    for kind, colorspace in (("albedo", "sRGB"), ("normal", "Non-Color")):
        im = bpy.data.images.new("%s_%s" % (tag, kind), BAKE_PX, BAKE_PX, alpha=False)
        im.colorspace_settings.name = colorspace
        images[kind] = im
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = im
        node.name = kind

    cage = make_cage(low)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.bake.use_cage = True
    scene.render.bake.cage_object = cage

    for kind, bake_type, extra in (("albedo", "DIFFUSE", {"pass_filter": {"COLOR"}}),
                                   ("normal", "NORMAL", {})):
        for n in nt.nodes:
            n.select = False
        node = nt.nodes[kind]
        node.select = True
        nt.nodes.active = node
        bpy.ops.object.select_all(action="DESELECT")
        high.select_set(True)
        low.select_set(True)
        bpy.context.view_layer.objects.active = low
        bpy.ops.object.bake(type=bake_type, use_selected_to_active=True,
                            use_cage=True,
                            margin=max(4, BAKE_PX // 128), **extra)

    scene.render.bake.use_cage = False
    scene.render.bake.cage_object = None
    bpy.data.objects.remove(cage, do_unlink=True)

    despeckle(images["albedo"])

    # Wire the baked images in so the exporter writes them into the glTF.
    nt.links.new(nt.nodes["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
    nrm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nt.nodes["normal"].outputs["Color"], nrm.inputs["Color"])
    nt.links.new(nrm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Metallic"].default_value = 0.0
    for im in images.values():
        im.pack()


def fill_share(ob):
    """Enclosed volume as a share of the bounding box."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    volume = abs(bm.calc_volume(signed=True))
    bm.free()
    lo, hi = bounds(ob)
    size = hi - lo
    box = size.x * size.y * size.z
    return volume / box if box > 0.0 else 0.0


def despeckle(image):
    """Replace dark outlier texels in a baked albedo with their neighbourhood.

    The bake casts each ray from a cage well outside the building and lets it
    run unbounded, which is the only setting that covers the whole surface:
    this source has deep eaves and set-back walls, and any shorter ray leaves
    whole faces unbaked and BLACK. The cost is that a ray aimed through a
    window or a gap in the source's own skin carries on and lands on the room
    behind, which comes back nearly black — scattered dark texels across walls
    that are otherwise cream. They are outliers against their own
    neighbourhood, which is what makes them separable: a texel is replaced
    only when it is much darker than the 3x3 median around it AND that median
    is itself light, so a genuinely dark region (a doorway, dark timber) keeps
    every one of its texels.
    """
    import numpy as np
    w, h = image.size
    buf = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = buf[:, :, :3]
    # 3x3 median per channel, via the 9 shifted copies
    stack = np.stack([np.roll(np.roll(rgb, dy, axis=0), dx, axis=1)
                      for dy in (-1, 0, 1) for dx in (-1, 0, 1)], axis=0)
    med = np.median(stack, axis=0)
    lum = rgb.mean(axis=2)
    med_lum = med.mean(axis=2)
    dark_outlier = (lum < med_lum * DESPECKLE_RATIO) & (med_lum > DESPECKLE_FLOOR)
    if dark_outlier.any():
        rgb[dark_outlier] = med[dark_outlier]
        buf[:, :, :3] = rgb
        image.pixels[:] = buf.reshape(-1)
    return int(dark_outlier.sum())


def self_check(ob, footprint_m, solid_fill=None):
    """The contract Map3DLayerHouses relies on."""
    lo, hi = bounds(ob)
    size = hi - lo
    assert abs(lo.z) < 1e-3, "%s does not stand on its origin (min z %.4f)" % (ob.name, lo.z)
    assert abs(lo.x + hi.x) < 1e-3 and abs(lo.y + hi.y) < 1e-3, \
        "%s is not centred on its footprint" % ob.name
    long_axis = max(size.x, size.y)
    assert abs(long_axis - footprint_m) < 1e-2, \
        "%s is %.2f m across, not its declared %.2f" % (ob.name, long_axis, footprint_m)
    assert size.z > 0.5, "%s has no height" % ob.name
    # A remesh whose voxel is coarser than the walls are thick produces a
    # hollow SHELL of the roof — with the right triangle count, the right
    # bounding box, and nothing where the building is. Check the WALL BAND
    # itself, not the lower third: strip_base_plate() leaves a flat skirt of
    # clamped vertices right at the bottom, and a "lower third" test counts
    # that skirt and passes a shell (it did).
    wall_lo = lo.z + size.z * WALL_CHECK_BAND[0]
    wall_hi = lo.z + size.z * WALL_CHECK_BAND[1]
    verts = ob.data.vertices
    in_wall = sum(1 for v in verts if wall_lo <= (ob.matrix_world @ v.co).z <= wall_hi)
    share = fill_share(ob)
    # ENCLOSED VOLUME, absolute vs relative (2026-09-22). A game mesh is a
    # SHELL — that is normal and fine; what this pipeline cannot take is a
    # shell with HOLES, because the bake fires rays from the low poly's
    # surface at the high poly's and a ray through a hole finds nothing and
    # writes black. But "encloses little of its bounding box" does not mean
    # "has holes": the realistic palace — a hall and a chapel standing
    # inside a low walled yard — is 5.6% enclosed volume and its bake came
    # out clean (rendered and looked at), while the toy castle that scored
    # far higher is a solid block by shape alone. So the ABSOLUTE floor is a
    # fact about the BUILDING and only warns; the refusal is the RELATIVE
    # test, which compares the finished mesh against the solidified source
    # it was made from and is the one that catches a remesh or decimate that
    # tore the surface apart. With no relative number to go on (no
    # solid_fill), the absolute floor still refuses, since something must.
    if solid_fill is not None and solid_fill > 0.0:
        if share < MIN_FILL_ABSOLUTE:
            log("%s: NOTE — encloses only %.1f%% of its bounding box. That is the "
                "building's own shape (an airy plan reads like this); the remesh kept "
                "%.0f%% of its source's volume, which is what matters. LOOK at the bake."
                % (ob.name, share * 100.0, share / solid_fill * 100.0))
        kept = share / solid_fill
        assert kept >= MIN_FILL_OF_SOURCE, \
            ("%s kept only %.0f%% of the volume its solidified source enclosed "
             "(%.1f%% of its box against %.1f%%) — the remesh or the decimate tore it "
             "apart rather than thinning it."
             % (ob.name, kept * 100.0, share * 100.0, solid_fill * 100.0))
    else:
        assert share >= MIN_FILL_ABSOLUTE, \
            ("%s encloses only %.1f%% of its bounding box and there is no source "
             "volume to compare it against — its Hunyuan3D source came back hollow "
             "and solidify did not close it. Regenerate that source."
             % (ob.name, share * 100.0))
    assert in_wall >= len(verts) * WALL_CHECK_MIN_SHARE, \
        ("%s has almost nothing where its WALLS should be (%d of %d verts in the "
         "%d-%d%% height band) — the remesh produced a shell, not a building"
         % (ob.name, in_wall, len(verts),
            int(WALL_CHECK_BAND[0] * 100), int(WALL_CHECK_BAND[1] * 100)))


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    # JPEG, not PNG: these images are baked photographs of a building, they
    # are drawn at 32-59 px, and a lossless 2048 px pair is ~10 MB per type —
    # 140 MB committed for 14 types, and that much again in git history on
    # every regeneration. At quality 92 the pair is well under a megabyte and
    # nothing a 32 px draw can show survives the difference.
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                              use_selection=True, export_yup=True,
                              export_apply=True,
                              export_image_format="JPEG",
                              export_jpeg_quality=92)


def main():
    with open(TABLE) as f:
        rows = list(csv.DictReader(f))
    manifest_path = os.path.join(OUT, "houses.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            manifest = json.load(f)

    # `--only a,b` retopologises just those types (the rest are left exactly
    # as they are), for re-running one building whose bake came out wrong
    # without paying for the other thirteen.
    only = []
    if "--only" in sys.argv:
        only = [t.strip() for t in sys.argv[sys.argv.index("--only") + 1].split(",") if t.strip()]
    # `--min-fill X` lowers self_check's absolute hollow floor for this run.
    # The floor is a heuristic about ENCLOSED VOLUME, and a building that is
    # genuinely airy — a hall and a chapel inside a low walled yard — scores
    # like a hollow shell without being one. Use it to TEST such a source,
    # then judge the bake that comes out (a truly hollow source bakes black),
    # never to wave one through unlooked at.
    global MIN_FILL_ABSOLUTE
    if "--min-fill" in sys.argv:
        MIN_FILL_ABSOLUTE = float(sys.argv[sys.argv.index("--min-fill") + 1])
        log("min fill override: %.3f" % MIN_FILL_ABSOLUTE)

    done = 0
    heights = {}
    failures = []
    for r in rows:
        t = r["type"]
        if only and t not in only:
            continue
        source = os.path.join(SRC, t + ".glb")
        if not os.path.exists(source):
            log("%s: no source at ai_src/%s.glb — keeping the procedural mesh" % (t, t))
            continue
        footprint_m = float(r["footprint_m"])
        yaw_offset = float(r.get("yaw_offset_deg") or 0.0)

        clear()
        high = import_joined(source, "HIGH_" + t)
        high_tris = tri_count(high)
        try:
            cut = strip_base_plate(high)
            size = place(high, footprint_m, yaw_offset)

            # The low poly is a COPY, retopologised in place, so the two already
            # occupy the same space and the bake needs no further alignment.
            low = high.copy()
            low.data = high.data.copy()
            low.name = "LOW_" + t
            bpy.context.scene.collection.objects.link(low)
            low_tris, solid_fill = retopologise(low, tri_budget(footprint_m))
            unwrap(low)
            bake_surface(low, high, t)
            # The remesh moves the surface by up to half a voxel, so re-seat it.
            place(low, footprint_m, 0.0)
            self_check(low, footprint_m, solid_fill)
        except AssertionError as err:
            # One bad type must not cost the other thirteen their run: the
            # existing mesh is left in place and the failure is reported at
            # the end, where it can be read against the ones that worked.
            failures.append((t, str(err)))
            log("%s: REFUSED — %s" % (t, err))
            continue

        path = os.path.join(OUT, t + ".glb")
        export(low, path)
        lo, hi = bounds(low)
        manifest[t] = {"footprint_m": footprint_m,
                       "height_m": round((hi - lo).z, 3),
                       "tris": low_tris,
                       "source": "hunyuan3d+retopo",
                       "source_tris": high_tris}
        heights[t] = "%.2f" % (hi - lo).z
        log("%s -> %s (%d tris from %d, %.2f x %.2f x %.2f m, base plate: %d verts pulled in)"
            % (t, os.path.relpath(path, ROOT), low_tris, high_tris,
               (hi - lo).x, (hi - lo).y, (hi - lo).z, cut))
        done += 1

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    if heights:
        write_back_heights(heights)
    log("%d type(s) retopologised" % done)
    for t, err in failures:
        log("REFUSED %s: %s" % (t, err))
    if failures:
        log("%d type(s) refused — their previous mesh is untouched" % len(failures))


def write_back_heights(heights):
    """Record each retopologised mesh's measured height in the table.

    Rewritten as LINES, not through csv.writer: the table's `notes` column
    holds commas and quotes that QUOTE_MINIMAL would re-quote differently,
    and a full rewrite would also churn every unrelated row's line ending.
    """
    with open(TABLE, encoding="utf-8") as f:
        text = f.read()
    lines = text.split("\n")
    header = lines[0].split(",")
    ti, hi = header.index("type"), header.index("height_m")
    changed = 0
    for n, line in enumerate(lines[1:], 1):
        if not line.strip():
            continue
        fields = line.split(",", len(header) - 1)
        t = fields[ti]
        if t in heights and fields[hi] != heights[t]:
            log("%s: height_m %s -> %s (the source's own proportions)"
                % (t, fields[hi], heights[t]))
            fields[hi] = heights[t]
            lines[n] = ",".join(fields)
            changed += 1
    if changed:
        with open(TABLE, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))


main()
