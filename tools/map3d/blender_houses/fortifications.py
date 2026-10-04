"""SUPERSEDED (2026-10-04): the shipped walls and piers are Tripo generations,
tools/map3d/tripo_harbour/. Kept as the hand-built fallback the owner ruled too
plain (2026-10-01: 城墙和码头都太丑太简陋了).

A town's WALLS and a port's PIER, built in the owner's Blender with the
houses' own kit (owner 2026-10-01: 城镇里的feature如果有城墙我希望城镇的外围能增加城墙；
城镇的feature里如果有码头，我希望城镇能够延伸出去一个码头到海里 — modelled by hand as
MODULES, owner's pick over Tripo parts). Run after kit.py and buildings.py:

    exec(open("<repo>/tools/map3d/blender_houses/kit.py").read())
    exec(open("<repo>/tools/map3d/blender_houses/buildings.py").read())
    exec(open("<repo>/tools/map3d/blender_houses/fortifications.py").read())
    for t in FORTS: print(build_and_export(t))

The bake (tools/map3d/bake_houses.py fortify / harbour) lays the modules
round a walled settlement and out from a port's shore, as extra rows of
houses.csv, so the houses' own layer draws them. Conventions, as the kit's:
game metres at TWICE life like the houses, FRONT (-Y) facing OUT of the town
(the wall's battlements, the gate's face) or out to sea (the pier runs along
+X from its landward end at x = -length/2); a wall module is exactly
WALL_LEN long, its ends flat so modules meet; no weathering sag (a sagging
top would dip between every pair of modules).
"""

WALL_LEN = 24.0      # one wall module's length, metres (data/map3d_houses.csv footprint_m)
WALL_T = 4.4         # its thickness
WALL_H = 11.0        # the wall walk's height
MERLON_W, MERLON_GAP = 1.5, 1.0


def _merlons_x(h, x0, x1, y0, y1, z0, z1, key):
    """Battlements along x, between y0 and y1."""
    step = MERLON_W + MERLON_GAP
    n = int((x1 - x0) // step)
    pad = ((x1 - x0) - n * step + MERLON_GAP) / 2
    for i in range(n):
        a = x0 + pad + i * step
        h.box(a, a + MERLON_W, y0, y1, z0, z1, key)


def _ring_merlons(h, cx, cy, r_in, r_out, z0, z1, n, key):
    """Battlements round a circle: n merlons, each a small turned box."""
    for i in range(n):
        a = 2 * math.pi * i / n
        M = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(a, 4, "Z")
        w = math.pi * r_out / n * 0.55
        with h.with_matrix(M):
            h.box(r_in, r_out, -w, w, z0, z1, key)


def _circle(cx, cy, r, sides, rot=0.0):
    return [(cx + r * math.cos(rot + 2 * math.pi * i / sides),
             cy + r * math.sin(rot + 2 * math.pi * i / sides)) for i in range(sides)]


def wall():
    """One module of a town wall: a rubble curtain on a dressed-stone plinth,
    a crenellated parapet to the field (front, -Y), a low one to the town,
    arrow slits outward."""
    h = House("wall")
    h.sag = 0.0
    L = WALL_LEN / 2
    t = WALL_T / 2
    h.box(-L, L, -t - 0.5, t, 0, 1.8, "wall_ashlar")                     # plinth, battered out
    h.box(-L, L, -t, t, 1.8, WALL_H, "wall_rubble")                        # the curtain
    h.box(-L, L, -t - 0.25, t + 0.15, WALL_H - 0.5, WALL_H, "wall_ashlar")  # string course
    h.box(-L, L, -t - 0.25, -t + 0.6, WALL_H, WALL_H + 1.3, "wall_rubble")  # outer parapet
    _merlons_x(h, -L, L, -t - 0.25, -t + 0.6, WALL_H + 1.3, WALL_H + 2.9, "wall_rubble")
    h.box(-L, L, t - 0.5, t + 0.15, WALL_H, WALL_H + 1.0, "wall_rubble")   # town-side parapet
    g = front(t, -t)
    for u in (-6.0, 6.0):
        h.opening(g, u, 0.4, 5.0, 8.0)
    return h.finish()


def wall_tower():
    """A round tower on the wall's line: a battered foot, rubble shaft,
    a corbelled crenellated top and a conical slate cap."""
    h = House("wall_tower")
    h.sag = 0.0
    h.prism(_circle(0, 0, 7.0, 16), 0, 2.4, "wall_ashlar")
    h.prism(_circle(0, 0, 6.4, 16), 2.4, 17.0, "wall_rubble")
    h.prism(_circle(0, 0, 7.1, 16), 17.0, 18.2, "wall_ashlar")
    _ring_merlons(h, 0, 0, 6.2, 7.1, 18.2, 19.8, 12, "wall_rubble")
    h.pyramid(0, 0, 6.6, 6.6, 18.4, 9.5, "roof_slate", sides=16)
    for a in (0.0, 0.9, -0.9, math.pi / 2, -math.pi / 2, math.pi):
        M = Matrix.Rotation(a - math.pi / 2, 4, "Z")
        with h.with_matrix(M):
            h.opening(front(6.4, -6.35), 0, 0.45, 7.0, 10.0)
            h.opening(front(6.4, -6.35), 0, 0.45, 12.5, 15.0)
    return h.finish()


def wall_gate():
    """A gatehouse astride the wall: an arched passage under a crenellated
    block, two round turrets to the field with slate caps, a portcullis
    half raised in the passage, the gate's face out (-Y)."""
    h = House("wall_gate")
    h.sag = 0.0
    hw, d0, d1, top = 9.0, -5.0, 5.0, 15.0
    pw, ph = 3.2, 9.5          # half the passage's width, its height to the crown
    for sgn in (-1, 1):        # the two piers
        h.box(sgn * pw if sgn > 0 else -hw, hw if sgn > 0 else -pw, d0, d1, 0, top, "wall_rubble")
    h.box(-pw, pw, d0, d1, ph, top, "wall_rubble")                         # over the passage
    h.box(-hw - 0.3, hw + 0.3, d0 - 0.3, d1 + 0.3, top - 0.6, top, "wall_ashlar")
    h.box(-hw - 0.3, hw + 0.3, d0 - 0.3, d0 + 0.6, top, top + 1.3, "wall_rubble")
    h.box(-hw - 0.3, hw + 0.3, d1 - 0.6, d1 + 0.3, top, top + 1.3, "wall_rubble")
    _merlons_x(h, -hw - 0.3, hw + 0.3, d0 - 0.3, d0 + 0.6, top + 1.3, top + 2.9, "wall_rubble")
    _merlons_x(h, -hw - 0.3, hw + 0.3, d1 - 0.6, d1 + 0.3, top + 1.3, top + 2.9, "wall_rubble")
    # the arch's dressed voussoirs, front and back, and the passage's dark vault
    for y in (d0 - 0.15, d1 + 0.15):
        h.box(-pw - 0.6, pw + 0.6, y - 0.15, y + 0.15, ph - 0.2, ph + 0.9, "wall_ashlar")
    h.box(-pw, pw, d0 + 0.2, d1 - 0.2, ph - 0.6, ph, "void")
    # the portcullis, half raised, just inside the face
    y = d0 + 1.0
    for x in (-2.4, -1.2, 0.0, 1.2, 2.4):
        h.box(x - 0.15, x + 0.15, y - 0.15, y + 0.15, 4.5, ph - 0.6, "timber")
    for z in (5.0, 6.6, 8.2):
        h.box(-pw, pw, y - 0.12, y + 0.12, z - 0.12, z + 0.12, "timber")
    # two round turrets on the field side
    for sgn in (-1, 1):
        cx, cy = sgn * (hw - 1.0), d0 - 1.2
        h.prism(_circle(cx, cy, 3.4, 12), 0, 2.0, "wall_ashlar")
        h.prism(_circle(cx, cy, 3.0, 12), 2.0, top + 2.0, "wall_rubble")
        h.prism(_circle(cx, cy, 3.5, 12), top + 2.0, top + 2.8, "wall_ashlar")
        h.pyramid(cx, cy, 3.3, 3.3, top + 2.8, 6.0, "roof_slate", sides=12)
        M = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "Z")
        with h.with_matrix(M):
            h.opening(front(3.0, -2.95), 0, 0.4, 7.0, 9.5)
    g = front(hw, d0)
    h.opening(g, 0, 1.4, 11.0, 13.4, arch="round", frame="wall_ashlar", frame_w=0.25)
    return h.finish()


