extends GutTest

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	s.tick = 3

func test_metric_gold_and_opinion_ops() -> void:
	var t0: float = s.metrics["treasury"]
	var o0: int = s.characters["char_chaplain"].opinion
	var res := EventEffects.apply(
		"gold:-30; metric:church_opinion:8; opinion:chaplain:4:blessed the gift", s, data)
	assert_eq(s.metrics["treasury"], t0 - 30.0)
	assert_eq(s.characters["char_chaplain"].opinion, o0 + 4)
	assert_string_contains(
		s.characters["char_chaplain"].opinion_log[-1]["reason"], "blessed the gift")
	assert_eq(res.size(), 3)

func test_schedule_flag_promise_ops() -> void:
	# A new campaign already carries the prologue's opener on its schedule
	# (GameState.new_campaign); this test is about what the ops append.
	s.event_state["scheduled"] = []
	EventEffects.apply("schedule:ev_test_followup:12; flag:omen_seen; promise:marshal:LEVY_RAISE:8", s, data)
	assert_eq(s.event_state["scheduled"].size(), 1)
	assert_eq(String(s.event_state["scheduled"][0]["event_id"]), "ev_test_followup")
	assert_eq(int(s.event_state["scheduled"][0]["due_tick"]), 15)
	assert_true("omen_seen" in s.event_state["flags"])
	assert_eq(s.promises.size(), 1)
	assert_eq(String(s.promises[0]["character_id"]), "char_marshal")
	assert_eq(int(s.promises[0]["tick_due"]), 11)

## FIX 2(a): optional reason_label param stamps metric/gold results with a
## human reason (used by EventSystem.apply_choice to pass the choice label);
## omitted entirely (as before this fix) when the caller doesn't pass one.
func test_reason_label_stamps_metric_and_gold_results() -> void:
	var res := EventEffects.apply("gold:-5; metric:unrest:1", s, data, "a choice's doing")
	for r in res:
		assert_eq(String(r["reason"]), "a choice's doing")

func test_no_reason_label_omits_reason_key() -> void:
	var res := EventEffects.apply("gold:-5; metric:unrest:1", s, data)
	for r in res:
		assert_false(r.has("reason"))

func test_unknown_op_is_loud_but_safe() -> void:
	var res := EventEffects.apply("frobnicate:9", s, data)
	assert_eq(res.size(), 0)

func test_event_state_round_trip() -> void:
	EventEffects.apply("schedule:ev_x:5; flag:f1", s, data)
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
	assert_true("f1" in s2.event_state["flags"])

## Ledger ops (spec 2026-09-09 §2.3): events reach the same fields orders do.
func test_world_and_attribute_ops_go_through_the_ledger() -> void:
	var before := int(WorldLedger.value_of(data, s, "military.kingdoms.player_realm.infantry"))
	var results := EventEffects.apply(
		"world:military.kingdoms.player_realm.infantry:-200:a plague in the barracks;"
		+ "attribute:you:prestige:-1:the court whispers", s, data)
	assert_eq(int(WorldLedger.value_of(data, s, "military.kingdoms.player_realm.infantry")),
		before - 200)
	assert_eq(String(results[0]["kind"]), "world")
	assert_eq(String(results[0]["reason"]), "a plague in the barracks")
	assert_eq(String(results[1]["kind"]), "attribute")
	assert_eq(String(s.characters["you"].attribute_log[-1]["reason"]), "the court whispers")

func test_gold_and_metric_ops_take_an_optional_reason() -> void:
	var results := EventEffects.apply("gold:-5:the clerks;metric:grain:3:a gift", s, data)
	assert_eq(String(results[0]["reason"]), "the clerks")
	assert_eq(String(results[1]["reason"]), "a gift")
