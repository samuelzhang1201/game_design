"""Implicit-surface (SDF-like) sculpting in numpy, and the tools that lay a controlled quad
cage ON that surface (courier model v1, 2026-09-29).

The organic forms of the courier (the horse's body, legs and head, the rider's body and
head) are sculpted as smooth unions of simple primitives. They are never polygonised by
marching cubes: the game mesh is a deliberate cage of rings (mirrored half, holes where a
limb joins), and each cage vertex is put on the surface by casting a ray from the ring's
own axis (`ring_rays`) and resampling the section by arc length, so the topology stays
the designer's and the shape stays the sculpture's.

Every function takes points as an (N, 3) float array. A "field" is any callable
P -> (N,) array, negative inside. Only its SIGN and smoothness matter for the ray cast;
smooth-min blend radii read it as a distance, so primitives return true or near-true
distances.
"""
import math
import numpy as np


# ------------------------------------------------------------------ primitives
def _v(a):
    return np.asarray(a, dtype=float)


def frame(axis, up=(0, 0, 1)):
    """A rotation matrix whose columns are (side, axis, normal) with `axis` as local Y."""
    a = _v(axis) / np.linalg.norm(axis)
    u = _v(up)
    s = np.cross(a, u)
    if np.linalg.norm(s) < 1e-6:
        s = np.cross(a, _v((1, 0, 0)))
    s /= np.linalg.norm(s)
    n = np.cross(s, a)
    return np.stack([s, a, n], axis=1)


class Field:
    def __call__(self, P):
        raise NotImplementedError


class Sph(Field):
    def __init__(self, c, r):
        self.c, self.r = _v(c), float(r)

    def __call__(self, P):
        return np.linalg.norm(P - self.c, axis=-1) - self.r


class Ell(Field):
    """Ellipsoid, radii along local (x, y, z); `axis` turns local Y (default world Y)."""

    def __init__(self, c, radii, axis=None, up=(0, 0, 1)):
        self.c, self.r = _v(c), _v(radii)
        self.R = frame(axis, up) if axis is not None else np.eye(3)

    def __call__(self, P):
        q = (P - self.c) @ self.R
        k0 = np.linalg.norm(q / self.r, axis=-1)
        k1 = np.linalg.norm(q / (self.r * self.r), axis=-1)
        return np.where(k1 > 1e-9, k0 * (k0 - 1.0) / np.maximum(k1, 1e-9), -self.r.min())


class RCone(Field):
    """Round cone between points a, b with radii ra, rb (Inigo Quilez's exact form)."""

    def __init__(self, a, b, ra, rb):
        self.a, self.b, self.ra, self.rb = _v(a), _v(b), float(ra), float(rb)

    def __call__(self, P):
        a, b, r1, r2 = self.a, self.b, self.ra, self.rb
        ba = b - a
        l2 = ba @ ba
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = P - a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - np.outer(y, ba)
        x2 = (xv * xv).sum(-1)
        y2 = y * y * l2
        z2 = z * z * l2
        k = math.copysign(1.0, rr) * rr * rr * x2
        d1 = np.sqrt(x2 + z2) * il2 - r2
        d2 = np.sqrt(x2 + y2) * il2 - r1
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
        return np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))


class Chain(Field):
    """Round cones through a polyline of (point, radius): a limb or a lock of hair."""

    def __init__(self, pts, radii):
        self.parts = [RCone(pts[i], pts[i + 1], radii[i], radii[i + 1]) for i in range(len(pts) - 1)]

    def __call__(self, P):
        return np.min(np.stack([p(P) for p in self.parts]), axis=0)


class Scaled(Field):
    """Child evaluated in a space scaled per axis about `c` (s < 1 flattens along that
    world axis). Not an exact distance; fine for the sign and for small factors."""

    def __init__(self, child, c, s):
        self.child, self.c, self.s = child, _v(c), _v(s)

    def __call__(self, P):
        return self.child((P - self.c) / self.s + self.c) * self.s.min()


