class_name SourceTrust
extends RefCounted
## How much one character's word is worth to another (spec §4.3). Directed:
## trust in A as a source, held by B. Derived from the listener's sentiment
## toward the speaker at campaign start, then moved only by the reckoning
## (ClaimLedger), so every change carries a reason.
##
## GameState.source_trust maps "speaker>listener" to
##   {"value": float 0..100, "log": [{"tick", "delta", "reason"}]}
## An absent key is not an error: get_trust derives it on demand, which keeps
## the save small and lets pre-feature saves work untouched.

static func key(speaker: String, listener: String) -> String:
	return speaker + ">" + listener

## Derivation: a listener trusts a speaker in proportion to how they feel
## about them. clamp(50 + sentiment(listener -> speaker) / 2, 0, 100).
static func derive(data: DataRepository, state: GameState, speaker: String,
		listener: String) -> float:
	var base := data.bal("source_trust_default")
	var edge := RelationshipGraph.edge(state, listener, speaker)
	if edge.is_empty():
		return base
	return clampf(base + float(edge["sentiment"]) / 2.0, 0.0, 100.0)

## Seeds every derived pair. Optional — get_trust derives on demand — but a
## campaign calls it so the opening values are visible in the save.
static func init_from_relationships(data: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for e in state.relationships:
		var speaker := String(e["to"])
		var listener := String(e["from"])
		out[key(speaker, listener)] = {
			"value": derive(data, state, speaker, listener), "log": [],
		}
	return out

static func get_trust(data: DataRepository, state: GameState, speaker: String,
		listener: String) -> float:
	var k := key(speaker, listener)
	if state.source_trust.has(k):
		return float(state.source_trust[k]["value"])
	return derive(data, state, speaker, listener)

## Moves trust and logs why. A reason is mandatory, same rule as
## Character.change_opinion and RelationshipGraph.adjust.
static func adjust(data: DataRepository, state: GameState, speaker: String,
		listener: String, delta: float, reason: String, tick: int) -> void:
	assert(reason != "", "source trust change requires a reason")
	var k := key(speaker, listener)
	if not state.source_trust.has(k):
		# Seed from the same derivation get_trust would have returned for this
		# pair, so the two can never disagree — including after a designer
		# retunes source_trust_default in balance.csv.
		state.source_trust[k] = {
			"value": derive(data, state, speaker, listener), "log": [],
		}
	var entry: Dictionary = state.source_trust[k]
	entry["value"] = clampf(float(entry["value"]) + delta, 0.0, 100.0)
	entry["log"].append({"tick": tick, "delta": delta, "reason": reason})
