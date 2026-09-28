extends GutTest

func before_each() -> void:
	Game.start_campaign(42)
	Game.data.balance["missive_seal_s"] = 0.05
	Game.data.balance["missive_fly_s"] = 0.05


func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r


func _spy_letter() -> int:
	return MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "Spy report — X",
		[MissiveLog.span("people", "People", 2800, 3200)]))


func test_an_envelope_lands_on_the_tab() -> void:
	var r: GameRoot = await _root()
	var tab := r.bottom_bar().button("MISSIVE")
	var f := EnvelopeFlight.fly(r, Rect2(400, 300, 300, 200), tab.get_global_rect(), true, Game.data)
	watch_signals(f)
	await wait_for_signal(f.landed, 2.0)
	assert_signal_emitted(f, "landed")


func test_a_spy_report_stops_the_clock_and_opens_the_dialog() -> void:
	var r: GameRoot = await _root()
	Game.set_clock_speed(1)
	var id := _spy_letter()
	r.on_new_missives([id])
	assert_eq(Game.clock_speed, 0, "the clock stopped")
	assert_true(r.report_popup().visible)
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_false(r.report_popup().visible)
	assert_eq(Game.clock_speed, 0, "nothing restarts the clock")


func test_two_spy_reports_in_one_frame_open_in_turn() -> void:
	var r: GameRoot = await _root()
	var a := _spy_letter()
	var b := _spy_letter()
	r.on_new_missives([a, b])
	assert_eq(r.pending_reports(), [b])
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_true(r.report_popup().visible, "the second opens after the first is sealed")
	assert_eq(r.pending_reports(), [])


func test_a_receipt_flies_without_stopping_the_clock() -> void:
	var r: GameRoot = await _root()
	Game.set_clock_speed(1)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("receipt", "credible", 3,
		MissiveLog.subject("regiment", "x", -1, Vector2(500, 300)), "Receipt — X", []))
	r.on_new_missives([id])
	assert_eq(Game.clock_speed, 1)
	assert_false(r.report_popup().visible)
	Game.set_clock_speed(0)
