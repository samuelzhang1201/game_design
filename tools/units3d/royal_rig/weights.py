"""Phase 4b-4c: region labels and the heat-equilibrium (Pinocchio) solve per region, written to
`royal`'s vertex groups. Blender's Python has no scipy, so the sparse system is solved by a
Jacobi-preconditioned conjugate gradient in numpy (the same system the skill factors with splu).

    exec common.py, labels.py, weights.py into one namespace;  G["regions"]();  G["solve"]()
"""
from mathutils import kdtree

RADII = {   # the skill's starting body radii (m)
    "R_Hips": 0.24, "R_Spine": 0.25, "R_Chest": 0.28, "R_Neck": 0.15, "R_Head": 0.2, "R_Clavicle": 0.15,
    "R_UpperArm": 0.13, "R_Forearm": 0.12, "R_Hand": 0.10, "R_Thigh": 0.16, "R_Shin": 0.10, "R_Foot": 0.10,
    "Sword": 0.05, "Reins": 1e-6,       # Reins never wins a distance competition: only the straps use it
    "Spine1": 0.33, "Spine2": 0.33, "Chest": 0.33, "Pelvis": 0.33, "Neck1": 0.25, "Neck2": 0.25, "Head": 0.18,
    "FrontScapula": 0.2, "FrontUpperArm": 0.18, "HindThigh": 0.18, "FrontForearm": 0.12, "HindShin": 0.12,
    "FrontCannon": 0.08, "HindCannon": 0.08, "FrontHoof": 0.10, "HindHoof": 0.10,
    "Tail1": 0.12, "Tail2": 0.12, "Tail3": 0.12, "Tail4": 0.12,
}
SUB_BONES = {   # rider sub-group -> the bones it may follow (the skill's masks)
    "lower": ("R_Hips", "R_Spine", "R_Thigh", "R_Shin", "R_Foot"),
    "torso": ("R_Hips", "R_Spine", "R_Chest", "R_Neck", "R_Clavicle", "R_UpperArm"),
    "head": ("R_Neck", "R_Head", "R_Chest"),
    "arm": ("R_Chest", "R_Clavicle", "R_UpperArm", "R_Forearm", "R_Hand", "Sword"),
}
# region codes per vertex (ARM: only the seam split's role -- a rider arm vertex)
MOUNT, RIDER, STRAP, ARM = 0, 1, 2, 3


def rig():
    return bpy.data.objects["royal_rig"]


def deform_bones():
    return [b for b in rig().data.bones if b.use_deform]


def is_rider_bone(n):
    return n.startswith("R_") or n == "Sword"


def base(n):
    return n.split(".")[0]


def seg_dist(P, bones):
    """(N, B) point-to-segment distances, armature rest space = world (the rig is at identity)."""
    D = np.empty((len(P), len(bones)))
    for j, b in enumerate(bones):
        a, c = np.array(b.head_local), np.array(b.tail_local)
        ab = c - a
        t = np.clip((P - a) @ ab / max(ab @ ab, 1e-12), 0, 1)
        D[:, j] = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    return D


