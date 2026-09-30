class_name HouseArms
extends RefCounted
## The coats of arms of houses and kingdoms (owner 2026-09-15, spec
## docs/superpowers/specs/2026-09-15-house-arms-design.md). The art is
## generated from the map pack's Azgaar `coa` (assets/flux/arms_prompts.py)
## and installed as assets/2D/arms/<map_id>/<key>.png:
##   kingdom_<code>        a kingdom's state arms
##   seat_<capital burg>   a house's: the arms of its seat town
##   province_<code>       a house seated in a province with no town
## A house's seat is its FIRST province by province_id among those
## MapObjects.house_name_of gives it. The crown resolves through
## player_setup.house_was, so renaming the royal family keeps its arms.
##
## A NEW MAP NEEDS NO NEW ARMS (owner 2026-09-18): which art a key wears is
##   1. maps/<id>/arms_bindings.csv, when it pins the key;
##   2. the pack's own assets/2D/arms/<id>/<key>.png, when installed;
##   3. else BORROWED from every other pack's installed arms — kingdoms from
##      the kingdom_ art, houses from the seat_ / province_ art — handed out
##      in the pack's own order (kingdoms by state_id, houses' seats by province_id),
##      so the same map always wears the same arms and none twice while the
##      pool lasts. Only when a map needs more than the pool holds do arms
##      repeat; report() counts it, and that is when to generate new ones.
## Pure: no nodes; textures are loaded once per path.

## repo instance id -> {family: seat province code}.
static var _seats: Dictionary = {}
## res path -> Texture2D (or null when the file is missing).
static var _textures: Dictionary = {}
## "<repo id>|<map_id>" -> {key: borrowed path, "_report": {...}}.
static var _borrowed: Dictionary = {}

const ARMS_ROOT := "res://assets/2D/arms"

static func forget() -> void:
	_seats.clear()
	_textures.clear()
	_borrowed.clear()

## An arms_bindings.csv value as a path: a res:// path as it is, or the
## shorthand <pack>/<key> for assets/2D/arms/<pack>/<key>.png.
static func arms_path(value: String) -> String:
	if value.begins_with("res://"):
		return value
	return "%s/%s.png" % [ARMS_ROOT, value.trim_suffix(".png")]

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
	return "res://assets/2D/arms/%s/%s.png" % [repo.map_id, key]

## The art a key actually wears: a binding, the pack's own, or borrowed
## (see the top of this file); "" when there is none anywhere.
static func resolved_path(repo: DataRepository, key: String) -> String:
	if key == "":
		return ""
	if repo.arms_bindings.has(key):
		return String(repo.arms_bindings[key])
	var own := path_of(repo, key)
	if ResourceLoader.exists(own):
		return own
	return String(_borrow_table(repo).get(key, ""))

## How the pack's arms are sourced: {own, bound, borrowed, repeated,
## missing} — repeated counts keys that had to reuse art already handed
## out (the pool ran short), missing keys that got none at all.
static func report(repo: DataRepository) -> Dictionary:
	return (_borrow_table(repo)["_report"] as Dictionary).duplicate()

## Every key the pack needs arms for, in its own order: kingdoms by
## state_id, then each house's seat key — one per family, its first
## province by province_id (the _seat_table order).
static func needed_keys(repo: DataRepository) -> Dictionary:
	var kingdoms: Array = repo.kingdoms.keys()
	kingdoms.sort_custom(func(a: String, b: String) -> bool:
		var sa := int(repo.kingdoms[a].get("state_id", 0))
		var sb := int(repo.kingdoms[b].get("state_id", 0))
		return sa < sb if sa != sb else a < b)
	var seats: Dictionary = _seat_table(repo)
	var seat_codes: Array = seats.values()
	seat_codes.sort_custom(func(a: String, b: String) -> bool:
		return int(repo.provinces[a].get("province_id", 0)) < int(repo.provinces[b].get("province_id", 0)))
	var houses: Array = []
	for code: String in seat_codes:
		var key := key_of_province(repo, code)
		if not houses.has(key):
			houses.append(key)
	return {"kingdoms": kingdoms.map(func(c: String) -> String: return key_of_kingdom(c)),
		"houses": houses}

