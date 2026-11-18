extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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


func test_axes_against_foot_strike_at_their_attack_value() -> void:
	# axemen mean = (1150 + 1000 + 800 + 1050 + 1000) / 5 = 1000; vs infantry attacking 1300 -> 1300
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [{"infantry": 500}], true), 1300)


func test_axes_hold_against_horse_at_their_defence_value() -> void:
	assert_eq(BattleMatchup.permille(repo, {"axemen": 300}, [{"cavalry": 200}], false), 700)


func test_a_mixed_unit_against_a_mixed_foe() -> void:
	# People = count x crew; a cavalry element is 2 people, so the foe is 600 horse and 100 foot.
	# infantry mean (1000 + 950 + 1250 + 1000 + 900) / 5 = 1020
	# infantry vs foe: (600*1200 + 100*1000) / 700 = 1171 -> 1171*1000/1020 = 1148
	# axemen vs foe: (600*900 + 100*1300) / 700 = 957 -> 957*1000/1000 = 957
	# unit: (100*1148 + 100*957) / 200 = 1052
	assert_eq(BattleMatchup.permille(repo, {"infantry": 100, "axemen": 100},
		[{"cavalry": 200}, {"cavalry": 100, "infantry": 100}], true), 1052)


func test_a_pair_without_a_row_is_neutral() -> void:
	assert_eq(BattleMatchup.permille(repo, {"fleet": 2}, [{"infantry": 300}], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"infantry": 300}, [{"fleet": 2}], true), 1000)


func test_nobody_on_either_side_is_neutral() -> void:
	assert_eq(BattleMatchup.permille(repo, {}, [{"infantry": 300}], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"infantry": 300}, [], true), 1000)
	assert_eq(BattleMatchup.permille(repo, {"infantry": 0}, [{"infantry": 0}], true), 1000)

