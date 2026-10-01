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


func test_a_regiment_on_another_sheet_is_listed_and_its_row_lays_that_sheet() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	var screen := r.war_room_screen()
	var off := WarRoom.off_sheet(Game.data, Game.state, screen.view().sheet_index())
	if off.is_empty():
		pass_test("every regiment stands on the home sheet in this pack")
		return
	var rows := screen.get_node("%Margin").get_children().filter(func(n: Node) -> bool: return n is Button)
	assert_eq(rows.size(), off.size())
	(rows[0] as Button).pressed.emit()
	_roll(screen.view())
	await wait_frames(2)
	assert_eq(screen.view().sheet_index(), int(off[0]["sheet"]))


## Run the roll-up's seconds at once, as the clock would over time.
func _roll(view: WarRoomView) -> void:
	view._process(10.0)


func test_the_rake_on_a_running_clock_says_why_and_arms_nothing() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
	Game.set_clock_speed(1)
	var screen := r.war_room_screen()
	var code := String(WarRoom.on_sheet(Game.data, Game.state, screen.view().sheet_index())[0]["code"])
	screen.view().rake_started.emit(code)
	Game.set_clock_speed(0)
	assert_eq(screen.orders().aiming(), "")


func test_a_committed_rake_plants_a_pennant_with_a_riding_slip() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_frames(2)
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
	await wait_frames(2)
	assert_eq(String(WarRoom.pennant_of(Game.data, Game.state, code).get("status", "")), "riding")
	var pennants: WarPennants = screen.view().get_node("%Pennants")
	assert_not_null(pennants.get_node_or_null(NodePath(code)))
