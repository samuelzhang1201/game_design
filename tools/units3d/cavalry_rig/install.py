"""Install the re-rigged cavalry (tools/units3d/cavalry_rig/, owner 2026-10-06: 接进游戏，替换掉原来的骑兵)
over the cavalry piece.

    python3 tools/units3d/cavalry_rig/install.py [SRC.glb]
    python3 tools/units3d/cavalry_rig/install.py --pivots BASE_INSTALLED.glb PIVOT_EXPORT.glb

SRC defaults to the main checkout's assets/3D/units/cavalry/model_wip/rig/cavalry_rigged.glb (git-ignored,
exported from cavalry_rig_work.blend). Writes assets/3D/units/cavalry/cavalry.glb with:
  * the clips named as the game plays them: cavalry_MARCH -> MARCH (the import's loops are by name);
  * the head bones renamed: the chip hangs over the bone named `head` (Map3DUnitRig.head_m, any case),
    so the rider's R_Head -> head and the horse's Head -> head_h (as before, as the king);
  * the rig turned half round: the blender-auto-rig frame faces Blender -Y (glTF +Z), every piece faces
    glTF -Z (Map3DUnits.yaw_for);
  * the three 2048 maps re-encoded JPEG under their old names, so Godot's import refreshes the very
    cavalry_cavalry_atlas{,_n,_mr}.jpg the scene's material points at.
Then: Godot's import. The scene (scenes/models/units/cavalry.tscn) and the .import carry over.
"""
import copy
import io
import math
import struct
import sys
from itertools import pairwise
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/units3d/royal_install"))
from install import read_glb, write_glb  # noqa: E402  (the king's GLB reader / writer)

MAIN = Path("/Users/samuelzhang/game_design")      # the git-ignored source lives in the main checkout
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else MAIN / "assets/3D/units/cavalry/model_wip/rig/cavalry_rigged.glb"
OUT = ROOT / "assets/3D/units/cavalry/cavalry.glb"
QUALITY = 92
BONES = {"Head": "head_h", "R_Head": "head"}
PREFIX = "cavalry_"


def install_pivots(base: Path, source: Path) -> None:
    """Append only the two new animations; retain the original BIN bytes and all old resources."""
    j, binary = read_glb(base)
    incoming, data = read_glb(source)
    assert {a["name"] for a in j["animations"]} == {"ATTACK", "DEFEND", "GARRISON", "MARCH", "STANDBY"}
    names = {n["name"]: i for i, n in enumerate(j["nodes"])}
    joints = set(j["skins"][0]["joints"])
    expected = {(c["target"]["node"], c["target"]["path"]) for c in next(a for a in j["animations"] if a["name"] == "MARCH")["channels"]}
    out = bytearray(binary)
    copied: dict[int, int] = {}

    def accessor(index: int) -> int:
        if index in copied:
            return copied[index]
        a = copy.deepcopy(incoming["accessors"][index])
        assert a["componentType"] == 5126 and a["type"] in ("SCALAR", "VEC3", "VEC4") and "sparse" not in a
        view = incoming["bufferViews"][a["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        assert view.get("buffer", 0) == 0 and view.get("byteStride", width * 4) == width * 4
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        size = a["count"] * width * 4
        assert a["count"] >= 2 and start >= 0 and start + size <= len(data)
        chunk = data[start:start + size]
        assert all(math.isfinite(v[0]) for v in struct.iter_unpack("<f", chunk))
        if a["type"] == "SCALAR":
            times = [v[0] for v in struct.iter_unpack("<f", chunk)]
            assert times[0] >= 0 and all(x < y for x, y in pairwise(times))
        out.extend(b"\0" * (-len(out) % 4))
        a["bufferView"] = len(j["bufferViews"])
        a.pop("byteOffset", None)
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(out), "byteLength": size})
        out.extend(chunk)
        copied[index] = len(j["accessors"])
        j["accessors"].append(a)
        return copied[index]

    for name in ("PIVOT_LEFT", "PIVOT_RIGHT"):
        matches = [a for a in incoming["animations"] if a["name"] == PREFIX + name]
        assert len(matches) == 1, name
        animation = copy.deepcopy(matches[0])
        animation["name"] = name
        channels = set()
        for channel in animation["channels"]:
            target = channel["target"]
            source_name = incoming["nodes"][target["node"]]["name"]
            target["node"] = names[BONES.get(source_name, source_name)]
            assert target["node"] in joints and target["path"] in ("translation", "rotation", "scale")
            sampler = animation["samplers"][channel["sampler"]]
            times = incoming["accessors"][sampler["input"]]
            values = incoming["accessors"][sampler["output"]]
            assert times["type"] == "SCALAR" and times["count"] == values["count"]
            assert values["type"] == ("VEC4" if target["path"] == "rotation" else "VEC3")
            channels.add((target["node"], target["path"]))
        assert channels and channels <= expected and len(channels) == len(animation["channels"])
        for sampler in animation["samplers"]:
            assert sampler.get("interpolation", "LINEAR") in ("LINEAR", "STEP")
            sampler["input"] = accessor(sampler["input"])
            sampler["output"] = accessor(sampler["output"])
        j["animations"].append(animation)
    assert out[:len(binary)] == binary
    j["buffers"][0]["byteLength"] = len(out)
    temporary = OUT.with_suffix(".glb.tmp")
    try:
        write_glb(temporary, j, bytes(out))
        temporary.replace(OUT)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"{OUT}: appended PIVOT_LEFT/PIVOT_RIGHT; original {len(binary)} BIN bytes retained")


def main() -> None:
    j, b = read_glb(SRC)
    image_views = {im["bufferView"]: i for i, im in enumerate(j["images"])}
    out = bytearray()
    for vi, bv in enumerate(j["bufferViews"]):
        off = bv.get("byteOffset", 0)
        chunk = b[off:off + bv["byteLength"]]
        if vi in image_views:
            im = j["images"][image_views[vi]]
            img = Image.open(io.BytesIO(chunk)).convert("RGB")
            buf = io.BytesIO()
            img.save(buf, "JPEG", quality=QUALITY, subsampling=0)
            chunk = buf.getvalue()
            im["mimeType"] = "image/jpeg"
        out += b"\0" * (-len(out) % 4)
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(chunk)
        out += chunk
    j["buffers"] = [{"byteLength": len(out)}]
    for n in j["nodes"]:
        n["name"] = BONES.get(n.get("name", ""), n.get("name", ""))
    for a in j["animations"]:
        if a["name"].startswith(PREFIX):
            a["name"] = a["name"][len(PREFIX):]
    root = j["nodes"][j["scenes"][0]["nodes"][0]]
    assert root["name"] == "cavalry_rig", root["name"]
    assert "rotation" not in root and "matrix" not in root, "the root already turns"
    root["rotation"] = [0.0, 1.0, 0.0, 0.0]
    write_glb(OUT, j, bytes(out))
    acc = j["accessors"]
    prim = j["meshes"][0]["primitives"][0]
    print("%s: %d tris, %d bones, clips %s, images %s, %.1f MB" % (
        OUT.relative_to(ROOT), acc[prim["indices"]]["count"] // 3, len(j["skins"][0]["joints"]),
        [a["name"] for a in j["animations"]], [im["name"] for im in j["images"]], OUT.stat().st_size / 1e6))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--pivots"]:
        assert len(sys.argv) == 4, "--pivots BASE_INSTALLED.glb PIVOT_EXPORT.glb"
        install_pivots(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        main()
