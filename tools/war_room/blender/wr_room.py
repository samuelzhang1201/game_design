# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
import numpy as np

# The sunlit chamber (spec 2026-10-13-war-room-sunlit-chamber): the far (north)
# wall closed for the wall map, a paired lancet window in a deep splayed
# embrasure with a stone seat in the WEST wall beside the table, a plank
# ceiling on oak beams (it closes the room to the sun). The glazing is its own
# object `glass` so the chamber casts shadows and the glass does not.
#
# Blender coords: x +-3, far wall (game -Z) at y=+2.0, near wall (game +Z) at y=-3.0,
# floor z=-0.8, wall top / ceiling z=2.4. Faces point INTO the room.
XW, YF, YN, ZF, ZC = 3.0, 2.0, -3.0, -0.8, 2.4
STONE, FLOOR, IRON, WAX, BEAM, PLANK = 0, 1, 2, 3, 4, 5
CEN = Vector((0.0, -0.5, 0.8))
shell = []          # faces to orient toward the room

# --- the west window (Blender y = -game z) ---
WC = 0.3                      # the embrasure's centre along the wall (game z -0.3: beside the table)
DEPTH = 0.7                   # wall thickness at the window
XO = -XW - DEPTH              # the glazing plane
AI, AO = 0.85, 0.64           # embrasure half widths: inner (room face) / outer (glazing plane)
ZSEAT = ZF + 0.45             # the window seat's top
ZG0 = -0.05                   # the glass's sill: just under the table top (y 0)
ZJI, RI = 1.15, 1.10          # inner arch: springing, radius of its two-centred arcs
ZJO, RO = 1.40, 0.90          # outer arch (round the lancets)
LW, MW = 0.48, 0.14           # a lancet's width, the mullion's
ZLS = 1.30                    # the lancets' springing; equilateral points (radius = width)
NA = 10                       # segments along an arch
NL = 8                        # segments across a lancet


def two_centred(x, a, r):
    """Height over the springing of a pointed arch of half-width a whose two arcs
    have radius r, at x (from its centre); 0 at +-a."""
    xc = -(r - a) if x >= 0 else (r - a)
    return math.sqrt(max(r * r - (x - xc) ** 2, 0.0))


def inner_arch(t):
    x = -AI + 2 * AI * t
    return (x, ZJI + two_centred(x, AI, RI))


def outer_arch(t):
    x = -AO + 2 * AO * t
    return (x, ZJO + two_centred(x, AO, RO))


LANCETS = [(-MW / 2 - LW / 2), (MW / 2 + LW / 2)]   # centres along the wall, from the embrasure's centre


def lancet_top(x, c):
    return ZLS + two_centred(x - c, LW / 2, LW)


bm = bmesh.new()
_vc = {}
def V(p):
    k = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
    if k not in _vc:
        _vc[k] = bm.verts.new(k)
    return _vc[k]
def Q(pts, mat):
    vs = []
    for p in pts:
        v = V(p)
        if v not in vs:
            vs.append(v)
    if len(vs) < 3:
        return None
    f = bm.faces.new(vs)
    f.material_index = mat
    shell.append(f)
    return f

def W(s, z):
    """A point on the west wall's face: s along the wall from the embrasure's centre."""
    return (-XW, WC + s, z)

def B(s, z):
    """A point on the glazing plane."""
    return (XO, WC + s, z)

# floor, split 3 x 2 so no single triangle spans 6 m
xs = [-XW, -1.0, 1.0, XW]; ys = [YN, -0.5, YF]
for i in range(3):
    for j in range(2):
        Q([(xs[i], ys[j], ZF), (xs[i + 1], ys[j], ZF), (xs[i + 1], ys[j + 1], ZF), (xs[i], ys[j + 1], ZF)], FLOOR)

# plinth course (projects 6 cm, 26 cm tall); the west one stops at the seat
PL, PH = 0.06, ZF + 0.26
def plinth(a, b, inward):
    a, b, n = Vector(a), Vector(b), Vector(inward)
    a2, b2 = a + n * PL, b + n * PL
    Q([(a.x, a.y, PH), (b.x, b.y, PH), (b2.x, b2.y, PH), (a2.x, a2.y, PH)], STONE)
    Q([(a2.x, a2.y, ZF), (b2.x, b2.y, ZF), (b2.x, b2.y, PH), (a2.x, a2.y, PH)], STONE)
