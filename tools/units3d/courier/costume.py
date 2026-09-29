"""The herald's costume ON the posed base-mesh body (courier model v3): each vertex's body
part (rider_pose.seat) decides its region - doublet (torso, arms), hose (hips, thighs),
boot (from just below the knee, feet), linen cuff (the forearm's last fifth), skin (hands,
neck, face), hair and beard (by the head's own frame), eyes. Cloth regions are pushed out
along the normals by their thickness (the doublet stands 12 mm off the skin, a boot 10 mm
with a flared top), so hems, cuffs and boot tops are real steps; the regions go into two
colour attributes for the paint bake (rgn_a = doublet, hose, boot, linen; rgn_b = hair,
beard, eye white, iris)."""
import bpy, math
import numpy as np
from mathutils import Vector

THICK = {"doublet": 0.017, "hose": 0.003, "boot": 0.013, "linen": 0.014, "skin": 0.0,
         "hair": 0.006, "beard": 0.006, "eye": 0.0, "iris": 0.0}
RELAX_DOUBLET = 14 * 16        # v3: the Multires level-2 body is 4x denser along each side
N_EYE_VERTS = 2 * 546          # the two eyeballs, appended last by human.load_body


def along(p, a, b):
    d = b - a
    return (p - a).dot(d) / d.length_squared


def regions(body, PJ, parts):
    me = body.data
    n = len(me.vertices)
    reg = ["skin"] * n
    head_h, head_t = PJ["head:h"], PJ["head:t"]
    up = (head_t - head_h).normalized()
    fwd = (Vector((0, 1, 0)) - up * up.y).normalized()
    hl = (head_t - head_h).length
    for i, v in enumerate(me.vertices):
        p = v.co
        part = parts[i]
        base = part.split(".")[0]
        if i >= n - N_EYE_VERTS:
            reg[i] = "eye"
            continue
        if base in ("chest", "spine", "clavicle", "upper_arm"):
            reg[i] = "doublet"
        elif base == "pelvis":
            reg[i] = "doublet" if p.z > PJ["thigh.R:h"].z + 0.06 else "hose"
        elif base == "forearm":
            sfx = part[-2:]
            t = along(p, PJ["forearm" + sfx + ":h"], PJ["forearm" + sfx + ":t"])
            reg[i] = "linen" if t > 0.8 else "doublet"
        elif base == "thigh":
            reg[i] = "hose"
        elif base == "shin":
            sfx = part[-2:]
            t = along(p, PJ["shin" + sfx + ":h"], PJ["shin" + sfx + ":t"])
            reg[i] = "boot" if t > 0.16 else "hose"
        elif base == "foot":
            reg[i] = "boot"
        elif base == "hand":
            reg[i] = "skin"
        elif base in ("head", "neck"):
            d = p - head_h
            a, f = d.dot(up) / hl, d.dot(fwd)
            if a > 0.25 and f < -0.01:
                reg[i] = "hair"                       # the back of the head, to the nape
            elif a > 0.62:
                reg[i] = "hair"                       # the crown (under the hat)
            else:
                reg[i] = "skin"
    # the eyes: the iris is the front cap of each ball
    E = np.array([me.vertices[i].co[:] for i in range(n - N_EYE_VERTS, n)])
    for half in (0, 1):
        idx = np.arange(n - N_EYE_VERTS + half * 546, n - N_EYE_VERTS + (half + 1) * 546)
        P = np.array([me.vertices[i].co[:] for i in idx])
        c = P.mean(0)
        r = np.linalg.norm(P - c, axis=1).max()
        for i, p in zip(idx, P):
            if (p - c)[1] > 0.55 * r:
                reg[i] = "iris"
    return reg


def inflate(body, reg, PJ, hairw=None):
    me = body.data
    me.update()
    n = len(me.vertices)
    t = np.array([THICK[r] for r in reg])
    if hairw is not None:            # v3: hair thickness feathered, not a step
        t = np.where(np.array([r == "hair" for r in reg]), 0.0, t) + hairw * 0.007
    # the boot's top flares out a little: the first 4 cm below its edge
    for sfx in (".R", ".L"):
        a, b = PJ["shin" + sfx + ":h"], PJ["shin" + sfx + ":t"]
        for i, v in enumerate(me.vertices):
            if reg[i] == "boot":
                tt = along(v.co, a, b)
                if 0.16 < tt < 0.26:
                    t[i] += 0.009 * (1 - (tt - 0.16) / 0.10)
    # neighbour averaging (a few passes: the mesh is dense) keeps the steps, kills spikes
    E = _edges(me)
    deg = np.zeros(n)
    np.add.at(deg, E[:, 0], 1); np.add.at(deg, E[:, 1], 1)
    deg = np.maximum(deg, 1)
    t2 = t.copy()
    fixed = np.array([r in ("eye", "iris") for r in reg[:n]])
    for _ in range(3):
        S = np.zeros(n)
        np.add.at(S, E[:, 0], t2[E[:, 1]]); np.add.at(S, E[:, 1], t2[E[:, 0]])
        t2 = np.where(fixed, t, 0.5 * t2 + 0.5 * S / deg)
    N = np.zeros(n * 3)
    me.vertices.foreach_get("normal", N)
    P = np.zeros(n * 3)
    me.vertices.foreach_get("co", P)
    P = P.reshape(n, 3) + N.reshape(n, 3) * t2[:, None]
    me.vertices.foreach_set("co", P.ravel())
    me.update()


