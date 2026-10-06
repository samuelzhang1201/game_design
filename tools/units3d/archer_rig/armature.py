"""Phase 3C: the custom armature `archer_rig`, from MEASURED joints (Phase 2). Frame (Gate 1): the
archer faces -Y, his left is +X, boots on z = 0, the helmet's crown at 1.85 m (the infantry's).

How each landmark was found (the skill's Phase 2):
  * arms -- centroids of the arm-labelled vertices every 4 cm of height (the right arm hangs) and,
    for the left forearm that comes forward to the bow, every 3 cm along -Y; the elbows where the
    centroid line turns, cross-checked on shots/grid_front_g.png and grid_side_g.png;
  * the left fist -- the vertices 1.4-6 cm from the bow's centreline at the grip (labels.py);
  * legs -- centroids of the lower-body vertices split at the body's centre x every 4 cm: ankles
    at the boots' narrowest (z 0.09), knees under the boot tops (z 0.47); the hips 0.43 m above
    (the coat hides them: a thigh as long as the shin, the pelvis 18 cm wide about x -0.04);
    the toes the sole points farthest from each ankle;
  * spine, neck, head -- the grid renders (the coat 0.29 m deep, the spine 2/3 back) and the
    head-labelled centroids every 4 cm (skull at x -0.04);
  * quiver -- the principal axis of the quiver-labelled vertices; scabbard likewise;
  * bow -- labels.bow_axis (the centreline, tip to tip); the string the line Phase 1c fitted
    (string_fit.txt) between the tips; the nock point on it level with the grip's top.
"""

V = Vector
CX = -0.04
HIPS = [(CX, 0.06, 0.92), (CX, 0.06, 1.05), (CX, 0.06, 1.22), (-0.035, 0.04, 1.42), (-0.035, 0.03, 1.53)]
HEAD_TOP = (-0.045, 0.03, 1.80)
ARMS = {   # clavicle root, shoulder, elbow, wrist, hand tip
    "L": [(0.0, 0.05, 1.40), (0.18, 0.07, 1.36), (0.27, 0.065, 1.10), (0.355, -0.15, 1.03), (0.37, -0.31, 1.0)],
    "R": [(-0.08, 0.05, 1.40), (-0.225, 0.04, 1.36), (-0.30, 0.04, 1.08), (-0.31, -0.01, 0.86), (-0.30, -0.06, 0.70)],
}
LEGS = {   # hip, knee, ankle (toe measured)
    "L": [(0.05, 0.06, 0.90), (0.095, 0.09, 0.47), (0.13, 0.105, 0.09)],
    "R": [(-0.13, 0.06, 0.90), (-0.18, 0.04, 0.47), (-0.205, 0.035, 0.09)],
}
GRIP_LO, GRIP_HI = 0.93, 1.07   # the grip's ends on the bow's centreline (the fist between)


def _axis_at(L, z):
    return V((float(np.interp(z, L[:, 2], L[:, 0])), float(np.interp(z, L[:, 2], L[:, 1])), z))


def string_line():
    cx, cy = eval(open(SRC + "string_fit.txt").read())
    return lambda z: V((cx[0] * z + cx[1], cy[0] * z + cy[1], z))


def toe(P, lab, ankle):
    S_ = P[(lab == ROLES.index("lower")) & (P[:, 2] < 0.04)]
    S_ = S_[np.linalg.norm(S_[:, :2] - np.array(ankle[:2]), axis=1) < 0.25]
    d = np.linalg.norm(S_[:, :2] - np.array(ankle[:2]), axis=1)
    t = S_[d.argmax()]
    return (float(t[0]), float(t[1]), 0.03)


def principal(Pp):
    c = Pp.mean(0)
    u = np.linalg.svd(Pp - c)[2][0]
    s = (Pp - c) @ u
    a, b = c + u * s.min(), c + u * s.max()
    return (a, b) if a[2] < b[2] else (b, a)        # low end first


