"""A contact sheet naming every Tripo part: each part red over the grey model, from the side
and from the front, labelled with its number (Workbench, the parts in the scene's own frame).

    S = {"__file__": ".../parts_sheet.py"}; exec(open(S["__file__"]).read(), S)
    S["tiles"](TILE_DIR, side_axis="Y")       # side_axis: the axis the side camera looks along
    python3 parts_sheet.py TILE_DIR OUT_PNG    # then, outside Blender
"""
import math, os
try:
    import bpy
    from mathutils import Vector
except ImportError:          # compose() runs in the system Python
    bpy = None

TILE = 300
COLL = "Royal_Parts"


def _parts():
    return sorted((o for o in bpy.data.collections[COLL].objects if o.type == "MESH"),
                  key=lambda o: int(o.name.split("_")[-1]))


def _camera(sc, centre, look, size):
    cam = bpy.data.objects.get("sheet_cam")
    if cam is None:
        cam = bpy.data.objects.new("sheet_cam", bpy.data.cameras.new("sheet_cam"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size
    cam.data.clip_end = 100
    cam.location = centre - look * 10
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


def tiles(out_dir, side_axis="Y"):
    """Blender side: <out_dir>/<part>_<view>.png (Blender's Python has no PIL; compose()
    lays them out from the system Python)."""
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type = "STUDIO", "OBJECT"
    sc.render.resolution_x = sc.render.resolution_y = TILE
    sc.render.film_transparent = False
    ps = _parts()
    for o in bpy.data.objects:
        if o.type == "MESH" and o not in ps:
            o.hide_render = True
    lo = Vector((min(min((o.matrix_world @ Vector(c))[i] for c in o.bound_box) for o in ps) for i in range(3)))
    hi = Vector((max(max((o.matrix_world @ Vector(c))[i] for c in o.bound_box) for o in ps) for i in range(3)))
    centre, size = (lo + hi) / 2, max(hi - lo) * 1.05
    side = Vector((0, 1, 0)) if side_axis == "Y" else Vector((1, 0, 0))
    front = Vector((1, 0, 0)) if side_axis == "Y" else Vector((0, 1, 0))
    views = [side, front, Vector((-1, -1, -0.6)).normalized()]
    for p in ps:
        for o in ps:
            o.color = (0.85, 0.1, 0.1, 1) if o is p else (0.75, 0.75, 0.75, 1)
        for j, look in enumerate(views):
            _camera(sc, centre, look, size)
            sc.render.filepath = os.path.join(out_dir, "%s_%d.png" % (p.name.split("_")[-1], j))
            bpy.ops.render.render(write_still=True)
    for o in ps:
        o.color = (1, 1, 1, 1)
    return len(ps)


def compose(out_dir, out, cols=4):
    """System Python: the tiles into one labelled sheet."""
    from PIL import Image, ImageDraw
    ids = sorted({int(f.split("_")[0]) for f in os.listdir(out_dir) if f.endswith(".png")})
    rows = math.ceil(len(ids) / cols)
    im = Image.new("RGB", (cols * TILE * 3, rows * (TILE + 18)), "white")
    d = ImageDraw.Draw(im)
    for k, i in enumerate(ids):
        x, y = (k % cols) * TILE * 3, (k // cols) * (TILE + 18)
        for j in (0, 1, 2):
            im.paste(Image.open(os.path.join(out_dir, "%d_%d.png" % (i, j))).convert("RGB"), (x + j * TILE, y + 18))
        d.text((x + 4, y + 3), str(i), fill="black")
    im.save(out)
    return out


if __name__ == "__main__":
    import sys
    print(compose(sys.argv[1], sys.argv[2]))


PALETTE = [(0.9, 0.1, 0.1), (0.1, 0.6, 0.95), (0.1, 0.8, 0.2), (0.95, 0.8, 0.1), (0.8, 0.2, 0.9),
           (1.0, 0.5, 0.0), (0.0, 0.9, 0.8), (0.5, 0.3, 0.1), (1.0, 0.6, 0.8), (0.3, 0.3, 1.0),
           (0.6, 1.0, 0.4), (0.2, 0.2, 0.2)]


def zoom(ids, out_dir, centre, size, looks):
    """Blender side: the listed parts each in its own colour (PALETTE order), the rest grey,
    rendered from each `looks` direction around `centre` with ortho `size`; returns, per view,
    each part's projected centroid in pixels so compose_zoom() can write its id there."""
    from bpy_extras.object_utils import world_to_camera_view
    import numpy as np
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light, sc.display.shading.color_type = "STUDIO", "OBJECT"
    R = 900
    sc.render.resolution_x = sc.render.resolution_y = R
    ps = _parts()
    for o in bpy.data.objects:
        if o.type == "MESH" and o not in ps:
            o.hide_render = True
    for o in ps:
        n = int(o.name.split("_")[-1])
        o.color = (*PALETTE[ids.index(n) % len(PALETTE)], 1) if n in ids else (0.72, 0.72, 0.72, 1)
    labels = []
    for j, look in enumerate(looks):
        cam = _camera(sc, Vector(centre), Vector(look).normalized(), size)
        sc.render.filepath = os.path.join(out_dir, "zoom_%d.png" % j)
        bpy.ops.render.render(write_still=True)
        lab = {}
        for o in ps:
            n = int(o.name.split("_")[-1])
            if n in ids:
                c = Vector(np.mean([v.co[:] for v in o.data.vertices], axis=0))
                p = world_to_camera_view(sc, cam, o.matrix_world @ c)
                lab[n] = (int(p.x * R), int((1 - p.y) * R))
        labels.append(lab)
    for o in ps:
        o.color = (1, 1, 1, 1)
    return labels


def compose_zoom(out_dir, labels, out):
    from PIL import Image, ImageDraw
    ims = [Image.open(os.path.join(out_dir, "zoom_%d.png" % j)).convert("RGB") for j in range(len(labels))]
    sheet = Image.new("RGB", (sum(i.width for i in ims), ims[0].height), "white")
    x = 0
    for im, lab in zip(ims, labels):
        d = ImageDraw.Draw(im)
        for n, (px, py) in lab.items():
            d.rectangle((px - 2, py - 8, px + 18, py + 8), fill="white")
            d.text((px, py - 6), str(n), fill="black")
        sheet.paste(im, (x, 0)); x += im.width
    sheet.save(out)
    return out
