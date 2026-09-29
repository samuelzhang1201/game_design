"""The courier from the owner's Tripo 3D models (owner 2026-09-29): courier_build.py's
default source.

The owner generated the piece in Tripo 3D from our pick (zimage_C4_s2) and supplied two
models of the same rider, git-ignored in assets/units3d/ai_src/courier/tripo/courier/:
  * textured.glb - one fused mesh (93k tris) with the colour, a normal map and a
    metal-roughness map, 4096 px each;
  * parts.glb    - the same shape as 43 untextured parts (tripo_part_0..42).
The PARTS are what ships: tripo_parts.csv names each one (role, weighting, tri budget,
texel weight). This module
  1. imports both, fits the parts onto the textured mesh (ICP: they are two generations of
     one shape, a few mm apart), turns the piece to face +Y, scales the horse to 2.45 m
     nose to tail and stands the planted hooves on z = 0;
  2. reduces every part to its budget (<= 20,000 tris together), unwraps them into one
     2048 atlas and bakes the textured mesh's colour, normal and metal-roughness onto
     them (selected-to-active), checking every part for missed texels;
  3. lays a skeleton with the cavalry's horse bone NAMES (cavalry_scan.rig_spec's layout
     cannot be used as is: this horse walks, one foreleg raised and one hind hoof lifted,
     so its legs are found part by part) and make_units' mounted rider names, placed on
     this rider's own parts; the staff rides the rider's off hand, the case the saddle;
  4. weights: bone heat on a welded copy of the fused textured mesh (horse bones, then
     rider bones) transferred to each part by nearest surface, or rigid / graded per
     tripo_parts.csv; the raised foreleg is kept in the rest pose and straightened by
     rig.NEUTRAL in every key.
rig.py then keys GALLOP and IDLE; courier_build.py exports.
"""
import bpy, bmesh, csv, math, os, sys
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SRC = os.path.join(REPO, "assets", "units3d", "ai_src", "courier", "tripo", "courier")
TABLE = os.path.join(HERE, "tripo_parts.csv")
import rig
import texture as tx

HORSE_LENGTH = 2.45        # nose to tail, as the cavalry's horse
TRIS_MAX = 19400           # the parts' budgets are scaled down to this if they add up to more
ICP_ITERS = 20             # parts -> textured fit
PROXY_TRIS = 30000         # the welded textured copy bone heat is solved on
MISS = (1.0, 0.0, 1.0, 1.0)     # the colour bake's fill: a texel still this colour was missed


def rows():
    with open(TABLE) as f:
        return [r for r in csv.DictReader(f)]


def load():
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "textured.glb"))
    tex = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "parts.glb"))
    parts = {}
    for o in bpy.context.scene.objects:
        if o in before:
            continue
        if o.type == "MESH":
            parts[int(o.name.split("_")[-1])] = o
    bpy.context.view_layer.update()
    for o in [tex] + list(parts.values()):          # world transforms into the data, no parents
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in [o for o in bpy.context.scene.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o, do_unlink=True)
    tex.name = "tripo_textured"
    return tex, parts


def world_co(o):
    n = len(o.data.vertices)
    co = np.empty(n * 3)
    o.data.vertices.foreach_get("co", co)
    return co.reshape(n, 3)


def icp(tex, parts):
    """Similarity transform (rotation, scale, shift) that fits the parts onto the textured
    surface, trimmed at the 90th percentile each round."""
    bm = bmesh.new(); bm.from_mesh(tex.data)
    tree = BVHTree.FromBMesh(bm)
    P = np.vstack([world_co(o) for o in parts.values()])[::3]
    R, s, t = np.eye(3), 1.0, np.zeros(3)
    for _ in range(ICP_ITERS):
        Q = P @ (s * R).T + t
        near = np.array([tree.find_nearest(Vector(q))[0][:] for q in Q])
        d = np.linalg.norm(near - Q, axis=1)
        keep = d < np.percentile(d, 90)
        A, B = P[keep], near[keep]
        ma, mb = A.mean(0), B.mean(0)
        U, S, Vt = np.linalg.svd((B - mb).T @ (A - ma))
        Dm = np.diag([1, 1, np.sign(np.linalg.det(U @ Vt))])
        R = U @ Dm @ Vt
        s = (S * np.diag(Dm)).sum() / ((A - ma) ** 2).sum()
        t = mb - s * R @ ma
    Q = P @ (s * R).T + t
    d = np.array([tree.find_nearest(Vector(q))[3] for q in Q])
    bm.free()
    M = Matrix.Identity(4)
    for i in range(3):
        for j in range(3):
            M[i][j] = s * R[i][j]
        M[i][3] = t[i]
    print("TRIPO icp: scale %.4f shift %s  residual mean %.4f p95 %.4f (native units)"
          % (s, np.round(t, 4), d.mean(), np.percentile(d, 95)))
    return M


