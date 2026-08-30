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

## --- Task 6: the reckoning (spec §6) ---

func _tell_lie_to_malvern() -> Dictionary:
	var lie := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	return ClaimLedger.record(data, state, "you", "char_lord_malvern", lie, 90.0, 4)

func test_nothing_resolves_while_the_truth_stays_hidden() -> void:
	_tell_lie_to_malvern()
	assert_eq(ClaimLedger.resolve_due(data, state, 5).size(), 0)
	assert_eq(ClaimLedger.open_claims(state).size(), 1)

func test_lie_is_caught_when_the_listener_learns_the_truth() -> void:
	var rec := _tell_lie_to_malvern()
	var trust_before := SourceTrust.get_trust(data, state, "you", "char_lord_malvern")
	# The truth reaches Malvern by some other route.
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var resolved := ClaimLedger.resolve_due(data, state, 9)
	assert_eq(resolved.size(), 1)
	assert_eq(String(resolved[0]["status"]), "caught")
	assert_eq(String(rec["status"]), "caught", "the stored record is updated in place")
	# Trust drops by lie_caught_trust_penalty (25): 87.5 -> 62.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		trust_before - 25.0, 0.001)

func test_caught_lie_costs_relationship_sentiment_with_a_reason() -> void:
	_tell_lie_to_malvern()
	var edge_before: float = RelationshipGraph.edge(state, "char_lord_malvern", "you")["sentiment"]
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	ClaimLedger.resolve_due(data, state, 9)
	var edge := RelationshipGraph.edge(state, "char_lord_malvern", "you")
	assert_almost_eq(float(edge["sentiment"]), edge_before - 12.0, 0.001)
	var last: Dictionary = edge["log"][edge["log"].size() - 1]
	assert_string_contains(String(last["reason"]), "lied")

func test_caught_lie_mints_a_betrayal_fact_the_wronged_character_knows() -> void:
	_tell_lie_to_malvern()
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var resolved := ClaimLedger.resolve_due(data, state, 9)
	var betrayal := String(resolved[0]["betrayal_fact"])
	assert_ne(betrayal, "")
	assert_eq(String(state.knowledge[betrayal]["kind"]), "secret")
	assert_eq(String(state.knowledge[betrayal]["subject"]), "you",
		"the liar is the subject, so it spreads as news about the king")
	assert_true(bool(state.knowledge[betrayal]["truth"]), "the betrayal itself is true")
	assert_true(KnowledgeBase.knows(state, "char_lord_malvern", betrayal))
	assert_false(KnowledgeBase.knows(state, "char_chaplain", betrayal),
		"it starts with the wronged character alone and spreads later")

func test_truth_told_is_rewarded_and_mints_nothing() -> void:
	var honest := _claim("grain", "eastmarch", "The eastmarch granaries stand empty", 0.0, true)
	ClaimLedger.record(data, state, "you", "char_lord_malvern", honest, 90.0, 4)
	var trust_before := SourceTrust.get_trust(data, state, "you", "char_lord_malvern")
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var resolved := ClaimLedger.resolve_due(data, state, 9)
	assert_eq(String(resolved[0]["status"]), "kept")
	assert_eq(String(resolved[0]["betrayal_fact"]), "")
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		trust_before + 3.0, 0.001)

func test_a_claim_resolves_only_once() -> void:
	_tell_lie_to_malvern()
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	assert_eq(ClaimLedger.resolve_due(data, state, 9).size(), 1)
	assert_eq(ClaimLedger.resolve_due(data, state, 10).size(), 0, "no double jeopardy")
