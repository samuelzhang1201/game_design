"""Courier model v3, the geometry: the scan horse, the seated base-mesh rider in his
costume, and v1's tack, clothing and props ported onto them. texture_v3.py then reduces,
unwraps and bakes the atlas; rebuild_v3.py runs both.
  Blender -b --factory-startup --python build_v3.py
"""
import bpy, sys, math
import numpy as np
from mathutils import Vector

HERE = __file__.rsplit("/", 1)[0]
V1 = HERE                      # the v1 helpers (sdfkit, cage, hair) sit beside this file
for p in (HERE, V1):
    if p not in sys.path:
        sys.path.insert(0, p)
import cage as cg
import scan_horse, human, rider_pose as rp, costume
from meshfield import MeshField
import tack_v3 as tk
import clothes_v3 as cl
import props_v3 as pr


def subset(ob, codes):
    a = ob.data.attributes["part_code"].data
    return [i for i in range(len(ob.data.vertices)) if a[i].value in codes]


def side_x(field, y, z, s):
    loc, _, _ = field.ray((s * 3.0, y, z), (-s, 0, 0))
    return abs(loc[0]) if loc is not None else 0.25


EYE_AT = (1.40, 1.80)          # the scan's sculpted eye bulge (y, z), found on a probe render


def horse_eyes(HF):
    """v3: a real eye each side - a dark eyeball set into the scan's socket (it stands 5 mm
    proud of the bulge) and a lid rim round it."""
    import cage as cg
    import tack_v3 as tk
    M = cg.Mesh()
    y, z = EYE_AT
    hits = {}
    for s in (1, -1):
        loc, nor, _ = HF.ray((s * 1.0, y, z), (-s, 0, 0))
        hits[s] = (loc, nor)
    cx = (hits[1][0][0] + hits[-1][0][0]) / 2
    for s in (1, -1):
        loc, nor, _ = HF.ray((cx, y, z), (s, 0, 0))
        n = np.array(nor)
        if n[0] * s < 0:
            n = -n
        c = np.array(loc) - n * 0.004
        fwd = np.array((0.0, 1.0, -0.35)); fwd -= n * (fwd @ n); fwd /= np.linalg.norm(fwd)
        up = np.cross(n, fwd)
        if up[2] < 0:
            up = -up
        R = np.stack([n, fwd, up], 1)
        _cubesphere(M, c, (0.011, 0.021, 0.016), R, 2, "horse_eye")
        # the lid rim: a ring round the eye, lying on the socket
        ring = []
        for k in range(12):
            a = 2 * math.pi * k / 12
            ring.append(c + n * 0.006 + fwd * math.cos(a) * 0.024 + up * math.sin(a) * 0.018)
        tk.rstrap(M, ring, 0.007, 0.006, up=tuple(n), closed=True, tag="horse_lid", n=4)
    return M


def _cubesphere(M, c, radii, R, n, tag):
    idx = {}
    for ax in range(3):
        for sgn in (-1, 1):
            grid = {}
            for i in range(n + 1):
                for j in range(n + 1):
                    q = [0.0, 0.0, 0.0]
                    q[ax] = sgn
                    q[(ax + 1) % 3] = -1 + 2 * i / n
                    q[(ax + 2) % 3] = -1 + 2 * j / n
                    key = tuple(np.round(q, 6))
                    if key not in idx:
                        d = np.array(q) / np.linalg.norm(q)
                        idx[key] = M.v(c + R @ (d * np.asarray(radii)))
                    grid[(i, j)] = idx[key]
            for i in range(n):
                for j in range(n):
                    fc = (grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)])
                    M.f(fc if sgn > 0 else fc[::-1], tag)


