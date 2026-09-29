"""The man-at-arms ARMOUR over the blueprint base mesh (owner 2026-09-28:
继续，按这个顺序做盔甲). Every plate is a one-sided shell of quads whose free
edges ROLL outward (four extra loops: the steel's visible thickness and the
edge's support loops in one), half-built on +X under a Mirror modifier like the
base. Shapes come from the base mesh's own tables (base_mesh.py), offset a few
millimetres out. Steps, each rebuilt from scratch so it can be looked at:
  1 breastplate, backplate   2 plackart, fauld   3 pauldrons, arms, legs
  4 helmet, gorget, gauntlets, sabatons
    exec(open(".../armour.py").read(), {"STEP": 1})
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

HERE = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
BASE = {"BUILD": False}
exec(open(HERE + "base_mesh.py").read(), BASE)
TORSO, TH = BASE["TORSO"], BASE["TH"]
STEP = globals().get("STEP", 1)
COLL = "Armour"


def lerp(a, b, t):
    return a + (b - a) * t


def bump(x, c, w):
    """1 at c, 0 beyond +-w, smooth."""
    d = abs(x - c) / w
    return 0.0 if d >= 1 else 0.5 + 0.5 * math.cos(math.pi * d)


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def torso_row(z):
    """The torso's section at any height: the base table interpolated."""
    rows = TORSO
    if z <= rows[0][0]:
        return rows[0]
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(lerp(x, y, t) for x, y in zip(a, b))
    return rows[-1]


def torso_at(z, th, off=0.0):
    row = torso_row(z)
    p = BASE["torso_pt"]((z,) + tuple(row[1:]), th)
    yc = (row[2] + row[3]) / 2
    n = Vector((p.x, p.y - yc, 0))
    n = n.normalized() if n.length > 1e-6 else Vector((0, -1, 0))
    return p + n * off, n


# ------------------------------------------------------------------ mesh ----
def normals_of(rows):
    """Outward normals per grid point: the cross of the grid's two directions,
    turned away from the vertical axis through the grid's own centre."""
    R, C = len(rows), len(rows[0])
    cen = sum((p for r in rows for p in r), Vector()) / (R * C)
    out = []
    for i in range(R):
        row = []
        for j in range(C):
            du = rows[i][min(j + 1, C - 1)] - rows[i][max(j - 1, 0)]
            dv = rows[min(i + 1, R - 1)][j] - rows[max(i - 1, 0)][j]
            n = du.cross(dv)
            if n.length < 1e-9:
                n = Vector((rows[i][j].x - cen.x, rows[i][j].y - cen.y, 0))
            n.normalize()
            ref = rows[i][j] - cen
            ref.z *= 0.2
            if n.dot(ref) < 0:
                n = -n
            row.append(n)
        out.append(row)
    return out


def roll(rows, r, end=True, angles=(60, 120, 180, 240), normals=None, taper=0):
    """Extra rows that roll the last (or first) row's edge OUT over the plate.
    taper > 0 fades the roll to nothing over that many points at both ends of
    the edge: where two rolled edges meet at a plate's corner, the second must
    not roll the first again (it curled into a spike)."""
    ns = normals or normals_of(rows)
    i, k = (-1, -2) if end else (0, 1)
    edge, prev, nn = rows[i], rows[k], ns[i]
    C = len(edge)
    new = []
    for a in angles:
        ar = math.radians(a)
        row = []
        for j, (p, q, n) in enumerate(zip(edge, prev, nn)):
            f = 1.0 if not taper else sstep(0.0, 1.0, min(j, C - 1 - j) / float(taper))
            rr = r * max(f, 0.0)
            t = (p - q).normalized()
            row.append(p + t * (rr * math.sin(ar)) + n * (rr * (1 - math.cos(ar))))
        new.append(row)
    return rows + new if end else list(reversed(new)) + rows


def transpose(rows):
    return [list(c) for c in zip(*rows)]


def coll():
    c = bpy.data.collections.get(COLL)
    if not c:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def material(name, rgb, metal=0.0, rough=0.5):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1.0)
    m.metallic = metal
    m.roughness = rough
    return m


STEEL = lambda: material("arm_steel", (0.70, 0.71, 0.73), 0.9, 0.35)
BRASS = lambda: material("arm_brass", (0.72, 0.55, 0.25), 1.0, 0.35)
RIVETS = {}                # host piece -> [(point, normal)], filled while the plates are built


def rivet_rows(host, rows, i, js, toward=None, f=0.0):
    """Rivet sites on row i of a plate grid (before its rolls), at columns js,
    pulled a share f of the way toward row `toward`."""
    ns = normals_of(rows)
    for j in js:
        p = rows[i][j]
        if toward is not None:
            p = p.lerp(rows[toward][j], f)
        RIVETS.setdefault(host, []).append((p.copy(), ns[i][j].copy()))
LEATHER = lambda: material("arm_leather", (0.36, 0.21, 0.12), 0.0, 0.6)
# owner 2026-09-29: the thighs in dark brown leather; a cloak the shield's colour; the shield wooden and old
LEATHER_DARK = lambda: material("arm_leather_dark", (0.17, 0.10, 0.06), 0.0, 0.7)
CLOAK = lambda: material("arm_cloak", (0.10, 0.22, 0.12), 0.0, 0.9)
SHIELD_FACE = lambda: material("arm_shield", (0.30, 0.26, 0.18), 0.0, 0.8)


def rivet_ring(host, rows, i, js, toward=None, f=0.0):
    """rivet_rows for a CLOSED ring grid (a band round a limb): the normals of a ring
    wrap, so they are taken across the seam."""
    R, C = len(rows), len(rows[0])
    for j in js:
        p = rows[i][j]
        if toward is not None:
            p = p.lerp(rows[toward][j], f)
        du = rows[i][(j + 1) % C] - rows[i][(j - 1) % C]
        dv = rows[min(i + 1, R - 1)][j] - rows[max(i - 1, 0)][j]
        n = du.cross(dv).normalized()
        cen = sum((q for q in rows[i]), Vector()) / C
        if n.dot(p - cen) < 0:
            n = -n
        RIVETS.setdefault(host, []).append((p.copy(), n))


