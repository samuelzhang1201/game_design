class_name BattleRules
extends RefCounted

## Conditions are normalized by the caller; every field must agree.
static func negotiate(ours: Dictionary, theirs: Dictionary) -> Dictionary:
	ours = ours.duplicate(true)
	theirs = theirs.duplicate(true)
	var agreed := {}
	var rejected := {}
	var ids := ours.keys()
	for id: String in theirs:
		if not id in ids:
			ids.append(id)
	ids.sort()
	for id: String in ids:
		if ours.has(id) and theirs.has(id) and ours[id] == theirs[id]:
			agreed[id] = ours[id].duplicate(true) if ours[id] is Dictionary else ours[id]
		else:
			rejected[id] = {"ours": ours.get(id), "theirs": theirs.get(id),
				"reason": "Received policies or complete conditions differ."}
	return {"agreed": agreed, "rejected": rejected}

## Freeze once at contact. Later laws, commanders and reinforcements inherit it.
static func freeze(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	if battle.has("parley"):
		return
	var proposals := {}
	var received := {}
	var representatives := {}
	for side: String in BattleSystem.SIDES:
		var codes: Array = battle[side].duplicate()
		codes.sort()
		var code := String(codes[0]) if not codes.is_empty() else ""
		representatives[side] = code
		proposals[side] = {}
		received[side] = {}
		for id: String in repo.parley_clauses:
			var row: Dictionary = repo.parley_clauses[id]
			var law := LawSystem.received(repo, state, String(row["law"]), code)
			received[side][id] = law
			var policies := {}
			for pair: String in String(row["policy_map"]).split("|", false):
				var parts := pair.split(":")
				policies[parts[0]] = parts[1]
			proposals[side][id] = {"policy": String(policies.get(law["value"], "unspecified")),
				"scope": String(row["scope"]), "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	var result := negotiate(proposals["att"], proposals["def"])
	result["battle_id"] = int(battle["id"])
	result["received"] = received
	result["representatives"] = representatives
	result["proposals"] = proposals
	result["reason"] = "Commanders negotiate under received military laws at first contact."
	battle["parley"] = result


static func _policy(battle: Dictionary, clause: String, today: int) -> String:
	var term: Dictionary = battle.get("parley", {}).get("agreed", {}).get(clause, {})
	if term.is_empty() or (int(term.get("until_day", 0)) > 0 and today > int(term["until_day"])):
		return ""
	return String(term.get("policy", ""))


## A live own law may be stricter; it can never revoke a shared obligation.
static func legal_actions(repo: DataRepository, state: GameState, battle_id: int, side: String) -> Array[String]:
	var battle := BattleSystem.battle_by_id(state, battle_id)
	if battle.is_empty() or not side in BattleSystem.SIDES or (battle[side] as Array).is_empty():
		return []
	var actions: Array[String] = ["attack", "hold", "inspire", "retreat", "surrender", "pursue", "charge", "red_flag"]
	for code: String in battle[side]:
		if LawSystem.received(repo, state, "quarter", code)["value"] == "give":
			actions.erase("red_flag")
		if LawSystem.received(repo, state, "own_surrender", code)["value"] == "forbid":
			actions.erase("surrender")
		if LawSystem.received(repo, state, "battle_tactics", code)["value"] == "restrained":
			actions.erase("charge")
			actions.erase("pursue")
	for code: String in battle[side]:
		if DevelopmentSystem.flag(repo, state, ArmySystem.realm_of(repo, code, state), "honour_bound"):
			actions.erase("red_flag")
	if _policy(battle, "surrender", state.absolute_day()) == "accept":
		actions.erase("red_flag")
	if _policy(battle, "tactics", state.absolute_day()) == "restrained":
		actions.erase("charge")
		actions.erase("pursue")
	if _policy(battle, "safe_withdrawal", state.absolute_day()) == "protect" \
			or _policy(battle, "ceasefire", state.absolute_day()) == "protect":
		actions.erase("pursue")
		if _policy(battle, "ceasefire", state.absolute_day()) == "protect":
			actions.erase("attack")
			actions.erase("charge")
	return actions

static func side_of(battle: Dictionary, code: String) -> String:
	for side: String in BattleSystem.SIDES:
		if code in battle.get(side, []):
			return side
	return ""


static func summary(repo: DataRepository, battle: Dictionary) -> String:
	var parley: Dictionary = battle.get("parley", {})
	var agreed: PackedStringArray = []
	var rejected: PackedStringArray = []
	for id: String in repo.parley_clauses:
		var label := String(repo.parley_clauses[id]["label"])
		var a: Dictionary = parley.get("received", {}).get("att", {}).get(id, {})
		var d: Dictionary = parley.get("received", {}).get("def", {}).get(id, {})
		if a.is_empty() or d.is_empty():
			continue
		var versions := ""
		if int(a["decree_id"]) > 0 or int(d["decree_id"]) > 0:
			var att := "decree %d" % int(a["decree_id"]) if int(a["decree_id"]) > 0 else "founding law"
			var defend := "decree %d" % int(d["decree_id"]) if int(d["decree_id"]) > 0 else "founding law"
			versions = " (attacker: %s; defender: %s)" % [att, defend]
		if parley.get("agreed", {}).has(id):
			var term: Dictionary = parley["agreed"][id]
			agreed.append("%s: %s%s" % [label, String(term["policy"]), versions])
		else:
			rejected.append("%s%s: %s" % [label, versions,
				String(parley.get("rejected", {}).get(id, {}).get("reason", "No proposal"))])
	var lines: PackedStringArray = []
	if not agreed.is_empty() or not rejected.is_empty():
		lines.append("The commanders carry the founding laws unless a decree is named below.")
	if not agreed.is_empty():
		lines.append("Agreed\n" + "\n".join(agreed))
	if not rejected.is_empty():
		lines.append("Not agreed\n" + "\n".join(rejected))
	return "\n".join(lines)


## Bilateral terms are public; enemy strength and private policies stay out.
static func encounter_view(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var view := {"agreements": summary(repo, battle), "options": [], "regiment": "", "battle_id": int(battle.get("id", -1))}
	for side: String in BattleSystem.SIDES:
		for code: String in battle.get(side, []):
			if ArmySystem.is_foe(state, code):
				continue
			view["regiment"] = code
			view["gold"] = int(OrderCosts.gold_of(repo, "BATTLE_FORMATION"))
			view["courier_gold"] = 0 if KingSystem.can_command(repo, state, code) or not CourierSystem.joinable(state, CourierSystem.ORDINARY, code, {}).is_empty() else CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)
			for formation: String in repo.battle_formations:
				view["options"].append({"id": formation, "label": String(repo.battle_formations[formation]["label"]),
					"reason": BattleFormation.refusal(repo, state, int(battle["id"]), side, formation),
					"note": BattleFormation.evaluate(repo, formation, BattleFormation.context(repo, state, battle, side), false)["reason"]})
			return view
	return view
