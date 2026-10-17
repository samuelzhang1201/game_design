class_name BattleEvents
extends RefCounted
## Engine journal, never a view model. Empty event_id is a saved no-event day.

static func offer(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
	var event := _offer_record(repo, state, battle_id)
	if event.is_empty():
		return {"status": "none"}
	if event.get("selected", "") == "" and event.authority == "commander":
		var choice := commander_choice(repo, state, event)
		var result := choose(repo, state, String(event.token), choice)
		if result.status != "accepted":
			return {"status": "none"}
		event = state.battle_events[event.token].duplicate(true)
	if event.get("selected", "") == "":
		return {"status": "blocked", "decision": event}
	return {"status": "resolved", "event": event}


static func _offer_record(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
	var battle := BattleSystem.battle_by_id(state, battle_id)
	if battle.is_empty():
		return {}
	# A local unresolved offer survives a new day and the king's departure.
	for saved: Dictionary in state.battle_events.values():
		if int(saved.get("battle_id", -1)) == battle_id and saved.get("event_id", "") != "" and saved.get("selected", "") == "":
			return saved.duplicate(true)
	var token := "battle-event:%d:%d" % [battle_id, state.absolute_day()]
	if state.battle_events.has(token):
		var saved: Dictionary = state.battle_events[token]
		return saved.duplicate(true) if saved.get("event_id", "") != "" else {}
	var record := {"token": token, "kind": "battle_event", "battle_id": battle_id,
		"day": state.absolute_day(), "event_id": "", "selected": "", "received_day": -1}
	state.battle_events[token] = record
	if not battle.has("event_checks"):
		battle["event_checks"] = {}
	battle.event_checks[str(state.absolute_day())] = {"token": token, "event_id": ""}
	var candidates: Array[Dictionary] = []
	var ids := repo.battle_events.keys()
	ids.sort()
	for id: String in ids:
		var row: Dictionary = repo.battle_events[id]
		var cooling := false
		for previous: Dictionary in state.battle_events.values():
			if int(previous.get("battle_id", -1)) == battle_id and previous.get("event_id", "") == id \
					and state.absolute_day() - int(previous["day"]) < int(row["cooldown_days"]):
				cooling = true
		if cooling:
			continue
		var evidence := _trigger(repo, state, battle, row)
		if not evidence.is_empty():
			candidates.append({"row": row, "evidence": evidence})
	if candidates.is_empty():
		return {}
	# One shared-stream draw picks both occurrence and weighted event.
	var total := 0
	for candidate: Dictionary in candidates:
		total += int(candidate.row.weight)
	var draw := state.rng.randi_range(0, total * 1000 - 1)
	record["draw"] = draw
	battle.event_checks[str(state.absolute_day())]["draw"] = draw
	var cursor := 0
	for candidate: Dictionary in candidates:
		var row: Dictionary = candidate.row
		var band := int(row.weight) * 1000
		if draw < cursor + band:
			if draw - cursor >= int(row.weight) * int(row.chance_permille):
				return {}
			record.merge(candidate.evidence)
			record["evidence"] = candidate.evidence.duplicate(true)
			record["event_id"] = row.event_id
			record["phase"] = row.phase
			battle.event_checks[str(state.absolute_day())]["event_id"] = row.event_id
			break
		cursor += band
	record["known_context"] = {"morale": int(state.regiments[record.unit].morale), "observations": state.sightings.duplicate(true)}
	record["authority"] = "king" if KingSystem.present(repo, state, battle_id) else "commander"
	record["commander_id"] = String(state.military_rosters.get(record.unit, {}).get("commander_id", ""))
	record["choices"] = []
	for option: Dictionary in choices_for(repo, state, record):
		if option.legal:
			record.choices.append(option.id)
	if record.choices.is_empty():
		record["event_id"] = ""
		return {}
	return record.duplicate(true)


static func choices_for(repo: DataRepository, state: GameState, event: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var battle := BattleSystem.battle_by_id(state, int(event.get("battle_id", -1)))
	var unit := String(event.get("unit", ""))
	var target_present: bool = not battle.is_empty() and unit in battle.get(String(event.get("side", "")), []) \
		and state.regiments.has(unit) and not bool(state.regiments[unit].get("captured", false))
	for row: Dictionary in repo.battle_event_choices:
		if row.event_id != event.get("event_id", ""):
			continue
		if row.effect == "report" and target_present:
			continue
		if row.effect != "report" and not target_present:
			continue
		var command_refusal := ""
		if row.effect == "charge":
			command_refusal = BattleOrders.refusal(repo, state, {"id": String(event.get("token", "event-charge")),
				"battle_id": int(event.battle_id), "side": String(event.side), "kind": "attack", "params": {"regiment": unit}})
		var reason := ""
		if row.effect == "report":
			pass
		elif not target_present:
			reason = "The affected regiment is no longer on this battlefield."
		elif command_refusal != "":
			reason = command_refusal
		elif not String(row.action) in BattleRules.legal_actions(repo, state, int(battle.id), String(event.side)) \
				or (row.action == "charge" and not "attack" in BattleRules.legal_actions(repo, state, int(battle.id), String(event.side))):
			reason = "The received military law or frozen agreement bars this action."
		elif event.event_id == "ev_33" and (not String(event.unit) in battle.get("event_reinforcements", []) or String(event.unit) in battle.get("event_reinforcements_consumed", [])):
			reason = "This reinforcement has already been committed or retained."
		elif int(row.gold) > BattleOrders.available_gold(state):
			reason = "The treasury cannot afford this choice after promised rewards."
		elif row.effect == "commit" and event.event_id != "ev_33" and _reserves(repo, state, battle, String(event.side)).is_empty():
			reason = "No fit reserve is waiting on this battlefield."
		elif row.effect in ["collect", "destroy"] and not _can_take_food(repo, state, battle, event):
			reason = "The captured food is no longer available."
		out.append({"id": String(row.choice_id), "label": String(row.label), "gold": int(row.gold),
			"reason": reason, "effects_text": String(row.effects_text), "legal": reason.is_empty()})
	return out


static func choose(repo: DataRepository, state: GameState, token: String, choice: String) -> Dictionary:
	if not state.battle_events.has(token) or state.battle_events[token].get("event_id", "") == "":
		return {"status": "stale"}
	var event: Dictionary = state.battle_events[token]
	if event.get("selected", "") != "":
		return {"status": "duplicate", "receipt": event.get("receipt", {}).duplicate(true)}
	var legal := false
	for option: Dictionary in choices_for(repo, state, event):
		if option.id == choice:
			if not option.legal:
				return {"status": "invalid", "reason": option.reason}
			legal = true
	if not legal:
		return {"status": "invalid", "reason": "This choice does not belong to this event."}
	var row: Dictionary = {}
	for candidate: Dictionary in repo.battle_event_choices:
		if candidate.event_id == event.event_id and candidate.choice_id == choice:
			row = candidate
	var battle := BattleSystem.battle_by_id(state, int(event.battle_id))
	var effects: Array = []
	var reason := String(row.reason)
	if int(row.gold) > 0:
		state.metrics.treasury -= int(row.gold)
		effects.append({"metric": "treasury", "delta": -int(row.gold), "reason": reason})
	var unit := String(event.unit)
	var entry: Dictionary = state.regiments.get(unit, {})
	if int(row.morale) != 0:
		var before := int(entry.morale)
		entry.morale = clampi(before + int(row.morale), 0, 100)
		effects.append({"unit": unit, "metric": "morale", "delta": int(entry.morale) - before, "reason": reason})
	if int(row.power_permille) != 1000 or row.effect == "charge":
		if not battle.has("event_modifiers"):
			battle["event_modifiers"] = []
		battle.event_modifiers.append({"token": token, "unit": unit, "until_day": state.absolute_day() + int(row.duration_days) - 1,
			"permille": int(row.power_permille), "exposure_permille": 1000 + int(row.amount) if row.effect == "charge" else 1000, "reason": reason})
	_apply_special(repo, state, battle, event, row, effects)
	event["selected"] = choice
	event["reason"] = reason if event.authority == "king" else "Commander %s chose %s from lawful affordable options using own morale, skills and personality. %s" % [String(event.commander_id), choice, reason]
	event["received_day"] = state.absolute_day() if event.authority == "king" else -1
	event["receipt"] = {"choice": choice, "reason": event.reason, "effects": effects, "day": state.absolute_day()}
	return {"status": "accepted", "receipt": event.receipt.duplicate(true)}


## Scores use the affected unit's real commander and own observable conditions only.
static func commander_choice(repo: DataRepository, state: GameState, event: Dictionary) -> String:
	var character: Character = state.characters.get(String(state.military_rosters.get(String(event.get("unit", "")), {}).get("commander_id", ""))) as Character
	var best := ""
	var best_score := -2147483648
	var options := choices_for(repo, state, event)
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	for option: Dictionary in options:
		if not option.legal:
			continue
		for row: Dictionary in repo.battle_event_choices:
			if row.event_id != event.event_id or row.choice_id != option.id:
				continue
			var score := int(row.score) + int(row.morale) * (100 - int(event.get("known_context", {}).get("morale", 100)))
			if character != null:
				score += int(row.boldness) * int(character.attributes.get("boldness", 0))
				score += int(row.compassion) * int(character.attributes.get("compassion", 0))
				score += int(row.martial) * int(character.skills.get("sk_martial", 0))
			if score > best_score:
				best_score = score
				best = option.id
	return best


static func factors(state: GameState, battle: Dictionary, unit: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for modifier: Dictionary in battle.get("event_modifiers", []):
		if modifier.unit == unit and int(modifier.until_day) >= state.absolute_day():
			out.append({"source": String(modifier.token), "category": "action", "permille": int(modifier.permille), "reason": String(modifier.reason)})
	return out


static func _trigger(repo: DataRepository, state: GameState, battle: Dictionary, row: Dictionary) -> Dictionary:
	for side: String in BattleSystem.SIDES:
		var codes: Array = battle.get(side, []).duplicate()
		codes.sort()
		for code: String in codes:
			if not state.regiments.has(code) or ArmySystem.fit_count(repo, state, code) <= 0:
				continue
			var entry: Dictionary = state.regiments[code]
			var matches := false
			match String(row.trigger):
				"flank":
					matches = int(entry.morale) <= int(row.threshold) or bool(BattleFormation.context(repo, state, battle, side).flanked)
				"nobles":
					matches = int(battle.get("rounds", 0)) > 0 and int(MilitaryQuality.profile(repo, state, code).fit_by_identity.noble) >= int(row.threshold)
				"reinforcements":
					matches = code in battle.get("event_reinforcements", []) and not code in battle.get("event_reinforcements_consumed", [])
				"wounded":
					matches = BattleOrders.kind(battle, side) == "retreat" and ArmySystem.wounded_count(repo, state, code) >= int(row.threshold) and String(entry.get("order", "")) == "march" and not ArmySystem._path_of(entry).is_empty()
				"supplies":
					matches = not _food_source(repo, state, battle, side, code).is_empty()
				"tunnel":
					# P6 owns the real engineering trigger; a field battle never invents one.
					matches = false
			if matches:
				var out := {"unit": code, "side": side}
				if row.trigger == "supplies":
					out["food_source"] = _food_source(repo, state, battle, side, code)
				return out
	return {}


static func _reserves(repo: DataRepository, state: GameState, battle: Dictionary, side: String) -> Array[String]:
	var out: Array[String] = []
	for code: String in battle.get(side, []):
		if state.regiments.has(code) and battle.get("reserves", {}).has(code) and ArmySystem.fit_count(repo, state, code) > 0:
			out.append(code)
	out.sort()
	return out


static func _food_source(repo: DataRepository, state: GameState, battle: Dictionary, side: String, unit: String) -> String:
	var ids: Array = battle.get("abandoned_supplies", {}).keys()
	ids.sort()
	for id: String in ids:
		var cache: Dictionary = battle.abandoned_supplies[id]
		if cache.side == side or int(cache.amount) <= 0:
			continue
		var event := {"side": side, "unit": unit, "food_source": id}
		if _can_take_food(repo, state, battle, event):
			return id
	return ""


static func _can_take_food(repo: DataRepository, state: GameState, battle: Dictionary, event: Dictionary) -> bool:
	var cache: Dictionary = battle.get("abandoned_supplies", {}).get(String(event.get("food_source", "")), {})
	if cache.is_empty() or int(cache.amount) <= 0:
		return false
	if not "pursue" in BattleRules.legal_actions(repo, state, int(battle.id), String(event.side)):
		return false
	var at := BattleSystem._at_m(repo, state, String(event.unit))
	var place := Vector2i(int(cache.x_m), int(cache.y_m))
	return BattleSystem._within(at, place, int(repo.bal("battle_event_capture_reach_m")))


static func _apply_special(repo: DataRepository, state: GameState, battle: Dictionary, event: Dictionary, row: Dictionary, effects: Array) -> void:
	var unit := String(event.unit)
	var reason := String(row.reason)
	match String(row.effect):
		"report":
			effects.append({"unit": unit, "cancelled": true, "reason": reason})
		"hold", "organize", "charge":
			if not battle.has("actions"):
				battle["actions"] = {}
			var current := BattleOrders.kind(battle, String(event.side))
			if row.effect != "organize" or not current in BattleRules.legal_actions(repo, state, int(battle.id), String(event.side)):
				battle.actions[event.side] = {"kind": "attack" if row.effect == "charge" else "hold", "reason": reason}
			if row.effect == "organize":
				var person: Character = state.characters.get(String(event.commander_id)) as Character
				if person != null and int(person.attributes.get("vanity", 0)) > int(repo.bal("battle_event_vanity_threshold")):
					person.change_opinion(int(repo.bal("battle_event_refused_charge_opinion")), reason, state.tick)
		"reserve":
			if not battle.has("reserves"):
				battle["reserves"] = {}
			battle.reserves[unit] = {"since_day": state.absolute_day(), "reason": reason}
			_consume_reinforcement(battle, unit)
			effects.append({"unit": unit, "reserve": true, "reason": reason})
		"commit":
			var reserves := _reserves(repo, state, battle, String(event.side))
			var committed := unit if event.event_id == "ev_33" else (reserves[0] if not reserves.is_empty() else "")
			if committed != "":
				battle.get("reserves", {}).erase(committed)
				_consume_reinforcement(battle, committed)
				effects.append({"unit": committed, "reserve": false, "reason": reason})
		"collect", "destroy":
			var cache: Dictionary = battle.abandoned_supplies[event.food_source]
			var taken := mini(int(cache.amount), int(row.amount))
			if row.effect == "collect":
				var reg := ArmySystem.regiment(repo, unit, state)
				var capacity := ArmySystem.max_units(repo, ArmySystem.supply_use(repo, reg, state))
				taken = mini(taken, maxi(0, capacity - int(state.regiments[unit].supplies)))
				state.regiments[unit].supplies = int(state.regiments[unit].supplies) + taken
			cache.amount = int(cache.amount) - taken
			effects.append({"unit": unit, "metric": "supplies", "delta": taken if row.effect == "collect" else 0,
				"cache_delta": -taken, "destroyed": taken if row.effect == "destroy" else 0, "reason": reason})
		"escort", "wait":
			CampSystem.request_departure(state, unit, state.absolute_day() + int(row.duration_days), true)
			state.regiments[unit]["event_march_after"] = state.absolute_day() + int(row.duration_days) + 1
			effects.append({"unit": unit, "march_after": state.regiments[unit].event_march_after, "reason": reason})


static func _consume_reinforcement(battle: Dictionary, unit: String) -> void:
	if not battle.has("event_reinforcements_consumed"):
		battle["event_reinforcements_consumed"] = []
	if not unit in battle.event_reinforcements_consumed:
		battle.event_reinforcements_consumed.append(unit)


## Called only at local observation or physical report arrival. Payload stays frozen.
static func receive_report(state: GameState, payload: Dictionary) -> void:
	if not state.king_state.has("battle_reports"):
		state.king_state["battle_reports"] = []
	var key := "%d:%d" % [int(payload.get("battle_id", -1)), int(payload.get("day", -1))]
	for prior: Dictionary in state.king_state.battle_reports:
		if prior.get("key", "") == key:
			return
	var received := payload.duplicate(true)
	received["key"] = key
	received["received_day"] = state.absolute_day()
	state.king_state.battle_reports.append(received)
	for token: String in payload.get("event_tokens", []):
		if state.battle_events.has(token):
			state.battle_events[token]["received_day"] = state.absolute_day()
