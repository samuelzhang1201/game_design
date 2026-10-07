extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Hidden strength (owner 2026-09-17, spec §5-6): a float round each arm's
## base, power from heads, training, morale and terrain, grades that show only
## words, and a placeholder battle odds.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

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
	var s := SuiteData.campaign(repo, 7)
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
	var s := SuiteData.campaign(repo, 7)
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
	var s := SuiteData.campaign(repo, 7)
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
	# The pack's player realm has more than one fleet, so this test strips
	# every fleet but the first from its campaign's roster, to assert the
	# spec's rule ("a kind with one regiment is Average") for real rather
	# than skipping via pass_test whenever the pack happens to have several.
	var s := SuiteData.campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var fleets: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, realm, s):
		if String(r.get("is_naval", "0")) == "1":
			fleets.append(r)
	assert_gt(fleets.size(), 0, "the player's realm has a fleet")
	for i in range(1, fleets.size()):
		s.army_roster.erase(String(fleets[i]["regiment_code"]))
		s.regiments.erase(String(fleets[i]["regiment_code"]))
	var lone_code: String = String(fleets[0]["regiment_code"])
	# Differ the lone fleet's power from its starting value so the assertion
	# is not trivially satisfied by the untouched default state.
	s.regiments[lone_code]["training"] = 100
	assert_eq(ArmySystem.strength_grade(repo, s, lone_code), "Average")

func test_battle_odds_placeholder() -> void:
	var s := SuiteData.campaign(repo, 7)
	var codes := _land_codes()
	var odds := ArmySystem.battle_odds(repo, s, codes[0], codes[1])
	assert_between(odds, 0.0, 1.0)
	s.regiments[codes[0]]["training"] = 100
	assert_gt(ArmySystem.battle_odds(repo, s, codes[0], codes[1]), odds, "a better drilled attacker has better odds")

## Power is read where the regiment stands NOW (owner 2026-10-06: 军事单位的
## 地理位置数据跟随单位移动变动): a column marched behind walls fights with
## them, exactly as a regiment the pack quartered there would.
func test_power_reads_the_ground_the_regiment_stands_on_now() -> void:
	var realm := repo.resolve_realm("player_realm")
	var code: String = _land_codes()[0]
	var reg := ArmySystem.regiment(repo, code)
	var home_works := ArmySystem.works_of(repo, reg)
	# a town of the realm with other works than the regiment's quarters
	var target := ""
	var burgs := repo.burgs.keys()
	burgs.sort()
	for b: String in burgs:
		var row: Dictionary = repo.burgs[b]
		if String(row["kingdom_code"]) != realm:
			continue
		var feats := String(row.get("features", "")).split("|")
		var works := "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "town")
		if works != home_works and works != "town":
			target = b
			break
	assert_ne(target, "", "the realm has a walled town")
	var at := Vector2(float(repo.burgs[target]["x"]), float(repo.burgs[target]["y"]))
	var s := SuiteData.campaign(repo, 7)
	var home := ArmySystem.power(repo, s, code, "defend")
	var m := ArmySystem.pack_to_metres(repo, at)
	var entry: Dictionary = s.regiments[code]
	entry["x_m"] = m.x
	entry["y_m"] = m.y
	entry["dest_x_m"] = m.x
	entry["dest_y_m"] = m.y
	assert_eq(ArmySystem.held_town_of(repo, reg, s), target)
	_seat(s, code, target)   # the works are the seat's (spec 2026-10-07-army-split-and-ground §4.1)
	var moved := ArmySystem.power(repo, s, code, "defend")
	# The same unit quartered there by the roster, with the same state.
	var s2 := SuiteData.campaign(repo, 7)
	var row2: Dictionary = s2.army_roster[code]
	row2["x"] = str(at.x)
	row2["y"] = str(at.y)
	(s2.regiments[code] as Dictionary).erase("x_m")
	_seat(s2, code, target)
	assert_eq(moved, ArmySystem.power(repo, s2, code, "defend"))
	assert_ne(moved, home, "other works change its power")

