extends GutTest
## The regiment's right-click orders (owner 2026-09-22): the menu's rows are
## data, MARCH is AIMED — the menu only arms the map and the next click on
## the ground is the destination — and every order goes through
## Game.try_execute, so it is validated and charged like any other.

## A stand-in for the map: ArmyOrderMenu.follow connects by signal NAME, the
## same way MapDetailPanel.follow does, so a test needs no 3D view at all.
class FakeMap extends Node:
	signal army_menu_requested(code: String, at: Vector2)
	signal ground_clicked(pack_px: Vector2)
	signal route_clicked(code: String, at: Vector2)
	var aiming := false
	var aim_dest := Vector2(-1, -1)


var _menu: ArmyOrderMenu
var _map: FakeMap


func before_each() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)
	_menu = ArmyOrderMenu.new()
	add_child_autofree(_menu)
	_map = FakeMap.new()
	add_child_autofree(_map)
	_menu.follow(_map)


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(Game.data, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _land_near(from: Vector2) -> Vector2:
	for i in range(2, 60):
		var probe := from + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(Game.data, probe) >= 0:
			return probe
	return Vector2.ZERO


func test_the_menu_offers_exactly_the_rows_in_the_table() -> void:
	_map.army_menu_requested.emit(_marcher(), Vector2(10.0, 10.0))
	assert_eq(_menu.item_count, Game.data.army_orders.size())
	for i in Game.data.army_orders.size():
		assert_eq(_menu.get_item_text(i), String(Game.data.army_orders[i]["label"]))


func test_choosing_march_only_AIMS_it_and_gives_the_map_the_word() -> void:
	var code := _marcher()
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)   # ARMY_MARCH is the first row
	assert_eq(_menu.aiming(), code, "the order waits for a destination")
	assert_true(_map.aiming, "and the map knows not to pick with the next click")
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON,
		"nothing is ordered until it is aimed")


func test_a_row_chosen_the_way_PopupMenu_chooses_it_still_takes() -> void:
	# PopupMenu.activate_item HIDES the menu and only then emits id_pressed.
	# The menu once forgot its regiment on popup_hide, so every order a player
	# clicked was silently dropped while the tests above — emitting
	# id_pressed on a menu still open — stayed green (owner 2026-09-24: 兵棋
	# 的操作我并没有看到实现). Choose both rows in the real order.
	var code := _marcher()
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)   # ARMY_MARCH
	assert_eq(_menu.aiming(), code, "MARCH chosen from a closing menu still aims")
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	ArmySystem.set_march(Game.data, Game.state, code, here + Vector2(30.0, 0.0))
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(1)   # ARMY_GARRISON
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON,
		"GARRISON chosen from a closing menu still halts it")


func test_an_order_on_a_stopped_clock_does_not_start_it() -> void:
	# owner 2026-09-24: 兵棋不进行移动，直到玩家点击继续游戏按钮.
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	Game.set_clock_speed(0)
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_commit()
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_MARCH, "the order is given")
	assert_eq(Game.clock_speed, 0, "but time stays stopped")


## COMMIT chosen the way PopupMenu chooses: hidden first, then id_pressed.
func _commit() -> void:
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.COMMIT)


func test_the_next_click_on_the_ground_sends_it_on_commit() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_commit()
	assert_eq(_menu.aiming(), "", "the aim is spent")
	assert_false(_map.aiming)
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_MARCH)
	var dest := ArmySystem.destination_of(Game.data, Game.state, code)
	assert_almost_eq(dest.x, there.x, 0.002)
	assert_almost_eq(dest.y, there.y, 0.002)


func test_a_click_on_the_ground_with_nothing_aimed_orders_nothing() -> void:
	var code := _marcher()
	_map.ground_clicked.emit(Vector2(500.0, 300.0))
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON)


func test_garrison_runs_at_once_and_halts_a_march() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	ArmySystem.set_march(Game.data, Game.state, code, here + Vector2(30.0, 0.0))
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(1)   # ARMY_GARRISON
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON)


