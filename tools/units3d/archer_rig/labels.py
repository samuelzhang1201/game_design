"""Phase 1d: the Tripo parts (Archer_Parts, the same raw frame as the textured mesh and moved by the
same Phase 1c transform) give every vertex of the game mesh `archer` a ROLE, by nearest part
and a 3-pass neighbour majority. Identified on shots/parts_sheet.png (red part over grey, front
and back):

  body, by sub-group (the solver's masks, weights.py):
    lower  0 coat skirt and belt, 1 right leg, 4 left leg, 5 left boot, 6 right boot
    torso  15 coat body, 8 baldric, 18 breastplate, 22 collar strap
    head   7 helmet, 9 head, 21 face, 23 cheek, 33 chin strap
    arm_l  3 left sleeve and hand
    arm_r  2 right sleeve, 12 right hand
  rigid props: quiver 16 tube, 13 14 20 26-30 32 34-36 38 arrows and fletching -> Quiver
               scabbard 11 -> Hips ; buckler 17 24 37 -> Hips
  bow: 19 upper limb, 10 lower limb, 25 31 grip ; 39 40 the string (deleted in Phase 1c)
"""
ROLE_OF = {}
for i in (0, 1, 4, 5, 6): ROLE_OF[i] = "lower"
for i in (15, 8, 18, 22): ROLE_OF[i] = "torso"
for i in (7, 9, 21, 23, 33): ROLE_OF[i] = "head"
ROLE_OF[3] = "arm_l"
for i in (2, 12): ROLE_OF[i] = "arm_r"
for i in (16, 13, 14, 20, 26, 27, 28, 29, 30, 32, 34, 35, 36, 38): ROLE_OF[i] = "quiver"
ROLE_OF[11] = "scabbard"
for i in (17, 24, 37): ROLE_OF[i] = "buckler"
for i in (19, 10, 25, 31, 39, 40): ROLE_OF[i] = "bow"
ROLES = ["lower", "torso", "head", "arm_l", "arm_r", "quiver", "scabbard", "buckler", "bow"]
assert sorted(ROLE_OF) == list(range(41)), "every part exactly once"


def part_points():
    pts, ids = [], []
    for p in bpy.data.collections["Archer_Parts"].objects:
        P = co(p)
        pts.append(P); ids.append(np.full(len(P), int(p.name.split("_")[-1])))
    return np.concatenate(pts), np.concatenate(ids)


def neighbours(o):
    nb = [[] for _ in o.data.vertices]
    for e in o.data.edges:
        a, b = e.vertices
        nb[a].append(b); nb[b].append(a)
    return nb


def label():
    """Each vertex's role index (ROLES) stored as the int attribute `role`; returns the counts
    and the median distance to the nearest part point (the alignment check)."""
    from mathutils.kdtree import KDTree
    o = mesh()
    P = co(o)
    Q, ids = part_points()
    kd = KDTree(len(Q))
    for i, q in enumerate(Q):
        kd.insert(q, i)
    kd.balance()
    lab = np.empty(len(P), int); dist = np.empty(len(P))
    for i, p in enumerate(P):
        _, j, d = kd.find(p)
        lab[i] = ROLES.index(ROLE_OF[int(ids[j])]); dist[i] = d
    nb = neighbours(o)
    for _ in range(3):
        new = lab.copy()
        for i in range(len(P)):
            if nb[i]:
                v, c = np.unique(lab[nb[i]], return_counts=True)
                if c.max() > 0.6 * len(nb[i]) and v[c.argmax()] != lab[i]:
                    new[i] = v[c.argmax()]
        lab = new
    a = o.data.attributes.get("role") or o.data.attributes.new("role", "INT", "POINT")
    a.data.foreach_set("value", lab)
    return {r: int((lab == k).sum()) for k, r in enumerate(ROLES)}, float(np.median(dist)), float(np.percentile(dist, 90))


def roles():
    o = mesh()
    lab = np.empty(len(o.data.vertices), int)
    o.data.attributes["role"].data.foreach_get("value", lab)
    return lab


def label_map(path_prefix):
    """Vertex colours by role, rendered front and back (the skill's label map)."""
    o = mesh()
    lab = roles()
    pal = [(0.55, 0.55, 0.55), (0.2, 0.5, 0.9), (0.95, 0.8, 0.2), (0.2, 0.85, 0.3), (0.9, 0.3, 0.2),
           (0.7, 0.3, 0.9), (0.5, 0.3, 0.1), (0.1, 0.9, 0.9), (1.0, 0.5, 0.0)]
    ca = o.data.color_attributes.get("role_col") or o.data.color_attributes.new("role_col", "FLOAT_COLOR", "POINT")
    cols = np.array([pal[k] + (1.0,) for k in lab]).ravel()
    ca.data.foreach_set("color", cols)
    o.data.color_attributes.active_color = ca
    for nm, look in (("front", (0.3, 1, -0.1)), ("back", (-0.3, -1, -0.1))):
        shot(path_prefix + nm + ".png", (0.05, 0, 0.92), look, 2.0, res=600, objs=[o], color="VERTEX")


