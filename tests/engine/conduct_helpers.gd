extends RefCounted
## Shared fixtures for the foraging and desertion tests (spec
## 2026-10-10-foraging-and-desertion). Nothing here names a pack, a kingdom or a
## province: all of it is read off the repository.


## A good tagged `food`, the first by code.
static func food_good(repo: DataRepository) -> String:
	var codes: Array = repo.world_table("economy", "goods").keys()
	codes.sort()
	for c: String in codes:
		var tags: PackedStringArray = String(repo.world_row("economy", "goods", c).get("tags", "")).split("|", false)
		if "food" in tags:
			return c
	return ""


## A good that is NOT food.
static func other_good(repo: DataRepository) -> String:
	var codes: Array = repo.world_table("economy", "goods").keys()
	codes.sort()
	for c: String in codes:
		var tags: PackedStringArray = String(repo.world_row("economy", "goods", c).get("tags", "")).split("|", false)
		if not ("food" in tags):
			return c
	return ""


## The province's first burg (by code); "" for none.
static func burg_of(repo: DataRepository, province: String) -> String:
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for b: String in codes:
		if String((repo.burgs[b] as Dictionary).get("province_code", "")) == province:
			return b
	return ""


## Add a production row of `units` of `good` at the province's first burg.
static func add_row(repo: DataRepository, province: String, good: String, units: int) -> void:
	var burg := burg_of(repo, province)
	(repo.world_table("economy", "production") as Dictionary)["%s:%s" % [burg, good]] = {
		"burg_code": burg, "good_code": good, "units": units}
	Forage.forget()


## The province's food rows removed, one row of `units` of a food good put in.
static func set_food(repo: DataRepository, province: String, units: int) -> void:
	var table: Dictionary = repo.world_table("economy", "production")
	var food := food_good(repo)
	for k: String in table.keys():
		var row: Dictionary = table[k]
		var tags: PackedStringArray = String(repo.world_row("economy", "goods", String(row["good_code"])).get("tags", "")).split("|", false)
		if "food" in tags and String((repo.burgs.get(String(row["burg_code"]), {}) as Dictionary).get("province_code", "")) == province:
			table.erase(k)
	add_row(repo, province, food, units)


## Every non-naval regiment code of the state, sorted.
static func land_units(_repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for c: String in state.regiments.keys():
		if String(ArmySystem.regiment(_repo, c, state).get("is_naval", "0")) != "1":
			out.append(c)
	out.sort()
	return out


## The first non-naval regiment code ("" for none).
static func land_unit(repo: DataRepository, state: GameState) -> String:
	var all := land_units(repo, state)
	return String(all[0]) if not all.is_empty() else ""


## The first province (by code) held by a kingdom other than the crown's.
static func foreign_province(repo: DataRepository, state: GameState) -> String:
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for p: String in codes:
		var holder := MapOwnership.owner_of(repo, state, p)
		if holder != "" and holder != repo.resolve_realm("player_realm"):
			return p
	return ""


## Write the crown's stance row toward `kingdom` (the diplomacy table).
static func set_stance(repo: DataRepository, kingdom: String, stance: String) -> void:
	var key := "%s>%s" % [repo.resolve_realm("player_realm"), kingdom]
	var table: Dictionary = repo.world_table("political", "diplomacy")
	var row: Dictionary = table.get(key, {})
	row["stance"] = stance
	table[key] = row


## A province the crown holds that has a burg.
static func home_province(repo: DataRepository, state: GameState) -> String:
	var provs: Array = MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))
	provs.sort()
	for p: String in provs:
		if burg_of(repo, p) != "":
			return p
	return ""
