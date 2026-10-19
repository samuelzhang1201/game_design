"""Install build: the ARP knight as THE infantry piece (docs/superpowers/specs/2026-10-19-infantry-arp-knight-design.md).

exec() in the owner's Blender with soldier_knight_arp.blend open, then install(ROOT) with ROOT the
checkout to write into. Works on copies; reopen the saved blend afterwards (nothing is saved).

What the map needs of the knight's GLB (a plain export of the rig does not give it):
- the node names infantry.tscn overrides: armature `inf_rig`, one skinned mesh `infantry`;
- ONE material on a 2048 atlas whose files keep the infantry's names
  (`infantry_infantry_atlas{,_mr,_n}.jpg`): the body in the lower-left 3/4, the sword and the shield
  in the right-hand strip; the gear merged into the mesh, wholly on its socket bone;
- rest = the guard stance (GARRISON's first frame): the map sizes a piece from its rest mesh;
- the looping clips closed (last frame = first), ATTACK_VAR1's lunge taken out (in place);
- the measured `stride_m` and `steps` of the MARCH for army_art.csv (returned).
"""
import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

GAME = {"WALK": "MARCH", "IDLE": "GARRISON", "ATTACK": "ATTACK", "SLASH": "SLASH",
        "ATTACK_VAR1": "ATTACK_VAR1"}
LOOPS = {"WALK", "IDLE"}
IN_PLACE = {"ATTACK_VAR1"}
REST = ("IDLE", 1)                       # the guard stance, GARRISON's first frame
RENAME = {"head.x": "head"}
ATLAS = 2048
# (u0, v0, du, dv) of each part in the atlas, v up as in Blender's UVs and image rows
REGION = {"body": (0.0, 0.0, 0.75, 0.75), "sword": (0.75, 0.0, 0.25, 0.5),
          "shield": (0.75, 0.5, 0.25, 0.5)}
SOCKET = {"sword": "cc_weapon.r", "shield": "cc_weapon.l"}
SEAM_FRAMES = 6                          # a loop's last frames blended to its first
# The game atlas's metallic (B) as a share of the authored map: on the map's light a near-pure metal
# mirrors the dark ground and woods round it and reads black; x0.45 keeps the steel lit grey with
# its sheen (bracketed x0.3 / x0.45 / x0.6 in real-window shots, 2026-10-19; the old knight sat at 0.27).
GAME_METAL = 0.45
# The shield's wood weathered in the game atlas (saturation share, value share): the Tripo wood is
# new, bright orange, the archers' tabard and the roof tiles' hue, so infantry and archers stopped
# parting at a glance (critic 2026-10-19); bracketed (0.55, 0.8) / (0.35, 0.68), the darker sank
# into the mail.
SHIELD_TONE = (0.55, 0.8)


def _set_action(rig, name):
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    return act


def _keep(src):
    keep = [b.name for b in src.data.bones if b.use_deform] + ["cc_weapon.l", "cc_weapon.r"]
    parents = {}
    for n in keep:
        p = src.data.bones[n].parent
        while p and p.name not in keep:
            p = p.parent
        parents[n] = p.name if p else None
    return keep, parents


def _skeleton(src, keep, parents, rest):
    data = bpy.data.armatures.new("inf_rig")
    rig = bpy.data.objects.new("inf_rig", data)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for n in keep:
        b = data.edit_bones.new(RENAME.get(n, n))
        b.length = max(src.data.bones[n].length, 0.02)
        b.matrix = rest[n]
        b.use_deform = not n.startswith("cc_weapon")
    for n, p in parents.items():
        if p:
            data.edit_bones[RENAME.get(n, n)].parent = data.edit_bones[RENAME.get(p, p)]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


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


