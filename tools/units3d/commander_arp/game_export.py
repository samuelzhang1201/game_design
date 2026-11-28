"""Install build: the mounted commander with his realm's banner (docs/superpowers/specs/2026-11-27-commander-figure-design.md).

Source (git-ignored, read only): assets/3D/model_wip/blender_output/units/commander/cmd_rider_clips.blend
(the game-budget body `Commander_body` on ARP rig `rig`, the heavy cavalry's `Horse_armored` on ARP rig `horse_rig`,
armature `Banner` + `Banner_mesh` bone-parented to the rider's `cc_weapon.r` socket; every rider clip an action on `rig`
naming its horse action in act["horse"] and its banner action in act["flag"]). Headless, nothing saved:

  Blender -b -y SOURCE.blend --python tools/units3d/commander_arp/game_export.py -- ROOT [OUT.json]

The cavalry's exporter (tools/units3d/cavalry_arp/game_export.py; its README explains the skeleton contract, the hoof lock,
the atlas and the clip keying) changed where the commander differs:
- the body comes in ALREADY at the game budget with its own baked maps (the work folder's d1..d5 scripts), so nothing is
  decimated here;
- the lance's place is the banner: staff and finial on the atlas (two flat swatches), the CLOTH a second surface with its own
  material `banner_cloth`, exported with NO texture (its UVs span one flag picture: the game sets a realm's flag on it,
  Map3DCommanderFigure.set_flag), six bones `flag_1..6` under `cc_weapon.r`, their keys the rider clip's banner action;
- clips MARCH / MARCH_WALK / STANDBY / COMMAND; names `commander_rig`, `commander`, `commander_atlas`.
"""
import importlib.util
import json
import math
import os
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

# Game clip <- source rider clip. MARCH is the run (the cavalry's march), MARCH_WALK the same carriage at the walk.
GAME = {"MARCH": "MARCH", "MARCH_WALK": "MARCH_WALK", "STANDBY": "STANDBY", "COMMAND": "COMMAND"}
LOOPS = {"MARCH", "MARCH_WALK", "STANDBY", "COMMAND"}
REST = ("STANDBY", 1)
SEAM_FRAMES = 6
# MARCH contacts (the source run: the left hind never comes nearer the ground than 44 mm, the right hind
# 11 mm, the fronts skate; the horse pipeline left the run's fronts unpinned). The 13-frame run is
# resampled DENSE keys a frame (its bones' locals interpolated, as Godot would between the 30 fps keys)
# and each hoof's stance is locked: the cyclic run of keys where its lowest sole point is within
# STANCE_M of its own lowest (or of the ground, where the interpolation dips it under), narrowed to the
# longest part of it whose hoof stays within max_offset_m of a straight path at the run's speed (the
# hind hooves are pinned in the source and set the speed; the fronts skate there), the hoof held rigid (its pose at mid-stance, set down onto the ground)
# and carried straight back at the run's speed; the offset eases out over EASE keys either side, and
# the leg follows by two-bone IK (upper arm / forearm, thigh / shin) with the pastern kept. Off its stance
# a hoof clears the ground by ramp_m a key from the stance's edges up to clear_m (the source's fronts stay
# on the ground for a third of the loop: unlocked, that part skated 0.4 m through the planting band).
DENSE = 8
LOCK = {"stance_m": 0.025, "ease": 16, "max_offset_m": 0.05, "min_keys": 8, "clear_m": 0.025, "ramp_m": 0.004}
KNIGHT, HORSE, SPEAR = "Commander_body", "Horse_armored", "Banner_mesh"
BANNER, FLAG = "Banner", ["flag_%d" % i for i in range(1, 7)]
NAME = "commander"
SIDES = {".l": ".L", ".r": ".R"}
# horse bone (ARP horse preset) -> game name. The front legs are ARP's `_dupli_001` leg. ARP cuts each
# long bone in two consecutive halves (twist above, stretch below, or stretch above, twist below); the
# solver's chain bone is the half whose origin is the joint, the other half rides it as a side child.
HORSE_CHAIN = {}
for s, S in SIDES.items():
    HORSE_CHAIN.update({
        "c_thigh_b_dupli_001" + s: "FrontScapula" + S, "thigh_twist_dupli_001" + s: "FrontUpperArm" + S,
        "leg_stretch_dupli_001" + s: "FrontForearm" + S, "foot_dupli_001" + s: "FrontCannon" + S,
        "toes_01_dupli_001" + s: "FrontHoof" + S,
        "thigh_twist" + s: "HindThigh" + S, "leg_stretch" + s: "HindShin" + S, "foot" + s: "HindCannon" + S,
        "toes_01" + s: "HindHoof" + S})
