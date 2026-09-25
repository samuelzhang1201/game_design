"""The fourteen settlement buildings, one function each, run inside Blender
after kit.py (see its docstring). Each was modelled looking at a reference
(first a Hunyuan3D mesh, since deleted over its licence; now the Flux
pictures in assets/flux/out/house_ref/) and at data/map3d_houses.csv's note,
never from its geometry. Dimensions are game metres before export() fits
the footprint."""
import math

from mathutils import Matrix

TURN = Matrix.Rotation(-math.pi / 2, 4, "Z")   # ridge along X, the long side to the front (-Y)


def cottage_a():
    """A one-room tiled stone cottage, its door in the long side, a chimney
    stack on one gable."""
    h = House("cottage_a")
    h.M = TURN.copy()
    hw, y0, y1, eave, ridge = 5.6, -7.6, 7.6, 6.4, 13.2
    h.hall(hw, y0, y1, eave, ridge, "wall_rubble")
    h.roof(hw, y0, y1, eave, ridge, "roof_orange", over=0.55, end0=0.45, end1=0.2)
    h.chimney(0, y1 + 0.7, 2.0, 1.4, 0, ridge + 1.6)
    f = side(hw, 1)
    h.opening(f, -1.8, 2.0, 0, 4.2, "timber", frame="timber", frame_w=0.25)
    for u in (-5.2, 2.6):
        h.opening(f, u, 1.5, 2.2, 3.9, frame="timber", frame_w=0.22)
    b = side(hw, -1)
    h.opening(b, 1.5, 1.4, 2.2, 3.8, frame="timber", frame_w=0.22)
    g = front(hw, y0)
    h.opening(g, 0, 1.2, 7.4, 9.0, frame="timber", frame_w=0.2)
    return h.finish()


def cottage_b():
    """A limewashed half-timbered cottage, its gable to the lane, with a
    tiled lean-to down one side."""
    h = House("cottage_b")
    hw, y0, y1, eave, ridge = 6.0, -8.0, 8.0, 8.0, 16.4
    h.hall(hw, y0, y1, eave, ridge, "wall_plaster")
    h.roof(hw, y0, y1, eave, ridge, "roof_rose", over=0.6, end0=0.6, end1=0.4)
    # lean-to on the -X side
    h.box(-hw - 3.6, -hw + 0.1, -3.5, 5.5, 0, 4.4, "wall_plaster")
    h.shed_roof(-hw + 0.1, -hw - 3.6, -3.5, 5.5, 4.2, 6.6, "roof_rose")
    h.chimney(hw - 1.8, 4.0, 1.6, 1.6, 6, ridge - 1.2)
    g = front(hw, y0)
    h.frame_wall(g, -hw, hw, 0, eave, posts=3, rails=(4.2,))
    h.frame_gable(g, hw, eave, ridge)
    h.opening(g, -1.45, 2.0, 0, 3.9, "timber")
    h.opening(g, 4.35, 1.9, 1.6, 3.6)
    h.opening(g, -4.35, 1.9, 5.0, 7.2)
    h.opening(g, 1.45, 1.9, 5.0, 7.2)
    h.opening(g, 0, 1.4, 9.2, 11.0)
    for sgn in (1, -1):
        s = side(hw, sgn)
        h.frame_wall(s, y0, y1, 0, eave, posts=4, rails=(4.2,))
        if sgn == 1:
            h.opening(s, -4.9, 1.9, 5.0, 7.2)
            h.opening(s, 1.6, 1.9, 5.0, 7.2)
            h.opening(s, 4.9, 1.9, 1.6, 3.6)
    bk = back(hw, y1)
    h.frame_wall(bk, -hw, hw, 0, eave, posts=3, rails=(4.2,))
    h.frame_gable(bk, hw, eave, ridge)
    return h.finish()


def cottage_c():
    """The smallest cottage: rubble walls, a steep red roof and its chimney
    rising out of the gable that faces the lane."""
    h = House("cottage_c")
    hw, y0, y1, eave, ridge = 5.2, -7.0, 7.0, 6.0, 13.6
    h.hall(hw, y0, y1, eave, ridge, "wall_rubble")
    h.roof(hw, y0, y1, eave, ridge, "roof_red", over=0.5, end0=0.2, end1=0.5)
    h.chimney(-2.4, y0 + 0.3, 1.8, 1.5, 0, ridge + 1.8)
    g = front(hw, y0)
    h.opening(g, 1.6, 2.0, 0, 4.0, "timber", frame="timber", frame_w=0.25)
    h.opening(g, -2.4, 1.3, 7.0, 8.6, frame="timber", frame_w=0.2)
    h.opening(g, 1.6, 1.3, 7.2, 8.8, frame="timber", frame_w=0.2)
    s = side(hw, 1)
    h.opening(s, 0.5, 1.5, 2.2, 3.8, frame="timber", frame_w=0.22)
    s = side(hw, -1)
    h.opening(s, -1.5, 1.5, 2.2, 3.8, frame="timber", frame_w=0.22)
    return h.finish()



