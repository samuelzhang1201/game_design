extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func test_population_ledger_exists() -> void:
	var path := "res://scripts/engine/military_population.gd"
	var subject: GDScript = load(path) if ResourceLoader.exists(path) else null
	assert_not_null(subject, "population availability has one personnel source")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.rng = Rng.new(7)
	var provinces := repo.world_table("economy", "provinces").keys()
	provinces.sort()
	var province: String = provinces[0]
	state.world["economy.provinces.%s.rural_population" % province] = 1000
	state.world["economy.provinces.%s.urban_population" % province] = 500
	return {"repo": repo, "state": state, "province": province}

func _cohort(id: String, province: String, field: String, amount: int) -> Dictionary:
	return {"id": id, "unit_code": "unit", "source_province": province,
		"source_population_field": field, "identity": "commoner", "family_name": "",
		"stage": "active", "initial": amount, "fit": amount, "wounded": 0,
		"captured_current": 0, "dead": 0, "released": 0}

func test_mobilization_death_capture_release_conserve_source_people() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var population: GDScript = load("res://scripts/engine/military_population.gd")
	var f := _fixture()
	var repo: DataRepository = f.repo
	var s: GameState = f.state
	var p: String = f.province
	var rural := "rural_population"
	var recruits := [_cohort("rural", p, rural, 600)]
	assert_false(roster.mobilize(repo, s, "raise", recruits, "called to service").has("error"))
	assert_eq(population.available(repo, s, p, rural), 400)
	assert_eq(population.occupied(s, p, rural), 600)
	var deaths := [{"cohort_id": "rural", "from": "fit", "to": "dead", "count": 40}]
	assert_false(roster.transition(repo, s, "deaths", deaths, "battle losses").has("error"))
	assert_eq(WorldLedger.value_of(repo, s, "economy.provinces.%s.%s" % [p, rural]), 960)
	assert_eq(population.occupied(s, p, rural), 560)
	assert_eq(population.available(repo, s, p, rural), 400)
	var captures := [{"cohort_id": "rural", "from": "fit", "to": "captured_current", "count": 60}]
	assert_false(roster.transition(repo, s, "capture", captures, "taken prisoner").has("error"))
	assert_eq(population.occupied(s, p, rural), 560)
	var release := [{"cohort_id": "rural", "from": "captured_current", "to": "released", "count": 60}]
	assert_false(roster.transition(repo, s, "release", release, "returned to civilian life").has("error"))
	assert_eq(population.occupied(s, p, rural), 500)
	assert_eq(population.available(repo, s, p, rural), 460)
	assert_true(roster.transition(repo, s, "deaths", deaths, "battle losses").duplicate)
	assert_true(roster.transition(repo, s, "release", release, "returned to civilian life").duplicate)
	assert_eq(WorldLedger.value_of(repo, s, "economy.provinces.%s.%s" % [p, rural]), 960)
	assert_eq(population.available(repo, s, p, rural), 460)
	assert_eq(roster.living(s, "unit"), 500)
	assert_eq(roster.fit(s, "unit"), 500)

func test_proportional_losses_only_reduce_their_sources_once() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var f := _fixture()
	var repo: DataRepository = f.repo
	var s: GameState = f.state
	var p: String = f.province
	assert_false(roster.mobilize(repo, s, "raise", [
		_cohort("rural", p, "rural_population", 80),
		_cohort("urban", p, "urban_population", 20)], "called to service").has("error"))
	var changes: Array = roster.plan_changes(s, "unit", "fit", "dead", 10)
	assert_false(roster.transition(repo, s, "loss", changes, "battle losses").has("error"))
	assert_eq(WorldLedger.value_of(repo, s, "economy.provinces.%s.rural_population" % p), 992)
	assert_eq(WorldLedger.value_of(repo, s, "economy.provinces.%s.urban_population" % p), 498)
	assert_eq(s.world_log.size(), 2)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(restored.military_cohorts, s.military_cohorts)
	assert_eq(roster.fit(restored, "unit"), 90)
	assert_true(roster.transition(repo, restored, "loss", changes, "battle losses").duplicate)

func test_mobilization_rejects_overbooked_sources_and_conflicts_atomically() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var f := _fixture()
	var s: GameState = f.state
	var p: String = f.province
	var a := _cohort("a", p, "rural_population", 600)
	var b := _cohort("b", p, "rural_population", 401)
	assert_true(roster.mobilize(f.repo, s, "raise", [a, b], "called to service").has("error"))
	assert_true(s.military_cohorts.is_empty())
	assert_true(s.military_events.is_empty())
	s.military_conflicts.append(p)
	assert_true(roster.mobilize(f.repo, s, "raise", [a], "called to service").has("error"))
	assert_true(s.military_cohorts.is_empty())