def frame(tex, parts, horse_ids):
    """Face +Y (the model's nose is at -X), scale the horse to HORSE_LENGTH nose to tail,
    centre it, planted hooves on z = 0."""
    H = np.vstack([world_co(parts[i]) for i in horse_ids])
    length = H[:, 0].max() - H[:, 0].min()
    s = HORSE_LENGTH / length
    rot = Matrix.Rotation(math.radians(-90), 4, "Z")
    cx = (H[:, 0].max() + H[:, 0].min()) / 2
    barrel = H[(H[:, 2] > 0.3) & (H[:, 2] < 0.45)]
    cy = (barrel[:, 1].max() + barrel[:, 1].min()) / 2
    M = Matrix.Scale(s, 4) @ rot @ Matrix.Translation((-cx, -cy, 0))
    for o in [tex] + list(parts.values()):
        o.data.transform(M)
    z0 = min(world_co(parts[i])[:, 2].min() for i in horse_ids)
    T = Matrix.Translation((0, 0, -z0))
    for o in [tex] + list(parts.values()):
        o.data.transform(T)
        o.data.update()
    print("TRIPO frame: x%.3f, horse %.3f m nose to tail" % (s, HORSE_LENGTH))
    return s


HIDDEN_M = 0.04           # a part's face this far from every point of the fused mesh is hidden


def cull_hidden(tex, parts):
    """Drop the faces the fused (textured) mesh does not have: where one part runs on inside
    another (the far hind leg's stub inside the rump, a thigh inside the saddle). Nothing
    shows there at rest, and in motion those faces came out as untextured flaps."""
    bm = bmesh.new(); bm.from_mesh(tex.data)
    tree = BVHTree.FromBMesh(bm)
    total = 0
    report = {}
    for pid, o in parts.items():
        pb = bmesh.new(); pb.from_mesh(o.data)
        far = {v: tree.find_nearest(v.co)[3] > HIDDEN_M for v in pb.verts}
        gone = [f for f in pb.faces if all(far[v] for v in f.verts)]
        if gone:
            bmesh.ops.delete(pb, geom=gone, context="FACES")
            bmesh.ops.delete(pb, geom=[v for v in pb.verts if not v.link_faces], context="VERTS")
            pb.to_mesh(o.data)
            o.data.update()
            report[pid] = len(gone)
            total += len(gone)
        pb.free()
    bm.free()
    print("TRIPO cull: %d hidden faces dropped %s" % (total, report))


# ----------------------------------------------------------------- geometry

def pca_ends(co):
    c = co.mean(0)
    u, s_, vt = np.linalg.svd(co - c, full_matrices=False)
    ax = vt[0]
    t = (co - c) @ ax
    lo, hi = co[t < np.percentile(t, 4)].mean(0), co[t > np.percentile(t, 96)].mean(0)
    return lo, hi


def slice_centroid(co, z, near_xy, r, dz=0.02):
    sl = co[(np.abs(co[:, 2] - z) < dz) & (np.linalg.norm(co[:, :2] - near_xy, axis=1) < r)]
    return sl.mean(0) if len(sl) else None


def leg_chain(co, hoof, levels, r=0.14):
    at = hoof[:2].copy()
    out = [np.array((hoof[0], hoof[1], hoof[2]))]
    for z in levels:
        c = slice_centroid(co, z, at, r)
        if c is not None:
            at = c[:2]
        out.append(np.array((at[0], at[1], z)))
    return out


def top_at(co, y, half=0.06):
    s = co[(np.abs(co[:, 0]) < half) & (np.abs(co[:, 1] - y) < 0.04)]
    return s[:, 2].max()


