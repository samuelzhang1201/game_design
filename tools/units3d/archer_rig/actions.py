"""The archer's five clips (owner 2026-10-06), keyed on `archer_rig` at 30 fps from frame 0, every
frame (the pose of each frame is SOLVED from smooth parameter tracks, the blender-natural-animation
skill's "generate it, don't pose it"):

  MARCH     行进 -- a run, 24 f (two steps of 1 m), after the owner's 8-phase sheet, the left arm hanging in a J and swinging, the bow tilted forward-down
  GARRISON  驻防 -- side-on, an arrow on the string: half draw -> full draw -> hold -> let down, 150 f
  ATTACK    攻击 -- shooting without pause: arrow from the quiver, nock, raise, draw, loose, 48 f
  DEFEND    防御 -- crouched behind the bow held crosswise before the face, a flinch at f 40, 80 f
  STANDBY   待命 -- the bow stood on its lower tip, both hands resting on it, at ease, 150 f
  (all loops; in place -- the map moves the piece; the runtime matches MARCH to the ground by stride_m)

A frame's pose is built from CHANNELS (body frame: the archer's own, his front -Y, his left +X,
metres and degrees), each a periodic monotone cubic (PCHIP) through keys, or a function of the
frame, each with an optional lag in frames (overlap down the chains):

  root_yaw           the whole figure turned about up (+ turns his front toward his left)
  hips_off, hips_rot hips moved (x, y, z) and turned (pitch fwd +, roll, yaw) about their head
  spine/chest/neck/head, clav_l/clav_r   local Euler (x pitch fwd +, y twist toward his left +, z)
  foot_l, foot_r     ankle (x, y, z), toe pitch down +, toe yaw toward his left +
  bow_g | bow_sh     the grip: a body-frame point, or an offset from the posed left shoulder
  bow_chord, bow_draw   the chord's direction (bottom tip -> top tip), the side
                     the string is on; the left arm is SOLVED to hold the bow there (it rides in
                     the fist: Bow is a child of Hand.L)
  l_pole, r_pole     where the elbows point
  rh_body, rh_bowd, rh_w   the right hand's hook point: a body-frame point, or the string drawn to
                     a fraction of the full 0.72 m draw; rh_w blends body (0) -> string (1)
  rh_dir             wrist -> fingers;  rfk = (shoulder pitch, elbow bend) replaces the IK (the run)
  hook               how much the string follows the hand (1 = drawn by it)
  arrow              "off" | "hand" | "nock" per frame range; arrow_dir for "hand"
  quiver, scab       local Euler of the quiver / the scabbard (secondary)
The limbs bend with the draw: BowLimb.U / .D turned so each tip comes BEND_DEG toward the string at
the full draw.
"""
import math
from mathutils import Euler, Quaternion

FPS = 30
PREFIX = "archer_"
DRAW_LEN = 0.72          # a longbow's full draw, grip to nock
BEND_DEG = 9.0           # each limb's turn at the full draw
HOOK = 0.085             # wrist -> the fingers' hook on the string
ARROW_REST = 0.035       # the arrow lies on the fist, this far up the chord from the grip's middle
ARROW_SIDE = 0.012       # ... and this far to the side of the bow


# ------------------------------------------------------------------ tracks ----

def _pchip_slopes(x, y):
    h = np.diff(x); d = np.diff(y, axis=0) / h[:, None]
    m = np.zeros_like(y)
    for i in range(1, len(x) - 1):
        a, b = d[i - 1], d[i]
        w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
        m[i] = np.where(a * b > 0, (w1 + w2) / (w1 / np.where(a == 0, 1, a) + w2 / np.where(b == 0, 1, b)), 0)
    m[0], m[-1] = d[0], d[-1]
    return m


def track(keys, N, lag=0.0):
    """A periodic (period N) monotone cubic through keys [(frame, value | tuple)], read at t - lag."""
    ks = sorted(keys)
    xs = [f for f, _ in ks]
    ys = [np.atleast_1d(np.array(v, float)) for _, v in ks]
    X = np.array([x - N for x in xs] + xs + [x + N for x in xs], float)
    Y = np.array(ys * 3)
    keep = np.concatenate([[True], np.diff(X) > 1e-9])
    X, Y = X[keep], Y[keep]
    M = _pchip_slopes(X, Y)
    scalar = all(np.ndim(v) == 0 for _, v in ks)

    def f(t):
        t = (t - lag) % N
        i = int(np.searchsorted(X, t, side="right") - 1)
        i = min(max(i, 0), len(X) - 2)
        h = X[i + 1] - X[i]; s = (t - X[i]) / h
        h00, h10, h01, h11 = 2 * s ** 3 - 3 * s ** 2 + 1, s ** 3 - 2 * s ** 2 + s, -2 * s ** 3 + 3 * s ** 2, s ** 3 - s ** 2
        v = h00 * Y[i] + h10 * h * M[i] + h01 * Y[i + 1] + h11 * h * M[i + 1]
        return float(v[0]) if scalar else Vector(v.tolist())
    return f


def ranges(spec, N):
    """[(start_frame, value)] -> f(t): the value of the last start <= t (periodic)."""
    sp = sorted(spec)

    def f(t):
        t = t % N
        v = sp[-1][1]
        for s, val in sp:
            if t >= s:
                v = val
        return v
    return f


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ rest data ----

class Rest:
    """Rest-pose facts the solver needs, read once from the armature."""

    def __init__(self):
        a = rig()
        B = a.data.bones
        self.M = {b.name: b.matrix_local.copy() for b in B}
        self.len = {b.name: b.length for b in B}
        self.hips_head = B["Hips"].head_local.copy()
        self.grip = (B["Bow"].head_local + B["Bow"].tail_local) / 2
        top, bot = B["BowLimb.U"].tail_local, B["BowLimb.D"].tail_local
        self.chord = (top - bot).normalized()
        nock = B["String"].head_local.copy()
        v = nock - self.grip
        self.draw = (v - self.chord * v.dot(self.chord)).normalized()
        self.brace = v.dot(self.draw)
        self.nock = nock
        self.nock_along = v.dot(self.chord)
        self.F0 = Matrix((self.draw, self.chord, self.draw.cross(self.chord))).transposed()
        self.ankle = {s: B["Foot." + s].head_local.copy() for s in "LR"}
        self.footdir = {s: (B["Foot." + s].tail_local - B["Foot." + s].head_local) for s in "LR"}
        self.tip0 = {k: B[k].tail_local.copy() for k in ("BowLimb.U", "BowLimb.D")}
        self.quiver_top = B["Quiver"].tail_local.copy()
        self.quiver_dir = (B["Quiver"].tail_local - B["Quiver"].head_local).normalized()
        fa = (B["Forearm.L"].tail_local - B["Forearm.L"].head_local).normalized()
        self.dev_axis = fa.cross(self.chord).normalized()      # the wrist's side bend turns the bow about this