def landmarks():
    o = mesh()
    P = co(o); lab = roles()
    L = bow_axis(lab, P)
    s = string_line()
    lm = {"toe.L": toe(P, lab, LEGS["L"][2]), "toe.R": toe(P, lab, LEGS["R"][2])}
    q0, q1 = principal(P[lab == ROLES.index("quiver")])
    sc0, sc1 = principal(P[lab == ROLES.index("scabbard")])
    lm.update({"quiver": (q0.tolist(), q1.tolist()), "scabbard": (sc1.tolist(), sc0.tolist()),   # scabbard hangs: top first
               "bow_bottom": L[0].tolist(), "bow_top": L[-1].tolist(),
               "grip_lo": _axis_at(L, GRIP_LO)[:], "grip_hi": _axis_at(L, GRIP_HI)[:],
               "nock": s(GRIP_HI)[:], "string_top": s(L[-1, 2])[:], "string_bottom": s(L[0, 2])[:]})
    return lm


def build():
    lm = landmarks()
    old = bpy.data.objects.get(RIG)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    arm = bpy.data.armatures.new(RIG)
    rig_ = bpy.data.objects.new(RIG, arm)
    coll("Archer_Rig").objects.link(rig_)
    activate(rig_)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones

    def B(n, h, t, par=None, con=False, deform=True, roll=None):
        b = eb.new(n); b.head = V(h); b.tail = V(t)
        if par:
            b.parent = eb[par]; b.use_connect = con
        b.use_deform = deform
        d = (b.tail - b.head).normalized()
        b.align_roll(V(roll) if roll else (V((0, -1, 0)) if abs(d.z) > 0.7 else V((0, 0, 1))))
        return b

    B("root", (0, 0, 0), (0, 0.3, 0), deform=False)
    B("Hips", HIPS[0], HIPS[1], "root")
    B("Spine", HIPS[1], HIPS[2], "Hips", True)
    B("Chest", HIPS[2], HIPS[3], "Spine", True)
    B("Neck", HIPS[3], HIPS[4], "Chest", True)
    B("head", HIPS[4], HEAD_TOP, "Neck", True)
    for sd in "LR":
        a = ARMS[sd]
        B("Clavicle." + sd, a[0], a[1], "Chest")
        B("UpperArm." + sd, a[1], a[2], "Clavicle." + sd, True)
        B("Forearm." + sd, a[2], a[3], "UpperArm." + sd, True)
        B("Hand." + sd, a[3], a[4], "Forearm." + sd, True)
        g = LEGS[sd]
        B("Thigh." + sd, g[0], g[1], "Hips")
        B("Shin." + sd, g[1], g[2], "Thigh." + sd, True)
        B("Foot." + sd, g[2], lm["toe." + sd], "Shin." + sd, True, roll=(0, 0, 1))
    q0, q1 = lm["quiver"]
    B("Quiver", q0, q1, "Chest")
    s0, s1 = lm["scabbard"]
    B("Scabbard", s0, s1, "Hips")
    B("Bow", lm["grip_lo"], lm["grip_hi"], "Hand.L")
    B("BowLimb.U", lm["grip_hi"], lm["bow_top"], "Bow")
    B("BowLimb.D", lm["grip_lo"], lm["bow_bottom"], "Bow")
    nock = V(lm["nock"]); grip = V(lm["grip_hi"])
    draw = (nock - grip).normalized()                         # the draw: from the grip back past the string
    B("String", nock, nock + draw * 0.05, "Bow")
    # the 76 cm arrow's REST lies along the string, inside the bow's own box: the runtime sizes and
    # spaces a piece by its rest mesh's box, and an arrow resting out past the grip spread the
    # formation (every clip poses Arrow outright, so its rest is only where it is bound)
    chord = (V(lm["string_top"]) - V(lm["string_bottom"])).normalized()
    a0 = nock - chord * 0.40
    B("Arrow", a0, a0 + chord * 0.76, "Bow")
    bpy.ops.object.mode_set(mode="OBJECT")
    col = arm.collections.new("Archer")
    for b in arm.bones:
        col.assign(b)
    return {k: (np.round(np.array(v, float), 3).tolist() if not isinstance(v, tuple) or not isinstance(v[0], list) else [np.round(x, 3).tolist() for x in v]) for k, v in lm.items()}


def bones_json(path):
    import json
    a = rig()
    json.dump([[b.name, list(b.head_local), list(b.tail_local), b.use_deform] for b in a.data.bones], open(path, "w"))
    return path
