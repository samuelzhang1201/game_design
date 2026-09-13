class_name MapManors
extends RefCounted
## Manors as units (MANOR_SYSTEM.md, owner 2026-09-13): the land cells of
## the pack, each with a name (political/manors.csv), a province, a HOUSE
## that holds it, a share of its province's people, buildings, rent, and a
## price. Engine-pure and static, like MapOwnership, which it mirrors:
##
## - The owner is a family name. "The crown" is the player's family
##   (GameState.player_setup.family_name). A manor nobody has moved belongs
##   to its province's house (MapObjects.house_name_of), so the pack needs no
##   manor-owner table and a re-export changes nothing.
## - GameState.manor_owner holds ONLY manors that moved, as province_owner
##   does; set_owner needs a reason and writes manor_log.
## - Population is never stored: a manor's share of its province's rural
##   people is its area x land value over the province's total, and a burg's
##   cell takes the province's urban people by burg population share — so
##   the manors of a province always sum to the province, and a ledger move
##   on the province moves every manor in it.
## - Every number in a formula is balance.csv (manor_*) or
##   manor_buildings.csv.

## Per-repo caches of the geometry that never changes: the manors of each
## province and each cell's weight. Dropped by invalidate().
static var _cache: Dictionary = {}

static func invalidate() -> void:
	_cache.clear()

