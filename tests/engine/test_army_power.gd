extends GutTest
## Hidden strength (owner 2026-09-17, spec §5-6): a float round each arm's
## base, power from heads, training, morale and terrain, grades that show only
## words, and a placeholder battle odds.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func _land_codes() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			out.append(String(r["regiment_code"]))
	out.sort()
	return out

func _naval_codes() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			out.append(String(r["regiment_code"]))
	out.sort()
	return out

func test_the_float_is_deterministic_bounded_and_monthly() -> void:
	var spread := int(repo.bal("army_float_permille"))
	var a := ArmySystem.float_factor(repo, "x", "cavalry", 3)
	assert_eq(a, ArmySystem.float_factor(repo, "x", "cavalry", 3))
	var changed := false
	for t in range(4, 12):
		var f := ArmySystem.float_factor(repo, "x", "cavalry", t)
		assert_between(f, 1000 - spread, 1000 + spread)
		changed = changed or f != a
	assert_true(changed, "the value moves month to month")

func test_training_grades_at_their_edges() -> void:
	assert_eq(ArmySystem.training_grade(repo, 10), "Militia")
	assert_eq(ArmySystem.training_grade(repo, 30), "Militia")
	assert_eq(ArmySystem.training_grade(repo, 31), "Recruits")
	assert_eq(ArmySystem.training_grade(repo, 50), "Recruits")
	assert_eq(ArmySystem.training_grade(repo, 51), "Well drilled")
	assert_eq(ArmySystem.training_grade(repo, 80), "Well drilled")
	assert_eq(ArmySystem.training_grade(repo, 81), "Elite")

func test_power_follows_training_morale_and_wounds() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code: String = _land_codes()[0]
	var base := ArmySystem.power(repo, s, code, "defend")
	assert_gt(base, 0)
	s.regiments[code]["training"] = 90
	var drilled := ArmySystem.power(repo, s, code, "defend")
	assert_gt(drilled, base)
	# training factor 500+10*10=600 -> 500+10*90=1400
	assert_almost_eq(float(drilled) / float(base), 1400.0 / 600.0, 0.01)
	s.regiments[code]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	assert_eq(ArmySystem.power(repo, s, code, "defend"), 0, "a regiment of wounded has no power")

## Regression (owner 2026-09-17 review): power's n * fit / heads step used
## to truncate to 0 whenever an arm's fit heads were fewer than the
## regiment's total, so a small fleet (few ships against the regiment's
## whole headcount) always read as 0 power no matter its training.
func test_the_smallest_fleet_has_power_and_training_still_raises_it() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := _naval_codes()
	assert_gt(codes.size(), 0, "the player has a fleet")
	var smallest: String = codes[0]
	var smallest_heads := ArmySystem.headcount(repo, ArmySystem.regiment(repo, smallest))
	for code: String in codes:
		var heads := ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
		if heads < smallest_heads:
			smallest = code
			smallest_heads = heads
	var base := ArmySystem.power(repo, s, smallest, "defend")
	assert_gt(base, 0, "even the smallest fleet has power")
	s.regiments[smallest]["training"] = 90
	var drilled := ArmySystem.power(repo, s, smallest, "defend")
	assert_gt(drilled, base, "raising training raises its power")

func test_strength_grades_against_the_mean_of_its_kind() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := _land_codes()
	assert_gt(codes.size(), 1, "the player has several land regiments")
	var code: String = codes[0]
	s.regiments[code]["training"] = 100
	s.regiments[code]["morale"] = 100
	assert_eq(ArmySystem.strength_grade(repo, s, code), "Strong")
	var weak: String = codes[1]
	s.regiments[weak]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, weak))
	assert_eq(ArmySystem.strength_grade(repo, s, weak), "Weak")

func test_a_lone_kind_is_average() -> void:
	# The pack's player realm has more than one fleet, so this test builds its
	# own repository and strips every fleet but the first, to assert the
	# spec's rule ("a kind with one regiment is Average") for real rather
	# than skipping via pass_test whenever the pack happens to have several.
	var repo2 := DataRepository.load_all("res://data")
	var realm := repo2.resolve_realm("player_realm")
	var fleets: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo2, realm):
		if String(r.get("is_naval", "0")) == "1":
			fleets.append(r)
	assert_gt(fleets.size(), 0, "the pack's player realm has a fleet")
	var table: Dictionary = repo2.world_table("military", "regiments")
	for i in range(1, fleets.size()):
		table.erase(String(fleets[i]["regiment_code"]))
	var lone_code: String = String(fleets[0]["regiment_code"])
	var s := GameState.new_campaign(repo2, 7)
	# Differ the lone fleet's power from its starting value so the assertion
	# is not trivially satisfied by the untouched default state.
	s.regiments[lone_code]["training"] = 100
	assert_eq(ArmySystem.strength_grade(repo2, s, lone_code), "Average")

func test_battle_odds_placeholder() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := _land_codes()
	var odds := ArmySystem.battle_odds(repo, s, codes[0], codes[1])
	assert_between(odds, 0.0, 1.0)
	s.regiments[codes[0]]["training"] = 100
	assert_gt(ArmySystem.battle_odds(repo, s, codes[0], codes[1]), odds, "a better drilled attacker has better odds")