def frame_of(chord, draw):
    c = Vector(chord).normalized()
    d = Vector(draw); d = (d - c * d.dot(c)).normalized()
    return Matrix((d, c, d.cross(c))).transposed()


# ------------------------------------------------------------------ pose ops ----

def _upd():
    bpy.context.view_layer.update()


def reset(a=None):
    a = a or rig()
    for pb in a.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))
    _upd()


def rot_local(pb, xyz):
    q = Euler([math.radians(v) for v in xyz]).to_quaternion()
    pb.rotation_quaternion = pb.rotation_quaternion @ q


def aim(pb, d, twist=0.0):
    M = pb.matrix.copy()
    y = M.to_3x3().col[1].normalized()
    R = y.rotation_difference(Vector(d).normalized()).to_matrix() @ M.to_3x3()
    if twist:
        R = Matrix.Rotation(twist, 3, Vector(d).normalized()) @ R
    N = R.to_4x4(); N.translation = M.translation
    pb.matrix = N
    _upd()


PREV_W = {}       # the last bend plane per chain: a pole nearly along the reach keeps it (no flip)
W_RATE = 15.0     # the bend plane turns at most this many degrees a frame about the reach


def set_frame(pb, y, xhint):
    """The bone's pose matrix from its axis `y` and a hint for its local X (its hinge, given the
    rolls armature.py sets); the head stays where the parent puts it. Twist is thereby FIXED, not
    left to a shortest rotation (an elbow flipped 176 deg in one frame that way)."""
    Y = Vector(y).normalized()
    X = Vector(xhint); X = (X - Y * X.dot(Y))
    X = X.normalized() if X.length > 1e-6 else Y.orthogonal().normalized()
    Z = X.cross(Y)
    M = Matrix((X, Y, Z)).transposed().to_4x4()
    M.translation = pb.head.copy()
    pb.matrix = M
    _upd()


def two_bone(a, up, lo, target, pole, sign=1.0):
    """Analytic two-bone IK: `up` and `lo` aimed so lo's tail reaches `target` (armature space),
    the middle joint toward `pole`; each bone's X set to the hinge, cross(axis, pole) * sign (+1
    a knee, -1 an elbow: the rest X of both points to the body's right). Returns the overshoot (m)."""
    A = a.pose.bones[up].head.copy()
    l1, l2 = a.data.bones[up].length, a.data.bones[lo].length
    T = Vector(target)
    d = T - A
    over = max(0.0, d.length - (l1 + l2) * 0.999)
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.999)
    u = d.normalized()
    x = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = Vector(pole).normalized()
    w = p - u * p.dot(u)
    prev = PREV_W.get(up)
    if prev is not None:
        pv = prev - u * prev.dot(u)
        if w.length < 0.35 and pv.length > 1e-6:          # the pole nearly along the reach: hold the plane
            k = w.length / 0.35
            w = w * k + pv.normalized() * (1 - k)
        if w.length > 1e-6 and pv.length > 1e-6:          # and never turn it faster than W_RATE a frame
            wn, pn = w.normalized(), pv.normalized()
            ang = wn.angle(pn)
            if ang > math.radians(W_RATE):
                w = pn.slerp(wn, math.radians(W_RATE) / ang) if hasattr(pn, "slerp") else pn.lerp(wn, math.radians(W_RATE) / ang)
    w = w.normalized() if w.length > 1e-6 else u.orthogonal().normalized()
    PREV_W[up] = w.copy()
    E = A + u * x + w * h
    T2 = A + u * dist
    hinge = (E - A).normalized().cross(w) * sign
    set_frame(a.pose.bones[up], E - A, hinge)
    set_frame(a.pose.bones[lo], T2 - E, hinge)
    return over


def twist_of(a, up, lo, R):
    """The lower bone's twist (rad) about its own axis against the upper, from their rest relation."""
    pb = a.pose.bones
    rel = pb[up].matrix.to_3x3().inverted() @ pb[lo].matrix.to_3x3()
    rel0 = R.M[up].to_3x3().inverted() @ R.M[lo].to_3x3()
    q = (rel0.inverted() @ rel).to_quaternion()
    return 2 * math.atan2(q.y, q.w)


def untwist(a, up, lo, R):
    """Turn the lower bone about its own axis so it carries no twist against the upper (a hinge set
    by two_bone may sit at another roll than the rest's: a candy-wrapper elbow)."""
    pl = a.pose.bones[lo]
    tw = twist_of(a, up, lo, R)
    M = pl.matrix.copy()
    N = (Matrix.Rotation(-tw, 3, M.to_3x3().col[1].normalized()) @ M.to_3x3()).to_4x4()
    N.translation = M.translation
    pl.matrix = N
    _upd()


def euler_m(xyz):
    return Euler([math.radians(v) for v in xyz], "XYZ").to_matrix().to_4x4()


# ------------------------------------------------------------------ the solver ----

