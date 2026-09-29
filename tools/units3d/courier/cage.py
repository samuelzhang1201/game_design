"""Quad cages laid on sdfkit fields (courier model v1). Pure numpy + a tiny mesh
accumulator; `to_object` turns a Mesh into a Blender object (only that needs bpy).

A trunk is a sequence of STATIONS (a plane with an origin inside the field and an
in-plane 'up'); each station's HALF section (up -> +X -> down) is ray-cast on the field and
resampled by arc length into C+1 points, so every ring of a mirrored trunk has the same
count, j = 0 and j = C on the mirror plane. Limbs grow out of rectangular HOLES in that
grid; their rings are horizontal (or any plane) sections of the limb field, resampled
into the hole's vertex count and turned to match the hole's order.
"""
import math
import numpy as np
import sdfkit as sk


class Mesh:
    def __init__(self):
        self.V = []          # positions
        self.F = []          # tuples of vertex indices
        self.tag = {}        # face index -> region tag (material later)
        self.vtag = {}       # vertex index -> tag

    def v(self, p, tag=None):
        self.V.append(np.asarray(p, dtype=float))
        i = len(self.V) - 1
        if tag:
            self.vtag[i] = tag
        return i

    def f(self, idx, tag=None):
        self.F.append(tuple(idx))
        if tag:
            self.tag[len(self.F) - 1] = tag
        return len(self.F) - 1

    def extend(self, other):
        off = len(self.V)
        self.V += other.V
        for k, fc in enumerate(other.F):
            self.F.append(tuple(i + off for i in fc))
            if k in other.tag:
                self.tag[len(self.F) - 1] = other.tag[k]
        for i, t in other.vtag.items():
            self.vtag[i + off] = t
        return off

    def tris(self):
        return sum(len(f) - 2 for f in self.F)


# ------------------------------------------------------------------ stations
class Station:
    def __init__(self, origin, up, normal):
        self.o = np.asarray(origin, float)
        self.u = np.asarray(up, float) / np.linalg.norm(up)
        self.n = np.asarray(normal, float) / np.linalg.norm(normal)


def yz_station(f, y_or_point, normal_yz, guess, tmax=1.5):
    """A station in a plane through the X axis direction: normal (0, ny, nz); `guess` a
    point inside near where the origin should be. The origin is the chord middle along the
    plane's up direction through the guess (projected onto the plane)."""
    n = np.array([0.0, normal_yz[0], normal_yz[1]])
    n /= np.linalg.norm(n)
    u = np.array([0.0, -n[2], n[1]])
    if u[2] < 0:
        u = -u
    p0 = np.asarray(y_or_point, float)
    g = np.asarray(guess, float)
    g = g - n * ((g - p0) @ n)
    o = sk.chord_mid(f, g, u, tmax)
    return Station(o, u, n)


def half_rings(f, stations, fracs, dense=161, tmax=1.5):
    """(S, C+1, 3) grid of points."""
    out = []
    for s in stations:
        if f(s.o[None])[0] >= 0:
            print("WARNING station origin outside the field", s.o)
        P, _ = sk.half_section(f, s.o, s.u, dense, tmax)
        R = sk.polyline_resample(P, fracs)
        R[0, 0] = 0.0
        R[-1, 0] = 0.0
        out.append(R)
    return np.array(out)


def check_order(G, stations):
    """Consecutive rings must lie on the right sides of each other's planes."""
    bad = 0
    for i in range(len(stations) - 1):
        a, b = stations[i], stations[i + 1]
        if ((G[i + 1] - a.o) @ a.n < -1e-4).any() or ((G[i] - b.o) @ b.n > 1e-4).any():
            bad += 1
            print("WARNING rings %d/%d cross" % (i, i + 1))
    return bad


# ------------------------------------------------------------------ grids
def grid_faces(M, idx, holes=(), tag=None, closed_cols=False):
    """Faces between idx[i][j] rows; `holes` = list of (i0, i1, j0, j1) cell rectangles
    (cells i0..i1-1, j0..j1-1) left open."""
    S, C1 = len(idx), len(idx[0])
    for i in range(S - 1):
        for j in range(C1 - (0 if closed_cols else 1)):
            j2 = (j + 1) % C1
            if any(i0 <= i < i1 and j0 <= j < j1 for i0, i1, j0, j1 in holes):
                continue
            M.f((idx[i][j], idx[i][j2], idx[i + 1][j2], idx[i + 1][j]), tag)


