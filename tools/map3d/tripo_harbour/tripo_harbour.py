"""The town walls, the piers and the harbour ships from Tripo 3D, processed
INSIDE the owner's Blender (owner 2026-10-04: 我已经在 tripo_inbox 中放入 tripo 3d
生成的3d模型，请操作blender修改并应用到游戏中去). Generated on the owner's PAID plan
(Tripo terms §5.2.2) from the reference picks of 2026-10-02; the hand-built
kit modules (tools/map3d/blender_houses/fortifications.py) were ruled too
plain (2026-10-01: 城墙和码头都太丑太简陋了).

    H = {"CC_ROOT": "<repo or worktree>"}
    exec(open(H["CC_ROOT"] + "/tools/map3d/tripo_harbour/tripo_harbour.py").read(), H)
    H["load_all"]()          # every source into the scene Tripo_Harbour, fitted and laid out
    H["build"]("wall")       # one type: shell, trim, reduce, uv, bake, footing, grime
    H["export"]("wall")      # assets/3D/<category>/<type>/<type>.glb + its CSV row + houses.json

It is tools/map3d/tripo_houses/tripo_houses.py's pipeline (exec'd here, its
helpers reused) with what these kinds need on top:

  * FITTED by JOBS' `fit` (the longer ground span, game metres at twice life
    like the houses) after turning by `yaw`, and stood with `z0` at z = 0:
    a wall's foot, a pier's DECK (the runtime seats a `pier` row's origin on
    the sea, map3d_pier_deck_m over it), a ship's WATERLINE (a `ship` row's
    origin is the sea's level).
  * A WALL module is cut to `trim` metres along X with flat ends, so modules
    meet (the source is a long curtain; its ends were towers), and squeezed
    by `squeeze` across its thickness.
  * Fortifications are untinted stone (hh_stone_, the town's wall tints would
    patch a wall module by module) under slate (hh_slate_); a pier and a ship
    are one untinted surface (hh_pier_ / hh_ship_) with no footing.
  * The voxel shell is finer than the houses' (JOBS `voxel`): a ship's sails
    are sheets a few centimetres thick, and only a fine shell keeps them
    whole and closed.
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = globals().get("CC_ROOT", "/Users/samuelzhang/game_design")
SRC_ROOT = "/Users/samuelzhang/game_design"   # the git-ignored Tripo sources live in the main checkout
SCENE = "Tripo_Harbour"
T = {"CC_ROOT": ROOT}
exec(open(ROOT + "/tools/map3d/tripo_houses/tripo_houses.py").read(), T)
K = T["K"]

# type: category, source glb (under assets/3D/<cat>/<type>/model_wip/tripo/), yaw degrees,
# fit (metres, the longer ground span before any trim), z0 (metres over the fitted
# source's bottom that becomes z = 0), triangle budget, atlas px, voxel metres,
# (0: no shell — the source is open sheets, welded, filled and collapsed like the palaces),
# kind (fort / pier / ship), trim (metres kept along X, centred; wall only), squeeze (y scale)
JOBS = {
    "wall": dict(cat="buildings", src="wall_tripo.glb", yaw=90, fit=48.0, z0=0.0, budget=1500,
                 px=1024, voxel=0.12, kind="fort", trim=24.0, squeeze=0.7),
    "wall_tower": dict(cat="buildings", src="wall_tower_tripo.glb", yaw=0, fit=18.0, z0=0.0,
                       budget=2500, px=1024, voxel=0.08, kind="fort"),
    "wall_gate": dict(cat="buildings", src="wall_gate_tripo.glb", yaw=0, fit=23.0, z0=0.0,
                      budget=4000, px=2048, voxel=0.1, kind="fort"),
    "pier": dict(cat="buildings", src="pier_tripo.glb", yaw=-90, fit=60.0, z0=5.9, budget=3000,
                 px=2048, voxel=0.1, kind="pier"),
    # the capital's cliff harbour (owner 2026-10-01: 适合那种我的首都建在悬崖边上的那种风格):
    # its ROCK KEPT (owner 2026-10-04 — cut away, the zigzag stair and walls built onto it
    # would hang in the air or sink into a real cliff they do not match), turned so the
    # rock is landward (-X) and the timber quay runs out to sea (+X), its deck at z = 0
    # z0 9.5, not the gate platform's 12: the timber walkway slopes 3 m down to its
    # end, and at 12 its outer half drowned to a line of post tops (2026-10-04)
    "pier_cliff": dict(cat="buildings", src="pier_cliff_tripo.glb", yaw=64, fit=140.0, z0=9.5,
                       budget=12000, px=2048, voxel=0.0, kind="pier"),
    "fishing_boat": dict(cat="ships", src="fishing_boat_tripo.glb", yaw=0, fit=16.0, z0=0.8,
                         budget=1500, px=1024, voxel=0.04, kind="ship"),
    "cog": dict(cat="ships", src="cog_tripo.glb", yaw=90, fit=36.0, z0=2.5, budget=3000,
                px=1024, voxel=0.07, kind="ship"),
    "longship": dict(cat="ships", src="longship_tripo.glb", yaw=0, fit=40.0, z0=1.8, budget=3000,
                     px=1024, voxel=0.0, kind="ship"),
    "carrack": dict(cat="ships", src="carrack_tripo.glb", yaw=90, fit=56.0, z0=5.0, budget=10000,
                    px=2048, voxel=0.0, kind="ship"),
}
LAYOUT = [["wall", "wall_gate", "wall_tower", "pier"], ["pier_cliff"],
          ["fishing_boat", "cog", "carrack", "longship"]]
GAP = 30.0                                  # metres between models in the scene
GAME_OFFSET = Vector((0.0, -340.0, 0.0))    # the game models: the same layout, south of the sources


def _scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = sc
    return sc


def _dir(t):
    return ROOT + "/assets/3D/" + JOBS[t]["cat"] + "/" + t + "/"


def _src_path(t):
    return SRC_ROOT + "/assets/3D/" + JOBS[t]["cat"] + "/" + t + "/model_wip/tripo/" + JOBS[t]["src"]


def _vbounds(obs):
    vs = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    return (Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs))),
            Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs))))


def _import(path, name, col_name):
    """One glb as ONE mesh object `name`, its transforms applied, in its own collection."""
    sc = _scene()
    col = bpy.data.collections.get(col_name)
    if col is None:
        col = bpy.data.collections.new(col_name)
        sc.collection.children.link(col)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
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
    return ob


def fit(ob, t):
    """Turn by the job's yaw, scale its longer ground span to `fit`, centre it
    and put z0 (over its bottom) at z = 0 — in the mesh, never the object."""
    j = JOBS[t]
    me = ob.data
    me.transform(Matrix.Rotation(math.radians(j["yaw"]), 4, "Z"))
    vs = [v.co for v in me.vertices]
    lo = Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs)))
    hi = Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs)))
    s = j["fit"] / max(hi.x - lo.x, hi.y - lo.y)
    me.transform(Matrix.Translation((0, 0, -j["z0"])) @ Matrix.Diagonal((s, s, s, 1)) @
                 Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    me.update()
    return s


def load_all():
    """Every job's source into the scene as <type>_src, fitted, laid out by LAYOUT."""
    _scene()
    for t in JOBS:
        if t + "_src" not in bpy.data.objects:
            fit(_import(_src_path(t), t + "_src", t + "_src"), t)
    return arrange()


