"""Phase 6/7: the courier and its two clips to one glTF (the archers' export): each clip on its own NLA
track named for it, the debug colour layers dropped, the rig in its rest pose, Blender -Y forward
(install.py turns it to face the pieces' way). Exec after the courier_rig files."""
CLIP_NAMES = ("GALLOP", "IDLE")
OUT_GLB = SRC + "courier_rigged.glb"


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
        act = bpy.data.actions[CLIP_PREFIX + n]
        tr = ad.nla_tracks.new()
        tr.name = n
        st = tr.strips.new(n, int(act.frame_range[0]), act)
        st.name = n
    reset(a)
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    a.hide_set(False); o.hide_set(False)
    a.select_set(True); o.select_set(True)
    bpy.context.view_layer.objects.active = a
    sc = bpy.context.scene
    sc.render.fps = FPS
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_def_bones=False, export_force_sampling=True, export_frame_step=1,
                              export_anim_single_armature=True, export_reset_pose_bones=True)
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
            "attrs": sorted(prims[0]["attributes"]), "images": [im.get("name") for im in j.get("images", [])],
            "anims": {an["name"]: round(max(acc[s["input"]]["max"][0] for s in an["samplers"]) * FPS)
                      for an in j.get("animations", [])},
            "MB": round(len(data) / 1e6, 1)}
