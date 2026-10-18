extends GutTest
const Strength := preload("res://scripts/engine/battle_strength.gd")
const SuiteData := preload("res://tests/suite_data.gd")

func _factor(category: String, source: String, permille: int) -> Dictionary:
	return {"category": category, "source": source, "permille": permille,
		"reason": "Strength fixture: " + source, "min_permille": 0, "max_permille": 3000}

func test_fixed_category_order_truncates_each_stage_and_keeps_reasons() -> void:
	var factors: Array[Dictionary] = [_factor("discipline", "discipline", 1000),
		_factor("morale", "morale", 900), _factor("training", "training", 800)]
	var result := Strength.combine(630, factors)
	assert_eq(result.get("power"), 453, "630 * 800 / 1000 = 504; 504 * 900 / 1000 = 453")
	var returned: Array = result.get("factors", [])
	assert_eq(returned.size(), factors.size(), "retain every explanatory source")
	for factor: Dictionary in returned:
		assert_true(factors.has(factor))
	var steps: Array = result.get("steps", [])
	assert_eq(steps.size(), 3)
	if steps.size() == 3:
		assert_eq(steps[0]["power"], 504)
		assert_eq(steps[1]["power"], 453)
		assert_eq(steps[2]["power"], 453)

func test_same_category_adds_deviations_and_applies_only_once() -> void:
	var factors: Array[Dictionary] = [_factor("formation_terrain", "terrain", 1100),
		_factor("formation_terrain", "formation", 1200)]
	var result := Strength.combine(630, factors)
	assert_eq(result.get("power"), 819, "630 * (1000 + 100 + 200) / 1000")
	assert_eq((result.get("steps", []) as Array).size(), 1)
	factors.reverse()
	assert_eq(Strength.combine(630, factors).get("power"), 819)

func test_category_clamps_once_after_merging() -> void:
	var factors: Array[Dictionary] = [_factor("action", "positive", 5000), _factor("action", "negative", -1000)]
	assert_eq(Strength.combine(630, factors).get("power"), 1890)
	factors = [_factor("action", "large", 9000)]
	assert_eq(Strength.combine(630, factors).get("power"), 1890)
	factors = [_factor("supply", "empty", -100)]
	assert_eq(Strength.combine(630, factors).get("power"), 0)

func test_duplicate_sources_and_invalid_factors_return_errors() -> void:
	var factors: Array[Dictionary] = [_factor("training", "same", 800), _factor("morale", "same", 900)]
	assert_true(Strength.combine(630, factors).has("error"))
	factors = [_factor("unknown", "bad_category", 1000)]
	assert_true(Strength.combine(630, factors).has("error"))
	factors = [_factor("training", "reason", 1000)]
	factors[0]["reason"] = ""
	assert_true(Strength.combine(630, factors).has("error"))
	factors = [_factor("training", "one", 1000), _factor("training", "two", 1000)]
	factors[1]["max_permille"] = 2000
	assert_true(Strength.combine(630, factors).has("error"))
	assert_true(Strength.combine(-1, []).has("error"))

func test_no_factors_preserves_base_and_input_is_not_mutated() -> void:
	assert_eq(Strength.combine(630, []).get("power"), 630)
	var factors: Array[Dictionary] = [_factor("action", "hold", 1000)]
	var original := factors.duplicate(true)
	Strength.combine(630, factors)
	assert_eq(factors, original)

func test_unit_applies_identity_training_morale_discipline_supply_and_action_once() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := SuiteData.campaign(repo, 7)
	repo.balance["battle_strength_factor_min_permille"] = 0
	repo.balance["battle_strength_factor_max_permille"] = 3000
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	var codes := state.regiments.keys()
	codes.sort()
	var code := ""
	for candidate: String in codes:
		if String(ArmySystem.regiment(repo, candidate, state).get("is_naval", "0")) != "1":
			code = candidate
			break
	var row: Dictionary = state.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		row[arm] = "0"
	row["infantry"] = "600"
	repo.world_table("military", "unit_types")["infantry"]["crew"] = "1"
	repo.army_matchups.clear()
	repo.army_terrain.clear()
	repo.army_town_defence.clear()
	var province := String(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))[0])
	state.world["economy.provinces.%s.rural_population" % province] = 10000
	repo.balance["recruitment_eligible_permille"] = 1000
	for pair: Array in [["commoner", 570], ["noble", 30]]:
		var identity := String(pair[0])
		var raised := MilitaryRoster.mobilize(repo, state, "strength:" + identity, [{"id": identity,
			"unit_code": code, "source_province": province, "source_population_field": "rural_population",
			"identity": identity, "family_name": "", "stage": "active", "count": int(pair[1])}], "Strength test enlistment")
		assert_false(raised.has("error"), str(raised))
	state.regiments[code]["training"] = 30
	state.regiments[code]["morale"] = 80
	state.regiments[code]["supplies"] = 100000
	state.king_state["mode"] = "court"
	var extra: Array[Dictionary] = [{"category": "action", "source": "action:attack", "permille": 800,
		"reason": "Attack exposes the line"}]
	var result := Strength.unit(repo, state, code, true, extra)
	assert_false(result.has("error"), str(result))
	assert_eq(result.get("base"), 630, "570 commoners + 30 nobles at double equipment power")
	assert_eq(result.get("power"), 380, "630 -> 504 training -> 453 morale -> 475 discipline -> 380 action")
	state.regiments[code]["supplies"] = 0
	assert_eq(Strength.unit(repo, state, code, true).get("power"), 0)
	state.regiments[code]["supplies"] = 100000
	row["infantry"] = "0"
	row["fleet"] = "20"
	repo.world_table("military", "unit_types")["fleet"]["crew"] = "30"
	var fleet := Strength.unit(repo, state, code, true)
	assert_eq(fleet.get("base"), 21, "20 equipment * 1050 identity / 1000, never 600 crew power")
	assert_eq(fleet.get("power"), 14, "21 -> 16 training -> 14 morale -> 14 discipline")
	var duplicate: Array[Dictionary] = [{"category": "training", "source": "unit:training", "permille": 1000,
		"reason": "A duplicate must be refused"}]
	assert_true(Strength.unit(repo, state, code, true, duplicate).has("error"))
	assert_false(extra[0].has("min_permille"), "unit never mutates caller factors")
