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


func _motion(view: WarRoomView, at: Vector2, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(e)


## A real drag box round `spot` (screen px), `half` px each way — Shift held
## unless `shift` is false (then a row must be lit for it to box).
func _box_round(view: WarRoomView, spot: Vector2, half := 90.0, shift := true) -> void:
	var from := spot - Vector2(half, half)
	var to := spot + Vector2(half, half)
	_button(view, from, true, MOUSE_BUTTON_LEFT, shift)
	for i in range(1, 9):
		_motion(view, from.lerp(to, float(i) / 8.0))
	_button(view, to, false, MOUSE_BUTTON_LEFT, shift)


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
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	roll.slot("blue", "blue").pressed.emit("blue")   # ours lit: a plain drag boxes our units (owner 2026-10-11)
	_box_round(view, _drawn_spot(screen, code), 90.0, false)
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


func _pick_stick(screen: WarRoomScreen, side: String) -> void:
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	roll.slot("front", side).pressed.emit("front")


func test_a_click_with_a_front_in_hand_selects_our_piece() -> void:
	var screen := await _room()
	var view := screen.view()
	var p := _land_piece(screen)
	var code := String(p["code"])
	_pick_stick(screen, "red")
	assert_true(view.plan_input().tool.in_hand(), "a red front is in hand")
	_click(view, p["press"])
	assert_true(code in view.plan_input().sel, "the click selected our piece")
	assert_true(Game.state.war_plans["strokes"].is_empty(), "no stroke was written")
	assert_true(view.plan_input().tool.in_hand(), "the stick is still in hand")


func test_a_click_on_open_table_with_a_stick_lets_the_selection_go() -> void:
	var screen := await _room()
	var view := screen.view()
	var p := _land_piece(screen)
	_click(view, p["press"])
	assert_false(view.plan_input().sel.is_empty())
	_pick_stick(screen, "red")
	var at := _open_land(screen)
	assert_ne(at, Vector2(-1, -1))
	_click(view, at)
	assert_true(view.plan_input().sel.is_empty(), "the selection went")
	assert_true(Game.state.war_plans["strokes"].is_empty(), "no stroke was written")
	assert_true(view.plan_input().tool.in_hand(), "the stick is still in hand")


func _blue_drag_from_piece(screen: WarRoomScreen) -> String:
	var view := screen.view()
	var p := _land_piece(screen)
	var code := String(p["code"])
	var from: Vector2 = p["press"]
	var to: Vector2 = view.screen_pos_of_px(_land_near(screen, p["drawn"], Game.data.bal("war_plan_min_len_px") + 16.0))
	_click(view, from)
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	roll.slot("arrow", "blue").pressed.emit("arrow")
	_button(view, from, true)
	for i in range(1, 13):
		_motion(view, from.lerp(to, float(i) / 12.0))
	_button(view, to, false)
	return code


func _land_near(screen: WarRoomScreen, at: Vector2, min_px: float) -> Vector2:
	var from: Vector2 = screen.view().screen_pos_of_px(at)
	for k: float in [6.0, 12.0, 24.0, 40.0, 60.0]:
		for d: Vector2 in [Vector2(-k, 0), Vector2(0, -k), Vector2(k, 0), Vector2(0, k)]:
			var scr: Variant = screen.view().screen_pos_of_px(at + d)
			if scr != null and MapEconomy.cell_at(Game.data, at + d) >= 0 \
					and (scr as Vector2).distance_to(from) >= min_px and screen.view().pack_at(scr).x >= 0.0:
				return at + d
	return at


func test_a_drag_from_a_piece_with_the_blue_arrow_draws() -> void:
	var screen := await _room()
	var code := _blue_drag_from_piece(screen)
	assert_eq(screen.orders().aiming(), code, "the drawn arrow armed the march")
	screen.orders().withdraw_aim()


func test_the_blue_arrow_is_laid_down_once_its_march_is_drawn() -> void:
	var screen := await _room()
	var view := screen.view()
	_blue_drag_from_piece(screen)
	assert_false(view.plan_input().tool.in_hand(), "the blue arrow was laid down")
	screen.orders().withdraw_aim()
	_pick_stick(screen, "red")
	var before: int = (Game.state.war_plans["strokes"] as Dictionary).size()
	for i in 2:
		var a := _open_land(screen)
		_button(view, a, true)
		for j in range(1, 9):
			_motion(view, a + Vector2(float(j) * 12.0, 0.0))
		_button(view, a + Vector2(96.0, 0.0), false)
		assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), before + i + 1, "red draw %d was written" % i)
		assert_true(view.plan_input().tool.in_hand(), "a red front stays in hand (draw %d)" % i)


