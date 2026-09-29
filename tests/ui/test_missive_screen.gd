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
	await wait_frames(2)
	r.toggle_missives()
	await wait_frames(1)
	r.missive_screen().select(id)
	await wait_frames(2)
	var frame := r.missive_screen().get_node("%Frame") as Control
	var viewport := r.get_viewport_rect().size
	var rect := frame.get_global_rect()
	assert_true(rect.position.x >= -0.5,
		"the frame's left edge (%.1f) is inside the viewport" % rect.position.x)
	assert_true(rect.end.x <= viewport.x + 0.5,
		"the frame's right edge (%.1f) fits inside the %d-wide viewport" % [rect.end.x, int(viewport.x)])
	assert_true(rect.end.y <= viewport.y + 0.5,
		"the frame's bottom edge (%.1f) fits inside the %d-tall viewport" % [rect.end.y, int(viewport.y)])


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
	var ps := picked.get_theme_stylebox("normal")
	var os := other.get_theme_stylebox("normal")
	# board art fix round finding #5's install: with note art installed, an
	# UNSELECTED note now wears the pinned-parchment texture instead of a
	# flat chip — the selected one still keeps the flat lit style (fix round
	# 1: "the selection still shows over parchment"), so the two are simply
	# different STYLEBOX TYPES now, not just different bg_colors.
	if MissiveArt.texture(Game.data, "note") != null:
		assert_true(ps is StyleBoxFlat, "the selected note keeps the flat lit style")
		assert_true(os is StyleBoxTexture, "an unselected note wears the pinned-parchment art")
	else:
		assert_true(ps is StyleBoxFlat and os is StyleBoxFlat)
		assert_ne((ps as StyleBoxFlat).bg_color, (os as StyleBoxFlat).bg_color, "the note on the desk is lit")
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