static func _repo_cache(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if not _cache.has(key):
		_cache[key] = {"by_province": {}, "weight": {}, "area": {}, "province_weight": {},
			"burg_pop": {}}
	return _cache[key]

# ---- identity ---------------------------------------------------------------

static func is_manor(repo: DataRepository, cell_id: int) -> bool:
	return repo.manors.has(cell_id)

static func label_of(repo: DataRepository, cell_id: int) -> String:
	return String((repo.manors.get(cell_id, {}) as Dictionary).get("label", "Manor %d" % cell_id))

static func code_of(repo: DataRepository, cell_id: int) -> String:
	return String((repo.manors.get(cell_id, {}) as Dictionary).get("manor_code", ""))

static func province_of(repo: DataRepository, cell_id: int) -> String:
	return String((repo.manors.get(cell_id, {}) as Dictionary).get("province_code", ""))

static func burg_of(repo: DataRepository, cell_id: int) -> String:
	return String((repo.manors.get(cell_id, {}) as Dictionary).get("burg_code", ""))

## The manor a player or the model named: its code, else its label in any
## case, with or without a trailing "manor". -1 for none.
static func find(repo: DataRepository, text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return -1
	if t.is_valid_int() and repo.manors.has(int(t)):
		return int(t)
	if repo.manor_by_code.has(t):
		return int(repo.manor_by_code[t])
	var lower := t.to_lower()
	if repo.manor_by_label.has(lower):
		return int(repo.manor_by_label[lower])
	for suffix in [" manor", " Manor"]:
		if lower.ends_with(suffix.to_lower()):
			var bare := lower.substr(0, lower.length() - suffix.length())
			if repo.manor_by_label.has(bare):
				return int(repo.manor_by_label[bare])
			if repo.manor_by_label.has(bare + " manor"):
				return int(repo.manor_by_label[bare + " manor"])
	if repo.manor_by_label.has(lower + " manor"):
		return int(repo.manor_by_label[lower + " manor"])
	return -1

## The manors (cell ids, ascending) of a province.
static func manors_of_province(repo: DataRepository, province_code: String) -> Array:
	var c := _repo_cache(repo)
	if (c["by_province"] as Dictionary).is_empty():
		var ids: Array = repo.manors.keys()
		ids.sort()
		for id: int in ids:
			var p := province_of(repo, id)
			if not c["by_province"].has(p):
				c["by_province"][p] = []
			(c["by_province"][p] as Array).append(id)
	return (c["by_province"] as Dictionary).get(province_code, [])

# ---- ownership --------------------------------------------------------------

## The player's family: the crown. The player character's LIVE family name
## (character creation may have renamed the house), else the setup's.
static func crown(state: GameState) -> String:
	if state == null:
		return ""
	var you: Character = state.characters.get("you", null)
	if you != null and you.family_name.strip_edges() != "":
		return you.family_name.strip_edges()
	return String(state.player_setup.get("family_name", "")).strip_edges()

## The house a manor belongs to when nobody has moved it: its province's —
## and when that is the royal house under the name it had before character
## creation renamed it (player_setup.house_was), it is the crown's.
static func default_owner(repo: DataRepository, state: GameState, cell_id: int) -> String:
	var province := province_of(repo, cell_id)
	if province == "":
		return ""
	var house := MapObjects.house_name_of(repo, province)
	if state != null and house != "" and house == String(state.player_setup.get("house_was", "")):
		return crown(state)
	return house

static func owner_of(repo: DataRepository, state: GameState, cell_id: int) -> String:
	if state != null and state.manor_owner.has(str(cell_id)):
		return String(state.manor_owner[str(cell_id)])
	return default_owner(repo, state, cell_id)

static func is_crowns(repo: DataRepository, state: GameState, cell_id: int) -> bool:
	var c := crown(state)
	return c != "" and owner_of(repo, state, cell_id) == c

## A house the game knows: the crown, a bound family, a character's family,
## or a province's default house.
static func is_known_house(repo: DataRepository, state: GameState, family: String) -> bool:
	if family == "":
		return false
	if family == crown(state):
		return true
	for province: String in repo.house_bindings:
		if String(repo.house_bindings[province]) == family:
			return true
	for id in state.characters:
		if (state.characters[id] as Character).family_name == family:
			return true
	for province: String in repo.provinces:
		if MapObjects.house_name_of(repo, province) == family:
			return true
	return false

## Move a manor to a house. Refuses an unknown manor, an unknown house, a
## move to its present holder, and an empty reason — a manor that changed
## hands must be able to say why. Logs {tick, cell, from, to, reason}.
static func set_owner(repo: DataRepository, state: GameState, cell_id: int, family: String,
		reason: String) -> bool:
	if not is_manor(repo, cell_id) or reason.strip_edges() == "":
		return false
	if not is_known_house(repo, state, family):
		return false
	var from := owner_of(repo, state, cell_id)
	if from == family:
		return false
	state.manor_owner[str(cell_id)] = family
	state.manor_log.append({"tick": state.tick, "cell": cell_id, "from": from, "to": family,
		"reason": reason})
	return true

## {family: count} over a province's manors, live.
static func holdings_of_province(repo: DataRepository, state: GameState, province_code: String) -> Dictionary:
	var out: Dictionary = {}
	for id: int in manors_of_province(repo, province_code):
		var h := owner_of(repo, state, id)
		out[h] = int(out.get(h, 0)) + 1
	return out

## Every manor a house holds, ascending; the whole pack unless a kingdom is
## named, in which case only its provinces' manors.
static func manors_of_house(repo: DataRepository, state: GameState, family: String,
		kingdom_code: String = "") -> Array:
	var out: Array = []
	var ids: Array = repo.manors.keys()
	ids.sort()
	for id: int in ids:
		if kingdom_code != "" and MapOwnership.owner_of(repo, state, province_of(repo, id)) != kingdom_code:
			continue
		if owner_of(repo, state, id) == family:
			out.append(id)
	return out

# ---- land and people --------------------------------------------------------

## Polygon area in native px².
static func area_of(repo: DataRepository, cell_id: int) -> float:
	var c := _repo_cache(repo)
	if not c["area"].has(cell_id):
		var poly := MapEconomy.cell_polygon(repo, repo.cells.get(cell_id, {"vertex_ids": PackedInt32Array()}))
		var sum := 0.0
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			sum += a.x * b.y - b.x * a.y
		c["area"][cell_id] = absf(sum) * 0.5
	return c["area"][cell_id]

static func land_value_of(repo: DataRepository, cell_id: int) -> float:
	return MapEconomy.land_value(repo, repo.cells.get(cell_id, {}))

## area x land value: the manor's share of its province's country folk.
static func weight_of(repo: DataRepository, cell_id: int) -> float:
	var c := _repo_cache(repo)
	if not c["weight"].has(cell_id):
		c["weight"][cell_id] = area_of(repo, cell_id) * maxf(land_value_of(repo, cell_id), 0.01)
	return c["weight"][cell_id]

static func _province_weight(repo: DataRepository, province_code: String) -> float:
	var c := _repo_cache(repo)
	if not c["province_weight"].has(province_code):
		var sum := 0.0
		for id: int in manors_of_province(repo, province_code):
			sum += weight_of(repo, id)
		c["province_weight"][province_code] = sum
	return c["province_weight"][province_code]

## Burg population summed per province, for the urban share.
static func _province_burg_pop(repo: DataRepository, province_code: String) -> float:
	var c := _repo_cache(repo)
	if not c["burg_pop"].has(province_code):
		var sum := 0.0
		for code: String in repo.burgs:
			var b: Dictionary = repo.burgs[code]
			if String(b.get("province_code", "")) == province_code:
				sum += float(b.get("population", 0))
		c["burg_pop"][province_code] = sum
	return c["burg_pop"][province_code]

static func _ledger(repo: DataRepository, state: GameState, path: String) -> float:
	var v: Variant = WorldLedger.value_of(repo, state, path)
	return float(v) if v != null else 0.0

## {rural, urban, total}: the manor's share of its province, live.
static func population_of(repo: DataRepository, state: GameState, cell_id: int) -> Dictionary:
	var province := province_of(repo, cell_id)
	if province == "":
		return {"rural": 0.0, "urban": 0.0, "total": 0.0}
	var total_weight := _province_weight(repo, province)
	var rural := 0.0
	if total_weight > 0.0:
		rural = _ledger(repo, state, "economy.provinces.%s.rural_population" % province) \
			* weight_of(repo, cell_id) / total_weight
	var urban := 0.0
	var burg := burg_of(repo, cell_id)
	if burg != "":
		var burg_total := _province_burg_pop(repo, province)
		if burg_total > 0.0:
			urban = _ledger(repo, state, "economy.provinces.%s.urban_population" % province) \
				* float(repo.burgs[burg].get("population", 0)) / burg_total
	return {"rural": rural, "urban": urban, "total": rural + urban}

# ---- buildings, rent, defence -------------------------------------------------

static func buildings_of(state: GameState, cell_id: int) -> Array:
	return (state.manor_buildings.get(str(cell_id), []) as Array).duplicate()

static func has_building(state: GameState, cell_id: int, building_code: String) -> bool:
	return buildings_of(state, cell_id).has(building_code)

## Raise a building. Refuses an unknown manor or building, a duplicate, and
## an empty reason; logs into manor_log with a "building" field.
static func build(repo: DataRepository, state: GameState, cell_id: int, building_code: String,
		reason: String) -> bool:
	if not is_manor(repo, cell_id) or not repo.manor_buildings.has(building_code):
		return false
	if reason.strip_edges() == "" or has_building(state, cell_id, building_code):
		return false
	var key := str(cell_id)
	if not state.manor_buildings.has(key):
		state.manor_buildings[key] = []
	(state.manor_buildings[key] as Array).append(building_code)
	state.manor_log.append({"tick": state.tick, "cell": cell_id, "building": building_code,
		"reason": reason})
	return true

## The sum of one bonus column over a manor's buildings.
static func building_bonus(repo: DataRepository, state: GameState, cell_id: int, column: String) -> float:
	var sum := 0.0
	for code: String in buildings_of(state, cell_id):
		sum += float((repo.manor_buildings.get(code, {}) as Dictionary).get(column, 0))
	return sum

static func building_cost(repo: DataRepository, state: GameState, cell_id: int) -> float:
	var sum := 0.0
	for code: String in buildings_of(state, cell_id):
		sum += float((repo.manor_buildings.get(code, {}) as Dictionary).get("cost_gold", 0))
	return sum

## Gold per tick the manor yields its holder.
static func rent_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	var pop: float = population_of(repo, state, cell_id)["total"]
	return pop / 1000.0 * repo.bal("manor_rent_per_1000") \
		* (1.0 + building_bonus(repo, state, cell_id, "tax_bonus"))

## Gold per tick from every manor the crown holds in its realm — what
## TickEngine pays into the treasury as "manor rents" (MANOR_SYSTEM.md §3).
static func crown_rents(repo: DataRepository, state: GameState) -> float:
	var total := 0.0
	for cell: int in manors_of_house(repo, state, crown(state), repo.resolve_realm("player_realm")):
		total += rent_of(repo, state, cell)
	return total

static func defence_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	return repo.bal("manor_defence_base") + building_bonus(repo, state, cell_id, "defence_bonus")

## Units of goods a working manor makes (MapEconomy.manors), 0 otherwise.
static func output_of(repo: DataRepository, cell_id: int) -> float:
	return float((MapEconomy.manors(repo).get(cell_id, {}) as Dictionary).get("total", 0.0))

# ---- price ------------------------------------------------------------------------

## How a house feels about the crown, -100..100: its council member's
## opinion, else any character of the family's, else 0 (a house with no
## voice at court is neither warm nor cold).
static func house_opinion(repo: DataRepository, state: GameState, family: String) -> int:
	var any_member := -1000
	for seat in state.council:
		var c: Character = state.characters.get(String(state.council[seat]), null)
		if c != null and c.family_name == family:
			return c.opinion
	for id in state.characters:
		var c: Character = state.characters[id]
		if c.family_name == family:
			any_member = c.opinion if any_member == -1000 else any_member
	return 0 if any_member == -1000 else any_member

## What a manor is worth before anyone's feelings: people, output, buildings,
## and the land — MANOR_SYSTEM.md §5.
static func base_value_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	var pop: float = population_of(repo, state, cell_id)["total"]
	var base := pop / 1000.0 * repo.bal("manor_price_per_1000") \
		+ output_of(repo, cell_id) * repo.bal("manor_price_per_unit") \
		+ building_cost(repo, state, cell_id) * repo.bal("manor_price_building_ratio")
	var land := 1.0 + (land_value_of(repo, cell_id) - 0.5) * repo.bal("manor_price_land_swing")
	return base * land

## The holding house's asking price to the crown: the value marked up by
## how little the house likes the crown (opinion -100..100 -> markup 0..max).
static func price_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	var opinion := house_opinion(repo, state, owner_of(repo, state, cell_id))
	var coolness := clampf((100.0 - float(opinion)) / 200.0, 0.0, 1.0)
	return round(base_value_of(repo, state, cell_id) * (1.0 + repo.bal("manor_markup_max") * coolness))

## What the crown gets selling a manor back to its province's house.
static func sell_price_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	return round(base_value_of(repo, state, cell_id) * repo.bal("manor_sell_ratio"))
