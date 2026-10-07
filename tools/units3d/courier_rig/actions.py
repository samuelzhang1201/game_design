"""The courier's two clips (owner 2026-10-07: 请根据最新骑兵动作建模流程，重新设计信使的动作; asked, he
chose the four-beat gallop and GALLOP + IDLE only), keyed on `courier_rig` at 30 fps from frame 0
through the royal rig's pose ops (royal_rig/actions.py: rot / aim / ik / rear / loc ...) plus:

  ("legs", tgt)        every leg solved for its hoof by the blender-natural-animation skill's
                       deterministic hinge least squares (no Blender IK: it flips between solutions
                       frame to frame) -- `tgt[leg] = (y, z, x, fold, carpus, elbow)` in the world,
                       warm-started from the previous frame, the anatomical preferences measured
                       against a STANDING leg (this mesh walks: the near fore is raised at rest)
  ("stirrups",)        the rider's feet put back in the irons (the ankles' rest places carried by
                       Spine1), after his hips have moved
  ("hand", side, p)    the rider's wrist reached to a point by a two-bone IK (upper arm, forearm)

Brief (blender-natural-animation Phase 1): a light white horse and a herald, game clips at 30 fps, in
place (the map moves the piece; `stride_m` is the gallop's stance speed x its loop).

  GALLOP  14 f loop: the right-lead transverse gallop -- LH 0, RH .10, LF .38, RF .50, then the
          suspension (duty .29) -- the hoof paths periodic PCHIP curves over the swing (the skill's
          canter recipe, raised for a gallop), the body pitching nose-up as the hinds land and
          down over the fores, lifted in the suspension, the back flexing; the neck counter-
          pitching 2 f late, the tail carried up and streaming. The rider in a two-point seat:
          hips up and forward, absorbing the lift 1.5 f late, the torso leaning 14 deg, the head
          level; the feet in the irons; the rein hand following the mouth; the staff upright
          in his right fist, the pennant streaming back and fluttering down its fly; the
          dispatch case bouncing 2 f behind the saddle.
  IDLE    150 f loop: halted, the four hooves square; breathing, a slow weight shift with the near
          hind cocked for a while, a nod, a tail swish; the rider looks left, back right, then
          reaches down to the dispatch case at his left knee and pats it twice (the despatches
          are safe), and takes up the rein again; the pennant stirring in the air.
"""
import math
from mathutils import Euler, Quaternion

FPS = 30
CLIP_PREFIX = "courier_"


def rigo():
    return bpy.data.objects[RIG_NAME]


def cpose(ops, a=None):
    """royal `pose`, then both reins' hand ends on the hands."""
    a = a or rigo()
    reset(a)
    for o_ in ops:
        OPS[o_[0]](a, *o_[1:])
    for s in "LR":
        op_follow(a, "Reins." + s, "R_Hand." + s)


def cclip(name, keys, passes=1, loop=False):
    """[(frame, ops)] keyed on every bone; `passes` > 1 runs the frames first unkeyed so the leg
    solver's warm start at frame 0 is the loop's last frame. A `loop` keys its last frame with the
    first frame's very pose (the solver's warm start would leave it a few tenths of a degree off)."""
    a = rigo()
    act = new_action(a, name)
    first = None
    for p in range(passes):
        for k, (frame, ops) in enumerate(keys):
            last = k == len(keys) - 1
            if loop and last and first is not None and p == passes - 1:
                for pb in a.pose.bones:
                    pb.rotation_quaternion, pb.location = first[pb.name]
                _upd()
            else:
                cpose(ops, a)
            if p == passes - 1:
                if k == 0:
                    first = {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in a.pose.bones}
                key(a, frame)
    a.animation_data.action = None
    reset(a)
    return act


# ------------------------------------------------------------- periodic PCHIP ----
def _pchip_slopes(x, y):
    h = np.diff(x); d = np.diff(y) / h
    m = np.zeros(len(x))
    for i in range(1, len(x) - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    m[0], m[-1] = d[0], d[-1]
    return m


def pchip(keys, wrap=True):
    """keys [(s, v)] over s in 0..1 -> f(s), shape-preserving; `wrap` repeats the keys one period
    either side so the curve is periodic (the skill's 'keys at p-1, p, p+1')."""
    xs = np.array([k[0] for k in keys], float); ys = np.array([k[1] for k in keys], float)
    if wrap:
        xs = np.concatenate([xs[:-1] - 1, xs, xs[1:] + 1]); ys = np.concatenate([ys[:-1], ys, ys[1:]])
    m = _pchip_slopes(xs, ys)

    def f(s):
        i = int(np.clip(np.searchsorted(xs, s) - 1, 0, len(xs) - 2))
        h = xs[i + 1] - xs[i]; t = (s - xs[i]) / h
        h00, h10, h01, h11 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t, -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        return float(h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1])
    return f


def curves(rows, names):
    """rows [(s, a, b, ...)] -> {name: pchip over s}, not wrapped (a swing runs 0..1 once)."""
    return {n: pchip([(r[0], r[k + 1]) for r in rows], wrap=False) for k, n in enumerate(names)}


