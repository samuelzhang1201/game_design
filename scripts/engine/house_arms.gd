class_name HouseArms
extends RefCounted
## The coats of arms of houses and kingdoms (owner 2026-09-15, spec
## docs/superpowers/specs/2026-09-15-house-arms-design.md). The art is
## generated from the map pack's Azgaar `coa` (assets/flux/arms_prompts.py)
## and installed as assets/arms/<map_id>/<key>.png:
##   kingdom_<code>        a kingdom's state arms
##   seat_<capital burg>   a house's: the arms of its seat town
##   province_<code>       a house seated in a province with no town
## A house's seat is its FIRST province by province_id among those
## MapObjects.house_name_of gives it. The crown resolves through
## player_setup.house_was, so renaming the royal family keeps its arms.
## Pure: no nodes; textures are loaded once per path.

## repo instance id -> {family: seat province code}.
static var _seats: Dictionary = {}
## res path -> Texture2D (or null when the file is missing).
static var _textures: Dictionary = {}

static func forget() -> void:
	_seats.clear()
	_textures.clear()

static func _seat_table(repo: DataRepository) -> Dictionary:
	var id := repo.get_instance_id()
	if _seats.has(id):
		return _seats[id]
	var codes: Array = repo.provinces.keys()
	codes.sort_custom(func(a: String, b: String) -> bool:
		return int(repo.provinces[a].get("province_id", 0)) < int(repo.provinces[b].get("province_id", 0)))
	var table: Dictionary = {}
	for code: String in codes:
		var family := MapObjects.house_name_of(repo, code)
		if not table.has(family):
			table[family] = code
	_seats[id] = table
	return table

## The royal family as the pack names it: the house of the province that
## holds the player realm's capital (house_bindings.csv binds it).
static func royal_family(repo: DataRepository) -> String:
	var realm: Dictionary = repo.kingdoms.get(repo.resolve_realm("player_realm"), {})
	var capital: Dictionary = repo.burgs.get(String(realm.get("capital_burg", "")), {})
	var province := String(capital.get("province_code", ""))
	return MapObjects.house_name_of(repo, province) if province != "" else ""

## The province a family is seated in; "" when it holds none.
static func seat_province(repo: DataRepository, state: GameState, family: String) -> String:
	if family == "":
		return ""
	var name := family
	if state != null and family == MapManors.crown(state):
		var was := String(state.player_setup.get("house_was", ""))
		if was != "":
			name = was
	return String(_seat_table(repo).get(name, ""))

static func key_of_province(repo: DataRepository, province_code: String) -> String:
	var capital := String(repo.provinces.get(province_code, {}).get("capital_burg", ""))
	return ("seat_" + capital) if capital != "" else ("province_" + province_code)

static func key_of_house(repo: DataRepository, state: GameState, family: String) -> String:
	var seat := seat_province(repo, state, family)
	return key_of_province(repo, seat) if seat != "" else ""

static func key_of_kingdom(kingdom_code: String) -> String:
	return "kingdom_" + kingdom_code

static func path_of(repo: DataRepository, key: String) -> String:
	return "res://assets/arms/%s/%s.png" % [repo.map_id, key]

static func texture_of_key(repo: DataRepository, key: String) -> Texture2D:
	if key == "":
		return null
	var path := path_of(repo, key)
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]

static func texture_of_house(repo: DataRepository, state: GameState, family: String) -> Texture2D:
	return texture_of_key(repo, key_of_house(repo, state, family))

static func texture_of_kingdom(repo: DataRepository, kingdom_code: String) -> Texture2D:
	return texture_of_key(repo, key_of_kingdom(kingdom_code))