def _mesh(src, rig):
    """The body posed into the rest pose (its armature applied), the gear set where it hangs."""
    vl = bpy.context.view_layer
    body0 = bpy.data.objects["Soldier_body"]
    body = body0.copy(); body.data = body0.data.copy()
    bpy.context.scene.collection.objects.link(body)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True); vl.objects.active = body
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    _region_uv(body, "body")
    parts = [body]
    for part, name in (("sword", "Sword"), ("shield", "Shield")):
        g0 = bpy.data.objects[name]
        g = g0.copy(); g.data = g0.data.copy()
        bpy.context.scene.collection.objects.link(g)
        mw = g0.matrix_world.copy()
        g.parent = None
        g.data.transform(mw)
        g.matrix_world = Matrix.Identity(4)
        g.vertex_groups.clear()
        g.vertex_groups.new(name=SOCKET[part]).add(range(len(g.data.vertices)), 1.0, "REPLACE")
        _region_uv(g, part)
        parts.append(g)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    vl.objects.active = body
    bpy.ops.object.join()
    body.name = "infantry"; body.data.name = "infantry"
    for old, new in RENAME.items():
        if old in body.vertex_groups:
            body.vertex_groups[old].name = new
    mat = bpy.data.materials.new("infantry_atlas_mat")
    body.data.materials.clear()
    body.data.materials.append(mat)
    for p in body.data.polygons:
        p.material_index = 0
    body.modifiers.clear()
    m = body.modifiers.new("Skin", "ARMATURE"); m.object = rig
    body.parent = rig
    body.matrix_parent_inverse.identity()
    return body, mat


