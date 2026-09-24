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
	var done := MapManors.advance_works(data, state)
	# A day on the road for every regiment under a march order (owner
	# 2026-09-22). The arrivals go on day_arrivals rather than into the
	# return value, which is the finished WORKS and is asserted as such by
	# tests/engine/test_tick_engine.gd.
	day_arrivals = ArmySystem.march_day(data, state)
	# The month's economy is computed a bucket a day (spec §11.2).
	RealmEconomy.step_day(data, state)
	return done

## The regiments that reached their destination in the last advance_day, in
## code order — read by Game for the news bar and by nothing else.
var day_arrivals: Array = []


func advance(state: GameState) -> TickReport:
	var r := TickReport.new()
	# The month that just ended is settled BEFORE the tick moves: its lines
	# are the month's own (growth of tick t), and the ledger reasons carry
	# its tick.
	_settle_economy(state, r)
	# The regiments' month (owner 2026-09-17): wounded return, supplies spent.
	ArmySystem.settle_month(data, state)
	state.tick += 1
	state.day = 1
	r.finished_works = MapManors.advance_works(data, state)
	# The tick IS a day on the road too (owner 2026-09-24: 行进速度必须和给定
	# 的速度相符): without this a regiment marched 29 days in every 30 and
	# its piece stood still for one day each month.
	day_arrivals = ArmySystem.march_day(data, state)
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

## The month's settlement (spec §5): the crown's provinces in full, the
## crown's share of the rest, less the ministers' salaries and the court's
## ration; the harvest in autumn. Whole gold, from RealmEconomy's sums.
func _settle_economy(state: GameState, r: TickReport) -> void:
	# Every key is there: GameState.default_metrics is the one place a
	# metric's presence is settled, for a fresh campaign and an old save alike.
	var m := state.metrics
	var p := RealmEconomy.purses(data, state)
	var lord: Dictionary = p["lord"]
	var crown_share: Dictionary = p["realm_share"]
	# Two purses (owner 2026-09-14). The LORD's: the provinces the player's
	# house controls pay into it in full — gold, strategic and civil goods.
	_apply(r, m, "lord_gold", float(int(lord["tax"])), "taxes of your own provinces")
	_apply(r, m, "lord_strategic", float(int(lord["strategic"])), "your own provinces' strategic goods")
	_apply(r, m, "lord_civil", float(int(lord["civil"])), "your own provinces' civil goods")
	# The CROWN's treasury and stores: its share of every other province.
	_apply(r, m, "treasury", float(int(crown_share["tax"])), "the crown's share of the realm's taxes")
	_apply(r, m, "strategic", float(int(crown_share["strategic"])),
		"the crown's share of the realm's strategic goods")
	_apply(r, m, "grain", float(int(crown_share["civil"])), "the crown's share of the realm's civil goods")
	_set_metric(r, m, "tax_income", float(int(lord["tax"]) + int(crown_share["tax"])), "taxes collected this month")
	# The court is the crown's: its ministers and its table.
	var salaries := 0
	for seat: String in state.council:
		salaries += int(float((data.seats.get(seat, {}) as Dictionary).get("salary_gold", 0)))
	_apply(r, m, "treasury", float(-salaries), "ministers' salaries")
	var people := 0
	for code: String in MapManors.controlled_provinces(data, state):
		people += RealmEconomy._figure(data, state, "economy.provinces.%s.rural_population" % code)
		people += RealmEconomy._figure(data, state, "economy.provinces.%s.urban_population" % code)
	var ration := int(roundf(float(people) / 1000.0 * data.bal("ration_gold_per_1000")))
	if m.get("grain_ration", 0.0) > 0.0:
		@warning_ignore("integer_division")  # whole gold (invariant 11)
		ration = ration / 2
	_apply(r, m, "grain", float(-ration), "the court's ration")
	# The harvest and the buildings are the lord's own fields and walls.
	if Calendar.season_name(state.tick + 1) == "Autumn":
		_apply(r, m, "lord_civil", float(int(roundf(float(people) / 1000.0 * data.bal("harvest_civil_per_1000")))),
			"the harvest comes in")
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "lord_gold", float(int(built["treasury"])), "tolls and rents of your buildings")
	_apply(r, m, "lord_civil", float(int(built["grain"])), "your mills and granaries")
	# The floor is a line like any other (invariant 4): what could not be
	# eaten is written off with its reason, never cut silently.
	for pool: String in ["grain", "lord_civil"]:
		if m[pool] < 0.0:
			_apply(r, m, pool, -m[pool], "the stores cannot fall below empty")
	if data.bal("economy_check_full") > 0.0:
		var bad := RealmEconomy.check_full(data, state)
		if not bad.is_empty():
			push_error("economy_check_full: %d province(s) differ from the cache: %s" % [bad.size(), str(bad[0])])

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
	# What the crown's finished buildings do each tick (2026-09-13): a
	# chapel's sermons, a hall's order, its walls (the gold and the goods
	# are settled with the month, in _settle_economy).
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "church_opinion", float(built["church_opinion"]), "the crown's chapels")
	_apply(r, m, "peasant_contentment", float(built["peasant_contentment"]), "lords in residence")
	_apply(r, m, "unrest", float(built["unrest"]), "the crown's walls")
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
