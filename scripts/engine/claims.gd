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
			"source": claimant,
		})
		KnowledgeBase.learn(state, listener, fact_code, belief)
	var rec := {
		"claimant": claimant, "listener": listener,
		"claim_type": String(claim["claim_type"]),
		"subject": String(claim["subject"]), "text": String(claim["text"]),
		"truth": bool(claim["truth"]), "belief": belief, "believed": believed,
		"tick": tick, "status": "open" if believed else "disbelieved",
		"fact_code": fact_code,
	}
	state.claims.append(rec)
	return rec

## Believed claims still awaiting their reckoning, in record order.
static func open_claims(state: GameState) -> Array:
	var out: Array = []
	for c in state.claims:
		if String(c["status"]) == "open":
			out.append(c)
	return out

const BETRAYAL_PREFIX := "betrayal_"

## Resolves every open claim whose listener has since learned a contradicting
## true fact (spec §6, "The reckoning"). Returns one entry per resolution:
##   {"claim", "status", "trust_delta", "betrayal_fact"}
## Deterministic and idempotent: a resolved claim leaves the open list.
static func resolve_due(data: DataRepository, state: GameState, tick: int) -> Array:
	var out: Array = []
	for claim in open_claims(state):
		if not _reality_known(state, claim):
			continue
		out.append(_resolve(data, state, claim, tick))
	return out

## True when the listener knows a true fact on the same claim_type and
## subject that is not the claim's own fact, and did not arrive via this same
## claimant — reality has caught up with what they were told, through an
## independent route (spec §6: a lie is exposed by an independent route, not
## by the speaker's own earlier word). Named for reality rather than
## contradiction because it fires for honest claims too, which is how
## truth-telling earns trust.
static func _reality_known(state: GameState, claim: Dictionary) -> bool:
	var claimant := String(claim["claimant"])
	for fact in KnowledgeBase.facts_about(state, String(claim["listener"]),
			String(claim["claim_type"]), String(claim["subject"])):
		if String(fact["code"]) == String(claim["fact_code"]):
			continue
		if String(fact.get("source", "")) == claimant:
			continue
		if bool(fact["truth"]):
			return true
	return false

static func _resolve(data: DataRepository, state: GameState, claim: Dictionary,
		tick: int) -> Dictionary:
	var claimant := String(claim["claimant"])
	var listener := String(claim["listener"])
	var betrayal := ""
	var trust_delta := 0.0
	if bool(claim["truth"]):
		claim["status"] = "kept"
		trust_delta = data.bal("truth_told_trust_gain")
		SourceTrust.adjust(data, state, claimant, listener, trust_delta,
			"told the truth about " + String(claim["subject"]), tick)
	else:
		claim["status"] = "caught"
		trust_delta = -data.bal("lie_caught_trust_penalty")
		var reason := "lied about " + String(claim["subject"])
		SourceTrust.adjust(data, state, claimant, listener, trust_delta, reason, tick)
		RelationshipGraph.adjust(state, listener, claimant,
			-data.bal("lie_relationship_penalty"), reason, tick)
		var claim_fact_code := String(claim["fact_code"])
		if claim_fact_code != "":
			KnowledgeBase.unlearn(state, listener, claim_fact_code)
		betrayal = "%s%d" % [BETRAYAL_PREFIX, state.claims.size() + state.knowledge.size()]
		KnowledgeBase.add_fact(state, betrayal, {
			"kind": "secret", "subject": claimant, "claim_type": "loyalty",
			"text": "%s lied about %s." % [_display_name(state, claimant),
				String(claim["subject"])],
			"truth": true,
		})
		# The wronged character knows it firsthand; propagation spreads it.
		KnowledgeBase.learn(state, listener, betrayal, 100.0)
	return {"claim": claim, "status": String(claim["status"]),
		"trust_delta": trust_delta, "betrayal_fact": betrayal}

static func _display_name(state: GameState, char_id: String) -> String:
	if state.characters.has(char_id):
		return state.characters[char_id].display_name
	return char_id
