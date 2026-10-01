extends GutTest
## The WAR ROOM tab opens the plotting room over the map (spec 2026-10-01 §1, §5).

## The court on a fresh reign, as Start Game begins it but without the
## opening narration's screen, which no test here needs.
func _court() -> GameRoot:
	Game.start_campaign(44)   # the seed Start Game begins
	Game.next_tick()
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	return r


func test_war_room_is_no_longer_a_placeholder() -> void:
	assert_false("WAR ROOM" in BottomBar.PLACEHOLDER_TABS)


func test_the_tab_lays_the_home_provinces_sheet_over_the_map() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_seconds(Game.data.bal("war_report_roll_s") + 0.1)   # the room widens over that time
	var screen := r.war_room_screen()
	assert_true(screen.visible)
	var map: Control = r.current_screen.map_panel()
	var column: Control = r.current_screen.left_column()
	var wide := Rect2(column.global_position, Vector2(map.global_position.x + map.size.x - column.global_position.x, map.size.y))
	assert_eq(screen.size, wide.size, "the room runs from the column's left edge to the map's right edge")
	assert_eq(screen.position, Vector2(column.global_position.x, map.global_position.y))
	var home := MapManors.home_province(Game.data, Game.state)
	var row: Dictionary = Game.data.provinces[home]
	var at := Vector2(float(row["center_x"]), float(row["center_y"]))
	assert_eq(screen.view().sheet_index(), WarSheets.sheet_of(Game.data, at))


func test_the_tab_again_closes_it_and_another_tab_closes_it_too() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	assert_false(r.war_room_screen().visible)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_process_frames(2)
	assert_false(r.war_room_screen().visible)
	assert_true(r.ledger_screen().visible)


func test_a_picked_piece_unrolls_its_card_over_the_room_and_closing_gives_it_back() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	var home := detail.get_parent()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	screen.view().piece_selected.emit(code)
	await wait_process_frames(1)
	var card := MapObjects.army_card(Game.data, code, Game.state)
	assert_eq(detail.get_parent(), screen.card_roll(), "the card is borrowed into the room's roll")
	assert_eq(UiPalette.card_ground(detail), UiPalette.card_ground(home), "its scroll fades into the same paper as in the column")
	assert_true(screen.card_roll().visible)
	assert_eq(detail.title_label().text, String(card["title"]))
	# the BODY is there too, not only the title: a regiment's stat rows
	assert_gt((card["stats"] as Array).size(), 0, "the fixture card has stats")
	assert_gt(detail.stats_grid().get_child_count(), 0, "the stat rows are there")
	await wait_seconds(Game.data.bal("war_report_roll_s") + 0.2)
	var roll := screen.card_roll()
	var body := detail.stats_grid().get_combined_minimum_size().y
	assert_gt(detail.content_height(), detail.get_combined_minimum_size().y + body * 0.9, "the card's height counts its scrolled body")
	assert_gt(roll.size.y, detail.get_combined_minimum_size().y + body * 0.9, "unrolled past the pinned parts: the body shows")
	var folio := screen.get_node("%Folio") as Control
	assert_gte(folio.get_global_rect().position.x, roll.get_global_rect().end.x, "the folio stands clear of the card")
	screen.close()
	assert_eq(detail.get_parent(), home, "given back to the column")
	assert_almost_eq(folio.offset_left, 0.0, 0.01, "and the folio has the room again")
	assert_false(detail.has_content())


func test_clearing_the_pick_rolls_the_card_away_and_gives_it_back() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	var home := detail.get_parent()
	var index := detail.get_index()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	screen.view().piece_selected.emit(code)
	await wait_process_frames(1)
	screen.view().clear_selection()
	await wait_seconds(Game.data.bal("war_report_roll_s") + 0.2)
	assert_eq(detail.get_parent(), home)
	assert_eq(detail.get_index(), index, "at its old place among the column's cards")
	assert_false(screen.card_roll().visible)


func test_after_the_room_the_courts_own_card_still_lands_in_the_column() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	screen.view().piece_selected.emit(code)
	await wait_process_frames(1)
	screen.close()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	detail.show_card(MapObjects.army_card(Game.data, code, Game.state))
	await wait_process_frames(1)
	assert_true(detail.is_visible_in_tree(), "the column shows the card again")
	assert_true(r.current_screen.left_column().is_ancestor_of(detail))


