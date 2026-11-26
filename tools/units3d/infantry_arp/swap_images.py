"""Replace the images packed in an installed unit GLB with new atlas files, touching nothing else
(mesh, skin, clips and the appended pivot pair stay byte for byte): a texture-only re-author does
not need the pivot pipeline again.

  python3 swap_images.py GLB DIR      (plain Python; DIR holds <glb stem>_<image name>.jpg)
"""
import json
import struct
import sys
from pathlib import Path


def swap(glb, src_dir):
    glb = Path(glb)
    raw = glb.read_bytes()
    n = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + n])
    bin_ = raw[20 + n + 8:]
    views = doc["bufferViews"]
    assert len(doc["buffers"]) == 1
    new = {im["bufferView"]: (Path(src_dir) / (glb.stem + "_" + im["name"] + ".jpg")).read_bytes()
           for im in doc["images"]}
    out = bytearray()
    kept = []
    for i in sorted(range(len(views)), key=lambda i: views[i].get("byteOffset", 0)):
        v = views[i]
        old = bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        data = new.get(i, old)
        out += b"\0" * (-len(out) % 4)
        v["byteOffset"], v["byteLength"] = len(out), len(data)
        out += data
        if i not in new:
            kept.append((i, old))
    out += b"\0" * (-len(out) % 4)
    for i, old in kept:                      # the check: every other view reads back unchanged
        assert bytes(out[views[i]["byteOffset"]:views[i]["byteOffset"] + views[i]["byteLength"]]) == old
    doc["buffers"][0]["byteLength"] = len(out)
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(out), b"BIN\0") + bytes(out)
    glb.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)
    return sorted(doc["images"][k]["name"] for k in range(len(doc["images"])))


if __name__ == "__main__":
    print("swapped", swap(sys.argv[1], sys.argv[2]))
