"""Crown and Council · 美术自检 — the artist's Blender add-on.

The artist (owner 2026-10-01: a non-coding artist makes the 3D models in Tripo
and Blender and exports them to the owner) checks and exports a house or a
regiment against the game's contract with three buttons: New template,
Check, Export GLB (and Record preview for a unit). Everything it knows is in
specs.json beside it, written by tools/art_kit/extract_specs.py from the
repository's own tables and the models the game ships, so the checks are the
game's own (tests/map3d/test_map3d_houses_meshes.gd's hole census, the
runtime's `head` bone and clip names, tools/map3d/blender_houses/kit.py's
export).

Each house and regiment is a SCENE in the game (scenes/models/...) inheriting
the .glb: it finds the mesh by its node name, hangs its materials on the
surfaces in order and points at the textures Godot extracts, named after the
glTF images. So the export writes the names the shipped model has (specs.json
"object" / "rig" / "mesh" / "images", from tools/art_kit/glb_names.py) and
reads the written file back to check them: a delivery then overwrites the
.glb as it is (owner 2026-10-04). The artist's own names are never touched.

Every message the artist reads is Chinese; the code is English like the rest
of the repository. Built into a zip by tools/art_kit/build_kit.py.
"""

bl_info = {
    "name": "Crown and Council · 美术自检",
    "author": "Crown and Council",
    "version": (1, 1, 0),
    "blender": (4, 2, 0),
    "location": "3D 视图 › 侧栏（N）› 王冠与议会",
    "description": "检查并导出《王冠与议会》的房屋和兵种模型",
    "category": "Import-Export",
}

import json
import math
import os
import struct

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "specs.json"), encoding="utf-8") as _f:
    SPECS = json.load(_f)

REF = "参考（不导出）"      # the template's reference collection: never exported
REPORT = "自检报告"          # the text datablock the last check writes
NEW = "__new__"
ERR, WARN, OK, LOOK, INFO = "err", "warn", "ok", "look", "info"
ICONS = {ERR: "CANCEL", WARN: "ERROR", OK: "CHECKMARK", LOOK: "HIDE_OFF", INFO: "INFO"}
MARKS = {ERR: "✗", WARN: "!", OK: "✓", LOOK: "◎", INFO: "·"}


# ------------------------------------------------------------------ helpers

def _house_items(_self, _ctx):
    items = [(t, "%s（%s）" % (t, s["role"]), s.get("notes", "")[:120])
             for t, s in SPECS["houses"].items()]
    return items + [(NEW, "新类型…", "一个尺寸表里还没有的房屋类型")]


def _unit_items(_self, _ctx):
    return [(c, "%s %s" % (u["label"], c), "") for c, u in SPECS["units"].items()]


def _in_ref(ob):
    return any(c.name == REF or c.name.startswith(REF + ".") for c in ob.users_collection)


def _bone_shapes(scene):
    """Meshes a pose bone wears as its display shape (the glTF importer makes
    an Icosphere for this): drawn in the viewport, never part of the model."""
    return {pb.custom_shape for o in scene.objects if o.type == "ARMATURE"
            for pb in o.pose.bones if pb.custom_shape}


def _exported(scene):
    shapes = _bone_shapes(scene)
    return [o for o in scene.objects
            if not _in_ref(o) and o.type in ("MESH", "ARMATURE") and o not in shapes]


def _house_type(props):
    return props.new_type.strip() if props.house_type == NEW else props.house_type


def _house_spec(props):
    t = _house_type(props)
    if props.house_type != NEW:
        return t, SPECS["houses"][t]
    return t, {"role": "house", "footprint_m": props.new_footprint, "tris": props.new_tris,
               "atlas_px": 1024, "materials": ["hh_roof_" + t, "hh_wall_" + t], "hd": False,
               "object": t + "_export", "images": [t + "_atlas"]}


