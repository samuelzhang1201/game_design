"""Texture a Hunyuan3D white model by PROJECTING its own 2D reference onto it
(owner 2026-09-24, "方案 A": the paint stage needs ~50 GB and swaps for half
an hour a house on the owner's 48 GB Mac; this takes seconds).

  blender -b --factory-startup --python tools/map3d/project_house_texture.py -- TYPE [TYPE ...]

For each TYPE it reads the newest white model
(~/ComfyUI-Shared/output/3D/houses/house_<type>_white_*.glb, the `shape`
stage of gen_house_sources.py) and its reference
(assets/flux/out/house_ref/<type>.png, cut out by the newest
house_<type>_rgba_*.png beside the white model), and writes
assets/hunyuan_ref/houses/sources/<type>.glb — the same input decimate_houses.py
takes from the paint stage.

How:
  1. FIND the reference's camera. Hunyuan's shape stands the building so the
     reference is an orthographic view of it, but not along which axis, so
     the view is searched: every azimuth and a range of elevations, the
     white model's silhouette from each (fitted to the cut-out's bounds)
     scored by its overlap with the cut-out (IoU), coarse then fine.
  2. The model is welded, decimated to the game's budget (decimate_houses.py's
     own rule) and unwrapped.
  3. Every face the reference camera SEES (facing it, and not hidden by
     another part — a ray to the camera) is painted from the reference. The
     rest is painted from the same picture projected from the OPPOSITE
     side: a house is near enough symmetric under a half turn that its back
     walls take its front walls' stone, windows and all.
  4. The atlas is rasterised in numpy (no bake, no render), and grown out
     into the gaps between islands so its mips never average in black.
"""

import bmesh
import bpy
import glob
import math
import os
import sys

import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF_DIR = os.path.join(ROOT, "assets", "flux", "out", "house_ref")
OUT = os.environ.get("PROJECT_OUT", os.path.join(ROOT, "assets", "hunyuan_ref", "houses", "sources"))
GEN = os.path.join(os.path.expanduser("~/ComfyUI-Shared/output"), "3D", "houses")

ATLAS_PX = 1024
SEARCH_PX = 128                 # silhouette raster for the camera search
BUDGET_TRIS = 2400              # decimate_houses.py re-decimates to the type's own budget
# Elevations searched, degrees. Never below 0: every reference is shot from
# "a slightly elevated camera", and an orthographic silhouette from below is
# near enough the one from above that the search took -9 and -13 on two
# houses, and painted their roofs from the half turn.
EL_RANGE = range(0, 46, 5)
FACING_MIN = 0.05               # n . view below this is not seen from that camera
GROW_PX = 24


def log(msg):
    print("project_house_texture: " + msg, flush=True)


def newest(pattern):
    found = sorted(glob.glob(pattern))
    if not found:
        raise RuntimeError("nothing at " + pattern)
    return found[-1]


def load_image(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]  # row 0 = top
    bpy.data.images.remove(im)
    return px


def camera_frame(az_deg, el_deg):
    """(direction TO the camera, right, up) for an orthographic view."""
    az, el = math.radians(az_deg), math.radians(el_deg)
    c = np.array([math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)])
    f = -c
    r = np.cross(f, [0.0, 0.0, 1.0])
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return c, r, u


def fit(pts2, box):
    """Scale and offset taking projected points' bounds onto the image box
    (x0, y0, x1, y1 in px, y down): one uniform scale, centres matched."""
    lo, hi = pts2.min(axis=0), pts2.max(axis=0)
    s = 0.5 * ((box[2] - box[0]) / max(hi[0] - lo[0], 1e-6) + (box[3] - box[1]) / max(hi[1] - lo[1], 1e-6))
    cx, cy = 0.5 * (box[0] + box[2]), 0.5 * (box[1] + box[3])
    mid = 0.5 * (lo + hi)
    return s, np.array([cx - s * mid[0], cy + s * mid[1]])


