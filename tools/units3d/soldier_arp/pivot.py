"""Bake native IK pivot samples onto the installed infantry without rebuilding its old data.

Samples are absolute native parent-relative matrices from Map3DInfantryPivot.sample_transition,
not Skeleton3D pose deltas. Positive pack turns select RIGHT. The body yaw stays in the engine.
Freeze entry/exit from the actual imported MARCH: Godot's optimized curve differs from raw glTF.
Include contact interval boundaries in the samples; uniform keys smear touchdown across stance.
A bake is not a contact/envelope certificate; its parameter mapping must be verified separately.
"""
import copy
import json
import math
import struct
from pathlib import Path

import numpy as np


def _read(path):
    raw = Path(path).read_bytes()
    assert raw[:4] == b"glTF" and struct.unpack_from("<I", raw, 4)[0] == 2
    assert struct.unpack_from("<I", raw, 8)[0] == len(raw)
    size, kind = struct.unpack_from("<I4s", raw, 12)
    assert kind == b"JSON"
    offset = 20 + size
    binary_size, kind = struct.unpack_from("<I4s", raw, offset)
    assert kind == b"BIN\0" and offset + 8 + binary_size == len(raw)
    return json.loads(raw[20:offset]), raw[offset + 8:]


def _quaternion(m):
    k = np.array([
        [m[0, 0]-m[1, 1]-m[2, 2], m[0, 1]+m[1, 0], m[0, 2]+m[2, 0], m[2, 1]-m[1, 2]],
        [m[0, 1]+m[1, 0], m[1, 1]-m[0, 0]-m[2, 2], m[1, 2]+m[2, 1], m[0, 2]-m[2, 0]],
        [m[0, 2]+m[2, 0], m[1, 2]+m[2, 1], m[2, 2]-m[0, 0]-m[1, 1], m[1, 0]-m[0, 1]],
        [m[2, 1]-m[1, 2], m[0, 2]-m[2, 0], m[1, 0]-m[0, 1], m[0, 0]+m[1, 1]+m[2, 2]],
    ]) / 3.0
    q = np.linalg.eigh(k)[1][:, -1]
    return q if q[3] >= 0 else -q


def bake(source, samples, destination, seconds):
    """Append the two canonical 90-degree references; reject lossy TRS or incomplete samples.

    Read source and samples before replacing destination atomically. Existing animations,
    mesh/skin/gear/material/image data and binary bytes are preserved, including native binds.
    Engine duration/phase select playback; ``seconds`` only authors the reference clip length.
    """
    assert type(seconds) in (int, float) and math.isfinite(seconds) and seconds > 0
    data, binary = _read(source)
    original = copy.deepcopy(data)
    original_binary = binary
    package = json.loads(Path(samples).read_text())
    assert isinstance(package, dict) and isinstance(package.get("cases"), list)
    assert all(a["name"] not in ("PIVOT_LEFT", "PIVOT_RIGHT") for a in data["animations"])
    names = {n.get("name"): i for i, n in enumerate(data["nodes"])}
    assert len(data["skins"]) == 1 and len(data["buffers"]) == 1
    root = data["nodes"][names["inf_rig"]]
    x, y, z, w = root.get("rotation", (0, 0, 0, 1))
    root_local = np.eye(4)
    root_local[:3, :3] = np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
        [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)],
    ]) @ np.diag(root.get("scale", (1, 1, 1)))
    root_local[:3, 3] = root.get("translation", (0, 0, 0))
    joints = [data["nodes"][i]["name"] for i in data["skins"][0]["joints"]]
    max_error = 0.0

    def add(values, kind):
        nonlocal binary
        values = np.asarray(values, dtype="<f4").reshape(len(values), -1)
        assert np.isfinite(values).all()
        view = len(data["bufferViews"])
        data["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": values.nbytes})
        binary += values.tobytes()
        accessor = {"bufferView": view, "componentType": 5126, "count": len(values), "type": kind}
        if kind == "SCALAR":
            accessor.update(min=[float(values.min())], max=[float(values.max())])
        index = len(data["accessors"])
        data["accessors"].append(accessor)
        return index

    for turn, label in ((90000000, "PIVOT_RIGHT"), (-90000000, "PIVOT_LEFT")):
        matches = [c for c in package["cases"] if c.get("turn_udeg") == turn]
        assert len(matches) == 1, (label, "one frozen reference required")
        row = matches[0]
        assert row.get("failures") == [] and isinstance(row.get("frames"), list)
        frames = row["frames"]
        assert len(frames) >= 2
        phases = [f["phase"] for f in frames]
        assert all(type(u) in (int, float) and math.isfinite(u) for u in phases)
        assert phases[0] == 0 and phases[-1] == 1
        assert all(a < b for a, b in zip(phases, phases[1:]))
        times = np.asarray(phases, dtype=np.float64) * seconds
        assert (np.diff(times.astype(np.float32)) > 0).all(), "clip times collapse in glTF float32"
        for frame in frames:
            assert set(frame["pose"]) == set(joints) | {"inf_rig"}
            assert np.max(np.abs(np.asarray(frame["pose"]["inf_rig"]) - root_local)) < 1e-5, "body root changed"
        time = add([[t] for t in times], "SCALAR")
        animation = {"name": label, "channels": [], "samplers": []}
        for name in joints:
            translations, rotations, scales = [], [], []
            for frame in frames:
                matrix = np.asarray(frame["pose"][name], dtype=float)
                assert matrix.shape == (4, 4) and np.isfinite(matrix).all()
                assert np.max(np.abs(matrix[3] - (0, 0, 0, 1))) < 1e-5
                assert np.linalg.det(matrix[:3, :3]) > 0
                scale = np.linalg.norm(matrix[:3, :3], axis=0)
                assert (scale > 0).all()
                u, _, v = np.linalg.svd(matrix[:3, :3] / scale)
                rotation = u @ v
                assert np.linalg.det(rotation) > 0
                error = float(np.max(np.abs(rotation @ np.diag(scale) - matrix[:3, :3])))
                assert error < 1e-5, (name, "native affine cannot be baked losslessly as glTF TRS", error)
                max_error = max(max_error, error)
                q = _quaternion(rotation)
                if rotations and np.dot(q, rotations[-1]) < 0:
                    q = -q
                translations.append(matrix[:3, 3]); rotations.append(q); scales.append(scale)
            for path, values, kind in (("translation", translations, "VEC3"),
                                       ("rotation", rotations, "VEC4"), ("scale", scales, "VEC3")):
                output = add(values, kind)
                sampler = len(animation["samplers"])
                animation["samplers"].append({"input": time, "output": output, "interpolation": "LINEAR"})
                animation["channels"].append({"sampler": sampler, "target": {"node": names[name], "path": path}})
        data["animations"].append(animation)
    data["buffers"][0]["byteLength"] = len(binary)
    for key, value in original.items():
        if key not in ("animations", "accessors", "bufferViews", "buffers"):
            assert data[key] == value, key
    for key in ("animations", "accessors", "bufferViews"):
        assert data[key][:len(original[key])] == original[key], key
    assert binary[:len(original_binary)] == original_binary
    header = json.dumps(data, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    binary += b"\0" * (-len(binary) % 4)
    result = (struct.pack("<4sII", b"glTF", 2, 28 + len(header) + len(binary))
              + struct.pack("<I4s", len(header), b"JSON") + header
              + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    destination = Path(destination)
    temporary = destination.with_name(destination.name + ".pivot-tmp")
    temporary.write_bytes(result)
    temporary.replace(destination)
    return {"clips": ["PIVOT_RIGHT", "PIVOT_LEFT"], "max_trs_error": max_error}
