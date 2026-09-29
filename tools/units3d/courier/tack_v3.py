"""The courier's tack on the SCAN horse (courier model v3): v1's tack (courier_src/tack.py)
ported - the same sheets, straps and irons - laid on the Hunt Museum scan through a mesh
field, its stations moved to where this horse's saddle sits (DY = +0.25 m: the scan's back
is lowest at y 0.2-0.3 and its withers rise from 0.5), the bridle placed in a head frame
taken from the scan's own poll and nose, the reins to the posed rider's fists and the
irons under his boots. Built by build_v3.py, which sets HORSE / HEAD / RIDER first."""
import math, sys
import numpy as np

HERE = __file__.rsplit("/", 1)[0]
V1 = HERE                      # the v1 helpers (sdfkit, cage, hair) sit beside this file
for p in (HERE, V1):
    if p not in sys.path:
        sys.path.insert(0, p)
import sdfkit as sk
import cage as cg

F = None            # the horse as a field (MeshField), set by setup()
HEAD = None         # the head frame: poll, A (poll -> nose), B (down the jaw), k (scale to v1)
RIDER = {}          # FIST_R, FIST_L, STIRRUP_R/L
CLOTH_OFF = 0.010
DY = 0.25


def head_frame(ob):
    """The scan's head: the nose is its furthest point forward, the poll the highest point
    within 0.55 m of it; the frame's scale k maps v1's 0.56 m head onto it."""
    co = np.array([v.co[:] for v in ob.data.vertices])
    nose = co[co[:, 1].argmax()]
    near = co[(co[:, 1] > nose[1] - 0.55) & (np.abs(co[:, 0] - nose[0]) < 0.035)]
    poll = near[near[:, 2].argmax()]           # between the ears (v2 took the left ear's tip)
    A = nose - poll
    Lh = np.linalg.norm(A)
    A = A / Lh
    X = np.array((1.0, 0, 0)) - A * A[0]
    X /= np.linalg.norm(X)
    B = np.cross(X, A)              # down the jaw side: X x A points back and down
    if B[2] > 0:
        B = -B
    return {"poll": poll, "nose": nose, "A": A, "B": B, "X": X, "k": Lh / 0.558, "L": Lh}


def setup(field, head, rider):
    global F, HEAD, RIDER
    F, HEAD, RIDER = field, head, rider


def H(a, b, x=0.0):
    """v1's head coordinates (metres on a 0.56 m head) on the scan's head."""
    k = HEAD["k"]
    return tuple(HEAD["poll"] + (a * 0.9 * k) * HEAD["A"] + (b * k) * HEAD["B"] + (x * k) * HEAD["X"])


# ------------------------------------------------------------------ helpers
def section_down(f, y, z_bot, n, fr=None, z0=1.2, arc_max=None):
    """Points from the top midline down the +X side of the vertical section at y, to
    z_bot (or arc_max), resampled into n + 1 points; the part below the widest point hangs
    straight down."""
    P, _ = sk.half_section(f, (0, y, z0), (0, 0, 1), 181, 1.0)
    pts = [P[0]]
    for a, b in zip(P, P[1:]):
        if b[2] <= z_bot:
            t = (a[2] - z_bot) / max(a[2] - b[2], 1e-9)
            pts.append(a + (b - a) * t)
            break
        pts.append(b)
    pts = np.array(pts)
    if arc_max is not None:
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        cum = np.concatenate([[0], np.cumsum(seg)])
        k = np.searchsorted(cum, arc_max)
        if k < len(pts):
            t = (arc_max - cum[k - 1]) / max(seg[k - 1], 1e-9)
            pts = np.vstack([pts[:k], pts[k - 1] + (pts[k] - pts[k - 1]) * t])
    fr = np.linspace(0, 1, n + 1) if fr is None else fr
    R = sk.polyline_resample(pts, fr)
    xm = 0.0
    for i in range(len(R)):
        xm = max(xm, R[i][0])
        if R[i][0] < xm:
            R[i][0] = xm
    R[0][0] = 0.0
    return R


