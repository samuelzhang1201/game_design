"""The cavalry piece from a Tripo 3D generation (owner 2026-09-30: 骑兵改用 tripo 3d 建模，
使用之前步兵同样的方法). Run step by step IN THE OWNER'S OPEN BLENDER through the Blender MCP
(owner 2026-09-29: 你接下来的操作都要在我打开的blender instance上进行), never headless:

    P = ".../cavalry_tripo/tripo.py"; T = {"__file__": P}; exec(open(P).read(), T)
    T["load"]()      # both Tripo files into the scene Tripo_Cavalry
    T["frame"]()     # face +Y, the horse 2.45 m nose to tail, hooves on z = 0

The owner generated it on the PAID Tripo plan (terms 5.2.2) from
assets/3D/units/cavalry/model_wip/tripo_kit/zimage_threequarter_s1.png (Z-Image, our own render:
the in-game design, WITHOUT the shield -- owner: 盾牌单独做，骑士不带盾出图). Two exports of
the same generation, git-ignored in assets/3D/units/cavalry/model_wip/tripo/:
  * armored+knight+3d+model.glb -- one 98k-tri mesh with its PBR maps: the TEXTURE source;
  * medieval+knight+on+horse+parts.glb -- the same shape as 69 untextured parts (48k tris):
    the GAME MESH, one part per plate / leg / strap, so a rider's plate rides its own bone
    whole (the infantry's way) and the horse's parts share one bone-heat solve (the courier's).
Both come in the same frame (their boxes agree to 2 mm), nose at -X, the rider's right at +Y.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = "/Users/samuelzhang/game_design/"
SRC = ROOT + "assets/3D/units/cavalry/model_wip/tripo/"
TEX_FILE = SRC + "armored+knight+3d+model.glb"
PARTS_FILE = SRC + "medieval+knight+on+horse+parts.glb"
HERE = os.path.dirname(os.path.abspath(globals().get("__file__") or ROOT + "tools/units3d/cavalry_tripo/tripo.py"))
SCENE = "Tripo_Cavalry"
HORSE_LENGTH = 2.45        # nose to tail, metres: the scanned cavalry's horse and the courier's

# the horse's parts (tripo_part_<n>), read off the part table and a render: they set the frame
HORSE = (0, 1, 6, 7, 8, 9, 10, 11, 19, 22, 23, 26, 27, 33, 40)


# -------------------------------------------------------------- scene ----

def scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    sc.sync_mode = "NONE"          # playback synced to CoreAudio crashed Blender 5.2 (2026-09-29)
    sc.unit_settings.system = "METRIC"
    if bpy.context.window:
        bpy.context.window.scene = sc
    return sc


def coll(name):
    sc = scene()
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in sc.collection.children:
        sc.collection.children.link(c)
    return c


def _import(path, cname):
    c = coll(cname)
    for o in list(c.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for uc in list(o.users_collection):
            uc.objects.unlink(o)
        c.objects.link(o)
    return new


def _bake_world(o):
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = Matrix.Identity(4)


def load():
    """The textured generation as `tripo_high`, the parts as tripo_part_<n>, no parents."""
    tex = _import(TEX_FILE, "Tripo_Textured")
    parts = _import(PARTS_FILE, "Tripo_Parts")
    bpy.context.view_layer.update()
    for o in tex + parts:
        if o.type == "MESH":
            _bake_world(o)
    for o in tex + parts:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    high = [o for o in bpy.data.collections["Tripo_Textured"].objects][0]
    high.name = "tripo_high"
    return high


def part(n):
    return bpy.data.objects["tripo_part_%d" % n]


def parts():
    return sorted((o for o in bpy.data.collections["Tripo_Parts"].objects if o.type == "MESH"),
                  key=lambda o: int(o.name.split("_")[-1]))


def world_co(o):
    n = len(o.data.vertices)
    co = np.empty(n * 3)
    o.data.vertices.foreach_get("co", co)
    return co.reshape(n, 3)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def activate(o):
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def residual():
    """How far the parts' vertices lie from the textured surface (native units): the two
    exports share one frame, so no fit is needed if this is a few mm."""
    high = bpy.data.objects["tripo_high"]
    bm = bmesh.new(); bm.from_mesh(high.data)
    tree = BVHTree.FromBMesh(bm)
    P = np.vstack([world_co(o) for o in parts()])[::7]
    d = np.array([tree.find_nearest(Vector(p))[3] for p in P])
    bm.free()
    return float(d.mean()), float(np.percentile(d, 95))


ICP_ITERS = 25


def fit():
    """The parts are a second generation of the same shape: ~19 mm mean / 55 mm p95 off
    the textured mesh as exported. A similarity transform (rotation, scale, shift) fitted by
    iterated closest points, trimmed at the 90th percentile each round, puts them on it
    (the courier's icp). Returns the residual before and after, in metres."""
    high = bpy.data.objects["tripo_high"]
    bm = bmesh.new(); bm.from_mesh(high.data)
    tree = BVHTree.FromBMesh(bm)
    P = np.vstack([world_co(o) for o in parts()])[::3]
    R, s, t = np.eye(3), 1.0, np.zeros(3)
    before = None
    for i in range(ICP_ITERS):
        Q = P @ (s * R).T + t
        near = np.array([tree.find_nearest(Vector(q))[0][:] for q in Q])
        d = np.linalg.norm(near - Q, axis=1)
        if before is None:
            before = (float(d.mean()), float(np.percentile(d, 95)))
        keep = d < np.percentile(d, 90)
        A, B = P[keep], near[keep]
        ma, mb = A.mean(0), B.mean(0)
        U, S, Vt = np.linalg.svd((B - mb).T @ (A - ma))
        Dm = np.diag([1, 1, np.sign(np.linalg.det(U @ Vt))])
        R = U @ Dm @ Vt
        s = (S * np.diag(Dm)).sum() / ((A - ma) ** 2).sum()
        t = mb - s * R @ ma
    M = Matrix.Identity(4)
    for i in range(3):
        for j in range(3):
            M[i][j] = s * R[i][j]
        M[i][3] = t[i]
    for o in parts():
        o.data.transform(M)
        o.data.update()
    Q = np.vstack([world_co(o) for o in parts()])[::3]
    d = np.array([tree.find_nearest(Vector(q))[3] for q in Q])
    bm.free()
    return {"before_mm": [round(x * 1000, 1) for x in before],
            "after_mm": [round(float(d.mean()) * 1000, 1), round(float(np.percentile(d, 95)) * 1000, 1)],
            "scale": round(float(s), 4)}


# -------------------------------------------------------------- frame ----

def frame():
    """Face +Y (the nose is at -X), scale the horse to HORSE_LENGTH nose to tail, centre the
    barrel on x = 0, and stand the hooves on z = 0. Applied to the mesh data of both."""
    H = np.vstack([world_co(part(i)) for i in HORSE])
    s = HORSE_LENGTH / (H[:, 0].max() - H[:, 0].min())
    cx = (H[:, 0].max() + H[:, 0].min()) / 2
    barrel = H[(H[:, 2] > H[:, 2].max() * 0.4) & (H[:, 2] < H[:, 2].max() * 0.6)]
    cy = (barrel[:, 1].max() + barrel[:, 1].min()) / 2
    M = Matrix.Scale(s, 4) @ Matrix.Rotation(math.radians(-90), 4, "Z") @ Matrix.Translation((-cx, -cy, 0))
    objs = [bpy.data.objects["tripo_high"]] + parts()
    for o in objs:
        o.data.transform(M)
    z0 = min(world_co(part(i))[:, 2].min() for i in HORSE)
    for o in objs:
        o.data.transform(Matrix.Translation((0, 0, -z0)))
        o.data.update()
    return {"scale": round(s, 4), "top_m": round(max(world_co(o)[:, 2].max() for o in objs), 3)}


# ------------------------------------------------------------ skeleton ----
# The bone NAMES are the scanned cavalry's (cavalry_scan.rig_spec / model_cavalry.rig_spec):
# the horse's, make_units' mounted rider's, `lance` on the off hand and `shield` -- which
# hangs on the rider's BACK here (owner 2026-09-30: 盾牌要背在身后), parented to the chest,
# and is carried to the near arm by GARRISON (animate). The frame after frame(): nose +Y,
# the rider's right (the off side) +X.

UNITS = ROOT + "tools/units3d/"
if UNITS not in sys.path:
    sys.path.insert(0, UNITS)

LEGS = {"fore_r": (8, 19), "fore_l": (11, 40), "hind_r": (6, 23), "hind_l": (7, 22)}
BODY = (1, 26)
MANE = 27
MANE_M = 0.06              # the mane's thickness over the crest: the body's own top under it is a hole
HEAD = (31, 30)
TAIL = 0
CAVALRY_LENGTH = 2.60      # cavalry_scan.rig_spec's leg-top heights were set on this horse


def W(*ids):
    return np.vstack([world_co(part(i)) for i in ids])


def top_at(co, y, half=0.06):
    s = co[(np.abs(co[:, 0]) < half) & (np.abs(co[:, 1] - y) < 0.04)]
    return float(s[:, 2].max())


def slice_centroid(co, z, near_xy, r, dz=0.02):
    sl = co[(np.abs(co[:, 2] - z) < dz) & (np.linalg.norm(co[:, :2] - near_xy, axis=1) < r)]
    return sl.mean(0) if len(sl) else None


def leg_chain(co, hoof, levels, r=0.14):
    at = hoof[:2].copy()
    out = [np.array(hoof)]
    for z in levels:
        c = slice_centroid(co, z, at, r)
        if c is not None:
            at = c[:2]
        out.append(np.array((at[0], at[1], z)))
    return out


def pca_ends(co):
    c = co.mean(0)
    _, _, vt = np.linalg.svd(co - c, full_matrices=False)
    t = (co - c) @ vt[0]
    return co[t < np.percentile(t, 4)].mean(0), co[t > np.percentile(t, 96)].mean(0)


def horse_spec():
    V = Vector
    H = W(*BODY)
    # the crest and the withers are the MANE part (the body part has a hole under it)
    HM = W(*BODY, MANE)
    rear_y, front_y = -0.55, 0.45
    croup, withers = top_at(H, rear_y), top_at(HM, front_y) - MANE_M
    b = [("root", None, V((0, 0, 0)), V((0, 0.3, 0))),
         ("horse_body", "root", V((0, rear_y, croup - 0.30)), V((0, front_y, withers - 0.30)))]
    head = W(*HEAD)
    nose = head[np.argmax(head[:, 1])]
    poll = head[np.argmax(head[:, 2])]
    wither = V((0, 0.50, top_at(HM, 0.50) - MANE_M - 0.22))
    pollv = V((0, poll[1] - 0.06, poll[2] - 0.14))
    mid = (wither + pollv) / 2 + V((0, 0.03, 0.05))
    b += [("neck_1", "horse_body", wither, mid), ("neck_2", "neck_1", mid, pollv),
          ("head_h", "neck_2", pollv, V((0, nose[1] - 0.08, nose[2])))]
    tail = W(TAIL)
    root = tail[tail[:, 2] > tail[:, 2].max() - 0.05].mean(0)
    tip = tail[np.argmin(tail[:, 2])]
    t1, t2 = V(root).lerp(V(tip), 0.33), V(root).lerp(V(tip), 0.66)
    b += [("tail_1", "horse_body", V(root), t1), ("tail_2", "tail_1", t1, t2), ("tail_3", "tail_2", t2, V(tip))]
    k = HORSE_LENGTH / CAVALRY_LENGTH
    ch = {}
    for name, (leg, hoof_part) in LEGS.items():
        co = W(leg, hoof_part)
        hoof = co[co[:, 2] < co[:, 2].min() + 0.03].mean(0)
        levels = (0.22 * k, 0.56 * k, 0.85 * k) if name.startswith("fore") else (0.22 * k, 0.52 * k, 0.88 * k)
        ch[name] = leg_chain(co, hoof, levels)
    for n in "lr":
        c = ch["fore_" + n]
        top = V((c[3][0], c[3][1] - 0.04, 0.81 * withers))
        b += [("fore_upper_" + n, "horse_body", top, V(c[2])),
              ("fore_lower_" + n, "fore_upper_" + n, V(c[2]), V(c[1])),
              ("fore_hoof_" + n, "fore_lower_" + n, V(c[1]), V(c[0]))]
        c = ch["hind_" + n]
        top = V((c[3][0], c[3][1] - 0.10, 0.83 * croup))
        b += [("hind_upper_" + n, "horse_body", top, V(c[3])),
              ("hind_gaskin_" + n, "hind_upper_" + n, V(c[3]), V(c[2])),
              ("hind_lower_" + n, "hind_gaskin_" + n, V(c[2]), V(c[1])),
              ("hind_hoof_" + n, "hind_lower_" + n, V(c[1]), V(c[0]))]
    return b


# the rider's parts by joint: (side r = +X, the lance hand; l = -X, the reins)
THIGH = {"r": 18, "l": 25}
KNEE = {"r": 24, "l": 36}
SABATON = {"r": 29, "l": 28}
PAULDRON = {"r": 17, "l": 16}
UPPERARM = {"r": 21, "l": 20}
FOREARM = {"r": 45, "l": 52}
FIST = {"r": 39, "l": 49}
TORSO, HELM = 4, 2
LANCE = (14, 51, 35)


def rider_spec():
    V = Vector
    torso, helm = W(TORSO), W(HELM)
    def col(z):
        s = torso[np.abs(torso[:, 2] - z) < 0.03]
        return np.array((0.0, float(s[:, 1].mean()), z))
    ends = {}
    for n in "rl":
        a, c = pca_ends(W(THIGH[n]))
        knee = W(KNEE[n]).mean(0)
        hip = a if np.linalg.norm(a - knee) > np.linalg.norm(c - knee) else c
        ends[n] = (hip, knee)
    hips_c = (ends["r"][0] + ends["l"][0]) / 2
    hips_c[0] = 0.0
    collar = helm[:, 2].min() + 0.03
    crown = helm[:, 2].max()
    z0 = hips_c[2] + 0.10
    spine_top = col(z0 + (collar - z0) * 0.45)
    chest_top = col(collar - 0.04)
    neck_top = np.array((0.0, float(helm[:, 1].mean()), collar + 0.06))
    b = [("hips", "horse_body", V(hips_c), V(col(z0))),
         ("spine", "hips", V(col(z0)), V(spine_top)),
         ("chest", "spine", V(spine_top), V(chest_top)),
         ("neck", "chest", V(chest_top), V(neck_top)),
         ("head", "neck", V(neck_top), V((0.0, neck_top[1], crown - 0.03)))]
    for n, s in (("r", 1.0), ("l", -1.0)):
        pa = W(PAULDRON[n])
        sh = np.array((s * (np.abs(pa[:, 0]).max() - 0.09), pa[:, 1].mean(), pa[:, 2].mean() - 0.05))
        up = W(UPPERARM[n])
        a, c = pca_ends(up)
        el = a if np.linalg.norm(a - sh) > np.linalg.norm(c - sh) else c
        fore = W(FOREARM[n])
        a, c = pca_ends(fore)
        wr = a if np.linalg.norm(a - el) > np.linalg.norm(c - el) else c
        fist = W(FIST[n]).mean(0)
        if np.linalg.norm(fist - wr) < 0.05:
            fist = wr + (wr - el) / np.linalg.norm(wr - el) * 0.08
        hip, knee = ends[n]
        sab = W(SABATON[n])
        ank = sab[sab[:, 2] > sab[:, 2].max() - 0.06].mean(0)
        toe = sab[sab[:, 2] < sab[:, 2].min() + 0.05]
        toe = toe[np.argmax(toe[:, 1])]
        b += [("clavicle_" + n, "chest", V((s * 0.03, chest_top[1], sh[2])), V(sh)),
              ("upperarm_" + n, "clavicle_" + n, V(sh), V(el)),
              ("forearm_" + n, "upperarm_" + n, V(el), V(wr)),
              ("hand_" + n, "forearm_" + n, V(wr), V(fist)),
              ("thigh_" + n, "hips", V(hip), V(knee)),
              ("shin_" + n, "thigh_" + n, V(knee), V(ank)),
              ("foot_" + n, "shin_" + n, V(ank), V(toe))]
    # the lance on the off fist, along its own shaft (lance() built it); the shield on the
    # back, along the shield's own long axis (shield() built it), both parented to what holds them
    ln = bpy.data.objects["cav_lance"]
    g, d = Vector(ln["grip"]), Vector(ln["dir"])
    b += [("lance", "hand_r", g, g + d * 0.30)]
    down = Vector((0, -math.sin(math.radians(SHIELD_BACK_DEG)), -math.cos(math.radians(SHIELD_BACK_DEG))))
    sc_ = SHIELD_TOP + down * (SHIELD_H * 0.45)
    b += [("shield", "chest", sc_ + down * 0.12, sc_ - down * 0.12)]
    return b


def skeleton():
    """The armature `cavalry_rig`, placed on this horse and rider."""
    import model_cavalry as mc
    old = bpy.data.objects.get("cavalry_rig")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    spec = horse_spec() + rider_spec()
    arm = mc.make_units.build_armature("cavalry", spec)
    for c in list(arm.users_collection):
        c.objects.unlink(arm)
    coll("Cavalry_Rig").objects.link(arm)
    arm.show_in_front = True
    arm.data.display_type = "STICK"
    return {n: (tuple(round(x, 3) for x in h), tuple(round(x, 3) for x in t)) for n, _, h, t in spec}


# ------------------------------------------------------ cull, lance, reduce ----

HIDDEN_M = 0.04            # a part's face this far from every point of the fused mesh is hidden


def cull():
    """Drop the faces the fused (textured) mesh does not have: where one part runs on inside
    another (a thigh inside the saddle, the belly under the girth). Nothing shows there at
    rest, and in motion those faces came out as untextured flaps (the courier's lesson)."""
    high = bpy.data.objects["tripo_high"]
    bm = bmesh.new(); bm.from_mesh(high.data)
    tree = BVHTree.FromBMesh(bm)
    report, gone_parts = {}, []
    for o in parts():
        pb = bmesh.new(); pb.from_mesh(o.data)
        far = {v: tree.find_nearest(v.co)[3] > HIDDEN_M for v in pb.verts}
        gone = [f for f in pb.faces if all(far[v] for v in f.verts)]
        if gone:
            bmesh.ops.delete(pb, geom=gone, context="FACES")
            bmesh.ops.delete(pb, geom=[v for v in pb.verts if not v.link_faces], context="VERTS")
            pb.to_mesh(o.data)
            o.data.update()
            report[o.name] = len(gone)
        pb.free()
        if not o.data.polygons:
            gone_parts.append(o.name)
            bpy.data.objects.remove(o, do_unlink=True)
    bm.free()
    return {"faces_dropped": sum(report.values()), "by_part": report, "parts_removed": gone_parts}


LANCE_TIP_M = 3.319        # the scanned cavalry's height_m: the runtime sizes a piece by its whole box
LANCE_BUTT_M = 0.80        # the butt rests by the off stirrup (Tripo ran it down past the belly)
LANCE_R = (0.021, 0.016)   # the shaft's radius at the butt and under the head
LANCE_HEAD_M = 0.30        # the steel head, a leaf blade
VAMPLATE = (0.065, 0.10)   # the round steel guard over the fist: radius, its cone's length
WOOD = (0.36, 0.24, 0.14)


def lance():
    """`cav_lance`, built by hand in place of Tripo's three lance parts (14, 51, 35): they
    were never coaxial (the lower shaft ran behind the fist) and their seams hid behind the
    fist and the knee, so no slide or stretch keeps them whole. A straight 8-sided shaft
    through the off fist on the line of the upper parts, a leaf head, and the round vamplate
    the design has and Tripo dropped; colours on `paint` / `pbr` corners like the shield.
    The Tripo parts are removed."""
    old = bpy.data.objects.get("cav_lance")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    up = W(14, 51)
    a, c = pca_ends(up)
    d = (c - a) / np.linalg.norm(c - a)
    if d[2] < 0:
        d = -d
    fist = W(FIST["r"]).mean(0)
    # the axis through the fist's centre, along the upper parts' line
    t_tip = (LANCE_TIP_M - fist[2]) / d[2]
    t_butt = (LANCE_BUTT_M - fist[2]) / d[2]
    tip, butt = fist + d * t_tip, fist + d * t_butt
    D = Vector(d)
    side = D.cross(Vector((0, 0, 1))).normalized()
    other = D.cross(side).normalized()
    bm = bmesh.new()
    paint = bm.loops.layers.float_color.new("paint")
    pbr = bm.loops.layers.float_color.new("pbr")
    SEG = 8

    def ring(centre, r, n=SEG, flat=1.0):
        return [bm.verts.new(Vector(centre) + side * (r * math.cos(2 * math.pi * k / n))
                             + other * (r * flat * math.sin(2 * math.pi * k / n))) for k in range(n)]

    def band(r0, r1, col, rough, metal):
        for k in range(len(r0)):
            f = bm.faces.new((r0[k], r0[(k + 1) % len(r0)], r1[(k + 1) % len(r1)], r1[k]))
            for lp in f.loops:
                lp[paint] = (*lin(col), 1.0)
                lp[pbr] = (1.0, rough, metal, 1.0)

    def cap(rg, apex, col, rough, metal):
        v = bm.verts.new(Vector(apex))
        for k in range(len(rg)):
            f = bm.faces.new((rg[k], rg[(k + 1) % len(rg)], v))
            for lp in f.loops:
                lp[paint] = (*lin(col), 1.0)
                lp[pbr] = (1.0, rough, metal, 1.0)

    head_base = tip - d * LANCE_HEAD_M
    grip_top = fist + d * 0.06
    rows = [(butt, LANCE_R[0]), (fist - d * 0.25, LANCE_R[0] * 0.97), (grip_top, LANCE_R[0] * 0.95),
            (grip_top + d * 0.8, (LANCE_R[0] + LANCE_R[1]) / 2), (head_base, LANCE_R[1])]
    rings = [ring(p, r) for p, r in rows]
    cap(list(reversed(rings[0])), butt - d * 0.012, (0.30, 0.29, 0.27), 0.55, 0.25)   # a steel butt cap
    for r0, r1 in zip(rings, rings[1:]):
        band(r0, r1, WOOD, 0.75, 0.0)
    # the head: a socket, then a flat leaf blade (4 around, wider across than through)
    sock = ring(head_base + d * 0.06, LANCE_R[1] * 1.1)
    band(rings[-1], sock, STEEL, 0.55, 0.25)
    widest = ring(head_base + d * 0.14, 0.035, 4, flat=0.28)
    sock4 = [sock[0], sock[2], sock[4], sock[6]]
    band(sock4, widest, STEEL, 0.55, 0.25)
    cap(widest, tip, STEEL, 0.55, 0.25)
    # the vamplate: a shallow steel cone over the fist, open toward the hand
    vc = fist + d * 0.11
    lip = ring(vc - d * VAMPLATE[1] * 0.35, VAMPLATE[0])
    neck = ring(vc + d * VAMPLATE[1] * 0.65, LANCE_R[0] * 1.25)
    band(lip, neck, STEEL, 0.55, 0.25)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("cav_lance")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cav_lance", me)
    coll("Cavalry_Lance").objects.link(ob)
    ob["grip"] = [float(x) for x in fist]
    ob["dir"] = [float(x) for x in d]
    for i in LANCE:
        o = bpy.data.objects.get("tripo_part_%d" % i)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    return {"tris": tris(ob), "tip": tuple(round(float(x), 3) for x in tip),
            "butt": tuple(round(float(x), 3) for x in butt), "lean_deg": round(math.degrees(math.acos(d[2])), 1)}


BUDGET = 18400             # tris for the Tripo parts; the hand-built shield takes the rest of 20,000
MIN_PART_TRIS = 60


def reduce():
    """Each part collapsed by one ratio to BUDGET (a part never below MIN_PART_TRIS)."""
    ps = parts()
    total = sum(tris(o) for o in ps)
    ratio = min(1.0, BUDGET / total)
    for o in ps:
        cur = tris(o)
        want = max(MIN_PART_TRIS, int(cur * ratio))
        if cur > want:
            m = o.modifiers.new("reduce", "DECIMATE")
            m.ratio = want / cur
            activate(o)
            bpy.ops.object.modifier_apply(modifier=m.name)
    return {"before": total, "after": sum(tris(o) for o in ps), "ratio": round(ratio, 3)}


# ------------------------------------------------------------- shield ----
# Built by hand (owner 2026-09-30: 盾牌单独做 -- the knight was generated without it; 盾牌不要
# 那根带子 -- no strap): a heater of the in-game design, green with a white pale, a steel rim
# and boss, LARGER than the old one on the arm (0.47 x 0.65) and slung on the rider's back,
# its point leaning back over the cantle. Its colours ride corner attributes (`paint`,
# `pbr`) that texture() bakes into the one atlas, so it needs no image of its own.

SHIELD_W, SHIELD_H = 0.50, 0.66
SHIELD_TOP = Vector((0.0, -0.30, 2.18))      # the top edge's middle, just behind the pauldrons (y -0.241)
SHIELD_BACK_DEG = 14.0                        # the point leans back over the cantle (its top at y -0.30 is 1.62 m)
SHIELD_BULGE = 0.10                           # the face's outward curve: depth = BULGE x w^2 (w half-widths, m)
SHIELD_THICK = 0.016
PALE = 0.060                                  # the white pale's half-width, m
GREEN = (34 / 255, 112 / 255, 58 / 255)       # model_cavalry's shield field, the in-game design
WHITE = (0.86, 0.85, 0.80)
STEEL = (0.42, 0.41, 0.39)
# the outline's right half, (half-width, height from the top), top corner to the point
OUTLINE = [(0.250, 0.000), (0.252, 0.160), (0.240, 0.300), (0.205, 0.420), (0.150, 0.525),
           (0.085, 0.605), (0.000, 0.660)]


def lin(c):
    """sRGB -> linear: `paint` is a float colour attribute, read linear by the bake."""
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def _half_width(h):
    for (w0, h0), (w1, h1) in zip(OUTLINE, OUTLINE[1:]):
        if h <= h1:
            t = (h - h0) / (h1 - h0)
            return w0 + (w1 - w0) * t
    return 0.0


def shield():
    """`cav_shield`: the heater on the rider's back, with `paint` and `pbr` corner colours."""
    old = bpy.data.objects.get("cav_shield")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    down = Vector((0, -math.sin(math.radians(SHIELD_BACK_DEG)), -math.cos(math.radians(SHIELD_BACK_DEG))))
    across = Vector((1, 0, 0))
    out = across.cross(down).normalized()      # away from the rider's back
    if out.y > 0:
        out = -out

    def at(w, h, d=0.0):
        return SHIELD_TOP + across * w + down * h + out * (d + SHIELD_BULGE * (0.25 ** 2 - w * w))

    # a quad grid: columns at the pale's edges so the white is crisp, rows down to the point
    us = [-1.0, -0.72, -0.45, -PALE / 0.25, 0.0, PALE / 0.25, 0.45, 0.72, 1.0]
    hs = [0.0, 0.06, 0.14, 0.23, 0.32, 0.40, 0.47, 0.53, 0.58, 0.62, SHIELD_H]
    bm = bmesh.new()
    paint = bm.loops.layers.float_color.new("paint")
    pbr = bm.loops.layers.float_color.new("pbr")
    grid = []
    for h in hs:
        hw = max(_half_width(h), 0.0)
        grid.append([bm.verts.new(at(u * hw, h)) for u in us])
    faces = []
    for r in range(len(hs) - 1):
        for c in range(len(us) - 1):
            a, b_, c_, d = grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]
            f = bm.faces.new((a, d, c_, b_)) if r < len(hs) - 2 else None
            if f is None:           # the last row closes on the point: triangles at the tip only
                if (a.co - b_.co).length > 1e-6:
                    f = bm.faces.new((a, d, b_))
            if f is not None:
                white = abs((us[c] + us[c + 1]) / 2) < PALE / 0.25
                faces.append((f, WHITE if white else GREEN))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    for f, col in faces:
        if f.is_valid:
            for lp in f.loops:
                lp[paint] = (*lin(col), 1.0)
                lp[pbr] = (1.0, 0.72, 0.0, 1.0)            # painted wood: rough, not metal
    # thickness toward the rider, then the rim: the boundary edges bevelled into a steel band
    face_set = [f for f in bm.faces]
    ext = bmesh.ops.extrude_face_region(bm, geom=face_set)
    back_verts = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    for v in back_verts:
        v.co -= out * SHIELD_THICK
    bmesh.ops.reverse_faces(bm, faces=face_set)
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f not in face_set])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        if f not in face_set:           # the back and the edge band: steel at the edge, wood behind
            n = f.normal
            edge = abs(n.dot(out)) < 0.6
            for lp in f.loops:
                lp[paint] = (*lin(STEEL if edge else (0.30, 0.22, 0.14)), 1.0)
                lp[pbr] = (1.0, 0.55, 0.25, 1.0) if edge else (1.0, 0.8, 0.0, 1.0)
    me = bpy.data.meshes.new("cav_shield")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cav_shield", me)
    coll("Cavalry_Shield").objects.link(ob)
    _rim_and_boss(ob, at, out)
    return {"tris": tris(ob), "top": tuple(round(x, 3) for x in at(0, 0)),
            "point": tuple(round(x, 3) for x in at(0, SHIELD_H))}


