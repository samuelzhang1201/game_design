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
