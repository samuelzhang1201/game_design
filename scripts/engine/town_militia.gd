class_name TownMilitia
extends RefCounted
## A besieged town's militia (player siege spec §5, step 4a). A town with no
## defenders when its siege opens raises ONE unit from its townsfolk:
##
##   men(arm) = min(population x men_permille / 1000, men_cap), whole crews
##
## for each row of data/battle/town_militia.csv of the town's best works
## (citadel over walls over none), the arms in file order each taking at most
## what is left of what the province can still mobilise (MilitaryPopulation.
## available, urban) and of army_living_cap_men. The men are enlisted through
## MilitaryRoster.mobilize (no population debit: only a death debits it) and
## released when the siege ends ("militia of <town> stood down"). The unit is
## an ordinary one on the town's seat — in `regiments` for a crown town, in
## `foes` (host "") for any other — marked `militia_town`, and never marches.
## A foreign town's standing roster units are WOKEN as its defenders first
## (wake, send_back), and a town that has them raises none. The enemy weighs
## the militia an empty town would raise (defend_power).

const FIELD := "urban_population"


## The town's best works: "citadel", "walls" or "town" (ArmySystem.works_of's
## test, read from the burg).
static func works_of_town(repo: DataRepository, town: String) -> String:
	var feats := String((repo.burgs.get(town, {}) as Dictionary).get("features", "")).split("|")
	if "citadel" in feats:
		return "citadel"
	if "walls" in feats:
		return "walls"
	return "town"


## Kingdom `k`'s land roster units with no state yet (in neither `foes` nor
## `regiments`) on `town`'s seat or camped by it (`camp_town`), in code order:
## the town's standing garrison.
static func standing_at(repo: DataRepository, state: GameState, town: String, k: String) -> Array:
	var seat := ArmyGround.seat_of(repo, state, town)
	var out: Array = []
	for c: String in state.army_roster:
		var r: Dictionary = state.army_roster[c]
		if String(r["kingdom_code"]) == k and String(r.get("is_naval", "0")) != "1" \
				and not state.foes.has(c) and not state.regiments.has(c) \
				and (c == seat or String(r.get("camp_town", "")) == town):
			out.append(c)
	out.sort()
	return out


## Wakes siege `id`'s standing garrison (standing_at of the record's
## defender) when the defender is not the crown (its units always have
## state): each goes into `foes` with its ArmySystem.starting_state, `host` ""
## and `garrison_of` the town, an ordinary foe from then on (a seat holder
## keeps its seat, so it fights from the works). The record's `woken` lists
## them. Returns their codes.
static func wake(repo: DataRepository, state: GameState, id: String) -> Array:
	var rec: Dictionary = state.sieges.get(id, {})
	var town := String(rec.get("town", ""))
	var defender := String(rec.get("defender", ""))
	if town == "" or defender == "" or defender == repo.resolve_realm("player_realm"):
		return []
	var codes := standing_at(repo, state, town, defender)
	for c: String in codes:
		var entry := ArmySystem.starting_state(repo, state.army_roster[c], state)
		entry["host"] = ""
		entry["garrison_of"] = town
		state.foes[c] = entry
	(rec.get_or_add("woken", []) as Array).append_array(codes)
	return codes


## Every woken unit (a foe with `garrison_of`) no siege record lists and in no
## battle, in code order: alive, at its post (at_post) and its kingdom still
## holding the town,
## it goes back to a standing roster unit (its `foes` entry erased; its losses
## stay in its personnel roster, its seat is kept), event {kind
## "garrison_returned", unit, town, day}; otherwise it stays an ordinary foe
## and loses the mark. Run at the end of SiegeSystem.settle_day.
static func send_back(repo: DataRepository, state: GameState) -> Array:
	var listed := {}
	for id: String in state.sieges:
		for c: Variant in state.sieges[id].get("woken", []):
			listed[String(c)] = true
	var codes: Array = []
	for c: String in state.foes:
		if String(state.foes[c].get("garrison_of", "")) != "" and not listed.has(c) \
				and BattleSystem.battle_of(state, c).is_empty():
			codes.append(c)
	codes.sort()
	var events: Array = []
	for code: String in codes:
		var town := String(state.foes[code]["garrison_of"])
		if MilitaryRoster.living(state, code) > 0 and at_post(repo, state, code, town) \
				and SiegeSystem.holder_of(repo, state, town) == ArmySystem.realm_of(repo, code, state):
			state.foes.erase(code)
			events.append({"kind": "garrison_returned", "unit": code, "town": town, "day": state.absolute_day()})
		else:
			state.foes[code].erase("garrison_of")
	return events


