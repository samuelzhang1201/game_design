# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
import random
random.seed(7)
IRON, WAX = 0, 1
O = Vector((0, 0, 0))   # built at the origin of its own object; the object is placed aside
bm = bmesh.new()

# base dish
base = [(0.086, 0.000), (0.089, 0.006), (0.083, 0.014), (0.058, 0.021), (0.030, 0.033), (0.021, 0.046)]
tag(lathe(bm, base, 16, O, cap_start=True), IRON)
# stem: baluster, collar at the arms
stem = [(0.021, 0.046), (0.015, 0.062), (0.019, 0.076), (0.015, 0.092), (0.025, 0.128), (0.029, 0.152),
        (0.020, 0.183), (0.012, 0.203), (0.018, 0.209), (0.018, 0.225), (0.011, 0.248)]
tag(lathe(bm, stem, 8, O, phase=math.pi / 8), IRON)

def cup(c):
    prof = [(0.007, 0.000), (0.029, 0.002), (0.030, 0.007), (0.018, 0.009), (0.019, 0.023), (0.022, 0.028), (0.0166, 0.0285)]
    tag(lathe(bm, prof, 8, c, phase=math.pi / 8), IRON)

def candle(c, h, r=0.0158):
    z0 = c.z + 0.014
    seg = 8
    rows = []
    for (rr, zz, jit) in [(r, z0, 0.0), (r * 1.01, z0 + h, 0.006), (r * 0.62, z0 + h - 0.007, 0.002)]:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg + math.pi / seg
            ring.append(c + Vector((math.cos(a) * rr, math.sin(a) * rr, zz - c.z - random.uniform(0, jit))))
        rows.append(ring)
    tag(quad_strip(bm, rows, True, False, True), WAX)
    return z0 + h

SEC = [(-0.0042, -0.0042), (0.0042, -0.0042), (0.0042, 0.0042), (-0.0042, 0.0042)]
def arm(s):
    # a scroll: from the collar over the top, down the outside and curling in beneath
    C = (0.054, 0.198)
    th0, th1, n = math.radians(161), math.radians(-215), 12
    r0, r1 = 0.0487, 0.007
    a = []
    for i in range(n):
        t = i / (n - 1)
        th = th0 + (th1 - th0) * t
        r = r0 + (r1 - r0) * t ** 0.8
        a.append((C[0] + math.cos(th) * r, C[1] + math.sin(th) * r))
    sc = [1.0] * (n - 4) + [0.95, 0.85, 0.75, 0.65]
    tag(sweep(bm, [Vector((s * x, 0, z)) for x, z in a], SEC, scale=sc), IRON)
    b = [(0.076, 0.185), (0.093, 0.185), (0.107, 0.199), (0.112, 0.216), (0.114, 0.233), (0.114, 0.248)]
    tag(sweep(bm, [Vector((s * x, 0, z)) for x, z in b], SEC, scale=[0.85, 0.95, 1, 1, 1, 1]), IRON)

DRIP = [(-0.0026, 0), (0, 0.0016), (0.0026, 0), (0, -0.0016)]
def drip(c, r, ang, ztop, length):
    d = Vector((math.cos(ang), math.sin(ang), 0))
    pts = [c + d * (r + 0.0006) + Vector((0, 0, ztop - c.z - t * length)) for t in (0.0, 0.45, 0.8, 1.0)]
    pts[-1] += d * 0.0012
    tag(sweep(bm, pts, DRIP, scale=[1.0, 1.05, 0.95, 0.55]), WAX)

# centre
cc = Vector((0, 0, 0.248))
cup(cc)
top = candle(cc, 0.160)
drip(cc, 0.0158, 0.4, top - 0.004, 0.07)
drip(cc, 0.0158, 2.6, top - 0.004, 0.035)
for s in (-1, 1):
    arm(s)
    c = Vector((s * 0.114, 0, 0.246))
    cup(c)
    t2 = candle(c, 0.105 if s < 0 else 0.092)
    drip(c, 0.0158, (0.9 if s > 0 else 2.4), t2 - 0.004, 0.06)
    if s < 0:
        drip(c, 0.0158, -1.2, t2 - 0.004, 0.04)
# one run over a pan's rim
drip(Vector((0.114, 0, 0.246)), 0.0275, -0.6, 0.2535, 0.026)

m_iron = bpy.data.materials.get("WR_iron") or mat_flat("WR_iron", (0.045, 0.040, 0.036), rough=0.55, metal=0.7)
m_wax = mat_flat("WR_tallow", (0.72, 0.62, 0.38), rough=0.45)
ob = new_obj("candlestick", bm, "WR_candlestick", [m_iron, m_wax])
finish_mesh(ob, hard_deg=50)
box_uv(ob, {0: 0.25, 1: 0.25})
ob.location = (3.0, 0.0, 0.0)
print("candlestick tris", tris_of(ob), "dims", tuple(round(d, 3) for d in ob.dimensions))
