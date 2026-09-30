"""The settlement houses from Tripo 3D, processed INSIDE the owner's Blender.

Owner 2026-09-30: 重构房屋3d模型 — the fourteen hand-modelled types are
remade from Tripo generations (the owner's PAID plan, whose outputs are ours:
Tripo terms §5.2.2) of the Qwen-Image-2512 references
(tools/map3d/gen_house_refs.py), and the church and palace keep every version
the owner exported as a VARIANT (church_b, palace_b, palace_c: same rank,
picked per settlement by bake_houses._pick_landmark). Everything runs in the
owner's open Blender through the Blender MCP (owner: 你在blender里的操作，
把所有房屋模型放到一个instance操作给我看), in the scene "Tripo_Houses":

    T = {}; exec(open("/Users/samuelzhang/game_design/tools/map3d/tripo_houses/tripo_houses.py").read(), T)
    T["load_all"]()                  # every source into the scene, fitted to its footprint
    T["build"]("cottage_a")          # one type: reduce, split, uv, bake, footing, grime
    T["export"]("cottage_a")         # assets/3D/buildings/<type>/<type>.glb + the CSV + houses.json
    T["build_all"](); T["export_all"]()

The sources are git-ignored: assets/3D/buildings/<type>/model_wip/tripo/*.glb
(~100k triangles, one 2K PBR texture each). What a type becomes:

  * REDUCED to its triangle budget (JOBS) by a collapse decimation — at map
    size a house is 10-60 px, so the silhouette carries it and the texture
    the rest; the runtime draws no normal map (kit.USE_NORMALS).
  * SPLIT into two surfaces by face: a roof (faces tilted up, above the
    eaves' share of the height) and a wall. They share ONE baked atlas, but
    their material NAMES are the runtime's roles (Map3DLayerHouses._tinted):
    hh_roof_<type> takes the roof tints of data/map3d_house_variants.csv,
    hh_slate_<type> (a slate roof) none, hh_wall_<type> the wall tints. The
    roof is surface 0 because Godot's glTF import leaves vertex colour off
    on a mesh's FIRST surface (kit.House), and the wall carries the grime.
  * BAKED: the Tripo texture's diffuse colour onto a smart-projected atlas of
    the reduced mesh (Cycles, selected to active), JOBS' size.
  * FOOTED: a stone footing kit.FOOT_M below the floor, traced from the
    walls' own cross-section just above the floor (never the mesh's box,
    owner 2026-09-25), kit.FOOT_PROUD out, capped at both ends so it is a
    closed solid, its UVs the nearest wall's, so it wears the wall's stone.
  * GRIMED: kit._grime's vertex colour on the wall and the footing, white on
    the roof (owner 2026-09-24: 墙根加上有污渍、做旧).
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector, kdtree

ROOT = "/Users/samuelzhang/game_design"
HOUSES = ROOT + "/assets/3D/buildings/"
SCENE = "Tripo_Houses"
K = {}
exec(open(ROOT + "/tools/map3d/blender_houses/kit.py").read(), K)

# type: (source, yaw degrees turning its door to -Y, triangle budget, atlas px, roof tinted)
JOBS = {
    "cottage_a": ("cottage_a", 0, 1200, 1024, True),
    "cottage_b": ("cottage_b", 0, 1200, 1024, True),
    "cottage_c": ("cottage_c", 0, 1200, 1024, True),
    "townhouse_a": ("townhouse_a", 0, 2000, 1024, True),
    "townhouse_b": ("townhouse_b", 0, 2000, 1024, True),
    "townhouse_c": ("townhouse_c", 0, 2000, 1024, False),
    "longhouse": ("longhouse", 90, 1200, 1024, True),
    "workshop": ("workshop", 0, 1200, 1024, True),
    "barn": ("barn", 0, 1200, 1024, True),
    "byre": ("byre", 0, 1200, 1024, False),
    "chapel": ("chapel", 0, 3000, 1024, False),
    "church": ("church_v1", 0, 4500, 2048, True),
    "church_b": ("church_v3", 0, 4500, 2048, True),
    "church_tower": ("church_tower", 0, 5500, 2048, False),
    "palace": ("palace_v1", 0, 12000, 2048, False),
    "palace_b": ("palace_v2", 0, 12000, 2048, False),
    "palace_c": ("palace_v3", 0, 12000, 2048, False),
}
ROOF_NZ = 0.35        # a face whose normal rises above this is roof ...
ROOF_ABOVE = 0.35     # ... when its centre stands above this share of the height
VOXEL_PER_M = 1.0 / 140.0   # the clean shell's voxel, a share of the footprint
VOXEL_MAX_M = 0.2           # never coarser than this voxel
SHEETS = {"palace", "palace_b", "palace_c"}   # no shell: collapsed, welded and their holes filled
WELD_M = 0.03               # seams closer than this are one edge
FAN_ROUNDS = 2              # a fan whose triangle already existed leaves its spokes open: fan again
PINCH_MAX_M = 4.0           # a hole still open after the fans and smaller than this is pinched shut
PINCH_ROUNDS = 12           # a pinch can tear a new hole beside it: pinch until none is left (palace_c: 5)
TIDY_ROUNDS = 4
DEGENERATE_M = 0.005        # a triangle thinner than this is dropped by the glTF export and opens a hole
BAKE_MARGIN = 16      # texels each island's colour is pushed out into its gutter
SLICE_Z = 0.6         # the walls' cross-section for the footing, metres above the floor
ROW_GAP = 12.0        # the scene's layout: metres between models
GAME_OFFSET = Vector((0.0, -260.0, 0.0))   # the game models: the same layout, south of the sources


def _scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = sc
    return sc


def _rows():
    import csv
    return {r["type"]: r for r in csv.DictReader(open(ROOT + "/data/map3d_houses.csv"))}


def _source_path(src):
    t, _, v = src.partition("_v")
    if v.isdigit():
        return HOUSES + t + "/model_wip/tripo/" + t + "_tripo_v" + v + ".glb"
    return HOUSES + src + "/model_wip/tripo/" + src + "_tripo.glb"


def _bounds(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs))),
            Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs))))


def _select(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def load_all():
    """Every job's source into the scene as <src>_src, joined into one mesh,
    turned by its yaw, fitted to its type's footprint, centred and stood on
    z = 0, laid out in a row per footprint class."""
    sc = _scene()
    rows = _rows()
    x, y, row_depth = 0.0, 0.0, 0.0
    for t, (src, yaw, _b, _px, _tint) in JOBS.items():
        name = src + "_src"
        if name in bpy.data.objects:
            continue
        foot = float(rows.get(t, rows.get(t.split("_")[0], {})).get("footprint_m", 20.0))
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=_source_path(src))
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == "MESH"]
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        if len(meshes) > 1:
            bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        for o in new:
            if o.name in bpy.data.objects and o != ob:
                bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        ob.name = name
        ob.data.transform(Matrix.Rotation(math.radians(yaw), 4, "Z"))
        lo, hi = _bounds(ob)
        s = foot / max(hi.x - lo.x, hi.y - lo.y)
        ob.data.transform(Matrix.Diagonal((s, s, s, 1)) @
                          Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
        ob.location = (x + foot / 2, y, 0)
        x += foot + ROW_GAP
        row_depth = max(row_depth, foot)
        if x > 260:
            x, y, row_depth = 0.0, y - row_depth - ROW_GAP, 0.0
    return sorted(o.name for o in sc.objects if o.name.endswith("_src"))


def _mat(name, img):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    it = nt.nodes.new("ShaderNodeTexImage")
    it.image = img
    nt.links.new(it.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Metallic"].default_value = 0.0
    nt.nodes.active = it
    return m


def _reduce(ob, budget, foot):
    """A voxel remesh first — a clean closed shell, every hole and every
    loose tile gone, at foot * VOXEL_PER_M — then a collapse to the budget:
    straight onto Tripo's 100k-triangle tile-by-tile roofs, a 1% collapse
    tore them into spikes (2026-09-30, cottage_a). The shell is also what
    closes the mesh: a Tripo palace is open sheets (1,800 open loops, its
    whole base one 94 m hole) and tests/map3d/test_map3d_houses_meshes.gd
    allows no hole a metre across. The voxel is never coarser than
    VOXEL_MAX_M. A palace (SHEETS) cannot take one: its open base leaves
    the remesh no inside, and palace v1 came back a solid wedge at 0.2 m and
    a bare courtyard at 0.49 m — a 12% collapse keeps Tripo's own surface
    clean, and _close() then welds and fills it."""
    if ob.get("house_type") in SHEETS:
        closed = _close(ob)          # BEFORE the collapse, which pulls unwelded seams apart
        _collapse(ob, budget)
        fans = [_fan_fill(ob) for _ in range(FAN_ROUNDS)]   # what the collapse opened round non-manifold joints
        pinched = []
        tidy = []
        for _ in range(TIDY_ROUNDS):
            while len(pinched) < PINCH_ROUNDS and (not pinched or pinched[-1]):
                pinched.append(_pinch(ob))
            tidy.append(_tidy(ob))
            c = census(ob)
            if not c["open_edges"] and not c["flipped"]:
                break
            _fan_fill(ob)
            pinched.append(-1)   # let the pinch run again after the fan
        return closed, fans, pinched, tidy, census(ob)
    rm = ob.modifiers.new("shell", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = min(foot * VOXEL_PER_M, VOXEL_MAX_M)
    rm.adaptivity = 0.0
    rm.use_smooth_shade = False
    _select(ob)
    bpy.ops.object.modifier_apply(modifier=rm.name)
    _collapse(ob, budget)


def _close(ob):
    """Weld the seams within WELD_M, then fill every hole left: the small
    ones are cracks between Tripo's sheets, the one big one its open base,
    which a flat cap closes under the ground. Tripo splits every vertex on a
    texture seam (palace v1: 53,129 open edges raw, 1,183 once welded), so
    this runs on the source mesh, before the collapse."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD_M)
    before = sum(1 for e in bm.edges if e.is_boundary)
    res = bmesh.ops.holes_fill(bm, edges=bm.edges, sides=0)
    bmesh.ops.triangulate(bm, faces=res["faces"])
    after = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(ob.data)
    bm.free()
    return before, after