def sheet(M, G, tag_of, walls, thick, normals_f):
    """Quads over grid G (rows x cols of points); walls = which free edges get a thickness
    row: subset of ('first_row', 'last_row', 'last_col'). Returns the index grid."""
    R, Cn = G.shape[:2]
    idx = [[M.v(G[i, j]) for j in range(Cn)] for i in range(R)]
    for i in range(R - 1):
        for j in range(Cn - 1):
            M.f((idx[i][j], idx[i][j + 1], idx[i + 1][j + 1], idx[i + 1][j]), tag_of(i, j))
    def inward(p):
        n = sk.normal(normals_f, p[None])[0]
        return p - n * thick
    if "last_col" in walls:
        w = [M.v(inward(G[i, -1])) for i in range(R)]
        for i in range(R - 1):
            M.f((idx[i][-1], w[i], w[i + 1], idx[i + 1][-1]), tag_of(i, Cn - 1))
    if "first_row" in walls:
        w = [M.v(inward(G[0, j])) for j in range(Cn)]
        for j in range(Cn - 1):
            M.f((idx[0][j], w[j], w[j + 1], idx[0][j + 1]), tag_of(0, j))
    if "last_row" in walls:
        w = [M.v(inward(G[-1, j])) for j in range(Cn)]
        for j in range(Cn - 1):
            M.f((idx[-1][j + 1], w[j + 1], w[j], idx[-1][j]), tag_of(R - 1, j))
    return idx


def rstrap(M, pts, width, thick, f=None, closed=False, tag="leather", up=None, n=6):
    """v3: a ROUND-section strap (an ellipse of n verts, width x thick): bridle and reins."""
    pts = np.asarray(pts, float)
    m = len(pts)
    rings = []
    for i, p in enumerate(pts):
        t = (pts[(i + 1) % m] - pts[(i - 1) % m]) if closed else (pts[min(i + 1, m - 1)] - pts[max(i - 1, 0)])
        t /= np.linalg.norm(t)
        nr = sk.normal(f, p[None])[0] if f is not None else np.asarray(up, float)
        nr = nr - t * (nr @ t)
        nr /= np.linalg.norm(nr)
        sd = np.cross(t, nr)
        rings.append([M.v(p + sd * math.cos(2 * math.pi * k / n) * width * 0.5
                          + nr * math.sin(2 * math.pi * k / n) * thick * 0.5) for k in range(n)])
    cnt = m if closed else m - 1
    for i in range(cnt):
        r0, r1 = rings[i], rings[(i + 1) % m]
        for k in range(n):
            k2 = (k + 1) % n
            M.f((r0[k], r1[k], r1[k2], r0[k2]), tag)
    if not closed:
        for r, rev in ((rings[0], False), (rings[-1], True)):
            c = M.v(sum(M.V[v] for v in r) / n)
            for k in range(n):
                fc = (r[k], r[(k + 1) % n], c)
                M.f(fc[::-1] if rev else fc, tag)
    return rings


def buckle(M, c, t, nr, w=0.03, h=0.036, tag="brass"):
    """A small square buckle frame round a strap: four round bars."""
    t = np.asarray(t, float); t /= np.linalg.norm(t)
    nr = np.asarray(nr, float); nr = nr - t * (nr @ t); nr /= np.linalg.norm(nr)
    sd = np.cross(t, nr)
    c = np.asarray(c, float) + nr * 0.004
    corners = [c + sd * w / 2 + t * h / 2, c - sd * w / 2 + t * h / 2, c - sd * w / 2 - t * h / 2, c + sd * w / 2 - t * h / 2]
    rstrap(M, corners, 0.005, 0.005, up=nr, closed=True, tag=tag, n=4)


