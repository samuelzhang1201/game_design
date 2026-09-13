class_name TickEngine
extends RefCounted

var data: DataRepository
var actions: ActionSystem
var suggestions: SuggestionGenerator
var events: EventSystem

func _init(d: DataRepository) -> void:
	data = d
	actions = ActionSystem.new(d)
	suggestions = SuggestionGenerator.new(d, actions)
	events = EventSystem.new(d)

## One day (owner 2026-09-13: the smallest unit of time). Works in
## progress step; the fifteenth day's end is a tick, which the caller
## (Game.advance_day) runs through advance(). Returns the works finished
## today, [{cell, building}].
func advance_day(state: GameState) -> Array:
	state.day = mini(state.day + 1, Calendar.DAYS_PER_TICK)
	return MapManors.advance_works(data, state)

func advance(state: GameState) -> TickReport:
	state.tick += 1
	state.day = 1
	var r := TickReport.new()
	r.finished_works = MapManors.advance_works(data, state)
	r.tick = state.tick
	r.season = state.season()
	r.year = state.year()
	r.outcomes = state.recent_outcomes
	state.recent_outcomes = []
	_drift(state, r)
	r.relationship_deltas = RelationshipGraph.drift(state, data)
	r.claim_resolutions = ClaimLedger.resolve_due(data, state, state.tick)
	for pr in state.promises:
		if String(pr["status"]) == "open" and state.tick > int(pr["tick_due"]):
			pr["status"] = "broken"
			var who: String = String(pr["character_id"])
			if state.characters.has(who):
				var c: Character = state.characters[who]
				c.change_opinion(int(data.bal("promise_broken_opinion")),
					"a promise broken: " + String(pr["promise_code"]), state.tick)
				if not "grudge" in c.flags:
					c.flags.append("grudge")
			r.promise_events.append({"character_id": who,
				"promise_code": String(pr["promise_code"]), "status": "broken"})
	r.concerns = ConcernScanner.scan(state, data)
	r.suggestions = suggestions.generate(state, r.concerns)
	r.event = events.roll(state).duplicate(true)
	return r

func _drift(state: GameState, r: TickReport) -> void:
	var m := state.metrics
	var cap := data.bal("admin_base")
	if state.council.has("chancellor"):
		var ch: Character = state.characters[state.council["chancellor"]]
		var capacity_bonus_per_skill: float = float(data.seats["chancellor"]["capacity_bonus_per_skill"])
		cap += ch.skills["sk_admin"] * capacity_bonus_per_skill
	else:
		cap -= data.bal("chancellor_vacancy_penalty")
	_set_metric(r, m, "admin_capacity", cap, "council administration")
	var income: float = m["tax_rate"] * cap * data.bal("tax_income_factor") \
		+ m["tariff_rate"] * data.bal("tariff_income_factor") + m["road_income_bonus"]
	_set_metric(r, m, "tax_income", income, "taxes and tariffs collected")
	_apply(r, m, "treasury", income - data.bal("court_upkeep"), "income minus court upkeep")
	# Manor rents (MANOR_SYSTEM.md §3): what the crown's own manors yield,
	# on top of taxes and tariffs — a manor bought is a manor that pays.
	var rents := MapManors.crown_rents(data, state)
	_set_metric(r, m, "manor_rents", rents, "rents from the crown's manors")
	if rents > 0.0:
		_apply(r, m, "treasury", rents, "rents from the crown's manors")
	# What the crown's finished buildings do each tick (2026-09-13): a
	# market's tolls, a mill's flour, a chapel's sermons, a hall's order.
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "treasury", float(built["treasury"]), "tolls and rents of the crown's buildings")
	_apply(r, m, "grain", float(built["grain"]), "the crown's mills and granaries")
	_apply(r, m, "church_opinion", float(built["church_opinion"]), "the crown's chapels")
	_apply(r, m, "peasant_contentment", float(built["peasant_contentment"]), "lords in residence")
	_apply(r, m, "unrest", float(built["unrest"]), "the crown's walls")
	if state.season() == "autumn":
		_apply(r, m, "grain", data.bal("harvest_gain"), "the harvest comes in")
	else:
		var drain := data.bal("grain_drain_winter") if state.season() == "winter" else data.bal("grain_drain")
		if m["grain_ration"] > 0.0:
			drain *= 0.5
		_apply(r, m, "grain", -drain, "the realm eats")
	m["grain"] = clampf(m["grain"], 0.0, data.bal("grain_cap_base") + m["grain_capacity_bonus"])
	var unrest_delta: float = (m["tax_rate"] - data.bal("unrest_tax_pivot")) * data.bal("unrest_tax_pressure") - data.bal("unrest_decay")
	if m["grain"] <= 0.0:
		unrest_delta += data.bal("unrest_famine")
	_apply(r, m, "unrest", unrest_delta, "tax pressure and the mood of the villages")
	m["unrest"] = clampf(m["unrest"], 0.0, 100.0)
	_drift_toward(r, m, "peasant_contentment", data.bal("drift_baseline"), data.bal("contentment_drift"), "life goes on")
	_drift_toward(r, m, "legitimacy", data.bal("drift_baseline"), data.bal("legitimacy_drift"), "memory of the crown settles")
	_drift_toward(r, m, "church_opinion", data.bal("drift_baseline"), data.bal("church_drift"), "sermons soften")
	if m["army_quality"] > data.bal("army_floor"):
		_apply(r, m, "army_quality", -data.bal("army_decay"), "drills lapse")

func _apply(r: TickReport, m: Dictionary, metric: String, delta: float, reason: String) -> void:
	if is_zero_approx(delta):
		return
	m[metric] = m[metric] + delta
	r.metric_deltas.append({"metric": metric, "delta": delta, "reason": reason})

func _set_metric(r: TickReport, m: Dictionary, metric: String, value: float, reason: String) -> void:
	var delta: float = value - m[metric]
	m[metric] = value
	if not is_zero_approx(delta):
		r.metric_deltas.append({"metric": metric, "delta": delta, "reason": reason})

func _drift_toward(r: TickReport, m: Dictionary, metric: String, baseline: float, rate: float, reason: String) -> void:
	var delta := clampf(baseline - m[metric], -rate, rate)
	_apply(r, m, metric, delta, reason)
