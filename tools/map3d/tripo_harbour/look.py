"""Quick looks at the Tripo harbour sources in the owner's Blender: a
Workbench render of one object (textured, studio light) from a few angles
into a PNG, for judging a source before and after processing.

    L = {}; exec(open("<repo>/tools/map3d/tripo_harbour/look.py").read(), L)
    L["shoot"](["wall_src"], "/tmp/x.png", views=("front", "side", "persp"))
"""
import math

import bpy
from mathutils import Vector


def _bounds(obs):
    pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


VIEWS = {   # direction FROM the object TO the camera
    "front": Vector((0, -1, 0.25)),
    "back": Vector((0, 1, 0.25)),
    "side": Vector((1, 0, 0.25)),
    "left": Vector((-1, 0, 0.25)),
    "persp": Vector((0.8, -1, 0.7)),
    "top": Vector((0.001, -0.001, 1)),
    "map": Vector((0.35, -1, 1.1)),
}


def shoot(names, path, view="persp", res=900, textured=True):
    """Render the named objects alone (everything else hidden from the render)
    from `view`, orthographic, framed on their box, into `path`."""
    sc = bpy.context.scene
    obs = [bpy.data.objects[n] for n in names]
    hidden = []
    for o in sc.objects:
        if o not in obs and not o.hide_render and o.type in ("MESH", "CURVE", "EMPTY"):
            o.hide_render = True
            hidden.append(o)
    lo, hi = _bounds(obs)
    c = (lo + hi) / 2
    size = (hi - lo).length
    cam_data = bpy.data.cameras.get("look_cam") or bpy.data.cameras.new("look_cam")
    cam = bpy.data.objects.get("look_cam") or bpy.data.objects.new("look_cam", cam_data)
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    d = VIEWS[view].normalized()
    cam.location = c + d * size * 2
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size * 1.02
    cam_data.clip_end = size * 10
    sc.camera = cam
    old = (sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, sc.render.filepath)
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE" if textured else "MATERIAL"
    sh.show_cavity = True
    sh.show_shadows = True
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sc.render.engine, sc.render.resolution_x, sc.render.resolution_y, sc.render.filepath = old
    for o in hidden:
        o.hide_render = False
    return path