def _pixels(img, w, h):
    c = img.copy(); c.scale(w, h)
    a = np.array(c.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(c)
    return a


def _atlases(mat, out_dir):
    """Colour, metal-rough (G roughness, B metallic) and normal atlases, written as the infantry's
    files and wired into the one material (the GLB embeds them; the scene's override uses the files)."""
    def src(name, label):
        m = bpy.data.objects[name].data.materials[0]
        return next(n.image for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.label == label)
    sources = {
        "albedo": {"body": src("Soldier_body", "BASE COLOR"), "sword": src("Sword", "BASE COLOR"),
                   "shield": src("Shield", "BASE COLOR")},
        "mr": {"body": src("Soldier_body", "metal_rough"), "sword": src("Sword", "METALLIC ROUGHNESS"),
               "shield": src("Shield", "METALLIC ROUGHNESS")},
        "n": {"body": None, "sword": src("Sword", "NORMAL MAP"), "shield": src("Shield", "NORMAL MAP")},
    }
    files = {}
    for kind, parts in sources.items():
        atlas = np.zeros((ATLAS, ATLAS, 4), np.float32)
        atlas[..., 3] = 1
        if kind == "n":
            atlas[..., :3] = (0.5, 0.5, 1.0)
        for part, img in parts.items():
            u0, v0, du, dv = REGION[part]
            w, h = int(du * ATLAS), int(dv * ATLAS)
            x, y = int(u0 * ATLAS), int(v0 * ATLAS)
            if img is not None:
                atlas[y:y + h, x:x + w] = _pixels(img, w, h)
            if kind == "albedo" and part == "shield":
                r = atlas[y:y + h, x:x + w, :3]
                lum = r.mean(2, keepdims=True)
                atlas[y:y + h, x:x + w, :3] = (lum + (r - lum) * SHIELD_TONE[0]) * SHIELD_TONE[1]
        if kind == "mr":
            atlas[..., 2] *= GAME_METAL
        # the image is named as the old GLB named it; Godot extracts it beside the .glb as
        # "<glb>_<image>" = the infantry_infantry_atlas*.jpg the scene's material reads (and never
        # overwrites them: this build writes those files itself)
        name = "infantry_atlas" + ("" if kind == "albedo" else "_" + kind)
        im = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
        if kind != "albedo":
            im.colorspace_settings.name = "Non-Color"
        im.pixels.foreach_set(atlas.ravel())
        path = str(Path(out_dir) / ("infantry_" + name + ".jpg"))
        im.filepath_raw = path
        im.file_format = "JPEG"
        bpy.context.scene.render.image_settings.quality = 92
        im.save(filepath=path, quality=92)
        im.pack()                                # the exporter names an image by its FILE: give it
        im.filepath_raw = name + ".jpg"          # the old GLB's name, read from the packed copy
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
    return {k: str(Path(out_dir) / ("infantry_" + v.name + ".jpg")) for k, v in files.items()}


def _poses(src, keep, clip):
    scn = bpy.context.scene
    act = _set_action(src, clip)
    f0, f1 = map(int, act.frame_range)
    poses = []
    for f in range(f0, f1 + 1):
        scn.frame_set(f)
        poses.append({n: src.pose.bones[n].matrix.copy() for n in keep})
    if clip in IN_PLACE:
        travel = poses[-1]["root.x"].translation - poses[0]["root.x"].translation
        travel.z = 0.0
        for i, p in enumerate(poses):
            shift = travel * (i / (len(poses) - 1))
            for m in p.values():
                m.translation -= shift
    if clip in LOOPS:
        n = len(poses)
        for k in range(SEAM_FRAMES):
            i = n - SEAM_FRAMES + k
            w = (k + 1) / SEAM_FRAMES
            poses[i] = {b: m.lerp(poses[0][b], w) for b, m in poses[i].items()}
    return poses


def _key(rig, keep, poses, game):
    rig.animation_data_create()
    act = bpy.data.actions.new("game_" + game)
    rig.animation_data.action = act
    for frame, pose in enumerate(poses, 1):
        for pb in rig.pose.bones:
            src_name = next(k for k in keep if RENAME.get(k, k) == pb.name)
            rest = pb.bone.matrix_local
            if pb.parent:
                psrc = next(k for k in keep if RENAME.get(k, k) == pb.parent.name)
                rel = pb.parent.bone.matrix_local.inverted() @ rest
                pb.matrix_basis = rel.inverted() @ pose[psrc].inverted() @ pose[src_name]
            else:
                pb.matrix_basis = rest.inverted() @ pose[src_name]
            for path in ("location", "rotation_quaternion", "scale"):
                pb.keyframe_insert(path, frame=frame, group=pb.name)
    track = rig.animation_data.nla_tracks.new()
    track.name = game
    track.strips.new(game, 1, act)
    rig.animation_data.action = None


def _march_measure(src, poses, keep):
    """stride_m: the planted foot's travel per frame (median, model metres) times the loop's frames;
    steps: the shares where a foot comes down (its height reaches the ground band)."""
    z = {s: np.array([p["foot" + s].translation.z for p in poses]) for s in (".l", ".r")}
    y = {s: np.array([p["foot" + s].translation.y for p in poses]) for s in (".l", ".r")}
    n = len(poses)
    planted, steps = [], []
    for s in (".l", ".r"):
        lo = z[s].min()
        down = z[s] < lo + 0.012
        for i in range(1, n):
            if down[i] and down[i - 1]:
                planted.append(abs(y[s][i] - y[s][i - 1]))
            if down[i] and not down[i - 1]:
                steps.append(round((i) / (n - 1), 2))
    return {"stride_m": round(float(np.median(planted)) * (n - 1), 3), "steps": sorted(steps),
            "frames": n}


def install(root):
    root = Path(root)
    out = root / "assets/3D/units/infantry"
    scn = bpy.context.scene
    src = bpy.data.objects["rig"]
    keep, parents = _keep(src)
    _set_action(src, REST[0]); scn.frame_set(REST[1]); bpy.context.view_layer.update()
    rest = {n: src.pose.bones[n].matrix.copy() for n in keep}
    rig = _skeleton(src, keep, parents, rest)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    _set_action(src, REST[0]); scn.frame_set(REST[1]); bpy.context.view_layer.update()
    body, mat = _mesh(src, rig)
    files = _atlases(mat, out)
    info = {"files": files, "clips": {}}
    for clip, game in GAME.items():
        poses = _poses(src, keep, clip)
        _key(rig, keep, poses, game)
        info["clips"][game] = {"source": clip, "frames": len(poses),
                               "loop": clip in LOOPS, "in_place": clip in IN_PLACE}
        if clip == "WALK":
            info["march"] = _march_measure(src, poses, keep)
    rig.rotation_euler.z = math.pi           # Blender -Y -> glTF +Z; the game's figures face -Z
    bpy.context.view_layer.update()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True); body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(out / "infantry.glb"), export_format="GLB", use_selection=True,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_def_bones=False, export_optimize_animation_size=False,
                              export_image_format="JPEG", export_jpeg_quality=92)
    me = body.data
    me.calc_loop_triangles()
    lo = min(v.co.z for v in me.vertices); hi = max(v.co.z for v in me.vertices)
    info.update(tris=len(me.loop_triangles), bones=len(rig.data.bones), height_m=round(hi - lo, 3))
    return info
