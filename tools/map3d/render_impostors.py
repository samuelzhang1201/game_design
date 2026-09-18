"""SPIKE: render each Poly Haven tree (assets/map3d/sources/polyhaven/models/<id>/<id>_1k.gltf)
as a transparent side view for a Terrain3D texture card, into
tools/map3d/trees/<id>[_<n>].png, and write trees.json with each
card's size in metres. One file may hold several trees (each root object
with meshes is rendered alone; *LOD1+ roots are skipped).
  Blender -b --factory-startup --python tools/map3d/render_impostors.py -- id ...
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "map3d", "sources", "polyhaven", "models")
OUT = os.path.join(ROOT, "assets", "map3d", "trees")
MAX_PX = 1024
ids = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def set_engine(scene):
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            return
        except TypeError:
            continue


def mesh_descendants(obj):
    out = [obj] if obj.type == "MESH" else []
    for c in obj.children:
        out += mesh_descendants(c)
    return out


def bbox(objs):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for o in objs:
        for corner in o.bound_box:
            p = o.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def lod_rank(name):
    low = name.lower()
    i = low.rfind("lod")
    if i < 0:
        return 0
    digits = "".join(ch for ch in low[i + 3:] if ch.isdigit())
    return int(digits) if digits else 0


os.makedirs(OUT, exist_ok=True)
manifest_path = os.path.join(OUT, "trees.json")
manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}

for asset_id in ids:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    set_engine(scene)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.6, 0.65, 1.0)
    bg.inputs[1].default_value = 0.8
    scene.world = world

    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, asset_id, asset_id + "_1k.gltf"))
    bpy.context.view_layer.update()
    roots = [o for o in scene.objects if o.parent is None and mesh_descendants(o)]
    roots = [r for r in roots if lod_rank(r.name) == 0]
    print(asset_id, "roots:", [r.name for r in roots])

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    cam.rotation_euler = (math.radians(90), 0, 0)  # looking along +Y
    scene.collection.objects.link(cam)
    scene.camera = cam

    for n, root in enumerate(roots):
        for other in roots:
            hide = other is not root
            for o in [other] + list(other.children_recursive):
                o.hide_render = hide
        lo, hi = bbox(mesh_descendants(root))
        size = hi - lo
        width = max(size.x, size.y)
        height = size.z
        scale = max(width, height) * 1.02
        cam_data.ortho_scale = scale
        centre = (lo + hi) / 2
        cam.location = (centre.x, lo.y - 50.0, centre.z)
        cam_data.clip_end = 1000.0
        if width >= height:
            rx, ry = MAX_PX, max(8, round(MAX_PX * height / width))
        else:
            rx, ry = max(8, round(MAX_PX * width / height)), MAX_PX
        scene.render.resolution_x = rx
        scene.render.resolution_y = ry
        key = asset_id if len(roots) == 1 else f"{asset_id}_{n}"
        scene.render.filepath = os.path.join(OUT, key + ".png")
        bpy.ops.render.render(write_still=True)
        # The frame spans ortho_scale on its longer side, so the card is that
        # much bigger than the bbox by the 1.02 margin.
        manifest[key] = {"width_m": round(scale * rx / max(rx, ry), 3),
                         "height_m": round(scale * ry / max(rx, ry), 3),
                         "px": [rx, ry], "root": root.name}
        print("rendered", key, manifest[key])

json.dump(manifest, open(manifest_path, "w"), indent=1)