def _tris(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    n = sum(len(p.vertices) - 2 for p in me.polygons)
    ev.to_mesh_clear()
    return n


def _world_mesh(ob):
    """A bmesh of `ob` as it will export: modifiers applied, in world space, triangulated."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    ev.to_mesh_clear()
    bm.transform(ob.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return bm


def _images(materials):
    imgs = []
    for m in materials:
        if m and m.use_nodes and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and n.image not in imgs:
                    imgs.append(n.image)
    return imgs


def _upstream_images(sock):
    """The image nodes feeding `sock`, through any nodes between."""
    found, seen, todo = [], set(), [sock]
    while todo:
        s = todo.pop()
        for link in s.links:
            n = link.from_node
            if n.name in seen:
                continue
            seen.add(n.name)
            if n.type == "TEX_IMAGE" and n.image:
                found.append(n.image)
            todo += [i for i in n.inputs if i.is_linked]
    return found


def _unit_image_roles(mats, want):
    """{image: wanted name} for a regiment's material: the colour texture,
    the normal map and the metallic / roughness texture, found by what they
    feed. Returns (pairs, problems)."""
    pairs, problems = {}, []
    for m in mats:
        p = _principled(m)
        if not p:
            continue
        roles = (("base", ("Base Color",)), ("normal", ("Normal",)), ("mr", ("Metallic", "Roughness")))
        for role, inputs in roles:
            if not want.get(role):
                continue
            imgs = []
            for name in inputs:
                sock = p.inputs.get(name)
                if sock is not None:
                    imgs += [i for i in _upstream_images(sock) if i not in imgs]
            if len(imgs) > 1:
                problems.append("%s 用了 %d 张贴图（%s）：每种只能一张" % (
                    {"base": "颜色", "normal": "法线", "mr": "金属度/粗糙度"}[role], len(imgs),
                    "、".join(i.name for i in imgs)))
            for img in imgs[:1]:
                if img in pairs and pairs[img] != want[role]:
                    problems.append("贴图 %s 同时用作两种用途" % img.name)
                pairs[img] = want[role]
    return pairs, problems


def _rename(items):
    """Give each datablock in {block: name} its name for the export; returns
    what restores every name, the artist's and any it had to move aside."""
    undo = []
    for block, name in items.items():
        if block.name == name:
            continue
        coll = bpy.data.images if isinstance(block, bpy.types.Image) else bpy.data.objects
        other = coll.get(name)
        if other is not None and other is not block:
            undo.append((other, other.name))
            other.name = name + "__src"
        undo.append((block, block.name))
        block.name = name
    return undo


def _restore(undo):
    for block, name in reversed(undo):
        block.name = name


def _glb_names(path):
    """tools/art_kit/glb_names.py read(): the names in the file written."""
    with open(path, "rb") as f:
        blob = f.read()
    size = struct.unpack_from("<I", blob, 12)[0]
    gltf = json.loads(blob[20:20 + size])
    nodes = gltf.get("nodes", [])
    return {
        "roots": [nodes[i].get("name", "") for s in gltf.get("scenes", []) for i in s.get("nodes", [])],
        "meshes": [n.get("name", "") for n in nodes if "mesh" in n],
        "images": [i.get("name", "") for i in gltf.get("images", [])],
    }


def _verify(path, roots, meshes, images):
    """Read the written file back: the names the game's scene needs. On a
    miss the file is renamed so it cannot be handed in by mistake."""
    got = _glb_names(path)
    rows = []
    for label, want, have in (("物体", roots, got["roots"]), ("网格", meshes, got["meshes"]),
                              ("贴图", images, got["images"])):
        miss = [w for w in want if w not in have]
        rows.append((ERR if miss else OK, "%s名 %s" % (label, "、".join(want)) if not miss else
                     "%s名不对：游戏要 %s，文件里是 %s" % (label, "、".join(want), "、".join(have) or "没有")))
    extra = [i for i in got["images"] if i not in images]
    if extra:
        rows.append((WARN, "多出来的贴图 %s：游戏场景不会用它，交付时在说明里写一句" % "、".join(extra)))
    if any(lvl == ERR for lvl, _ in rows):
        bad = path[:-4] + "_名字不对.glb"
        if os.path.exists(bad):
            os.remove(bad)
        os.rename(path, bad)
        rows.append((ERR, "这个文件不能直接交：已改名为 %s，请把它和自检报告发给开发" % os.path.basename(bad)))
        path = bad
    return path, rows


def _rows_text(rows):
    return "\n".join("%s %s" % (MARKS[lvl], text) for lvl, text in rows) + "\n"


def _principled(m):
    if m and m.use_nodes and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                return n
    return None


def _identity(ob, tol=1e-4):
    mw = ob.matrix_world
    return all(abs(mw[i][j] - (1.0 if i == j else 0.0)) < tol for i in range(4) for j in range(4))


def _census(bm, scale):
    """tests/map3d/test_map3d_houses_meshes.gd _manifold_check, on the same
    terms: triangles, edges keyed by position rounded to the millimetre at
    the size the game draws, a hole measured by its loop's box diagonal, a
    face flipped when two of its own edges disagree with their neighbours."""
    key = lambda v: "%.3f,%.3f,%.3f" % (v.co.x * scale, v.co.y * scale, v.co.z * scale)
    edge_dir, edge_any, edge_tris = {}, {}, {}
    for i, f in enumerate(bm.faces):
        ks = [key(v) for v in f.verts]
        for k in range(3):
            a, b = ks[k], ks[(k + 1) % 3]
            edge_dir[a + ">" + b] = edge_dir.get(a + ">" + b, 0) + 1
            u = (a + "<>" + b) if a < b else (b + "<>" + a)
            edge_any[u] = edge_any.get(u, 0) + 1
            edge_tris.setdefault(u, []).append(i)
    border, bad = {}, {}
    for u, count in edge_any.items():
        a, b = u.split("<>")
        if count == 1:
            border.setdefault(a, []).append(b)
            border.setdefault(b, []).append(a)
        elif count == 2 and (edge_dir.get(a + ">" + b, 0) != 1 or edge_dir.get(b + ">" + a, 0) != 1):
            for t in edge_tris[u]:
                bad[t] = bad.get(t, 0) + 1
    flipped = sum(1 for n in bad.values() if n >= 2)
    seen, biggest = set(), 0.0
    for start in border:
        if start in seen:
            continue
        stack, pts = [start], []
        seen.add(start)
        while stack:
            k = stack.pop()
            pts.append([float(c) for c in k.split(",")])
            for n in border[k]:
                if n not in seen:
                    seen.add(n)
                    stack.append(n)
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        biggest = max(biggest, math.sqrt(sum((hi[i] - lo[i]) ** 2 for i in range(3))))
    return biggest, flipped


def _bind(ad, act):
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


def _clip_bones(arm, names):
    return [b for b in arm.pose.bones if any(b.name.lower().startswith(n) for n in names)]


def _stride(arm, act):
    """Metres of ground one loop carries the piece (data/screens/map3d/army_art.csv stride_m):
    how fast a planted foot slides back, times the loop's length — the same
    measure as tools/units3d/infantry_blueprint/export.py."""
    feet = _clip_bones(arm, ("foot",)) or _clip_bones(arm, ("fore_hoof", "hind_hoof", "hoof"))
    if not feet:
        return 0.0
    sc = bpy.context.scene
    ad = arm.animation_data or arm.animation_data_create()
    keep, keep_frame = ad.action, sc.frame_current
    _bind(ad, act)
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    speeds = []
    for pb in feet:
        pts = []
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            pts.append((arm.matrix_world @ pb.head).copy())
        low = min(p.z for p in pts)
        speeds += [abs(b.y - a.y) for a, b in zip(pts, pts[1:]) if a.z < low + 0.006 and b.z < low + 0.006]
    if keep:
        _bind(ad, keep)
    else:
        ad.action = None
    sc.frame_set(keep_frame)
    speeds.sort()
    return (speeds[len(speeds) // 2] if speeds else 0.0) * (f1 - f0)


# ------------------------------------------------------------------ checks

def check_house(props):
    t, spec = _house_spec(props)
    out = []
    if not t:
        return [(ERR, "新类型需要先填一个英文名字（例如 smithy）")], {}
    meshes = [o for o in _exported(bpy.context.scene) if o.type == "MESH"]
    if not meshes:
        return [(ERR, "场景里没有要导出的模型（「%s」集合里的东西不算）" % REF)], {}
    if len(meshes) > 1:
        out.append((ERR, "房屋必须是一个物体：现在有 %d 个（全选后 Ctrl+J 合并）" % len(meshes)))
        return out, {}
    ob = meshes[0]
    tris = _tris(ob)
    out.append((OK if tris <= spec["tris"] else ERR,
                "面数 %d / 上限 %d" % (tris, spec["tris"])))

    mats = [s.material for s in ob.material_slots]
    names = [m.name if m else "（空）" for m in mats]
    want = spec["materials"]
    if spec.get("hd"):
        ok = names == want
    else:
        ok = (len(names) == 2 and names[1] == want[1]
              and names[0] in ("hh_roof_" + t, "hh_slate_" + t))
    out.append((OK if ok else ERR, "材质 %s" % "、".join(names) if ok else
                "材质必须正好是：1. %s（或 hh_slate_%s，石板顶不换色）2. %s；现在是 %s"
                % (want[0], t, want[-1], "、".join(names) or "没有材质")))
    if ok and not spec.get("hd") and props.house_type != NEW and names[0] != want[0]:
        out.append((WARN, "尺寸表里 %s 的屋顶是 %s，你用了 %s：换屋顶种类请先和开发确认"
                    % (t, want[0], names[0])))
    used = {p.material_index for p in ob.data.polygons}
    if ok and len(used) < len(names):
        out.append((ERR, "有材质没有分到任何面：屋顶和墙都要有面"))

    imgs = _images(mats)
    if spec.get("hd"):
        out.append((OK if imgs else ERR, "贴图 %d 张" % len(imgs)))
    elif len(imgs) != 1:
        out.append((ERR, "屋顶和墙必须共用一张贴图；现在有 %d 张" % len(imgs)))
    else:
        w, h = imgs[0].size
        px = spec["atlas_px"]
        out.append((OK if (w, h) == (px, px) else WARN, "贴图 %d×%d（要求 %d×%d）" % (w, h, px, px)))
    if spec.get("hd"):
        have = sorted(os.path.splitext(i.name)[0] for i in imgs)
        if have != sorted(spec["images"]):
            out.append((WARN, "游戏里这栋的贴图叫 %s，你的是 %s：图像名要和游戏里一致（改 Blender 里图像的名字）"
                        % ("、".join(spec["images"]), "、".join(have) or "没有")))
        out.append((INFO, "导出时物体命名为 %s（游戏场景按这个名字找）" % spec["object"]))
    else:
        out.append((INFO, "导出时物体命名为 %s、贴图命名为 %s（游戏场景按这些名字找，自动处理）"
                    % (spec["object"], spec["images"][0])))

    bm = _world_mesh(ob)
    zs = [v.co.z for v in bm.verts]
    up = [v.co for v in bm.verts if v.co.z >= -0.01]
    info = {}
    if not up:
        out.append((ERR, "地板不在 z = 0：整栋房子都在地面以下"))
        bm.free()
        return out, info
    span = max(max(v.x for v in up) - min(v.x for v in up), max(v.y for v in up) - min(v.y for v in up))
    s = spec["footprint_m"] / span if span > 0 else 1.0
    height = max(zs) * s
    footing = max(0.0, -min(zs) * s)
    info = {"scale": s, "height_m": height, "footing_m": footing, "tris": tris}
    out.append((INFO, "导出时缩放 ×%.3f 到占地 %.1f m：高 %.1f m" % (s, spec["footprint_m"], height)))
    need = SPECS["footing_m"] - 0.5
    out.append((OK if footing >= need else ERR,
                "地基深 %.1f m（要求墙脚往下 %.0f m）" % (footing, SPECS["footing_m"])))
    hole, flipped = _census(bm, s)
    bm.free()
    out.append((OK if hole < SPECS["hole_max_m"] else ERR,
                "最大的洞 %.2f m（要求小于 %.1f m）" % (hole, SPECS["hole_max_m"])))
    out.append((OK if flipped == 0 else ERR, "反面 %d 个（要求 0）" % flipped))
    if not ob.data.color_attributes and not spec.get("hd"):
        out.append((WARN, "没有顶点色：墙脚往上约 2.6 m 要用顶点色画出变暗的污渍"))
    out += [(LOOK, "目视确认：正门朝 -Y（前视图看到的是正门）"),
            (LOOK, "目视确认：没有底座、地板、草盘、旗帜、灌木、小人"),
            (LOOK, "目视确认：屋顶是暖色陶瓦（石板只给教堂），没有茅草、没有深棕瓦"),
            (LOOK, "目视确认：石头和木头边角不死直，墙脚有做旧")]
    return out, info


def check_unit(props):
    code = props.unit
    spec = SPECS["units"][code]
    out, info = [], {}
    objs = _exported(bpy.context.scene)
    arms = [o for o in objs if o.type == "ARMATURE"]
    meshes = [o for o in objs if o.type == "MESH"]
    if len(arms) != 1:
        return [(ERR, "必须正好有一套骨架；现在有 %d 套" % len(arms))], info
    arm = arms[0]
    if not meshes:
        return [(ERR, "场景里没有要导出的模型")], info
    loose = [o.name for o in meshes
             if not any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers)]
    out.append((OK if not loose else ERR, "所有模型都绑在骨架上" if not loose else
                "这些模型没有绑到骨架（缺 Armature 修改器）：%s" % "、".join(loose)))
    moved = [o.name for o in [arm] + meshes if not _identity(o)]
    out.append((OK if not moved else ERR, "变换已应用" if not moved else
                "这些物体的位置/旋转/缩放没有应用（选中后 Ctrl+A › 全部变换）：%s" % "、".join(moved)))

    tris = sum(_tris(o) for o in meshes)
    out.append((OK if tris <= spec["tris"] else ERR, "面数 %d / 上限 %d" % (tris, spec["tris"])))
    if len(meshes) > 1:
        out.append((WARN, "有 %d 个网格物体：游戏场景只认一个（%s），多出来的要开发另接；最好全选后 Ctrl+J 合并"
                    % (len(meshes), spec["mesh"])))

    names = [b.name for b in arm.data.bones]
    out.append((OK if any(n.lower() == "head" for n in names) else ERR,
                "有 head 骨骼（游戏把人数牌挂在它上方）" if any(n.lower() == "head" for n in names)
                else "缺少名叫 head 的骨骼：游戏要把人数牌挂在它上方"))
    want = [b["name"] for b in spec["bones"]]
    missing = [n for n in want if n not in names]
    extra = [n for n in names if n not in want]
    if missing or extra:
        out.append((WARN, "骨架和模板不一致：缺 %s；多 %s（改骨骼名请先和开发确认）"
                    % ("、".join(missing[:8]) or "无", "、".join(extra[:8]) or "无")))
    else:
        out.append((OK, "骨架与模板一致（%d 根）" % len(names)))

    fps = bpy.context.scene.render.fps
    out.append((OK if fps == SPECS["fps"] else ERR, "帧率 %d fps（要求 %d）" % (fps, SPECS["fps"])))
    acts = {a.name: a for a in bpy.data.actions}
    for clip in spec["clips"]:
        a = acts.get(clip)
        if a is None:
            out.append((ERR, "缺少动作 %s" % clip))
            continue
        f0, f1 = a.frame_range
        out.append((OK if int(f0) == 0 else ERR, "动作 %s：第 %d–%d 帧%s" % (
            clip, f0, f1, "" if int(f0) == 0 else "（必须从第 0 帧开始）")))
    for clip in spec["optional"]:
        if clip in acts:
            out.append((INFO, "可选动作 %s 也会导出" % clip))

    unbound, crowded = 0, 0
    bone_names = set(names)
    for o in meshes:
        groups = {g.index: g.name for g in o.vertex_groups}
        for v in o.data.vertices:
            n = sum(1 for g in v.groups if g.weight > 0 and groups.get(g.group) in bone_names)
            unbound += n == 0
            crowded += n > 4
    out.append((OK if not unbound else ERR, "每个顶点都绑了骨骼" if not unbound else
                "%d 个顶点没有绑到任何骨骼" % unbound))
    if crowded:
        out.append((WARN, "%d 个顶点受超过 4 根骨骼影响：导出会截成 4 根" % crowded))

    zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
    low, top = min(zs), max(zs)
    out.append((OK if abs(low) <= 0.03 else ERR, "脚踩在 z = 0（最低点 %.3f m）" % low))
    info["height_m"] = top - low
    out.append((INFO, "静止姿势总高 %.2f m（游戏现用的 %s 是 %.2f m）"
                % (top - low, code, spec["shipped_height_m"])))
    weapon = spec.get("weapon")
    if weapon and weapon in arm.data.bones:
        b = arm.data.bones[weapon]
        d = (arm.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).normalized()
        tilt = math.degrees(math.acos(min(1.0, abs(d.z))))
        out.append((OK if tilt <= 20 else WARN, "%s 在静止姿势里%s（偏 %.0f°）" % (
            weapon, "竖直" if tilt <= 20 else "不竖直：游戏按静止姿势量大小，会把整个兵种算得很宽", tilt)))

    mats = []
    for o in meshes:
        mats += [s.material for s in o.material_slots if s.material and s.material not in mats]
    out.append((OK if len(mats) == 1 else ERR, "一个材质（%s）" % mats[0].name if len(mats) == 1 else
                "必须只有一个材质；现在有 %d 个" % len(mats)))
    pairs, problems = _unit_image_roles(mats, spec["images"])
    out += [(ERR, p) for p in problems]
    if not any(v == spec["images"]["base"] for v in pairs.values()):
        out.append((ERR, "找不到接在 Base Color 上的颜色贴图"))
    out.append((INFO, "导出时骨架命名为 %s、网格 %s、贴图 %s（游戏场景按这些名字找，自动处理）" % (
        spec["rig"], spec["mesh"], "、".join(v for v in spec["images"].values() if v))))
    imgs = _images(mats)
    px = SPECS["unit_atlas_px"]
    big = [i for i in imgs if tuple(i.size) != (px, px)]
    out.append((OK if imgs and not big else WARN, "贴图都是 %d×%d" % (px, px) if imgs and not big else
                "贴图应为 %d×%d：%s" % (px, px, "、".join("%s %d×%d" % (i.name, *i.size) for i in big) or "没有贴图")))
    for m in mats:
        p = _principled(m)
        if not p:
            continue
        for key, limit, lo in (("Metallic", SPECS["metallic_max"], False), ("Roughness", SPECS["roughness_min"], True)):
            sock = p.inputs.get(key)
            if sock is None:
                continue
            zh = "金属度" if key == "Metallic" else "粗糙度"
            if sock.is_linked:
                out.append((LOOK, "目视确认：%s由贴图控制，%s %.2f" % (zh, "不低于" if lo else "不超过", limit)))
            else:
                v = sock.default_value
                good = v >= limit if lo else v <= limit
                out.append((OK if good else ERR, "%s %.2f（要求%s %.2f）" % (zh, v, "不低于" if lo else "不超过", limit)))
    out += [(LOOK, "目视确认：面朝 +Y（从 -Y 方向的前视图看到的是背面）"),
            (LOOK, "目视确认：没有底座"),
            (LOOK, "目视确认：行军原地走、脚尖朝前不外八字；长矛扛在肩上"),
            (LOOK, "目视确认：关节处甲片不撕裂，手腕不拧")]
    return out, info


def run_check(ctx):
    props = ctx.scene.cc_art
    rows, info = (check_house(props) if props.kind == "HOUSE" else check_unit(props))
    props.results = json.dumps(rows, ensure_ascii=False)
    name = _house_type(props) if props.kind == "HOUSE" else props.unit
    lines = ["《王冠与议会》美术自检 · %s" % name,
             "文件：%s" % (bpy.data.filepath or "（未保存）"), ""]
    lines += ["%s %s" % (MARKS[lvl], text) for lvl, text in rows]
    errs = sum(1 for lvl, _ in rows if lvl == ERR)
    lines += ["", "结果：%s" % ("全部通过（◎ 项请目视确认）" if not errs else "%d 项不合格" % errs)]
    txt = bpy.data.texts.get(REPORT) or bpy.data.texts.new(REPORT)
    txt.clear()
    txt.write("\n".join(lines) + "\n")
    return rows, info, "\n".join(lines) + "\n"


# ------------------------------------------------------------------ export

def _out_dir(props):
    d = bpy.path.abspath(props.out_dir) if props.out_dir else ""
    if not d and bpy.data.filepath:
        d = os.path.dirname(bpy.data.filepath)
    return d


def export_house(props, info, report):
    t, spec = _house_spec(props)
    ob = [o for o in _exported(bpy.context.scene) if o.type == "MESH"][0]
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(ob.matrix_world)
    vs = [v.co for v in me.vertices]
    up = [v for v in vs if v.z >= -0.01]
    lo = Vector((min(v.x for v in up), min(v.y for v in up), 0.0))
    hi = Vector((max(v.x for v in up), max(v.y for v in up), 0.0))
    s = info["scale"]
    # the kit.export rule: the FLOOR stays at z = 0, centred on its footprint
    me.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0.0)))
    obj = spec["object"]
    held = _free_name(obj)
    exp = bpy.data.objects.new(obj, me)
    bpy.context.scene.collection.objects.link(exp)
    imgs = _images([s.material for s in ob.material_slots])
    undo = [] if spec.get("hd") or len(imgs) != 1 else _rename({imgs[0]: spec["images"][0]})
    try:
        bpy.ops.object.select_all(action="DESELECT")
        exp.select_set(True)
        bpy.context.view_layer.objects.active = exp
        d = _out_dir(props)
        path = os.path.join(d, t + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                  use_active_scene=True,
                                  export_image_format="JPEG", export_jpeg_quality=88, export_yup=True,
                                  export_apply=True, export_cameras=False, export_lights=False,
                                  export_vertex_color="ACTIVE")
        w, dpt = (hi.x - lo.x) * s, (hi.y - lo.y) * s
        report += "\n导出：%s\n尺寸 宽 %.2f m × 深 %.2f m × 高 %.2f m，地基 %.2f m，%d 面\n" % (
            path, w, dpt, info["height_m"], info["footing_m"], info["tris"])
    finally:
        _restore(undo)
        bpy.data.objects.remove(exp)
        bpy.data.meshes.remove(me)
        if held is not None:
            held.name = obj
    path, rows = _verify(path, [obj], [obj], spec["images"])
    report += "\n导出文件里的名字：\n" + _rows_text(rows)
    return path, report, not any(lvl == ERR for lvl, _ in rows)


