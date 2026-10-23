extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

func test_saved_second_encounter_resumes_then_upgrades_once() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := Scenario.two_battles(repo, 10)
	# Freeze this fixture as a pre-v2 save, rather than the capped new opening.
	state.military_migration.erase("living_cap_version")
	# Only the two encounter pairs belong to this frozen-day import fixture.
	var participants: Array = load("res://tests/invasion_play.gd").land_regiments(repo, 400).slice(0, 2)
	participants.append_array(state.foes.keys())
	for code: String in state.army_roster.keys():
		if code in participants: continue
		state.army_roster.erase(code)
		state.regiments.erase(code)
		for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []): state.military_cohorts.erase(id)
		state.military_rosters.erase(code)
	for town: String in state.town_seat.keys():
		if not state.town_seat[town] in participants: state.town_seat.erase(town)

	# The old save already has an open day; do not migrate a new-day fixture first.
	state.day_resolution = DayResolution.begin(state.day, false, state.absolute_day(), int(repo.bal("battle_substeps")))
	var engine := TickEngine.new(repo)
	var first := engine.resolve_day(state)
	assert_eq(first.status, "blocked")
	if first.status != "blocked": return
	DayResolution.acknowledge(state.day_resolution, state.day_resolution.pending_decision.token, "continue")
	var second := engine.resolve_day(state)
	assert_eq(second.status, "blocked")
	if second.status != "blocked": return
	assert_false(state.military_migration.has("living_cap_version"), "The legacy frozen input must precede living-cap migration")
	if state.military_migration.has("living_cap_version"): return
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