func test_opening_the_room_withdraws_an_aim_armed_on_the_map() -> void:
	var r: GameRoot = await _court()
	var map_orders := r.current_screen.find_child("ArmyOrders", true, false) as ArmyOrderMenu
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	Game.set_clock_speed(0)
	assert_eq(map_orders.aim_for(code), "", "the aim is armed on a paused clock")
	assert_eq(map_orders.aiming(), code)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	assert_eq(map_orders.aiming(), "")


func test_closing_the_room_lets_its_selection_go() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var view := r.war_room_screen().view()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	view._selected = code
	r.war_room_screen().close()
	assert_eq(view.selected_army(), "")


func test_an_out_of_range_sheet_is_ignored() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var was := screen.view().sheet_index()
	screen.lay_sheet(-1)
	screen.lay_sheet(9999)
	assert_eq(screen.view().sheet_index(), was)


func test_a_regiment_on_another_sheet_is_listed_and_its_row_lays_that_sheet() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var off := WarRoom.off_sheet(Game.data, Game.state, screen.view().sheet_index())
	if off.is_empty():
		pass_test("every regiment stands on the home sheet in this pack")
		return
	var rows := screen.get_node("%Margin").get_children().filter(func(n: Node) -> bool: return n is Button)
	assert_eq(rows.size(), off.size())
	(rows[0] as Button).pressed.emit()
	_roll(screen.view())
	await wait_process_frames(2)
	assert_eq(screen.view().sheet_index(), int(off[0]["sheet"]))


## Run the roll-up's seconds at once, as the clock would over time.
func _roll(view: WarRoomView) -> void:
	view._process(10.0)


func test_the_rake_on_a_running_clock_says_why_and_arms_nothing() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	Game.set_clock_speed(1)
	var screen := r.war_room_screen()
	var code := String(WarRoom.on_sheet(Game.data, Game.state, screen.view().sheet_index())[0]["code"])
	watch_signals(Game)
	screen.view().rake_started.emit(code)
	Game.set_clock_speed(0)
	assert_eq(screen.orders().aiming(), "")
	assert_signal_emitted(Game, "news_published", "the reason is published")


func test_a_committed_rake_plants_a_pennant_with_a_riding_slip() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	Game.set_clock_speed(0)
	var screen := r.war_room_screen()
	var p: Dictionary = {}
	for q: Dictionary in WarRoom.on_sheet(Game.data, Game.state, screen.view().sheet_index()):
		if not bool(q["naval"]):
			p = q
			break
	var code := String(p["code"])
	screen.view().rake_started.emit(code)
	assert_eq(screen.orders().aiming(), code)
	var to: Vector2 = (p["at"] as Vector2) + Vector2(6.0, 0.0)
	if MapEconomy.cell_at(Game.data, to) < 0:
		to = (p["at"] as Vector2) + Vector2(0.0, 6.0)
	screen.view().ground_clicked.emit(to, Vector2(100, 100))
	screen.orders().id_pressed.emit(ArmyOrderMenu.COMMIT)
	await wait_process_frames(2)
	assert_eq(String(WarRoom.pennant_of(Game.data, Game.state, code).get("status", "")), "riding")
	var pennants: WarPennants = screen.view().get_node("%Pennants")
	assert_not_null(pennants.get_node_or_null(NodePath(code)))


