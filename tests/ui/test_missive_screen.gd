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
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)


func test_the_tab_opens_the_board_with_its_letters() -> void:
	Game.start_campaign(42)
	_letter("credible")
	_letter("rumour")
	var r := _root()
	await _enter(r)
	r.bottom_bar().button("MISSIVE").pressed.emit()
	await wait_process_frames(1)
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
	await wait_process_frames(1)
	var top_bar_bottom: float = r.current_screen.top_bar().get_global_rect().end.y
	var frame_top: float = r.missive_screen().find_child("Frame", true, false).get_global_rect().position.y
	assert_gte(frame_top, top_bar_bottom,
		"the board's frame (%d) clears the top bar's bottom edge (%d)" % [frame_top, top_bar_bottom])


## Board art fix round finding #1: at 1280x720 the desk's right edge (and
## CLOSE) ran past the window in board_art_v2_desk.png. With all installed
## art (the frame's texture margin, the content inset, four plaques' own
## texture-margin floor, a note's unbreakable date, the letter's inset) the
## Frame's combined minimum width must still fit inside its own offsets —
## nothing may push it wider than the design viewport.
func test_the_frame_fits_inside_the_viewport_with_all_art_installed() -> void:
	Game.start_campaign(42)
	# the real steward's report (five facts, unbreakable names like "Tax,
	# all your provinces") is the letter board_art_v2_desk.png showed cut off.
	var id := MissiveLog.add(Game.data, Game.state, MissiveWriter.monthly(Game.data, Game.state, 3))
	_letter("credible")
	_letter("consult")
	_letter("rumour")
	var r := _root()
	await _enter(r)
	get_tree().root.size = Vector2i(1280, 720)
	await wait_process_frames(2)
	r.toggle_missives()
	await wait_process_frames(1)
	r.missive_screen().select(id)
	await wait_process_frames(2)
	var frame := r.missive_screen().get_node("%Frame") as Control
	var viewport := r.get_viewport_rect().size
	var rect := frame.get_global_rect()
	assert_true(rect.position.x >= -0.5,
		"the frame's left edge (%.1f) is inside the viewport" % rect.position.x)
	assert_true(rect.end.x <= viewport.x + 0.5,
		"the frame's right edge (%.1f) fits inside the %d-wide viewport" % [rect.end.x, int(viewport.x)])
	assert_true(rect.end.y <= viewport.y + 0.5,
		"the frame's bottom edge (%.1f) fits inside the %d-tall viewport" % [rect.end.y, int(viewport.y)])


## The marshal's monthly report has a row per land regiment (spec 2026-10-07-
## army-supply-lines §5.5), far more than the desk's height: the desk scrolls
## its facts, so the frame stays inside the window and Show on map stays in
## reach (a real-window shot showed the report running off the bottom).
func test_a_long_marshal_report_scrolls_inside_the_desk() -> void:
	Game.start_campaign(42)
	var rows := SupplyLines.settle_month(Game.data, Game.state)
	var id := MissiveLog.add(Game.data, Game.state, MissiveWriter.marshal_report(Game.data, Game.state, 3, rows))
	var r := _root()
	await _enter(r)
	get_tree().root.size = Vector2i(1280, 720)
	await wait_process_frames(2)
	r.toggle_missives()
	await wait_process_frames(1)
	var ms := r.missive_screen()
	ms.select(id)
	await wait_process_frames(2)
	assert_gt(ms.get_node("%LetterFacts").get_child_count(), 8, "a row per regiment")
	var viewport := r.get_viewport_rect().size
	var frame := ms.get_node("%Frame") as Control
	assert_true(frame.get_global_rect().end.y <= viewport.y + 0.5,
		"the frame's bottom (%.1f) fits the %d-tall window" % [frame.get_global_rect().end.y, int(viewport.y)])
	var button := ms.get_node("%ShowOnMap") as Control
	assert_true(button.get_global_rect().end.y <= viewport.y + 0.5, "Show on map stays on screen")
	assert_true(ms.get_node("%LetterFacts").get_parent() is ScrollContainer, "the facts scroll")


