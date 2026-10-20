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
		ensure_parties(battle)
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
	ensure_parties(battle)


## P4.4e3: an agreement binds only the units that were its parties (the sides' members at contact, plus
## the reinforcements that joined that battle). A parley saved without them takes the battle's current members.
static func ensure_parties(battle: Dictionary) -> void:
	var parley: Dictionary = battle.get("parley", {})
	if parley.is_empty() or parley.has("parties"):
		return
	var parties := {}
	for side: String in BattleSystem.SIDES:
		var codes: Array = (battle.get(side, []) as Array).duplicate()
		codes.sort()
		parties[side] = codes
	parley["parties"] = parties


## Every agreement the battle carries: its own, then each absorbed source's (in id order).
static func _agreements(battle: Dictionary) -> Array:
	ensure_parties(battle)
	var out: Array = []
	if battle.has("parley"):
		out.append(battle["parley"])
	var ids: Array = (battle.get("sources", {}) as Dictionary).keys()
	ids.sort()
	for id: Variant in ids:
		var parley: Dictionary = battle.sources[id].get("parley", {})
		if not parley.is_empty():
			out.append(parley)
	return out


## True when an agreement that sets `clause` to `policy` binds one of `members`. With a `target` the target
## must be a party on the agreement's other side; without one the object cannot be confirmed, so it applies.
static func _binds(battle: Dictionary, clause: String, policy: String, today: int, members: Array, target: String) -> bool:
	for parley: Dictionary in _agreements(battle):
		if _policy({"parley": parley}, clause, today) != policy:
			continue
		var parties: Dictionary = parley.get("parties", {})
		for code: String in members:
			for side: String in BattleSystem.SIDES:
				if not code in parties.get(side, []):
					continue
				var other := "def" if side == "att" else "att"
				if target == "" or target in parties.get(other, []):
					return true
	return false


static func _policy(battle: Dictionary, clause: String, today: int) -> String:
	var term: Dictionary = battle.get("parley", {}).get("agreed", {}).get(clause, {})
	if term.is_empty() or (int(term.get("until_day", 0)) > 0 and today > int(term["until_day"])):
		return ""
	return String(term.get("policy", ""))


## A live own law may be stricter; it can never revoke a shared obligation.
static func legal_actions(repo: DataRepository, state: GameState, battle_id: int, side: String, unit := "", target := "") -> Array[String]:
	var battle := BattleSystem.battle_by_id(state, battle_id)
	if battle.is_empty() or not side in BattleSystem.SIDES or (battle[side] as Array).is_empty():
		return []
	if unit != "" and not unit in battle[side]:
		return []
	var members: Array = battle[side] if unit == "" else [unit]
	var actions: Array[String] = ["attack", "hold", "inspire", "retreat", "surrender", "pursue", "charge", "red_flag"]
	for code: String in members:
		if LawSystem.received(repo, state, "quarter", code)["value"] == "give":
			actions.erase("red_flag")
		if LawSystem.received(repo, state, "own_surrender", code)["value"] == "forbid":
			actions.erase("surrender")
		if LawSystem.received(repo, state, "battle_tactics", code)["value"] == "restrained":
			actions.erase("charge")
			actions.erase("pursue")
	for code: String in members:
		if DevelopmentSystem.flag(repo, state, ArmySystem.realm_of(repo, code, state), "honour_bound"):
			actions.erase("red_flag")
	var today := state.absolute_day()
	if _binds(battle, "surrender", "accept", today, members, target):
		actions.erase("red_flag")
	if _binds(battle, "tactics", "restrained", today, members, target):
		actions.erase("charge")
		actions.erase("pursue")
	var ceasefire := _binds(battle, "ceasefire", "protect", today, members, target)
	if ceasefire or _binds(battle, "safe_withdrawal", "protect", today, members, target):
		actions.erase("pursue")
		if ceasefire:
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