## True when woken unit `code` stands at its post for `town`: woken for it
## (`garrison_of`), not on the march, and at the town (SiegeSystem.at_town) or
## within battle_contact_km of its own camp spot (its roster row's point) — a
## camp is invested with its town, as a crown camp is (ArmyGround.camped_by).
static func at_post(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	var e: Dictionary = state.foes.get(code, {})
	if String(e.get("garrison_of", "")) != town or String(e.get("order", "")) == ArmySystem.ORDER_MARCH:
		return false
	if SiegeSystem.at_town(repo, state, code, town):
		return true
	var r: Dictionary = state.army_roster.get(code, {})
	var home := ArmySystem.pack_to_metres(repo, Vector2(float(r.get("x", 0)), float(r.get("y", 0))))
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	var dx := int(e.get("x_m", 0)) - home.x
	var dy := int(e.get("y_m", 0)) - home.y
	return dx * dx + dy * dy <= reach * reach


## The defence the enemy reads in the militia `town` would raise (spec §5,
## EnemyAi._gather): ArmySystem.power_of_arms "defend" of size's men (whole
## crews as elements), at the start training and morale, on the town's ground
## behind its works at full strength (spec §14). 0 for no militia.
static func defend_power(repo: DataRepository, state: GameState, town: String) -> int:
	var arms := size(repo, state, town)
	if arms.is_empty():
		return 0
	var types := repo.world_table("military", "unit_types")
	var elements := {}
	var men := 0
	for arm: String in arms:
		@warning_ignore("integer_division")  # size gave whole crews
		elements[arm] = int(arms[arm]) / maxi(1, int((types.get(arm, {}) as Dictionary).get("crew", 1)))
		men += int(arms[arm])
	var b: Dictionary = repo.burgs[town]
	return ArmySystem.power_of_arms(repo, elements, men, int(repo.bal("army_start_training")),
		int(repo.bal("army_start_morale")), "defend", ArmySystem.terrain_at(repo, Vector2(float(b["x"]), float(b["y"]))),
		works_of_town(repo, town))


## The militia `town` would raise: arm -> men, in table order, arms with no men
## left out. `state` null reads the table alone (no province bound).
static func size(repo: DataRepository, state: GameState, town: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(town, {})
	if b.is_empty():
		return {}
	var people := int(float(b.get("population", 0)))
	var works := works_of_town(repo, town)
	var types := repo.world_table("military", "unit_types")
	var left := int(repo.bal("army_living_cap_men"))
	if state != null:
		left = mini(left, MilitaryPopulation.available(repo, state, String(b.get("province_code", "")), FIELD))
	var out: Dictionary = {}
	for row: Dictionary in repo.town_militia:
		if String(row["works"]) != works:
			continue
		var crew := maxi(1, int((types.get(String(row["arm"]), {}) as Dictionary).get("crew", 1)))
		@warning_ignore("integer_division")  # whole men, whole crews
		var men := mini(mini(people * int(row["men_permille"]) / 1000, int(row["men_cap"])), maxi(0, left)) / crew * crew
		if men > 0:
			out[String(row["arm"])] = int(out.get(String(row["arm"]), 0)) + men
			left -= men
	return out


## Raises the militia of siege `id`'s town when it has no defenders
## (SiegeSystem.defenders_of) and no unit on its seat (step 4b wakes a
## standing one): one unit "militia:<id>" of the size (size), for the record's
## defender, its men one commoner cohort enlisted from the town's province
## (MilitaryRoster.mobilize, reason "militia of <town> raised"), an army_roster
## row with its equipment, standing on the town's seat. The record's `militia`
## lists it. Returns the unit's code, "" when none is raised.
static func raise(repo: DataRepository, state: GameState, id: String) -> String:
	var rec: Dictionary = state.sieges.get(id, {})
	var town := String(rec.get("town", ""))
	if town == "" or not SiegeSystem.defenders_of(repo, state, town).is_empty() \
			or ArmyGround.seat_of(repo, state, town) != "":
		return ""
	var arms := size(repo, state, town)
	if arms.is_empty():
		return ""
	var b: Dictionary = repo.burgs[town]
	var prov := String(b["province_code"])
	var label := String(b.get("label", town))
	var code := "militia:" + id
	var total := 0
	for arm: String in arms:
		total += int(arms[arm])
	var enlisted := MilitaryRoster.mobilize(repo, state, code, [{"id": code + ":commoner", "unit_code": code,
		"count": total, "source_province": prov, "source_population_field": FIELD, "identity": "commoner",
		"family_name": "", "stage": "active", "person_id": ""}], "militia of %s raised" % label)
	if enlisted.has("error"):
		return ""
	var defender := String(rec["defender"])
	var types := repo.world_table("military", "unit_types")
	var row := {"regiment_code": code, "label": "%s militia" % label, "kingdom_code": defender,
		"province_code": prov, "parent_code": "", "organization_arm": String(arms.keys()[0]), "is_royal": "0",
		"is_naval": "0", "camp_town": town, "x": String(b["x"]), "y": String(b["y"]), "source_parts": []}
	for kind: String in types:
		row[kind] = "0"
	for arm: String in arms:
		var crew := maxi(1, int((types[arm] as Dictionary).get("crew", 1)))
		@warning_ignore("integer_division")  # size gave whole crews
		var elements := int(arms[arm]) / crew
		row[arm] = str(elements)
		(row["source_parts"] as Array).append({"regiment_code": code, "province_code": prov, "arm": arm,
			"equipment_count": elements, "crew_per_element": crew})
	state.army_roster[code] = row
	var entry := ArmySystem.starting_state(repo, row, state)
	ArmyGround._put(entry, _stand(repo, state, code, town, String(row["organization_arm"])))
	entry["camp_town"] = town
	entry["militia_town"] = town
	var crown := defender == repo.resolve_realm("player_realm")
	if crown:
		state.regiments[code] = entry
	else:
		entry["host"] = ""
		state.foes[code] = entry
	state.town_seat[town] = code
	if crown:
		LawSystem.on_settle(repo, state, code)
	(rec.get_or_add("militia", []) as Array).append(code)
	return code


## Where the militia `code` stands: the town's point, or with the clearance
## rule on the nearest free slot round it (a host column may already stand on
## the point: the record opens as it arrives), as EnemyAi.spawn places a host.
static func _stand(repo: DataRepository, state: GameState, code: String, town: String, arm: String) -> Vector2i:
	var at := ArmyGround.town_point_m(repo, town)
	if not ArmyGround.clearance_on(repo):
		return at
	var taken := ArmyGround.held_taken(repo, state, code)
	var slot := ArmyGround.free_slot(repo, at, arm, taken, "")
	if slot == ArmyGround.NONE:
		slot = ArmyGround.free_slot(repo, at, arm, taken, "", true)
	return at if slot == ArmyGround.NONE else slot


## A militia beaten in battle breaks up into its town instead of withdrawing
## (it never marches; BattleSystem._start_retreat asks this first): its fit
## and wounded are released at once (event "<code>:broke", reason "militia of
## <town> broke"), so the battle reads it broken and it leaves; its husk
## stands down with its siege (stand_down). Returns the men released.
static func disperse(repo: DataRepository, state: GameState, code: String) -> int:
	var town := town_of(state, code)
	if town == "" or state.military_events.has(code + ":broke"):
		return 0
	return int(_release(repo, state, code, code + ":broke", "militia of %s broke" % _label(repo, town)).get("released", 0))


## Releases every fit and wounded man of unit `code` (MilitaryRoster.
## transition, event `event`, `reason`): {released, captives} (its captives
## still held), or the transition's {error}.
static func _release(repo: DataRepository, state: GameState, code: String, event: String, reason: String) -> Dictionary:
	var changes: Array = []
	var released := 0
	var captives := 0
	for cid: String in (state.military_rosters.get(code, {}) as Dictionary).get("cohort_ids", []):
		var co: Dictionary = state.military_cohorts[cid]
		captives += int(co["captured_current"])
		for st: String in ["fit", "wounded"]:
			if int(co[st]) > 0:
				changes.append({"cohort_id": cid, "from": st, "to": "released", "count": int(co[st])})
				released += int(co[st])
	if not changes.is_empty():
		var out := MilitaryRoster.transition(repo, state, event, changes, reason)
		if out.has("error"):
			return out
	return {"released": released, "captives": captives}


static func _label(repo: DataRepository, town: String) -> String:
	return String((repo.burgs.get(town, {}) as Dictionary).get("label", town))


## The town whose militia `code` is, "" for any other unit.
static func town_of(state: GameState, code: String) -> String:
	return String((state.foes.get(code, state.regiments.get(code, {})) as Dictionary).get("militia_town", ""))


## Every militia unit no siege record lists (its siege is over) and in no
## battle stands down, in code order: its fit and wounded are released
## (MilitaryRoster.transition, event "<code>:stood_down", reason "militia of
## <town> stood down"; release adds no one to the population, a death alone
## took one off); with no captive of it left (PrisonerSystem holds those), its
## entry, roster row, personnel roster, cohorts and seat go. Run at the end of
## SiegeSystem.settle_day. Events {kind "militia_stood_down", unit, town,
## released, day}.
static func stand_down(repo: DataRepository, state: GameState) -> Array:
	var listed := {}
	for id: String in state.sieges:
		for c: Variant in state.sieges[id].get("militia", []):
			listed[String(c)] = true
	var codes: Array = []
	for c: String in state.regiments.keys() + state.foes.keys():
		if town_of(state, c) != "" and not listed.has(c) and BattleSystem.battle_of(state, c).is_empty():
			codes.append(c)
	codes.sort()
	var events: Array = []
	for code: String in codes:
		var town := town_of(state, code)
		var ids: Array = (state.military_rosters.get(code, {}) as Dictionary).get("cohort_ids", [])
		var gone := _release(repo, state, code, code + ":stood_down", "militia of %s stood down" % _label(repo, town))
		if gone.has("error"):
			continue
		var released := int(gone["released"])
		var captives := int(gone["captives"])
		if captives == 0:
			for cid: String in ids:
				state.military_cohorts.erase(cid)
			state.military_rosters.erase(code)
			state.army_roster.erase(code)
			state.regiments.erase(code)
			state.foes.erase(code)
			if String(state.town_seat.get(town, "")) == code:
				state.town_seat.erase(town)
		elif released == 0:
			continue   # ponytail: a husk kept for its captives is swept daily; cheap while militia are few
		events.append({"kind": "militia_stood_down", "unit": code, "town": town, "released": released,
			"day": state.absolute_day()})
	return events
