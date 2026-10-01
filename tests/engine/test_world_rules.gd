extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The deterministic floor that overrides any model verdict (spec D8).

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()


## Each kind of impossible claim is vetoed by its own rule, with a reason.
func test_impossible_claims_are_vetoed_by_their_rule() -> void:
	for case in [
			["identity", "I am a dragon", "onto_dragon"],
			["event_report", "He came back from the dead", "onto_resurrection"],
			["identity", "She is immortal", "onto_magic"],
			["event_report", "They fired a cannon", "era_gunpowder"],
			["event_report", "He watched through a telescope", "era_optics"]]:
		var v := WorldRules.veto(data, String(case[0]), String(case[1]), 0.0)
		assert_true(v["vetoed"], String(case[1]))
		assert_eq(String(v["rule_code"]), String(case[2]))
		assert_ne(String(v["reason"]), "", "%s: the veto carries a reason" % case[2])

func test_ontology_match_is_case_insensitive() -> void:
	assert_true(WorldRules.veto(data, "identity", "I AM A DRAGON", 0.0)["vetoed"])

func test_magnitude_beyond_bound_is_vetoed() -> void:
	var v := WorldRules.veto(data, "army_size", "I command a great host", 100000000.0)
	assert_true(v["vetoed"])
	assert_eq(String(v["rule_code"]), "mag_army")

func test_magnitude_within_bound_passes() -> void:
	assert_false(WorldRules.veto(data, "army_size", "I command eight thousand", 8000.0)["vetoed"])

func test_plausible_claim_is_not_vetoed() -> void:
	var v := WorldRules.veto(data, "event_report", "The granary is full", 0.0)
	assert_false(v["vetoed"])
	assert_eq(String(v["rule_code"]), "")

func test_magnitude_rule_ignores_other_claim_types() -> void:
	# A huge number in a claim type with no magnitude rule must pass.
	assert_false(WorldRules.veto(data, "intent", "I mean to build much", 100000000.0)["vetoed"])
