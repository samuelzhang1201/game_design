extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

func test_saved_second_encounter_resumes_then_upgrades_once() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := Scenario.two_battles(repo, 10)
	var engine := TickEngine.new(repo)
	var first := engine.resolve_day(state)
	assert_eq(first.status, "blocked")
	if first.status != "blocked": return
	DayResolution.acknowledge(state.day_resolution, state.day_resolution.pending_decision.token, "continue")
	var second := engine.resolve_day(state)
	assert_eq(second.status, "blocked")
	if second.status != "blocked": return
	# Represent the accepted pre-roster save, retaining its saved equipment and day cursor.
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	var tx := state.day_resolution.duplicate(true)
	var chest: float = state.metrics.treasury
	var a := Scenario.roundtrip(state)
	var b := Scenario.roundtrip(state)
	for loaded: GameState in [a, b]:
		assert_false(MilitaryBootstrap.migrate(repo, loaded).has("error"))
		assert_eq(loaded.day_resolution, tx)
		assert_true(bool(loaded.military_migration.get("organization_pending", false)))
		assert_eq(int(loaded.military_migration.get("organization_version", 0)), 0)
		DayResolution.acknowledge(loaded.day_resolution, loaded.day_resolution.pending_decision.token, "continue")
		var result := TickEngine.new(repo).resolve_day(loaded)
		assert_eq(result.status, "complete")
		assert_false(MilitaryReorganization.reconcile(repo, loaded).has("error"))
		assert_eq(int(loaded.military_migration.get("organization_version", 0)), 1)
		assert_false(bool(loaded.military_migration.get("organization_pending", false)))
		assert_eq(loaded.metrics.treasury, chest, "migration never repays an order")
	assert_eq(SaveLoad.state_hash(a), SaveLoad.state_hash(b))
	var again := Scenario.roundtrip(a)
	var before := SaveLoad.state_hash(again)
	assert_false(MilitaryBootstrap.migrate(repo, again).has("error"))
	assert_eq(SaveLoad.state_hash(again), before)
