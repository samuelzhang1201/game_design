# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
import numpy as np

# Blender coords: x +-3, far wall (game -Z) at y=+2.0, near wall (game +Z) at y=-3.0,
# floor z=-0.8, wall top z=2.4. Faces point INTO the room.
XW, YF, YN, ZF, ZC = 3.0, 2.0, -3.0, -0.8, 2.4
STONE, FLOOR, IRON, WAX, GLASS = 0, 1, 2, 3, 4
CEN = Vector((0.0, -0.5, 0.8))
shell = []          # faces to orient toward the room

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
    f = bm.faces.new(vs)
    f.material_index = mat
    shell.append(f)
    return f

# floor, split 3 x 2 so no single triangle spans 6 m
xs = [-XW, -1.0, 1.0, XW]; ys = [YN, -0.5, YF]
for i in range(3):
    for j in range(2):
        Q([(xs[i], ys[j], ZF), (xs[i + 1], ys[j], ZF), (xs[i + 1], ys[j + 1], ZF), (xs[i], ys[j + 1], ZF)], FLOOR)

# plinth course (projects 6 cm, 26 cm tall) on every wall
PL, PH = 0.06, ZF + 0.26
def plinth(a, b, inward):
    a, b, n = Vector(a), Vector(b), Vector(inward)
    a2, b2 = a + n * PL, b + n * PL
    Q([(a.x, a.y, PH), (b.x, b.y, PH), (b2.x, b2.y, PH), (a2.x, a2.y, PH)], STONE)
    Q([(a2.x, a2.y, ZF), (b2.x, b2.y, ZF), (b2.x, b2.y, PH), (a2.x, a2.y, PH)], STONE)
plinth((-XW + PL, YF, 0), (XW - PL, YF, 0), (0, -1, 0))
plinth((-XW + PL, YN, 0), (XW - PL, YN, 0), (0, 1, 0))
plinth((-XW, YN, 0), (-XW, YF, 0), (1, 0, 0))
plinth((XW, YN, 0), (XW, YF, 0), (-1, 0, 0))

# walls: three plain, from the plinth's foot (hidden behind it) to the top
for (a, b) in (((-XW, YN), (XW, YN)), ((-XW, YN), (-XW, YF)), ((XW, YN), (XW, YF))):
    for z0, z1 in ((ZF, ZF + 0.55), (ZF + 0.55, 1.10), (1.10, ZC)):
        Q([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], STONE)

# far wall with a deep-set window: splayed reveals, a window seat, a segmental arch
WI, WO = 0.46, 0.25                 # half widths: inner (room face) / outer (glass)
ZS = ZF + 0.55                      # the seat's top
ZJI, ZJO = 1.10, 1.02               # springing of the arch, inner / outer
RISE_I, RISE_O = 0.24, 0.16
DEPTH = 0.62
YG = YF + DEPTH - 0.04              # glass plane
NA = 6
def arch(w, zj, rise, y):
    pts = []
    for k in range(NA + 1):
        t = k / NA
        x = -w + 2 * w * t
        pts.append((x, y, zj + rise * math.sin(math.pi * t)))
    return pts
ai = arch(WI, ZJI, RISE_I, YF)
ao = arch(WO, ZJO, RISE_O, YF + DEPTH)
# far wall face around the opening
for z0, z1 in ((ZF, ZS), (ZS, ZJI), (ZJI, ZC)):   # split where the opening's corners meet: no T-junctions
    Q([(-XW, YF, z0), (-WI, YF, z0), (-WI, YF, z1), (-XW, YF, z1)], STONE)
    Q([(WI, YF, z0), (XW, YF, z0), (XW, YF, z1), (WI, YF, z1)], STONE)
Q([(-WI, YF, ZF), (WI, YF, ZF), (WI, YF, ZS), (-WI, YF, ZS)], STONE)
for k in range(NA):
    p, q = ai[k], ai[k + 1]
    Q([p, q, (q[0], YF, ZC), (p[0], YF, ZC)], STONE)
