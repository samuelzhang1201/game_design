class_name ArmySplit
extends RefCounted
## The opening army as UNITS (owner 2026-10-07, spec docs/superpowers/specs/
## 2026-10-07-army-split-and-ground-design.md §3): every pack regiment split
## into pure-arm units of at most army_split_cap_men PERSONNEL, as even as
## equipment crews allow; a
## kingdom's guns pooled into ONE royal train at its capital; fleets as they
## are. Every unit is placed on its own camp (ArmyGround) around its
## regiment's town (or its own point in the field) and every held town's seat
## is filled by the camp's most infantry. Pure and deterministic — the same
## pack, the same roster. GameState.new_campaign writes it into the save;
## ArmySystem.roster falls back to it where there is no campaign.

static var _cache: Dictionary = {}


## Forget the per-pack splits (DataRepository.load_map, as the town grid is).
static func forget() -> void:
	_cache.clear()


## The pack's split, made once a repository; never edited — split() copies.
## Four at most are kept: the suite makes a repository copy per test.
static func _of(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if not _cache.has(key):
		if _cache.size() >= 4:
			_cache.erase(_cache.keys()[0])
		_cache[key] = _make(repo)
	return _cache[key]


## The roster where there is no campaign (the editor's previews, a reader
## with no state). Read-only.
static func roster_of(repo: DataRepository) -> Dictionary:
	return _of(repo)["roster"]


## The opening seats, town -> unit. Read-only.
static func seats_of(repo: DataRepository) -> Dictionary:
	return _of(repo)["seats"]


## A new campaign's own copy: {roster: code -> row, seats: town -> code}.
static func split(repo: DataRepository) -> Dictionary:
	return _of(repo).duplicate(true)


## `men` as ceil(men / cap) shares, the sizes at most one apart, the larger
## first: 1268 by 600 is [423, 423, 422]. [] for none.
@warning_ignore("integer_division")  # whole men
static func shares(men: int, cap: int) -> Array:
	if men <= 0 or cap <= 0:
		return []
	@warning_ignore("integer_division")
	var n := (men + cap - 1) / cap
	var out: Array = []
	for i in n:
		@warning_ignore("integer_division")
		out.append(men / n + (1 if i < men % n else 0))
	return out


## Whole equipment elements split below the personnel capacity.
static func element_shares(elements: int, crew: int, cap_men: int) -> Array:
	if crew <= 0 or crew > cap_men:
		return []
	@warning_ignore("integer_division")
	return shares(elements, cap_men / crew)


static func _make(repo: DataRepository) -> Dictionary:
	var cap := int(repo.bal("army_split_cap_men"))
	var rows: Array = repo.world_table("military", "regiments").values()
	var error := _configuration_error(repo, rows, cap)
	if not error.is_empty():
		return {"error": error, "roster": {}, "seats": {}}
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%s|%s" % [a["kingdom_code"], a["regiment_code"]] < "%s|%s" % [b["kingdom_code"], b["regiment_code"]])
	var roster: Dictionary = {}
	var taken := ArmyGround.new_taken(repo)
	var guns: Dictionary = {}
	var gun_sources: Dictionary = {}
	var home: Dictionary = {}   # kingdom -> its first land regiment's {town, centre}
	for row: Dictionary in rows:
		var code := String(row["regiment_code"])
		if String(row.get("is_naval", "0")) == "1":
			var fleet := row.duplicate()
			fleet["parent_code"] = ""
			fleet["is_royal"] = "0"
			fleet["camp_town"] = ""
			fleet["source_parts"] = []
			for arm: String in repo.world_table("military", "unit_types"):
				var count := int(float(row.get(arm, 0)))
				if count > 0:
					fleet["source_parts"].append(_source_part(repo, row, arm, count))
			roster[code] = fleet
			continue
		var k := String(row["kingdom_code"])
		guns[k] = int(guns.get(k, 0)) + int(float(row.get("artillery", 0)))
		if not gun_sources.has(k):
			gun_sources[k] = []
		var gun_count := int(float(row.get("artillery", 0)))
		if gun_count > 0:
			gun_sources[k].append(_source_part(repo, row, "artillery", gun_count))
		var at := Vector2(float(row["x"]), float(row["y"]))
		var town := _held(repo, ArmySystem.town_at(repo, at), k)
		var centre := ArmyGround.town_point_m(repo, town) if town != "" else ArmySystem.pack_to_metres(repo, at)
		if not home.has(k):
			home[k] = {"town": town, "centre": centre, "province_code": String(row.get("province_code", ""))}
		var armed := 0
		for arm_row: Dictionary in repo.army_split:
			if not bool(arm_row["pooled"]) and int(float(row.get(String(arm_row["arm"]), 0))) > 0:
				armed += 1
		for arm_row: Dictionary in repo.army_split:
			if bool(arm_row["pooled"]):
				continue
			var arm := String(arm_row["arm"])
			var equipment := int(float(row.get(arm, 0)))
			if equipment <= 0:
				continue
			var crew := int(repo.world_row("military", "unit_types", arm)["crew"])
			@warning_ignore("integer_division")
			var element_cap := cap / crew
			var parts := shares(equipment, element_cap)
			for i in parts.size():
				var unit := _unit(repo, row, arm_row, i, parts.size(), int(parts[i]), armed == 1)
				unit["camp_town"] = town
				_place(repo, unit, centre, arm, taken, town)
				roster[String(unit["regiment_code"])] = unit
	var ks := guns.keys()
	ks.sort()
	for k: String in ks:
		if int(guns[k]) > 0:
			var train := _train(repo, k, int(guns[k]), home[k])
			train["source_parts"] = gun_sources[k]
			var t_town := String(train["camp_town"])
			var t_centre: Vector2i = ArmyGround.town_point_m(repo, t_town) if t_town != "" else home[k]["centre"]
			_place(repo, train, t_centre, String(train["_arm"]), taken, t_town)
			train.erase("_arm")
			roster[String(train["regiment_code"])] = train
	_crown(repo, rows, roster)
	return {"roster": roster, "seats": _seat(repo, roster)}


## Validate the whole construction before placing any unit. Callers must
## propagate refusal instead of creating a campaign with a partial army.
static func _configuration_error(repo: DataRepository, rows: Array, cap: int) -> String:
	if cap <= 0:
		return "Army personnel split cap must be positive."
	for row: Dictionary in rows:
		# Fleets and pooled guns are exempt from subdivision, not from having
		# valid crews. Their saved provenance must also account for people.
		for arm: String in repo.world_table("military", "unit_types"):
			if int(float(row.get(arm, 0))) <= 0:
				continue
			var crew_text := String(repo.world_row("military", "unit_types", arm).get("crew", ""))
			if not crew_text.is_valid_int() or int(crew_text) <= 0:
				return "Army arm %s requires a positive whole crew size." % arm
		if String(row.get("is_naval", "0")) == "1":
			continue
		for arm_row: Dictionary in repo.army_split:
			var arm := String(arm_row["arm"])
			if bool(arm_row["pooled"]) or int(float(row.get(arm, 0))) <= 0:
				continue
			var crew := int(repo.world_row("military", "unit_types", arm).get("crew", 0))
			if crew <= 0:
				return "Army arm %s requires a positive crew size." % arm
			if crew > cap:
				return "Army arm %s crew exceeds the personnel split cap." % arm
	return ""


## `town` when kingdom `k` holds it at the start, else "".
static func _held(repo: DataRepository, town: String, k: String) -> String:
	if town == "":
		return ""
	var b: Dictionary = repo.burgs[town]
	return town if MapOwnership.owner_of(repo, null, String(b.get("province_code", ""))) == k else ""


## Put `unit` on the first free slot round `centre` — round `town` ("" in the
## field) outside its reach (R16) — its centre when none is free.
static func _place(repo: DataRepository, unit: Dictionary, centre: Vector2i, arm: String,
		taken: Dictionary, town: String) -> void:
	var slot := ArmyGround.free_slot(repo, centre, arm, taken, town)
	if slot == ArmyGround.NONE:  # a town among the blocked terrains camps on them
		slot = ArmyGround.free_slot(repo, centre, arm, taken, town, true)
	if slot == ArmyGround.NONE:
		slot = centre
	ArmyGround.take(taken, slot, ArmyGround.arm_radius(repo, arm))
	_put(repo, unit, slot)


static func _put(repo: DataRepository, unit: Dictionary, p_m: Vector2i) -> void:
	var px := ArmySystem.metres_to_pack(repo, p_m)
	unit["x"] = "%.3f" % px.x
	unit["y"] = "%.3f" % px.y


static func _unit(repo: DataRepository, parent: Dictionary, arm_row: Dictionary, i: int, n: int,
		men: int, one_arm: bool) -> Dictionary:
	var out := parent.duplicate()
	for arm: String in repo.world_table("military", "unit_types"):
		out[arm] = "0"
	out[String(arm_row["arm"])] = str(men)
	var code := "%s_%s" % [parent["regiment_code"], arm_row["code_word"]]
	if n > 1:
		code += "_%d" % (i + 1)
	out["regiment_code"] = code
	var label := String(parent["label"])
	if not one_arm:
		label = "%s %s" % [label.trim_suffix(" Regiment"), arm_row["label_word"]]
	if n > 1:
		label += " " + roman(i + 1)
	out["label"] = label
	out["parent_code"] = String(parent["regiment_code"])
	out["is_royal"] = "0"
	out["source_parts"] = [_source_part(repo, parent, String(arm_row["arm"]), men)]
	return out


## Keep the pack's actual equipment provenance before moving or pooling it.
## province_code is the recorded opening province, not an invented history
## of rural/urban recruitment; the personnel initializer applies its own rule.
static func _source_part(repo: DataRepository, row: Dictionary, arm: String, count: int) -> Dictionary:
	return {"regiment_code": String(row["regiment_code"]),
		"province_code": String(row.get("province_code", "")),
		"arm": arm, "equipment_count": count,
		"crew_per_element": int(repo.world_row("military", "unit_types", arm)["crew"])}


## A kingdom's royal train: every gun it has, quartered on its capital — or,
## with no capital, where its first land regiment (by code) stands (`home`:
## its town, centre and province), so no gun is lost. `_arm` (the pooled arm)
## is the caller's to drop.
static func _train(repo: DataRepository, k: String, men: int, home: Dictionary) -> Dictionary:
	var cap_code := String((repo.kingdoms.get(k, {}) as Dictionary).get("capital_burg", ""))
	var province := String(home["province_code"])
	if repo.burgs.has(cap_code):
		province = String(repo.burgs[cap_code].get("province_code", ""))
	else:
		cap_code = String(home["town"])
	var pooled: Dictionary = {}
	for row: Dictionary in repo.army_split:
		if bool(row["pooled"]):
			pooled = row
	var out: Dictionary = {"regiment_code": "%s_%s" % [k, pooled["code_word"]], "kingdom_code": k,
		"province_code": province,
		"label": String(pooled["label_word"]).replace("{kingdom}", String((repo.kingdoms.get(k, {}) as Dictionary).get("label", k))),
		"is_naval": "0", "parent_code": "", "is_royal": "0", "camp_town": cap_code, "_arm": String(pooled["arm"])}
	for arm: String in repo.world_table("military", "unit_types"):
		out[arm] = "0"
	out[String(pooled["arm"])] = str(men)
	return out


## The royal household (§3.1 step 5): in each kingdom, the land regiment
## nearest its capital (ties to the earlier code) gives its largest horse
## unit — else its largest foot, else its largest unit — the crown.
static func _crown(repo: DataRepository, rows: Array, roster: Dictionary) -> void:
	var codes := roster.keys()
	codes.sort()
	var ks: Dictionary = {}
	for row: Dictionary in rows:
		ks[String(row["kingdom_code"])] = true
	var sorted_ks := ks.keys()
	sorted_ks.sort()
	for k: String in sorted_ks:
		var cap: Dictionary = repo.burgs.get(String((repo.kingdoms.get(k, {}) as Dictionary).get("capital_burg", "")), {})
		if cap.is_empty():
			continue
		var seat := Vector2(float(cap["x"]), float(cap["y"]))
		var nearest := ""
		var best := INF
		for row: Dictionary in rows:
			if String(row["kingdom_code"]) != k or String(row.get("is_naval", "0")) == "1":
				continue
			var d := seat.distance_to(Vector2(float(row["x"]), float(row["y"])))
			if d < best:
				best = d
				nearest = String(row["regiment_code"])
		if nearest == "":
			continue
		var pick := ""
		for arm: String in ["cavalry", "infantry", ""]:
			var most := 0
			for c: String in codes:
				var r: Dictionary = roster[c]
				if String(r["parent_code"]) != nearest:
					continue
				var men := int(MapObjects.regiment_size(repo, r)) if arm == "" else int(float(r.get(arm, 0)))
				if men > most:
					most = men
					pick = c
			if pick != "":
				break
		if pick != "":
			roster[pick]["is_royal"] = "1"


## Every held town's seat (§4.4): among the holder's land units camped
## around it, the most infantry (ties to the earlier code), else the largest;
## that unit steps onto the town's point.
static func _seat(repo: DataRepository, roster: Dictionary) -> Dictionary:
	var by_town: Dictionary = {}
	var codes := roster.keys()
	codes.sort()
	for c: String in codes:
		var town := String(roster[c].get("camp_town", ""))
		if town != "":
			if not by_town.has(town):
				by_town[town] = []
			(by_town[town] as Array).append(c)
	var seats: Dictionary = {}
	var towns := by_town.keys()
	towns.sort()
	for town: String in towns:
		var pick := ""
		var best := 0
		for c: String in by_town[town]:
			var foot := int(float(roster[c].get("infantry", 0)))
			if foot > best:
				best = foot
				pick = c
		if pick == "":
			for c: String in by_town[town]:
				var size := int(MapObjects.regiment_size(repo, roster[c]))
				if size > best:
					best = size
					pick = c
		if pick != "":
			seats[town] = pick
			_put(repo, roster[pick], ArmyGround.town_point_m(repo, town))
	return seats


## 1 -> I, 4 -> IV, 12 -> XII.
static func roman(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	for i in vals.size():
		while n >= int(vals[i]):
			out += String(syms[i])
			n -= int(vals[i])
	return out


## Reconstruct and validate saved equipment provenance without rebuilding its army.
static func saved_sources(repo: DataRepository, unit: Dictionary) -> Dictionary:
	var types := repo.world_table("military", "unit_types")
	var parts: Array = unit.get("source_parts", []).duplicate(true)
	var reconstructed := parts.is_empty()
	var code := String(unit.get("regiment_code", ""))
	var realm := String(unit.get("kingdom_code", ""))
	if code.is_empty() or not repo.kingdoms.has(realm):
		return {"error": "Saved equipment needs a known realm and unit ID."}
	for arm: String in types:
		if not is_whole_count(unit.get(arm, 0)) or not is_whole_count(types[arm].get("crew", 0)) or int(types[arm].get("crew", 0)) <= 0:
			return {"error": "Invalid saved equipment or crew: " + code}
	if reconstructed:
		var originals := repo.world_table("military", "regiments")
		var pooled := false
		for definition: Dictionary in repo.army_split:
			if bool(definition.get("pooled", false)) and String(definition.get("arm", "")) == "artillery" \
					and int(unit.get("artillery", 0)) > 0:
				pooled = true
		if pooled:
			var sources: Array = []
			var weights: Array = []
			var keys := originals.keys()
			keys.sort()
			var authored_train := false
			for definition: Dictionary in repo.army_split:
				if bool(definition.get("pooled", false)) and code == "%s_%s" % [realm, definition.get("code_word", "")]:
					authored_train = true
			for key: String in keys:
				if not authored_train:
					continue
				var source: Dictionary = originals[key]
				if source.get("kingdom_code", "") == realm and int(source.get("artillery", 0)) > 0:
					sources.append(source)
					weights.append(int(source["artillery"]))
			if sources.is_empty():
				if not repo.provinces.has(String(unit.get("province_code", ""))):
					return {"error": "Saved royal train has no documented or estimated origin."}
				var estimated := _migration_part(unit, "artillery", int(unit["artillery"]), int(types["artillery"]["crew"]))
				estimated["origin_basis"] = "estimated_saved_garrison"
				estimated["origin_reason"] = "Original pooled sources unrecorded; origin estimated from saved garrison province " + String(unit["province_code"])
				parts.append(estimated)
			var counts := BattleSystem.apportion(weights, int(unit["artillery"]))
			for i: int in sources.size():
				if int(counts[i]) > 0:
					parts.append(_migration_part(sources[i], "artillery", int(counts[i]), int(types["artillery"]["crew"])))
		else:
			var parent := String(unit.get("parent_code", ""))
			var source: Dictionary = originals.get(parent if parent != "" else code, {})
			if source.is_empty() or source.get("kingdom_code", "") != realm:
				return {"error": "Saved unit has no documented parent origin: " + code}
			for arm: String in types:
				var count := int(unit.get(arm, 0))
				if count > 0:
					if int(source.get(arm, 0)) <= 0:
						return {"error": "Saved parent did not supply this arm: " + code}
					parts.append(_migration_part(source, arm, count, int(types[arm]["crew"])))
	var totals: Dictionary = {}
	for part: Dictionary in parts:
		var arm := String(part.get("arm", ""))
		if not types.has(arm) or not repo.provinces.has(String(part.get("province_code", ""))) \
				or String(part.get("regiment_code", "")).is_empty() \
				or not is_whole_count(part.get("equipment_count", -1)) or int(part.get("equipment_count", 0)) <= 0 \
				or not is_whole_count(part.get("crew_per_element", -1)) or int(part.get("crew_per_element", 0)) != int(types[arm]["crew"]):
			return {"error": "Invalid saved equipment provenance: " + code}
		totals[arm] = int(totals.get(arm, 0)) + int(part["equipment_count"])
	for arm: String in types:
		if int(totals.get(arm, 0)) != int(unit.get(arm, 0)):
			return {"error": "Saved equipment and origin counts disagree: " + code}
	return {"parts": parts, "reconstructed": reconstructed}

static func _migration_part(source: Dictionary, arm: String, count: int, crew: int) -> Dictionary:
	return {"regiment_code": String(source["regiment_code"]), "province_code": String(source.get("province_code", "")),
		"arm": arm, "equipment_count": count, "crew_per_element": crew}

static func is_whole_count(value: Variant) -> bool:
	if value is String:
		if not value.is_valid_int():
			return false
		return int(value) >= 0
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and float(value) >= 0 and float(value) == floor(float(value))