def regions():
    """Per vertex: region (mount / rider / strap), the rider sub-group, the rigid anchor (or ''),
    from the part labels + the normalised distance competition for the mixed saddle-and-thigh
    part and for contacts; written as attributes `region`, `sub` (index into SUB_BONES keys) and
    `anchor` (index into the bone list, -1 = none)."""
    o = mesh()
    rt = roles()
    lab = read_int(o, "part")
    P = co(o)
    bones = deform_bones()
    names = [b.name for b in bones]
    D = seg_dist(P, bones)
    r = np.array([RADII[base(n)] for n in names])
    Dn = D / r
    rider_cols = np.array([is_rider_bone(n) for n in names])
    comp_rider = Dn[:, rider_cols].min(1) < Dn[:, ~rider_cols].min(1)
    N = len(P)
    region = np.full(N, MOUNT)
    sub = np.full(N, -1)
    anchor = np.full(N, -1)
    subs = list(SUB_BONES)
    for i, n in enumerate(lab):
        if n >= 1000:
            region[i] = STRAP
            continue
        row = rt[int(n)]
        role = row["role"]
        if role == "strap":           # a rein vertex the thin flood missed is still a rein
            region[i] = STRAP
        elif role == "mount":
            region[i] = MOUNT
        elif role == "prop":
            region[i] = MOUNT; anchor[i] = names.index(row["anchor"])
        elif role == "rprop":
            region[i] = RIDER; anchor[i] = names.index(row["anchor"])
            sub[i] = subs.index("arm" if row["anchor"] == "Sword" else "torso")
        elif role == "rider":
            region[i] = RIDER; sub[i] = subs.index(row["sub"])
        elif role == "mixed":       # saddle + cloth (mount prop) or the rider's thigh
            if comp_rider[i]:
                region[i] = RIDER; sub[i] = subs.index("lower")
            else:
                region[i] = MOUNT; anchor[i] = names.index(row["anchor"])
    # contact arbitration: within 5 cm of the other body's labelled vertices, the competition wins
    kd_r, kd_m = _kd(P[region == RIDER]), _kd(P[region == MOUNT])
    flips = 0
    for i in range(N):
        if region[i] == MOUNT and anchor[i] >= 0 and comp_rider[i] and kd_r.find(P[i])[2] < 0.05:
            region[i], anchor[i], sub[i] = RIDER, -1, subs.index("lower"); flips += 1
        elif region[i] == RIDER and anchor[i] < 0 and not comp_rider[i] and subs[sub[i]] == "lower" \
                and kd_m.find(P[i])[2] < 0.05 and lab[i] == 1:
            region[i], anchor[i], sub[i] = MOUNT, names.index("Spine1"), -1; flips += 1
    # saddle-labelled vertices within 6 cm of a hand or forearm bone belong to that arm
    hands = [j for j, n in enumerate(names) if base(n) in ("R_Hand", "R_Forearm")]
    to_hand = 0
    for i in range(N):
        if region[i] == MOUNT and anchor[i] >= 0 and D[i, hands].min() < 0.06:
            region[i], anchor[i], sub[i] = RIDER, -1, subs.index("arm"); to_hand += 1
    # neighbour majority, 4 passes, flip only past 60 %
    nb = neighbours(o.data)
    for _ in range(4):
        new = region.copy()
        for i, ns in enumerate(nb):
            if not ns or region[i] == STRAP:
                continue
            vals, cnt = np.unique(region[ns], return_counts=True)
            k = np.argmax(cnt)
            if vals[k] != region[i] and vals[k] != STRAP and cnt[k] > 0.6 * len(ns):
                new[i] = vals[k]
                if vals[k] == RIDER and sub[i] < 0:
                    sub[i] = subs.index("lower"); anchor[i] = -1
                if vals[k] == MOUNT:
                    sub[i] = -1
                    if anchor[i] >= 0 and is_rider_bone(names[anchor[i]]):
                        anchor[i] = -1
        region = new
    write_int(o, "region", region)
    write_int(o, "sub", sub)
    write_int(o, "anchor", anchor)
    return {"mount": int((region == MOUNT).sum()), "rider": int((region == RIDER).sum()),
            "strap": int((region == STRAP).sum()), "contact_flips": flips, "to_hand": to_hand,
            "mixed_to_rider": int(((lab == 1) & (region == RIDER)).sum())}


def _kd(P):
    kd = kdtree.KDTree(max(1, len(P)))
    for i, p in enumerate(P):
        kd.insert(p, i)
    kd.balance()
    return kd


def region_map():
    o = mesh()
    region, sub, anchor = read_int(o, "region"), read_int(o, "sub"), read_int(o, "anchor")
    cols = np.zeros((len(region), 3))
    cols[region == MOUNT] = (0.6, 0.6, 0.6)
    cols[(region == MOUNT) & (anchor >= 0)] = (0.95, 0.8, 0.1)
    subc = [(0.15, 0.35, 0.95), (0.1, 0.75, 0.9), (0.6, 0.3, 0.9), (0.2, 0.8, 0.3)]
    for k in range(4):
        cols[(region == RIDER) & (sub == k)] = subc[k]
    cols[(region == RIDER) & (anchor >= 0)] = (1.0, 0.5, 0.7)
    cols[region == STRAP] = (0.9, 0.1, 0.1)
    return paint(cols)


# ------------------------------------------------------------------ the solve ----

