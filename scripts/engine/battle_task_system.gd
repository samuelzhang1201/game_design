class_name BattleTaskSystem
extends RefCounted

## Internal warrants: ActionSystem/couriers own dispatch, costs and actual arrival.
## A receipt never moves a unit or starts a second simulation clock.
static func current(state: GameState, unit: String) -> Dictionary:
	var ledger: Dictionary = state.unit_tasks.get(unit, {})
	return ledger.get("orders", {}).get(String(ledger.get("current_id", "")), {}).duplicate(true)


static func _find(state: GameState, id: String) -> Dictionary:
	for ledger: Dictionary in state.unit_tasks.values():
		if ledger["orders"].has(id):
			return ledger["orders"][id]
	return {}


static func _canonical(order: Dictionary) -> Dictionary:
	return {"id": String(order.get("id", "")), "unit": String(order.get("unit", "")),
		"battle_id": int(order.get("battle_id", -1)), "task": String(order.get("task", "")),
		"formation": String(order.get("formation", "")), "target_unit": String(order.get("target_unit", "")),
		"source": String(order.get("source", "player")), "issuer": String(order.get("issuer", ""))}


static func _format_error(order: Dictionary) -> String:
	var fields := ["id", "unit", "battle_id", "task", "formation", "target_unit", "source", "issuer"]
	for field: Variant in order:
		if not field is String:
			return "A unit task field name must be text."
		if not field in fields:
			return "Unknown unit task field: " + field
		if field == "battle_id":
			if not order[field] is int or int(order[field]) < 0:
				return "A unit task needs a whole battlefield id."
		elif not order[field] is String:
			return "A unit task field must be text: " + field
	return ""


static func _refusal(repo: DataRepository, state: GameState, order: Dictionary) -> String:
	var unit := String(order["unit"])
	var battle := BattleSystem.battle_by_id(state, int(order["battle_id"]))
	var side := BattleRules.side_of(battle, unit)
	if order["id"] == "":
		return "A unit task needs a stable request id."
	if battle.is_empty() or side == "":
		return "The unit is no longer on this battlefield."
	var entry := BattleSystem._stored(state, unit)
	if not BattleSystem._can_fight(repo, state, unit) or bool(entry.get("captured", false)):
		return "The unit can no longer receive a fighting task."
	if not repo.battle_behaviors.has(order["task"]):
		return "Unknown unit task."
	if order["formation"] != "" and not repo.battle_formations.has(order["formation"]):
		return "Unknown unit task formation."
	var action := String(repo.battle_behaviors[order["task"]]["legal_action"])
	var source := String(order["source"])
	if source == "player":
		if not state.regiments.has(unit) or ArmySystem.is_foe(state, unit) \
				or ArmySystem.realm_of(repo, unit, state) != repo.resolve_realm("player_realm"):
			return "The crown cannot command this unit."
	elif source == "general":
		var issuer := String(order["issuer"])
		if issuer == "" or issuer != String(battle.get("commanders", {}).get(side, "")):
			return "The warrant is not from this side's commanding general."
		var eligible := false
		for member: String in battle[side]:
			if BattleSystem._can_fight(repo, state, member) \
					and not bool(BattleSystem._stored(state, member).get("captured", false)) \
					and MilitaryCommanders.eligible_for_unit(repo, state, member, issuer) \
					and String(state.military_rosters.get(member, {}).get("commander_id", "")) == issuer:
				eligible = true
		if not eligible:
			return "The commanding general is no longer available on this battlefield."
		var active := current(state, unit)
		if not active.is_empty() and active["request"]["source"] == "player":
			return "A general cannot replace a delivered player unit task."
		# shortcut: accept only royal pursuit until contact-plan authority has a validated delivery path.
		if action == "pursue":
			return "Pursuit needs an explicit royal task or a received contact plan."
	else:
		return "A local commander cannot replace a unit's primary task."
	var target := String(order["target_unit"])
	if target != "":
		var target_side := BattleRules.side_of(battle, target)
		if target_side == "" or target_side == side or not BattleSystem._can_fight(repo, state, target) \
				or bool(BattleSystem._stored(state, target).get("captured", false)):
			return "The designated enemy can no longer be tasked against."
	if not action in BattleRules.legal_actions(repo, state, int(battle["id"]), side, unit):
		return "Received military law or an agreed battlefield term forbids this unit task."
	if String(battle.get("routed_side", "")) == side and action != "retreat":
		return "A routed unit cannot resume its battle line."
	return ""


static func _transition(state: GameState, record: Dictionary, status: String, reason: String) -> void:
	record["status"] = status
	record["reason"] = reason
	record["history"].append({"status": status, "reason": reason, "day": state.absolute_day(),
		"source": String(record["request"]["source"])})


static func refusal_of(repo: DataRepository, state: GameState, raw: Dictionary) -> String:
	var why := _format_error(raw)
	if why != "":
		return why
	return _refusal(repo, state, _canonical(raw))


static func invalidate_task(state: GameState, id: String, reason: String) -> void:
	var record := _find(state, id)
	if not record.is_empty() and record["status"] == "pending":
		_transition(state, record, "invalid", reason)


static func issue_task(repo: DataRepository, state: GameState, raw: Dictionary) -> Dictionary:
	var why := _format_error(raw)
	if why != "":
		return {"status": "invalid", "reason": why}
	var order := _canonical(raw)
	var old := _find(state, String(order["id"]))
	if not old.is_empty():
		return old.duplicate(true) if old["request"] == order else \
			{"status": "invalid", "reason": "This request id already names another unit task."}
	why = _refusal(repo, state, order)
	if why != "":
		return {"status": "invalid", "reason": why}
	var unit := String(order["unit"])
	if not state.unit_tasks.has(unit):
		state.unit_tasks[unit] = {"current_id": "", "issued_sequence": 0, "received_sequence": 0,
			"player_received_sequence": 0, "orders": {}}
	var ledger: Dictionary = state.unit_tasks[unit]
	ledger["issued_sequence"] += 1
	var record := {"request": order, "sequence": int(ledger["issued_sequence"]), "history": []}
	_transition(state, record, "pending", "The unit task awaits actual delivery.")
	ledger["orders"][order["id"]] = record
	return record.duplicate(true)


static func deliver_task(repo: DataRepository, state: GameState, order_id: String) -> Dictionary:
	var record := _find(state, order_id)
	if record.is_empty():
		return {"status": "invalid", "reason": "Unknown unit task warrant."}
	if record["status"] != "pending":
		return record.duplicate(true)
	var order: Dictionary = record["request"]
	var ledger: Dictionary = state.unit_tasks[order["unit"]]
	var received := int(ledger["player_received_sequence"] if order["source"] == "player" else ledger["received_sequence"])
	if int(record["sequence"]) <= received:
		_transition(state, record, "superseded", "A newer unit task has already arrived.")
		return record.duplicate(true)
	var why := _refusal(repo, state, order)
	if why != "":
		_transition(state, record, "invalid", why)
		return record.duplicate(true)
	var previous: Dictionary = ledger["orders"].get(String(ledger["current_id"]), {})
	if not previous.is_empty():
		_transition(state, previous, "replaced", "A newer lawful unit task arrived: " + order_id)
	ledger["current_id"] = order_id
	ledger["received_sequence"] = maxi(int(ledger["received_sequence"]), int(record["sequence"]))
	if order["source"] == "player":
		ledger["player_received_sequence"] = int(record["sequence"])
	_transition(state, record, "received", "The unit receives its lawful primary task.")
	return record.duplicate(true)