# ------------------------------------------------------------- the leg solver ----
CHAINS = {"FL": ("Chest", ["FrontScapula.L", "FrontUpperArm.L", "FrontForearm.L", "FrontCannon.L", "FrontHoof.L"]),
          "FR": ("Chest", ["FrontScapula.R", "FrontUpperArm.R", "FrontForearm.R", "FrontCannon.R", "FrontHoof.R"]),
          "HL": ("Pelvis", ["HindThigh.L", "HindShin.L", "HindCannon.L", "HindHoof.L"]),
          "HR": ("Pelvis", ["HindThigh.R", "HindShin.R", "HindCannon.R", "HindHoof.R"])}
REF = {"F": "FR", "H": "HL"}     # the standing legs the preferences are measured against
LIM = {"FrontScapula": (-26, 26), "FrontUpperArm": (-70, 75), "FrontForearm": (-35, 100), "FrontCannon": (-125, 4),
       "FrontHoof": (-110, 40), "HindThigh": (-65, 65), "HindShin": (-90, 25), "HindCannon": (-8, 100),
       "HindHoof": (-110, 40)}   # deg about local X from the STANDING leg: +X swings the lower end forward
PREV = {}
ABDUCT = 15                       # deg either way: the first bone's plane tilt


def _sag(v):
    """A direction's angle in the side (YZ) plane, measured the way +local X turns a leg bone."""
    return math.atan2(-v.y, -v.z)


def neutral(a):
    """Per leg, per bone: the hinge angle that puts this bone at the reference standing leg's angle
    (relative to its parent; the first bone relative to the body)."""
    out = {}
    B = a.data.bones
    for k, (par, chain) in CHAINS.items():
        ref = CHAINS[REF[k[0]]][1]
        n = []
        for i, b in enumerate(chain):
            d = B[b].tail_local - B[b].head_local
            r = B[ref[i]].tail_local - B[ref[i]].head_local
            if i == 0:
                n.append(_sag(r) - _sag(d))
            else:
                dp = B[chain[i - 1]].tail_local - B[chain[i - 1]].head_local
                rp = B[ref[i - 1]].tail_local - B[ref[i - 1]].head_local
                n.append((_sag(r) - _sag(rp)) - (_sag(d) - _sag(dp)))
        out[k] = np.array(n)
    return out


def _rot0(ph, ab):
    """The first bone's turn: the hinge about local X, then a small abduction about local Z (the
    leg's plane tilted in or out -- this horse's legs slant inward, and a purely planar leg slid
    its planted hoof sideways 2-3 cm a frame)."""
    return Matrix.Rotation(ab, 4, "Z") @ Matrix.Rotation(ph, 4, "X")


def _fk(a, chain, par, phis, Mp):
    """`phis`: one hinge angle a bone, then the first bone's abduction."""
    B = a.data.bones
    M = Mp
    prevR = B[par].matrix_local
    for i, b in enumerate(chain):
        Rk = B[b].matrix_local
        R = _rot0(phis[0], phis[-1]) if i == 0 else Matrix.Rotation(phis[i], 4, "X")
        M = M @ (prevR.inverted() @ Rk) @ R
        prevR = Rk
    tip = M @ Vector((0, B[chain[-1]].length, 0))
    return tip, (M.to_3x3() @ Vector((0, 1, 0))).normalized()


def _lm(res, x0, iters=60):
    """Levenberg-Marquardt with an absolute finite-difference Jacobian (mathutils is float32: a
    relative step reads a zero gradient) -- Blender's Python has no scipy."""
    x = x0.copy(); r = res(x); c = r @ r; lam = 1e-3
    for _ in range(iters):
        J = np.zeros((len(r), len(x)))
        for i in range(len(x)):
            xp = x.copy(); xp[i] += 1e-3
            J[:, i] = (res(xp) - r) / 1e-3
        A = J.T @ J; g = J.T @ r
        while True:
            dx = -np.linalg.solve(A + lam * np.diag(np.diag(A) + 1e-9), g)
            xn = x + dx; rn = res(xn); cn = rn @ rn
            if cn < c:
                x, r, c = xn, rn, cn; lam = max(lam / 3, 1e-7); break
            lam *= 4
            if lam > 1e6:
                return x, c
        if np.abs(dx).max() < 1e-5:
            break
    return x, c


NEUTRAL = {}
HOOF_DIR = {}


