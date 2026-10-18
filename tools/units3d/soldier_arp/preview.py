"""Preview frames of each clip (exec() in the owner's Blender): render(clip) -> PNGs in OUT/<clip>/.

A fixed orthographic three-quarter camera, a sun and a soft world, EEVEE at low samples. The
preview objects are created once (names start with `preview_`); nothing else is changed.
"""
import math
import os

import bpy
from mathutils import Vector

OUT = "/Users/samuelzhang/game_design/assets/3D/units/soldier/model_wip/arp_knight_20261018/preview"


def setup(size=420):
    scn = bpy.context.scene
    cam = bpy.data.objects.get("preview_cam")
    if cam is None:
        cam = bpy.data.objects.new("preview_cam", bpy.data.cameras.new("preview_cam"))
        scn.collection.objects.link(cam)
        sun = bpy.data.objects.new("preview_sun", bpy.data.lights.new("preview_sun", "SUN"))
        sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(50), 0, math.radians(30))
        scn.collection.objects.link(sun)
    cam.data.type = "ORTHO"
    scn.camera = cam
    if scn.world is None:
        scn.world = bpy.data.worlds.new("preview_world")
    scn.world.use_nodes = True
    bg = next(n for n in scn.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.32, 0.33, 0.35, 1)
    bg.inputs[1].default_value = 0.8
    r = scn.render
    r.resolution_x = r.resolution_y = size
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    scn.eevee.taa_render_samples = 8
    for n in ("Camera", "Light"):
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = True


VIEW = Vector((-0.7, -1.0, 0.3)).normalized()   # from the knight's right front: sword and shield face


def frame_clip(clip):
    """Aim the camera at the middle of the clip's root travel, wide enough for all of it."""
    scn = bpy.context.scene
    rig = bpy.data.objects["rig"]
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    f0, f1 = map(int, act.frame_range)
    ys = []
    for f in range(f0, f1 + 1, 2):
        scn.frame_set(f)
        ys.append((rig.matrix_world @ rig.pose.bones["c_root_master.x"].matrix.translation).y)
    cam = bpy.data.objects["preview_cam"]
    target = Vector((0, (min(ys) + max(ys)) / 2 - 0.25, 0.85))
    cam.data.ortho_scale = 2.3 + (max(ys) - min(ys)) * 0.8
    cam.location = target + VIEW * 6
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    return f0, f1


def render(clip, name=None, framing=None):
    """framing: the clip whose root travel sets the camera (so a before/after pair matches)."""
    scn = bpy.context.scene
    rig = bpy.data.objects["rig"]
    frame_clip(framing or clip)
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    f0, f1 = map(int, act.frame_range)
    d = os.path.join(OUT, name or clip)
    os.makedirs(d, exist_ok=True)
    for f in range(f0, f1 + 1):
        scn.frame_set(f)
        scn.render.filepath = os.path.join(d, "%03d.png" % f)
        bpy.ops.render.render(write_still=True)
    return d, f1 - f0 + 1


def closeup(clip, frames, view=(0.4, -1.0, 0.1), scale=1.0, name=None, z=0.85):
    """Orthographic close-up following the hips: one PNG per frame in OUT/<name>/."""
    scn = bpy.context.scene
    rig = bpy.data.objects["rig"]
    cam = bpy.data.objects["preview_cam"]
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    d = os.path.join(OUT, name or clip + "_closeup")
    os.makedirs(d, exist_ok=True)
    cam.data.ortho_scale = scale
    v = Vector(view).normalized()
    out = []
    for f in frames:
        scn.frame_set(f)
        hip = rig.matrix_world @ rig.pose.bones["root.x"].head
        target = Vector((hip.x, hip.y, z))
        cam.location = target + v * 6
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = os.path.join(d, "%03d.png" % f)
        bpy.ops.render.render(write_still=True)
        out.append(scn.render.filepath)
    return out
