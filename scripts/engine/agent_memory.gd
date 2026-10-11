class_name AgentMemory
extends RefCounted
## What each character remembers being told (spec D4, §4.3). Distinct from
## KnowledgeBase: remembering that the king said a thing is not the same as
## believing it, and belief is ClaimLedger's business. This unit only records
## that words were spoken, to whom, and in whose company.
##
## GameState.agent_memory maps character_id to an Array of exchanges, oldest
## first, capped at council/balance.csv's memory_exchanges_kept:
##   {"tick": int, "location": String, "speaker": String, "text": String,
##    "audience": Array[String]}
##
## `audience` is the whole set addressed, so a character can tell a private
## word from one spoken in front of the room — the same sentence means
## different things depending on who else heard it.
##
## Deterministic, no RNG, no Nodes.

## Records one utterance against one listener. Silently ignores an unknown
## character or blank text: callers iterate an audience that may contain ids
## a given campaign no longer has.
static func remember(data: DataRepository, state: GameState, char_id: String,
		speaker: String, text: String, audience: Array, location: String,
		tick: int) -> void:
	if not state.characters.has(char_id) or text.strip_edges() == "":
		return
	if not state.agent_memory.has(char_id):
		state.agent_memory[char_id] = []
	var entries: Array = state.agent_memory[char_id]
	entries.append({
		"tick": tick, "location": location, "speaker": speaker,
		"text": text.strip_edges(), "audience": audience.duplicate(),
	})
	var cap := int(data.bal("memory_exchanges_kept"))
	while entries.size() > cap:
		entries.pop_front()

## This character's remembered exchanges, oldest first. Empty when they have
## never been spoken to.
static func exchanges_for(state: GameState, char_id: String) -> Array:
	return state.agent_memory.get(char_id, [])

## Prompt-ready recap for this character's LLM context: what was said in
## their hearing — the ruler's words, their own replies, and other speakers
## — and whether it was said in private or in company (review finding
## 2026-09-01: memory used to hold only the ruler's voice).
static func describe_for(state: GameState, char_id: String) -> String:
	var lines: Array = []
	for entry in exchanges_for(state, char_id):
		var audience: Array = entry["audience"]
		var company := "privately" if audience.size() <= 1 else "with others present"
		var speaker := String(entry["speaker"])
		var quoted := String(entry["text"])
		if speaker == "you":
			lines.append('You were told, %s: "%s"' % [company, quoted])
		elif speaker == char_id:
			lines.append('You replied, %s: "%s"' % [company, quoted])
		else:
			var who: String = speaker
			if state.characters.has(speaker):
				who = state.characters[speaker].display_name
			lines.append('%s said, %s: "%s"' % [who, company, quoted])
	return "\n".join(lines)