def _free_name(name):
    """Give `name` back to the export: an object already called that is
    renamed for the moment; returns it (or None) so it can be restored."""
    ob = bpy.data.objects.get(name)
    if ob is not None:
        ob.name = name + "__src"
    return ob


def export_unit(props, report):
    """Exports COPIES of the rig and its meshes, so the artist's own scene,
    its NLA tracks and its active action are never touched: the copy's rig
    carries one muted NLA track per clip and nothing else, which the
    exporter's NLA_TRACKS mode writes as one glTF animation each
    (tools/units3d/make_units.py stash)."""
    code = props.unit
    spec = SPECS["units"][code]
    objs = _exported(bpy.context.scene)
    arm = [o for o in objs if o.type == "ARMATURE"][0]
    meshes = [o for o in objs if o.type == "MESH"]
    acts = [bpy.data.actions[c] for c in spec["clips"] + spec["optional"] if c in bpy.data.actions]
    walk = next((a for a in acts if a.name in ("MARCH", "GALLOP")), None)
    stride = _stride(arm, walk) if walk else 0.0
    sc = bpy.context.scene
    renamed = [(o, o.name) for o in [arm] + meshes]
    for o, n in renamed:
        o.name = n + "__src"
    mats = []
    for o in meshes:
        mats += [s.material for s in o.material_slots if s.material and s.material not in mats]
    pairs, _problems = _unit_image_roles(mats, spec["images"])
    undo = _rename(pairs)
    copies = []
    try:
        arm2 = arm.copy()
        undo += _rename({arm2: spec["rig"]})
        sc.collection.objects.link(arm2)
        copies.append(arm2)
        arm2.animation_data_clear()
        ad = arm2.animation_data_create()
        for a in acts:
            tr = ad.nla_tracks.new()
            tr.name = a.name
            st = tr.strips.new(a.name, int(a.frame_range[0]), a)
            st.name = a.name
            if hasattr(st, "action_slot") and getattr(a, "slots", None):
                try:
                    st.action_slot = a.slots[0]
                except Exception:
                    pass
            tr.mute = True
        for o, (_src, n) in zip(meshes, renamed[1:]):
            m2 = o.copy()
            undo += _rename({m2: spec["mesh"] if len(meshes) == 1 else n})
            sc.collection.objects.link(m2)
            copies.append(m2)
            if m2.parent == arm:
                m2.parent = arm2
            for mod in m2.modifiers:
                if mod.type == "ARMATURE" and mod.object == arm:
                    mod.object = arm2
        bpy.ops.object.select_all(action="DESELECT")
        for o in copies:
            o.select_set(True)
        bpy.context.view_layer.objects.active = arm2
        path = os.path.join(_out_dir(props), code + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                  use_active_scene=True, export_yup=True, export_apply=False,
                                  export_image_format="JPEG", export_jpeg_quality=92,
                                  export_animations=True, export_animation_mode="NLA_TRACKS",
                                  export_frame_range=False, export_optimize_animation_size=False,
                                  export_anim_single_armature=True)
    finally:
        _restore(undo)          # before the copies go: their names are in it
        for o in copies:
            bpy.data.objects.remove(o)
        for o, n in renamed:
            o.name = n
    report += "\n导出：%s\n动作：%s\n%s 一个循环走 %.3f m（填进 data/screens/map3d/army_art.csv 的 stride_m）\n" % (
        path, "、".join(a.name for a in acts), walk.name if walk else "行军", stride)
    path, rows = _verify(path, [spec["rig"]], [spec["mesh"]], [v for v in spec["images"].values() if v])
    report += "\n导出文件里的名字：\n" + _rows_text(rows)
    return path, report, not any(lvl == ERR for lvl, _ in rows)