## `code` holds `town`'s seat in `s`, and no other.
func _seat(s: GameState, code: String, town: String) -> void:
	for t: String in s.town_seat.keys():
		if String(s.town_seat[t]) == code:
			s.town_seat.erase(t)
	s.town_seat[town] = code

func test_power_is_power_on_its_own_ground() -> void:
	var s := SuiteData.campaign(repo, 7)
	for code: String in _land_codes():
		var reg := ArmySystem.regiment(repo, code)
		for stance in ["defend", "attack"]:
			assert_eq(ArmySystem.power(repo, s, code, stance),
				ArmySystem.power_on(repo, s, code, stance, ArmySystem.terrain_of(repo, reg, s), ArmySystem.works_of(repo, reg, s)),
				"%s %s" % [code, stance])

func test_archers_alone_on_hills_by_the_terrain_table() -> void:
	var r := SuiteData.repo()
	var s := SuiteData.campaign(r, 7)
	var code: String = _land_codes()[0]
	var row: Dictionary = s.army_roster[code]
	for arm in ["infantry", "cavalry", "artillery", "fleet"]:
		row[arm] = "0"
	row["archers"] = "800"
	var plains_d := ArmySystem.power_on(r, s, code, "defend", "plains", "")
	var plains_a := ArmySystem.power_on(r, s, code, "attack", "plains", "")
	# army_terrain.csv: hills,archers,1150,1050
	assert_almost_eq(float(ArmySystem.power_on(r, s, code, "defend", "hills", "")) / plains_d, 1.15, 0.01)
	assert_almost_eq(float(ArmySystem.power_on(r, s, code, "attack", "hills", "")) / plains_a, 1.05, 0.01)
	# army_town_defence.csv: walls,archers defend 1250, attack untouched
	assert_almost_eq(float(ArmySystem.power_on(r, s, code, "defend", "plains", "walls")) / plains_d, 1.25, 0.01)
	assert_eq(ArmySystem.power_on(r, s, code, "attack", "plains", "walls"), plains_a)


## power_of_arms (spec 2026-10-07-war-room-annotations-and-planning-pieces
## §1.2): a host of given arms with no state — no wounds, the float at 1000.
## By hand from the CSVs: archers' base is the mean of (1200+800)/2,
## (1000+1000)/2, (800+700)/2, (1000+900)/2 = 925; training 10 -> 600,
## morale 75 -> 875; hills archers defend 1150; a citadel archers 1350.
func test_power_of_arms_is_worked_by_hand() -> void:
	var arms := {"archers": 2000}
	# 2000 * 1000 milli-heads * 925 * 600 * 875 / 1000^3 = 971,250
	assert_eq(ArmySystem.power_of_arms(repo, arms, 2000, 10, 75, "defend", "plains", ""), 972)
	# 971,250 * 1150 / 1000 = 1,116,937 -> ceil to 1117
	assert_eq(ArmySystem.power_of_arms(repo, arms, 2000, 10, 75, "defend", "hills", ""), 1117)
	# and behind a citadel's works: 1,116,937 * 1350 / 1000 = 1,507,864 -> 1508
	assert_eq(ArmySystem.power_of_arms(repo, arms, 2000, 10, 75, "defend", "hills", "citadel"), 1508)
	# works never help the attacker: hills archers attack 1050
	assert_eq(ArmySystem.power_of_arms(repo, arms, 2000, 10, 75, "attack", "hills", "citadel"), 1020)


func test_power_on_is_power_of_arms_with_the_regiments_own_state() -> void:
	var s := SuiteData.campaign(repo, 7)
	for code: String in _land_codes():
		var reg := ArmySystem.regiment(repo, code)
		var st: Dictionary = s.regiments[code]
		var fit := ArmySystem.headcount(repo, reg) - int(st["wounded"])
		assert_eq(ArmySystem.power_on(repo, s, code, "attack", "hills", "walls"),
			ArmySystem.power_of_arms(repo, reg, fit, int(st["training"]), int(st["morale"]), "attack", "hills", "walls", code, s.tick))