def icp_align(iters=45, n_sub=6000, seed=0):
    """ICP with scale (the skill's Phase 1d step 1): the parts moved onto the full-resolution
    textured mesh `archer_src` (string removed), worst 20 % trimmed each step. Returns the
    median / p90 distance before and after."""
    from mathutils.bvhtree import BVHTree
    src = bpy.data.objects["archer_src"]
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(src, dg)
    Q, _ = part_points()
    rng = np.random.default_rng(seed)
    sub = Q[rng.choice(len(Q), min(n_sub, len(Q)), replace=False)]

    def near(X):
        out = np.empty_like(X); D = np.empty(len(X))
        for i, x in enumerate(X):
            loc, _, _, d = bvh.find_nearest(Vector(x))
            out[i] = loc; D[i] = d
        return out, D

    _, D0 = near(sub)
    R = np.eye(3); t = np.zeros(3); s = 1.0
    for _ in range(iters):
        X = s * sub @ R.T + t
        Qn, D = near(X)
        k = D < np.percentile(D, 80)
        A = sub[k]; B = Qn[k]; ma = A.mean(0); mb = B.mean(0); A0 = A - ma; B0 = B - mb
        U, S, Vt = np.linalg.svd(A0.T @ B0)
        Dm = np.diag([1, 1, np.sign(np.linalg.det(Vt.T @ U.T))])
        R = Vt.T @ Dm @ U.T; s = (S * np.diag(Dm)).sum() / (A0 ** 2).sum(); t = mb - s * (R @ ma)
    _, D1 = near(s * sub @ R.T + t)
    M = Matrix.Identity(4)
    for i in range(3):
        for j in range(3):
            M[i][j] = s * R[i, j]
        M[i][3] = t[i]
    for p in bpy.data.collections["Archer_Parts"].objects:
        p.data.transform(M)
    return [float(np.median(D0)), float(np.percentile(D0, 90)), float(np.median(D1)), float(np.percentile(D1, 90)), float(s)]


GRIP_Z = (0.93, 1.06)     # the fist's height on the grip (shots/nostring_hand.png)
TIP_Z = 0.25              # below this the bottom tip is found by walking the mesh down the bow


def bottom_tip(lab, P):
    """The bow's bottom tip: the vertices reached over mesh edges from the bow-labelled ones
    at TIP_Z-5 cm..TIP_Z without climbing above TIP_Z (the bow does not touch the boot)."""
    nb = neighbours(mesh())
    bow = ROLES.index("bow")
    seed = list(np.nonzero((lab == bow) & (P[:, 2] > TIP_Z - 0.05) & (P[:, 2] < TIP_Z))[0])
    seen = set(seed)
    while seed:
        i = seed.pop()
        for j in nb[i]:
            if j not in seen and P[j, 2] < TIP_Z:
                seen.add(j); seed.append(j)
    out = np.zeros(len(P), bool)
    out[list(seen)] = True
    return out


def bow_axis(lab, P):
    """The bow's centreline, tip to tip, from the mesh itself (the parts file's bow is a separate
    generation ~10 cm off): centroids every 2 cm of height of the bow-labelled vertices, the
    vertices past TIP_X at the bottom tip, the fist's band bridged by interpolation."""
    B = P[lab == ROLES.index("bow")]
    T = P[bottom_tip(lab, P)]
    zs = np.arange(0.005, B[:, 2].max(), 0.02)
    pts = []
    for z in zs:
        if GRIP_Z[0] <= z <= GRIP_Z[1]:
            continue
        S_ = T if z < TIP_Z - 0.05 else B
        k = np.abs(S_[:, 2] - z) < 0.01
        if k.sum() >= 3:
            pts.append(S_[k].mean(0))
    pts = np.array(pts)
    zs = np.arange(pts[0, 2], pts[-1, 2] + 1e-6, 0.02)
    return np.c_[np.interp(zs, pts[:, 2], pts[:, 0]), np.interp(zs, pts[:, 2], pts[:, 1]), zs]


def seg_dist(P, A, B):
    d = B - A
    t = np.clip(((P - A) * d).sum(1) / max((d * d).sum(), 1e-12), 0, 1)
    return np.linalg.norm(P - (A + t[:, None] * d), axis=1)


def dist_to_polyline(P, L):
    return np.min([seg_dist(P, L[i], L[i + 1]) for i in range(len(L) - 1)], axis=0)


def fist_centre(P, lab, L):
    """The left fist: the vertices 1.4-6 cm from the bow's centreline within the grip band."""
    d = dist_to_polyline(P, L)
    k = (d > 0.014) & (d < 0.06) & (P[:, 2] > GRIP_Z[0]) & (P[:, 2] < GRIP_Z[1])
    return P[k].mean(0)


def arbitrate():
    """Contacts the nearest-part labels get wrong. Inside the fist (7 cm round its centre) only
    the grip, within 1.4 cm of the bow's centreline, is bow; outside it anything within 1.6 cm
    of the centreline is bow (the bottom tip beside the boot) and a bow vertex farther than
    3 cm is not (left as it was labelled before, reported)."""
    o = mesh()
    P = co(o)
    lab = roles()
    L = bow_axis(lab, P)
    d = dist_to_polyline(P, L)
    bow, hand = ROLES.index("bow"), ROLES.index("arm_l")
    C = fist_centre(P, lab, L)
    fist = np.linalg.norm(P - C, axis=1) < 0.07
    to_hand = fist & ((lab == bow) | (lab == hand)) & (d >= 0.014)
    tip = bottom_tip(lab, P)
    to_bow = (~fist & (d < 0.016) & ((P[:, 2] >= TIP_Z) | tip)) | (fist & (d < 0.014)) | tip
    lab[to_hand] = hand
    lab[to_bow] = bow
    near_grip = (P[:, 2] > GRIP_Z[0] - 0.08) & (P[:, 2] < GRIP_Z[1] + 0.08)
    stray = (lab == bow) & (d > 0.03) & near_grip      # the wrist's cuff, labelled by the grip part
    lab[stray] = hand
    o.data.attributes["role"].data.foreach_set("value", lab)
    return {"fist": C.round(3).tolist(), "to_hand": int(to_hand.sum()), "to_bow": int(to_bow.sum()),
            "cuff_to_hand": int(stray.sum()), "tip": int(tip.sum()), "axis_bottom": L[0].round(3).tolist(), "axis_top": L[-1].round(3).tolist()}