# ------------------------------------------------------------------ templates

def _ref_collection(scene):
    col = bpy.data.collections.get(REF)
    if col is None:
        col = bpy.data.collections.new(REF)
    if col.name not in scene.collection.children:
        scene.collection.children.link(col)
    return col


def _link(col, ob):
    col.objects.link(ob)
    return ob


def _camera(col, target, dist, pitch_deg=50.0, yaw_deg=-30.0):
    cam = _link(col, bpy.data.objects.new("游戏机位", bpy.data.cameras.new("游戏机位")))
    p, y = math.radians(pitch_deg), math.radians(yaw_deg)
    off = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p))) * dist
    cam.location = Vector(target) + off
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 50
    bpy.context.scene.camera = cam
    return cam


def _text(col, name, body, loc, size):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    ob = _link(col, bpy.data.objects.new(name, cu))
    ob.location = loc
    ob.rotation_euler = (math.radians(90), 0, 0)
    return ob


def _outline(col, name, hx, hy, z=0.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-hx, -hy, z), (hx, -hy, z), (hx, hy, z), (-hx, hy, z)], [(0, 1), (1, 2), (2, 3), (3, 0)], [])
    return _link(col, bpy.data.objects.new(name, me))


def _material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    return m


def template_house(props):
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    t, spec = _house_spec(props)
    col = _ref_collection(sc)
    h = spec["footprint_m"] / 2
    _outline(col, "占地 %.0f m" % spec["footprint_m"], h, h)
    _outline(col, "地基底 -%.0f m" % SPECS["footing_m"], h, h, -SPECS["footing_m"])
    arrow = _link(col, bpy.data.objects.new("正门朝这边（-Y）", None))
    arrow.empty_display_type = "SINGLE_ARROW"
    arrow.empty_display_size = h * 0.6
    arrow.location = (0, -h, 0)
    arrow.rotation_euler = (math.radians(90), 0, 0)    # its +Z arrow turned to point down -Y
    _text(col, "正门文字", "正门 -Y", (-h * 0.4, -h - 1.0, 0.2), max(1.0, h * 0.15))
    _camera(col, (0, 0, spec.get("height_m", h) * 0.4), spec["footprint_m"] * 3.0)
    for name in spec["materials"]:
        _material(name)
    return "已建房屋模板「%s」：占地 %.0f m 的方框、-%.0f m 的地基线、正门方向、游戏机位相机，材质 %s 已创建（请分配到面上）" % (
        t, spec["footprint_m"], SPECS["footing_m"], "、".join(spec["materials"]))


