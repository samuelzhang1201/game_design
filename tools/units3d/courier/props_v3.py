"""The courier's props on the v3 rider (courier model v3): v1's hat and feather, dispatch
case and pennon (courier_src/props.py), placed from the posed joints and the scan's flank.
build_v3.py calls setup() first."""
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
import hair as hr


class _NS:
    pass


rs = _NS()


def setup(hat_c, hat_rx, hat_ry, fist_l, pole_butt, case_c, belt):
    global HAT_C, HAT_RX, HAT_RY, CASE_C, BELT
    HAT_C, HAT_RX, HAT_RY = np.asarray(hat_c), hat_rx, hat_ry
    rs.FIST_L = np.asarray(fist_l)
    rs.POLE_BUTT = np.asarray(pole_butt)
    CASE_C = np.asarray(case_c)
    BELT = np.asarray(belt)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array(((1, 0, 0), (0, c, -s), (0, s, c)))


# ------------------------------------------------------------------ hat
HAT_TILT = math.radians(-6)
HAT_SEG = 20


def hat(M):
    prof = [(1.00, -0.002), (1.55, -0.012), (2.02, -0.006), (2.16, 0.004), (2.03, 0.014),
            (1.52, 0.011), (1.05, 0.012), (1.035, 0.036), (1.00, 0.075), (0.93, 0.105),
            (0.72, 0.128), (0.42, 0.138)]
    R = rot_x(HAT_TILT)
    rings = []
    for k, (s, dz) in enumerate(prof):
        ring = []
        for i in range(HAT_SEG):
            th = 2 * math.pi * i / HAT_SEG
            c, sn = math.cos(th), math.sin(th)
            brim = min(1.0, max(0.0, (s - 1.05) / 1.0))
            droop = (-0.034 * max(c, 0) ** 2 - 0.018 * max(-c, 0) ** 2 + 0.014 * sn * sn) * brim ** 1.5
            if k in (1, 5):
                droop *= 0.6
            pinch = -0.018 * max(c, 0) ** 3 if k >= 10 else 0.0
            crease = -0.012 * (1 - abs(sn)) if k == 11 else 0.0
            p = np.array((HAT_RX * s * sn, HAT_RY * s * c, dz + droop + pinch + crease))
            ring.append(M.v(HAT_C + R @ p))
        rings.append(ring)
    for k in range(len(rings) - 1):
        tag = "hat_band" if k == 6 else "hat_felt"
        a, b = rings[k], rings[k + 1]
        for i in range(HAT_SEG):
            i2 = (i + 1) % HAT_SEG
            M.f((a[i], a[i2], b[i2], b[i]), tag)
    n0 = len(M.F)
    cg.rect_patch(M, rings[-1], 5, 5)
    for k in range(n0, len(M.F)):
        M.tag[k] = "hat_felt"
        M.F[k] = M.F[k][::-1]


def feather(M):
    R = rot_x(HAT_TILT)
    th = math.radians(-118)
    base = HAT_C + R @ np.array((HAT_RX * 1.02 * math.sin(th), HAT_RY * 1.02 * math.cos(th), 0.03))
    pts = [base, base + np.array((-0.02, -0.05, 0.05)), base + np.array((-0.03, -0.12, 0.11)),
           base + np.array((-0.028, -0.20, 0.15)), base + np.array((-0.02, -0.27, 0.165)),
           base + np.array((-0.01, -0.32, 0.155))]
    P = tk.smooth_path(pts, 9)
    widths = [0.008, 0.02, 0.034, 0.042, 0.044, 0.04, 0.034, 0.024, 0.01]
    thicks = [0.006] * 9
    flat = [np.array((0.15, 0.0, 1.0))] * 9
    n0 = len(M.F)
    hr.lock(M, P, widths, thicks, flat, "feather")