def _laplacian(P, T, cut=None):
    """Cotangent Laplacian (clamped, so an M-matrix) and the vertex areas; `cut(a, b)` -> True
    drops that edge (its cotangent weight 0)."""
    N = len(P)
    I, J, Vv = [], [], []
    area = np.zeros(N)
    for k in range(3):
        a, b, c = T[:, k], T[:, (k + 1) % 3], T[:, (k + 2) % 3]
        u, v = P[b] - P[a], P[c] - P[a]
        cr = np.linalg.norm(np.cross(u, v), axis=1)
        cot = np.clip((u * v).sum(1) / np.maximum(cr, 1e-12), 0, 1e3) * 0.5
        if cut is not None:
            cot = np.where(cut(b, c), 0.0, cot)
        I += [b, c, b, c]; J += [c, b, b, c]; Vv += [-cot, -cot, cot, cot]
        np.add.at(area, a, cr / 6)
    I, J, Vv = np.concatenate(I), np.concatenate(J), np.concatenate(Vv)
    order = np.lexsort((J, I))
    return I[order], J[order], Vv[order], area


def _matvec(rows, I, J, Vv, N):
    starts = np.searchsorted(I, np.arange(N))
    has = np.bincount(I, minlength=N) > 0

    def mv(X):
        prod = Vv[:, None] * X[J]
        out = np.zeros_like(X)
        idx = np.nonzero(has)[0]
        red = np.add.reduceat(prod, starts[idx], axis=0)
        out[idx] = red
        return out
    return mv


def _pcg(Amv, diag, Bm, iters=4000, tol=1e-7):
    X = np.zeros_like(Bm)
    R = Bm - Amv(X)
    Z = R / diag[:, None]
    Pp = Z.copy()
    rz = (R * Z).sum(0)
    b2 = np.maximum((Bm * Bm).sum(0), 1e-30)
    for it in range(iters):
        AP = Amv(Pp)
        alpha = rz / np.maximum((Pp * AP).sum(0), 1e-30)
        X += Pp * alpha
        R -= AP * alpha
        if ((R * R).sum(0) / b2).max() < tol * tol:
            return X, it
        Z = R / diag[:, None]
        rz_new = (R * Z).sum(0)
        Pp = Z + Pp * (rz_new / np.maximum(rz, 1e-30))
        rz = rz_new
    return X, iters


def solve_region(idx, bone_ids, D, T_all, mask=None, cut=None):
    """Heat weights over the vertices `idx` from the bones `bone_ids` (columns of D); `mask`
    (len(idx), len(bone_ids)) bool blocks a bone for a vertex; `cut(a, b)` on GLOBAL vertex ids."""
    P_all = co(mesh())
    loc = -np.ones(len(P_all), dtype=np.int64)
    loc[idx] = np.arange(len(idx))
    inside = (loc[T_all] >= 0).all(1)
    T = loc[T_all[inside]]
    P = P_all[idx]
    Dr = D[np.ix_(idx, bone_ids)].copy()
    if mask is not None:
        Dr[~mask] = np.inf
    dmin = Dr.min(1)
    dmin = np.where(np.isfinite(dmin), dmin, 1.0)
    near = (Dr <= dmin[:, None] * 1.0001 + 1e-6).astype(float)
    near /= np.maximum(near.sum(1, keepdims=True), 1e-9)
    gcut = (lambda a, b: cut(idx[a], idx[b])) if cut is not None else None
    I, J, Vv, area = _laplacian(P, T, gcut)
    MH = np.maximum(area, 1e-9) / np.maximum(dmin, 0.01) ** 2
    N = len(idx)
    Lmv = _matvec(None, I, J, Vv, N)
    diagL = np.zeros(N)
    np.add.at(diagL, I[I == J], Vv[I == J])
    A = lambda X: Lmv(X) + MH[:, None] * X
    Wr, its = _pcg(A, diagL + MH, MH[:, None] * near)
    return np.clip(Wr, 0, 1), its, Dr


LEG_BELOW = ("FrontUpperArm", "FrontForearm", "FrontCannon", "FrontHoof",
             "HindThigh", "HindShin", "HindCannon", "HindHoof")
BARREL = {"z_min": 0.75, "y": (-0.20, 0.60)}     # the belly between the legs (Gate 5: it sagged with a leg's swing)


def barrel_mask(P, bone_names):
    """The barrel's vertices may not follow the leg bones below the scapula / hip."""
    m = np.ones((len(P), len(bone_names)), bool)
    inb = (P[:, 2] > BARREL["z_min"]) & (P[:, 1] > BARREL["y"][0]) & (P[:, 1] < BARREL["y"][1])
    for j, n in enumerate(bone_names):
        if base(n) in LEG_BELOW:
            m[inb, j] = False
    return m