def to_px(p3, frame, s, off):
    _, r, u = frame
    sx, sy = (s[0], s[1]) if np.ndim(s) else (s, s)
    return np.stack([p3 @ r * sx + off[0], -(p3 @ u) * sy + off[1]], axis=1)


def raster_mask(tri_px, size):
    """Fill triangles (N, 3, 2 px) into a boolean mask, by bounding box."""
    m = np.zeros((size, size), dtype=bool)
    for t in tri_px:
        x0, y0 = np.floor(t.min(axis=0)).astype(int)
        x1, y1 = np.ceil(t.max(axis=0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        inside = barycentric_inside(t, xs, ys)[0]
        m[y0:y1 + 1, x0:x1 + 1] |= inside
    return m


def barycentric_inside(t, xs, ys):
    (ax, ay), (bx, by), (cx, cy) = t
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(d) < 1e-12:
        return np.zeros(xs.shape, dtype=bool), None
    l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
    l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
    l3 = 1.0 - l1 - l2
    eps = -1e-4
    return (l1 >= eps) & (l2 >= eps) & (l3 >= eps), (l1, l2, l3)


def search_camera(tris3, mask):
    size = mask.shape[0]
    ys, xs = np.nonzero(mask)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    flat = tris3.reshape(-1, 3)

    def score(az, el):
        fr = camera_frame(az, el)
        s, off = fit(np.stack([flat @ fr[1], -(flat @ fr[2])], axis=1) * [1, -1], box)
        sil = raster_mask(to_px(flat, fr, s, off).reshape(-1, 3, 2), size)
        inter = np.logical_and(sil, mask).sum()
        return inter / max(np.logical_or(sil, mask).sum(), 1)

    best = max(((score(az, el), az, el) for az in range(0, 360, 10) for el in EL_RANGE))
    _, az0, el0 = best
    best = max(((score(az, el), az, el)
                for az in range(az0 - 8, az0 + 9, 2) for el in range(el0 - 4, el0 + 5, 2)))
    return best


def scaled(s, off, box, adjust):
    """Apply refine()'s (scale, dx, dy) about the box's centre."""
    kx, ky, dx, dy = adjust[0], adjust[1], adjust[2], adjust[3]
    cx, cy = 0.5 * (box[0] + box[2]), 0.5 * (box[1] + box[3])
    return np.array([s * kx, s * ky]), np.array([cx + (off[0] - cx) * kx + dx, cy + (off[1] - cy) * ky + dy])


def refine(tris3, alpha, az, el, box, px=192):
    """The bounds fit matches extents, not shapes: a chimney or an eave the
    reference and the model disagree on pulls it off by a few percent, and
    the roof's tiles land on the wall under the eaves. So the view (to a
    degree), each axis's scale and the shift are searched for the best
    overlap at `px`, coordinate by coordinate. Returns (az, el, (kx, ky, dx,
    dy), iou)."""
    step = alpha.shape[0] // px
    mask = alpha[::step, ::step][:px, :px]
    flat = tris3.reshape(-1, 3)
    span = 0.04 * (box[2] - box[0])

    def iou_of(p):
        a, e, kx, ky, dx, dy = p
        fr = camera_frame(a, e)
        s, off = fit(np.stack([flat @ fr[1], -(flat @ fr[2])], axis=1) * [1, -1], box)
        s2, off2 = scaled(s, off, box, (kx, ky, dx, dy))
        sil = raster_mask(to_px(flat, fr, s2 / step, off2 / step).reshape(-1, 3, 2), px)
        return np.logical_and(sil, mask).sum() / max(np.logical_or(sil, mask).sum(), 1)

    p = [az, el, 1.0, 1.0, 0.0, 0.0]
    steps = [2.0, 2.0, 0.03, 0.03, span / 3, span / 3]
    best = iou_of(p)
    for _ in range(3):
        for i in range(6):
            improved = True
            while improved:
                improved = False
                for sign in (-1, 1):
                    q = list(p)
                    q[i] += sign * steps[i]
                    if q[1] < 0.0:
                        continue
                    v = iou_of(q)
                    if v > best + 1e-4:
                        p, best, improved = q, v, True
                        break
        steps = [x * 0.5 for x in steps]
    return p[0], p[1], tuple(p[2:]), best


def paper_cut(ref, paper=0.92):
    """The building's mask when no BiRefNet cut-out was saved: the paper is
    the near-white flooded in from the picture's border, so a white wall the
    timbers enclose stays building (the aerial settlements' own cut-out)."""
    white = ref.min(axis=2) > paper
    bg = np.zeros(white.shape, dtype=bool)
    bg[0, :], bg[-1, :], bg[:, 0], bg[:, -1] = white[0, :], white[-1, :], white[:, 0], white[:, -1]
    while True:
        grown = bg.copy()
        grown[1:] |= bg[:-1]
        grown[:-1] |= bg[1:]
        grown[:, 1:] |= bg[:, :-1]
        grown[:, :-1] |= bg[:, 1:]
        grown &= white
        if (grown == bg).all():
            return ~bg
        bg = grown


def grow(img, filled, px):
    """Flood filled pixels' colours outward into the unfilled, nearest first."""
    a, f = img.copy(), filled.copy()
    for _ in range(px):
        empty = ~f
        if not empty.any():
            break
        got = np.zeros(f.shape, dtype=bool)
        src = np.zeros_like(a)
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nb = np.roll(f, shift, axis=axis)
            take = empty & nb & ~got
            src[take] = np.roll(a, shift, axis=axis)[take]
            got |= take
        a[got] = src[got]
        f |= got
    return a


def sample(ref, uv_px):
    h, w = ref.shape[:2]
    x = np.clip(uv_px[..., 0], 0, w - 1.001)
    y = np.clip(uv_px[..., 1], 0, h - 1.001)
    x0, y0 = x.astype(int), y.astype(int)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    c = (ref[y0, x0] * (1 - fx) * (1 - fy) + ref[y0, x0 + 1] * fx * (1 - fy)
         + ref[y0 + 1, x0] * (1 - fx) * fy + ref[y0 + 1, x0 + 1] * fx * fy)
    return c


def build(t):
    white = newest(os.path.join(GEN, "house_%s_white_*.glb" % t))
    ref = load_image(os.path.join(REF_DIR, t + ".png"))[..., :3]
    cuts = sorted(glob.glob(os.path.join(GEN, "house_%s_rgba_*.png" % t)))
    alpha = load_image(cuts[-1])[..., 3] > 0.5 if cuts else paper_cut(ref)
    # Grow the building's colour out over the paper, so a face at the
    # silhouette's edge samples wall, not white.
    ref = grow(ref, alpha, 24)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=white)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-4)
    bm.to_mesh(ob.data)
    bm.free()
    m = ob.modifiers.new("d", "DECIMATE")
    m.ratio = min(1.0, BUDGET_TRIS / max(len(ob.data.polygons), 1))
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="d")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    me = ob.data
    me.calc_loop_triangles()

    verts = np.array([v.co[:] for v in me.vertices])
    tri_v = np.array([lt.vertices[:] for lt in me.loop_triangles])
    tri_l = np.array([lt.loops[:] for lt in me.loop_triangles])
    tri_p = np.array([lt.polygon_index for lt in me.loop_triangles])
    uv = np.array([d.uv[:] for d in me.uv_layers.active.data])
    normals = np.array([me.polygons[i].normal[:] for i in tri_p])
    tris3 = verts[tri_v]

    small = alpha[::alpha.shape[0] // SEARCH_PX, ::alpha.shape[1] // SEARCH_PX][:SEARCH_PX, :SEARCH_PX]
    iou, az, el = search_camera(tris3, small)
    log("%s: reference camera az %d el %d, silhouette IoU %.3f" % (t, az, el, iou))

    ys, xs = np.nonzero(alpha)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    az, el, adjust, iou = refine(tris3, alpha, az, el, box)
    log("%s: fit refined to az %.1f el %.1f, scale x%.3f y%.3f, shift %+.1f/%+.1f px, IoU %.3f"
        % ((t, az, el) + adjust + (iou,)))
    bvh = BVHTree.FromPolygons([Vector(v) for v in verts], [list(p.vertices) for p in me.polygons])
    views = []
    for turn in (0, 180):
        fr = camera_frame(az + turn, el)
        flat = tris3.reshape(-1, 3)
        s, off = fit(np.stack([flat @ fr[1], -(flat @ fr[2])], axis=1) * [1, -1], box)
        s, off = scaled(s, off, box, adjust)
        facing = normals @ fr[0]
        seen = facing > FACING_MIN
        centres = tris3.mean(axis=1)
        for i in np.nonzero(seen)[0]:
            o = Vector(centres[i] + normals[i] * 1e-3)
            hit = bvh.ray_cast(o, Vector(fr[0]), 10.0)
            if hit[0] is not None:
                seen[i] = False
        views.append((to_px(flat, fr, s, off).reshape(-1, 3, 2), facing, seen))
    front, back = views
    if os.environ.get("PROJECT_DEBUG"):
        sil = raster_mask(front[0][front[1] > -2], alpha.shape[0])
        dbg = np.zeros(alpha.shape + (4,), dtype=np.float32)
        dbg[..., 0] = alpha
        dbg[..., 1] = sil
        dbg[..., 3] = 1
        im = bpy.data.images.new("dbg", alpha.shape[1], alpha.shape[0], alpha=True)
        im.pixels[:] = dbg[::-1].reshape(-1)
        im.filepath_raw = os.path.join(os.environ["PROJECT_DEBUG"], t + "_fit.png")
        im.file_format = "PNG"
        im.save()
    use_front = front[2] | (~back[2] & (front[1] >= back[1]))
    log("%s: %d of %d triangles seen by the reference, %d by its half turn"
        % (t, int(front[2].sum()), len(tri_v), int((~use_front).sum())))

    atlas = np.zeros((ATLAS_PX, ATLAS_PX, 3), dtype=np.float32)
    filled = np.zeros((ATLAS_PX, ATLAS_PX), dtype=bool)
    for i in range(len(tri_v)):
        a = uv[tri_l[i]] * ATLAS_PX
        a[:, 1] = ATLAS_PX - a[:, 1]
        proj = (front if use_front[i] else back)[0][i]
        x0, y0 = np.floor(a.min(axis=0)).astype(int)
        x1, y1 = np.ceil(a.max(axis=0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, ATLAS_PX - 1), min(y1, ATLAS_PX - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        inside, bary = barycentric_inside(a, gx, gy)
        if bary is None or not inside.any():
            continue
        l1, l2, l3 = bary
        p = (l1[..., None] * proj[0] + l2[..., None] * proj[1] + l3[..., None] * proj[2])
        col = sample(ref, p)
        region = atlas[y0:y1 + 1, x0:x1 + 1]
        region[inside] = col[inside]
        filled[y0:y1 + 1, x0:x1 + 1] |= inside
    atlas = grow(atlas, filled, GROW_PX)

    im = bpy.data.images.new("%s_albedo" % t, ATLAS_PX, ATLAS_PX, alpha=False)
    rgba = np.ones((ATLAS_PX, ATLAS_PX, 4), dtype=np.float32)
    rgba[..., :3] = atlas[::-1]
    im.pixels[:] = rgba.reshape(-1)
    im.file_format = "PNG"
    im.pack()
    mat = bpy.data.materials.new(t)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = im
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.clear()
    me.materials.append(mat)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, t + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                              export_image_format="JPEG", export_jpeg_quality=92)
    log("%s -> %s" % (t, os.path.relpath(path, ROOT)))


def main():
    for t in sys.argv[sys.argv.index("--") + 1:]:
        build(t)


main()
