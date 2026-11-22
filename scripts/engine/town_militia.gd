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
	ArmyGround._put(entry, ArmyGround.town_point_m(repo, town))
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
		var changes: Array = []
		var released := 0
		var captives := 0
		for cid: String in ids:
			var co: Dictionary = state.military_cohorts[cid]
			captives += int(co["captured_current"])
			for st: String in ["fit", "wounded"]:
				if int(co[st]) > 0:
					changes.append({"cohort_id": cid, "from": st, "to": "released", "count": int(co[st])})
					released += int(co[st])
		if not changes.is_empty():
			var out := MilitaryRoster.transition(repo, state, code + ":stood_down", changes,
				"militia of %s stood down" % String((repo.burgs.get(town, {}) as Dictionary).get("label", town)))
			if out.has("error"):
				continue
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