def _rings(member, nb, depth=4):
    """Ring index (0..depth-1, else depth) of each member vertex from the member set's border."""
    ring = np.full(len(member), depth)
    front = [i for i in np.nonzero(member)[0] if any(not member[j] for j in nb[i])]
    for i in front:
        ring[i] = 0
    for r in range(1, depth):
        nxt = []
        for i in front:
            for j in nb[i]:
                if member[j] and ring[j] > r:
                    ring[j] = r; nxt.append(j)
        front = nxt
    return ring


def solve():
    """The weights of `royal`: mount and rider solved apart, rider sub-group masks and cut edges,
    rigid props blended over 4 rings, straps graded head -> hand per strand; pruned (<0.01),
    4 a vertex, normalised; written as vertex groups, the mesh parented to the rig."""
    o = mesh()
    arm = rig()
    bones = deform_bones()
    names = [b.name for b in bones]
    P = co(o)
    N = len(P)
    D = seg_dist(P, bones)
    region, sub, anchor = read_int(o, "region"), read_int(o, "sub"), read_int(o, "anchor")
    T_all = np.array([p.vertices[:] for p in o.data.polygons])
    nb = neighbours(o.data)
    W = np.zeros((N, len(bones)))
    report = {}
    # --- mount
    m_idx = np.nonzero(region == MOUNT)[0]
    m_bones = [j for j, n in enumerate(names) if not is_rider_bone(n) and n != "Reins"]
    Wm, its, _ = solve_region(m_idx, m_bones, D, T_all, mask=barrel_mask(P[m_idx], [names[j] for j in m_bones]))
    W[np.ix_(m_idx, m_bones)] = Wm
    report["mount_iters"] = its
    # --- rider, masked per sub-group, opposite-side limbs blocked past 8 cm, edges cut
    r_idx = np.nonzero(region == RIDER)[0]
    r_bones = [j for j, n in enumerate(names) if is_rider_bone(n)]
    subs = list(SUB_BONES)
    mask = np.zeros((len(r_idx), len(r_bones)), bool)
    for a, i in enumerate(r_idx):
        allowed = SUB_BONES[subs[sub[i]]] if sub[i] >= 0 else SUB_BONES["lower"]
        for b, j in enumerate(r_bones):
            n = names[j]
            ok = base(n) in allowed
            if ok and n.endswith((".L", ".R")) and abs(P[i, 0]) > 0.08:
                ok = (n.endswith(".L")) == (P[i, 0] > 0)
            mask[a, b] = ok
    side = np.sign(P[:, 0])
    is_arm = (region == RIDER) & (sub == subs.index("arm"))
    is_low = (region == RIDER) & (sub == subs.index("lower"))
    is_head = (region == RIDER) & (sub == subs.index("head"))

    def cut(a, b):
        x = (is_arm[a] & is_low[b]) | (is_low[a] & is_arm[b]) | (is_arm[a] & is_head[b]) | (is_head[a] & is_arm[b])
        x |= is_arm[a] & is_arm[b] & (side[a] != side[b]) & (np.abs(P[a, 0]) > 0.05) & (np.abs(P[b, 0]) > 0.05)
        return x
    Wr, its, _ = solve_region(r_idx, r_bones, D, T_all, mask=mask, cut=cut)
    W[np.ix_(r_idx, r_bones)] = Wr
    report["rider_iters"] = its
    # --- rigid props: 1.0 on the anchor, blended over 4 rings from the prop's border
    for j in sorted(set(anchor[anchor >= 0].tolist())):
        member = anchor == j
        ring = _rings(member, nb)
        a = np.minimum((ring + 1) / 5.0, 1.0)
        idx = np.nonzero(member)[0]
        one = np.zeros(len(bones)); one[j] = 1.0
        W[idx] = a[idx, None] * one + (1 - a[idx, None]) * W[idx]
    # --- straps: graded from the bit (Head) to the rein hand's place (Reins) by the distances to
    # the two ends, ONE grade over every strand -- graded per strand, a short strand by the hand
    # had its own "bit end" there and drew a line from the old hand to the new when he dismounted
    strap = region == STRAP
    head_j, reins_j = names.index("Head"), names.index("Reins")
    rb = arm.data.bones["Reins"]
    hand_pt = np.array(rb.head_local)
    hb = arm.data.bones["Head"]
    bit_pt = np.array(hb.tail_local) + (np.array(hb.head_local) - np.array(hb.tail_local)) * 0.25
    idx = np.nonzero(strap)[0]
    dh = np.linalg.norm(P[idx] - bit_pt, axis=1)
    dr = np.linalg.norm(P[idx] - hand_pt, axis=1)
    t = np.clip(dh / np.maximum(dh + dr, 1e-6), 0, 1)
    t = np.clip((t - 0.15) / 0.7, 0, 1)            # the last 15 % at each end rigid on its anchor
    W[idx] = 0
    W[idx, head_j] = 1 - t
    W[idx, reins_j] = t
    report["strands"] = int(len(idx))
    # --- prune, top 4, renormalise; any vertex left bare -> 1/d^4 over its region's 2 nearest bones
    W[W < 0.01] = 0
    order = np.argsort(-W, axis=1)
    keep = np.zeros_like(W, bool)
    np.put_along_axis(keep, order[:, :4], True, axis=1)
    W[~keep] = 0
    s = W.sum(1)
    bare = np.nonzero(s < 1e-6)[0]
    for i in bare:
        cols = r_bones if region[i] == RIDER else m_bones
        d = D[i, cols]
        two = np.argsort(d)[:2]
        w = 1.0 / np.maximum(d[two], 1e-3) ** 4
        W[i] = 0
        W[i, np.array(cols)[two]] = w / w.sum()
    W /= W.sum(1, keepdims=True)
    report["bare_fallback"] = len(bare)
    write_groups(o, arm, names, W)
    np.save(SRC + "weights.npy", W)
    return report


