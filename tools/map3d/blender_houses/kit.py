"""The kit the hand-modelled settlement houses are built from, run INSIDE Blender.

Owner 2026-09-24: every house type is modelled anew in Blender (through the
Blender MCP), against the Flux reference pictures in
assets/flux/out/house_ref/ (no AI 3D: Hunyuan3D was removed over its
licence). Load it in Blender with

    exec(open("<repo>/tools/map3d/blender_houses/kit.py").read())
    exec(open("<repo>/tools/map3d/blender_houses/buildings.py").read())
    build_and_export("cottage_a")

Conventions:
  * Blender Z is up; the building's FRONT (its door, the side that faces the
    lane) looks down -Y, which the glTF exporter turns into Godot's +Z — the
    way bake_houses.half_extents and Map3DLayerHouses expect a house to face.
  * A building is modelled in GAME metres (the map draws houses at twice
    life size, taste.md 2026-09-21), and export() then scales it uniformly so
    its longer ground span is data/map3d_houses.csv's footprint_m: the packer
    was measured against those footprints and keeps working.
  * Every part is a CLOSED solid (box, prism, extrusion); parts may
    interpenetrate. tests/map3d/test_map3d_houses_meshes.gd holds that no
    hole is wide enough to look through, so nothing may be left open.
  * Materials are KEYS of textures.py (tiling Poly Haven CC0 textures, tinted
    to the palette) plus "void" (a door or window's dark recess); a key's
    texture is laid by world-space projection at its tile size in metres, so
    courses stay level on every wall and run up every roof slope.
  * Detail is geometry that reads at 10-30 px: silhouette first (roof,
    chimney, tower, jetty), then dark openings, then beams standing proud of
    the wall. No base plate, ever (taste.md).
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = "/Users/samuelzhang/game_design"
TEX = ROOT + "/assets/map3d/sources/polyhaven/houses/"
HOUSES = ROOT + "/assets/map3d_houses/"

# key: (tinted diffuse, normal source, tile metres, roughness)
MATS = {
    "roof_red": ("roof_red", "clay_roof_tiles_03", 7.0, 0.8),
    "roof_rose": ("roof_rose", "clay_roof_tiles_03", 7.0, 0.8),
    "roof_orange": ("roof_orange", "clay_roof_tiles_03", 7.0, 0.8),
    "roof_orange_brown": ("roof_orange_brown", "clay_roof_tiles_03", 7.0, 0.8),
    "roof_brown_grey": ("roof_brown_grey", "clay_roof_tiles_03", 7.0, 0.85),
    "roof_slate": ("roof_slate", "roof_slates_02", 7.0, 0.7),
    "wall_rubble": ("wall_rubble", "rustic_stone_wall_02", 4.5, 0.9),
    "wall_ashlar": ("wall_ashlar", "medieval_blocks_03", 4.5, 0.9),
    "wall_plaster": ("wall_plaster", "painted_plaster_wall", 6.0, 0.95),
    "wall_daub": ("wall_daub", "clay_plaster", 6.0, 0.95),
    "timber": ("timber", "old_planks_02", 3.0, 0.9),
    "planks": ("planks", "old_planks_02", 4.0, 0.9),
    "cross_wood": ("cross_wood", "rough_wood", 3.0, 0.9),
}
# Grime (owner 2026-09-24: 墙根加上有污渍、做旧): every wall solid gets a ring
# of vertices GRIME_H above the ground, and the vertex colour (COLOR_0, which
# Godot's glTF import multiplies into the albedo) runs from a damp earthy
# GRIME_BASE at the foot to clean at GRIME_H, then eases GRIME_TOP darker
# toward the eaves. Stain strength varies per vertex by a position hash so
# a long wall is not one even band. Only the wall keys carry it.
WALL_KEYS = ("wall_rubble", "wall_ashlar", "wall_plaster", "wall_daub")
GRIME_H = 2.6
GRIME_BASE = (0.50, 0.45, 0.36)
GRIME_VARY = 0.10
GRIME_TOP = 0.90
GRIME_TOP_M = 9.0
SLOT_M = 90.0        # a new model's place in the Blender scene: its own cell of this grid
VOID = (0x33 / 255, 0x27 / 255, 0x1E / 255)   # warmer than house_void: a pure near-black read as holes stuck on the wall
# Off (2026-09-24): an A/B in game showed no difference at map size, and
# each normal map is another texture and sample per surface.
USE_NORMALS = False


def _lin(c):
    return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92


def material(key):
    name = "hh_" + key
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    if key == "void":
        b.inputs["Base Color"].default_value = (*[_lin(c) for c in VOID], 1)
        b.inputs["Roughness"].default_value = 1.0
        return m
    diff, nrm, _tile, rough = MATS[key]
    it = nt.nodes.new("ShaderNodeTexImage")
    it.image = bpy.data.images.load(TEX + "tinted/" + diff + ".jpg", check_existing=True)
    nt.links.new(it.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    if not USE_NORMALS:
        return m
    nn = nt.nodes.new("ShaderNodeTexImage")
    nn.image = bpy.data.images.load(TEX + nrm + "_nor_gl_1k.jpg", check_existing=True)
    nn.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = rough
    return m


class Wall:
    """One flat wall face: `origin` on the wall's plane at ground level,
    `u` along it and `n` its outward normal (both horizontal). Openings,
    beams and trims are laid in (u, z) and stand `d` metres off the plane."""

    def __init__(self, origin, u, n):
        self.o = Vector(origin)
        self.u = Vector(u).normalized()
        self.n = Vector(n).normalized()

    def at(self, u, z, d=0.0):
        return self.o + self.u * u + self.n * d + Vector((0, 0, z))


class House:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        # "void" is always surface 0: Godot 4.7's glTF import leaves
        # vertex_color_use_as_albedo OFF on a mesh's FIRST surface only
        # (measured 2026-09-24 over five types, every later surface on), and
        # the void is the one surface whose colour the grime never touches
        self.keys = ["void"]
        self.M = Matrix.Identity(4)

    # -- plumbing -----------------------------------------------------------
    def mi(self, key):
        if key not in self.keys:
            self.keys.append(key)
        return self.keys.index(key)

    def _solid(self, rings, key):
        """Faces between consecutive rings of points (same count), capped at
        both ends. Each ring is a closed polygon; the result is closed."""
        idx = self.mi(key)
        vs = [[self.bm.verts.new(self.M @ Vector(p)) for p in ring] for ring in rings]
        k = len(rings[0])
        faces = [self.bm.faces.new(vs[0][::-1]), self.bm.faces.new(vs[-1])]
        for a, b in zip(vs, vs[1:]):
            for i in range(k):
                j = (i + 1) % k
                faces.append(self.bm.faces.new((a[i], a[j], b[j], b[i])))
        for f in faces:
            f.material_index = idx
        return faces

    def with_matrix(self, M):
        """Run the next calls under M (e.g. a wing turned 90 degrees)."""
        house = self

        class _Ctx:
            def __enter__(self_):
                self_.old = house.M
                house.M = house.M @ M

            def __exit__(self_, *a):
                house.M = self_.old
        return _Ctx()

    # -- solids ---------------------------------------------------------------
    def box(self, x0, x1, y0, y1, z0, z1, key):
        return self.prism([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1, key)

    def prism(self, pts, z0, z1, key):
        """A footprint polygon (counter-clockwise, seen from above) raised
        from z0 to z1 (a wall gets a ring at GRIME_H for its stains)."""
        zs = [z0, z1]
        if key in WALL_KEYS and z0 < GRIME_H < z1:
            zs = [z0, GRIME_H, z1]
        return self._solid([[(x, y, z) for x, y in pts] for z in zs], key)

    def along_y(self, prof, y0, y1, key):
        """A profile in (x, z) (counter-clockwise seen from -Y) extruded
        from y0 to y1; a wall's vertical edges get a point at GRIME_H."""
        if key in WALL_KEYS:
            out = []
            for i, (x, z) in enumerate(prof):
                out.append((x, z))
                nx, nz = prof[(i + 1) % len(prof)]
                if abs(nx - x) < 1e-6 and min(z, nz) < GRIME_H < max(z, nz):
                    out.append((x, GRIME_H))
            prof = out
        return self._solid([[(x, y0, z) for x, z in prof], [(x, y1, z) for x, z in prof]], key)

    def hall(self, hw, y0, y1, eave, ridge, key, z0=0.0):
        """A gabled block: walls to `eave`, gable ends to `ridge`, ridge along Y."""
        return self.along_y([(-hw, z0), (hw, z0), (hw, eave), (0, ridge), (-hw, eave)], y0, y1, key)

    def roof(self, hw, y0, y1, eave, ridge, key, over=0.5, thick=0.35, end0=0.4, end1=0.4):
        """A pitched roof slab sitting ON a hall(hw, eave, ridge): its
        underside is the hall's own slope, so the two never z-fight."""
        slope = (ridge - eave) / hw
        t = thick / math.cos(math.atan(slope))
        xo = hw + over
        ze = eave - over * slope
        prof = [(-xo, ze), (-xo, ze + t), (0, ridge + t), (xo, ze + t), (xo, ze), (0, ridge)]
        return self.along_y(prof, y0 - end0, y1 + end1, key)

    def shed_roof(self, x0, x1, y0, y1, z_low, z_high, key, thick=0.3, over=0.4):
        """A lean-to slab falling from z_high at x0 to z_low at x1."""
        sgn = 1.0 if x1 > x0 else -1.0
        drop = (z_high - z_low) / abs(x1 - x0) * over
        prof = [(x0, z_high), (x1 + sgn * over, z_low - drop),
                (x1 + sgn * over, z_low - drop + thick), (x0, z_high + thick)]
        if sgn < 0:
            prof = prof[::-1]
        return self.along_y(prof, y0 - over, y1 + over, key)

    def hipped(self, x0, x1, y0, y1, eave, ridge, key, over=0.5, thick=0.35):
        """A hipped roof over a rectangle: the ridge runs along the longer
        side, every face sloping at the same pitch."""
        x0, x1, y0, y1 = x0 - over, x1 + over, y0 - over, y1 + over
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
        h = ridge - eave
        if hy >= hx:
            ra, rb = (cx, y0 + hx, ridge), (cx, y1 - hx, ridge)
        else:
            ra, rb = (x0 + hy, cy, ridge), (x1 - hy, cy, ridge)
        idx = self.mi(key)
        bm = self.bm
        base = [bm.verts.new(self.M @ Vector(p)) for p in
                ((x0, y0, eave), (x1, y0, eave), (x1, y1, eave), (x0, y1, eave))]
        low = [bm.verts.new(self.M @ Vector(p)) for p in
               ((x0, y0, eave - thick), (x1, y0, eave - thick), (x1, y1, eave - thick), (x0, y1, eave - thick))]
        a, b = bm.verts.new(self.M @ Vector(ra)), bm.verts.new(self.M @ Vector(rb))
        if hy >= hx:
            faces = [(base[0], base[1], a), (base[1], base[2], b, a), (base[2], base[3], b), (base[3], base[0], a, b)]
        else:
            faces = [(base[0], base[1], b, a), (base[1], base[2], b), (base[2], base[3], a, b), (base[3], base[0], a)]
        out = [bm.faces.new(f) for f in faces]
        out.append(bm.faces.new(low[::-1]))
        for i in range(4):
            j = (i + 1) % 4
            out.append(bm.faces.new((low[i], low[j], base[j], base[i])))
        for f in out:
            f.material_index = idx
        return out

    def pyramid(self, cx, cy, hw, hd, z0, h, key, sides=4, rot=0.0):
        """A pyramid or cone cap (a spire when tall): base polygon at z0, apex h above."""
        idx = self.mi(key)
        bm = self.bm
        if sides == 4:
            pts = [(cx - hw, cy - hd), (cx + hw, cy - hd), (cx + hw, cy + hd), (cx - hw, cy + hd)]
        else:
            pts = [(cx + hw * math.cos(rot + 2 * math.pi * i / sides), cy + hd * math.sin(rot + 2 * math.pi * i / sides))
                   for i in range(sides)]
        ring = [bm.verts.new(self.M @ Vector((x, y, z0))) for x, y in pts]
        apex = bm.verts.new(self.M @ Vector((cx, cy, z0 + h)))
        out = [bm.faces.new(ring[::-1])]
        for i in range(len(ring)):
            out.append(bm.faces.new((ring[i], ring[(i + 1) % len(ring)], apex)))
        for f in out:
            f.material_index = idx
        return out

    def chimney(self, x, y, w, d, z0, z1, key="wall_rubble", cap="wall_rubble"):
        self.box(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z0, z1, key)
        self.box(x - w / 2 - 0.2, x + w / 2 + 0.2, y - d / 2 - 0.2, y + d / 2 + 0.2, z1, z1 + 0.35, cap)
        self.box(x - w / 4, x + w / 4, y - d / 4, y + d / 4, z1 + 0.35, z1 + 0.6, "void")

    # -- things laid on a wall ---------------------------------------------
    def panel(self, wall, outline, key, d0=-0.05, d1=0.08):
        """An outline in the wall's (u, z), counter-clockwise seen from
        outside, extruded from d0 to d1 off the wall plane."""
        rings = [[tuple(wall.at(u, z, d)) for u, z in outline] for d in (d0, d1)]
        return self._solid(rings, key)

    def opening(self, wall, u, w, z0, z1, key="void", arch=None, frame=None, frame_w=0.3):
        """A door or window: a dark panel `w` wide from z0 to z1 (`arch`:
        None square, 'pointed', 'round'), optionally ringed by a `frame`
        of another key standing a little prouder."""
        out = _outline(u, w, z0, z1, arch)
        if frame:
            self.panel(wall, _outline(u, w + 2 * frame_w, z0 - (frame_w if z0 > 0.01 else 0), z1 + frame_w, arch),
                       frame, 0.0, 0.14)
        self.panel(wall, out, key, -0.05, 0.18 if frame else 0.08)

    def beam(self, wall, u0, z0, u1, z1, w=0.35, d=0.12, key="timber"):
        """A timber standing proud of a wall from (u0, z0) to (u1, z1)."""
        a, b = Vector((u0, z0)), Vector((u1, z1))
        t = (b - a).normalized()
        s = Vector((-t.y, t.x)) * (w / 2)
        quad = [a - s, a + s, b + s, b - s]
        if (quad[1] - quad[0]).cross(quad[2] - quad[1]) < 0:
            quad = quad[::-1]
        return self.panel(wall, [(p.x, p.y) for p in quad], key, -0.04, d)

    def frame_wall(self, wall, u0, u1, z0, z1, posts=3, rails=(), braces=True, key="timber", w=0.4):
        """Half-timbering over the rectangle u0..u1, z0..z1 of a wall:
        a sill and a head, `posts` evenly spaced studs between the corner
        posts, rails at the given heights, and a brace in each end bay."""
        self.beam(wall, u0, z0 + w / 2, u1, z0 + w / 2, w, key=key)
        self.beam(wall, u0, z1 - w / 2, u1, z1 - w / 2, w, key=key)
        xs = [u0 + w / 2 + (u1 - u0 - w) * i / (posts + 1) for i in range(posts + 2)]
        for x in xs:
            self.beam(wall, x, z0, x, z1, w, key=key)
        for z in rails:
            self.beam(wall, u0, z, u1, z, w * 0.8, key=key)
        if braces and posts >= 1:
            lo, hi = z0 + w, (rails[0] if rails else z1 - w)
            self.beam(wall, xs[0], lo + 0.2, xs[1], hi - 0.2, w * 0.8, key=key)
            self.beam(wall, xs[-1], lo + 0.2, xs[-2], hi - 0.2, w * 0.8, key=key)

    def frame_gable(self, wall, hw, eave, ridge, key="timber", w=0.4, studs=2):
        """The gable triangle's timbers: its two rakes, a collar and a king post."""
        self.beam(wall, -hw + w, eave, 0, ridge - w, w, key=key)
        self.beam(wall, hw - w, eave, 0, ridge - w, w, key=key)
        self.beam(wall, 0, eave, 0, ridge - w, w, key=key)
        cz = eave + (ridge - eave) * 0.45
        cx = hw * (1 - 0.45)
        self.beam(wall, -cx, cz, cx, cz, w * 0.8, key=key)
        for i in range(1, studs + 1):
            x = hw * i / (studs + 1.5)
            top = eave + (ridge - eave) * (1 - x / hw) - w
            self.beam(wall, x, eave, x, top, w * 0.8, key=key)
            self.beam(wall, -x, eave, -x, top, w * 0.8, key=key)

    # -- finish ----------------------------------------------------------------
    def finish(self):
        # No remove_doubles: each part is its own closed solid, and welding
        # coincident vertices ACROSS parts makes edges with four faces, on
        # which recalc_face_normals can turn a face inside out.
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        uv = bm.loops.layers.uv.verify()
        for f in bm.faces:
            key = self.keys[f.material_index]
            s = MATS[key][2] if key in MATS else 3.0
            n = f.normal
            nh = math.hypot(n.x, n.y)
            for lp in f.loops:
                p = lp.vert.co
                if nh < 0.2:
                    u, v = p.x, p.y
                else:
                    t = Vector((-n.y / nh, n.x / nh, 0))
                    u, v = p.dot(t), p.z / nh
                lp[uv].uv = (u / s, v / s)
        col_layer = bm.loops.layers.color.new("Col")
        for f in bm.faces:
            wall = self.keys[f.material_index] in WALL_KEYS
            for lp in f.loops:
                lp[col_layer] = _grime(lp.vert.co) if wall else (1.0, 1.0, 1.0, 1.0)
        old = bpy.data.objects.get(self.name)
        where = _free_slot(self.name) if old is None else old.location.copy()
        if old is not None:
            bpy.data.objects.remove(old)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for key in self.keys:
            me.materials.append(material(key))
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        ob.location = where
        col = bpy.data.collections.get("HOUSES") or bpy.data.collections.new("HOUSES")
        if col.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(col)
        col.objects.link(ob)
        return ob