def _edges(me):
    E = np.zeros(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", E)
    return E.reshape(-1, 2)


def relax(body, reg, which, iters, lam=0.5, mu=-0.53):
    """Laplacian (Taubin when mu < 0) smoothing of the verts in regions `which`, vectorised
    (the v3 body is Multires level 2: ~170k verts); the others stay put."""
    me = body.data
    n = len(me.vertices)
    E = _edges(me)
    P = np.zeros(n * 3)
    me.vertices.foreach_get("co", P)
    P = P.reshape(n, 3)
    move = np.array([r in which for r in reg[:n]])
    deg = np.zeros(n)
    np.add.at(deg, E[:, 0], 1); np.add.at(deg, E[:, 1], 1)
    deg = np.maximum(deg, 1)[:, None]
    for k in range(iters):
        for f in ((lam, mu) if mu else (lam,)):
            S = np.zeros_like(P)
            np.add.at(S, E[:, 0], P[E[:, 1]]); np.add.at(S, E[:, 1], P[E[:, 0]])
            D = S / deg - P
            P = P + f * D * move[:, None]
    me.vertices.foreach_set("co", P.ravel())
    me.update()


def _sk():
    import sys
    V1 = __file__.rsplit("/", 1)[0]
    if V1 not in sys.path:
        sys.path.insert(0, V1)
    import sdfkit as sk
    return sk


def fist_frame(PJ, sfx):
    W = np.array(PJ["hand" + sfx + ":h"][:])
    T = np.array(PJ["hand" + sfx + ":t"][:])
    a = (T - W) / np.linalg.norm(T - W)
    a = a * np.array((1.0, 1.0, 0.3))          # the fist carried level: thumb up, knuckles forward
    a /= np.linalg.norm(a)
    k = np.array((0.0, 0.0, 1.0)) - a * a[2]
    k /= np.linalg.norm(k)
    n = np.cross(a, k)                       # the palm's side: towards the body's middle
    if n[0] * (1 if sfx == ".R" else -1) > 0:
        n = -n
    return W, a, k, n


def fist_centre(PJ, sfx):
    """Where the fist's grip hole is (the rein or the pole passes up through it)."""
    W, a, k, n = fist_frame(PJ, sfx)
    return W + a * 0.082 + n * 0.012


def fist_field(PJ, sfx):
    sk = _sk()
    W, a, k, n = fist_frame(PJ, sfx)
    P = lambda da, dk, dn: tuple(W + a * da + k * dk + n * dn)
    parts = [sk.Ell(P(0.045, 0.0, 0.002), (0.046, 0.05, 0.019), axis=tuple(a), up=tuple(n)),     # palm
             sk.RCone(P(-0.035, 0.0, 0.0), P(0.02, 0.0, 0.0), 0.027, 0.03)]                      # wrist
    for dk, sc in ((0.0285, 0.95), (0.0095, 1.0), (-0.0095, 0.95), (-0.0275, 0.84)):
        p0 = np.array(P(0.086, dk, -0.004))
        p1 = p0 + (a * 0.028 + n * 0.012) * sc
        p2 = p1 + (-a * 0.004 + n * 0.022) * sc
        p3 = p2 + (-a * 0.019 + n * 0.009) * sc
        parts.append(sk.Chain([tuple(p0), tuple(p1), tuple(p2), tuple(p3)], [0.0098, 0.0092, 0.0086, 0.0078]))
    parts.append(sk.Chain([P(0.018, 0.028, 0.012), P(0.055, 0.042, 0.024), P(0.082, 0.034, 0.034)],
                          [0.0125, 0.011, 0.0092]))                                              # thumb
    return sk.U(0.0035, *parts), np.array(P(0.055, 0.0, 0.006)), (a, k, n)


def fists(PJ, nq=6, name="rider_hands"):
    """Two closed fists on their fields: a stretched cube-sphere cast from the hand's middle."""
    sk = _sk()
    V, F = [], []
    for sfx in (".R", ".L"):
        f, c, (a, k, n) = fist_field(PJ, sfx)
        R = np.stack([a, k, n], 1)
        S = np.array((1.5, 1.2, 0.8))
        idx = {}
        def vid(q):
            key = tuple(np.round(q, 6))
            if key not in idx:
                d = R @ (np.array(q) * S)
                d /= np.linalg.norm(d)
                t = sk.raycast(f, c[None], d[None], 0.2)[0]
                idx[key] = len(V)
                V.append(c + d * t)
            return idx[key]
        for ax in range(3):
            for sgn in (-1, 1):
                a1, a2 = (ax + 1) % 3, (ax + 2) % 3
                for i in range(nq):
                    for j in range(nq):
                        qs = []
                        for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                            q = [0.0, 0.0, 0.0]
                            q[ax] = sgn
                            q[a1] = -1 + 2 * (i + di) / nq
                            q[a2] = -1 + 2 * (j + dj) / nq
                            qs.append(vid(q))
                        F.append(qs if sgn > 0 else qs[::-1])
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in V], [], F)
    # v3b: one side's frame is left-handed, which wound that fist inside out (its AO baked
    # black, the rein hand a brown blob): face every fist outward
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me); bm.free()
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def cut_hands(body, PJ, parts):
    """The base mesh's hands go past the wrist: the fists stand in."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    gone = []
    for sfx in (".R", ".L"):
        W, a, k, n = fist_frame(PJ, sfx)
        gone += [bm.verts[i] for i, p in enumerate(parts[:len(bm.verts)]) if p == "hand" + sfx
                 and (np.array(bm.verts[i].co[:]) - W) @ a > 0.012]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def cut_feet_by_attr(body, PJ):
    """cut_feet after an earlier cut: the feet found by the part_code attribute (6)."""
    import bmesh
    me = body.data
    codes = [d.value for d in me.attributes["part_code"].data]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    gone = []
    for sfx, s in ((".R", 1), (".L", -1)):
        az = PJ["foot" + sfx + ":h"].z
        gone += [bm.verts[i] for i, c in enumerate(codes) if c == 6 and bm.verts[i].co.z < az + 0.01
                 and bm.verts[i].co.x * s > 0]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()


def cut_feet(body, PJ, parts):
    """Drop the bare feet below the ankle: a boot foot (boot_foot) is laid over the stump."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    gone = []
    for sfx in (".R", ".L"):
        az = PJ["foot" + sfx + ":h"].z
        gone += [bm.verts[i] for i, p in enumerate(parts) if p == "foot" + sfx and bm.verts[i].co.z < az + 0.01]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def boot_foot_field(PJ, sfx, floor):
    sk = _sk()
    A = np.array(PJ["foot" + sfx + ":h"][:])
    T = np.array(PJ["foot" + sfx + ":t"][:])
    d = T - A
    d[2] = 0
    d /= np.linalg.norm(d)
    toe = np.array((T[0], T[1], floor + 0.042)) + d * 0.03
    heel = np.array((A[0], A[1], floor + 0.045)) - d * 0.05
    mid = (toe + heel) / 2 + np.array((0, 0, 0.008))
    L = np.linalg.norm(toe - heel)
    f = sk.U(0.03, sk.Ell(tuple(mid), (0.05, L / 2 + 0.015, 0.046), axis=tuple(d), up=(0, 0, 1)),
             sk.Sph(tuple(heel), 0.048),
             sk.RCone(tuple(A + np.array((0, 0.012, 0.09))), tuple(A + np.array((0, 0.0, -0.03))), 0.068, 0.062))
    return f, heel + (toe - heel) * 0.33 + np.array((0, 0, 0.05)), d


