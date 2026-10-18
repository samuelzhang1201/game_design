"""Retarget the owner's six Mixamo clips using the equipped ARP file's saved map.

Blender --background --python retarget.py -- SOURCE_PROJECT OUTPUT_DIRECTORY
Requires the owner's installed Auto-Rig Pro; never changes the source blend.
"""
import json
from pathlib import Path
import sys

import bpy


CLIPS = {
    "STANDBY": "Standing Idle 03 Examine",
    "MARCH": "Standard Walk",
    "SPRINT": "Standing Sprint Forward",
    "DRAW": "Standing Draw Arrow",
    "GARRISON": "Standing Aim Overdraw",
    "DEATH": "Standing Death Forward 02",
}


def curves(action):
    return [fc for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags for fc in bag.fcurves]


def main():
    root, out = map(Path, sys.argv[sys.argv.index("--") + 1:])
    out.mkdir(parents=True, exist_ok=True)
    source = root / "assets/3D/units/soldier/model_wip/arp_draw_arrow_equipped_20261018/soldier_arp_equipped.blend"
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    rig, motion = (bpy.data.objects[n] for n in ("Soldier_ARP", "Motion_Source"))
    original_draw = rig.animation_data.action
    original_draw.name = "DRAW"
    original_draw.use_fake_user = True
    scene.frame_set(1)
    calibrated = {p.name: p.location.copy() for p in motion.pose.bones}
    actions, report = {"DRAW": original_draw}, {}
    # The saved source has ARP's scale and rest-origin correction. Calibrate
    # against the identical draw FBX instead of guessing a centimetre conversion.
    order = ["DRAW"] + [key for key in CLIPS if key != "DRAW"]
    offsets = None
    for key in order:
        before = set(bpy.data.objects)
        folder = "general" if key == "MARCH" else "archers"
        path = root / "assets/3D/model_wip/Motion" / folder / (CLIPS[key] + ".fbx")
        bpy.ops.import_scene.fbx(filepath=str(path))
        imported = set(bpy.data.objects) - before
        raw = next(o for o in imported if o.type == "ARMATURE")
        action = raw.animation_data.action.copy()
        action.name = "SOURCE_" + key
        factor = motion.data.bones["mixamorig:Spine"].length / raw.data.bones["mixamorig:Spine"].length
        scene.frame_set(1)
        if offsets is None:
            offsets = {p.name: calibrated[p.name] - p.location * factor for p in raw.pose.bones}
        for fc in curves(action):
            if fc.data_path.endswith(".location"):
                bone = fc.data_path.split('"')[1]
                offset = offsets[bone][fc.array_index]
                for point in fc.keyframe_points:
                    for co in (point.co, point.handle_left, point.handle_right):
                        co.y = co.y * factor + offset
        motion.animation_data.action = action
        motion.animation_data.action_slot = action.slots[0]
        first, last = map(int, action.frame_range)
        if key != "DRAW":
            for obj in bpy.context.selected_objects:
                obj.select_set(False)
            rig.hide_set(False)
            rig.select_set(True)
            bpy.context.view_layer.objects.active = rig
            scene.source_rig, scene.target_rig = motion.name, rig.name
            scene.source_action = action.name
            assert bpy.ops.arp.retarget(frame_start=first, frame_end=last,
                                       fake_user_action=True, interpolation_type="LINEAR") == {"FINISHED"}
            result = rig.animation_data.action
            assert result != original_draw and len(curves(result)) > 100
            result.name = key
            result.use_fake_user = True
            actions[key] = result
        report[key] = {"source": path.name, "frames": [first, last], "fps": scene.render.fps}
        for obj in imported:
            bpy.data.objects.remove(obj, do_unlink=True)
        print("RETARGETED", key, first, last, flush=True)
    rig.animation_data.action = actions["DRAW"]
    rig.animation_data.action_slot = actions["DRAW"].slots[0]
    scene.frame_start, scene.frame_end = 1, 31
    scene.frame_set(31)
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "archer_six_clips.blend"))
    (out / "clips.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
