# The WAR ROOM's wooden unit pieces (owner 2026-10-06): Tripo generations of
# carved oak figures on a round lacquered plinth with an iron band, fitted for
# the table. exec'd in the OWNER's Blender through the MCP (README.md here):
#
#   P = {"CC_ROOT": "/Users/samuelzhang/game_design"}
#   exec(open(P["CC_ROOT"] + "/tools/war_room/blender/wr_pieces.py").read(), P)
#   P["load_all"](); P["build"]("cavalry"); P["export"]("cavalry")
#
# Each piece: turned to face game -Z (Blender +Y), its plinth's foot centred on
# the origin and scaled to a diameter of 1 (the game sizes it by
# war_piece_base_mm), collapsed to TRIS triangles on Tripo's own UVs, the
# textures cut to TEX px. The plinth's lacquer is the realm's colour in the
# game (owner: 底座漆色按国家颜色), so the blue Tripo painted is read off the
# albedo into piece_<arm>_lacquer.png: R = how much of the pixel is lacquer,
# G = the paint's own light and shade (V over twice its mean), B unused.
import bpy, bmesh, glob, os
import numpy as np

CC_ROOT = globals().get("CC_ROOT", "/Users/samuelzhang/game_design")
# The git-ignored sources live in the main checkout's inbox, or after
# processing in each piece's model_wip/tripo/.
SRC_ROOT = globals().get("SRC_ROOT", "/Users/samuelzhang/game_design")
INBOX = SRC_ROOT + "/assets/3D/model_wip/tripo_inbox/war_room"
OUT = CC_ROOT + "/assets/3D/war_room"
SCENE = "WarPieces"
TRIS = 15000
TEX = 1024
PLINTH_SLICE = 0.02   # the bottom share of the height read as the plinth's foot
WELD = 1e-5          # plinth diameters: vertices this close are one (the glTF seam split)
# yaw (degrees about Blender Z) that turns the source's front to Blender +Y,
# read off the source's own views: the infantry and the gun face -Y, the
# horses -X, the archer aims +X, the trebuchet throws toward its counterweight (+X).
JOBS = {
    "infantry": {"yaw": 180.0},
    "cavalry": {"yaw": -90.0},
    "royal": {"yaw": -90.0},
    "archers": {"yaw": 90.0},
    "bombard": {"yaw": 180.0},
    "trebuchet": {"yaw": 90.0},
}
ORDER = list(JOBS)


def _scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = sc
    return sc


def _col(name):
    sc = _scene()
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    return col


def _source(arm):
    for d in (f"{INBOX}/piece_{arm}", f"{SRC_ROOT}/assets/3D/war_room/piece_{arm}/model_wip/tripo"):
        found = sorted(glob.glob(d + "/*.glb"))
        if found:
            return found[-1]
    raise FileNotFoundError(f"no Tripo glb for {arm}")


def load(arm):
    """The Tripo glb into WP_<arm> as piece_<arm>_src, x = 3 m × its index."""
    name = f"piece_{arm}_src"
    if name in bpy.data.objects:
        return name
    col = _col("WP_" + arm)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=_source(arm))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        col.objects.link(o)
    mesh = next(o for o in new if o.type == "MESH")
    mesh.name = name
    mesh.location = (3.0 * ORDER.index(arm), 0.0, 0.0)
    return name


def load_all():
    return [load(a) for a in ORDER]


def _image_copy(src, name, size):
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = src.copy()
    img.name = name
    img.scale(size, size)
    img.pack()
    return img


