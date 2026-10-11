class_name KnowledgeBase
extends RefCounted
## Facts and who knows them (spec D5). Knowledge is per-character: a secret
## exists as one fact with a knower list, never as a copy per person.
## Deterministic, no RNG, no Nodes.
##
## GameState.knowledge maps fact_code to:
##   {"kind": public|secret|rumor|common_sense, "subject": String,
##    "claim_type": String, "text": String, "truth": bool, "source": String,
##    "knowers": Array[String], "credibility": {char_id: float}}
## "source" is the char_id who planted this fact via a claim, or "" when the
## fact is authored (CSV-seeded) or arrived independently of any speaker —
## the provenance ClaimLedger._reality_known and Belief._corroboration use to
## tell an independent route to the truth from a speaker corroborating himself.
##
## text/truth are stored in state, not read back from CSV, because the
## reckoning (ClaimLedger) creates facts at runtime that no CSV authored.

const ALL_KNOWERS := "ALL"

## Builds the starting knowledge from data/intel/facts.csv. The ALL sentinel in
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
			"truth": String(row["truth"]).to_lower() == "true", "source": "",
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

## Reverses learn(): the character no longer knows this fact. A no-op when
## they never knew it or the fact does not exist (spec §6, a caught lie stops
## being knowledge — the listener cannot simultaneously hold the lie and the
## truth that exposed it).
static func unlearn(state: GameState, char_id: String, fact_code: String) -> void:
	if not state.knowledge.has(fact_code):
		return
	var fact: Dictionary = state.knowledge[fact_code]
	var knowers: Array = fact["knowers"]
	if char_id in knowers:
		knowers.erase(char_id)
	var credibility: Dictionary = fact["credibility"]
	if credibility.has(char_id):
		credibility.erase(char_id)

## Creates a fact at runtime (the reckoning's betrayal facts, or a claim's
## own believed fact). No knowers until learn() is called. "source" is the
## char_id who spoke this into being, or "" for an authored/independent fact.
static func add_fact(state: GameState, fact_code: String, fields: Dictionary) -> void:
	state.knowledge[fact_code] = {
		"kind": String(fields.get("kind", "secret")),
		"subject": String(fields.get("subject", "")),
		"claim_type": String(fields.get("claim_type", "")),
		"text": String(fields.get("text", "")),
		"truth": bool(fields.get("truth", true)),
		"source": String(fields.get("source", "")),
		"knowers": [], "credibility": {},
	}

## Every fact this character knows, each as the stored fact plus its "code",
## sorted by fact_code. Insertion order into state.knowledge is not stable
## across a save round-trip (SaveLoad stringifies with sort_keys=true), so
## this sorts defensively rather than relying on Dictionary iteration order.
static func known_facts(state: GameState, char_id: String) -> Array:
	var codes: Array = []
	for code in state.knowledge:
		if knows(state, char_id, String(code)):
			codes.append(String(code))
	codes.sort()
	var out: Array = []
	for code in codes:
		var entry: Dictionary = state.knowledge[code].duplicate(true)
		entry["code"] = String(code)
		out.append(entry)
	return out

## Prompt-ready recap of what this character knows and how firmly they hold
## it, for their LLM persona sheet (review finding 2026-09-01: knowledge
## never reached the voiced character, so a minister could not speak of
## secrets they know). Confidence phrasing comes from the character's OWN
## credibility for each fact — never from the engine's hidden truth flag,
## which must stay invisible to the model (a believed lie reads exactly like
## knowledge here; that is the point).
static func describe_for(data: DataRepository, state: GameState, char_id: String) -> String:
	var lines: Array = []
	for fact in known_facts(state, char_id):
		var cred := float(fact["credibility"].get(char_id, 0.0))
		var opener := "You know"
		if cred < data.bal("knowledge_doubt_threshold"):
			opener = "You have heard, though you doubt it"
		elif cred < data.bal("knowledge_sure_threshold"):
			opener = "You believe"
		var marker := ""
		match String(fact["kind"]):
			"secret":
				marker = " (a secret — do not reveal it lightly)"
			"rumor":
				marker = " (hearsay)"
		lines.append("%s: %s%s" % [opener, String(fact["text"]), marker])
	return "\n".join(lines)

## Known facts narrowed to one claim_type and subject — the corroboration
## lookup used by Belief.
static func facts_about(state: GameState, char_id: String, claim_type: String,
		subject: String) -> Array:
	var out: Array = []
	for entry in known_facts(state, char_id):
		if String(entry["claim_type"]) == claim_type and String(entry["subject"]) == subject:
			out.append(entry)
	return out
