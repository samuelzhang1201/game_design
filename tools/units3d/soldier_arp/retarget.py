"""Retarget the owner's Mixamo clips onto the ARP knight with ARP Remap (mixamo_fk map).

Run inside the owner's Blender through the MCP: exec(open(this).read()) with
soldier_knight_arp.blend open (rig `rig`, mesh `Soldier_body`, ARP-bound).
"""
import contextlib
import io
from pathlib import Path

import bpy

exec(open(str(Path("/Users/samuelzhang/game_design/tools/units3d/soldier_arp/ctx.py"))).read())

MOTION = Path("/Users/samuelzhang/game_design/assets/3D/model_wip/Motion")
CLIPS = {
    "WALK": "general/Standard Walk",
    "IDLE": "infantry/Sword And Shield Idle",
    "SLASH": "infantry/Sword And Shield Slash",
    "ATTACK": "infantry/Sword And Shield Attack",
    "ATTACK_VAR1": "infantry/Sword And Shield Attack - var 1",
}  # infantry/Two Hand Club Combo belongs to a longsword, no-shield figure (owner 2026-10-18)
IN_PLACE = {"WALK"}  # the map moves the piece; locomotion keeps no root travel


def _quiet(op, *a, **kw):
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            return run(op, *a, **kw)
        except RuntimeError as e:  # preset warns about the absent eye bones
            if "Eye" not in str(e):
                raise
            return {"FINISHED"}


def _in_place(action):
    """Remove the linear forward travel of c_root_master, keep the bob and sway."""
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if fc.data_path == 'pose.bones["c_root_master.x"].location' and fc.array_index in (0, 2):
                        k = fc.keyframe_points
                        a, b = k[0].co, k[-1].co
                        slope = (b.y - a.y) / max(b.x - a.x, 1)
                        for p in k:
                            p.co.y -= slope * (p.co.x - a.x)
                            p.handle_left.y -= slope * (p.handle_left.x - a.x)
                            p.handle_right.y -= slope * (p.handle_right.x - a.x)


def retarget_all(keys=CLIPS):
    scn = bpy.context.scene
    rig = bpy.data.objects["rig"]
    for n in ("c_foot_ik.l", "c_foot_ik.r", "c_hand_ik.l", "c_hand_ik.r"):
        rig.pose.bones[n]["ik_fk_switch"] = 1.0  # FK: the mixamo_fk map keys the FK chain
    report = {}
    for key in keys:
        old = bpy.data.actions.get(key)
        if old:
            bpy.data.actions.remove(old)
        before = set(bpy.data.objects)
        with contextlib.redirect_stdout(io.StringIO()):
            bpy.ops.import_scene.fbx(filepath=str(MOTION / (CLIPS[key] + ".fbx")))
        new = [o for o in bpy.data.objects if o not in before]
        src = next(o for o in new if o.type == "ARMATURE")
        src.name = "SRC_" + key
        src_action = src.animation_data.action
        src_action.name = "SRC_" + key
        scn.source_rig, scn.target_rig, scn.source_action = src.name, rig.name, src_action.name
        for o in bpy.context.selected_objects:
            o.select_set(False)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        _quiet(bpy.ops.arp.build_bones_list, "EXEC_DEFAULT")
        _quiet(bpy.ops.arp.import_config_preset, "EXEC_DEFAULT", preset_name="mixamo_fk")
        _quiet(bpy.ops.arp.auto_scale, "EXEC_DEFAULT")
        f0, f1 = map(int, src_action.frame_range)
        _quiet(bpy.ops.arp.retarget, "EXEC_DEFAULT", frame_start=f0, frame_end=f1,
               fake_user_action=True, interpolation_type="LINEAR")
        act = rig.animation_data.action
        act.name = key
        act.use_fake_user = True
        if key in IN_PLACE:
            _in_place(act)
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.actions.remove(src_action)
        report[key] = [f0, f1]
    return report
