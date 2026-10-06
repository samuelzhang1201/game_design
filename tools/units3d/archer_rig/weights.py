"""Phase 4b-4d: the archer's weights. Each body sub-group (labels.ROLES) is solved by the
heat-equilibrium (Pinocchio) system over its own vertices with only its own bones (the skill's
masks); Blender's Python has no scipy, so the sparse system is solved by a Jacobi-preconditioned
conjugate gradient in numpy (the royal rig's solver). Props are rigid on their bones, blended
over 4 rings into the body they touch; the bow is graded grip -> tip so a draw bends its limbs.

    exec common, labels, armature, weights;  G["solve"]();  G["seam_split"]()
"""
from mathutils import kdtree

SUB_BONES = {
    "lower": ("Hips", "Spine", "Thigh.L", "Thigh.R", "Shin.L", "Shin.R", "Foot.L", "Foot.R"),
    "torso": ("Hips", "Spine", "Chest", "Neck", "Clavicle.L", "Clavicle.R"),   # no upper arm: a raised arm tore the chest (Gate 5)
    "head": ("Neck", "head", "Chest"),
    "arm_l": ("Chest", "Clavicle.L", "UpperArm.L", "Forearm.L", "Hand.L"),
    "arm_r": ("Chest", "Clavicle.R", "UpperArm.R", "Forearm.R", "Hand.R"),
}
RIGID = {"quiver": "Quiver", "scabbard": "Scabbard", "buckler": "Hips"}
SKIRT_Z = 0.60          # the coat's hem: above it a lower-body vertex is the skirt
SKIRT_HIPS = 0.6        # ... and keeps this share on Hips, so a stride does not tear it between the legs
SKIRT_SMOOTH = 6        # neighbour-average passes over the skirt's weights (a lifted knee tore it, Gate 5)


def deform_names():
    return [b.name for b in rig().data.bones if b.use_deform]


def seg_dist(P, names):
    a = rig()
    D = np.empty((len(P), len(names)))
    for j, n in enumerate(names):
        b = a.data.bones[n]
        h, t = np.array(b.head_local), np.array(b.tail_local)
        ab = t - h
        u = np.clip((P - h) @ ab / max(ab @ ab, 1e-12), 0, 1)
        D[:, j] = np.linalg.norm(P - (h + u[:, None] * ab), axis=1)
    return D


def tris_array(o):
    o.data.calc_loop_triangles()
    T = np.empty(len(o.data.loop_triangles) * 3, int)
    o.data.loop_triangles.foreach_get("vertices", T)
    return T.reshape(-1, 3)


def _laplacian(P, T, cut=None):
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


def _matvec(I, J, Vv, N):
    starts = np.searchsorted(I, np.arange(N))
    has = np.bincount(I, minlength=N) > 0
    idx = np.nonzero(has)[0]

    def mv(X):
        out = np.zeros_like(X)
        out[idx] = np.add.reduceat(Vv[:, None] * X[J], starts[idx], axis=0)
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


def solve_region(P_all, T_all, idx, D, cut=None):
    """Heat weights over vertices `idx` from the columns of D (distances to the region's bones);
    `cut(a, b)` on GLOBAL vertex ids drops a Laplacian edge."""
    loc = -np.ones(len(P_all), dtype=np.int64)
    loc[idx] = np.arange(len(idx))
    inside = (loc[T_all] >= 0).all(1)
    T = loc[T_all[inside]]
    P = P_all[idx]
    Dr = D[idx]
    dmin = Dr.min(1)
    near = (Dr <= dmin[:, None] * 1.0001 + 1e-6).astype(float)
    near /= near.sum(1, keepdims=True)
    gcut = (lambda a, b: cut(idx[a], idx[b])) if cut is not None else None
    I, J, Vv, area = _laplacian(P, T, gcut)
    MH = np.maximum(area, 1e-9) / np.maximum(dmin, 0.01) ** 2
    N = len(idx)
    Lmv = _matvec(I, J, Vv, N)
    diagL = np.zeros(N)
    np.add.at(diagL, I[I == J], Vv[I == J])
    W, its = _pcg(lambda X: Lmv(X) + MH[:, None] * X, diagL + MH, MH[:, None] * near)
    W = np.clip(W, 0, 1)
    # a vertex the solve left empty (an island cut off): inverse distance over its two nearest bones
    empty = W.sum(1) < 1e-4
    if empty.any():
        o2 = np.argsort(Dr[empty], 1)[:, :2]
        dd = np.take_along_axis(Dr[empty], o2, 1)
        w = 1 / np.maximum(dd, 1e-3) ** 4
        w /= w.sum(1, keepdims=True)
        Wf = np.zeros((empty.sum(), Dr.shape[1]))
        np.put_along_axis(Wf, o2, w, 1)
        W[empty] = Wf
    return W, its


