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


## The 3D view's own signature: the click's point rides with it.
class ClickMap extends Node:
	signal army_menu_requested(code: String, at: Vector2)
	signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
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
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if ArmySystem.base_pace_km(Game.data, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _land_near(from: Vector2) -> Vector2:
	for i in range(2, 60):
		var probe := from + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(Game.data, probe) >= 0:
			return probe
	return Vector2.ZERO


## Days run until every courier has delivered (or the fuse has taken him).
func _deliver_all() -> void:
	Game.set_clock_speed(0)
	for i in int(Game.data.bal("courier_max_days")) + 1:
		if Game.state.couriers.is_empty():
			return
		Game.advance_day()


## The ids of the rows after the march rows (separators left out).
func _supply_ids(menu: ArmyOrderMenu) -> Array:
	var out: Array = []
	for i in range(Game.data.army_orders.size(), menu.item_count):
		if not menu.is_item_separator(i) and menu.get_item_id(i) != ArmyOrderMenu.SEAT:
			out.append(menu.get_item_id(i))
	return out


## What a land regiment of the realm with no supply point is offered: Add, then the carry loads.
func _land_supply_ids() -> Array:
	var out: Array = [ArmyOrderMenu.SUPPLY_ADD]
	for i in Game.data.army_carry_loads.size():
		out.append(ArmyOrderMenu.CARRY_BASE + i)
	return out


## Owner 2026-09-30 (军队到达目的地后自动驻防，取消驻防按钮): the regiment's
## menu has no Garrison row — a march garrisons on arrival.
func test_the_menu_offers_exactly_the_rows_in_the_table() -> void:
	_map.army_menu_requested.emit(_marcher(), Vector2(10.0, 10.0))
	for i in Game.data.army_orders.size():
		assert_eq(_menu.get_item_text(i), String(Game.data.army_orders[i]["label"]))
	assert_eq(_supply_ids(_menu), _land_supply_ids(), "the supply rows follow the march rows, and only they")
	for row: Dictionary in Game.data.army_orders:
		assert_ne(String(row["action_code"]), "ARMY_GARRISON", "no Garrison row")


## A land unit of the realm camped by a town but not seated in it, "" for none.
func _camper() -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		var c := String(r["regiment_code"])
		if ArmyGround.camped_by(Game.data, Game.state, c) != "" and ArmyGround.seated_in(Game.data, Game.state, c) == "":
			return c
	return ""


func _ids(menu: ArmyOrderMenu) -> Array:
	var out: Array = []
	for i in menu.item_count:
		out.append(menu.get_item_id(i))
	return out


## Spec 2026-10-07-army-split-and-ground §4.5: a camped unit may take its
## town's seat; the unit already inside has no such row; a draft never does.
func test_a_camped_unit_is_offered_the_seat_and_the_seated_one_is_not() -> void:
	var camper := _camper()
	assert_ne(camper, "")
	_map.army_menu_requested.emit(camper, Vector2(10.0, 10.0))
	assert_true(ArmyOrderMenu.SEAT in _ids(_menu), "the seat row")
	var i := _menu.get_item_index(ArmyOrderMenu.SEAT)
	assert_eq(_menu.get_item_text(i), String(Game.data.army_route_orders["seat"]["label"]))
	var town := ArmyGround.camped_by(Game.data, Game.state, camper)
	var seated := ArmyGround.seat_of(Game.data, Game.state, town)
	_map.army_menu_requested.emit(seated, Vector2(10.0, 10.0))
	assert_false(ArmyOrderMenu.SEAT in _ids(_menu), "the holder is inside already")
	Game.state.town_seat.erase(town)
	_map.army_menu_requested.emit(camper, Vector2(10.0, 10.0))
	i = _menu.get_item_index(ArmyOrderMenu.SEAT)
	assert_eq(_menu.get_item_text(i), String(Game.data.army_route_orders["seat_empty"]["label"]), "an empty seat reads Garrison the town")
	_menu.drafting = true
	_map.army_menu_requested.emit(camper, Vector2(10.0, 10.0))
	assert_false(ArmyOrderMenu.SEAT in _ids(_menu), "the war room's drafts never take the seat")


func test_choosing_the_seat_row_sends_a_courier() -> void:
	var camper := _camper()
	_map.army_menu_requested.emit(camper, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.SEAT)
	assert_eq(Game.state.couriers.size(), 1, "a courier rides with the seat order")
	_deliver_all()
	assert_eq(ArmyGround.seat_of(Game.data, Game.state, ArmyGround.camped_by(Game.data, Game.state, camper)), camper)


func test_choosing_march_only_AIMS_it_and_gives_the_map_the_word() -> void:
	var code := _marcher()
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)   # ARMY_MARCH is the first row
	assert_eq(_menu.aiming(), code, "the order waits for a destination")
	assert_true(_map.aiming, "and the map knows not to pick with the next click")
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY,
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
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.HALT)
	assert_eq(Game.state.couriers.size(), 1, "a courier rides with the halt")
	_deliver_all()
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON,
		"Cancel march chosen from a closing menu still halts it, once the courier delivers")


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
	watch_signals(Game)
	_commit()
	assert_eq(Game.state.couriers.size(), 1, "the order is given: a courier waits to ride")
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY, "the column waits for him")
	assert_eq(Game.clock_speed, 0, "but time stays stopped")
	assert_signal_emitted_with_parameters(Game, "news_published",
		["A courier will ride for %s when time runs." % String(ArmySystem.regiment(Game.data, code)["label"])])


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
	assert_eq(Game.state.couriers.size(), 1)
	_deliver_all()
	assert_eq(Game.state.couriers, [], "delivered")
	var dest := ArmySystem.destination_of(Game.data, Game.state, code)
	assert_almost_eq(dest.x, there.x, 0.002)
	assert_almost_eq(dest.y, there.y, 0.002)