# -- helpers shared by the grander buildings --------------------------------------
def buttress(h, wall, u, key, w=1.0, steps=((1.4, 5.0), (0.9, 8.6))):
    """A stepped buttress against `wall` at u: each step (depth, top)."""
    z0 = 0.0
    for depth, top in steps:
        h.panel(wall, [(u - w / 2, z0), (u + w / 2, z0), (u + w / 2, top), (u - w / 2, top)], key, -0.3, depth)
        z0 = top - 0.4


def battlements(h, x0, x1, y0, y1, z, key, t=0.8, parapet=0.9, merlon=1.3, step=2.4):
    """A parapet ring on top of the rectangle x0..x1, y0..y1 at z, with
    merlons along it."""
    h.box(x0, x1, y0, y0 + t, z, z + parapet, key)
    h.box(x0, x1, y1 - t, y1, z, z + parapet, key)
    h.box(x0, x0 + t, y0, y1, z, z + parapet, key)
    h.box(x1 - t, x1, y0, y1, z, z + parapet, key)
    zt = z + parapet + merlon
    for lo, hi, fixed, along_x in ((x0, x1, y0, True), (x0, x1, y1 - t, True), (y0, y1, x0, False), (y0, y1, x1 - t, False)):
        n = max(2, int((hi - lo) / step))
        for i in range(n + 1):
            c = lo + (hi - lo) * i / n
            a, b = max(lo, c - step / 4), min(hi, c + step / 4)
            if along_x:
                h.box(a, b, fixed, fixed + t, z + parapet, zt, key)
            else:
                h.box(fixed, fixed + t, a, b, z + parapet, zt, key)


def octagon(r, cx=0.0, cy=0.0, rot=0.0):
    return [(cx + r * math.cos(rot + math.pi * i / 4), cy + r * math.sin(rot + math.pi * i / 4)) for i in range(8)]


def cross(h, x, y, z, s=1.0, key="wall_ashlar"):
    h.box(x - 0.14 * s, x + 0.14 * s, y - 0.14 * s, y + 0.14 * s, z, z + 1.4 * s, key)
    h.box(x - 0.45 * s, x + 0.45 * s, y - 0.14 * s, y + 0.14 * s, z + 0.8 * s, z + 1.08 * s, key)


def cross_y(h, x, y, z, s=1.0, key="wall_ashlar"):
    """A cross whose arms run along Y (on a gable facing X)."""
    h.box(x - 0.14 * s, x + 0.14 * s, y - 0.14 * s, y + 0.14 * s, z, z + 1.4 * s, key)
    h.box(x - 0.14 * s, x + 0.14 * s, y - 0.45 * s, y + 0.45 * s, z + 0.8 * s, z + 1.08 * s, key)


def gable_coping(h, hw, y, eave, ridge, key, over=0.25, t=0.45, w=0.9):
    """A stone coping laid up both rakes of the gable at y."""
    slope = (ridge - eave) / hw
    lift = 0.35 / math.cos(math.atan(slope)) + 0.05
    for sgn in (1, -1):
        a = (sgn * (hw + over), eave - over * slope + lift)
        b = (0.0, ridge + lift)
        h.along_y([a, b, (b[0], b[1] + t), (a[0], a[1] + t)], y - w / 2, y + w / 2, key)


# -- the town and village houses ----------------------------------------------------
def townhouse_a():
    """A two-storey tiled house between crow-stepped gables, its long side
    and round-arched door to the street; only from a town upward."""
    h = House("townhouse_a")
    h.M = TURN.copy()
    hw, y0, y1, eave, ridge = 6.8, -8.6, 8.6, 12.0, 20.4
    h.hall(hw, y0, y1, eave, ridge, "wall_plaster")
    h.roof(hw, y0 + 0.4, y1 - 0.4, eave, ridge, "roof_red", over=0.6, end0=0.0, end1=0.0)
    n = 6
    for y in (y0 + 0.35, y1 - 0.35):
        for i in range(n):
            x = hw - i * hw / n
            zb = eave + (ridge - eave) * i / n
            h.box(-x, x, y - 0.4, y + 0.4, zb, zb + (ridge - eave) / n + 1.1, "wall_plaster")
            h.box(-x - 0.12, x + 0.12, y - 0.5, y + 0.5, zb + (ridge - eave) / n + 1.1, zb + (ridge - eave) / n + 1.3,
                  "wall_ashlar")
    h.chimney(-3.5, 3.0, 1.6, 1.6, eave, ridge + 1.5, "wall_ashlar", "wall_ashlar")
    f = side(hw, 1)
    h.opening(f, 0, 2.6, 0, 5.0, "timber", arch="round", frame="wall_ashlar", frame_w=0.4)
    for u in (-5.6, -2.8, 2.8, 5.6):
        h.opening(f, u, 1.7, 1.8, 4.2, frame="wall_ashlar", frame_w=0.28)
    for u in (-5.6, -2.8, 0, 2.8, 5.6):
        h.opening(f, u, 1.7, 6.8, 9.6, frame="wall_ashlar", frame_w=0.28)
    b = side(hw, -1)
    for u in (-4.2, 0, 4.2):
        h.opening(b, u, 1.7, 1.8, 4.2, frame="wall_ashlar", frame_w=0.28)
        h.opening(b, u, 1.7, 6.8, 9.6, frame="wall_ashlar", frame_w=0.28)
    for w in (front(hw, y0), back(hw, y1)):
        h.opening(w, -2.2, 1.5, 6.8, 9.4, frame="wall_ashlar", frame_w=0.26)
        h.opening(w, 2.2, 1.5, 6.8, 9.4, frame="wall_ashlar", frame_w=0.26)
        h.opening(w, 0, 1.2, 13.2, 15.2, frame="wall_ashlar", frame_w=0.24)
    return h.finish()


