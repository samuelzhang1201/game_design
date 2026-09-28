extends GutTest
## The Missive board screen (spec 2026-09-28-missive-board-and-spies §2,
## Task 7): four credibility columns, a reading desk, Show on map.

var _keep_before: Variant


func before_each() -> void:
	_keep_before = Game.data.balance.get("missive_keep_per_column")


func after_each() -> void:
	if _keep_before != null:
		Game.data.balance["missive_keep_per_column"] = _keep_before


func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r


func _letter(column: String) -> int:
	return MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", column, 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "A letter",
		[MissiveLog.span("people", "People", 2800, 3200)]))


func _enter(r: GameRoot) -> void:
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)


func test_the_tab_opens_the_board_with_its_letters() -> void:
	Game.start_campaign(42)
	_letter("credible")
	_letter("rumour")
	var r := _root()
	await _enter(r)
	r.bottom_bar().button("MISSIVE").pressed.emit()
	await wait_frames(1)
	var ms := r.missive_screen()
	assert_true(ms.visible)
	assert_eq(ms.notes_in("credible"), 1)
	assert_eq(ms.notes_in("rumour"), 1)
	assert_eq(ms.notes_in("truth"), 0)


func test_selecting_a_letter_reads_it_and_the_badge_follows() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.refresh_missive_badge()
	assert_eq(r.bottom_bar().badge("MISSIVE"), 1)
	r.toggle_missives()
	r.missive_screen().select(id)
	assert_true(bool(MissiveLog.find(Game.state, id)["read"]))
	assert_eq(r.bottom_bar().badge("MISSIVE"), 0)
	assert_string_contains(r.missive_screen().desk_text(), "2,800–3,200")


func test_show_on_map_closes_the_board() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(id)
	watch_signals(ms)
	ms.show_on_map_button().pressed.emit()
	assert_signal_emitted(ms, "show_requested")
	await wait_frames(1)
	assert_false(ms.visible)


func test_a_capped_away_letter_empties_the_desk() -> void:
	Game.start_campaign(42)
	Game.data.balance["missive_keep_per_column"] = 1.0
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(id)
	_letter("credible")
	ms.refresh()
	assert_eq(ms.selected(), -1)
	assert_string_contains(ms.desk_text(), "Choose a letter")