def _rim_and_boss(ob, at, out):
    """A steel rim tube round the outline and a low boss, joined into the shield."""
    ring = [(w, h) for w, h in OUTLINE] + [(-w, h) for w, h in reversed(OUTLINE[:-1])]
    ring += [(-0.25 + 0.5 * k / 6, 0.0) for k in range(1, 6)]
    bm = bmesh.new()
    paint = bm.loops.layers.float_color.new("paint")
    pbr = bm.loops.layers.float_color.new("pbr")
    R, SEG = 0.011, 4
    rings = []
    for i, (w, h) in enumerate(ring):
        p = at(w, h, -SHIELD_THICK / 2)
        q = at(*ring[(i + 1) % len(ring)], -SHIELD_THICK / 2)
        o = at(*ring[i - 1], -SHIELD_THICK / 2)
        t = (q - o).normalized()
        side = t.cross(out).normalized()
        rings.append([bm.verts.new(p + (side * math.cos(a) + out * math.sin(a)) * R)
                      for a in (2 * math.pi * k / SEG for k in range(SEG))])
    for i in range(len(rings)):
        a_, b_ = rings[i], rings[(i + 1) % len(rings)]
        for k in range(SEG):
            bm.faces.new((a_[k], a_[(k + 1) % SEG], b_[(k + 1) % SEG], b_[k]))
    # the boss: a low dome of 8 x 3 on the face's centre
    c = at(0.0, 0.26, 0.0)
    rows = [bm.verts.new(c + out * 0.028)]
    prev = None
    for ri, (rr, dz) in enumerate(((0.030, 0.024), (0.052, 0.013), (0.064, 0.0))):
        cur = []
        for k in range(8):
            a = 2 * math.pi * k / 8
            cur.append(bm.verts.new(c + across_dir() * (rr * math.cos(a)) + updir(out) * (rr * math.sin(a)) + out * dz))
        if prev is None:
            for k in range(8):
                bm.faces.new((rows[0], cur[k], cur[(k + 1) % 8]))
        else:
            for k in range(8):
                bm.faces.new((prev[k], cur[k], cur[(k + 1) % 8], prev[(k + 1) % 8]))
        prev = cur
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        for lp in f.loops:
            lp[paint] = (*lin(STEEL), 1.0)
            lp[pbr] = (1.0, 0.55, 0.25, 1.0)
    extra = bpy.data.meshes.new("cav_shield_rim")
    bm.to_mesh(extra)
    bm.free()
    tmp = bpy.data.objects.new("cav_shield_rim", extra)
    coll("Cavalry_Shield").objects.link(tmp)
    activate(ob)
    tmp.select_set(True)
    bpy.ops.object.join()