## Installed arms of every OTHER pack, split {kingdom: [...], house: [...]},
## sorted by pack then key. An exported build lists `<file>.png.import`
## rather than the PNG, so both spellings are read.
static func pool(repo: DataRepository) -> Dictionary:
	var out := {"kingdom": [], "house": []}
	var packs := Array(DirAccess.get_directories_at(ARMS_ROOT))
	packs.sort()
	for pack: String in packs:
		if pack == repo.map_id:
			continue
		var names: Dictionary = {}
		for f: String in DirAccess.get_files_at("%s/%s" % [ARMS_ROOT, pack]):
			var n := f.trim_suffix(".remap").trim_suffix(".import")
			if n.ends_with(".png"):
				names[n.get_basename()] = true
		var keys: Array = names.keys()
		keys.sort()
		for key: String in keys:
			var path := "%s/%s/%s.png" % [ARMS_ROOT, pack, key]
			(out["kingdom"] if key.begins_with("kingdom_") else out["house"]).append(path)
	return out

static func _borrow_table(repo: DataRepository) -> Dictionary:
	var id := "%d|%s" % [repo.get_instance_id(), repo.map_id]
	if _borrowed.has(id):
		return _borrowed[id]
	var table: Dictionary = {}
	var counts := {"own": 0, "bound": 0, "borrowed": 0, "repeated": 0, "missing": 0}
	var bound_art: Dictionary = {}
	for k: String in repo.arms_bindings:
		bound_art[String(repo.arms_bindings[k])] = true
	var src := pool(repo)
	var kingdom_pool: Array = (src["kingdom"] as Array).filter(func(p: String) -> bool: return not bound_art.has(p))
	var house_pool: Array = (src["house"] as Array).filter(func(p: String) -> bool: return not bound_art.has(p))
	var needed := needed_keys(repo)
	var want_kingdoms: Array = []
	var want_houses: Array = []
	for group: String in ["kingdoms", "houses"]:
		for key: String in needed[group]:
			if repo.arms_bindings.has(key):
				counts["bound"] += 1
			elif ResourceLoader.exists(path_of(repo, key)):
				counts["own"] += 1
			else:
				(want_kingdoms if group == "kingdoms" else want_houses).append(key)
	# Kingdoms take the kingdom art first, then — should a map have more
	# realms than the pool has kingdom arms — the house art from its END, so
	# the houses keep the front of theirs.
	for i in want_kingdoms.size():
		if i < kingdom_pool.size():
			table[want_kingdoms[i]] = kingdom_pool[i]
		elif not house_pool.is_empty():
			table[want_kingdoms[i]] = house_pool.pop_back()
	var used: Dictionary = {}
	for key: String in want_kingdoms:
		if table.has(key):
			used[table[key]] = true
	for i in want_houses.size():
		if house_pool.is_empty():
			break
		var path: String = house_pool[i % house_pool.size()]
		if used.has(path):
			counts["repeated"] += 1
		used[path] = true
		table[want_houses[i]] = path
	for key: String in want_kingdoms + want_houses:
		if table.has(key):
			counts["borrowed"] += 1
		else:
			counts["missing"] += 1
	table["_report"] = counts
	_borrowed[id] = table
	return table

static func texture_of_key(repo: DataRepository, key: String) -> Texture2D:
	if key == "":
		return null
	var path := resolved_path(repo, key)
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]

static func texture_of_house(repo: DataRepository, state: GameState, family: String) -> Texture2D:
	return texture_of_key(repo, key_of_house(repo, state, family))

static func texture_of_kingdom(repo: DataRepository, kingdom_code: String) -> Texture2D:
	return texture_of_key(repo, key_of_kingdom(kingdom_code))
