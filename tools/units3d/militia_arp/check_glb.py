"""Round trip of the installed militia.glb: what the game loads, not what the .blend holds.

  Blender -b --factory-startup --python tools/units3d/militia_arp/check_glb.py -- GLB FACES.json [SHOT_DIR]

FACES.json is the source's `textures_parts/exposure_faces.json` (git-ignored, written from the .blend): one
[u, v, class] per source face at its UV centre, class 1 = skirt above its hem row and below the belt's rows,
2 = legs and leg wraps, 0 = everything else. A GLB face takes the class of the nearest source face in UV
(the body sits in the atlas's lower-left 3/4).

Per clip it lists the frames in which a leg face crosses a skirt face, with the pairs and the skirt chains they
hang on (the export's MARCH foot lock moves the legs after the skirt's keys were baked, so the .blend's own gate
does not cover it; the cure is in the .blend: swing those chains out on that frame), and prints bones and triangles. With SHOT_DIR it renders a few frames of the imported file.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

BODY_REGION = 0.75
SHOTS = (("MARCH", 8), ("GARRISON", 0), ("DEFEND", 20), ("SLASH", 20), ("ATTACK_VAR1", 30), ("SLASH_3", 14))


def _load(glb):
    bpy.ops.wm.read_factory_settings(use_empty=True)      # no default cube, light or camera
    bpy.ops.import_scene.gltf(filepath=str(glb))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == rig)
    return rig, body


def _classes(body, faces):
    kd = KDTree(len(faces))
    for i, (u, v, _k) in enumerate(faces):
        kd.insert((u, v, 0.0), i)
    kd.balance()
    uv = body.data.uv_layers[0].data
    out = {1: [], 2: []}
    for p in body.data.polygons:
        c = sum((uv[l].uv for l in p.loop_indices), Vector((0.0, 0.0))) / len(p.loop_indices)
        if c.x >= BODY_REGION or c.y >= BODY_REGION:
            continue                                   # the sword's and the shield's strip
        k = faces[kd.find((c.x / BODY_REGION, c.y / BODY_REGION, 0.0))[1]][2]
        if k:
            out[k].append(tuple(p.vertices))
    return out


def _set(rig, act):
    rig.animation_data_create()
    rig.animation_data.action = act
    if getattr(act, "slots", None):
        rig.animation_data.action_slot = act.slots[0]


def check(glb, faces_json, shot_dir=None):
    rig, body = _load(glb)
    cls = _classes(body, json.loads(Path(faces_json).read_text()))
    scn = bpy.context.scene
    for t in list(rig.animation_data.nla_tracks) if rig.animation_data else []:
        t.mute = True
    out = {"faces": {"skirt": len(cls[1]), "legs": len(cls[2])}, "bones": len(rig.data.bones),
           "tris": sum(len(p.vertices) - 2 for p in body.data.polygons), "clips": {}}
    names = {g.index: g.name for g in body.vertex_groups}
    for act in sorted(bpy.data.actions, key=lambda a: a.name):
        _set(rig, act)
        f0, f1 = map(int, act.frame_range)
        bad = []
        for f in range(f0, f1 + 1):
            scn.frame_set(f)
            ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
            me = ev.to_mesh()
            co = [v.co.copy() for v in me.vertices]
            ev.to_mesh_clear()
            pairs = BVHTree.FromPolygons(co, cls[1]).overlap(BVHTree.FromPolygons(co, cls[2]))
            if pairs:
                # (frame, crossing face pairs, the skirt chains those faces hang on)
                vs = {v for i, _ in pairs for v in cls[1][i]}
                chains = sorted({names[g.group][6:8] for v in vs for g in body.data.vertices[v].groups
                                 if g.weight > 0.3 and names[g.group].startswith("skirt_")})
                bad.append((f, len(pairs), chains))
        out["clips"][act.name] = {"frames": f1 - f0 + 1, "leg_through_skirt": bad}
    if shot_dir:
        _shoot(rig, shot_dir)
    return out


def _shoot(rig, shot_dir):
    scn = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    for o in (cam, sun):
        scn.collection.objects.link(o)
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 2.2
    scn.camera = cam
    scn.world = scn.world or bpy.data.worlds.new("w")
    scn.world.use_nodes = True
    bg = next(n for n in scn.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.32, 0.33, 0.35, 1); bg.inputs[1].default_value = 0.8
    r = scn.render
    r.resolution_x = r.resolution_y = 480
    r.image_settings.file_format = "PNG"
    try:
        r.engine = "BLENDER_EEVEE"
    except TypeError:
        r.engine = "BLENDER_EEVEE_NEXT"
    Path(shot_dir).mkdir(parents=True, exist_ok=True)
    centre = Vector((0.0, 0.0, 0.9))
    for clip, frame in SHOTS:
        _set(rig, bpy.data.actions[clip])
        scn.frame_set(frame)
        # the installed figure faces +Y in Blender after the import (the game's -Z)
        for tag, d in (("front", Vector((0.7, 1.0, 0.3))), ("back", Vector((-0.7, -1.0, 0.3)))):
            cam.location = centre + d.normalized() * 8
            cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
            r.filepath = str(Path(shot_dir) / ("%s_%02d_%s.png" % (clip, frame, tag)))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    print("MILITIA_GLB", json.dumps(check(argv[0], argv[1], argv[2] if len(argv) > 2 else None)))
