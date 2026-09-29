"""The herald's clothing on the posed base-mesh rider (courier model v3): v1's skirt,
gold scalloped shoulder caps, belt and buckle, collar and chest cross (courier_src/
clothes.py), laid on the costumed body through mesh fields instead of v1's sculpted
fields. build_v3.py calls setup() with the fields and the posed joints first."""
import math, sys
import numpy as np

HERE = __file__.rsplit("/", 1)[0]
V1 = HERE                      # the v1 helpers (sdfkit, cage, hair) sit beside this file
for p in (HERE, V1):
    if p not in sys.path:
        sys.path.insert(0, p)
import sdfkit as sk
import cage as cg
import tack_v3 as tk


class _NS:
    pass


rs = _NS()      # stands in for v1's rider_sdf: TORSO, BODY, LEG fields and joints
hs = _NS()      # and horse_sdf: FULL


def setup(torso, body, legs, horse, PJ, arm=None):
    global BELT_Z
    rs.TORSO, rs.BODY, rs.LEG = torso, body, legs
    rs.ARM = arm or body
    hs.FULL = horse
    rs.SHOULDER = np.array(PJ["upper_arm.R:h"][:])
    rs.ELBOW = np.array(PJ["upper_arm.R:t"][:])
    rs.PJ = PJ
    BELT_Z = float(PJ["spine:h"].z) + 0.02
    rs.NECK_Z = float(PJ["neck:h"].z)
    rs.CHEST = np.array(PJ["chest:h"][:])
    global THIGH
    THIGH = np.array((PJ["thigh.R:t"] - PJ["thigh.R:h"])[:])
    THIGH /= np.linalg.norm(THIGH)


BELT_Z = 1.748


def body_x(z, phi, f=None, off=0.0):
    """The torso's surface point at height z, angle phi from the front round +X."""
    f = f or rs.TORSO
    o = sk.chord_mid(f, np.array((0.0, rs.CHEST[1] - 0.02, z)), (0, 1, 0), 0.5)
    d = np.array((math.sin(phi), math.cos(phi), 0.0))
    t = sk.raycast(f, o[None], d[None], 0.5)[0]
    return o + d * (t + off), o


def _drape(f, p, clear=0.013):          # the rendered legs are the REDUCED mesh, up to ~1 cm off the field
    """v3b: a point that sinks into what it hangs over (a thigh, the saddle, the croup) is
    pushed out along that surface's normal onto it, so the cloth LIES on the thigh; lifting it
    straight up, as before, stair-stepped the hem wherever neighbours rose different heights."""
    p = np.array(p, float)
    for _ in range(3):
        d = f(p[None])[0]
        if d >= clear or d < -0.12:       # outside, or an open part's field reading 'inside' forever
            break
        n = sk.normal(f, p[None])[0]
        p = p + n * (clear - d)
    return p


