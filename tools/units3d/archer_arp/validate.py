"""Numeric gate for the baked rig; run with Blender --background --python ... -- WORK."""
import json
from pathlib import Path
import sys

import bpy
import numpy as np


def coordinates(obj, graph):
    evaluated = obj.evaluated_get(graph)
    mesh = evaluated.to_mesh()
    result = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", result)
    evaluated.to_mesh_clear()
    return result.reshape(-1, 3)


def main():
    work = Path(sys.argv[sys.argv.index("--") + 1])
    bpy.ops.wm.open_mainfile(filepath=str(work / "archer_game_export.blend"))
    scene = bpy.context.scene
    rig, source = (bpy.data.objects[n] for n in ("archers_rig", "Soldier_ARP"))
    source.hide_set(False)
    bpy.data.objects["Soldier"].hide_set(False)
    rig.rotation_euler.z = 0
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    report = {"clips": {}, "draw_skin_max_error_m": 0.0}
    for clip in ("STANDBY", "MARCH", "SPRINT", "DRAW", "GARRISON", "DEATH"):
        action = bpy.data.actions["game_" + clip]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        source.animation_data.action = bpy.data.actions[clip]
        source.animation_data.action_slot = source.animation_data.action.slots[0]
        low, bow_low = 100.0, 100.0
        foot_positions = {side: [] for side in ("l", "r")}
        for frame in range(1, int(action.frame_range[1]) + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            body = coordinates(bpy.data.objects["archers"], graph)
            low = min(low, float(body[:, 2].min()))
            bow_low = min(bow_low, float(coordinates(bpy.data.objects["archers_bow"], graph)[:, 2].min()))
            for side in foot_positions:
                foot_positions[side].append(list(rig.pose.bones["foot." + side].head))
            if clip == "DRAW":
                original = coordinates(bpy.data.objects["Soldier"], graph)
                error = float(np.linalg.norm(body - original, axis=1).max())
                report["draw_skin_max_error_m"] = max(report["draw_skin_max_error_m"], error)
        report["clips"][clip] = {"body_floor_m": low, "bow_floor_m": bow_low, "feet": foot_positions}
        print("VALIDATED", clip, low, bow_low, flush=True)
    assert report["draw_skin_max_error_m"] < 1e-5, "the corrected skin changed during baking"
    assert all(item["body_floor_m"] > -0.0005 for item in report["clips"].values()), "body penetrates the ground"
    body = bpy.data.objects["archers"]
    errors = [abs(sum(group.weight for group in vertex.groups) - 1.0) for vertex in body.data.vertices]
    report["weight_sum_max_error"] = max(errors)
    report["unweighted_vertices"] = sum(not vertex.groups for vertex in body.data.vertices)
    assert report["unweighted_vertices"] == 0 and max(errors) < 1e-5
    (work / "validation.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
