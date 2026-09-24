"""Turn the Hunyuan3D 2.1 house sources into the game's meshes by WELDING
and DECIMATING them, keeping the paint's own UVs and texture (owner
2026-09-23: "平衡清晰度和游戏performance ... 模型也不需要太细节，但是一定要清晰").

  blender -b --factory-startup --python tools/map3d/decimate_houses.py -- [--only a,b]

Reads data/map3d_houses.csv and, for every type with a source at
assets/hunyuan_ref/houses/sources/<type>.glb (tools/map3d/gen_house_sources.py),
writes assets/map3d_houses/<type>.glb — the files retopo_houses.py wrote
before it, under the same contract (one mesh standing ON its origin,
centred on its footprint, facing +Z, its long horizontal side footprint_m),
and records height_m / tris in the table and houses.json.

Why this and not retopo_houses.py for these sources. retopo's voxel remesh
and re-bake exist for the 2026-09-21 sources: ~500k-triangle cloud
generations with base discs, hollow rooms and no usable UVs. A local
Hunyuan3D 2.1 paint is different: a closed 40k-triangle marching-cubes
surface with an xatlas atlas and its own painted albedo, no disc and no
black between islands. Measured on cottage_a, the source welded and
collapse-decimated to 1,500 triangles reads the same as the retopo's 5,896
at every size a house is drawn — and keeps the paint's texels rather than a
re-bake of them. Welding FIRST is the whole trick: the paint stores a vertex
per face corner at every UV seam, and collapse on that soup shreds the
mesh into confetti (tried: 1,000-4,000 triangles, all confetti).

Budgets go with the footprint to the 1.5 power (TRI_BASE at
TRI_REF_FOOTPRINT_M): a cottage ~2,000, a church ~6,000, the palace ~16,000 —
against 3,000-94,000 from the retopo, whose average house of ~8,000 made
5,000 instances 40 million triangles before the shadow pass.
"""

import bmesh
import bpy
import csv
import json
import math
import os
import sys
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "data", "map3d_houses.csv")
OUT = os.path.join(ROOT, "assets", "map3d_houses")
SRC = os.path.join(ROOT, "assets", "hunyuan_ref", "houses", "sources")

TRI_BASE = 1600
TRI_REF_FOOTPRINT_M = 14.0
TRI_EXPONENT = 1.5
# Faces meeting at more than this are drawn with a hard edge: a wall meets
# its neighbour and the eaves meet the wall crisply, while the thatch's own
# undulation stays smooth.
SHARP_DEG = 40.0
# Hunyuan's metallic-roughness map is metallic ~0.03, roughness ~0.8 all over
# — a second 1024 px texture per type that says "matte". It is dropped for
# these constants.
ROUGHNESS = 0.85
WELD_SHARE = 1e-4          # of the building's longest side
# The paint comes back LIGHTER and warmer than the reference it was painted
# from (cottage_a: atlas mean RGB 149/108/69 against the reference's
# 113/92/67), and in the game's light that read as white-washed. The atlas
# is scaled by ONE gain so its mean LUMINANCE meets the reference
# foreground's — the approved 2D picture is the authority on value — and
# only ever darkened (GRADE_GAIN). Per-channel matching was tried and
# shifted hue: an atlas's area is not the picture's (cottage_b's white
# walls fill more of its atlas than of its reference), so it turned the
# golden thatch beige.
REF_DIR = os.path.join(ROOT, "assets", "flux", "out", "house_ref")
REF_BACKGROUND = 235       # a reference pixel this light on every channel is paper
GRADE_GAIN = (0.6, 1.0)
# Two corrections the independent critic found at map size (2026-09-24):
# the paint gives grey slate a cold SKY-BLUE cast that no ground on the map
# has — it read as plastic — so any texel bluer than it is red and green is
# pulled BLUE_PULL of the way to a warm grey of its own luminance; and a
# dark-brown roof comes back near-black with its courses gone, so a texel
# darker than DARK_FLOOR in luminance is lifted towards it (DARK_LIFT, a
# power: 0 leaves it, 1 lifts it to the floor).
BLUE_PULL = 0.75
WARM_GREY = (1.03, 1.0, 0.94)
DARK_FLOOR = 0.22
DARK_LIFT = 0.45
LUMA = (0.2126, 0.7152, 0.0722)


def log(msg):
    print("decimate_houses: " + msg, flush=True)


def tri_budget(footprint_m):
    return int(TRI_BASE * (max(footprint_m, 1.0) / TRI_REF_FOOTPRINT_M) ** TRI_EXPONENT)


def apply_transform(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bounds(ob):
    cs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    hi = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    return lo, hi


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def import_joined(path, name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
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


def place(ob, footprint_m, yaw_offset_deg):
    """Turn, scale uniformly so the long horizontal side is footprint_m, and
    stand the mesh on its origin, centred."""
    if yaw_offset_deg:
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw_offset_deg))
        apply_transform(ob)
    lo, hi = bounds(ob)
    k = footprint_m / max((hi - lo).x, (hi - lo).y)
    ob.scale = (k, k, k)
    apply_transform(ob)
    lo, hi = bounds(ob)
    c = (lo + hi) * 0.5
    ob.location += Vector((-c.x, -c.y, -lo.z))
    apply_transform(ob)


def weld(ob):
    lo, hi = bounds(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=max(hi - lo) * WELD_SHARE)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def decimate(ob, budget):
    got = tri_count(ob)
    if got <= budget:
        return
    m = ob.modifiers.new("decimate", "DECIMATE")
    m.ratio = float(budget) / float(got)
    m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