def ang_yz(v):
    return math.degrees(math.atan2(v[2], v[1]))


def horse_spec(P):
    """The cavalry's horse bone names on this horse. P: role -> vertex array."""
    H = np.vstack([P[k] for k in ("hind_l", "hind_r", "fore_l_up", "fore_l_low", "fore_r", "barrel",
                                  "rump", "neck", "head", "belly")])
    b = [("root", None, Vector((0, 0, 0)), Vector((0, 0.3, 0)))]
    rear_y, front_y = -0.55, 0.45
    back_rear, back_front = top_at(H, rear_y), top_at(H, front_y)
    b.append(("horse_body", "root", Vector((0, rear_y, back_rear - 0.30)), Vector((0, front_y, back_front - 0.30))))
    head = P["head"]
    nose = head[np.argmax(head[:, 1])]
    front = np.vstack([P["neck"], head])
    poll = front[front[:, 1] > nose[1] - 0.55]
    poll = poll[np.argmax(poll[:, 2])]
    wither = Vector((0, 0.50, top_at(H, 0.50) - 0.22))
    pollv = Vector((0, poll[1] - 0.08, poll[2] - 0.12))
    mid = (wither + pollv) / 2 + Vector((0, 0.03, 0.05))
    b += [("neck_1", "horse_body", wither, mid), ("neck_2", "neck_1", mid, pollv),
          ("head_h", "neck_2", pollv, Vector((0, nose[1] - 0.08, nose[2])))]
    tail = P["tail"]
    root = tail[tail[:, 1] > tail[:, 1].max() - 0.05].mean(0)
    tip = tail[np.argmin(tail[:, 2])]
    t1 = Vector(root).lerp(Vector(tip), 0.33)
    t2 = Vector(root).lerp(Vector(tip), 0.66)
    b += [("tail_1", "horse_body", Vector(root), t1), ("tail_2", "tail_1", t1, t2), ("tail_3", "tail_2", t2, Vector(tip))]
    k = HORSE_LENGTH / rig.CAVALRY_LENGTH
    withers, croup = top_at(H, 0.45), top_at(H, -0.55)
    ch = {}
    # the standing off foreleg and the two hind legs: slices up from the hoof, as cavalry_scan
    for name, key, levels in (("fore_r", "fore_r", (0.22 * k, 0.56 * k, 0.85 * k)),
                              ("hind_l", "hind_l", (0.22 * k, 0.52 * k, 0.88 * k)),
                              ("hind_r", "hind_r", (0.22 * k, 0.52 * k, 0.88 * k))):
        co = P[key]
        low = co[co[:, 2] < co[:, 2].min() + 0.03]
        hoof = low.mean(0)
        ch[name] = leg_chain(co, hoof, levels)
    # the raised near foreleg: its lower part hangs from the knee, folded back
    low = P["fore_l_low"]
    hoof = low[low[:, 2] < low[:, 2].min() + 0.03].mean(0)
    knee = low[low[:, 2] > low[:, 2].max() - 0.04].mean(0)
    axis = knee - hoof
    t = (low - hoof) @ axis / (axis @ axis)
    fet = low[np.abs(t - 0.35) < 0.08].mean(0)
    up = P["fore_l_up"]
    # its top is the standing leg's shoulder mirrored across (the raised forearm reaches forward)
    ch["fore_l"] = [hoof, fet, knee, np.array((up[:, 0].mean(), ch["fore_r"][3][1], 0.85 * k))]
    for n in ("l", "r"):
        c = ch["fore_" + n]
        top = Vector((c[3][0], c[3][1] - 0.04, 0.81 * withers))
        b += [("fore_upper_" + n, "horse_body", top, Vector(c[2])),
              ("fore_lower_" + n, "fore_upper_" + n, Vector(c[2]), Vector(c[1])),
              ("fore_hoof_" + n, "fore_lower_" + n, Vector(c[1]), Vector(c[0]))]
    for n in ("l", "r"):
        c = ch["hind_" + n]
        top = Vector((c[3][0], c[3][1] - 0.10, 0.83 * croup))
        b += [("hind_upper_" + n, "horse_body", top, Vector(c[3])),
              ("hind_gaskin_" + n, "hind_upper_" + n, Vector(c[3]), Vector(c[2])),
              ("hind_lower_" + n, "hind_gaskin_" + n, Vector(c[2]), Vector(c[1])),
              ("hind_hoof_" + n, "hind_lower_" + n, Vector(c[1]), Vector(c[0]))]
    return b


