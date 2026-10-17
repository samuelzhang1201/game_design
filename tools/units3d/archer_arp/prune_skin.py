"""Trim equipment skin palettes, keeping every weighted bind matrix unchanged."""
import json
import struct

import numpy as np


def prune_skin(path):
    data = path.read_bytes()
    assert struct.unpack_from("<4sII", data) == (b"glTF", 2, len(data))
    size = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20+size])
    binary = bytearray(data[28+size:])

    def array(index):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        width = {"VEC4": 4, "MAT4": 16}[accessor["type"]]
        dtype = np.dtype({5121: "u1", 5123: "<u2", 5126: "<f4"}[accessor["componentType"]])
        return np.ndarray((accessor["count"], width), dtype=dtype, buffer=binary,
            offset=view.get("byteOffset", 0)+accessor.get("byteOffset", 0),
            strides=(view.get("byteStride", width*dtype.itemsize), dtype.itemsize))

    skin = doc["skins"][0]
    attributes = [p["attributes"] for mesh in doc["meshes"] for p in mesh["primitives"]]
    used = set()
    for attrs in attributes:
        for key in attrs:
            if key.startswith("JOINTS_"):
                used.update(array(attrs[key])[array(attrs[key.replace("JOINTS", "WEIGHTS")]) > 0].tolist())
    used = sorted(used)
    assert 1 <= len(used) <= 2, "equipment must stay rigid except its two-bone bow string"
    remap = np.zeros(len(skin["joints"]), dtype=np.uint16)
    remap[used] = np.arange(len(used))
    binds = array(skin["inverseBindMatrices"])[used].tobytes()
    for attrs in attributes:
        for key in attrs:
            if key.startswith("JOINTS_"):
                joints = array(attrs[key])
                joints[:] = remap[joints]
    # Release numpy's buffer views before extending the bytearray.
    del joints
    binary.extend(b"\0" * (-len(binary) % 4))
    view = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(binds)})
    binary.extend(binds)
    accessor = len(doc["accessors"])
    doc["accessors"].append({"bufferView": view, "componentType": 5126, "count": len(used), "type": "MAT4"})
    skin["joints"] = [skin["joints"][i] for i in used]
    skin["inverseBindMatrices"] = accessor
    doc["buffers"][0]["byteLength"] = len(binary)
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 28+len(encoded)+len(binary))
        + struct.pack("<I4s", len(encoded), b"JSON") + encoded
        + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
