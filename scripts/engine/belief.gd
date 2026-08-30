class_name Belief
extends RefCounted
## Turns an externally supplied plausibility into this listener's belief
## (spec 2.1). The model may judge how credible a claim sounds in the
## abstract; who is speaking, who is listening, and what they already know
## are engine business, so relationship maths stays testable and a model can
## never adjudicate its own trust with the player.
##
## Pure and deterministic: no RNG, no Nodes, no state mutation.

## `claim`: {"claim_type", "subject", "text", "magnitude", "truth"}.
## `plausibility`: 0..100 from the judge (or a test).
## Returns {"belief", "vetoed", "rule_code", "corroboration", "reason"}.
static func score(data: DataRepository, state: GameState, listener: String,
		speaker: String, claim: Dictionary, plausibility: float) -> Dictionary:
	var veto := WorldRules.veto(data, String(claim["claim_type"]),
		String(claim["text"]), float(claim.get("magnitude", 0.0)))
	if bool(veto["vetoed"]):
		return {"belief": 0.0, "vetoed": true,
			"rule_code": String(veto["rule_code"]), "corroboration": 0,
			"reason": "impossible on its face: " + String(veto["reason"])}
	var trust := SourceTrust.get_trust(data, state, speaker, listener)
	var corroboration := _corroboration(state, listener, speaker, claim)
	var trait_mod := _trait_modifier(data, state, listener)
	var raw := plausibility * (trust / 100.0) \
		+ trait_mod \
		+ float(corroboration) * data.bal("belief_corroboration_bonus")
	return {
		"belief": clampf(raw, 0.0, 100.0), "vetoed": false, "rule_code": "",
		"corroboration": corroboration,
		"reason": "plausibility %d, trust %d, corroboration %d" % [
			int(plausibility), int(trust), corroboration],
	}

## Net count of the listener's known facts on the same claim_type and subject
## that did not come from this same speaker: +1 each when their truth agrees
## with the claim, -1 each when it does not. A speaker's own earlier claims on
## the same subject are excluded — corroboration must come from an
## independent source, or a speaker could corroborate himself by repetition
## (spec §6).
static func _corroboration(state: GameState, listener: String, speaker: String,
		claim: Dictionary) -> int:
	var net := 0
	var claim_truth := bool(claim.get("truth", true))
	for fact in KnowledgeBase.facts_about(state, listener,
			String(claim["claim_type"]), String(claim["subject"])):
		if String(fact.get("source", "")) == speaker:
			continue
		net += 1 if bool(fact["truth"]) == claim_truth else -1
	return net

static func _trait_modifier(data: DataRepository, state: GameState, listener: String) -> float:
	if not state.characters.has(listener):
		return 0.0
	var c: Character = state.characters[listener]
	var mod := 0.0
	if "paranoid" in c.traits:
		mod += data.bal("belief_trait_paranoid")
	if "trusting" in c.traits:
		mod += data.bal("belief_trait_trusting")
	return mod