def apply_pose(ch, t, R):
    """Pose `archer_rig` for frame t from the channels; returns diagnostics."""
    a = rig()
    reset(a)
    pb = a.pose.bones
    g = lambda k, d=None: ch[k](t) if k in ch else d
    # root: the turn about up and the bob
    yaw = g("root_yaw", 0.0)
    rootM = Matrix.Translation((0, 0, g("root_z", 0.0))) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    pb["root"].matrix = rootM @ R.M["root"]
    _upd()
    Bm = rootM                                       # body frame -> armature space
    Bd = Bm.to_3x3()
    W = lambda p: Bm @ Vector(p)
    Wd = lambda d: Bd @ Vector(d)
    # hips
    off = Vector(g("hips_off", (0, 0, 0)))
    hr = g("hips_rot", Vector((0, 0, 0)))
    Rh = Matrix.Rotation(math.radians(hr[2]), 4, "Z") @ Matrix.Rotation(math.radians(hr[1]), 4, "Y") @ Matrix.Rotation(math.radians(hr[0]), 4, "X")
    h0 = R.hips_head
    pb["Hips"].matrix = Bm @ Matrix.Translation(off) @ Matrix.Translation(h0) @ Rh @ Matrix.Translation(-h0) @ R.M["Hips"]
    _upd()
    for k, b in (("spine", "Spine"), ("chest", "Chest"), ("neck", "Neck"), ("head", "head"),
                 ("clav_l", "Clavicle.L"), ("clav_r", "Clavicle.R"), ("quiver", "Quiver"), ("scab", "Scabbard")):
        if k in ch:
            rot_local(pb[b], ch[k](t))
    _upd()
    over = {}
    # legs
    for s, k in (("L", "foot_l"), ("R", "foot_r")):
        f = ch[k](t)
        ank = W((f[0], f[1], f[2]))
        fd = R.footdir[s]
        yawf = f[4] if len(f) > 4 else 0.0
        fd = Matrix.Rotation(math.radians(yawf), 3, "Z") @ fd
        lat = Vector((0, 0, 1)).cross(fd).normalized()
        fd = Matrix.Rotation(math.radians(f[3]), 3, lat) @ fd       # toe down + (lat = up x toe: +X for a toe ahead)
        fwd = Vector((fd.x, fd.y, 0)).normalized()
        over["leg." + s] = two_bone(a, "Thigh." + s, "Shin." + s, ank, Wd(fwd + Vector((0, 0, 0.15))))
        set_frame(pb["Foot." + s], Wd(fd), pb["Shin." + s].matrix.to_3x3().col[0])
    # the bow, and the left arm holding it
    if "l_wrist" in ch:
        # the arm leads (the run's hanging arm): the wrist placed from the shoulder, the hand kept at
        # its rest angle to the forearm (no twist) but for a side bend of the wrist, l_dev degrees
        # (- tips the bow's upper tip down), at most DEV_MAX
        wr = pb["UpperArm.L"].head + Wd(g("l_wrist"))
        over["arm.L"] = two_bone(a, "UpperArm.L", "Forearm.L", wr, Wd(g("l_pole", (0.3, 0.6, -1))), -1.0)
        untwist(a, "UpperArm.L", "Forearm.L", R)
        # pronation (+ turns the thumb in), as the forearm does it: along its length, half of it
        # showing at the elbow end of the bone and half at the wrist
        pr = math.radians(g("l_pron", 0.0))
        pf = pb["Forearm.L"]; Mf_ = pf.matrix.copy(); fax = Mf_.to_3x3().col[1].normalized()
        Nf = (Matrix.Rotation(0.5 * pr, 3, fax) @ Mf_.to_3x3()).to_4x4(); Nf.translation = Mf_.translation
        pf.matrix = Nf
        _upd()
        Rf = Matrix.Rotation(0.5 * pr, 3, fax) @ pb["Forearm.L"].matrix.to_3x3() @ R.M["Forearm.L"].to_3x3().inverted()   # rest -> posed
        Rh0 = Rf @ R.M["Hand.L"].to_3x3()
        ax = (Rf @ R.dev_axis).normalized()
        dev = max(-math.radians(DEV_MAX), min(math.radians(DEV_MAX), math.radians(g("l_dev", 0.0))))
        DEV_SEEN.append(math.degrees(dev))
        M_hand = (Matrix.Rotation(dev, 3, ax) @ Rh0).to_4x4()
        M_hand.translation = pb["Hand.L"].head.copy()
        pb["Hand.L"].matrix = M_hand
        _upd()
        bowT = M_hand @ R.M["Hand.L"].inverted()                              # rest bow -> posed bow
        M_bow = bowT @ R.M["Bow"]                     # (the bow never turns in the fist: welded, it tears)
    else:
        Gd = W(g("bow_g"))
        Fd = frame_of(Wd(g("bow_chord")), Wd(g("bow_draw")))
        Rb = (Fd @ R.F0.transposed()).to_4x4()
        bowT = Matrix.Translation(Gd) @ Rb @ Matrix.Translation(-R.grip)      # rest bow -> posed bow
        M_bow = bowT @ R.M["Bow"]
        M_hand = M_bow @ R.M["Bow"].inverted() @ R.M["Hand.L"]
        over["arm.L"] = two_bone(a, "UpperArm.L", "Forearm.L", M_hand.translation, Wd(g("l_pole", (0.3, 0.6, -1))), -1.0)
        _hand(a, "Forearm.L", "Hand.L", M_hand, R)
    # the right hand
    if "rfk" in ch:
        sp, el = ch["rfk"](t)[0], ch["rfk"](t)[1]
        rot_local(pb["UpperArm.R"], (sp, 0, 0)); _upd()
        rot_local(pb["Forearm.R"], (el, 0, 0)); _upd()
        hook_pt = pb["Hand.R"].head + (pb["Hand.R"].tail - pb["Hand.R"].head).normalized() * HOOK
        over["arm.R"] = 0.0
    else:
        w = g("rh_w", 0.0)
        pb_ = W(g("rh_body", (0, 0, 0))) if w < 1 else Vector()
        fdraw = g("rh_bowd", 0.0)
        ps = bowT @ (R.grip + R.draw * (R.brace + (DRAW_LEN - R.brace) * fdraw) + R.chord * R.nock_along)
        hook_pt = pb_.lerp(ps, w) if w < 1 else ps
        dh = Wd(g("rh_dir", (0, -1, 0))).normalized()
        wrist = hook_pt - dh * HOOK
        over["arm.R"] = two_bone(a, "UpperArm.R", "Forearm.R", wrist, Wd(g("r_pole", (-1, 0.5, -0.5))), -1.0)
        set_frame(pb["Hand.R"], dh, pb["Forearm.R"].matrix.to_3x3().col[0])
    # the string, drawn by the hand as far as it is hooked
    nock_rest = bowT @ R.nock
    hook = min(1.0, max(0.0, g("hook", 0.0)))
    nock = nock_rest.lerp(hook_pt, hook)
    Ms = M_bow @ R.M["Bow"].inverted() @ R.M["String"]
    Ms.translation = nock
    pb["String"].matrix = Ms
    _upd()
    # the limbs bend toward the string with the draw
    drawn = max(0.0, min(1.0, ((nock - nock_rest).length) / (DRAW_LEN - R.brace)))
    for b, sgn in SIGNS.items():
        rot_local(pb[b], (sgn * BEND_DEG * drawn, 0, 0))
    _upd()
    # the arrow
    mode = g("arrow", "off")
    Ma = R.M["Arrow"].copy()
    if mode == "nock":
        rest_pt = bowT @ (R.grip + R.chord * ARROW_REST + R.draw.cross(R.chord) * ARROW_SIDE)
        d = (rest_pt - nock).normalized()
        head = nock
    elif mode == "hand":
        d = Wd(g("arrow_dir", (1, 0, 0))).normalized()
        head = hook_pt
    else:
        d = (R.M["Arrow"].to_3x3().col[1]).normalized(); head = nock
    y0 = Ma.to_3x3().col[1].normalized()
    Rr = y0.rotation_difference(d).to_matrix() @ Ma.to_3x3()
    N = Rr.to_4x4(); N.translation = head
    pb["Arrow"].matrix = N
    _upd()
    if mode == "off":
        pb["Arrow"].scale = (0.001, 0.001, 0.001)
    _upd()
    return {k: round(v, 3) for k, v in over.items() if v > 0.005}


