class_name TickEngine
extends RefCounted

var data: DataRepository
var actions: ActionSystem
var suggestions: SuggestionGenerator

func _init(d: DataRepository) -> void:
	data = d

func advance(state: GameState) -> TickReport:
	if actions == null:
		actions = ActionSystem.new(data)
	if suggestions == null:
		suggestions = SuggestionGenerator.new(data, actions)
	state.tick += 1
	var r := TickReport.new()
	r.tick = state.tick
	r.season = state.season()
	r.year = state.year()
	r.outcomes = state.recent_outcomes
	state.recent_outcomes = []
	_drift(state, r)
	r.concerns = ConcernScanner.scan(state, data)
	r.suggestions = suggestions.generate(state, r.concerns)
	return r

func _drift(state: GameState, r: TickReport) -> void:
	var m := state.metrics
	var cap := data.bal("admin_base")
	if state.council.has("chancellor"):
		var ch: Character = state.characters[state.council["chancellor"]]
		cap += ch.skills["sk_admin"] * 0.10
	else:
		cap -= data.bal("chancellor_vacancy_penalty")
	_set_metric(r, m, "admin_capacity", cap, "council administration")
	var income := m["tax_rate"] * cap * data.bal("tax_income_factor") \
		+ m["tariff_rate"] * data.bal("tariff_income_factor") + m["road_income_bonus"]
	_set_metric(r, m, "tax_income", income, "taxes and tariffs collected")
	_apply(r, m, "treasury", income - data.bal("court_upkeep"), "income minus court upkeep")
	if state.season() == "autumn":
		_apply(r, m, "grain", data.bal("harvest_gain"), "the harvest comes in")
	else:
		var drain := data.bal("grain_drain_winter") if state.season() == "winter" else data.bal("grain_drain")
		if m["grain_ration"] > 0.0:
			drain *= 0.5
		_apply(r, m, "grain", -drain, "the realm eats")
	m["grain"] = clampf(m["grain"], 0.0, 200.0 + m["grain_capacity_bonus"])
	var unrest_delta := (m["tax_rate"] - 5.0) * data.bal("unrest_tax_pressure") - data.bal("unrest_decay")
	if m["grain"] <= 0.0:
		unrest_delta += data.bal("unrest_famine")
	_apply(r, m, "unrest", unrest_delta, "tax pressure and the mood of the villages")
	m["unrest"] = clampf(m["unrest"], 0.0, 100.0)
	_drift_toward(r, m, "peasant_contentment", 50.0, data.bal("contentment_drift"), "life goes on")
	_drift_toward(r, m, "legitimacy", 50.0, data.bal("legitimacy_drift"), "memory of the crown settles")
	_drift_toward(r, m, "church_opinion", 50.0, data.bal("church_drift"), "sermons soften")
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
