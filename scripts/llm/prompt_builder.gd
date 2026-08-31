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
		lines += "\nWhat the ruler has said to you:\n" + memory
	return lines

static func briefing_prompts(report: TickReport, state: GameState) -> Dictionary:
	var personas := ""
	for seat in state.council:
		var c: Character = state.characters[state.council[seat]]
		personas += "- %s, %s. Traits: %s. Opinion of the ruler: %d.\n" % [
			c.display_name, c.seat, ", ".join(c.traits), c.opinion]
		var rels := RelationshipGraph.describe_for(state, c.id, 3)
		if rels != "":
			personas += "  Relations: %s\n" % rels.replace("\n", "; ")
	var system := """You write in-character dialogue for a medieval royal council.
Voice ONLY what the report contains — never invent numbers, actions, or events.
One short paragraph per speaking minister, plain prose, no markdown.
Council:
%s""" % personas
	return {"system": system, "user": JSON.stringify(report.to_dict(), "", true)}

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

## In-character conversational reply: the player's free text parsed to no
## action, so a role answers them directly ("who are you", "what do you make
## of the marshal"). The persona sheet (attributes, traits, live
## relationships) is the whole context; the model may only speak — it cannot
## decide actions or state (those go through parse_prompts + the validator).
static func converse_prompts(speaker_id: String, player_text: String,
		state: GameState, data: DataRepository) -> Dictionary:
	var system := """You roleplay one character at a medieval royal court, speaking to the ruler.
Your character:
%s
The realm today (engine truth — quote these numbers, never invent others):
%s
Answer the ruler in character, first person, 1-3 sentences of plain prose.
You cannot perform actions, issue orders, or change anything — you may only speak.
Never invent events, numbers, or people beyond your character sheet and the realm facts.""" % \
		[persona_context(speaker_id, state, data), realm_facts(state)]
	return {"system": system, "user": player_text}

## Compact engine-truth snapshot for conversational answers ("how is my
## army?" must be answered from these, not hallucinated).
static func realm_facts(state: GameState) -> String:
	var parts: Array = []
	for m in ["treasury", "grain", "unrest", "legitimacy", "army_quality",
			"church_opinion", "peasant_contentment", "tax_income", "tax_rate"]:
		if state.metrics.has(m):
			parts.append("%s %d" % [m, int(state.metrics[m])])
	return ", ".join(parts) + ". Season: %s, year %d." % [state.season(), state.year()]

# No event prompt exists by design (user ruling 2026-08-31). Event stories
# are fixed authored prose from RANDOM_EVENTS.md, delivered by
# Voicer.voice_event without a model. Do not add one back: if an event needs
# different words, write them in the story document.
