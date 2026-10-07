"""Phase 1d + 4 for the courier: roles from `part` (every vertex carries its Tripo part id, the row of
tools/units3d/courier/tripo_parts.csv), then weights:

  * horse parts -- one heat solve on the horse WELDED into one surface (the cavalry's: its parts are
    separate shells, a joint split between two must bend as one), with the skill's 4e limits: a
    leg bone reaches only so far from its segment (faded past it, the weight handed to the torso
    bones), the belly never follows a leg below the scapula / hip, the tail bones only the tail,
    the neck and mane no leg bone;
  * saddle, cloth, leathers, stirrups, girth -- rigid on Spine1, blended over 4 rings into the solve;
  * breast collar and bridle -- the weights of the skin under them (the 6 nearest horse vertices),
    so a strap moves with the shoulder it lies on;
  * the reins -- found by geometry (one is a part, the other is welded into the bridle), graded from
    the bit (Head) to the hand end of ITS strand (Reins.L / Reins.R, picked per strand);
  * the rider -- a cloth coat, not plates: a heat solve per sub-group (the cavalry's king's masks):
    the coat split into its arms / torso / skirt by the normalised distance competition, the arms'
    edges to the rest cut; head, hands, hat rigid; the boots and breeches on the leg chain;
  * the staff on Pole; the pennant graded Pole -> Pennon1 -> Pennon2 down its fly, its hoist and
    the finial on Pole; the dispatch case and its strap on Case.

Exec after royal_rig/{common,labels,weights}, cavalry_rig/weights, courier_rig/{common,armature}.
"""
HORSE_PARTS = (1, 2, 3, 4, 6, 8, 16, 19, 22, 23, 28)
TACK_SPINE = (13, 17, 18, 20, 25, 27, 33, 34, 37, 39, 42)
TACK_SKIN = (9, 15)
RIGID = {26: "R_Head", 35: "R_Head", 12: "R_Head", 29: "R_Hand.R", 41: "R_Hand.R", 21: "R_Hand.R",
         32: "R_Hand.L", 38: "Pole", 5: "Case", 31: "Case"}
RIDER_SUB = {0: "coat", 36: "torso", 40: "head", 7: "lower", 14: "lower", 10: "lower", 24: "lower"}   # 36: the badge on his chest
REINS, PENNANT = 30, 11
SUB_BONES = {
    "lower": ("R_Hips", "R_Spine", "R_Thigh", "R_Shin", "R_Foot"),
    "torso": ("R_Hips", "R_Spine", "R_Chest", "R_Neck", "R_Clavicle", "R_UpperArm"),
    "skirt": ("R_Hips", "R_Spine"),
    "head": ("R_Neck", "R_Head", "R_Chest"),
    "arm": ("R_Chest", "R_Clavicle", "R_UpperArm", "R_Forearm", "R_Hand"),
}
SUBS = list(SUB_BONES)
SKIRT_Z = 1.45                    # the coat below this (and not an arm) hangs from the hips
RIDER_X = 0.02                    # the rider's own centreline
SLEEVE_R = 0.085                  # a sleeve's reach from its arm bone
TORSO_HALF_X = 0.165              # the coat's sides (front render), the arms outside them
TORSO_FRONT_Y = -0.21             # the coat's front; the forearms come forward before it
LEG_REACH = {"FrontScapula": 0.30, "HindThigh": 0.30}           # m; every other leg bone 0.20
LEG_BASES = ("FrontScapula", "FrontUpperArm", "FrontForearm", "FrontCannon", "FrontHoof",
             "HindThigh", "HindShin", "HindCannon", "HindHoof")
TORSO_BONES = ("Spine1", "Spine2", "Chest", "Pelvis", "Neck1")
BELLY = {"z_min": 0.80, "y": (-0.40, 0.22)}                    # between the elbows and the stifles
REIN_OFF_HEAD = 0.13              # a bridle vertex this far from the head / neck bones is a rein
SKIN_K = 6


def is_rider_bone(n):
    return n.startswith("R_") or n in ("Pole", "Pennon1", "Pennon2")