def _grime(p):
    """The vertex colour at local position p: stained at the foot, clean at
    GRIME_H, a touch darker toward the eaves."""
    if p.z < GRIME_H:
        h = (math.sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453) % 1.0
        k = min(1.0, max(0.0, GRIME_VARY * (h - 0.5) * 2.0))
        base = [c + (1.0 - c) * k for c in GRIME_BASE]
        t = max(0.0, p.z) / GRIME_H
        rgb = [b + (1.0 - b) * t for b in base]
    else:
        t = min(1.0, (p.z - GRIME_H) / GRIME_TOP_M)
        v = 1.0 - (1.0 - GRIME_TOP) * t
        rgb = [v, v, v]
    return (rgb[0], rgb[1], rgb[2], 1.0)


def _free_slot(name):
    """A new model's place in the Blender scene (owner 2026-09-24: never
    build a new model on top of the last one): the first cell of a
    SLOT_M grid, row by row, that no object in the scene stands in. A model
    rebuilt under the same name keeps the place it has."""
    taken = {(round(o.location.x / SLOT_M), round(o.location.y / SLOT_M))
             for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "Ground"}
    i = 0
    while True:
        cell = (i % 6, -(i // 6))
        if cell not in taken:
            return Vector((cell[0] * SLOT_M, cell[1] * SLOT_M, 0.0))
        i += 1


def _outline(u, w, z0, z1, arch, seg=5):
    h = w / 2
    pts = [(u - h, z0), (u + h, z0)]
    if arch is None:
        pts += [(u + h, z1), (u - h, z1)]
    elif arch == "round":
        zs = z1 - h
        pts += [(u + h * math.cos(math.pi * i / (2 * seg)), zs + h * math.sin(math.pi * i / (2 * seg)))
                for i in range(0, 2 * seg + 1)]
    else:  # pointed: two arcs of radius w from the opposite springings
        zs = z1 - w * math.sin(math.radians(60))
        pts.append((u + h, zs))
        for i in range(1, seg + 1):
            a = math.radians(60 * i / seg)
            pts.append((u - h + w * math.cos(a), zs + w * math.sin(a)))
        for i in range(seg - 1, -1, -1):
            a = math.radians(60 * i / seg)
            pts.append((u + h - w * math.cos(a), zs + w * math.sin(a)))
    return pts


# -- walls of a hall ------------------------------------------------------------
def front(hw, y0):
    """The -Y end wall of a hall hw wide starting at y0 (the house's front
    when its ridge runs along Y); u runs +X."""
    return Wall((0, y0, 0), (1, 0, 0), (0, -1, 0))


def back(hw, y1):
    return Wall((0, y1, 0), (-1, 0, 0), (0, 1, 0))


def side(hw, sign):
    """The long wall at x = sign*hw; u runs along +Y on the +X side."""
    return Wall((sign * hw, 0, 0), (0, sign, 0), (sign, 0, 0))


# -- export ------------------------------------------------------------------------
def export(ob, type_):
    """Scale `ob` so its longer ground span is the type's footprint_m, centre
    it on its own footprint, stand it on z = 0, write
    assets/map3d_houses/<type>.glb and record its measured size in
    houses.json and data/map3d_houses.csv."""
    import csv
    import io
    rows = list(csv.DictReader(open(ROOT + "/data/map3d_houses.csv")))
    row = next(r for r in rows if r["type"] == type_)
    foot = float(row["footprint_m"])
    exp = ob.copy()
    exp.data = ob.data.copy()
    exp.name = type_ + "_export"
    bpy.context.scene.collection.objects.link(exp)
    exp.location = (0, 0, 0)
    vs = [v.co for v in exp.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    s = foot / max(hi.x - lo.x, hi.y - lo.y)
    exp.data.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    exp.data.update()
    bpy.ops.object.select_all(action="DESELECT")
    exp.select_set(True)
    bpy.context.view_layer.objects.active = exp
    bpy.ops.export_scene.gltf(filepath=HOUSES + type_ + ".glb", export_format="GLB", use_selection=True,
                              export_image_format="JPEG", export_jpeg_quality=88, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False,
                              export_vertex_color="ACTIVE")
    width, depth, height = (hi.x - lo.x) * s, (hi.y - lo.y) * s, (hi.z - lo.z) * s
    tris = sum(len(p.vertices) - 2 for p in exp.data.polygons)
    bpy.data.objects.remove(exp)
    man_path = HOUSES + "houses.json"
    man = json.load(open(man_path))
    man[type_] = {"footprint_m": foot, "height_m": round(height, 3), "source": "blender-mcp", "tris": tris}
    with open(man_path, "w") as f:
        json.dump(man, f, indent=1, sort_keys=True)
        f.write("\n")
    lines = open(ROOT + "/data/map3d_houses.csv").read().split("\n")
    for i, line in enumerate(lines):
        if line.startswith(type_ + ","):
            parts = next(csv.reader([line]))
            parts[5:8] = ["%.2f" % width, "%.2f" % depth, "%.2f" % height]
            buf = io.StringIO()
            csv.writer(buf, lineterminator="").writerow(parts)
            lines[i] = buf.getvalue()
    open(ROOT + "/data/map3d_houses.csv", "w").write("\n".join(lines))
    return {"type": type_, "scale": round(s, 3), "w": round(width, 2), "d": round(depth, 2),
            "h": round(height, 2), "tris": tris, "surfaces": len(ob.data.materials)}


def render_views(ob, out_prefix, res=(900, 700)):
    """Two close renders of `ob` (front-left and back-right) for review."""
    sc = bpy.context.scene
    cam = sc.camera
    sc.render.resolution_x, sc.render.resolution_y = res
    for o in bpy.data.collections["HOUSES"].objects:
        o.hide_render = o is not ob
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c, r = (lo + hi) / 2, (hi - lo).length
    paths = []
    for tag, d in (("front", Vector((-0.8, -1.0, 0.7))), ("back", Vector((1.0, 0.9, 0.75)))):
        cam.location = c + d.normalized() * r * 1.25
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = out_prefix + "_" + tag + ".png"
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    return paths
