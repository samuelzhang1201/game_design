class_name PromptBuilder
extends RefCounted

## One role's full persona sheet for an LLM context window: identity,
## numeric attributes, skills, traits, and their live 1-hop relationship
## graph (design: role_player.md §LLM context contract). The model roleplays
## from this; it never decides state — it only picks among engine-legal
## options and writes dialogue.
static func persona_context(id: String, state: GameState, data: DataRepository) -> String:
	if not state.characters.has(id):
		return ""
	var c: Character = state.characters[id]
	var trait_labels: Array = []
	for t in c.traits:
		trait_labels.append(String(data.traits[t]["label"]) if data.traits.has(t) else String(t))
	var attrs: Array = []
	for a in ["ambition","loyalty","integrity","boldness","piety","compassion",
			"vanity","temper","pragmatism","health","wealth","prestige","influence"]:
		if c.attributes.has(a):
			attrs.append("%s %d" % [a, int(c.attributes[a])])
	var skills: Array = []
	for sk in c.skills:
		skills.append("%s %d/20" % [String(sk).trim_prefix("sk_"), int(c.skills[sk])])
	var station := c.seat if c.seat != "" else c.category
	var lines := "%s — %s%s%s%s." % [c.display_name, station,
		(", House " + c.family_name) if c.family_name != "" else "",
		(", of " + c.kingdom) if c.kingdom != "" else "",
		(", age %d" % int(c.attributes["age"])) if c.attributes.has("age") else ""]
	lines += "\nAttributes (0-100): " + ", ".join(attrs) + "."
	lines += "\nSkills: " + ", ".join(skills) + "."
	lines += "\nTraits: " + ", ".join(trait_labels) + "."
	lines += "\nOpinion of the ruler: %d." % c.opinion
	var rels := RelationshipGraph.describe_for(state, id)
	if rels != "":
		lines += "\nRelationships:\n" + rels
	# What the ruler has actually said to them, so they can refer back to it
	# rather than meeting the player fresh every time (AgentMemory).
	var memory := AgentMemory.describe_for(state, id)
	if memory != "":
		lines += "\nWhat you remember being said:\n" + memory
	# What they know and believe (KnowledgeBase) — only THEIR facts, at THEIR
	# credibility. The engine's hidden truth flags never enter any prompt.
	var knowledge := KnowledgeBase.describe_for(data, state, id)
	if knowledge != "":
		lines += "\nWhat you know and believe:\n" + knowledge
	return lines

static func parse_prompts(player_text: String, report: TickReport, state: GameState,
		data: DataRepository) -> Dictionary:
	var catalog := ""
	for code in data.actions:
		catalog += "- %s: %s\n" % [code, data.actions[code].get("notes", "")]
	var ids := ", ".join(state.characters.keys())
	var event_ctx := ""
	if not state.pending_event.is_empty():
		var choice_ids := []
		for ch in state.pending_event["choices"]:
			choice_ids.append("%s (%s)" % [ch["choice_id"], ch["label"]])
		event_ctx = ("\nAn event awaits a decision. To resolve it use action_code"
			+ " EVENT_CHOICE with params {\"choice_id\": one of: %s}.") % ", ".join(choice_ids)
	var promise_rule := "\npromise_code in promises MUST be one of the legal action codes above."
	var system := """You translate a ruler's plain-language order into game actions.
Output ONLY a JSON object, no prose, shaped exactly:
{"actions":[{"action_code":"...","params":{},"target":""}],
 "court_reaction":{"addressed":[],"tone":"neutral","promises":[]}}
Legal action codes (use ONLY these; leave "actions" empty if nothing fits):
%s
Character ids for target/addressed: %s
tone is one of respectful|neutral|curt|flattering|threatening|dismissive.%s
Current tick: %d.""" % [catalog, ids, event_ctx + promise_rule, report.tick]
	return {"system": system, "user": player_text}

## Compact engine-truth snapshot for a typed order's reply ("how is my
## army?" must be answered from these, not hallucinated).
static func realm_facts(state: GameState) -> String:
	var parts: Array = []
	for m in ["treasury", "grain", "unrest", "legitimacy", "army_quality",
			"church_opinion", "peasant_contentment", "tax_income", "tax_rate"]:
		if state.metrics.has(m):
			parts.append("%s %d" % [m, int(state.metrics[m])])
	return ", ".join(parts) + ". Season: %s, year %d." % [state.season(), state.year()]

## The single order call (spec 2026-09-09 §4): the engine-chosen speaker
## answers in character AND translates the words into impacts. Two parts,
## one reply, bound by the correlation rules below; the validator and the
## ledger clamp everything the model proposes, and the model may only move
## the fields WorldLedger.prompt_catalog offers.
static func order_prompts(player_text: String, speaker_id: String, report: TickReport,
		state: GameState, data: DataRepository) -> Dictionary:
	var persona := persona_context(speaker_id, state, data) if speaker_id != "" else \
		"the court herald — a neutral clerk who records the ruler's orders and answers plainly."
	var catalog := ""
	for code in data.actions:
		catalog += "- %s: %s\n" % [code, data.actions[code].get("notes", "")]
	var ids := ", ".join(state.characters.keys())
	var event_ctx := ""
	if not state.pending_event.is_empty():
		var choice_ids := []
		for ch in state.pending_event["choices"]:
			choice_ids.append("%s (%s)" % [ch["choice_id"], ch["label"]])
		event_ctx = ("\nAn event awaits a decision. To resolve it use action_code"
			+ " EVENT_CHOICE with params {\"choice_id\": one of: %s}.") % ", ".join(choice_ids)
	var system := """You roleplay one voice at a medieval royal court, speaking to the ruler. You are %s
The realm today (engine truth — quote these numbers, never invent others):
%s
You answer the ruler's words in character AND translate them into game effects.
Output ONLY a JSON object, no prose outside it, shaped exactly:
{"narrative": "1-3 sentences in your own voice",
 "impacts": {"actions": [{"action_code": "...", "params": {}, "target": ""}],
			 "world": [{"path": "...", "delta": 0, "reason": "a few words"}],
			 "court_reaction": {"addressed": [], "tone": "neutral", "promises": []}}}
Rules that bind the two parts together:
- Every world impact is something the narrative says happens; the narrative claims no change that is not in impacts.
- Prefer a legal action whenever one fits the order; use world impacts only for concrete consequences no action covers.
- Every impact carries a reason of a few words, in your voice.
- If the ruler only asks or converses, leave actions and world empty and let the narrative answer.
Legal action codes (use ONLY these):
%s
Fields you may move, with their caps (a delta beyond the cap is clamped; you may only move your own realm's fields):
%s
Character ids for target/addressed: %s
tone is one of respectful|neutral|curt|flattering|threatening|dismissive.%s
promise_code in promises MUST be one of the legal action codes above.
Current tick: %d.""" % [persona, realm_facts(state), catalog,
		WorldLedger.prompt_catalog(data, state), ids, event_ctx, report.tick]
	return {"system": system, "user": player_text}

# No event prompt exists by design (user ruling 2026-08-31). Event stories
# are fixed authored prose from RANDOM_EVENTS.md, delivered by
# Voicer.voice_event without a model. Do not add one back: if an event needs
# different words, write them in the story document.
