class_name ClaimLedger
extends RefCounted
## Every assertion made to a character, with the engine's ground truth
## attached (spec §6). A believed claim becomes a fact the listener knows, so
## a swallowed lie behaves exactly like knowledge until reality contradicts
## it — at which point resolve_due (Task 6) collects the debt.
##
## Records live in GameState.claims:
##   {"claimant", "listener", "claim_type", "subject", "text", "truth",
##    "belief", "believed", "tick", "status", "fact_code"}
## status: open | disbelieved | kept | caught

const FACT_PREFIX := "claim_"

## Records one claim and, when believed, teaches it to the listener.
## `claim`: {"claim_type", "subject", "text", "magnitude", "truth"}.
static func record(data: DataRepository, state: GameState, claimant: String,
		listener: String, claim: Dictionary, plausibility: float,
		tick: int) -> Dictionary:
	var scored := Belief.score(data, state, listener, claimant, claim, plausibility)
	var belief := float(scored["belief"])
	var believed := belief >= data.bal("belief_threshold")
	var fact_code := ""
	if believed:
		fact_code = "%s%d" % [FACT_PREFIX, state.claims.size()]
		KnowledgeBase.add_fact(state, fact_code, {
			"kind": "rumor", "subject": String(claim["subject"]),
			"claim_type": String(claim["claim_type"]),
			"text": String(claim["text"]), "truth": bool(claim["truth"]),
		})
		KnowledgeBase.learn(state, listener, fact_code, belief)
	var record := {
		"claimant": claimant, "listener": listener,
		"claim_type": String(claim["claim_type"]),
		"subject": String(claim["subject"]), "text": String(claim["text"]),
		"truth": bool(claim["truth"]), "belief": belief, "believed": believed,
		"tick": tick, "status": "open" if believed else "disbelieved",
		"fact_code": fact_code,
	}
	state.claims.append(record)
	return record

## Believed claims still awaiting their reckoning, in record order.
static func open_claims(state: GameState) -> Array:
	var out: Array = []
	for c in state.claims:
		if String(c["status"]) == "open":
			out.append(c)
	return out
