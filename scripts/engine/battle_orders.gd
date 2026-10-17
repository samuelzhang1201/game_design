class_name BattleOrders
extends RefCounted

## The warrant survives the battlefield: retries never spend or inspire twice.
static func canonical(order: Dictionary) -> Dictionary:
	return {"id": String(order.get("id", "")), "battle_id": int(order.get("battle_id", -1)),
		"side": String(order.get("side", "")), "kind": String(order.get("kind", "")),
		"issued_day": int(order.get("issued_day", 0)), "params": order.get("params", {}).duplicate(true)}

static func available_gold(state: GameState) -> int:
	var gold := int(state.metrics.get("treasury", 0))
	for record: Dictionary in state.battle_orders.values():
		gold -= int(record.get("reserved_gold", 0))
	return gold

static func kind(battle: Dictionary, side: String) -> String:
	return String(battle.get("actions", {}).get(side, {}).get("kind", "hold"))

static func refusal(repo: DataRepository, state: GameState, order: Dictionary) -> String:
	var battle := BattleSystem.battle_by_id(state, int(order.get("battle_id", -1)))
	var side := String(order.get("side", ""))
	var action := String(order.get("kind", ""))
	if String(order.get("id", "")) == "":
		return "A battle warrant needs a stable request id."
	if battle.is_empty() or not side in BattleSystem.SIDES:
		return "This battlefield no longer exists."
	if not repo.battle_orders.has(action):
		return "Unknown battle order: " + action
	var code := String(order.get("params", {}).get("regiment", ""))
	if code == "" or not code in battle.get(side, []) or ArmySystem.state_of(repo, state, code).is_empty():
		return "The target army has left this battlefield."
	for member: String in battle[side]:
		var entry := ArmySystem.state_of(repo, state, member)
		if entry.is_empty() or bool(entry.get("captured", false)) or (MilitaryRoster.fit(state, member) <= 0 and (action != "surrender" or MilitaryRoster.living(state, member) <= 0)):
			return "A target army is no longer able to receive this warrant."
	if not action in BattleRules.legal_actions(repo, state, int(battle["id"]), side):
		return "Received military law or an agreed battlefield term forbids " + action + "."
	if String(battle.get("routed_side", "")) == side and action in ["hold", "attack"]:
		return "This side has broken and cannot resume its battle line."
	if action == "inspire" and int(battle.get("inspire_cooldown", {}).get(side, 0)) > state.absolute_day():
		return "The army has already received its inspiration reward during this cooldown."
	return ""

static func reward_gold(repo: DataRepository, heads: int) -> int:
	var rate := int(repo.battle_orders["inspire"]["reserve_gold_per_1000"])
	@warning_ignore("integer_division")
	return (heads * rate + 999) / 1000

static func preview(repo: DataRepository, state: GameState, order: Dictionary) -> Dictionary:
	var why := refusal(repo, state, order)
	var reserve := 0
	if String(order.get("kind", "")) == "inspire" and why == "":
		var battle := BattleSystem.battle_by_id(state, int(order["battle_id"]))
		var heads := 0
		for code: String in battle[String(order["side"])]:
			heads += MilitaryRoster.living(state, code)
		reserve = reward_gold(repo, heads)
	if why == "" and available_gold(state) < reserve:
		why = "The treasury cannot reserve the promised battlefield reward."
	return {"reason": why, "reserved_gold": reserve, "available_gold": available_gold(state)}

static func issue(repo: DataRepository, state: GameState, raw: Dictionary) -> Dictionary:
	var order := canonical(raw)
	var id := String(order["id"])
	if state.battle_orders.has(id):
		var old: Dictionary = state.battle_orders[id]
		return old.duplicate(true) if old["request"] == order else {"status": "invalid", "reason": "This request id already names another battle warrant."}
	var quote := preview(repo, state, order)
	if quote["reason"] != "":
		return {"status": "invalid", "reason": quote["reason"]}
	var record := {"request": order, "status": "pending", "reserved_gold": int(quote["reserved_gold"]),
		"reason": "The battlefield reward is reserved until the warrant arrives.", "result": {}, "targets": BattleSystem.battle_by_id(state, int(order["battle_id"]))[String(order["side"])].duplicate()}
	record["target_counts"] = {}
	for code: String in record["targets"]:
		record["target_counts"][code] = MilitaryRoster.living(state, code)
	state.battle_orders[id] = record
	return record.duplicate(true)

static func invalidate(_repo: DataRepository, state: GameState, id: String, reason: String) -> Dictionary:
	if not state.battle_orders.has(id):
		return {"status": "invalid", "reason": "Unknown battle warrant."}
	var record: Dictionary = state.battle_orders[id]
	if record["status"] == "pending":
		record["status"] = "invalid"
		record["reserved_gold"] = 0
		record["reason"] = reason
		record["result"] = {"reason": reason, "day": state.absolute_day()}
	return record.duplicate(true)

static func end_battle(repo: DataRepository, state: GameState, battle_id: int, reason: String) -> void:
	for id: String in state.battle_orders:
		if int(state.battle_orders[id]["request"]["battle_id"]) == battle_id:
			invalidate(repo, state, id, reason)

