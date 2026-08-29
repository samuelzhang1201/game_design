extends GutTest
## TopBar (UI_example chrome, supersedes the KingdomCard): date + the six
## metrics with this tick's deltas + a pending-event chip. Ports the old
## kingdom-card coverage (values mode, changes mode) onto the strip.

func _bar() -> TopBar:
	var t: TopBar = load("res://scenes/top_bar.tscn").instantiate()
	add_child_autofree(t)
	return t

func test_shows_date_and_metric_values() -> void:
	Game.start_campaign(42)
	var t := _bar()
	await wait_frames(1)
	assert_string_contains(t.find_child("DateLabel", true, false).text, "Year 1")
	assert_eq(t.metric_text("treasury"), str(int(Game.state.metrics["treasury"])))
	assert_eq(t.metric_text("grain"), str(int(Game.state.metrics["grain"])))

func test_shows_tick_deltas_from_current_report() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var t := _bar()
	await wait_frames(1)
	assert_ne(t.delta_text("treasury"), "",
		"income always moves treasury, so its delta column is filled")
	assert_true(t.delta_text("treasury").begins_with("+")
		or t.delta_text("treasury").begins_with("-"))

func test_event_chip_tracks_pending_event() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var t := _bar()
	await wait_frames(1)
	assert_false(t.find_child("EventChip", true, false).visible)
	Game.engine.events._fire("ev_01", Game.state)
	t.refresh()
	assert_true(t.find_child("EventChip", true, false).visible,
		"a pending event shows the chip")
	Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	await wait_frames(1)
	assert_false(t.find_child("EventChip", true, false).visible,
		"resolving the event (state_changed) hides the chip again")
