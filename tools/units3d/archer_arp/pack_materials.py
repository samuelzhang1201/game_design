"""Keep the authored material response while merging surfaces for formations."""
import bpy


def pack_materials(obj, label):
    originals = list(obj.data.materials)
    if len(originals) < 2:
        return
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.bake.use_clear = True
    scene.render.bake.margin = 8
    for selected in bpy.context.selected_objects:
        selected.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    temporary = []
    for i, material in enumerate(originals):
        material = material.copy()
        obj.data.materials[i] = material
        nodes = material.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        normal = next(n for n in nodes if n.type == "NORMAL_MAP")
        normal_image = normal.inputs["Color"].links[0].from_node
        strength = normal.inputs["Strength"].default_value
        output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
        emission = nodes.new("ShaderNodeEmission")
        emission.inputs["Color"].default_value = (1, bsdf.inputs["Roughness"].default_value,
                                                   bsdf.inputs["Metallic"].default_value, 1)
        material.node_tree.links.new(emission.outputs[0], output.inputs["Surface"])
        target = nodes.new("ShaderNodeTexImage")
        temporary.append((material, emission, target, normal_image, strength))
    images = []
    for role in ("metal_rough", "normal"):
        image = bpy.data.images.new(label + "_" + role, width=2048, height=2048, alpha=False)
        image.colorspace_settings.name = "Non-Color"
        for material, emission, target, normal_image, strength in temporary:
            target.image = image
            material.node_tree.nodes.active = target
            if role == "normal":
                node = material.node_tree.nodes.new("ShaderNodeVectorMath")
                node.operation = "MULTIPLY_ADD"
                node.inputs[1].default_value = (strength, strength, 1)
                node.inputs[2].default_value = ((1-strength)/2, (1-strength)/2, 0)
                material.node_tree.links.new(normal_image.outputs["Color"], node.inputs[0])
                material.node_tree.links.new(node.outputs["Vector"], emission.inputs["Color"])
        assert bpy.ops.object.bake(type="EMIT") == {"FINISHED"}
        image.pack()
        images.append(image)
    material = originals[0].copy()
    material.name = label + "_materials"
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    normal = next(n for n in nodes if n.type == "NORMAL_MAP")
    normal.inputs["Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 1.0
    packed = nodes.new("ShaderNodeTexImage")
    packed.image = images[0]
    separate = nodes.new("ShaderNodeSeparateColor")
    links.new(packed.outputs["Color"], separate.inputs["Color"])
    links.new(separate.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(separate.outputs["Blue"], bsdf.inputs["Metallic"])
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = images[1]
    links.new(texture.outputs["Color"], normal.inputs["Color"])
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
