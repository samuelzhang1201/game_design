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
	var system := """You translate a ruler's plain-language order into game actions.
Output ONLY a JSON object, no prose, shaped exactly:
{"actions":[{"action_code":"...","params":{},"target":""}],
 "court_reaction":{"addressed":[],"tone":"neutral","promises":[]}}
Legal action codes (use ONLY these; leave "actions" empty if nothing fits):
%s
Character ids for target/addressed: %s
tone is one of respectful|neutral|curt|flattering|threatening|dismissive.
Current tick: %d.""" % [catalog, ids, report.tick]
	return {"system": system, "user": player_text}
