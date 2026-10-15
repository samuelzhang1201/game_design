extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

var repo: DataRepository

func before_each() -> void:
	repo = SuiteData.repo()

func _resolve(engine: TickEngine, state: GameState) -> Dictionary:
	return engine.call("resolve_day", state)

func _ready_engine(engine: TickEngine) -> bool:
	assert_true(engine.has_method("resolve_day"), "day resolution must expose blocked/complete")
	return engine.has_method("resolve_day")

func test_encounter_blocks_before_any_round_and_retries_do_nothing() -> void:
	var s := Scenario.contact(repo, 10)
	var engine := TickEngine.new(repo)
	if not _ready_engine(engine):
		return
	var out := _resolve(engine, s)
	assert_eq(out["status"], "blocked")
	assert_eq(s.day, 10)
	assert_eq(s.battles.size(), 1)
	assert_eq(int(s.battles[0]["rounds"]), 0)
	for e: Dictionary in s.foes.values():
		assert_eq(int(e.get("dead", 0)), 0)
	var held := SaveLoad.state_hash(s)
	_resolve(engine, s)
	_resolve(engine, s)
	assert_eq(SaveLoad.state_hash(s), held, "retry must not repeat march, food, scouts or RNG")

func test_acknowledge_resumes_same_day_once() -> void:
	var s := Scenario.contact(repo, 10)
	var engine := TickEngine.new(repo)
	if not _ready_engine(engine):
		return
	var blocked := _resolve(engine, s)
	var token := String(blocked["decision"]["token"])
	var invalid: Dictionary = engine.call("resolve_decision", s, token, "bad")
	assert_eq(invalid["status"], "invalid")
	assert_eq(_resolve(engine, s)["status"], "blocked")
	var accepted: Dictionary = engine.call("resolve_decision", s, token, "continue")
	assert_eq(accepted["status"], "accepted")
	var duplicate: Dictionary = engine.call("resolve_decision", s, token, "continue")
	assert_eq(duplicate["status"], "duplicate")
	var out := _resolve(engine, s)
	assert_eq(out["status"], "complete")
	assert_eq(s.day, 11)
	assert_eq(int(s.battles[0]["rounds"]), 1)
	assert_eq(out["journal"]["battles"].filter(func(e: Dictionary) -> bool: return e["kind"] == "start").size(), 1)
	assert_eq(s.get("day_resolution"), {})

func test_blocked_roundtrip_preserves_journal_and_rng() -> void:
	var s := Scenario.contact(repo, 10)
	var engine := TickEngine.new(repo)
	if not _ready_engine(engine):
		return
	var blocked := _resolve(engine, s)
	var loaded := Scenario.roundtrip(s)
	var resumed := TickEngine.new(repo)
	assert_eq(_resolve(resumed, loaded)["decision"], blocked["decision"])
	var token := String(blocked["decision"]["token"])
	engine.call("resolve_decision", s, token, "continue")
	resumed.call("resolve_decision", loaded, token, "continue")
	var uninterrupted := _resolve(engine, s)
	var restored := _resolve(resumed, loaded)
	assert_eq(restored["journal"], uninterrupted["journal"])
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))

func test_month_end_blocks_before_settlement() -> void:
	var s := Scenario.contact(repo, 30)
	var engine := TickEngine.new(repo)
	if not _ready_engine(engine):
		return
	var treasury: float = s.metrics["treasury"]
	var blocked := _resolve(engine, s)
	assert_eq(blocked["status"], "blocked")
	assert_eq(s.tick, 1)
	assert_eq(s.day, 30)
	assert_eq(s.metrics["treasury"], treasury)
	engine.call("resolve_decision", s, String(blocked["decision"]["token"]), "continue")
	var out := _resolve(engine, s)
	assert_eq(out["status"], "complete")
	assert_eq(s.tick, 2)
	assert_eq(s.day, 1)
	var report: TickReport = out["report"]
	assert_eq(report.metric_deltas.filter(func(d: Dictionary) -> bool: return d["reason"] == "ministers' salaries").size(), 1)

