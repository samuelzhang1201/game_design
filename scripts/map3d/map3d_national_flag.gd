@tool
class_name Map3DNationalFlag
extends Node3D
## One physical standard. Geometry, wind and materials belong to its scene.
@export var cloth: MeshInstance3D
var _texture: Texture2D
static var _cloth_materials: Dictionary = {}

func set_texture(value: Texture2D) -> void:
	if cloth == null or value == _texture: return
	_texture = value
	var base := cloth.material_override as ShaderMaterial
	var key := [value, base.shader]
	for uniform: String in ["wave_amplitude", "wave_speed", "wave_frequency", "sag", "cloth_width"]:
		key.append(base.get_shader_parameter(uniform))
	if not _cloth_materials.has(key):
		var material := base.duplicate() as ShaderMaterial
		material.set_shader_parameter("flag_texture", value)
		_cloth_materials[key] = material
	cloth.material_override = _cloth_materials[key]

static func texture_for(repo: DataRepository, table: ArtTable, realm: String) -> Texture2D:
	if table == null or realm.is_empty(): return null
	for slot: String in table.art:
		if repo.resolve_realm(slot) == realm:
			return table.of(slot) as Texture2D
	return null

static func city_realm(repo: DataRepository, state: GameState, burg: Dictionary) -> String:
	return MapOwnership.owner_of(repo, state, String(burg.get("province_code", "")))