class Shear(Field):
    """Child with its y shifted by k * (z - z0): leans a shape forward as it goes down."""

    def __init__(self, child, k, z0):
        self.child, self.k, self.z0 = child, float(k), float(z0)

    def __call__(self, P):
        Q = P.copy()
        Q[:, 1] = Q[:, 1] - self.k * (Q[:, 2] - self.z0)
        return self.child(Q)


class MirX(Field):
    """The child built on +x, mirrored: evaluated at |x|."""

    def __init__(self, child):
        self.child = child

    def __call__(self, P):
        Q = P.copy()
        Q[:, 0] = np.abs(Q[:, 0])
        return self.child(Q)


class Plane(Field):
    """Half space: inside where (P - p) . n < 0."""

    def __init__(self, p, n):
        self.p, self.n = _v(p), _v(n) / np.linalg.norm(n)

    def __call__(self, P):
        return (P - self.p) @ self.n


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


class U(Field):
    """Smooth union of children with blend radius k (0 = hard)."""

    def __init__(self, k, *children):
        self.k, self.children = float(k), children

    def __call__(self, P):
        d = self.children[0](P)
        for c in self.children[1:]:
            d = smin(d, c(P), self.k)
        return d


class Sub(Field):
    """a minus b, blended over k."""

    def __init__(self, k, a, b):
        self.k, self.a, self.b = float(k), a, b

    def __call__(self, P):
        return -smin(-self.a(P), self.b(P), self.k)


class Isect(Field):
    def __init__(self, k, a, b):
        self.k, self.a, self.b = float(k), a, b

    def __call__(self, P):
        return -smin(-self.a(P), -self.b(P), self.k)


class Offset(Field):
    """The child grown by d (a layer of cloth, a coat over the body)."""

    def __init__(self, child, d):
        self.child, self.d = child, float(d)

    def __call__(self, P):
        return self.child(P) - self.d


class Fn(Field):
    def __init__(self, fn):
        self.fn = fn

    def __call__(self, P):
        return self.fn(P)


# ------------------------------------------------------------------ queries
def grad(f, P, h=1e-3):
    P = np.atleast_2d(_v(P))
    g = np.zeros_like(P)
    for i in range(3):
        e = np.zeros(3)
        e[i] = h
        g[:, i] = (f(P + e) - f(P - e)) / (2 * h)
    return g


def normal(f, P):
    g = grad(f, P)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def project(f, P, iters=6):
    """Newton steps onto the zero set along the gradient."""
    P = np.array(P, dtype=float)
    for _ in range(iters):
        g = grad(f, P)
        v = f(P)
        P -= (v / np.maximum((g * g).sum(1), 1e-9))[:, None] * g
    return P


def raycast(f, O, D, tmax=1.5, step=0.004):
    """Distance along each ray (origin O inside) to the FIRST exit from the field.
    Rays that never exit return tmax."""
    O, D = np.atleast_2d(_v(O)), np.atleast_2d(_v(D))
    # a mesh (courier v2's MeshField) answers exactly with its own BVH, and so does a
    # layer grown over one: sampling its nearest-face sign mis-reads a collapsed scan
    exact = None
    if getattr(f, "exact", False):
        exact = f.exit_ray(O, D, tmax)
    elif isinstance(f, Offset) and getattr(f.child, "exact", False):
        exact = f.child.exit_ray(O, D, tmax, grow=f.d)
    if exact is not None:
        t, ok = exact
        ok = ok & (f(O) < 0)                 # only rays that start inside and do leave
        if ok.all():
            return t
        rest = raycast(_Sampled(f), O[~ok], D[~ok], tmax, step)
        t = t.copy()
        t[~ok] = rest
        return t
    N = len(O)
    ts = np.arange(step, tmax + step * 0.5, step)
    S = len(ts)
    P = O[:, None, :] + D[:, None, :] * ts[None, :, None]
    v = f(P.reshape(-1, 3)).reshape(N, S)
    out = v > 0
    has = out.any(1)
    first = np.argmax(out, axis=1)
    hi = ts[first]
    lo = np.where(first > 0, ts[np.maximum(first - 1, 0)], 0.0)
    for _ in range(24):
        mid = 0.5 * (lo + hi)
        inside = f(O + D * mid[:, None]) < 0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    t = 0.5 * (lo + hi)
    return np.where(has, t, tmax)