func test_transition_batch_is_atomic_and_terminal_states_cannot_reenter() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var f := _fixture()
	var s: GameState = f.state
	var p: String = f.province
	assert_false(roster.mobilize(f.repo, s, "raise", [_cohort("a", p, "rural_population", 100)], "called to service").has("error"))
	var before := s.to_dict()
	assert_true(roster.transition(f.repo, s, "bad", [
		{"cohort_id": "a", "from": "fit", "to": "dead", "count": 60},
		{"cohort_id": "a", "from": "fit", "to": "wounded", "count": 60}], "battle losses").has("error"))
	assert_eq(s.to_dict(), before)
	var moves := [{"from": "fit", "to": "dead", "count": 40}, {"from": "fit", "to": "wounded", "count": 60}]
	var planned: Array = roster.plan_unit_changes(s, "unit", moves)
	assert_false(roster.transition(f.repo, s, "good", planned, "battle losses").has("error"))
	assert_eq(roster.fit(s, "unit"), 0)
	assert_eq(roster.living(s, "unit"), 60)
	assert_true(roster.transition(f.repo, s, "revive", [{"cohort_id": "a", "from": "dead", "to": "fit", "count": 1}], "invalid return").has("error"))
	assert_true(roster.transition(f.repo, s, "good", [], "different reason").has("error"))

func test_historical_service_preserves_overcapacity_and_blocks_new_mobilization() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var population: GDScript = load("res://scripts/engine/military_population.gd")
	var f := _fixture()
	var s: GameState = f.state
	var p: String = f.province
	var recruits := [_cohort("old", p, "rural_population", 1100)]
	assert_false(roster.initialize_historical(f.repo, s, "old-army", recruits, "existing service migrated").has("error"))
	assert_eq(roster.fit(s, "unit"), 1100)
	assert_true(s.military_conflicts.has(p))
	assert_eq(population.available(f.repo, s, p, "rural_population"), 0)
	assert_eq(WorldLedger.value_of(f.repo, s, "economy.provinces.%s.rural_population" % p), 1000)
	assert_true(roster.initialize_historical(f.repo, s, "old-army", recruits, "existing service migrated").duplicate)
	assert_eq(s.military_cohorts.size(), 1)

func test_named_people_cannot_serve_twice_and_wounds_remove_command() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var f := _fixture()
	var s: GameState = f.state
	var p: String = f.province
	var person := Character.new()
	person.id = "officer"
	person.family_name = "Family"
	s.characters[person.id] = person
	var noble := _cohort("noble", p, "rural_population", 2)
	noble.identity = "noble"
	assert_false(roster.mobilize(f.repo, s, "raise", [noble], "called to service").has("error"))
	var named: String = roster.bind_person(s, "unit", person.id, "noble", "appointed to command")
	assert_ne(named, "")
	assert_eq(roster.fit(s, "unit"), 2)
	assert_eq(s.military_cohorts[named].initial, 1)
	assert_eq(roster.bind_person(s, "unit", person.id, "noble", "duplicate service"), "")
	var duplicate := _cohort("duplicate", p, "rural_population", 1)
	duplicate.identity = "noble"
	duplicate.person_id = person.id
	assert_true(roster.mobilize(f.repo, s, "duplicate", [duplicate], "duplicate service").has("error"))
	s.military_rosters.unit.commander_id = person.id
	assert_false(roster.transition(f.repo, s, "wound", [{"cohort_id": named, "from": "fit", "to": "wounded", "count": 1}], "commander wounded").has("error"))
	assert_eq(s.military_rosters.unit.commander_id, "")
	assert_eq(s.military_rosters.unit.appointments[-1].reason, "commander wounded")
	assert_false(roster.transition(f.repo, s, "recover", [{"cohort_id": named, "from": "wounded", "to": "fit", "count": 1}], "commander recovered").has("error"))
	assert_eq(s.military_rosters.unit.commander_id, "")

func test_missing_source_death_rolls_back_entire_batch() -> void:
	var roster: GDScript = load("res://scripts/engine/military_roster.gd")
	var f := _fixture()
	var s: GameState = f.state
	var p: String = f.province
	assert_false(roster.mobilize(f.repo, s, "raise", [
		_cohort("rural", p, "rural_population", 80),
		_cohort("urban", p, "urban_population", 20)], "called to service").has("error"))
	s.world["economy.provinces.%s.urban_population" % p] = 0
	var before := s.to_dict()
	var changes: Array = roster.plan_changes(s, "unit", "fit", "dead", 10)
	assert_true(roster.transition(f.repo, s, "loss", changes, "battle losses").has("error"))
	assert_eq(s.to_dict(), before)
