"""Hook knight_metal_rough.png (metal_map.py) into the knight's material, and an HDRI world for
previews (metal needs something to reflect). exec() in the owner's Blender."""
import bpy

D = "/Users/samuelzhang/game_design/assets/3D/units/soldier/model_wip/arp_knight_20261018/"
HDRI = "/Applications/Blender.app/Contents/Resources/5.2/datafiles/studiolights/world/"


def apply_metal(body, png=D + "knight_metal_rough.png"):
    mat = body.data.materials[0]
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.label == "metal_rough"), None)
    if tex is None:
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.label = "metal_rough"; tex.location = (-600, -300)
        sep = nt.nodes.new("ShaderNodeSeparateColor"); sep.location = (-300, -300)
        nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    img = bpy.data.images.load(png, check_existing=True)
    img.reload()
    img.colorspace_settings.name = "Non-Color"
    tex.image = img
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat.name


def hdri_world(name="forest.exr", strength=1.0):
    scn = bpy.context.scene
    w = bpy.data.worlds.get("preview_hdri") or bpy.data.worlds.new("preview_hdri")
    w.use_nodes = True
    nt = w.node_tree
    env = next((n for n in nt.nodes if n.type == "TEX_ENVIRONMENT"), None) or nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(HDRI + name, check_existing=True)
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    scn.world = w
    scn.render.film_transparent = False
    return w.name