static func deliver(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	if not state.battle_orders.has(id):
		return {"status": "invalid", "reason": "Unknown battle warrant."}
	var record: Dictionary = state.battle_orders[id]
	if record["status"] != "pending":
		return record.duplicate(true)
	var order: Dictionary = record["request"]
	var why := refusal(repo, state, order)
	var live := BattleSystem.battle_by_id(state, int(order["battle_id"]))
	for code: String in record.get("targets", []):
		if not code in live.get(String(order["side"]), []):
			why = "An army named by the warrant has left the battlefield."
	if why != "":
		return invalidate(repo, state, id, why)
	var battle := BattleSystem.battle_by_id(state, int(order["battle_id"]))
	var side := String(order["side"])
	var action := String(order["kind"])
	var row: Dictionary = repo.battle_orders[action]
	var result := {"day": state.absolute_day(), "effects": []}
	if action == "surrender":
		var capture := _surrender(repo, state, battle, side, id)
		if capture.has("error"):
			return invalidate(repo, state, id, String(capture["error"]))
		result["capture_handoff"] = capture
		if bool(capture.get("accepted", false)):
			result["effects"].append({"kind": "personnel", "metric": "army", "reason": String(capture["reason"]),
				"units": capture["units"].duplicate(true), "personnel": capture["personnel"].duplicate(true)})
		if not bool(capture["accepted"]):
			record["status"] = "refused"
			record["reserved_gold"] = 0
			record["reason"] = "The opposing commander refuses surrender; the prior order continues."
			record["result"] = result
			return record.duplicate(true)
	if action == "inspire":
		var heads := 0
		for code: String in record["targets"]:
			heads += mini(MilitaryRoster.living(state, code), int(record["target_counts"][code]))
		var price := mini(reward_gold(repo, heads), int(record["reserved_gold"]))
		if int(state.metrics["treasury"]) < price:
			return invalidate(repo, state, id, "The promised reward is no longer available.")
		state.metrics["treasury"] -= price
		result["effects"].append({"metric": "treasury", "delta": -price, "reason": "The delivered battlefield reward is paid to the troops."})
		var bonus := int(row["morale_gain"])
		if KingSystem.present(repo, state, int(battle["id"])):
			bonus += int(row["king_morale_bonus"])
		for code: String in record["targets"]:
			var entry := ArmySystem.state_of(repo, state, code)
			var before := int(entry.get("morale", 0))
			entry["morale"] = clampi(before + bonus, 0, 100)
			result["effects"].append({"metric": "morale", "regiment": code, "delta": int(entry["morale"]) - before,
				"reason": "The troops receive their promised reward and battlefield encouragement."})
		if not battle.has("inspire_cooldown"):
			battle["inspire_cooldown"] = {}
		battle["inspire_cooldown"][side] = state.absolute_day() + int(row["cooldown_days"])
		if not battle.has("inspire_until"):
			battle["inspire_until"] = {}
		battle["inspire_until"][side] = state.absolute_day() + int(row["inspire_duration_days"])
	else:
		if not battle.has("actions"):
			battle["actions"] = {}
		if action in ["hold", "attack"]:
			for code: String in battle[side]:
				BattleSystem.stop_withdrawal(state, code)
		battle["actions"][side] = {"kind": action, "order_id": id, "day": state.absolute_day(),
			"reason": "The last delivered lawful warrant orders " + action + "."}
	record["reserved_gold"] = 0
	record["status"] = "delivered"
	record["reason"] = "The battlefield warrant is executed once: " + action + "."
	record["result"] = result
	return record.duplicate(true)

static func _equipment(repo: DataRepository, reg: Dictionary) -> Dictionary:
	var equipment := {}
	for arm: String in repo.world_table("military", "unit_types"):
		equipment[arm] = int(reg.get(arm, 0))
	return equipment

static func _surrender(repo: DataRepository, state: GameState, battle: Dictionary, side: String, id: String) -> Dictionary:
	var enemy := "def" if side == "att" else "att"
	var accepts := BattleRules._policy(battle, "surrender", state.absolute_day()) == "accept"
	if not accepts:
		accepts = true
		for code: String in battle[enemy]:
			if LawSystem.received(repo, state, "quarter", code)["value"] != "give":
				accepts = false
	if not accepts:
		return {"accepted": false}
	var changes: Array = []
	var evidence: Array = []
	var captors: Array = battle[enemy].duplicate()
	captors.sort()
	if captors.is_empty():
		return {"error": "No opposing army can accept surrender."}
	var captor := String(captors[0])
	var commander := String(state.military_rosters.get(captor, {}).get("commander_id", ""))
	var codes: Array = battle[side].duplicate()
	for code: String in codes:
		for cohort_id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
			var cohort: Dictionary = state.military_cohorts[cohort_id]
			var person := String(cohort.get("person_id", ""))
			var character: Character = state.characters.get(person) as Character
			if person == "you" or (character != null and character.category == "player"):
				return {"error": "The king cannot enter the prisoner roster."}
			for from: String in ["fit", "wounded"]:
				var count := int(cohort.get(from, 0))
				if count > 0:
					changes.append({"cohort_id": cohort_id, "from": from, "to": "captured_current", "count": count})
		var reg := ArmySystem.regiment(repo, code, state)
		evidence.append({"unit_code": code, "equipment": _equipment(repo, reg),
			"cohort_ids": state.military_rosters.get(code, {}).get("cohort_ids", []).duplicate(),
			"commander_id": String(state.military_rosters.get(code, {}).get("commander_id", "")),
			"equipment_sources": reg.get("source_parts", []).duplicate(true)})
	if changes.is_empty():
		return {"error": "There are no surviving personnel to surrender."}
	var reason := "The opposing commander accepts surrender; all surviving fit and wounded personnel are captured."
	var moved := MilitaryRoster.transition(repo, state, "battle_surrender:" + id, changes, reason)
	if moved.has("error"):
		return moved
	for code: String in codes:
		ArmySystem.state_of(repo, state, code)["captured"] = true
		battle[side].erase(code)
	return {"accepted": true, "battle_id": int(battle["id"]), "captor_side": enemy,
		"captor_unit": captor, "captor_commander": commander, "units": evidence, "personnel": changes, "reason": reason}