def boot_foot(M_add, PJ, sfx, floor):
    """A closed all-quad boot foot: a stretched cube-sphere cast onto the boot field."""
    sk = _sk()
    f, c, d = boot_foot_field(PJ, sfx, floor)
    side = np.cross(d, (0, 0, 1)); up = np.cross(side, d)
    R = np.stack([side, d, up], 1)
    S = np.array((0.5, 1.6, 0.9))
    nq = {0: 3, 1: 5, 2: 3}
    idx = {}
    V, F = [], []
    def vid(q):
        key = tuple(np.round(q, 6))
        if key not in idx:
            dd = R @ (np.array(q) * S)
            dd /= np.linalg.norm(dd)
            t = sk.raycast(f, c[None], dd[None], 0.4)[0]
            idx[key] = len(V)
            V.append(c + dd * t)
        return idx[key]
    for ax in range(3):
        for sgn in (-1, 1):
            a1, a2 = (ax + 1) % 3, (ax + 2) % 3
            n1, n2 = nq[a1] * 2, nq[a2] * 2
            for i in range(n1):
                for j in range(n2):
                    qs = []
                    for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                        q = [0.0, 0.0, 0.0]
                        q[ax] = sgn
                        q[a1] = -1 + 2 * (i + di) / n1
                        q[a2] = -1 + 2 * (j + dj) / n2
                        qs.append(vid(q))
                    F.append(qs if sgn > 0 else qs[::-1])
    return V, F


