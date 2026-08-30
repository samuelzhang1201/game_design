class_name KnowledgeBase
extends RefCounted
## Facts and who knows them (spec D5). Knowledge is per-character: a secret
## exists as one fact with a knower list, never as a copy per person.
## Deterministic, no RNG, no Nodes.
##
## GameState.knowledge maps fact_code to:
##   {"kind": public|secret|rumor|common_sense, "subject": String,
##    "claim_type": String, "text": String, "truth": bool,
##    "knowers": Array[String], "credibility": {char_id: float}}
##
## text/truth are stored in state, not read back from CSV, because the
## reckoning (ClaimLedger) creates facts at runtime that no CSV authored.

const ALL_KNOWERS := "ALL"

## Builds the starting knowledge from data/facts.csv. The ALL sentinel in
## initial_knowers seeds a fact to every character in the roster.
static func init_from_data(data: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for row in data.facts:
		var code := String(row["fact_code"])
		var credit: float = float(row.get("base_credibility", 50))
		var knowers: Array = []
		var credibility: Dictionary = {}
		var raw := String(row.get("initial_knowers", ""))
		var ids: Array = state.characters.keys() if raw == ALL_KNOWERS \
			else Array(raw.split("|", false))
		for id in ids:
			var char_id := String(id)
			if not state.characters.has(char_id):
				continue
			knowers.append(char_id)
			credibility[char_id] = credit
		out[code] = {
			"kind": String(row["kind"]), "subject": String(row["subject"]),
			"claim_type": String(row["claim_type"]), "text": String(row["text"]),
			"truth": String(row["truth"]).to_lower() == "true",
			"knowers": knowers, "credibility": credibility,
		}
	return out

static func knows(state: GameState, char_id: String, fact_code: String) -> bool:
	if not state.knowledge.has(fact_code):
		return false
	return char_id in state.knowledge[fact_code]["knowers"]

## This character's credibility for a fact; 0.0 when they do not know it.
static func credibility_of(state: GameState, char_id: String, fact_code: String) -> float:
	if not knows(state, char_id, fact_code):
		return 0.0
	return float(state.knowledge[fact_code]["credibility"].get(char_id, 0.0))

## Teaches a character a fact at a credibility. Idempotent on the knower list;
## a repeat call updates credibility without duplicating the knower.
static func learn(state: GameState, char_id: String, fact_code: String,
		credibility: float) -> void:
	if not state.knowledge.has(fact_code):
		return
	var fact: Dictionary = state.knowledge[fact_code]
	if not char_id in fact["knowers"]:
		fact["knowers"].append(char_id)
	fact["credibility"][char_id] = clampf(credibility, 0.0, 100.0)

## Creates a fact at runtime (the reckoning's betrayal facts). No knowers
## until learn() is called.
static func add_fact(state: GameState, fact_code: String, fields: Dictionary) -> void:
	state.knowledge[fact_code] = {
		"kind": String(fields.get("kind", "secret")),
		"subject": String(fields.get("subject", "")),
		"claim_type": String(fields.get("claim_type", "")),
		"text": String(fields.get("text", "")),
		"truth": bool(fields.get("truth", true)),
		"knowers": [], "credibility": {},
	}

## Every fact this character knows, each as the stored fact plus its "code".
static func known_facts(state: GameState, char_id: String) -> Array:
	var out: Array = []
	for code in state.knowledge:
		if knows(state, char_id, String(code)):
			var entry: Dictionary = state.knowledge[code].duplicate(true)
			entry["code"] = String(code)
			out.append(entry)
	return out

## Known facts narrowed to one claim_type and subject — the corroboration
## lookup used by Belief.
static func facts_about(state: GameState, char_id: String, claim_type: String,
		subject: String) -> Array:
	var out: Array = []
	for entry in known_facts(state, char_id):
		if String(entry["claim_type"]) == claim_type and String(entry["subject"]) == subject:
			out.append(entry)
	return out