def hole_loop(idx, i0, i1, j0, j1):
    """Boundary vertex indices of the hole of cells i0..i1-1 x j0..j1-1, in order."""
    L = [idx[i0][j] for j in range(j0, j1)]
    L += [idx[i][j1] for i in range(i0, i1)]
    L += [idx[i1][j] for j in range(j1, j0, -1)]
    L += [idx[i][j0] for i in range(i1, i0, -1)]
    return L


def coons(ring_pts, k):
    """Interior points of a k x k patch whose boundary is ring_pts (4k points, CCW from a
    corner, sides B(i,0) T R L as in quadkit.fill_ring_quad_grid). Returns dict (i,j)->p
    for all grid points including the boundary."""
    per = [(i, 0) for i in range(k)] + [(k, j) for j in range(k)] + \
          [(i, k) for i in range(k, 0, -1)] + [(0, j) for j in range(k, 0, -1)]
    P = {ij: np.asarray(ring_pts[t], float) for t, ij in enumerate(per)}
    return per, P


def rect_patch(M, border, a, b, fproj=None, relax=40, keep_x0=None):
    """Fill a rectangle a x b with quads. `border` = vertex indices round the rectangle,
    2a + 2b of them, starting at corner (0,0), going (i,0) i=0..a-1, (a,j) j=0..b-1,
    (i,b) i=a..1, (0,j) j=b..1. Interior points by Coons + Laplace, then projected on the
    field `fproj` if given. keep_x0: grid points forced to x = 0 (mirror plane)."""
    per = [(i, 0) for i in range(a)] + [(a, j) for j in range(b)] + \
          [(i, b) for i in range(a, 0, -1)] + [(0, j) for j in range(b, 0, -1)]
    G = {ij: border[t] for t, ij in enumerate(per)}
    X = {ij: M.V[v] for ij, v in G.items()}
    B = [X[(i, 0)] for i in range(a + 1)]
    T = [X[(i, b)] for i in range(a + 1)]
    L = [X[(0, j)] for j in range(b + 1)]
    R = [X[(a, j)] for j in range(b + 1)]
    for i in range(1, a):
        for j in range(1, b):
            u, v = i / a, j / b
            X[(i, j)] = ((1 - v) * B[i] + v * T[i] + (1 - u) * L[j] + u * R[j]
                         - ((1 - u) * (1 - v) * X[(0, 0)] + u * (1 - v) * X[(a, 0)]
                            + (1 - u) * v * X[(0, b)] + u * v * X[(a, b)]))
    inner = [(i, j) for i in range(1, a) for j in range(1, b)]
    for _ in range(relax):
        for (i, j) in inner:
            X[(i, j)] = (X[(i - 1, j)] + X[(i + 1, j)] + X[(i, j - 1)] + X[(i, j + 1)]) / 4
    if fproj is not None and inner:
        Q = sk.project(fproj, np.array([X[ij] for ij in inner]))
        for ij, q in zip(inner, Q):
            X[ij] = q
    for ij in inner:
        p = X[ij]
        if keep_x0 and keep_x0(ij):
            p = p.copy(); p[0] = 0.0
        G[ij] = M.v(p)
    for i in range(a):
        for j in range(b):
            M.f((G[(i, j)], G[(i + 1, j)], G[(i + 1, j + 1)], G[(i, j + 1)]))
    return G


# ------------------------------------------------------------------ limbs
def ring_section(f, origin, n=12, front=(0, 1, 0), side=(1, 0, 0), dense=180, tmax=0.5):
    P, ang = sk.full_section(f, origin, front, side, dense, tmax)
    return P, ang


def angle_of(p, o, front, side):
    d = p - o
    return math.atan2(d @ side, d @ front) % (2 * math.pi)


def transport_frames(normals, front):
    """Parallel-transported (front, side) frames along a list of plane normals."""
    out = []
    n0 = np.asarray(normals[0], float); n0 = n0 / np.linalg.norm(n0)
    fr = np.asarray(front, float) - n0 * (np.asarray(front, float) @ n0)
    fr /= np.linalg.norm(fr)
    prev = n0
    for n in normals:
        n = np.asarray(n, float); n = n / np.linalg.norm(n)
        ax = np.cross(prev, n)
        s_ = np.linalg.norm(ax)
        if s_ > 1e-9:
            ax /= s_
            ang = math.atan2(s_, prev @ n)
            fr = (fr * math.cos(ang) + np.cross(ax, fr) * math.sin(ang)
                  + ax * (ax @ fr) * (1 - math.cos(ang)))
        fr = fr - n * (fr @ n)
        fr /= np.linalg.norm(fr)
        out.append((fr, np.cross(n, fr)))
        prev = n
    return out


