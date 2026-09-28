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


func _menu_btn(r: GameRoot, node_name: String) -> Button:
	return r.pause_menu().find_child(node_name, true, false)


## Fix round 1: a spy report open (and a second waiting) when the player
## restarts from the pause menu must not crash, and must leave nothing
## behind to reopen or misfire once Game.state is gone.
func test_a_restart_mid_report_clears_the_queue_without_crashing() -> void:
	var r: GameRoot = await _root()
	var a := _spy_letter()
	var b := _spy_letter()
	r.on_new_missives([a, b])
	assert_true(r.report_popup().visible)
	assert_eq(r.pending_reports(), [b])
	Game.menu_requested.emit()
	_menu_btn(r, "Restart").pressed.emit()
	await wait_frames(2)
	assert_null(Game.state, "the realm is gone")
	assert_false(r.report_popup().visible, "the stale dialog is hidden by the reset")
	assert_eq(r.pending_reports(), [], "the queue is cleared")
	# Sealing the now-stale, already-hidden dialog must be harmless.
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_false(r.report_popup().visible)
	assert_eq(r.pending_reports(), [])


## Fix round 1: same shape of bug via Load Game — the loaded (earlier-saved)
## state never had the letters queued after the save, so their ids are
## genuinely stale, not just discarded.
func test_a_load_mid_report_discards_a_stale_id_without_crashing() -> void:
	var r: GameRoot = await _root()
	Game.save_campaign()
	var a := _spy_letter()
	var b := _spy_letter()
	r.on_new_missives([a, b])
	assert_true(r.report_popup().visible)
	assert_eq(r.pending_reports(), [b])
	Game.menu_requested.emit()
	_menu_btn(r, "LoadGame").pressed.emit()
	await wait_frames(2)
	assert_true(MissiveLog.find(Game.state, b).is_empty(), "the loaded realm never had this letter")
	assert_false(r.report_popup().visible)
	assert_eq(r.pending_reports(), [])
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_false(r.report_popup().visible)
	assert_eq(r.pending_reports(), [])


## Fix round 2: on_new_missives can open a report and, in the very same
## stepped day, a pending event can still switch to CONVERSATION — an
## actively-open report must survive that (nothing is left in
## _pending_reports to reopen it if it were hidden), staying stacked above
## the new screen; only a switch to MENU forces it shut (a reset already ran,
## or the campaign is being left outright).
func test_the_popup_survives_a_switch_to_conversation_but_not_to_menu() -> void:
	var r: GameRoot = await _root()
	var id := _spy_letter()
	r.on_new_missives([id])
	assert_true(r.report_popup().visible)
	r._switch_to(GameRoot.State.CONVERSATION)
	assert_true(r.report_popup().visible, "an open report survives a switch to CONVERSATION")
	assert_true(r.report_popup().get_index() > r.current_screen.get_index(),
		"the popup stays stacked above the new screen")
	r._switch_to(GameRoot.State.MENU)
	assert_false(r.report_popup().visible, "MENU always closes it")


## Fix round 2: the restart hotkey (R) skipped _reset_reports() before — it
## now routes through _on_menu_restart() like the pause menu's own button.
func test_the_restart_hotkey_also_clears_the_report_queue() -> void:
	var r: GameRoot = await _root()
	var a := _spy_letter()
	var b := _spy_letter()
	r.on_new_missives([a, b])
	assert_true(r.report_popup().visible)
	assert_eq(r.pending_reports(), [b])
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	r._unhandled_input(key)
	await wait_frames(2)
	assert_null(Game.state, "the restart hotkey still restarts")
	assert_false(r.report_popup().visible, "and clears the report dialog too")
	assert_eq(r.pending_reports(), [])
