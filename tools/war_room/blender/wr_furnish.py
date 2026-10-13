# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
import random
import numpy as np

# The sunlit chamber's dressing (spec 2026-10-13-war-room-sunlit-chamber), game
# budget: no subdivision, hard edges by angle, real sizes in metres. Each object
# has its origin at its foot's centre and its FRONT toward Blender -y (game +Z);
# the scene turns and places it. References: assets/imagegen/room_prop_prompts.csv
# WP-01..WP-13. Call build_<name>() one at a time, or build_all().

COL = "WR_dressing"


def mats():
    oak = bpy.data.materials.get("WR_table_oak") or mat_tex(
        "WR_table_oak", TEX + "/dark_wooden_planks_diffuse_2k_oak.jpg", TEX + "/dark_wooden_planks_nor_gl_2k.jpg",
        TEX + "/dark_wooden_planks_rough_2k.jpg")
    iron = bpy.data.materials.get("WR_iron") or mat_flat("WR_iron", (0.045, 0.040, 0.036), rough=0.55, metal=0.7)
    wax = bpy.data.materials.get("WR_tallow") or mat_flat("WR_tallow", (0.72, 0.62, 0.38), rough=0.45)
    return {
        "oak": oak, "iron": iron, "wax": wax,
        "paper": parchment(),
        "seal": bpy.data.materials.get("WR_seal") or mat_flat("WR_seal", (0.38, 0.05, 0.04), rough=0.4),
        "leather": bpy.data.materials.get("WR_leather") or mat_flat("WR_leather", (0.16, 0.08, 0.045), rough=0.7),
        "horn": bpy.data.materials.get("WR_horn") or mat_flat("WR_horn", (0.12, 0.09, 0.06), rough=0.35),
        "quill": bpy.data.materials.get("WR_quill") or mat_flat("WR_quill", (0.78, 0.75, 0.68), rough=0.8),
        "cord": bpy.data.materials.get("WR_cord") or mat_flat("WR_cord", (0.36, 0.28, 0.18), rough=0.9),
    }


