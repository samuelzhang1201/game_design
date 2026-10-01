extends GutTest
## The WAR ROOM tab opens the plotting room over the map (spec 2026-10-01 §1, §5).

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
	return r


func test_war_room_is_no_longer_a_placeholder() -> void:
	assert_false("WAR ROOM" in BottomBar.PLACEHOLDER_TABS)


func test_the_tab_lays_the_home_provinces_sheet_over_the_map() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(3)
	var screen := r.war_room_screen()
	assert_true(screen.visible)
	var map: Control = r.current_screen.map_panel()
	assert_eq(screen.size, map.size)
	var home := MapManors.home_province(Game.data, Game.state)
	var row: Dictionary = Game.data.provinces[home]
	var at := Vector2(float(row["center_x"]), float(row["center_y"]))
	assert_eq(screen.view().sheet_index(), WarSheets.sheet_of(Game.data, at))


func test_the_tab_again_closes_it_and_another_tab_closes_it_too() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	assert_false(r.war_room_screen().visible)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	assert_false(r.war_room_screen().visible)
	assert_true(r.ledger_screen().visible)


func test_a_selected_piece_puts_its_card_in_the_left_column_and_closing_takes_it_away() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	r.war_room_screen().view().piece_selected.emit(code)
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, String(MapObjects.army_card(Game.data, code, Game.state)["title"]))
	r.war_room_screen().close()
	assert_false(detail.has_content())


func test_opening_the_room_withdraws_an_aim_armed_on_the_map() -> void:
	var r: GameRoot = await _court()
	var map_orders := r.current_screen.find_child("ArmyOrders", true, false) as ArmyOrderMenu
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	Game.set_clock_speed(0)
	assert_eq(map_orders.aim_for(code), "", "the aim is armed on a paused clock")
	assert_eq(map_orders.aiming(), code)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	assert_eq(map_orders.aiming(), "")


func test_closing_the_room_lets_its_selection_go() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	var view := r.war_room_screen().view()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	view._selected = code
	r.war_room_screen().close()
	assert_eq(view.selected_army(), "")


func test_an_out_of_range_sheet_is_ignored() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	var screen := r.war_room_screen()
	var was := screen.view().sheet_index()
	screen.lay_sheet(-1)
	screen.lay_sheet(9999)
	assert_eq(screen.view().sheet_index(), was)
