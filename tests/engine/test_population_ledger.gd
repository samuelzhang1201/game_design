extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var province: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	# This fixture exercises a fresh explicit enlistment, not the opening host.
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	repo.balance["recruitment_eligible_permille"] = 1000
	province = MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))[0]

func test_kingdom_people_are_live_province_sums_not_a_second_pool() -> void:
	var provinces := MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))
	for code: String in provinces:
		state.world["economy.provinces.%s.rural_population" % code] = 1000
	var path := "economy.kingdoms.%s.rural_population" % repo.resolve_realm("player_realm")
	state.world[path] = 77  # an obsolete saved override must not shadow the sum
	assert_eq(int(WorldLedger.value_of(repo, state, path)), provinces.size() * 1000)
	WorldLedger.apply(repo, state, "economy.provinces.%s.rural_population" % province, -8, "rural losses", "test")
	assert_eq(int(WorldLedger.value_of(repo, state, path)), provinces.size() * 1000 - 8)
	MapOwnership.set_owner(repo, state, province, repo.resolve_realm("raider_realm"), "province occupied")
	assert_eq(int(WorldLedger.value_of(repo, state, path)), (provinces.size() - 1) * 1000)
	var before := SaveLoad.state_hash(state)
	assert_true(WorldLedger.apply(repo, state, path, -10, "duplicate kingdom loss", "test").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_civil_population_change_cannot_delete_reserved_people() -> void:
	var path := "economy.provinces.%s.rural_population" % province
	state.world[path] = 1000
	Roster.mobilize(repo, state, "raise", [{"id": "c", "unit_code": "unit", "source_province": province,
		"source_population_field": "rural_population", "identity": "commoner", "count": 600, "stage": "active"}], "levy raised")
	var before := SaveLoad.state_hash(state)
	assert_true(WorldLedger.apply(repo, state, path, -401, "civil losses", "test").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_false(WorldLedger.apply(repo, state, path, -400, "civil losses", "test").has("error"))
	assert_eq(int(WorldLedger.value_of(repo, state, path)), 600)
	assert_false(Roster.transition(repo, state, "death", [{"cohort_id": "c", "from": "fit", "to": "dead", "count": 40}], "battle loss").has("error"))
	assert_eq(int(WorldLedger.value_of(repo, state, path)), 560, "death checks the post-transition reservation")
