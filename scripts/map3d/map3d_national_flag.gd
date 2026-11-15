@tool
class_name Map3DNationalFlag
extends Node3D
## One physical standard. Geometry, wind and materials belong to its scene.
@export var cloth: MeshInstance3D
var _texture: Texture2D

func set_texture(value: Texture2D) -> void:
	if cloth == null or value == _texture: return
	_texture = value
	var material := cloth.material_override.duplicate() as ShaderMaterial
	material.set_shader_parameter("flag_texture", value)
	cloth.material_override = material

static func texture_for(repo: DataRepository, table: ArtTable, realm: String) -> Texture2D:
	if table == null or realm.is_empty(): return null
	for slot: String in table.art:
		if repo.resolve_realm(slot) == realm:
			return table.of(slot) as Texture2D
	return null

static func city_realm(repo: DataRepository, state: GameState, burg: Dictionary) -> String:
	return MapOwnership.owner_of(repo, state, String(burg.get("province_code", "")))
