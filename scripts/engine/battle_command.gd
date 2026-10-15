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