def skirt(M):
    """Each point hangs from the belt: pushed out off the TORSO along its horizontal radial
    (plus a flare and folds towards the hem), then LIFTED straight up out of anything it
    would sink into - the thighs in front, the saddle and the croup behind - so it drapes
    over them instead of being shoved along them."""
    horse_back = sk.Offset(hs.FULL, 0.055)
    ycut = rs.PJ["thigh.R:h"].y + 0.06
    lift_f = sk.U(0.0, sk.Offset(rs.LEG, 0.012),
                  sk.Fn(lambda P: np.where(P[:, 1] < ycut, horse_back(P), 1.0)))
    phis = np.radians(np.linspace(10, 180, 13))   # v3b: closed at the back (a slit showed the hose as a white hole)
    drops = [0.0, 0.04, 0.08, 0.12, 0.16, 0.20, 0.24, 0.28, 0.32, 0.36]      # v3: to mid-thigh
    G = []
    for d in drops:
        row = []
        for k, ph in enumerate(phis):
            # v3: the front of the tunic falls ALONG the thigh, the back straight down (and
            # over the cantle): the fall direction turns from the thigh's to plumb round him
            p0, o = body_x(BELT_Z, ph, off=0.012)
            r_dir = np.array((math.sin(ph), math.cos(ph), 0.0))
            w = min(1.0, max(0.0, (math.degrees(ph) - 22.0) / 46.0))   # v3b: only the front follows the thigh
            w = w * w * (3 - 2 * w)
            fall = THIGH * (1 - w) + np.array((0.0, 0.0, -1.0)) * w
            fall /= np.linalg.norm(fall)
            s = d / drops[-1]
            fold = 0.02 * math.sin(ph * 6.0 + 0.6) * s + 0.035 * s * s          # folds, flare
            p = p0 + fall * d * (1.0 + 0.25 * (1 - w)) + r_dir * fold
            p = _drape(lift_f, p)
            row.append(p)
        G.append(row)
    G = np.array(G)
    # the lift is per point: smooth the sheet across its columns, then lift again, so the
    # hem drapes over the thighs and the cantle instead of stepping
    for _ in range(3):
        H = G.copy()
        H[1:, 1:-1] = G[1:, 1:-1] * 0.5 + (G[1:, :-2] + G[1:, 2:]) * 0.25
        H[2:-1, :] = H[2:-1, :] * 0.6 + (H[1:-2, :] + H[3:, :]) * 0.2
        G = H
        for i in range(1, G.shape[0]):
            for j in range(G.shape[1]):
                G[i, j] = _drape(lift_f, G[i, j])
    G[:, -1, 0] = 0.0          # the back column on the midline: the mirrored halves weld there
    # the hem dips at the back over the cantle and at the front over the thighs
    R, Cn = G.shape[:2]
    idx = [[M.v(G[i, j]) for j in range(Cn)] for i in range(R)]
    for i in range(R - 1):
        for j in range(Cn - 1):
            M.f((idx[i][j], idx[i + 1][j], idx[i + 1][j + 1], idx[i][j + 1]), "doublet")
    # thickness: the hem and both slit edges turn in by 1 cm
    def inward(p, o_axis=True):
        v = p.copy()
        c = sk.chord_mid(rs.TORSO, np.array((0.0, rs.CHEST[1] - 0.02, max(min(p[2], BELT_Z), BELT_Z - 0.1))), (0, 1, 0), 0.5)
        r = np.array((p[0] - c[0], p[1] - c[1], 0.0))
        return p - r / max(np.linalg.norm(r), 1e-6) * 0.012
    # v3: no turned-in hem wall (it read as a sawtooth); the slit edges keep theirs
    for jj, rev in ((0, False),):          # v3b: the back is closed, only the front slit
        w = [M.v(inward(G[i, jj])) for i in range(R)]
        for i in range(R - 1):
            fc = (idx[i][jj], w[i], w[i + 1], idx[i + 1][jj])
            M.f(fc[::-1] if not rev else fc, "doublet")


def shoulder_cap(M):
    # cast on the ARM alone: from the arm's axis a ray into the chest never leaves the body
    # (arm and torso are one volume) and ran on to the back
    f = sk.Offset(rs.ARM, 0.011)
    S, E = rs.SHOULDER, rs.ELBOW
    ax = (E - S) / np.linalg.norm(E - S)
    out = np.array((1.0, 0, 0.35)); out -= ax * (out @ ax); out /= np.linalg.norm(out)
    fwd = np.cross(ax, out)
    if fwd[1] < 0:
        fwd = -fwd
    us = np.radians(np.linspace(-72, 72, 11))
    vs = [-0.04, -0.018, 0.005, 0.028, 0.05, 0.072]
    G = []
    for iv, v in enumerate(vs):
        row = []
        for u in us:
            s_ = v
            if iv == len(vs) - 1:
                s_ += 0.03 * abs(math.cos(u * 4.5))             # the scallops (as the pick's)
            c = S + ax * s_
            d = out * math.cos(u) + fwd * math.sin(u)
            t = sk.raycast(f, c[None], d[None], 0.3)[0]
            row.append(c + d * t)
        G.append(row)
    G = np.array(G)
    # a raised bead just inside the scalloped edge: the piece's rolled rim
    nrm = np.array([sk.normal(f, p[None])[0] for p in G[-1]])
    bead = (G[-2] * 0.35 + G[-1] * 0.65) + nrm * 0.005
    G = np.concatenate([G[:-1], bead[None], G[-1:]], 0)
    R, Cn = G.shape[:2]
    idx = [[M.v(G[i, j]) for j in range(Cn)] for i in range(R)]
    for i in range(R - 1):
        for j in range(Cn - 1):
            M.f((idx[i][j], idx[i][j + 1], idx[i + 1][j + 1], idx[i + 1][j]), "gold")
    # the scalloped edge turned in: its thickness
    w = []
    for j in range(Cn):
        p = G[-1, j]
        n = sk.normal(f, p[None])[0]
        w.append(M.v(p - n * 0.01))
    for j in range(Cn - 1):
        M.f((idx[-1][j], idx[-1][j + 1], w[j + 1], w[j]), "gold")