func test_completed_work_is_never_replayed_across_encounter_save() -> void:
	var s := Scenario.contact(repo, 10)
	var engine := TickEngine.new(repo)
	repo.balance["artisan_speed_cap_permille"] = 0
	var cells := MapManors.manors_of_house(repo, s, MapManors.crown(s), repo.resolve_realm("player_realm"))
	var cell := int(cells[0])
	assert_true(MapManors.start_work(repo, s, cell, "palisade", "test construction"))
	var blocked := _resolve(engine, s)
	assert_eq(int(s.manor_works[str(cell)][0]["done"]), 1000)
	s = Scenario.roundtrip(s)
	engine = TickEngine.new(repo)
	engine.advance_day(s)
	assert_null(engine.advance(s), "a different adapter cannot bypass the same decision")
	assert_eq(int(s.manor_works[str(cell)][0]["done"]), 1000)
	engine.resolve_decision(s, String(blocked["decision"]["token"]), "continue")
	_resolve(engine, s)
	assert_eq(int(s.manor_works[str(cell)][0]["done"]), 1000)
	assert_eq(s.day, 11)
	assert_eq(s.tick, 1, "the blocked ordinary day cannot be upgraded to a month settlement")

func test_acknowledged_save_does_not_ask_again() -> void:
	var s := Scenario.contact(repo, 10)
	var engine := TickEngine.new(repo)
	var blocked := _resolve(engine, s)
	engine.resolve_decision(s, String(blocked["decision"]["token"]), "continue")
	var loaded := Scenario.roundtrip(s)
	assert_eq(_resolve(TickEngine.new(repo), loaded)["status"], "complete")
	assert_eq(loaded.day, 11)
	assert_eq(int(loaded.battles[0]["rounds"]), 1)

func test_all_first_contacts_are_acknowledged_before_any_losses() -> void:
	var s := Scenario.two_battles(repo, 10)
	var engine := TickEngine.new(repo)
	var first := engine.resolve_day(s)
	assert_eq(first["status"], "blocked")
	assert_eq(s.battles.size(), 2)
	engine.resolve_decision(s, String(first["decision"]["token"]), "continue")
	var second := engine.resolve_day(s)
	assert_eq(second["status"], "blocked")
	assert_ne(second["decision"]["token"], first["decision"]["token"])
	for battle: Dictionary in s.battles:
		assert_eq(int(battle["rounds"]), 0)
	var loaded := Scenario.roundtrip(s)
	var resumed := TickEngine.new(repo)
	assert_eq(resumed.resolve_day(loaded)["decision"], second["decision"])
	engine.resolve_decision(s, String(second["decision"]["token"]), "continue")
	resumed.resolve_decision(loaded, String(second["decision"]["token"]), "continue")
	var out := engine.resolve_day(s)
	resumed.resolve_day(loaded)
	assert_eq(out["status"], "complete")
	assert_eq(out["journal"]["battles"].filter(func(e: Dictionary) -> bool: return e["kind"] == "round").size(), 2)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))
	assert_eq(engine.resolve_decision(s, String(first["decision"]["token"]), "continue")["status"], "stale")

func test_month_end_roundtrip_settles_once_with_same_report() -> void:
	var s := Scenario.contact(repo, 30)
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(s)
	var loaded := Scenario.roundtrip(s)
	var resumed := TickEngine.new(repo)
	var token := String(blocked["decision"]["token"])
	engine.resolve_decision(s, token, "continue")
	resumed.resolve_decision(loaded, token, "continue")
	var original := engine.resolve_day(s)
	var restored := resumed.resolve_day(loaded)
	assert_eq(restored["journal"], original["journal"])
	assert_eq(restored["report"].metric_deltas, original["report"].metric_deltas)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))
	assert_eq(loaded.tick, 2)
	assert_eq(loaded.day, 1)