def _fan_fill(ob):
    """Close every hole left, whatever its shape: a vertex at each open
    loop's centre and a triangle from it to each of the loop's edges, wound
    against the face already on that edge. holes_fill leaves a loop that
    crosses itself (a boundary vertex of degree 4, round a non-manifold
    joint) open; at 1-3 m on a 68 m palace the fan never reads."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    border = [e for e in bm.edges if e.is_boundary]
    adj = {}
    for e in border:
        for v in e.verts:
            adj.setdefault(v, []).append(e)
    seen, n = set(), 0
    for e0 in border:
        if e0 in seen:
            continue
        comp, stack = [], [e0]
        while stack:
            e = stack.pop()
            if e in seen:
                continue
            seen.add(e)
            comp.append(e)
            for v in e.verts:
                stack.extend(x for x in adj[v] if x not in seen)
        vs = {v for e in comp for v in e.verts}
        c = bm.verts.new(sum((v.co for v in vs), Vector()) / len(vs))
        for e in comp:
            lp = e.link_loops[0]
            a, b = lp.vert, lp.link_loop_next.vert
            try:
                f = bm.faces.new((b, a, c))
                f.material_index = 1
            except ValueError:
                pass
        n += 1
    bm.to_mesh(ob.data)
    bm.free()
    return n


def _pinch(ob):
    """The last resort: every hole still open and under PINCH_MAX_M across
    has its rim merged into its centre. What neither fill closes is a knot
    round a non-manifold joint (palace: one 1.9 m hole, palace_b 1.2 m);
    pinched, it moves a few rim vertices by a metre on a 68 m building."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    border = [e for e in bm.edges if e.is_boundary]
    adj = {}
    for e in border:
        a, b = e.verts
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    seen, groups = set(), []
    for v in adj:
        if v in seen:
            continue
        comp, stack = [], [v]
        while stack:
            x = stack.pop()
            if x in seen:
                continue
            seen.add(x)
            comp.append(x)
            stack.extend(adj[x] - seen)
        groups.append(comp)
    n = 0
    for comp in groups:
        pts = [x.co for x in comp]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        if (hi - lo).length < PINCH_MAX_M and all(x.is_valid for x in comp):
            bmesh.ops.pointmerge(bm, verts=comp, merge_co=(lo + hi) / 2)
            n += 1
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
    bm.to_mesh(ob.data)
    bm.free()
    return n


