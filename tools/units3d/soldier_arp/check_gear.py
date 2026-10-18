"""Per-clip clipping census for the mounted sword and shield (exec() in the owner's Blender).

check(clips, step) -> {clip: {pair: (frames_hit, worst_frame, worst_count)}}: polygon overlaps
(BVHTree.overlap) of sword x body, shield x body, sword x shield. The holding hand and its
forearm are left out of the body for its own weapon (the fist closes on the grip by design).
"""
import bpy
from mathutils.bvhtree import BVHTree

HAND = ("hand", "thumb", "index", "middle", "ring", "pinky", "forearm")


def _held_polys(body, side):
    gi = {g.index: g.name for g in body.vertex_groups}
    held = {v.index for v in body.data.vertices
            if any(gi.get(g.group, "").replace("c_", "").startswith(HAND)
                   and gi[g.group].endswith(side) and g.weight > 0.3 for g in v.groups)}
    return {p.index for p in body.data.polygons if any(i in held for i in p.vertices)}


def _bvh(obj, dg):
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    M = obj.matrix_world
    t = BVHTree.FromPolygons([M @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    ev.to_mesh_clear()
    return t


def check(clips, step=2):
    scn = bpy.context.scene
    rig, body = bpy.data.objects["rig"], bpy.data.objects["Soldier_body"]
    sword, shield = bpy.data.objects["Sword"], bpy.data.objects["Shield"]
    skip = {"sword": _held_polys(body, ".r"), "shield": _held_polys(body, ".l")}
    out = {}
    for name in clips:
        act = bpy.data.actions[name]
        rig.animation_data.action = act
        rig.animation_data.action_slot = act.slots[0]
        f0, f1 = map(int, act.frame_range)
        res = {k: [0, None, 0] for k in ("sword_body", "shield_body", "sword_shield")}
        for f in range(f0, f1 + 1, step):
            scn.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            tb, tw, ts = _bvh(body, dg), _bvh(sword, dg), _bvh(shield, dg)
            hits = {
                "sword_body": [1 for a, b in tw.overlap(tb) if b not in skip["sword"]],
                "shield_body": [1 for a, b in ts.overlap(tb) if b not in skip["shield"]],
                "sword_shield": tw.overlap(ts),
            }
            for k, h in hits.items():
                if h:
                    r = res[k]; r[0] += 1
                    if len(h) > r[2]:
                        r[1], r[2] = f, len(h)
        out[name] = {k: tuple(v) for k, v in res.items()}
    return out
