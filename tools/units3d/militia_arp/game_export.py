"""Install build of the town militia figure: the infantry's export (tools/units3d/infantry_arp/game_export.py)
run on the militia source with the militia's names (README beside this file).

Source (git-ignored): assets/3D/model_wip/blender_output/militia/militia_parts_11_hem.blend (rig `rig`, body
`Militia_body`, the infantry's ShortSword `Weapon` / RoundShield `Shield` on cc_weapon.r / .l).
Headless, nothing saved:
  Blender -b -y SOURCE.blend --python tools/units3d/militia_arp/game_export.py -- ROOT [OUT.json]
Writes ROOT/assets/3D/units/militia/: militia.glb (armature `mil_rig`, one skinned mesh `militia`) and
militia_militia_atlas{,_mr,_n}.jpg. The ten clips are named as the infantry's first ten (MARCH ... SLASH_3) and
get the same loop closing, in-place lunges, MARCH contact lock and shield-hand thumb; the body has no authored
material classes, so its baked atlas goes in as it is; the realm tint's mask (militia_tunic_mask.png) is drawn
from the body's `part_id`: the tunic's and the skirt's faces.
Then check what was written: check_glb.py (leg through skirt in the installed file must be none).
"""
import importlib.util
import json
import sys
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("infantry_game_export", HERE.parent / "infantry_arp/game_export.py")
inf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inf)

FIRST_TEN = ("WALK", "IDLE", "STANDBY", "DEFEND", "ATTACK", "SLASH", "ATTACK_VAR1", "ATTACK_2", "SLASH_2", "SLASH_3")
FPS = 30
inf.UNIT = "militia"
inf.RIG_NAME = "mil_rig"
inf.BODY = "Militia_body"
inf.BODY_CLASSES = False
inf.GAME = {k: inf.GAME[k] for k in FIRST_TEN}


# The source body's faces carry their part in the mesh attribute `part_id` (the build's order); the realm's
# colour goes on the dyed cloth: the tunic above the belt and the skirt below it.
PARTS = ("head", "coif", "helmet", "tunic", "legs", "wraps", "shoes", "hands", "skirt", "belt")
TINT_PARTS = ("tunic", "skirt")
MASK_MARGIN_PX = 6
DYE_SATURATION = 0.3            # the russet wool sits near 0.65, the linen near 0.1


def _raster(tris, size):
    """UV triangles (N, 3, 2) in pixels -> a size x size bool raster, rows bottom-up, texel centres tested."""
    out = np.zeros((size, size), bool)
    for t in tris:
        x0, y0 = np.floor(t.min(0)).astype(int)
        x1, y1 = np.ceil(t.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0 - 1, 0), max(y0 - 1, 0), min(x1 + 1, size - 1), min(y1 + 1, size - 1)
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        e = [(t[j][0] - t[i][0]) * (gy - t[i][1]) - (t[j][1] - t[i][1]) * (gx - t[i][0]) for i, j in ((0, 1), (1, 2), (2, 0))]
        tol = 0.75 * max(float(np.abs(t[1] - t[0]).max()), float(np.abs(t[2] - t[1]).max()), 1.0)   # a texel's reach
        inside = ((e[0] >= -tol) & (e[1] >= -tol) & (e[2] >= -tol)) | ((e[0] <= tol) & (e[1] <= tol) & (e[2] <= tol))
        out[y0:y1 + 1, x0:x1 + 1] |= inside
    return out


def _grow(a):
    out = a.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out |= np.roll(a, (dy, dx), (0, 1))
    return out


def tunic_mask():
    """The realm tint's mask (`militia_tunic_mask.png`'s pixels, rows bottom-up, 0..1): the tunic's and the
    skirt's faces drawn where the body sits in the atlas, grown by the bake's margin without entering another
    part's island, edges softened as the infantry's mask is."""
    me = bpy.data.objects[inf.BODY].data
    ids = np.zeros(len(me.vertices), np.int32)
    me.attributes["part_id"].data.foreach_get("value", ids)
    uv = np.zeros(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    u0, v0, du, dv = inf.REGION["body"]
    uv = (np.array([u0, v0]) + uv.reshape(-1, 2) * np.array([du, dv])) * inf.ATLAS
    me.calc_loop_triangles()
    tint = {PARTS.index(p) for p in TINT_PARTS}
    cloth, other = [], []
    for t in me.loop_triangles:
        (cloth if int(ids[t.vertices[0]]) in tint else other).append(uv[list(t.loops)])
    m, o = _raster(np.array(cloth), inf.ATLAS), _raster(np.array(other), inf.ATLAS)
    o &= ~m
    for _ in range(MASK_MARGIN_PX):
        m, o = m | (_grow(m) & ~o), o | (_grow(o) & ~m)
    # only the DYED cloth: the linen showing at the neck and cuffs is in the tunic's faces and stays white
    mat = bpy.data.objects[inf.BODY].data.materials[0]
    base = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image
                and Path(n.image.filepath).stem.endswith("_base"))
    w, h = int(du * inf.ATLAS), int(dv * inf.ATLAS)
    px = inf._pixels(base, w, h)[..., :3]
    dyed = np.zeros_like(m)
    dyed[int(v0 * inf.ATLAS):int(v0 * inf.ATLAS) + h, int(u0 * inf.ATLAS):int(u0 * inf.ATLAS) + w] = \
        (px.max(2) - px.min(2)) > DYE_SATURATION * np.maximum(px.max(2), 1e-4)
    return inf.tunic_mask.box((m & dyed).astype(np.float32), 2)


def _tunic_luminance(albedo_jpg, mask):
    """The atlas's mean linear luminance over the mask: the tint material's `tunic_luminance`."""
    im = bpy.data.images.load(str(albedo_jpg), check_existing=False)
    px = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)[..., :3]
    bpy.data.images.remove(im)
    lin = np.where(px <= 0.04045, px / 12.92, ((px + 0.055) / 1.055) ** 2.4)
    return round(float((lin @ np.array([0.2126, 0.7152, 0.0722]))[mask > 0.5].mean()), 3)


def install(root):
    # the clips are authored at 30 a second (the infantry's); the source's scene was left at Blender's 24, and
    # the glTF exporter times keys by the scene: at 24 every clip played a fifth slow
    scn = bpy.context.scene
    scn.render.fps, scn.render.fps_base = FPS, 1.0
    mask = tunic_mask()                      # from the source body, before the export joins and renames
    info = inf.install(root)
    out = Path(root) / "assets/3D/units" / inf.UNIT
    (out / (inf.UNIT + "_tunic_mask.png")).write_bytes(inf.tunic_mask.png_gray(mask))
    info["tunic_mask"] = {"coverage": round(float((mask > 0.5).mean()), 4),
                          "tunic_luminance": _tunic_luminance(info["files"]["albedo"], mask)}
    return info


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = install(argv[0])
    text = json.dumps(result, indent=1, default=str)
    if len(argv) > 1:
        Path(argv[1]).write_text(text)
    print("MILITIA_EXPORT", text)
