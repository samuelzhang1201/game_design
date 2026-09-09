class_name TemplateVoicer
extends RefCounted

static func render_briefing(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var lines: Array = []
	var chancellor := _speaker_for_seat("chancellor", state)
	lines.append({"speaker": chancellor["name"], "text": _line(data, "opener",
		chancellor["traits"], report.tick, {"season": report.season, "year": report.year})})
	for c in report.concerns:
		var sp := _speaker_for_seat(c["seat"], state)
		lines.append({"speaker": sp["name"], "text": _line(data, "concern_" + c["metric"],
			sp["traits"], report.tick, {"value": int(c["value"])})})
	for sug in report.suggestions:
		var sp := _speaker_for_seat(sug["seat"], state)
		lines.append({"speaker": sp["name"], "text": _line(data, "pitch_" + sug["pitch_key"],
			sp["traits"], report.tick, {"tradeoff": sug["tradeoff"]})})
	return lines

static func render_outcomes(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var lines: Array = []
	var chancellor := _speaker_for_seat("chancellor", state)
	for o in report.outcomes:
		lines.append({"speaker": chancellor["name"], "text": _line(data,
			"outcome_" + o["action_code"], chancellor["traits"], report.tick,
			{"label": o["notes"]})})
	return lines

static func _speaker_for_seat(seat: String, state: GameState) -> Dictionary:
	if state.council.has(seat):
		var c: Character = state.characters[state.council[seat]]
		return {"name": c.display_name, "traits": c.traits}
	return {"name": "The court clerk", "traits": []}

static func line_for(data: DataRepository, key: String, speaker_traits: Array,
		tick: int, vars: Dictionary = {}) -> String:
	var generic: Array = []
	var tinted: Array = []
	for row in data.templates:
		if row["key"] != key:
			continue
		if row["trait"] == "":
			generic.append(row["text"])
		elif row["trait"] in speaker_traits:
			tinted.append(row["text"])
	var pool := tinted if not tinted.is_empty() else generic
	if pool.is_empty():
		return "[missing template: %s]" % key
	# Realm labels ride along with {season}/{year} so a template can name a
	# kingdom as {raider_realm} rather than spelling this map's name. Caller
	# vars win, so a beat can still override one.
	var all_vars := data.realm_vars()
	all_vars.merge(vars, true)
	return String(pool[tick % pool.size()]).format(all_vars)

static func _line(data: DataRepository, key: String, speaker_traits: Array,
		tick: int, vars: Dictionary) -> String:
	return line_for(data, key, speaker_traits, tick, vars)
