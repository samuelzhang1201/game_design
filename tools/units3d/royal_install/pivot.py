"""Bake the royal's contact-solved pivot poses on a COPY of its 20k source.

Blender --factory-startup -b COPY.blend --python-exit-code 1 \
    --python tools/units3d/royal_install/pivot.py \
    -- --poses SOLVED.json --baseline knight_rigged_20k.glb --out CANDIDATE.glb

SOLVED binds source_sha256, fps and duration to the retained
Map3DCavalryPivot.sample output: {cases:[{angle,phase,ok,
locals:{bone:[12 row-major affine coefficients]}}],failures:[]}. The pure
provider consumes the actual immutable royal bind hierarchy, anatomical heads
and tails, full native MARCH entry/current/exit locals and full hoof contacts.
Its successful results are numerical inputs, never a skin/contact certificate.

Positive pack turns select RIGHT; negative select LEFT. The engine supplies
body yaw, origin, duration and operation phase: these clips contain no body yaw.
The author must retain the parameter mapping and actual source inputs alongside
the copied blend. A retimed 180 clip alone cannot map arbitrary turns or native
MARCH phases. Native-window and continuous contact/envelope acceptance remain
separate gates. This tool never installs an asset or changes the source blend.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path


def read_glb(path):
    raw = path.read_bytes()
    assert struct.unpack_from("<II", raw) == (0x46546C67, 2), "Expected glTF 2"
    length = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20 + length]), raw[28 + length:]


def accessor(document, binary, index):
    row = document["accessors"][index]
    assert "sparse" not in row, "Unexpected sparse source accessor"
    view = document["bufferViews"][row["bufferView"]]
    width = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[row["componentType"]]
    width *= {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[row["type"]]
    offset = view.get("byteOffset", 0) + row.get("byteOffset", 0)
    stride = view.get("byteStride", width)
    payload = b"".join(binary[offset + i * stride:offset + i * stride + width]
                       for i in range(row["count"]))
    return row["count"], row["type"], row["componentType"], row.get("normalized", False), payload


def verify_preserved(baseline, candidate):
    old, old_binary = read_glb(baseline)
    new, new_binary = read_glb(candidate)
    for key in ("nodes", "scenes", "materials", "textures", "samplers"):
        assert old.get(key) == new.get(key), "Changed source " + key
    assert len(old["meshes"]) == len(new["meshes"]) == 1
    for left, right in zip(old["meshes"][0]["primitives"], new["meshes"][0]["primitives"], strict=True):
        assert left["attributes"].keys() == right["attributes"].keys()
        for key in left["attributes"]:
            assert accessor(old, old_binary, left["attributes"][key]) == accessor(new, new_binary, right["attributes"][key]), key
        assert accessor(old, old_binary, left["indices"]) == accessor(new, new_binary, right["indices"])
        assert left.get("material") == right.get("material")
    for left, right in zip(old["skins"], new["skins"], strict=True):
        assert {k: v for k, v in left.items() if k != "inverseBindMatrices"} == {k: v for k, v in right.items() if k != "inverseBindMatrices"}
        assert accessor(old, old_binary, left["inverseBindMatrices"]) == accessor(new, new_binary, right["inverseBindMatrices"])
    for left, right in zip(old["images"], new["images"], strict=True):
        a, b = old["bufferViews"][left["bufferView"]], new["bufferViews"][right["bufferView"]]
        assert left.get("mimeType") == right.get("mimeType")
        assert old_binary[a.get("byteOffset", 0):a.get("byteOffset", 0) + a["byteLength"]] == new_binary[b.get("byteOffset", 0):b.get("byteOffset", 0) + b["byteLength"]]
    def clips(document, binary):
        return {animation["name"]: {
            (document["nodes"][channel["target"]["node"]]["name"], channel["target"]["path"]): (
                animation["samplers"][channel["sampler"]].get("interpolation", "LINEAR"),
                accessor(document, binary, animation["samplers"][channel["sampler"]]["input"]),
                accessor(document, binary, animation["samplers"][channel["sampler"]]["output"]))
            for channel in animation["channels"]} for animation in document["animations"]}
    a, b = clips(old, old_binary), clips(new, new_binary)
    assert set(a) == {"STANDBY", "GARRISON", "MARCH", "ATTACK", "DEFEND"}
    assert set(b) == set(a) | {"PIVOT_LEFT", "PIVOT_RIGHT"}
    assert all(a[name] == b[name] for name in a), "Changed old animation samples"


def validate_poses(data, names):
    assert data["failures"] == [], "Refuse a failed numerical mapping"
    assert all(type(data[key]) in (float, int) and math.isfinite(data[key]) and data[key] > 0
               for key in ("fps", "duration")), "Invalid authoring clock"
    frames = data["fps"] * data["duration"]
    assert abs(frames - round(frames)) < 1e-9, "Duration must span whole authoring frames"
    groups = {}
    for row in data["cases"]:
        assert row["ok"] is True and set(row["locals"]) == names
        angle, phase = row["angle"], row["phase"]
        assert type(angle) in (float, int) and math.isfinite(angle) and -180 < angle <= 180 and angle != 0
        assert type(phase) in (float, int) and math.isfinite(phase) and 0 <= phase <= 1
        for values in row["locals"].values():
            assert len(values) == 12 and all(type(x) in (float, int) and math.isfinite(x) for x in values)
        groups.setdefault(angle, []).append(row)
    assert len(groups) == 2 and sum(angle > 0 for angle in groups) == 1
    for rows in groups.values():
        assert len(rows) == round(frames) + 1 and len(rows) > 2 and rows[0]["phase"] == 0 and rows[-1]["phase"] == 1
        assert all(abs(row["phase"] - i / (len(rows) - 1)) < 1e-12 for i, row in enumerate(rows)), "Nonuniform or unordered samples"
    return groups


def main():
    import bpy
    from mathutils import Matrix

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--poses", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    source = Path(bpy.data.filepath).resolve()
    out = args.out.resolve()
    assert "model_wip" in out.parts and out.suffix == ".glb", "Stage in the object's ignored source folder"
    assert out.with_suffix(".blend") != source and not out.exists() and not out.with_suffix(".blend").exists(), "Retain previous source and variants"
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    names = {bone.name for bone in rig.data.bones}
    assert len(names) == 59, "Expected the actual royal source"
    assert {a.name for a in bpy.data.actions} == {"STANDBY", "GARRISON", "MARCH", "ATTACK", "DEFEND"}
    data = json.loads(args.poses.read_text())
    assert data["source_sha256"] == source_hash, "Solved poses belong to another source"
    assert data["fps"] == bpy.context.scene.render.fps / bpy.context.scene.render.fps_base, "Authoring FPS mismatch"
    groups = validate_poses(data, names)
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    for angle, rows in groups.items():
        name = "PIVOT_RIGHT" if angle > 0 else "PIVOT_LEFT"
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        for frame, row in enumerate(rows):
            for bone in rig.data.bones:
                values = row["locals"][bone.name]
                local = Matrix([values[:4], values[4:8], values[8:], [0, 0, 0, 1]])
                assert local.determinant() != 0, "Singular solved affine"
                # Pose basis differs from the full parent-relative native transform.
                basis = bone.matrix_local.inverted() @ (bone.parent.matrix_local if bone.parent else Matrix.Identity(4)) @ local
                pose = rig.pose.bones[bone.name]
                pose.rotation_mode = "QUATERNION"
                pose.matrix_basis = basis
                for prop in ("location", "rotation_quaternion", "scale"):
                    pose.keyframe_insert(prop, frame=frame, group=bone.name)
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = "LINEAR"
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, action)
        track.mute = True
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = False
    out.parent.mkdir(parents=True, exist_ok=True)
    staged = out.with_suffix(".stage.glb")
    assert not staged.exists(), "Retain the failed export"
    bpy.ops.export_scene.gltf(filepath=str(staged), export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_skins=True,
                              export_yup=True, export_apply=False)
    verify_preserved(args.baseline, staged)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    staged.rename(out)
    bpy.ops.wm.save_as_mainfile(filepath=str(out.with_suffix(".blend")), copy=True)
    print("ROYAL_PIVOT_BAKED", out, "source", source_hash)


if __name__ == "__main__":
    main()