def paint_attributes(body, reg):
    me = body.data
    for nm in ("rgn_a", "rgn_b"):
        if nm in me.color_attributes:
            me.color_attributes.remove(me.color_attributes[nm])
    A = me.color_attributes.new("rgn_a", "FLOAT_COLOR", "POINT")
    B = me.color_attributes.new("rgn_b", "FLOAT_COLOR", "POINT")
    ka = {"doublet": 0, "hose": 1, "boot": 2, "linen": 3}
    kb = {"hair": 0, "beard": 1, "eye": 2, "iris": 3}
    ca = np.zeros((len(reg), 4)); cb = np.zeros((len(reg), 4))
    for i, r in enumerate(reg):
        if r in ka:
            ca[i, ka[r]] = 1.0
        if r in kb:
            cb[i, kb[r]] = 1.0
    A.data.foreach_set("color", ca.ravel())
    B.data.foreach_set("color", cb.ravel())


def face_masks(body, reg, PJ, parts):
    """v3: the face painted, not built - soft masks off the face's own landmarks (the nose
    tip, the chin, the eyeballs) into the colour attribute `face`: R the beard and
    moustache (the lips left clear), G the brows, B the lips, A a flush on cheeks and nose.
    Returns the hair weight too (soft, for a feathered hair thickness)."""
    me = body.data
    n = len(me.vertices)
    P = np.zeros(n * 3); me.vertices.foreach_get("co", P); P = P.reshape(n, 3)
    hh, ht = np.array(PJ["head:h"][:]), np.array(PJ["head:t"][:])
    up = (ht - hh) / np.linalg.norm(ht - hh)
    fwd = np.array((0.0, 1.0, 0.0)) - up * up[1]
    fwd /= np.linalg.norm(fwd)
    side = np.cross(fwd, up)
    D = P - hh
    a, f, x = D @ up, D @ fwd, D @ side
    head = np.array([parts[i].startswith("head") or parts[i].startswith("neck") for i in range(n)])
    eyes = np.zeros(n, bool); eyes[n - N_EYE_VERTS:] = True
    skin = head & ~eyes
    # landmarks, from the face's own midline profile (how far forward it stands at each
    # height): the eyes, the nose tip below them, the chin, the mouth at the profile's dip
    E = P[eyes]
    eyeL, eyeR = E[:546].mean(0), E[546:].mean(0)
    a_e = ((eyeL - hh) @ up + (eyeR - hh) @ up) / 2
    mid = skin & (np.abs(x) < 0.005)
    band = mid & (a > a_e - 0.085) & (a < a_e - 0.02)
    i_nose = np.where(band)[0][np.argmax(f[band])]
    a_n, f_n = a[i_nose], f[i_nose]
    below = mid & (a < a_n) & (f > f_n - 0.045)
    a_c = a[below].min()
    bins = np.arange(a_n - 0.036, a_n - 0.014, 0.002)      # the mouth: 1.4-3.6 cm under the nose tip
    prof = [f[mid & (a >= b0) & (a < b0 + 0.002)].max() if (mid & (a >= b0) & (a < b0 + 0.002)).any() else 9 for b0 in bins]
    a_m = bins[int(np.argmin(prof))] + 0.001                 # the mouth slit
    a_ll, a_ul = a_m - 0.009, a_m + 0.008
    sst = lambda lo, hi, v: np.clip((v - lo) / (hi - lo), 0, 1) ** 2 * (3 - 2 * np.clip((v - lo) / (hi - lo), 0, 1))
    frontal = sst(-0.035, -0.01, f - (f_n - 0.09))
    beard = sst(a_ll - 0.001, a_ll - 0.01, a) * frontal * sst(a_c - 0.012, a_c - 0.002, a)   # chin (v3b: stops at the chin's underside, not down the throat)
    headpart = np.array([p.startswith("head") for p in parts[:n]])
    jaw = sst(a_c - 0.004, a_c + 0.006, a) * headpart            # not down the neck
    beard = np.maximum(beard, sst(a_m + 0.014, a_m - 0.002, a) * sst(0.024, 0.036, np.abs(x)) * frontal * jaw)   # jaw sides
    moust = sst(a_ul - 0.001, a_ul + 0.003, a) * sst(a_n - 0.008, a_n - 0.014, a) * sst(0.03, 0.022, np.abs(x))
    moust = np.maximum(moust, sst(a_ul + 0.002, a_ll, a) * sst(0.02, 0.024, np.abs(x)) * sst(0.034, 0.028, np.abs(x)))   # down the corners
    lips = sst(a_ll - 0.003, a_ll + 0.001, a) * sst(a_ul + 0.001, a_ul - 0.003, a) * sst(0.024, 0.017, np.abs(x)) * (f > f_n - 0.045)
    beard = np.clip(np.maximum(beard, moust) * (1 - lips), 0, 1) * skin
    # v3b: the head is bowed, so under the jaw's angle the neck still reads 'above the chin' in
    # the head's own frame and the beard ran down it: nothing below the chin in the WORLD
    z_c = P[below][np.argmin(a[below]), 2]
    beard *= sst(z_c - 0.014, z_c - 0.004, P[:, 2])
    print("FACE landmarks: eyes %.3f nose %.3f mouth %.3f chin %.3f" % (a_e, a_n, a_m, a_c))
    brow = np.zeros(n)
    for e in (eyeL, eyeR):
        de = P - e
        ab = de @ up
        xb = de @ side
        brow = np.maximum(brow, sst(0.009, 0.013, ab) * sst(0.021, 0.017, ab) * sst(0.026, 0.018, np.abs(xb + 0.002)))
    brow *= skin * (f > (eyeL - hh) @ fwd - 0.02)
    flush = np.zeros(n)
    for c in (eyeL, eyeR):
        cc = c + up * (-0.03) + fwd * 0.0
        flush = np.maximum(flush, sst(0.035, 0.0, np.linalg.norm(P - cc, axis=1)))
    flush = np.maximum(flush, 0.6 * sst(0.02, 0.0, np.linalg.norm(P - P[i_nose], axis=1)))
    flush *= skin
    at = me.color_attributes.new("face", "FLOAT_COLOR", "POINT")
    at.data.foreach_set("color", np.stack([beard, brow, lips * skin, flush * 0.6], 1).ravel())
    # the hair: behind and above, feathered 1.5 cm
    hairw = np.maximum(sst(-0.005, -0.022, f) * sst(0.2 * (ht - hh) @ up, 0.32 * (ht - hh) @ up, a), sst(0.60 * np.linalg.norm(ht - hh), 0.7 * np.linalg.norm(ht - hh), a)) * skin
    return hairw