def band(M, z0, z1, off, tag, flare=0.0, n=13, closed_front=True):
    """A band round the torso/neck between heights z0 < z1 (half, front to back)."""
    phis = np.linspace(0, math.pi, n)
    rows = []
    for z, fl in ((z0, 0.0), (z1, flare)):
        row = []
        for ph in phis:
            p, o = body_x(z, ph, off=off + fl)
            if ph in (0.0, math.pi):
                p[0] = 0.0
            row.append(p)
        rows.append(row)
    inner = []
    for z in (z0, z1):
        row = []
        for ph in phis:
            p, o = body_x(z, ph, off=-0.004)
            if ph in (0.0, math.pi):
                p[0] = 0.0
            row.append(p)
        inner.append(row)
    I0 = [M.v(p) for p in inner[0]]
    O0 = [M.v(p) for p in rows[0]]
    O1 = [M.v(p) for p in rows[1]]
    I1 = [M.v(p) for p in inner[1]]
    for a, b in ((I0, O0), (O0, O1), (O1, I1)):
        for j in range(n - 1):
            M.f((a[j], a[j + 1], b[j + 1], b[j]), tag)


def collar(M):
    """v3: a turned-down linen collar (the pick's): a band standing round the neck, folded
    over, its fall lying on the doublet's shoulders; open at the front, its free edges
    turned in (the linen's thickness). Built on +X, mirrored."""
    phis = np.radians(np.linspace(16, 180, 12))
    zn = rs.NECK_Z
    rows = []
    for ph in phis:
        r_dir = np.array((math.sin(ph), math.cos(ph), 0.0))
        p0, o = body_x(zn - 0.012, ph, off=0.007)
        p1, _ = body_x(zn + 0.022, ph, off=0.013)
        p2 = p1 + r_dir * 0.022 + np.array((0, 0, -0.004))
        p3, _ = body_x(zn - 0.034, ph, off=0.011)
        p3 = p3 + r_dir * 0.008 + np.array((0, 0, 0.004 * math.cos(ph)))
        col = [p0, p1, p2, p3]
        if abs(ph - math.pi) < 1e-6:
            for p in col:
                p[0] = 0.0
        rows.append(col)
    G = np.array(rows)                                   # (phi, 4, 3)
    C, R = G.shape[:2]
    idx = [[M.v(G[i, j]) for j in range(R)] for i in range(C)]
    for i in range(C - 1):
        for j in range(R - 1):
            M.f((idx[i][j], idx[i + 1][j], idx[i + 1][j + 1], idx[i][j + 1]), "linen")
    # the fall's edge and the front edge turned in 5 mm
    def under(p):
        q, _ = body_x(p[2], math.atan2(p[0], p[1] - rs.CHEST[1]), off=0.0)
        v = p - q
        return p - v / max(np.linalg.norm(v), 1e-6) * 0.005
    edge = [M.v(under(G[i, -1])) for i in range(C)]
    for i in range(C - 1):
        M.f((idx[i][-1], idx[i + 1][-1], edge[i + 1], edge[i]), "linen")
    front = [M.v(under(G[0, j])) for j in range(R)]
    for j in range(R - 1):
        M.f((idx[0][j + 1], idx[0][j], front[j], front[j + 1]), "linen")


def buckle(M):
    p, o = body_x(BELT_Z, 0.0, off=0.02)
    c = p + np.array((0, 0.002, 0))
    tk.strap(M, [c + np.array((-0.022, 0, 0)), c + np.array((0.022, 0, 0))], 0.04, 0.008,
             up=(0, 1, 0), tag="brass")


def badge(M):
    """A gold cross on the chest, laid on the doublet."""
    f = sk.Offset(rs.TORSO, 0.005)
    zc, arm, w = rs.CHEST[2] + 0.1, 0.05, 0.014
    xs = [-arm, -w, w, arm]
    zs = [zc - arm * 1.3, zc - w, zc + w, zc + arm]
    vid = {}
    def V(i, j):
        if (i, j) not in vid:
            q = np.array((xs[i], rs.CHEST[1] + 0.4, zs[j]))
            t = sk.raycast(sk.Fn(lambda P: -f(P)), q[None], [[0, -1, 0]], 0.4)[0]
            vid[(i, j)] = M.v(q + np.array((0, -t, 0)))
        return vid[(i, j)]
    for a, b in ((1, 0), (0, 1), (1, 1), (2, 1), (1, 2)):
        M.f((V(a, b), V(a, b + 1), V(a + 1, b + 1), V(a + 1, b)), "gold")


def build():
    M = cg.Mesh()          # mirrored half
    skirt(M)
    n0 = len(M.F)
    cg.orient(M, sk.U(0.0, rs.BODY, hs.FULL), range(0, n0))
    shoulder_cap(M)
    band(M, BELT_Z - 0.036, BELT_Z + 0.02, 0.018, "leather")   # v3: lower and prouder, over the skirt's join
    collar(M)
    cg.orient(M, rs.BODY, range(n0, len(M.F)))
    cg.mirror_x(M)
    Mw = cg.Mesh()         # built whole
    buckle(Mw)
    badge(Mw)
    return M, Mw