def is_prop_bone(n):
    return n in ("Pole", "Pennon1", "Pennon2", "Case", "Reins.L", "Reins.R")


def smooth_arr(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def rein_mask(P, lab, arm):
    """Part 30, and the bridle's vertices far from the head and the neck (the near rein)."""
    segs = [arm.data.bones[n] for n in ("Head", "Neck2", "Neck1")]
    d = seg_dist(P, segs).min(1)
    return (lab == REINS) | ((lab == 15) & (d > REIN_OFF_HEAD))


def strands(mask, nb):
    """Connected components of the masked vertices."""
    comp = -np.ones(len(mask), dtype=np.int64)
    k = 0
    for s in np.nonzero(mask)[0]:
        if comp[s] >= 0:
            continue
        st = [s]; comp[s] = k
        while st:
            i = st.pop()
            for j in nb[i]:
                if mask[j] and comp[j] < 0:
                    comp[j] = k; st.append(j)
        k += 1
    return comp, k


def coat_subs(P, idx, names, D):
    """The coat's vertices: 'arm' inside a sleeve -- within SLEEVE_R of an arm bone AND outside the
    torso's sides or before its front (the arms hang against the coat, so a plain distance
    competition took the coat's side panels for sleeves) -- else 'torso', or 'skirt' below SKIRT_Z."""
    armc = np.array([base(n) in ("R_UpperArm", "R_Forearm", "R_Hand") for n in names])
    xr, y = np.abs(P[idx, 0] - RIDER_X), P[idx, 1]
    is_arm = (D[np.ix_(idx, np.nonzero(armc)[0])].min(1) < SLEEVE_R) & ((xr > TORSO_HALF_X) | (y < TORSO_FRONT_Y))
    sub = np.where(is_arm, SUBS.index("arm"),
                   np.where(P[idx, 2] < SKIRT_Z, SUBS.index("skirt"), SUBS.index("torso")))
    return sub


def courier_roles(o, arm, names, D, P, lab, nb):
    """region (MOUNT / RIDER / STRAP), sub (rider sub-group), anchor (rigid bone or -1) per vertex."""
    N = len(P)
    region = np.full(N, MOUNT)
    sub = np.full(N, -1)
    anchor = np.full(N, -1)
    for p, b in RIGID.items():
        m = lab == p
        region[m] = RIDER if is_rider_bone(b) else MOUNT
        anchor[m] = names.index(b)
    for p in TACK_SPINE:
        anchor[lab == p] = names.index("Spine1")
    for p, s in RIDER_SUB.items():
        m = lab == p
        region[m] = RIDER
        if s != "coat":
            sub[m] = SUBS.index(s)
    coat = np.nonzero(lab == 0)[0]
    cs = coat_subs(P, coat, names, D)
    # neighbour majority over the coat, 3 passes (the arm / torso line follows the sleeve seam)
    s_all = np.full(N, -1); s_all[coat] = cs
    for _ in range(3):
        new = s_all.copy()
        for i in coat:
            ns = [j for j in nb[i] if s_all[j] >= 0]
            if not ns:
                continue
            vals, cnt = np.unique(s_all[ns], return_counts=True)
            k = np.argmax(cnt)
            if vals[k] != s_all[i] and cnt[k] > 0.6 * len(ns):
                new[i] = vals[k]
        s_all = new
    sub[coat] = s_all[coat]
    # the heads of the rigid rider parts take a sub-group too (their solve is overwritten)
    for p, b in RIGID.items():
        if is_rider_bone(b):
            sub[lab == p] = SUBS.index("arm" if "Hand" in b or b == "Pole" else "head")
    pen = lab == PENNANT
    region[pen] = RIDER; sub[pen] = SUBS.index("arm")
    rm = rein_mask(P, lab, arm)
    region[rm] = STRAP; anchor[rm] = -1
    return region, sub, anchor


def horse_mask(P, idx, lab, bnames, D_sub):
    """(len(idx), len(bnames)) bool: may the vertex follow the bone (skill 4e)."""
    m = np.ones((len(idx), len(bnames)), bool)
    L = lab[idx]
    tail_v = L == 2
    neckish = np.isin(L, (3, 22, 23, 28, 15))
    belly = (P[idx, 2] > BELLY["z_min"]) & (P[idx, 1] > BELLY["y"][0]) & (P[idx, 1] < BELLY["y"][1])
    for j, n in enumerate(bnames):
        b = base(n)
        if b.startswith("Tail"):
            m[~tail_v, j] = False
        elif tail_v.any():
            m[tail_v, j] = b in ("Pelvis", "Spine1")
        if b in LEG_BASES:
            m[neckish, j] = False
            m[D_sub[:, j] > LEG_REACH.get(b, 0.20), j] = False
            if b not in ("FrontScapula", "HindThigh"):
                m[belly, j] = False
    return m


def courier_weights():
    o = mesh()
    arm = rig()
    bones = [b for b in arm.data.bones if b.use_deform]
    names = [b.name for b in bones]
    P = co(o)
    N = len(P)
    lab = read_int(o, "part")
    D = seg_dist(P, bones)
    nb = neighbours(o.data)
    region, sub, anchor = courier_roles(o, arm, names, D, P, lab, nb)
    write_int(o, "region", region); write_int(o, "sub", sub); write_int(o, "anchor", anchor)
    o.data.calc_loop_triangles()
    T_all = np.array([t.vertices[:] for t in o.data.loop_triangles])
    W = np.zeros((N, len(bones)))
    rep_out = {}
    # --- the horse and its tack: one solve on the welded surface
    m_idx = np.nonzero(region == MOUNT)[0]
    m_bones = [j for j, n in enumerate(names) if not is_rider_bone(n) and not is_prop_bone(n)]
    mb_names = [names[j] for j in m_bones]
    rep = weld_reps(P, m_idx)
    mask = horse_mask(P, m_idx, lab, mb_names, D[np.ix_(m_idx, m_bones)])
    Wm, its = solve_welded(P, m_idx, rep, m_bones, D, T_all, mask)
    # leg reach: a smoothstep fade past each leg bone's reach, the weight handed to the torso
    torso = [k for k, n in enumerate(mb_names) if n in TORSO_BONES]
    Dm = D[np.ix_(m_idx, m_bones)]
    for k, n in enumerate(mb_names):
        b = base(n)
        if b not in LEG_BASES:
            continue
        lim = LEG_REACH.get(b, 0.20)
        f = 1 - smooth_arr((Dm[:, k] - (lim - 0.06)) / 0.10)
        moved = Wm[:, k] * (1 - f)
        Wm[:, k] *= f
        tw = Wm[:, torso]
        share = np.where(tw.sum(1, keepdims=True) > 1e-6, tw / np.maximum(tw.sum(1, keepdims=True), 1e-9),
                         (Dm[:, torso] == Dm[:, torso].min(1, keepdims=True)).astype(float))
        Wm[:, torso] += moved[:, None] * share / np.maximum(share.sum(1, keepdims=True), 1e-9)
    W[np.ix_(m_idx, m_bones)] = Wm
    rep_out["mount"] = [len(m_idx), int(len(set(rep.tolist()))), its]
    # tack rigid on Spine1, blended over 4 rings from its border
    j1 = names.index("Spine1")
    member = np.isin(lab, TACK_SPINE)
    ring = _rings(member, nb)
    a_ = np.minimum((ring + 1) / 5.0, 1.0)
    idx = np.nonzero(member)[0]
    one = np.zeros(len(bones)); one[j1] = 1.0
    W[idx] = a_[idx, None] * one + (1 - a_[idx, None]) * W[idx]
    # breast collar and bridle: the skin's weights under them (lower-leg skin excluded)
    skin = np.isin(lab, HORSE_PARTS) & (P[:, 2] > 0.70)
    s_idx = np.nonzero(skin)[0]
    kd = kdtree.KDTree(len(s_idx))
    for k, i in enumerate(s_idx):
        kd.insert(P[i], k)
    kd.balance()
    t_idx = np.nonzero(np.isin(lab, TACK_SKIN) & (region == MOUNT))[0]
    for i in t_idx:
        hits = kd.find_n(P[i], SKIN_K)
        w = np.array([1.0 / max(d, 1e-3) for (_, _, d) in hits])
        W[i] = (w[:, None] * W[[s_idx[k] for (_, k, _) in hits]]).sum(0) / w.sum()
    # --- the rider: heat per sub-group, opposite-side limbs blocked, the arms' edges cut
    r_idx = np.nonzero(region == RIDER)[0]
    r_bones = [j for j, n in enumerate(names) if n.startswith("R_")]
    rmask = np.zeros((len(r_idx), len(r_bones)), bool)
    xr = P[:, 0] - RIDER_X
    for a, i in enumerate(r_idx):
        allowed = SUB_BONES[SUBS[sub[i]]] if sub[i] >= 0 else SUB_BONES["torso"]
        for b, j in enumerate(r_bones):
            n = names[j]
            ok = base(n) in allowed
            if ok and n.endswith((".L", ".R")) and abs(xr[i]) > 0.08:
                ok = n.endswith(".L") == (xr[i] > 0)
            rmask[a, b] = ok
    side = np.sign(xr)
    is_arm = (region == RIDER) & (sub == SUBS.index("arm"))
    rest_ = (region == RIDER) & ~is_arm
    # only the forearms' and hands' welded contacts are cut (where they lie on the coat's front or
    # the thighs); the sleeve and the coat meet at the shoulder as ONE cloth and stay joined
    fore = np.array([base(n) in ("R_Forearm", "R_Hand") for n in names])
    upper = np.array([base(n) == "R_UpperArm" for n in names])
    lower_arm = is_arm & (D[:, fore].min(1) < D[:, upper].min(1))

    def cut(a, b):
        x = (lower_arm[a] & rest_[b]) | (rest_[a] & lower_arm[b])
        x |= is_arm[a] & is_arm[b] & (side[a] != side[b]) & (np.abs(xr[a]) > 0.05) & (np.abs(xr[b]) > 0.05)
        return x
    Wr, its, _ = solve_region(r_idx, r_bones, D, T_all, mask=rmask, cut=cut)
    W[np.ix_(r_idx, r_bones)] = Wr
    rep_out["rider_iters"] = its
    # rigid rider parts and props (they are separate shells: no ring blend needed)
    for p, b in RIGID.items():
        m = lab == p
        W[m] = 0; W[m, names.index(b)] = 1.0
    # the pennant: hoist and finial on Pole; the fly graded down Pole -> Pennon1 -> Pennon2
    pb = arm.data.bones["Pole"]
    pi = np.nonzero(lab == PENNANT)[0]
    dp = seg_dist(P[pi], [pb])[:, 0]
    s = np.clip((arm.data.bones["Pennon1"].head_local.z - P[pi, 2]) / 0.42, 0, 1)
    jp, j1_, j2_ = names.index("Pole"), names.index("Pennon1"), names.index("Pennon2")
    zw = np.zeros((len(pi), len(bones)))
    lo = s < 0.5
    zw[lo, jp] = 1 - 2 * s[lo]; zw[lo, j1_] = 2 * s[lo]
    zw[~lo, j1_] = 2 - 2 * s[~lo]; zw[~lo, j2_] = 2 * s[~lo] - 1
    a_ = smooth_arr((dp - 0.01) / 0.06)[:, None]
    one = np.zeros(len(bones)); one[jp] = 1.0
    W[pi] = (1 - a_) * one + a_ * zw
    # --- the reins: bit -> the hand end of each strand, the last 15 % at each end rigid
    st_mask = region == STRAP
    comp, nk = strands(st_mask, nb)
    hb = arm.data.bones["Head"]
    bit = np.array(hb.tail_local) + (np.array(hb.head_local) - np.array(hb.tail_local)) * 0.25
    hands = {s_: np.array(arm.data.bones["Reins." + s_].head_local) for s_ in "LR"}
    used = {"L": 0, "R": 0}
    for k in range(nk):
        idx = np.nonzero(comp == k)[0]
        far = P[idx[np.argmax(np.linalg.norm(P[idx] - bit, axis=1))]]
        s_ = min("LR", key=lambda q: np.linalg.norm(far - hands[q]))
        used[s_] += len(idx)
        hand = hands[s_]
        dh = np.linalg.norm(P[idx] - bit, axis=1); dr = np.linalg.norm(P[idx] - hand, axis=1)
        t = np.clip((np.clip(dh / np.maximum(dh + dr, 1e-6), 0, 1) - 0.15) / 0.7, 0, 1)
        W[idx] = 0
        W[idx, names.index("Head")] = 1 - t
        W[idx, names.index("Reins." + s_)] = t
    rep_out["reins"] = {"strands": nk, **used}
    # --- prune, top 4, normalise; a bare vertex -> its region's nearest bone
    W[W < 0.01] = 0
    order = np.argsort(-W, axis=1)
    keep = np.zeros_like(W, bool)
    np.put_along_axis(keep, order[:, :4], True, axis=1)
    W[~keep] = 0
    bare = np.nonzero(W.sum(1) < 1e-6)[0]
    for i in bare:
        cols = r_bones if region[i] == RIDER else m_bones
        W[i, cols[int(np.argmin(D[i, cols]))]] = 1.0
    W /= W.sum(1, keepdims=True)
    write_groups(o, arm, names, W)
    np.save(SRC + "weights.npy", W)
    rep_out.update(bare=len(bare), rider=int(len(r_idx)),
                   coat={k: int(((lab == 0) & (sub == SUBS.index(k))).sum()) for k in ("arm", "torso", "skirt")})
    return rep_out


def courier_numeric():
    """The royal gates (zero weight, > 4, unnormalised) and the cross-region leak: a rider vertex
    (not a prop) with any horse bone, or a horse vertex with any rider bone."""
    o = mesh()
    names = {g.index: g.name for g in o.vertex_groups}
    region = read_int(o, "region")
    zero = over4 = unnorm = leak = 0
    for v in o.data.vertices:
        ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 1e-6]
        s = sum(w for _, w in ws)
        zero += not ws
        over4 += len(ws) > 4
        unnorm += bool(ws) and abs(s - 1) > 0.02
        r = region[v.index]
        if r == RIDER and any(not is_rider_bone(n) for n, _ in ws):
            leak += 1
        if r == MOUNT and any(is_rider_bone(n) for n, _ in ws):
            leak += 1
    return {"zero_weight": zero, "over_4": over4, "not_normalised": unnorm, "cross_region_leak": leak}