HORSE_RENAME = {**HORSE_CHAIN, "head.x": "head_h"}
KNIGHT_RENAME = {"head.x": "head"}
SADDLE_ON = "spine_02.x"       # the horse bone the saddle (and the stirrups) ride
ATLAS = (4096, 2048)           # w, h
# (u0, v0, du, dv) of each part in the atlas, v up as in Blender's UVs and image rows; each region is
# square in pixels: knight 2048, horse 1536, spear 512
REGION = {"knight": (0.0, 0.0, 0.5, 1.0), "horse": (0.5, 0.25, 0.375, 0.75),
          "spear": (0.875, 0.75, 0.125, 0.25)}
GAME_METAL = float(os.environ.get("CAVALRY_GAME_METAL", "0.45"))  # as the infantry: near-pure metal mirrors the dark map and reads black


def use(name):
    """The rider clip and its horse clip on the two rigs (the source's c10_use.use)."""
    act = bpy.data.actions[name]
    ha = bpy.data.actions[act["horse"]]
    for o, a in ((bpy.data.objects["rig"], act), (bpy.data.objects["horse_rig"], ha), (bpy.data.objects[BANNER], bpy.data.actions[act["flag"]])):
        o.animation_data.action = a
        o.animation_data.action_slot = a.slots[0]
    return tuple(map(int, ha.frame_range))


# ----------------------------------------------------------------- skeleton --

def _bones():
    """[(rig, source bone, game name, game parent)] in parent-before-child order, + the Saddle."""
    K, H = bpy.data.objects["rig"], bpy.data.objects["horse_rig"]
    kk = [b.name for b in K.data.bones if b.use_deform] + ["cc_weapon.r"]
    hk = [b.name for b in H.data.bones if b.use_deform]
    kname = {n: KNIGHT_RENAME.get(n, n) for n in kk}
    hname = {n: HORSE_RENAME.get(n, "h_" + n) for n in hk}

    def nearest(rig, keep, n):
        p = rig.data.bones[n].parent
        while p and p.name not in keep:
            p = p.parent
        return p.name if p else None

    par = {}
    for n in hk:
        p = nearest(H, hk, n)
        par[hname[n]] = hname[p] if p else None
    for n in kk:
        p = nearest(K, kk, n)
        par[kname[n]] = kname[p] if p else None
    # anatomical parents where ARP hangs a deform bone off a control (c_traj, the IK chains): the
    # rider's limbs blend in the pivot by their locals, so every joint must be its parent's child
    for s, S in SIDES.items():
        par.update({
            "h_c_thigh_b" + s: "h_root.x", "HindThigh" + S: "h_c_thigh_b" + s,
            "h_thigh_stretch" + s: "HindThigh" + S, "HindShin" + S: "HindThigh" + S,
            "h_leg_twist" + s: "HindShin" + S, "HindCannon" + S: "HindShin" + S, "HindHoof" + S: "HindCannon" + S,
            "FrontScapula" + S: "h_spine_03.x", "FrontUpperArm" + S: "FrontScapula" + S,
            "h_thigh_stretch_dupli_001" + s: "FrontUpperArm" + S, "FrontForearm" + S: "FrontUpperArm" + S,
            "h_leg_twist_dupli_001" + s: "FrontForearm" + S, "FrontCannon" + S: "FrontForearm" + S,
            "FrontHoof" + S: "FrontCannon" + S,
            "h_stirrup" + s: "Saddle", "h_rein_hand" + s: "hand.l",
            "thigh_twist" + s: "root.x", "thigh_stretch" + s: "thigh_twist" + s,
            "leg_stretch" + s: "thigh_stretch" + s, "leg_twist" + s: "leg_stretch" + s,
            "foot" + s: "leg_twist" + s, "toes_01" + s: "foot" + s,
            "shoulder" + s: "spine_03.x", "c_arm_twist_offset" + s: "shoulder" + s,
            "arm_stretch" + s: "shoulder" + s,
            "forearm_stretch" + s: "arm_stretch" + s, "forearm_twist" + s: "forearm_stretch" + s,
            "hand" + s: "forearm_stretch" + s})
    par.update({"h_root.x": None, "h_spine_01.x": "h_root.x", "h_spine_02.x": "h_spine_01.x",
                "h_spine_03.x": "h_spine_02.x", "h_c_subneck_1.x": "h_spine_03.x",
                "h_c_subneck_2.x": "h_c_subneck_1.x", "h_neck.x": "h_c_subneck_2.x", "head_h": "h_neck.x",
                "h_c_tail_00.x": "h_root.x", "root.x": "Saddle", "spine_01.x": "root.x",
                "spine_02.x": "spine_01.x", "spine_03.x": "spine_02.x", "neck.x": "spine_03.x",
                "head": "neck.x", "cc_weapon.r": "hand.r", "Saddle": "h_" + SADDLE_ON})
    src = {hname[n]: (H, n) for n in hk}
    src.update({kname[n]: (K, n) for n in kk})
    src["Saddle"] = (H, SADDLE_ON)
    B = bpy.data.objects[BANNER]
    for i, n in enumerate(FLAG):                       # the cloth's chain, under the socket the staff rides
        src[n] = (B, n); par[n] = FLAG[i - 1] if i else "cc_weapon.r"
    names = list(src)
    assert set(par) == set(names), set(par) ^ set(names)
    order, seen = [], set()

    def visit(n, trail=()):
        assert n not in trail, ("cycle", trail)
        if n in seen:
            return
        if par[n]:
            visit(par[n], trail + (n,))
        seen.add(n)
        order.append(n)
    for n in names:
        visit(n)
    roots = [n for n in order if par[n] is None]
    assert roots == ["h_root.x"], roots
    return order, par, src