def pier():
    """A port's timber pier: a plank deck on squared piles out from the
    shore (x = -30) to a wider head (x = +30) with bollards and a small
    crane; the piles reach FOOT_M down so a pier over deep water never
    floats. Its deck stands at the house's floor (z = 0), which the runtime
    seats at the sea's level (role `pier`)."""
    h = House("pier")
    h.sag = 0.0
    L, hw, deck = 30.0, 4.0, 0.7
    h.box(-L, L - 9.0, -hw, hw, -deck, 0.0, "planks")                      # the deck
    h.box(L - 9.0, L, -hw - 3.5, hw + 3.5, -deck, 0.0, "planks")           # the head
    for x in [-L + 1.0 + 6.0 * i for i in range(10)]:                      # piles
        for y in (-hw + 0.4, hw - 0.4):
            h.box(x - 0.35, x + 0.35, y - 0.35, y + 0.35, -FOOT_M, -deck, "timber")
    for x in (L - 8.0, L - 4.5, L - 1.0):
        for y in (-hw - 3.1, hw + 3.1):
            h.box(x - 0.35, x + 0.35, y - 0.35, y + 0.35, -FOOT_M, -deck, "timber")
    for x in [-L + 1.0 + 6.0 * i for i in range(10)]:                      # stringers under the planks
        h.box(x - 0.2, x + 0.2, -hw, hw, -deck - 0.5, -deck, "timber")
    for x, y in ((L - 1.2, -hw - 2.8), (L - 1.2, hw + 2.8), (L - 7.8, -hw - 2.8), (L - 7.8, hw + 2.8)):
        h.box(x - 0.4, x + 0.4, y - 0.4, y + 0.4, 0.0, 1.0, "timber")      # bollards
    for y in (-hw + 0.15, hw - 0.15):                                       # a low rail along the deck
        h.box(-L, L - 9.0, y - 0.12, y + 0.12, 0.9, 1.1, "timber")
        for x in [-L + 3.0 * i for i in range(14)]:
            h.box(x - 0.12, x + 0.12, y - 0.12, y + 0.12, 0.0, 0.9, "timber")
    # a small wooden crane at the head
    cx, cy = L - 4.0, -hw - 1.5
    h.box(cx - 0.4, cx + 0.4, cy - 0.4, cy + 0.4, 0.0, 6.5, "timber")
    with h.with_matrix(Matrix.Translation((cx, cy, 6.5)) @ Matrix.Rotation(-0.5, 4, "Y")):
        h.box(-0.25, 5.5, -0.25, 0.25, -0.25, 0.25, "timber")
    return h.finish()


FORTS = {"wall": wall, "wall_tower": wall_tower, "wall_gate": wall_gate, "pier": pier}
BUILDERS.update(FORTS)
