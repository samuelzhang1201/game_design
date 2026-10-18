"""Bake the equipped ARP rig to one shared game skeleton and separate gear GLBs.

Blender --background --python export.py -- WORK_DIRECTORY PROJECT_DIRECTORY
The source skin and topology stay intact; the string's linear shape keys are
baked to a string bone so separately imported gear follows the same skeleton.
"""
import json
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from retarget import CLIPS
from pack_materials import pack_materials
from prune_skin import prune_skin


def apply_pose(rig, pose):
    for bone in rig.pose.bones:
        rest = bone.bone.matrix_local
        bone.rotation_mode = "QUATERNION"
        bone.matrix_basis = (rest.inverted() @ bone.parent.bone.matrix_local
            @ pose[bone.parent.name].inverted() @ pose[bone.name]) if bone.parent else rest.inverted() @ pose[bone.name]


def mirror_pose(pose, rests):
    reflection = Matrix.Diagonal(Vector((-1, 1, 1, 1)))
    result = {}
    for name in pose:
        other = name
        for a, b in ((".l", ".r"), (".r", ".l"), (".L", ".R"), (".R", ".L")):
            if name.endswith(a):
                other = name[:-2] + b
                break
        result[name] = reflection @ pose[other] @ rests[other].inverted() @ reflection @ rests[name]
    return result


