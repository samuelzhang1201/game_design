extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Belief scoring (spec 2.1, 5 node 2). Plausibility comes from outside;
## this unit is the engine half that turns it into a number, so every value
## below is hand-computed.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = SuiteData.repo()
	state = SuiteData.campaign(data, 42)

func _claim(claim_type: String, subject: String, text: String,
		magnitude: float, truth: bool) -> Dictionary:
	return {"claim_type": claim_type, "subject": subject, "text": text,
		"magnitude": magnitude, "truth": truth}

func test_impossible_claim_scores_zero_whatever_the_plausibility() -> void:
	var c := _claim("identity", "you", "I am a dragon", 0.0, false)
	var r := Belief.score(data, state, "char_lord_malvern", "you", c, 100.0)
	assert_eq(float(r["belief"]), 0.0, "the floor overrides any plausibility")
	assert_true(bool(r["vetoed"]))
	assert_eq(String(r["rule_code"]), "onto_dragon")

func test_trusted_listener_believes_a_plausible_claim() -> void:
	# Malvern's trust in the king is 87.5, he has no belief traits, and knows
	# nothing about grain stores in "eastmarch": 80 * 0.875 = 70.0
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, true)
	var r := Belief.score(data, state, "char_lord_malvern", "you", c, 80.0)
	assert_almost_eq(float(r["belief"]), 70.0, 0.001)
	assert_eq(int(r["corroboration"]), 0)

func test_paranoid_listener_discounts_the_same_claim() -> void:
	# Quill is paranoid and has no edge toward the king, so trust is the
	# default 50: 80 * 0.5 = 40.0, minus 10 for paranoia = 30.0
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, true)
	var r := Belief.score(data, state, "char_spymaster", "you", c, 80.0)
	assert_almost_eq(float(r["belief"]), 30.0, 0.001)

func test_corroboration_raises_belief() -> void:
	# Quill knows fact_raider_muster (army_size / the raider realm, truth true).
	# An agreeing claim: 80 * 0.5 = 40.0, -10 paranoid, +8 corroboration = 38.0
	var raider := data.resolve_realm("raider_realm")
	var c := _claim("army_size", raider, "The raiders mass for a raid", 9000.0, true)
	var r := Belief.score(data, state, "char_spymaster", "you", c, 80.0)
	assert_eq(int(r["corroboration"]), 1)
	assert_almost_eq(float(r["belief"]), 38.0, 0.001)

func test_contradiction_lowers_belief() -> void:
	# Same known fact, but the claim asserts the opposite: 40.0 - 10 - 8 = 22.0
	var raider := data.resolve_realm("raider_realm")
	var c := _claim("army_size", raider, "The raiders are at peace", 0.0, false)
	var r := Belief.score(data, state, "char_spymaster", "you", c, 80.0)
	assert_eq(int(r["corroboration"]), -1)
	assert_almost_eq(float(r["belief"]), 22.0, 0.001)

func test_belief_is_clamped_to_the_range() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, true)
	var high := Belief.score(data, state, "char_lord_malvern", "you", c, 100.0)
	assert_lte(float(high["belief"]), 100.0)
	var low := Belief.score(data, state, "char_spymaster", "you", c, 0.0)
	assert_gte(float(low["belief"]), 0.0)

func test_result_always_carries_a_reason() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, true)
	assert_ne(String(Belief.score(data, state, "char_lord_malvern", "you", c, 80.0)["reason"]), "")

func test_trusting_listener_inflates_the_same_claim() -> void:
	# char_lady_ysolde (trusting) and char_lord_edgar (no belief traits) both
	# have no relationship edge with "you", so both trust at the default 50:
	# 80 * 0.5 = 40.0. Trusting adds +10 -> 50.0; the neutral listener stays 40.0.
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, true)
	var trusting := Belief.score(data, state, "char_lady_ysolde", "you", c, 80.0)
	var neutral := Belief.score(data, state, "char_lord_edgar", "you", c, 80.0)
	assert_almost_eq(float(neutral["belief"]), 40.0, 0.001)
	assert_almost_eq(float(trusting["belief"]), 50.0, 0.001)
	assert_gt(float(trusting["belief"]), float(neutral["belief"]))

func test_repetition_does_not_corroborate() -> void:
	# The same speaker's own earlier believed claim mints a fact with
	# "source" set to that speaker, so it must not count as corroboration for
	# a second telling of the same thing (spec §6 — corroboration must come
	# from an independent source). Malvern knows nothing about grain in
	# eastmarch beforehand, so any corroboration here can only come from the
	# king's own first telling.
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	var first := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 1)
	assert_true(bool(first["believed"]), "the first telling is believed and minted as a fact")
	var second := Belief.score(data, state, "char_lord_malvern", "you", c, 90.0)
	assert_eq(int(second["corroboration"]), 0,
		"the speaker's own earlier claim does not corroborate this one")