def op_legs(a, tgt):
    """Solve each leg in `tgt` = {leg: (y, z, x, fold, carpus, elbow)}: its hoof bone's tail to
    (x, y, z) in the world, the hoof turned `fold` deg (+ = toe back) from the reference standing
    hoof, the carpus / elbow flexed by the given degrees (fore), the hock following the stifle (hind)."""
    _upd()
    if not NEUTRAL:
        NEUTRAL.update(neutral(a))
        B = a.data.bones
        for k in "FH":
            hb = B[CHAINS[REF[k]][1][-1]]
            HOOF_DIR[k] = (hb.tail_local - hb.head_local).normalized()
    for k, (y, z, x, fold, carpus, elbow) in tgt.items():
        par, chain = CHAINS[k]
        front = k[0] == "F"
        toe = Vector((x, y, z))
        D = (Matrix.Rotation(math.radians(fold), 3, "X") @ HOOF_DIR[k[0]]).normalized()
        Mp = a.pose.bones[par].matrix.copy()
        n = NEUTRAL[k]
        n = np.append(n, 0.0)                      # + the abduction, neutral 0
        lo = n + np.radians([LIM[b.split(".")[0]][0] for b in chain] + [-ABDUCT])
        hi = n + np.radians([LIM[b.split(".")[0]][1] for b in chain] + [ABDUCT])
        x0 = PREV.get(k, n.copy())

        def res(q):
            t, d = _fk(a, chain, par, q, Mp)
            u = q - n
            r = [(t.x - toe.x) * 40, (t.y - toe.y) * 40, (t.z - toe.z) * 40, (d.y - D.y) * 2, (d.z - D.z) * 2,
                 u[-1] * 0.3]
            r += ([u[0] * 0.9, (u[3] + math.radians(carpus)) * 0.9, u[1] * 0.08, (u[2] - math.radians(elbow)) * 0.5]
                  if front else [(u[2] + u[1]) * 1.0, u[0] * 0.05])
            return np.array(r + list(np.maximum(0, q - hi) * 6) + list(np.maximum(0, lo - q) * 6)
                            + list((q - x0) * 0.12), float)
        q, _c = _lm(res, x0)
        PREV[k] = q
        for i, b in enumerate(chain):
            pb = a.pose.bones[b]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = _rot0(q[0], q[-1]).to_quaternion() if i == 0 else Quaternion((1, 0, 0), q[i])
    _upd()


def op_stirrups(a):
    """The rider's ankles back where they rest relative to Spine1 (the irons hang from the saddle),
    each foot turned as it rests there."""
    sp = a.pose.bones["Spine1"]
    carry = sp.matrix @ sp.bone.matrix_local.inverted()
    for s in "LR":
        sb = a.data.bones["R_Shin." + s]
        op_ik(a, "R_Shin." + s, carry @ sb.tail_local, 2)
        fb = a.data.bones["R_Foot." + s]
        op_aim(a, "R_Foot." + s, carry.to_3x3() @ (fb.tail_local - fb.head_local))


def op_hand(a, s, spec):
    """`spec` [(frame_bone, rest_point, w)]: the wrist to the weighted sum of where each rest point
    is carried now by its bone (evaluated after the ops before it)."""
    p = Vector()
    for fb, rp, w in spec:
        p += carried(a, fb, rp) * w
    op_ik(a, "R_Forearm." + s, p, 2)


OPS.update({"legs": op_legs, "stirrups": op_stirrups, "hand": op_hand, "follow": op_follow})


def carried(a, frame_bone, rest_point):
    fb = a.pose.bones[frame_bone]
    return (fb.matrix @ fb.bone.matrix_local.inverted()) @ Vector(rest_point)


def wave(u, lag=0.0):
    return math.sin(2 * math.pi * (u - lag))


def cwave(u, lag=0.0):
    return math.cos(2 * math.pi * (u - lag))


# ------------------------------------------------------------------- GALLOP ----
GALLOP_FRAMES = 14
GALLOP = {"HL": 0.00, "HR": 0.10, "FL": 0.38, "FR": 0.50}       # right lead, transverse
DUTY = 0.29
STRIDE = 2.8                      # model metres a loop: a planted hoof travels STRIDE * DUTY back
HOME = {"FL": (0.165, -0.55), "FR": (-0.01, -0.55), "HL": (0.05, 0.68), "HR": (-0.035, 0.68)}   # x, y standing
CENTRE = {"F": -0.07, "H": -0.22}  # the stance's middle forward of home (the skill's canter recipe)
FORE_SWING = curves([(0, 0, 0, 45, 10, 0), (.12, .04, .10, 78, 55, 22), (.32, .30, .38, 125, 112, 62),
                     (.52, .70, .42, 88, 78, 55), (.68, 1.07, .26, 15, 14, 18), (.86, 1.10, .12, -4, 0, 6),
                     (1, 1, 0, -6, 0, 0)], ("fwd", "z", "fold", "carpus", "elbow"))
HIND_SWING = curves([(0, 0, 0, 32), (.15, .11, .12, 58), (.40, .52, .30, 75), (.62, .86, .28, 40),
                     (.80, 1.10, .14, 6), (.90, 1.10, .07, -4), (1, 1, 0, -5)], ("fwd", "z", "fold"))
FORE_STANCE = pchip([(0, -6), (.25, 0), (.5, 0), (1, 45)], wrap=False)
HIND_STANCE = pchip([(0, -5), (.25, 0), (.5, 0), (1, 32)], wrap=False)
BODY_PIVOT = (0.0, 0.05, 1.0)


def hoof_target(k, g, stride=STRIDE):
    """(y, z, x, fold, carpus, elbow) of leg `k` at gait phase g."""
    hx, hy = HOME[k]
    sweep = stride * DUTY
    c = hy + CENTRE[k[0]]
    p = (g - GALLOP[k]) % 1.0
    front = k[0] == "F"
    if p < DUTY:
        s = p / DUTY
        return (c - sweep / 2 + sweep * s, 0.0, hx, (FORE_STANCE if front else HIND_STANCE)(s), 0.0, 0.0)
    s = (p - DUTY) / (1 - DUTY)
    C = FORE_SWING if front else HIND_SWING
    y = c + sweep / 2 - sweep * C["fwd"](s)
    if front:
        return (y, C["z"](s), hx, C["fold"](s), C["carpus"](s), C["elbow"](s))
    return (y, C["z"](s), hx, C["fold"](s), 0.0, 0.0)


def body(g):
    """pitch (deg, + nose up), lift (m), back flex (deg)."""
    return (4.0 * cwave(g, 0.12), -0.05 + 0.035 * cwave(g, 0.90), 5.0 * cwave(g, 0.92))


# ------------------------------------------------------------ the rider's springs ----
# (owner 2026-10-07: 上半身过于僵硬): the rider is not posed with sines, he is SIMULATED, once, as damped
# springs hung from the saddle and driven by the gallop's own footfalls (the skill's Phase 4.7: a
# damped follow, not a hard parent). The forcing is the hooves, not a sine: each landing is an
# impact, the hinds' stance pushes him back and up, the fores' stance brakes him forward -- so his
# motion carries the footfalls' accents. Each spring answers the one below it: the trunk (an
# inverted pendulum on the pelvis) the impacts, the chest the trunk's swing, the head the chest's,
# against a stiff pull back to a level gaze. Run to its steady state, the last loop kept: periodic.
SUB = 20                          # simulation steps a frame
IMPACT_W = 0.6                    # frames: an impact's width
STANCE_PUSH = {"HL": -0.45, "HR": -0.55, "FL": 0.85, "FR": 1.0}   # + brakes him forward, - pushes him back
IMPACT = {"HL": 0.45, "HR": 0.55, "FL": 0.9, "FR": 1.0}
ROLL_SIGN = {"HL": 1.0, "HR": -1.0, "FL": 1.0, "FR": -1.0}
TRUNK_SHIFT = 4.5                 # frames: the trunk's response moved in time -- a grid search for the
                                  # stillest head (head_still: 36 / 59 mm against 139 / 87 before)
BACK_ARCH = 12.0                  # deg of curl in his back (owner 2026-10-07: 信使的腰可以弯一点 -- 他的背弓起来一点):
                                  # the pelvis tucked back, the lower and upper back rolled forward over it,
                                  # the shoulders rounded -- a curve, not a fold at the hips
PELVIS_FOLLOW = 0.2               # how much of the saddle's pitch his pelvis takes
RIDER_P2P = {"trunk": 10.0, "chest": 3.5, "head": 2.4, "sink": 0.045, "surge": 0.024, "roll": 4.0,
             "twist": 5.0, "clav_l": 6.0, "clav_r": 5.0, "fist_y": 0.03, "fist_z": 0.025, "staff": 0.11,
             "give_spine": 3.0, "give_chest": 2.0, "give_neck": 2.5, "rein": 0.05}


def _periodic_pulse(N, at, w):
    t = np.arange(N)
    return sum(np.exp(-0.5 * ((t - at * N + k * N) / w) ** 2) for k in (-1, 0, 1))


def _osc(force, wn, zeta, cycles=40):
    """Steady state of x'' + 2 zeta wn x' + wn^2 x = force over one loop (time in frames)."""
    N = len(force)
    dt = 1.0 / SUB
    x = v = 0.0
    out = np.zeros(N)
    for c in range(cycles):
        for i in range(N):
            v += (force[i] - 2 * zeta * wn * v - wn * wn * x) * dt
            x += v * dt
            if c == cycles - 1:
                out[i] = x
    return out


def _accel(x):
    return (np.roll(x, -1) - 2 * x + np.roll(x, 1)) * SUB * SUB


def _p2p(x, p2p):
    x = x - x.mean()
    return x * (p2p / max(float(x.max() - x.min()), 1e-12))


