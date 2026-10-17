extends RefCounted
## Fixture mutations go through the same source-preserving personnel writer.
const Roster := preload("res://scripts/engine/military_roster.gd")

static func count(state: GameState, code: String, status: String) -> int:
	var total := 0
	for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
		total += int(state.military_cohorts[id].get(status, 0))
	return total

static func move(repo: DataRepository, state: GameState, code: String, from: String, to: String, count_value: int, token: String) -> Dictionary:
	if count_value == 0:
		return {"status": "unchanged"}
	return Roster.transfer_units(repo, state, token, [{"unit_code": code, "from": from,
		"to": to, "count": count_value}], "Personnel fixture: " + token)

static func enlist(repo: DataRepository, state: GameState, code: String, people: int, token: String) -> Dictionary:
	var unit: Dictionary = state.army_roster[code]
	return Roster.mobilize(repo, state, token, [{"id": token + ":cohort", "unit_code": code,
		"source_province": String(unit["province_code"]), "source_population_field": "rural_population",
		"identity": "commoner", "family_name": "", "stage": "active", "count": people}], "Personnel fixture: " + token)