def census(ob):
    """tests/map3d/test_map3d_houses_meshes.gd's own census, over the
    triangulated mesh keyed by millimetre POSITION: an edge walked by one
    triangle is a hole (biggest_hole_m its loop's box diagonal), and a
    triangle whose edges are walked the same way as their neighbour's on
    two or more sides is flipped. `bad` lists the flipped faces' indices in
    ob.data.polygons."""
    me = ob.data
    key = lambda co: "%.3f,%.3f,%.3f" % (co.x, co.y, co.z)
    edge_dir, edge_any, edge_faces = {}, {}, {}
    for p in me.polygons:
        ks = [key(me.vertices[v].co) for v in p.vertices]
        for tri in [(0, i, i + 1) for i in range(1, len(ks) - 1)]:
            t = [ks[j] for j in tri]
            for k in range(3):
                a, b = t[k], t[(k + 1) % 3]
                edge_dir[a + ">" + b] = edge_dir.get(a + ">" + b, 0) + 1
                u = (a + "<>" + b) if a < b else (b + "<>" + a)
                edge_any[u] = edge_any.get(u, 0) + 1
                edge_faces.setdefault(u, []).append(p.index)
    border, bad = {}, {}
    for u, c in edge_any.items():
        a, b = u.split("<>")
        if c == 1:
            border.setdefault(a, []).append(b)
            border.setdefault(b, []).append(a)
        elif c == 2 and (edge_dir.get(a + ">" + b, 0) != 1 or edge_dir.get(b + ">" + a, 0) != 1):
            for f in edge_faces[u]:
                bad[f] = bad.get(f, 0) + 1
    seen, big = set(), 0.0
    for start in border:
        if start in seen:
            continue
        stack, pts = [start], []
        seen.add(start)
        while stack:
            x = stack.pop()
            pts.append(Vector([float(c) for c in x.split(",")]))
            for n in border[x]:
                if n not in seen:
                    seen.add(n)
                    stack.append(n)
        lo = Vector((min(q.x for q in pts), min(q.y for q in pts), min(q.z for q in pts)))
        hi = Vector((max(q.x for q in pts), max(q.y for q in pts), max(q.z for q in pts)))
        big = max(big, (hi - lo).length)
    flipped = [f for f, n in bad.items() if n >= 2]
    return {"open_edges": sum(1 for c in edge_any.values() if c == 1), "biggest_hole_m": round(big, 2),
            "flipped": len(flipped), "bad": flipped}