def _rings(member, nb, depth=4):
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
    """All weights of `archer`; pruned (< 0.01), 4 a vertex, normalised; written as vertex groups
    and the mesh parented to the rig with an Armature modifier."""
    o = mesh()
    P = co(o); lab = roles(); T_all = tris_array(o); nb = neighbours(o)
    names = deform_names()
    col = {n: j for j, n in enumerate(names)}
    W = np.zeros((len(P), len(names)))
    sub_of = {k: ROLES.index(k) for k in SUB_BONES}
    arm_r, arm_l = ROLES.index("arm_r"), ROLES.index("arm_l")

    def cut(a, b):          # never diffuse across an arm's seam with the coat
        la, lb = lab[a], lab[b]
        return ((la == arm_r) != (lb == arm_r)) | ((la == arm_l) != (lb == arm_l))
    report = {}
    for k, bones in SUB_BONES.items():
        idx = np.nonzero(lab == sub_of[k])[0]
        D = seg_dist(P, bones)
        Wr, its = solve_region(P, T_all, idx, D, cut)
        for j, n in enumerate(bones):
            W[idx, col[n]] = Wr[:, j]
        report[k] = [int(len(idx)), int(its)]
    # the coat's skirt keeps a share on the hips
    skirt = (lab == sub_of["lower"]) & (P[:, 2] > SKIRT_Z)
    W[skirt] *= (1 - SKIRT_HIPS)
    W[skirt, col["Hips"]] += SKIRT_HIPS
    sk = np.nonzero(skirt)[0]
    for _ in range(SKIRT_SMOOTH):
        W[sk] = 0.5 * W[sk] + 0.5 * np.array([W[[j for j in nb[i] if lab[j] == lab[i]] or [i]].mean(0) for i in sk])
    # rigid props, blended over 4 rings into what they touch
    for role, bone in RIGID.items():
        mem = lab == ROLES.index(role)
        ring = _rings(mem, nb)
        a = np.clip((ring + 1) / 5.0, 0, 1)[mem]
        one = np.zeros(len(names)); one[col[bone]] = 1
        Wb = W[mem]
        Wb = np.where(Wb.sum(1, keepdims=True) > 0, Wb, one)
        W[mem] = a[:, None] * one + (1 - a[:, None]) * Wb
    # the bow: the grip on Bow, each limb graded from the grip (0) to its tip (1)
    a = rig().data.bones
    zlo, zhi = a["BowLimb.D"].head_local.z, a["BowLimb.U"].head_local.z
    ztop, zbot = a["BowLimb.U"].tail_local.z, a["BowLimb.D"].tail_local.z
    bow = lab == ROLES.index("bow")
    z = P[:, 2]
    tu = np.clip((z - zhi) / (ztop - zhi), 0, 1)
    td = np.clip((zlo - z) / (zlo - zbot), 0, 1)
    W[bow] = 0
    W[bow, col["Bow"]] = 1 - np.maximum(tu, td)[bow]
    W[bow & (z > zhi), col["BowLimb.U"]] = tu[bow & (z > zhi)]
    W[bow & (z < zlo), col["BowLimb.D"]] = td[bow & (z < zlo)]
    # prune, top 4, normalise
    W[W < 0.01] = 0
    if W.shape[1] > 4:
        kth = np.sort(W, 1)[:, -4][:, None]
        W[W < kth] = 0
    s = W.sum(1, keepdims=True)
    W = W / np.maximum(s, 1e-9)
    write_groups(o, rig(), names, W)
    report["unweighted"] = int((W.sum(1) < 0.5).sum())
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