# ------------------------------------------------------------------ dispatch case
def rbox(M, c, half, r, R, tag, seg=2):
    """A rounded box: a cube grid mapped so its edges round with radius r in `seg` steps."""
    c, half = np.asarray(c, float), np.asarray(half, float)
    def coords(h):
        k = (h - r) / h
        steps = [k + (1 - k) * math.sin(math.pi / 2 * t / seg) for t in range(seg + 1)]
        return sorted(set([-s for s in steps] + steps))
    CO = [coords(h) for h in half]
    idx = {}
    def V(q):
        key = tuple(np.round(q, 6))
        if key not in idx:
            a = np.asarray(q) * half
            cl = np.clip(a, -(half - r), half - r)
            d = a - cl
            n = np.linalg.norm(d)
            p = cl + (d / n * r if n > 1e-9 else 0)
            idx[key] = M.v(c + R @ p)
        return idx[key]
    for ax in range(3):
        a1, a2 = (ax + 1) % 3, (ax + 2) % 3
        for sgn in (-1, 1):
            L1, L2 = CO[a1], CO[a2]
            for i in range(len(L1) - 1):
                for j in range(len(L2) - 1):
                    qs = []
                    for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                        q = [0.0, 0.0, 0.0]
                        q[ax] = sgn
                        q[a1] = L1[i + di]
                        q[a2] = L2[j + dj]
                        qs.append(V(q))
                    M.f(tuple(qs) if sgn > 0 else tuple(qs[::-1]), tag)


CASE_H = np.array((0.035, 0.125, 0.09))


def case(M):
    tilt = math.radians(8)                  # the bottom tucks in towards the horse
    R = np.array(((math.cos(tilt), 0, -math.sin(tilt)), (0, 1, 0), (math.sin(tilt), 0, math.cos(tilt))))
    rbox(M, CASE_C, CASE_H, 0.014, R, "leather_case")
    flap_c = CASE_C + R @ np.array((-0.003, 0.0, CASE_H[2] - 0.05))
    rbox(M, flap_c, np.array((CASE_H[0] + 0.005, CASE_H[1] + 0.005, 0.056)), 0.015, R, "leather_case")
    bk = CASE_C + R @ np.array((-CASE_H[0] - 0.008, 0.0, CASE_H[2] - 0.098))
    rbox(M, bk, np.array((0.004, 0.016, 0.018)), 0.003, R, "brass", seg=1)
    top = CASE_C + R @ np.array((0.0, 0.0, CASE_H[2] + 0.003))
    belt = BELT
    mid = top * 0.45 + belt * 0.55 + np.array((-0.05, 0, 0))
    pts = tk.smooth_path([top, mid, belt], 8)
    tk.strap(M, pts, 0.028, 0.006, up=(-1, 0, 0.2), tag="leather")


# ------------------------------------------------------------------ pennon
POLE_TOP_Z = 3.15


def pole_axis():
    d = rs.FIST_L - rs.POLE_BUTT
    d /= np.linalg.norm(d)
    top = rs.POLE_BUTT + d * ((POLE_TOP_Z - rs.POLE_BUTT[2]) / d[2])
    return rs.POLE_BUTT, top, d


