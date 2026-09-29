"""The horse's mane, forelock and tail on the SCAN (courier model v3), from v1's hair.py:
sculpted locks and fluted masses, opaque geometry (no alpha). The mane falls to the near
(left) side, longer and fuller than the statue's own short crest; the tail arches from the
dock and falls full and long behind the hocks, over the statue's own tail.

v1's docstring follows.
The horse's mane, forelock and tail (courier model v1): sculpted LOCKS, not cards.

A lock is a flat lens-section tube (6 verts round) along a path, wide and thin, tapering
to a closed tip. Mane locks are DRAPED: a walk from the crest over the near (left, -X)
side of the neck, each step the tangential part of gravity plus a sideways bias, projected
back onto the neck surface grown by the lock's own thickness, so they lie on the neck and
fall as hair does; the last fifth lifts off. The tail is one fluted mass (12 round, the
flutes are the strands) hanging from the dock, a ragged end, and loose locks round it.
"""
import math, sys
import numpy as np

HERE = __file__.rsplit("/", 1)[0]
V1 = HERE                      # the v1 helpers (sdfkit, cage, hair) sit beside this file
for p in (HERE, V1):
    if p not in sys.path:
        sys.path.insert(0, p)
import sdfkit as sk
import cage as cg


class _NS:
    pass


hs = _NS()          # set by setup(): TRUNK (the horse field), POLL, head frame


def setup(field, head):
    hs.TRUNK = field
    hs.POLL = tuple(head["poll"])
    hs.HEAD = head

RNG = np.random.default_rng(7)
LENS = [(1.0, 0.0), (0.5, 1.0), (-0.5, 1.0), (-1.0, 0.0), (-0.5, -1.0), (0.5, -1.0)]


def lock(M, pts, widths, thicks, flat_dirs, tag, cap_root=True):
    """Lens-section tube along pts; flat_dirs = the ribbon's wide direction per point."""
    pts = [np.asarray(p, float) for p in pts]
    rings = []
    n = len(pts)
    for i, p in enumerate(pts):
        t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        s = np.asarray(flat_dirs[i], float)
        s = s - t * (s @ t)
        s /= np.linalg.norm(s)
        u = np.cross(t, s)
        if i == n - 1:
            rings.append([M.v(p)])
            continue
        rings.append([M.v(p + s * a * widths[i] * 0.5 + u * b * thicks[i] * 0.5) for a, b in LENS])
    for r0, r1 in zip(rings[:-2], rings[1:-1]):
        for k in range(6):
            k2 = (k + 1) % 6
            M.f((r0[k], r0[k2], r1[k2], r1[k]), tag)
    last, tip = rings[-2], rings[-1][0]
    for k in range(6):
        M.f((last[k], last[(k + 1) % 6], tip), tag)
    if cap_root:
        r = rings[0]
        M.f((r[3], r[2], r[1], r[0]), tag)
        M.f((r[0], r[5], r[4], r[3]), tag)


def drape(f, p0, L, bias, step=0.02, bias_decay=0.12, gravity=1.0, bias_floor=0.25):
    """Walk from p0 over the surface of f: gravity's tangential part + a decaying bias."""
    pts = [sk.project(f, np.asarray(p0, float)[None])[0]]
    walked = 0.0
    while walked < L:
        p = pts[-1]
        n = sk.normal(f, p[None])[0]
        b = math.exp(-walked / bias_decay)
        g = np.array((0, 0, -1.0)) * gravity + np.asarray(bias) * (bias_floor + 1.6 * b)
        d = g - n * (g @ n)
        if np.linalg.norm(d) < 1e-6:
            d = np.asarray(bias, float)
        d /= np.linalg.norm(d)
        q = sk.project(f, (p + d * step)[None])[0]
        walked += np.linalg.norm(q - p)
        pts.append(q)
    return pts


def resample(pts, n):
    pts = np.asarray(pts)
    return sk.polyline_resample(pts, np.linspace(0, 1, n))


