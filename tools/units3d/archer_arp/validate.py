"""Numeric gate for the baked rig; run with Blender --background --python ... -- WORK."""
import json
from pathlib import Path
import sys
from statistics import median

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
    report = {"clips": {}, "bow_hand": "left", "draw_hand": "right"}
    body_mesh = bpy.data.objects["archers"]
    original_mesh = bpy.data.objects["Soldier"]
    assert len(body_mesh.data.vertices) == len(original_mesh.data.vertices)
    assert max((a.co - b.co).length for a, b in zip(body_mesh.data.vertices, original_mesh.data.vertices)) < 1e-7
    assert [tuple(p.vertices) for p in body_mesh.data.polygons] == [tuple(p.vertices) for p in original_mesh.data.polygons]
    assert len(body_mesh.data.uv_layers) == len(original_mesh.data.uv_layers)
    for exported_uv, original_uv in zip(body_mesh.data.uv_layers, original_mesh.data.uv_layers):
        assert len(exported_uv.data) == len(original_uv.data)
        assert max((a.uv - b.uv).length for a, b in zip(exported_uv.data, original_uv.data)) < 1e-7
    for a, b in zip(body_mesh.data.vertices, original_mesh.data.vertices):
        exported = {body_mesh.vertex_groups[g.group].name: g.weight for g in a.groups}
        original = {("head" if original_mesh.vertex_groups[g.group].name == "head.x" else original_mesh.vertex_groups[g.group].name): g.weight for g in b.groups}
        assert exported == original, "the corrected source weights must be preserved"
    assert rig.data.bones["DEF-bow"].parent.name == "DEF-weapon.L"
    bow_mesh = bpy.data.objects["archers_bow"]
    string_group = bow_mesh.vertex_groups["DEF-string"].index
    string_indices = [v.index for v in bow_mesh.data.vertices
                      if any(g.group == string_group and g.weight > 0.99 for g in v.groups)]
    grip = None
    for clip in ("STANDBY", "MARCH", "SPRINT", "DRAW", "GARRISON", "DEATH"):
        action = bpy.data.actions["game_" + clip]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        source.animation_data.action = bpy.data.actions[clip]
        source.animation_data.action_slot = source.animation_data.action.slots[0]
        low, bow_low, grip_error, nock_gap = 100.0, 100.0, 0.0, 0.0
        foot_positions = {side: [] for side in ("l", "r")}
        for frame in range(1, int(action.frame_range[1]) + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            body = coordinates(bpy.data.objects["archers"], graph)
            low = min(low, float(body[:, 2].min()))
            bow_coordinates = coordinates(bow_mesh, graph)
            bow_low = min(bow_low, float(bow_coordinates[:, 2].min()))
            if clip == "GARRISON" or (clip == "DRAW" and frame >= 25):
                arrow_nock = np.array(rig.pose.bones["DEF-arrow"].head)
                nock_gap = max(nock_gap, float(np.linalg.norm(bow_coordinates[string_indices] - arrow_nock, axis=1).min()))
            for side in foot_positions:
                foot_positions[side].append(list(rig.pose.bones["foot." + side].head))
            mounted = rig.pose.bones["hand.l"].matrix.inverted() @ rig.pose.bones["DEF-bow"].matrix
            if grip is None:
                grip = mounted.copy()
            grip_error = max(grip_error, max(abs(mounted[i][j] - grip[i][j]) for i in range(4) for j in range(4)))
        report["clips"][clip] = {"body_floor_m": low, "bow_floor_m": bow_low, "left_grip_error": grip_error, "nock_gap_m": nock_gap, "feet": foot_positions}
        if clip == "MARCH":
            stance_deltas = []
            for positions in foot_positions.values():
                floor = min(p[2] for p in positions)
                stance_deltas.extend(b[1] - a[1] for a, b in zip(positions, positions[1:-1])
                                     if max(a[2], b[2]) < floor + 0.02 and b[1] > a[1])
            assert stance_deltas, "walk has no measured stance interval"
            report["march_stride_m"] = median(stance_deltas) * (action.frame_range[1] - 1)
            report["march_stance_samples"] = len(stance_deltas)
        print("VALIDATED", clip, low, bow_low, flush=True)
    assert all(item["left_grip_error"] < 1e-4 for item in report["clips"].values()), "bow slips from the left hand"
    assert all(item["nock_gap_m"] < 0.015 for item in report["clips"].values()), "loaded arrow misses the string"
    assert all(item["bow_floor_m"] > -0.005 for item in report["clips"].values()), "bow penetrates the ground"
    assert all(item["body_floor_m"] > -0.0005 for item in report["clips"].values()), "body penetrates the ground"
    body = bpy.data.objects["archers"]
    errors = [abs(sum(group.weight for group in vertex.groups) - 1.0) for vertex in body.data.vertices]
    report["weight_sum_max_error"] = max(errors)
    report["unweighted_vertices"] = sum(not vertex.groups for vertex in body.data.vertices)
    assert report["unweighted_vertices"] == 0 and max(errors) < 1e-5
    (work / "validation.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
