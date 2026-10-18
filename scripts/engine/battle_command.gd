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
