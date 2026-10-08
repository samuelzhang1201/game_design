extends GutTest
const ClearPiece := preload("res://tests/war_room/clear_piece.gd")
## The WAR ROOM's tools through the room's own input (spec 2026-10-08-war-room-
## tools-polish): a red selection holds over a docked book, Esc lays the stick
## down before the book closes.

func _room() -> WarRoomScreen:
	Game.start_campaign(44)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(3)
	Game.set_clock_speed(0)
	return r.war_room_screen()


func _button(view: WarRoomView, at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.shift_pressed = shift
	view._gui_input(e)


func _click(view: WarRoomView, at: Vector2) -> void:
	_button(view, at, true)
	_button(view, at, false)


func _esc(screen: WarRoomScreen) -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.pressed = true
	screen.get_viewport().push_input(k)   # the real chain: the folio (a child) hears it first


## Open land on the screen, off every crown piece: a point near the view's middle.
func _open_land(screen: WarRoomScreen) -> Vector2:
	var view := screen.view()
	for fy: float in [0.5, 0.6, 0.4, 0.7, 0.3]:
		for fx: float in [0.5, 0.4, 0.6, 0.3, 0.7]:
			var at := Vector2(view.size) * Vector2(fx, fy)
			var pk := view.pack_at(at)
			if pk.x >= 0.0 and view.piece_under(at) == "" and MapEconomy.cell_at(Game.data, pk) >= 0 \
					and not MapTerrain.is_water(Game.data.cells[MapEconomy.cell_at(Game.data, pk)]):
				return at
	return Vector2(-1, -1)


func _land_piece(screen: WarRoomScreen) -> Dictionary:
	return ClearPiece.find(screen.view(), Game.data, Game.state)


func _motion(view: WarRoomView, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(e)


## A real Shift-drag box round `spot` (screen px), `half` px each way.
func _box_round(view: WarRoomView, spot: Vector2, half := 90.0) -> void:
	var from := spot - Vector2(half, half)
	var to := spot + Vector2(half, half)
	_button(view, from, true, MOUSE_BUTTON_LEFT, true)
	for i in range(1, 9):
		_motion(view, from.lerp(to, float(i) / 8.0))
	_button(view, to, false, MOUSE_BUTTON_LEFT, true)


## The DRAWN screen spot of one of our land pieces.
func _drawn_spot(screen: WarRoomScreen, code: String) -> Vector2:
	var view := screen.view()
	var pk: Vector2 = view.piece_pack_positions()[code]
	return view.screen_pos_of_px(pk)


func test_a_box_over_our_units_selects_them_after_red_work() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	assert_ne(at, Vector2(-1, -1))
	var id := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	await wait_process_frames(2)
	_click(view, view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id])))
	assert_eq(view.plan_input().sel_side, "red")
	var code := String(_land_piece(screen)["code"])
	_box_round(view, _drawn_spot(screen, code))
	assert_eq(view.plan_input().sel_side, "blue")
	assert_true(code in view.plan_input().sel, "the boxed unit is chosen")


func test_a_second_box_over_the_same_units_keeps_them() -> void:
	var screen := await _room()
	var view := screen.view()
	var code := String(_land_piece(screen)["code"])
	var spot := _drawn_spot(screen, code)
	_box_round(view, spot)
	var first: Array = view.plan_input().sel.duplicate()
	_box_round(view, spot)
	assert_true(code in first)
	assert_eq(view.plan_input().sel_side, "blue")
	assert_eq(view.plan_input().sel, first, "the same box keeps the same units")


func test_an_empty_box_keeps_the_selection() -> void:
	var screen := await _room()
	var view := screen.view()
	var p := _land_piece(screen)
	_click(view, p["press"])
	var before: Array = view.plan_input().sel.duplicate()
	assert_false(before.is_empty())
	var at := _open_land(screen)
	_box_round(view, at, 8.0)
	assert_eq(view.plan_input().sel, before)


func test_a_supposed_piece_clicked_with_our_unit_chosen_stays_selected() -> void:
	var screen := await _room()
	var view := screen.view()
	var folio := screen.get_node("%Folio") as WarFolioPanel
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	var at := _open_land(screen)
	assert_ne(at, Vector2(-1, -1))
	var id := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	await wait_process_frames(2)
	var p := _land_piece(screen)
	_click(view, p["press"])
	assert_true(folio.visible, "our unit's book is docked")
	var spot: Vector2 = view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id]))
	_click(view, spot)
	assert_eq([view.plan_input().sel_side, view.plan_input().sel], ["red", [id]])
	assert_false(folio.visible, "the book went with our unit")
	assert_eq(roll.slot("arrow", "red").why, "", "the red arrow is live")


func test_escape_lays_the_stick_down_before_closing_the_book() -> void:
	var screen := await _room()
	var view := screen.view()
	var folio := screen.get_node("%Folio") as WarFolioPanel
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	var p := _land_piece(screen)
	var code := String(p["code"])
	_click(view, p["press"])
	assert_true(folio.visible)
	roll.slot("arrow", "blue").pressed.emit("arrow")
	assert_true(view.plan_input().tool.in_hand())
	_esc(screen)
	assert_false(view.plan_input().tool.in_hand(), "the stick is down")
	assert_true(folio.visible, "the book stays")
	assert_eq(view.selected_army(), code, "our unit is still chosen")
	_esc(screen)
	assert_false(view.has_selection(), "the selection is empty")
	assert_false(folio.visible, "the book is closed")


func _fleet_code(view: WarRoomView) -> String:
	for q: Dictionary in WarRoom.on_sheet(Game.data, Game.state, view.sheet_index(), view.drawn()):
		if bool(q["naval"]):
			return String(q["code"])
	return ""


func test_a_new_sheet_drops_off_sheet_units_and_closes_their_book() -> void:
	var screen := await _room()
	var view := screen.view()
	var folio := screen.get_node("%Folio") as WarFolioPanel
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	var p := _land_piece(screen)
	var code := String(p["code"])
	_click(view, p["press"])
	assert_true(folio.visible)
	var other := -1
	for i in range(WarSheets.series(Game.data).size()):
		if i == view.sheet_index():
			continue
		var held := WarRoom.on_sheet(Game.data, Game.state, i, view.drawn()).any(
			func(q: Dictionary) -> bool: return String(q["code"]) == code)
		if not held:
			other = i
			break
	assert_ne(other, -1, "a sheet that does not hold the unit")
	view.lay_sheet(other)
	await wait_process_frames(2)
	assert_true(view.plan_input().sel.is_empty(), "the off-sheet unit left the selection")
	assert_false(folio.visible, "its book closed")
	assert_ne(roll.slot("arrow", "blue").why, "", "the blue arrow greys")


func test_a_fleet_alone_greys_the_blue_arrow() -> void:
	var screen := await _room()
	var view := screen.view()
	var fleet := _fleet_code(view)
	assert_ne(fleet, "", "the home sheet holds a fleet")
	view.plan_input().select("blue", [fleet])
	assert_eq(view.plan_input().why_of("blue", "arrow"), "Fleets are ordered on the map")
