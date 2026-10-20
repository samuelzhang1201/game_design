class_name FamilyLosses
extends RefCounted
## What a noble house feels when its kin die or are taken in battle. Pure and replay-safe:
## the same loss id returns its saved result; a different request under it is refused.

const CAUSES := {"dead": "dead", "captured_current": "captured"}

## `changes` are MilitaryRoster transition rows {cohort_id, from, to, count}; `context` names
## {place, order}. Returns the applied rows [{family, person, delta, reason}] or {error}.
static func consume(repo: DataRepository, state: GameState, loss_id: String, changes: Array, context: Dictionary) -> Variant:
	if loss_id.strip_edges().is_empty():
		return {"error": "A family loss needs an id."}
	var key := "family:" + loss_id
	var request := {"changes": changes.duplicate(true), "context": context.duplicate(true)}
	if state.military_events.has(key):
		var saved: Dictionary = state.military_events[key]
		if saved.get("request", null) != request:
			return {"error": "Family loss id was already used for a different request."}
		return (saved["result"] as Array).duplicate(true)
	# family -> "cause|kind" -> heads
	var tally: Dictionary = {}
	for change: Dictionary in changes:
		var cohort: Dictionary = state.military_cohorts.get(String(change.get("cohort_id", "")), {})
		var cause: String = CAUSES.get(String(change.get("to", "")), "")
		var from := String(change.get("from", ""))
		var family := String(cohort.get("family_name", ""))
		if cohort.get("identity", "") != "noble" or cause == "" or family == "" or not from in ["fit", "wounded"]:
			continue
		var slot := cause + "_" + ("named" if String(cohort.get("person_id", "")) != "" else "cadre")
		if not tally.has(family):
			tally[family] = {}
		tally[family][slot] = int(tally[family].get(slot, 0)) + int(change.get("count", 0))
	var realm := repo.resolve_realm("player_realm")
	var ids: Array = state.characters.keys()
	ids.sort()
	var families: Array = tally.keys()
	families.sort()
	var rows: Array = []
	for family: String in families:
		var slots: Array = tally[family].keys()
		slots.sort()
		for person: String in ids:
			var character: Character = state.characters[person]
			if character.family_name != family or character.kingdom != realm:
				continue
			for slot: String in slots:
				var heads := int(tally[family][slot])
				var delta := heads * int(repo.bal("family_loss_opinion_" + slot))
				if delta == 0:
					continue
				var parts := slot.split("_")
				var reason := "%d: %s lost %d %s (%s) at %s under %s" % [delta, family, heads, parts[1], parts[0],
					context.get("place", "the field"), context.get("order", "no order")]
				character.change_opinion(delta, reason, state.tick)
				rows.append({"family": family, "person": person, "delta": delta, "reason": reason})
	state.military_events[key] = {"request": request, "result": rows.duplicate(true)}
	return rows