def mane(M):
    """The mane as ONE fluted mass draped over the crest to the near side (like the tail),
    its lower edge broken into pointed lock ends, and a few loose locks laid over it."""
    T = hs.TRUNK
    A0, A1 = np.array((0, 0.66, 1.45)), np.array((0, 1.30, 1.86))
    d = (A1 - A0) / np.linalg.norm(A1 - A0)
    up = np.array((0, -d[2], d[1]))
    NC, NR = 24, 8
    f = sk.Offset(T, 0.004)
    cols = []
    for k in range(NC):
        u = k / (NC - 1)
        t = 1.04 - 1.10 * u                    # poll -> withers
        a = A0 + (A1 - A0) * t
        top = a + up * sk.raycast(T, a[None], up[None])[0]
        base_L = 0.11 + 0.23 * math.sin(math.pi * min(1.0, u * 1.06)) ** 0.6        # v3: a little longer than v1
        L = base_L * (1.12 if k % 2 == 0 else 0.84) * RNG.uniform(0.9, 1.1)
        root = top + np.array((0.03, 0, 0)) + up * 0.004
        path = drape(f, root, L + 0.02, bias=(-1, -0.05, 0.0), step=0.012, gravity=0.55, bias_floor=0.9)
        cols.append(resample(path, NR))
    G = np.array(cols)                                 # (NC, NR, 3)
    # thickness off the neck: full over the crest and body of the mane, thinning to the tips;
    # alternate columns stand out a little (the locks), the tips lift off the neck
    out = np.zeros_like(G)
    for k in range(NC):
        for r in range(NR):
            p = G[k, r]
            n = sk.normal(T, p[None])[0]
            s_ = r / (NR - 1)
            th = 0.034 * (1 - 0.5 * s_ ** 2) + (0.009 if k % 2 == 0 else -0.004) * min(1.0, s_ * 3)
            th += 0.026 * s_ ** 3                 # v3: fuller, the tips lift off the neck
            out[k, r] = p + n * th
    # the lock ends: every other column's tip draws to a point between its neighbours
    for k in range(1, NC - 1, 2):
        out[k, -1] = out[k, -1] * 0.5 + (out[k - 1, -1] + out[k + 1, -1]) * 0.25 + (out[k, -1] - out[k, -2]) * 0.3
    idx = [[M.v(out[k, r]) for r in range(NR)] for k in range(NC)]
    inner = [[M.v(G[k, r] + sk.normal(T, G[k, r][None])[0] * 0.002) for r in range(NR)] for k in range(NC)]
    for k in range(NC - 1):
        for r in range(NR - 1):
            M.f((idx[k][r], idx[k][r + 1], idx[k + 1][r + 1], idx[k + 1][r]), "horse_mane")
    # the free edges down to the neck: lock ends, and both ends of the mane
    for k in range(NC - 1):
        M.f((idx[k][-1], inner[k][-1], inner[k + 1][-1], idx[k + 1][-1]), "horse_mane")
        M.f((idx[k][0], idx[k + 1][0], inner[k + 1][0], inner[k][0]), "horse_mane")
    for k, rev in ((0, True), (NC - 1, False)):
        for r in range(NR - 1):
            fc = (idx[k][r], inner[k][r], inner[k][r + 1], idx[k][r + 1])
            M.f(fc[::-1] if rev else fc, "horse_mane")
    for k in range(NC - 1):
        for r in range(NR - 1):
            M.f((inner[k][r], inner[k + 1][r], inner[k + 1][r + 1], inner[k][r + 1]), "horse_mane")
    # a few loose locks over the mass break its outline
    for k in range(7):
        u = 0.1 + 0.8 * k / 6 + RNG.uniform(-0.03, 0.03)
        t = 1.04 - 1.10 * u
        a = A0 + (A1 - A0) * t
        top = a + up * sk.raycast(T, a[None], up[None])[0]
        L = (0.13 + 0.24 * math.sin(math.pi * u) ** 0.6) * RNG.uniform(0.9, 1.2)
        ff = sk.Offset(T, 0.034)
        path = drape(ff, top + up * 0.02, L, bias=(-1, 0.02 * (k - 3), 0.0), step=0.016, gravity=0.6, bias_floor=0.9)
        P = resample(path, 6)
        for i in range(3, 6):
            P[i] = P[i] + sk.normal(T, P[i][None])[0] * 0.012 * (i - 2) / 3
        lock(M, P, np.linspace(0.06, 0.02, 6), np.linspace(0.022, 0.008, 6), [d] * 6, "horse_mane")