SPLIT_GROUPS = {   # role -> body it belongs to for the seam split (welded contacts)
    "lower": 0, "torso": 0, "head": 0, "arm_l": 1, "arm_r": 2, "quiver": 3, "scabbard": 4, "buckler": 0, "bow": 5,
}


def seam_split():
    """Phase 4d: split `archer` where an arm, the quiver, the scabbard or the bow meets another
    body (face role = its corners' majority); a duplicate on the other side takes the weights of
    the nearest vertex of the body its faces belong to."""
    o = mesh()
    lab = roles()
    body = np.array([SPLIT_GROUPS[ROLES[k]] for k in lab])
    a = o.data.attributes.get("body") or o.data.attributes.new("body", "INT", "POINT")
    a.data.foreach_set("value", body)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    bl = bm.verts.layers.int.get("body")
    dl = bm.verts.layers.deform.verify()

    def mode(vals):
        u, c = np.unique(vals, return_counts=True)
        return int(u[np.argmax(c)])
    fb = [mode([v[bl] for v in f.verts]) for f in bm.faces]
    cut = [e for e in bm.edges if len({fb[f.index] for f in e.link_faces}) > 1]
    bmesh.ops.split_edges(bm, edges=cut)
    bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table(); bm.verts.index_update(); bm.faces.index_update()
    vb = {}
    for f in bm.faces:
        for v in f.verts:
            vb[v.index] = fb[f.index]
    bodies = sorted(set(SPLIT_GROUPS.values()))
    good = {r: [v for v in bm.verts if vb.get(v.index) == r and v[bl] == r] for r in bodies}
    kds = {}
    for r, vs in good.items():
        kd = kdtree.KDTree(max(1, len(vs)))
        for k, v in enumerate(vs):
            kd.insert(v.co, k)
        kd.balance()
        kds[r] = kd
    fixed = 0
    for v in bm.verts:
        r = vb.get(v.index)
        if r is None or v[bl] == r or not good[r]:
            continue
        src = good[r][kds[r].find(v.co)[1]]
        v[dl].clear()
        for g, w in src[dl].items():
            v[dl][g] = w
        v[bl] = r
        fixed += 1
    nv0 = len(o.data.vertices)
    bm.to_mesh(o.data); bm.free(); o.data.update()
    return {"cut_edges": len(cut), "verts": [nv0, len(o.data.vertices)], "reweighted": fixed, "roles_fixed": fix_roles()}


def fix_roles():
    """After a split each vertex touches the faces of ONE body; a duplicate keeps the role it was
    copied with, so set every vertex whose body differs from its faces' to the commonest role
    among the corners of its faces of that body (a re-solve reads the roles)."""
    o = mesh()
    lab = roles()
    body = np.array([SPLIT_GROUPS[ROLES[k]] for k in lab])
    vf = [[] for _ in o.data.vertices]
    for f in o.data.polygons:
        for v in f.vertices:
            vf[v].append(f.index)
    fv = [list(f.vertices) for f in o.data.polygons]
    fbody = np.array([np.bincount(body[vs]).argmax() for vs in fv])
    fixed = 0
    new = lab.copy()
    for i, fs in enumerate(vf):
        if not fs:
            continue
        b = np.bincount(fbody[fs]).argmax()
        if body[i] != b:
            cand = [lab[j] for f in fs for j in fv[f] if body[j] == b]
            if cand:
                new[i] = np.bincount(cand).argmax(); fixed += 1
    o.data.attributes["role"].data.foreach_set("value", new)
    return fixed