def build(arm):
    """piece_<arm> beside its source (y = 1.5 m): turned, centred, scaled,
    collapsed, its material on TEX-px copies of Tripo's maps."""
    src = bpy.data.objects[load(arm)]
    name = f"piece_{arm}"
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.meshes.remove(old.data)
    me = src.data.copy()
    me.name = name
    ob = bpy.data.objects.new(name, me)
    _col("WP_" + arm).objects.link(ob)

    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    yaw = np.radians(JOBS[arm]["yaw"])
    c, s = np.cos(yaw), np.sin(yaw)
    co = co @ np.array([[c, s, 0.0], [-s, c, 0.0], [0.0, 0.0, 1.0]])
    z0 = co[:, 2].min()
    foot = co[co[:, 2] < z0 + PLINTH_SLICE * (co[:, 2].max() - z0)]
    lo, hi = foot[:, :2].min(0), foot[:, :2].max(0)
    centre = (lo + hi) / 2.0
    diameter = float((hi - lo).max())
    co -= np.array([centre[0], centre[1], z0])
    co /= diameter
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    # glTF splits a vertex at every UV seam; collapsed apart, the islands'
    # edges drifted open into hairline cracks that showed the parchment
    # through (white speckle in the game). Weld them first: Blender keeps UVs
    # per corner, so the seams stay.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD)
    bm.to_mesh(me)
    bm.free()
    me.update()

    mod = ob.modifiers.new("collapse", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    mod.ratio = min(1.0, TRIS / tris)
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in me.polygons:
        p.use_smooth = True

    mat = src.data.materials[0].copy()
    mat.name = name
    roles = {"Base Color": "albedo", "Color": "orm", "Normal": "normal"}
    for n in mat.node_tree.nodes:
        if n.type != "TEX_IMAGE" or not n.outputs["Color"].links:
            continue
        to = n.outputs["Color"].links[0].to_socket.name
        role = "albedo" if to == "Base Color" else ("normal" if n.outputs["Color"].links[0].to_node.type == "NORMAL_MAP" else "orm")
        n.image = _image_copy(n.image, f"{name}_{role}", TEX)
    me.materials.clear()
    me.materials.append(mat)
    ob.location = (3.0 * ORDER.index(arm), 1.5, 0.0)
    ob.scale = (0.5, 0.5, 0.5)  # display only, near the source's size; export writes the mesh at 1
    bpy.context.view_layer.update()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    return {"arm": arm, "tris": tris, "plinth_src_m": round(diameter, 4),
            "height": round(float(co[:, 2].max()), 3),
            "span": [round(float(v), 3) for v in (co[:, :2].max(0) - co[:, :2].min(0))]}


def lacquer(arm):
    """piece_<arm>_lacquer.png from the albedo: R the lacquer's share, G its
    shade normalised to 0.5 at the mean. Blue is the stand-in Tripo painted."""
    img = bpy.data.images[f"piece_{arm}_albedo"]
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[:, :, :3]
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    v = px.max(-1)
    sat = (v - px.min(-1)) / np.maximum(v, 1e-4)
    blue = np.clip((b - np.maximum(r, g)) / 0.08, 0.0, 1.0) * np.clip((sat - 0.2) / 0.2, 0.0, 1.0)
    mean_v = float((v * blue).sum() / max(blue.sum(), 1.0))
    shade = np.clip(v / (2.0 * max(mean_v, 1e-3)), 0.0, 1.0)
    out = np.zeros((h, w, 4), dtype=np.float32)
    out[..., 0] = blue
    out[..., 1] = np.where(blue > 0.0, shade, 0.5)
    out[..., 3] = 1.0
    name = f"piece_{arm}_lacquer"
    m = bpy.data.images.get(name)
    if m:
        bpy.data.images.remove(m)
    m = bpy.data.images.new(name, w, h, alpha=False, float_buffer=False)
    m.colorspace_settings.name = "Non-Color"
    m.pixels.foreach_set(out.ravel())
    d = f"{OUT}/piece_{arm}"
    os.makedirs(d, exist_ok=True)
    m.filepath_raw = f"{d}/{name}.png"
    m.file_format = "PNG"
    m.save()
    return {"arm": arm, "lacquer_share": round(float((blue > 0.5).mean()), 3), "mean_v": round(mean_v, 3)}


def export(arm):
    """assets/3D/war_room/piece_<arm>/piece_<arm>.glb, the mesh at scale 1."""
    ob = bpy.data.objects[f"piece_{arm}"]
    d = f"{OUT}/piece_{arm}"
    os.makedirs(d, exist_ok=True)
    keep = (tuple(ob.location), tuple(ob.scale))
    ob.location, ob.scale = (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)
    for o in bpy.context.view_layer.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    path = f"{d}/piece_{arm}.glb"
    # Godot extracts an embedded image as <glb>_<image name>.png: named by role
    # for the export, they land as piece_<arm>_albedo.png and so on.
    imgs = [bpy.data.images[f"piece_{arm}_{r}"] for r in ("albedo", "orm", "normal")]
    for img in imgs:
        img.name = img.name.rsplit("_", 1)[1]
    try:
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                  export_yup=True, export_apply=True, export_animations=False,
                                  export_skins=False, export_image_format="AUTO")
    finally:
        ob.location, ob.scale = keep
        for img in imgs:
            img.name = f"piece_{arm}_{img.name}"
    return {"arm": arm, "glb": path, "kb": os.path.getsize(path) // 1024}
