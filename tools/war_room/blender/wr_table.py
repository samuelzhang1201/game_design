# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
import numpy as np

# Blender coords. Game z = -Blender y. Top: x +-0.9, y -0.70..+1.00 (game z +0.70..-1.00).
X0, X1 = -0.9, 0.9
Y0, Y1 = -0.70, 1.00
ZT, ZB = -0.045, -0.105
CH = 0.007            # chamfer of the top's upper edge
WOOD, IRON, WOODV = 0, 1, 2

bm = bmesh.new()

# --- top: chamfered slab (rings bottom -> top) ---
def rect(x0, y0, x1, y1, z):
    return [Vector((x0, y0, z)), Vector((x1, y0, z)), Vector((x1, y1, z)), Vector((x0, y1, z))]
rows = [rect(X0, Y0, X1, Y1, ZB), rect(X0, Y0, X1, Y1, ZT - CH), rect(X0 + CH, Y0 + CH, X1 - CH, Y1 - CH, ZT)]
tag(quad_strip(bm, rows, True, True, True), WOOD)

# --- iron band round the edge face (4 mm proud, 46 mm tall) ---
T = 0.004
zb0, zb1 = -0.099, -0.0535
tag(box(bm, (X0 - T, Y0 - T, zb0), (X1 + T, Y0, zb1), skip=('+y',)), IRON)
tag(box(bm, (X0 - T, Y1, zb0), (X1 + T, Y1 + T, zb1), skip=('-y',)), IRON)
tag(box(bm, (X0 - T, Y0, zb0), (X0, Y1, zb1), skip=('+x', '-y', '+y')), IRON)
tag(box(bm, (X1, Y0, zb0), (X1 + T, Y1, zb1), skip=('-x', '-y', '+y')), IRON)

# --- straps: a plate on the top (60 mm in) + a plate down the edge over the band ---
S, W, TT = 0.003, 0.038, 0.06
def strap_x(x, side):   # on the y-edges (side -1 = Y0, +1 = Y1)
    if side < 0:
        tag(box(bm, (x - W / 2, Y0, ZT), (x + W / 2, Y0 + TT, ZT + S), skip=('-z',)), IRON)
        tag(box(bm, (x - W / 2, Y0 - T - S, ZB - 0.004), (x + W / 2, Y0 - T, ZT + S), skip=('+y',)), IRON)
    else:
        tag(box(bm, (x - W / 2, Y1 - TT, ZT), (x + W / 2, Y1, ZT + S), skip=('-z',)), IRON)
        tag(box(bm, (x - W / 2, Y1 + T, ZB - 0.004), (x + W / 2, Y1 + T + S, ZT + S), skip=('-y',)), IRON)
def strap_y(y, side):
    if side < 0:
        tag(box(bm, (X0, y - W / 2, ZT), (X0 + TT, y + W / 2, ZT + S), skip=('-z',)), IRON)
        tag(box(bm, (X0 - T - S, y - W / 2, ZB - 0.004), (X0 - T, y + W / 2, ZT + S), skip=('+x',)), IRON)
    else:
        tag(box(bm, (X1 - TT, y - W / 2, ZT), (X1, y + W / 2, ZT + S), skip=('-z',)), IRON)
        tag(box(bm, (X1 + T, y - W / 2, ZB - 0.004), (X1 + T + S, y + W / 2, ZT + S), skip=('-x',)), IRON)
for x in np.linspace(X0, X1, 7)[1:-1]:
    strap_x(float(x), -1); strap_x(float(x), 1)
for y in np.linspace(Y0, Y1, 7)[1:-1]:
    strap_y(float(y), -1); strap_y(float(y), 1)