def across_dir():
    return Vector((1, 0, 0))


def updir(out):
    return across_dir().cross(out).normalized() * -1


# ------------------------------------------------------------ texture ----
# ONE 2048 atlas (colour, tangent normal, metal-roughness G/B), the courier's bake: every
# game part unwrapped into one tile and baked selected-to-active from `tripo_high` -- a FAR
# pass first (a long cage: faces inside other parts find the nearest skin), then the NEAR
# pass over it; the hand-built shield and lance bake their own `paint` / `pbr` corners.
# The steel is then toned like the infantry's, but ONLY inside the rider's islands: the
# dappled grey coat is as grey and as bright as the plate.

COURIER = UNITS + "courier/"
ATLAS = 2048
FAR_CAGE, FAR_RAY = 0.12, 0.40
NEAR_CAGE, NEAR_RAY = 0.03, 0.08
UV_ANGLE = 80.0
TEXEL = {"horse": 1.0, "tack": 1.1, "rider": 1.5, "shield": 1.6, "lance": 1.0}
STEEL_METAL = 0.25               # the infantry's lesson (2026-09-29): fully metallic plate reads BLACK at 30 px
STEEL_TARGET = 0.32              # the infantry's: the steel's median value after toning
STEEL_ROUGH_MIN = 0.55
STEEL_TINT = (1.0, 0.95, 0.88)
STEEL_SAT_MAX = 0.16
STEEL_VAL_MIN = 0.30


