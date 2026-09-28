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


## Fix round 1 finding 5: the board's frame used a fixed 48 px top margin,
## shorter than the court screen's own two-line TopBar, so it covered the
## lower half of the purse row.
func test_the_frame_sits_below_the_top_bar() -> void:
	Game.start_campaign(42)
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	await wait_frames(1)
	var top_bar_bottom: float = r.current_screen.top_bar().get_global_rect().end.y
	var frame_top: float = r.missive_screen().find_child("Frame", true, false).get_global_rect().position.y
	assert_gte(frame_top, top_bar_bottom,
		"the board's frame (%d) clears the top bar's bottom edge (%d)" % [frame_top, top_bar_bottom])


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


## Task 10's look check (2026-09-28): the letter on the desk looked like any
## other read note, and a note's date broke as "Spring 30, Year / 1".
func test_the_selected_note_stands_out_and_its_date_never_breaks() -> void:
	Game.start_campaign(42)
	var a := _letter("credible")
	var b := _letter("credible")
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(a)
	MissiveLog.mark_read(Game.state, b)
	ms.refresh()
	var picked := ms.find_child("Note%d" % a, true, false) as Button
	var other := ms.find_child("Note%d" % b, true, false) as Button
	var ps := picked.get_theme_stylebox("normal") as StyleBoxFlat
	var os := other.get_theme_stylebox("normal") as StyleBoxFlat
	assert_ne(ps.bg_color, os.bg_color, "the note on the desk is lit")
	var date := CourierCard.date_of(3)
	assert_string_contains(picked.text, date.replace(" ", "\u00a0"), "the date is one unbreakable unit")
	# ...and a long one still fits a column's note (at the body's 18 px the
	# date overflowed and was clipped)
	await wait_frames(2)
	var font := picked.get_theme_font("font")
	var px := picked.get_theme_font_size("font_size")
	var room := picked.size.x - ps.content_margin_left - ps.content_margin_right
	var widest := font.get_string_size("Autumn 90, Year 60", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_lt(widest, room, "the longest date fits a note (%d of %d px)" % [widest, room])


## M4 (final review): an open board takes a letter in as it lands — the
## clock can run with the board up, and it used to refresh only on showing.
func test_an_open_board_takes_in_a_letter_as_it_lands() -> void:
	Game.start_campaign(42)
	var keep_fly: Variant = Game.data.balance.get("missive_fly_s")
	Game.data.balance["missive_fly_s"] = 0.05
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	await wait_frames(1)
	var ms := r.missive_screen()
	assert_true(ms.visible)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("receipt", "credible", 3,
		MissiveLog.subject("regiment", "x", -1, Vector2(500, 300)), "Receipt — X", []))
	r.on_new_missives([id])
	await wait_frames(30)
	Game.data.balance["missive_fly_s"] = keep_fly
	assert_not_null(ms.find_child("Note%d" % id, true, false), "the landed letter is on the open board")


## M7 (final review): reading a letter is a state change, so it goes
## through Game (Game.mark_missive_read), never by the screen writing
## Game.state itself.
func test_reading_a_letter_goes_through_game() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	watch_signals(Game)
	r.missive_screen().select(id)
	assert_signal_emitted_with_parameters(Game, "missive_read", [id])
	assert_true(bool(MissiveLog.find(Game.state, id)["read"]))