# window seat
Q([(-WI, YF, ZS), (WI, YF, ZS), (WO, YF + DEPTH, ZS), (-WO, YF + DEPTH, ZS)], STONE)
# jambs (splayed)
Q([(-WI, YF, ZS), (-WO, YF + DEPTH, ZS), (-WO, YF + DEPTH, ZJO), (-WI, YF, ZJI)], STONE)
Q([(WI, YF, ZS), (WI, YF, ZJI), (WO, YF + DEPTH, ZJO), (WO, YF + DEPTH, ZS)], STONE)
# soffit of the arch
for k in range(NA):
    Q([ai[k], ao[k], ao[k + 1], ai[k + 1]], STONE)
# back of the embrasure round the glass (a stone frame 4 cm deep)
Q([(-WO, YF + DEPTH, ZS), (WO, YF + DEPTH, ZS), (WO, YF + DEPTH, ZJO), (-WO, YF + DEPTH, ZJO)], GLASS)
for k in range(NA):
    p, q = ao[k], ao[k + 1]
    Q([p, q, (q[0], YF + DEPTH, ZJO), (p[0], YF + DEPTH, ZJO)], GLASS)

# orient the shell into the room
for f in shell:
    c = f.calc_center_median()
    if f.normal.dot(CEN - c) < 0:
        f.normal_flip()
# the glass faces the room (-y) regardless
for f in shell:
    if f.material_index == GLASS and f.normal.y > 0:
        f.normal_flip()

# --- two wall sconces, two candles each, flanking the window ---
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
m_iron = bpy.data.materials.get("WR_iron")
m_wax = bpy.data.materials.get("WR_tallow")

# leaded glass: diamond quarries in lead cames, made here (no outside art)
W, H = 256, 512
ys_, xs_ = np.mgrid[0:H, 0:W].astype(np.float32)
u = xs_ / W * 6.0; v = ys_ / H * 6.0 * (H / W) * 0.62
d1 = np.abs(((u + v) % 1.0) - 0.5); d2 = np.abs(((u - v) % 1.0) - 0.5)
lead = np.minimum(np.minimum(d1, d2) / 0.045, 1.0)
rng = np.random.default_rng(3)
tone = 0.78 + 0.06 * np.sin(u * 2.1 + v * 1.3) + rng.normal(0, 0.012, (H, W))
img_rgba = np.zeros((H, W, 4), np.float32)
pane = np.stack([tone * 0.86, tone * 0.92, tone * 0.97], -1)
leadc = np.array([0.05, 0.05, 0.055])
img_rgba[..., :3] = pane * lead[..., None] + leadc * (1 - lead[..., None])
img_rgba[..., 3] = 1.0
gpath = TEX + "/leaded_glass.png"
gi = bpy.data.images.get("leaded_glass.png") or bpy.data.images.new("leaded_glass.png", W, H, alpha=False)
gi.pixels = img_rgba[::-1].reshape(-1)
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
bs.inputs["Emission Strength"].default_value = 1.2
bs.inputs["Roughness"].default_value = 0.3

ob = new_obj("room", bm, "WR_room", [m_stone, m_floor, m_iron, m_wax, m_glass])
finish_mesh(ob, hard_deg=40)
box_uv(ob, {STONE: 2.5, FLOOR: 2.0, IRON: 0.25, WAX: 0.25, GLASS: 1.0})
# the glass: planar over the outer opening, 0..1
me = ob.data
uvl = me.uv_layers.active.data
for p in me.polygons:
    if p.material_index == GLASS:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uvl[li].uv = ((co.x + WO) / (2 * WO), (co.z - ZS) / (ZJO + RISE_O - ZS))
print("room tris", tris_of(ob), "dims", tuple(round(d, 3) for d in ob.dimensions))
