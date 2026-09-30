"""Photograph ONE built unit .glb from set angles into a contact sheet — for
checking a trial build that is not (yet) assets/3D/units/<code>/<code>.glb, which is
what shoot_units.py reads.

  blender -b --python tools/units3d/shoot_glb.py -- GLB OUT_PREFIX MODE

MODE: rest (six angles), close (the rider and the head), side (a man on foot from
four sides), feet (low, at the hooves),
or an action name (garrison | march | attack: eight frames from the side).
Writes OUT_PREFIX_<n>.png per shot and OUT_PREFIX_sheet.png.
"""
import bpy
import math
import sys
import mathutils
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
GLB, OUTP = argv[0], argv[1]
MODE = argv[2] if len(argv) > 2 else "rest"
W, H = 640, 640

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = e
        break
    except TypeError:
        pass
sc.render.resolution_x, sc.render.resolution_y = W, H
world = bpy.data.worlds.new("w")
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.55, 0.6, 0.68, 1)
bg.inputs["Strength"].default_value = 0.9
sc.world = world
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sc.collection.objects.link(sun)
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), 0, math.radians(-40))
bpy.ops.mesh.primitive_plane_add(size=40)
floor = bpy.context.active_object
m = bpy.data.materials.new("floor")
m.use_nodes = True
next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.35, 0.33, 0.28, 1)
floor.data.materials.append(m)
bpy.ops.import_scene.gltf(filepath=GLB)
arm = next(o for o in sc.objects if o.type == "ARMATURE")
acts = {a.name.split("|")[-1].upper(): a for a in bpy.data.actions}
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 50


def aim(yaw, elev, dist, tz=1.45, ty=0.0):
    a, e = math.radians(yaw), math.radians(elev)
    t = mathutils.Vector((0, ty, tz))
    cam.location = t + mathutils.Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()


def bind(act):
    ad = arm.animation_data or arm.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = act
    if getattr(act, "slots", None):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


shots = []


def shot(tag):
    p = OUTP + "_%s.png" % tag
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    shots.append(p)


cols = 3
if MODE in ("rest", "close", "feet", "side"):
    bind(acts["GARRISON"])
    sc.frame_set(1)
    plan = {
        "rest": [(35, 8, 8.0, 1.45, 0), (90, 2, 8.0, 1.45, 0), (0, 4, 8.0, 1.45, 0),
                 (180, 4, 8.0, 1.45, 0), (215, 20, 8.0, 1.45, 0), (35, 50, 9.5, 1.45, 0)],
        "close": [(40, 6, 2.8, 2.0, 0.2), (300, 10, 2.8, 1.9, 0.2), (60, 5, 2.4, 1.6, 1.0)],
        "side": [(90, 4, 3.4, 1.05, 0), (270, 4, 3.4, 1.05, 0), (0, 4, 3.4, 1.05, 0), (180, 4, 3.4, 1.05, 0)],
        "feet": [(30, 12, 3.2, 0.5, 0.0), (140, 18, 3.2, 0.5, 0.0), (35, 50, 6.5, 1.0, 0.0), (80, 8, 1.6, 0.2, -0.6)],
    }[MODE]
    for i, (yaw, el, d, tz, ty) in enumerate(plan):
        aim(yaw, el, d, tz, ty)
        shot(i)
    cols = 2 if MODE == "feet" else 4 if MODE == "side" else 3
else:
    act = acts[MODE.upper()]
    bind(act)
    f0, f1 = [int(x) for x in act.frame_range]
    for fr in list(range(f0, f1 + 1, max(1, (f1 - f0) // 7)))[:8]:
        sc.frame_set(fr)
        aim(90, 4, 8.5)
        shot("%s%03d" % (MODE, fr))
    cols = 4
imgs = [np.array(bpy.data.images.load(p).pixels[:], np.float32).reshape(H, W, 4) for p in shots]
rows = (len(imgs) + cols - 1) // cols
sheet = np.ones((H * rows, W * cols, 4), np.float32)
for i, a in enumerate(imgs):
    r, c = rows - 1 - i // cols, i % cols
    sheet[r * H:(r + 1) * H, c * W:(c + 1) * W] = a
out = bpy.data.images.new("sheet", W * cols, H * rows)
out.pixels[:] = sheet.ravel()
out.filepath_raw = OUTP + "_sheet.png"
out.file_format = "PNG"
out.save()