def forelock(M):
    T = hs.TRUNK
    A = np.array(hs.HEAD["A"])
    poll = np.array(hs.POLL)
    top = poll + np.array((0, 0.0, 0.01))
    top = sk.project(T, top[None])[0]
    for k, x in enumerate((-0.022, 0.0, 0.02)):
        f = sk.Offset(T, 0.008)
        p0 = top + np.array((x, 0.01, 0.015))
        path = drape(f, p0, 0.15 + 0.02 * (k == 1), bias=(x * 4, 0.6, 0), step=0.015)
        P = resample(path, 5)
        side = np.array((1.0, 0, 0))
        lock(M, P, np.linspace(0.05, 0.02, 5), np.linspace(0.014, 0.006, 5), [side] * 5, "horse_mane")


def tail(M):
    # the fluted mass: path from inside the croup, out over the dock, down to the hocks
    # the scan's dock stands at about (0, -0.66, 1.42); the tail arches out and falls
    # full and long behind the hocks (the statue's own tail hangs against the thighs)
    path = np.array([(0, -0.64, 1.43), (0, -0.74, 1.40), (0, -0.83, 1.31), (0, -0.885, 1.16),
                     (0, -0.905, 0.98), (0, -0.91, 0.80), (0, -0.90, 0.62), (0, -0.885, 0.46)])
    P = resample(path, 15)
    rx = np.interp(np.linspace(0, 1, 15), [0, 0.12, 0.3, 0.55, 0.8, 1.0], [0.045, 0.06, 0.095, 0.115, 0.10, 0.05])
    ry = np.interp(np.linspace(0, 1, 15), [0, 0.12, 0.3, 0.55, 0.8, 1.0], [0.045, 0.055, 0.085, 0.10, 0.085, 0.045])
    n = 12
    rings = []
    for i, p in enumerate(P):
        t = P[min(i + 1, 14)] - P[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        side = np.array((1.0, 0, 0))
        back = np.cross(side, t)
        flute = 0.16 * min(1.0, i / 4.0)
        twist = 0.18 * math.sin(i * 0.7)
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n + twist
            m = 1.0 + flute * (1 if k % 2 == 0 else -1)
            q = p + side * math.cos(a) * rx[i] * m + back * math.sin(a) * ry[i] * m
            if i == 14:                                   # a ragged end
                q[2] += RNG.uniform(-0.05, 0.03)
            ring.append(M.v(q))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            M.f((r0[k], r0[k2], r1[k2], r1[k]), "horse_mane")
    cg.rect_patch(M, rings[-1], 3, 3)
    for k in range(len(M.F) - 9, len(M.F)):
        M.tag[k] = "horse_mane"
    cg.rect_patch(M, rings[0][::-1], 3, 3)
    for k in range(len(M.F) - 9, len(M.F)):
        M.tag[k] = "horse_mane"
    # loose locks round the mass, breaking its outline
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.3
        off = np.array((math.cos(a) * 0.055, math.sin(a) * 0.04, 0))
        z_end = 0.42 + RNG.uniform(0.0, 0.14)
        wob = RNG.uniform(-1, 1)
        pts = [P[3] + off * 0.6,
               P[5] + off * 1.15,
               P[8] + off * 1.35 + np.array((0.012 * wob, -0.01, 0)),
               P[11] + off * 1.3 + np.array((-0.015 * wob, 0.0, 0)),
               np.array((off[0] * 1.2 + 0.01 * wob, P[13][1] + off[1] * 1.2 - 0.01, z_end))]
        Q = resample(pts, 7)
        lock(M, Q, np.linspace(0.05, 0.015, 7), np.linspace(0.02, 0.008, 7),
             [np.array((-off[1], off[0], 0)) + 1e-3] * 7, "horse_mane")


def build():
    M = cg.Mesh()
    mane(M)
    forelock(M)
    tail(M)
    return M