def _tidy(ob):
    """What the glTF export would do to the mesh, done first so it opens
    nothing: triangles thinner than DEGENERATE_M dissolved, normals made
    consistent, and each face the census calls flipped turned over."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.dissolve_degenerate(bm, dist=DEGENERATE_M, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.validate()
    turned = 0
    for _ in range(6):
        bad = census(ob)["bad"]
        if not bad:
            break
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for i in bad])
        bm.to_mesh(ob.data)
        bm.free()
        turned += len(bad)
    bad = census(ob)["bad"]
    if bad:
        # a face that is wrong whichever way it turns (a knot of non-manifold
        # sheets, palace_b: 2) goes, and a fan wound by its neighbours closes it
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in bad], context="FACES_ONLY")
        bm.to_mesh(ob.data)
        bm.free()
        _fan_fill(ob)
        turned += len(bad)
    return turned


def _collapse(ob, budget):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    mod = ob.modifiers.new("reduce", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, budget / tris)
    mod.use_collapse_triangulate = True
    _select(ob)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def _split(ob, t, img, tinted):
    """Slot 0 the roof, slot 1 the wall; each face by its normal and height."""
    ob.data.materials.clear()
    roof = _mat(("hh_roof_" if tinted else "hh_slate_") + t, img)
    wall = _mat("hh_wall_" + t, img)
    ob.data.materials.append(roof)
    ob.data.materials.append(wall)
    top = max(v.co.z for v in ob.data.vertices)
    n_roof = 0
    for p in ob.data.polygons:
        is_roof = p.normal.z > ROOF_NZ and p.center.z > ROOF_ABOVE * top
        p.material_index = 0 if is_roof else 1
        n_roof += is_roof
    return n_roof


def _uv(ob):
    _select(ob)
    for uv in list(ob.data.uv_layers):
        ob.data.uv_layers.remove(uv)
    ob.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, area_weight=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")


def _mean_colour(ob):
    """The mean colour of the source's own texture: what a texel the bake
    misses, and the gutters between the atlas's islands, are filled with."""
    import numpy as np
    for m in ob.data.materials:
        for n in (m.node_tree.nodes if m and m.use_nodes else []):
            if n.type == "TEX_IMAGE" and n.image is not None and n.image.size[0] > 0:
                px = np.empty(n.image.size[0] * n.image.size[1] * 4, dtype=np.float32)
                n.image.pixels.foreach_get(px)
                c = px.reshape(-1, 4)[:, :3].mean(axis=0)
                return (float(c[0]), float(c[1]), float(c[2]), 1.0)
    return (0.5, 0.5, 0.5, 1.0)


