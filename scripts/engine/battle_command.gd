class_name BattleCommand
extends RefCounted

## Eligibility (presence, rank and existing appointments) belongs to the caller.
## An explicit invalid nomination is refused, never silently replaced.
static func select(state: GameState, ids: Array[String], nominee: String) -> String:
	if not nominee.is_empty():
		if nominee in ids and state.characters.get(nominee) is Character:
			return nominee
		return ""
	var selected := ""
	for id: String in ids:
		var candidate: Character = state.characters.get(id) as Character
		if candidate == null:
			continue
		if selected.is_empty():
			selected = id
			continue
		var incumbent: Character = state.characters[selected]
		var martial := int(candidate.skills.get("sk_martial", 0))
		var incumbent_martial := int(incumbent.skills.get("sk_martial", 0))
		var prestige := int(candidate.attributes.get("prestige", 0))
		var incumbent_prestige := int(incumbent.attributes.get("prestige", 0))
		if martial > incumbent_martial or (martial == incumbent_martial and
				(prestige > incumbent_prestige or (prestige == incumbent_prestige and id < selected))):
			selected = id
	return selected


## Reinforcements retain a fit incumbent; nominations validate both sides before publication.
static func update_battle(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var selected: Dictionary = battle.get("commanders", {}).duplicate()
	for side: String in ["att", "def"]:
		var ids: Array[String] = []
		for code: String in battle.get(side, []):
			var person := String(state.military_rosters.get(code, {}).get("commander_id", ""))
			if not person.is_empty() and MilitaryCommanders.eligible_for_unit(repo, state, code, person):
				ids.append(person)
		var nominee := String(battle.get("commander_nominees", {}).get(side, ""))
		var incumbent := String(selected.get(side, ""))
		if not nominee.is_empty():
			var chosen := select(state, ids, nominee)
			if chosen.is_empty():
				return {"error": "The nominated battlefield commander is unavailable or absent"}
			selected[side] = chosen
		else:
			selected[side] = incumbent if incumbent in ids else select(state, ids, "")
	battle["commanders"] = selected
	return selected


## P4.4e2: a merge leaves ONE commander per side. Candidates are the survivor's and the absorbed
## source's commanders (mapped by allegiance) still eligible for a unit now on that side; a valid
## explicit nominee wins (both: the newer `commander_nominee_seq`, then the smaller id), else
## `select`. Each choice is journaled in `command_unions`.
static func unify(repo: DataRepository, state: GameState, survivor: Dictionary, source: Dictionary, side_map: Dictionary) -> void:
	for gone_side: String in ["att", "def"]:
		var side := String(side_map.get(gone_side, ""))
		if side == "":
			continue
		var theirs := String(source.get("commanders", {}).get(gone_side, ""))
		var mine := String(survivor.get("commanders", {}).get(side, ""))
		var ids: Array[String] = []
		for id: String in [mine, theirs]:
			if id != "" and not id in ids and _serves(repo, state, survivor, side, id):
				ids.append(id)
		var nominees: Array = []   # [person, seq] from the survivor, then the source
		for pair: Array in [[survivor, side], [source, gone_side]]:
			var holder: Dictionary = pair[0]
			var who := String(holder.get("commander_nominees", {}).get(pair[1], ""))
			if who != "" and who in ids and not nominees.any(func(n: Array) -> bool: return n[0] == who):
				nominees.append([who, int(holder.get("commander_nominee_seq", {}).get(pair[1], 0))])
		var chosen := ""
		var seq := 0
		for n: Array in nominees:
			if chosen == "" or int(n[1]) > seq or (int(n[1]) == seq and String(n[0]) < chosen):
				chosen = String(n[0])
				seq = int(n[1])
		var by := "an explicit appointment"
		if chosen == "":
			chosen = select(state, ids, "")
			by = "military ability, prestige, then id"
		if chosen == "":
			continue
		if not survivor.has("commanders"):
			survivor["commanders"] = {}
		survivor.commanders[side] = chosen
		if not nominees.is_empty():
			if not survivor.has("commander_nominees"):
				survivor["commander_nominees"] = {}
			if not survivor.has("commander_nominee_seq"):
				survivor["commander_nominee_seq"] = {}
			survivor.commander_nominees[side] = chosen
			survivor.commander_nominee_seq[side] = seq
		if not survivor.has("command_unions"):
			survivor["command_unions"] = []
		survivor.command_unions.append({"side": side, "chosen": chosen, "from": [mine, theirs],
			"reason": "Battles merged: %s commands the %s side by %s." % [chosen, side, by]})


static func _serves(repo: DataRepository, state: GameState, battle: Dictionary, side: String, person: String) -> bool:
	for code: String in battle.get(side, []):
		if String(state.military_rosters.get(code, {}).get("commander_id", "")) == person \
				and MilitaryCommanders.eligible_for_unit(repo, state, code, person):
			return true
	return false