def parchment():
    """Old paper: a warm cream, uneven, darker at random patches (painted here)."""
    m = bpy.data.materials.get("WR_parchment")
    if m is not None:
        return m
    S = 256
    rng = np.random.default_rng(11)
    base = rng.normal(0, 1, (S // 16, S // 16))
    big = np.kron(base, np.ones((16, 16)))
    for _ in range(3):   # blur by box passes, wrapping (the texture tiles)
        big = (big + np.roll(big, 4, 0) + np.roll(big, -4, 0) + np.roll(big, 4, 1) + np.roll(big, -4, 1)) / 5
    fine = rng.normal(0, 1, (S, S)) * 0.015
    t = 0.62 + 0.06 * big / (np.abs(big).max() + 1e-6) + fine
    rgba = np.zeros((S, S, 4), np.float32)
    rgba[..., 0], rgba[..., 1], rgba[..., 2], rgba[..., 3] = t * 0.95, t * 0.82, t * 0.6, 1.0
    path = TEX + "/parchment.png"
    im = bpy.data.images.new("parchment.png", S, S, alpha=False)
    im.pixels = rgba.reshape(-1)
    im.filepath_raw = path
    im.file_format = 'PNG'
    im.save()
    return mat_tex("WR_parchment", path, rough_val=0.85)


def obj_from(name, bm, mlist, tiles, hard=40.0):
    ob = new_obj(name, bm, COL, mlist)
    finish_mesh(ob, hard_deg=hard)
    box_uv(ob, tiles)
    return ob


def bx(bm, x0, y0, z0, x1, y1, z1, mi, skip=()):
    tag(box(bm, (x0, y0, z0), (x1, y1, z1), skip=skip), mi)


def cyl(bm, c, axis, r, length, seg, mi, caps=True, phase=0.0):
    """A cylinder of `seg` sides along a unit axis from c (its first end)."""
    axis = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    a = axis.cross(ref).normalized()
    b = axis.cross(a).normalized()
    rows = []
    for d in (0.0, length):
        rows.append([Vector(c) + axis * d + (a * math.cos(2 * math.pi * k / seg + phase) + b * math.sin(2 * math.pi * k / seg + phase)) * r
                     for k in range(seg)])
    tag(quad_strip(bm, rows, True, caps, caps), mi)


def cyl_front(bm, c, r, length, mi, phase):
    """A 6-sided scroll along +y from c, capped only at its front (-y) end."""
    rows = [[Vector(c) + Vector((math.cos(2 * math.pi * k / 6 + phase) * r, d, math.sin(2 * math.pi * k / 6 + phase) * r))
             for k in range(6)] for d in (0.0, length)]
    tag(quad_strip(bm, rows, True, True, False), mi)


# ---------------------------------------------------------------- WP-01 rack
def build_rack(name="rack", seed=1):
    M = mats()
    OAK, PAPER, SEAL, CORD = 0, 1, 2, 3
    bm = bmesh.new()
    W, D, H = 1.0, 0.38, 1.95
    T, BASE = 0.03, 0.09
    rows, cols = 5, 4
    bx(bm, -W / 2, -D / 2, 0, -W / 2 + T, D / 2, H, OAK)                     # sides
    bx(bm, W / 2 - T, -D / 2, 0, W / 2, D / 2, H, OAK)
    bx(bm, -W / 2 - 0.015, -D / 2 - 0.015, H, W / 2 + 0.015, D / 2 + 0.01, H + 0.035, OAK)   # top
    bx(bm, -W / 2 + T, D / 2 - 0.015, BASE, W / 2 - T, D / 2, H, OAK, skip=('-x', '+x'))     # back
    bx(bm, -W / 2 + T, -D / 2 + 0.01, 0, W / 2 - T, -D / 2 + 0.03, BASE, OAK, skip=('-x', '+x'))   # plinth front
    inner_w = (W - 2 * T)
    cw = inner_w / cols
    ch = (H - BASE) / rows
    for r in range(rows + 1):                                              # shelves
        z = BASE + r * ch
        bx(bm, -W / 2 + T, -D / 2, z - 0.012, W / 2 - T, D / 2 - 0.015, z + 0.012, OAK, skip=('-x', '+x', '+y'))
    for c in range(1, cols):                                               # uprights
        x = -W / 2 + T + c * cw
        for r in range(rows):
            z0, z1 = BASE + r * ch + 0.012, BASE + (r + 1) * ch - 0.012
            bx(bm, x - 0.01, -D / 2, z0, x + 0.01, D / 2 - 0.015, z1, OAK, skip=('-z', '+z', '+y'))
    rng = random.Random(seed)
    for r in range(rows):
        for c in range(cols):
            x0 = -W / 2 + T + c * cw + 0.012
            x1 = x0 + cw - 0.024
            zf = BASE + r * ch + 0.012
            if rng.random() < 0.18:      # a bundle of folded letters, a seal on the top one
                n = rng.randint(3, 6)
                for k in range(n):
                    lx = rng.uniform(x0 + 0.01, x1 - 0.17)
                    bx(bm, lx, -D / 2 + 0.05, zf + k * 0.012, lx + 0.16, -D / 2 + 0.05 + 0.11, zf + (k + 1) * 0.012 - 0.002, PAPER)
                cyl(bm, (lx + 0.08, -D / 2 + 0.06, zf + n * 0.012), (0, 0, 1), 0.013, 0.004, 8, SEAL)
                continue
            # scrolls lying along the depth, their ends to the front, heaped course on
            # course to most of the hole's height (only the front end is capped: the
            # back one is never seen)
            fill = zf + (ch - 0.024) * rng.uniform(0.72, 0.88)
            course = 0
            z = zf
            while True:
                rmax = 0.0
                x = x0 + (rng.uniform(0.008, 0.02) if course % 2 else 0.0)
                placed = False
                while True:
                    rr = rng.uniform(0.02, 0.034)
                    if x + 2 * rr > x1:
                        break
                    if z + 2 * rr > fill:
                        break
                    ln = rng.uniform(0.24, D - 0.05)
                    y0 = -D / 2 + rng.uniform(-0.035, 0.03)
                    sag = rng.uniform(-0.004, 0.004)
                    cyl_front(bm, (x + rr, y0, z + rr + sag), rr, ln, PAPER, rng.uniform(0, 1))
                    rmax = max(rmax, rr)
                    x += 2 * rr + rng.uniform(0.0, 0.006)
                    placed = True
                if not placed:
                    break
                z += rmax * 1.7
                course += 1
    ob = obj_from(name, bm, [M["oak"], M["paper"], M["seal"], M["cord"]], {OAK: 1.0, PAPER: 0.3, SEAL: 0.1, CORD: 0.2})
    return ob


# ---------------------------------------------------------------- WP-02 lectern
def build_lectern(name="lectern"):
    M = mats()
    OAK, LEATHER, PAPER = 0, 1, 2
    bm = bmesh.new()
    # cross foot and post
    bx(bm, -0.30, -0.045, 0, 0.30, 0.045, 0.07, OAK)
    bx(bm, -0.045, -0.30, 0, 0.045, 0.30, 0.07, OAK)
    bx(bm, -0.045, -0.045, 0.07, 0.045, 0.045, 0.98, OAK)
    bx(bm, -0.07, -0.07, 0.98, 0.07, 0.07, 1.02, OAK)
    # the slanted desk: a board 0.56 x 0.42, rising 30 deg toward the back (+y)
    ang = math.radians(30)
    bmd = bmesh.new()
    bx(bmd, -0.28, -0.21, 0.0, 0.28, 0.21, 0.025, OAK)
    bx(bmd, -0.28, -0.235, 0.0, 0.28, -0.21, 0.06, OAK)          # the ledge at the front edge
    # the open ledger: two page blocks rising to the spine, a leather cover under them
    for sgn in (-1, 1):
        rows = []
        for k in range(5):
            t = k / 4
            x = sgn * (0.006 + 0.2 * t)
            z = 0.058 - 0.022 * t * t
            rows.append((x, z))
        top = [[Vector((x, -0.15, z)), Vector((x, 0.15, z))] for (x, z) in rows]
        tag(quad_strip(bmd, top, False), PAPER)
        xe, ze = rows[-1]
        tag([bmd.faces.new([bmd.verts.new(p) for p in ((xe, -0.15, 0.03), (xe, 0.15, 0.03), (xe, 0.15, ze), (xe, -0.15, ze))])], PAPER)
        bx(bmd, min(0, sgn * 0.215), -0.165, 0.025, max(0, sgn * 0.215), 0.165, 0.03, LEATHER)
    mat_r = Matrix.Rotation(-ang, 4, 'X')
    bmesh.ops.transform(bmd, matrix=Matrix.Translation((0, 0, 1.02)) @ mat_r, verts=bmd.verts)
    me_tmp = bpy.data.meshes.new("_tmp_lectern")
    bmd.to_mesh(me_tmp)
    bmd.free()
    bm.from_mesh(me_tmp)
    bpy.data.meshes.remove(me_tmp)
    return obj_from(name, bm, [M["oak"], M["leather"], M["paper"]], {OAK: 1.0, LEATHER: 0.3, PAPER: 0.4})


# ---------------------------------------------------------------- WP-03 map chest
def handle(bm, x, y, z, mi):
    """A forged drop handle: a back plate and a hanging half ring, y = the face."""
    bx(bm, x - 0.035, y - 0.004, z - 0.012, x + 0.035, y, z + 0.012, mi, skip=('+y',))
    pts = [Vector((x + 0.03 * math.cos(math.pi * k / 6), y - 0.012, z - 0.03 * math.sin(math.pi * k / 6))) for k in range(7)]
    tag(sweep(bm, pts, [(-0.004, -0.004), (0.004, -0.004), (0.004, 0.004), (-0.004, 0.004)]), mi)


def build_map_chest(name="map_chest"):
    M = mats()
    OAK, IRON, PAPER = 0, 1, 2
    bm = bmesh.new()
    W, D, H = 1.2, 0.7, 0.85
    bx(bm, -W / 2 + 0.02, -D / 2 + 0.03, 0, W / 2 - 0.02, D / 2 - 0.02, 0.08, OAK)        # plinth
    bx(bm, -W / 2, -D / 2 + 0.02, 0.08, W / 2, D / 2, H - 0.035, OAK, skip=('-y',))      # carcass, open front
    bx(bm, -W / 2 - 0.025, -D / 2 - 0.005, H - 0.035, W / 2 + 0.025, D / 2 + 0.01, H, OAK)   # top
    n = 6
    z0, z1 = 0.10, H - 0.05
    dh = (z1 - z0) / n
    yf = -D / 2 + 0.02
    bx(bm, -W / 2, yf, 0.08, W / 2, yf + 0.005, H - 0.035, OAK, skip=('-y',))           # the drawers' back shadow face
    for k in range(n):
        za, zb = z0 + k * dh + 0.006, z0 + (k + 1) * dh - 0.006
        bx(bm, -W / 2 + 0.035, yf - 0.02, za, W / 2 - 0.035, yf, zb, OAK, skip=('+y',))
        zc = (za + zb) / 2
        handle(bm, -W / 4, yf - 0.02, zc + 0.01, IRON)
        handle(bm, W / 4, yf - 0.02, zc + 0.01, IRON)
    cyl(bm, (-0.35, 0.05, H + 0.03), (1, 0.12, 0), 0.03, 0.7, 8, PAPER)                   # a rolled map on top
    return obj_from(name, bm, [M["oak"], M["iron"], M["paper"]], {OAK: 1.0, IRON: 0.2, PAPER: 0.3})


# ---------------------------------------------------------------- WP-12 side table
def build_side_table(name="side_table", seed=4):
    M = mats()
    OAK, HORN, QUILL, SEAL, PAPER = 0, 1, 2, 3, 4
    bm = bmesh.new()
    W, D, H, L = 0.6, 0.42, 0.74, 0.045
    bx(bm, -W / 2 - 0.02, -D / 2 - 0.02, H - 0.03, W / 2 + 0.02, D / 2 + 0.02, H, OAK)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W / 2 - L / 2 - 0.01), sy * (D / 2 - L / 2 - 0.01)
            bx(bm, x - L / 2, y - L / 2, 0, x + L / 2, y + L / 2, H - 0.03, OAK)
    bx(bm, -W / 2 + 0.03, -D / 2 + 0.02, H - 0.11, W / 2 - 0.03, -D / 2 + 0.04, H - 0.03, OAK, skip=('+z',))   # aprons
    bx(bm, -W / 2 + 0.03, D / 2 - 0.04, H - 0.11, W / 2 - 0.03, D / 2 - 0.02, H - 0.03, OAK, skip=('+z',))
    bx(bm, -W / 2 + 0.03, -0.015, 0.12, W / 2 - 0.03, 0.015, 0.15, OAK)                  # stretcher
    for sx in (-1, 1):
        bx(bm, sx * (W / 2 - 0.035) - 0.015, -D / 2 + 0.04, 0.12, sx * (W / 2 - 0.035) + 0.015, D / 2 - 0.04, 0.15, OAK)
    top = H
    # papers, the inkwell, the sand shaker, the wax, three quills
    for k in range(5):
        bx(bm, -0.24 + k * 0.002, -0.12, top + k * 0.003, -0.02 + k * 0.002, 0.06 - k * 0.003, top + (k + 1) * 0.003, PAPER)
    tag(lathe(bm, [(0.0, 0.0), (0.035, 0.0), (0.04, 0.012), (0.036, 0.045), (0.016, 0.06), (0.016, 0.07), (0.011, 0.07)],
              12, Vector((0.12, 0.0, top)), cap_start=True), HORN)
    tag(lathe(bm, [(0.0, 0.0), (0.025, 0.0), (0.027, 0.06), (0.02, 0.075), (0.008, 0.085), (0.0, 0.088)],
              10, Vector((0.2, 0.1, top)), cap_start=True), HORN)
    bx(bm, 0.04, -0.15, top, 0.16, -0.135, top + 0.014, SEAL)
    rng = random.Random(seed)
    for k in range(3):     # quills standing in the well, leaning out
        a = 2 * math.pi * k / 3 + rng.uniform(-0.3, 0.3)
        base = Vector((0.12, 0.0, top + 0.05))
        tip = base + Vector((math.cos(a) * 0.09, math.sin(a) * 0.09, 0.27))
        pts = [base.lerp(tip, t) for t in (0.0, 0.3, 0.6, 1.0)]
        tag(sweep(bm, pts, [(-0.0025, -0.0025), (0.0025, -0.0025), (0.0025, 0.0025), (-0.0025, 0.0025)]), QUILL)
        side = (tip - base).cross(Vector((0, 0, 1))).normalized() * 0.018
        v0 = base.lerp(tip, 0.35)
        f = [bm.verts.new(p) for p in (v0, tip, tip + side * 0.3, v0.lerp(tip, 0.5) + side)]
        tag([bm.faces.new(f)], QUILL)
    return obj_from(name, bm, [M["oak"], M["horn"], M["quill"], M["seal"], M["paper"]],
                    {OAK: 1.0, HORN: 0.1, QUILL: 0.1, SEAL: 0.1, PAPER: 0.3})


# ---------------------------------------------------------------- WP-10 easel
EASEL_TILT = 18.0      # the board leans back this much (the scene's %Easel)

def build_easel(name="easel"):
    """Upright in the room: front legs leaning back EASEL_TILT degrees, a rear
    leg, a cross bar, a deep ledge the board's foot rests on at LEDGE_Z."""
    M = mats()
    OAK = 0
    bm = bmesh.new()
    t = math.radians(EASEL_TILT)
    LH = 1.85          # front leg length
    S = 0.045
    for x in (-0.52, 0.52):
        rows = []
        for (lz, w) in ((0.0, S), (LH, S * 0.85)):
            c = Vector((x * (1 - 0.12 * lz / LH), math.sin(t) * lz, math.cos(t) * lz))
            rows.append([c + Vector((dx, dy, 0)) for dx, dy in ((-w / 2, -w / 2), (w / 2, -w / 2), (w / 2, w / 2), (-w / 2, w / 2))])
        tag(quad_strip(bm, rows, True, True, True), OAK)
    top = Vector((0.0, math.sin(t) * (LH - 0.1), math.cos(t) * (LH - 0.1)))
    foot = Vector((0.0, 0.78, 0.0))
    pts = [top + Vector((0, 0.03, 0)), foot]
    tag(sweep(bm, pts, [(-0.02, -0.02), (0.02, -0.02), (0.02, 0.02), (-0.02, 0.02)]), OAK)
    for lz, hw in ((1.70, 0.47), (0.35, 0.56)):          # cross bars
        c = Vector((0, math.sin(t) * lz, math.cos(t) * lz))
        bx(bm, -hw, c.y - 0.012, c.z - 0.03, hw, c.y + 0.012, c.z + 0.03, OAK)
    lz = LEDGE_LEG_Z
    c = Vector((0, math.sin(t) * lz, math.cos(t) * lz))
    bx(bm, -0.66, c.y - 0.10, c.z - 0.025, 0.66, c.y + 0.01, c.z, OAK)                  # the ledge
    bx(bm, -0.66, c.y - 0.10, c.z, 0.66, c.y - 0.085, c.z + 0.03, OAK)                  # its lip
    return obj_from(name, bm, [M["oak"]], {OAK: 1.0}, hard=35.0)

LEDGE_LEG_Z = 0.75   # the board's foot (%Easel local y 0.85, its origin 0.1 under the floor)


# ---------------------------------------------------------------- WP-06 floor candle
def build_floor_candle(name="floor_candle"):
    M = mats()
    IRON, WAX = 0, 1
    bm = bmesh.new()
    sec = [(-0.008, -0.008), (0.008, -0.008), (0.008, 0.008), (-0.008, 0.008)]
    for k in range(3):     # three curled feet
        a = 2 * math.pi * k / 3 + math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [Vector((0, 0, 0.16)) + d * 0.02, Vector((0, 0, 0.09)) + d * 0.12, Vector((0, 0, 0.03)) + d * 0.2,
               Vector((0, 0, 0.0)) + d * 0.25, Vector((0, 0, 0.02)) + d * 0.28]
        tag(sweep(bm, pts, sec), IRON)
    # the twisted shaft: a square section turned along its length
    n = 36
    rows = []
    for i in range(n + 1):
        z = 0.15 + (1.38 - 0.15) * i / n
        a = 6 * math.pi * i / n
        rows.append([Vector((math.cos(a + math.pi / 2 * k) * 0.013, math.sin(a + math.pi / 2 * k) * 0.013, z)) for k in range(4)])
    tag(quad_strip(bm, rows, True, True, True), IRON)
    tag(lathe(bm, [(0.012, 1.37), (0.09, 1.385), (0.095, 1.40), (0.085, 1.405), (0.02, 1.40), (0.02, 1.42)], 16,
              Vector((0, 0, 0)), cap_start=True), IRON)
    tag(lathe(bm, [(0.03, 1.40), (0.031, 1.56), (0.026, 1.575), (0.004, 1.58)], 12, Vector((0, 0, 0))), WAX)
    return obj_from(name, bm, [M["iron"], M["wax"]], {IRON: 0.2, WAX: 0.2})


# ---------------------------------------------------------------- the wall map's rods
MAP_W = 2.1     # the wall map between the north wall's sconces (x +-1.25)
MAP_H = 0.83    # rod to rod: the pack's map (~2.76:1) on parchment; %WallMap is this size

def build_map_rods(name="map_rods"):
    """Two turned oak rods (top and bottom of a hanging map MAP_W wide), a cord
    up to an iron nail. Origin: the nail, the map hangs below it in the xz plane."""
    M = mats()
    OAK, IRON, CORD = 0, 1, 2
    bm = bmesh.new()
    for z in (-0.2, -0.2 - MAP_H):
        cyl(bm, (-MAP_W / 2 - 0.04, 0.0, z), (1, 0, 0), 0.018, MAP_W + 0.08, 8, OAK)
        for sgn in (-1, 1):      # turned knobs at the rod's ends
            x0 = sgn * (MAP_W / 2 + 0.04)
            cyl(bm, (x0, 0.0, z), (sgn, 0, 0), 0.028, 0.035, 8, OAK)
            cyl(bm, (x0 + sgn * 0.035, 0.0, z), (sgn, 0, 0), 0.018, 0.02, 8, OAK)
    for s in (-1, 1):
        pts = [Vector((s * (MAP_W / 2 - 0.05), 0.005, -0.2)), Vector((0, 0.005, -0.01))]
        tag(sweep(bm, pts, [(-0.003, -0.003), (0.003, -0.003), (0.003, 0.003), (-0.003, 0.003)]), CORD)
    cyl(bm, (0, 0.03, 0.0), (0, -1, 0), 0.008, 0.04, 6, IRON)
    return obj_from(name, bm, [M["oak"], M["iron"], M["cord"]], {OAK: 0.5, IRON: 0.1, CORD: 0.1})


# ---------------------------------------------------------------- textile planes
def textile(name, image_path, w, h, lying, crop=None):
    """A thin textile: one quad (lying on the floor when `lying`, else hanging in
    the xz plane), its picture cropped by `crop` (u0, v0, u1, v1) of the image."""
    im = img(image_path)
    m = bpy.data.materials.get("WR_" + name) or bpy.data.materials.new("WR_" + name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = im
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    bm = bmesh.new()
    nx, ny = 6, 6           # a little sag and wear room
    vs = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            if lying:
                p = ((u - 0.5) * w, (v - 0.5) * h, 0.004 + 0.003 * math.sin(u * 7.0 + v * 3.0) * (0.3 + 0.7 * abs(u - 0.5)))
            else:
                p = ((u - 0.5) * w, 0.004 * math.sin(u * math.pi * 5), -(1 - v) * h)
            row.append(bm.verts.new(p))
        vs.append(row)
    uvl = bm.loops.layers.uv.new("UVMap")
    c0u, c0v, c1u, c1v = crop or (0, 0, 1, 1)
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
            for l, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                l[uvl].uv = (c0u + (c1u - c0u) * ii / nx, c0v + (c1v - c0v) * jj / ny)
            if lying and f.normal.z < 0:
                f.normal_flip()
            if not lying and f.normal.y > 0:
                f.normal_flip()
    ob = new_obj(name, bm, COL, [m])
    finish_mesh(ob, hard_deg=80)
    return ob


def build_all():
    out = {}
    for f in (build_rack, build_lectern, build_map_chest, build_side_table, build_easel, build_floor_candle, build_map_rods, lambda: build_textiles()[0], lambda: build_textiles()[1]):
        ob = f()
        out[ob.name] = (tris_of(ob), tuple(round(d, 3) for d in ob.dimensions))
    return out


def build_textiles():
    rug = textile("rug", TEX + "/rug.png", 2.4, 1.72, lying=True)
    tap = textile("tapestry", TEX + "/tapestry.png", 1.2, 1.6, lying=False)
    return rug, tap


def export(names, folder=None, max_px=1024):
    """Export the named objects ALONE as assets/3D/war_room/<folder>/<folder>.glb
    (+Y up, modifiers applied, images embedded at most max_px — the 1k rule)."""
    folder = folder or names[0]
    for im in bpy.data.images:
        if im.size[0] > max_px or im.size[1] > max_px:
            s = max_px / max(im.size[0], im.size[1])
            im.scale(int(im.size[0] * s), int(im.size[1] * s))
    bpy.ops.object.select_all(action='DESELECT')
    keep = {}
    for n in names:
        ob = bpy.data.objects[n]
        keep[n] = ob.location.copy()
        ob.location = (0, 0, 0) if len(names) == 1 else ob.location
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
    os.makedirs(EXP + "/" + folder, exist_ok=True)
    path = EXP + "/" + folder + "/" + folder + ".glb"
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_skins=False)
    for n, loc in keep.items():
        bpy.data.objects[n].location = loc
    return path
