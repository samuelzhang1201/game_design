# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
import numpy as np

# ---------------- RAKE ----------------
# Origin: the head's bottom centre (where it meets the table). The head lies across X
# (16 cm), 3 cm deep; the shaft runs toward the player (game +Z = Blender -Y), lying flat.
ASH, OAK, BRASS = 0, 1, 2
bm = bmesh.new()
HW, HD, HH = 0.08, 0.015, 0.024
rows = [[Vector((-HW, -HD, 0)), Vector((HW, -HD, 0)), Vector((HW, HD, 0)), Vector((-HW, HD, 0))],
        [Vector((-HW, -HD, HH - 0.005)), Vector((HW, -HD, HH - 0.005)), Vector((HW, HD, HH - 0.005)), Vector((-HW, HD, HH - 0.005))],
        [Vector((-HW + 0.004, -HD + 0.004, HH)), Vector((HW - 0.004, -HD + 0.004, HH)), Vector((HW - 0.004, HD - 0.004, HH)), Vector((-HW + 0.004, HD - 0.004, HH))]]
tag(quad_strip(bm, rows, True, True, True), OAK)
# a brass shoe on the head's pushing face (away from the player)
tag(box(bm, (-HW + 0.004, HD, 0.002), (HW - 0.004, HD + 0.0018, 0.012), skip=('-y',)), BRASS)
# shaft: built up +Z then turned so +Z -> -Y, its axis at the head's mid height
ZC_ = HH * 0.5
L = 1.10
seg = 10
fer = [(0.0098, 0.000), (0.0105, 0.004), (0.0105, 0.036), (0.0098, 0.042), (0.0082, 0.044)]
shaft = [(0.0082, 0.044), (0.0086, 0.30), (0.0080, L - 0.03), (0.0084, L - 0.008), (0.0060, L)]
fa = lathe(bm, fer, seg, Vector((0, 0, 0)), phase=math.pi / seg)
sa = lathe(bm, shaft, seg, Vector((0, 0, 0)), cap_end=True, phase=math.pi / seg)
tag(fa, BRASS); tag(sa, ASH)
verts = list({v for f in fa + sa for v in f.verts})
bmesh.ops.rotate(bm, verts=verts, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.radians(90), 3, 'X'))
bmesh.ops.translate(bm, verts=verts, vec=Vector((0, -HD + 0.004, ZC_)))
m_ash = mat_flat("WR_ash", (0.34, 0.235, 0.13), rough=0.6)
m_oak = mat_flat("WR_oak_head", (0.11, 0.062, 0.03), rough=0.65)
m_brass = mat_flat("WR_brass", (0.72, 0.52, 0.22), rough=0.35, metal=1.0)
rk = new_obj("rake", bm, "WR_rake", [m_ash, m_oak, m_brass])
finish_mesh(rk, hard_deg=40)
box_uv(rk, {0: 0.3, 1: 0.3, 2: 0.3})
rk.location = (0.0, -4.5, 0.0)
print("rake tris", tris_of(rk), "dims", tuple(round(d, 4) for d in rk.dimensions))

# ---------------- PENNANT ----------------
# Real size ~35 mm. Origin: the pin's point (bottom centre). One material, a small atlas.
bm = bmesh.new()
CLOTH, PAPER, BR, STR = 0, 1, 2, 3        # temporary indices -> atlas regions
H = 0.035
pin = [(0.00012, 0.0), (0.00055, 0.0016), (0.00055, H - 0.0030)]
tag(lathe(bm, pin, 6, Vector((0, 0, 0)), cap_end=False), BR)
# ball
R = 0.0018
cz = H - R
ball = [(R * math.cos(a), cz + R * math.sin(a)) for a in (math.radians(-60), math.radians(-20), math.radians(20), math.radians(60))]
tag(lathe(bm, ball, 8, Vector((0, 0, 0)), cap_start=True, cap_end=True), BR)

