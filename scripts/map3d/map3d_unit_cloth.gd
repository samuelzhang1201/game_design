class_name Map3DUnitCloth
extends RefCounted
## A regiment's figures in its REALM'S CLOTH: each surface whose albedo atlas
## has a cloth mask (`assets/3D/units/cloth_masks.tres`, an ArtTable keyed by
## the atlas's file name; masks baked by tools/units3d/cloth_mask.py) is drawn
## with `unit_cloth.tres` over the figure scene's own textures, the dye turned
## to the realm's map colour (instance uniform `realm_color`). Metal B /
## rough G is the atlas packing every unit scene uses. The WAR ROOM builds its
## own figures and never sees this.

const TEMPLATE := preload("res://scenes/map3d/materials/unit_cloth.tres")
const MASKS := preload("res://assets/3D/units/cloth_masks.tres")
static var _cloths: Dictionary = {}  # source material -> its cloth ShaderMaterial (null: no mask)


static func sync(piece: Dictionary, color: Color) -> void:
	for m: MeshInstance3D in Map3DUnits.meshes(piece["node"]):
		var dressed := false
		for i in m.get_surface_override_material_count():
			var cloth := _cloth_of(m.get_active_material(i))
			if cloth == null:
				continue
			m.set_surface_override_material(i, cloth)
			dressed = true
		if dressed:
			m.set_instance_shader_parameter("realm_color", color)


static func _cloth_of(src: Material) -> ShaderMaterial:
	if src is ShaderMaterial and (src as ShaderMaterial).shader == TEMPLATE.shader:
		return src  # already dressed
	var base := src as BaseMaterial3D
	if base == null or base.albedo_texture == null:
		return null
	if _cloths.has(base):
		return _cloths[base]
	var mask := MASKS.of(base.albedo_texture.resource_path.get_file()) as Texture2D
	var mat: ShaderMaterial = null
	if mask != null:
		mat = TEMPLATE.duplicate() as ShaderMaterial
		mat.set_shader_parameter("albedo_tex", base.albedo_texture)
		mat.set_shader_parameter("albedo_tint", base.albedo_color)
		mat.set_shader_parameter("mr_tex", base.metallic_texture)
		mat.set_shader_parameter("metallic", base.metallic)
		mat.set_shader_parameter("roughness", base.roughness)
		mat.set_shader_parameter("has_normal", base.normal_enabled and base.normal_texture != null)
		mat.set_shader_parameter("normal_tex", base.normal_texture)
		mat.set_shader_parameter("cloth_tex", mask)
	_cloths[base] = mat
	return mat