func test_a_click_with_a_stick_on_a_supposed_piece_selects_it_red() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	var id := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	await wait_process_frames(2)
	_pick_stick(screen, "red")
	_click(view, view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][id])))
	assert_eq([view.plan_input().sel_side, view.plan_input().sel], ["red", [id]])
	assert_true((Game.state.war_plans["strokes"] as Dictionary).is_empty(), "no stroke written")


func _drag(view: WarRoomView, from: Vector2, to: Vector2, shift := false, steps := 12) -> void:
	_button(view, from, true, MOUSE_BUTTON_LEFT, shift)
	for i in range(1, steps + 1):
		_motion(view, from.lerp(to, float(i) / steps), (to - from) / steps)
	_button(view, to, false, MOUSE_BUTTON_LEFT, shift)


func _stroke_pts(id: String) -> PackedVector2Array:
	return WarPlans.points_px(Game.data, Game.state.war_plans["strokes"][id])


func test_a_drag_from_an_unchosen_stroke_pans_and_a_click_chooses_it() -> void:
	var screen := await _room()
	var view := screen.view()
	var a := view.pack_at(Vector2(view.size) * Vector2(0.3, 0.5))
	var b := view.pack_at(Vector2(view.size) * Vector2(0.7, 0.5))
	var id := Game.draw_plan("phase", "red", PackedVector2Array([a, b]), 0.0, "Line", false)
	await wait_process_frames(2)
	var before := _stroke_pts(id)
	var mid: Vector2 = view.screen_pos_of_px(a.lerp(b, 0.5))
	var cam_before := view.camera_rig().target
	_drag(view, mid, mid + Vector2(0, 120))
	assert_ne(view.camera_rig().target, cam_before, "the drag panned the table")
	assert_eq(_stroke_pts(id), before, "the stroke did not move")
	assert_ne(view.plan_input().chosen_id, id, "a drag chooses nothing")
	mid = view.screen_pos_of_px(a.lerp(b, 0.5))
	_click(view, mid)
	assert_eq(view.plan_input().chosen_id, id, "a click chooses the stroke")
	_drag(view, mid, mid + Vector2(0, 60))
	assert_ne(_stroke_pts(id), before, "the chosen stroke now drags")


func test_a_shift_drawn_blue_arrow_marches_straight() -> void:
	var screen := await _room()
	var view := screen.view()
	var p := _land_piece(screen)
	var from: Vector2 = p["press"]
	var to: Vector2 = view.screen_pos_of_px(_land_near(screen, p["drawn"], Game.data.bal("war_plan_min_len_px") + 90.0))
	var away := (to - from).orthogonal().normalized() * 90.0
	_click(view, from)
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	roll.slot("arrow", "blue").pressed.emit("arrow")
	_button(view, from, true, MOUSE_BUTTON_LEFT, true)
	for i in range(1, 7):
		_motion(view, from.lerp(from + (to - from) * 0.5 + away, float(i) / 6.0))
	for i in range(1, 7):
		_motion(view, (from + (to - from) * 0.5 + away).lerp(to, float(i) / 6.0))
	_button(view, to, false, MOUSE_BUTTON_LEFT, true)
	assert_ne(screen.orders().aiming(), "", "the march was armed")
	assert_eq(view.aim_waypoints.size(), 0, "a Shift-drawn arrow has no bend")
	screen.orders().withdraw_aim()