def rider_springs(n=None):
    n = n or GALLOP_FRAMES
    N = n * SUB
    w = IMPACT_W * SUB
    wf = 2 * math.pi / n                                   # the stride's own frequency, rad a frame
    push = np.zeros(N); hit = np.zeros(N); roll = np.zeros(N)
    t = np.arange(N) / N
    for k, ph in GALLOP.items():
        p = (t - ph) % 1.0
        inst = np.where(p < DUTY, np.sin(math.pi * np.clip(p / DUTY, 0, 1)), 0.0)
        imp = _periodic_pulse(N, ph, w)
        push += STANCE_PUSH[k] * (0.6 * inst + imp)
        hit += IMPACT[k] * imp
        roll += ROLL_SIGN[k] * imp
    trunk = np.roll(_p2p(_osc(push, wf / 0.55, 0.35), RIDER_P2P["trunk"]), int(round(TRUNK_SHIFT * SUB)))
    wc = wf / 0.7                                             # the chest follows the trunk ~2 f late
    chest = _osc(trunk * wc * wc, wc, 0.40) - trunk           # ... as a turn ON the trunk
    head = _p2p(_osc(-_accel(trunk + chest), wf / 0.28, 0.60), RIDER_P2P["head"])
    sink = _p2p(_osc(hit, wf / 0.8, 0.5), RIDER_P2P["sink"])
    # the give: a quick, impact-driven flex of the spine on each landing (not the stride's slow swing),
    # passed up the chain a frame a link -- spine, chest, neck -- so the trunk is not one block
    give = _p2p(_osc(hit, wf / 0.30, 0.45), 1.0)
    surge = _p2p(_osc(push, wf / 0.5, 0.45), RIDER_P2P["surge"])
    rl = _p2p(_osc(roll, wf / 0.5, 0.40), RIDER_P2P["roll"])
    tw = _p2p(_osc(np.roll(roll, SUB), wf / 0.45, 0.35), RIDER_P2P["twist"])
    clv = _osc(-_accel(sink), wf / 0.4, 0.35)
    fy = _p2p(_osc(-_accel(trunk + chest), wf / 0.45, 0.30), RIDER_P2P["fist_y"])
    fz = _p2p(_osc(-_accel(sink), wf / 0.42, 0.30), RIDER_P2P["fist_z"])
    staff = _p2p(_osc(-_accel(fy), wf / 0.55, 0.25), RIDER_P2P["staff"])
    return {"trunk": trunk, "chest": chest, "head": head, "sink": sink, "give": give, "surge": surge, "roll": rl,
            "twist": tw, "clav_l": _p2p(clv, RIDER_P2P["clav_l"]),
            "clav_r": _p2p(np.roll(clv, SUB), RIDER_P2P["clav_r"]),
            "fist_y": fy, "fist_z": fz, "staff": staff}


RIDER = {}


def rs(name, u):
    """A rider spring's value at gait phase u (linear between simulation steps)."""
    if not RIDER:
        RIDER.update(rider_springs())
    x = RIDER[name]
    N = len(x)
    i = (u % 1.0) * N
    i0 = int(math.floor(i)) % N
    f = i - math.floor(i)
    return float(x[i0] * (1 - f) + x[(i0 + 1) % N] * f)


def gallop_pose(u):
    n = GALLOP_FRAMES
    pitch, lift, flex = body(u)
    ops = [("rear", pitch, BODY_PIVOT), ("loc", "root", (0, 0, lift)),
           ("rot", "Pelvis", (-flex, 0, 0)), ("rot", "Spine1", (0.35 * flex, 0, 0)),
           ("rot", "Spine2", (0.6 * wave(u, 0.2), 0, 0))]
    # the neck counter-pitches the body 2 f late, the head nods over the fores' stance
    lp = body(u - 2.0 / n)[0]
    ops += [("rot", "Neck1", (-6 - 0.7 * lp, 0, 0)), ("rot", "Neck2", (3 - 0.4 * body(u - 3.0 / n)[0], 0, 0)),
            ("rot", "Head", (5 - 4 * cwave(u, 0.62), 0, 0))]
    # the tail streaming back and down, a wave travelling root -> tip; never lifted clear of the
    # buttocks: the mesh's rump has a ragged, untextured hem behind the thighs that only the tail
    # hides (as at rest)
    for i, (base_, amp) in enumerate(((-16, 3), (-8, 5), (-6, 7), (-4, 9), (-3, 11))):
        ops.append(("rot", "Tail%d" % (i + 1), (base_ + amp * wave(u, 0.15 + 0.09 * i), 0, 0)))
    ops.append(("legs", {k: hoof_target(k, u) for k in CHAINS}))
    # the rider, two-point, from his springs (rider_springs): the pelvis follows the saddle's pitch only
    # in part and late, the trunk swings on it, the chest after the trunk, the head held level; each
    # bone's turn is what its WORLD lean wants less what the bone below already gives it
    lag = lambda f: f / n
    l2 = body(u - lag(1.5))
    saddle = lambda g: -(body(g)[0] + 0.35 * body(g)[2])           # the saddle's forward lean (deg)
    tr, chs, hd = rs("trunk", u), rs("chest", u), rs("head", u)
    w_hips = 16 - 0.3 * BACK_ARCH + PELVIS_FOLLOW * saddle(u - lag(1.5))
    gv = lambda f, amp: amp * rs("give", u - lag(f))
    w_spine = 21.5 + 0.3 * BACK_ARCH + tr + gv(0.0, RIDER_P2P["give_spine"])
    w_chest = w_spine + 0.7 * BACK_ARCH + chs + gv(1.0, RIDER_P2P["give_chest"])
    w_head = 2 + hd
    w_neck = 0.5 * (w_chest - 9.5 + w_head + 10) + gv(2.0, RIDER_P2P["give_neck"])
    ops += [("loc", "R_Hips", (0, -0.06 - rs("surge", u), 0.05 - 0.80 * (l2[1] - (-0.05)) - rs("sink", u))),
            ("rot", "R_Hips", (w_hips - saddle(u), 0.0, 0.4 * rs("roll", u))),
            ("rot", "R_Spine", (w_spine - w_hips, -0.4 * rs("twist", u), 0.6 * rs("roll", u))),
            ("rot", "R_Chest", (w_chest - w_spine, rs("twist", u), 0.3 * rs("roll", u))),
            ("rot", "R_Neck", (w_neck - w_chest, -0.3 * rs("twist", u), -0.4 * rs("roll", u))),
            ("rot", "R_Head", (w_head - w_neck, -0.3 * rs("twist", u), -0.5 * rs("roll", u))),
            ("rot", "R_Clavicle.L", (rs("clav_l", u), 0, -0.5 * BACK_ARCH)),     # shoulders rounded forward
            ("rot", "R_Clavicle.R", (rs("clav_r", u), 0, 0.5 * BACK_ARCH)),
            ("stirrups",)]
    # the rein hand following the mouth (the elbow gives); the staff fist carried by his chest and
    # thrown about by it a moment late, the staff swinging on in the fist after that
    nod = cwave(u, 0.62 + lag(1.0))                                  # the horse's nod, a frame late in his fist
    lw = [("Neck1", (0.14, -0.33 - 0.5 * RIDER_P2P["rein"] * nod, 1.50 - 0.012 * nod), 0.8),
          ("R_Chest", (0.14, -0.31, 1.50), 0.2)]
    rw = [("Spine1", (-0.09, -0.37 + rs("fist_y", u), 1.58 + rs("fist_z", u)), 0.3),
          ("R_Chest", (-0.09, -0.37 + rs("fist_y", u), 1.58 + rs("fist_z", u)), 0.7)]
    ops += [("hand", "L", lw), ("hand", "R", rw),
            ("aim", "Pole", (0.3 * rs("roll", u) / 57.3, -0.42 + rs("staff", u), 1.0)),      # raked forward: the pennant clear of his hat
            ("aim", "Pennon1", (0.05 * wave(u * 2, 0.1), 1.0, -0.55 + 0.10 * wave(u * 2, 0.1))),
            ("aim", "Pennon2", (0.10 * wave(u * 2, 0.3), 1.0, -0.40 + 0.18 * wave(u * 2, 0.3))),
            ("rot", "Case", (-7 * cwave(u, 0.92 + 2.0 / n), 0, 0))]
    return ops