func test_an_order_the_engine_would_refuse_is_greyed_out_with_its_reason() -> void:
	# An empty chest cannot pay the column's provisions, and ActionSystem
	# refuses on that before anything else — so the row must be offered dead,
	# with the refusal as its tooltip, rather than live and then failing.
	var code := _marcher()
	Game.state.metrics["treasury"] = 0.0
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	for i in _menu.item_count:
		assert_true(_menu.is_item_disabled(i), _menu.get_item_text(i) + " cannot be paid for")
		assert_string_contains(_menu.get_item_tooltip(i), "afford")


func test_a_row_that_can_be_paid_for_is_live_and_says_what_it_does() -> void:
	_map.army_menu_requested.emit(_marcher(), Vector2(10.0, 10.0))
	for i in _menu.item_count:
		assert_false(_menu.is_item_disabled(i), _menu.get_item_text(i))
		assert_eq(_menu.get_item_tooltip(i), String(Game.data.army_orders[i]["hint"]))


func test_the_order_is_charged_like_every_other() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	var before: float = Game.state.metrics["treasury"]
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_commit()
	assert_lt(Game.state.metrics["treasury"], before,
		"every order carries a cost (architecture invariant 8)")



## owner 2026-09-27: 当点击完兵人行进路线后，会出现commit/cancel的选项.
func test_the_destination_click_only_ASKS() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON,
		"nothing is sent before COMMIT")
	assert_eq(_menu.pending(), there)
	assert_eq(_map.aim_dest, there, "the route is drawn to where it was clicked")
	assert_eq(_menu.get_item_index(ArmyOrderMenu.COMMIT), 0)
	assert_eq(_menu.get_item_text(0), String(Game.data.army_route_orders["commit"]["label"]))
	assert_eq(_menu.get_item_text(1), String(Game.data.army_route_orders["cancel"]["label"]))


func test_cancel_gives_the_march_up() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.CANCEL)
	assert_eq(_menu.aiming(), "")
	assert_eq(_map.aim_dest, Vector2(-1, -1))
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON)


func test_clicking_away_from_the_confirm_gives_it_up() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_menu.hide()   # closed with no row chosen
	await wait_process_frames(2)
	assert_eq(_menu.aiming(), "")
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON)


## owner 2026-09-27: 兵人行进路线只能在暂停模式下选择，时间流逝的时候不可以操作.
func test_march_is_greyed_out_while_time_runs() -> void:
	Game.set_clock_speed(1)
	_map.army_menu_requested.emit(_marcher(), Vector2(10.0, 10.0))
	assert_true(_menu.is_item_disabled(0), "MARCH")
	assert_eq(_menu.get_item_tooltip(0), String(Game.data.army_route_orders["paused_only"]["hint"]))
	assert_false(_menu.is_item_disabled(1), "GARRISON still halts a column while time runs")
	Game.set_clock_speed(0)


func test_starting_the_clock_withdraws_an_aim() -> void:
	var code := _marcher()
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	assert_eq(_menu.aiming(), code)
	Game.set_clock_speed(1)
	await wait_process_frames(2)
	assert_eq(_menu.aiming(), "")
	assert_false(_map.aiming)
	Game.set_clock_speed(0)


## owner 2026-09-27: 行进路线commit后，再次点击终点可以edit路线或者cancel操作.
func test_the_end_ring_edits_or_halts_the_march() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	ArmySystem.set_march(Game.data, Game.state, code, here + Vector2(30.0, 0.0))
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	assert_eq(_menu.item_count, 2)
	assert_eq(_menu.get_item_text(0), String(Game.data.army_route_orders["edit"]["label"]))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.EDIT)
	assert_eq(_menu.aiming(), code, "Edit aims the march anew")
	_menu.id_pressed.emit(ArmyOrderMenu.CANCEL)
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.HALT)
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON,
		"Cancel march halts the column")


func test_the_route_menu_is_paused_only() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	ArmySystem.set_march(Game.data, Game.state, code, here + Vector2(30.0, 0.0))
	Game.set_clock_speed(1)
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	assert_true(_menu.is_item_disabled(0))
	assert_true(_menu.is_item_disabled(1))
	Game.set_clock_speed(0)