def template_unit(props):
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.render.fps = SPECS["fps"]
    sc.frame_start = 0
    code = props.unit
    spec = SPECS["units"][code]
    col = _ref_collection(sc)
    _outline(col, "地面 z=0", 2.0, 2.0)
    bar = _link(col, bpy.data.objects.new("游戏现用模型高 %.2f m" % spec["shipped_height_m"], None))
    bar.empty_display_type = "SINGLE_ARROW"
    bar.empty_display_size = spec["shipped_height_m"]
    bar.location = (1.2, 0, 0)
    face = _link(col, bpy.data.objects.new("面朝这边（+Y）", None))
    face.empty_display_type = "SINGLE_ARROW"
    face.empty_display_size = 1.0
    face.rotation_euler = (math.radians(-90), 0, 0)    # its +Z arrow turned to point down +Y
    _camera(col, (0, 0, spec["shipped_height_m"] * 0.5), spec["shipped_height_m"] * 4.0, yaw_deg=150.0)
    name = spec["rig"]
    have = [o.name for o in _exported(sc) if o.type == "ARMATURE"]
    if have:
        return "场景里已经有骨架「%s」，只补了参考线和相机，没有再建骨架" % "、".join(have)
    arm_data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_data)
    sc.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for b in spec["bones"]:
        eb = arm_data.edit_bones.new(b["name"])
        eb.head, eb.tail, eb.roll = Vector(b["head"]), Vector(b["tail"]), b["roll"]
        made[b["name"]] = eb
    for b in spec["bones"]:
        if b["parent"]:
            made[b["name"]].parent = made[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
    return "已建%s模板：骨架「%s」（%d 根，和游戏现用的一致，只调位置不改名）、地面、面朝 +Y、游戏机位相机；帧率 %d，从第 0 帧开始；需要的动作：%s" % (
        spec["label"], name, len(spec["bones"]), SPECS["fps"], "、".join(spec["clips"]))


# ------------------------------------------------------------------ preview

def record_preview(props):
    """One video per clip from the template's game camera, Workbench, so the
    owner can judge the motion at the angle the map is played at."""
    sc = bpy.context.scene
    spec = SPECS["units"][props.unit]
    arm = next((o for o in _exported(sc) if o.type == "ARMATURE"), None)
    if arm is None or sc.camera is None:
        return [], "需要骨架和「游戏机位」相机（先点「新建模板」）"
    r = sc.render
    keep = (r.engine, r.resolution_x, r.resolution_y, r.filepath, sc.frame_start, sc.frame_end,
            r.image_settings.file_format)
    ad = arm.animation_data or arm.animation_data_create()
    keep_action = ad.action
    done = []
    try:
        r.engine = "BLENDER_WORKBENCH"
        r.resolution_x, r.resolution_y = 960, 540
        if hasattr(r.image_settings, "media_type"):
            r.image_settings.media_type = "VIDEO"
        r.image_settings.file_format = "FFMPEG"
        r.ffmpeg.format = "MPEG4"
        r.ffmpeg.codec = "H264"
        for clip in spec["clips"]:
            a = bpy.data.actions.get(clip)
            if a is None:
                continue
            _bind(ad, a)
            f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
            loops = 1 if clip == "ATTACK" else 3
            sc.frame_start, sc.frame_end = f0, f0 + (f1 - f0) * loops
            path = os.path.join(_out_dir(props), "%s_%s.mp4" % (props.unit, clip))
            r.filepath = path
            bpy.ops.render.render(animation=True)
            done.append(path)
    finally:
        r.engine, r.resolution_x, r.resolution_y, r.filepath, sc.frame_start, sc.frame_end, fmt = keep
        if hasattr(r.image_settings, "media_type"):
            r.image_settings.media_type = "IMAGE"
        r.image_settings.file_format = fmt
        if keep_action:
            _bind(ad, keep_action)
        else:
            ad.action = None
    return done, "已录 %d 段：%s" % (len(done), "、".join(os.path.basename(p) for p in done))


# ------------------------------------------------------------------ UI

class CCArtProps(bpy.types.PropertyGroup):
    kind: bpy.props.EnumProperty(name="类别", items=[("HOUSE", "房屋", ""), ("UNIT", "兵种", "")])
    house_type: bpy.props.EnumProperty(name="房屋类型", items=_house_items)
    new_type: bpy.props.StringProperty(name="新类型英文名", default="")
    new_footprint: bpy.props.FloatProperty(name="占地（米）", default=18.0, min=4.0, max=120.0)
    new_tris: bpy.props.IntProperty(name="面数上限", default=2200, min=500, max=61000)
    unit: bpy.props.EnumProperty(name="兵种", items=_unit_items)
    out_dir: bpy.props.StringProperty(name="导出到", subtype="DIR_PATH", default="")
    results: bpy.props.StringProperty(default="[]")


class CC_OT_template(bpy.types.Operator):
    bl_idname = "cc_art.template"
    bl_label = "新建模板"
    bl_description = "在当前场景里放好参考线、方向、相机和规定的材质 / 骨架"

    def execute(self, ctx):
        props = ctx.scene.cc_art
        if props.kind == "HOUSE" and not _house_type(props):
            self.report({"ERROR"}, "新类型需要先填一个英文名字")
            return {"CANCELLED"}
        msg = template_house(props) if props.kind == "HOUSE" else template_unit(props)
        self.report({"INFO"}, msg)
        return {"FINISHED"}


class CC_OT_check(bpy.types.Operator):
    bl_idname = "cc_art.check"
    bl_label = "检查"
    bl_description = "按游戏的规格逐条检查，结果写进文本「自检报告」"

    def execute(self, ctx):
        rows, _info, _rep = run_check(ctx)
        errs = sum(1 for lvl, _ in rows if lvl == ERR)
        self.report({"WARNING"} if errs else {"INFO"},
                    "%d 项不合格" % errs if errs else "全部通过（◎ 项请目视确认）")
        return {"FINISHED"}


class CC_OT_export(bpy.types.Operator):
    bl_idname = "cc_art.export"
    bl_label = "导出 GLB"
    bl_description = "先检查；全部通过才导出 GLB 和自检报告"

    def execute(self, ctx):
        props = ctx.scene.cc_art
        if not _out_dir(props):
            self.report({"ERROR"}, "先保存 .blend 文件，或者在「导出到」里选一个文件夹")
            return {"CANCELLED"}
        rows, info, rep = run_check(ctx)
        errs = sum(1 for lvl, _ in rows if lvl == ERR)
        if errs:
            self.report({"ERROR"}, "%d 项不合格，没有导出：看「自检报告」" % errs)
            return {"CANCELLED"}
        path, rep, good = export_house(props, info, rep) if props.kind == "HOUSE" else export_unit(props, rep)
        name = _house_type(props) if props.kind == "HOUSE" else props.unit
        with open(os.path.join(os.path.dirname(path), name + "_自检.txt"), "w", encoding="utf-8") as f:
            f.write(rep)
        txt = bpy.data.texts.get(REPORT)
        txt.clear()
        txt.write(rep)
        if not good:
            self.report({"ERROR"}, "导出的文件名字和游戏里的不一致，不能直接交：看「自检报告」")
            return {"CANCELLED"}
        self.report({"INFO"}, "已导出 %s" % path)
        return {"FINISHED"}


class CC_OT_preview(bpy.types.Operator):
    bl_idname = "cc_art.preview"
    bl_label = "录制动作预览"
    bl_description = "用「游戏机位」相机把每个动作录成一段 mp4，和 GLB 一起交"

    def execute(self, ctx):
        props = ctx.scene.cc_art
        if not _out_dir(props):
            self.report({"ERROR"}, "先保存 .blend 文件，或者在「导出到」里选一个文件夹")
            return {"CANCELLED"}
        done, msg = record_preview(props)
        self.report({"INFO"} if done else {"ERROR"}, msg)
        return {"FINISHED"} if done else {"CANCELLED"}


class CC_PT_panel(bpy.types.Panel):
    bl_label = "美术自检"
    bl_idname = "CC_PT_art_check"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "王冠与议会"

    def draw(self, ctx):
        props = ctx.scene.cc_art
        col = self.layout.column()
        col.row().prop(props, "kind", expand=True)
        if props.kind == "HOUSE":
            col.prop(props, "house_type")
            if props.house_type == NEW:
                col.prop(props, "new_type")
                col.prop(props, "new_footprint")
                col.prop(props, "new_tris")
            else:
                s = SPECS["houses"][props.house_type]
                col.label(text="占地 %.0f m · 面数 ≤ %d · 贴图 %d" % (s["footprint_m"], s["tris"], s["atlas_px"]))
        else:
            col.prop(props, "unit")
            u = SPECS["units"][props.unit]
            col.label(text="面数 ≤ %d · 动作 %s" % (u["tris"], " ".join(u["clips"])))
        col.prop(props, "out_dir")
        col.separator()
        col.operator("cc_art.template", icon="ADD")
        row = col.row(align=True)
        row.scale_y = 1.4
        row.operator("cc_art.check", icon="VIEWZOOM")
        row.operator("cc_art.export", icon="EXPORT")
        if props.kind == "UNIT":
            col.operator("cc_art.preview", icon="RENDER_ANIMATION")
        rows = json.loads(props.results or "[]")
        if rows:
            box = col.box()
            for lvl, text in rows:
                box.label(text=text, icon=ICONS.get(lvl, "DOT"))


CLASSES = (CCArtProps, CC_OT_template, CC_OT_check, CC_OT_export, CC_OT_preview, CC_PT_panel)


def register():
    for c in CLASSES:
        bpy.utils.register_class(c)
    bpy.types.Scene.cc_art = bpy.props.PointerProperty(type=CCArtProps)


def unregister():
    del bpy.types.Scene.cc_art
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)
