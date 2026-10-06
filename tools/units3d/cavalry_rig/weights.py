"""Phase 1d + 4 for the cavalry: the role table from `tripo_part` (on every vertex) and the old
part table (tools/units3d/cavalry_tripo/tripo_parts.csv: group + weighting rule), then weights:

  * horse parts -- one heat solve on the horse WELDED into one surface (vertices of different parts
    within WELD_M share one solve unknown: the parts are separate shells, a knee split between two
    parts must bend as one -- the skill's Phase 1d step 6);
  * tack -- rigid on its anchor (Head / Chest / Spine1), blended over 4 rings into the solve;
  * reins -- graded from the bit (Head) to the rein hand's place (Reins) by distance;
  * rider plates -- each part rigid on ONE bone, the nearest of those its rule allows (a plate shared
    between bones by distance bends like rubber; steel does not);
  * the shield on `Shield`, the lance on `Lance`.

Exec after royal_rig/common, royal_rig/labels, royal_rig/weights, cavalry_rig/common.
"""
import csv as _csv

WELD_M = 0.006
OLD = {"head": "R_Head", "chest": "R_Chest", "spine": "R_Spine", "hips": "R_Hips",
       "upperarm": "R_UpperArm", "forearm": "R_Forearm", "hand": "R_Hand",
       "thigh": "R_Thigh", "shin": "R_Shin", "foot": "R_Foot", "head_h": "Head", "horse_body": "Spine1"}


def old_bone(n):
    """cavalry_tripo's bone name -> this rig's (l / r -> .L / .R: the turn put the near side at +X)."""
    if n in OLD:
        return OLD[n]
    base_, side = n.rsplit("_", 1)
    return "%s.%s" % (OLD[base_], side.upper())


def part_table():
    with open(PARTS_CSV) as f:
        return {int(r["part"]): r for r in _csv.DictReader(f)}


def cav_roles():
    """part id -> (role, anchor bone or candidate list)."""
    out = {-1: ("rprop", "Shield"), -2: ("rprop", "Lance")}
    for p, r in part_table().items():
        g, w = r["group"], r["weights"]
        if g == "horse":
            out[p] = ("mount", None)
        elif w == "reins":
            out[p] = ("strap", None)
        elif g == "tack":
            out[p] = ("prop", "Chest" if w == "horse" else old_bone(w.split(":", 1)[1]))
        elif w.startswith("rigid:"):
            out[p] = ("plate", [old_bone(w.split(":", 1)[1])])
        else:
            out[p] = ("plate", [old_bone(x) for x in w.split(":", 1)[1].split("|")])
    return out


