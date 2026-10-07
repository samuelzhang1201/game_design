"""Phase 6/7: the archer and its five clips to one glTF: each clip on its own NLA track named for
its action (the runtime finds a clip by the end of its name: MARCH, GARRISON, ATTACK, DEFEND,
STANDBY), the debug colour layers dropped, the rig in its rest pose, Blender -Y forward (the
installer turns it to face the pieces' way)."""
CLIP_NAMES = ("MARCH", "GARRISON", "ATTACK", "DEFEND", "STANDBY")
OUT_GLB = SRC + "archer_rigged.glb"


def export(path=None):
    path = path or OUT_GLB
    a, o = rig(), mesh()
    for n in [c.name for c in o.data.color_attributes]:
        o.data.color_attributes.remove(o.data.color_attributes[n])
    ad = a.animation_data or a.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for n in CLIP_NAMES:
        act = bpy.data.actions["archer_" + n]
        tr = ad.nla_tracks.new()
        tr.name = n
        st = tr.strips.new(n, int(act.frame_range[0]), act)
        st.name = n
    reset(a)
    hidden = [(x, x.hide_get()) for x in (a, o)]
    for x, _ in hidden:                 # a hidden object cannot be selected: the export would drop it
        x.hide_set(False)
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    a.select_set(True); o.select_set(True)
    bpy.context.view_layer.objects.active = a
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_def_bones=False, export_force_sampling=True, export_frame_step=1,
                              export_anim_single_armature=True, export_reset_pose_bones=True)
    for x, h in hidden:
        x.hide_set(h)
    return path


def glb_summary(path=None):
    import json, struct
    data = open(path or OUT_GLB, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    acc = j["accessors"]
    prims = [p for m in j["meshes"] for p in m["primitives"]]
    return {"meshes": len(j["meshes"]), "skins": len(j.get("skins", [])), "joints": len(j["skins"][0]["joints"]),
            "tris": sum(acc[p["indices"]]["count"] // 3 for p in prims),
            "attrs": sorted(prims[0]["attributes"]), "images": len(j.get("images", [])),
            "anims": {an["name"]: round(max(acc[s["input"]]["max"][0] for s in an["samplers"]) * 30) for an in j.get("animations", [])},
            "MB": round(len(data) / 1e6, 1)}
