"""Take the wargame base OUT of an already-built unit .glb (owner 2026-09-27:
"撤除所有底座"), for a unit whose sources are gone — the infantry's Hunyuan3D
source was deleted with the rest of Hunyuan (docs: no-hunyuan-3d), so it
cannot simply be rebuilt without one.

  blender -b --factory-startup --python tools/units3d/strip_base.py -- CODE [CODE ...]

Imports assets/units3d/<code>.glb, deletes the "<code>_base" mesh, lowers
the rig until the figure's lowest point stands on z = 0 (make_units.py had
lifted it onto the base), and writes the .glb back with the same actions.
Bones are imported with Blender's own heuristic so their rests go back out
exactly as they came in. The units3d.json entry loses its base_m.
"""
import bpy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_common import OUT, log

codes = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
manifest_path = os.path.join(OUT, "units3d.json")
manifest = json.load(open(manifest_path))
for code in codes:
    path = os.path.join(OUT, code + ".glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path, bone_heuristic="BLENDER")
    sc = bpy.context.scene
    base = [o for o in sc.objects if o.type == "MESH" and o.data.name.endswith("_base")]
    for o in base:
        bpy.data.objects.remove(o, do_unlink=True)
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    # only what hangs off the rig: the importer adds an "Icosphere" of its own
    # for the bones' display shape, which is neither figure nor export
    figure = [o for o in sc.objects if o.type == "MESH" and o.parent is arm]
    # the rest pose's lowest point, evaluated through the skin
    for o in figure:
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.show_viewport = True
    ad = arm.animation_data
    keep = ad.action if ad else None
    if ad:
        ad.action = None
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    low = min((o.evaluated_get(dg).matrix_world @ v.co).z
              for o in figure for v in o.evaluated_get(dg).to_mesh().vertices)
    arm.data.pose_position = "POSE"
    if ad:
        ad.action = keep
    top = arm
    while top.parent is not None:
        top = top.parent
    top.location.z -= low
    bpy.context.view_layer.update()
    for o in sc.objects:
        o.select_set(o is arm or o in figure)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_yup=True, export_apply=False, export_image_format="JPEG", export_jpeg_quality=92,
        export_animations=True, export_animation_mode="ACTIONS", export_frame_range=False,
        export_optimize_animation_size=False, export_anim_single_armature=True)
    manifest.get(code, {}).pop("base_m", None)
    log("%s: base removed (%d mesh), lowered %.3f m -> %s" % (code, len(base), low, path))
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=1, sort_keys=True)
    f.write("\n")
