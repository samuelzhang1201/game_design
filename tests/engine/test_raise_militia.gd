extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Raising a militia regiment through the same order the recruitment panel sends
## (ARMY_RECRUIT), with the shipped recruitment row (build_days 3, equipment 1 gold an element), and
## loading a save from before the arm (spec 2026-11-26-militia-arm-design).
var repo: DataRepository
var state: GameState
var request: Dictionary

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	SuiteData.open_country(repo)
	var realm := repo.resolve_realm("player_realm")
	var town := ""
	var towns := repo.burgs.keys()
	towns.sort()
	for code: String in towns:
		if String(repo.burgs[code]["kingdom_code"]) == realm:
			town = code
			break
	var province := String(repo.burgs[town]["province_code"])
	state.recruitment_projects.clear()
	state.ai_hosts.clear()
	state.metrics["treasury"] = 5000
	repo.balance["recruitment_eligible_permille"] = 1000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 1000
	var officers := RecruitmentSystem.available_commanders(repo, state, "militia")
	assert_gt(officers.size(), 0, "a commander may lead militia")
	request = {"request_id": "raise-militia", "mode": "new", "arm": "militia", "total": 300,
		"source_province": province, "source_population_field": "rural_population", "assembly_town": town,
		"noble_permille": 0, "commander_id": officers[0] if not officers.is_empty() else ""}

func test_raise_a_militia_regiment() -> void:
	# The opening's own cohorts draw on the same origins: start from an empty muster, as test_recruitment.
	for table: Dictionary in [state.army_roster, state.regiments, state.foes, state.town_seat, state.military_rosters,
			state.military_cohorts, state.military_events, state.military_migration]:
		table.clear()
	state.battles.clear()
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("ARMY_RECRUIT", request)
	assert_eq(actions.validate(req, state), "")
	var quote: Dictionary = RecruitmentSystem.quote(repo, state, request)
	assert_false(quote.has("error"), str(quote))
	assert_eq(int(quote.get("build_days", 0)), 3, "townsmen muster in three days")
	var result := actions.execute(req, state)
	assert_true(result.get("ok", false), str(result))
	var code := String((state.recruitment_projects["raise-militia"] as Dictionary)["unit_code"])
	var engine := TickEngine.new(repo)
	for day: int in 2:
		assert_eq(engine.resolve_day(state).get("status"), "complete")
		assert_eq(MilitaryRoster.fit(state, code), 0, "still assembling after day %d" % (day + 1))
	assert_eq(engine.resolve_day(state).get("status"), "complete")
	assert_eq(MilitaryRoster.fit(state, code), 300)
	var reg := ArmySystem.regiment(repo, code, state)
	assert_eq(MapObjects.regiment_arm(repo, reg), "militia")
	assert_gt(int(float(reg.get("militia", 0))), 0)

func test_old_save_without_the_militia_arm_loads() -> void:
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	_strip(data)
	var loaded := GameState.from_dict(data, false)
	assert_gt(loaded.army_roster.size(), 0)
	# The steps Game.load_campaign runs after parsing a save.
	var personnel := MilitaryBootstrap.migrate(repo, loaded)
	assert_false(personnel.has("error"), str(personnel))
	var organization := MilitaryReorganization.reconcile(repo, loaded)
	assert_ne(organization.get("status", "error"), "error", str(organization))
	for code: String in loaded.army_roster:
		var reg := ArmySystem.regiment(repo, code, loaded)
		assert_eq(int(float(reg.get("militia", 0))), 0, code)
		assert_ne(MapObjects.regiment_arm(repo, reg), "militia", code)

func _strip(value: Variant) -> void:
	if value is Dictionary:
		(value as Dictionary).erase("militia")
		for key: Variant in value:
			_strip(value[key])
	elif value is Array:
		for item: Variant in value:
			_strip(item)