class _Sampled(Field):
    """The same field, without its exact ray (for the rays the exact one cannot answer)."""

    def __init__(self, f):
        self.f = f

    def __call__(self, P):
        return self.f(P)


def inside_start(f, O):
    return f(np.atleast_2d(_v(O))) < 0


# ------------------------------------------------------------------ sections
def polyline_resample(pts, fracs, closed=False):
    """Points at the given arc-length fractions (0..1) along a polyline."""
    pts = np.asarray(pts)
    if closed:
        pts = np.vstack([pts, pts[:1]])
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    L = cum[-1]
    out = []
    for f in fracs:
        s = (f % 1.0 if closed else min(max(f, 0.0), 1.0)) * L
        i = min(np.searchsorted(cum, s, side="right") - 1, len(seg) - 1)
        t = (s - cum[i]) / max(seg[i], 1e-12)
        out.append(pts[i] * (1 - t) + pts[i + 1] * t)
    return np.array(out)


def arc_fraction_of(pts, idx, closed=False):
    """Arc-length fraction of each polyline vertex index."""
    pts = np.asarray(pts)
    if closed:
        pts = np.vstack([pts, pts[:1]])
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    return cum[np.asarray(idx)] / cum[-1]


def half_section(f, origin, up, dense=121, tmax=1.5):
    """A HALF ring (mirrored model): rays from `origin` in the plane spanned by `up` and
    +X, from up (angle 0) round +X to -up (angle pi). Returns the dense polyline."""
    up = _v(up) / np.linalg.norm(up)
    X = _v((1, 0, 0))
    ang = np.linspace(0, math.pi, dense)
    D = np.cos(ang)[:, None] * up + np.sin(ang)[:, None] * X
    O = np.repeat(np.atleast_2d(_v(origin)), dense, axis=0)
    t = raycast(f, O, D, tmax)
    P = O + D * t[:, None]
    P[0, 0] = 0.0
    P[-1, 0] = 0.0
    return P, ang


def full_section(f, origin, front, side, dense=144, tmax=0.6):
    """A full ring about an axis: rays in the plane of `front` and `side`, angle 0 at front,
    pi/2 at side. Returns the dense polyline and its angles."""
    front, side = _v(front), _v(side)
    ang = np.linspace(0, 2 * math.pi, dense, endpoint=False)
    D = np.cos(ang)[:, None] * front + np.sin(ang)[:, None] * side
    O = np.repeat(np.atleast_2d(_v(origin)), dense, axis=0)
    t = raycast(f, O, D, tmax)
    return O + D * t[:, None], ang


def chord_mid(f, p, u, tmax=1.5):
    """Midpoint of the chord of the field along direction u through p (p inside)."""
    p, u = _v(p), _v(u) / np.linalg.norm(u)
    a = raycast(f, p[None], u[None], tmax)[0]
    b = raycast(f, p[None], -u[None], tmax)[0]
    return p + u * (a - b) * 0.5


# ------------------------------------------------------------------ noise
def hash3(ix, iy, iz, seed=0):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def vnoise(P, scale, seed=0):
    """Smooth 3D value noise in 0..1."""
    Q = np.asarray(P) / scale
    i = np.floor(Q).astype(np.int64)
    fr = Q - i
    w = fr * fr * (3 - 2 * fr)
    out = np.zeros(len(Q))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                h = hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
                wx = w[:, 0] if dx else 1 - w[:, 0]
                wy = w[:, 1] if dy else 1 - w[:, 1]
                wz = w[:, 2] if dz else 1 - w[:, 2]
                out += h * wx * wy * wz
    return out


def sstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=float) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)