## Main's look of 2026-09-28, adopted on the rebase: the board and the spy's
## report FLOAT, so they are windows (the ornament, under
## ui_panel_ornament 3, marks windows only), titled in the title face; the
## board's column plaques are section headers.
func test_the_board_and_the_report_wear_mains_window_look() -> void:
	var keep: float = Game.data.balance.get("ui_panel_ornament", 1.0)
	Game.data.balance["ui_panel_ornament"] = 3.0
	Game.start_campaign(42)
	var ms: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	var rp: MissiveReportPopup = load("res://scenes/missive_report_popup.tscn").instantiate()
	add_child_autofree(ms)
	add_child_autofree(rp)
	await wait_frames(1)
	Game.data.balance["ui_panel_ornament"] = keep
	# board art follow-up: frame/letter art is now installed on this branch,
	# so the panel wears its own nine-sliced piece instead of the vellum
	# ornament — check whichever the current data actually names.
	for entry in [{"panel": ms.get_node("%Frame"), "key": "frame"},
			{"panel": rp.get_node("%Window"), "key": "letter"}]:
		var panel: Control = entry["panel"]
		if MissiveArt.texture(Game.data, String(entry["key"])) != null:
			assert_true(panel.get_theme_stylebox("panel") is StyleBoxTexture,
				"%s wears its installed piece art" % panel.name)
		else:
			var style := panel.get_theme_stylebox("panel") as VellumPanelStyle
			assert_not_null(style, "%s is a leather panel" % panel.name)
			if style != null and UiPalette.load_art(UiPalette.PANEL_ORNAMENT_PATH) != null:
				assert_not_null(style.texture, "%s is a window: it wears the ornament" % panel.name)
	var title_font := UiPalette.role_font("title")
	assert_eq(ms.get_node("%Title").get_theme_font("font"), title_font, "the board's title is a title")
	assert_eq(rp.get_node("%ReportTitle").get_theme_font("font"), title_font, "the report's title is a title")
	var plaque := ms.get_node("%TruthPlaque") as Label
	assert_eq(plaque.get_theme_font("font"), UiPalette.role_font("header"), "a plaque is a section header")
	assert_eq(plaque.get_theme_color("font_color"), MapPalette.named(Game.data, "intel_truth"),
		"in its column's own colour")
	# fix round 1: MissiveArt's fallback must be the rule style_section already
	# set, not a blank StyleBoxEmpty that erases it — with no plaque art
	# installed, the gold rule (and its spacing) must still be there.
	# Board art follow-up: plaque art is now installed on this branch, so the
	# rule is already superseded by a StyleBoxTexture — check whichever the
	# current data actually names, same as the frame/window check above.
	var rule_alpha := float(Game.data.balance.get("ui_section_rule_alpha", 0.0))
	var got := plaque.get_theme_stylebox("normal")
	if MissiveArt.texture(Game.data, "plaque") != null:
		assert_true(got is StyleBoxTexture, "installed plaque art nine-slices over the rule")
	elif rule_alpha > 0.0:
		var ref := Label.new()
		UiPalette.style_section(ref, MissiveScreen.PLAQUE_FONT_SIZE, MapPalette.named(Game.data, "intel_truth"))
		var want := ref.get_theme_stylebox("normal") as StyleBoxFlat
		assert_true(got is StyleBoxFlat, "with no plaque art installed the plaque keeps its gold section rule")
		if got is StyleBoxFlat and want != null:
			assert_eq((got as StyleBoxFlat).border_color, want.border_color, "same rule colour")
			assert_eq((got as StyleBoxFlat).border_width_bottom, want.border_width_bottom, "same rule width")
			assert_eq((got as StyleBoxFlat).content_margin_bottom, want.content_margin_bottom, "same rule spacing")
		ref.queue_free()
	else:
		assert_false(got is StyleBoxTexture, "no rule configured and no art installed: nothing to nine-slice")
	# the desk had no panel style before this task; with no letter art
	# installed it must stay fully transparent, not gain a border/inset —
	# board art follow-up: letter art is now installed on this branch, so
	# the desk wears its own nine-sliced parchment instead.
	if MissiveArt.texture(Game.data, "letter") != null:
		assert_true(ms.get_node("%Desk").get_theme_stylebox("panel") is StyleBoxTexture,
			"the desk wears its installed parchment")
	else:
		assert_true(ms.get_node("%Desk").get_theme_stylebox("panel") is StyleBoxEmpty,
			"the desk stays transparent until its parchment art is installed")
	# once art IS installed, the plaque nine-slices over the rule.
	var saved_plaque := String(Game.data.missive_art.get("plaque", ""))
	Game.data.missive_art["plaque"] = "res://icon.png"
	var ms2: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(ms2)
	var plaque2 := ms2.get_node("%TruthPlaque") as Label
	assert_true(plaque2.get_theme_stylebox("normal") is StyleBoxTexture,
		"installed plaque art nine-slices over the rule")
	Game.data.missive_art["plaque"] = saved_plaque
	# an empty column's hint is an aside, no larger than the notes beside it
	ms.refresh()
	var hint := ms.get_node("%ConsultNotes").get_child(0) as Label
	assert_eq(hint.get_theme_font_size("font_size"), MissiveScreen.NOTE_FONT_SIZE, "the hint is note-sized")
	# Board art follow-up: once the frame's wood is installed, the hint sits
	# on its cream opening and needs dark ink instead of the theme's dim one.
	if MissiveArt.texture(Game.data, "frame") != null:
		assert_eq(hint.get_theme_color("font_color"), MapPalette.named(Game.data, "missive_ink_soft"),
			"reads on the frame's cream opening")
	else:
		assert_eq(hint.get_theme_color("font_color"), UiPalette.TEXT_DIM, "and dim")


