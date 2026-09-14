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
## - Population is never stored, and is WHOLE (spec 2026-09-14 §4.1): a
##   province's country folk are apportioned to its manors by area x land
##   value and its townsfolk to its burgs' cells, by largest remainder — so
##   the manors of a province always sum EXACTLY to the province, and a
##   ledger move on the province moves every manor in it.
## - Every number in a formula is balance.csv (manor_*) or
##   manor_buildings.csv.

## Per-repo caches of the geometry that never changes: the manors of each
## province and each cell's weight. Dropped by invalidate().
static var _cache: Dictionary = {}

static func invalidate() -> void:
	_cache.clear()
	_people_cache.clear()

static func _repo_cache(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if not _cache.has(key):
		_cache[key] = {"by_province": {}, "weight": {}, "area": {}}
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

# ---- shades: neighbouring provinces told apart ------------------------------

## Provinces that touch: province code -> Array of province codes, from the
## cells' neighbour lists (two land cells of different provinces sharing an
## edge). Geometry, cached per repo.
static func province_neighbours(repo: DataRepository) -> Dictionary:
	var c := _repo_cache(repo)
	if not c.has("neighbours"):
		var out: Dictionary = {}
		for id: int in repo.manors:
			var mine := province_of(repo, id)
			if mine == "":
				continue
			for n: int in ((repo.cells.get(id, {}) as Dictionary).get("neighbor_ids", PackedInt32Array()) as PackedInt32Array):
				var other := province_of(repo, n)
				if other == "" or other == mine:
					continue
				if not out.has(mine):
					out[mine] = []
				if not (out[mine] as Array).has(other):
					(out[mine] as Array).append(other)
		c["neighbours"] = out
	return c["neighbours"]

## A shade level per province, 0..levels-1, such that no two provinces that
## touch share one (owner 2026-09-13: neighbouring provinces' manors must
## not look alike, even under one house or one realm). Greedy over the
## provinces in code order — deterministic, and a planar map rarely needs
## more than a handful of levels. Cached per repo.
static func province_shades(repo: DataRepository, levels: int) -> Dictionary:
	var c := _repo_cache(repo)
	var key := "shades_%d" % levels
	if not c.has(key):
		var adjacent := province_neighbours(repo)
		var codes: Array = repo.provinces.keys()
		codes.sort()
		var shades: Dictionary = {}
		for code: String in codes:
			var taken: Dictionary = {}
			for other: String in adjacent.get(code, []):
				if shades.has(other):
					taken[int(shades[other])] = true
			var level := 0
			while taken.has(level) and level < maxi(levels, 1) - 1:
				level += 1
			shades[code] = level
		c[key] = shades
	return c[key]

## A colour taken to a shade level: 0 as it is, then lighter and darker
## by turns, each step `step` further from the colour toward white or
## black — so 1 is a touch lighter, 2 a touch darker, 3 lighter still.
static func shade(color: Color, level: int, step: float) -> Color:
	if level <= 0:
		return color
	var amount := step * float((level + 1) / 2)
	var toward := Color(1, 1, 1, color.a) if level % 2 == 1 else Color(0, 0, 0, color.a)
	return color.lerp(toward, clampf(amount, 0.0, 0.9))

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

## Who CONTROLS a province (owner 2026-09-13): the house holding the most
## of its manors; a tie goes to the province's own house (the crown's, if
## that is the royal house), else to the first by name. The crown starts
## with the capital's province and gains or loses others manor by manor.
static func controller_of(repo: DataRepository, state: GameState, province_code: String) -> String:
	var counts := holdings_of_province(repo, state, province_code)
	if counts.is_empty():
		return ""
	var best := ""
	var most := -1
	var home := MapObjects.house_name_of(repo, province_code)
	if state != null and home == String(state.player_setup.get("house_was", "")):
		home = crown(state)
	var houses: Array = counts.keys()
	houses.sort()
	for h: String in houses:
		var n := int(counts[h])
		if n > most or (n == most and h == home):
			most = n
			best = h
	return best

static func crown_controls(repo: DataRepository, state: GameState, province_code: String) -> bool:
	var c := crown(state)
	return c != "" and controller_of(repo, state, province_code) == c

## The provinces the crown controls, in code order — the crown's economy,
## the land it may build on, the ledger the model may touch. Cached per
## manor ownership, which is the only thing that moves it.
static func controlled_provinces(repo: DataRepository, state: GameState) -> Array:
	if state == null:
		return []
	var c := _repo_cache(repo)
	var sig := hash([state.manor_owner.hash(), crown(state), String(state.player_setup.get("house_was", ""))])
	if c.has("control") and int(c["control"]["sig"]) == sig:
		return c["control"]["provinces"]
	var out: Array = []
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		if crown_controls(repo, state, code):
			out.append(code)
	c["control"] = {"sig": sig, "provinces": out}
	return out

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

static func _ledger(repo: DataRepository, state: GameState, path: String) -> float:
	var v: Variant = WorldLedger.value_of(repo, state, path)
	return float(v) if v != null else 0.0

## --- Integer people (spec 2026-09-14 §4.1) -----------------------------------
## The float share of a province a manor used to be given (population_of /
## population_table / _share) is GONE (2026-09-14): it was a second economy
## beside the integer one below, and the manor card printed one figure from
## each. People are whole and sum exactly to their province — people_of and
## people_table are the only reading.
##
## The province's country folk apportioned to its manors by weight with the
## largest-remainder method, so the manors sum EXACTLY to the province and
## no manor has a fraction of a person; its townsfolk the same way over its
## burgs. Cached per (province, rural, urban): the two ledger figures are
## the only inputs that move.
static var _people_cache: Dictionary = {}

## Largest remainder: every id gets the floor of its share, the units left
## go to the largest fractional remainders, ties to the id that comes first.
static func apportion(ids: Array, weights: PackedFloat64Array, total: int) -> Dictionary:
	var out: Dictionary = {}
	var sum := 0.0
	for w in weights:
		sum += w
	if ids.is_empty() or total <= 0 or sum <= 0.0:
		for id in ids:
			out[id] = 0
		return out
	var floors := PackedInt32Array()
	var rem := PackedFloat64Array()
	var given := 0
	for i in ids.size():
		var exact := float(total) * weights[i] / sum
		var f := int(floor(exact))
		floors.append(f)
		rem.append(exact - float(f))
		given += f
	var order: Array = range(ids.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return a < b if rem[a] == rem[b] else rem[a] > rem[b])
	for k in total - given:
		floors[order[k]] += 1
	for i in ids.size():
		out[ids[i]] = floors[i]
	return out

static func people_table(repo: DataRepository, state: GameState, province_code: String) -> Dictionary:
	var rural := int(roundf(_ledger(repo, state, "economy.provinces.%s.rural_population" % province_code)))
	var urban := int(roundf(_ledger(repo, state, "economy.provinces.%s.urban_population" % province_code)))
	var key := "%d|%s|%d|%d" % [repo.get_instance_id(), province_code, rural, urban]
	if _people_cache.has(key):
		return _people_cache[key]
	if _people_cache.size() > 4096:
		_people_cache.clear()
	var cells := manors_of_province(repo, province_code)
	var weights := PackedFloat64Array()
	for id: int in cells:
		weights.append(weight_of(repo, id))
	var out := apportion(cells, weights, rural)
	var burg_cells: Array = []
	var burg_weights := PackedFloat64Array()
	for id: int in cells:
		var burg := burg_of(repo, id)
		if burg != "":
			burg_cells.append(id)
			burg_weights.append(float(repo.burgs[burg].get("population", 0)))
	var town := apportion(burg_cells, burg_weights, urban)
	for id: int in town:
		out[id] = int(out[id]) + int(town[id])
	_people_cache[key] = out
	return out

## A manor's people, whole. 0 for a cell that is no manor.
static func people_of(repo: DataRepository, state: GameState, cell_id: int) -> int:
	var province := province_of(repo, cell_id)
	return 0 if province == "" else int(people_table(repo, state, province).get(cell_id, 0))

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

# ---- slots and works (owner 2026-09-13: building takes time and room) ----------

## How many buildings a manor has room for: manor_slots_base, and
## manor_slots_burg_bonus more when a town stands in it.
static func slots_of(repo: DataRepository, cell_id: int) -> int:
	var n := int(repo.bal("manor_slots_base"))
	if burg_of(repo, cell_id) != "":
		n += int(repo.bal("manor_slots_burg_bonus"))
	return n

## Works in progress on a manor: [{building, start, days}], copies.
static func works_of(state: GameState, cell_id: int) -> Array:
	return (state.manor_works.get(str(cell_id), []) as Array).duplicate(true)

static func is_building(state: GameState, cell_id: int, building_code: String) -> bool:
	for w: Dictionary in works_of(state, cell_id):
		if String(w["building"]) == building_code:
			return true
	return false

## Slots taken: finished buildings and works alike.
static func slots_used(state: GameState, cell_id: int) -> int:
	return buildings_of(state, cell_id).size() + works_of(state, cell_id).size()

static func free_slots(repo: DataRepository, state: GameState, cell_id: int) -> int:
	return slots_of(repo, cell_id) - slots_used(state, cell_id)

## Begin a building: it takes build_days (data/manor_buildings.csv) from
## today and a slot until it stands. Refuses an unknown manor or building,
## one already standing or begun, a full manor, and an empty reason; logs
## into manor_log with a "begun" field.
static func start_work(repo: DataRepository, state: GameState, cell_id: int, building_code: String,
		reason: String) -> bool:
	if not is_manor(repo, cell_id) or not repo.manor_buildings.has(building_code):
		return false
	if reason.strip_edges() == "" or has_building(state, cell_id, building_code) \
			or is_building(state, cell_id, building_code) or free_slots(repo, state, cell_id) <= 0:
		return false
	var key := str(cell_id)
	if not state.manor_works.has(key):
		state.manor_works[key] = []
	var days := maxi(int(float((repo.manor_buildings[building_code] as Dictionary).get("build_days", 0))), 0)
	(state.manor_works[key] as Array).append({"building": building_code,
		"start": state.absolute_day(), "days": days})
	state.manor_log.append({"tick": state.tick, "cell": cell_id, "building": building_code,
		"begun": days, "reason": reason})
	return true

## Days a work still needs, 0 when it is done; -1 for no such work.
static func work_days_left(state: GameState, cell_id: int, building_code: String) -> int:
	for w: Dictionary in works_of(state, cell_id):
		if String(w["building"]) == building_code:
			return maxi(int(w["start"]) + int(w["days"]) - state.absolute_day(), 0)
	return -1

## How far along a work is, 0..1.
static func work_progress(state: GameState, cell_id: int, building_code: String) -> float:
	for w: Dictionary in works_of(state, cell_id):
		if String(w["building"]) == building_code:
			var days := int(w["days"])
			if days <= 0:
				return 1.0
			return clampf(float(state.absolute_day() - int(w["start"])) / float(days), 0.0, 1.0)
	return 0.0

## Cut `days` off a work in progress (spec 2026-09-14 §5: gold hurries the
## masons), never below done. Returns the days actually cut; 0 for no
## such work or an empty reason. Logs into manor_log with a "rushed" field.
static func rush_work(repo: DataRepository, state: GameState, cell_id: int, building_code: String,
		days: int, reason: String) -> int:
	if days <= 0 or reason.strip_edges() == "":
		return 0
	var key := str(cell_id)
	if not state.manor_works.has(key):
		return 0
	for w: Dictionary in state.manor_works[key]:
		if String(w["building"]) != building_code:
			continue
		var left := maxi(int(w["start"]) + int(w["days"]) - state.absolute_day(), 0)
		var cut := mini(days, left)
		if cut <= 0:
			return 0
		w["days"] = int(w["days"]) - cut
		state.manor_log.append({"tick": state.tick, "cell": cell_id, "building": building_code,
			"rushed": cut, "reason": reason})
		return cut
	return 0

## The day's step for every work: those whose days are up become
## buildings. Returns [{cell, building}] finished today, cell order.
static func advance_works(repo: DataRepository, state: GameState) -> Array:
	var done: Array = []
	var today := state.absolute_day()
	var keys: Array = state.manor_works.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var left: Array = []
		for w: Dictionary in state.manor_works[key]:
			if today - int(w["start"]) >= int(w["days"]):
				var code := String(w["building"])
				if build(repo, state, int(key), code, "finished after %d days" % int(w["days"])):
					done.append({"cell": int(key), "building": code})
			else:
				left.append(w)
		if left.is_empty():
			state.manor_works.erase(key)
		else:
			state.manor_works[key] = left
	return done

## Pull a building down, or stop a work: the slot frees and
## manor_demolish_refund of the cost comes back. Returns the refund, or
## -1 when there was nothing to pull down (or no reason).
static func demolish(repo: DataRepository, state: GameState, cell_id: int, building_code: String,
		reason: String) -> float:
	if reason.strip_edges() == "" or not repo.manor_buildings.has(building_code):
		return -1.0
	var key := str(cell_id)
	var found := false
	if has_building(state, cell_id, building_code):
		(state.manor_buildings[key] as Array).erase(building_code)
		if (state.manor_buildings[key] as Array).is_empty():
			state.manor_buildings.erase(key)
		found = true
	elif is_building(state, cell_id, building_code):
		var left: Array = []
		for w: Dictionary in state.manor_works[key]:
			if String(w["building"]) != building_code:
				left.append(w)
		if left.is_empty():
			state.manor_works.erase(key)
		else:
			state.manor_works[key] = left
		found = true
	if not found:
		return -1.0
	var refund := float((repo.manor_buildings[building_code] as Dictionary).get("cost_gold", 0)) \
		* repo.bal("manor_demolish_refund")
	state.manor_log.append({"tick": state.tick, "cell": cell_id, "building": building_code,
		"demolished": refund, "reason": reason})
	return refund

## What finished buildings on these manors add to the crown's metrics
## each tick: {treasury, grain, church_opinion, peasant_contentment, unrest}
## from the *_per_tick columns (church_bonus is church_opinion's).
static func building_effects(repo: DataRepository, state: GameState, cells: Array) -> Dictionary:
	var out := {"treasury": 0.0, "grain": 0.0, "church_opinion": 0.0,
		"peasant_contentment": 0.0, "unrest": 0.0}
	for cell: int in cells:
		out["treasury"] += building_bonus(repo, state, cell, "gold_per_tick")
		out["grain"] += building_bonus(repo, state, cell, "grain_per_tick")
		out["church_opinion"] += building_bonus(repo, state, cell, "church_bonus")
		out["peasant_contentment"] += building_bonus(repo, state, cell, "contentment_per_tick")
		out["unrest"] += building_bonus(repo, state, cell, "unrest_per_tick")
	return out

static func crown_building_effects(repo: DataRepository, state: GameState) -> Dictionary:
	return building_effects(repo, state,
		manors_of_house(repo, state, crown(state), repo.resolve_realm("player_realm")))

## Goods a manor's finished buildings make: {good: units}.
static func building_output_of(repo: DataRepository, state: GameState, cell_id: int) -> Dictionary:
	var out: Dictionary = {}
	for code: String in buildings_of(state, cell_id):
		var row: Dictionary = repo.manor_buildings.get(code, {})
		var good := String(row.get("produce_good", "")).strip_edges()
		var units := float(row.get("produce_units", 0))
		if good != "" and units > 0.0:
			out[good] = float(out.get(good, 0.0)) + units
	return out

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

# ---- focus: the chief good a manor works at (owner 2026-09-13) ---------------

## Whether a manor touches the sea — what a fishery needs.
static func is_coastal(repo: DataRepository, cell_id: int) -> bool:
	var row: Dictionary = repo.cells.get(cell_id, {})
	for n: int in (row.get("neighbor_ids", PackedInt32Array()) as PackedInt32Array):
		if MapTerrain.is_sea(repo.cells.get(n, {})):
			return true
	return false

## Whether a focus may be worked on a manor: its biome is listed (or the
## row says any) and, for a coastal focus, the sea is next door.
static func focus_allowed(repo: DataRepository, cell_id: int, focus_code: String) -> bool:
	var row: Dictionary = repo.manor_focus.get(focus_code, {})
	if row.is_empty() or not is_manor(repo, cell_id):
		return false
	if int(float(row.get("coast", 0))) > 0 and not is_coastal(repo, cell_id):
		return false
	var biomes := String(row.get("biomes", "")).strip_edges()
	if biomes == "any":
		return true
	var mine := str(int((repo.cells.get(cell_id, {}) as Dictionary).get("biome_id", -1)))
	return mine in biomes.split("|")

## The focuses a manor may work, in manor_focus.csv order — the choices
## its card offers. Geometry, cached per repo.
static func focuses_for(repo: DataRepository, cell_id: int) -> Array:
	var c := _repo_cache(repo)
	if not c.has("focuses"):
		c["focuses"] = {}
	if not c["focuses"].has(cell_id):
		var out: Array = []
		for code: String in repo.manor_focus:
			if focus_allowed(repo, cell_id, code):
				out.append(code)
		c["focuses"][cell_id] = out
	return c["focuses"][cell_id]

## What a manor works at when nobody has chosen (owner 2026-09-14: it
## follows the terrain): the first focus in file order whose default_on
## claims the cell — a biome id, `coast` for a sea neighbour, `high` for
## height at/above manor_focus_high_height, `peak` for
## manor_focus_peak_height — and that the land allows; else the first
## focus the land allows; "" for land that allows none. Cached per repo.
static func default_focus(repo: DataRepository, cell_id: int) -> String:
	var c := _repo_cache(repo)
	if not c.has("default_focus"):
		c["default_focus"] = {}
	if c["default_focus"].has(cell_id):
		return c["default_focus"][cell_id]
	var allowed := focuses_for(repo, cell_id)
	var pick := String(allowed[0]) if not allowed.is_empty() else ""
	var cell: Dictionary = repo.cells.get(cell_id, {})
	var biome := str(int(cell.get("biome_id", -1)))
	var height := float(cell.get("height", 0.0))
	# A claim on the coast outranks one on a peak, a peak the high ground,
	# and any of those a biome; ties go to file order.
	var best_rank := -1
	for code: String in repo.manor_focus:
		if not code in allowed:
			continue
		var claims := String((repo.manor_focus[code] as Dictionary).get("default_on", "")).strip_edges()
		if claims == "":
			continue
		var rank := -1
		for token: String in claims.split("|"):
			var t := token.strip_edges()
			var r := -1
			match t:
				"coast":
					r = 3 if is_coastal(repo, cell_id) else -1
				"peak":
					r = 2 if height >= repo.bal("manor_focus_peak_height") else -1
				"high":
					r = 1 if height >= repo.bal("manor_focus_high_height") else -1
				_:
					r = 0 if t == biome else -1
			rank = maxi(rank, r)
		if rank > best_rank:
			best_rank = rank
			pick = code
	c["default_focus"][cell_id] = pick
	return pick

## The focus a manor works at now: the one set, else the default.
static func focus_of(repo: DataRepository, state: GameState, cell_id: int) -> String:
	if state != null and state.manor_focus.has(str(cell_id)):
		return String((state.manor_focus[str(cell_id)] as Dictionary).get("focus", ""))
	return default_focus(repo, cell_id)

## How far a set focus has settled in, 0..1: a switch yields nothing on
## the tick it is made and everything transition_ticks later, linearly
## between. A default (never switched) focus is 1.
static func focus_ramp(repo: DataRepository, state: GameState, cell_id: int) -> float:
	if state == null or not state.manor_focus.has(str(cell_id)):
		return 1.0
	var entry: Dictionary = state.manor_focus[str(cell_id)]
	var row: Dictionary = repo.manor_focus.get(String(entry.get("focus", "")), {})
	var ticks := float(row.get("transition_ticks", 0))
	if ticks <= 0.0:
		return 1.0
	return clampf(float(state.tick - int(entry.get("since", state.tick))) / ticks, 0.0, 1.0)

## Set a manor's focus. Refuses an unknown manor or focus, one the land
## does not allow, the focus it already works, and an empty reason; logs
## into manor_log with a "focus" field.
static func set_focus(repo: DataRepository, state: GameState, cell_id: int, focus_code: String,
		reason: String) -> bool:
	if not focus_allowed(repo, cell_id, focus_code) or reason.strip_edges() == "":
		return false
	if focus_of(repo, state, cell_id) == focus_code:
		return false
	state.manor_focus[str(cell_id)] = {"focus": focus_code, "since": state.tick}
	state.manor_log.append({"tick": state.tick, "cell": cell_id, "focus": focus_code,
		"reason": reason})
	return true

## The manor's month of tax, for the card (spec 2026-09-14 §4.2): whole
## gold, the tariff of its town included, as ManorEconomy figures it. ONE
## manor — a table of them goes through RealmEconomy.tax_table, which reads
## a whole province's cached lines at a time.
static func rent_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	return float(ManorEconomy.line_of(repo, state, cell_id, state.tick)["tax"])

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
## and the land — MANOR_SYSTEM.md §5. Every figure comes off the one integer
## economy (2026-09-14): whole people, and the units of goods the manor
## ships in a month as RealmEconomy has them cached — its chief good, its
## buildings' and its town's alike, which is what the ECONOMY column counts.
static func base_value_of(repo: DataRepository, state: GameState, cell_id: int) -> float:
	return value_of_line(repo, state, cell_id, RealmEconomy.line_of(repo, state, cell_id))

## The same for a caller that already holds the manor's month — the Manor
## Master, which reads a whole province's lines at once
## (RealmEconomy.lines_table) rather than one line per row.
static func value_of_line(repo: DataRepository, state: GameState, cell_id: int,
		line: Dictionary) -> float:
	var base := float(line.get("people", 0)) / 1000.0 * repo.bal("manor_price_per_1000") \
		+ float(line.get("units", 0)) * repo.bal("manor_price_per_unit") \
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
