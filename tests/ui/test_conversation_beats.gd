extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_minister_beats_group_concern_with_pitch() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	var engine := TickEngine.new(data)
	var r := engine.advance(s)
	if not s.pending_event.is_empty():
		engine.events.apply_choice(String(s.pending_event["choices"][0]["choice_id"]), s)
		r.event = {}
	var beats := ConversationBeats.build(r, s, data)
	assert_gt(beats.size(), 1)
	var steward_beat := {}
	for b in beats:
		if b["kind"] == "minister" and b["portrait_id"] == "char_steward":
			steward_beat = b
	assert_false(steward_beat.is_empty(), "steward speaks about grain")
	assert_string_contains(String(steward_beat["text"]), "Grain")
	assert_gt(steward_beat["suggestions"].size(), 0)
	# no numeric metric values spoken beyond the template's own {value} fills:
	assert_eq(beats[-1]["kind"], "summary")
	assert_eq(beats[-1]["portrait_id"], "round_table")

func test_event_beat_first_when_pending() -> void:
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	var r := engine.advance(s)
	engine.events._fire("ev_01", s)
	r.event = s.pending_event.duplicate(true)
	var beats := ConversationBeats.build(r, s, data)
	assert_eq(beats[0]["kind"], "event")
	assert_eq(beats[0]["portrait_id"], "round_table")

func test_summary_reflects_outcomes_without_numbers() -> void:
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	var r2 := engine.advance(s)
	if not s.pending_event.is_empty():
		r2.event = {}
	var beats := ConversationBeats.build(r2, s, data)
	var summary: String = beats[-1]["text"]
	assert_string_contains(summary, "Raise fresh levies")
	for ch in ["0","1","2","3","4","5","6","7","8","9"]:
		assert_false(ch in summary, "no digits in summary (R7): " + summary)