func test_a_click_on_the_ground_with_nothing_aimed_orders_nothing() -> void:
	var code := _marcher()
	_map.ground_clicked.emit(Vector2(500.0, 300.0))
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY)


func test_an_order_the_engine_would_refuse_is_greyed_out_with_its_reason() -> void:
	# An empty chest cannot pay the column's provisions, and ActionSystem
	# refuses on that before anything else — so the row must be offered dead,
	# with the refusal as its tooltip, rather than live and then failing.
	var code := _marcher()
	Game.state.metrics["treasury"] = 0.0
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	for i in Game.data.army_orders.size():
		assert_true(_menu.is_item_disabled(i), _menu.get_item_text(i) + " cannot be paid for")
		assert_string_contains(_menu.get_item_tooltip(i), "afford")


func test_a_row_that_can_be_paid_for_is_live_and_says_what_it_does() -> void:
	_map.army_menu_requested.emit(_marcher(), Vector2(10.0, 10.0))
	for i in Game.data.army_orders.size():
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
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY,
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
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY)


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
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY)


## owner 2026-09-27: 兵人行进路线只能在暂停模式下选择，时间流逝的时候不可以操作.
func test_march_is_greyed_out_while_time_runs() -> void:
	var march := Game.data.army_orders.find_custom(func(row: Dictionary) -> bool:
		return String(row["action_code"]) == "ARMY_MARCH")
	assert_gt(march, -1, "the menu has a MARCH row")
	Game.set_clock_speed(1)
	_map.army_menu_requested.emit(_marcher(), Vector2(10.0, 10.0))
	assert_true(_menu.is_item_disabled(march), "MARCH")
	assert_eq(_menu.get_item_tooltip(march), String(Game.data.army_route_orders["paused_only"]["hint"]))
	# a halt is the route menu's Cancel march, greyed too (test_the_route_menu_is_paused_only)
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
	assert_eq(_menu.get_item_text(_menu.get_item_index(ArmyOrderMenu.HALT)),
		String(Game.data.army_route_orders["halt"]["label"]), "and Cancel march halts it (see above)")


## Owner 2026-09-28: the row confirms the order; it does not say "send courier".
func test_the_commit_row_confirms_the_order_and_names_the_fee() -> void:
	var row: Dictionary = Game.data.army_route_orders["commit"]
	assert_false(String(row["label"]).to_lower().contains("courier"))
	assert_string_contains(String(row["hint"]), "{fee}")


func test_the_route_menu_is_paused_only() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	ArmySystem.set_march(Game.data, Game.state, code, here + Vector2(30.0, 0.0))
	Game.set_clock_speed(1)
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	assert_true(_menu.is_item_disabled(0))
	assert_true(_menu.is_item_disabled(1))
	Game.set_clock_speed(0)


func _fleet() -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if not CourierSystem.carries_orders(r):
			return String(r["regiment_code"])
	return ""


