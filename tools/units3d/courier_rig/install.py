"""Install the re-rigged courier (tools/units3d/courier_rig/) over the courier piece -- the cavalry's
installer with the courier's names.

    python3 tools/units3d/courier_rig/install.py [SRC.glb]

SRC defaults to the main checkout's assets/3D/units/courier/model_wip/rig/courier_rigged.glb (git-ignored,
exported from courier_rig_work.blend by export.py). Writes assets/3D/units/courier/courier.glb with:
  * the clips named as the game plays them (GALLOP, IDLE: the NLA tracks already carry the names);
  * the head bones renamed: the chip hangs over the bone named `head` (Map3DUnitRig.head_m), so the
    rider's R_Head -> head and the horse's Head -> head_h (as the cavalry and the king);
  * the rig turned half round: the blender-auto-rig frame faces Blender -Y (glTF +Z), every piece
    faces glTF -Z (Map3DUnits.yaw_for);
  * the three 2048 maps re-encoded JPEG under their old names, so Godot's import refreshes the very
    courier_courier_atlas{,_n,_mr}.jpg the scene's material points at.
Then: Godot's import. The scene (scenes/models/units/courier.tscn) and the .import carry over.
"""
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/units3d/royal_install"))
from install import read_glb, write_glb  # noqa: E402  (the king's GLB reader / writer)

MAIN = Path("/Users/samuelzhang/game_design")      # the git-ignored source lives in the main checkout
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else MAIN / "assets/3D/units/courier/model_wip/rig/courier_rigged.glb"
OUT = ROOT / "assets/3D/units/courier/courier.glb"
QUALITY = 92
BONES = {"Head": "head_h", "R_Head": "head"}
PREFIX = "courier_"
IMAGES = {"courier_atlas", "courier_atlas_n", "courier_atlas_mr"}


def main() -> None:
    j, b = read_glb(SRC)
    assert {im["name"] for im in j["images"]} == IMAGES, [im["name"] for im in j["images"]]
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
    assert root["name"] == "courier_rig", root["name"]
    assert "rotation" not in root and "matrix" not in root, "the root already turns"
    root["rotation"] = [0.0, 1.0, 0.0, 0.0]
    write_glb(OUT, j, bytes(out))
    acc = j["accessors"]
    prim = j["meshes"][0]["primitives"][0]
    print("%s: %d tris, %d bones, clips %s, images %s, %.1f MB" % (
        OUT.relative_to(ROOT), acc[prim["indices"]]["count"] // 3, len(j["skins"][0]["joints"]),
        [a["name"] for a in j["animations"]], [im["name"] for im in j["images"]], OUT.stat().st_size / 1e6))


if __name__ == "__main__":
    main()