def table():
    import csv
    with open(os.path.join(HERE, "tripo_parts.csv")) as f:
        return {int(r["part"]): r for r in csv.DictReader(f)}


def game_objects():
    """(object, group) for every piece of the game mesh: the Tripo parts, shield, lance."""
    tab = table()
    out = [(o, tab[int(o.name.split("_")[-1])]["group"]) for o in parts()]
    out += [(bpy.data.objects["cav_shield"], "shield"), (bpy.data.objects["cav_lance"], "lance")]
    return out


def _tx():
    if COURIER not in sys.path:
        sys.path.insert(0, COURIER)
    import importlib, texture as tx
    importlib.reload(tx)
    return tx


def _emit(name, colour=None, image=None, attribute=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    e = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs["Emission"], out.inputs["Surface"])
    if image is not None:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = image
        nt.links.new(t.outputs["Color"], e.inputs["Color"])
    elif attribute is not None:
        a = nt.nodes.new("ShaderNodeAttribute"); a.attribute_name = attribute
        nt.links.new(a.outputs["Color"], e.inputs["Color"])
    else:
        e.inputs["Color"].default_value = (*colour, 1.0)
    return m


def unwrap(objs):
    """Smart-project each piece, its islands scaled to metres x its texel weight, all
    packed into one tile (the courier's unwrap)."""
    for ob, grp in objs:
        activate(ob)
        if not ob.data.uv_layers:
            ob.data.uv_layers.new(name="UVMap")
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(UV_ANGLE), island_margin=0.001, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        me = ob.data
        uv = np.zeros(len(me.loops) * 2)
        me.uv_layers.active.data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        area3 = sum(p.area for p in me.polygons)
        a2 = 0.0
        for p in me.polygons:
            q = uv[list(p.loop_indices)]
            a2 += 0.5 * abs(np.dot(q[:, 0], np.roll(q[:, 1], 1)) - np.dot(q[:, 1], np.roll(q[:, 0], 1)))
        k = math.sqrt(area3 / max(a2, 1e-9)) * TEXEL[grp]
        me.uv_layers.active.data.foreach_set("uv", (uv * k).ravel())
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for ob, _ in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0][0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    try:
        bpy.ops.uv.pack_islands(udim_source="ACTIVE_UDIM", rotate=True, margin=0.002, shape_method="CONCAVE")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")


def _bake(tx, low, image, kind, high=None, cage=None, ray=None, clear=False):
    sc = bpy.context.scene
    for m in low.data.materials:
        tx.target_node(m, image)
    tx.activate(low)
    b = sc.render.bake
    b.use_selected_to_active = high is not None
    if high is not None:
        high.select_set(True)
        bpy.context.view_layer.objects.active = low
        b.cage_extrusion = cage
        b.max_ray_distance = ray
    b.margin = tx.MARGIN
    b.use_clear = clear
    b.target = "IMAGE_TEXTURES"
    if kind == "NORMAL":
        b.normal_space = "TANGENT"
    bpy.ops.object.bake(type=kind)


def texture():
    tx = _tx()
    sc = scene()
    high = bpy.data.objects["tripo_high"]
    high.hide_set(False); high.hide_render = False
    objs = game_objects()
    unwrap(objs)
    src = high.data.materials[0]
    imgs = {}
    for n in src.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            to = [l.to_node.type for l in n.outputs["Color"].links]
            key = "col" if "BSDF_PRINCIPLED" in to else "mr" if ("SEPARATE_COLOR" in to or "SEPRGB" in to) else "nor"
            imgs[key] = n.image
    col = tx.new_image("cavalry_atlas", True, (0.5, 0.5, 0.5, 1))
    nor = tx.new_image("cavalry_atlas_n", False, (0.5, 0.5, 1.0, 1))
    mr = tx.new_image("cavalry_atlas_mr", False, (1.0, 0.8, 0.0, 1))
    rider = tx.new_image("cavalry_rider_mask", False, (0, 0, 0, 1))
    tmp = bpy.data.materials.get("cav_bake_target") or bpy.data.materials.new("cav_bake_target")
    tmp.use_nodes = True
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = True
        sc.cycles.device = "GPU"
    except Exception as ex:
        print("GPU not set:", ex)
    tripo = [(o, g) for o, g in objs if g not in ("shield", "lance")]
    own = [(o, g) for o, g in objs if g in ("shield", "lance")]
    for o, _ in tripo:
        o.data.materials.clear(); o.data.materials.append(tmp)
    # colour: far pass, then near pass over it
    high.data.materials[0] = _emit("cav_src_col", image=imgs["col"])
    for o, _ in tripo:
        _bake(tx, o, col, "EMIT", high, FAR_CAGE, FAR_RAY)
    for o, _ in tripo:
        _bake(tx, o, col, "EMIT", high, NEAR_CAGE, NEAR_RAY)
    if "mr" in imgs:
        high.data.materials[0] = _emit("cav_src_mr", image=imgs["mr"])
        for o, _ in tripo:
            _bake(tx, o, mr, "EMIT", high, FAR_CAGE, FAR_RAY)
        for o, _ in tripo:
            _bake(tx, o, mr, "EMIT", high, NEAR_CAGE, NEAR_RAY)
    hold_metal(mr)
    high.data.materials[0] = src
    for o, _ in tripo:
        _bake(tx, o, nor, "NORMAL", high, NEAR_CAGE, NEAR_RAY)
    # the rider's islands, for the steel toning
    white, black = _emit("cav_white", colour=(1, 1, 1)), _emit("cav_black", colour=(0, 0, 0))
    for o, g in tripo:
        o.data.materials[0] = white if g == "rider" else black
        _bake(tx, o, rider, "EMIT")
        o.data.materials[0] = tmp
    # the shield and the lance from their own corners
    for o, _ in own:
        o.data.materials.clear(); o.data.materials.append(_emit("cav_paint", attribute="paint"))
        _bake(tx, o, col, "EMIT")
        o.data.materials[0] = _emit("cav_pbr", attribute="pbr")
        _bake(tx, o, mr, "EMIT")
    mat = tx.atlas_material(col, nor, mr)
    mat.name = "cavalry_atlas"
    for o, _ in objs:
        o.data.materials.clear(); o.data.materials.append(mat)
    tone = tone_steel(col, mr, rider)
    for img in (col, nor, mr):
        img.pack()
    high.hide_set(True); high.hide_render = True
    return {"maps": sorted(imgs), "steel": tone}


def hold_metal(mr):
    """Tripo's metallic x STEEL_METAL (before the shield and lance bake their own)."""
    m = np.array(mr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    m[..., 2] *= STEEL_METAL
    mr.pixels.foreach_set(m.ravel())


def tone_steel(col, mr, rider):
    """The rider's steel toned toward STEEL_TARGET, warm, no glossier than STEEL_ROUGH_MIN
    (the infantry's tone_steel, masked to the rider's islands)."""
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    m = np.array(mr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    mask = np.array(rider.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., 0] > 0.5
    rgb = c[..., :3]
    mx_, mn_ = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx_ > 1e-4, (mx_ - mn_) / np.maximum(mx_, 1e-4), 0)
    steel = mask & (sat < STEEL_SAT_MAX) & (mx_ > STEEL_VAL_MIN)
    if not steel.any():
        return "no steel found"
    med = float(np.median(mx_[steel]))
    k = min(1.0, STEEL_TARGET / med)
    rgb[steel] = rgb[steel] * k * np.array(STEEL_TINT, np.float32)
    c[..., :3] = np.clip(rgb, 0, 1)
    col.pixels.foreach_set(c.ravel())
    m[..., 1][steel] = np.maximum(m[..., 1][steel], STEEL_ROUGH_MIN)
    mr.pixels.foreach_set(m.ravel())
    return "%.1f%% of the rider's pixels, median %.2f -> x%.2f" % (steel.sum() / max(1, mask.sum()) * 100, med, k)


# ------------------------------------------------------------ weights ----
# The horse's parts copy one bone-heat solve on a welded copy of the fused mesh (one surface
# across the parts' joins, so a knee split between two parts bends as one) and keep only the
# bones their kind may follow, an upper leg's top handed to the body (the courier's weigh /
# keep_only); a rider's plate rides ONE bone whole, the nearest of those its row names (the
# infantry's rule: plates shared by distance tore when a joint bent far); the reins run from
# the bit to the near fist; the tack, the shield and the lance are rigid.


def _courier_tripo():
    import importlib.util
    if COURIER not in sys.path:
        sys.path.insert(0, COURIER)
    spec = importlib.util.spec_from_file_location("courier_tripo", COURIER + "tripo.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _nearest_bone(o, arm, bones):
    c = world_co(o).mean(0)
    best = None
    for b in arm.data.bones:
        if b.name not in bones:
            continue
        a_, b_ = np.array(b.head_local), np.array(b.tail_local)
        ab = b_ - a_
        t = np.clip((c - a_) @ ab / max(ab @ ab, 1e-9), 0, 1)
        d = float(np.linalg.norm(c - (a_ + t * ab)))
        if best is None or d < best[0]:
            best = (d, b.name)
    return best[1]


def horse_proxy():
    """The horse's own (reduced) parts welded into one surface. Bone heat on the fused
    textured mesh FAILED here (100% bare: the rider, the old lance and the horse run through
    each other in it), so unlike the courier the solve runs on the horse alone."""
    tab = table()
    bm = bmesh.new()
    for o in parts():
        if tab[int(o.name.split("_")[-1])]["group"] == "horse":
            bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.006)
    me = bpy.data.meshes.new("proxy_horse")
    bm.to_mesh(me); bm.free()
    ph = bpy.data.objects.new("proxy_horse", me)
    scene().collection.objects.link(ph)
    return ph


def weigh():
    ct = _courier_tripo()
    rig, mc = ct.rig, ct.rig.mc
    arm = bpy.data.objects["cavalry_rig"]
    tab = table()
    for o in [o for o in bpy.data.objects if o.name.startswith("proxy_horse")]:
        bpy.data.objects.remove(o, do_unlink=True)
    ph = horse_proxy()
    how = mc.heat(ph, arm, rig.HORSE)
    if how != "heat":
        raise SystemExit("bone heat failed on the horse proxy")
    hand_l = arm.data.bones["hand_l"].head_local
    chosen = {}
    for o in parts():
        w = tab[int(o.name.split("_")[-1])]["weights"]
        if w in ct.ALLOWED:
            mc.copy_weights(o, ph)
            ct.keep_only(o, ct.ALLOWED[w], arm)
        elif w.startswith("rigid:"):
            rig.rigid(o, w.split(":", 1)[1])
        elif w.startswith("near:"):
            b = _nearest_bone(o, arm, set(w.split(":", 1)[1].split("|")))
            rig.rigid(o, b)
            chosen[o.name] = b
        elif w == "reins":        # the bit end with the head, the hand end with the near fist
            mc.copy_weights(o, ph)
            idx = {g.index: g.name for g in o.vertex_groups}
            t = {}
            for v in o.data.vertices:
                ws = {idx[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
                f = max(0.0, min(1.0, (0.45 - (v.co - hand_l).length) / 0.35))
                ws = {b: x * (1 - f) for b, x in ws.items()}
                ws["hand_l"] = ws.get("hand_l", 0.0) + f
                t[v.index] = ws or {"head_h": 1.0}
            rig.set_weights(o, t)
        else:
            raise SystemExit("tripo_parts.csv: unknown weighting %r" % w)
    rig.rigid(bpy.data.objects["cav_shield"], "shield")
    rig.rigid(bpy.data.objects["cav_lance"], "lance")
    bpy.data.objects.remove(ph, do_unlink=True)
    return {"horse_heat": how, "near": chosen}


def join():
    """Every piece into ONE mesh `cavalry` on the rig (4 weights a vertex, normalised); the
    Tripo part each vertex came from is kept as `tripo_part` (not exported)."""
    import model_cavalry as mc
    arm = bpy.data.objects["cavalry_rig"]
    objs = [o for o, _ in game_objects()]
    for o in objs:
        n = int(o.name.split("_")[-1]) if o.name.startswith("tripo_part_") else (-1 if o.name == "cav_shield" else -2)
        at = o.data.attributes.get("tripo_part") or o.data.attributes.new("tripo_part", "INT", "POINT")
        at.data.foreach_set("value", [n] * len(o.data.vertices))
    for a in ("paint", "pbr"):
        for o in objs:
            if o.data.attributes.get(a):
                o.data.attributes.remove(o.data.attributes[a])
    activate(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = "cavalry"
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll("Cavalry_Game").objects.link(ob)
    for poly in ob.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    ob.parent = arm
    bare = mc.make_units.unweighted_share(ob, arm)
    return {"tris": tris(ob), "verts": len(ob.data.vertices), "unweighted_pct": round(bare * 100, 3),
            "materials": len(ob.data.materials)}
