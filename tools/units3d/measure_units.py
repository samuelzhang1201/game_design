"""Measure and photograph the AI sources, so the skeleton is built from the
mesh instead of from an assumption about which way it faces.

  blender -b --factory-startup --python tools/units3d/measure_units.py -- OUTDIR
"""

import bpy, os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_common import (ROOT, SRC, rows, clear, import_joined, place,
                         bounds, tri_count, profile, log)

OUTDIR = sys.argv[-1] if "--" in sys.argv else "/tmp"


def set_engine(scene):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            return
        except TypeError:
            continue


def shoot(ob, tag, hi):
    """Four orthographic views: front (-Y), right (+X), back (+Y), top."""
    scene = bpy.context.scene
    set_engine(scene)
    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.5, 0.52, 0.55, 1.0)
    bg.inputs["Strength"].default_value = 1.4
    scene.world = world

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55), 0.0, math.radians(35))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(hi.x - 0, hi.z) * 2.4
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    mid = hi.z * 0.5
    d = 10.0
    views = {
        "front": ((0, -d, mid), (math.radians(90), 0, 0)),
        "right": ((d, 0, mid), (math.radians(90), 0, math.radians(90))),
        "back":  ((0, d, mid), (math.radians(90), 0, math.radians(180))),
        "top":   ((0, 0, d), (0, 0, 0)),
    }
    for name, (loc, rot) in views.items():
        cam.location = loc
        cam.rotation_euler = rot
        if name == "top":
            cam_data.ortho_scale = max(hi.x, hi.y) * 2.6
        scene.render.filepath = os.path.join(OUTDIR, "%s_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)


def main():
    for row in rows():
        clear()
        path = os.path.join(SRC, row["source"])
        if not os.path.exists(path):
            log("no source for " + row["code"])
            continue
        ob = import_joined(path, row["code"])
        log("%s raw tris %d" % (row["code"], tri_count(ob)))
        lo, hi = place(ob, float(row["height_m"]), float(row["yaw_offset_deg"]))
        log("%s box  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f"
            % (row["code"], lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
        log("%s profile  frac  n      xmin   xmax   ymin   ymax" % row["code"])
        for f, n, x0, x1, y0, y1 in profile(ob, 20):
            log("   %.2f  %6d  %6.3f %6.3f  %6.3f %6.3f" % (f, n, x0, x1, y0, y1))
        shoot(ob, row["code"], hi)


main()
