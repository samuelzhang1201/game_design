class_name Map3DHouseMaterials
extends RefCounted
## The house meshes' surfaces as Map3DLayerHouses draws them (moved out of the
## layer, perf 2026-10-02, to keep it small). Every surface's material is
## AUTHORED in its house type's scene (scenes/models/buildings/<type>.tscn,
## owner 2026-10-04: each house model is a scene, edited in the editor) —
## house_surface.gdshader with its texture, roughness and role; the layer
## draws its own COPY of each, to which it adds only what is not the house's:
## the Houses node's wall and roof tints, picked per house and handed over as
## instance custom data, and the weather's uniforms.

const HOUSE_SHADER := preload("res://scripts/map3d/house_surface.gdshader")


## A copy of `mesh` whose surface i wears a copy of `materials[i]` (the scene's,
## Map3DAssetCache.house_model) with the tints and `weather`'s uniforms laid on
## it; each copy is appended to `made` (Map3DLayerWeather sets the weather on
## them later). A surface whose scene material is not house_surface.gdshader
## keeps it as it is — untinted, no weather — and says so once.
static func tinted(mesh: Mesh, materials: Array, wall_tints: PackedVector3Array,
		roof_tints: PackedVector3Array, weather: Dictionary, made: Array,
		trim_tints: PackedVector3Array = PackedVector3Array()) -> Mesh:
	var out := mesh.duplicate() as Mesh
	if not (out is ArrayMesh):
		return mesh
	for i in out.get_surface_count():
		var src: Material = materials[i] if i < materials.size() else null
		if not (src is ShaderMaterial and (src as ShaderMaterial).shader == HOUSE_SHADER):
			Map3DWorldLoader.warn_once("houses:mat:%s:%d" % [mesh.resource_path, i],
				"map3d houses: surface %d of %s is not drawn by house_surface.gdshader in its scene" % [i, mesh.resource_path])
			if src != null:
				(out as ArrayMesh).surface_set_material(i, src)
			continue
		var mat := src.duplicate() as ShaderMaterial
		mat.set_shader_parameter("wall_tints", wall_tints)
		mat.set_shader_parameter("roof_tints", roof_tints)
		mat.set_shader_parameter("wall_count", wall_tints.size())
		mat.set_shader_parameter("roof_count", roof_tints.size())
		if trim_tints.size() > 1:
			mat.set_shader_parameter("trim_tints", trim_tints)
			mat.set_shader_parameter("trim_count", trim_tints.size())
		made.append(mat)
		for key: String in weather: mat.set_shader_parameter(key, weather[key])
		(out as ArrayMesh).surface_set_material(i, mat)
	return out


## An empty MultiMesh of `mesh` for a layer to fill (TRANSFORM_3D with custom
## data: Map3DHouses.pack's buffer), casting shadows or not.
static func multimesh_instance(node_name: String, mesh: Mesh, shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
