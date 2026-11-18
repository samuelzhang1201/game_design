extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
## Matchups against the arms actually faced (spec 2026-11-18-axemen-arm-design, step 2). The rows are
## pinned here so the hand sums hold whatever the design data is tuned to later.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	repo.army_matchups = {}
	for row: Array in [["infantry", "infantry", 1000, 1000], ["infantry", "archers", 900, 1000],
			["infantry", "cavalry", 1200, 1300], ["infantry", "artillery", 1100, 900], ["infantry", "axemen", 1000, 800],
			["axemen", "infantry", 1300, 1000], ["axemen", "archers", 1100, 900], ["axemen", "cavalry", 900, 700],
			["axemen", "artillery", 1200, 900], ["axemen", "axemen", 1000, 1000], ["fleet", "fleet", 1000, 1000]]:
		if not repo.army_matchups.has(row[0]):
			repo.army_matchups[row[0]] = []
		repo.army_matchups[row[0]].append({"vs": row[1], "attack": row[2], "defense": row[3]})


## Column means of the pinned rows: axemen attack (1300+1100+900+1200+1000)/5 = 1100, defence
## (1000+900+700+900+1000)/5 = 900; infantry attack (1000+900+1200+1100+1000)/5 = 1040.
func test_axes_against_foot_strike_at_their_attack_value() -> void:
	# vs infantry attacking 1300 -> 1300*1000/1100 = 1181
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [{"infantry": 500}], true), 1181)


func test_axes_hold_against_horse_at_their_defence_value() -> void:
	# vs cavalry defending 700 -> 700*1000/900 = 777
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [{"cavalry": 200}], false), 777)


func test_a_foe_of_every_arm_alike_is_neutral_in_either_stance() -> void:
	# 8 people of each arm (cavalry crew 2, artillery crew 8): the foe value is the column's mean
	var even := {"infantry": 8, "archers": 8, "cavalry": 4, "artillery": 1, "axemen": 8}
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [even], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [even], false), 1000)


func test_a_foe_counts_by_its_fit_share() -> void:
	# infantry 500 people at fit 1000 -> 500,000; cavalry 250 elements = 500 people at fit 100 -> 50,000
	# (500000*1300 + 50000*900) / 550000 = 1263 -> 1263*1000/1100 = 1148
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [{"infantry": 500}, {"cavalry": 250}], true,
		[1000, 100]), 1148)


func test_a_mixed_unit_against_a_mixed_foe() -> void:
	# People = count x crew; a cavalry element is 2 people, so the foe is 600 horse and 100 foot.
	# infantry vs foe: (600*1200 + 100*1000) / 700 = 1171 -> 1171*1000/1040 = 1125
	# axemen vs foe: (600*900 + 100*1300) / 700 = 957 -> 957*1000/1100 = 870
	# unit: (100*1125 + 100*870) / 200 = 997
	assert_eq(BattleMatchup.permille(repo, {"infantry": 100, "axemen": 100},
		[{"cavalry": 200}, {"cavalry": 100, "infantry": 100}], true), 997)


func test_a_pair_without_a_row_is_neutral() -> void:
	assert_eq(BattleMatchup.permille(repo, {"fleet": 2}, [{"infantry": 300}], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"infantry": 300}, [{"fleet": 2}], true), 1000)


func test_nobody_on_either_side_is_neutral() -> void:
	assert_eq(BattleMatchup.permille(repo, {}, [{"infantry": 300}], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"infantry": 300}, [], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"infantry": 0}, [{"infantry": 0}], true), 1000)



func test_both_battle_paths_carry_the_matchup_factor() -> void:
	var data := SuiteData.repo()
	var state := SuiteData.campaign(data, 42)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var enemies := [String(codes[1]), String(codes[2])]
	assert_false(Personnel.move(data, state, enemies[1], "fit", "wounded",
		ArmySystem.fit_count(data, state, enemies[1]) / 2).has("error"))
	var expected := BattleMatchup.permille(data, ArmySystem.regiment(data, code, state),
		enemies.map(func(e: String) -> Dictionary: return ArmySystem.regiment(data, e, state)), true,
		enemies.map(func(e: String) -> int: return ArmySystem.fit_permille(data, state, e)))
	var resolved := BattleSystem.unit_strength(data, state, code, Callable(), true, enemies)
	assert_false(resolved.has("error"), str(resolved))
	assert_eq(_matchup(resolved.get("factors", [])), expected, "resolved battles")
	var rounds := BodyBattleRounds._factors(data, state, {}, code, true, enemies, {})
	assert_eq(_matchup(rounds), expected, "body-battle rounds")


func _matchup(factors: Array) -> int:
	for factor: Dictionary in factors:
		if String(factor.get("source", "")) == "matchup:arms":
			return int(factor["permille"])
	return -1
