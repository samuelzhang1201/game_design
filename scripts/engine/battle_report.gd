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
	if not battle.has("unit_entries"):
		battle["unit_entries"] = {}
	if not battle.unit_entries.has(code):
		battle.unit_entries[code] = {"code": code, "side": side,
			"commander_id": String(state.military_rosters.get(code, {}).get("commander_id", "")),
			"supplies": int(state.regiments.get(code, state.foes.get(code, {})).get("supplies", 0)),
			"day": state.absolute_day()}
	else:
		battle.unit_entries[code].erase("exit_supplies")

## Freeze a departing cohort so later fighting elsewhere cannot rewrite this battle.
static func leave(state: GameState, battle: Dictionary, code: String) -> void:
	if battle.get("unit_entries", {}).has(code) and not battle.unit_entries[code].has("exit_supplies"):
		battle.unit_entries[code]["exit_supplies"] = int(state.regiments.get(code, state.foes.get(code, {})).get("supplies", 0))
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
			if batch.get("source_cohort", "") == id and BattleSystem.canonical(state, int(batch.get("battle_id", -1))) == int(battle["id"]):
				captured_here += int(batch.get("initial_count", int(batch.commoners) + int(batch.nobles)))
				released_captives += int(batch.get("released_count",
					batch.get("initial_count", int(batch.commoners) + int(batch.nobles)) if batch.get("disposition", "") == "released" else 0))
		counts.captured += captured_here
		counts.released += maxi(0, int(cohort.released) - int(baseline.released) - released_captives)
	return out

## Private engine truth. Delivery/presentation never reads this storage directly.
static func snapshot(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
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
		"reinforcements": battle.get("reinforcement_evidence", []).duplicate(true), "prisoners": [],
		"custody": custody_batches(repo, state, battle_id)}
	for batch: Dictionary in state.prisoner_batches.values():
		if BattleSystem.canonical(state, int(batch.get("battle_id", -1))) == battle_id:
			var captured := batch.duplicate(true)
			captured["holder_label"] = String(ArmySystem.regiment(repo, String(batch.holder_code), state).get("label", batch.holder_code)) if repo != null else batch.holder_code
			captured["named"] = []
			for person: String in batch.get("named_ids", []):
				var character: Character = state.characters.get(person) as Character
				captured.named.append({"id": person, "name": character.display_name if character != null else person})
			record.prisoners.append(captured)
	record["place"] = BattleSystem.place_label(repo, state, {"town": record.town, "place_x_m": record.place_x_m, "place_y_m": record.place_y_m}) if repo != null else "The field"
	record["duration_days"] = maxi(1, int(record.end_day) - int(record.start_day) + 1)
	record["participants"] = []
	for unit: Dictionary in battle.get("unit_entries", {}).values():
		var participant := unit.duplicate(true)
		participant["realm"] = ArmySystem.realm_of(repo, unit.code, state) if repo != null else ""
		participant["label"] = String(ArmySystem.regiment(repo, unit.code, state).get("label", unit.code)) if repo != null else unit.code
		var commander: Character = state.characters.get(unit.commander_id) as Character
		participant["commander"] = commander.display_name if commander != null else "The field officers"
		record.participants.append(participant)
	record.participants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.code) < String(b.code) if a.side == b.side else String(a.side) < String(b.side))
	record["formations"] = battle.get("formations", {}).duplicate(true)
	record["orders"] = []
	record["equipment"] = []
	record["supplies"] = []
	for unit: Dictionary in record.participants:
		record.supplies.append({"unit_code": unit.code, "before": unit.supplies,
			"after": int(unit.get("exit_supplies", state.regiments.get(unit.code, state.foes.get(unit.code, {})).get("supplies", 0)))})
	for id: String in state.battle_orders:
		var order: Dictionary = state.battle_orders[id]
		if BattleSystem.canonical(state, int(order.get("request", {}).get("battle_id", -1))) != battle_id: continue
		record.orders.append(order.duplicate(true))
		var handoff: Dictionary = order.get("result", {}).get("capture_handoff", {})
		if bool(handoff.get("accepted", false)):
			for unit: Dictionary in handoff.get("units", []):
				record.equipment.append({"unit_code": unit.unit_code, "equipment": unit.get("equipment", {}).duplicate(true), "reason": handoff.reason})
	record["events"] = battle.get("report_events", []).duplicate(true)
	for event: Dictionary in state.battle_events.values():
		if int(event.get("battle_id", -1)) == battle_id:
			record.events.append(event.duplicate(true))
	record["family_changes"] = battle.get("family_changes", []).duplicate(true)
	record["outcome"] = battle.get("report_outcome", {}).duplicate(true)
	state.battle_records[key] = record.duplicate(true)
	return record

