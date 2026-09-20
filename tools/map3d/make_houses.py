"""Generate the 3D map's house meshes (spec 2026-09-20 §2).

  blender -b --factory-startup --python tools/map3d/make_houses.py

Reads data/map3d_houses.csv and writes one glTF per type into
assets/map3d_houses/, plus houses.json. Every mesh stands ON its origin
(min y = 0, centred on its footprint) and faces +Z, because
Map3DLayerHouses places it with a yaw and sinks it by map3d_house_sink_m —
a mesh that carries its own base plate or offset would defeat both.

Low poly on purpose: at the owner's 800 m closest zoom a house is 9-17 px,
where the silhouette and the roof colour are all that read.
"""
import csv
import json
import math
import os
import sys

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


def gable_roof(name, w, d, h, z, overhang=0.5):
    """A ridged roof as a 6-vertex prism: the silhouette that separates a
    house from a box at 12 px."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    verts = [(-w2, -d2, z), (w2, -d2, z), (w2, d2, z), (-w2, d2, z),
             (0, -d2, z + h), (0, d2, z + h)]
    faces = [(0, 1, 4), (2, 3, 5), (1, 2, 5, 4), (3, 0, 4, 5), (0, 3, 2, 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return ob


def hip_tower(name, w, h, z):
    """A square tower with a spire — a church or a palace's landmark mass."""
    body = box(name + "_body", w, w, h, z)
    spire_h = h * 0.55
    verts = [(-w / 2, -w / 2, z + h), (w / 2, -w / 2, z + h),
             (w / 2, w / 2, z + h), (-w / 2, w / 2, z + h), (0, 0, z + h + spire_h)]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    mesh = bpy.data.meshes.new(name + "_spire")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    spire = bpy.data.objects.new(name + "_spire", mesh)
    bpy.context.collection.objects.link(spire)
    return body, spire


# type -> a builder returning (wall objects, roof objects)
def build(type_name, fp, ht):
    """One house. `fp` is the footprint's longest side in metres, `ht` the
    total height including the roof."""
    walls, roofs = [], []
    if type_name.startswith("cottage") or type_name == "byre":
        wall_h = ht * 0.55
        w, d = fp * 0.8, fp * 0.6
        walls.append(box("wall", w, d, wall_h))
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.35))
        if type_name == "cottage_b":
            walls.append(box("lean", w * 0.45, d * 0.5, wall_h * 0.7))
            walls[-1].location.x = w * 0.6
    elif type_name.startswith("townhouse") or type_name == "workshop":
        wall_h = ht * 0.68
        w, d = fp * 0.7, fp * 0.65
        walls.append(box("wall", w, d, wall_h))
        if type_name == "townhouse_b":
            jetty = box("jetty", w * 1.12, d * 1.12, wall_h * 0.35, wall_h * 0.6)
            walls.append(jetty)
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.4))
    elif type_name == "longhouse":
        wall_h = ht * 0.5
        w, d = fp * 0.95, fp * 0.34
        walls.append(box("wall", w, d, wall_h))
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.5))
    elif type_name == "barn":
        wall_h = ht * 0.45
        w, d = fp * 0.9, fp * 0.5
        walls.append(box("wall", w, d, wall_h))
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.6))
    elif type_name in ("chapel", "church", "church_tower"):
        nave_h = ht * (0.32 if type_name == "church_tower" else 0.5)
        w, d = fp * 0.78, fp * 0.42
        walls.append(box("nave", w, d, nave_h))
        roofs.append(gable_roof("nave_roof", w, d, nave_h * 0.55, nave_h, overhang=0.35))
        tower_w = d * 0.72
        tower_h = ht * (0.82 if type_name == "church_tower" else 0.62)
        body, spire = hip_tower("tower", tower_w, tower_h, 0.0)
        body.location.x = -w * 0.5
        spire.location.x = -w * 0.5
        walls.append(body)
        roofs.append(spire)
    elif type_name == "palace":
        w, d = fp * 0.85, fp * 0.5
        wall_h = ht * 0.55
        walls.append(box("hall", w, d, wall_h))
        roofs.append(gable_roof("hall_roof", w, d, ht * 0.2, wall_h, overhang=0.6))
        for sx in (-1, 1):
            body, spire = hip_tower("wing%d" % sx, d * 0.5, ht * 0.72, 0.0)
            body.location.x = sx * w * 0.5
            spire.location.x = sx * w * 0.5
            walls.append(body)
            roofs.append(spire)
    else:
        raise SystemExit("make_houses: no builder for type %r" % type_name)
    return walls, roofs


def join_and_normalise(name, objs, fp, ht):
    """One object at the origin, min z = 0, no bigger than its claims."""
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
    s = min(fp / span if span > 0 else 1.0, ht / tall if tall > 0 else 1.0)
    for v in ob.data.vertices:
        v.co *= s
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
