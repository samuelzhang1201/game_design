extends GutTest
## The folio opens on a chosen piece and closes on ×, Escape or a click outside (spec §4).

var panel: WarFolioPanel
var code := ""


func before_each() -> void:
	Game.start_campaign(42)
	panel = load("res://scenes/war_room/war_folio.tscn").instantiate()
	panel.size = Vector2(1000, 640)
	add_child_autofree(panel)
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break


func test_the_right_page_lays_out_every_section_and_row() -> void:
	panel.open_for(code)
	assert_true(panel.visible)
	var secs := WarFolio.sections(Game.data, Game.state, code)
	var nodes := panel.section_nodes()
	assert_eq(nodes.size(), secs.size())
	var first: Node = nodes[0]
	assert_eq((first.get_node("Header") as Label).text, String(secs[0]["label"]).to_upper())
	assert_eq(first.get_node("Rows").get_child_count(), (secs[0]["rows"] as Array).size())


func test_escape_closes_it() -> void:
	panel.open_for(code)
	watch_signals(panel)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	panel._unhandled_input(e)
	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")


func test_a_click_on_the_dim_closes_it() -> void:
	panel.open_for(code)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	(panel.get_node("%Dim") as ColorRect).gui_input.emit(e)
	assert_false(panel.visible)


func _court() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	menu.menu_column().get_node("StartGame").pressed.emit()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	return r


func _own_code() -> String:
	return String(WarRoom.pieces(Game.data, Game.state)[0]["code"])


func test_all_six_sections_are_laid_in_columns_of_the_balance_key() -> void:
	panel.open_for(code)
	var cols := panel.get_node("%Right").get_children()
	assert_eq(cols.size(), int(Game.data.bal("war_folio_columns")))
	var keys: Array = []
	for col in cols:
		assert_gt(col.get_child_count(), 0, "no empty column")
		for sec in col.get_children():
			keys.append(String(sec.name))
	assert_eq(keys, ["composition", "arms", "morale", "supply", "ground", "march"])


func test_a_long_label_keeps_its_fixed_width_and_is_present() -> void:
	panel.open_for(code)
	await wait_frames(2)
	var found := false
	var w := Game.data.bal("war_folio_label_w_px")
	for sec in panel.section_nodes():
		for line in sec.get_node("Rows").get_children():
			var l := line.get_child(0) as Label
			assert_lte(l.size.x, w + 0.5, "label '%s' wider than the key" % l.text)
			assert_eq(l.vertical_alignment, VERTICAL_ALIGNMENT_TOP)
			if l.text.begins_with("Matchups"):
				found = true
	assert_true(found, "a Matchups label is present")


func test_the_page_is_laid_again_when_the_state_moves_under_it() -> void:
	panel.open_for(code)
	var st := ArmySystem.state_of(Game.data, Game.state, code)
	var before := _row_text("Morale")
	assert_ne(before, "")
	Game.state.regiments[code] = st.duplicate()
	Game.state.regiments[code]["morale"] = int(st["morale"]) - 7
	panel.refresh()
	assert_ne(_row_text("Morale"), before)
	assert_true(_row_text("Morale").begins_with(str(int(st["morale"]) - 7)))


func _row_text(label: String) -> String:
	for sec in panel.section_nodes():
		for line in sec.get_node("Rows").get_children():
			if (line.get_child(0) as Label).text == label:
				return (line.get_child(1) as Label).text
	return ""


func test_escape_does_nothing_while_the_folio_is_not_in_a_visible_tree() -> void:
	var holder := Control.new()
	add_child_autofree(holder)
	var p: WarFolioPanel = load("res://scenes/war_room/war_folio.tscn").instantiate()
	holder.add_child(p)
	p.open_for(code)
	holder.hide()
	watch_signals(p)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	p._unhandled_input(e)
	assert_signal_not_emitted(p, "closed")


func test_open_for_starts_at_the_top() -> void:
	panel.open_for(code)
	var scroll: ScrollContainer = panel.get_node("%RightScroll")
	scroll.scroll_vertical = 50
	panel.open_for(code)
	assert_eq(scroll.scroll_vertical, 0)


func test_a_piece_selected_in_the_war_room_opens_the_folio_and_closing_clears_it() -> void:
	var r: GameRoot = await _court()
	var screen := r.war_room_screen()
	var folio: WarFolioPanel = screen.get_node("%Folio")
	assert_false(folio.visible)
	var c := _own_code()
	screen.view().select(c)
	await wait_frames(1)
	assert_true(folio.visible)
	assert_eq(folio.code(), c)
	assert_eq(screen.view().selected_army(), c)
	folio.close()
	assert_false(folio.visible)
	assert_eq(screen.view().selected_army(), "")


func test_closing_the_war_room_closes_the_folio() -> void:
	var r: GameRoot = await _court()
	var screen := r.war_room_screen()
	var folio: WarFolioPanel = screen.get_node("%Folio")
	screen.view().select(_own_code())
	await wait_frames(1)
	assert_true(folio.visible)
	screen.close()
	assert_false(folio.visible)


func test_the_screens_refresh_lays_an_open_folio_again() -> void:
	var r: GameRoot = await _court()
	var screen := r.war_room_screen()
	var folio: WarFolioPanel = screen.get_node("%Folio")
	var c := _own_code()
	screen.view().select(c)
	await wait_frames(1)
	var st := ArmySystem.state_of(Game.data, Game.state, c).duplicate()
	st["morale"] = int(st["morale"]) - 9
	Game.state.regiments[c] = st
	screen.refresh()
	await wait_frames(3)
	var found := false
	for sec in folio.section_nodes():
		for line in sec.get_node("Rows").get_children():
			if (line.get_child(0) as Label).text == "Morale":
				found = (line.get_child(1) as Label).text.begins_with(str(int(st["morale"])))
	assert_true(found)