def townhouse_b():
    """A tiled town house: a rubble ground floor, a jettied half-timbered
    upper floor and an outside stair up to its door."""
    h = House("townhouse_b")
    hw0, hw, y0, y1 = 5.3, 6.1, -8.0, 8.0
    z1, eave, ridge = 5.2, 10.8, 18.6
    h.box(-hw0, hw0, y0, y1, 0, z1, "wall_rubble")
    h.hall(hw, y0 - 0.8, y1 + 0.3, eave, ridge, "wall_plaster", z0=z1)
    h.roof(hw, y0 - 0.8, y1 + 0.3, eave, ridge, "roof_orange_brown", over=0.6, end0=0.6, end1=0.4)
    h.box(-hw - 0.1, hw + 0.1, y0 - 0.9, y1 + 0.4, z1 - 0.2, z1 + 0.35, "timber")  # jetty bressumer
    for x in (-hw0 + 0.8, 0, hw0 - 0.8):
        h.box(x - 0.2, x + 0.2, y0 - 0.9, y0 + 0.5, z1 - 0.9, z1 - 0.2, "timber")   # joist ends
    h.chimney(-2.6, 5.0, 1.6, 1.6, eave, ridge + 1.2, "wall_rubble", "wall_rubble")
    g = front(hw, y0 - 0.8)
    h.frame_wall(g, -hw, hw, z1, eave, posts=3, rails=(z1 + 2.6,))
    h.frame_gable(g, hw, eave, ridge)
    h.opening(g, -3.0, 2.0, z1 + 0.9, z1 + 3.4)
    h.opening(g, 3.0, 2.0, z1 + 0.9, z1 + 3.4)
    h.opening(g, 0, 1.4, eave + 1.2, eave + 3.2)
    gl = front(hw0, y0)
    h.opening(gl, -1.8, 2.4, 0, 4.0, "timber", frame="wall_rubble", frame_w=0.3)
    h.opening(gl, 2.6, 1.6, 1.6, 3.4)
    for sgn in (1, -1):
        s = side(hw, sgn)
        h.frame_wall(s, y0 - 0.8, y1 + 0.3, z1, eave, posts=4, rails=(z1 + 2.6,))
    bk = back(hw, y1 + 0.3)
    h.frame_wall(bk, -hw, hw, z1, eave, posts=3, rails=(z1 + 2.6,))
    h.frame_gable(bk, hw, eave, ridge)
    h.opening(bk, 2.8, 1.9, z1 + 0.9, z1 + 3.2)
    s = side(hw, 1)
    h.opening(s, 5.6, 1.8, z1, z1 + 3.8, "timber")                     # the upper door
    h.opening(s, -3.4, 1.9, z1 + 0.9, z1 + 3.2)
    # the outside stair up the +X wall to the upper door
    steps = 8
    for i in range(steps):
        ya = -1.0 + i * 0.95
        h.box(hw0, hw0 + 1.8, ya, ya + 0.95, 0, (i + 1) * z1 / steps, "timber")
    h.box(hw0, hw + 1.9, 6.6, 8.2, 0, z1 - 0.1, "timber")
    return h.finish()