def gallop():
    PREV.clear()
    n = GALLOP_FRAMES
    return cclip("GALLOP", [(f, gallop_pose(f / n)) for f in range(0, n + 1)], passes=2, loop=True)


# --------------------------------------------------------------------- IDLE ----
IDLE_FRAMES = 150
STAND = {"FL": (-0.55, 0.165), "FR": (-0.55, -0.01), "HL": (0.70, 0.05), "HR": (0.68, -0.035)}   # y, x


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def plateau(u, a_, b_, c_, d_):
    return smooth((u - a_) / (b_ - a_)) * (1 - smooth((u - c_) / (d_ - c_)))


def env(u, a_, b_):
    if u <= a_ or u >= b_:
        return 0.0
    return math.sin(math.pi * (u - a_) / (b_ - a_)) ** 2


def look(u):
    """The head's turn (deg, + = to his left), a moving hold while it is held."""
    return (32 * plateau(u, 0.04, 0.15, 0.26, 0.36) + 3 * env(u, 0.15, 0.26)
            - 30 * plateau(u, 0.33, 0.44, 0.52, 0.60) - 3 * env(u, 0.44, 0.52))


def reach(u):
    """0..1: the left hand gone from the rein to the dispatch case."""
    return plateau(u, 0.58, 0.68, 0.84, 0.94)


def pat(u):
    """Two pats on the case's lid while the hand is there."""
    return env(u, 0.70, 0.75) + env(u, 0.76, 0.81)


