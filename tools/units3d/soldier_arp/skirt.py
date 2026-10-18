"""The fauld (outer plates, the torso island) over the mail skirt (the leg island): measure where the
mail pokes through the plates in a clip, and make the two layers deform together.

exec() in the owner's Blender. Islands are found by connectivity on Soldier_body: OUTER = the one
holding the torso, INNER = the one holding the thighs.
"""
import bmesh
import bpy
import numpy as np
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ZONE = (0.55, 1.08)      # the skirt band, metres (rest)


def islands(me):
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    lab = [-1] * len(bm.verts); k = 0
    for v in bm.verts:
        if lab[v.index] >= 0:
            continue
        st = [v]; lab[v.index] = k
        while st:
            a = st.pop()
            for e in a.link_edges:
                b = e.other_vert(a)
                if lab[b.index] < 0:
                    lab[b.index] = k; st.append(b)
        k += 1
    bm.free()
    return np.array(lab)


def layers(body):
    me = body.data
    lab = islands(me)
    sizes = np.bincount(lab)
    co = np.array([v.co for v in me.vertices])
    big = [i for i in np.argsort(-sizes) if sizes[i] > 300]
    top = {i: co[lab == i][:, 2].max() for i in big}
    outer = max(big, key=lambda i: top[i])                 # reaches the shoulders
    inner = max((i for i in big if i != outer), key=lambda i: top[i])
    return lab, outer, inner


def _tree(co, polys):
    return BVHTree.FromPolygons([tuple(c) for c in co], polys)


def census(clip, step=1):
    """-> (frames hit, worst frame, worst count): INNER skirt verts that cross to the outside of OUTER."""
    body, rig, scn = bpy.data.objects["Soldier_body"], bpy.data.objects["rig"], bpy.context.scene
    me = body.data
    lab, outer, inner = layers(body)
    rest = np.array([v.co for v in me.vertices])
    opolys = [tuple(p.vertices) for p in me.polygons if lab[p.vertices[0]] == outer]
    zone = np.where((lab == inner) & (rest[:, 2] > ZONE[0]) & (rest[:, 2] < ZONE[1]))[0]
    t0 = _tree(rest, opolys)
    side0 = {}
    for i in zone:
        loc, nor, _, d = t0.find_nearest(rest[i])
        if loc is not None and d < 0.06:
            side0[i] = np.sign(np.dot(rest[i] - np.array(loc), np.array(nor)))
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    f0, f1 = map(int, act.frame_range)
    hit, worst = 0, (None, 0)
    for f in range(f0, f1 + 1, step):
        scn.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        m = ev.to_mesh()
        co = np.array([v.co for v in m.vertices])
        ev.to_mesh_clear()
        t = _tree(co, opolys)
        n = 0
        for i, s0 in side0.items():
            loc, nor, _, d = t.find_nearest(co[i])
            if loc is not None and np.sign(np.dot(co[i] - np.array(loc), np.array(nor))) != s0 and d > 0.003:
                n += 1
        hit += bool(n)
        if n > worst[1]:
            worst = (f, n)
    return hit, worst[0], worst[1], len(side0)


def pairs(body, band=ZONE, reach=0.04):
    """Layered pairs on the torso island: (outer vertex, inner triangle, barycentric) where a ray
    inward along the vertex normal meets the island again within `reach` (rest pose)."""
    me = body.data
    lab, outer, _ = _torso(body)
    me.calc_loop_triangles()
    tris = [t for t in me.loop_triangles if lab[t.vertices[0]] == outer]
    tv = [tuple(t.vertices) for t in tris]
    co = [v.co.copy() for v in me.vertices]
    tree = BVHTree.FromPolygons(co, tv)
    out = []
    for v in me.vertices:
        if lab[v.index] != outer or not (band[0] < v.co.z < band[1]):
            continue
        n = v.normal
        loc, nor, ti, d = tree.ray_cast(v.co - n * 0.004, -n, reach)
        if loc is None or v.index in tv[ti]:
            continue
        a, b, c = (co[i] for i in tv[ti])
        w = _bary(loc, a, b, c)
        out.append((v.index, tv[ti], w, d + 0.004))
    return out


def _torso(body):
    lab = islands(body.data)
    sizes = np.bincount(lab)
    co = np.array([v.co for v in body.data.vertices])
    band = (co[:, 2] > ZONE[0]) & (co[:, 2] < ZONE[1])
    torso = max(range(len(sizes)), key=lambda i: (band & (lab == i)).sum() if co[lab == i][:, 2].max() > 1.3 else -1)
    return lab, torso, None