def label_map():
    """Debug colours: horse grey, Spine1 tack yellow, skin tack orange, reins red (L) / magenta (R),
    coat arm cyan / torso blue / skirt violet, head green, lower teal, rigid rider pink, pennant."""
    o = mesh()
    lab, region, sub, anchor = read_int(o, "part"), read_int(o, "region"), read_int(o, "sub"), read_int(o, "anchor")
    C = np.full((len(lab), 3), 0.6)
    C[np.isin(lab, TACK_SPINE)] = (0.95, 0.8, 0.1)
    C[np.isin(lab, TACK_SKIN) & (region == MOUNT)] = (1.0, 0.5, 0.1)
    subc = {"arm": (0.1, 0.85, 0.9), "torso": (0.15, 0.3, 0.95), "skirt": (0.55, 0.3, 0.9),
            "head": (0.2, 0.8, 0.3), "lower": (0.1, 0.55, 0.5)}
    for k, c in subc.items():
        C[(region == RIDER) & (sub == SUBS.index(k))] = c
    C[(region == RIDER) & (anchor >= 0)] = (1.0, 0.5, 0.7)
    C[lab == PENNANT] = (0.9, 0.2, 0.9)
    C[region == STRAP] = (0.9, 0.1, 0.1)
    return paint(C)
