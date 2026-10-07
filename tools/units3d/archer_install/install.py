"""Install the rigged archer as the archers' piece.

    python3 tools/units3d/archer_install/install.py [SRC.glb]

SRC defaults to assets/3D/units/archers/model_wip/tripo/archer_rigged.glb:
tools/units3d/archer_rig/export.py's export of archer_rig_work.blend (the
Tripo generation rigged and animated by tools/units3d/archer_rig/).
Writes assets/3D/units/archers/archers.glb: the same mesh, skin and five clips,
turned half round to face the way every piece faces (glTF -Z), named on the
cavalry's pattern (archers_rig / archers / archers_atlas*) so Godot's import
extracts the maps as archers_archers_atlas{,_n,_mr}.jpg beside it, each
downsized 4096 -> 2048 JPEG (one 2048 atlas per unit). It also writes the
archers' entry in assets/3D/units/units3d.json (MEASURED: height, stride).
Then: Godot's import, and tools/units3d/archer_install/make_scene.gd.
"""
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets/3D/units/archers/model_wip/tripo/archer_rigged.glb"
OUT = ROOT / "assets/3D/units/archers/archers.glb"
UNITS = ROOT / "assets/3D/units/units3d.json"
STRIDE_M = 2.0          # archer_rig/actions.py march(): one loop of MARCH carries the body this far
SIZE = 2048
QUALITY = 92
BONES: dict = {}       # the rig already names the chip's bone "head"


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
        j["textures"][pbr["baseColorTexture"]["index"]]["source"]: "archers_atlas",
        j["textures"][mat["normalTexture"]["index"]]["source"]: "archers_atlas_n",
        j["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"]: "archers_atlas_mr",
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
    mat["name"] = "archers_atlas"
    for n in j["nodes"]:
        if "mesh" in n:
            n["name"] = "archers"
        n["name"] = BONES.get(n.get("name", ""), n.get("name", ""))
    root = j["nodes"][j["scenes"][0]["nodes"][0]]
    root["name"] = "archers_rig"
    # the export faces Blender -Y (the blender-auto-rig frame) = glTF +Z;
    # every other piece faces Blender +Y = glTF -Z (Map3DUnits.yaw_for), so
    # the rig turns half round about up
    assert "rotation" not in root and "matrix" not in root, "the root already turns"
    root["rotation"] = [0.0, 1.0, 0.0, 0.0]
    j["meshes"][0]["name"] = "archers"
    for s in j.get("skins", []):
        s["name"] = "archers_rig"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    write_glb(OUT, j, bytes(out))
    acc = j["accessors"]
    prim = j["meshes"][0]["primitives"][0]
    write_units(j)
    print("%s: %d tris, %d bones, clips %s, %.1f MB" % (
        OUT.relative_to(ROOT), acc[prim["indices"]]["count"] // 3, len(j["skins"][0]["joints"]),
        [a["name"] for a in j["animations"]], OUT.stat().st_size / 1e6))


def write_units(j: dict) -> None:
    """The archers' entry in units3d.json, measured from the file: height (glTF y of the mesh's
    POSITION max), the clips' frame ranges at 30 fps, bones, triangles."""
    acc = j["accessors"]
    prim = j["meshes"][0]["primitives"][0]
    pos = acc[prim["attributes"]["POSITION"]]
    units = json.loads(UNITS.read_text())
    units["archers"] = {
        "actions": {a["name"]: [0, round(max(acc[s["input"]]["max"][0] for s in a["samplers"]) * 30)] for a in j["animations"]},
        "bones": len(j["skins"][0]["joints"]),
        "fps": 30,
        "height_m": round(pos["max"][1] - pos["min"][1], 3),
        "kind": "humanoid",
        "label": "Archer",
        "source": "Tripo 3D (owner, paid plan) from REF_archers_qwenfast_s2.png; tools/units3d/archer_rig/",
        "stride_m": STRIDE_M,
        "tris": acc[prim["indices"]]["count"] // 3,
        "weights": {"body": "heat", "props": "rigid", "bow": "graded"},
    }
    UNITS.write_text(json.dumps(dict(sorted(units.items())), indent=1) + "\n")


if __name__ == "__main__":
    main()
