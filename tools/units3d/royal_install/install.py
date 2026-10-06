"""Install the owner's rigged king on horseback as the royal regiment's piece.

    python3 tools/units3d/royal_install/install.py [SRC.glb]

SRC defaults to assets/3D/units/royal/model_wip/tripo/knight_rigged_20k.glb:
decimate.py's export of the owner's delivery (knight_rig_anim.blend, rigged
and animated by the owner) collapsed to the units' ~20k triangles.
Writes assets/3D/units/royal/royal.glb: the same mesh, skin and five clips,
turned half round to face the way every piece faces (glTF -Z), the two head
bones renamed (BONES) and the rest named on the cavalry's pattern (royal_rig /
royal / royal_atlas*) so Godot's import extracts the maps as
royal_royal_atlas{,_n,_mr}.jpg beside it, each
downsized 4096 -> 2048 JPEG (one 2048 atlas per unit, like the cavalry: the
piece is a few dozen px on the map, the WAR ROOM's closest look ~400 px).
Then: Godot's import, and tools/units3d/royal_install/make_scene.gd.
Nothing else in the file changes, so a re-delivery is one re-run.
"""
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets/3D/units/royal/model_wip/tripo/knight_rigged_20k.glb"
OUT = ROOT / "assets/3D/units/royal/royal.glb"
SIZE = 2048
QUALITY = 92
BONES = {"Head": "head_h", "R_Head": "head"}  # delivery name -> the game's


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
    return j, data[28 + jlen:28 + jlen + blen]


def write_glb(path: Path, j: dict, binary: bytes) -> None:
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, total)
                     + struct.pack("<II", len(js), 0x4E4F534A) + js
                     + struct.pack("<II", len(binary), 0x004E4942) + binary)


def main() -> None:
    j, b = read_glb(SRC)
    mat = j["materials"][0]
    pbr = mat["pbrMetallicRoughness"]
    role = {  # image index -> its new name
        j["textures"][pbr["baseColorTexture"]["index"]]["source"]: "royal_atlas",
        j["textures"][mat["normalTexture"]["index"]]["source"]: "royal_atlas_n",
        j["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"]: "royal_atlas_mr",
    }
    image_views = {im["bufferView"]: i for i, im in enumerate(j["images"])}
    # rebuild the buffer view by view, the images re-encoded
    out = bytearray()
    for vi, bv in enumerate(j["bufferViews"]):
        off = bv.get("byteOffset", 0)
        chunk = b[off:off + bv["byteLength"]]
        if vi in image_views:
            img = Image.open(io.BytesIO(chunk)).convert("RGB")
            if img.width > SIZE:
                img = img.resize((SIZE, SIZE), Image.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, "JPEG", quality=QUALITY, subsampling=0)
            chunk = buf.getvalue()
            im = j["images"][image_views[vi]]
            im["mimeType"] = "image/jpeg"
            im["name"] = role[image_views[vi]]
        out += b"\0" * (-len(out) % 4)
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(chunk)
        out += chunk
    j["buffers"] = [{"byteLength": len(out)}]
    mat["name"] = "royal_atlas"
    for n in j["nodes"]:
        if "mesh" in n:
            n["name"] = "royal"
        # the chip hangs over the bone named "head" (Map3DUnitRig.head_m): the
        # KING's, as on the cavalry, whose horse's head is head_h
        n["name"] = BONES.get(n.get("name", ""), n.get("name", ""))
    root = j["nodes"][j["scenes"][0]["nodes"][0]]
    root["name"] = "royal_rig"
    # the delivery faces Blender -Y (the blender-auto-rig frame) = glTF +Z;
    # every other piece faces Blender +Y = glTF -Z (Map3DUnits.yaw_for), so
    # the rig turns half round about up
    assert "rotation" not in root and "matrix" not in root, "the root already turns"
    root["rotation"] = [0.0, 1.0, 0.0, 0.0]
    j["meshes"][0]["name"] = "royal"
    for s in j.get("skins", []):
        s["name"] = "royal_rig"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    write_glb(OUT, j, bytes(out))
    acc = j["accessors"]
    prim = j["meshes"][0]["primitives"][0]
    print("%s: %d tris, %d bones, clips %s, %.1f MB" % (
        OUT.relative_to(ROOT), acc[prim["indices"]]["count"] // 3, len(j["skins"][0]["joints"]),
        [a["name"] for a in j["animations"]], OUT.stat().st_size / 1e6))


if __name__ == "__main__":
    main()