## A later defeat changes custody, not the original capture's battle attribution.
static func custody_batches(repo: DataRepository, state: GameState, battle_id: int) -> Array:
	var changed := {}
	for event_id: String in state.prisoner_events:
		if not event_id.begins_with("battle_holder:%d:" % battle_id): continue
		var event: Dictionary = state.prisoner_events[event_id]
		var holder := String(event.get("request", {}).get("holder", ""))
		var realm := ArmySystem.realm_of(repo, holder, state) if repo != null and holder != "" else ""
		for id: String in event.get("result", {}).get("batch_ids", []):
			if not changed.has(id): changed[id] = []
			if not realm in changed[id]: changed[id].append(realm)
	var out: Array = []
	var ids := state.prisoner_batches.keys()
	ids.sort()
	for id: String in ids:
		var batch: Dictionary = state.prisoner_batches[id]
		if BattleSystem.canonical(state, int(batch.get("battle_id", -1))) != battle_id and not changed.has(id): continue
		var copy := batch.duplicate(true)
		copy["previous_holder_realms"] = changed.get(id, []).duplicate()
		out.append(copy)
	return out

## The daily journal is saved with the active battle; terminal truth freezes once.
static func note(battle: Dictionary, events: Array) -> void:
	if not battle.has("report_events"): battle["report_events"] = []
	for event: Dictionary in events:
		if int(event.get("battle_id", -1)) == int(battle["id"]) and not event in battle.report_events:
			battle.report_events.append(event.duplicate(true))

## Only this filtered copy may leave engine truth in a report courier.
static func for_realm(repo: DataRepository, record: Dictionary, realm: String) -> Dictionary:
	var out := {}
	for key: String in ["battle_id", "place", "start_day", "end_day", "duration_days", "rounds", "outcome"]:
		var value: Variant = record.get(key, {} if key == "outcome" else "")
		out[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	var side := ""
	out["participants"] = []
	var own_codes: Array[String] = []
	for unit: Dictionary in record.get("participants", []):
		if unit.get("realm", "") == realm:
			side = String(unit.side)
			own_codes.append(String(unit.code))
			out.participants.append(unit.duplicate(true))
	if side == "": return {}
	var other := "def" if side == "att" else "att"
	var foe: Dictionary = record.personnel[other]
	var enemy := {}
	for metric: String in ["dead", "wounded"]:
		var span := SpySystem.estimate(repo, int(foe[metric]), int(repo.bal("battle_foe_estimate_quality")), 0,
			int(repo.intel_facts.get("foe_losses", {}).get("round_to", 1)))
		enemy[metric] = {"lo": int(span[0]), "hi": int(span[1])}
	out.outcome["winner_label"] = "Our side" if String(out.outcome.get("winner", "")) == side else "The opposing side" if String(out.outcome.get("winner", "")) == other else "Neither side"
	out.outcome["town_label"] = String(repo.burgs.get(String(out.outcome.get("town", "")), {}).get("label", ""))
	out["personnel"] = {"own": record.personnel[side].duplicate(true), "enemy": enemy}
	out["identities"] = {}
	for identity: String in record.get("identities", {}):
		out.identities[identity] = record.identities[identity][side].duplicate(true)
	out["formations"] = {side: record.get("formations", {}).get(side, {}).duplicate(true)}
	out["reinforcements"] = []
	for row: Dictionary in record.get("reinforcements", []):
		if row.get("side", "") == side: out.reinforcements.append(row.duplicate(true))
	out["orders"] = []
	for row: Dictionary in record.get("orders", []):
		if row.get("request", {}).get("side", "") == side: out.orders.append(row.duplicate(true))
	out["events"] = []
	for row: Dictionary in record.get("events", []):
		if row.has("event_id") and row.get("side", "") == side:
			out.events.append({"event_id": row.event_id, "title": repo.event_titles.get(String(row.event_id), "Battlefield event"), "day": row.get("day", 0), "selected": row.get("selected", ""), "receipt": row.get("receipt", {}).duplicate(true)})
		elif row.get("kind", "") == "end":
			out.events.append({"kind": "end", "why": row.get("why", ""), "winner": row.get("winner", "")})
	out["prisoners"] = []
	for row: Dictionary in record.get("prisoners", []):
		if row.get("holder_code", "") in own_codes or row.get("origin_realm", "") == realm:
			out.prisoners.append(row.duplicate(true))
	out["equipment"] = []
	for row: Dictionary in record.get("equipment", []):
		# Accepted surrendered equipment is seen by its recipients, including captured enemy kit.
		if row.get("unit_code", "") in own_codes or not out.prisoners.is_empty(): out.equipment.append(row.duplicate(true))
	out["supplies"] = []
	for row: Dictionary in record.get("supplies", []):
		if row.get("unit_code", "") in own_codes: out.supplies.append(row.duplicate(true))
	out["family_changes"] = record.get("family_changes", []).duplicate(true)
	return out