def _bake(low, high, img, extrusion):
    """Diffuse colour, selected to active, onto an atlas PRE-FILLED with the
    source's mean colour and never cleared: on a black ground the gutters
    and the missed texels bled black into every mip (2026-09-30, the
    palaces read speckled)."""
    import numpy as np
    fill = _mean_colour(high)
    img.pixels.foreach_set(np.tile(np.array(fill, dtype=np.float32), img.size[0] * img.size[1]))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 4
    try:
        sc.cycles.device = "GPU"
    except TypeError:
        pass
    bk = sc.render.bake
    bk.use_selected_to_active = True
    bk.cage_extrusion = extrusion
    bk.max_ray_distance = extrusion * 4
    bk.margin = BAKE_MARGIN
    bk.use_pass_direct = False
    bk.use_pass_indirect = False
    bk.use_pass_color = True
    high.hide_set(False)
    high.hide_render = False
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=False, margin=BAKE_MARGIN)
    img.filepath_raw = HOUSES + low["house_type"] + "/model_wip/tripo/" + low["house_type"] + "_atlas.png"
    img.file_format = "PNG"
    img.save()


def _loops_at(ob, z):
    """The mesh's cross-section at height z as closed 2-D loops (lists of
    (x, y)), from a bisect of a copy."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                 plane_co=(0, 0, z), plane_no=(0, 0, 1))
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    adj = {}
    for e in edges:
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    seen, loops = set(), []
    for start in adj:
        if start in seen or len(adj[start]) != 2:
            continue
        loop, prev, cur = [], None, start
        while cur not in seen:
            seen.add(cur)
            loop.append((cur.co.x, cur.co.y))
            nxt = [n for n in adj.get(cur, []) if n is not prev and len(adj.get(n, [])) == 2]
            if not nxt:
                loop = []
                break
            prev, cur = cur, nxt[0]
        if len(loop) >= 3 and cur is start:
            loops.append(loop)
    bm.free()
    return loops


def _area(pts):
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                     for i in range(len(pts)))


def _inside(p, poly):
    c = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[i - 1]
        if (y1 > p[1]) != (y2 > p[1]) and p[0] < (x2 - x1) * (p[1] - y1) / (y2 - y1) + x1:
            c = not c
    return c


def _hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def half(ps):
        h = []
        for p in ps:
            while len(h) >= 2 and ((h[-1][0] - h[-2][0]) * (p[1] - h[-2][1]) -
                                   (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0])) <= 0:
                h.pop()
            h.append(p)
        return h
    lo, up = half(pts), half(reversed(pts))
    return lo[:-1] + up[:-1]


def _simplify(pts, tol):
    """Drop points closer than tol to the line through their neighbours."""
    out = list(pts)
    changed = True
    while changed and len(out) > 4:
        changed = False
        for i in range(len(out)):
            a, b, c = Vector(out[i - 1]), Vector(out[i]), Vector(out[(i + 1) % len(out)])
            ac = c - a
            if ac.length < 1e-6:
                continue
            d = abs(ac.x * (b - a).y - ac.y * (b - a).x) / ac.length
            if d < tol:
                out.pop(i)
                changed = True
                break
    return out


def _footing(ob):
    """A closed prism under each outer wall loop, from kit.FOOT_TOP above the
    floor to kit.FOOT_M below it, kit.FOOT_PROUD proud of the wall; slot 1
    (the wall), UVs from the nearest wall vertex near the floor."""
    loops = [l for l in _loops_at(ob, SLICE_Z) if abs(_area(l)) > 4.0]
    outer = [l for l in loops if not any(m is not l and _inside(l[0], m) for m in loops)]
    if not outer:
        outer = [_hull([(v.co.x, v.co.y) for v in ob.data.vertices if v.co.z < SLICE_Z * 2])]
    uvl = ob.data.uv_layers.active.data
    wall_loops = [li for p in ob.data.polygons if p.material_index == 1 for li in p.loop_indices
                  if ob.data.vertices[ob.data.loops[li].vertex_index].co.z < 3.0]
    kd = kdtree.KDTree(len(wall_loops))
    for li in wall_loops:   # only the wall's foot: the eaves' roof UVs painted the footing orange
        co = ob.data.vertices[ob.data.loops[li].vertex_index].co
        kd.insert((co.x, co.y, co.z * 4.0), li)
    kd.balance()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv_layer = bm.loops.layers.uv.active
    added = 0
    for poly in outer:
        poly = _simplify(poly, 0.12)
        if _area(poly) < 0:
            poly = poly[::-1]
        ring = K["_offset"](poly, K["FOOT_PROUD"])
        top = [bm.verts.new((x, y, K["FOOT_TOP"])) for x, y in ring]
        bot = [bm.verts.new((x, y, -K["FOOT_M"])) for x, y in ring]
        n = len(ring)
        faces = [bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i])) for i in range(n)]
        faces.append(bm.faces.new(top))
        faces.append(bm.faces.new(bot[::-1]))
        for f in faces:
            f.material_index = 1
            for lp in f.loops:
                co = lp.vert.co
                _, idx, _ = kd.find((co.x, co.y, max(co.z, 0.0) * 4.0))
                lp[uv_layer].uv = uvl[idx].uv
        added += len(faces)
    bm.to_mesh(ob.data)
    bm.free()
    return len(outer), added


def _grime(ob):
    me = ob.data
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    col = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = 0
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            col.data[li].color = (1, 1, 1, 1) if p.material_index == 0 else K["_grime"](co)


def build(t):
    """One type from its source, in place beside it as <type>_game."""
    _scene()
    src_name, _yaw, budget, px, tinted = JOBS[t]
    src = bpy.data.objects[src_name + "_src"]
    for n in (t + "_game", t + "_high"):
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
    high = src.copy()
    high.data = src.data.copy()
    high.name = t + "_high"
    bpy.context.scene.collection.objects.link(high)
    low = src.copy()
    low.data = src.data.copy()
    low.name = t + "_game"
    low["house_type"] = t
    bpy.context.scene.collection.objects.link(low)
    lo0, hi0 = _bounds(src)
    _reduce(low, budget, max(hi0.x - lo0.x, hi0.y - lo0.y))
    img = bpy.data.images.get(t + "_atlas")
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(t + "_atlas", px, px)
    n_roof = _split(low, t, img, tinted)
    _uv(low)
    lo, hi = _bounds(low)
    _bake(low, high, img, extrusion=max(0.1, 0.012 * (hi - lo).length))
    loops, fpf = _footing(low)
    _grime(low)
    bpy.data.objects.remove(high, do_unlink=True)
    low.location = src.location + GAME_OFFSET
    tris = sum(len(p.vertices) - 2 for p in low.data.polygons)
    return {"type": t, "tris": tris, "roof_faces": n_roof, "footing_loops": loops,
            "size": [round(hi.x - lo.x, 1), round(hi.y - lo.y, 1), round(hi.z, 1)]}


def export(t):
    """kit.export's glb, CSV sizes and houses.json, the source marked tripo."""
    ob = bpy.data.objects[t + "_game"]
    out = K["export"](ob, t)
    path = HOUSES + "houses.json"
    man = json.load(open(path))
    man[t]["source"] = "tripo"
    with open(path, "w") as f:
        json.dump(man, f, indent=1, sort_keys=True)
        f.write("\n")
    return out