def main():
    work, project = map(Path, sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.wm.open_mainfile(filepath=str(work / "archer_six_clips.blend"))
    scene = bpy.context.scene
    source = bpy.data.objects["Soldier_ARP"]
    body, bow, quiver, arrow = (bpy.data.objects[n] for n in ("Soldier", "Longbow", "Quiver", "Arrow"))
    originals = [body, bow, quiver, arrow]
    actions = {key: bpy.data.actions[key] for key in CLIPS}
    source.animation_data.action = actions["DRAW"]
    source.animation_data.action_slot = actions["DRAW"].slots[0]
    scene.frame_set(31)
    bpy.context.view_layer.update()
    reflection = Matrix.Diagonal(Vector((-1, 1, 1, 1)))
    draw_rest = {n: source.data.bones[n].matrix_local.copy() for n in ("hand.l", "hand.r")}
    draw_hands = mirror_pose({n: source.pose.bones[n].matrix.copy() for n in draw_rest}, draw_rest)
    arrow_grip = draw_hands["hand.r"].inverted() @ reflection @ arrow.matrix_world @ reflection
    bow_grip = draw_hands["hand.l"].inverted() @ reflection @ bow.matrix_world @ reflection
    source.data.pose_position = "REST"
    bpy.context.view_layer.update()
    original_rests = [obj.matrix_world.copy() for obj in (bow, quiver, arrow)]
    bow_rest, quiver_rest, arrow_rest = [reflection @ m @ reflection for m in original_rests]
    keep = sorted({b.name for b in source.data.bones if b.use_deform} | {"DEF-weapon.L", "DEF-weapon.R"})
    parents = {}
    for name in keep:
        parent = source.data.bones[name].parent
        while parent and parent.name not in keep:
            parent = parent.parent
        parents[name] = parent.name if parent else None
    rests = {n: source.data.bones[n].matrix_local.copy() for n in keep}
    bow_local = rests["DEF-weapon.L"].inverted() @ bow_rest
    quiver_local = rests["spine_02.x"].inverted() @ quiver_rest
    rests.update({"DEF-bow": bow_rest, "DEF-quiver": quiver_rest,
                  "DEF-arrow": arrow_rest, "DEF-string": bow_rest})
    parents.update({"DEF-bow": "DEF-weapon.L", "DEF-quiver": "spine_02.x",
                    "DEF-arrow": "root.x", "DEF-string": "DEF-bow"})
    data = bpy.data.armatures.new("archers_skeleton")
    rig = bpy.data.objects.new("archers_rig", data)
    scene.collection.objects.link(rig)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, rest in rests.items():
        b = data.edit_bones.new(name)
        # A zero-length EditBone cannot retain the matrix's orientation.
        b.length = 0.05
        b.matrix = rest
    for name, parent in parents.items():
        if parent:
            data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    rest_error = max(abs(data.bones[n].matrix_local[i][j] - rest[i][j])
                     for n, rest in rests.items() for i in range(4) for j in range(4))
    assert rest_error < 1e-5, ("bind axes changed", rest_error)
    # Preserve the public head name used by Map3DUnitRig.head_m.
    data.bones["head.x"].name = "head"
    source.data.pose_position = "POSE"
    scene.frame_set(31)
    bpy.context.view_layer.update()
    draw_pose = mirror_pose({n: source.pose.bones[n].matrix.copy() for n in keep}, rests)
    grip_bones = [n for n in keep if source.data.bones["hand.l"] in source.data.bones[n].parent_recursive
                  and not n.startswith("DEF-weapon")]
    finger_grip = {n: draw_pose["hand.l"].inverted() @ draw_pose[n] for n in grip_bones}
    string_key = bow.data.shape_keys.key_blocks["String_Draw_X"]
    string_middle = [v.co for i, v in enumerate(bow.data.vertices) if string_key.data[i].co.x - v.co.x > 0.99]
    string_nock = reflection.to_3x3() @ (sum(string_middle, Vector()) / len(string_middle))
    samples, metrics = {}, {}
    for clip, action in actions.items():
        source.animation_data.action = action
        source.animation_data.action_slot = action.slots[0]
        first, last = map(int, action.frame_range)
        poses = []
        root_start = root_end = None
        for frame in (first, last):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            if root_start is None:
                root_start = source.pose.bones["root.x"].head.copy()
            else:
                root_end = source.pose.bones["root.x"].head.copy()
        travel = root_end - root_start
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            pose = {n: source.pose.bones[n].matrix.copy() for n in keep}
            if clip == "DRAW":
                # The equipped source draws left-handed; retain its rest axes
                # and corrected skin while swapping the motion to a right-hand draw.
                pose = mirror_pose(pose, rests)
            if clip in ("MARCH", "GARRISON", "SPRINT", "DEATH"):
                # Fit the mocap wrist to this bow's grip: upright when aiming,
                # carried along the stride when sprinting to clear the ground.
                if clip == "DEATH":
                    current = pose["hand.l"] @ bow_grip
                    z = current.to_3x3().col[2].copy()
                    z.z = 0
                    z.normalize()
                    x = Vector((0, 0, 1))
                    y = z.cross(x).normalized()
                else:
                    z = (Vector((0, -0.6, 0.8)) if clip == "MARCH" else
                         Vector((0, 0, 1)) if clip == "GARRISON" else Vector((0.4, -0.8, 0.35))).normalized()
                    y = Vector((0, -1, 0)) if clip == "MARCH" else pose["hand.l"].translation - pose["hand.r"].translation
                    y = (y - z * y.dot(z)).normalized()
                    x = y.cross(z).normalized()
                desired = Matrix((x, y, z)).transposed().to_4x4()
                desired.translation = (pose["hand.l"] @ bow_grip).translation
                if clip == "DEATH":
                    weight = max(0, min(1, (frame / last - 0.20) / 0.35))
                    desired = current.lerp(desired, weight)
                hand = desired @ bow_grip.inverted()
                delta = hand @ pose["hand.l"].inverted()
                for name in keep:
                    bone = source.data.bones[name]
                    if name == "hand.l" or source.data.bones["hand.l"] in bone.parent_recursive:
                        pose[name] = delta @ pose[name]
            if clip != "DRAW":
                # Empty-hand locomotion must keep the bow's reviewed closed grip.
                for name, local in finger_grip.items():
                    pose[name] = pose["hand.l"] @ local
            pose["head"] = pose.pop("head.x")
            pose["DEF-bow"] = pose["DEF-weapon.L"] @ bow_local
            pose["DEF-quiver"] = pose["spine_02.x"] @ quiver_local
            if clip == "DRAW":
                pose["DEF-arrow"] = reflection @ arrow.matrix_world @ reflection
                draw = reflection.to_3x3() @ Vector([bow.data.shape_keys.key_blocks["String_Draw_" + axis].value for axis in "XYZ"])
            elif clip == "GARRISON":
                hand = pose["hand.r"] @ arrow_grip
                grip = pose["DEF-bow"].translation
                x = (grip - hand.translation).normalized()
                y = Vector((0, 0, 1)).cross(x).normalized()
                z = x.cross(y).normalized()
                pose["DEF-arrow"] = Matrix((x, y, z)).transposed().to_4x4()
                pose["DEF-arrow"].translation = hand.translation
                draw = pose["DEF-bow"].inverted() @ hand.translation - string_nock
            else:
                stored = Matrix.Rotation(1.5707963267948966, 4, "Y")
                stored.translation = Vector((0.02, 0, 0.8))
                pose["DEF-arrow"] = pose["DEF-quiver"] @ stored
                draw = Vector((0, 0, 0))
            pose["DEF-string"] = pose["DEF-bow"] @ Matrix.Translation(draw)
            if clip in ("MARCH", "SPRINT"):
                shift = Vector((travel.x, travel.y, 0)) * ((frame - first) / (last - first))
                for matrix in pose.values():
                    matrix.translation -= shift
            poses.append(pose)
        if clip == "GARRISON":
            # Close the sampled mocap loop without a snap at its wrap.
            for i in range(min(6, len(poses) - 1)):
                index = len(poses) - 6 + i
                weight = (i + 1) / 6
                poses[index] = {n: m.lerp(poses[0][n], weight) for n, m in poses[index].items()}
        elif clip in ("MARCH", "SPRINT", "STANDBY"):
            poses[-1] = {n: m.copy() for n, m in poses[0].items()}
        samples[clip] = poses
        metrics[clip] = {"frames": [first, last], "duration_s": (last - first) / scene.render.fps,
                         "travel_m": round(Vector((travel.x, travel.y, 0)).length, 6)}
    # Build separate meshes in the SAME bind space. Godot uses named skin binds
    # to connect the equipment MeshInstance3Ds to the character's Skeleton3D.
    meshes = []
    for original, name, socket, rest in zip(originals,
            ("archers", "archers_bow", "archers_quiver", "archers_arrow"),
            (None, "DEF-bow", "DEF-quiver", "DEF-arrow"),
            (Matrix.Identity(4), bow_rest, quiver_rest, arrow_rest)):
        obj = original.copy()
        obj.data = original.data.copy()
        scene.collection.objects.link(obj)
        obj.name = name
        obj.animation_data_clear()
        for constraint in list(obj.constraints):
            obj.constraints.remove(constraint)
        obj.parent = rig
        obj.matrix_parent_inverse.identity()
        obj.matrix_world.identity()
        weights = None
        if obj.data.shape_keys:
            basis = obj.data.shape_keys.key_blocks[0]
            key = obj.data.shape_keys.key_blocks["String_Draw_X"]
            weights = [max(0.0, min(1.0, key.data[i].co.x - v.co.x)) for i, v in enumerate(basis.data)]
            # Only this export copy changes representation; source keys stay editable.
            obj.shape_key_clear()
        if socket:
            # Reflect the original gear's bind geometry with its mounting side;
            # reverse winding to retain outward faces (topology/UVs stay intact).
            obj.data.transform(rest @ reflection)
            for polygon in obj.data.polygons:
                polygon.flip()
            obj.vertex_groups.clear()
            group = obj.vertex_groups.new(name=socket)
            group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
            if weights:
                string = obj.vertex_groups.new(name="DEF-string")
                for i, weight in enumerate(weights):
                    if weight > 0:
                        group.add([i], 1 - weight, "REPLACE")
                        string.add([i], weight, "REPLACE")
        else:
            obj.vertex_groups["head.x"].name = "head"
        obj.modifiers.clear()
        modifier = obj.modifiers.new("Skin", "ARMATURE")
        modifier.object = rig
        meshes.append(obj)
    for image in bpy.data.images:
        if image.size[0] > 2048:
            image.scale(2048, 2048)
    rig.data.pose_position = "REST"
    pack_materials(meshes[0], "archers_body")
    pack_materials(meshes[3], "archers_arrow")
    rig.data.pose_position = "POSE"
    rig.animation_data_create()
    for clip, poses in samples.items():
        rig.animation_data.action = None
        corrections = []
        for pose in poses:
            apply_pose(rig, pose)
            bpy.context.view_layer.update()
            evaluated = meshes[0].evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh()
            lift = max(0.0, -min(v.co.z for v in mesh.vertices))
            evaluated.to_mesh_clear()
            for matrix in pose.values():
                matrix.translation.z += lift
            corrections.append(lift)
        metrics[clip]["floor_correction_max_m"] = max(corrections)
        action = bpy.data.actions.new("game_" + clip)
        rig.animation_data.action = action
        for frame, pose in enumerate(poses, 1):
            apply_pose(rig, pose)
            for bone in rig.pose.bones:
                bone.keyframe_insert("location", frame=frame, group=bone.name)
                bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
                bone.keyframe_insert("scale", frame=frame, group=bone.name)
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        track.strips.new(clip, 1, action)
        track.mute = True
    rig.animation_data.action = None
    # Blender -Y becomes glTF +Z; the game's figures face glTF -Z.
    rig.rotation_euler.z = 3.141592653589793
    for track in rig.animation_data.nla_tracks:
        track.mute = False
    out = project / "assets/3D/units/archers"
    out.mkdir(parents=True, exist_ok=True)
    for index, mesh in enumerate(meshes):
        for obj in bpy.context.selected_objects:
            obj.select_set(False)
        rig.select_set(True)
        mesh.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = out / ("archers.glb" if index == 0 else mesh.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
            export_animations=index == 0, export_animation_mode="NLA_TRACKS",
            export_anim_slide_to_zero=True,
            export_skins=True, export_def_bones=False, export_influence_nb=8,
            export_all_influences=True, export_image_format="JPEG", export_jpeg_quality=90,
            export_yup=True, export_morph=False, export_apply=False)
        if index > 0:
            prune_skin(path)
        print("EXPORTED", path, flush=True)
    metrics["geometry"] = {o.name: sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes}
    metrics["bind_matrix_max_error"] = rest_error
    (work / "export_metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    for original in originals:
        original.hide_set(True)
        original.hide_render = True
    source.hide_set(True)
    for track in rig.animation_data.nla_tracks:
        track.mute = track.name != "DRAW"
    scene.frame_set(31)
    bpy.ops.wm.save_as_mainfile(filepath=str(work / "archer_game_export.blend"))


if __name__ == "__main__":
    main()