def strap(M, pts, width, thick, f=None, closed=False, tag="leather", up=None):
    """A flat strap along pts; its flat face follows f's normal (or the fixed `up`)."""
    pts = np.asarray(pts, float)
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        if closed:
            t = pts[(i + 1) % n] - pts[(i - 1) % n]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        nr = sk.normal(f, p[None])[0] if f is not None else np.asarray(up, float)
        nr = nr - t * (nr @ t)
        nr /= np.linalg.norm(nr)
        sd = np.cross(t, nr)
        rings.append([M.v(p + sd * a * width * 0.5 + nr * b * thick * 0.5)
                      for a, b in ((1, 1), (1, -1), (-1, -1), (-1, 1))])
    m = n if closed else n - 1
    for i in range(m):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(4):
            k2 = (k + 1) % 4
            M.f((r0[k], r0[k2], r1[k2], r1[k]), tag)
    if not closed:
        M.f(tuple(rings[0][::-1]), tag)
        M.f(tuple(rings[-1]), tag)
    return rings


def torus(M, c, R, r, axis, n=10, m=4, tag="steel"):
    c = np.asarray(c, float)
    ax = np.asarray(axis, float); ax /= np.linalg.norm(ax)
    u = np.cross(ax, (0, 0, 1) if abs(ax[2]) < 0.9 else (1, 0, 0)); u /= np.linalg.norm(u)
    v = np.cross(ax, u)
    idx = []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = u * math.cos(a) + v * math.sin(a)
        ring = []
        for j in range(m):
            b = 2 * math.pi * j / m
            ring.append(M.v(c + d * (R + r * math.cos(b)) + ax * r * math.sin(b)))
        idx.append(ring)
    for i in range(n):
        for j in range(m):
            a0, a1 = idx[i], idx[(i + 1) % n]
            M.f((a0[j], a1[j], a1[(j + 1) % m], a0[(j + 1) % m]), tag)


def on_surface(f, pts, lift=0.0):
    P = sk.project(f, np.asarray(pts, float))
    if lift:
        P = P + sk.normal(f, P) * lift
    return P


def smooth_path(pts, n):
    """Catmull-Rom through pts, n points."""
    P = np.asarray(pts, float)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    segs = len(P) - 3
    for k in range(n):
        s = k / (n - 1) * segs
        i = min(int(s), segs - 1)
        t = s - i
        p0, p1, p2, p3 = P[i:i + 4]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return np.array(out)


# ------------------------------------------------------------------ saddle cloth
CLOTH_Y = [y + DY for y in (-0.46, -0.435, -0.37, -0.29, -0.21, -0.13, -0.05, 0.03, 0.11, 0.19, 0.26, 0.32, 0.355, 0.38)]
CLOTH_FR = [0.0, 0.14, 0.28, 0.42, 0.55, 0.67, 0.78, 0.87, 0.945, 1.0]
CLOTH_BOT = 1.02


def cloth_grid():
    f = sk.Offset(F, CLOTH_OFF)
    G = []
    for y in CLOTH_Y:
        R = section_down(f, y, CLOTH_BOT, 0, fr=CLOTH_FR)
        # folds: a ripple growing towards the hem, and the rear lower corner rounded up
        for j, p in enumerate(R):
            s = CLOTH_FR[j]
            p[0] += 0.006 * math.sin(y * 38.0) * s * s
        G.append(R)
    G = np.array(G)
    # round the two lower corners: lift the last column near the first/last rows
    for i, dz in ((0, 0.05), (1, 0.02), (len(CLOTH_Y) - 1, 0.035), (len(CLOTH_Y) - 2, 0.012)):
        G[i, -1, 2] += dz
        G[i, -2, 2] += dz * 0.4
    return G


def cloth_x(G, y, z):
    """The cloth's x at (y, z), interpolated from its grid (for plates laid on it)."""
    ys = G[:, 0, 1]
    i = int(np.clip(np.searchsorted(ys, y) - 1, 0, len(ys) - 2))
    t = (y - ys[i]) / (ys[i + 1] - ys[i])
    def col_x(row):
        zs, xs = row[:, 2][::-1], row[:, 0][::-1]
        return float(np.interp(z, zs, xs))
    return col_x(G[i]) * (1 - t) + col_x(G[i + 1]) * t