def shade(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(SHARP_DEG))


def matte(ob, tag):
    """One material: the painted albedo, constant roughness, no metal."""
    for mat in ob.data.materials:
        if mat is None or mat.node_tree is None:
            continue
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        for name in ("Metallic", "Roughness"):
            for link in list(bsdf.inputs[name].links):
                mat.node_tree.links.remove(link)
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = ROUGHNESS
        for n in list(nodes):
            if n.type in ("SEPARATE_COLOR", "SEPARATE_RGB"):
                nodes.remove(n)
        for n in list(nodes):
            if n.type == "TEX_IMAGE" and not n.outputs["Color"].links:
                nodes.remove(n)
        for n in nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                n.image.name = "%s_albedo" % tag
        mat.name = tag


def grade(ob, tag):
    """Match the painted atlas's mean colour to its reference's (see GRADE_GAIN)."""
    import numpy as np
    ref_path = os.path.join(REF_DIR, tag + ".png")
    if not os.path.exists(ref_path):
        log("%s: no reference at %s — colour left as painted" % (tag, ref_path))
        return None
    ref = bpy.data.images.load(ref_path)
    r = np.array(ref.pixels[:], dtype=np.float32).reshape(-1, 4)[:, :3]
    want = r[r.min(axis=1) < REF_BACKGROUND / 255.0].mean(axis=0)
    bpy.data.images.remove(ref)
    for mat in ob.data.materials:
        for n in mat.node_tree.nodes:
            if n.type != "TEX_IMAGE" or n.image is None:
                continue
            im = n.image
            px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
            luma = np.array(LUMA, dtype=np.float32)
            gain = float(np.clip((want @ luma) / (px[:, :3].mean(axis=0) @ luma), *GRADE_GAIN))
            rgb = px[:, :3] * gain
            lum = (rgb @ luma)[:, None]
            blue = np.clip((rgb[:, 2:3] - np.maximum(rgb[:, 0:1], rgb[:, 1:2])) * 8.0, 0.0, 1.0)
            rgb = rgb + (lum * np.array(WARM_GREY, dtype=np.float32) - rgb) * blue * BLUE_PULL
            lum = np.maximum(rgb @ luma, 1e-4)[:, None]
            lift = np.where(lum < DARK_FLOOR, (DARK_FLOOR / lum) ** DARK_LIFT, 1.0)
            px[:, :3] = np.clip(rgb * lift, 0.0, 1.0)
            im.pixels[:] = px.reshape(-1)
            im.update()
            return gain
    return None


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True,
                              export_image_format="JPEG", export_jpeg_quality=92)


def write_back_heights(heights):
    """As retopo_houses.py: rewritten as LINES, so the notes column's commas
    and quotes are left exactly as they are."""
    with open(TABLE, encoding="utf-8") as f:
        lines = f.read().split("\n")
    header = lines[0].split(",")
    ti, hi = header.index("type"), header.index("height_m")
    wi, di = header.index("width_m"), header.index("depth_m")
    for n, line in enumerate(lines[1:], 1):
        if not line.strip():
            continue
        fields = line.split(",", len(header) - 1)
        if fields[ti] in heights:
            fields[wi], fields[di], fields[hi] = heights[fields[ti]]
            lines[n] = ",".join(fields)
    with open(TABLE, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    global SRC, OUT
    if "--src" in sys.argv:
        SRC = sys.argv[sys.argv.index("--src") + 1]
    if "--out" in sys.argv:   # a trial build, beside the shipped meshes
        OUT = sys.argv[sys.argv.index("--out") + 1]
    only = []
    if "--only" in sys.argv:
        only = [t for t in sys.argv[sys.argv.index("--only") + 1].split(",") if t]
    with open(TABLE) as f:
        rows = list(csv.DictReader(f))
    mpath = os.path.join(OUT, "houses.json")
    manifest = json.load(open(mpath)) if os.path.exists(mpath) else {}
    dims = {}
    for r in rows:
        t = r["type"]
        src = os.path.join(SRC, t + ".glb")
        if (only and t not in only) or not os.path.exists(src):
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        ob = import_joined(src, t)
        src_tris = tri_count(ob)
        weld(ob)
        footprint_m = float(r["footprint_m"])
        place(ob, footprint_m, float(r.get("yaw_offset_deg") or 0.0))
        decimate(ob, tri_budget(footprint_m))
        shade(ob)
        matte(ob, t)
        gain = grade(ob, t)
        place(ob, footprint_m, 0.0)
        export(ob, os.path.join(OUT, t + ".glb"))
        lo, hi = bounds(ob)
        size = hi - lo
        tris = tri_count(ob)
        # glTF is Y-up: Blender's X is the mesh's width, Blender's Y its depth.
        dims[t] = ("%.2f" % size.x, "%.2f" % size.y, "%.2f" % size.z)
        manifest[t] = {"footprint_m": footprint_m, "height_m": round(size.z, 3),
                       "tris": tris, "source": "hunyuan3d21+decimate", "source_tris": src_tris}
        log("%s: %d tris from %d, %.2f x %.2f x %.2f m, colour gain %s"
            % (t, tris, src_tris, size.x, size.y, size.z,
               "none" if gain is None else "%.2f" % gain))
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    if dims:
        write_back_heights(dims)
    log("%d type(s) built" % len(dims))


main()