def write_groups(o, arm, names, W):
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    for j, n in enumerate(names):
        vg = o.vertex_groups.new(name=n)
        nz = np.nonzero(W[:, j] > 0)[0]
        if not len(nz):
            continue
        q = np.round(W[nz, j], 3)
        for val in np.unique(q):
            vg.add([int(i) for i in nz[q == val]], float(val), "REPLACE")
    for m in [m for m in o.modifiers if m.type == "ARMATURE"]:
        o.modifiers.remove(m)
    mod = o.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    o.parent = arm


def seam_split():
    """Phase 4d: split `royal` along the boundaries between the rider, the mount and the straps
    and between a rider's arm and the rest of him (face role = the majority role of its corners); a duplicate whose faces belong to another
    body takes the deform weights of the nearest vertex of that body."""
    o = mesh()
    region, sub = read_int(o, "region"), read_int(o, "sub")
    role = region.copy()
    role[(region == RIDER) & (sub == list(SUB_BONES).index("arm"))] = ARM   # the arms split from the body too
    write_int(o, "role", role)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    rl = bm.verts.layers.int.get("role")
    gl = bm.verts.layers.int.get("region")
    dl = bm.verts.layers.deform.verify()

    def mode(vals):
        u, c = np.unique(vals, return_counts=True)
        return int(u[np.argmax(c)])
    frole = [mode([v[rl] for v in f.verts]) for f in bm.faces]
    cut = [e for e in bm.edges if len({frole[f.index] for f in e.link_faces}) > 1]
    bmesh.ops.split_edges(bm, edges=cut)
    bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table(); bm.verts.index_update(); bm.faces.index_update()
    vrole = {}
    for f in bm.faces:
        for v in f.verts:
            vrole[v.index] = frole[f.index]
    good = {r: [v for v in bm.verts if vrole.get(v.index) == r and v[rl] == r] for r in (MOUNT, RIDER, STRAP, ARM)}
    kds = {}
    for r, vs in good.items():
        kd = kdtree.KDTree(max(1, len(vs)))
        for k, v in enumerate(vs):
            kd.insert(v.co, k)
        kd.balance()
        kds[r] = kd
    fixed = 0
    for v in bm.verts:
        r = vrole.get(v.index)
        if r is None or v[rl] == r or not good[r]:
            continue
        src = good[r][kds[r].find(v.co)[1]]
        v[dl].clear()
        for g, w in src[dl].items():
            v[dl][g] = w
        v[rl] = r
        v[gl] = RIDER if r == ARM else r          # the region follows the body it now belongs to
        fixed += 1
    nv0 = len(o.data.vertices)
    bm.to_mesh(o.data); bm.free(); o.data.update()
    return {"cut_edges": len(cut), "verts": [nv0, len(o.data.vertices)], "reweighted": fixed}