def neutral_pose(spec):
    """Rotations (about X, the swing plane) that bring the raised near foreleg's bones to
    the standing off foreleg's directions: the leg stands in every key."""
    d = {n: (t - h) for n, _, h, t in spec}
    out, prev = {}, 0.0
    for seg in ("fore_upper_", "fore_lower_", "fore_hoof_"):
        want = ang_yz(d[seg + "r"]) - ang_yz(d[seg + "l"])
        out[seg + "l"] = {"rot": [("x", want - prev)]}
        prev = want
    print("TRIPO neutral foreleg:", {k: round(v["rot"][0][1], 1) for k, v in out.items()})
    return out


def rider_spec(P):
    coat, th = P["coat"], {"r": P["thigh_r"], "l": P["thigh_l"]}
    boot = {"r": P["boot_r"], "l": P["boot_l"]}
    hand = {"r": P["hand_r"].mean(0), "l": P["hand_l"].mean(0)}
    ends = {}
    for n in "rl":
        a, b_ = pca_ends(th[n])
        hip, knee = (a, b_) if a[1] < b_[1] else (b_, a)          # the hip is the rear end
        ends[n] = (hip, knee)
    hips_c = (ends["r"][0] + ends["l"][0]) / 2
    hips_c[0] = 0.0
    neck = P["neck"].mean(0)
    head = np.vstack([P["head"], P["face"]])
    head_c = head.mean(0)
    crown = np.array((head_c[0], head_c[1], head[:, 2].max()))
    collar_z = P["collar"][:, 2].mean()
    torso = coat[np.abs(coat[:, 0]) < 0.10]
    def col(z):
        s = torso[np.abs(torso[:, 2] - z) < 0.04]
        return np.array((0.0, s[:, 1].mean(), z))
    z0 = hips_c[2] + 0.10
    spine_top = col(z0 + (collar_z - z0) * 0.45)
    chest_top = col(collar_z - 0.02)
    V = Vector
    b = [("hips", "horse_body", V(hips_c), V(col(z0))),
         ("spine", "hips", V(col(z0)), V(spine_top)),
         ("chest", "spine", V(spine_top), V(chest_top)),
         ("neck", "chest", V(chest_top), V((0.0, neck[1], neck[2] + 0.04))),
         ("head", "neck", V((0.0, neck[1], neck[2] + 0.04)), V(crown - np.array((0, 0, 0.03))))]
    shz = chest_top[2] - 0.06
    band = coat[np.abs(coat[:, 2] - shz) < 0.04]
    for n, s in (("r", 1.0), ("l", -1.0)):
        side = band[band[:, 0] * s > 0]
        sh = np.array((s * (np.abs(side[:, 0]).max() - 0.06), side[:, 1].mean(), shz))
        ha = hand[n]
        el = sh + (ha - sh) * 0.45 + np.array((s * 0.05, -0.06, -0.14))
        hip, knee = ends[n]
        bt = boot[n]
        ankle_z = bt[:, 2].min() + 0.13
        ank = bt[np.abs(bt[:, 2] - ankle_z) < 0.03].mean(0)
        toe = bt[bt[:, 2] < bt[:, 2].min() + 0.06]
        toe = toe[np.argmax(toe[:, 1])]
        b += [("clavicle_" + n, "chest", V((s * 0.03, chest_top[1], shz)), V(sh)),
              ("upperarm_" + n, "clavicle_" + n, V(sh), V(el)),
              ("forearm_" + n, "upperarm_" + n, V(el), V(ha)),
              ("hand_" + n, "forearm_" + n, V(ha), V(ha + (ha - el) / np.linalg.norm(ha - el) * 0.08)),
              ("thigh_" + n, "hips", V(hip), V(knee)),
              ("shin_" + n, "thigh_" + n, V(knee), V(ank)),
              ("foot_" + n, "shin_" + n, V(ank), V(toe))]
    return b