def limb_stations(joints, spacing, pivots, fan_steps):
    """Planes along a jointed limb: parallel planes on each straight segment, and at each
    inner joint a fan of planes through a pivot line outside the bend (pivots[i] = its
    distance from the joint, towards the inside of the bend), so no two rings cross.
    Returns [(point, normal, guess_axis_point)]."""
    J = [np.asarray(j, float) for j in joints]
    D = [(J[i + 1] - J[i]) / np.linalg.norm(J[i + 1] - J[i]) for i in range(len(J) - 1)]
    out = []
    start_clear = 0.0
    for i in range(len(D)):
        L = np.linalg.norm(J[i + 1] - J[i])
        end_clear = 0.0
        if i + 1 < len(D):
            bis = D[i + 1] - D[i]
            bis /= np.linalg.norm(bis)
            end_clear = pivots[i] * abs(bis @ D[i]) + 0.01
        sp = spacing[i]
        n = max(1, int(round((L - start_clear - end_clear) / sp)))
        for k in range(n + (1 if i == len(D) - 1 else 0)):
            s_ = start_clear + (L - start_clear - end_clear) * k / n
            p = J[i] + D[i] * s_
            out.append((p, D[i], p))
        if i + 1 < len(D):
            bis = D[i + 1] - D[i]
            bis /= np.linalg.norm(bis)
            P = J[i + 1] + bis * pivots[i]
            ax = np.cross(D[i], D[i + 1]); ax /= np.linalg.norm(ax)
            tot = math.acos(max(-1.0, min(1.0, D[i] @ D[i + 1])))
            for k in range(fan_steps[i] + 1):
                th = tot * k / fan_steps[i]
                d0 = D[i]
                nrm = d0 * math.cos(th) + np.cross(ax, d0) * math.sin(th) + ax * (ax @ d0) * (1 - math.cos(th))
                g = J[i + 1] - nrm * ((J[i + 1] - P) @ nrm)
                out.append((P, nrm, g))
            start_clear = pivots[i] * abs(bis @ D[i + 1]) + 0.01
    return out


def limb_from_hole(M, loop, f, origins, front=(0, 1, 0), side=(1, 0, 0), blend_rings=3,
                   normals=None, tag=None, tmax=0.5):
    """Grow a limb out of the hole `loop` (vertex indices). `origins` = the axis point of
    each ring; the ring planes are horizontal unless `normals` are given, and their
    frames are parallel-transported from `front` so the limb never twists. Returns the
    list of ring index lists."""
    front, side = np.asarray(front, float), np.asarray(side, float)
    n = len(loop)
    if normals is None:
        normals = [(0, 0, 1)] * len(origins)
    frames = transport_frames(normals, front)
    # keep the side on the caller's side
    if frames[0][1] @ side < 0:
        frames = [(fr, -sd) for fr, sd in frames]
    o0 = np.asarray(origins[0], float)
    f0, s0 = frames[0]
    psi = np.array([angle_of(M.V[v], o0, f0, s0) for v in loop])
    d = np.diff(np.unwrap(psi))
    if d.sum() < 0:
        loop = [loop[0]] + loop[:0:-1]
        psi = np.array([angle_of(M.V[v], o0, f0, s0) for v in loop])
    psi_u = np.unwrap(psi)
    rings, prev = [], loop
    for k, o in enumerate(origins):
        o = np.asarray(o, float)
        fr, sd = frames[k]
        P, ang = sk.full_section(f, o, fr, sd, 240, tmax)
        seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
        cum = np.concatenate([[0], np.cumsum(seg)]) / seg.sum()
        a_hole = np.interp(psi_u % (2 * math.pi), np.append(ang, 2 * math.pi), cum)
        a_hole = np.unwrap(a_hole * 2 * math.pi) / (2 * math.pi)
        uni = np.arange(n) / n
        if k == 0:
            off = np.angle(np.exp(2j * math.pi * (a_hole - uni)).mean()) / (2 * math.pi)
        w = min(1.0, (k + 1) / float(blend_rings + 1))
        # the hole's angles only steer the first rings; after that the (transported)
        # frame's own uniform spacing, with ONE offset for the whole limb (no twist)
        a_near = a_hole + np.round((uni + off) - a_hole)
        fr_k = (1 - w) * a_near + w * (uni + off)
        R = sk.polyline_resample(P, fr_k, closed=True)
        ring = [M.v(p) for p in R]
        for j in range(n):
            j2 = (j + 1) % n
            M.f((prev[j], prev[j2], ring[j2], ring[j]), tag)
        rings.append(ring)
        prev = ring
    return rings