def _hand(a, fore, hand, M_hand, R):
    """Set the hand to M_hand's rotation, the forearm taking half the twist about its own axis
    (no candy-wrapper wrist)."""
    pf, ph = a.pose.bones[fore], a.pose.bones[hand]
    Q0 = R.M[fore].to_3x3().inverted() @ R.M[hand].to_3x3()
    Rf = pf.matrix.to_3x3()
    D = (Rf @ Q0).inverted() @ M_hand.to_3x3()
    q = D.to_quaternion()
    tw = 2 * math.atan2(q.y, q.w)
    if tw > math.pi:
        tw -= 2 * math.pi
    axis = Rf.col[1].normalized()
    M = pf.matrix.copy()
    N = (Matrix.Rotation(0.5 * tw, 3, axis) @ M.to_3x3()).to_4x4(); N.translation = M.translation
    pf.matrix = N
    _upd()
    Mh = M_hand.copy(); Mh.translation = ph.head.copy()
    ph.matrix = Mh
    _upd()


SIGNS = {}


def calibrate():
    """Which way BowLimb.U / .D turn to bring their tips toward the string."""
    a = rig(); R = Rest()
    for b in ("BowLimb.U", "BowLimb.D"):
        reset(a)
        rot_local(a.pose.bones[b], (5, 0, 0)); _upd()
        moved = a.pose.bones[b].tail - R.tip0[b]
        SIGNS[b] = 1.0 if moved.dot(R.draw) > 0 else -1.0
    reset(a)
    return dict(SIGNS)


# ------------------------------------------------------------------ keying ----

