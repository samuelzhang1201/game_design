"""SPIKE: pack the Poly Haven sets (assets/map3d/sources/polyhaven, .gdignored 4K sources)
into Terrain3D's two maps per texture, at SIZE px:
  <key>_alb_ht.png   albedo RGB + displacement in A (height blending)
  <key>_nrm_rgh.png  OpenGL normal RGB + roughness in A
plus the ambientCG Cliff (rock023, assets/map3d/sources/ambientcg) resized to match - a texture array needs
every layer the same size. Runs inside Blender (it reads the EXRs):
  Blender -b --factory-startup --python tools/map3d/pack_textures.py
"""
import os
import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "map3d", "sources", "polyhaven")
OUT = os.path.join(ROOT, "assets", "map3d", "textures")
SIZE = 2048
DEFAULT_ROUGH = 0.85  # rocky_trail ships no roughness map
SETS = ["leafy_grass", "dry_decay_leaves", "dirt_floor", "rocky_trail",
        "excavated_soil_wall", "sand_03"]


def load(path, colorspace):
    """RGBA float array (H, W, 4) at SIZE, rows top-down, raw values."""
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = colorspace
    if img.size[0] != SIZE:
        img.scale(SIZE, SIZE)
    px = np.empty(SIZE * SIZE * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(SIZE, SIZE, 4)[::-1]  # Blender stores bottom-up


def save(arr, path):
    arr = np.clip(arr, 0.0, 1.0)
    img = bpy.data.images.new("out", SIZE, SIZE, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"  # write the bytes as given
    img.pixels.foreach_set(arr[::-1].astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


os.makedirs(OUT, exist_ok=True)
for key in SETS:
    base = os.path.join(SRC, f"{key}_4k.blend", "textures", key)
    # Non-Color everywhere: the JPEG's sRGB bytes pass through unchanged.
    diff = load(base + "_diff_4k.jpg", "Non-Color")
    disp = load(base + "_disp_4k.png", "Non-Color")
    nor = load(base + "_nor_gl_4k.exr", "Non-Color")
    rough_path = base + "_rough_4k.exr"
    alb = np.dstack([diff[..., :3], disp[..., 0]])
    if os.path.exists(rough_path):
        rough = load(rough_path, "Non-Color")[..., 0]
    else:
        rough = np.full((SIZE, SIZE), DEFAULT_ROUGH, dtype=np.float32)
    nrm = np.dstack([nor[..., :3], rough])
    save(alb, os.path.join(OUT, f"{key}_alb_ht.png"))
    save(nrm, os.path.join(OUT, f"{key}_nrm_rgh.png"))
    print("packed", key, "height", float(disp[..., 0].min()), float(disp[..., 0].max()))

for src, dst in [("rock023_alb_ht", "cliff_alb_ht"), ("rock023_nrm_rgh", "cliff_nrm_rgh")]:
    arr = load(os.path.join(ROOT, "assets", "map3d", "sources", "ambientcg", src + ".png"), "Non-Color")
    save(arr, os.path.join(OUT, dst + ".png"))
print("packed cliff")
