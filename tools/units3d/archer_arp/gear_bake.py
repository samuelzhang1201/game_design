"""Blender worker for gear_lod.py: exact source rig, surface audit, UVs and bakes."""
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys
import struct
import shutil

import bmesh
import bpy
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
from mathutils import Vector
import numpy as np


def main():
    stage, project, work, variant, quality, source_directory = sys.argv[sys.argv.index("--") + 1:]
    project, work = Path(project), Path(work)
    spec = importlib.util.spec_from_file_location("decikit", quality)
    dk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dk)
    sys.path.insert(0, str(project / "tools"))
    from data_index import table_path
    with open(table_path("archer_gear_lod"), newline="") as file:
        settings = list(csv.DictReader(file))
    report = {}
    for row in settings:
        part = row["part"]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        source = Path(source_directory) / f"archers_{part}.glb"
        bpy.ops.import_scene.gltf(filepath=str(source))
        low = next(o for o in bpy.context.scene.objects if o.type == "MESH")
        raw = dk.snapshot(low, "raw_reference")
        preflight = dk.preflight(low, weld=1e-7)
        if stage == "extract":
            np.savez(work / (part + ".npz"), v=np.array([tuple(v.co) for v in low.data.vertices]),
                     f=np.array([list(f.vertices) for f in low.data.polygons]))
            continue
        reference = dk.snapshot(low, "canonical_reference")
        original_material = raw.data.materials[0]
        rig = next(m.object for m in low.modifiers if m.type == "ARMATURE")
        for modifier in list(low.modifiers):
            low.modifiers.remove(modifier)
        data = np.load(work / variant / (part + ".npz"))
        mesh_name = low.data.name
        low.data.name = "reference_" + mesh_name
        mesh = bpy.data.meshes.new(mesh_name)
        mesh.from_pydata(data["v"], [], data["f"])
        low.data = mesh
        low.vertex_groups.clear()
        names = [g.name for g in raw.vertex_groups]
        groups = [low.vertex_groups.new(name=n) for n in names]
        source_vertices = [v.co for v in raw.data.vertices]
        source_faces = [list(p.vertices) for p in raw.data.polygons]
        tree = BVHTree.FromPolygons(source_vertices, source_faces, all_triangles=True)
        source_weights = []
        for vertex in raw.data.vertices:
            weights = {g.group: g.weight for g in vertex.groups}
            source_weights.append(Vector([weights.get(i, 0.0) for i in range(len(names))] + [0.0] * (3 - len(names))))
        for vertex in mesh.vertices:
            point, _, face, _ = tree.find_nearest(vertex.co)
            ids = source_faces[face]
            weights = barycentric_transform(point, *(source_vertices[i] for i in ids),
                                            *(source_weights[i] for i in ids))
            weights = [max(0.0, min(1.0, weights[i])) for i in range(len(names))]
            total = sum(weights)
            assert total > 0.99, "a gear vertex lost its attachment"
            for group, weight in zip(groups, weights):
                if weight > 0:
                    group.add([vertex.index], weight / total, "REPLACE")
        dk.fix_shading(low, angle_deg=float(row["shading_deg"]), normals_from=raw)
        bm = dk._bm(low)
        for edge in bm.edges:
            if len(edge.link_faces) == 2 and edge.calc_face_angle(0) > math.radians(float(row["shading_deg"])):
                edge.smooth = False
        bm.to_mesh(mesh)
        bm.free()
        skin = low.modifiers.new("Skin", "ARMATURE")
        skin.object = rig
        audit = dk.audit_decimate(low, high=reference,
                                 budget=int(row["tri_budget"]) if variant == "proposed" else None)
        assert audit["pass"], (part, audit)
        skin.show_viewport = skin.show_render = False
        dk._activate(low)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(float(row["uv_angle_deg"])), island_margin=float(row["uv_margin"]))
        bpy.ops.object.mode_set(mode="OBJECT")
        output = work / variant
        material_name = original_material.name
        original_material.name = "reference_" + material_name
        material = original_material.copy()
        material.name = material_name
        mesh.materials.clear()
        mesh.materials.append(material)
        shader = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        original_shader = next(n for n in original_material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        source_output = next(n for n in original_material.node_tree.nodes if n.type == "OUTPUT_MATERIAL")
        source_link = source_output.inputs["Surface"].links[0].from_socket
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 1
        scene.render.bake.use_selected_to_active = True
        scene.render.bake.margin = int(row["bake_margin_px"])
        # Explicit cage follows smoothed geometric normals, avoiding a jagged automatic cage.
        cage = low.copy()
        cage.data = low.data.copy()
        cage.name = "bake_cage"
        scene.collection.objects.link(cage)
        for vertex, normal in zip(cage.data.vertices, (v.normal.copy() for v in mesh.vertices)):
            vertex.co += normal * float(row["cage_m"])
        scene.render.bake.use_cage = True
        scene.render.bake.cage_object = cage
        cage.hide_render = True
        raw.hide_render = False
        raw.hide_set(False)
        reference.hide_render = True
        target_node = material.node_tree.nodes.new("ShaderNodeTexImage")
        blob = source.read_bytes()
        document = json.loads(blob[20:20 + struct.unpack_from("<I", blob, 12)[0]])
        source_material = document["materials"][0]
        pbr = source_material["pbrMetallicRoughness"]
        textures = {"base": pbr["baseColorTexture"], "normal": source_material["normalTexture"]}
        if "metallicRoughnessTexture" in pbr:
            textures["mr"] = pbr["metallicRoughnessTexture"]
        image_names = {key: document["images"][document["textures"][value["index"]]["source"]]["name"]
                       for key, value in textures.items()}
        for image in list(bpy.data.images):
            image.name = "reference_" + image.name
        maps = {}
        for channel in ("base", "mr", "normal"):
            if channel == "mr" and part == "quiver":
                continue
            image = bpy.data.images.new(image_names[channel], width=int(row["atlas_px"]), height=int(row["atlas_px"]))
            image.colorspace_settings.name = "sRGB" if channel == "base" else "Non-Color"
            target_node.image = image
            material.node_tree.nodes.active = target_node
            if channel == "normal":
                original_material.node_tree.links.new(source_link, source_output.inputs["Surface"])
                bake_type = "NORMAL"
            else:
                nodes, links = original_material.node_tree.nodes, original_material.node_tree.links
                emission = nodes.new("ShaderNodeEmission")
                if channel == "base":
                    socket = original_shader.inputs["Base Color"]
                    if socket.is_linked:
                        links.new(socket.links[0].from_socket, emission.inputs["Color"])
                    else:
                        emission.inputs["Color"].default_value = socket.default_value
                else:
                    combine = nodes.new("ShaderNodeCombineColor")
                    for name, index in [("Roughness", 1), ("Metallic", 2)]:
                        socket = original_shader.inputs[name]
                        if socket.is_linked:
                            links.new(socket.links[0].from_socket, combine.inputs[index])
                        else:
                            combine.inputs[index].default_value = socket.default_value
                    links.new(combine.outputs[0], emission.inputs["Color"])
                links.new(emission.outputs[0], source_output.inputs["Surface"])
                bake_type = "EMIT"
            dk._activate(low)
            raw.select_set(True)
            bpy.ops.object.bake(type=bake_type)
            path = output / (image_names[channel] + ".jpg")
            image.filepath_raw = str(path)
            image.file_format = "JPEG"
            scene.render.image_settings.quality = int(row["jpeg_quality"])
            image.save()
            shutil.copyfile(path, output / (part + "_" + channel + ".jpg"))
            maps[channel] = image
        original_material.node_tree.links.new(source_link, source_output.inputs["Surface"])
        # Replace only the gear atlas inputs; material constants retain the source values.
        for name in ("Base Color", "Metallic", "Roughness", "Normal"):
            for link in list(shader.inputs[name].links):
                material.node_tree.links.remove(link)
        base = material.node_tree.nodes.new("ShaderNodeTexImage")
        base.image = maps["base"]
        material.node_tree.links.new(base.outputs["Color"], shader.inputs["Base Color"])
        if "mr" in maps:
            mr = material.node_tree.nodes.new("ShaderNodeTexImage")
            mr.image = maps["mr"]
            split = material.node_tree.nodes.new("ShaderNodeSeparateColor")
            material.node_tree.links.new(mr.outputs["Color"], split.inputs[0])
            material.node_tree.links.new(split.outputs[1], shader.inputs["Roughness"])
            material.node_tree.links.new(split.outputs[2], shader.inputs["Metallic"])
        normal = material.node_tree.nodes.new("ShaderNodeTexImage")
        normal.image = maps["normal"]
        normal_map = material.node_tree.nodes.new("ShaderNodeNormalMap")
        material.node_tree.links.new(normal.outputs["Color"], normal_map.inputs["Color"])
        material.node_tree.links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
        skin.show_viewport = skin.show_render = True
        audit = dk.audit_decimate(low, high=reference,
                                 budget=int(row["tri_budget"]) if variant == "proposed" else None)
        assert audit["pass"], (part, audit)
        dk._activate(low)
        rig.select_set(True)
        path = output / ("archers_" + part + ".glb")
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                                  export_animations=False, export_skins=True, export_def_bones=False,
                                  export_yup=True, export_apply=False, export_image_format="JPEG", export_jpeg_quality=int(row["jpeg_quality"]))
        report[part] = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "preflight": preflight, "audit": audit, "skin": names,
                        "uv": "new UVs; selected-to-active albedo/metal-rough/normal bake", "image_names": image_names}
        (output / "audit.json").write_text(json.dumps(report, indent=2) + "\n")
        print("BAKED", part, audit, flush=True)


if __name__ == "__main__":
    main()