## Plaques on one line: board_art_v3_desk.png showed "WORTH CONSULTING"
## breaking INSIDE a word ("CONSULTI / NG"), spilling a third line below the
## plaque's own box, while the other three plaques wrapped to one or two
## lines each — the four plaques (and the hints under them) sat at
## different heights. Every plaque must read on ONE line, at both the
## default design size and the smallest supported window.
func test_every_plaque_reads_on_one_line_and_all_are_the_same_height() -> void:
	Game.start_campaign(42)
	var r := _root()
	await _enter(r)
	for shape in [Vector2i(1280, 720), Vector2i(1512, 982)]:
		get_tree().root.size = shape
		await wait_process_frames(2)
		r.toggle_missives()
		await wait_process_frames(1)
		var ms := r.missive_screen()
		var heights: Array[float] = []
		for col: String in MissiveScreen.HEADERS:
			var plaque := ms.get_node("%" + col.capitalize() + "Plaque") as Label
			assert_eq(plaque.get_line_count(), 1,
				"%s reads on one line at %s (%s)" % [col, shape, plaque.text])
			heights.append(plaque.size.y)
		for h in heights:
			assert_almost_eq(h, heights[0], 0.5,
				"every plaque is the same height at %s (%s)" % [shape, heights])
		var frame := ms.get_node("%Frame") as Control
		var viewport := r.get_viewport_rect().size
		var rect := frame.get_global_rect()
		assert_true(rect.end.x <= viewport.x + 0.5,
			"the frame still fits the %s viewport (right edge %.1f)" % [shape, rect.end.x])
		r.toggle_missives()
		await wait_process_frames(1)


## Owner 2026-10-10: the tab counts letters not yet SEEN — showing the board
## sees them all (each note keeps its own unread gold edge until selected),
## and a letter landing while the board is open is seen at once.
func test_showing_the_board_sees_the_letters_and_selecting_reads_one() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.refresh_missive_badge()
	assert_eq(r.bottom_bar().badge("MISSIVE"), MissiveLog.unseen(Game.state))
	assert_gt(r.bottom_bar().badge("MISSIVE"), 0)
	r.toggle_missives()
	assert_eq(r.bottom_bar().badge("MISSIVE"), 0, "the board shown: every letter seen")
	assert_eq(r.bottom_bar().button("MISSIVE").text, "MISSIVE", "no count at none")
	assert_false(bool(MissiveLog.find(Game.state, id)["read"]), "seen is not read")
	var more := _letter("credible")
	r.refresh_missive_badge()
	assert_eq(r.bottom_bar().badge("MISSIVE"), 0, "a letter landing on the open board is seen")
	assert_false(bool(MissiveLog.find(Game.state, more)["read"]))
	r.missive_screen().select(id)
	assert_true(bool(MissiveLog.find(Game.state, id)["read"]))
	r.toggle_missives()
	_letter("rumour")
	r.refresh_missive_badge()
	assert_eq(r.bottom_bar().badge("MISSIVE"), 1, "the board shut: a new letter counts")
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
	await wait_process_frames(1)
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
	var ps := picked.get_theme_stylebox("normal")
	var os := other.get_theme_stylebox("normal")
	# with note art installed every note is an aged slip (owner 2026-09-30):
	# the one on the desk wears the gold-ruled slip, the rest the ink-ruled one
	assert_true(ps is ScaledNineSlice and os is ScaledNineSlice, "both are slips")
	assert_ne((ps as ScaledNineSlice).texture, (os as ScaledNineSlice).texture,
		"the note on the desk is ruled in gold")
	var date := CourierCard.date_of(3)
	assert_string_contains(picked.text, date.replace(" ", "\u00a0"), "the date is one unbreakable unit")
	# ...and a long one still fits a column's note (at the body's 18 px the
	# date overflowed and was clipped)
	await wait_process_frames(2)
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
	await wait_process_frames(1)
	var ms := r.missive_screen()
	assert_true(ms.visible)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("receipt", "credible", 3,
		MissiveLog.subject("regiment", "x", -1, Vector2(500, 300)), "Receipt — X", []))
	r.on_new_missives([id])
	await wait_until(func() -> bool: return ms.find_child("Note%d" % id, true, false) != null, 2.0)
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


## Main's look of 2026-09-28, adopted on the rebase: the board and the spy's
## report FLOAT, so they are windows, titled in the title face; once plaque
## art is installed it nine-slices over the plaque's rule; an empty column
## is simply empty (owner 2026-09-30).
func test_the_board_and_the_report_wear_mains_window_look() -> void:
	Game.start_campaign(42)
	var ms: MissiveScreen = load("res://scenes/screens/missive_screen.tscn").instantiate()
	var rp: MissiveReportPopup = load("res://scenes/panels/missive_report_popup.tscn").instantiate()
	add_child_autofree(ms)
	add_child_autofree(rp)
	await wait_process_frames(1)
	var title_font := UiPalette.role_font("title")
	assert_eq(ms.get_node("%Title").get_theme_font("font"), title_font, "the board's title is a title")
	assert_eq(rp.get_node("%ReportTitle").get_theme_font("font"), title_font, "the report's title is a title")
	assert_true((ms.get_node("%TruthPlaque") as Label).get_theme_stylebox("normal") is ScaledNineSlice,
		"the plaque is its carved art")
	ms.refresh()
	assert_eq(ms.get_node("%ConsultNotes").get_child_count(), 0, "no description under an empty column")