## Board art follow-up: with the letter parchment installed, the desk's
## title/meta/facts must use dark ink (missive_ink/_soft) instead of the
## theme's light ink, which is unreadable on cream; without it, unchanged.
## _fill_desk re-creates the fact labels every call, so each call must
## re-apply the colour, not just the first.
func test_ink_on_parchment_once_the_letter_art_is_installed() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var saved := String(Game.data.missive_art.get("letter", ""))

	Game.data.missive_art["letter"] = ""
	var plain: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(plain)
	plain.select(id)
	assert_eq(plain.get_node("%LetterMeta").get_theme_color("font_color"), UiPalette.TEXT_MUTED,
		"unchanged without letter art")
	var plain_fact := plain.get_node("%LetterFacts").get_child(0) as Label
	assert_false(plain_fact.has_theme_color_override("font_color"), "the theme's own colour, untouched")

	Game.data.missive_art["letter"] = "res://icon.png"
	var inked: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(inked)
	inked.select(id)
	var ink := MapPalette.named(Game.data, "missive_ink")
	var ink_soft := MapPalette.named(Game.data, "missive_ink_soft")
	assert_eq(inked.get_node("%LetterTitle").get_theme_color("font_color"), ink, "the title")
	assert_eq(inked.get_node("%LetterMeta").get_theme_color("font_color"), ink_soft, "the meta line")
	var inked_fact := inked.get_node("%LetterFacts").get_child(0) as Label
	assert_eq(inked_fact.get_theme_color("font_color"), ink, "a fact, freshly created by _fill_desk")
	# re-select (a fresh set of fact labels) to prove the colour is applied
	# every time, not just the first _fill_desk call. Board art fix round
	# finding #3: _fill_desk only queue_free()d the old facts, so without
	# remove_child() first, get_child(0) right after re-filling could still
	# read the FIRST call's (already-inked) label — assert instance
	# inequality too, so a regression here cannot pass by reading stale data.
	inked.select(-1)
	inked.select(id)
	var inked_fact2 := inked.get_node("%LetterFacts").get_child(0) as Label
	assert_ne(inked_fact2, inked_fact, "a fresh label from the second fill, not the first's")
	assert_eq(inked_fact2.get_theme_color("font_color"), ink, "still inked after a second fill")

	Game.data.missive_art["letter"] = saved


## Board art fix round finding #4: with the frame's carved wood installed
## the "Missives" title sits on its cream opening, where gold (the theme's
## default title colour) reads faint. Plaques and CLOSE are unaffected —
## the plaques already read well on the dark plaque art, and CLOSE is a
## button, not text on the wood.
func test_the_title_inks_over_the_frames_cream_opening_once_installed() -> void:
	var saved := String(Game.data.missive_art.get("frame", ""))

	Game.data.missive_art["frame"] = ""
	var plain: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(plain)
	assert_eq(plain.get_node("%Title").get_theme_color("font_color"), UiPalette.GOLD,
		"unchanged without frame art")

	Game.data.missive_art["frame"] = "res://icon.png"
	var framed: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(framed)
	assert_eq(framed.get_node("%Title").get_theme_color("font_color"),
		MapPalette.named(Game.data, "missive_ink"), "reads on the frame's cream opening")

	Game.data.missive_art["frame"] = saved


## Board art fix round finding #5 (the install look check): an unselected
## note's title/date kept the theme's light chip text, unreadable once the
## note wears the pale parchment art — dark ink stands in, the same pattern
## as the desk. The selected note keeps its flat lit chip and default text.
func test_an_unselected_note_inks_over_installed_parchment() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var saved := String(Game.data.missive_art.get("note", ""))

	Game.data.missive_art["note"] = ""
	var plain: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(plain)
	plain.refresh()
	var plain_note := plain.find_child("Note%d" % id, true, false) as Button
	assert_false(plain_note.has_theme_color_override("font_color"), "unchanged without note art")

	Game.data.missive_art["note"] = "res://icon.png"
	var inked: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(inked)
	inked.refresh()
	var inked_note := inked.find_child("Note%d" % id, true, false) as Button
	assert_eq(inked_note.get_theme_color("font_color"), MapPalette.named(Game.data, "missive_ink"),
		"reads on the installed parchment")
	inked.select(id)
	var selected_note := inked.find_child("Note%d" % id, true, false) as Button
	assert_false(selected_note.has_theme_color_override("font_color"),
		"the selected note keeps its flat lit chip and default text")

	Game.data.missive_art["note"] = saved


func test_a_receipt_on_the_desk_wears_the_delivered_painting() -> void:
	Game.start_campaign(42)
	var saved := String(Game.data.courier_paintings.get("delivered", ""))
	Game.data.courier_paintings["delivered"] = "res://icon.png"
	var subj := MissiveLog.subject("point", "", -1, Vector2(500, 300))
	var receipt := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("receipt", "credible", 3, subj, "Receipt", []))
	var monthly := MissiveLog.add(Game.data, Game.state,
		MissiveLog.make("monthly", "truth", 3, subj, "Steward's report", []))
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	await wait_frames(1)
	var ms := r.missive_screen()
	ms.select(receipt)
	assert_true(ms.desk_painting().visible, "a receipt shows the rider at the camp")
	assert_true(ms.desk_painting().clip_contents, "a covered painting never spills out of its box")
	ms.select(monthly)
	assert_false(ms.desk_painting().visible, "other letters show none")
	Game.data.courier_paintings["delivered"] = saved
