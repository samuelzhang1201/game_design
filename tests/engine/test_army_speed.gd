extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A regiment's march in km a day (owner 2026-09-19: "每个兵种都要有自己的速度，
## 多少km每天，速度需要有一套计算公式，取决于兵种，物资，士气，训练四方面按一定权重").
## Whole numbers throughout: the pace is kept in TENTHS of a km.
##
##   base   = the slowest arm under the banner, data/army_speed.csv (km/day)
##   S      = supplies in hand over army_speed_supply_full_months of use,
##            per mille, capped at 1000
##   M      = morale x 10, T = training x 10 (both 0..100 -> 0..1000)
##   ready  = (Wa*1000 + Ws*S + Wm*M + Wt*T) / (Wa + Ws + Wm + Wt)
##   pace   = base * 10 * ready / 1000   tenths of a km a day

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	# Fix the table and weights so the hand sums below hold whatever the
	# design data is tuned to later.
	repo.army_speed = {"infantry": 20, "archers": 22, "cavalry": 40, "artillery": 12, "fleet": 100}
	repo.balance["army_speed_w_arm"] = 40.0
	repo.balance["army_speed_w_supply"] = 25.0
	repo.balance["army_speed_w_morale"] = 20.0
	repo.balance["army_speed_w_training"] = 15.0
	repo.balance["army_speed_supply_full_months"] = 3.0


func test_every_arm_has_a_pace() -> void:
	var fresh := SuiteData.repo()
	for arm: String in fresh.world_table("military", "unit_types"):
		assert_gt(int(fresh.army_speed.get(arm, 0)), 0, arm + " has a km/day in army_speed.csv")


func test_readiness_is_the_weighted_mean_of_the_four_scores() -> void:
	# (40*1000 + 25*1000 + 20*700 + 15*100) / 100 = (40000+25000+14000+1500)/100 = 805
	assert_eq(ArmySystem.readiness_permille(repo, 1000, 70, 10), 805)
	# All at their best: 1000. All at their worst: only the arm's own weight, 400.
	assert_eq(ArmySystem.readiness_permille(repo, 1000, 100, 100), 1000)
	assert_eq(ArmySystem.readiness_permille(repo, 0, 0, 0), 400)


func test_supplies_score_by_months_in_hand() -> void:
	# 1.5 months of 3 -> 500; 6 of 3 -> capped 1000; none -> 0.
	assert_eq(ArmySystem.supply_score(repo, 150, 100), 500)
	assert_eq(ArmySystem.supply_score(repo, 600, 100), 1000)
	assert_eq(ArmySystem.supply_score(repo, 0, 100), 0)
	assert_eq(ArmySystem.supply_score(repo, 10, 0), 1000, "a banner that eats nothing never runs short")


func test_a_regiment_marches_at_its_slowest_arm() -> void:
	var reg := {"infantry": 100, "cavalry": 50, "artillery": 0, "archers": 0, "fleet": 0}
	assert_eq(ArmySystem.base_pace_km(repo, reg), 20, "horse waits for the foot")
	reg["artillery"] = 2
	assert_eq(ArmySystem.base_pace_km(repo, reg), 12, "and everyone waits for the guns")
	assert_eq(ArmySystem.base_pace_km(repo, {"cavalry": 10}), 40)


func test_the_pace_in_tenths_of_a_km() -> void:
	# infantry 20 km * 10 * 805 / 1000 = 161 tenths = 16.1 km a day
	assert_eq(ArmySystem.pace_tenths(repo, 20, 1000, 70, 10), 161)
	# cavalry 40 at the worst: 40 * 10 * 400 / 1000 = 160
	assert_eq(ArmySystem.pace_tenths(repo, 40, 0, 0, 0), 160)


func test_a_real_regiment_of_the_player_has_a_speed() -> void:
	Game.start_campaign(42)
	var mine := Game.data.resolve_realm("player_realm")
	var reg: Dictionary = MapObjects.regiments_of(Game.data, mine)[0]
	var code := String(reg["regiment_code"])
	var km := ArmySystem.speed_km_per_day(Game.data, Game.state, code)
	assert_gt(km, 0.0)
	var st := ArmySystem.state_of(Game.data, Game.state, code)
	var expect := ArmySystem.pace_tenths(Game.data, ArmySystem.base_pace_km(Game.data, reg),
		ArmySystem.supply_score(Game.data, int(st["supplies"]), ArmySystem.supply_use(Game.data, reg)),
		int(st["morale"]), int(st["training"]))
	# on the ground it stands on (spec 2026-10-06 §6)
	var ground := ArmySystem.ground_permille(Game.data, reg, ArmySystem.position_of(Game.data, Game.state, reg))
	assert_almost_eq(km, expect / 10.0 * float(ground) / 1000.0, 0.0001)


func test_hunger_and_low_morale_slow_the_march() -> void:
	Game.start_campaign(42)
	var mine := Game.data.resolve_realm("player_realm")
	var code := String(MapObjects.regiments_of(Game.data, mine)[0]["regiment_code"])
	ArmySystem.ensure(Game.data, Game.state)
	var before := ArmySystem.speed_km_per_day(Game.data, Game.state, code)
	Game.state.regiments[code]["supplies"] = 0
	Game.state.regiments[code]["morale"] = 10
	assert_lt(ArmySystem.speed_km_per_day(Game.data, Game.state, code), before)


## Owner 2026-09-19: clicking a counter shows the regiment — its state and
## its march, not only its heads.
func test_the_regiments_detail_card_carries_its_march() -> void:
	Game.start_campaign(42)
	var mine := Game.data.resolve_realm("player_realm")
	var code := String(MapObjects.regiments_of(Game.data, mine)[0]["regiment_code"])
	var card := MapObjects.army_card(Game.data, code, Game.state)
	var march: Dictionary = {}
	for s: Dictionary in card["stats"]:
		if String(s["key"]) == "army_march":
			march = s
	assert_false(march.is_empty(), "the card's icons include the march")
	assert_eq(String(march["text"]), "%.1f km/day" % ArmySystem.speed_km_per_day(Game.data, Game.state, code))
	assert_true(Game.data.resource_icons.has("army_march"), "with its icon row")


## The map's two bars (owner 2026-09-27): red the readiness, yellow the supply.
func test_the_bars_are_readiness_and_supply() -> void:
	var st := GameState.new()
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var code := String(reg["regiment_code"])
	var use := ArmySystem.supply_use(repo, reg)
	st.regiments[code] = {"morale": 50, "training": 20, "supplies": use, "wounded": 0}
	# readiness scores one month of three: 333; (40*1000 + 25*333 + 20*500 + 15*200) / 100 = 613.
	# The yellow bar is the stores against a full train (owner 2026-09-30: it falls
	# every day): one month of army_supply_target_months 4 = 250.
	assert_eq(ArmySystem.bars_of(repo, st, code), Vector2i(613, 250))


func test_a_foreign_regiment_reads_as_it_would_start() -> void:
	repo.balance["army_start_morale"] = 70.0
	repo.balance["army_start_training"] = 10.0
	repo.balance["army_start_supply_months"] = 6.0
	var mine := repo.resolve_realm("player_realm")
	for reg: Dictionary in repo.world_table("military", "regiments").values():
		if String(reg["kingdom_code"]) != mine:
			# six months of three: 1000; readiness 805 (above)
			assert_eq(ArmySystem.bars_of(repo, GameState.new(), String(reg["regiment_code"])),
				Vector2i(805, 1000))
			return
	fail_test("the pack has no foreign regiment")
