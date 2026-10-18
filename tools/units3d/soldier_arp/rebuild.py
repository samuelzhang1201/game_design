"""Rebuild every clip on the ARP knight after a rest-pose or rig change (exec() in the owner's Blender).

retarget -> fist on both hands -> WALK carry -> clear the three attacks. Needs the scripts beside it.
"""
import bpy

HERE = "/Users/samuelzhang/game_design/tools/units3d/soldier_arp/"


def rebuild():
    g = globals()
    for f in ("retarget.py", "equip.py", "solve_clear.py"):
        exec(open(HERE + f).read(), g)
    for a in list(bpy.data.actions):
        if a.name.endswith("_raw"):
            bpy.data.actions.remove(a)
    log = {"clips": retarget_all()}
    log["grip"] = fix_grip(list(CLIPS))
    rig = bpy.data.objects["rig"]
    walk = bpy.data.actions["WALK"]
    raw = walk.copy(); raw.name = "WALK_raw"; raw.use_fake_user = True
    for bone, axis, deg in WALK_CARRY:
        world_offset(rig, walk, bone, axis, deg)
    for clip in ("ATTACK", "SLASH", "ATTACK_VAR1"):
        log[clip] = solve(clip, rounds=6)
    return log
