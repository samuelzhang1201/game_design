class_name ConversationBeats
extends RefCounted
## Builds the turn's conversation as a beat queue (spec §3). Pure - no Nodes.

static func build(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var beats: Array = []
	if not report.event.is_empty():
		beats.append({"kind": "event", "portrait_id": "round_table",
			"speaker": "The Council", "event": report.event})
	# FIX 1 (post-Task-5 review): broken/kept promises were narrated nowhere
	# under the conversation flow (report.promise_events only ever fed a
	# now-retired pre-Task-5 screen's begin-turn path). The wronged/vindicated
	# minister speaks about it, before their (or anyone's) concern/pitch
	# beat, so it reads as the first thing said about them this session.
	for pe in report.promise_events:
		var pid := String(pe.get("character_id", ""))
		if not state.characters.has(pid):
			continue
		var pc: Character = state.characters[pid]
		beats.append({"kind": "minister", "portrait_id": pid,
			"speaker": pc.display_name,
			"text": TemplateVoicer.line_for(data, "promise_" + String(pe["status"]),
				pc.traits, report.tick),
			"suggestions": []})
	var per_minister := {}   # char_id -> {texts: [], suggestions: []}
	for c in report.concerns:
		var id := _seat_char(c["seat"], state)
		if id == "":
			continue
		var entry: Dictionary = per_minister.get_or_add(id, {"texts": [], "suggestions": []})
		entry["texts"].append(TemplateVoicer.line_for(data, "concern_" + String(c["metric"]),
			state.characters[id].traits, report.tick, {"value": int(c["value"])}))
	for sug in report.suggestions:
		# Standing-menu fillers raise no topic of their own, so they neither
		# speak a pitch line nor render a reply option here (user request
		# 2026-08-31); they stay available on the court screen's order bar.
		if String(sug.get("source", "concern")) == "standing":
			continue
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
	# FIX 2 (post-Task-5 review): the summary beat carries no "text" - it's
	# computed at display time by summary_text below, from whatever has
	# actually happened by the moment the player reaches it (report.outcomes
	# PLUS anything the player just decided earlier in this very
	# conversation via a quick-reply/free-text, which live-appends to
	# state.recent_outcomes).
	beats.append({"kind": "summary", "portrait_id": "round_table", "speaker": "The Council"})
	return beats

## The ministers this report would have speak, in the order they would —
## the WAR TABLE's seal shows them waiting to be heard (owner 2026-10-01).
static func waiting(report: TickReport, state: GameState, data: DataRepository) -> Array[String]:
	var out: Array[String] = []
	if report == null:
		return out
	for b: Dictionary in build(report, state, data):
		var id := String(b.get("portrait_id", ""))
		if String(b.get("kind", "")) == "minister" and state.characters.has(id) and not id in out:
			out.append(id)
	return out

## The councillor who brings the pending event before the crown (owner
## 2026-10-02: every event waits on the table, its presenter marked, until the
## player clicks them): the holder of event_presenters.csv's seat for the
## event's id, else for its category; failing that (a seat empty, an event the
## table does not name) the holder of the first council_seats.csv seat with
## `presents_events` 1. "" when there is no event or nobody to bring it.
static func event_presenter(state: GameState, data: DataRepository) -> String:
	if state.pending_event.is_empty():
		return ""
	var event_id := String(state.pending_event.get("event_id", ""))
	var category := String((data.events_by_id.get(event_id, {}) as Dictionary).get("category", ""))
	for key in [event_id, category]:
		var seat := String(data.event_presenters.get(key, ""))
		var holder := _seat_char(seat, state) if seat != "" else ""
		if holder != "" and state.characters.has(holder):
			return holder
	for seat: String in data.seats:
		if String(data.seats[seat].get("presents_events", "0")) != "1":
			continue
		var id := _seat_char(seat, state)
		if id != "" and state.characters.has(id):
			return id
	return ""

## Composes the summary line at the moment it's shown (called from
## ConversationScene._advance, not from build): last-tick's already-decided
## outcomes (report.outcomes, prefixed once by council_summary_open) followed
## by anything resolved live during THIS conversation (state.recent_outcomes,
## one council_summary_now line each - see ActionSystem.execute, which
## appends there immediately on execution). Idle only when both are empty.
static func summary_text(report: TickReport, state: GameState, data: DataRepository) -> String:
	var lines: Array = []
	if not report.outcomes.is_empty():
		lines.append(TemplateVoicer.line_for(data, "council_summary_open", [], report.tick))
		for o in report.outcomes:
			lines.append(TemplateVoicer.line_for(data, "council_summary_decision", [],
				report.tick, {"label": o["notes"]}))
	for o in state.recent_outcomes:
		lines.append(TemplateVoicer.line_for(data, "council_summary_now", [],
			report.tick, {"label": o["notes"]}))
	if lines.is_empty():
		lines.append(TemplateVoicer.line_for(data, "council_summary_idle", [], report.tick))
	return " ".join(lines)

static func _seat_char(seat: String, state: GameState) -> String:
	return String(state.council.get(seat, ""))