def arrange():
    """Each source in its LAYOUT row, its game model (if built) GAME_OFFSET south of it."""
    y = 0.0
    for row in LAYOUT:
        x, depth = 0.0, 0.0
        for t in row:
            src = bpy.data.objects.get(t + "_src")
            if src is None:
                continue
            vs = [v.co for v in src.data.vertices]
            w = max(p.x for p in vs) - min(p.x for p in vs)
            d = max(p.y for p in vs) - min(p.y for p in vs)
            src.location = (x + w / 2, y - d / 2, 0)
            game = bpy.data.objects.get(t + "_game")
            if game is not None:
                game.location = src.location + GAME_OFFSET
            x += w + GAP
            depth = max(depth, d)
        y -= depth + GAP * 1.5
    return y


def _shell(ob, voxel):
    rm = ob.modifiers.new("shell", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.adaptivity = 0.0
    rm.use_smooth_shade = False
    T["_select"](ob)
    bpy.ops.object.modifier_apply(modifier=rm.name)


def _trim(ob, length, squeeze):
    """Keep |x| <= length / 2, each cut end capped flat; squeeze y."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for sign in (-1.0, 1.0):
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=(sign * length / 2, 0, 0), plane_no=(sign, 0, 0),
                                     clear_outer=True)
        cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if cut:
            bmesh.ops.holes_fill(bm, edges=cut, sides=0)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    for v in bm.verts:
        v.co.y *= squeeze
    bm.to_mesh(ob.data)
    bm.free()


def _one_slot(ob, name, img):
    ob.data.materials.clear()
    ob.data.materials.append(T["_mat"](name, img))
    for p in ob.data.polygons:
        p.material_index = 0


def _fort_slots(ob, t, img):
    """Slot 0 the slate roofs (faces tilted up, above the eaves' share), slot 1
    the untinted stone: a fortification takes no wall tint."""
    T["_split"](ob, t, img, False)
    ob.data.materials[1] = T["_mat"]("hh_stone_" + t, img)


def _scrub(ob, rounds=6):
    """What the houses' tidy cannot fix on a sheet-built ship: faces the
    census calls flipped whichever way they turn (crossed sails, carrack 19)
    are deleted, the small holes they leave pinched, and a face left alone
    on a boundary edge of its own (a 5 m sliver along the carrack's
    bowsprit) dropped. Runs after the bake: it only removes and merges."""
    for _ in range(rounds):
        c = T["census"](ob)
        if c["biggest_hole_m"] < 1.0 and not c["bad"]:
            break
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        drop = {bm.faces[i] for i in c["bad"]}
        lone = [e for e in bm.edges if e.is_boundary]
        if len(lone) <= 2:
            drop |= {f for e in lone for f in e.link_faces}
        bmesh.ops.delete(bm, geom=list(drop), context="FACES_ONLY")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        T["_pinch"](ob)
    c = T["census"](ob)
    c.pop("bad")
    return c


SPECK_M = 1.2   # a loose piece smaller than this across is dropped


def _drop_specks(ob):
    """Loose pieces under SPECK_M across go: the collapse turns rigging and
    ropes into strings of beads that read, beside a moored ship, as stones
    skipping on the water (critic 2026-10-04; the fishing boat carried 131)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    seen, drop = set(), []
    for v0 in bm.verts:
        if v0 in seen:
            continue
        comp, stack = [v0], [v0]
        seen.add(v0)
        while stack:
            v = stack.pop()
            for e in v.link_edges:
                w = e.other_vert(v)
                if w not in seen:
                    seen.add(w)
                    comp.append(w)
                    stack.append(w)
        lo = Vector((min(v.co.x for v in comp), min(v.co.y for v in comp), min(v.co.z for v in comp)))
        hi = Vector((max(v.co.x for v in comp), max(v.co.y for v in comp), max(v.co.z for v in comp)))
        if (hi - lo).length < SPECK_M:
            drop += comp
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    return len(drop)


def build(t):
    """One type from its source, beside it as <type>_game."""
    _scene()
    j = JOBS[t]
    T["HOUSES"] = ROOT + "/assets/3D/" + j["cat"] + "/"   # where _bake saves the atlas
    os.makedirs(_dir(t) + "model_wip/tripo", exist_ok=True)
    src = bpy.data.objects[t + "_src"]
    for n in (t + "_game", t + "_high"):
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
    high = src.copy()
    high.data = src.data.copy()
    high.name = t + "_high"
    bpy.context.scene.collection.objects.link(high)
    high.location = (0, 0, 0)
    low = high.copy()
    low.data = high.data.copy()
    low.name = t + "_game"
    low["house_type"] = t
    bpy.context.scene.collection.objects.link(low)
    if j["voxel"] > 0.0:
        _shell(low, j["voxel"])
        if j.get("trim"):
            _trim(low, j["trim"], j.get("squeeze", 1.0))
            _trim(high, j["trim"] + 4.0, j.get("squeeze", 1.0))   # the bake's source squeezed alike
        T["_collapse"](low, j["budget"])
        T["_tidy"](low)
    else:
        # an open hull (longship, carrack) leaves a voxel remesh no inside: it came
        # back as scattered spars and sail corners (2026-10-04)
        T["SHEETS"].add(t)
        T["_reduce"](low, j["budget"], j["fit"])
    T["_reclose"](low)
    img = bpy.data.images.get(t + "_atlas")
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(t + "_atlas", j["px"], j["px"])
    if j["kind"] == "fort":
        _fort_slots(low, t, img)
    else:
        _one_slot(low, ("hh_pier_" if j["kind"] == "pier" else "hh_ship_") + t, img)
    T["_uv"](low)
    lo, hi = T["_bounds"](low)
    T["_bake"](low, high, img, extrusion=max(0.1, 0.012 * (hi - lo).length))
    loops = 0
    if j["kind"] == "fort":
        loops, _ = T["_footing"](low)
        T["_grime"](low)
    bpy.data.objects.remove(high, do_unlink=True)
    T["_shade_by_angle"](low, T["HD_SHARP_DEG"])
    arrange()
    c = _scrub(low)
    if j["kind"] != "fort":
        _drop_specks(low)
        for p in low.data.polygons:    # the fills put their faces on slot 1
            p.material_index = 0
    lo, hi = T["_bounds"](low)
    return {"type": t, "tris": sum(len(p.vertices) - 2 for p in low.data.polygons),
            "footing_loops": loops, "census": c,
            "size": [round(hi.x - lo.x, 1), round(hi.y - lo.y, 1), round(lo.z, 1), round(hi.z, 1)]}


def export(t):
    """kit.export's glb into assets/3D/<category>/<type>/, its CSV row's sizes
    and houses.json; a fortification is fitted by what stands above z = 0
    (its footing reaches below), a pier or a ship by all of it."""
    import csv
    import io
    ob = bpy.data.objects[t + "_game"]
    rows = {r["type"]: r for r in csv.DictReader(open(ROOT + "/data/map3d_houses.csv"))}
    foot = float(rows[t]["footprint_m"])
    exp = ob.copy()
    exp.data = ob.data.copy()
    exp.name = t + "_export"
    bpy.context.scene.collection.objects.link(exp)
    exp.location = (0, 0, 0)
    vs = [v.co for v in exp.data.vertices]
    # a house's footing hides in the ground; a pier's piles, a cliff harbour's rock and
    # a ship's hull under the water are drawn, so they count toward the footprint
    up = vs if JOBS[t]["kind"] != "fort" else [v for v in vs if v.z >= -0.01]
    lo = Vector((min(v.x for v in up), min(v.y for v in up), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in up), max(v.y for v in up), max(v.z for v in vs)))
    s = foot / max(hi.x - lo.x, hi.y - lo.y)
    exp.data.transform(Matrix.Diagonal((s, s, s, 1)) @
                       Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0.0)))
    exp.data.update()
    T["_select"](exp)
    os.makedirs(_dir(t), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=_dir(t) + t + ".glb", export_format="GLB", use_selection=True,
                              export_image_format="JPEG", export_jpeg_quality=88, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False,
                              export_vertex_color="ACTIVE")
    width, depth, height = (hi.x - lo.x) * s, (hi.y - lo.y) * s, hi.z * s
    tris = sum(len(p.vertices) - 2 for p in exp.data.polygons)
    bpy.data.objects.remove(exp)
    man_path = ROOT + "/assets/3D/buildings/houses.json"
    man = json.load(open(man_path))
    man[t] = {"footing_m": round(-lo.z * s, 3), "footprint_m": foot, "height_m": round(height, 3),
              "source": "tripo", "tris": tris}
    with open(man_path, "w") as f:
        json.dump(man, f, indent=1, sort_keys=True)
        f.write("\n")
    lines = open(ROOT + "/data/map3d_houses.csv").read().split("\n")
    for i, line in enumerate(lines):
        if line.startswith(t + ","):
            parts = next(csv.reader([line]))
            parts[4:7] = ["%.2f" % width, "%.2f" % depth, "%.2f" % height]
            buf = io.StringIO()
            csv.writer(buf, lineterminator="").writerow(parts)
            lines[i] = buf.getvalue()
    open(ROOT + "/data/map3d_houses.csv", "w").write("\n".join(lines))
    return {"type": t, "scale": round(s, 3), "w": round(width, 2), "d": round(depth, 2),
            "h": round(height, 2), "below": round(-lo.z * s, 2), "tris": tris}
