extends GutTest

var _kept: Dictionary = {}


func before_each() -> void:
	Game.start_campaign(42)
	_kept = {}
	for key in ["missive_seal_s", "missive_fly_s"]:
		_kept[key] = Game.data.balance[key]
	Game.data.balance["missive_seal_s"] = 0.05
	Game.data.balance["missive_fly_s"] = 0.05


## M9 (final review): the flight timings are put back for every later file.
func after_each() -> void:
	for key: String in _kept:
		Game.data.balance[key] = _kept[key]
	Game.set_clock_speed(0)


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
	# a flag, not watch_signals: at the test's 0.05 s timings one slow frame
	# lets the flight land AND free itself before the awaiter resumes, and a
	# freed object cannot be asked what it emitted (2026-10-01)
	var landed := [false]
	f.landed.connect(func() -> void: landed[0] = true)
	await wait_until(func() -> bool: return landed[0], 2.0)
	assert_true(landed[0], "the envelope lands on the tab")


func test_a_spy_report_stops_the_clock_and_opens_the_dialog() -> void:
	var r: GameRoot = await _root()
	Game.set_clock_speed(1)
	var id := _spy_letter()
	r.on_new_missives([id])
	assert_eq(Game.clock_speed, 0, "the clock stopped")
	assert_true(r.report_popup().visible)
	r.refresh_missive_badge()
	var before := r.bottom_bar().badge("MISSIVE")
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_false(r.report_popup().visible)
	assert_eq(Game.clock_speed, 0, "nothing restarts the clock")
	# M16 (final review): Seal ends with the letter counted on the tab.
	assert_eq(r.bottom_bar().badge("MISSIVE"), MissiveLog.unread(Game.state))
	assert_true(r.bottom_bar().button("MISSIVE").text.contains("(%d)" % MissiveLog.unread(Game.state)),
		"the tab's label carries the count")
	assert_gte(r.bottom_bar().badge("MISSIVE"), before)


## Fix round 1 finding 4: spec §2 says the dialog is "centred over the map
## panel", not the window — with the fixed left column always on, the map
## panel's own centre sits well right of the window's, so a window-centred
## dialog does not sit over it. Checked on the court screen; conversation_scene
## exposes the same map_panel() and GameRoot's fix reads neither by name.
func test_the_report_dialog_centres_on_the_map_panel_not_the_window() -> void:
	var r: GameRoot = await _root()
	var id := _spy_letter()
	r.on_new_missives([id])
	await wait_frames(1)
	assert_true(r.report_popup().visible)
	var map_rect: Rect2 = r.current_screen.map_panel().get_global_rect()
	var win_rect: Rect2 = r.report_popup().find_child("Window", true, false).get_global_rect()
	assert_almost_eq(win_rect.get_center().x, map_rect.get_center().x, 1.0,
		"the dialog centres on the map panel's x, not the window's")
	assert_almost_eq(win_rect.get_center().y, map_rect.get_center().y, 1.0,
		"the dialog centres on the map panel's y, not the window's")


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


## M6 (final review): play pressed while a sealed report flies to the tab
## and another waits must bank no time — the next report stops the clock
## again, and no burst of days follows its Seal. The loop is driven through
## GameRoot._process itself, the way a frame runs it.
func test_no_days_bank_behind_a_waiting_report() -> void:
	var r: GameRoot = await _root()
	var a := _spy_letter()
	var b := _spy_letter()
	r.on_new_missives([a, b])
	var day0 := Game.state.absolute_day()
	r.report_popup().seal_button().pressed.emit()   # a flies; b waits
	assert_false(r.report_popup().visible)
	Game.set_clock_speed(1)                          # play, mid-flight
	r._process(Game.data.bal("time_day_seconds") * 20.0)   # a long frame
	assert_eq(Game.state.absolute_day(), day0, "no day runs past a waiting report")
	assert_eq(r._clock_acc, 0.0, "and no time banks behind it")
	await wait_frames(30)
	assert_true(r.report_popup().visible, "b opens")
	assert_eq(Game.clock_speed, 0, "and stops the clock again")
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	Game.set_clock_speed(1)
	r._process(0.0)
	assert_eq(Game.state.absolute_day(), day0, "no burst of days after the Seal")


## M6: a spy's report that stops the clock mid-step leaves no time banked.
func test_a_spy_stop_banks_no_time() -> void:
	var r: GameRoot = await _root()
	Game.set_clock_speed(1)
	r._clock_acc = Game.data.bal("time_day_seconds") * 3.0
	r.on_new_missives([_spy_letter()])
	assert_eq(Game.clock_speed, 0)
	assert_eq(r._clock_acc, 0.0, "the stop zeroes the day's accumulator")


## M2 (final review): the news bar says when the steward's report is in.
func test_the_news_bar_says_the_stewards_report_is_in() -> void:
	var r: GameRoot = await _root()
	var id := MissiveLog.add(Game.data, Game.state, MissiveWriter.monthly(Game.data, Game.state, 3))
	watch_signals(Game)
	r.on_new_missives([id])
	var title := String(MissiveLog.find(Game.state, id)["title"])
	assert_signal_emitted_with_parameters(Game, "news_published",
		["The steward's report for %s is in." % title.get_slice(" — ", 1)])