def refine_origin(f, p, n, fr, tmax=0.4):
    """Centre a ring origin in its plane: chord middles along the frame's two axes."""
    n = np.asarray(n, float); fr = np.asarray(fr, float)
    sd = np.cross(n, fr)
    p = np.asarray(p, float)
    if f(p[None])[0] >= 0:
        return p
    p = sk.chord_mid(f, p, fr, tmax)
    p = sk.chord_mid(f, p, sd, tmax)
    return p


def cap_ring_flat(M, ring, z=None, tag=None):
    """Close a ring of 4k verts with a k x k quad patch (flattened to z if given)."""
    n = len(ring)
    k = n // 4
    G = rect_patch(M, ring, k, k)
    if z is not None:
        for ij, v in G.items():
            M.V[v] = M.V[v].copy()
            M.V[v][2] = z
    return G


# ------------------------------------------------------------------ mirror / out
def mirror_x(M, eps=1e-6):
    """Mirror the +X half across x = 0, welding the verts on the plane."""
    n = len(M.V)
    remap = {}
    for i in range(n):
        p = M.V[i]
        if abs(p[0]) < eps:
            remap[i] = i
        else:
            q = p.copy(); q[0] = -q[0]
            remap[i] = len(M.V)
            M.V.append(q)
            if i in M.vtag:
                M.vtag[remap[i]] = M.vtag[i]
    nf = len(M.F)
    for k in range(nf):
        fc = M.F[k]
        M.F.append(tuple(remap[i] for i in reversed(fc)))
        if k in M.tag:
            M.tag[len(M.F) - 1] = M.tag[k]
    return M


def relax_on(M, f, verts, iters=3, lam=0.4, fixed=()):
    """Tangential umbrella smoothing of `verts` on the field f (mirror-plane verts stay on
    x = 0, their missing mirrored neighbours counted)."""
    nb = {}
    for fc in M.F:
        for a in range(len(fc)):
            i, j = fc[a], fc[(a + 1) % len(fc)]
            nb.setdefault(i, set()).add(j)
            nb.setdefault(j, set()).add(i)
    verts = [v for v in verts if v not in set(fixed)]
    for _ in range(iters):
        P = np.array([M.V[v] for v in verts])
        tgt = []
        for v in verts:
            on_plane = abs(M.V[v][0]) < 1e-7
            acc, wsum = np.zeros(3), 0.0
            for u in nb.get(v, ()):
                w = 1.0
                if on_plane and abs(M.V[u][0]) > 1e-7:
                    w = 2.0
                acc += M.V[u] * w
                wsum += w
            tgt.append(acc / max(wsum, 1e-9))
        T = np.array(tgt)
        N = sk.normal(f, P)
        D = T - P
        D -= N * (D * N).sum(1, keepdims=True)
        P2 = sk.project(f, P + lam * D, 4)
        for v, p in zip(verts, P2):
            if abs(M.V[v][0]) < 1e-7:
                p = p.copy(); p[0] = 0.0
            M.V[v] = p


def to_object(M, name, default_tag="default", collection=None, recalc=True):
    """A Blender object from the Mesh; each face tag becomes a material slot of that name
    (materials are made empty here and dressed by materials.py)."""
    import bpy, bmesh
    bm = bmesh.new()
    used = set(i for fc in M.F for i in fc)          # the grid points inside limb holes go
    BV = {i: bm.verts.new(tuple(M.V[i])) for i in sorted(used)}
    made = []
    for k, fc in enumerate(M.F):
        try:
            bm.faces.new([BV[i] for i in fc])
            made.append(M.tag.get(k, default_tag))
        except ValueError as e:
            print("face fail", name, k, fc, e)
    tags = []
    for t in made:
        if t not in tags:
            tags.append(t)
    bm.faces.ensure_lookup_table()
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for fce, t in zip(bm.faces, made):
        fce.material_index = tags.index(t)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for t in tags:
        me.materials.append(bpy.data.materials.get(t) or bpy.data.materials.new(t))
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    return ob


def orient(M, f, faces=None, eps=0.004):
    """Flip every face (of `faces`, default all) whose normal points INTO the field f,
    for open sheets laid over a body (recalc cannot tell their outside)."""
    faces = range(len(M.F)) if faces is None else faces
    C, N, K = [], [], []
    for k in faces:
        P = np.array([M.V[i] for i in M.F[k]])
        n = np.zeros(3)
        for a in range(len(P)):
            b = (a + 1) % len(P)
            n += np.cross(P[a], P[b])
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            continue
        C.append(P.mean(0)); N.append(n / ln); K.append(k)
    if not K:
        return 0
    C, N = np.array(C), np.array(N)
    flip = f(C + N * eps) < f(C - N * eps)
    for k, fl in zip(K, flip):
        if fl:
            M.F[k] = M.F[k][::-1]
    return int(flip.sum())