def townhouse_c():
    """A tall merchant's house in dressed stone under red tile, three storeys
    of windows to the street and a stack on each gable."""
    h = House("townhouse_c")
    h.M = TURN.copy()
    hw, y0, y1, eave, ridge = 5.4, -7.4, 7.4, 13.0, 19.4
    h.hall(hw, y0, y1, eave, ridge, "wall_ashlar")
    h.roof(hw, y0, y1, eave, ridge, "roof_red", over=0.5, end0=0.25, end1=0.25)
    for y in (y0 + 0.9, y1 - 0.9):
        h.chimney(0, y, 1.8, 1.4, ridge - 3, ridge + 1.8, "wall_ashlar", "wall_ashlar")
    for z in (4.6, 8.8):
        h.box(-hw - 0.15, hw + 0.15, y0 - 0.15, y1 + 0.15, z, z + 0.35, "wall_ashlar")     # string courses
    f = side(hw, 1)
    h.opening(f, 0, 2.2, 0, 4.0, "timber", frame="wall_ashlar", frame_w=0.35)
    for u in (-5.0, -2.4, 2.4, 5.0):
        h.opening(f, u, 1.4, 1.6, 3.8)
    for z0 in (5.6, 9.8):
        for u in (-5.0, -2.4, 0, 2.4, 5.0):
            h.opening(f, u, 1.4, z0, z0 + 2.4)
    b = side(hw, -1)
    for z0 in (1.6, 5.6, 9.8):
        for u in (-3.6, 0, 3.6):
            h.opening(b, u, 1.4, z0, z0 + 2.4)
    for w in (front(hw, y0), back(hw, y1)):
        for z0 in (5.6, 9.8):
            h.opening(w, -2.2, 1.3, z0, z0 + 2.3)
            h.opening(w, 2.2, 1.3, z0, z0 + 2.3)
    return h.finish()


def longhouse():
    """A long, low hall with its byre under one roof: daub between timbers,
    the family's door and the cattle's wider one on the same long side."""
    h = House("longhouse")
    h.M = TURN.copy()
    hw, y0, y1, eave, ridge = 3.6, -10.0, 10.0, 3.6, 8.2
    h.hall(hw, y0, y1, eave, ridge, "wall_daub")
    h.roof(hw, y0, y1, eave, ridge, "roof_orange", over=0.6, end0=0.5, end1=0.5)
    h.chimney(0, -3.0, 1.2, 1.2, 5, ridge + 1.0, "wall_rubble", "wall_rubble")
    for sgn in (1, -1):
        s = side(hw, sgn)
        h.frame_wall(s, y0, y1, 0, eave, posts=6, rails=(), braces=True)
    for w in (front(hw, y0), back(hw, y1)):
        h.frame_wall(w, -hw, hw, 0, eave, posts=1, rails=(), braces=False)
        h.frame_gable(w, hw, eave, ridge, studs=1)
    f = side(hw, 1)
    h.opening(f, -4.4, 1.6, 0, 3.0, "timber")
    h.opening(f, 5.6, 2.6, 0, 3.2, "timber")
    h.opening(f, -7.6, 1.0, 1.6, 2.6)
    h.opening(f, -1.6, 1.0, 1.6, 2.6)
    return h.finish()


def workshop():
    """A workshop whose roof runs on over an open front bay on two posts,
    a forge stack standing up its side."""
    h = House("workshop")
    hw, y0, yb, y1, eave, ridge = 6.4, -9.2, -3.6, 9.2, 5.8, 12.6
    h.hall(hw, yb, y1, eave, ridge, "wall_rubble")
    h.footing([(-hw, y0 + 0.1), (hw, y0 + 0.1), (hw, yb), (-hw, yb)])   # the open bay's floor
    h.roof(hw, y0, y1, eave, ridge, "roof_orange_brown", over=0.6, end0=0.4, end1=0.4)
    for x in (-hw + 0.3, hw - 0.3):
        h.box(x - 0.3, x + 0.3, y0 + 0.1, y0 + 0.7, 0, eave, "timber")
    h.box(-hw, hw, y0 + 0.1, y0 + 0.7, eave - 0.6, eave, "timber")
    h.along_y([(-hw, eave), (hw, eave), (0, ridge)], y0 + 0.1, y0 + 0.4, "timber")   # the gable's board
    h.box(-hw + 0.8, -1.0, yb - 1.6, yb - 0.1, 0, 1.2, "timber")                      # a bench in the bay
    h.box(hw + 0.1, hw + 2.2, 2.0, 4.6, 0, ridge + 2.4, "wall_rubble")                  # forge stack
    h.box(hw - 0.1, hw + 2.5, 1.7, 4.9, ridge + 2.4, ridge + 2.8, "wall_rubble")
    h.box(hw + 0.5, hw + 1.8, 2.6, 4.0, ridge + 2.8, ridge + 3.3, "void")
    g = front(hw, yb)
    h.opening(g, 0, 4.2, 0, 4.2, "void")
    for sgn in (1, -1):
        s = side(hw, sgn)
        h.opening(s, 5.6 if sgn > 0 else -5.6, 1.5, 2.0, 3.6, frame="timber", frame_w=0.22)
    return h.finish()