def tube(M, pts, radii, n, tag, cap0=True, cap1=True):
    pts = [np.asarray(p, float) for p in pts]
    ax = pts[-1] - pts[0]; ax /= np.linalg.norm(ax)
    u = np.cross(ax, (1, 0, 0) if abs(ax[0]) < 0.9 else (0, 1, 0)); u /= np.linalg.norm(u)
    v = np.cross(ax, u)
    rings = []
    for p, r in zip(pts, radii):
        rings.append([M.v(p + (u * math.cos(2 * math.pi * k / n) + v * math.sin(2 * math.pi * k / n)) * r)
                      for k in range(n)])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            M.f((a[k], a[k2], b[k2], b[k]), tag)
    if cap0:
        cg.rect_patch(M, rings[0], n // 4, n // 4)
        for k in range(len(M.F) - (n // 4) ** 2, len(M.F)):
            M.tag[k] = tag
    if cap1:
        cg.rect_patch(M, rings[-1], n // 4, n // 4)
        for k in range(len(M.F) - (n // 4) ** 2, len(M.F)):
            M.tag[k] = tag
    return rings


def pennon(M, Mc):
    butt, top, d = pole_axis()
    L = np.linalg.norm(top - butt)
    zs = [0.0, 0.02, 0.5, 0.5 + 0.02, L * 0.7, L]
    tube(M, [butt + d * s for s in zs], [0.013, 0.014, 0.014, 0.014, 0.013, 0.012], 8, "wood")
    # the bucket strapped to the flap
    tube(M, [butt - d * 0.03, butt + d * 0.06], [0.026, 0.024], 8, "leather", cap0=True, cap1=False)
    # the finial: a gold knob and point
    k0 = top
    kr = tube(M, [k0, k0 + d * 0.012, k0 + d * 0.03, k0 + d * 0.045], [0.016, 0.024, 0.02, 0.008], 8,
              "gold", cap0=True, cap1=False)
    ring = kr[-1]
    tip = M.v(k0 + d * 0.11)
    for k in range(8):
        M.f((ring[k], ring[(k + 1) % 8], tip), "gold")
    # the flag
    fly0 = np.array((0.0, -1.0, 0.0)) - d * (d @ np.array((0.0, -1.0, 0.0)))
    fly0 /= np.linalg.norm(fly0)
    nf = np.cross(fly0, -d)
    nu, nv = 9, 6
    H0, HL, FL = 0.07, 0.30, 0.52

    def P(u, v):
        ue = 1.0 - 0.36 * (1.0 - abs(2 * v - 1)) if u > 0 else 1.0
        uu = u * ue
        vv = 0.5 + (v - 0.5) * (1.0 - 0.18 * uu)
        wave = 0.04 * math.sin(2 * math.pi * (uu * 1.15) + 0.4 + vv * 0.6) * uu
        return (top - d * (H0 + vv * HL) + fly0 * (uu * FL) - d * 0.11 * uu * uu
                + nf * wave + nf * 0.016)
    G = np.array([[P(i / (nu - 1), j / (nv - 1)) for j in range(nv)] for i in range(nu)])
    # the grid's own normals, for the two faces of the slab
    Nrm = np.zeros_like(G)
    for i in range(nu):
        for j in range(nv):
            du = G[min(i + 1, nu - 1), j] - G[max(i - 1, 0), j]
            dv = G[i, min(j + 1, nv - 1)] - G[i, max(j - 1, 0)]
            n = np.cross(du, dv)
            Nrm[i, j] = n / np.linalg.norm(n)
    h = 0.002
    A = [[M.v(G[i, j] + Nrm[i, j] * h) for j in range(nv)] for i in range(nu)]
    B = [[M.v(G[i, j] - Nrm[i, j] * h) for j in range(nv)] for i in range(nu)]
    for i in range(nu - 1):
        for j in range(nv - 1):
            M.f((A[i][j], A[i + 1][j], A[i + 1][j + 1], A[i][j + 1]), "cloth_blue")
            M.f((B[i][j], B[i][j + 1], B[i + 1][j + 1], B[i + 1][j]), "cloth_blue")
    border = [(i, 0) for i in range(nu - 1)] + [(nu - 1, j) for j in range(nv - 1)] + \
             [(i, nv - 1) for i in range(nu - 1, 0, -1)] + [(0, j) for j in range(nv - 1, 0, -1)]
    for k in range(len(border)):
        (i0, j0), (i1, j1) = border[k], border[(k + 1) % len(border)]
        M.f((A[i0][j0], B[i0][j0], B[i1][j1], A[i1][j1]), "cloth_blue")
    # the gold crown on each face
    uc, vc = 0.30, 0.5
    def crown_pt(du, dv, side):
        u, v = uc + du / FL, vc + dv / HL
        i, j = u * (nu - 1), v * (nv - 1)
        i0, j0 = min(int(i), nu - 2), min(int(j), nv - 2)
        a, b = i - i0, j - j0
        g = (G[i0, j0] * (1 - a) * (1 - b) + G[i0 + 1, j0] * a * (1 - b)
             + G[i0, j0 + 1] * (1 - a) * b + G[i0 + 1, j0 + 1] * a * b)
        n = (Nrm[i0, j0] * (1 - a) * (1 - b) + Nrm[i0 + 1, j0] * a * (1 - b)
             + Nrm[i0, j0 + 1] * (1 - a) * b + Nrm[i0 + 1, j0 + 1] * a * b)
        return g + n / np.linalg.norm(n) * (h + 0.0025) * side
    for side in (1, -1):
        def F(pts, tri=False):
            ids = [Mc.v(crown_pt(du, dv, side)) for du, dv in pts]
            Mc.f(tuple(ids[::-1]) if side > 0 else tuple(ids), "gold")
        # dv < 0 is UP the pole
        F([(-0.05, 0.035), (0.05, 0.035), (0.05, 0.012), (-0.05, 0.012)])
        F([(-0.05, 0.012), (0.05, 0.012), (0.05, -0.002), (-0.05, -0.002)])
        for cx in (-0.042, 0.0, 0.042):
            F([(cx - 0.013, -0.002), (cx + 0.013, -0.002), (cx, -0.045)])


def build():
    M = cg.Mesh()
    Mc = cg.Mesh()          # the flag's crowns: loose plates, their winding set by hand
    hat(M)
    feather(M)
    case(M)
    pennon(M, Mc)
    return M, Mc


