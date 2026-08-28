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

## FIX 2 (post-Task-5 review): the summary beat no longer carries "text" at
## build time - it's computed at display time by ConversationBeats.summary_text
## so a quick-reply/free-text order taken later in the SAME conversation can
## still be reflected. This test covers the "last tick's already-decided
## outcomes" half of that (report.outcomes -> council_summary_open + one
## council_summary_decision per outcome); the "resolved this session" half
## (state.recent_outcomes -> council_summary_now) is covered in
## tests/ui/test_conversation_scene.gd, since it needs a live quick-reply.
func test_summary_reflects_outcomes_without_numbers() -> void:
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	var r2 := engine.advance(s)
	if not s.pending_event.is_empty():
		r2.event = {}
	var beats := ConversationBeats.build(r2, s, data)
	assert_eq(beats[-1]["kind"], "summary")
	assert_false(beats[-1].has("text"), "summary text is composed at display time now")
	var summary := ConversationBeats.summary_text(r2, s, data)
	assert_string_contains(summary, "Raise fresh levies")
	for ch in ["0","1","2","3","4","5","6","7","8","9"]:
		assert_false(ch in summary, "no digits in summary (R7): " + summary)

## FIX 1 (post-Task-5 review): report.promise_events (broken promises) used
## to be narrated nowhere under the conversation flow. The wronged minister
## now gets a minister beat about it, inserted before any concern/pitch beat
## (right after the event beat, if any) - here it lands first outright since
## r.event is cleared and no other minister beat can precede index 0.
func test_broken_promise_becomes_minister_beat_before_concerns() -> void:
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	var r := engine.advance(s)
	if not s.pending_event.is_empty():
		engine.events.apply_choice(String(s.pending_event["choices"][0]["choice_id"]), s)
		r.event = {}
	r.promise_events.append({"character_id": "char_marshal",
		"promise_code": "LEVY_RAISE", "status": "broken"})
	var beats := ConversationBeats.build(r, s, data)
	assert_eq(beats[0]["kind"], "minister")
	assert_eq(beats[0]["portrait_id"], "char_marshal")
	assert_gt(String(beats[0]["text"]).length(), 0, "promise beat is spoken")