def saddle_cloth(M):
    G = cloth_grid()
    R, Cn = G.shape[:2]
    def tag(i, j):
        return "gold" if (i == 0 or i == R - 2 or j >= Cn - 2) else "cloth_blue"
    sheet(M, G, tag, ("first_row", "last_row", "last_col"), 0.014, F)
    return G


def cross_plate(M, G):
    """The gold cross on the cloth's rear half: a 3-wide cross of quads on the cloth."""
    yc, zc, arm_v, arm_h, w = -0.30 + DY, 1.215, 0.15, 0.105, 0.032
    ys = [yc - arm_h, yc - w, yc + w, yc + arm_h]
    zs = [zc - arm_v, zc - w, zc + w, zc + arm_v * 0.8]
    def P(y, z):
        return (cloth_x(G, y, z) + 0.004, y, z)
    grid = {}
    cells = [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)]
    for (a, b) in cells:
        for (da, db) in ((0, 0), (1, 0), (1, 1), (0, 1)):
            key = (a + da, b + db)
            if key not in grid:
                # subdivide the long arms so the plate follows the cloth's curve
                grid[key] = key
    vid = {}
    def V(i, j):
        if (i, j) not in vid:
            vid[(i, j)] = M.v(P(ys[i], zs[j]))
        return vid[(i, j)]
    for (a, b) in cells:
        M.f((V(a, b), V(a + 1, b), V(a + 1, b + 1), V(a, b + 1)), "gold")


# ------------------------------------------------------------------ saddle
SEAT_Y = [y + DY for y in (-0.235, -0.215, -0.17, -0.12, -0.06, 0.0, 0.06, 0.12, 0.18, 0.23, 0.27, 0.295)]
SEAT_FR = [0.0, 0.2, 0.4, 0.58, 0.74, 0.88, 1.0]


def seat(M):
    f = sk.Offset(F, CLOTH_OFF + 0.012)
    G = []
    for y in SEAT_Y:
        R = section_down(f, y, 0.0, 0, fr=SEAT_FR, arc_max=0.21)
        out = []
        for j, p in enumerate(R):
            u = SEAT_FR[j]
            nrm = sk.normal(f, p[None])[0]
            t = 0.03 * (1 - u ** 3)
            t += 0.042 * sk.sstep(-0.10 + DY, -0.235 + DY, y) * (1 - u * u) ** 1.6   # a low cantle (v3: dies out before the edge, no curled corners)
            t += 0.03 * sk.sstep(0.14 + DY, 0.295 + DY, y) * (1 - u * u) ** 1.6    # a low pommel
            t -= 0.012 * sk.sstep(0.22 + DY, 0.29 + DY, y) * (1 - u) ** 6        # the gullet
            out.append(p + nrm * t)
        G.append(out)
    G = np.array(G)
    sheet(M, G, lambda i, j: "leather", ("first_row", "last_row", "last_col"), 0.02, F)


def flap(M):
    f = sk.Offset(F, CLOTH_OFF + 0.022)
    zt, zb = 1.47, 1.2
    rows = []
    nz = 7
    for k in range(nz):
        z = zt + (zb - zt) * k / (nz - 1)
        s = k / (nz - 1)
        y0 = -0.03 + 0.03 * s + DY
        y1 = 0.30 + 0.06 * s - 0.05 * s ** 4 + DY
        ys = np.linspace(y0, y1, 6)
        row = []
        for y in ys:
            x = sk.raycast(f, [[0, y, z]], [[1, 0, 0]])[0]
            row.append((x, y, z))
        rows.append(row)
    G = np.array(rows)
    # hang: never tuck back in below the widest point
    for j in range(G.shape[1]):
        xm = 0.0
        for i in range(G.shape[0]):
            xm = max(xm, G[i, j, 0])
            G[i, j, 0] = xm
    G = np.transpose(G, (1, 0, 2))        # rows along y, cols down
    sheet(M, G, lambda i, j: "leather", ("first_row", "last_row", "last_col"), 0.012, F)


# ------------------------------------------------------------------ straps, irons


