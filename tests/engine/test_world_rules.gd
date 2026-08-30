extends GutTest
## The deterministic floor that overrides any model verdict (spec D8).

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_data_loads() -> void:
	assert_gte(data.world_rules.size(), 8, "world rules loaded")
	assert_true(data.claim_types.has("army_size"), "claim taxonomy loaded")

func test_ontology_claim_is_vetoed() -> void:
	var v := WorldRules.veto(data, "identity", "I am a dragon", 0.0)
	assert_true(v["vetoed"])
	assert_eq(String(v["rule_code"]), "onto_dragon")
	assert_ne(String(v["reason"]), "", "veto carries a reason")

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