plinth((-XW + PL, YF, 0), (XW - PL, YF, 0), (0, -1, 0))
plinth((-XW + PL, YN, 0), (XW - PL, YN, 0), (0, 1, 0))
plinth((-XW, YN, 0), (-XW, WC - AI, 0), (1, 0, 0))
plinth((-XW, WC + AI, 0), (-XW, YF, 0), (1, 0, 0))
plinth((XW, YN, 0), (XW, YF, 0), (-1, 0, 0))

# three plain walls: north (far), south (near), east
for (a, b) in (((-XW, YF), (XW, YF)), ((-XW, YN), (XW, YN)), ((XW, YN), (XW, YF))):
    for z0, z1 in ((ZF, ZF + 0.55), (ZF + 0.55, 1.10), (1.10, ZC)):
        Q([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], STONE)

# west wall round the embrasure, split where the opening's corners meet (no T-junctions)
for z0, z1 in ((ZF, ZSEAT), (ZSEAT, ZJI), (ZJI, ZC)):
    Q([(-XW, YN, z0), W(-AI, z0), W(-AI, z1), (-XW, YN, z1)], STONE)
    Q([W(AI, z0), (-XW, YF, z0), (-XW, YF, z1), W(AI, z1)], STONE)
Q([W(-AI, ZF), W(AI, ZF), W(AI, ZSEAT), W(-AI, ZSEAT)], STONE)        # the seat's front
ai = [inner_arch(k / NA) for k in range(NA + 1)]
for k in range(NA):
    (s0, z0), (s1, z1) = ai[k], ai[k + 1]
    Q([W(s0, z0), W(s1, z1), W(s1, ZC), W(s0, ZC)], STONE)

# the embrasure: seat, splayed jambs, soffit
Q([W(-AI, ZSEAT), W(AI, ZSEAT), B(AO, ZSEAT), B(-AO, ZSEAT)], STONE)
Q([W(-AI, ZSEAT), B(-AO, ZSEAT), B(-AO, ZJO), W(-AI, ZJI)], STONE)
Q([W(AI, ZSEAT), W(AI, ZJI), B(AO, ZJO), B(AO, ZSEAT)], STONE)
ao = [outer_arch(k / NA) for k in range(NA + 1)]
for k in range(NA):
    (si0, zi0), (si1, zi1) = ai[k], ai[k + 1]
    (so0, zo0), (so1, zo1) = ao[k], ao[k + 1]
    Q([W(si0, zi0), B(so0, zo0), B(so1, zo1), W(si1, zi1)], STONE)

# the glazing plane: stone round two lancets; the glass itself into `gbm`
def outer_top(s):
    return ZJO + two_centred(s, AO, RO)

cols = [-AO, -MW / 2 - LW]
cols += [-MW / 2 - LW + LW * k / NL for k in range(1, NL + 1)]      # left lancet
cols += [MW / 2 + LW * k / NL for k in range(0, NL + 1)]            # mullion, right lancet
cols += [AO]
glass_quads = []
for i in range(len(cols) - 1):
    s0, s1 = cols[i], cols[i + 1]
    Q([B(s0, ZSEAT), B(s1, ZSEAT), B(s1, ZG0), B(s0, ZG0)], STONE)   # below the sill
    lanc = None
    for c in LANCETS:
        if c - LW / 2 - 1e-6 <= s0 and s1 <= c + LW / 2 + 1e-6:
            lanc = c
    if lanc is None:            # side strip or mullion: stone to the outer arch
        Q([B(s0, ZG0), B(s1, ZG0), B(s1, outer_top(s1)), B(s0, outer_top(s0))], STONE)
    else:
        t0, t1 = lancet_top(s0, lanc), lancet_top(s1, lanc)
        glass_quads.append((lanc, s0, s1, t0, t1))
        Q([B(s0, t0), B(s1, t1), B(s1, outer_top(s1)), B(s0, outer_top(s0))], STONE)

# --- ceiling: planks on oak beams running east-west ---
for j in range(2):
    for i in range(3):
        Q([(xs[i], ys[j], ZC), (xs[i + 1], ys[j], ZC), (xs[i + 1], ys[j + 1], ZC), (xs[i], ys[j + 1], ZC)], PLANK)

# orient the shell into the room
for f in shell:
    c = f.calc_center_median()
    if f.normal.dot(CEN - c) < 0:
        f.normal_flip()

BH, BWH = 0.24, 0.10          # beam depth, half width
for yb in (-2.2, -1.1, 0.0, 1.1):
    tag(box(bm, (-XW, yb - BWH, ZC - BH), (XW, yb + BWH, ZC), skip=('+z', '-x', '+x')), BEAM)
