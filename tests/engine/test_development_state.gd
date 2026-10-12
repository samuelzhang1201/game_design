extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The development axes' core: scores, tiers with hysteresis, flags, save
## (spec 2026-10-12-development-axes-design §2).

var repo: DataRepository
var s: GameState
var player: String

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	player = repo.resolve_realm("player_realm")

func _foreign() -> String:
	for r: String in DevelopmentSystem.realms(repo, s):
		if r != player:
			return r
	return ""

func _flags() -> Array:
	return s.event_state.get("flags", [])

func test_seed_gives_every_realm_start_scores_and_tier_zero() -> void:
	var realms := DevelopmentSystem.realms(repo, s)
	assert_eq(realms.size(), 4)
	for r: String in realms:
		for axis: String in DevelopmentSystem.AXES:
			assert_eq(DevelopmentSystem.score(s, r, axis), int(repo.bal("dev_start_" + axis)))
			assert_eq(DevelopmentSystem.tier(s, r, axis), 0)

func test_tier_for_hysteresis() -> void:
	assert_eq(DevelopmentSystem.tier_for(repo, "renaissance", 240, 1), 1)
	assert_eq(DevelopmentSystem.tier_for(repo, "renaissance", 229, 1), 0)
	assert_eq(DevelopmentSystem.tier_for(repo, "renaissance", 249, 0), 0)
	assert_eq(DevelopmentSystem.tier_for(repo, "renaissance", 250, 0), 1)
	assert_eq(DevelopmentSystem.tier_for(repo, "renaissance", 760, 1), 3)

func test_move_clamps_and_returns_applied_delta() -> void:
	s.development[player]["renaissance"] = 995
	var r := DevelopmentSystem.move(repo, s, player, "renaissance", 10, "test")
	assert_eq(DevelopmentSystem.score(s, player, "renaissance"), 1000)
	assert_eq(int(r["delta"]), 5)
	s.development[player]["renaissance"] = 3
	r = DevelopmentSystem.move(repo, s, player, "renaissance", -10, "test")
	assert_eq(DevelopmentSystem.score(s, player, "renaissance"), 0)
	assert_eq(int(r["delta"]), -3)
	s.development[player]["renaissance"] = 1000
	assert_eq(DevelopmentSystem.move(repo, s, player, "renaissance", 5, "test"), {})

func test_move_sets_crossing_flag_once_per_crossing() -> void:
	s.development[player]["renaissance"] = 240
	var r := DevelopmentSystem.move(repo, s, player, "renaissance", 20, "a school")
	assert_eq(int(r["from_tier"]), 0)
	assert_eq(int(r["to_tier"]), 1)
	assert_eq(DevelopmentSystem.tier(s, player, "renaissance"), 1)
	assert_true(_flags().has("dev_renaissance_up_1"))
	DevelopmentSystem.move(repo, s, player, "renaissance", 5, "more")
	assert_eq(_flags().count("dev_renaissance_up_1"), 1)
	var f := _foreign()
	s.development[f]["chivalry"] = 240
	DevelopmentSystem.move(repo, s, f, "chivalry", 20, "a tourney")
	var slot := ""
	for sl: String in ["raider_realm", "neighbor_realm", "empire_realm"]:
		if repo.resolve_realm(sl) == f:
			slot = sl
			break
	assert_ne(slot, "")
	assert_true(_flags().has("dev_foreign_%s_chivalry_up_1" % slot), "foreign flags name the slot")
	assert_eq(s.development_log.size(), 3)
	assert_eq(String(s.development_log[0]["reason"]), "a school")

func test_save_round_trip_keeps_development() -> void:
	DevelopmentSystem.move(repo, s, player, "renaissance", 200, "x")
	DevelopmentSystem.move(repo, s, _foreign(), "chivalry", 300, "y")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.development, s.development)
	assert_eq(back.development_log, s.development_log)

func test_old_save_without_development_loads_seeded() -> void:
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	d.erase("development")
	d.erase("development_log")
	var back := GameState.from_dict(d)
	assert_true(back.development.is_empty())
	DevelopmentSystem.ensure(repo, back)
	assert_eq(back.development, s.development)