def new_action(a, name):
    ad = a.animation_data or a.animation_data_create()
    old = bpy.data.actions.get(PREFIX + name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(PREFIX + name)
    act.use_fake_user = True
    ad.action = act
    return act


def bake(name, ch, N, R=None):
    """Key every bone at every frame 0..N (frame N = frame 0: the loop closes)."""
    a = rig(); R = R or Rest()
    if not SIGNS:
        calibrate()
    act = new_action(a, name)
    PREV_W.clear()
    for f in range(N):                         # a whole cycle first: the bend memory warm, the loop closed
        apply_pose(ch, float(f), R)
    worst = {}
    for f in range(N + 1):
        o = apply_pose(ch, float(f), R)
        for k, v in o.items():
            worst[k] = max(worst.get(k, 0), v)
        for pb in a.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("scale", frame=f)
    quat_hemisphere(act)
    for fc in fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    a.animation_data.action = None
    reset(a)
    return {"clip": name, "frames": N, "unreached_m": worst}


def fcurves(act):
    fcs = getattr(act, "fcurves", None)
    if fcs is None or len(fcs) == 0:
        fcs = [fc for l in act.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
    return fcs


def quat_hemisphere(act):
    byb = {}
    for fc in fcurves(act):
        if fc.data_path.endswith("rotation_quaternion"):
            byb.setdefault(fc.data_path, {})[fc.array_index] = fc
    for fcs in byb.values():
        if len(fcs) != 4:
            continue
        prev = None
        for i in range(len(fcs[0].keyframe_points)):
            q = [fcs[c].keyframe_points[i].co[1] for c in range(4)]
            if prev is not None and sum(x * y for x, y in zip(q, prev)) < 0:
                for c in range(4):
                    fcs[c].keyframe_points[i].co[1] = -q[c]
                q = [-v for v in q]
            prev = q
        for c in range(4):
            fcs[c].update()


def show(name, frame):
    a = rig()
    a.animation_data_create()
    a.animation_data.action = bpy.data.actions[PREFIX + name]
    bpy.context.scene.frame_set(int(frame))


# ------------------------------------------------------------------ the clips ----

def _rest_feet(R, dx_l=0.0, dx_r=0.0, dy_l=0.0, dy_r=0.0, dz=0.0):
    L, Rr = R.ankle["L"], R.ankle["R"]
    return (L.x + dx_l, L.y + dy_l, L.z + dz, 0.0, 0.0), (Rr.x + dx_r, Rr.y + dy_r, Rr.z + dz, 0.0, 0.0)


def hermite(keys, m0, m1):
    """A cubic Hermite through keys [(q, vector)] on q in [0, 1], the end slopes given (per unit q)
    so a swing joins its stance with no step in velocity; interior slopes the weighted three-point
    derivative."""
    q = [k for k, _ in keys]
    y = [np.array(v, float) for _, v in keys]
    m = [np.array(m0, float)]
    for i in range(1, len(q) - 1):
        a, b = q[i] - q[i - 1], q[i + 1] - q[i]
        m.append(((y[i + 1] - y[i]) / b * a + (y[i] - y[i - 1]) / a * b) / (a + b))
    m.append(np.array(m1, float))

    def f(t):
        i = min(max(int(np.searchsorted(q, t, side="right") - 1), 0), len(q) - 2)
        h = q[i + 1] - q[i]; s = (t - q[i]) / h
        return ((2 * s ** 3 - 3 * s ** 2 + 1) * y[i] + (s ** 3 - 2 * s ** 2 + s) * h * m[i]
                + (-2 * s ** 3 + 3 * s ** 2) * y[i + 1] + (s ** 3 - s ** 2) * h * m[i + 1])
    return f


RUN_LEAN = 7.0           # the run's forward lean (deg, at the hips): nearly upright, the chest open (owner's sheet 2026-10-07)
HEEL_BACK = 0.065        # the boot's heel behind the ankle, on the sole
ARM_OUT = (0.23, 0.38)   # the run's left upper arm / forearm, out from straight down (tan): the forearm
                         # angled a little out from the elbow, a man's carrying angle (never in: a C)
ARM_SWING = (18.0, 22.0)  # the run's left upper arm / forearm swing (deg either way)
ARM_LAG = 2.5            # frames the left forearm trails the upper arm
HAND_LAG = 2.0           # ... and the hand (and the bow) the forearm: a relaxed wrist
L_DEV = -33.0            # the run's left wrist, bent toward the little finger at rest
ELBOW_RUN = 18.0         # the run's left elbow, bent forward: the arm hangs in a J, never a straight rod
L_PRON = 36.0           # the run's left forearm turned thumb-in (half at each end): the bow fore and aft
DEV_MAX = 45.0           # the wrist's side bend (ulnar/radial), at most
DEV_SEEN = []            # the side bends the last solve used (diagnostics)
RUN = dict(N=24, duty=0.36, S=2.0)


def march(R):
    """A run after the owner's 8-phase sheet (2026-10-07), 24 f, two steps of 1 m; per step:
      contact  the front heel strikes, the toe up, the leg nearly straight, ahead of the hip
      down     the foot flat, the knee bent, the hips at their LOWEST
      passing  the support leg straightening under him, the swing heel tucked up past its knee
      up       pushed off the toe, the rear leg out behind, the other knee driven forward: the
               flight, the hips at their HIGHEST
    The stance foot ROLLS heel -> flat -> toe, its pivot carried back at the belt's speed (in place:
    2 m a loop); the swing is a Hermite through the sheet's poses, joined to the stance with no
    step in velocity. The left arm hangs in a J (owner 2026-10-07: 大臂和小臂应该是一个类J字形 -- a
    straight arm with the wrist bent hard read as a C): the upper arm close and a little behind,
    the elbow bent ELBOW_RUN forward, swinging against the left leg; the hand at its rest angle to
    the forearm but for an ulnar bend, the arm turned at the shoulder so the bow runs fore and aft
    beside him, its upper tip forward and down (左手自然下垂并摆动，弓倾斜向前下方), rocking with the arm."""
    N, duty, S = RUN["N"], RUN["duty"], RUN["S"]
    D = S * duty                                       # the ground's travel under one stance
    hy = R.hips_head.y
    x = {"L": R.ankle["L"].x - 0.05, "R": R.ankle["R"].x + 0.05}
    z0 = {"L": R.ankle["L"].z, "R": R.ankle["R"].z}
    phase = {"L": 0.0, "R": 0.5}
    mid = hy + 0.035                                   # the stance's middle: the foot under the hip at "down"
    yawf = {"L": -22.0, "R": 18.0}
    nst, nsw = duty * N, (1 - duty) * N                # frames of stance / swing

    def rot(s, pitch):
        fd = Matrix.Rotation(math.radians(yawf[s]), 3, "Z") @ R.footdir[s]
        lat = Vector((0, 0, 1)).cross(fd).normalized()
        return Matrix.Rotation(math.radians(pitch), 3, lat), fd

    def pitch_of(u):                                   # u: the stance's fraction
        if u < 0.28:
            return -13.0 * (1 - u / 0.28) ** 2         # heel strike, the toe up, lowered onto the sole
        if u > 0.42:
            return 48.0 * ((u - 0.42) / 0.58) ** 2     # the heel rising: the roll onto the toe
        return 0.0

    def stance(s, u):
        """The ankle (y, z) and pitch at stance fraction u: the pivot (heel, or toe once the heel
        is up) fixed to the ground, which moves back D over the stance."""
        th = pitch_of(u)
        M, fd = rot(s, th)
        e = mid + D * (u - 0.5)
        A0 = Vector((x[s], e, z0[s]))
        if th < 0:
            fh = Vector((fd.x, fd.y, 0)).normalized()
            heel = Vector((x[s], e, 0.01)) - fh * HEEL_BACK
            A = heel + M @ (A0 - heel)
        else:
            toe = A0 + fd
            A = toe - M @ fd
        return np.array((A.y, A.z, th))

    def foot(s):
        eps = 1e-3
        on, off = stance(s, 0.0), stance(s, 1.0)
        v_on = (stance(s, eps) - on) / eps * (nsw / nst)        # per unit swing fraction
        v_off = (off - stance(s, 1 - eps)) / eps * (nsw / nst)
        # the sheet's swing poses (ankle y from the hip, ankle z, pitch toe-down +)
        sw = hermite([(0.0, off),
                      (0.18, (hy + 0.41, 0.285, 50)),            # trailing behind (the other's contact)
                      (0.36, (hy + 0.30, 0.32, 58)),            # the heel up behind (the other's down)
                      (0.54, (hy + 0.09, 0.32, 38)),            # passing: under him, the heel low
                      (0.72, (hy - 0.12, 0.27, 22)),            # the knee carried forward, low
                      (0.84, (hy - 0.24, 0.20, 5)),             # the shin swinging out (the flight)
                      (0.94, (hy - 0.297, 0.16, -9)),           # reaching: the longest just before the strike
                      (1.0, on)], v_off, v_on)

        def f(t):
            p = (t / N - phase[s]) % 1.0
            if p < duty:
                y, z, th = stance(s, p / duty)
            else:
                y, z, th = sw((p - duty) / (1 - duty))
            return (x[s], float(y), float(z), float(th), yawf[s])
        return f
    w = lambda t, lag=0.0: 2 * math.pi * ((t - lag) / N)
    # the hips' height over a step (frames into the step): sinking from the strike to "down", driven
    # up by the push-off, then BALLISTIC in the flight (a shallow parabola: ~1.5 cm over 3.4 f)
    st = N / 2
    fo = duty * N                                      # the toe-off, frames into the step
    hz_keys = [(0.0, -0.040), (0.26 * st, -0.078), (0.52 * st, -0.058), (fo, -0.040), ((fo + st) / 2, -0.026)]
    hz = track(hz_keys + [(f + st, v) for f, v in hz_keys], N)
    sw_l = lambda t, lag=1.5: math.cos(w(t, lag) - math.pi)                       # +1 forward, -1 back
    # the left arm as a chain of hanging weights (owner 2026-10-07: 大臂带动小臂，手腕自然放松): the
    # upper arm swings, the forearm follows it ARM_LAG frames late (so the elbow opens and closes by
    # itself), the hand and bow follow the forearm another ARM_LAG late (a relaxed wrist)
    lu, lf = R.len["UpperArm.L"], R.len["Forearm.L"]
    up_ang = lambda t: -25 + ARM_SWING[0] * sw_l(t)                             # deg, + forward
    fore_ang = lambda t: -25 + ELBOW_RUN + ARM_SWING[1] * sw_l(t, 1.5 + ARM_LAG)
    hand_ang = lambda t: -25 + ELBOW_RUN + ARM_SWING[1] * sw_l(t, 1.5 + ARM_LAG + HAND_LAG)

    def l_wrist(t):
        """The wrist from the shoulder: the upper arm at its swing, the forearm at its own (lagging)
        angle, both a little out from the coat; the elbow never straighter than its own bend."""
        a1 = math.radians(up_ang(t)); a2 = math.radians(fore_ang(t))
        return (Vector((ARM_OUT[0], -math.sin(a1), -math.cos(a1))).normalized() * lu
                + Vector((ARM_OUT[1], -math.sin(a2), -math.cos(a2))).normalized() * lf)
    ch = {
        "foot_l": foot("L"), "foot_r": foot("R"),
        "hips_off": lambda t: Vector((0.012 * math.cos(w(t) - 0.9), -0.02, hz(t))),
        "hips_rot": lambda t: Vector((RUN_LEAN + 2.0 * math.cos(2 * w(t, 1.0)), 3 * math.cos(w(t) + 0.6), -6 * math.cos(w(t)))),
        "spine": lambda t: Vector((0, 4 * math.cos(w(t, 1.0)), 0)),
        "chest": lambda t: Vector((-1 - 1.0 * math.cos(2 * w(t, 1.5)), 6 * math.cos(w(t, 1.5)), 0)),           # the chest open
        "neck": lambda t: Vector((-2, -3 * math.cos(w(t, 2.0)), 0)),
        "head": lambda t: Vector((-RUN_LEAN + 1.5 * math.cos(2 * w(t, 2.5)), -1.5 * math.cos(w(t, 2.5)), 0)),   # the gaze level
        "clav_r": lambda t: Vector((4 * math.cos(w(t, 1)), 0, 0)),
        "clav_l": lambda t: Vector((-3 * math.cos(w(t, 1.5)), 0, 0)),
        "rfk": lambda t: Vector((-4 + 38 * math.cos(w(t, 1.5)), 102 - 12 * math.cos(w(t, 2.5)))),     # a runner's arm: the elbow ~90, the fist at the waist
        # the left arm hanging from the shoulder and swinging against the left leg (forward at the
        # right foot's strike), the bow in the relaxed fist rocking behind the forearm
        "l_wrist": l_wrist,
        "l_dev": lambda t: L_DEV + (hand_ang(t) - fore_ang(t)),                 # ulnar, plus the hand trailing
        "l_pole": lambda t: Vector((0.0, 1.0, 0.0)),                            # the elbow bends fore and aft only (no C)
        "l_pron": lambda t: L_PRON,
        "quiver": lambda t: Vector((5 * math.cos(2 * w(t, 3.5)), 0, 2 * math.cos(w(t, 3)))),
        "scab": lambda t: Vector((9 * math.cos(w(t, 3) - math.pi), 0, 3 * math.cos(2 * w(t, 2)))),
        "arrow": lambda t: "off",
    }
    return ch, N


def _shoot_frame(R, elev, k=(-0.03, -0.15, 1.46)):
    """For a side-on shot (root turned -90: the target off his left shoulder, +X of the body): the
    anchor K under the jaw and the grip a full draw along the aim from it."""
    aimv = Vector((math.cos(math.radians(elev)), 0, math.sin(math.radians(elev))))
    K = Vector(k)
    return K, K + aimv * DRAW_LEN, aimv


def _stance(R):
    return _rest_feet(R, dx_l=0.03, dx_r=-0.02, dy_l=-0.03, dy_r=0.02)


def garrison(R):
    """Side-on, an arrow nocked: half draw, the full draw to the jaw, a held aim, let down. 150 f."""
    N = 150
    K, G, aimv = _shoot_frame(R, 6, k=(-0.05, -0.12, 1.46))
    fl, fr = _stance(R)
    up = Vector((0, 0, 1)); chord = (up - aimv * up.dot(aimv)).normalized()
    chord = (chord + Vector((0, 0.10, 0))).normalized()             # a little cant toward him
    half, full = 0.40, 1.0
    draw = track([(0, half), (22, half + 0.03), (42, full), (48, full), (96, full), (102, full - 0.03), (124, half), (150, half)], N)
    breath = lambda t: math.sin(2 * math.pi * t / 75)
    tremble = lambda t: 0.003 * math.sin(2 * math.pi * t / 7.3) * smooth((draw(t) - 0.9) / 0.1)
    ch = {
        "root_yaw": lambda t: -90.0,
        "foot_l": lambda t: fl, "foot_r": lambda t: fr,
        "hips_off": lambda t: Vector((0, 0, -0.025 + 0.004 * breath(t))),
        "hips_rot": lambda t: Vector((1, 0, -4)),
        "spine": track([(0, (1, -4, 0)), (42, (0, -6, 0)), (96, (0, -6, 0)), (124, (1, -4, 0))], N, lag=-2),
        "chest": lambda t: Vector((1.5 * breath(t - 3), -8 - 4 * smooth((draw(t) - half) / (full - half)), 0)),
        # the chest squared off the line (-12..-20 deg below the neck): the neck and head turn the
        # face onto the arrow, so the draw forearm lies along the cheek, not across the face
        "neck": lambda t: Vector((2, 46, 0)),
        "head": lambda t: Vector((-6 + 0.8 * breath(t - 6), 60, 3)),
        "clav_r": lambda t: Vector((-4 * draw(t), 0, 0)),
        "bow_g": lambda t: G + Vector((0, 0.01 * (1 - draw(t)), 0.02 * (1 - draw(t)) + 0.004 * breath(t - 4) + tremble(t))),
        "bow_chord": lambda t: chord,
        "bow_draw": lambda t: -aimv,
        "l_pole": lambda t: Vector((0, 0.4, -1)),
        "rh_w": lambda t: 1.0, "rh_bowd": lambda t: draw(t) + tremble(t) * 3,
        "rh_dir": lambda t: aimv + Vector((0, 0, -0.35)),
        "r_pole": lambda t: Vector((-1, 0.3, 0.1)),
        "hook": lambda t: 1.0,
        "quiver": lambda t: Vector((0.8 * breath(t - 8), 0, 0)),
        "arrow": lambda t: "nock",
    }
    return ch, N


def attack(R):
    """Shooting without pause, one arrow every 48 f: draw an arrow from the quiver (0-8), bring it
    to the bow (8-15), nock (15-17), raise and draw to the jaw (17-30), loose (31), follow through,
    back to the quiver."""
    N = 48
    K, G, aimv = _shoot_frame(R, 14, k=(-0.03, -0.12, 1.46))
    G0 = Vector((0.46, -0.12, 1.18))                       # the bow lowered between shots
    fl, fr = _stance(R)
    up = Vector((0, 0, 1))
    chord_aim = (up - aimv * up.dot(aimv)).normalized()
    chord_low = Vector((0.15, 0.05, 1)).normalized()
    Q = R.quiver_top + Vector((0.0, 0.0, -0.02))           # where the fletchings stand (rest body frame)
    ear = Vector((-0.22, 0.02, 1.55))
    Gn = Vector((0.30, -0.22, 1.16))                        # brought in low before the chest to nock
    bowg = track([(0, G0), (11, G0 + Vector((-0.06, -0.04, 0))), (16, Gn), (18, Gn + Vector((0.02, 0, 0.02))),
                  (23, G + Vector((-0.08, 0, -0.10))), (28, G + Vector((0, 0, -0.01))), (30, G), (31, G),
                  (34, G + Vector((0.03, 0, -0.03))), (38, G + Vector((0.02, 0, -0.03))), (48, G0)], N)
    chord = track([(0, chord_low), (16, chord_low), (25, chord_aim), (38, chord_aim), (48, chord_low)], N)
    # right hand: into the quiver (0-8), the arrow drawn up and over beside the head (8-14), down
    # onto the string (14-18), drawn to the jaw (18-30), loosed past the ear (31-36), round again
    beside = Vector((-0.10, -0.16, 1.52))
    rh_body = track([(0, ear + Vector((-0.08, 0.10, 0.05))), (6, Q + Vector((0, 0, 0.04))), (8, Q + Vector((0, 0, 0.03))),
                     (11, Q + Vector((0.03, -0.06, 0.20))), (14, beside), (18, Gn + Vector((-0.12, 0.10, 0.06))), (30, K),
                     (32, K + Vector((-0.10, 0.03, 0.04))), (36, ear), (48, ear + Vector((-0.08, 0.10, 0.05)))], N)
    rh_w = track([(0, 0), (14, 0), (18, 1), (31, 1), (32, 0), (48, 0)], N)
    rh_bowd = track([(0, 0), (18, 0), (20, 0.05), (25, 0.6), (29, 0.98), (31, 1.0), (32, 1.0), (48, 0)], N)
    hook = track([(0, 0), (18, 0), (19, 1), (31, 1), (32, 0), (48, 0)], N)
    rh_dir = track([(0, (0.2, 0.2, 1)), (8, (0.1, 0.3, 1)), (11, (0.1, -0.1, 1)), (14, (0.6, -0.4, 0.5)), (18, (1, 0, -0.2)),
                    (30, (1, 0, -0.3)), (34, (0.5, 0.3, 0.6)), (48, (0.2, 0.2, 1))], N)
    arrow_dir = track([(0, -R.quiver_dir), (8, -R.quiver_dir), (11, (0.0, -0.2, -1)), (14, (0.7, -0.3, -0.4)), (18, aimv)], N)
    ch = {
        "root_yaw": lambda t: -90.0,
        "foot_l": lambda t: fl, "foot_r": lambda t: fr,
        "hips_off": track([(0, (0, 0, -0.02)), (8, (-0.01, 0, -0.03)), (30, (0.01, 0, -0.025)), (32, (0.0, 0, -0.03)), (48, (0, 0, -0.02))], N),
        "hips_rot": track([(0, (1, 0, -2)), (8, (2, 0, -6)), (30, (0, 0, -5)), (48, (1, 0, -2))], N),
        "spine": track([(0, (2, -2, 0)), (8, (3, -8, 0)), (16, (1, -4, 0)), (30, (-3, -6, 0)), (48, (2, -2, 0))], N, lag=1),
        "chest": track([(0, (2, -4, 0)), (8, (4, -12, 0)), (16, (1, -6, 0)), (30, (-5, -10, 0)), (33, (-5, -9, 0)), (48, (2, -4, 0))], N, lag=1.5),
        "neck": track([(0, (0, 34, 0)), (8, (0, 12, 0)), (18, (2, 38, 0)), (30, (-2, 46, 0)), (48, (0, 34, 0))], N, lag=2),
        "head": track([(0, (-4, 42, 0)), (9, (-2, 18, 0)), (18, (-6, 48, 2)), (30, (-8, 60, 3)), (48, (-4, 42, 0))], N, lag=2.5),
        "clav_r": track([(0, (0, 0, 0)), (6, (-8, 0, 0)), (30, (-6, 0, 0)), (48, (0, 0, 0))], N),
        "bow_g": bowg, "bow_chord": chord, "bow_draw": lambda t: -aimv,
        "l_pole": lambda t: Vector((0, 0.4, -1)),
        "rh_body": rh_body, "rh_w": rh_w, "rh_bowd": rh_bowd, "rh_dir": rh_dir,
        # the elbow's own path: forward and up (the hand reaching back over the shoulder into the
        # quiver), out to the side (pulling the arrow), down (nocking), back level with the arrow
        # (the draw), up and round again after the loose
        "r_pole": track([(0, (-0.4, -0.7, 0.6)), (8, (-0.4, -0.7, 0.6)), (12, (-1, -0.3, 0.3)), (15, (-0.9, 0.1, -0.3)),
                         (18, (-0.7, 0.3, -0.5)), (25, (-1, 0.3, 0.1)), (31, (-1, 0.3, 0.1)), (38, (-0.8, -0.3, 0.5)), (48, (-0.4, -0.7, 0.6))], N),
        "hook": hook,
        "arrow": ranges([(0, "off"), (8, "hand"), (18, "nock"), (31, "off")], N),
        "arrow_dir": arrow_dir,
        "quiver": track([(0, (0, 0, 0)), (8, (3, 0, 0)), (12, (-2, 0, 0)), (18, (0, 0, 0)), (48, (0, 0, 0))], N),
    }
    return ch, N


def defend(R):
    """Crouched behind the bow held crosswise before the face (the left hand on the grip, the right
    on the upper limb, the string toward him); a blow takes it at f 38, he gives and recovers. 80 f."""
    N = 80
    fl, fr = _rest_feet(R, dx_l=0.05, dx_r=-0.04, dy_l=-0.06, dy_r=0.06)
    G = Vector((0.06, -0.38, 1.40))
    chord = Vector((-1, 0, 0.12)).normalized()
    hit = track([(0, 0), (36, 0), (39, 1), (44, 0.75), (60, 0.1), (80, 0)], N)
    breath = lambda t: math.sin(2 * math.pi * t / 40)
    ch = {
        "foot_l": lambda t: fl, "foot_r": lambda t: fr,
        "hips_off": lambda t: Vector((0, 0.02 * hit(t - 1), -0.10 - 0.015 * hit(t - 1) + 0.004 * breath(t))),
        "hips_rot": lambda t: Vector((10 - 3 * hit(t - 1), 0, 0)),
        "spine": lambda t: Vector((5 - 3 * hit(t - 2), 0, 0)),
        "chest": lambda t: Vector((6 + 1.5 * breath(t - 2) - 5 * hit(t - 2), 0, 0)),
        "neck": lambda t: Vector((10 + 4 * hit(t - 3), 0, 0)),
        "head": lambda t: Vector((10 + 6 * hit(t - 3.5), -4, 0)),
        "clav_l": lambda t: Vector((6, 0, 0)), "clav_r": lambda t: Vector((6, 0, 0)),
        "bow_g": lambda t: G + Vector((0, 0.07 * hit(t), 0.02 * hit(t) + 0.005 * breath(t - 3))),
        "bow_chord": lambda t: (chord + Vector((0, 0.06 * hit(t - 1), 0.04 * math.sin(2 * math.pi * t / 80)))).normalized(),
        "bow_draw": lambda t: Vector((0, 1, -0.25)),
        "l_pole": lambda t: Vector((0.8, 0.3, -0.6)),
        "rh_body": lambda t: G + chord * 0.33 + Vector((0, 0.07 * hit(t), 0.025 + 0.02 * hit(t))),
        "rh_w": lambda t: 0.0,
        "rh_dir": lambda t: Vector((0, -0.55, -0.85)),
        "r_pole": lambda t: Vector((-0.8, 0.3, -0.6)),
        "hook": lambda t: 0.0,
        "quiver": lambda t: Vector((-4 * hit(t - 4), 0, 0)),
        "scab": lambda t: Vector((3 * hit(t - 5), 0, 0)),
        "arrow": lambda t: "off",
    }
    return ch, N


def standby(R):
    """At ease: the bow stood on its lower tip before his left foot, the left hand on the grip, the
    right resting on the upper limb; he breathes, shifts his weight, looks about. 150 f."""
    N = 150
    fl, fr = _rest_feet(R, dx_l=-0.02, dx_r=0.03)
    tip = Vector((0.14, -0.26, 0.0))
    chord = Vector((0.0, 0.10, 1)).normalized()            # the top leans back toward him
    draw = Vector((-0.6, 1, 0))
    Rb = frame_of(chord, draw) @ R.F0.transposed()
    G = tip - Rb @ (R.tip0["BowLimb.D"] - R.grip)          # the grip where the bottom tip stands on `tip`
    shift = track([(0, 0), (30, 0.1), (55, 1), (95, 1), (120, 0.1), (150, 0)], N)     # weight onto the right leg and back
    look = track([(0, 0), (60, 0), (72, 28), (88, 26), (100, -8), (112, -6), (126, 0), (150, 0)], N)
    breath = lambda t: math.sin(2 * math.pi * t / 75)
    ch = {
        "foot_l": lambda t: fl, "foot_r": lambda t: fr,
        "hips_off": lambda t: Vector((-0.03 * shift(t), 0, -0.012 - 0.012 * shift(t) + 0.003 * breath(t))),
        "hips_rot": lambda t: Vector((0, -3.5 * shift(t), -2 * shift(t))),
        "spine": lambda t: Vector((0.5 * breath(t - 2), 2 * shift(t - 3), 0)),
        "chest": lambda t: Vector((-1.5 + 1.5 * breath(t - 3), 1.5 * shift(t - 4), 0)),
        "neck": lambda t: Vector((2, 0.4 * look(t + 2), 0)),
        "head": lambda t: Vector((3 + 0.6 * breath(t - 5), 0.6 * look(t + 3), 0)),
        "clav_r": lambda t: Vector((3, 0, 0)),
        "bow_g": lambda t: G,
        "bow_chord": lambda t: chord,
        "bow_draw": lambda t: draw,
        "l_pole": lambda t: Vector((0.5, 0.6, -0.6)),
        "rh_body": lambda t: G + chord * 0.30 + Vector((-0.03, 0.0, 0.03 + 0.003 * breath(t - 4))),
        "rh_w": lambda t: 0.0,
        "rh_dir": lambda t: Vector((0.55, -0.6, -0.55)),
        "r_pole": lambda t: Vector((-0.7, 0.4, -0.6)),
        "hook": lambda t: 0.0,
        "quiver": lambda t: Vector((0.6 * breath(t - 8), 0, 0)),
        "arrow": lambda t: "off",
    }
    return ch, N


CLIPS = {"MARCH": march, "GARRISON": garrison, "ATTACK": attack, "DEFEND": defend, "STANDBY": standby}


def all_clips(names=None):
    R = Rest()
    calibrate()
    out = []
    for n in names or CLIPS:
        ch, N = CLIPS[n](R)
        out.append(bake(n, ch, N, R))
    return out


def preview(name, frames, prefix, views=(("q", (0.6, 1, -0.25)), ("s", (1, 0.05, -0.1)), ("f", (0.05, 1, -0.05)))):
    """Pose `name` at each frame (no keys) and shoot it from each view; returns the paths."""
    R = Rest()
    if not SIGNS:
        calibrate()
    ch, N = CLIPS[name](R)
    out = []
    ad = rig().animation_data
    muted = [(t, t.mute) for t in ad.nla_tracks] if ad else []
    for t, _ in muted:                  # export.py's NLA tracks (or a left-over action) would pose
        t.mute = True                   # the rig at render time
    held = ad.action if ad else None
    if ad:
        ad.action = None
    PREV_W.clear()
    for f in range(N):
        apply_pose(ch, float(f), R)
    for f in frames:
        apply_pose(ch, float(f), R)
        for vn, look in views:
            p = "%s%s_%03d_%s.png" % (prefix, name, f, vn)
            shot(p, (0.05, -0.05, 0.95), look, 2.3, res=360, objs=[mesh()])
            out.append(p)
    for t, m in muted:
        t.mute = m
    if ad:
        ad.action = held
    reset()
    return out