tag(box(bm, (-XW, YF - 0.18, ZC - 0.16), (XW, YF, ZC), skip=('+z', '-x', '+x', '+y')), BEAM)   # wall plates
tag(box(bm, (-XW, YN, ZC - 0.16), (XW, YN + 0.18, ZC), skip=('+z', '-x', '+x', '-y')), BEAM)

# --- two wall sconces, two candles each, flanking the wall map ---
SEC = [(-0.005, -0.005), (0.005, -0.005), (0.005, 0.005), (-0.005, 0.005)]
def sconce(x0):
    wy = YF                                # wall face
    tag(box(bm, (x0 - 0.035, wy - 0.014, 0.78), (x0 + 0.035, wy, 1.00), skip=('+y',)), IRON)
    for s in (-1, 1):
        pts = []
        for k in range(8):                 # out from the plate, a scroll down then up to the pan
            t = k / 7
            x = x0 + s * (0.02 + 0.13 * t)
            y = wy - 0.014 - 0.13 * math.sin(math.pi * 0.5 * t)
            z = 0.84 - 0.05 * math.sin(math.pi * t) + 0.10 * t * t
            pts.append(Vector((x, y, z)))
        tag(sweep(bm, pts, SEC), IRON)
        c = pts[-1] + Vector((0, 0, 0.004))
        prof = [(0.008, 0.000), (0.034, 0.003), (0.035, 0.008), (0.019, 0.010), (0.020, 0.030), (0.024, 0.035), (0.0175, 0.0355)]
        tag(lathe(bm, prof, 8, c, phase=math.pi / 8), IRON)
        h = 0.11 if s < 0 else 0.13
        rows = []
        for (rr, zz) in ((0.0172, 0.016), (0.0175, 0.016 + h), (0.011, 0.016 + h - 0.008)):
            rows.append([c + Vector((math.cos(a) * rr, math.sin(a) * rr, zz)) for a in
                         [2 * math.pi * k / 8 + math.pi / 8 for k in range(8)]])
        tag(quad_strip(bm, rows, True, False, True), WAX)
sconce(-1.25)
sconce(1.25)

# --- materials ---
m_stone = mat_tex("WR_stone", TEX + "/stone_brick_wall_001_diffuse_2k.jpg", TEX + "/stone_brick_wall_001_nor_gl_2k.jpg",
                  TEX + "/stone_brick_wall_001_rough_2k.jpg")
m_floor = mat_tex("WR_floor", TEX + "/weathered_planks_diffuse_2k.jpg", TEX + "/weathered_planks_nor_gl_2k.jpg",
                  TEX + "/weathered_planks_rough_2k.jpg")
m_iron = bpy.data.materials.get("WR_iron") or mat_flat("WR_iron", (0.045, 0.040, 0.036), rough=0.55, metal=0.7)
m_wax = bpy.data.materials.get("WR_tallow") or mat_flat("WR_tallow", (0.72, 0.62, 0.38), rough=0.45)
m_beam = mat_tex("WR_beam", TEX + "/dark_wooden_planks_diffuse_2k_oak.jpg", TEX + "/dark_wooden_planks_nor_gl_2k.jpg",
                 TEX + "/dark_wooden_planks_rough_2k.jpg")
m_plank = mat_tex("WR_ceiling", TEX + "/weathered_planks_diffuse_2k.jpg", TEX + "/weathered_planks_nor_gl_2k.jpg",
                  TEX + "/weathered_planks_rough_2k.jpg", rough_val=0.9)

ob = new_obj("room", bm, "WR_room", [m_stone, m_floor, m_iron, m_wax, m_beam, m_plank])
finish_mesh(ob, hard_deg=40)
box_uv(ob, {STONE: 2.5, FLOOR: 2.0, IRON: 0.25, WAX: 0.25, BEAM: 1.5, PLANK: 2.0}, rot90_mats=(BEAM,))
# stains as a vertex colour (Godot multiplies it into the albedo): damp and grime at the
# foot of the walls, smoke under the ceiling, the floor dark toward its walls
me = ob.data
ca = me.color_attributes.get("Col") or me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
def _sm(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)
for poly in me.polygons:
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        f = 1.0
        if poly.material_index == STONE:
            f = 0.5 + 0.5 * _sm((co.z - ZF) / 1.1)                     # damp and grime at the foot
            f *= 1.0 - 0.18 * _sm((co.z - (ZC - 0.7)) / 0.7)           # smoke under the ceiling
        elif poly.material_index == FLOOR:
            wall = min(abs(abs(co.x) - XW), abs(co.y - YF), abs(co.y - YN))
            f = 0.62 + 0.38 * _sm(wall / 1.2)
        elif poly.material_index in (BEAM, PLANK):
            f = 0.78
        ca.data[li].color = (f, f * 0.97, f * 0.93, 1.0)