## The desk is cream parchment and the notes aged slips, so their words are
## the letter's dark ink (missive_ink): the theme's MissiveLetter*,
## MissiveFact and MissiveNote kinds. _fill_desk makes the fact labels every
## call, so a second fill must ink its fresh labels too.
func test_the_desk_and_the_notes_write_in_the_letters_ink() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var ms: MissiveScreen = load("res://scenes/screens/missive_screen.tscn").instantiate()
	add_child_autofree(ms)
	ms.select(id)
	var ink := MapPalette.named(Game.data, "missive_ink")
	assert_eq(ms.get_node("%LetterTitle").get_theme_color("font_color"), ink, "the title")
	assert_eq(ms.get_node("%LetterMeta").get_theme_color("font_color"), ink,
		"the meta line in the letter's own ink (owner 2026-09-30: the paler grey read out of place)")
	var fact := ms.get_node("%LetterFacts").get_child(0) as Label
	assert_eq(fact.get_theme_color("font_color"), ink, "a fact, freshly created by _fill_desk")
	ms.select(-1)
	ms.select(id)
	var fact2 := ms.get_node("%LetterFacts").get_child(0) as Label
	assert_ne(fact2, fact, "a fresh label from the second fill, not the first's")
	assert_eq(fact2.get_theme_color("font_color"), ink, "still inked after a second fill")
	var note := ms.find_child("Note%d" % id, true, false) as Button
	assert_eq(note.get_theme_color("font_color"), ink, "the note on the desk is a slip in the same ink")
	var lit := note.get_theme_stylebox("normal") as ScaledNineSlice
	assert_eq(lit, MissiveScreen.NOTE_LIT, "the gold-ruled slip")


func test_a_receipt_on_the_desk_wears_the_delivered_painting() -> void:
	Game.start_campaign(42)
	var subj := MissiveLog.subject("point", "", -1, Vector2(500, 300))
	var receipt := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("receipt", "credible", 3, subj, "Receipt", []))
	var monthly := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("monthly", "truth", 3, subj, "Steward's report", []))
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	await wait_process_frames(1)
	var ms := r.missive_screen()
	ms.select(receipt)
	assert_true(ms.desk_painting().visible, "a receipt shows the rider at the camp")
	assert_true(ms.desk_painting().clip_contents, "a covered painting never spills out of its box")
	ms.select(monthly)
	assert_false(ms.desk_painting().visible, "other letters show none")


## Desk painting aspect fix: the box was a fixed 150 design px tall
## regardless of its own (flexible, per-screen-width) column — far wider and
## shallower than delivered.png's 5:4, so the cover-crop cut the mounted
## courier's head off (card-look-report.md, desk_receipt.png). The box's
## height now follows its OWN width at ui_missive_desk_painting_aspect.
func test_the_desk_paintings_height_follows_its_width_at_the_aspect_key() -> void:
	Game.start_campaign(42)
	var subj := MissiveLog.subject("point", "", -1, Vector2(500, 300))
	var receipt := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("receipt", "credible", 3, subj, "Receipt", []))
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	await wait_process_frames(1)
	var ms := r.missive_screen()
	ms.select(receipt)
	await wait_process_frames(3)
	var painting := ms.desk_painting()
	assert_true(painting.visible, "the receipt shows its painting")
	var aspect := Game.data.bal("ui_missive_desk_painting_aspect")
	assert_almost_eq(painting.size.y, painting.size.x / aspect, 1.0,
		"the box's height (%.1f) follows its own width (%.1f) at the aspect key (%.2f)" %
			[painting.size.y, painting.size.x, aspect])


## Final review M1 (LEDGER M3): an audit letter is about the LEDGER's books,
## not a place — its button opens the LEDGER on a lens that draws the flow.
func test_an_audit_letter_opens_the_ledger() -> void:
	Game.start_campaign(42)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("audit", "credible", 3,
		MissiveLog.subject("ledger", "supply_line", -1, Vector2.ZERO), "Audit — The supply lines",
		[MissiveLog.exact("total", "In all, this month", 5)]))
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(id)
	assert_eq(ms.show_on_map_button().text, "Open the LEDGER")
	ms.show_on_map_button().pressed.emit()
	await wait_process_frames(1)
	assert_false(ms.visible)
	assert_true(r.ledger_screen().visible, "the LEDGER opened")
	assert_eq(r.ledger_screen().lens(), "war", "on the first lens that draws the supply lines")
	r.ledger_screen().close()
	ms.select(_letter("credible"))
	assert_eq(ms.show_on_map_button().text, "Show on map", "a letter about a place keeps its words")