def prop_spec(P, flag_axis):
    pole = P["pole"]
    a, b_ = pca_ends(pole)
    bot, top = (a, b_) if a[2] < b_[2] else (b_, a)
    d = (top - bot) / np.linalg.norm(top - bot)
    flag = P["flag"]
    fc = flag.mean(0)
    r = fc - bot
    hoist = bot + d * (r @ d)
    out = fc - hoist
    out -= d * (out @ d)
    width = max(float(np.linalg.norm((flag - hoist) - np.outer((flag - hoist) @ d, d), axis=1).max()), 0.05)
    out /= max(np.linalg.norm(out), 1e-6)
    flag_axis.update({"bot": bot, "d": d, "hoist": hoist, "out": out, "width": width})
    case = P["case"]
    cc = case.mean(0)
    V = Vector
    return [("pole", "hand_r", V(bot), V(top)),
            ("pennon_1", "pole", V(hoist), V(hoist + out * width * 0.5)),
            ("pennon_2", "pennon_1", V(hoist + out * width * 0.5), V(hoist + out * width)),
            ("case", "horse_body", V(cc + (0, 0, 0.10)), V(cc - (0, 0, 0.06)))]


def ik_spec(spec):
    by = {n: (h, t) for n, _, h, t in spec}
    return [("ik_foot_" + n, "horse_body", by["shin_" + n][1], by["shin_" + n][1] + Vector((0, 0.08, 0)))
            for n in "rl"]


# ------------------------------------------------------------------ weights

def proxy(tex, name):
    """A welded, reduced copy of the fused textured mesh (UV seams split its vertices)."""
    o = tex.copy()
    o.data = tex.data.copy()
    o.name = o.data.name = name
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.clear()
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bm.to_mesh(o.data); bm.free()
    cur = len(o.data.polygons)
    m = o.modifiers.new("d", "DECIMATE")
    m.ratio = min(1.0, PROXY_TRIS / max(cur, 1))
    rig.activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


TAIL = {"tail_1", "tail_2", "tail_3"}
# the horse bones a part may follow once its weights are copied from the heat proxy: a
# part hidden under the tail's root (the rump's) must not stream out with the tail
ALLOWED = {"horse": rig.HORSE - TAIL,
           "horse_tail": TAIL | {"horse_body"},
           "horse_mane": {"horse_body", "neck_1", "neck_2", "head_h"}}


HIP_BLEND_M = 0.20      # an upper leg's weight hands over to the body over its top this far


def keep_only(o, bones, arm=None, fallback="horse_body"):
    """Only `bones`; and (with `arm`) the top of each upper leg handed to the body, so the
    parts of a leg hidden inside the rump or the shoulder stay in when the leg swings."""
    idx = {g.index: g.name for g in o.vertex_groups}
    tops = {}
    if arm is not None:
        tops = {b.name: b.head_local.z for b in arm.data.bones
                if b.name.startswith(("fore_upper_", "hind_upper_"))}
    tab = {}
    for v in o.data.vertices:
        ws = {idx[g.group]: g.weight for g in v.groups if g.weight > 1e-4 and idx[g.group] in bones}
        for b, top in tops.items():
            if b in ws:
                t = max(0.0, min(1.0, (v.co.z - (top - HIP_BLEND_M)) / HIP_BLEND_M))
                if t > 0:
                    ws["horse_body"] = ws.get("horse_body", 0.0) + ws[b] * t
                    ws[b] *= 1 - t
        tab[v.index] = ws
    # a vertex left with nothing (it followed only bones it may not, e.g. the rump under the
    # tail's root) is weighted by distance to the bones it may follow
    empty = [i for i, ws in tab.items() if not ws]
    if empty and arm is not None:
        segs = [(b.name, np.array(b.head_local), np.array(b.tail_local)) for b in arm.data.bones if b.name in bones]
        for i in empty:
            p = np.array(o.data.vertices[i].co[:])
            d = []
            for name, a_, b_ in segs:
                ab = b_ - a_
                t = np.clip((p - a_) @ ab / max(ab @ ab, 1e-9), 0, 1)
                d.append((float(np.linalg.norm(p - (a_ + t * ab))), name))
            d.sort()
            w = {name: 1.0 / (dist + 1e-4) ** 5 for dist, name in d[:3]}
            tab[i] = w
    for i, ws in tab.items():
        if not ws:
            tab[i] = {fallback: 1.0}
    rig.set_weights(o, tab)


