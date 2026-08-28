class_name PromptBuilder
extends RefCounted

static func briefing_prompts(report: TickReport, state: GameState) -> Dictionary:
	var personas := ""
	for id in state.characters:
		var c: Character = state.characters[id]
		personas += "- %s, %s. Traits: %s. Opinion of the ruler: %d.\n" % [
			c.display_name, c.seat, ", ".join(c.traits), c.opinion]
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
		event_ctx = "\nAn event awaits a decision. To resolve it use action_code EVENT_CHOICE with params {\"choice_id\": one of: %s}." % ", ".join(choice_ids)
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

static func briefing_prompts_for_event(ev: Dictionary, state: GameState, template_line: String) -> Dictionary:
	var system := """You narrate a single scene at a medieval royal court.
Rewrite the scene below in 2-3 vivid sentences, second person, present tense.
Do not add choices, numbers, or events beyond what the scene states."""
	return {"system": system, "user": "Scene (tick %d): %s" % [state.tick, template_line]}