func test_a_red_arrow_for_two_selected_pieces_draws_two() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	var ida := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at), 0)
	var idb := Game.place_plan_piece("cavalry", 2000, WarPlans.UNKNOWN, view.pack_at(at + Vector2(0, 90)), 0)
	await wait_process_frames(2)
	var spot_a: Vector2 = view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][ida]))
	var spot_b: Vector2 = view.screen_pos_of_px(WarPlans.at_px(Game.data, Game.state.war_plans["pieces"][idb]))
	_click(view, spot_a)
	_button(view, spot_b, true, MOUSE_BUTTON_LEFT, true)
	_button(view, spot_b, false, MOUSE_BUTTON_LEFT, true)
	assert_eq(view.plan_input().sel.size(), 2, "two pieces selected")
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	roll.slot("arrow", "red").pressed.emit("arrow")
	var open := _open_land(screen)
	_drag(view, open + Vector2(120, 0), open + Vector2(260, -30))
	var arrows: Array = (Game.state.war_plans["strokes"] as Dictionary).values().filter(
		func(s: Dictionary) -> bool: return String(s["kind"]) == "arrow")
	assert_eq(arrows.size(), 2, "one arrow a host")
	assert_eq((view.plan_input()._ghost["rows"] as Array).size(), 2, "both arrows stay drawn until painted")
	var starts: Dictionary = {}
	for s: Dictionary in arrows:
		starts[String(s["of"])] = WarPlans.points_px(Game.data, s)[0]
	assert_eq(starts.keys().size(), 2)
	for pair: Array in [[ida, spot_a], [idb, spot_b]]:
		assert_true(starts.has(pair[0]), "an arrow of %s" % pair[0])
		var scr: Variant = view.screen_pos_of_px(starts.get(pair[0], Vector2.ZERO))
		assert_lt((scr as Vector2).distance_to(pair[1]), 6.0, "starts at its piece")


func test_a_table_press_commits_the_name_and_keys_work_again() -> void:
	var screen := await _room()
	var view := screen.view()
	view.plan_input().pick_kind("phase", "blue")
	_drag(view, Vector2(view.size) * Vector2(0.4, 0.3), Vector2(view.size) * Vector2(0.45, 0.7))
	var box := screen.get_node("%PlanName") as WarPlanName
	assert_true(box.visible, "the name box is open")
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_TAB
	screen._unhandled_input(k)
	assert_eq(view.plan_input().tool.side, "blue", "the open box traps the keys")
	_button(view, Vector2(view.size) * Vector2(0.8, 0.5), true, MOUSE_BUTTON_RIGHT)
	assert_false(box.visible, "a press on the table commits the name")
	var s: Dictionary = Game.state.war_plans["strokes"].values()[0]
	assert_eq(String(s["name"]), "Line I", "the default is kept")
	screen._unhandled_input(k)
	assert_eq(view.plan_input().tool.side, "red", "Tab reaches the desk again")


func test_a_released_stroke_stays_drawn_until_its_layer_is_painted() -> void:
	var screen := await _room()
	var view := screen.view()
	var hud := view.get_node("%PlanHud") as WarPlanHud
	# headless never posts a draw: the paint begun when the room opened never ends. Hand in the
	# process frame and start the layer's paints afresh.
	view._inks.frame_done = get_tree().process_frame
	view._intel_busy = false
	view._ink_busy = 0
	view.refresh_plans()
	view.plan_input().pick_kind("front", "red")
	_drag(view, Vector2(view.size) * Vector2(0.4, 0.3), Vector2(view.size) * Vector2(0.45, 0.7))
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 1, "the front was written")
	assert_true(hud.drawing(), "the ghost is drawn right after release")
	var key := WarPlanInk.cache_key(Game.state, view.sheet_key())
	await wait_until(func() -> bool: return view.plan_key_shown() == key, 5.0)
	assert_eq(view.plan_key_shown(), key, "its layer was painted")
	assert_false(hud.drawing(), "the ghost is gone once the layer is painted")


func _cmd_z(screen: WarRoomScreen, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.meta_pressed = true
	k.ctrl_pressed = true
	k.shift_pressed = shift
	k.pressed = true
	screen._unhandled_input(k)


## A red front drawn by real input; true when it landed.
func _draw_front(screen: WarRoomScreen) -> void:
	var view := screen.view()
	_pick_stick(screen, "red")
	var a := _open_land(screen)
	_button(view, a, true)
	for j in range(1, 9):
		_motion(view, a + Vector2(float(j) * 12.0, 0.0))
	_button(view, a + Vector2(96.0, 0.0), false)


func test_cmd_z_strikes_a_drawn_march() -> void:
	var screen := await _room()
	_draw_front(screen)
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 1, "a front is drawn")
	screen.view().plan_input().put_down()
	var code := _blue_drag_from_piece(screen)
	screen.orders().shown_confirm().confirm_button().pressed.emit()
	await wait_process_frames(2)
	assert_eq(String(WarDrafts.of(Game.state, code).get("order", "")), "march", "the march is pencilled")
	_cmd_z(screen)
	assert_true(WarDrafts.of(Game.state, code).is_empty(), "Cmd-Z struck the march")
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 1, "the front drawn earlier stands")
	_cmd_z(screen, true)
	assert_eq(String(WarDrafts.of(Game.state, code).get("order", "")), "march", "Shift-Cmd-Z puts it back")


func test_undo_after_a_new_campaign_does_nothing() -> void:
	var screen := await _room()
	_draw_front(screen)
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 1)
	Game.start_campaign(45)
	var before: Dictionary = Game.state.war_plans.duplicate(true)
	_cmd_z(screen)
	assert_eq(Game.state.war_plans, before, "the old game's step was not applied")


func test_a_refused_write_leaves_no_undo_step() -> void:
	var screen := await _room()
	_draw_front(screen)
	_draw_front(screen)
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 2)
	screen.view().plan_input().piece_moved.emit("p999", Vector2(1, 1), 0)   # no such piece: refused
	_cmd_z(screen)
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 1, "Cmd-Z undid the previous mark, not the refusal")


func _news_since(f: Callable) -> Array:
	var said: Array = []
	var listen := func(t: String) -> void: said.append(t)
	Game.news_published.connect(listen)
	f.call()
	Game.news_published.disconnect(listen)
	return said


func test_undo_of_a_march_since_sealed_revives_nothing() -> void:
	var screen := await _room()
	var code := _blue_drag_from_piece(screen)
	screen.orders().shown_confirm().confirm_button().pressed.emit()
	await wait_process_frames(2)
	var first: Dictionary = WarDrafts.of(Game.state, code).duplicate(true)
	assert_eq(String(first.get("order", "")), "march", "M1 pencilled")
	_blue_drag_from_piece(screen)   # re-drawn: M2 over M1
	screen.orders().shown_confirm().confirm_button().pressed.emit()
	await wait_process_frames(2)
	assert_eq(String(WarDrafts.of(Game.state, code).get("order", "")), "march", "M2 pencilled")
	var out := Game.deploy_drafts()
	assert_true(code in out["sent"], "M2 went by courier")
	var said := _news_since(func() -> void: _cmd_z(screen))
	assert_true(WarDrafts.of(Game.state, code).is_empty(), "M1 is not pencilled again")
	assert_true(WarDrafts.codes(Game.state).is_empty(), "nothing is pencilled")
	assert_true("That march has since been sealed or changed — nothing to undo." in said, "the news says why")


func test_undo_of_a_march_puts_the_earlier_draft_back() -> void:
	var screen := await _room()
	var p := _land_piece(screen)
	var code := String(p["code"])
	Game.plant_draft(code, WarDrafts.GARRISON, Vector2.ZERO)
	var earlier: Dictionary = WarDrafts.of(Game.state, code).duplicate(true)
	_blue_drag_from_piece(screen)
	screen.orders().shown_confirm().confirm_button().pressed.emit()
	await wait_process_frames(2)
	assert_eq(String(WarDrafts.of(Game.state, code).get("order", "")), "march")
	_cmd_z(screen)
	assert_eq(WarDrafts.of(Game.state, code), earlier, "the halt pencilled before is back")


func test_a_ghost_goes_once_the_layer_is_current_after_an_undo() -> void:
	var screen := await _room()
	var view := screen.view()
	var hud := view.get_node("%PlanHud") as WarPlanHud
	view._inks.frame_done = get_tree().process_frame
	view._intel_busy = false
	view._ink_busy = 0
	view.refresh_plans()
	view.plan_input().pick_kind("front", "red")
	_drag(view, Vector2(view.size) * Vector2(0.4, 0.3), Vector2(view.size) * Vector2(0.45, 0.7))
	assert_true(hud.drawing(), "the ghost is drawn right after release")
	_cmd_z(screen)   # before the paint ends: the ghost's own key is never painted
	assert_true((Game.state.war_plans["strokes"] as Dictionary).is_empty(), "the front is undone")
	await wait_until(func() -> bool: return view.plan_key_shown() == WarPlanInk.cache_key(Game.state, view.sheet_key()), 5.0)
	assert_eq(view.plan_key_shown(), WarPlanInk.cache_key(Game.state, view.sheet_key()), "the layer is current")
	assert_false(hud.drawing(), "the ghost went with it")


func test_a_shift_drag_from_an_unchosen_stroke_boxes_not_pans() -> void:
	var screen := await _room()
	var view := screen.view()
	var a := view.pack_at(Vector2(view.size) * Vector2(0.3, 0.5))
	var b := view.pack_at(Vector2(view.size) * Vector2(0.7, 0.5))
	var id := Game.draw_plan("phase", "red", PackedVector2Array([a, b]), 0.0, "Line", false)
	await wait_process_frames(2)
	var before := _stroke_pts(id)
	var mid: Vector2 = view.screen_pos_of_px(a.lerp(b, 0.5))
	var cam_before := view.camera_rig().target
	_drag(view, mid, mid + Vector2(60, 60), true)
	assert_eq(view.camera_rig().target, cam_before, "a Shift-drag never pans")
	assert_eq(_stroke_pts(id), before, "the stroke did not move")
	assert_ne(view.plan_input().chosen_id, id, "a box chooses no stroke")


func test_a_stick_drag_out_and_back_is_no_click() -> void:
	var screen := await _room()
	var view := screen.view()
	var p := _land_piece(screen)
	_click(view, p["press"])
	assert_false(view.plan_input().sel.is_empty())
	_pick_stick(screen, "red")
	var at := _open_land(screen)
	assert_ne(at, Vector2(-1, -1))
	_button(view, at, true)
	for j in range(1, 9):
		_motion(view, at + Vector2(float(j) * 10.0, 0.0))
	for j in range(1, 9):
		_motion(view, at + Vector2(80.0 - float(j) * 10.0, 4.0))
	_button(view, at + Vector2(2.0, 2.0), false)
	assert_false(view.plan_input().sel.is_empty(), "a drag out and back is not an open-table click")


func test_a_resting_pointer_on_open_table_shows_the_slip() -> void:
	var screen := await _room()
	var view := screen.view()
	var at := _open_land(screen)
	assert_ne(at, Vector2(-1, -1))
	assert_false((screen.get_node("%HoverSlip") as Control).visible, "no slip before the pointer comes to rest")
	var e := InputEventMouseMotion.new()   # no button: a pointer moving over the table
	e.position = at
	view._gui_input(e)
	await wait_until(func() -> bool: return (screen.get_node("%HoverSlip") as Control).visible, 3.0)
	assert_true((screen.get_node("%HoverSlip") as Control).visible, "a pointer at rest on open table raises the slip")


## B1: the supply preview is clipped to the laid sheet in pack px; a road from a
## town off the sheet ends at the sheet's edge with the town's name beside it.
func _burg_off_sheet(view: WarRoomView) -> String:
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	for t: String in codes:
		var b: Dictionary = Game.data.burgs[t]
		if WarSheets.sheet_of(Game.data, Vector2(float(b["x"]), float(b["y"]))) != view.sheet_index() \
				and not view.sheet_rect().has_point(Vector2(float(b["x"]), float(b["y"]))):
			return t
	return ""


func _in_quad(view: WarRoomView, p: Vector2) -> bool:
	var r := view.sheet_rect()
	var quad := PackedVector2Array()
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		quad.append(view.screen_pos_of_px(c))
	var fat := Geometry2D.offset_polygon(quad, 3.0)
	return not fat.is_empty() and Geometry2D.is_point_in_polygon(p, fat[0])


func test_a_supply_road_inside_the_sheet_has_no_exit_mark() -> void:
	var screen := await _room()
	var view := screen.view()
	var c := view.sheet_rect().get_center()
	view.aiming = true
	view.supply_preview = PackedVector2Array([c, c + Vector2(40, 20)])
	view.plan_input().redraw_live()
	var hud := view.get_node("%PlanHud") as WarPlanHud
	assert_eq(hud.runs().size(), 1)
	assert_true(hud.exit_mark().is_empty())


func test_a_supply_road_from_off_the_sheet_ends_at_its_edge_with_the_towns_name() -> void:
	var screen := await _room()
	var view := screen.view()
	var town := _burg_off_sheet(view)
	assert_ne(town, "")
	var b: Dictionary = Game.data.burgs[town]
	var from := Vector2(float(b["x"]), float(b["y"]))
	view.aiming = true
	view.supply_town = town
	view.supply_preview = PackedVector2Array([from, view.sheet_rect().get_center()])
	view.plan_input().redraw_live()
	var hud := view.get_node("%PlanHud") as WarPlanHud
	assert_gt(hud.runs().size(), 0, "the part on the sheet is drawn")
	for run: PackedVector2Array in hud.runs():
		for p in run:
			assert_true(_in_quad(view, p), "no gold on the oak: " + str(p))
	var mark := hud.exit_mark()
	assert_false(mark.is_empty())
	assert_string_contains(String(mark["text"]), String(b["label"]))
	assert_string_contains(String(mark["text"]), String(WarSheets.series(Game.data)[WarSheets.sheet_of(Game.data, from)]["id"]))


func test_the_confirm_does_not_cover_the_margin_slip() -> void:
	var screen := await _room()
	_blue_drag_from_piece(screen)
	var p := screen.orders().confirm_panel()
	assert_true(p.visible, "the confirm is open")
	var slip := screen.get_node("%Slip") as Control
	# a route box swallowing every tip-adjacent spot sends the old placement to the top-left corner
	var view_rect := screen.view().get_global_rect()
	p.place_near(view_rect.get_center(), view_rect.grow(-40.0), view_rect, screen.blocked_rects())
	# whatever the window (the suite's root size is shared): the slip steps aside or is put away
	assert_true(not slip.visible or not p.get_global_rect().intersects(slip.get_global_rect()),
		"the confirm never covers the margin slip")
	p.global_position = view_rect.position + Vector2(8, 8)   # a confirm in the corner: the slip steps right of it, clear
	screen._make_way()
	assert_true(slip.visible, "the slip steps aside when there is room")
	assert_false(p.get_global_rect().intersects(slip.get_global_rect()), "the confirm and the margin slip do not overlap")
	screen.orders().withdraw_aim()


func test_the_margin_slip_comes_back_when_the_confirm_closes() -> void:
	var screen := await _room()
	var slip := screen.get_node("%Slip") as Control
	_blue_drag_from_piece(screen)
	var p := screen.orders().confirm_panel()
	var view_rect := screen.view().get_global_rect()
	p.global_position = view_rect.position + Vector2(8, 8)   # over the slip's corner
	screen._make_way()
	assert_true(not slip.visible or slip.offset_left > 16.0, "the slip made way for the confirm")
	screen.orders().withdraw_aim()
	await wait_process_frames(2)
	assert_false(p.visible, "the confirm closed")
	assert_true(slip.visible, "the slip is back")
	var folio := screen.get_node("%Folio") as WarFolioPanel
	var home := folio.book_rect().end.x + 12.0 if folio.visible and not folio.is_full() else 16.0
	assert_eq(slip.offset_left, home, "where the book (or the corner) leaves it")


func test_the_open_book_is_a_blocked_rect_where_it_stands() -> void:
	var screen := await _room()
	var land := _land_piece(screen)
	screen._on_piece(String(land["code"]))
	await wait_process_frames(2)
	var folio := screen.get_node("%Folio") as Control
	var docket := folio.get_node("%Docket") as Control
	var want := Rect2(docket.global_position, docket.size * docket.scale)
	var found := false
	for r: Rect2 in screen.blocked_rects():
		if r.position.distance_to(want.position) < 2.0 and r.size.distance_to(want.size) < 2.0:
			found = true
	assert_true(found, "the docked book's rect %s is blocked (%s)" % [want, screen.blocked_rects()])


func test_the_confirm_opens_somewhere_when_every_spot_is_blocked() -> void:
	var p := load("res://scenes/panels/march_confirm_panel.tscn").instantiate() as MarchConfirmPanel
	add_child_autofree(p)
	await wait_process_frames(2)
	var view := Rect2(Vector2.ZERO, p.get_viewport_rect().size)
	var all: Array[Rect2] = [view]
	p.place_near(view.get_center(), Rect2(), view, all)
	var r := Rect2(p.global_position, p.get_combined_minimum_size())
	assert_true(view.encloses(r), "still inside the window")
	assert_false(r.grow(-1.0).has_point(view.get_center()), "never over the tip")


func _covered(r: Rect2, blocked: Array[Rect2]) -> float:
	var sum := 0.0
	for b: Rect2 in blocked:
		sum += r.intersection(b).get_area()
	return sum


func test_a_blocked_rect_over_the_winning_spot_moves_the_confirm() -> void:
	var p := load("res://scenes/panels/march_confirm_panel.tscn").instantiate() as MarchConfirmPanel
	add_child_autofree(p)
	await wait_process_frames(2)
	var view := Rect2(Vector2.ZERO, p.get_viewport_rect().size)
	var tip := view.get_center()
	p.place_near(tip, Rect2(), view, [])
	var free_at := p.global_position
	var box := p.size
	var over: Array[Rect2] = [Rect2(free_at, box)]
	p.place_near(tip, Rect2(), view, over)
	assert_ne(p.global_position, free_at, "the blocked rect moved the winner")
	assert_lt(_covered(Rect2(p.global_position, p.size), over), box.x * box.y, "and it covers less of it")


func test_the_least_covered_spot_wins_among_blocked_rects() -> void:
	var p := load("res://scenes/panels/march_confirm_panel.tscn").instantiate() as MarchConfirmPanel
	add_child_autofree(p)
	await wait_process_frames(2)
	var view := Rect2(Vector2.ZERO, p.get_viewport_rect().size)
	var left := Rect2(view.position, Vector2(view.size.x * 0.5, view.size.y))
	var blocked: Array[Rect2] = [left, view]   # the left half is covered twice, the right once
	p.place_near(view.get_center(), Rect2(), view, blocked)
	var got := _covered(Rect2(p.global_position, p.size), blocked)
	var at_left := _covered(Rect2(view.position, p.size), blocked)
	assert_lt(got, at_left, "less covered than the left corner")
	var best := INF
	for spot: Vector2 in [view.position, Vector2(view.end.x - p.size.x, view.position.y),
			Vector2(view.position.x, view.end.y - p.size.y), view.end - p.size]:
		best = minf(best, _covered(Rect2(spot.clamp(view.position, (view.end - p.size).max(view.position)), p.size), blocked))
	assert_lte(got, best + 1.0, "no corner is less covered")


func test_a_held_up_book_is_blocked_whole() -> void:
	var screen := await _room()
	var land := _land_piece(screen)
	screen._on_piece(String(land["code"]))
	await wait_process_frames(2)
	var folio := screen.get_node("%Folio") as WarFolioPanel
	folio.set_full(true)
	await wait_process_frames(2)
	var folder := folio.get_node("%Folder") as Control
	var want := Rect2(folder.global_position, folder.size * folder.scale)
	var found := false
	for r: Rect2 in screen.blocked_rects():
		if r.position.distance_to(want.position) < 2.0 and r.size.distance_to(want.size) < 2.0:
			found = true
	assert_true(found, "the held-up book's rect %s is blocked (%s)" % [want, screen.blocked_rects()])


## A blue FRONT drawn with our piece chosen (spec 2026-10-11-war-room-front-
## line-design §1): the stroke is written as any mark, and the regiment gets a
## march draft to its post on the line carrying a hold facing the teeth; the
## front stays in hand.
func test_a_blue_front_with_our_piece_chosen_pencils_a_hold_draft() -> void:
	var screen := await _room()
	var view := screen.view()
	var p := _land_piece(screen)
	var code := String(p["code"])
	_click(view, p["press"])
	assert_true(code in view.plan_input().sel)
	var roll := screen.get_node("%ToolRoll") as WarToolRoll
	roll.slot("front", "blue").pressed.emit("front")
	var a := _open_land(screen)
	assert_ne(a, Vector2(-1, -1))
	var before: int = (Game.state.war_plans["strokes"] as Dictionary).size()
	_button(view, a, true)
	for j in range(1, 9):
		_motion(view, a + Vector2(float(j) * 12.0, 0.0))
	_button(view, a + Vector2(96.0, 0.0), false)
	await wait_process_frames(2)
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), before + 1, "the front was written")
	var d := WarDrafts.of(Game.state, code)
	assert_false(d.is_empty(), "a draft was pencilled")
	assert_true(d.has("hold"), "it carries the hold")
	assert_eq(String(d["hold"]["stance"]), "hold")
	assert_true(int(d["hold"]["facing"]) >= 0 and int(d["hold"]["facing"]) < 360)
	assert_true(d.has("front"), "it names its front")
	assert_true(view.plan_input().tool.in_hand(), "the front stays in hand")
	var lines: Array = Game.review_drafts()["lines"]
	assert_eq(lines.size(), 1)
	assert_ne(String(lines[0]["hold"]), "", "the resolutions say the hold")
