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
	EventEffects.apply("schedule:ev_test_followup:12; flag:omen_seen; promise:marshal:LEVY_RAISE:8", s, data)
	assert_eq(s.event_state["scheduled"].size(), 1)
	assert_eq(String(s.event_state["scheduled"][0]["event_id"]), "ev_test_followup")
	assert_eq(int(s.event_state["scheduled"][0]["due_tick"]), 15)
	assert_true("omen_seen" in s.event_state["flags"])
	assert_eq(s.promises.size(), 1)
	assert_eq(String(s.promises[0]["character_id"]), "char_marshal")
	assert_eq(int(s.promises[0]["tick_due"]), 11)

func test_unknown_op_is_loud_but_safe() -> void:
	var res := EventEffects.apply("frobnicate:9", s, data)
	assert_eq(res.size(), 0)

func test_event_state_round_trip() -> void:
	EventEffects.apply("schedule:ev_x:5; flag:f1", s, data)
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
	assert_true("f1" in s2.event_state["flags"])
