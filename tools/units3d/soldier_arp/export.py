"""Export the ARP knight as game GLBs: a constraint-free skeleton (the 67 deform bones + the
cc_weapon.l/.r sockets), the skinned body with its colour + metal/rough maps, five clips, and the
sword and shield (as children of their sockets, and as their own GLBs in the socket frame).

exec() in the owner's Blender with soldier_knight_arp.blend open, then export_all(). Works on
copies; reopen the saved blend afterwards (nothing is saved here).
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix

OUT = Path("/Users/samuelzhang/game_design/assets/3D/units/soldier/model_wip/arp_knight_20261018/export")
CLIPS = ("WALK", "IDLE", "SLASH", "ATTACK", "ATTACK_VAR1")
SOCKETS = ("cc_weapon.l", "cc_weapon.r")
RENAME = {"head.x": "head"}            # the public head name the map's units read
MAX_TEX = 2048


def _keep(src):
    keep = [b.name for b in src.data.bones if b.use_deform] + list(SOCKETS)
    parents = {}
    for n in keep:
        p = src.data.bones[n].parent
        while p and p.name not in keep:
            p = p.parent
        parents[n] = p.name if p else None
    return keep, parents


def _skeleton(src, keep, parents):
    data = bpy.data.armatures.new("soldier_knight_skeleton")
    rig = bpy.data.objects.new("soldier_knight_rig", data)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for n in keep:
        b = data.edit_bones.new(RENAME.get(n, n))
        b.length = max(src.data.bones[n].length, 0.02)
        b.matrix = src.data.bones[n].matrix_local
        b.use_deform = n not in SOCKETS
    for n, p in parents.items():
        if p:
            data.edit_bones[RENAME.get(n, n)].parent = data.edit_bones[RENAME.get(p, p)]
    bpy.ops.object.mode_set(mode="OBJECT")
    err = max(abs(data.bones[RENAME.get(n, n)].matrix_local[i][j] - src.data.bones[n].matrix_local[i][j])
              for n in keep for i in range(4) for j in range(4))
    assert err < 1e-4, ("rest changed", err)
    return rig


def _bake(src, rig, keep):
    scn = bpy.context.scene
    rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    info = {}
    for clip in CLIPS:
        act = bpy.data.actions[clip]
        src.animation_data.action = act
        src.animation_data.action_slot = act.slots[0]
        f0, f1 = map(int, act.frame_range)
        out = bpy.data.actions.new("game_" + clip)
        rig.animation_data.action = out
        for f in range(f0, f1 + 1):
            scn.frame_set(f)
            pose = {RENAME.get(n, n): src.pose.bones[n].matrix.copy() for n in keep}
            for pb in rig.pose.bones:       # armature-space pose -> local basis, no depsgraph round trips
                rest = pb.bone.matrix_local
                if pb.parent:
                    rel = pb.parent.bone.matrix_local.inverted() @ rest
                    pb.matrix_basis = rel.inverted() @ pose[pb.parent.name].inverted() @ pose[pb.name]
                else:
                    pb.matrix_basis = rest.inverted() @ pose[pb.name]
            for pb in rig.pose.bones:
                for path in ("location", "rotation_quaternion", "scale"):
                    pb.keyframe_insert(path, frame=f - f0 + 1, group=pb.name)
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        track.strips.new(clip, 1, out)
        info[clip] = {"frames": f1 - f0 + 1, "seconds": round((f1 - f0) / scn.render.fps, 3)}
    rig.animation_data.action = None
    return info


def _err(src, rig, keep):
    """Largest bone-head distance between the ARP rig and the baked one over every clip frame."""
    scn = bpy.context.scene
    worst = 0.0
    for clip in CLIPS:
        act = bpy.data.actions[clip]
        src.animation_data.action = act
        src.animation_data.action_slot = act.slots[0]
        for tr in rig.animation_data.nla_tracks:
            tr.mute = tr.name != clip
        f0, f1 = map(int, act.frame_range)
        for f in range(f0, f1 + 1, 5):      # every clip starts at frame 1, as its NLA strip does
            scn.frame_set(f)
            got = {pb.name: pb.head.copy() for pb in rig.pose.bones}
            for n in keep:
                worst = max(worst, (src.pose.bones[n].head - got[RENAME.get(n, n)]).length)
    for tr in rig.animation_data.nla_tracks:
        tr.mute = False
    return worst


def _body(src_body, rig):
    body = src_body.copy()
    body.data = src_body.data.copy()
    bpy.context.scene.collection.objects.link(body)
    body.name = "soldier_knight"
    body.animation_data_clear()
    for old, new in RENAME.items():
        if old in body.vertex_groups:
            body.vertex_groups[old].name = new
    body.parent = rig
    body.matrix_parent_inverse.identity()
    body.matrix_world = Matrix.Identity(4)
    body.modifiers.clear()
    m = body.modifiers.new("Skin", "ARMATURE")
    m.object = rig
    m.use_deform_preserve_volume = False      # glTF / Godot skin linearly
    mat = body.data.materials[0].copy()
    body.data.materials[0] = mat
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > MAX_TEX:
            img = n.image.copy()
            img.scale(MAX_TEX, MAX_TEX)
            n.image = img
    return body


def _gear(src, src_gear, rig, socket, name):
    g = src_gear.copy()
    g.data = src_gear.data.copy()
    bpy.context.scene.collection.objects.link(g)
    g.name = name
    bpy.context.view_layer.update()
    bone = rig.data.bones[socket]
    # the gear's frame relative to the socket at rest -> baked into the mesh, so the gear GLB's
    # origin IS the socket: a Godot BoneAttachment3D on cc_weapon.* takes it with no offset
    # measured against the SOURCE socket in its current pose (the gear sits in the posed hand)
    local = (src.matrix_world @ src.pose.bones[socket].matrix).inverted() @ src_gear.matrix_world
    g.parent = None
    g.matrix_world = Matrix.Identity(4)
    g.data.transform(local)
    g.parent = rig
    g.parent_type = "BONE"
    g.parent_bone = socket
    bpy.context.view_layer.update()
    # on the socket as it stands NOW (the rig is posed): the node's local transform is identity
    g.matrix_world = rig.matrix_world @ rig.pose.bones[socket].matrix
    return g


def _export(path, objs, animations):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
              export_apply=False, export_skins=True, export_animations=animations)
    if animations:
        kw.update(export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                  export_def_bones=False, export_optimize_animation_size=False)
    bpy.ops.export_scene.gltf(**kw)


def _glb_summary(path):
    import struct
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    skin = j["skins"][0] if j.get("skins") else None
    names = [j["nodes"][i]["name"] for i in skin["joints"]] if skin else []
    return {"kb": len(b) // 1024, "meshes": [m["name"] for m in j["meshes"]],
            "joints": len(names), "sockets": [s for s in SOCKETS if s in names],
            "animations": [a["name"] for a in j.get("animations", [])],
            "images": len(j.get("images", [])),
            "metal_rough": any("metallicRoughnessTexture" in m.get("pbrMetallicRoughness", {})
                               for m in j.get("materials", [])),
            "gear_children": {j["nodes"][c]["name"]: round(sum(abs(x) for x in j["nodes"][c].get("translation", [0, 0, 0])), 5)
                              for i in range(len(j["nodes"])) for c in j["nodes"][i].get("children", [])
                              if j["nodes"][i]["name"] in SOCKETS}}


def export_all():
    OUT.mkdir(parents=True, exist_ok=True)
    src = bpy.data.objects["rig"]
    keep, parents = _keep(src)
    rig = _skeleton(src, keep, parents)
    info = _bake(src, rig, keep)
    info["bake_error_m"] = round(_err(src, rig, keep), 6)
    src.animation_data.action = bpy.data.actions["IDLE"]
    body = _body(bpy.data.objects["Soldier_body"], rig)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    sword = _gear(src, bpy.data.objects["Sword"], rig, "cc_weapon.r", "soldier_knight_sword")
    shield = _gear(src, bpy.data.objects["Shield"], rig, "cc_weapon.l", "soldier_knight_shield")
    rig.rotation_euler.z = math.pi            # Blender -Y -> glTF +Z; the game's figures face -Z
    bpy.context.view_layer.update()
    _export(OUT / "soldier_knight.glb", [rig, body, sword, shield], True)
    # the gear on its own, origin = the socket
    rig.rotation_euler.z = 0
    for g, name in ((sword, "soldier_knight_sword"), (shield, "soldier_knight_shield")):
        solo = g.copy(); solo.data = g.data; bpy.context.scene.collection.objects.link(solo)
        solo.parent = None
        solo.matrix_world = Matrix.Identity(4)
        _export(OUT / (name + ".glb"), [solo], False)
    info["files"] = {p.name: _glb_summary(p) for p in sorted(OUT.glob("*.glb"))}
    (OUT / "export.json").write_text(json.dumps(info, indent=2, ensure_ascii=False) + "\n")
    return info
