"""Install build of the town militia figure: the infantry's export (tools/units3d/infantry_arp/game_export.py)
run on the militia source with the militia's names (README beside this file).

Source (git-ignored): assets/3D/model_wip/blender_output/militia/militia_parts_12_duel.blend (rig `rig`, body
`Militia_body`, the infantry's ShortSword `Weapon` / RoundShield `Shield` on cc_weapon.r / .l).
Headless, nothing saved:
  Blender -b -y SOURCE.blend --python tools/units3d/militia_arp/game_export.py -- ROOT [OUT.json]
Writes ROOT/assets/3D/units/militia/: militia.glb (armature `mil_rig`, one skinned mesh `militia`) and
militia_militia_atlas{,_mr,_n}.jpg. The ten clips are named as the infantry's first ten (MARCH ... SLASH_3), then
the duel's BLOCK..BLOCK_4 and HIT..HIT_3 (no DEATH yet: its skirt fails lying down, spec
2026-11-26-militia-figure-wiring-design step 1b); they get the same loop closing, in-place lunges, MARCH contact lock and shield-hand thumb; the body has no authored
material classes, so its baked atlas goes in as it is; the realm tint's mask (militia_tunic_mask.png) is drawn
from the body's `part_id`: the tunic's and the skirt's faces.
Then check what was written: check_glb.py (leg through skirt in the installed file must be none).
"""
import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

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
DUEL = ("BLOCK", "BLOCK_2", "BLOCK_3", "BLOCK_4", "HIT", "HIT_2", "HIT_3")
inf.GAME = {k: inf.GAME[k] for k in FIRST_TEN + DUEL}


# The skirt's keys are baked in the source for the legs it has there; the export's MARCH lock then moves the
# legs. Where the installed file still shows a leg through the cloth (check_glb.py names the frame, counted from
# 0, and the chains), those chains' _b and _c bones swing further out here, as the source's `nudge` does: the
# degrees on the frame, half on the frames either side, a quarter one further.
SKIRT_NUDGE = {"WALK": ((22, (8, 9), 5.0), (24, (8, 9), 4.0), (25, (3, 4), 5.0), (27, (3, 4), 3.0))}
_poses = inf._poses


def _nudged_poses(src, keep, clip):
    poses = _poses(src, keep, clip)
    n = len(poses) - 1                       # the last pose is the first again
    for frame, chains, deg in SKIRT_NUDGE.get(clip, ()):
        for df, w in ((0, 1.0), (-1, 0.5), (1, 0.5), (-2, 0.25), (2, 0.25)):
            pose = poses[(frame + df) % n]
            for k in chains:
                b, c = "skirt_%02d_b" % k, "skirt_%02d_c" % k
                for pivot, moved in ((b, (b, c)), (c, (c,))):
                    h = pose[pivot].translation.copy()
                    out = Vector((h.x - pose["root.x"].translation.x, h.y - pose["root.x"].translation.y, 0.0)).normalized()
                    turn = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg * w), 4, Vector((0, 0, -1)).cross(out)) \
                        @ Matrix.Translation(-h)
                    for name in moved:
                        pose[name] = turn @ pose[name]
    for name in poses[0]:
        poses[-1][name] = poses[0][name].copy()
    return poses


inf._poses = _nudged_poses


# The source body's faces carry their part in the mesh attribute `part_id` (the build's order); the realm's
# colour goes on the dyed cloth: the tunic above the belt and the skirt below it.
PARTS = ("head", "coif", "helmet", "tunic", "legs", "wraps", "shoes", "hands", "skirt", "belt")
TINT_PARTS = ("tunic", "skirt")
MASK_MARGIN_PX = 6
LINEN = (0.3, 0.65)             # linen: less saturated than this AND brighter than this (the wool: 0.65 / 0.4)


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
    part's island, less the linen; softened outward only."""
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
    faces = o.copy()                         # the other parts' own texels: never tinted
    for _ in range(MASK_MARGIN_PX):
        m, o = m | (_grow(m) & ~o), o | (_grow(o) & ~m)
    mat = bpy.data.objects[inf.BODY].data.materials[0]
    base = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image
                and Path(n.image.filepath).stem.endswith("_base"))
    w, h = int(du * inf.ATLAS), int(dv * inf.ATLAS)
    px = np.zeros((inf.ATLAS, inf.ATLAS, 3), np.float32)
    px[int(v0 * inf.ATLAS):int(v0 * inf.ATLAS) + h, int(u0 * inf.ATLAS):int(u0 * inf.ATLAS) + w] = inf._pixels(base, w, h)[..., :3]
    hi = px.max(2)
    sat = (hi - px.min(2)) / np.maximum(hi, 1e-4)
    # The tunic's faces also carry the linen at the neck (bright, unsaturated): it stays white. A grey stain on the
    # wool is cloth all the same: cut by saturation alone it showed as a rust spot on the tinted skirt, and a mask
    # softened INTO its own islands left a rust seam where two islands lie close (critic 2026-11-24). So the
    # cloth's texels are fully set, the softening runs outward only, and never onto another part's faces.
    m &= ~((sat < LINEN[0]) & (hi > LINEN[1]))
    soft = np.maximum(inf.tunic_mask.box(m.astype(np.float32), 2), m.astype(np.float32))
    return np.where(faces, 0.0, soft).astype(np.float32)


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
