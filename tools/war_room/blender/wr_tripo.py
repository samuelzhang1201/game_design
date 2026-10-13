# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())

# A Tripo generation (the owner's PAID plan, set private) made game-ready: the
# high mesh is kept as `<name>_hi`, a collapsed copy `<name>` is unwrapped, and
# its colour and normal are baked from the high (Cycles, selected to active) into
# `tex_px` maps — the houses' route, shrunk. Origin at the foot's centre, the
# front toward Blender -y, the lowest point at z 0. Call tripo_build(...) after
# tripo_import(...); wr_furnish.export([name]) writes the .glb (its 1k rule).

INBOX = os.path.dirname(os.path.dirname(os.path.dirname(WR))) + "/../../assets/3D/model_wip/tripo_inbox/war_room"
INBOX = "/Users/samuelzhang/game_design/assets/3D/model_wip/tripo_inbox/war_room"


def tripo_import(name, glb, spin_deg=0.0, width_m=None):
    """Import one Tripo glb as `<name>_hi`, apply its transform, spin it about z
    so its front faces -y, rest it on z 0 centred on x/y, and (optionally) scale
    it to a real width in metres."""
    sc = bpy.data.scenes.get("TripoWR") or bpy.data.scenes.new("TripoWR")
    bpy.context.window.scene = sc
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=INBOX + "/" + name + "/" + glb)
    ob = next(o for o in bpy.data.objects if o not in before and o.type == 'MESH')
    for o in set(bpy.data.objects) - before:
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)
    ob.name = name + "_hi"
    ob.data.name = name + "_hi"
    ob.parent = None
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.rotation_euler = (0, 0, math.radians(spin_deg))
    if width_m:
        s = width_m / max(ob.dimensions.x, ob.dimensions.y)
        ob.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    lo = Vector((min(v.co.x for v in ob.data.vertices), min(v.co.y for v in ob.data.vertices), min(v.co.z for v in ob.data.vertices)))
    hi = Vector((max(v.co.x for v in ob.data.vertices), max(v.co.y for v in ob.data.vertices), max(v.co.z for v in ob.data.vertices)))
    ob.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
    return ob


def _bake_image(name, px, color):
    im = bpy.data.images.get(name)
    if im is not None:
        bpy.data.images.remove(im)
    im = bpy.data.images.new(name, px, px, alpha=False)
    im.colorspace_settings.name = "sRGB" if color else "Non-Color"
    return im


def tripo_build(name, target_tris, tex_px=1024, rough=0.72, cage=0.012, voxel=0.012):
    hi = bpy.data.objects[name + "_hi"]
    hi.hide_set(False)   # a hidden object cannot be selected for the bake
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = name
    lo.data.name = name
    bpy.context.scene.collection.objects.link(lo)
    lo.data.materials.clear()
    for uv in list(lo.data.uv_layers):
        lo.data.uv_layers.remove(uv)
    bpy.ops.object.select_all(action='DESELECT')
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    # Tripo's surface is grain-level noise AND its own UVs are shattered islands: a
    # voxel remesh filters the noise (the bake restores it), the collapse then takes
    # the clean mesh to the budget, and one unwrap makes a few big islands
    rm = lo.modifiers.new("remesh", 'REMESH')
    rm.mode = 'VOXEL'
    rm.voxel_size = voxel
    bpy.ops.object.modifier_apply(modifier="remesh")
    mod = lo.modifiers.new("collapse", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = min(1.0, target_tris / max(len(lo.data.polygons) * 2, 1))   # quads count twice as triangles
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="collapse")
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.uv.smart_project(angle_limit=math.radians(70), island_margin=0.008, area_weight=0.7)
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in lo.data.polygons:
        p.use_smooth = True
    # the low material: first with its two maps NOT linked (a bake target wired into
    # its own material is a circular dependency and bakes nothing), linked after
    m = bpy.data.materials.get("WR_" + name) or bpy.data.materials.new("WR_" + name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0])
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = 0.0
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = _bake_image(name + "_color", tex_px, True)
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = _bake_image(name + "_normal", tex_px, False)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    lo.data.materials.append(m)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 4
    sc.cycles.use_denoising = False
    bk = sc.render.bake
    bk.use_selected_to_active = True
    bk.cage_extrusion = cage
    bk.max_ray_distance = cage * 3
    bk.margin = 6
    bk.use_clear = True
    for kind, node in (("DIFFUSE", tc), ("NORMAL", tn)):
        nt.nodes.active = node
        bpy.ops.object.select_all(action='DESELECT')
        hi.select_set(True)
        lo.select_set(True)
        bpy.context.view_layer.objects.active = lo
        if kind == "DIFFUSE":
            bk.use_pass_direct = False
            bk.use_pass_indirect = False
            bk.use_pass_color = True
        bpy.ops.object.bake(type=kind)
    nt.links.new(tc.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    hi.hide_set(True)
    return tris_of(lo), tuple(round(d, 3) for d in lo.dimensions)
