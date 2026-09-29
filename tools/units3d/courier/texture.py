"""The courier's bake helpers (tripo.py): the atlas images, a selected-to-active bake into
them, and the one atlas material.

The atlas is ONE 2048 image per map: colour (sRGB), tangent normal and metal-roughness
(G = roughness, B = metal, as the cavalry's), each read by the material below.
"""
import bpy

ATLAS = 2048      # the atlas's side, px
MARGIN = 6        # the bake's margin round each island, px


def activate(ob):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def new_image(name, colour, fill):
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.generated_color = fill
    return img


def target_node(mat, image):
    nt = mat.node_tree
    key = "bake_" + image.name
    node = nt.nodes.get(key)
    if node is None:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.name = key
        node.image = image
    for n in nt.nodes:
        n.select = False
    node.select = True
    nt.nodes.active = node


def bake(low, image, kind, high=None):
    sc = bpy.context.scene
    for m in low.data.materials:
        target_node(m, image)
    activate(low)
    b = sc.render.bake
    b.use_selected_to_active = high is not None
    if high is not None:
        high.select_set(True)
        bpy.context.view_layer.objects.active = low
        b.cage_extrusion = 0.03
        b.max_ray_distance = 0.08
    b.margin = MARGIN
    b.use_clear = False
    b.target = "IMAGE_TEXTURES"
    if kind == "NORMAL":
        b.normal_space = "TANGENT"
    bpy.ops.object.bake(type=kind)


def atlas_material(col, nor, mr):
    mat = bpy.data.materials.new("courier_atlas")
    mat.use_nodes = True
    mat.use_backface_culling = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexImage"); tc.image = col
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = nor
    nm = nt.nodes.new("ShaderNodeNormalMap")
    tm = nt.nodes.new("ShaderNodeTexImage"); tm.image = mr
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat
