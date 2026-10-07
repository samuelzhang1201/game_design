extends GutTest
## The WAR ROOM's plans through the room's own input (spec 2026-10-07-war-room-
## annotations-and-planning-pieces): the ground menu places a supposed piece
## through the form, a stick drawn across the table makes a stroke, a drag
## carries a piece, the scraper and Delete remove, undo puts back, the slip
## reads a supposed piece.

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
	return r.war_room_screen()


func _button(view: WarRoomView, at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.shift_pressed = shift
	view._gui_input(e)


func _motion(view: WarRoomView, at: Vector2, left := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if left else 0
	view._gui_input(e)


func _drag(view: WarRoomView, from: Vector2, to: Vector2, steps := 12) -> void:
	_button(view, from, true)
	for i in range(1, steps + 1):
		_motion(view, from.lerp(to, float(i) / steps))
	_button(view, to, false)


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


func _row(menu: PopupMenu, id: int) -> void:
	menu.hide()   # PopupMenu.activate_item's order: hidden first, then id_pressed
	menu.id_pressed.emit(id)


func test_a_right_click_on_open_ground_places_a_supposed_piece_through_the_form() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	assert_ne(at, Vector2(-1, -1))
	_button(view, at, true, MOUSE_BUTTON_RIGHT)
	_button(view, at, false, MOUSE_BUTTON_RIGHT)
	var menu := screen.get_node("%GroundMenu") as PopupMenu
	assert_true(menu.visible, "the ground menu")
	assert_eq(menu.get_item_text(0), "Place a supposed enemy here…")
	_row(menu, WarPlanDesk.PLACE)
	var form := screen.get_node("%PlanForm") as WarPlanForm
	assert_true(form.visible, "the Place form")
	assert_gt((form.get_node("%Figures") as Node).get_child_count(), 0, "its figures read live")
	watch_signals(Game)
	(form.get_node("%Place") as Button).pressed.emit()
	assert_signal_emitted(Game, "plans_changed")
	var pieces: Dictionary = Game.state.war_plans["pieces"]
	assert_eq(pieces.size(), 1)
	var p: Dictionary = pieces.values()[0]
	assert_eq(int(p["heads"]), int(Game.data.bal("war_plan_heads_default")))
	await wait_process_frames(2)
	assert_not_null(view.plan_pieces().piece(String(pieces.keys()[0])), "the piece stands on the table")


## Spec 2026-10-08-war-room-draw-orders rulings 1-2: two rows, a side first.
func test_a_rows_slot_draws_a_front_in_that_sides_colour_facing_the_other_side() -> void:
	var screen := await _room()
	var view := screen.view()
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	assert_not_null(roll.slot("front", "red"))
	assert_not_null(roll.slot("front", "blue"))
	assert_null(roll.slot("ink"), "the pen is retired")
	assert_null(roll.slot("piece", "blue"), "a supposed piece is theirs only")
	assert_ne(roll.slot("arrow", "blue").why, "", "no selection: the blue arrow is greyed")
	roll.slot("front", "red").pressed.emit("front")
	assert_true(view.plan_input().tool.in_hand())
	assert_eq(view.plan_input().tool.side, "red")
	assert_true(roll.slot("front", "red").chosen)
	assert_false(roll.slot("front", "blue").chosen)
	assert_lt(roll.row("blue").modulate.a, 1.0, "the other row is dimmed")
	# a row of open table, no piece of ours within 80 px of it
	var fy := -1.0
	for y: float in [0.6, 0.5, 0.7, 0.4, 0.3, 0.75, 0.25]:
		var a := Vector2(view.size) * Vector2(0.3, y)
		var b := Vector2(view.size) * Vector2(0.6, y)
		var clear := WarRoom.pieces(Game.data, Game.state, view.drawn()).all(func(q: Dictionary) -> bool:
			var at: Variant = view.screen_pos_of_px(q["at"])
			return at == null or Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) > 80.0)
		if clear and view.pack_at(a).x >= 0.0 and view.pack_at(b).x >= 0.0:
			fy = y
			break
	assert_gt(fy, 0.0, "an open row of table")
	var from := Vector2(view.size) * Vector2(0.3, fy)
	var to := Vector2(view.size) * Vector2(0.6, fy)
	# a blue mark below the line: the red front faces it
	var below := view.pack_at(Vector2(view.size) * Vector2(0.45, fy) + Vector2(0, 30))
	Game.draw_plan("phase", "blue", PackedVector2Array([below, below + Vector2(3, 0)]), 0.0, "Line I", false)
	var target := view.camera_rig().target
	_drag(view, from, to)
	assert_eq(view.camera_rig().target, target, "drawing never pans")
	var fronts: Array = (Game.state.war_plans["strokes"] as Dictionary).values().filter(
		func(s: Dictionary) -> bool: return String(s["kind"]) == "front")
	assert_eq(fronts.size(), 1)
	var s: Dictionary = fronts[0]
	assert_eq(String(s["colour"]), "red")
	# drawn left to right (east): the drawer's right is the screen's south when the room looks north
	assert_eq(int(s["flip"]), 0, "its teeth face the blue mark south of it")
	assert_true(view.plan_input().tool.in_hand(), "the stick stays in hand")


func test_escape_lays_the_stick_down_and_digits_pick_a_kind() -> void:
	var screen := await _room()
	var view := screen.view()
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_2
	screen._unhandled_input(k)
	assert_false(view.plan_input().tool.in_hand(), "no side yet: a digit takes nothing")
	k.keycode = KEY_TAB
	screen._unhandled_input(k)
	assert_eq(view.plan_input().tool.side, "blue", "Tab lights a row")
	k.keycode = KEY_2
	screen._unhandled_input(k)
	assert_eq([view.plan_input().tool.side, view.plan_input().tool.kind], ["blue", "front"])
	k.keycode = KEY_TAB
	screen._unhandled_input(k)
	assert_eq([view.plan_input().tool.side, view.plan_input().tool.kind], ["red", "front"], "Tab: the same kind, theirs")
	k.keycode = KEY_ESCAPE
	screen._unhandled_input(k)
	assert_false(view.plan_input().tool.in_hand())


func test_a_phase_line_asks_its_name_and_keeps_it() -> void:
	var screen := await _room()
	var view := screen.view()
	view.plan_input().pick_kind("phase", "blue")
	_drag(view, Vector2(view.size) * Vector2(0.4, 0.3), Vector2(view.size) * Vector2(0.45, 0.7))
	var box := screen.get_node("%PlanName") as WarPlanName
	assert_true(box.visible, "the name box")
	var edit := box.get_node("%NameEdit") as LineEdit
	assert_eq(edit.text, "Line I", "prefilled with the next free name")
	edit.text_submitted.emit("Line of the Ash")
	var s: Dictionary = Game.state.war_plans["strokes"].values()[0]
	assert_eq(String(s["name"]), "Line of the Ash")


func test_a_drag_carries_a_supposed_piece_and_delete_and_undo() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	var id := Game.place_plan_piece("infantry", 1000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	await wait_process_frames(2)
	var spot: Vector2 = view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id]))
	var to := spot + Vector2(60, 20)
	_drag(view, spot, to)
	assert_almost_eq(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id]).distance_to(view.pack_at(to)), 0.0, 0.01,
		"dropped where it was carried")
	# a click chooses it, Delete removes it, undo puts it back
	var now: Vector2 = view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id]))
	_button(view, now, true)
	_button(view, now, false)
	assert_eq(view.plan_input().chosen_id, id)
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_DELETE
	screen._unhandled_input(k)
	assert_false((Game.state.war_plans["pieces"] as Dictionary).has(id))
	k.keycode = KEY_Z
	k.meta_pressed = true
	screen._unhandled_input(k)
	assert_true((Game.state.war_plans["pieces"] as Dictionary).has(id), "undo puts it back")


func test_the_slip_reads_a_supposed_piece() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	var id := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	await wait_process_frames(2)
	view.plan_hovered.emit(id, at)
	var slip := screen.get_node("%HoverSlip") as WarHoverSlip
	assert_true(slip.visible)
	var first := ((slip.get_node("%Lines") as Node).get_child(0) as Label).text
	assert_eq(first, "Supposed horse")


func test_the_scraper_removes_a_stroke() -> void:
	var screen := await _room()
	var view := screen.view()
	var a := view.pack_at(Vector2(view.size) * Vector2(0.3, 0.5))
	var b := view.pack_at(Vector2(view.size) * Vector2(0.7, 0.5))
	var id := Game.draw_plan("front", "red", PackedVector2Array([a, b]), 0.0, "", false)
	view.plan_input().pick_action("red", WarPlanInput.SCRAPE)
	var on: Vector2 = view.screen_pos_of_px(a.lerp(b, 0.5))
	_button(view, on, true)
	_button(view, on, false)
	assert_false((Game.state.war_plans["strokes"] as Dictionary).has(id))



func test_the_blue_scraper_leaves_a_red_mark() -> void:
	var screen := await _room()
	var view := screen.view()
	var a := view.pack_at(Vector2(view.size) * Vector2(0.3, 0.5))
	var b := view.pack_at(Vector2(view.size) * Vector2(0.7, 0.5))
	var id := Game.draw_plan("front", "red", PackedVector2Array([a, b]), 0.0, "", false)
	view.plan_input().pick_action("blue", WarPlanInput.SCRAPE)
	var on: Vector2 = view.screen_pos_of_px(a.lerp(b, 0.5))
	_button(view, on, true)
	_button(view, on, false)
	assert_true((Game.state.war_plans["strokes"] as Dictionary).has(id), "ours scrapes only ours")


## Ruling 17: the red arrow is drawn for a selected supposed piece, and goes with it.
func test_a_red_arrow_is_drawn_for_a_selected_supposed_piece() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	var id := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	await wait_process_frames(2)
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	assert_ne(roll.slot("arrow", "red").why, "")
	var spot: Vector2 = view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id]))
	_button(view, spot, true)
	_button(view, spot, false)
	assert_eq([view.plan_input().sel_side, view.plan_input().sel], ["red", [id]])
	assert_eq(roll.slot("arrow", "red").why, "", "a supposed piece selected: the red arrow is live")
	roll.slot("arrow", "red").pressed.emit("arrow")
	_drag(view, spot + Vector2(10, 0), spot + Vector2(160, -40))
	var arrows: Array = (Game.state.war_plans["strokes"] as Dictionary).values().filter(
		func(s: Dictionary) -> bool: return String(s["kind"]) == "arrow")
	assert_eq(arrows.size(), 1)
	assert_eq([String(arrows[0]["colour"]), String(arrows[0]["of"])], ["red", id])
	Game.remove_plan(id)
	assert_true((Game.state.war_plans["strokes"] as Dictionary).is_empty(), "the piece's arrow went with it")


## Ruling 18: a spy's report of foreign men is a hint the red arrow is drawn from.
func test_an_intel_hint_is_selected_and_its_ants_march() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	var pk := view.pack_at(at)
	MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", Game.state.absolute_day(),
		MissiveLog.subject("point", "", -1, pk), "Spy report — here",
		[MissiveLog.span("troops_foreign", "Foreign men", 600, 900)]))
	view.redraw_marks()
	var hud := view.get_node("%Hud") as WarHud
	assert_eq((hud.marks()["hints"] as Array).size(), 1, "the hint is drawn")
	var spot: Vector2 = view.screen_pos_of_px(Vector2(roundi(pk.x), roundi(pk.y)))
	_button(view, spot, true)
	_button(view, spot, false)
	assert_eq(view.plan_input().sel_side, "red")
	assert_string_starts_with(String(view.plan_input().sel[0]), "h")
	assert_eq((screen.get_node("%ToolRoll") as WarToolRoll).slot("arrow", "red").why, "")


## Ruling 12: a chosen front's facing handle flips its teeth.
func test_the_facing_handle_flips_a_chosen_front() -> void:
	var screen := await _room()
	var view := screen.view()
	var a := view.pack_at(Vector2(view.size) * Vector2(0.3, 0.5))
	var b := view.pack_at(Vector2(view.size) * Vector2(0.7, 0.5))
	var id := Game.draw_plan("front", "red", PackedVector2Array([a, b]), 0.0, "", false, 0)
	var on: Vector2 = view.screen_pos_of_px(a.lerp(b, 0.3))
	_button(view, on, true)
	_button(view, on, false)
	assert_eq(view.plan_input().chosen_id, id)
	var hud := view.get_node("%PlanHud") as WarPlanHud
	var f: Dictionary = hud.facing()
	assert_false(f.is_empty(), "the facing arrow shows")
	_button(view, f["at"], true)
	_button(view, f["at"], false)
	assert_eq(int(Game.state.war_plans["strokes"][id]["flip"]), 1, "a click flips the teeth")