def dress(body, PJ, parts):
    reg = regions(body, PJ, parts)
    relax(body, reg, {"doublet"}, RELAX_DOUBLET, 0.55, 0.0)
    hairw = face_masks(body, reg, PJ, parts)
    inflate(body, reg, PJ, hairw)
    paint_attributes(body, reg)
    code = {"pelvis": 1, "spine": 1, "chest": 1, "clavicle": 1, "neck": 1, "thigh": 2, "shin": 2,
            "upper_arm": 3, "forearm": 3, "head": 4, "hand": 5, "foot": 6}
    pa = body.data.attributes.new("part_code", "INT", "POINT")
    pa.data.foreach_set("value", [code[p.split(".")[0]] for p in parts])
    floor = min(v.co.z for i, v in enumerate(body.data.vertices) if parts[i].startswith("foot"))
    hands = fists(PJ, 5, "rider_hands")
    hands_high = fists(PJ, 26, "rider_hands_high")          # the bake source: the fingers' grooves
    hands["high"] = hands_high.name
    cut_hands(body, PJ, parts)
    # after the hands went, the part list no longer lines up: recompute it by position
    parts2 = [None] * len(body.data.vertices)
    cut_feet_by_attr(body, PJ)
    # the boots' feet, one object
    V, F = [], []
    for sfx in (".R", ".L"):
        v, f = boot_foot(None, PJ, sfx, floor)
        off = len(V)
        V += v
        F += [[i + off for i in fc] for fc in f]
    me = bpy.data.meshes.new("rider_boots")
    me.from_pydata([tuple(p) for p in V], [], F)
    me.update()
    ob = bpy.data.objects.new("rider_boots", me)
    bpy.context.scene.collection.objects.link(ob)
    return reg, ob, hands
