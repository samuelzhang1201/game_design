class_name Map3DHouseMaterials
extends RefCounted
## The house meshes' surfaces as Map3DLayerHouses draws them (moved out of the
## layer, perf 2026-10-02, to keep it small): every surface keeps its OWN
## imported texture, drawn by house_surface.gdshader, which also multiplies a
## wall or a roof by one of Map3DLayerHouses' tints, picked per
## house and handed over as instance custom data.

const HOUSE_SHADER := preload("res://scripts/map3d/house_surface.gdshader")


## A copy of `mesh` whose every surface is drawn by house_surface.gdshader
## with that surface's own imported texture, roughness, vertex-colour use and
## normal map when it has one (the palaces): a wall surface (material
## hh_wall_*) takes the wall tints, a tile roof (hh_roof_*, not slate) the
## roof tints, anything else none. Each material made is appended to `made`
## with `weather`'s uniforms laid on it (Map3DLayerWeather).
static func tinted(mesh: Mesh, wall_tints: PackedVector3Array, roof_tints: PackedVector3Array,
		weather: Dictionary, made: Array) -> Mesh:
	var out := mesh.duplicate() as Mesh
	if not (out is ArrayMesh):
		return mesh
	for i in out.get_surface_count():
		var src := out.surface_get_material(i) as StandardMaterial3D
		if src == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = HOUSE_SHADER
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("albedo_color", src.albedo_color)
		mat.set_shader_parameter("roughness", src.roughness)
		mat.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
		# a surface that brought a normal map (the palaces) draws it; the rest have none
		mat.set_shader_parameter("use_normal", src.normal_enabled and src.normal_texture != null)
		if src.normal_texture != null:
			mat.set_shader_parameter("normal_tex", src.normal_texture)
			mat.set_shader_parameter("normal_depth", src.normal_scale)
		var mat_name := src.resource_name
		var role := 0
		if mat_name.begins_with("hh_wall_"):
			role = 1
		elif mat_name.begins_with("hh_roof_") and mat_name != "hh_roof_slate":
			role = 2
		mat.set_shader_parameter("role", role)
		mat.set_shader_parameter("wall_tints", wall_tints)
		mat.set_shader_parameter("roof_tints", roof_tints)
		mat.set_shader_parameter("wall_count", wall_tints.size())
		mat.set_shader_parameter("roof_count", roof_tints.size())
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