# --- corner caps: an L on the top + plates down both edge faces ---
L = 0.075
for sx, xe in ((-1, X0), (1, X1)):
    for sy, ye in ((-1, Y0), (1, Y1)):
        xa, xb = sorted((xe, xe - sx * L))
        ya, yb = sorted((ye, ye - sy * L))
        yat, ybt = sorted((ye - sy * 0.039, ye - sy * L))
        ya2, yb2 = sorted((ye, ye - sy * 0.04))
        xa2, xb2 = sorted((xe, xe - sx * 0.04))
        tag(box(bm, (xa, ya2, ZT), (xb, yb2, ZT + S), skip=('-z',)), IRON)          # along x
        tag(box(bm, (xa2, yat, ZT), (xb2, ybt, ZT + S), skip=('-z',)), IRON)          # along y
        # down the y-face
        yo = ye + sy * T
        xc, xd = sorted((xe + sx * (T + S), xe - sx * L))
        tag(box(bm, (xc, min(yo, yo + sy * S), ZB - 0.006), (xd, max(yo, yo + sy * S), ZT + S)), IRON)
        xo = xe + sx * T
        tag(box(bm, (min(xo, xo + sx * S), ya, ZB - 0.006), (max(xo, xo + sx * S), yb, ZT + S)), IRON)

# --- legs: square block, turned baluster, square block, bun foot ---
LX = 0.78
LY = (-0.56, 0.86)
H = 0.06
seg = 12
for lx in (-LX, LX):
    for ly in LY:
        c = Vector((lx, ly, 0))
        tag(box(bm, (lx - H, ly - H, -0.30), (lx + H, ly + H, ZB), skip=('+z',)), WOODV)
        prof = [(0.050, -0.300), (0.040, -0.325), (0.044, -0.345), (0.056, -0.425), (0.058, -0.475),
                (0.048, -0.540), (0.035, -0.578), (0.047, -0.598), (0.042, -0.620)]
        tag(lathe(bm, list(reversed([(r, z) for r, z in prof])), seg, c, phase=math.pi / seg), WOODV)
        tag(box(bm, (lx - H, ly - H, -0.740), (lx + H, ly + H, -0.620)), WOODV)
        foot = [(0.030, -0.800), (0.045, -0.792), (0.052, -0.772), (0.046, -0.752), (0.040, -0.740)]
        tag(lathe(bm, foot, seg, c, cap_start=True, phase=math.pi / seg), WOODV)

# --- aprons (rails under the top) ---
A = 0.04
ZA0 = -0.215
tag(box(bm, (-LX + H, LY[0] - H + 0.008, ZA0), (LX - H, LY[0] - H + 0.008 + A, ZB), skip=('+z',)), WOOD)
tag(box(bm, (-LX + H, LY[1] + H - 0.008 - A, ZA0), (LX - H, LY[1] + H - 0.008, ZB), skip=('+z',)), WOOD)
for lx in (-LX, LX):
    s = 1 if lx > 0 else -1
    xa, xb = sorted((lx + s * (H - 0.008), lx + s * (H - 0.008 - A)))
    tag(box(bm, (xa, LY[0] + H, ZA0), (xb, LY[1] - H, ZB), skip=('+z',)), WOODV)

# --- stretchers: one along each end (y), one long one (x) between them ---
ZS0, ZS1 = -0.715, -0.655
for lx in (-LX, LX):
    tag(box(bm, (lx - 0.03, LY[0] + H, ZS0), (lx + 0.03, LY[1] - H, ZS1), skip=('-y', '+y')), WOOD)
ym = (LY[0] + LY[1]) / 2
tag(box(bm, (-LX + 0.03, ym - 0.03, ZS0 + 0.005), (LX - 0.03, ym + 0.03, ZS1 - 0.005), skip=('-x', '+x')), WOOD)

m_wood = mat_tex("WR_table_oak", TEX + "/dark_wooden_planks_diffuse_2k_oak.jpg", TEX + "/dark_wooden_planks_nor_gl_2k.jpg",
                 TEX + "/dark_wooden_planks_rough_2k.jpg")
m_iron = mat_flat("WR_iron", (0.045, 0.040, 0.036), rough=0.55, metal=0.7)
ob = new_obj("table", bm, "WR_table", [m_wood, m_iron, m_wood])
finish_mesh(ob)
box_uv(ob, {0: 2.0, 1: 0.5, 2: 2.0}, rot90_mats=(2,))
# fold the vertical-grain wood back into the wood slot
for p in ob.data.polygons:
    if p.material_index == 2:
        p.material_index = 0
ob.data.materials.pop(index=2)
print("table tris", tris_of(ob), "dims", tuple(round(d, 3) for d in ob.dimensions))