print("room tris", tris_of(ob), "dims", tuple(round(d, 3) for d in ob.dimensions))

# --- the glass: two lancets, UV 0..1 over each, facing the room (+x) ---
# lead cames: diamond quarries, ~4 across a lancet, plus a came round the edge
GW, GH = 256, 1024
apex = ZLS + two_centred(0.0, LW / 2, LW)
ys_, xs_ = np.mgrid[0:GH, 0:GW].astype(np.float32)
u = (xs_ + 0.5) / GW * 4.0
v = (ys_ + 0.5) / GH * 4.0 * ((apex - ZG0) / LW) / 1.6
d1 = np.abs(((u + v) % 1.0) - 0.5); d2 = np.abs(((u - v) % 1.0) - 0.5)
lead = np.minimum(np.minimum(d1, d2) / 0.05, 1.0)
edge = np.minimum(np.minimum(xs_, GW - 1 - xs_) / (GW * 0.03), 1.0)
lead = np.minimum(lead, edge)
gimg = np.zeros((GH, GW, 4), np.float32)
gimg[..., 0] = gimg[..., 1] = gimg[..., 2] = lead
gimg[..., 3] = 1.0
gpath = TEX + "/leaded_glass.png"
gi = bpy.data.images.get("leaded_glass.png")
if gi is not None and tuple(gi.size) != (GW, GH):
    bpy.data.images.remove(gi)
    gi = None
gi = gi or bpy.data.images.new("leaded_glass.png", GW, GH, alpha=False)
gi.pixels = gimg[::-1].reshape(-1)
gi.filepath_raw = gpath
gi.file_format = 'PNG'
gi.save()
m_glass = bpy.data.materials.get("WR_window") or bpy.data.materials.new("WR_window")
m_glass.use_nodes = True
nt = m_glass.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
nt.links.new(bs.outputs[0], out.inputs[0])
t = nt.nodes.new("ShaderNodeTexImage"); t.image = gi
nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
nt.links.new(t.outputs["Color"], bs.inputs["Emission Color"])
bs.inputs["Emission Strength"].default_value = 3.0
bs.inputs["Roughness"].default_value = 0.3

gbm = bmesh.new()
lay = gbm.faces.layers.int.new("lancet")   # before any face: a new layer drops every BMFace held
uvl = gbm.loops.layers.uv.new("UVMap")
gv = {}
def GV(p):
    k = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
    if k not in gv:
        gv[k] = gbm.verts.new(k)
    return gv[k]
for (c, s0, s1, t0, t1) in glass_quads:
    pts = [B(s0, ZG0), B(s0, t0), B(s1, t1), B(s1, ZG0)]       # wound to face +x (into the room)
    vs = []
    for p in pts:
        v_ = GV(p)
        if v_ not in vs:
            vs.append(v_)
    if len(vs) < 3:
        continue
    f = gbm.faces.new(vs)
    f.normal_update()
    if f.normal.x < 0:
        f.normal_flip()
    f.material_index = 0
    f[lay] = 0 if c < 0 else 1
for f in gbm.faces:
    c = LANCETS[f[lay]]
    for l in f.loops:
        co = l.vert.co
        l[uvl].uv = ((co.y - WC - (c - LW / 2)) / LW, (co.z - ZG0) / (apex - ZG0))
gob = new_obj("glass", gbm, "WR_room", [m_glass])
print("glass tris", tris_of(gob), "lancet apex", round(apex, 3), "sill", ZG0)

# the lattice: the glass's own mesh again, a separate object the scene sets to
# cast SHADOW ONLY with war_window_lattice.tres (the lead cames cut out of the sun)
old = bpy.data.objects.get("lattice")
if old is not None:
    bpy.data.objects.remove(old, do_unlink=True)
lme = gob.data.copy()
lme.name = "lattice"
lme.materials.clear()
lme.materials.append(bpy.data.materials.get("WR_lattice") or bpy.data.materials.new("WR_lattice"))
lob = bpy.data.objects.new("lattice", lme)
coll("WR_room").objects.link(lob)