def idle_pose(u):
    n = IDLE_FRAMES
    breath = wave(u * 3)                                   # three breaths a loop
    rest = plateau(u, 0.12, 0.22, 0.62, 0.74)              # the near hind cocked
    sway = 0.012 * wave(u, 0.1)
    ops = [("loc", "root", (0, sway, -0.008 - 0.004 * rest)),
           ("rot", "Spine1", (0.4 * breath, 0, 0.8 * rest)), ("rot", "Spine2", (0.5 * breath, 0, 0)),
           ("rot", "Pelvis", (0, 0, -1.2 * rest))]
    hl = look(u - 14.0 / n) * 0.18
    ops += [("rot", "Neck1", (2.0 * wave(u * 2, 0.3), 0, hl)), ("rot", "Neck2", (-1.0 * wave(u * 2, 0.4), 0, 0.6 * hl)),
            ("rot", "Head", (-3.0 * env(u, 0.80, 0.92) + 1.5 * wave(u * 2, 0.5), 0, 0))]
    sw = env(u, 0.40, 0.55)
    for i in range(5):
        ops.append(("rot", "Tail%d" % (i + 1), (-3 + 1.5 * wave(u * 2, 0.1 * i), 0,
                                                (6 + 3 * i) * sw * math.sin(2 * math.pi * ((u - 0.40) / 0.15 - 0.06 * i)))))
    tg = {}
    for k, (y, x) in STAND.items():
        if k == "HL":
            tg[k] = (y, 0.0, x, 30 * rest, 0.0, 0.0)          # cocked on the toe: the heel up, the toe kept
        else:
            tg[k] = (y, 0.0, x, 0.0, 0.0, 0.0)
    ops.append(("legs", tg))
    # the rider: breathing, looking about, then the case
    h, nk, ch = look(u), look(u - 2.0 / n), look(u - 4.0 / n)
    r = reach(u)
    # the reach is a lean to the side, not a bow: his head stays up, a glance down at the case
    ops += [("rot", "R_Hips", (1.5, 0, 0)), ("rot", "R_Spine", (0.8 * breath + 1.5 * r, 0, -6 * r)),
            ("rot", "R_Chest", (0.8 * breath + 1.0 * r, 0.22 * ch, -4 * r)),
            ("rot", "R_Neck", (-3 * r, 0.35 * nk, 0)),
            ("rot", "R_Head", (3 * env(u, 0.15, 0.26) + 4 * r, 0.55 * h + 22 * r, 0)),
            ("stirrups",)]
    lw = [("Neck1", (0.14, -0.31, 1.50 + 0.006 * breath), 1 - r), ("Spine1", (0.25, -0.08, 1.465 - 0.03 * pat(u)), r)]   # on the lid (1.50 hovered above it)
    rw = [("Spine1", (-0.09, -0.35, 1.57 + 0.004 * breath), 1.0)]
    ops += [("hand", "L", lw), ("hand", "R", rw),
            ("aim", "Pole", (0.01 * wave(u, 0.2), -0.30 + 0.012 * breath, 1.0)),
            ("aim", "Pennon1", (0.03 * wave(u * 2, 0.2), 0.12 + 0.06 * wave(u * 3, 0.1), -1.0)),
            ("aim", "Pennon2", (0.05 * wave(u * 2, 0.35), 0.10 + 0.10 * wave(u * 3, 0.25), -1.0)),
            ("rot", "Case", (2.5 * pat(u - 1.0 / n), 0, 0))]
    return ops


def idle():
    PREV.clear()
    n = IDLE_FRAMES
    return cclip("IDLE", [(f, idle_pose(f / n)) for f in range(0, n + 1, 3)], passes=2, loop=True)


def all_clips():
    return [gallop(), idle()]


# ----------------------------------------------------------------- the gates ----
HOOF_TIPS = {"LH": "HindHoof.L", "RH": "HindHoof.R", "LF": "FrontHoof.L", "RF": "FrontHoof.R"}


def _ang(q1, q2):
    d = math.degrees(q1.rotation_difference(q2).angle)
    return min(d, 360 - d)


def gait_metrics(name="GALLOP", sub=4, h=0.02, ground_speed=0.0):
    """Footfall chart (contact per 1/sub frame), planted slide per frame (mm, both frames planted,
    against the ground's `ground_speed` m a frame back: the clip is in place),
    penetration (mm), the largest single-frame joint turn (deg) per leg bone, loop closure."""
    a = rigo()
    act = bpy.data.actions[CLIP_PREFIX + name]
    a.animation_data.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    sc = bpy.context.scene
    rows = {k: "" for k in HOOF_TIPS}
    for i in range((f1 - f0) * sub):
        f = f0 + i / sub
        sc.frame_set(int(f), subframe=f - int(f))
        for k, b in HOOF_TIPS.items():
            rows[k] += "#" if (a.matrix_world @ a.pose.bones[b].tail).z < h else "."
    land = {k: [round(j / sub, 2) for j in range(len(s)) if s[j] == "#" and s[j - 1] == "."] for k, s in rows.items()}
    P = {k: [] for k in HOOF_TIPS}
    Q = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for k, b in HOOF_TIPS.items():
            P[k].append(np.array(a.matrix_world @ a.pose.bones[b].tail))
        for pb in a.pose.bones:
            if pb.name.startswith(("Front", "Hind", "R_", "Neck", "Head", "Tail", "Spine", "Pennon", "Pole")):
                Q.setdefault(pb.name, []).append(pb.matrix.to_quaternion())
    slide, pen = {}, {}
    for k, p in P.items():
        p = np.array(p)
        dv = np.diff(p[:, :2], axis=0) - np.array([0.0, ground_speed])
        v = np.linalg.norm(dv, axis=1)
        c = (p[:-1, 2] < h) & (p[1:, 2] < h)
        slide[k] = round(float(v[c].max()) * 1000, 1) if c.any() else 0.0
        pen[k] = round(max(0.0, -float(p[:, 2].min())) * 1000, 1)
    turn = {}
    for b, qs in Q.items():
        t_ = [_ang(qs[i], qs[i + 1]) for i in range(len(qs) - 1)]
        # a pop is a frame's turn far above its neighbours' (a smooth fast swing is not)
        jump = max(t_[i] - 0.5 * (t_[i - 1] + t_[(i + 1) % len(t_)]) for i in range(len(t_)))
        turn[b] = (round(max(t_), 1), round(jump, 1))
    worst = sorted(turn.items(), key=lambda kv: -kv[1][1])[:6]
    loop = round(max(_ang(qs[0], qs[-1]) for qs in Q.values()), 3)
    a.animation_data.action = None
    reset(a)
    return {"chart": rows, "land": land, "slide_mm": slide, "penetration_mm": pen, "worst_turn_deg": worst,
            "loop_err_deg": loop}