def limb_band(M, field, a, b, t0, t1, off, flare, tag, n=12, also=None):
    """A leather band round a limb between t0..t1 of the joint segment a->b: a boot's cuff,
    an ankle strap. Cast from the limb's axis onto its surface, pushed out by off."""
    import sdfkit as sk
    a, b = np.asarray(a, float), np.asarray(b, float)
    ax = (b - a) / np.linalg.norm(b - a)
    fr = np.array((0.0, 1.0, 0.0)) - ax * ax[1]
    fr /= np.linalg.norm(fr)
    sd = np.cross(ax, fr)
    rows = []
    for t, fl in ((t0, 0.0), (t1, flare)):
        c = a + (b - a) * t
        ring = []
        for k in range(n):
            ang = 2 * math.pi * k / n
            d = fr * math.cos(ang) + sd * math.sin(ang)
            r = sk.raycast(field, c[None], d[None], 0.2)[0]
            if also is not None:          # v3: a second surface to enclose (the boot's shaft)
                r2 = sk.raycast(also, c[None], d[None], 0.2)[0]
                if r2 < 0.15:
                    r = max(r, r2)
            ring.append(c + d * (r + off + fl))
        rows.append(ring)
    # the band's inside: its two rims turned in towards the leg
    inner = []
    for ring, t in zip(rows, (t0, t1)):
        c = a + (b - a) * t
        inner.append([c + (p - c) * 0.9 for p in ring])
    R = [[M.v(p) for p in r] for r in (inner[0], rows[0], rows[1], inner[1])]
    for r0, r1 in zip(R, R[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            M.f((r0[k], r0[k2], r1[k2], r1[k]), tag)


def build():
    horse = scan_horse.horse_high()
    horse.name = horse.data.name = "horse_high"
    body, eyes = human.load_body_mr(2)
    PJ, parts, _ = rp.seat_mr(body, eyes, horse)
    reg, boots, hands = costume.dress(body, PJ, parts)
    hands_high = bpy.data.objects[hands["high"]]
    body.name = body.data.name = "rider_high"
    import texture_v3
    horse_low = texture_v3.reduce(horse, "horse", texture_v3.BUDGET["horse"])
    HF = MeshField(horse_low, exact=True)
    BODY = MeshField(body)
    TORSO = MeshField(body, verts=subset(body, {1, 4}))
    LEGS = MeshField(body, verts=subset(body, {2}))
    bco = np.array([v.co[:] for v in boots.data.vertices])
    floor = bco[:, 2].min()
    A, T = np.array(PJ["foot.R:h"][:]), np.array(PJ["foot.R:t"][:])
    ball = A + (T - A) * 0.62
    stirrup = np.array((ball[0], ball[1], floor - 0.004))
    rider = {"FIST_R": costume.fist_centre(PJ, ".R"), "FIST_L": costume.fist_centre(PJ, ".L"),
             "STIRRUP_R": stirrup}
    head = tk.head_frame(horse_low)
    tk.setup(HF, head, rider)
    ARM = MeshField(body, verts=subset(body, {3}))
    cl.setup(TORSO, BODY, LEGS, HF, PJ, arm=ARM)
    crown = np.array(PJ["head:t"][:])
    zb = crown[2] - 0.062
    o = np.array((0.0, crown[1] + 0.01, zb))
    fr = BODY.ray(o, (0, 1, 0))[2] or 0.09
    bk = BODY.ray(o, (0, -1, 0))[2] or 0.09
    rt = BODY.ray(o, (1, 0, 0))[2] or 0.07
    hat_c = o + np.array((0, (fr - bk) / 2, 0.0))
    ycase, zcase = PJ["thigh.L:h"].y - 0.085, 1.40
    case_c = (-(side_x(HF, ycase, zcase, -1) + tk.CLOTH_OFF + 0.040), ycase, zcase)
    ypole, zpole = 0.585, 1.215
    pole_butt = (-(side_x(HF, ypole, zpole, -1) + 0.058), ypole, zpole)
    belt = (-0.15, PJ["spine:h"].y - 0.05, cl.BELT_Z)
    pr.setup(hat_c, rt + 0.012, (fr + bk) / 2 + 0.012, rider["FIST_L"], pole_butt, case_c, belt)
    import bmesh
    from mathutils import Matrix
    bm = bmesh.new(); bm.from_mesh(horse_low.data)
    bm.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    HF_left = MeshField(bm=bm, exact=True)
    Mt, Mb = tk.build(left_field=HF_left)
    Mc, Mw = cl.build()
    Mp, Mcr = pr.build()
    import hair_v3
    hair_v3.setup(HF, head)
    Mh = hair_v3.build()
    Me = horse_eyes(HF)
    # the boots' cuffs and the ankle straps (they hide the boot's edges)
    Mk = cg.Mesh()
    BOOTS = MeshField(boots, exact=True)
    for sfx in (".R", ".L"):
        kn, an = PJ["shin" + sfx + ":h"], PJ["shin" + sfx + ":t"]
        limb_band(Mk, BODY, kn, an, 0.10, 0.20, 0.004, 0.012, "boot")
        # v3: the strap sits on the boot foot's top rim, where the shin passes into the
        # foot's shaft - the two surfaces met there in a jagged line
        s_ = 1 if sfx == ".R" else -1
        ztop = max(v.co.z for v in boots.data.vertices if v.co.x * s_ > 0)
        tz = lambda z: (kn.z - z) / (kn.z - an.z)
        limb_band(Mk, BODY, kn, an, tz(ztop + 0.012), tz(ztop - 0.058), 0.006, 0.0, "leather",
                  also=BOOTS)
    objs = {"tack": cg.to_object(Mt, "tack", recalc=False), "bridle": cg.to_object(Mb, "bridle", recalc=True),
            "clothes": cg.to_object(Mc, "clothes", recalc=False), "clothes_trim": cg.to_object(Mw, "clothes_trim", recalc=False),
            "props": cg.to_object(Mp, "props", recalc=True), "props_crowns": cg.to_object(Mcr, "props_crowns", recalc=False),
            "horse_hair": cg.to_object(Mh, "horse_hair", recalc=True), "horse_eyes": cg.to_object(Me, "horse_eyes", recalc=True),
            "boot_bands": cg.to_object(Mk, "boot_bands", recalc=True)}
    objs.update({"horse_high": horse, "horse_low": horse_low, "rider_high": body, "rider_boots": boots,
                 "rider_hands": hands, "rider_hands_high": hands_high})
    return objs, PJ


if __name__ == "__main__":
    objs, PJ = build()
    for k, o in objs.items():
        print("PART", k, len(o.data.polygons), sum(len(p.vertices) - 2 for p in o.data.polygons))