def _pose(order, src):
    """Every game bone's armature-space matrix at the current frame (both rigs sit at identity)."""
    out = {}
    for n in order:
        rig, b = src[n]
        out[n] = rig.matrix_world @ rig.pose.bones[b].matrix
    return out


def _frame(f):
    scn = bpy.context.scene
    scn.frame_set(f)
    scn.frame_set(f)                 # ARP drivers lag one update (source README)


def _skeleton(order, par, rest, src):
    data = bpy.data.armatures.new(NAME + "_rig")
    rig = bpy.data.objects.new(NAME + "_rig", data)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for n in order:
        b = data.edit_bones.new(n)
        r, s = src[n]
        b.length = max(r.data.bones[s].length, 0.02) if n != "Saddle" else 0.2
        b.matrix = rest[n]
        b.use_deform = n != "Saddle"
    for n in order:
        if par[n]:
            data.edit_bones[n].parent = data.edit_bones[par[n]]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return rig


# ------------------------------------------------------------- body, banner --


def _copy(name, new):
    o0 = bpy.data.objects[name]
    o = o0.copy()
    o.data = o0.data.copy()
    o.name = new
    bpy.context.scene.collection.objects.link(o)
    return o


BAKED = {}   # part -> {albedo, mr, n}: (h, w, 4) float arrays laid into its atlas region as they are


SWATCH = {"wood": ((0.40, 0.30, 0.22), (0.0, 0.6, 0.0)), "gilt": ((0.88, 0.77, 0.48), (0.0, 0.35, 1.0))}   # sRGB colour, (0, rough, metal)


def _body(report):
    """The low body as it is in the file (scripts/d1..d5: per-part COLLAPSE, audit, re-unwrap and bake)."""
    ob = _copy(KNIGHT, "knight_low")
    ob.data.calc_loop_triangles()
    report["knight"] = {"tris": len(ob.data.loop_triangles), "decimated_by": "scripts/d1_decimate.py .. d5_finalize.py"}
    return ob


