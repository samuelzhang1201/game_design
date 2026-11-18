extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Tier modifiers reach the ledger, arm power and cavalry upkeep (spec
## 2026-10-12-development-axes §4). Hand values in each test.

var repo: DataRepository
var s: GameState
var player: String


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	player = repo.resolve_realm("player_realm")
	repo.development_tier_effects = []


func _row(axis: String, tier: int, channel: String, target: String, amount: String, timing: String) -> void:
	repo.development_tier_effects.append({"axis": axis, "tier": str(tier), "channel": channel,
		"target": target, "amount": amount, "timing": timing, "reason": "%s tier %d %s" % [axis, tier, channel]})


func _tier(axis: String, t: int) -> void:
	DevelopmentSystem.seed(repo, s)
	s.development[player]["tier_" + axis] = t


func _cavalry(heads: int) -> void:
	s.army_roster = {"horse": {"regiment_code": "horse", "kingdom_code": player, "cavalry": heads}}


func test_month_lines_follow_confirmed_tier() -> void:
	_row("renaissance", 1, "treasury", "", "99", "monthly")
	_row("renaissance", 2, "church_opinion", "", "-0.5", "monthly")
	_row("renaissance", 2, "treasury", "", "10", "monthly")
	_tier("renaissance", 2)
	var lines := DevelopmentSystem.month_lines(repo, s)
	assert_eq(lines.size(), 2)
	assert_eq(String(lines[0]["metric"]), "church_opinion")
	assert_almost_eq(float(lines[0]["delta"]), -0.5, 0.001)
	assert_eq(String(lines[0]["reason"]), "renaissance tier 2 church_opinion")
	assert_eq(String(lines[1]["metric"]), "treasury")
	assert_almost_eq(float(lines[1]["delta"]), 10.0, 0.001)
	_tier("renaissance", 0)
	assert_eq(DevelopmentSystem.month_lines(repo, s).size(), 0)


func test_cavalry_upkeep_whole_gold() -> void:
	repo.balance["dev_cavalry_upkeep_per_head"] = 2.0
	_row("chivalry", 1, "cavalry_upkeep_permille", "", "500", "permanent")
	_tier("chivalry", 1)
	_cavalry(400)
	var lines := DevelopmentSystem.month_lines(repo, s)
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["metric"]), "treasury")
	assert_almost_eq(float(lines[0]["delta"]), -400.0, 0.001)
	assert_eq(String(lines[0]["reason"]), "chivalry tier 1 cavalry_upkeep_permille (400 horse)")


func test_no_cavalry_no_upkeep_line() -> void:
	repo.balance["dev_cavalry_upkeep_per_head"] = 2.0
	_row("chivalry", 1, "cavalry_upkeep_permille", "", "500", "permanent")
	_tier("chivalry", 1)
	_cavalry(0)
	assert_eq(DevelopmentSystem.month_lines(repo, s).size(), 0)


func test_arm_permille_sums_and_floors() -> void:
	_row("renaissance", 1, "arm_power_permille", "artillery", "100", "permanent")
	_row("chivalry", 1, "arm_power_permille", "artillery", "-50", "permanent")
	_tier("renaissance", 1)
	_tier("chivalry", 1)
	var p := DevelopmentSystem.arm_permille(repo, s, player)
	assert_eq(int(p["artillery"]), 1050)
	assert_eq(int(p.get("cavalry", 1000)), 1000)
	_row("chivalry", 1, "arm_power_permille", "artillery", "-1200", "permanent")
	assert_eq(int(DevelopmentSystem.arm_permille(repo, s, player)["artillery"]), 0)


func test_power_of_arms_scales_one_arm() -> void:
	# Artillery 1000 guns, 8000 crew all fit, training 50 (500+50*10 = 1000), morale 50
	# (500+50*5 = 750), no terrain (1000). Base: the artillery rows' mean
	# ((1100+700)/2 + (900+800)/2 + (800+600)/2 + 1000 + (1100+700)/2) / 5 = 4350/5 = 870.
	# p = 1000*1000*1000/1000 = 1,000,000 -> *870/1000 = 870,000 -> *1000/1000
	# -> *750/1000 = 652,500 -> *1000/1000 = 652,500.
	# base = ceil(652500/1000) = 653; at 1100: ceil(652500*1100/1e6) = ceil(717.75) = 718.
	var arms := {"artillery": 1000}
	var base := ArmySystem.power_of_arms(repo, arms, 8000, 50, 50, "defend", "", "")
	assert_eq(base, 653)
	assert_eq(ArmySystem.power_of_arms(repo, arms, 8000, 50, 50, "defend", "", "", "", 0, {}), 653)
	assert_eq(ArmySystem.power_of_arms(repo, arms, 8000, 50, 50, "defend", "", "", "", 0, {"artillery": 1100}), 718)


func test_ranged_penalty_hits_archers_only() -> void:
	# Archers 1000 + cavalry 1000 elements: 1000 + 2000 crew, all 3000 fit.
	# p is 1,000,000 per arm. Archers base (1000+1000+750+950+1000)/5 = 940: p ->
	# 940,000 -> *750/1000 = 705,000; at 900: ceil(705000*900/1e6) =
	# ceil(634.5) = 635. Cavalry base (850+1250+1000+1200+1150)/5 = 1090: p ->
	# 1,090,000 -> 817,500; ceil(817.5) = 818. Hit host = 818 + 635 = 1453.
	var arms := {"archers": 1000, "cavalry": 1000}
	var hit := ArmySystem.power_of_arms(repo, arms, 3000, 50, 50, "defend", "", "", "", 0, {"archers": 900})
	var only_cav := ArmySystem.power_of_arms(repo, {"cavalry": 1000}, 2000, 50, 50, "defend", "", "")
	var scaled_archers := ArmySystem.power_of_arms(repo, {"archers": 1000}, 1000, 50, 50, "defend", "", "", "", 0, {"archers": 900})
	assert_eq(only_cav, 818)
	assert_eq(scaled_archers, 635)
	assert_eq(hit, 1453)
	assert_eq(hit, only_cav + scaled_archers)


func test_arm_permille_without_state_is_all_1000() -> void:
	for v in DevelopmentSystem.arm_permille(repo, null, player).values():
		assert_eq(int(v), 1000)


func test_flag_and_unlocked_by_tier() -> void:
	_row("renaissance", 2, "unlock", "arquebus", "1", "permanent")
	_row("chivalry", 1, "flag", "honour_bound", "1", "permanent")
	_tier("renaissance", 1)
	_tier("chivalry", 0)
	assert_false(DevelopmentSystem.unlocked(repo, s, player).has("arquebus"))
	assert_false(DevelopmentSystem.flag(repo, s, player, "honour_bound"))
	_tier("renaissance", 2)
	_tier("chivalry", 1)
	assert_true(DevelopmentSystem.unlocked(repo, s, player).has("arquebus"))
	assert_true(DevelopmentSystem.flag(repo, s, player, "honour_bound"))
	_tier("renaissance", 3)
	assert_true(DevelopmentSystem.unlocked(repo, s, player).has("arquebus"))
