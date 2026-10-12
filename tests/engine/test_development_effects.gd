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
	var arms := {"artillery": 10}
	var base := ArmySystem.power_of_arms(repo, arms, 10, 50, 50, "defend", "", "")
	assert_gt(base, 0)
	assert_eq(ArmySystem.power_of_arms(repo, arms, 10, 50, 50, "defend", "", "", "", 0, {}), base)
	var scaled := ArmySystem.power_of_arms(repo, arms, 10, 50, 50, "defend", "", "", "", 0, {"artillery": 1100})
	assert_almost_eq(float(scaled), base * 1.1, 1.0)


func test_ranged_penalty_hits_archers_only() -> void:
	var arms := {"archers": 1000, "cavalry": 1000}
	var base := ArmySystem.power_of_arms(repo, arms, 2000, 50, 50, "defend", "", "")
	var only_arch := ArmySystem.power_of_arms(repo, {"archers": 1000}, 1000, 50, 50, "defend", "", "")
	var hit := ArmySystem.power_of_arms(repo, arms, 2000, 50, 50, "defend", "", "", "", 0, {"archers": 900})
	assert_lt(hit, base)
	# The cavalry half is untouched: the drop is all archers'.
	assert_almost_eq(float(base - hit), float(only_arch) * 0.1, 2.0)
	var cav := ArmySystem.power_of_arms(repo, arms, 2000, 50, 50, "defend", "", "", "", 0, {"cavalry": 1000})
	assert_eq(cav, base)