def grid_object(name, rows, mat, closed=False, mirror=True):
    old = bpy.data.objects.get(name)
    if old:
        me_old = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        bpy.data.meshes.remove(me_old)
    bm = bmesh.new()
    R = [[bm.verts.new(p) for p in r] for r in rows]
    n = len(rows[0])
    for i in range(len(R) - 1):
        for j in range(n if closed else n - 1):
            j2 = (j + 1) % n
            bm.faces.new((R[i][j], R[i][j2], R[i + 1][j2], R[i + 1][j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    me.materials.append(mat)
    if mirror:
        m = ob.modifiers.new("Mirror", "MIRROR")
        m.use_clip = True
        m.use_mirror_merge = True
        m.merge_threshold = 0.0008
    ob.show_wire = True
    return ob


def tris_of(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    t = sum(len(p.vertices) - 2 for p in me.polygons)
    ev.to_mesh_clear()
    return t


def report(names):
    tot = 0
    for nme in names:
        ob = bpy.data.objects[nme]
        t = tris_of(ob)
        tot += t
        print("  %-18s %5d tris" % (nme, t))
    allt = sum(tris_of(o) for o in coll().objects)
    print("  step total %d tris; all armour so far %d tris" % (tot, allt))


# ------------------------------------------------------------ STEP 1 ----
B_OFF = 0.008            # the breastplate over the base
K_OFF = 0.004            # the backplate, under the breastplate where they overlap


def breast_top(th):
    """The neck opening, then the armhole cut down to the armpit."""
    return 1.50 - 0.09 * sstep(35, 86, th) + 0.01 * sstep(92, 105, th)


def breastplate():
    cols = [0, 12, 24, 36, 48, 60, 72, 84, 95, 105]
    z0 = 1.04
    rows = []
    for k in range(12):
        u = k / 11
        row = []
        for th in cols:
            z = lerp(z0, breast_top(th), u)
            keel = 0.004 * math.exp(-(th / 9.0) ** 2) * sstep(1.10, 1.18, z) * (1 - sstep(1.40, 1.47, z))
            row.append(torso_at(z, th, B_OFF + keel)[0])
        rows.append(row)
    rivet_rows("breastplate", rows, len(rows) - 1, (2, 4, 6, 8), toward=len(rows) - 2, f=0.55)   # the brass round the edges
    rivet_rows("breastplate", transpose(rows), len(cols) - 1, (2, 5, 8), toward=len(cols) - 2, f=0.5)
    rows = roll(rows, 0.0045)                               # the neck and the armholes
    rows = transpose(roll(transpose(rows), 0.0032))          # the flank, over the backplate
    return grid_object("breastplate", rows, STEEL())


def back_top(th):
    return 1.43 + 0.09 * sstep(112, 150, th)


def backplate():
    cols = [95, 108, 121, 134, 147, 160, 170, 180]
    z0 = 1.00
    rows = []
    for k in range(12):
        u = k / 11
        rows.append([torso_at(lerp(z0, back_top(th), u), th, K_OFF)[0] for th in cols])
    rivet_rows("backplate", rows, len(rows) - 1, (1, 3, 5), toward=len(rows) - 2, f=0.55)
    rows = roll(rows, 0.0045)
    return grid_object("backplate", rows, STEEL())


def step1():
    breastplate()
    backplate()
    base = bpy.data.objects.get("base_body")
    if base and base.data.materials:
        base.data.materials[0].diffuse_color = (0.22, 0.21, 0.20, 1.0)      # mail and arming doublet, under the plate
        base.show_wire = False
    print("STEP 1")
    report(["breastplate", "backplate"])


if STEP >= 1:
    step1()


# ------------------------------------------------------------ STEP 2 ----
P_OFF = 0.014            # the plackart over the breastplate


def plackart_top(th):
    return 1.27 - 0.15 * (th / 80.0) ** 0.75          # a pointed cusp, not an arc


def plackart():
    cols = [0, 10, 20, 30, 40, 50, 60, 70, 80]
    rows = []
    for k in range(8):
        u = k / 7
        row = []
        for th in cols:
            z = lerp(1.045, plackart_top(th), u)
            keel = 0.004 * math.exp(-(th / 9.0) ** 2) * sstep(1.10, 1.18, z)
            row.append(torso_at(z, th, P_OFF + keel)[0])
        rows.append(row)
    rivet_rows("plackart", rows, len(rows) - 1, (1, 3, 5, 7), toward=len(rows) - 2, f=0.45)
    rows = roll(rows, 0.004)
    return grid_object("plackart", rows, STEEL())


def skirt_at(z, th, off):
    """Below the pelvis's last row the fauld flares out on its own profile."""
    if z >= TORSO[0][0]:
        return torso_at(z, th, off)[0]
    d = TORSO[0][0] - z
    z0, hw, yf, yb = TORSO[0]
    row = (z, hw + d * 0.18, yf - d * 0.22, yb + d * 0.15)
    p = BASE["torso_pt"](row, th)
    yc = (row[2] + row[3]) / 2
    n = Vector((p.x, p.y - yc, 0)).normalized() if th not in (0, 180) else Vector((0, -1 if th == 0 else 1, 0))
    return p + n * off


FAULD_N, FAULD_TOP, FAULD_PITCH, FAULD_H = 5, 1.075, 0.075, 0.085


def fauld():
    """Two waist lames round the body; below them the front splits into two
    TASSETS either side of an arch over the mail, and the back ends in a
    culet with a point at the middle."""
    names = []
    for k in range(FAULD_N):
        zt = FAULD_TOP - FAULD_PITCH * k
        zb = zt - FAULD_H
        o0 = 0.019 + 0.004 * k                  # each lame UNDER the one above, like roof tiles
        start = {2: 13, 3: 22, 4: 27}.get(k, 0) # the arch: ~18 cm wide at the bottom
        cols = [start] + [c for c in range(15, 181, 15) if c > start]
        rows = []
        for u in (0.0, 0.5, 1.0):
            row = []
            for th in cols:
                zz = lerp(zt, zb, u)
                if k >= 2:
                    zz -= u * 0.030 * math.exp(-((180 - th) / 22.0) ** 2)   # the culet's point
                row.append(skirt_at(zz, th, o0 + 0.008 * u))
            rows.append(row)
        rivet_rows("fauld_%d" % k, rows, 1, range(1, len(cols), 2))
        rows = roll(rows, 0.0030)
        nm = "fauld_%d" % k
        grid_object(nm, rows, STEEL())
        names.append(nm)
    # the tassets: two more lames in front of each thigh, hung from the last
    for k in range(2):
        zt = FAULD_TOP - FAULD_PITCH * (FAULD_N + k)
        zb = zt - FAULD_H
        o0 = 0.019 + 0.004 * (FAULD_N + k)
        cols = [27, 38, 50, 62, 74, 86, 98]
        rows = [[skirt_at(lerp(zt, zb, u), th, o0 + 0.008 * u) for th in cols] for u in (0.0, 0.5, 1.0)]
        rivet_rows("tasset_%d" % k, rows, 1, (1, 3, 5))
        rows = roll(rows, 0.0030)
        rows = transpose(roll(roll(transpose(rows), 0.0025, taper=3), 0.0025, end=False, taper=3))
        nm = "tasset_%d" % k
        grid_object(nm, rows, STEEL())
        names.append(nm)
    return names


def step2():
    plackart()
    names = fauld()
    print("STEP 2")
    report(["plackart"] + names)


if STEP >= 2:
    step2()


# ------------------------------------------------------------ STEP 3 ----
S_, EL_, W_ = BASE["S"], BASE["EL"], BASE["W"]
D1, D2 = (EL_ - S_).normalized(), (W_ - EL_).normalized()
ARM_R = [(0.0, 0.074), (0.3, 0.063), (0.8, 0.055), (1.0, 0.058), (1.2, 0.052), (1.55, 0.047), (2.0, 0.038)]


def table(keys, x):
    if x <= keys[0][0]:
        return keys[0][1]
    for (a, va), (b, vb) in zip(keys, keys[1:]):
        if a <= x <= b:
            return lerp(va, vb, (x - a) / (b - a))
    return keys[-1][1]


def arm_frame(u):
    """u 0..1 the upper arm (shoulder to elbow), 1..2 the forearm (elbow to wrist)."""
    p = S_.lerp(EL_, u) if u <= 1 else EL_.lerp(W_, u - 1)
    t = D1.lerp(D2, sstep(0.88, 1.12, u)).normalized()
    o = Vector((1, 0, 0)) - t * t.x
    o.normalize()
    f = t.cross(o)
    if f.y > 0:
        f = -f
    return p, t, f, o, table(ARM_R, u)


def arm_pt(u, psi, off):
    p, t, f, o, r = arm_frame(u)
    a = math.radians(psi)
    return p + (f * math.cos(a) + o * math.sin(a)) * (r + off)


def ring_rows(us, fn, n=12):
    return [[fn(u, 360.0 * j / n) for j in range(n)] for u in us]


def band(name, us, fn, r_roll=0.0022, roll_top=False, roll_bottom=True, n=12, mat=None, rivet=None):
    """rivet: (row, columns) of brass rivets, pulled a third of the way in from that edge."""
    rows = ring_rows(us, fn, n)
    if rivet:
        i, js = rivet
        rivet_ring(name, rows, i, js, toward=1 if i == 0 else i - 1, f=0.35)
    if roll_bottom:
        rows = roll(rows, r_roll)
    if roll_top:
        rows = roll(rows, r_roll, end=False)
    return grid_object(name, rows, mat or STEEL(), closed=True)


def disc(name, c, n, radius, dome, segs=12, r_roll=0.003):
    """A shallow round plate: a besagew, a couter's or a poleyn's wing."""
    n = n.normalized()
    a = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
    b = n.cross(a)
    rows = []
    for k, fr in enumerate((0.3, 0.65, 1.0)):
        h = dome * (1 - fr * fr)
        rows.append([c + n * h + (a * math.cos(2 * math.pi * j / segs) + b * math.sin(2 * math.pi * j / segs)) * radius * fr
                     for j in range(segs)])
    rows = roll(rows, r_roll)
    ob = grid_object(name, rows, STEEL(), closed=True)
    # the centre: one fan, the only triangles on the plate
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    ring = [v for v in bm.verts if (v.co - (c + n * dome * (1 - 0.09))).length < radius * 0.31 and len(v.link_faces) <= 2][:segs]
    ctr = bm.verts.new(c + n * dome)
    ring.sort(key=lambda v: math.atan2((v.co - c).dot(b), (v.co - c).dot(a)))
    for j in range(len(ring)):
        bm.faces.new((ring[j], ring[(j + 1) % len(ring)], ctr))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data); bm.free()
    return ob


_BVH = {}


def body_bvh():
    """The base body's surface (mirror and subdivision applied), for wrapping plates onto it."""
    if "t" not in _BVH:
        from mathutils.bvhtree import BVHTree
        ob = bpy.data.objects["base_body"]
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        verts = [ob.matrix_world @ v.co for v in me.vertices]
        polys = [tuple(p.vertices) for p in me.polygons]
        ev.to_mesh_clear()
        _BVH["t"] = BVHTree.FromPolygons(verts, polys)
    return _BVH["t"]


def wrap(p, off):
    loc, nor, _, _ = body_bvh().find_nearest(p)
    if (p - loc).dot(nor) < 0 and (p - loc).length > 0.002:
        pass
    return loc + nor.normalized() * off


def relax(rows, k=0.5, iters=2, edges=True):
    """Laplacian smoothing of a grid; the four boundary lines are smoothed ALONG
    themselves (their corners fixed), so a wrapped plate's outline runs clean."""
    R, C = len(rows), len(rows[0])
    for _ in range(iters):
        new = [list(r) for r in rows]
        for i in range(1, R - 1):
            for j in range(1, C - 1):
                avg = (rows[i - 1][j] + rows[i + 1][j] + rows[i][j - 1] + rows[i][j + 1]) / 4
                new[i][j] = rows[i][j].lerp(avg, k)
        if edges:
            for i in (0, R - 1):
                for j in range(1, C - 1):
                    new[i][j] = rows[i][j].lerp((rows[i][j - 1] + rows[i][j + 1]) / 2, k)
            for j in (0, C - 1):
                for i in range(1, R - 1):
                    new[i][j] = rows[i][j].lerp((rows[i - 1][j] + rows[i + 1][j]) / 2, k)
        rows = new
    return rows


def fan(name, c, n, up, radius, spread=150, flutes=5, dome=0.018):
    """A gothic fan wing: a cupped, fluted sector opening along `up`, its rim rolled."""
    n = n.normalized()
    u = (up - n * up.dot(n)).normalized()
    v = n.cross(u)
    rows = []
    cols = [lerp(-spread / 2, spread / 2, k / 10) for k in range(11)]
    for fr in (0.12, 0.35, 0.6, 0.82, 1.0):
        row = []
        for a in cols:
            ar = math.radians(a)
            d = u * math.cos(ar) + v * math.sin(ar)
            flute = 0.0035 * math.cos(math.pi * flutes * a / spread) ** 2 * fr
            h = dome * (1 - fr * fr) + flute
            row.append(c + d * radius * fr + n * h)
        rows.append(row)
    RIVETS.setdefault(name, []).append((c + n * dome, n.copy()))
    rows = roll(rows, 0.0028, taper=2)
    return grid_object(name, rows, STEEL())


def pauldron():
    """A big shell over the shoulder: a chart swept front (u -) to back (u +) and from the
    neck side over the top down the arm (lam), each point pulled onto the body's nearest
    surface and stood off it, the edges flaring a little further out (owner's critic:
    'mushroom caps' - the blueprint's sweep onto the breast and the shoulder blade)."""
    C = Vector((0.175, -0.005, 1.37))
    RX, RY, RZ = 0.21, 0.27, 0.165
    phis = [-80, -67, -54, -41, -28, -14, 0, 14, 28, 41, 54, 67, 80]
    lams = [-30, -18, -6, 6, 18, 30, 42, 54, 66, 78, 90, 102, 114]
    rows = []
    for li, lam in enumerate(lams):
        L = math.radians(lam)
        row = []
        for pi_, ph in enumerate(phis):
            P = math.radians(ph)
            guess = C + Vector((math.cos(P) * math.sin(L) * RX, -math.sin(P) * RY, math.cos(P) * math.cos(L) * RZ))
            eu, ev_ = abs(ph) / 80.0, li / (len(lams) - 1)
            flare = 0.010 * max(eu, ev_) ** 3
            row.append(wrap(guess, 0.020 + flare))
        rows.append(row)
    rows = relax(rows, 0.5, 8)
    rows = [[wrap(p, 0.0) + (p - wrap(p, 0.0)).normalized() * max(0.018, (p - wrap(p, 0.0)).length) for p in r] for r in rows]
    rows = relax(rows, 0.5, 3)
    rivet_rows("pauldron", rows, len(rows) - 1, range(2, len(rows[0]) - 2, 2), toward=len(rows) - 2, f=0.55)
    rows = roll(rows, 0.0035, taper=3)             # the rim over the arm
    rows = roll(rows, 0.0030, end=False, taper=3)  # the rim at the neck
    rows = transpose(roll(roll(transpose(rows), 0.0030, taper=3), 0.0030, end=False, taper=3))   # front and back rims
    grid_object("pauldron", rows, STEEL())
    disc("besagew", S_ + Vector((-0.045, -0.115, -0.085)), Vector((-0.25, -1.0, 0.05)), 0.050, 0.012)
    return ["pauldron", "besagew"]


def arm_pieces():
    names = []
    for k in range(3):                                      # the pauldron's lames, each under the one above
        u0 = 0.30 + 0.09 * k
        off = 0.024 - 0.004 * k
        nm = "pauldron_lame_%d" % k
        band(nm, [u0, u0 + 0.13], lambda u, ps, off=off: arm_pt(u, ps, off), rivet=(1, (0, 2, 4)))
        names.append(nm)
    band("rerebrace", [0.56, 0.70, 0.86], lambda u, ps: arm_pt(u, ps, 0.010), roll_top=True, rivet=(0, (0, 2, 4)))
    names.append("rerebrace")

    def couter(u, ps):
        a = math.radians(ps)
        point = 0.020 * max(0.0, -math.cos(a)) ** 2 * math.exp(-((u - 1.0) / 0.07) ** 2)   # the point of the elbow, behind
        return arm_pt(u, ps, 0.016 + point)
    band("couter", [0.84, 0.92, 1.0, 1.08, 1.16], couter, roll_top=True, rivet=(0, (0, 3)))
    p, t, f, o, r = arm_frame(1.0)
    fan("couter_wing", p + o * (r + 0.012), o - f * 0.35, -f + t * 0.25, 0.072, 150, 5, 0.020)
    names += ["couter", "couter_wing"]
    band("vambrace_upper", [1.14, 1.35, 1.58], lambda u, ps: arm_pt(u, ps, 0.010), roll_top=False, rivet=(2, (0, 3)))
    band("vambrace_lower", [1.53, 1.75, 1.97], lambda u, ps: arm_pt(u, ps, 0.015), roll_top=True, rivet=(2, (0, 2, 4)))
    names += ["vambrace_upper", "vambrace_lower"]
    return names


LEG_T = BASE["LEG"]


def leg_row(z):
    rows = sorted(LEG_T)
    if z <= rows[0][0]:
        return rows[0]
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(lerp(x, y, t) for x, y in zip(a, b))
    return rows[-1]


def leg_pt(z, phi, off):
    _, cx, cy, rx, ry = leg_row(z)
    p = math.radians(phi)
    return Vector((cx + (rx + off) * math.sin(p), cy - (ry + off) * math.cos(p), z))


def greave_pt(z, ph):
    a = math.radians(ph)
    calf = 0.020 * math.exp(-((z - 0.31) / 0.07) ** 2) * (0.35 + 0.65 * max(0.0, -math.cos(a)))
    ankle = -0.012 * sstep(0.19, 0.12, z)
    return leg_pt(z, ph, 0.010 + calf + ankle)


def leg_pieces():
    """Owner 2026-09-29: the thigh wears dark brown LEATHER over the mail (no steel
    cuisse); the knee is its own plate, strapped round the back of the knee; the greave
    stops short of it, so knee plate and greave are two pieces with the leg between."""
    names = []
    # the leather thigh: a closed sleeve, quilted in vertical channels, its hems turned
    n = 16

    def thigh(z, ph):
        quilt = 0.0028 * (0.5 + 0.5 * math.cos(math.radians(ph) * 8)) * sstep(0.83, 0.79, z) * sstep(0.55, 0.59, z)
        return leg_pt(z, ph, 0.011 + quilt)
    rows = [[thigh(z, 360.0 * j / n) for j in range(n)] for z in (0.84, 0.79, 0.73, 0.67, 0.61, 0.555)]
    rows = roll(roll(rows, 0.0022), 0.0022, end=False)
    grid_object("cuisse", rows, LEATHER_DARK(), closed=True)

    def poleyn(z, ph):
        a = math.radians(ph)
        cap = 0.030 * max(0.0, math.cos(a)) ** 4 * math.exp(-((z - 0.485) / 0.036) ** 2)
        return leg_pt(z, ph, 0.020 + cap)
    cols = [-105, -80, -55, -30, -10, 10, 30, 55, 80, 105]
    rows = [[poleyn(z, ph) for ph in cols] for z in (0.555, 0.53, 0.505, 0.475, 0.45, 0.425)]
    rivet_rows("poleyn", rows, 0, (1, 3, 6, 8), toward=1, f=0.45)
    rivet_rows("poleyn", rows, len(rows) - 1, (1, 8), toward=len(rows) - 2, f=0.45)
    rows = roll(roll(rows, 0.0035), 0.0035, end=False)
    rows = transpose(roll(roll(transpose(rows), 0.003, taper=3), 0.003, end=False, taper=3))
    grid_object("poleyn", rows, STEEL())
    _, cx, cy, rx, ry = leg_row(0.49)
    fan("poleyn_wing", Vector((cx + rx + 0.024, cy + 0.004, 0.49)), Vector((1, -0.2, 0)), Vector((0, 1, 0.15)), 0.062, 150, 5, 0.016)
    # two leather straps round the back of the knee, under the plate's upper and lower edges
    for k, zc in enumerate((0.535, 0.445)):
        band("knee_strap_%d" % k, [zc + 0.009, zc, zc - 0.009], lambda z, ph: leg_pt(z, ph, 0.016 + 0.0015 * (z == zc)),
             roll_bottom=False, mat=LEATHER())
        names.append("knee_strap_%d" % k)
    band("greave", [0.395, 0.36, 0.33, 0.29, 0.25, 0.20, 0.15, 0.10], greave_pt, roll_top=True, rivet=(0, (0, 2, 3, 4)))
    names += ["cuisse", "poleyn", "poleyn_wing", "greave"]
    return names


def step3():
    names = pauldron() + arm_pieces() + leg_pieces()
    print("STEP 3")
    report(names)


if STEP >= 3:
    step3()


# ------------------------------------------------------------ STEP 4 ----
def cap_grid(bm, ring, dome_dir, dome, iters=30):
    """Close a ring of 4n verts with an n x n grid of QUADS (no pole): the ring
    is the grid's perimeter, the inner verts relaxed, then domed."""
    n = len(ring) // 4
    per = []
    for i in range(n):
        per.append((i, 0))
    for j in range(n):
        per.append((n, j))
    for i in range(n, 0, -1):
        per.append((i, n))
    for j in range(n, 0, -1):
        per.append((0, j))
    G = {}
    for k, ij in enumerate(per):
        G[ij] = ring[k]
    inner = [(i, j) for i in range(1, n) for j in range(1, n)]
    pos = {ij: sum((v.co for v in ring), Vector()) / len(ring) for ij in inner}
    for _ in range(iters):
        for (i, j) in inner:
            nb = [(i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1)]
            pos[(i, j)] = sum(((G[q].co if q in G else pos[q]) for q in nb), Vector()) / 4
    for (i, j) in inner:
        cx, cy = (i / n - 0.5) * 2, (j / n - 0.5) * 2
        h = dome * (1 - cx * cx) * (1 - cy * cy)
        G[(i, j)] = bm.verts.new(pos[(i, j)] + dome_dir * h)
    faces = []
    for i in range(n):
        for j in range(n):
            faces.append(bm.faces.new((G[(i, j)], G[(i + 1, j)], G[(i + 1, j + 1)], G[(i, j + 1)])))
    return faces


def mesh_object(name, bm, mats, mirror=False):
    old = bpy.data.objects.get(name)
    if old:
        me_old = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        bpy.data.meshes.remove(me_old)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    for m in mats:
        me.materials.append(m)
    if mirror:
        md = ob.modifiers.new("Mirror", "MIRROR")
        md.use_clip = True
        md.use_mirror_merge = True
    ob.show_wire = True
    return ob


DARK = lambda: material("arm_dark", (0.05, 0.05, 0.05), 0.0, 0.8)

# the close helmet: z, half width, front, back   (front / side blueprint)
HELM = [(1.54, 0.085, -0.105, 0.080),
        (1.56, 0.094, -0.125, 0.086),
        (1.59, 0.104, -0.148, 0.093),
        (1.62, 0.110, -0.160, 0.098),
        (1.645, 0.113, -0.160, 0.099),
        (1.665, 0.113, -0.156, 0.099),
        (1.678, 0.113, -0.150, 0.099),
        (1.686, 0.112, -0.146, 0.098),
        (1.694, 0.111, -0.142, 0.097),
        (1.702, 0.110, -0.137, 0.096),
        (1.72, 0.106, -0.125, 0.093),
        (1.745, 0.095, -0.103, 0.085),
        (1.77, 0.075, -0.075, 0.070),
        (1.785, 0.052, -0.048, 0.050)]
BRIM_Z = 1.690           # the brim's lower edge: the eye slit opens under it
FACE_TH = 76             # the face opening, either side of the front
FACE_SINK = 0.018        # how far the face is set back behind the visor (dark, seen through the slit)


def helmet():
    """Owner 2026-09-29: a real eye slit between the visor and the brim. The skull's
    face is set back (dark, the helmet's inside) so the gap under the brim is OPEN: you
    look through it into shadow. The brim over it juts forward with a turned lip."""
    bm = bmesh.new()
    N = 24
    zs = [r[0] for r in HELM]
    k = next(i for i, z in enumerate(zs) if z > BRIM_Z)            # the first row above the brim
    table = HELM[:k] + [(BRIM_Z + 0.0005,) + tuple(HELM[k][1:])] + HELM[k:]
    rows, par = [], []
    for i, (z, hw, yf, yb) in enumerate(table):
        row, pr = [], []
        for j in range(N):
            th = 360.0 * j / N
            thf = th if th <= 180 else 360 - th                # angle from the front, either side
            t = math.radians(th)
            s, c = math.sin(t), math.cos(t)
            yc = (yf + yb) / 2
            x = hw * math.copysign(abs(s) ** 0.9, s)
            y = yc + (yf - yc) * abs(c) ** 0.9 if c >= 0 else yc + (yb - yc) * abs(c) ** 0.9
            p = Vector((x, y, z))
            n = Vector((x, y - yc, 0)).normalized()
            face = sstep(FACE_TH + 8, FACE_TH - 6, thf)
            if z < BRIM_Z:
                p -= n * FACE_SINK * face                            # the face set back
            elif z < BRIM_Z + 0.006:
                p += n * 0.008 * face                                # the brim's lip, forward
            comb = 0.007 * (math.exp(-(thf / 11.0) ** 2) + math.exp(-((180 - thf) / 11.0) ** 2)) * sstep(1.66, 1.72, z)
            p.z += comb
            row.append(p)
            pr.append((z, thf))
        rows.append(row)
        par.append(pr)
    rows = roll(rows, 0.0045, end=False)                         # the lower edge rolled
    par = [par[0]] * 4 + par
    V = [[bm.verts.new(p) for p in r] for r in rows]
    for i in range(len(V) - 1):
        for j in range(N):
            f = bm.faces.new((V[i][j], V[i][(j + 1) % N], V[i + 1][(j + 1) % N], V[i + 1][j]))
            zt, tf = par[i + 1][j]
            tf2 = par[i + 1][(j + 1) % N][1]
            if 1.60 < zt <= BRIM_Z + 0.001 and max(tf, tf2) < FACE_TH + 4:
                f.material_index = 1                                 # the inside of the helmet
    rivet_rows_helm()
    cap = cap_grid(bm, V[-1], Vector((0, 0, 1)), 0.022, iters=60)
    done = set()
    for f in cap:
        for v in f.verts:
            if v in done or v in V[-1]:
                continue
            done.add(v)
            v.co.z += 0.007 * math.exp(-(v.co.x / 0.022) ** 2)
    return mesh_object("helmet", bm, [STEEL(), DARK()])


def rivet_rows_helm():
    """Brass rivets round the skull's lower rim behind the visor, and along the brim."""
    for th in (104, 128, 152, 170):
        p = helm_at(1.556, th, 0.001, beak=False)
        _, hw, yf, yb = helm_row(1.556)
        RIVETS.setdefault("helmet", []).append((p, Vector((p.x, p.y - (yf + yb) / 2, 0)).normalized()))
    for th in (20, 44, 66):
        p = helm_at(BRIM_Z + 0.009, th, 0.004, beak=False)
        _, hw, yf, yb = helm_row(BRIM_Z + 0.009)
        RIVETS.setdefault("helmet", []).append((p, Vector((p.x, p.y - (yf + yb) / 2, 0)).normalized()))


def gorget():
    names = []
    for k, (zt, zb, o0, o1) in enumerate(((1.565, 1.515, 0.010, 0.014), (1.53, 1.48, 0.016, 0.020))):
        cols = list(range(0, 181, 15))
        rows = [[torso_at(lerp(zt, zb, u), th, lerp(o0, o1, u))[0] for th in cols] for u in (0.0, 0.5, 1.0)]
        rivet_rows("gorget_%d" % k, rows, 1, (2, 6, 10))
        rows = roll(rows, 0.0035)
        nm = "gorget_%d" % k
        grid_object(nm, rows, STEEL())
        names.append(nm)
    return names


SHAFT_R = 0.0165           # the spear's shaft, and the shield's grip bar


def fist_frame():
    """The fist round a grip channel: its axis g is the hand's FRONT at rest (a hanging
    arm), so a forearm raised forward turns it upright. Around the channel, phi 0 is the
    outside of the hand (o), 90 its far end (t), 180 the palm side, 270 the wrist."""
    p, t, f, o, _ = arm_frame(2.0)
    C = p + t * 0.058
    return C, t, f, o


def gauntlet():
    bm = bmesh.new()
    N = 12
    rows = []
    for u, off in ((1.93, 0.019), (1.98, 0.013), (2.05, 0.009), (2.12, 0.007)):     # the bell cuff
        rows.append([arm_pt(u, 360.0 * j / N, off) for j in range(N)])
    rows = roll(rows, 0.0035, end=False)                                             # its mouth rolled
    V = [[bm.verts.new(p) for p in r] for r in rows]
    for i in range(len(V) - 1):
        for j in range(N):
            bm.faces.new((V[i][j], V[i][(j + 1) % N], V[i + 1][(j + 1) % N], V[i + 1][j]))
    C, t, f, o = fist_frame()
    g = f

    def at(phi, h, r):
        a = math.radians(phi)
        return C + (o * math.cos(a) + t * math.sin(a)) * r + g * h

    def grid(rows_, closed=False):
        Vg = [[bm.verts.new(q) for q in r] for r in rows_]
        n = len(rows_[0])
        for i in range(len(Vg) - 1):
            for j in range(n if closed else n - 1):
                j2 = (j + 1) % n
                bm.faces.new((Vg[i][j], Vg[i][j2], Vg[i + 1][j2], Vg[i + 1][j]))
        return Vg
    # the fingers: one mitten band curled round the channel, a groove between fingers,
    # its lames stepping along the curl
    ZHI, ZLO, R_IN, TH = 0.044, -0.048, SHAFT_R + 0.0012, 0.024
    NF, NL = 4, 4

    def r_out(phi, h):
        u = (phi - 10) / 202.0
        lame = 0.0013 * ((u * NL) % 1.0) ** 2
        fz = (ZHI - h) / (ZHI - ZLO) * NF
        d = min(fz % 1.0, 1.0 - fz % 1.0)
        groove = (0.0040 * max(0.0, 1 - d / 0.22) ** 1.5) if 0.5 < fz < NF - 0.5 else 0.0
        return R_IN + TH + lame - groove - 0.0025 * sstep(0.55, 1.0, (ZHI - h) / (ZHI - ZLO))
    NS = 16
    band = []
    for phi in [10 + 202.0 * k / 12 for k in range(13)]:
        loop = []
        for k in range(NS):
            a = 2 * math.pi * k / NS
            c, s_ = math.cos(a), math.sin(a)
            h = (ZHI + ZLO) / 2 + (ZHI - ZLO) / 2 * math.copysign(abs(s_) ** 0.62, s_)
            ro = r_out(phi, h)
            r = (R_IN + ro) / 2 + (ro - R_IN) / 2 * math.copysign(abs(c) ** 0.62, c)
            loop.append(at(phi, h, r))
        band.append(loop)
    Vb = grid(band, closed=True)
    # close the band's two ends
    for Vend, sgn in ((Vb[0], 1), (Vb[-1], -1)):
        ctr = bm.verts.new(sum((v.co for v in Vend), Vector()) / NS)
        for k in range(NS):
            bm.faces.new((Vend[k], Vend[(k + 1) % NS], ctr))
    # the knuckle plate and the back of the hand, one sheet from the wrist to the knuckles
    sheet = []
    for kz in range(7):
        v = kz / 6
        row = []
        for kp in range(9):
            c = kp / 8                                        # 0 at the wrist side, 1 at the knuckles
            phi = lerp(-88, 34, c)
            half = lerp(0.034, 0.047, c ** 0.6)
            h = (ZHI + ZLO) / 2 + half * (2 * v - 1)
            fz = (ZHI - h) / (ZHI - ZLO) * NF
            knuck = 0.0035 * max(bump(fz, i + 0.5, 0.42) for i in range(NF)) * sstep(0.55, 0.8, c) * (1 - sstep(0.95, 1.0, c))
            rr = lerp(0.036, R_IN + TH + 0.0035, sstep(0.0, 0.7, c)) + knuck + 0.004 * math.sin(v * math.pi)
            row.append(at(phi, h, rr))
        sheet.append(row)
    sheet = roll(transpose(sheet), 0.0025)                    # the knuckles' edge turned
    grid(sheet)
    # the thumb: from the palm side up and over the index finger
    T = [at(262, ZHI - 0.004, R_IN + 0.013), at(222, ZHI + 0.006, R_IN + TH * 0.8),
         at(172, ZHI + 0.009, R_IN + TH * 0.75), at(128, ZHI + 0.008, R_IN + TH * 0.7),
         at(100, ZHI + 0.005, R_IN + TH * 0.6)]
    th_rows = []
    for k, c in enumerate(T):
        sc_ = 1.0 - 0.25 * k / (len(T) - 1)
        d = (T[min(k + 1, len(T) - 1)] - T[max(k - 1, 0)]).normalized()
        sv = d.cross(g).normalized()
        up = sv.cross(d).normalized()
        th_rows.append([c + sv * (0.0092 * sc_ * math.cos(2 * math.pi * j / 8)) + up * (0.0078 * sc_ * math.sin(2 * math.pi * j / 8))
                        for j in range(8)])
    Vt = grid(th_rows, closed=True)
    tip = bm.verts.new(T[-1] + (T[-1] - T[-2]).normalized() * 0.006)
    for j in range(8):
        bm.faces.new((Vt[-1][j], Vt[-1][(j + 1) % 8], tip))
    return mesh_object("gauntlet", bm, [STEEL()], mirror=True)


SAB = [  # y, half width, top z  (the sole at 0.004); pairs make each lame's step
    (0.078, 0.046, 0.072), (0.050, 0.058, 0.150), (0.012, 0.062, 0.150), (-0.020, 0.058, 0.112),
    (-0.024, 0.060, 0.110), (-0.046, 0.058, 0.094), (-0.050, 0.060, 0.092), (-0.072, 0.056, 0.078),
    (-0.076, 0.058, 0.076), (-0.098, 0.052, 0.064), (-0.102, 0.054, 0.062), (-0.124, 0.046, 0.052),
    (-0.150, 0.036, 0.040), (-0.176, 0.024, 0.030), (-0.198, 0.012, 0.022), (-0.212, 0.004, 0.016)]


def sabaton():
    bm = bmesh.new()
    N = 12
    cx = 0.135
    rows = []
    for y, w, top in SAB:
        zc, hh = (top + 0.004) / 2, (top - 0.004) / 2
        row = []
        for j in range(N):
            a = 2 * math.pi * j / N
            s, c = math.sin(a), math.cos(a)
            row.append(Vector((cx + w * math.copysign(abs(s) ** 0.6, s), y, zc + hh * math.copysign(abs(c) ** 0.55, c))))
        rows.append(row)
    V = [[bm.verts.new(p) for p in r] for r in rows]
    for i in range(len(V) - 1):
        for j in range(N):
            f = bm.faces.new((V[i][j], V[i][(j + 1) % N], V[i + 1][(j + 1) % N], V[i + 1][j]))
            if all(v.co.z < 0.012 for v in f.verts):
                f.material_index = 1
    cap_grid(bm, V[0], Vector((0, 1, 0)), 0.010)
    cap_grid(bm, V[-1], Vector((0, -1, 0)), 0.008)
    return mesh_object("sabaton", bm, [STEEL(), LEATHER()], mirror=True)


def helm_row(z):
    rows = HELM
    if z <= rows[0][0]:
        return rows[0]
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(lerp(x, y, t) for x, y in zip(a, b))
    return rows[-1]


def helm_at(z, th, off, beak=True):
    """The skull's surface without the slit: th from the front, signed (+ his left)."""
    _, hw, yf, yb = helm_row(z)
    t = math.radians(th)
    s, c = math.sin(t), math.cos(t)
    yc = (yf + yb) / 2
    x = hw * math.copysign(abs(s) ** 0.9, s)
    y = yc + (yf - yc) * abs(c) ** 0.9 if c >= 0 else yc + (yb - yc) * abs(c) ** 0.9
    if beak:
        y -= 0.020 * math.exp(-((z - 1.645) / 0.04) ** 2) * math.exp(-(abs(th) / 16.0) ** 2)
    n = Vector((x, y - yc, 0)).normalized()
    return Vector((x, y, z)) + n * off


VIS_Z0, VIS_Z1 = 1.592, 1.667   # the visor's chin and its upper lip (the eye slit is between it and the brim)
VIS_SIDE = 64                   # where its flat cheeks meet the skull's curve


def vis_proj(z):
    """How far the ridge stands out: little at the chin, most at the upper lip, so the
    visor's face slants UP and forward to a point under the slit (owner 2026-09-29)."""
    return lerp(0.014, 0.036, (z - VIS_Z0) / (VIS_Z1 - VIS_Z0))    # owner 2026-09-29: 面罩太突出了，收进去一点


def vis_pt(z, t, side=1):
    """t 0 the ridge, 1 the cheek's end at VIS_SIDE; beyond 1 it follows the skull back
    to the pivot. The cheeks are STRAIGHT in plan (a prow, not a bowl)."""
    lift = 0.009 * sstep(1.62, VIS_Z0, z)                    # clear of the bevor at the chin
    if t <= 1.0:
        ridge = helm_at(z, 0, 0.006 + vis_proj(z), beak=False)
        cheek = helm_at(z, side * VIS_SIDE, 0.007 + lift, beak=False)
        p = ridge.lerp(cheek, t)
        d = cheek - ridge
        out = Vector((d.y, -d.x, 0)).normalized() * side     # the chord's outward normal in plan
        if out.y > 0.3:
            out = -out
        p = p + out * 0.004 * math.sin(math.pi * t)          # a faint belly on each cheek
        return clear_of_skull(p, z, vis_min(z))
    th = VIS_SIDE + (t - 1.0) * 30.0
    return helm_at(z, side * th, max(0.007 + lift, vis_min(z) * sstep(2.0, 1.0, t)), beak=False)


def vis_min(z):
    """The least the visor stands off the skull: over the bevor's top near the chin."""
    return lerp(0.009, 0.019, sstep(1.640, 1.622, z))


def clear_of_skull(p, z, off):
    """Push p out along the skull's own normal until it stands `off` clear of it (a
    straight cheek would cut into the round skull between the ridge and the side)."""
    _, hw, yf, yb = helm_row(z)
    yc = (yf + yb) / 2
    ang = math.atan2(p.x, -(p.y - yc))
    best = min((helm_at(z, th, off, beak=False) for th in [a * 0.5 for a in range(-200, 201)]),
               key=lambda q: abs(math.atan2(q.x, -(q.y - yc)) - ang))
    rp = Vector((p.x, p.y - yc, 0)).length
    rq = Vector((best.x, best.y - yc, 0)).length
    if rp < rq:
        d = Vector((p.x, p.y - yc, 0)).normalized()
        p = Vector((d.x * rq, yc + d.y * rq, p.z))
    return p


def visor():
    """The pointed visor: two flat cheeks meeting in a sharp ridge, jutting forward as it
    rises, its upper lip turned; breaths (air holes) pierce both cheeks."""
    ts = [2.0, 1.5, 1.0, 0.8, 0.6, 0.4, 0.2, 0.0]
    cols = [(t, -1) for t in ts] + [(t, 1) for t in reversed(ts[:-1])]
    rows = []
    for z in [lerp(VIS_Z0, VIS_Z1, k / 7) for k in range(8)]:
        rows.append([vis_pt(z, t, sd) for t, sd in cols])
    rows = roll(rows, 0.0025)                                   # its upper lip: the slit's lower edge
    rows = roll(rows, 0.0025, end=False)                        # the chin
    rows = transpose(roll(roll(transpose(rows), 0.003, taper=3), 0.003, end=False, taper=3))
    ob = grid_object("visor", rows, STEEL(), mirror=False)
    breaths()
    return ob


def breaths():
    """Air holes: small dark discs lying on each cheek, three columns by four rows."""
    bm = bmesh.new()
    for sd in (-1, 1):
        for t in (0.30, 0.46, 0.62):
            for z in (1.604, 1.616, 1.628, 1.640):
                c = vis_pt(z, t, sd)
                du = vis_pt(z, t + 0.02, sd) - vis_pt(z, t - 0.02, sd)
                dv = vis_pt(z + 0.002, t, sd) - vis_pt(z - 0.002, t, sd)
                n = du.cross(dv).normalized()
                if n.y > 0:
                    n = -n
                a, b = du.normalized(), n.cross(du.normalized())
                ring_ = [bm.verts.new(c + n * 0.0006 + (a * math.cos(2 * math.pi * k / 6) + b * math.sin(2 * math.pi * k / 6)) * 0.0026)
                         for k in range(6)]
                bm.faces.new((ring_[0], ring_[1], ring_[2], ring_[3]))
                bm.faces.new((ring_[0], ring_[3], ring_[4], ring_[5]))
    return mesh_object("visor_breaths", bm, [DARK()], mirror=False)


def bevor():
    """A round cup over the chin and throat, its top edge rising to the front."""
    cols = [-110, -92, -74, -56, -40, -26, -13, 0, 13, 26, 40, 56, 74, 92, 110]
    rows = []
    for u in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0):
        row = []
        for th in cols:
            ztop = 1.598 + 0.026 * math.exp(-(th / 45.0) ** 2)
            z = lerp(1.542, ztop, u)
            cup = 0.010 * math.sin(math.pi * u) * math.exp(-(th / 60.0) ** 2)     # the chin swells
            row.append(helm_at(z, th, lerp(0.005, 0.011, u) + 0.6 * cup, beak=False))
        rows.append(row)
    rows = roll(rows, 0.0025)
    rows = transpose(roll(roll(transpose(rows), 0.003, taper=3), 0.003, end=False, taper=3))
    return grid_object("bevor", rows, STEEL(), mirror=False)


WOOD = lambda: material("arm_wood", (0.55, 0.40, 0.25), 0.0, 0.6)
PAINT = lambda: material("arm_paint_green", (0.10, 0.33, 0.16), 0.0, 0.55)
WHITE = lambda: material("arm_paint_white", (0.86, 0.84, 0.78), 0.0, 0.55)


def ring(bm, c, a, x, y, r, n):
    return [bm.verts.new(c + (x * math.cos(2 * math.pi * j / n) + y * math.sin(2 * math.pi * j / n)) * r) for j in range(n)]


def tube(bm, rings_, mat=0):
    for i in range(len(rings_) - 1):
        n = len(rings_[i])
        for j in range(n):
            f = bm.faces.new((rings_[i][j], rings_[i][(j + 1) % n], rings_[i + 1][(j + 1) % n], rings_[i + 1][j]))
            f.material_index = mat


def spear():
    """Held in the RIGHT fist (-X), along the grip channel: ash shaft, iron butt,
    a socketed leaf-shaped head with a midrib."""
    C, t, f, o = fist_frame()
    C, t, f, o = Vector((-C.x, C.y, C.z)), Vector((-t.x, t.y, t.z)), Vector((-f.x, f.y, f.z)), Vector((-o.x, o.y, o.z))
    a = f.normalized()
    C = C + a * 0.23                         # held lower on the shaft: the butt clears the ground
    x = o - a * o.dot(a); x.normalize()
    y = a.cross(x)
    bm = bmesh.new()
    shaft = [(-0.95, 0.0150), (-0.92, 0.0165), (0.0, 0.0165), (0.80, 0.0158), (1.20, 0.0150)]
    R_ = [ring(bm, C + a * s_, a, x, y, r_, 8) for s_, r_ in shaft]
    tube(bm, R_, 0)
    butt = [ring(bm, C + a * s_, a, x, y, r_, 8) for s_, r_ in ((-1.00, 0.0120), (-0.97, 0.0172), (-0.92, 0.0172))]
    tube(bm, butt, 1)
    tipb = bm.verts.new(C + a * -1.005)
    for j in range(8):
        bm.faces.new((butt[0][(j + 1) % 8], butt[0][j], tipb)).material_index = 1
    sock = [ring(bm, C + a * s_, a, x, y, r_, 8) for s_, r_ in ((1.19, 0.0172), (1.21, 0.0190), (1.27, 0.0150), (1.31, 0.0110))]
    tube(bm, sock, 1)
    # the head: a diamond section, wide across x, the midrib along y
    rows = []
    L = 0.26
    for k in range(11):
        u = k / 10
        w = 0.046 * math.sin(math.pi * min(1.0, u / 0.95)) ** 0.75 * (1 - 0.25 * u) + 0.004 * (1 - u)
        th_ = 0.0075 * (1 - u) + 0.0015
        c_ = C + a * (1.31 + L * u)
        rows.append([bm.verts.new(c_ + x * w), bm.verts.new(c_ + y * th_), bm.verts.new(c_ - x * w), bm.verts.new(c_ - y * th_)])
    tube(bm, rows, 1)
    pt = bm.verts.new(C + a * (1.31 + L + 0.02))
    for j in range(4):
        bm.faces.new((rows[-1][j], rows[-1][(j + 1) % 4], pt)).material_index = 1
    return mesh_object("spear", bm, [WOOD(), STEEL()], mirror=False)


def shield():
    """A heater shield on the LEFT forearm (+X): its back against the forearm, its face
    outward (o), its top toward the hand's front (f) — upright once the forearm is raised.
    Green with a white pale, a steel boss and rim, two leather arm straps behind."""
    # carried on a HANGING arm (owner 2026-09-28: 双手可以自然下垂): the shield hangs point-down
    # along the forearm, the forearm through its straps, the hand on the grip across its width
    p, t, f, o, _ = arm_frame(1.72)
    Cs = p + o * 0.072
    n = o                                    # the face's normal: out from the arm
    hv = (Vector((0, 0, 1)) - n * n.z).normalized()          # upright while the arm hangs
    wv = (f - hv * f.dot(hv) - n * f.dot(n)).normalized()
    TOP, BOT, HW = 0.22, -0.50, 0.27
    def hw_at(yv):
        if yv >= 0.02:
            return HW
        return max(0.0015, HW * math.cos((0.02 - yv) / (0.02 - BOT) * math.pi / 2) ** 0.85)

    def face(xu, yv, back=0.0):
        x = xu * hw_at(yv)
        bul = 0.045 * (1 - (x / HW) ** 2)
        return Cs + wv * x + hv * yv + n * (bul - back)
    bm = bmesh.new()
    ys = [lerp(BOT, TOP, (k / 11) ** 0.85) for k in range(12)]
    xs = [lerp(-1, 1, k / 12) for k in range(13)]
    F = [[bm.verts.new(face(xu, yv)) for xu in xs] for yv in ys]
    B = [[bm.verts.new(face(xu, yv, 0.014)) for xu in xs] for yv in ys]
    for i in range(len(ys) - 1):
        for j in range(len(xs) - 1):
            fc = bm.faces.new((F[i][j], F[i][j + 1], F[i + 1][j + 1], F[i + 1][j]))
            xm = (xs[j] + xs[j + 1]) / 2
            fc.material_index = 0                # boards and their old paint: painted in the texture bake
            bm.faces.new((B[i][j + 1], B[i][j], B[i + 1][j], B[i + 1][j + 1])).material_index = 2
    # the rim: the outline's front and back joined, in steel
    per = [(0, j) for j in range(len(xs))] + [(i, len(xs) - 1) for i in range(1, len(ys))] + \
          [(len(ys) - 1, j) for j in range(len(xs) - 2, -1, -1)] + [(i, 0) for i in range(len(ys) - 2, 0, -1)]
    for k in range(len(per)):
        a_, b_ = per[k], per[(k + 1) % len(per)]
        try:
            bm.faces.new((F[a_[0]][a_[1]], F[b_[0]][b_[1]], B[b_[0]][b_[1]], B[a_[0]][a_[1]])).material_index = 3
        except ValueError:
            pass
    # the boss
    bc = face(0.0, 0.0) + n * 0.002
    x_, y_ = wv, hv
    rings_ = [ring(bm, bc + n * h, n, x_, y_, r_, 12) for r_, h in ((0.055, 0.0), (0.050, 0.010), (0.036, 0.022), (0.018, 0.028))]
    tube(bm, rings_, 3)
    top = bm.verts.new(bc + n * 0.030)
    for j in range(12):
        bm.faces.new((rings_[-1][j], rings_[-1][(j + 1) % 12], top)).material_index = 3
    # two leather arm straps behind, across its width, bowed round the forearm
    for yv in (0.12, -0.02):
        rows_ = []
        for k in range(5):
            xu = (k / 4 - 0.5) * 0.52
            q = face(xu, yv, 0.014) - n * (0.030 * math.cos(math.pi * xu / 0.52))
            rows_.append([q + hv * -0.012, q + hv * 0.012])
        Vs = [[bm.verts.new(q) for q in r] for r in rows_]
        for i in range(len(Vs) - 1):
            bm.faces.new((Vs[i][0], Vs[i][1], Vs[i + 1][1], Vs[i + 1][0])).material_index = 4
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    # its frame, for the texture's boards and paint (texture.py reads it off the scene)
    bpy.context.scene["shield_frame"] = list(Cs) + list(wv) + list(hv) + list(n) + [HW, TOP, BOT]
    return mesh_object("shield", bm, [SHIELD_FACE(), WOOD(), WOOD(), STEEL(), LEATHER()], mirror=False)


def mail_skirt():
    """A short mail skirt under the fauld, to mid-thigh: it closes the crotch and the
    backs of the thighs that showed as black holes. In the body's own mail."""
    cols = list(range(0, 181, 15))
    rows = []
    for z, off in ((0.98, 0.010), (0.90, 0.016), (0.82, 0.024), (0.74, 0.030), (0.68, 0.034)):
        rows.append([skirt_at(z, th, off) for th in cols])
    mat = bpy.data.materials.get("base_clay")
    return grid_object("mail_skirt", rows, mat)


def rivets():
    """Domed brass rivet heads, one object per host plate (so each rides that plate's bones)."""
    names = []
    for host, pts in RIVETS.items():
        bm = bmesh.new()
        for p, n in pts:
            n = n.normalized()
            a = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
            b = n.cross(a)
            r = 0.0052
            base = [bm.verts.new(p - n * 0.0006 + (a * math.cos(2 * math.pi * j / 6) + b * math.sin(2 * math.pi * j / 6)) * r) for j in range(6)]
            mid = [bm.verts.new(p + n * 0.0030 + (a * math.cos(2 * math.pi * j / 6) + b * math.sin(2 * math.pi * j / 6)) * r * 0.62) for j in range(6)]
            for j in range(6):
                j2 = (j + 1) % 6
                bm.faces.new((base[j], base[j2], mid[j2], mid[j]))
            bm.faces.new((mid[0], mid[1], mid[2], mid[3]))
            bm.faces.new((mid[0], mid[3], mid[4], mid[5]))
        nm = "rivets_" + host
        mesh_object(nm, bm, [BRASS()], mirror=True)
        names.append(nm)
    return names


def belt():
    """A brown leather belt round the waist over the top of the fauld, a steel buckle at the front."""
    cols = list(range(0, 181, 15))
    rows = [[skirt_at(z, th, 0.030)[0] if False else torso_at(z, th, 0.031)[0] for th in cols] for z in (1.078, 1.060, 1.042)]
    rows = roll(rows, 0.0015)
    rows = roll(rows, 0.0015, end=False)
    grid_object("belt", rows, LEATHER())
    rows = [[torso_at(z, th, 0.037)[0] for th in (0, 4, 8)] for z in (1.036, 1.050, 1.070, 1.084)]
    rows = roll(rows, 0.0018)
    rows = roll(rows, 0.0018, end=False)
    grid_object("belt_buckle", rows, STEEL())
    return ["belt", "belt_buckle"]


def neck_rope():
    """A roped (twisted) roll round the neck, on the breastplate's collar edge."""
    NP, NR, R0 = 30, 6, 0.0062
    path = [torso_at(1.487, 180.0 * i / NP, 0.024)[0] for i in range(NP + 1)]
    L = sum((path[i + 1] - path[i]).length for i in range(NP))
    rows, s = [], 0.0
    for i, p in enumerate(path):
        if i:
            s += (path[i] - path[i - 1]).length
        t = (path[min(i + 1, NP)] - path[max(i - 1, 0)]).normalized()
        o = Vector((p.x, p.y, 0)).normalized()
        o = (o - t * o.dot(t)).normalized()
        b = t.cross(o)
        ph = 2 * math.pi * s / 0.018                      # one twist every 1.8 cm
        row = []
        for j in range(NR):
            a = 2 * math.pi * j / NR
            rr = R0 * (1 + 0.28 * math.cos(2 * a - ph))   # two strands wound round each other
            row.append(p + (o * math.cos(a) + b * math.sin(a)) * rr)
        rows.append(row)
    grid_object("neck_rope", transpose(rows), BRASS())
    return ["neck_rope"]


CLOAK_UNDER = ("base_body", "breastplate", "backplate", "pauldron", "besagew", "gorget_0", "gorget_1",
               "fauld_0", "fauld_1", "fauld_2", "fauld_3", "fauld_4", "belt", "belt_buckle", "mail_skirt",
               "cuisse", "tasset_0", "tasset_1", "rivets_backplate", "rivets_fauld_0", "rivets_fauld_1",
               "rivets_fauld_2", "rivets_fauld_3", "rivets_fauld_4")


def cloak():
    """Owner 2026-09-29: 加上披风，和盾牌同色. A knee-length cloak hung from the collar
    (tucked under the neck rope) over the back and the backs of the pauldrons: each
    point laid over the outermost armour behind it (a ray from behind), then HUNG — it
    may stand off a narrower waist but never cling to it — pleated, deeper toward the
    hem, the hem uneven and turned."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for nm in CLOAK_UNDER:
        ob = bpy.data.objects.get(nm)
        if not ob:
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        o = len(verts)
        verts += [ob.matrix_world @ v.co for v in me.vertices]
        polys += [tuple(o + i for i in p.vertices) for p in me.polygons]
        ev.to_mesh_clear()
    tree = BVHTree.FromPolygons(verts, polys)
    ZS = [1.487, 1.468, 1.445, 1.415, 1.375, 1.315, 1.245, 1.165, 1.075, 0.985, 0.895, 0.805, 0.715, 0.625, 0.545]
    US = [k / 8 for k in range(9)]
    CLEAR = 0.015

    def half_w(z):
        return lerp(0.092, 0.215, sstep(1.487, 1.415, z)) + 0.022 * sstep(1.30, 0.55, z)

    Y = []
    for r, z in enumerate(ZS):
        row = []
        gap_up = (ZS[r - 1] - z) if r else 0.0
        gap_dn = (z - ZS[r + 1]) if r + 1 < len(ZS) else 0.0
        for u in US:
            x = u * half_w(z)
            best = None                      # the outermost armour anywhere between this row and its neighbours
            for kz in range(-4, 5):
                zz = z + (gap_up if kz > 0 else gap_dn) * kz / 5.0
                loc, nor, _, _ = tree.ray_cast(Vector((max(x, 0.002), 1.0, zz)), Vector((0, -1, 0)))
                if loc is not None and (best is None or loc.y > best):
                    best = loc.y
            row.append(None if best is None else best + CLEAR)
        for j in range(len(US)):                     # past the body's edge: curl on from the last hit
            if row[j] is None:
                k = min((i for i in range(len(US)) if row[i] is not None), key=lambda i: abs(i - j))
                row[j] = row[k] - 0.035 * max(0, j - k)
        if r:
            dz = ZS[r - 1] - z
            row = [max(y, yp - 0.20 * dz) for y, yp in zip(row, Y[-1])]     # it hangs, it does not cling
        Y.append(row)
    rows = []
    for r, z in enumerate(ZS):
        t = (ZS[0] - z) / (ZS[0] - ZS[-1])
        amp = 0.002 + 0.020 * t ** 1.2
        row = []
        for u, y in zip(US, Y[r]):
            x = u * half_w(z)
            fold = 0.5 * (1.35 + math.cos(x * 2 * math.pi / 0.105) + 0.35 * math.cos(x * 2 * math.pi / 0.047 + 0.9))   # out only
            zz = z + (0.010 * math.cos(x * 2 * math.pi / 0.105 + 0.4) if r == len(ZS) - 1 else 0.0)
            row.append(Vector((x, y + amp * fold, zz)))
        rows.append(row)
    rows = relax(rows, 0.35, 2)
    rows = [[Vector((0.0, p.y, p.z)) if j == 0 else p for j, p in enumerate(r)] for r in rows]
    rows = roll(rows, 0.0030)                                   # the hem turned
    rows = roll(rows, 0.0020, end=False)                        # the collar edge
    rows = transpose(roll(transpose(rows), 0.0025, taper=3))    # the side edges
    return grid_object("cloak", rows, CLOAK())


def step5():
    names = [spear().name, shield().name, mail_skirt().name] + belt() + neck_rope() + rivets() + [cloak().name]
    print("STEP 5")
    report(names)


def step4():
    names = [helmet().name, visor().name, bevor().name]
    disc("visor_pivot", helm_at(1.665, 90, 0.012), Vector((1, 0, 0)), 0.012, 0.004, segs=8, r_roll=0.0015)
    names.append("visor_pivot")
    names += gorget() + [gauntlet().name, sabaton().name]
    print("STEP 4")
    report(names)


if STEP >= 4:
    step4()
if STEP >= 5:
    step5()
