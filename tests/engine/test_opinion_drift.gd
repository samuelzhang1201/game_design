extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)


func test_variant_matching() -> void:
	var pos := OpinionDrift.signature_for(data, "TAX_RATE_ADJUST", {"delta": 2})
	var neg := OpinionDrift.signature_for(data, "TAX_RATE_ADJUST", {"delta": -1})
	assert_eq(pos["tax_incidence"], -30.0)
	assert_eq(neg["tax_incidence"], 30.0)
	var tithe := OpinionDrift.signature_for(data, "CHURCH_POLICY", {"mode": "tithe"})
	assert_eq(tithe["orthodoxy"], -50.0)
	assert_eq(OpinionDrift.signature_for(data, "COUNCIL_CONSULT", {}), {
		"centralism": 0.0, "militarism": 0.0, "orthodoxy": 0.0,
		"tax_incidence": 0.0, "expansionism": 0.0})
	assert_eq(OpinionDrift.signature_for(data, "NO_SUCH_ACTION", {}), {})

func test_odo_hates_the_tithe_worked_example() -> void:
	# CHURCH_POLICY tithe sig: centralism +10, orthodoxy -50 (L1 norm 60).
	# Odo: centralism 10, orthodoxy 70, sensitivity 80, pragmatism 30.
	# dot = 10*10 + (-50)*70 = -3400; alignment = -3400/6000 = -0.5667
	# delta = round(-0.5667 * 0.8 * 0.7 * 20) = round(-6.35) = -6
	var sig := OpinionDrift.signature_for(data, "CHURCH_POLICY", {"mode": "tithe"})
	var odo: Character = s.characters["char_chaplain"]
	var before: int = odo.opinion
	var applied := OpinionDrift.apply(data, s, sig, "tithed the church")
	assert_eq(odo.opinion, before - 6)
	assert_string_contains(odo.opinion_log[-1]["reason"], "tithed the church (opposes, orthodoxy)")
	var found := false
	for a in applied:
		if a["character_id"] == "char_chaplain":
			found = true
			assert_eq(a["delta"], -6)
	assert_true(found)

func test_pragmatist_barely_notices() -> void:
	# Mirella on tithe: dot = 10*10 + (-50)*(-20) = 1100; a = 0.1833
	# delta = round(0.1833 * 0.55 * 0.25 * 20) = round(0.50) = 1
	var sig := OpinionDrift.signature_for(data, "CHURCH_POLICY", {"mode": "tithe"})
	var before: int = s.characters["char_steward"].opinion
	OpinionDrift.apply(data, s, sig, "tithed the church")
	assert_eq(s.characters["char_steward"].opinion, before + 1)

func test_zero_signature_applies_nothing() -> void:
	var logs_before: int = s.characters["char_marshal"].opinion_log.size()
	OpinionDrift.apply(data, s, {}, "nothing")
	OpinionDrift.apply(data, s, OpinionDrift.signature_for(data, "COUNCIL_CONSULT", {}), "consulted")
	assert_eq(s.characters["char_marshal"].opinion_log.size(), logs_before)