def shell(pts_fn, nu, nv, thick, mat):
    """A thin closed sheet: front grid, back grid (thick apart, along +Y), rim."""
    F = [[pts_fn(i / nu, j / nv) for i in range(nu + 1)] for j in range(nv + 1)]
    front = [[bm.verts.new(p + Vector((0, -thick / 2, 0))) for p in r] for r in F]
    back = [[bm.verts.new(p + Vector((0, thick / 2, 0))) for p in r] for r in F]
    out = []
    for j in range(nv):
        for i in range(nu):
            out.append(bm.faces.new((front[j][i], front[j][i + 1], front[j + 1][i + 1], front[j + 1][i])))
            out.append(bm.faces.new((back[j][i], back[j + 1][i], back[j + 1][i + 1], back[j][i + 1])))
    ring = [(0, i) for i in range(nu)] + [(j, nu) for j in range(nv)] + [(nv, i) for i in range(nu, 0, -1)] + [(j, 0) for j in range(nv, 0, -1)]
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        out.append(bm.faces.new((front[a[0]][a[1]], back[a[0]][a[1]], back[b[0]][b[1]], front[b[0]][b[1]])))
    bmesh.ops.recalc_face_normals(bm, faces=out)
    tag(out, mat)
    return out

# swallowtail cloth: hoist at the pin, fly to +X, notch at mid height, a gentle wave
ZT, ZB = H - 0.0040, H - 0.0040 - 0.0115
def cloth(u, v):
    Lf = 0.0175 - 0.0062 * (1 - abs(2 * v - 1))
    x = 0.0005 + u * Lf
    z = ZT + (ZB - ZT) * v - 0.0010 * u * u          # the fly droops a little
    y = 0.0011 * math.sin(u * math.pi * 1.4) * u
    return Vector((x, y, z))
cloth_faces = shell(cloth, 4, 4, 0.00025, CLOTH)

# paper slip below, tied to the pin, its end notched
PZ0, PZ1 = 0.0098, 0.0148
def paper(u, v):
    Lp = 0.0125 - 0.0022 * (1 - abs(2 * v - 1))
    x = 0.0005 + u * Lp
    z = PZ1 + (PZ0 - PZ1) * v
    y = -0.0004 * math.sin(u * math.pi)
    return Vector((x, y, z))
paper_faces = shell(paper, 3, 2, 0.00018, PAPER)

# string tie round the pin and over the slip, a short loose end
def torus(c, Rm, rm, nu, nv, mat):
    rows = []
    for j in range(nv):
        b = 2 * math.pi * j / nv
        rows.append([c + Vector((math.cos(2 * math.pi * i / nu) * (Rm + rm * math.cos(b)),
                                 math.sin(2 * math.pi * i / nu) * (Rm + rm * math.cos(b)), rm * math.sin(b))) for i in range(nu)])
    rows.append(rows[0])
    fs = quad_strip(bm, rows, True)
    tag(fs, mat)
    return fs
tor = torus(Vector((0.0009, 0, 0.0123)), 0.0011, 0.00028, 6, 3, STR)
tail = [Vector((-0.0006, -0.0008, 0.0122)), Vector((-0.0022, -0.0013, 0.0108)), Vector((-0.0034, -0.0010, 0.0088))]
tag(sweep(bm, tail, [(-0.00022, -0.00022), (0.00022, -0.00022), (0.00022, 0.00022), (-0.00022, 0.00022)], cap_ends=False), STR)

bmesh.ops.remove_doubles(bm, verts=list({v for f in tor for v in f.verts}), dist=1e-9)
bmesh.ops.recalc_face_normals(bm, faces=[f for f in tor if f.is_valid])
# atlas: 4 regions (cloth red | brass / paper | string)
N = 256
A = np.zeros((N, N, 4), np.float32); A[..., 3] = 1
rng = np.random.default_rng(5)
yy, xx = np.mgrid[0:N, 0:N]
def region(r0, c0, rgb, noise=0.02):
    h = N // 2
    blk = np.array(rgb, np.float32)[None, None, :] * (1 + rng.normal(0, noise, (h, h, 1)))
    A[r0:r0 + h, c0:c0 + h, :3] = blk
