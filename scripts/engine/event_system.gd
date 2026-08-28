class_name EventSystem
extends RefCounted
## Rolls and resolves random events (spec §4.2). The ONLY slice-2 consumer of
## state.rng; everything else stays RNG-free so headless and UI runs match.

var data: DataRepository

func _init(d: DataRepository) -> void:
	data = d

func roll(state: GameState) -> Dictionary:
	if not state.pending_event.is_empty():
		return state.pending_event
	# chains first: due scheduled events fire regardless of the daily roll
	var remaining: Array = []
	var due_id := ""
	for sc in state.event_state["scheduled"]:
		var event_id := String(sc["event_id"])
		if not data.events_by_id.has(event_id):
			printerr("EventSystem: scheduled event %s not in events_by_id — dropped" % event_id)
			continue
		if due_id == "" and int(sc["due_tick"]) <= state.tick:
			due_id = event_id
		else:
			remaining.append(sc)
	state.event_state["scheduled"] = remaining
	if due_id != "":
		return _fire(due_id, state)
	state.event_state["pity"] = int(state.event_state["pity"]) + 1
	var forced: bool = int(state.event_state["pity"]) > int(data.bal("event_pity_ticks"))
	if not forced and not state.rng.chance(data.bal("event_base_chance")):
		return {}
	var eligible: Array = []
	var weights: Array = []
	for row in data.events:
		var id := String(row["event_id"])
		if id in state.event_state["once"]:
			continue
		if int(state.event_state["cooldowns"].get(id, -99999)) > state.tick:
			continue
		if not TriggerDsl.evaluate(String(row["trigger"]), state, data):
			continue
		eligible.append(row)
		weights.append(float(row["weight"]))
	if eligible.is_empty():
		return {}
	return _fire(String(eligible[state.rng.pick_weighted(weights)]["event_id"]), state)

func _fire(event_id: String, state: GameState) -> Dictionary:
	var row: Dictionary = data.events_by_id[event_id]
	# Build choices FIRST to detect if any are eligible
	var choices: Array = []
	for c in data.event_choices:
		if String(c["event_id"]) != event_id:
			continue
		if not _requires_met(String(c.get("requires", "")), state):
			continue
		choices.append({"choice_id": String(c["choice_id"]), "label": String(c["label"])})
	# If no eligible choices, return empty without mutating state
	if choices.is_empty():
		printerr("EventSystem: event %s fired with no eligible choices — skipped" % event_id)
		return {}
	# Now mutate state
	state.event_state["pity"] = 0
	state.event_state["cooldowns"][event_id] = state.tick + int(row["cooldown_ticks"])
	if String(row["once"]) == "1":
		state.event_state["once"].append(event_id)
	state.pending_event = {"event_id": event_id, "title_key": String(row["title_key"]),
		"voice": String(row["voice"]), "choices": choices}
	return state.pending_event

func _requires_met(requires: String, state: GameState) -> bool:
	if requires.strip_edges() == "":
		return true
	return TriggerDsl.evaluate(requires, state, data)

func apply_choice(choice_id: String, state: GameState) -> Dictionary:
	if state.pending_event.is_empty():
		return {}
	var event_id := String(state.pending_event["event_id"])
	var active := false
	for ch in state.pending_event["choices"]:
		if String(ch["choice_id"]) == choice_id:
			active = true
	if not active:
		return {}
	for c in data.event_choices:
		if String(c["event_id"]) == event_id and String(c["choice_id"]) == choice_id:
			var effects := EventEffects.apply(String(c["effects"]), state, data)
			var sig := {}
			for ax in OpinionDrift.AXES:
				sig[ax] = float(c[ax])
			var all_zero := true
			for ax in OpinionDrift.AXES:
				if sig[ax] != 0.0:
					all_zero = false
			var drift: Array = []
			if not all_zero:
				drift = OpinionDrift.apply(data, state, sig, String(c["label"]))
			state.pending_event = {}
			return {"event_id": event_id, "choice_id": choice_id,
				"label": String(c["label"]), "effects": effects, "drift": drift}
	return {}
