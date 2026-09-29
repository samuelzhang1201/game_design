"""The man-at-arms BASE MESH from the blueprint (owner 2026-09-28: 用蓝图在
blender里开始建模…注意多边形的合理分布). Half body (+X) under a Mirror
modifier, all quads; the ring sizes are read off the blueprint's front and
side views (see the tables). Built in stages so each can be looked at:
  STAGE 1 torso (12 round, the armhole left open), 2 + legs, 3 + arms and caps.
    exec(open(".../base_mesh.py").read(), {"STAGE": 3})
The character faces -Y (Blender's front view shows his front).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

STAGE = globals().get("STAGE", 3)
E = 0.83                      # superellipse exponent on the torso rings: a little boxier than round

# torso rows: z, half width, front y, back y   (front / side blueprint)
TORSO = [(0.86, 0.190, -0.130, 0.120),
         (0.95, 0.195, -0.150, 0.135),
         (1.06, 0.146, -0.185, 0.098),
         (1.20, 0.166, -0.212, 0.118),
         (1.32, 0.176, -0.200, 0.140),
         (1.40, 0.172, -0.155, 0.142),
         (1.46, 0.145, -0.110, 0.125),
         (1.50, 0.095, -0.075, 0.095),
         (1.56, 0.065, -0.045, 0.070)]
TH = [0, 30, 60, 90, 120, 150, 180]           # half ring, front (-Y) round the +X side to the back
HOLE_ROWS, HOLE_TH = (4, 5, 6), (2, 3, 4)       # the armhole: a 2x2 patch of the side
CROTCH = (0.0, -0.005, 0.79)

# leg rings: z, centre x, centre y, radius x, radius y   (angles 0 = front, 90 = outer)
LEG = [(0.78, 0.100, -0.012, 0.090, 0.105),
       (0.66, 0.118, -0.018, 0.080, 0.100),
       (0.56, 0.122, -0.018, 0.075, 0.092),     # above the knee
       (0.48, 0.124, -0.020, 0.082, 0.100),     # the knee
       (0.40, 0.120, -0.010, 0.070, 0.082),     # below the knee
       (0.30, 0.118, -0.004, 0.060, 0.064),
       (0.20, 0.125, 0.000, 0.052, 0.060),
       (0.12, 0.132, 0.000, 0.050, 0.060)]      # the ankle
LEG_PHI = [-45, 0, 45, 90, 135, 180, 225, 270]

# arm: shoulder, elbow, wrist centres (front + side blueprint)
S, EL, W = Vector((0.214, 0.006, 1.38)), Vector((0.315, -0.028, 1.11)), Vector((0.320, -0.130, 0.87))
# rings along the arm: (point, radius, axis)
def arm_rings():
    d1 = (EL - S).normalized()
    d2 = (W - EL).normalized()
    t0 = (Vector((1, 0, 0)) * 0.55 + d1 * 0.45).normalized()
    return [(Vector((0.212, 0.0, 1.382)), 0.074, t0),
            (S.lerp(EL, 0.30), 0.063, d1),
            (S.lerp(EL, 0.80), 0.055, d1),
            (EL, 0.058, (d1 + d2).normalized()),     # the elbow
            (EL.lerp(W, 0.20), 0.052, d2),
            (EL.lerp(W, 0.55), 0.047, d2),
            (W, 0.038, d2)]                          # the wrist


def sp(c, e):
    return math.copysign(abs(c) ** e, c)


def torso_pt(row, th):
    z, hw, yf, yb = row
    t = math.radians(th)
    s, c = math.sin(t), math.cos(t)
    yc = (yf + yb) / 2
    x = hw * sp(s, E) if th not in (0, 180) else 0.0
    y = yc + (yf - yc) * sp(c, E) if c >= 0 else yc + (yb - yc) * sp(-c, E)
    return Vector((x, y, z))


def leg_pt(row, phi):
    z, cx, cy, rx, ry = row
    p = math.radians(phi)
    return Vector((cx + rx * math.sin(p), cy - ry * math.cos(p), z))


def arm_ring(p, r, t):
    # a frame round the axis: O the outward side (+X kept perpendicular), F the front (-Y)
    o = Vector((1, 0, 0)) - t * t.x
    o.normalize()
    f = t.cross(o)
    if f.y > 0:
        f = -f
    # directions matching the armhole's order: front-bottom, bottom, back-bottom, back,
    # back-top, top, front-top, front  ->  front-inner, inner, back-inner, back, back-outer,
    # outer, front-outer, front
    dirs = [(1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0)]
    out = []
    for a, b in dirs:
        d = (f * a + o * b).normalized()
        out.append(p + d * r)
    return out


def build():
    old = bpy.data.objects.get("base_body")
    if old:
        me_old = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        bpy.data.meshes.remove(me_old)
    bm = bmesh.new()
    V = {}
    for i, row in enumerate(TORSO):
        for j, th in enumerate(TH):
            if i == HOLE_ROWS[1] and j == HOLE_TH[1]:
                continue                                  # the hole's centre vertex is not needed
            V[(i, j)] = bm.verts.new(torso_pt(row, th))
    for i in range(len(TORSO) - 1):
        for j in range(len(TH) - 1):
            if i in HOLE_ROWS[:2] and j in HOLE_TH[:2]:
                continue                                  # the 2x2 armhole
            bm.faces.new((V[(i, j)], V[(i, j + 1)], V[(i + 1, j + 1)], V[(i + 1, j)]))
    top = len(TORSO) - 1
    if STAGE >= 3:
        # the neck's cap: a centre on the mirror plane, three quads a half
        c = bm.verts.new(Vector((0, (TORSO[top][2] + TORSO[top][3]) / 2, TORSO[top][0] + 0.008)))
        for j in (0, 2, 4):
            bm.faces.new((V[(top, j)], V[(top, j + 1)], V[(top, j + 2)], c))
    if STAGE >= 2:
        # the leg: its top loop is the pelvis's bottom half ring plus the crotch
        cr = bm.verts.new(Vector(CROTCH))
        loop = [V[(0, j)] for j in range(len(TH))] + [cr]           # 8 verts
        prev = loop
        for row in LEG:
            ring = [bm.verts.new(leg_pt(row, p)) for p in LEG_PHI]
            # the top loop runs front-centre .. back-centre .. crotch; LEG_PHI -45 .. 270 matches it
            for k in range(8):
                bm.faces.new((prev[k], prev[(k + 1) % 8], ring[(k + 1) % 8], ring[k]))
            prev = ring
        c = bm.verts.new(sum((v.co for v in prev), Vector()) / 8 + Vector((0, 0, -0.012)))
        for k in (0, 2, 4, 6):
            bm.faces.new((prev[k], prev[k + 1], prev[(k + 2) % 8], c))
    if STAGE >= 3:
        r0, r1, r2 = HOLE_ROWS
        j0, j1, j2 = HOLE_TH
        hole = [V[(r0, j0)], V[(r0, j1)], V[(r0, j2)], V[(r1, j2)], V[(r2, j2)], V[(r2, j1)], V[(r2, j0)], V[(r1, j0)]]
        prev = hole
        for p, r, t in arm_rings():
            ring = [bm.verts.new(q) for q in arm_ring(p, r, t)]
            for k in range(8):
                bm.faces.new((prev[k], prev[(k + 1) % 8], ring[(k + 1) % 8], ring[k]))
            prev = ring
        c = bm.verts.new(sum((v.co for v in prev), Vector()) / 8 + arm_rings()[-1][2] * 0.012)
        for k in (0, 2, 4, 6):
            bm.faces.new((prev[k], prev[k + 1], prev[(k + 2) % 8], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("base_body")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("base_body", me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new("Mirror", "MIRROR")
    m.use_clip = True
    m.use_mirror_merge = True
    m.merge_threshold = 0.001
    s = ob.modifiers.new("Subdivision", "SUBSURF")
    s.levels = 0
    s.render_levels = 1
    ob.show_wire = True
    ob.show_all_edges = True
    mat = bpy.data.materials.get("base_clay") or bpy.data.materials.new("base_clay")
    mat.diffuse_color = (0.72, 0.62, 0.52, 1.0)
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = False
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("base_body stage %d: %d verts, %d faces (all quads: %s), %d tris half -> %d mirrored" % (
        STAGE, len(me.vertices), len(me.polygons), all(len(p.vertices) == 4 for p in me.polygons), tris, tris * 2))
    return ob


if globals().get("BUILD", True):
    build()
