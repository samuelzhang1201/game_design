extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Development axes data (spec 2026-10-12-development-axes §3-4): the tier
## tables, the trait preference columns and the balance keys.

const AXES := ["renaissance", "chivalry"]
const SPECIAL := ["arm_power_permille", "cavalry_upkeep_permille", "adopt_permille", "flag", "unlock"]
const BALANCE_KEYS := ["dev_start_renaissance", "dev_start_chivalry", "dev_decay_per_month",
		"dev_ai_target_per_pref", "dev_ai_step", "dev_decree_opinion_per_100", "dev_cavalry_upkeep_per_head"]

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_axes_cover_both_axes_and_four_tiers() -> void:
	for axis in AXES:
		var rows := repo.development_axes.filter(func(r): return r["axis"] == axis)
		assert_eq(rows.size(), 4, axis + " has four tiers")
		var last := -1
		for i in rows.size():
			assert_eq(int(rows[i]["tier"]), i, axis + " tier order")
			var m := int(rows[i]["min_score"])
			assert_gt(m, last, axis + " min_score rises")
			last = m
			assert_gte(int(rows[i]["hysteresis"]), 0)
		assert_eq(int(rows[0]["min_score"]), 0, axis + " starts at 0")


func test_tier_effect_rows_are_well_formed() -> void:
	var metrics := {}
	for p in ["treasury", "grain", "strategic", "civil", "unrest", "legitimacy", "army_quality",
			"church_opinion", "peasant_contentment"]:
		metrics[p] = true
	assert_gt(repo.development_tier_effects.size(), 0)
	for r in repo.development_tier_effects:
		var ch := String(r["channel"])
		assert_true(AXES.has(r["axis"]))
		assert_between(int(r["tier"]), 1, 3)
		assert_true(metrics.has(ch) or SPECIAL.has(ch), "channel " + ch)
		if metrics.has(ch):
			assert_eq(String(r["timing"]), "monthly", ch + " is monthly")
		var amt := LawEffects.amount_of(repo, String(r["amount"]))
		assert_ne(amt, 0.0, "amount resolves and is non-zero")
		assert_ne(String(r["reason"]).strip_edges(), "")


func test_trait_columns_present() -> void:
	for code in repo.traits:
		for col in ["dev_renaissance", "dev_chivalry"]:
			var raw := String(repo.traits[code].get(col, "x"))
			assert_true(raw.is_valid_int(), code + "." + col)
			assert_between(int(raw), -100, 100)


func test_balance_keys_exist() -> void:
	for k in BALANCE_KEYS:
		assert_true(repo.balance.has(k), k)
	assert_eq(repo.bal("dev_start_renaissance"), 100.0)
	assert_eq(repo.bal("dev_ai_step"), 5.0)