def _bary(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11, d20, d21 = v0.dot(v0), v0.dot(v1), v1.dot(v1), v2.dot(v0), v2.dot(v1)
    den = d00 * d11 - d01 * d01 or 1e-12
    y = (d11 * d20 - d01 * d21) / den; z = (d00 * d21 - d01 * d20) / den
    return (1 - y - z, y, z)


def flips(clip, P, step=1, tol=0.002):
    """-> (frames with a flip, worst frame, worst count): pairs whose inner point ends up in front."""
    body, rig, scn = bpy.data.objects["Soldier_body"], bpy.data.objects["rig"], bpy.context.scene
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    f0, f1 = map(int, act.frame_range)
    hit, worst = 0, (None, 0)
    for f in range(f0, f1 + 1, step):
        scn.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        m = ev.to_mesh()
        n = 0
        for vi, tri, w, _ in P:
            p = m.vertices[tri[0]].co * w[0] + m.vertices[tri[1]].co * w[1] + m.vertices[tri[2]].co * w[2]
            if (m.vertices[vi].co - p).dot(m.vertices[vi].normal) < -tol:
                n += 1
        ev.to_mesh_clear()
        hit += bool(n)
        if n > worst[1]:
            worst = (f, n)
    return hit, worst[0], worst[1]


def share_weights(body, radius=0.05, band=(0.60, 1.10), feather=0.05, passes=2):
    """Spatial (not topological) Gaussian smoothing of the deform weights over the torso island's
    skirt band, so the plates and the mail 1-3 cm beneath them carry the same weights and move as
    one. Full strength inside the band, ramped to none over `feather` at its ends."""
    me = body.data
    lab, torso, _ = _torso(body)
    co = np.array([v.co for v in me.vertices])
    idx = np.where((lab == torso) & (co[:, 2] > band[0]) & (co[:, 2] < band[1]))[0]
    names = [g.name for g in body.vertex_groups]
    W = np.zeros((len(idx), len(names)))
    for r, i in enumerate(idx):
        for g in me.vertices[i].groups:
            W[r, g.group] = g.weight
    kd = KDTree(len(idx))
    for r, i in enumerate(idx):
        kd.insert(co[i], r)
    kd.balance()
    z = co[idx, 2]
    alpha = np.clip(np.minimum(z - band[0], band[1] - z) / feather, 0, 1)[:, None]
    sig = radius / 2
    for _ in range(passes):
        N = np.zeros_like(W)
        for r, i in enumerate(idx):
            nb = kd.find_range(co[i], radius)
            js = [j for _, j, _ in nb]; ds = np.array([d for _, _, d in nb])
            k = np.exp(-0.5 * (ds / sig) ** 2)
            N[r] = (k[:, None] * W[js]).sum(0) / k.sum()
        W = alpha * N + (1 - alpha) * W
    # keep the four largest, normalise, write back
    for r, i in enumerate(idx):
        row = W[r].copy()
        keep = np.argsort(-row)[:4]
        mask = np.zeros_like(row, bool); mask[keep] = True
        row[~mask] = 0
        row[row < 0.01] = 0
        row /= row.sum()
        for gi_, w in enumerate(row):
            vg = body.vertex_groups[gi_]
            if w > 0:
                vg.add([int(i)], float(w), "REPLACE")
            else:
                vg.remove([int(i)])
    return len(idx)


def bind_pairs(body, P):
    """Give each inner triangle vertex the (average) weights of the outer vertices layered over it,
    so a pair moves as one; run after share_weights."""
    me = body.data
    acc = {}
    for vi, tri, w, _ in P:
        wv = {g.group: g.weight for g in me.vertices[vi].groups}
        for t, b in zip(tri, w):
            if b <= 0.05:
                continue
            d, s = acc.setdefault(t, ({}, [0.0]))
            for k, x in wv.items():
                d[k] = d.get(k, 0.0) + b * x
            s[0] += b
    for t, (d, s) in acc.items():
        row = {k: x / s[0] for k, x in d.items()}
        top = sorted(row.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(x for _, x in top)
        for g in list(me.vertices[t].groups):
            body.vertex_groups[g.group].remove([t])
        for k, x in top:
            body.vertex_groups[k].add([t], x / tot, "REPLACE")
    return len(acc)


def open_gap(body, P, min_gap=0.02, max_push=0.015):
    """Move the inner layer under each pair inward, along the OUTER vertex's normal (the mail's own
    normals are not consistent), so the plates stand at least `min_gap` off it at rest; the inner
    layer is hidden under the plates, so the look is unchanged."""
    me = body.data
    push = {}
    for vi, tri, w, gap in P:
        need = min(max_push, max(0.0, min_gap - gap))
        n = me.vertices[vi].normal.copy()
        for t, b in zip(tri, w):
            if b > 0.05:
                d = need * min(1.0, b * 1.5)
                if d > push.get(t, (0.0, None))[0]:
                    push[t] = (d, n)
    for t, (d, n) in push.items():
        me.vertices[t].co -= n * d
    me.update()
    return len(push), round(max(d for d, _ in push.values()), 4) if push else 0


def trouser_pokes(clips):
    """Trouser (leg island) verts in the skirt band that cross to the outside of the torso shell."""
    body, rig, scn = bpy.data.objects["Soldier_body"], bpy.data.objects["rig"], bpy.context.scene
    me = body.data
    lab, torso, _ = _torso(body)
    sizes = np.bincount(lab)
    co = np.array([v.co for v in me.vertices])
    legs = [i for i in range(len(sizes)) if sizes[i] > 300 and 0.9 < co[lab == i][:, 2].max() < 1.05][0]
    opolys = [tuple(p.vertices) for p in me.polygons if lab[p.vertices[0]] == torso]
    zone = np.where((lab == legs) & (co[:, 2] > 0.6) & (co[:, 2] < 1.0))[0]
    t0 = BVHTree.FromPolygons([tuple(c) for c in co], opolys)
    side0 = {}
    for i in zone:
        loc, nor, _, d = t0.find_nearest(co[i])
        if loc is not None and d < 0.08:
            side0[i] = np.sign(np.dot(co[i] - np.array(loc), np.array(nor)))
    res = {}
    for clip in clips:
        a = bpy.data.actions[clip]
        rig.animation_data.action = a
        rig.animation_data.action_slot = a.slots[0]
        f0, f1 = map(int, a.frame_range)
        hit, worst = 0, (None, 0)
        for f in range(f0, f1 + 1):
            scn.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            ev = body.evaluated_get(dg)
            m = ev.to_mesh()
            c = np.array([v.co for v in m.vertices])
            ev.to_mesh_clear()
            t = BVHTree.FromPolygons([tuple(x) for x in c], opolys)
            n = 0
            for i, s0 in side0.items():
                loc, nor, _, d = t.find_nearest(c[i])
                if loc is not None and d > 0.004 and np.sign(np.dot(c[i] - np.array(loc), np.array(nor))) != s0:
                    n += 1
            hit += bool(n)
            if n > worst[1]:
                worst = (f, n)
        res[clip] = (hit, worst[0], worst[1])
    return res


def slim_thighs(body, clearance=0.035, max_slim=0.025, feather=(0.70, 0.76), top=1.02):
    """Pull the trouser verts hidden under the skirt toward their thigh bone so the shell stands
    `clearance` off them at rest; ramped from nothing at feather[0] (the visible hem) to full at
    feather[1]."""
    rig = bpy.data.objects["rig"]
    me = body.data
    lab, torso, _ = _torso(body)
    sizes = np.bincount(lab)
    co = np.array([v.co for v in me.vertices])
    legs = [i for i in range(len(sizes)) if sizes[i] > 300 and 0.9 < co[lab == i][:, 2].max() < 1.05][0]
    opolys = [tuple(p.vertices) for p in me.polygons if lab[p.vertices[0]] == torso]
    shell = BVHTree.FromPolygons([tuple(c) for c in co], opolys)
    bones = {s: (rig.data.bones["thigh_stretch" + s].head_local, rig.data.bones["thigh_stretch" + s].tail_local)
             for s in (".l", ".r")}
    moved = 0
    for i in np.where((lab == legs) & (co[:, 2] > feather[0]) & (co[:, 2] < top))[0]:
        v = me.vertices[i]
        loc, _, _, d = shell.find_nearest(v.co)
        if loc is None:
            continue
        need = min(max_slim, clearance - d)
        if need <= 0:
            continue
        a, b = bones[".l" if v.co.x > 0 else ".r"]
        ab = b - a
        t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
        r = v.co - (a + ab * t)
        r.z = 0.0                                   # radial in the horizontal plane
        if r.length < 1e-4:
            continue
        k = min(1.0, (v.co.z - feather[0]) / (feather[1] - feather[0]))
        v.co -= r.normalized() * min(need * k, r.length - 0.03)
        moved += 1
    me.update()
    return moved


def untangle(body, band=(0.62, 0.97), step=0.004, rounds=12):
    """Tripo fused the mail into the plates: at rest they already cross (dark mail patches on the
    plates). For every self-intersecting triangle pair of the torso island in `band`, push the
    inner one (nearer the torso's axis) inward along the outer one's normal, until none is left."""
    me = body.data
    lab, torso, _ = _torso(body)
    log = []
    for _ in range(rounds):
        me.calc_loop_triangles()
        tris = [t for t in me.loop_triangles if lab[t.vertices[0]] == torso]
        tv = [tuple(t.vertices) for t in tris]
        co = [v.co.copy() for v in me.vertices]
        tree = BVHTree.FromPolygons(co, tv)
        cen = lambda i: sum((co[k] for k in tv[i]), co[0] * 0) / 3
        hits = [(a, b) for a, b in tree.overlap(tree)
                if a < b and not set(tv[a]) & set(tv[b]) and band[0] < cen(a).z < band[1]]
        log.append(len(hits))
        if not hits:
            break
        push = {}
        for a, b in hits:
            ca, cb = cen(a), cen(b)
            ra, rb = ca.xy.length, cb.xy.length
            outer, inner = (a, b) if ra > rb else (b, a)
            n = tris[outer].normal.copy()
            if n.dot(cen(outer).to_2d().to_3d()) < 0:   # face the outer normal away from the axis
                n = -n
            for k in tv[inner]:
                push.setdefault(k, n)
        for k, n in push.items():
            me.vertices[k].co -= n * step
        me.update()
    return log


def fix_skirt(body, band=(0.78, 1.10), radius=0.07):
    """The whole fix on a fresh file: untangle the rest pose, open the gap under the plates, slim the
    hidden thighs, share weights over the plate/mail overlap band. Returns the pairs."""
    untangle(body)
    P = pairs(body)
    open_gap(body, P)
    slim_thighs(body)
    share_weights(body, radius=radius, band=band)
    return P


def plates_follow_mail(body, P):
    """Give each outer (plate) vertex the weights of the mail point beneath it, so the plates are
    carried by the thighs exactly as the mail is (the mail is what keeps the thighs covered)."""
    me = body.data
    rows = {}
    for vi, tri, w, _ in P:
        acc = {}
        for t, b in zip(tri, w):
            for g in me.vertices[t].groups:
                acc[g.group] = acc.get(g.group, 0.0) + b * g.weight
        rows[vi] = acc
    for vi, acc in rows.items():
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(x for _, x in top) or 1.0
        for g in list(me.vertices[vi].groups):
            body.vertex_groups[g.group].remove([vi])
        for k, x in top:
            if x / tot > 0.01:
                body.vertex_groups[k].add([vi], x / tot, "REPLACE")
    return len(rows)


def skirt_field(body, z_belt=1.00, z_hem=0.68, thigh_max=0.75, centre=0.04, feather=0.06):
    """One weight field for the whole skirt band of the torso island (plates and mail alike): root
    at the belt, the thigh of its own side growing to `thigh_max` at the hem, the two sides blended
    over +-`centre` at the middle; ramped back to the original weights above the belt."""
    me = body.data
    lab, torso, _ = _torso(body)
    G = {n: body.vertex_groups[n].index for n in
         ("root.x", "thigh_twist.l", "thigh_stretch.l", "thigh_twist.r", "thigh_stretch.r")}
    n = 0
    for v in me.vertices:
        z = v.co.z
        if lab[v.index] != torso or z > z_belt + feather or z < z_hem - 0.2:
            continue
        t = min(1.0, max(0.0, (z_belt - z) / (z_belt - z_hem)))
        T = thigh_max * t ** 1.2
        sl = min(1.0, max(0.0, (v.co.x + centre) / (2 * centre)))
        field = {G["root.x"]: 1 - T,
                 G["thigh_twist.l"]: 0.5 * T * sl, G["thigh_stretch.l"]: 0.5 * T * sl,
                 G["thigh_twist.r"]: 0.5 * T * (1 - sl), G["thigh_stretch.r"]: 0.5 * T * (1 - sl)}
        k = min(1.0, max(0.0, (z_belt + feather - z) / feather))     # 0 above the belt band
        old = {g.group: g.weight for g in v.groups}
        tot = sum(old.values()) or 1.0
        new = {gi: k * field.get(gi, 0.0) + (1 - k) * old.get(gi, 0.0) / tot for gi in set(field) | set(old)}
        for g in list(v.groups):
            body.vertex_groups[g.group].remove([v.index])
        top = sorted(new.items(), key=lambda kv: -kv[1])[:4]
        s = sum(x for _, x in top) or 1.0
        for gi, x in top:
            if x / s > 0.005:
                body.vertex_groups[gi].add([v.index], x / s, "REPLACE")
        n += 1
    return n