def girth(M):
    f = sk.Offset(F, CLOTH_OFF + 0.004)
    y = 0.19 + DY
    P, _ = sk.half_section(f, (0, y, 1.1), (0, 0, 1), 121, 1.0)
    pts = [p for p in P if p[2] < 1.26]
    pts = sk.polyline_resample(np.array(pts), np.linspace(0, 1, 9))
    pts[-1][0] = 0.0
    full = np.vstack([pts, (pts[:-1] * np.array((-1, 1, 1)))[::-1]])
    strap(M, full, 0.065, 0.008, F, tag="leather")


def stirrups(M, sfx="R"):
    STIRRUP_C = RIDER["STIRRUP_" + sfx] * np.array((1 if sfx == "R" else -1, 1, 1))
    # v3: the leather comes out from under the flap, lying on it (a fixed x left it
    # standing off the scan's narrower right side, a strap flying in the air from behind)
    xt = sk.raycast(sk.Offset(F, CLOTH_OFF + 0.03), [[0.0, 0.13 + DY, 1.44]], [[1.0, 0, 0]])[0]
    top = np.array((min(0.30, xt), 0.13 + DY, 1.44))
    print("STIRRUP_TOP", sfx, round(float(xt), 3))
    iron_top = STIRRUP_C + np.array((0.0, 0.0, 0.14))
    mid = (top + iron_top) / 2 + np.array((0.03, 0.02, 0.0))
    pts = smooth_path([top, mid, iron_top], 7)
    strap(M, pts, 0.032, 0.006, up=(1, 0, 0), tag="leather")
    t = pts[2] - pts[1]
    buckle(M, pts[1] * 0.4 + pts[2] * 0.6, t, (1, 0, 0), w=0.04, h=0.03)
    c = STIRRUP_C
    loop = [c + np.array(d) for d in ((0.0, 0, 0.14), (0.028, 0, 0.13), (0.052, 0, 0.09), (0.062, 0, 0.035),
                                      (0.056, 0, 0.0), (0.0, 0, -0.004), (-0.056, 0, 0.0), (-0.062, 0, 0.035),
                                      (-0.052, 0, 0.09), (-0.028, 0, 0.13))]
    rstrap(M, loop, 0.014, 0.014, up=(0, 1, 0), closed=True, tag="steel", n=6)
    tread = [c + np.array((-0.054, 0, -0.002)), c + np.array((0.054, 0, -0.002))]
    strap(M, tread, 0.07, 0.009, up=(0, 0, 1), tag="steel")


def bridle(M):
    T = F
    f = sk.Offset(T, 0.006)
    # the noseband: a closed band round the face
    A, B = HEAD["A"], HEAD["B"]
    P, _ = sk.full_section(f, np.array(H(0.40, 0.085)), -B, np.array((1.0, 0, 0)), 64, 0.3)
    nb = sk.polyline_resample(P, np.linspace(0, 1, 16, endpoint=False), closed=True)
    rstrap(M, nb, 0.026, 0.009, f, closed=True)
    buckle(M, nb[3], nb[4] - nb[2], sk.normal(f, nb[3][None])[0])
    # the cheek pieces and crownpiece: bit ring - cheek - behind the ears - other side
    def side_pts(x_sign):
        ab = [(0.56, 0.10), (0.46, 0.12), (0.34, 0.14), (0.22, 0.155), (0.10, 0.13), (0.02, 0.07)]
        out = []
        for a, b in ab:
            q = np.array(H(a, b, 0.0))
            d = np.array((x_sign, 0, 0))
            t = sk.raycast(f, q[None], d[None], 0.3)[0]
            out.append(q + d * t)
        return out
    top = np.array(H(-0.015, 0.0))
    top = top + np.array((0, 0, 0.3))
    top = top - np.array((0, 0, 1.0)) * sk.raycast(sk.Fn(lambda P: -f(P)), top[None], [[0, 0, -1]], 0.6)[0]
    crown = side_pts(1)[::-1] + [top] + side_pts(-1)
    crown = smooth_path(crown, 17)
    crown = on_surface(f, crown)
    rstrap(M, crown, 0.022, 0.009, f)
    for i in (4, 12):
        buckle(M, crown[i], crown[i + 1] - crown[i - 1], sk.normal(f, crown[i][None])[0])
    # the browband: across the forehead in front of the ears
    bb = [np.array(H(0.07, 0.07, s * 0.075)) for s in (1, 0.5, 0, -0.5, -1)]
    bb = on_surface(f, smooth_path(bb, 7))
    rstrap(M, bb, 0.02, 0.009, f)
    # the throatlatch: from the crownpiece under the throat
    tl = [np.array(H(0.05, 0.12, 0.075)), np.array(H(0.19, 0.28, 0.06)), np.array(H(0.213, 0.307, 0.0)),
          np.array(H(0.19, 0.28, -0.06)), np.array(H(0.05, 0.12, -0.075))]
    tl = on_surface(f, smooth_path(tl, 9))
    rstrap(M, tl, 0.016, 0.008, f)
    # the bit rings at the corners of the mouth
    rings = []
    for s in (1, -1):
        q = np.array(H(0.575, 0.108, 0.0))
        t = sk.raycast(T, q[None], np.array([[s, 0, 0]]), 0.2)[0]
        c = q + np.array((s * (t + 0.008), 0, 0))
        torus(M, c, 0.026, 0.0055, (1, 0, 0), 12, 6, "steel")
        rings.append(c)
    return rings


