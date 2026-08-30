extends GutTest
## Recording claims (spec §6, "Telling"). Resolution is Task 6.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func _claim(claim_type: String, subject: String, text: String,
		magnitude: float, truth: bool) -> Dictionary:
	return {"claim_type": claim_type, "subject": subject, "text": text,
		"magnitude": magnitude, "truth": truth}

func test_believed_claim_is_recorded_open_and_becomes_a_known_fact() -> void:
	# Malvern trusts the king at 87.5; plausibility 90 gives 78.75, over the
	# belief_threshold of 55.
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	assert_true(bool(rec["believed"]))
	assert_eq(String(rec["status"]), "open")
	assert_eq(state.claims.size(), 1)
	assert_ne(String(rec["fact_code"]), "", "a believed claim creates a fact")
	assert_true(KnowledgeBase.knows(state, "char_lord_malvern", String(rec["fact_code"])),
		"the listener now knows the thing he was told")
	assert_almost_eq(KnowledgeBase.credibility_of(state, "char_lord_malvern",
		String(rec["fact_code"])), 78.75, 0.001)

func test_disbelieved_claim_is_recorded_but_teaches_nothing() -> void:
	# Quill has no edge toward the king (trust 50) and is paranoid (-10):
	# 80 * 0.50 - 10 = 30, under the belief_threshold of 55.
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_spymaster", c, 80.0, 4)
	assert_false(bool(rec["believed"]))
	assert_eq(String(rec["status"]), "disbelieved")
	assert_eq(String(rec["fact_code"]), "", "nothing is learned")
	assert_eq(KnowledgeBase.known_facts(state, "char_spymaster").filter(
		func(f): return String(f["subject"]) == "eastmarch").size(), 0)

func test_impossible_claim_is_disbelieved_and_never_open() -> void:
	var c := _claim("identity", "you", "I am a dragon", 0.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 100.0, 4)
	assert_false(bool(rec["believed"]))
	assert_eq(String(rec["status"]), "disbelieved")
	assert_eq(ClaimLedger.open_claims(state).size(), 0)

func test_claim_stores_ground_truth_the_listener_cannot_see() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	assert_false(bool(rec["truth"]), "the engine records that this was a lie")

func test_open_claims_lists_only_believed_unresolved_ones() -> void:
	var lie := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	ClaimLedger.record(data, state, "you", "char_lord_malvern", lie, 90.0, 4)
	ClaimLedger.record(data, state, "you", "char_spymaster", lie, 80.0, 4)
	assert_eq(ClaimLedger.open_claims(state).size(), 1)

func test_fact_codes_are_unique_across_claims() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	var a := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	var b := ClaimLedger.record(data, state, "you", "char_chaplain", c, 90.0, 5)
	assert_ne(String(a["fact_code"]), String(b["fact_code"]))

func test_claims_survive_save_round_trip() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(restored.claims.size(), 1)
	assert_eq(String(restored.claims[0]["listener"]), "char_lord_malvern")
	assert_false(bool(restored.claims[0]["truth"]))

func test_pre_feature_save_loads_with_no_claims() -> void:
	var d := state.to_dict()
	d.erase("claims")
	var restored := GameState.from_dict(d)
	assert_not_null(restored)
	assert_eq(restored.claims.size(), 0)