def barn():
    """A tall half-timbered barn under a weathered brown-grey tiled roof,
    its great doors in the gable."""
    h = House("barn")
    hw, y0, y1, eave, ridge = 7.4, -10.0, 10.0, 6.6, 18.4
    h.hall(hw, y0, y1, eave, ridge, "wall_daub")
    h.roof(hw, y0, y1, eave, ridge, "roof_brown_grey", over=0.7, end0=0.6, end1=0.6)
    for w in (front(hw, y0), back(hw, y1)):
        h.frame_wall(w, -hw, hw, 0, eave, posts=3, rails=(3.4,), braces=True, w=0.45)
        h.frame_gable(w, hw, eave, ridge, w=0.45)
    g = front(hw, y0)
    h.opening(g, 0, 5.4, 0, 5.8, "timber")
    h.beam(g, 0, 0, 0, 5.8, 0.25, 0.2, "void")
    h.opening(g, 0, 1.3, 11.0, 12.6)
    for sgn in (1, -1):
        s = side(hw, sgn)
        h.frame_wall(s, y0, y1, 0, eave, posts=5, rails=(3.4,), braces=True, w=0.45)
    h.opening(side(hw, 1), 0, 3.0, 0, 3.8, "timber")
    return h.finish()


def byre():
    """A low stone byre under warm tile, a wide boarded door in its gable."""
    h = House("byre")
    hw, y0, y1, eave, ridge = 6.2, -8.5, 8.5, 4.2, 10.4
    h.hall(hw, y0, y1, eave, ridge, "wall_rubble")
    h.roof(hw, y0, y1, eave, ridge, "roof_orange_brown", over=0.5, end0=0.4, end1=0.4)
    g = front(hw, y0)
    h.opening(g, 0.6, 3.6, 0, 3.8, "timber", frame="timber", frame_w=0.3)
    h.opening(g, 0, 1.1, 6.0, 7.2)
    for sgn in (1, -1):
        s = side(hw, sgn)
        for u in (-4.5, 0, 4.5):
            h.opening(s, u, 0.5, 2.0, 3.2)
    return h.finish()


# -- the landmarks ---------------------------------------------------------------------
def chapel():
    """A village's chapel: dressed stone under slate, pointed windows, and
    an open stone belfry with a pyramid cap over the far gable."""
    h = House("chapel")
    hw, y0, y1, eave, ridge = 6.0, -10.0, 10.0, 7.4, 15.4
    h.hall(hw, y0, y1, eave, ridge, "wall_ashlar")
    h.roof(hw, y0, y1, eave, ridge, "roof_slate", over=0.5, end0=0.1, end1=0.1)
    for y in (y0, y1):
        gable_coping(h, hw, y, eave, ridge, "wall_ashlar")
    for sgn in (1, -1):
        for yb in (y0 + 0.3, y1 - 0.3):
            h.box(sgn * hw - 0.6, sgn * hw + 0.6, yb - 0.5, yb + 0.5, 0, 0.1, "wall_ashlar")
        s = side(hw, sgn)
        for u in (-5.0, 0.0, 5.0):
            h.opening(s, u, 1.3, 2.6, 6.0, arch="pointed", frame="wall_ashlar", frame_w=0.25)
        for u in (-7.5, -2.5, 2.5, 7.5):
            buttress(h, s, u, "wall_ashlar", w=0.8, steps=((1.0, 3.8), (0.6, 6.4)))
    g = front(hw, y0)
    h.opening(g, 0, 2.2, 0, 4.6, "timber", arch="pointed", frame="wall_ashlar", frame_w=0.35)
    h.opening(g, 0, 1.6, 7.6, 11.2, arch="pointed", frame="wall_ashlar", frame_w=0.25)
    cross(h, 0, y0, ridge + 0.4, 1.0)
    # belfry over the back gable
    by, zb, zt = y1 - 0.9, ridge - 2.0, ridge + 4.2
    h.box(-1.9, 1.9, by - 1.7, by + 1.7, zb, zb + 2.2, "wall_ashlar")
    for px in (-1.9, 1.3):
        for py in (by - 1.7, by + 1.1):
            h.box(px, px + 0.6, py, py + 0.6, zb + 2.2, zt, "wall_ashlar")
    h.box(-1.9, 1.9, by - 0.25, by + 0.25, zb + 2.2, zb + 3.6, "void")               # the bell
    h.box(-2.2, 2.2, by - 2.0, by + 2.0, zt, zt + 0.5, "wall_ashlar")
    h.pyramid(0, by, 2.5, 2.5, zt + 0.5, 4.4, "roof_slate")
    cross(h, 0, by, zt + 4.8, 0.9)
    return h.finish()


