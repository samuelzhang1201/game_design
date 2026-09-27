"""Re-author a built unit .glb's actions from make_units.py's action code,
without rebuilding it (written when the infantry's Hunyuan3D source was
gone; since 2026-09-27 infantry_scan.py rebuilds the infantry whole from its
CC0 scans with the same actions, so this is only the quick path), so a change
to its GARRISON / MARCH / ATTACK can reach the game (owner 2026-09-27: 行进动作
设计幅度再大一点).

  blender -b --factory-startup --python tools/units3d/reanimate.py -- CODE [CODE ...]

Imports assets/units3d/<code>.glb (bones by Blender's own heuristic, as
strip_base.py does, so their rests go back out as they came in), deletes every
action, rebuilds them with make_units.humanoid_actions at the manifest's
height_m, pushes them onto NLA tracks and writes the .glb back. Only the
humanoid kind: the cavalry is rebuilt whole by cavalry_scan.py.
"""
import bpy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_units as mu
from unit_common import OUT, log

codes = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
manifest = json.load(open(os.path.join(OUT, "units3d.json")))
for code in codes:
    entry = manifest.get(code, {})
    if entry.get("kind") != "humanoid":
        raise SystemExit("reanimate: %s is not a humanoid unit" % code)
    path = os.path.join(OUT, code + ".glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path, bone_heuristic="BLENDER")
    sc = bpy.context.scene
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    figure = [o for o in sc.objects if o.type == "MESH" and o.parent is arm]
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    acts = mu.humanoid_actions(arm, float(entry.get("height_m", 1.8)))
    mu.stash(arm, acts)
    for o in sc.objects:
        o.select_set(o is arm or o in figure)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_yup=True, export_apply=False, export_image_format="JPEG", export_jpeg_quality=92,
        export_animations=True, export_animation_mode="ACTIONS", export_frame_range=False,
        export_optimize_animation_size=False, export_anim_single_armature=True)
    log("%s: %d actions re-authored -> %s" % (code, len(acts), path))