def _banner(report):
    """The banner mesh: staff + finial get the atlas's two flat swatches (left half wood, right half gilt of the `spear` region),
    the cloth keeps its UVs and its own material."""
    ob = _copy(SPEAR, "banner_low")
    me = ob.data
    names = [m.name for m in me.materials]
    u0, v0, du, dv = REGION["spear"]
    uv = me.uv_layers.active.data
    cloth = names.index("banner_cloth")
    for p in me.polygons:
        if p.material_index == cloth:
            continue
        k = 0.75 if names[p.material_index] == "banner_gilt" else 0.25
        for li in p.loop_indices:
            uv[li].uv = (u0 + k * du, v0 + 0.5 * dv)
    size = int(REGION["spear"][2] * ATLAS[0])
    maps = {"albedo": np.ones((size, size, 4), np.float32), "mr": np.ones((size, size, 4), np.float32), "n": np.ones((size, size, 4), np.float32)}
    maps["n"][..., :3] = (0.5, 0.5, 1.0)
    for x0, x1, key in ((0, size // 2, "wood"), (size // 2, size, "gilt")):
        maps["albedo"][:, x0:x1, :3] = SWATCH[key][0]
        maps["mr"][:, x0:x1, :3] = SWATCH[key][1]
    BAKED["spear"] = maps
    me.calc_loop_triangles()
    report["banner"] = {"tris": len(me.loop_triangles), "cloth_tris": sum(len(p.vertices) - 2 for p in me.polygons if p.material_index == cloth),
                        "cloth_material": "banner_cloth", "cloth_image": [n.image.name for n in me.materials[cloth].node_tree.nodes if n.type == "TEX_IMAGE"]}
    # the cloth ships bare: the flag is the game's to set, and no realm's picture is embedded in the model
    nodes = me.materials[cloth].node_tree.nodes
    for n in [n for n in nodes if n.type == "TEX_IMAGE"]:
        nodes.remove(n)
    return ob, cloth


# --------------------------------------------------------------------- mesh --

def _region_uv(obj, part):
    u0, v0, du, dv = REGION[part]
    uv = obj.data.uv_layers.active.data
    co = np.zeros(len(uv) * 2)
    uv.foreach_get("uv", co)
    co = co.reshape(-1, 2)
    assert co.min() > -1e-3 and co.max() < 1 + 1e-3, (part, co.min(), co.max())
    co = np.c_[u0 + np.clip(co[:, 0], 0, 1) * du, v0 + np.clip(co[:, 1], 0, 1) * dv]
    uv.foreach_set("uv", co.ravel())
    obj.data.uv_layers.active.name = "UVMap"


def _posed(ob, rename, prefix):
    """ob's armature applied at the current frame (rest = this pose), its groups renamed to game bones."""
    vl = bpy.context.view_layer
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    vl.objects.active = ob
    mods = [m for m in ob.modifiers if m.type == "ARMATURE"]
    assert len(mods) == 1, [m.name for m in ob.modifiers]
    bpy.ops.object.modifier_apply(modifier=mods[0].name)
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.data.transform(mw)
    ob.matrix_world = Matrix.Identity(4)
    for g in ob.vertex_groups:
        g.name = rename.get(g.name, prefix + g.name)
    return ob


def _mesh(rig, knight, banner, cloth_index):
    """Body, horse and banner posed at REST, merged into ONE mesh: surface 0 on the atlas, surface 1 the cloth."""
    horse = _copy(HORSE, "horse_low")
    _posed(knight, KNIGHT_RENAME, "")
    _posed(horse, HORSE_RENAME, "h_")
    _posed(banner, {"pole": "cc_weapon.r"}, "")
    for ob, part in ((knight, "knight"), (horse, "horse")):
        _region_uv(ob, part)
    banner.data.uv_layers.active.name = "UVMap"
    mat = bpy.data.materials.new(NAME + "_atlas")
    cloth = banner.data.materials[cloth_index]
    for ob in (knight, horse):
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        for p in ob.data.polygons:
            p.material_index = 0
    is_cloth = [p.material_index == cloth_index for p in banner.data.polygons]
    banner.data.materials.clear()
    banner.data.materials.append(mat)
    banner.data.materials.append(cloth)
    for p, c in zip(banner.data.polygons, is_cloth):
        p.material_index = 1 if c else 0
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in (knight, horse, banner):
        o.select_set(True)
    bpy.context.view_layer.objects.active = knight
    bpy.ops.object.join()
    body = knight
    body.name = NAME
    body.data.name = NAME
    assert [m.name for m in body.data.materials] == [NAME + "_atlas", "banner_cloth"], [m.name for m in body.data.materials]
    unknown = [g.name for g in body.vertex_groups if g.name not in rig.data.bones]
    assert not unknown, unknown
    body.modifiers.clear()
    m = body.modifiers.new("Skin", "ARMATURE")
    m.object = rig
    body.parent = rig
    body.matrix_parent_inverse.identity()
    return body, mat


def _pixels(img, w, h):
    c = img.copy()
    c.scale(w, h)
    a = np.array(c.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(c)
    return a


def _maps(name):
    """{albedo, mr, n: image or None} of a source object's material (by the socket each feeds)."""
    nt = bpy.data.objects[name].data.materials[0].node_tree
    out = {"albedo": None, "mr": None, "n": None}
    for n in nt.nodes:
        if n.type != "TEX_IMAGE" or not n.image:
            continue
        for l in n.outputs["Color"].links:
            if l.to_node.type == "BSDF_PRINCIPLED" and l.to_socket.name == "Base Color":
                out["albedo"] = n.image
            elif l.to_node.type == "SEPARATE_COLOR":
                assert {lk.to_socket.name for lk in l.to_node.outputs["Green"].links} == {"Roughness"}, name
                assert {lk.to_socket.name for lk in l.to_node.outputs["Blue"].links} == {"Metallic"}, name
                out["mr"] = n.image
            elif l.to_node.type == "NORMAL_MAP":
                out["n"] = n.image
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    out["const_rough"] = float(bsdf.inputs["Roughness"].default_value)
    out["const_metal"] = float(bsdf.inputs["Metallic"].default_value)
    assert out["albedo"] is not None, name
    return out


def _atlases(mat, out_dir):
    W, H = ATLAS
    parts = {"knight": _maps(KNIGHT), "horse": _maps(HORSE), "spear": {"albedo": None, "mr": None, "n": None}}
    files = {}
    for kind in ("albedo", "mr", "n"):
        atlas = np.zeros((H, W, 4), np.float32)
        atlas[..., 3] = 1
        if kind == "n":
            atlas[..., :3] = (0.5, 0.5, 1.0)
        for part, maps in parts.items():
            u0, v0, du, dv = REGION[part]
            w, h = int(round(du * W)), int(round(dv * H))
            x, y = int(round(u0 * W)), int(round(v0 * H))
            img = maps[kind]
            if part in BAKED:
                atlas[y:y + h, x:x + w] = BAKED[part][kind]
            elif img is not None:
                atlas[y:y + h, x:x + w] = _pixels(img, w, h)
            elif kind == "mr":           # a constant BSDF: G roughness, B metallic
                atlas[y:y + h, x:x + w, :3] = (0.0, maps["const_rough"], maps["const_metal"])
        if kind == "mr":
            atlas[..., 2] *= GAME_METAL
        name = NAME + "_atlas" + ("" if kind == "albedo" else "_" + kind)
        im = bpy.data.images.new(name, W, H, alpha=False)
        if kind != "albedo":
            im.colorspace_settings.name = "Non-Color"
        im.pixels.foreach_set(atlas.ravel())
        path = str(Path(out_dir) / (NAME + "_" + name + ".jpg"))
        im.filepath_raw = path
        im.file_format = "JPEG"
        bpy.context.scene.render.image_settings.quality = 92
        im.save(filepath=path, quality=92)
        im.pack()
        im.filepath_raw = name + ".jpg"
        files[kind] = im
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["albedo"]
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["mr"]
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(t.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["n"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(t.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return {k: str(Path(out_dir) / (NAME + "_" + v.name + ".jpg")) for k, v in files.items()}


# -------------------------------------------------------------------- clips --

def _poses(order, src, clip):
    """The clip's poses, one per frame from its first; a loop gets its own period: when its last frame
    is not its first pose again, the first is appended (the source loops are cyclic: MARCH's 13 frames
    are a 13-frame period, frame 14 = 1), then any residual is spread over the last SEAM_FRAMES."""
    f0, f1 = use(GAME[clip])
    poses = []
    for f in range(f0, f1 + 1):
        _frame(f)
        poses.append(_pose(order, src))
    info = {"source": GAME[clip], "source_frames": [f0, f1], "loop": clip in LOOPS}
    if clip in LOOPS:
        def gap(a, b):
            return max((a[n].translation - b[n].translation).length for n in a)
        last_first = gap(poses[-1], poses[0])
        step = float(np.median([gap(poses[i], poses[i + 1]) for i in range(len(poses) - 1)]))
        info["seam_last_to_first_m"] = round(last_first, 5)
        info["median_step_m"] = round(step, 5)
        if last_first > 0.25 * step:            # last != first: the period ends one frame on
            poses.append({n: m.copy() for n, m in poses[0].items()})
            info["closed"] = "appended first pose"
        else:
            n = len(poses)
            fix = {b: poses[0][b] @ poses[-1][b].inverted() for b in poses[0]}
            for k in range(SEAM_FRAMES):
                i = n - SEAM_FRAMES + k
                w = (k + 1) / SEAM_FRAMES
                poses[i] = {b: Matrix.Identity(4).lerp(fix[b], w) @ m for b, m in poses[i].items()}
            info["closed"] = "residual spread over %d frames" % SEAM_FRAMES
    info["frames"] = len(poses)
    return poses, info


def _rot_about(p, q):
    return Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p)


def _locals(order, par, pose):
    return {n: (pose[par[n]].inverted() @ pose[n]) if par[n] else pose[n].copy() for n in order}


def _fk(order, par, loc, override=None):
    out = {}
    for n in order:
        if override and n in override:
            out[n] = override[n]
        else:
            out[n] = (out[par[n]] @ loc[n]) if par[n] else loc[n].copy()
    return out


def _dense(order, par, poses):
    """poses (a closed loop, last = first) resampled DENSE keys a frame by interpolating each bone's local."""
    locs = [_locals(order, par, p) for p in poses]
    out = []
    for j in range((len(poses) - 1) * DENSE + 1):
        k, a = divmod(j, DENSE)
        a /= DENSE
        if a == 0:
            out.append(_fk(order, par, locs[k]))
            continue
        loc = {}
        for n in order:
            l0, q0, s0 = locs[k][n].decompose()
            l1, q1, s1 = locs[k + 1][n].decompose()
            loc[n] = Matrix.LocRotScale(l0.lerp(l1, a), q0.slerp(q1, a), s0.lerp(s1, a))
        out.append(_fk(order, par, loc))
    return out


def _low(m, pts):
    return min((m @ p).z for p in pts)


def _two_bone(S, E0, K0, K):
    a, b = (E0 - S).length, (K0 - E0).length
    d0 = (K - S).length
    d = min(max(d0, abs(a - b) + 1e-4), a + b - 1e-4)
    t = (K - S).normalized()
    n = (E0 - S).cross(K0 - S)
    w = n.normalized().cross(t).normalized()
    if w.dot(E0 - S) < 0:
        w = -w
    c = (a * a + d * d - b * b) / (2 * a * d)
    E = S + a * (c * t + math.sqrt(max(0.0, 1 - c * c)) * w)
    return E, S + d * t, d != d0


def _lock(order, par, poses, patch):
    """LOCK on a dense closed loop; returns (poses, report). Bone names are the game's."""
    n = len(poses) - 1                      # keys in the period (last = first)
    chains = {}
    for hoof in patch:
        S = hoof[-2:]
        if hoof.startswith("Front"):
            chains[hoof] = ("FrontUpperArm" + S, "FrontForearm" + S, "FrontCannon" + S)
        else:
            chains[hoof] = ("HindThigh" + S, "HindShin" + S, "HindCannon" + S)
    h = {f: np.array([_low(poses[j][f], patch[f]) for j in range(n)]) for f in patch}
    ymid = {f: np.array([float(np.mean([(poses[j][f] @ p).y for p in patch[f]])) for j in range(n)]) for f in patch}
    down_run = {}
    for f in patch:
        # within stance_m of its lowest, or of the ground where the interpolation dips the hoof under it
        down = h[f] <= max(float(h[f].min()), 0.0) + LOCK["stance_m"]
        j0 = int(np.argmin(h[f]))
        a = j0
        while down[(a - 1) % n] and (j0 - a) < n - 1:
            a -= 1
        b = j0
        while down[(b + 1) % n] and (b - a) < n - 1:
            b += 1
        down_run[f] = (a, b)                 # inclusive, may run below 0 (cyclic)
    speeds = []
    for f, (a, b) in down_run.items():
        if f.startswith("Hind"):
            speeds += [ymid[f][(j + 1) % n] - ymid[f][j % n] for j in range(a, b)]
    v = float(np.median(speeds))             # model m per key, +Y = backward (the horse faces -Y)

    # off[f][m, j]: how far (largest sole point) the hoof held at key m's pose, set on the ground and
    # carried back at v, lies from its own pose at key j
    off = {}
    for f in patch:
        pts = np.array([[(poses[j][f] @ p)[:] for p in patch[f]] for j in range(n)])      # n, k, 3
        ref = pts.copy()
        ref[:, :, 2] -= pts[:, :, 2].min(axis=1, keepdims=True)
        dj = np.arange(n)[None, :] - np.arange(n)[:, None]                                  # j - m
        dj = (dj + n // 2) % n - n // 2
        moved = ref[:, None, :, :] + np.stack([np.zeros_like(dj), v * dj, np.zeros_like(dj)], -1)[:, :, None, :]
        off[f] = np.linalg.norm(moved - pts[None, :, :, :], axis=-1).max(-1)                # n, n

    def cost(f, s0, e0):
        jm = (s0 + e0) // 2
        return float(max(off[f][jm % n, j % n] for j in range(s0, e0 + 1)))
    stance = {}
    for f, (a, b) in down_run.items():
        best = None
        for length in range(b - a + 1, LOCK["min_keys"] - 1, -1):
            c, s0 = min((cost(f, s0, s0 + length - 1), s0) for s0 in range(a, b - length + 2))
            if c <= LOCK["max_offset_m"] or length == LOCK["min_keys"]:
                best = (s0, s0 + length - 1)
                break
        stance[f] = best
    rep = {"speed_m_per_key": round(v, 6), "stride_m": round(v * n, 4), "hooves": {}}
    target = {f: {} for f in patch}
    for f, (a, b) in stance.items():
        jm = (a + b) // 2
        ref = poses[jm % n][f].copy()
        ref = Matrix.Translation((0, 0, -_low(ref, patch[f]))) @ ref
        for j in range(a, b + 1):
            target[f][j % n] = Matrix.Translation((0, v * (j - jm), 0)) @ ref
        E = LOCK["ease"]
        for side, edge, step in (("out", b, 1), ("in", a, -1)):
            D = target[f][edge % n] @ poses[edge % n][f].inverted()
            dl, dq, _ = D.decompose()
            for k in range(1, E + 1):
                j = (edge + step * k) % n
                if any(j == (x % n) for x in range(a, b + 1)):
                    break
                w = 1 - k / (E + 1)
                w = w * w * (3 - 2 * w)
                blend = Matrix.LocRotScale(Vector((0, 0, 0)).lerp(dl, w),
                                           Matrix.Identity(3).to_quaternion().slerp(dq, w), Vector((1, 1, 1)))
                t = blend @ poses[j][f]
                if j in target[f]:          # both eases reach this key: average them
                    t0 = target[f][j]
                    t = Matrix.LocRotScale(t0.translation.lerp(t.translation, 0.5),
                                           t0.to_quaternion().slerp(t.to_quaternion(), 0.5), Vector((1, 1, 1)))
                lift = _low(t, patch[f])
                if lift < 0:                # an eased hoof never dips under the ground
                    t = Matrix.Translation((0, 0, -lift)) @ t
                target[f][j] = t
        locked = {x % n for x in range(a, b + 1)}
        for j in range(n):                  # off the stance: clear of the ground, ramping up from its edges
            if j in locked:
                continue
            d = min(min((j - x) % n, (x - j) % n) for x in (a % n, b % n))
            need = min(LOCK["clear_m"], LOCK["ramp_m"] * d)
            t = target[f].get(j, poses[j][f])
            low = _low(t, patch[f])
            if low < need:
                target[f][j] = Matrix.Translation((0, 0, need - low)) @ t
        rep["hooves"][f] = {"stance_keys": [a % n, b % n], "low_keys": [down_run[f][0] % n, down_run[f][1] % n], "duty": round((b - a + 1) / n, 3),
                            "source_lowest_m": round(float(h[f].min()), 4),
                            "max_offset_m": round(max((target[f][j].translation - poses[j][f].translation).length
                                                      for j in target[f]), 4), "clamped": 0}
    out = []
    for j in range(n):
        P = poses[j]
        loc = _locals(order, par, P)
        over = {}
        for f, (U, F, C) in chains.items():
            if j not in target[f]:
                continue
            Ht = target[f][j]
            Ct = Ht @ P[f].inverted() @ P[C]
            E, K, clamped = _two_bone(P[U].translation, P[F].translation, P[C].translation, Ct.translation)
            rep["hooves"][f]["clamped"] += int(clamped)
            S0 = P[U].translation
            R1 = (P[F].translation - S0).rotation_difference(E - S0)
            U1 = _rot_about(S0, R1) @ P[U]
            F1 = _rot_about(S0, R1) @ P[F]
            K1 = _rot_about(S0, R1) @ P[C].translation
            R2 = (K1 - E).rotation_difference(K - E)
            F2 = _rot_about(E, R2) @ F1
            Ct.translation = K
            # the hoof keeps its native pastern on the cannon (= the target unless the reach was clamped)
            over.update({U: U1, F: F2, C: Ct, f: Ct @ (P[C].inverted() @ P[f])})
        out.append(_fk(order, par, loc, over))
    out.append({k: m.copy() for k, m in out[0].items()})
    # after: planted slide (key to key, the lowest sole points' travel against the run) and lowest points
    for f, (a, b) in stance.items():
        slide = 0.0
        for j in range(a, b):
            p0 = [out[j % n][f] @ p for p in patch[f]]
            p1 = [out[(j + 1) % n][f] @ p for p in patch[f]]
            slide = max(slide, max(((q - p) - Vector((0, v, 0))).length for p, q in zip(p0, p1)))
        r = rep["hooves"][f]
        r["planted_slide_mm_per_key"] = round(slide * 1000, 3)
        r["lowest_m"] = round(min(_low(out[j][f], patch[f]) for j in range(n)), 4)
    return out, rep


def _key(rig, par, poses, game, step=1.0):
    """One action `game` keyed from frame 0, every bone, every `step` frames (fcurves written whole, LINEAR:
    the exporter writes these keys as they are, so MARCH keeps its DENSE keys)."""
    rig.animation_data_create()
    act = bpy.data.actions.new(game)
    rig.animation_data.action = act
    n = len(poses)
    for pb in rig.pose.bones:
        name = pb.name
        rest = pb.bone.matrix_local
        p = par[name]
        rel = (pb.parent.bone.matrix_local.inverted() @ rest) if p else rest
        loc, rot, scl = [], [], []
        prev = None
        for pose in poses:
            local = pose[p].inverted() @ pose[name] if p else pose[name]
            basis = rel.inverted() @ local
            l, q, s = basis.decompose()
            if prev is not None and prev.dot(q) < 0:
                q.negate()
            prev = q
            loc.append(l); rot.append(q); scl.append(s)
        for path, vals, width in (("location", loc, 3), ("rotation_quaternion", rot, 4), ("scale", scl, 3)):
            for i in range(width):
                fc = act.fcurve_ensure_for_datablock(rig, 'pose.bones["%s"].%s' % (name, path), index=i,
                                                     group_name=name)
                fc.keyframe_points.add(n)
                co = np.empty(2 * n)
                co[0::2] = np.arange(n) * step
                co[1::2] = [v[i] for v in vals]
                fc.keyframe_points.foreach_set("co", co)
                fc.keyframe_points[0].interpolation = "LINEAR"
                lin = np.zeros(n, dtype=np.int32)
                fc.keyframe_points.foreach_get("interpolation", lin)
                fc.keyframe_points.foreach_set("interpolation", np.full(n, lin[0], dtype=np.int32))
                fc.update()
    track = rig.animation_data.nla_tracks.new()
    track.name = game
    strip = track.strips.new(game, 0, act)
    strip.action_slot = act.slots[0]
    rig.animation_data.action = None


def _transplant(shipped, dense):
    """Every MARCH channel of `shipped` takes `dense`'s keys (same rig, same channel set, same length)."""
    spec = importlib.util.spec_from_file_location("archer_march_transplant",
                                                  Path(__file__).resolve().parents[1] / "archer_arp/march_transplant.py")
    gm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm)
    gl, binary = gm.read(shipped.read_bytes())
    egl, ebin = gm.read(dense.read_bytes())
    mine, theirs = gm.channels(gl, binary), gm.channels(egl, ebin)
    assert set(mine) == set(theirs), sorted(set(mine) ^ set(theirs))
    times = {theirs[k][1].tobytes() for k in theirs}
    assert len(times) == 1, "dense MARCH channels do not share one key list"
    etimes = next(iter(theirs.values()))[1]
    end = float(next(iter(mine.values()))[1][-1, 0])
    assert abs(float(etimes[0, 0])) < 1e-6 and abs(float(etimes[-1, 0]) - end) < 1e-5, (etimes[-1, 0], end)

    def append(values, like):
        nonlocal binary
        binary += b"\0" * (-len(binary) % 4)
        data = np.ascontiguousarray(values, "<f4").tobytes()
        gl["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary += data
        a = {k: v for k, v in like.items() if k not in ("bufferView", "byteOffset", "min", "max", "count")}
        a.update({"bufferView": len(gl["bufferViews"]) - 1, "count": int(values.shape[0])})
        if values.shape[1] == 1:
            a.update({"min": [float(values.min())], "max": [float(values.max())]})
        gl["accessors"].append(a)
        return len(gl["accessors"]) - 1
    shared = None
    for key in sorted(mine):
        sampler, _, _ = mine[key]
        if shared is None:
            shared = append(etimes, gl["accessors"][sampler["input"]])
        sampler["input"] = shared
        sampler["output"] = append(theirs[key][2], gl["accessors"][sampler["output"]])
        sampler["interpolation"] = "LINEAR"
    gl["buffers"][0]["byteLength"] = len(binary) + (-len(binary) % 4)
    shipped.write_bytes(gm.write(gl, binary))
    return {"channels": len(mine), "keys": int(etimes.shape[0])}


def install(root):
    out = Path(root) / "assets/3D/units/commander"
    out.mkdir(parents=True, exist_ok=True)
    report = {}
    order, par, src = _bones()
    K, H = bpy.data.objects["rig"], bpy.data.objects["horse_rig"]
    report["bbone_segments"] = {n: r.data.bones[b].bbone_segments for n, (r, b) in src.items()
                                if r.data.bones[b].bbone_segments > 1}
    # decimate in the bind pose (the armature off), before anything is posed
    use(REST[0]); _frame(REST[1])
    knight = _body(report)
    banner, cloth_index = _banner(report)
    use(REST[0]); _frame(REST[1]); bpy.context.view_layer.update()
    rest = _pose(order, src)
    rig = _skeleton(order, par, rest, src)
    body, mat = _mesh(rig, knight, banner, cloth_index)
    report["files"] = _atlases(mat, out)
    # each hoof's patch for the stride: its vertices weighted > 0.8 on it, within 5 mm of its lowest
    me = body.data
    gi = {g.index: g.name for g in body.vertex_groups}
    patch = {}
    for hoof in [n for n in order if "Hoof" in n]:
        pts = []
        for v in me.vertices:
            if any(gi[g.group] == hoof and g.weight > 0.8 for g in v.groups):
                pts.append(v.co.copy())
        lo = min(p.z for p in pts)
        patch[hoof] = [rest[hoof].inverted() @ p for p in pts if p.z <= lo + 0.005]
    report["clips"] = {}
    for game in GAME:
        poses, info = _poses(order, src, game)
        if game == "MARCH":
            dense = _dense(order, par, poses)
            report["march_before"] = {f: round(min(_low(p[f], patch[f]) for p in dense), 4) for f in patch}
            poses, report["march"] = _lock(order, par, dense, patch)
            _key(rig, par, poses[::DENSE], game)   # the 30 fps clip; its dense keys are transplanted
            dense_march = poses
            info["keys"] = len(poses)
        else:
            _key(rig, par, poses, game)
        report["clips"][game] = info
    rig.rotation_euler.z = math.pi           # Blender -Y -> glTF +Z; the game's figures face -Z
    bpy.context.view_layer.update()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True); body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    kw = dict(export_format="GLB", use_selection=True, export_yup=True, export_skins=True,
              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
              export_def_bones=False, export_optimize_animation_size=False, export_image_format="JPEG",
              export_jpeg_quality=92)
    bpy.ops.export_scene.gltf(filepath=str(out / (NAME + ".glb")), **kw)
    # MARCH's DENSE keys: the same rig with MARCH alone, keyed a frame a key at DENSE x the fps, its
    # channels moved into the shipped GLB (the exporter samples at the scene's fps)
    for t in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(t)
    _key(rig, par, dense_march, "MARCH")
    scn = bpy.context.scene
    fps = scn.render.fps
    scn.render.fps = fps * DENSE
    tmp = Path(tempfile.mkdtemp()) / (NAME + "_march_dense.glb")
    try:
        bpy.ops.export_scene.gltf(filepath=str(tmp), **{**kw, "export_image_format": "NONE"})
    finally:
        scn.render.fps = fps
    report["march"]["transplant"] = _transplant(out / (NAME + ".glb"), tmp)
    tmp.unlink(); tmp.parent.rmdir()
    me.calc_loop_triangles()
    lo = min(v.co.z for v in me.vertices); hi = max(v.co.z for v in me.vertices)
    report.update(tris=len(me.loop_triangles), verts=len(me.vertices), bones=len(rig.data.bones),
                  height_m=round(hi - lo, 3), bone_parents={n: par[n] for n in order})
    return report


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = install(argv[0])
    text = json.dumps(result, indent=1, default=str)
    if len(argv) > 1:
        Path(argv[1]).write_text(text)
    print("COMMANDER_EXPORT", text[:3000])