def reins(M, rings):
    f = sk.Offset(F, 0.03)
    for s, c in zip((1, -1), rings):
        fist = RIDER["FIST_R"] if s > 0 else RIDER["FIST_L"]
        a = c + np.array((0, -0.01, 0.0))
        b = fist + np.array((0, 0.035, -0.02))
        mid = (a + b) / 2 + np.array((s * 0.06, 0, -0.16))
        pts = smooth_path([a, a * 0.7 + mid * 0.3, mid, b * 0.7 + mid * 0.3, b], 14)
        # keep the rein outside the neck and mane
        v = f(pts)
        bad = v < 0
        if bad.any():
            pts[bad] = sk.project(f, pts[bad])
        rstrap(M, pts, 0.017, 0.008, up=(s, 0, 0.3))


def breast_collar(M):
    f = sk.Offset(F, CLOTH_OFF + 0.004)
    pts = [(0.25, 0.30 + DY, 1.43), (0.24, 0.50 + DY, 1.31), (0.17, 0.70 + DY, 1.24), (0.0, 0.795 + DY, 1.22)]
    pts = on_surface(f, smooth_path(pts, 8))
    pts[-1][0] = 0.0
    full = np.vstack([pts, (pts[:-1] * np.array((-1, 1, 1)))[::-1]])
    rstrap(M, full, 0.045, 0.011, f, n=6)


def mirror_only(M):
    """The mesh turned to its mirror image across x = 0 (faces reversed)."""
    for i in range(len(M.V)):
        q = M.V[i].copy()
        q[0] = -q[0]
        M.V[i] = q
    M.F = [tuple(reversed(f)) for f in M.F]
    return M


def half(field):
    global F
    F = field
    M = cg.Mesh()
    G = saddle_cloth(M)
    cross_plate(M, G)
    seat(M)
    flap(M)
    cg.orient(M, F)
    stirrups(M, "R")
    return M


def build(left_field=None):
    """The scan is not symmetric (its left flank stands a few cm further out than its
    right), so each side is laid on its own flank: the right half on the horse, the left
    half on the horse's mirror image, then mirrored back."""
    global F
    right = F
    M = half(right)
    if left_field is not None:
        L = mirror_only(half(left_field))
        M.extend(L)
    else:
        cg.mirror_x(M)
    F = right
    Mb = cg.Mesh()         # built whole: girth, breast collar, bridle, bit rings, reins
    girth(Mb)
    breast_collar(Mb)
    rings = bridle(Mb)
    reins(Mb, rings)
    return M, Mb
