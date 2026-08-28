class_name ConversationBeats
extends RefCounted
## Builds the turn's conversation as a beat queue (spec §3). Pure - no Nodes.

static func build(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var beats: Array = []
	if not report.event.is_empty():
		beats.append({"kind": "event", "portrait_id": "round_table",
			"speaker": "The Council", "event": report.event})
	var per_minister := {}   # char_id -> {texts: [], suggestions: []}
	for c in report.concerns:
		var id := _seat_char(c["seat"], state)
		if id == "":
			continue
		var entry: Dictionary = per_minister.get_or_add(id, {"texts": [], "suggestions": []})
		entry["texts"].append(TemplateVoicer.line_for(data, "concern_" + String(c["metric"]),
			state.characters[id].traits, report.tick, {"value": int(c["value"])}))
	for sug in report.suggestions:
		var id := _seat_char(sug["seat"], state)
		if id == "":
			continue
		var entry: Dictionary = per_minister.get_or_add(id, {"texts": [], "suggestions": []})
		entry["texts"].append(TemplateVoicer.line_for(data, "pitch_" + String(sug["pitch_key"]),
			state.characters[id].traits, report.tick, {"tradeoff": sug["tradeoff"]}))
		entry["suggestions"].append(sug)
	for seat in state.council:   # seat order = insertion order (deterministic)
		var id: String = state.council[seat]
		if per_minister.has(id):
			beats.append({"kind": "minister", "portrait_id": id,
				"speaker": state.characters[id].display_name,
				"text": " ".join(per_minister[id]["texts"]),
				"suggestions": per_minister[id]["suggestions"]})
	beats.append(_summary_beat(report, data))
	return beats

static func _summary_beat(report: TickReport, data: DataRepository) -> Dictionary:
	var lines: Array = [TemplateVoicer.line_for(data, "council_summary_open", [], report.tick)]
	var decided := false
	for o in report.outcomes:
		decided = true
		lines.append(TemplateVoicer.line_for(data, "council_summary_decision", [],
			report.tick, {"label": o["notes"]}))
	if not decided:
		lines[0] = TemplateVoicer.line_for(data, "council_summary_idle", [], report.tick)
	return {"kind": "summary", "portrait_id": "round_table",
		"speaker": "The Council", "text": " ".join(lines)}

static func _seat_char(seat: String, state: GameState) -> String:
	return String(state.council.get(seat, ""))