def church():
    """A town's parish church: a long nave, a lower chancel ending in a
    polygonal apse, stepped buttresses, a south porch and a great hewn
    wooden cross standing on the west gable (first modelled 2026-09-24
    against the Hunyuan church; the owner then ruled the bell-cote and its
    two small crosses out — too small to read — for one big wooden cross)."""
    h = House("church")
    hw, y0, y1, eave, ridge = 7.5, -8.0, 18.0, 10.6, 18.4
    chw, cy0, ceave, cridge = 5.0, -14.0, 8.4, 14.2
    h.hall(hw, y0, y1, eave, ridge, "wall_rubble")
    h.roof(hw, y0, y1, eave, ridge, "roof_slate", over=0.55, end0=0.2, end1=0.2)
    for y in (y0, y1):
        gable_coping(h, hw, y, eave, ridge, "wall_ashlar")
    h.box(-hw - 0.25, hw + 0.25, y0, y1 + 0.25, 0, 0.9, "wall_rubble")                 # plinth
    h.hall(chw, cy0, y0 + 0.2, ceave, cridge, "wall_rubble")
    h.roof(chw, cy0, y0, ceave, cridge, "roof_slate", over=0.55, end0=0.0, end1=0.0)
    ring = octagon(chw, 0, cy0)
    h.prism(ring, 0, ceave, "wall_rubble")
    slope = (cridge - ceave) / chw
    t = 0.35 / math.cos(math.atan(slope))
    h.pyramid(0, cy0, chw + 0.55, chw + 0.55, ceave - 0.55 * slope + t, cridge - ceave + 0.55 * slope, "roof_slate",
              sides=8)
    for sgn in (1, -1):
        s = side(hw, sgn)
        for u in (-5.25, 0.25, 5.75, 11.25, 16.0):
            if sgn == 1 and u == 5.75:
                continue
            h.opening(s, u, 1.5, 3.8, 8.5, arch="pointed", frame="wall_ashlar", frame_w=0.25)
        for u in (-7.3, -2.5, 3.0, 8.5, 14.0, 17.3):
            buttress(h, s, u, "wall_rubble", w=1.0, steps=((1.9, 5.2), (1.3, 9.0)))
        cs = side(chw, sgn)
        h.opening(cs, -11.0, 1.2, 3.2, 6.8, arch="pointed", frame="wall_ashlar", frame_w=0.22)
        buttress(h, cs, -8.9, "wall_rubble", w=0.8, steps=((1.2, 4.2), (0.8, 7.0)))
    for i in (1, 2, 5, 6):
        a0, a1 = math.pi * i / 4, math.pi * (i + 1) / 4
        p0 = (chw * math.cos(a0), cy0 + chw * math.sin(a0))
        p1 = (chw * math.cos(a1), cy0 + chw * math.sin(a1))
        if p0[1] > cy0 + 0.1 or p1[1] > cy0 + 0.1:
            continue
        mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
        u = (p1[0] - p0[0], p1[1] - p0[1])
        n = (mid[0], mid[1] - cy0)
        wall = Wall((mid[0], mid[1], 0), (u[0], u[1], 0), (n[0], n[1], 0))
        h.opening(wall, 0, 1.1, 3.2, 6.6, arch="pointed", frame="wall_ashlar", frame_w=0.2)
    w = back(hw, y1)                       # the west front
    h.opening(w, 0, 3.0, 6.6, 13.2, arch="pointed", frame="wall_ashlar", frame_w=0.35)
    h.opening(w, 0, 2.2, 0, 4.8, "cross_wood", arch="pointed", frame="wall_ashlar", frame_w=0.35)
    for x in (-6.8, 6.8):
        buttress(h, w, x, "wall_rubble", w=1.0, steps=((1.9, 5.2), (1.3, 9.0)))
    # the great wooden cross on the west gable: a hewn post and beam big
    # enough to read as a cross from the map's own height
    post, arm, reach = 1.1, 0.95, 3.6
    base, top = ridge - 1.0, ridge + 11.5
    yc = y1 + 0.1
    h.box(-post / 2, post / 2, yc - post / 2, yc + post / 2, base, top, "cross_wood")
    za = top - 4.2
    h.box(-reach, reach, yc - arm / 2, yc + arm / 2, za - arm / 2, za + arm / 2, "cross_wood")
    # south porch (+X), ridge along X
    with h.with_matrix(Matrix.Translation((hw + 1.9, 6.2, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z")):
        h.hall(1.9, -1.9, 2.0, 4.3, 6.9, "wall_rubble")
        h.roof(1.9, -2.0, 2.0, 4.3, 6.9, "roof_slate", over=0.4, end0=0.0, end1=0.4)
        h.opening(back(1.9, 2.0), 0, 1.8, 0, 3.6, "void", arch="pointed", frame="wall_ashlar", frame_w=0.25)
    return h.finish()


def church_tower():
    """A city's church: a slate-roofed nave and chancel behind a tall west
    tower, its belfry lights under a parapet and an octagonal slate spire."""
    h = House("church_tower")
    h.M = TURN.copy()
    hw, y0, y1, eave, ridge = 7.0, -10.0, 16.0, 11.0, 19.6
    chw, cy0, ceave, cridge = 5.0, -17.0, 9.0, 15.0
    h.hall(hw, y0, y1, eave, ridge, "wall_ashlar")
    h.roof(hw, y0, y1, eave, ridge, "roof_slate", over=0.5, end0=0.2, end1=0.0)
    gable_coping(h, hw, y0, eave, ridge, "wall_ashlar")
    h.hall(chw, cy0, y0 + 0.2, ceave, cridge, "wall_ashlar")
    h.roof(chw, cy0, y0, ceave, cridge, "roof_slate", over=0.5, end0=0.3, end1=0.0)
    gable_coping(h, chw, cy0, ceave, cridge, "wall_ashlar")
    cross(h, 0, cy0, cridge + 0.5, 1.0)
    for sgn in (1, -1):
        s = side(hw, sgn)
        for u in (-7.5, -2.5, 2.5, 7.5, 12.5):
            h.opening(s, u, 1.6, 3.8, 9.0, arch="pointed", frame="wall_ashlar", frame_w=0.25)
        for u in (-9.8, -5.0, 0.0, 5.0, 10.0):
            buttress(h, s, u, "wall_ashlar", w=1.0, steps=((1.6, 5.4), (1.0, 9.4)))
        cs = side(chw, sgn)
        h.opening(cs, -13.5, 1.3, 3.4, 7.4, arch="pointed", frame="wall_ashlar", frame_w=0.22)
    e = front(chw, cy0)
    h.opening(e, 0, 2.4, 3.2, 10.0, arch="pointed", frame="wall_ashlar", frame_w=0.3)
    # the west tower
    tx, ty0, ty1, top = 5.2, 15.6, 26.0, 33.0
    h.box(-tx, tx, ty0, ty1, 0, top, "wall_ashlar")
    for z in (12.0, 22.0):
        h.box(-tx - 0.25, tx + 0.25, ty0 - 0.25, ty1 + 0.25, z, z + 0.45, "wall_ashlar")
    for cxs in (-1, 1):
        for cys in (0, 1):
            yb = ty0 if cys == 0 else ty1
            h.box(cxs * tx - 0.8, cxs * tx + 0.8, yb - 0.8, yb + 0.8, 0, top - 4.0, "wall_ashlar")   # corner buttresses
    faces = [Wall((0, ty1, 0), (-1, 0, 0), (0, 1, 0)), Wall((tx, (ty0 + ty1) / 2, 0), (0, 1, 0), (1, 0, 0)),
             Wall((-tx, (ty0 + ty1) / 2, 0), (0, -1, 0), (-1, 0, 0))]
    for f in faces:
        h.opening(f, -1.5, 1.4, 24.5, 30.0, arch="pointed", frame="wall_ashlar", frame_w=0.25)
        h.opening(f, 1.5, 1.4, 24.5, 30.0, arch="pointed", frame="wall_ashlar", frame_w=0.25)
        h.opening(f, 0, 1.0, 15.0, 17.6, arch="pointed")
    w = faces[0]
    h.opening(w, 0, 2.6, 0, 5.4, "timber", arch="pointed", frame="wall_ashlar", frame_w=0.4)
    h.opening(w, 0, 2.0, 7.4, 11.0, arch="pointed", frame="wall_ashlar", frame_w=0.3)
    battlements(h, -tx - 0.3, tx + 0.3, ty0 - 0.3, ty1 + 0.3, top, "wall_ashlar", step=2.6)
    cy = (ty0 + ty1) / 2
    h.prism(octagon(4.0, 0, cy, math.pi / 8), top, top + 0.8, "wall_ashlar")
    h.pyramid(0, cy, 4.0, 4.0, top + 0.8, 19.0, "roof_slate", sides=8, rot=math.pi / 8)
    cross(h, 0, cy, top + 19.6, 1.2)
    return h.finish()


def palace():
    """A capital's centre: a buttressed great hall under slate with tall
    pointed windows, a battlemented keep at one end with a stair turret,
    a cross wing with square battlemented towers at its corners (not cones: a
    palace of spires read as a second church_tower at map size), and a gatehouse on the hall's
    front."""
    h = House("palace")
    h.M = TURN.copy()
    # great hall along local Y
    hw, y0, y1, eave, ridge = 8.0, -14.0, 12.0, 15.0, 25.0
    h.hall(hw, y0, y1, eave, ridge, "wall_ashlar")
    h.roof(hw, y0, y1, eave, ridge, "roof_brown_grey", over=0.6, end0=0.0, end1=0.0)
    for sgn in (1, -1):
        s = side(hw, sgn)
        for u in (-10.5, -5.5, -0.5, 4.5, 9.5):
            if sgn == 1 and u == -0.5:
                continue
            h.opening(s, u, 2.0, 5.0, 12.6, arch="pointed", frame="wall_ashlar", frame_w=0.3)
        for u in (-13.0, -8.0, -3.0, 2.0, 7.0):
            buttress(h, s, u, "wall_ashlar", w=1.2, steps=((2.0, 7.0), (1.3, 13.4)))
    # the keep at the +Y end
    k0, k1, kx, ktop = 11.0, 25.0, 7.0, 32.0
    h.box(-kx, kx, k0, k1, 0, ktop, "wall_ashlar")
    for z in (15.0, 24.0):
        h.box(-kx - 0.3, kx + 0.3, k0 - 0.3, k1 + 0.3, z, z + 0.5, "wall_ashlar")
    battlements(h, -kx - 0.4, kx + 0.4, k0 - 0.4, k1 + 0.4, ktop, "wall_ashlar", step=2.8)
    kf = [Wall((kx, (k0 + k1) / 2, 0), (0, 1, 0), (1, 0, 0)), Wall((0, k1, 0), (-1, 0, 0), (0, 1, 0)),
          Wall((-kx, (k0 + k1) / 2, 0), (0, -1, 0), (-1, 0, 0))]
    for f in kf:
        for z in (17.0, 26.5):
            h.opening(f, -2.6, 1.2, z, z + 3.0, arch="round")
            h.opening(f, 2.6, 1.2, z, z + 3.0, arch="round")
    # stair turret on the keep's outer corner
    h.prism(octagon(2.4, kx - 0.4, k1 - 0.4, math.pi / 8), 0, ktop + 5.0, "wall_ashlar")
    h.pyramid(kx - 0.4, k1 - 0.4, 2.8, 2.8, ktop + 5.0, 6.5, "roof_brown_grey", sides=8, rot=math.pi / 8)
    # the cross wing at the -Y end, ridge across (along local X)
    wy0, wy1, wx = -27.0, -13.0, 14.0
    with h.with_matrix(Matrix.Translation((0, (wy0 + wy1) / 2, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z")):
        whw = (wy1 - wy0) / 2
        h.hall(whw, -wx, wx, 13.0, 21.0, "wall_ashlar")
        h.roof(whw, -wx, wx, 13.0, 21.0, "roof_brown_grey", over=0.6, end0=0.0, end1=0.0)
        for yy in (-wx, wx):
            gable_coping(h, whw, yy, 13.0, 21.0, "wall_ashlar")
    wf = Wall((0, wy0, 0), (1, 0, 0), (0, -1, 0))
    for u in (-9.0, -4.5, 4.5, 9.0):
        h.opening(wf, u, 1.8, 3.0, 7.0, arch="pointed", frame="wall_ashlar", frame_w=0.28)
        h.opening(wf, u, 1.6, 8.6, 11.8, arch="pointed", frame="wall_ashlar", frame_w=0.26)
    h.opening(wf, 0, 3.0, 0, 6.0, "timber", arch="pointed", frame="wall_ashlar", frame_w=0.4)
    for sx in (-1, 1):
        for yy in (wy0, wy1):
            cx, cyy = sx * wx, yy
            h.box(cx - 3.4, cx + 3.4, cyy - 3.4, cyy + 3.4, 0, 22.0, "wall_ashlar")
            battlements(h, cx - 3.7, cx + 3.7, cyy - 3.7, cyy + 3.7, 22.0, "wall_ashlar", step=2.2)
            wall = Wall((cx + sx * 3.1, cyy, 0), (0, sx, 0), (sx, 0, 0))
            h.opening(wall, 0, 1.0, 14.0, 17.0, arch="round")
    # gatehouse on the hall's front (local +X), battlemented
    gx0, gx1, gy0, gy1, gtop = hw - 0.5, hw + 6.0, -4.5, 3.5, 19.0
    h.box(gx0, gx1, gy0, gy1, 0, gtop, "wall_ashlar")
    battlements(h, gx0, gx1 + 0.3, gy0 - 0.3, gy1 + 0.3, gtop, "wall_ashlar", step=2.4)
    gf = Wall((gx1, (gy0 + gy1) / 2, 0), (0, 1, 0), (1, 0, 0))
    h.opening(gf, 0, 3.6, 0, 7.0, "timber", arch="pointed", frame="wall_ashlar", frame_w=0.5)
    h.opening(gf, 0, 1.4, 10.0, 13.6, arch="pointed", frame="wall_ashlar", frame_w=0.3)
    return h.finish()


BUILDERS = {
    "cottage_a": cottage_a, "cottage_b": cottage_b, "cottage_c": cottage_c,
    "townhouse_a": townhouse_a, "townhouse_b": townhouse_b, "townhouse_c": townhouse_c,
    "longhouse": longhouse, "workshop": workshop, "barn": barn, "byre": byre,
    "chapel": chapel, "church": church, "church_tower": church_tower, "palace": palace,
}


def build_and_export(type_):
    ob = BUILDERS[type_]()
    return export(ob, type_)