def build_all():
    return [build(t) for t in JOBS]


def export_all():
    return [export(t) for t in JOBS]


LAYOUT = [
    ["cottage_a", "cottage_b", "cottage_c", "townhouse_a", "townhouse_b", "townhouse_c"],
    ["longhouse", "workshop", "barn", "byre", "chapel"],
    ["church", "church_b", "church_tower"],
    ["palace", "palace_b", "palace_c"],
]


def arrange():
    """Each type's source and, just in front of it (-Y), its game model; one
    row per LAYOUT line, spaced by the row's biggest footprint."""
    rows = _rows()
    y = 0.0
    for line in LAYOUT:
        feet = [float(rows.get(t, rows.get(t.split("_")[0], {})).get("footprint_m", 20.0)) for t in line]
        big = max(feet)
        x = 0.0
        for t, foot in zip(line, feet):
            src = bpy.data.objects.get(JOBS[t][0] + "_src")
            game = bpy.data.objects.get(t + "_game")
            if src is not None:
                src.hide_set(False)
                src.location = (x + foot / 2, y - big / 2, 0)
            if game is not None:
                game.location = (x + foot / 2, y - big * 1.5 - ROW_GAP / 2, 0)
            x += foot + ROW_GAP
        y -= 2 * big + ROW_GAP * 2.5
    return y