## Final review M1: a fleet takes no courier yet, so its COMMIT and its
## Cancel march promise none and name no fee; a land regiment's still do.
func test_a_fleets_route_menus_promise_no_courier() -> void:
	var fleet := _fleet()
	assert_ne(fleet, "", "the realm has a fleet")
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, fleet))
	_map.army_menu_requested.emit(fleet, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(here + Vector2(20.0, 0.0))
	var commit := _menu.get_item_index(ArmyOrderMenu.COMMIT)
	assert_eq(_menu.get_item_text(commit), String(Game.data.army_route_orders["commit_fleet"]["label"]))
	assert_false(_menu.get_item_tooltip(commit).to_lower().contains("courier"), "no courier for a fleet")
	assert_false(_menu.get_item_tooltip(commit).contains("Fee"), "and no fee")
	_menu.id_pressed.emit(ArmyOrderMenu.CANCEL)
	ArmySystem.set_march(Game.data, Game.state, fleet, here + Vector2(30.0, 0.0))
	_map.route_clicked.emit(fleet, Vector2(10.0, 10.0))
	var halt := _menu.get_item_index(ArmyOrderMenu.HALT)
	assert_eq(_menu.get_item_tooltip(halt), String(Game.data.army_route_orders["halt_fleet"]["hint"]))
	# a land regiment's rows still send a courier
	var code := _marcher()
	var there := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	ArmySystem.set_march(Game.data, Game.state, code, there + Vector2(30.0, 0.0))
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	assert_string_contains(_menu.get_item_tooltip(_menu.get_item_index(ArmyOrderMenu.HALT)), "courier")


## The confirm opens at the CLICK, not wherever the OS cursor is (2026-09-30:
## a pushed click put it in the window's corner).
func test_the_confirm_opens_where_the_ground_was_clicked() -> void:
	var map := ClickMap.new()
	add_child_autofree(map)
	var menu := ArmyOrderMenu.new()
	add_child_autofree(menu)
	menu.follow(map)
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	menu.hide()
	menu.id_pressed.emit(0)
	map.ground_clicked.emit(there, Vector2(120.0, 70.0))
	assert_true(menu.visible, "COMMIT / CANCEL asked")
	assert_eq(menu.position, Vector2i(120, 70))


func test_aim_for_arms_a_march_on_a_paused_clock() -> void:
	var code := _marcher()
	assert_eq(_menu.aim_for(code), "")
	assert_eq(_menu.aiming(), code)
	assert_true(_map.aiming)


func test_aim_for_refuses_while_time_runs_and_arms_nothing() -> void:
	Game.set_clock_speed(1)
	var why := _menu.aim_for(_marcher())
	Game.set_clock_speed(0)
	assert_eq(why, String(Game.data.army_route_orders["paused_only"]["hint"]))
	assert_eq(_menu.aiming(), "")


func test_aim_for_then_ground_then_commit_runs_the_march() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code))
	var to := _land_near(here + Vector2(8.0, 0.0))
	assert_eq(_menu.aim_for(code), "")
	_map.ground_clicked.emit(to)
	assert_eq(_menu.pending(), to)
	_menu.id_pressed.emit(ArmyOrderMenu.COMMIT)
	assert_eq(_menu.aiming(), "")
	assert_false(CourierSystem.pending_for(Game.state, code).is_empty(), "a courier rides with the order")


## A map that is hidden never takes Escape (the closed WAR ROOM's view).
class SelMap extends Control:
	signal army_menu_requested(code: String, at: Vector2)
	signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
	var picked := "x"
	func selected_army() -> String:
		return picked
	func clear_selection() -> void:
		picked = ""


func _escape() -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_ESCAPE
	return e


func test_escape_lets_a_shown_maps_selection_go_but_a_hidden_map_keeps_it() -> void:
	var m := SelMap.new()
	add_child_autofree(m)
	var menu := ArmyOrderMenu.new()
	add_child_autofree(menu)
	menu.follow(m)
	m.visible = false
	menu._unhandled_input(_escape())
	assert_eq(m.picked, "x", "a hidden map is left alone")
	m.visible = true
	menu._unhandled_input(_escape())
	assert_eq(m.picked, "", "a shown map lets go")


## Owner 2026-10-06 (choice A): a town's garrison lists its regiments; the one
## chosen is selected on the map and its own orders open where the list stood.
class GarrisonMap extends Node:
	signal army_menu_requested(code: String, at: Vector2)
	signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
	signal garrison_menu_requested(codes: Array, at: Vector2)
	var aiming := false
	var aim_dest := Vector2(-1, -1)
	var selected := ""
	func select_army(code: String) -> void:
		selected = code


func test_a_garrison_lists_its_regiments_and_the_chosen_one_takes_orders() -> void:
	var menu := ArmyOrderMenu.new()
	add_child_autofree(menu)
	var map := GarrisonMap.new()
	add_child_autofree(map)
	menu.follow(map)
	var codes := MapObjects.garrison_of(Game.data, Game.state,
		MapObjects.royal_regiment(Game.data, Game.data.resolve_realm("player_realm")))
	assert_gt(codes.size(), 1)
	map.garrison_menu_requested.emit(codes, Vector2(40, 40))
	assert_true(menu.visible, "the list is up")
	assert_eq(menu.item_count, codes.size(), "a row a regiment")
	var second := ArmySystem.regiment(Game.data, String(codes[1]))
	assert_string_starts_with(menu.get_item_text(1), String(second["label"]))
	# choose the second, as a click does: the menu hides, then names the row
	menu.hide()
	menu.id_pressed.emit(ArmyOrderMenu.GARRISON_ROW + 1)
	await wait_process_frames(2)
	assert_eq(map.selected, String(codes[1]), "the chosen regiment is selected on the map")
	assert_true(menu.visible, "and its orders are open")
	assert_eq(_supply_ids(menu), _land_supply_ids(), "the regiment's own order rows, then its supply rows")