def weigh(parts, table, arm, tex, flag_axis):
    mc = rig.mc
    ph = proxy(tex, "proxy_horse")
    pr = proxy(tex, "proxy_rider")
    how = {"horse": mc.heat(ph, arm, rig.HORSE), "rider": mc.heat(pr, arm, rig.RIDER)}
    hand_l = arm.data.bones["hand_l"].head_local
    for pid, o in parts.items():
        w = table[pid]["weights"]
        if w == "horse_self":
            # bone heat on the part itself: the rump-and-trailing-leg shell, which the fused
            # mesh's heat mixed with the tail and the other leg (a flap in the gallop)
            if mc.heat(o, arm, ALLOWED["horse"]) != "heat":
                mc.copy_weights(o, ph)
            keep_only(o, ALLOWED["horse"], arm)
        elif w in ALLOWED:
            # copied from the fused mesh's heat: one surface across the parts' joins, so a
            # knee split between two parts bends as one
            mc.copy_weights(o, ph)
            keep_only(o, ALLOWED[w], arm)
        elif w == "rider":
            mc.copy_weights(o, pr)
        elif w.startswith("rigid:"):
            rig.rigid(o, w.split(":", 1)[1])
        elif w == "reins":        # the bit end with the head, the hand end with the near fist
            mc.copy_weights(o, ph)
            idx = {g.index: g.name for g in o.vertex_groups}
            tab = {}
            for v in o.data.vertices:
                ws = {idx[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
                f = max(0.0, min(1.0, (0.45 - (v.co - hand_l).length) / 0.35))
                ws = {b: x * (1 - f) for b, x in ws.items()}
                ws["hand_l"] = ws.get("hand_l", 0.0) + f
                tab[v.index] = ws or {"head_h": 1.0}
            rig.set_weights(o, tab)
        elif w == "flag":         # the hoist on the staff, the fly on the two pennon bones
            fa = flag_axis
            tab = {}
            for v in o.data.vertices:
                r = np.array(v.co[:]) - fa["bot"]
                u = float(np.linalg.norm(r - fa["d"] * (r @ fa["d"]))) / fa["width"]
                if u < 0.2:
                    tab[v.index] = {"pole": 1.0}
                elif u < 0.6:
                    t = (u - 0.2) / 0.4
                    tab[v.index] = {"pole": 1 - t, "pennon_1": t}
                else:
                    t = min(1.0, (u - 0.6) / 0.4)
                    tab[v.index] = {"pennon_1": 1 - t, "pennon_2": t}
            rig.set_weights(o, tab)
        else:
            raise SystemExit("tripo_parts.csv: unknown weighting %r" % w)
    for o in (ph, pr):
        bpy.data.objects.remove(o, do_unlink=True)
    return how


# ------------------------------------------------------------------ texture

def emission_material(src_image, name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = src_image
    e = nt.nodes.new("ShaderNodeEmission")
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(t.outputs["Color"], e.inputs["Color"])
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return m


UV_ANGLE = 80.0           # smart-project angle: the reduced Tripo mesh at 60 fell into thousands of islands
FINE = {26: (0.008, 0.03), 35: (0.008, 0.03)}   # parts baked with a short cage (the face under the hat's brim)
FLAT_NORMAL = {26, 35}    # the face: its baked normals washed it out under the brim; it keeps the flat normal


def unwrap(objs, weights):
    """Smart-project each part, scale its islands to metres x its texel
    weight, put them in one 0..1 tile and pack them (a wide angle: fewer, larger islands)."""
    for ob in objs:
        tx.activate(ob)
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
        k = math.sqrt(area3 / max(a2, 1e-9)) * weights.get(ob.name, 1.0)
        me.uv_layers.active.data.foreach_set("uv", (uv * k).ravel())
    mx = 0.0
    for ob in objs:
        uv = np.zeros(len(ob.data.loops) * 2)
        ob.data.uv_layers.active.data.foreach_get("uv", uv)
        mx = max(mx, np.abs(uv).max())
    for ob in objs:
        uv = np.zeros(len(ob.data.loops) * 2)
        ob.data.uv_layers.active.data.foreach_get("uv", uv)
        ob.data.uv_layers.active.data.foreach_set("uv", uv / (mx * 1.01))
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    try:
        bpy.ops.uv.pack_islands(udim_source="ACTIVE_UDIM", rotate=True, margin=0.002, shape_method="CONCAVE")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")


FAR_CAGE, FAR_RAY = 0.12, 0.40    # the far colour pass (metres)
HIDDEN_GREY = (0.80, 0.80, 0.80)  # a texel no ray reaches (a face hidden deep inside another part)


def check_misses(parts, col, tex):
    """The near pass into a scratch image (magenta fill): the share of each part's loop and
    face samples its rays miss (they keep the far pass's colour in the atlas)."""
    probe = tx.new_image("courier_probe", True, MISS)
    for pid, o in parts.items():
        if pid in FINE:
            far_bake(o, probe, tex, *FINE[pid])
        else:
            tx.bake(o, probe, "EMIT", tex)
    for pid, o in parts.items():
        if pid in FINE:
            far_bake(o, col, tex, *FINE[pid])
        else:
            tx.bake(o, col, "EMIT", tex)
    W = probe.size[0]
    px = np.array(probe.pixels[:], np.float32).reshape(W, W, 4)
    bad = {}
    for pid, o in parts.items():
        uv = np.zeros(len(o.data.loops) * 2)
        o.data.uv_layers.active.data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        cen = np.array([uv[list(p.loop_indices)].mean(0) for p in o.data.polygons])
        ij = np.clip((np.vstack([uv, cen]) * (W - 1)).round().astype(int), 0, W - 1)
        sm = px[ij[:, 1], ij[:, 0], :3]
        miss = float(np.mean((sm[:, 0] > 0.95) & (sm[:, 1] < 0.05) & (sm[:, 2] > 0.95)))
        if miss > 0.01:
            bad[pid] = round(miss, 3)
    bpy.data.images.remove(probe)
    print("TRIPO bake check: parts whose near-pass rays miss > 1%% of samples (far colour kept): %s" % (bad or "none"))
    return bad


def far_bake(low, image, tex, cage=None, ray=None):
    """texture.bake with its own cage and ray (the far pass's by default)."""
    sc = bpy.context.scene
    for m in low.data.materials:
        tx.target_node(m, image)
    tx.activate(low)
    tex.select_set(True)
    bpy.context.view_layer.objects.active = low
    b = sc.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = FAR_CAGE if cage is None else cage
    b.max_ray_distance = FAR_RAY if ray is None else ray
    b.margin = tx.MARGIN
    b.use_clear = False
    b.target = "IMAGE_TEXTURES"
    bpy.ops.object.bake(type="EMIT")


def texture(parts, table, tex):
    sc = bpy.context.scene
    src_mat = tex.data.materials[0]
    imgs = {}
    for n in src_mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            to = [l.to_node.type for l in n.outputs["Color"].links]
            key = "col" if "BSDF_PRINCIPLED" in to else "mr" if "SEPARATE_COLOR" in to or "SEPRGB" in to else "nor"
            imgs[key] = n.image
    print("TRIPO source maps:", {k: v.name for k, v in imgs.items()})
    objs = list(parts.values())
    unwrap(objs, {o.name: float(table[pid]["texel"]) for pid, o in parts.items()})
    col = tx.new_image("courier_atlas", True, MISS)
    nor = tx.new_image("courier_atlas_n", False, (0.5, 0.5, 1.0, 1))
    mr = tx.new_image("courier_atlas_mr", False, (1.0, 0.8, 0.0, 1))
    tmp = bpy.data.materials.new("bake_target")
    tmp.use_nodes = True
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(tmp)
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
    col_mat = emission_material(imgs["col"], "src_col")
    mr_mat = emission_material(imgs["mr"], "src_mr") if "mr" in imgs else None
    tex.data.materials[0] = col_mat
    # a FAR pass first (a longer cage and ray): a part's hidden faces (inside another part,
    # where the fused mesh has no surface) find the nearest skin; what even it misses is
    # counted and greyed; then the NEAR pass over it, which leaves its own misses as the far
    # pass painted them
    for o in objs:
        far_bake(o, col, tex)
    W = col.size[0]
    px = np.array(col.pixels[:], np.float32).reshape(W, W, 4)
    miss_far = (px[..., 0] > 0.95) & (px[..., 1] < 0.05) & (px[..., 2] > 0.95)
    px[miss_far, :3] = HIDDEN_GREY
    col.pixels.foreach_set(px.ravel())
    near_miss = check_misses(parts, col, tex)
    print("TRIPO bake: atlas %.0f%% covered by islands (the rest greyed)" % (100.0 * (1 - miss_far.mean())))
    if mr_mat:
        tex.data.materials[0] = mr_mat
        for o in objs:
            tx.bake(o, mr, "EMIT", tex)
    tex.data.materials[0] = src_mat
    for pid, o in parts.items():
        if pid not in FLAT_NORMAL:
            tx.bake(o, nor, "NORMAL", tex)
    bad = near_miss
    mat = tx.atlas_material(col, nor, mr)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    for img in (col, nor, mr):
        img.pack()
    return mat, bad


# -------------------------------------------------------------------- build

def build():
    """Into the current (empty) file: returns (courier object, armature, weights used,
    part tris)."""
    table = {int(r["part"]): r for r in rows()}
    tex, parts = load()
    M = icp(tex, parts)
    for o in parts.values():
        o.data.transform(M)
    groups = lambda g: [i for i, r in table.items() if r["group"] == g]
    frame(tex, parts, groups("horse"))
    cull_hidden(tex, parts)
    # budgets, scaled to the game's cap
    want = {i: int(r["tris"]) for i, r in table.items()}
    k = min(1.0, TRIS_MAX / sum(want.values()))
    tris = {}
    for pid, o in list(parts.items()):
        o.name = o.data.name = "tp%02d" % pid
        cur = len(o.data.polygons)
        target = int(want[pid] * k)
        if cur > target:
            m = o.modifiers.new("d", "DECIMATE")
            m.ratio = target / cur
            rig.activate(o)
            bpy.ops.object.modifier_apply(modifier=m.name)
        tris[pid] = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("TRIPO tris %d over %d parts" % (sum(tris.values()), len(tris)))
    # role -> vertices, for the skeleton (part ids from tripo_parts.csv)
    W = lambda *ids: np.vstack([world_co(parts[i]) for i in ids])
    H = {"hind_l": W(1), "hind_r": W(6), "fore_r": W(8), "fore_l_up": W(4), "fore_l_low": W(19),
         "rump": W(1), "barrel": W(16), "belly": W(16), "neck": W(3), "head": W(23, 28, 3), "tail": W(2)}
    H["hind_l"] = H["hind_l"][H["hind_l"][:, 2] < 1.0]      # part 1 is the rump AND the trailing leg
    H["fore_r"] = H["fore_r"][H["fore_r"][:, 2] < 1.0]
    P = {"coat": W(0), "thigh_r": W(10), "thigh_l": W(24), "boot_r": W(7), "boot_l": W(14),
         "hand_r": W(29), "hand_l": W(32), "collar": W(36), "neck": W(40), "head": W(26), "face": W(35),
         "pole": W(38), "flag": W(11), "case": W(5)}
    spec = horse_spec(H)
    spec += rider_spec(P)
    flag_axis = {}
    spec += prop_spec(P, flag_axis)
    rig.NEUTRAL = neutral_pose(spec)
    spec += ik_spec(spec)
    arm = rig.mu.build_armature(rig.NAME, spec)
    mat, bad = texture(parts, table, tex)
    how = weigh(parts, table, arm, tex, flag_axis)
    for pid, o in parts.items():      # which part each vertex came from (not exported)
        at = o.data.attributes.new("part_id", "INT", "POINT")
        at.data.foreach_set("value", [pid] * len(o.data.vertices))
    objs = list(parts.values())
    rig.activate(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = rig.NAME
    for poly in ob.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    bpy.data.objects.remove(tex, do_unlink=True)
    return ob, arm, how, {"parts": tris, "bake_misses": bad}
