class_name BattleReport
extends RefCounted

## First entry owns the baseline even if a reinforcement leaves and rejoins.
static func enroll(state: GameState, battle: Dictionary, code: String, side: String) -> void:
	if not battle.has("personnel_entries"):
		battle["personnel_entries"] = {}
	for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
		if battle.personnel_entries.has(id):
			var previous: Dictionary = battle.personnel_entries[id]
			if previous.has("exit_counts"):
				var outside: Dictionary = previous.get("outside_delta", {})
				for status: String in ["dead", "captured_current", "released"]:
					outside[status] = int(previous.exit_counts[status]) - int(state.military_cohorts[id].get(status, 0))
				previous["outside_delta"] = outside
				# Off-field losses stay survivors of their earlier visit; healing can change live status.
				previous["away_survivors"] = maxi(0, int(previous.exit_counts.fit) + int(previous.exit_counts.wounded)
					- int(state.military_cohorts[id].fit) - int(state.military_cohorts[id].wounded))
				previous.erase("exit_counts")
			continue
		var cohort: Dictionary = state.military_cohorts[id]
		if cohort.get("stage", "") != "active":
			continue
		var counts := {}
		for status: String in MilitaryRoster.PERSONNEL_STATES:
			counts[status] = int(cohort.get(status, 0))
		battle.personnel_entries[id] = {"unit_code": code, "side": side, "counts": counts,
			"identity": String(cohort.get("identity", "")), "person_id": String(cohort.get("person_id", ""))}

## Freeze a departing cohort so later fighting elsewhere cannot rewrite this battle.
static func leave(state: GameState, battle: Dictionary, code: String) -> void:
	for id: String in battle.get("personnel_entries", {}):
		var entry: Dictionary = battle.personnel_entries[id]
		if entry.unit_code == code and not entry.has("exit_counts"):
			entry["exit_counts"] = _counts(state, id, entry)

static func _counts(state: GameState, id: String, entry: Dictionary) -> Dictionary:
	if entry.has("exit_counts"):
		return entry.exit_counts
	var counts := {}
	for status: String in MilitaryRoster.PERSONNEL_STATES:
		counts[status] = int(state.military_cohorts[id].get(status, 0)) + int(entry.get("outside_delta", {}).get(status, 0))
	counts["fit"] += int(entry.get("away_survivors", 0))
	return counts

static func tally(state: GameState, battle: Dictionary, identity := "") -> Dictionary:
	var out := {}
	for side: String in BattleSystem.SIDES:
		out[side] = {"participants": 0, "fit": 0, "wounded": 0, "dead": 0, "captured": 0, "released": 0}
	var ids: Array = battle.get("personnel_entries", {}).keys()
	ids.sort()
	for id: String in ids:
		var entry: Dictionary = battle.personnel_entries[id]
		if identity != "" and entry.identity != identity:
			continue
		var baseline: Dictionary = entry.counts
		var cohort := _counts(state, id, entry)
		var counts: Dictionary = out[entry.side]
		counts.participants += int(baseline.fit) + int(baseline.wounded)
		counts.fit += int(cohort.fit)
		counts.wounded += int(cohort.wounded)
		counts.dead += int(cohort.dead) - int(baseline.dead)
		var captured_here := 0
		var released_captives := 0
		for batch: Dictionary in state.prisoner_batches.values():
			if batch.get("source_cohort", "") == id and int(batch.get("battle_id", -1)) == int(battle["id"]):
				captured_here += int(batch.get("initial_count", int(batch.commoners) + int(batch.nobles)))
				released_captives += int(batch.get("released_count",
					batch.get("initial_count", int(batch.commoners) + int(batch.nobles)) if batch.get("disposition", "") == "released" else 0))
		counts.captured += captured_here
		counts.released += maxi(0, int(cohort.released) - int(baseline.released) - released_captives)
	return out

## Private engine truth. Delivery/presentation never reads this storage directly.
static func snapshot(_repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
	var key := str(battle_id)
	if state.battle_records.has(key):
		return (state.battle_records[key] as Dictionary).duplicate(true)
	var battle := BattleSystem.battle_by_id(state, battle_id)
	if battle.is_empty():
		return {"error": "No battlefield exists for this snapshot."}
	var record := {"battle_id": battle_id, "start_day": int(battle.get("start_day", state.absolute_day())),
		"end_day": state.absolute_day(), "rounds": int(battle.get("rounds", 0)),
		"place_x_m": int(battle.get("place_x_m", 0)), "place_y_m": int(battle.get("place_y_m", 0)),
		"town": String(battle.get("town", "")), "personnel": tally(state, battle),
		"identities": {"commoner": tally(state, battle, "commoner"), "noble": tally(state, battle, "noble")},
		"entries": battle.get("personnel_entries", {}).duplicate(true),
		"reinforcements": battle.get("reinforcement_evidence", []).duplicate(true), "prisoners": []}
	for batch: Dictionary in state.prisoner_batches.values():
		if int(batch.get("battle_id", -1)) == battle_id:
			record.prisoners.append(batch.duplicate(true))
	state.battle_records[key] = record.duplicate(true)
	return record
