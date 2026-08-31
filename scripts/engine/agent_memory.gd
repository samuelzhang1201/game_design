class_name AgentMemory
extends RefCounted
## What each character remembers being told (spec D4, §4.3). Distinct from
## KnowledgeBase: remembering that the king said a thing is not the same as
## believing it, and belief is ClaimLedger's business. This unit only records
## that words were spoken, to whom, and in whose company.
##
## GameState.agent_memory maps character_id to an Array of exchanges, oldest
## first, capped at balance.csv's memory_exchanges_kept:
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
	var log: Array = state.agent_memory[char_id]
	log.append({
		"tick": tick, "location": location, "speaker": speaker,
		"text": text.strip_edges(), "audience": audience.duplicate(),
	})
	var cap := int(data.bal("memory_exchanges_kept"))
	while log.size() > cap:
		log.pop_front()

## This character's remembered exchanges, oldest first. Empty when they have
## never been spoken to.
static func exchanges_for(state: GameState, char_id: String) -> Array:
	return state.agent_memory.get(char_id, [])

## Prompt-ready recap for this character's LLM context: what they were told,
## and whether it was said to them alone or in company.
static func describe_for(state: GameState, char_id: String) -> String:
	var lines: Array = []
	for entry in exchanges_for(state, char_id):
		var audience: Array = entry["audience"]
		var company := "privately" if audience.size() <= 1 else "with others present"
		lines.append('You were told, %s: "%s"' % [company, String(entry["text"])])
	return "\n".join(lines)
