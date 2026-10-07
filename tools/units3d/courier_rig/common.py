"""The courier re-rigged and re-animated the way the cavalry was (owner 2026-10-07: 请根据最新骑兵动作建模
流程，重新设计信使的动作 -- GALLOP a four-beat gallop, IDLE; the existing game mesh). The royal rig's
helpers are exec'd first, then this file points them at the courier:

    G = {}
    for f in ("royal_rig/common", "royal_rig/labels", "royal_rig/weights", "royal_rig/validate",
              "royal_rig/actions", "courier_rig/common", ...):
        G["__file__"] = ".../tools/units3d/%s.py" % f; exec(open(G["__file__"]).read(), G)

Source: the game mesh `courier` of courier_rigged_tripo.blend (tools/units3d/courier_build.py's output:
43 Tripo parts, one 2048 atlas, 19,346 tris), every vertex carrying `part_id` (the row of
tools/units3d/courier/tripo_parts.csv) -- the labels come with it. The mesh was modelled mid-walk:
the near foreleg raised, the near hind hoof lifted.
"""
ROOT = "/Users/samuelzhang/game_design/"
COU = ROOT + "assets/3D/units/courier/model_wip/"
SRC_BLEND = COU + "tripo/courier_rigged_tripo.blend"
SRC = COU + "rig/"
WORK = SRC + "courier_rig_work.blend"
SHOTS = SRC + "shots/"
SCENE = "Courier_Rig"
PARTS_CSV = ROOT + "tools/units3d/courier/tripo_parts.csv"
MESH_NAME = "courier"
RIG_NAME = "courier_rig"


def mesh():
    return bpy.data.objects[MESH_NAME]


def rig():
    return bpy.data.objects[RIG_NAME]


def load():
    """The game mesh appended into its own scene, unparented, its old skin dropped, turned to the
    skill's frame: the courier faced +Y with his left at -X; turned half round he faces -Y with his
    left at +X. Hooves stay on z = 0. `part_id` is copied to `part` (the royal helpers' name)."""
    sc = scene()
    for n in (MESH_NAME, RIG_NAME):
        old = bpy.data.objects.get(n)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    # the last load's material and maps go first: appended again they would come in as `.001`,
    # and the export names the maps (Godot extracts `courier_<image name>.jpg`)
    for me in [me for me in bpy.data.meshes if me.name.startswith(MESH_NAME) and me.users == 0]:
        bpy.data.meshes.remove(me)          # the old mesh would keep the material in use
    for m in [m for m in bpy.data.materials if m.name.startswith("courier_atlas") and m.users == 0]:
        bpy.data.materials.remove(m)
    for im in [i for i in bpy.data.images if i.name.startswith("courier_atlas") and i.users == 0]:
        bpy.data.images.remove(im)
    with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
        dst.objects = [MESH_NAME]
    o = dst.objects[0]
    coll("Courier_Mesh").objects.link(o)
    o.parent = None
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.vertex_groups.clear()
    o.data.name = MESH_NAME                 # the glTF mesh takes this name (the art kit checks it)
    o.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    o.matrix_world = Matrix.Identity(4)
    o.data.update()
    write_int(o, "part", read_int(o, "part_id"))
    V = co(o)
    return {"verts": len(V), "tris": tris(o), "min": [round(float(x), 3) for x in V.min(0)],
            "max": [round(float(x), 3) for x in V.max(0)], "materials": [m.name for m in o.data.materials]}


def relax_hems(parts=(1, 6), z_max=0.95, x_max=-0.02, free_r=0.015, passes=5, cap=0.025, near_cap=0.012):
    """The rump shell's hems below the buttocks are saw-toothed open edges (the generator cut the
    off hind leg in under them); at rest the tail hides them, at a gallop the swinging legs show
    them. Each FREE boundary vertex of `parts` below `z_max` (no other part within `free_r`: not a
    seam) is averaged with its neighbours along the boundary, `passes` times, no vertex moved more
    than `cap` metres on the off side (x < `x_max`) and `near_cap` on the near side (relaxed freely
    there, it opened holes in the flank) (blender-auto-rig 4f)."""
    import collections
    from mathutils import kdtree as _kd
    o = mesh()
    me = o.data
    lab = read_int(o, "part")
    P = co(o)
    cnt = collections.Counter()
    for p in me.polygons:
        for ek in p.edge_keys:
            cnt[ek] += 1
    bnb = collections.defaultdict(list)
    for (a_, b_), c in cnt.items():
        if c == 1:
            bnb[a_].append(b_); bnb[b_].append(a_)
    other = np.nonzero(~np.isin(lab, parts))[0]
    kd = _kd.KDTree(len(other))
    for k, i in enumerate(other):
        kd.insert(P[i], k)
    kd.balance()
    free = [v for v in bnb if lab[v] in parts and P[v, 2] < z_max and len(bnb[v]) == 2
            and kd.find(P[v])[2] > free_r]
    Q = P.copy()
    for _ in range(passes):
        R = Q.copy()
        for v in free:
            R[v] = 0.5 * Q[v] + 0.25 * (Q[bnb[v][0]] + Q[bnb[v][1]])
        Q = R
    d = Q[free] - P[free]
    n_ = np.linalg.norm(d, axis=1, keepdims=True)
    lim = np.where(P[free, 0] < x_max, cap, near_cap)[:, None]
    Q[free] = P[free] + d * np.minimum(1.0, lim / np.maximum(n_, 1e-9))
    moved = np.linalg.norm(Q[free] - P[free], axis=1)
    for v in free:
        me.vertices[v].co = Vector(Q[v])
    me.update()
    return {"free_hem_verts": len(free), "moved_mm_max": round(float(moved.max()) * 1000, 1) if len(free) else 0}


def vshot(path, centre, look, size, res=700, colour="VERTEX", xray=None, persp=False):
    """`shot` with the colour source kept (VERTEX shows the debug paint); `xray` an alpha or None."""
    sc = scene()
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type = "STUDIO", colour
    sh.show_xray, sh.xray_alpha = xray is not None, xray or 1.0
    sc.render.resolution_x = sc.render.resolution_y = res
    cam = bpy.data.objects.get("shot_cam") or bpy.data.objects.new("shot_cam", bpy.data.cameras.new("shot_cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.hide_set(True)
    L = Vector(look).normalized()
    cam.data.type = "PERSP" if persp else "ORTHO"
    cam.data.ortho_scale, cam.data.clip_end, cam.data.lens = size, 50, 50
    cam.location = Vector(centre) - L * (size * 1.9 if persp else 10)
    cam.rotation_euler = L.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sh.show_xray = False
    return path


def save():
    bpy.ops.wm.save_as_mainfile(filepath=WORK)
    return WORK