region(0, 0, (0.55, 0.045, 0.035), 0.05)          # cloth (top-left)
region(0, 128, (0.78, 0.60, 0.26), 0.03)          # brass (top-right)
region(128, 0, (0.78, 0.70, 0.52), 0.03)          # paper (bottom-left)
region(128, 128, (0.62, 0.52, 0.36), 0.06)        # string (bottom-right)
# cloth weave and a pale stitch inside its edge; ink lines on the paper
cl = A[0:128, 0:128, :3]
cl *= (1 + 0.06 * np.sin(np.arange(128) * 1.9))[None, :, None]
cl[[10, 11, 116, 117], 8:120] = (0.80, 0.62, 0.45)
pp = A[128:256, 0:128, :3]
for k in range(5):
    r = 20 + k * 22
    pp[r:r + 2, 10:118] = (0.25, 0.22, 0.18)
pp[30:100, 60:62] = (0.45, 0.12, 0.08)
img = bpy.data.images.get("pennant_atlas.png") or bpy.data.images.new("pennant_atlas.png", N, N, alpha=False)
img.pixels = A[::-1].reshape(-1)     # row 0 of A = top of the image
img.filepath_raw = TEX + "/pennant_atlas.png"; img.file_format = 'PNG'; img.save()
m_pen = bpy.data.materials.get("WR_pennant") or bpy.data.materials.new("WR_pennant")
m_pen.use_nodes = True
nt = m_pen.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
o = nt.nodes.new("ShaderNodeOutputMaterial"); b = nt.nodes.new("ShaderNodeBsdfPrincipled")
nt.links.new(b.outputs[0], o.inputs[0])
t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
# roughness (G) and metal (B) per region, read through Separate Color so glTF packs them
O = np.ones((N, N, 4), np.float32)
O[..., 1] = 0.75; O[..., 2] = 0.0
O[0:128, 128:256, 1] = 0.32; O[0:128, 128:256, 2] = 1.0        # brass
O[0:128, 0:128, 1] = 0.85                                       # cloth
img2 = bpy.data.images.get("pennant_orm.png") or bpy.data.images.new("pennant_orm.png", N, N, alpha=False)
img2.pixels = O[::-1].reshape(-1)
img2.filepath_raw = TEX + "/pennant_orm.png"; img2.file_format = 'PNG'; img2.save()
img2.colorspace_settings.name = "Non-Color"
t2 = nt.nodes.new("ShaderNodeTexImage"); t2.image = img2
sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(t2.outputs["Color"], sep.inputs[0])
nt.links.new(sep.outputs[1], b.inputs["Roughness"])
nt.links.new(sep.outputs[2], b.inputs["Metallic"])
pn = new_obj("pennant", bm, "WR_pennant", [m_pen])
finish_mesh(pn, hard_deg=40, merge=1e-8)
# UVs: each part planar (x,z) into its region with a 6 px margin
me = pn.data
if not me.uv_layers:
    me.uv_layers.new(name="UVMap")
uvl = me.uv_layers.active.data
REG = {CLOTH: (0.0, 0.5), BR: (0.5, 0.5), PAPER: (0.0, 0.0), STR: (0.5, 0.0)}   # (u0, v0) of each 0.5 box, v up
bounds = {}
for p in me.polygons:
    for li in p.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        lo, hi = bounds.get(p.material_index, ((9, 9), (-9, -9)))
        bounds[p.material_index] = ((min(lo[0], co.x), min(lo[1], co.z)), (max(hi[0], co.x), max(hi[1], co.z)))
m = 6 / 256
for p in me.polygons:
    (x0, z0), (x1, z1) = bounds[p.material_index]
    u0, v0 = REG[p.material_index]
    for li in p.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        uu = (co.x - x0) / max(x1 - x0, 1e-6); vv = (co.z - z0) / max(z1 - z0, 1e-6)
        uvl[li].uv = (u0 + m + uu * (0.5 - 2 * m), v0 + m + vv * (0.5 - 2 * m))
for p in me.polygons:
    p.material_index = 0
pn.location = (0.6, -4.5, 0.0)
print("pennant tris", tris_of(pn), "dims", tuple(round(d, 4) for d in pn.dimensions))