func _real_press(view: WarRoomView, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	view._gui_input(e)


func _land_piece(screen: WarRoomScreen) -> Dictionary:
	for q: Dictionary in WarRoom.on_sheet(Game.data, Game.state, screen.view().sheet_index()):
		if not bool(q["naval"]):
			return q
	return {}


## A land point of the sheet, at least war_rake_min_px + 4 design px from `at` on the screen.
func _land_near(screen: WarRoomScreen, at: Vector2) -> Vector2:
	var from: Vector2 = screen.view().screen_pos_of_px(at)
	for k: float in [6.0, 12.0, 24.0, 40.0]:
		for d: Vector2 in [Vector2(-k, 0), Vector2(0, -k), Vector2(k, 0), Vector2(0, k)]:
			var scr: Variant = screen.view().screen_pos_of_px(at + d)
			if scr != null and MapEconomy.cell_at(Game.data, at + d) >= 0 \
					and (scr as Vector2).distance_to(from) >= Game.data.bal("war_rake_min_px") + 4.0 \
					and screen.view().pack_at(scr).x >= 0.0:
				return at + d
	return at


func test_a_real_drag_from_a_piece_commits_a_march_and_plants_a_riding_pennant() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(3)
	Game.set_clock_speed(0)
	var screen := r.war_room_screen()
	var view := screen.view()
	var p := _land_piece(screen)
	var code := String(p["code"])
	var from: Vector2 = view.screen_pos_of_px(p["at"])
	var to: Vector2 = view.screen_pos_of_px(_land_near(screen, p["at"]))
	_real_press(view, from, true)
	var e := InputEventMouseMotion.new()
	e.position = to
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(e)
	assert_eq(screen.orders().aiming(), code, "the drag armed the march")
	_real_press(view, to, false)
	assert_true(screen.orders().pending().x >= 0.0, "the release named a destination and asked COMMIT / CANCEL")
	screen.orders().id_pressed.emit(ArmyOrderMenu.COMMIT)
	await wait_process_frames(2)
	assert_eq(String(WarRoom.pennant_of(Game.data, Game.state, code).get("status", "")), "riding")
	assert_not_null((view.get_node("%Pennants") as WarPennants).pennant(code))


func test_a_click_on_a_riding_pennant_opens_edit_route_and_cancel_march() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(3)
	Game.set_clock_speed(0)
	var screen := r.war_room_screen()
	var view := screen.view()
	var p := _land_piece(screen)
	var code := String(p["code"])
	var to := _land_near(screen, p["at"])
	screen.orders().aim_for(code)
	view.ground_clicked.emit(to, Vector2(100, 100))
	screen.orders().id_pressed.emit(ArmyOrderMenu.COMMIT)
	await wait_process_frames(2)
	var hit: Dictionary = (view.get_node("%Pennants") as WarPennants).screen_hits(
		view.get_node("%Camera"), view.window_scale())[0]
	var at := (hit["rect"] as Rect2).get_center()
	_real_press(view, at, true)
	_real_press(view, at, false)
	var menu := screen.orders()
	assert_gte(menu.get_item_index(ArmyOrderMenu.EDIT), 0, "Edit route is offered over a march whose courier still rides")
	assert_gte(menu.get_item_index(ArmyOrderMenu.HALT), 0, "and Cancel march")
	assert_false(menu.is_item_disabled(menu.get_item_index(ArmyOrderMenu.HALT)), "Cancel march can be chosen")


func test_a_rake_released_off_the_table_withdraws_the_armed_march() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(3)
	Game.set_clock_speed(0)
	var screen := r.war_room_screen()
	var view := screen.view()
	var p := _land_piece(screen)
	var from: Vector2 = view.screen_pos_of_px(p["at"])
	_real_press(view, from, true)
	var e := InputEventMouseMotion.new()
	e.position = from + Vector2(50, 0)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(e)
	assert_eq(screen.orders().aiming(), String(p["code"]))
	_real_press(view, Vector2(-50, -50), false)
	assert_eq(screen.orders().aiming(), "")


func test_a_sheet_roll_withdraws_a_rake_in_hand_s_armed_march() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(3)
	Game.set_clock_speed(0)
	var screen := r.war_room_screen()
	var view := screen.view()
	var p := _land_piece(screen)
	var from: Vector2 = view.screen_pos_of_px(p["at"])
	_real_press(view, from, true)
	var e := InputEventMouseMotion.new()
	e.position = from + Vector2(50, 0)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(e)
	assert_eq(screen.orders().aiming(), String(p["code"]))
	view.swap_to((view.sheet_index() + 1) % WarSheets.series(Game.data).size())
	assert_eq(screen.orders().aiming(), "")


func test_the_margin_slip_is_a_scrolling_slip_of_at_most_war_margin_rows() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(3)
	var screen := r.war_room_screen()
	var scroll := screen.get_node("%MarginScroll") as ScrollContainer
	var rows := screen.get_node("%Margin").get_children().filter(func(n: Node) -> bool: return n is Button)
	var row_h := (rows[0] as Control).get_combined_minimum_size().y if not rows.is_empty() else 0.0
	assert_almost_eq(scroll.custom_minimum_size.y, row_h * minf(float(rows.size()), Game.data.bal("war_margin_rows")), 0.5)
	# the slip hangs off the screen's top-left, under the title, never from the bottom
	var slip := screen.get_node("%Slip") as Control
	assert_lt(slip.position.y, screen.size.y * 0.25)
	assert_lt(slip.position.x, screen.size.x * 0.2)


func test_a_new_graphics_tier_reaches_the_room_and_the_folio() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var want := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}
	for tier: String in ["low", "ultra"]:
		screen.set_tier(tier)
		var msaa: int = want[int(Map3DQuality.num(Map3DQuality.row(Game.data, tier), "msaa", 0.0))]
		assert_eq((screen.view().get_node("%Viewport") as SubViewport).msaa_3d, msaa, tier + ": the room")
		assert_eq((screen.get_node("%Folio").get_node("%FigViewport") as SubViewport).msaa_3d, msaa, tier + ": the figure")