def stance_speed(name="GALLOP"):
    """Model metres a loop: a planted hind hoof's speed back over its stance x the loop's frames."""
    a = rigo()
    act = bpy.data.actions[CLIP_PREFIX + name]
    a.animation_data.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    ys, planted = [], []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        p = a.matrix_world @ a.pose.bones["HindHoof.L"].tail
        ys.append(p.y); planted.append(p.z < 0.02)
    a.animation_data.action = None
    reset(a)
    v = [ys[i + 1] - ys[i] for i in range(len(ys) - 1) if planted[i] and planted[i + 1]]
    return round(sum(v) / max(1, len(v)) * (f1 - f0), 3)


def frames_to(name, frames, folder, look=(-1, 0, -0.08), size=3.0, res=360, centre=(0, 0, 1.2),
              colour="TEXTURE", ground=True):
    """One ortho Workbench render a frame of clip `name` into `folder` (f000.png ...); with
    `ground`, a striped floor scrolling back at the clip's ground speed (an in-place gait reads
    slower than it is without it)."""
    import os
    os.makedirs(folder, exist_ok=True)
    a = rigo()
    a.animation_data.action = bpy.data.actions[CLIP_PREFIX + name]
    fl = None
    if ground:
        fl = bpy.data.objects.get("stripe_floor")
        if fl is None:
            me = bpy.data.meshes.new("stripe_floor")
            vs, fs = [], []
            for i in range(24):
                y0 = -6 + i * 0.5
                k = len(vs)
                vs += [(-1.2, y0, -0.002), (1.2, y0, -0.002), (1.2, y0 + 0.25, -0.002), (-1.2, y0 + 0.25, -0.002)]
                fs.append((k, k + 1, k + 2, k + 3))
            me.from_pydata(vs, [], fs)
            fl = bpy.data.objects.new("stripe_floor", me)
            bpy.context.scene.collection.objects.link(fl)
        fl.hide_render = False
    speed = STRIDE / GALLOP_FRAMES if name == "GALLOP" else 0.0
    out = []
    for f in frames:
        bpy.context.scene.frame_set(f)
        if fl is not None:
            fl.location.y = (f * speed) % 0.5
        p = folder + "/f%03d.png" % f
        vshot(p, centre, look, size, res, colour)
        out.append(p)
    if fl is not None:
        fl.hide_render = True
    a.animation_data.action = None
    reset(a)
    return out


RIDER_CHAIN = ("R_Hips", "R_Spine", "R_Chest", "R_Neck", "R_Head", "R_Clavicle.L", "R_Clavicle.R",
               "R_Hand.L", "R_Hand.R", "Pole")


def rider_motion(name="GALLOP"):
    """Per rider bone over the clip, relative to the saddle (Spine1): the range of its pitch, roll and
    yaw (deg) and of its head's position (mm), the frame its pitch peaks, and `local_peak`: the frame
    its OWN turn (against its parent) peaks -- a stiff rider has small ranges and every link peaking
    on the same frame."""
    a = rigo()
    act = bpy.data.actions[CLIP_PREFIX + name]
    a.animation_data.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    rec = {b: [] for b in RIDER_CHAIN}
    for f in range(f0, f1):
        bpy.context.scene.frame_set(f)
        sp = a.pose.bones["Spine1"]
        inv = (sp.matrix @ sp.bone.matrix_local.inverted()).inverted()
        for b in RIDER_CHAIN:
            M = inv @ a.pose.bones[b].matrix
            e = M.to_3x3().to_euler("XYZ")
            pb = a.pose.bones[b]
            loc = math.degrees(pb.rotation_quaternion.to_euler("XYZ").x)
            rec[b].append((math.degrees(e.x), math.degrees(e.y), math.degrees(e.z), *M.translation, loc))
    a.animation_data.action = None
    reset(a)
    out = {}
    for b, r in rec.items():
        r = np.array(r)
        rng = r.max(0) - r.min(0)
        out[b] = {"pitch": round(float(rng[0]), 1), "roll": round(float(rng[1]), 1), "yaw": round(float(rng[2]), 1),
                  "move_mm": round(float(np.linalg.norm(rng[3:6])) * 1000), "peak_f": int(np.argmax(r[:, 0])),
                  "local_peak": int(np.argmax(r[:, 6]))}
    return out


def head_still(frames=None):
    """World travel of his head over the gallop (mm, fore-aft and up-down), posed directly (no
    keys): the measure the trunk's tuning minimises -- a rider's head is the steadiest thing on him."""
    a = rigo()
    n = GALLOP_FRAMES
    P = []
    for f in (frames or range(n)):
        cpose(gallop_pose(f / n), a)
        P.append(np.array(a.pose.bones["R_Head"].head))
    reset(a)
    P = np.array(P)
    return round(float(np.ptp(P[:, 1])) * 1000), round(float(np.ptp(P[:, 2])) * 1000)