def cav_weights():
    o = mesh()
    arm = bpy.data.objects[RIG_NAME]
    bones = [b for b in arm.data.bones if b.use_deform]
    names = [b.name for b in bones]
    P = co(o)
    N = len(P)
    lab = read_int(o, "tripo_part")
    roles_ = cav_roles()
    missing = sorted(set(lab.tolist()) - set(roles_))
    if missing:
        raise SystemExit("parts with no role: %s" % missing)
    D = seg_dist(P, bones)
    W = np.zeros((N, len(bones)))
    region = np.array([{"mount": MOUNT, "prop": MOUNT, "strap": STRAP}.get(roles_[int(n)][0], RIDER) for n in lab])
    anchor = np.full(N, -1)
    for i, n in enumerate(lab):
        role, a = roles_[int(n)]
        if role in ("prop", "rprop"):
            anchor[i] = names.index(a)
    write_int(o, "region", region)
    write_int(o, "anchor", anchor)
    o.data.calc_loop_triangles()                  # the game mesh keeps some quads
    T_all = np.array([t.vertices[:] for t in o.data.loop_triangles])
    # --- the horse and its tack: one solve on the welded surface
    m_idx = np.nonzero(region == MOUNT)[0]
    m_bones = [j for j, n in enumerate(names) if not is_rider_bone(n) and n not in ("Reins", "Lance", "Shield")]
    rep = weld_reps(P, m_idx)
    Wm, its = solve_welded(P, m_idx, rep, m_bones, D, T_all, barrel_mask(P[m_idx], [names[j] for j in m_bones]))
    W[np.ix_(m_idx, m_bones)] = Wm
    # tack rigid on its anchor, blended over 4 rings from its border
    nb = neighbours(o.data)
    for j in sorted(set(anchor[(region == MOUNT) & (anchor >= 0)].tolist())):
        member = (anchor == j)
        ring = _rings(member, nb)
        a_ = np.minimum((ring + 1) / 5.0, 1.0)
        idx = np.nonzero(member)[0]
        one = np.zeros(len(bones)); one[j] = 1.0
        W[idx] = a_[idx, None] * one + (1 - a_[idx, None]) * W[idx]
    # --- rider plates: one bone each, the nearest its rule allows (part centroid to bone)
    chosen = {}
    for p in sorted(set(lab.tolist())):
        role, a = roles_[p]
        idx = np.nonzero(lab == p)[0]
        if role == "rprop":
            W[idx] = 0; W[idx, names.index(a)] = 1.0
        elif role == "plate":
            c = P[idx].mean(0)
            cand = [names.index(b) for b in a]
            dd = seg_dist(c[None, :], [bones[j] for j in cand])[0]
            j = cand[int(np.argmin(dd))]
            W[idx] = 0; W[idx, j] = 1.0
            chosen[p] = names[j]
    # --- reins: bit -> rein hand by distance, the last 15 % at each end rigid
    idx = np.nonzero(region == STRAP)[0]
    hb, rb = arm.data.bones["Head"], arm.data.bones["Reins"]
    bit = np.array(hb.tail_local) + (np.array(hb.head_local) - np.array(hb.tail_local)) * 0.25
    hand = np.array(rb.head_local)
    dh = np.linalg.norm(P[idx] - bit, axis=1); dr = np.linalg.norm(P[idx] - hand, axis=1)
    t = np.clip((np.clip(dh / np.maximum(dh + dr, 1e-6), 0, 1) - 0.15) / 0.7, 0, 1)
    W[idx] = 0
    W[idx, names.index("Head")] = 1 - t
    W[idx, names.index("Reins")] = t
    # --- prune, top 4, normalise
    W[W < 0.01] = 0
    order = np.argsort(-W, axis=1)
    keep = np.zeros_like(W, bool)
    np.put_along_axis(keep, order[:, :4], True, axis=1)
    W[~keep] = 0
    bare = np.nonzero(W.sum(1) < 1e-6)[0]
    for i in bare:
        j = int(np.argmin(D[i, m_bones]))
        W[i, m_bones[j]] = 1.0
    W /= W.sum(1, keepdims=True)
    write_groups(o, arm, names, W)
    return {"mount_iters": its, "welded": [len(m_idx), int(len(set(rep.tolist())))], "bare": len(bare),
            "plates": len(chosen), "reins_verts": int(len(idx))}


def weld_reps(P, idx):
    """Per vertex of `idx`, the index (into idx) of its weld representative within WELD_M."""
    kd = kdtree.KDTree(len(idx))
    for k, i in enumerate(idx):
        kd.insert(P[i], k)
    kd.balance()
    rep = -np.ones(len(idx), dtype=np.int64)
    for k, i in enumerate(idx):
        if rep[k] >= 0:
            continue
        for (_, j, _d) in kd.find_range(P[i], WELD_M):
            if rep[j] < 0:
                rep[j] = k
    return rep


def solve_welded(P_all, idx, rep, bone_ids, D, T_all, mask):
    """solve_region on the welded unknowns: triangles re-indexed to their corners' representatives."""
    uniq, inv = np.unique(rep, return_inverse=True)
    loc = -np.ones(len(P_all), dtype=np.int64)
    loc[idx] = inv
    inside = (loc[T_all] >= 0).all(1)
    T = loc[T_all[inside]]
    T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])]
    P = P_all[idx[uniq]]
    Dr = D[np.ix_(idx[uniq], bone_ids)].copy()
    Dr[~mask[uniq]] = np.inf
    dmin = Dr.min(1)
    near = (Dr <= dmin[:, None] * 1.0001 + 1e-6).astype(float)
    near /= np.maximum(near.sum(1, keepdims=True), 1e-9)
    I, J, Vv, area = _laplacian(P, T)
    n = len(uniq)
    MH = np.maximum(area, 1e-9) / np.maximum(dmin, 0.01) ** 2
    Lmv = _matvec(None, I, J, Vv, n)
    diagL = np.zeros(n)
    np.add.at(diagL, I[I == J], Vv[I == J])
    Wr, its = _pcg(lambda X: Lmv(X) + MH[:, None] * X, diagL + MH, MH[:, None] * near)
    return np.clip(Wr, 0, 1)[inv], its