func test_the_margin_keeps_its_buttons_while_the_list_stands_and_refills_on_reopen() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var box := screen.get_node("%Margin")
	var first := box.get_children()
	screen._fill_margin()
	assert_eq(box.get_children(), first, "an unchanged list keeps the very same buttons")
	# shut, a regiment walks onto another sheet, and the room opens again
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(1)
	var sheet := screen.view().sheet_index()
	var mover := ""
	for p: Dictionary in WarRoom.on_sheet(Game.data, Game.state, sheet):
		if not bool(p["naval"]):
			mover = String(p["code"])
			break
	assert_ne(mover, "")
	var far := -1
	for i in WarSheets.series(Game.data).size():
		var rect: Rect2 = WarSheets.series(Game.data)[i]["rect"]
		if WarSheets.sheet_of(Game.data, rect.get_center()) == i and i != sheet:
			far = i
			break
	ArmySystem.ensure(Game.data, Game.state)
	var m := ArmySystem.pack_to_metres(Game.data, (WarSheets.series(Game.data)[far]["rect"] as Rect2).get_center())
	Game.state.regiments[mover]["x_m"] = m.x
	Game.state.regiments[mover]["y_m"] = m.y
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var texts: Array = box.get_children().filter(func(n: Node) -> bool: return n is Button) \
		.map(func(b: Button) -> String: return b.text)
	var label := String(ArmySystem.regiment(Game.data, mover).get("label", mover))
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with(label)), "%s is in the margin now" % label)


func test_closing_the_room_hands_the_column_its_place_back() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	r.war_room_screen().close()
	await wait_process_frames(1)
	assert_false(r.war_room_screen().visible)
	assert_true(r.current_screen.left_column().is_visible_in_tree())


func test_the_easel_shows_the_missive_board_and_a_note_opens_the_full_board_over_the_room() -> void:
	var r: GameRoot = await _court()
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "A letter", []))
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var board := screen.board_screen()
	assert_not_null(board)
	assert_true(board.board_only())
	assert_not_null(board.find_child("Note%d" % id, true, false), "the easel carries the real letters")
	board.note_chosen.emit(id)
	await wait_process_frames(1)
	assert_true(r.missive_screen().visible, "the full board opens")
	assert_eq(r.missive_screen().selected(), id, "on that letter")
	assert_true(screen.visible, "over the room, which stays open")


func test_escape_in_board_view_returns_to_the_table_not_the_pause_menu() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var view := r.war_room_screen().view()
	view.enter_board()
	await wait_seconds(Game.data.bal("war_board_fly_s") + 0.2)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	r.get_viewport().push_input(e)
	await wait_process_frames(2)
	assert_eq(view.board_mode(), "to_table")
	assert_false(r._pause_menu.visible, "Escape went to the board, not the pause menu")


func test_a_click_on_the_easel_at_a_notes_place_opens_that_letter() -> void:
	var r: GameRoot = await _court()
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "A letter", []))
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	screen.refresh_board()
	await wait_process_frames(2)
	var note := screen.board_screen().find_child("Note%d" % id, true, false) as Button
	var layout := Vector2(screen.board_screen().get_viewport().size_2d_override)
	if layout == Vector2.ZERO:
		layout = Vector2(screen.board_screen().get_viewport().size)
	var uv := note.get_global_rect().get_center() / layout
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		screen._push_board_click(uv, e)
	await wait_process_frames(1)
	assert_true(r.missive_screen().visible, "a real click through the panel")
	assert_eq(r.missive_screen().selected(), id)
