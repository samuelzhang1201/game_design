extends GutTest
## Per-character knowledge (spec D5): facts carry knower lists, so who knows
## what is the engine's business, never the model's.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_seed_facts_load_into_state() -> void:
	assert_gte(state.knowledge.size(), 9, "seed facts present")
	assert_true(state.knowledge.has("fact_chancellor_graft"))

func test_every_seed_knower_exists_in_the_roster() -> void:
	# init_from_data silently `continue`s past any id not in the roster, so
	# asserting against state.knowledge (post-filter) can never fail. Assert
	# against data.facts.csv rows directly so a typo in initial_knowers is
	# actually caught.
	for row in data.facts:
		var raw := String(row.get("initial_knowers", ""))
		if raw == KnowledgeBase.ALL_KNOWERS:
			continue
		for id in raw.split("|", false):
			assert_true(state.characters.has(String(id)),
				"%s knower %s is a real character" % [String(row["fact_code"]), id])

func test_secret_is_known_only_to_its_knowers() -> void:
	assert_true(KnowledgeBase.knows(state, "char_steward", "fact_chancellor_graft"))
	assert_true(KnowledgeBase.knows(state, "char_spymaster", "fact_chancellor_graft"))
	assert_false(KnowledgeBase.knows(state, "char_marshal", "fact_chancellor_graft"),
		"the Marshal has not heard about the graft")
	assert_false(KnowledgeBase.knows(state, "you", "fact_chancellor_graft"),
		"nor has the king — this is the plot")

func test_common_sense_is_known_by_everyone_at_full_credibility() -> void:
	for id in state.characters:
		assert_true(KnowledgeBase.knows(state, String(id), "common_dragons"),
			String(id) + " has common sense")
		assert_eq(KnowledgeBase.credibility_of(state, String(id), "common_dragons"), 100.0)

func test_learn_adds_a_knower_at_the_given_credibility() -> void:
	KnowledgeBase.learn(state, "char_marshal", "fact_chancellor_graft", 42.0)
	assert_true(KnowledgeBase.knows(state, "char_marshal", "fact_chancellor_graft"))
	assert_eq(KnowledgeBase.credibility_of(state, "char_marshal", "fact_chancellor_graft"), 42.0)
	# Learning again does not duplicate the knower.
	KnowledgeBase.learn(state, "char_marshal", "fact_chancellor_graft", 50.0)
	assert_eq(state.knowledge["fact_chancellor_graft"]["knowers"].count("char_marshal"), 1)

func test_credibility_of_unknown_fact_is_zero() -> void:
	assert_eq(KnowledgeBase.credibility_of(state, "char_marshal", "fact_chancellor_graft"), 0.0)

func test_add_fact_creates_a_runtime_fact() -> void:
	KnowledgeBase.add_fact(state, "fact_test_lie", {
		"kind": "secret", "subject": "you", "claim_type": "loyalty",
		"text": "The king lied about the granaries.", "truth": true})
	KnowledgeBase.learn(state, "char_chaplain", "fact_test_lie", 90.0)
	assert_true(KnowledgeBase.knows(state, "char_chaplain", "fact_test_lie"))
	assert_eq(String(state.knowledge["fact_test_lie"]["text"]),
		"The king lied about the granaries.")

func test_facts_about_filters_by_type_and_subject_for_one_knower() -> void:
	var found := KnowledgeBase.facts_about(state, "char_spymaster", "army_size", "doncaster")
	assert_eq(found.size(), 1)
	assert_eq(String(found[0]["code"]), "fact_doncaster_muster")
	assert_eq(KnowledgeBase.facts_about(state, "char_chaplain", "army_size", "doncaster").size(), 0,
		"the chaplain knows nothing of Doncaster's muster")

func test_knowledge_survives_save_round_trip() -> void:
	KnowledgeBase.learn(state, "char_marshal", "fact_chancellor_graft", 42.0)
	var restored := GameState.from_dict(state.to_dict())
	assert_true(KnowledgeBase.knows(restored, "char_marshal", "fact_chancellor_graft"))
	assert_eq(KnowledgeBase.credibility_of(restored, "char_marshal", "fact_chancellor_graft"), 42.0)
	assert_eq(bool(restored.knowledge["fact_chancellor_graft"]["truth"]), true)

func test_pre_feature_save_loads_with_empty_knowledge() -> void:
	var d := state.to_dict()
	d.erase("knowledge")
	var restored := GameState.from_dict(d)
	assert_not_null(restored, "old saves are not refused")
	assert_eq(restored.knowledge.size(), 0)
