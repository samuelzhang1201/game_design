extends GutTest
## The regiment's right-click orders (owner 2026-09-22): the menu's rows are
## data, MARCH is AIMED — the menu only arms the map and the next click on
## the ground is the destination — and every order goes through
## Game.try_execute, so it is validated and charged like any other.

## A stand-in for the map: ArmyOrderMenu.follow connects by signal NAME, the
## same way MapDetailPanel.follow does, so a test needs no 3D view at all.
class FakeMap extends Node:
	@warning_ignore("unused_signal")
	signal army_menu_requested(code: String, at: Vector2)
	@warning_ignore("unused_signal")
	signal ground_clicked(pack_px: Vector2)
	signal route_clicked(code: String, at: Vector2)
	signal route_bent(waypoints: PackedVector2Array)
	var aiming := false
	var aim_dest := Vector2(-1, -1)
	var aim_waypoints := PackedVector2Array()
	var supply_pick := {}
	var supply_preview := PackedVector2Array()
	## The map's selection (Map3DView.selected_armies), set by a test.
	var selection: Array = []

	func selected_armies() -> Array:
		return selection


## The 3D view's own signature: the click's point rides with it.
class ClickMap extends Node:
	@warning_ignore("unused_signal")
	signal army_menu_requested(code: String, at: Vector2)
	@warning_ignore("unused_signal")
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


var _max_days_kept := -1.0


func _set_max_days(days: float) -> void:
	if _max_days_kept < 0.0:
		_max_days_kept = Game.data.bal("supply_point_max_days")
	Game.data.balance["supply_point_max_days"] = days


func after_each() -> void:
	if _max_days_kept >= 0.0:
		Game.data.balance["supply_point_max_days"] = _max_days_kept
		_max_days_kept = -1.0


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


## What a land regiment of the realm with no supply point is offered: Add
## alone — the load is asked on the march's confirm (owner 2026-10-07).
func _land_supply_ids() -> Array:
	return [ArmyOrderMenu.SUPPLY_ADD]


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


## A battle stance row (spec 2026-10-07-enemy-ai-and-battle §4.4) sends its
## row's `params` stance with every selected unit: one ARMY_STANCE courier each,
## and each unit holds the stance once its courier has landed.
func test_a_stance_row_rides_to_every_selected_unit() -> void:
	var units: Array = []
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if units.size() < 2 and String(r.get("is_naval", "0")) != "1" and CourierSystem.carries_orders(r):
			units.append(String(r["regiment_code"]))
	assert_eq(units.size(), 2)
	_map.selection = units
	_map.army_menu_requested.emit(units[0], Vector2(10.0, 10.0))
	assert_eq(_menu.selected_codes(), units, "the menu orders the selection")
	var hold := -1
	for i in Game.data.army_orders.size():
		var row: Dictionary = Game.data.army_orders[i]
		if String(row["action_code"]) == "ARMY_STANCE" and String((row["params"] as Dictionary).get("stance", "")) == "hold":
			hold = i
	assert_gte(hold, 0, "a Hold row")
	assert_false(_menu.is_item_disabled(_menu.get_item_index(hold)), "the stance is an order the engine takes")
	_menu.hide()
	_menu.id_pressed.emit(hold)
	assert_eq(Game.state.couriers.size(), 2, "a courier for each unit")
	_deliver_all()
	Game.advance_day()
	for c: String in units:
		assert_eq(BattleSystem.stance_of(Game.state, c), "hold", c + " holds")


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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	Game.set_clock_speed(0)
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	watch_signals(Game)
	_menu.shown_confirm().select_supply("")   # no supply point: the march's courier alone
	_commit()
	assert_eq(Game.state.couriers.size(), 1, "the order is given: a courier waits to ride")
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY, "the column waits for him")
	assert_eq(Game.clock_speed, 0, "but time stays stopped")
	assert_signal_emitted_with_parameters(Game, "news_published",
		["A courier will ride for %s when time runs." % String(ArmySystem.regiment(Game.data, code, Game.state)["label"])])


## Confirm pressed on the march's confirm panel, as a click on it presses it.
func _commit(menu: ArmyOrderMenu = null) -> void:
	var m := menu if menu != null else _menu
	assert_not_null(m.shown_confirm(), "the confirm panel stands")
	if m.shown_confirm() != null:
		m.shown_confirm().confirm_button().pressed.emit()


func test_the_next_click_on_the_ground_sends_it_on_commit() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_menu.shown_confirm().select_supply("")   # no supply point: the march's courier alone
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
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
	var panel := _menu.shown_confirm()
	assert_not_null(panel, "the confirm panel asks")
	assert_eq(panel.confirm_button().text, String(Game.data.army_route_orders["commit"]["label"]))
	assert_eq(panel.add_button().text, String(Game.data.army_route_orders["add_waypoint"]["label"]))
	assert_eq(panel.cancel_button().text, String(Game.data.army_route_orders["cancel"]["label"]))
	assert_eq(panel.shown_rows().size(), Game.data.army_carry_loads.size(), "a row for every load")


func test_cancel_gives_the_march_up() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_menu.shown_confirm().cancel_button().pressed.emit()
	assert_null(_menu.shown_confirm(), "the panel goes")
	assert_eq(_menu.aiming(), "")
	assert_eq(_map.aim_dest, Vector2(-1, -1))
	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_STANDBY)


## Spec 2026-10-07-march-waypoints ruling 7: the confirm stands while the map
## is clicked (the route is bent there); Escape gives it up.
func test_a_click_away_from_the_confirm_leaves_it_and_escape_gives_it_up() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(there)
	_map.ground_clicked.emit(there + Vector2(3, 3))
	await wait_process_frames(2)
	assert_eq(_menu.aiming(), code, "a click away keeps the route")
	assert_eq(_menu.pending(), there, "and its end")
	assert_not_null(_menu.shown_confirm())
	_menu._unhandled_input(_escape())
	assert_eq(_menu.aiming(), "")
	assert_null(_menu.shown_confirm())
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	ArmySystem.set_march(Game.data, Game.state, code, here + Vector2(30.0, 0.0))
	_map.route_clicked.emit(code, Vector2(10.0, 10.0))
	assert_eq(_menu.item_count, 2)
	assert_eq(_menu.get_item_text(0), String(Game.data.army_route_orders["edit"]["label"]))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.EDIT)
	assert_eq(_menu.aiming(), code, "Edit takes the march up")
	assert_almost_eq(_menu.pending().distance_to(here + Vector2(30.0, 0.0)), 0.0, 0.002,
		"its end loaded for the confirm (spec 2026-10-07-march-waypoints ruling 10)")
	assert_not_null(_menu.shown_confirm())
	_menu.shown_confirm().cancel_button().pressed.emit()
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, fleet, Game.state))
	_map.army_menu_requested.emit(fleet, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(here + Vector2(20.0, 0.0))
	var commit := _menu.shown_confirm().confirm_button()
	assert_eq(commit.text, String(Game.data.army_route_orders["commit_fleet"]["label"]))
	assert_false(commit.tooltip_text.to_lower().contains("courier"), "no courier for a fleet")
	assert_false(commit.tooltip_text.contains("Fee"), "and no fee")
	assert_eq(_menu.shown_confirm().shown_rows(), [], "a fleet carries no train: no loads")
	_menu.shown_confirm().cancel_button().pressed.emit()
	ArmySystem.set_march(Game.data, Game.state, fleet, here + Vector2(30.0, 0.0))
	_map.route_clicked.emit(fleet, Vector2(10.0, 10.0))
	var halt := _menu.get_item_index(ArmyOrderMenu.HALT)
	assert_eq(_menu.get_item_tooltip(halt), String(Game.data.army_route_orders["halt_fleet"]["hint"]))
	# a land regiment's rows still send a courier
	var code := _marcher()
	var there := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var there := _land_near(here)
	if there == Vector2.ZERO:
		return
	map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	menu.hide()
	menu.id_pressed.emit(0)
	map.ground_clicked.emit(there, Vector2(120.0, 70.0))
	assert_not_null(menu.shown_confirm(), "the confirm asked")
	assert_eq(menu.shown_confirm().global_position, Vector2(134.0, 84.0), "beside the click, not the OS cursor")


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
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var to := _land_near(here + Vector2(8.0, 0.0))
	assert_eq(_menu.aim_for(code), "")
	_map.ground_clicked.emit(to)
	assert_eq(_menu.pending(), to)
	_commit()
	assert_eq(_menu.aiming(), "")
	assert_false(CourierSystem.pending_for(Game.state, code).is_empty(), "a courier rides with the order")


## A map that is hidden never takes Escape (the closed WAR ROOM's view).
class SelMap extends Control:
	@warning_ignore("unused_signal")
	signal army_menu_requested(code: String, at: Vector2)
	@warning_ignore("unused_signal")
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


## Every unit holds its own ground (spec 2026-10-07-army-split-and-ground §5.1):
## a unit standing with others round its town opens its OWN orders, never a
## list of the town's units to choose from.
func test_a_unit_round_a_town_opens_its_own_orders_not_a_list() -> void:
	assert_false((ArmyOrderMenu as Script).get_script_constant_map().has("GARRISON_ROW"),
		"no garrison list rows")
	var camper := _camper()
	var town := ArmyGround.camped_by(Game.data, Game.state, camper)
	var seated := ArmyGround.seat_of(Game.data, Game.state, town)
	assert_ne(seated, "", "the town's seat is held")
	var labels: Array = []
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if ArmyGround.camped_by(Game.data, Game.state, String(r["regiment_code"])) == town:
			labels.append(String(r["label"]))
	assert_gt(labels.size(), 1, "more than one unit stands round the town")
	var map := ClickMap.new()
	add_child_autofree(map)
	var menu := ArmyOrderMenu.new()
	add_child_autofree(menu)
	menu.follow(map)
	map.army_menu_requested.emit(seated, Vector2(40, 40))
	assert_true(menu.visible, "its orders are open")
	for i in Game.data.army_orders.size():
		assert_eq(menu.get_item_text(i), String(Game.data.army_orders[i]["label"]), "the order rows first")
	for i in menu.item_count:
		for label: String in labels:
			assert_false(menu.get_item_text(i).begins_with(label), "no row names a unit: %s" % label)
	assert_eq(_supply_ids(menu), _land_supply_ids(), "the unit's own order rows, then its supply rows")


## Owner 2026-10-07 (item 9): Add waypoint keeps the point and aims on; the
## next click is the end; Confirm sends the route, the courier carrying it.
func test_add_waypoint_aims_on_and_confirm_sends_the_route() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var wp := _land_near(here)
	var to := _land_near(here + Vector2(6.0, 0.0))
	if wp == Vector2.ZERO or to == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(wp)
	_menu.shown_confirm().add_button().pressed.emit()
	assert_null(_menu.shown_confirm(), "the panel steps aside for the next click")
	assert_eq(_menu.waypoints(), [wp])
	assert_eq(_map.aim_waypoints, PackedVector2Array([wp]), "the map draws through it")
	assert_eq(_map.aim_dest, Vector2(-1, -1), "and aims on from it")
	_map.ground_clicked.emit(to)
	assert_eq(_menu.pending(), to)
	_commit()
	var order: Dictionary = CourierSystem.march_order(CourierSystem.pending_for(Game.state, code))
	assert_eq((order["waypoints_m"] as Array).size(), 1, "the courier carries the route")
	assert_eq(_map.aim_waypoints, PackedVector2Array(), "the plan is spent")


## Owner 2026-10-07 (item 7): the load is chosen on the confirm; a new one
## runs before the march — on the same courier (owner 2026-10-10).
func test_a_load_chosen_on_the_confirm_rides_before_the_march() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var to := _land_near(here)
	if to == Vector2.ZERO:
		return
	var own := ArmySystem.carry_of(Game.data, Game.state.regiments[code])
	var other := 30 if own != 30 else 10
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(to)
	var panel := _menu.shown_confirm()
	var pressed: Array = panel.shown_rows().filter(func(r: Dictionary) -> bool: return bool(r["pressed"]))
	assert_eq(pressed.size(), 1, "one load pressed")
	assert_eq(int(pressed[0]["days"]), own, "the load it carries now")
	panel.pick(other)
	assert_eq(panel.chosen_carry(), other)
	panel.select_supply("")   # no supply point: the load and the march alone
	_commit()
	assert_eq(Game.state.couriers.size(), 1, "one courier carries both")
	var kinds: Array = CourierSystem.orders_of(Game.state.couriers[0]).map(
		func(o: Dictionary) -> String: return String(o["action_code"]))
	assert_eq(kinds, ["SUPPLY_CARRY_SET", "ARMY_MARCH"])


## Ruling 9: a bend the regiment could not walk (a waypoint in the sea) is put back.
func test_a_bend_into_the_sea_is_put_back() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var to := _land_near(here)
	if to == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(to)
	var land := (here + to) * 0.5
	if MapEconomy.cell_at(Game.data, land) >= 0:
		_map.aim_waypoints = PackedVector2Array([land])
		_map.route_bent.emit(_map.aim_waypoints)
		assert_eq(_menu.waypoints(), [land], "a bend on land is kept")
	_map.aim_waypoints = PackedVector2Array([Vector2(-50, -50)])
	_map.route_bent.emit(_map.aim_waypoints)
	assert_eq(_map.aim_waypoints, PackedVector2Array(_menu.waypoints()), "off the map: put back")


## Spec 2026-10-08-war-room-draw-orders rulings 13-15: the confirm asks where
## to supply the march from; the towns are lit on the map, a click on a lit
## one chooses it, and Confirm sends the supply point, then the march — ONE
## courier to the regiment carrying both (owner 2026-10-10).
func test_a_supply_town_chosen_on_the_confirm_rides_before_the_march() -> void:
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var to := _land_near(here)
	if to == Vector2.ZERO:
		return
	_map.army_menu_requested.emit(code, Vector2(10.0, 10.0))
	_menu.hide()
	_menu.id_pressed.emit(0)
	_map.ground_clicked.emit(to)
	assert_not_null(_menu.shown_confirm())
	var ok := SupplyLines.march_eligibility(Game.data, Game.state, code, to)
	var order := SupplyLines.rear_order(Game.data, Game.state, code, ok)
	assert_eq(_menu.supply_choice(), String(order[0]) if String(ok[order[0]]) == "" else "",
		"no line yet: the nearest town on our side pressed (ruling 20)")
	_menu.shown_confirm().select_supply("")
	var town := ""
	for t: String in order:
		if String(ok[t]) == "":
			town = t
			break
	assert_ne(town, "")
	var b: Dictionary = Game.data.burgs[town]
	_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])))   # a click on the lit town
	assert_eq(_menu.supply_choice(), town, "the click chose it")
	assert_eq(_menu.pending(), to, "and the march's end stayed")
	_commit()
	assert_eq(Game.state.couriers.size(), 1, "one courier for the target")
	var c: Dictionary = Game.state.couriers[0]
	var kinds: Array = CourierSystem.orders_of(c).map(func(o: Dictionary) -> String: return String(o["action_code"]))
	assert_eq(kinds, ["SUPPLY_POINT_SET", "ARMY_MARCH"], "the supply point runs first")
	assert_eq(String(c["target"]), code, "he rides for the regiment, not the town")
	assert_eq(String(CourierSystem.first_order(c).get("to_town", "")), "")


## Owner 2026-10-08 (spec 2026-10-08-war-room-draw-orders ruling 20): a town
## AHEAD of the column is greyed with its reason; the town pressed is the
## nearest allowed one on our side, listed first after the current point.
func test_a_town_ahead_is_greyed_and_the_nearest_rear_town_is_pressed() -> void:
	# the wagons go round slopes now (owner 2026-10-11), their roads are
	# longer, and a town ahead of this column was no longer in reach of ten days
	_set_max_days(20.0)
	var code := _marcher()
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var now := SupplyLines.eligibility(Game.data, Game.state, code)
	var towns: Array = now.keys()
	towns.sort()
	var ahead := ""   # a town the column can be sent to, farther from the capital than the column
	var rear := CourierSystem.origin(Game.data, Game.state)
	var tol := Game.data.bal("supply_ahead_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(Game.data))
	for t: String in towns:
		var burg: Dictionary = Game.data.burgs[t]
		var at := Vector2(float(burg["x"]), float(burg["y"]))
		if String(now[t]) == "" and at.distance_to(rear) > here.distance_to(rear) + tol * 2.0 and Game.engine.actions.validate_place(
				ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": at.x, "y": at.y}), Game.state) == "":
			ahead = t
			break
	if ahead == "":
		pending("no town to march on")
		return
	var b: Dictionary = Game.data.burgs[ahead]
	var to := Vector2(float(b["x"]), float(b["y"]))
	assert_eq(_menu.aim_for(code), "")
	_map.ground_clicked.emit(to)   # the march ends ON the town, which lies on the frontier side of the column
	var panel := _menu.shown_confirm()
	assert_not_null(panel)
	var rows := panel.shown_supply()
	var row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return String(r["town"]) == ahead)[0]
	assert_true(bool(row["disabled"]), "the town ahead cannot be chosen")
	assert_string_contains(String(row["why"]), "frontier side of the column")
	assert_ne(_menu.supply_choice(), ahead)
	var ok := SupplyLines.march_eligibility(Game.data, Game.state, code, to)
	var first := ""
	for t: String in SupplyLines.rear_order(Game.data, Game.state, code, ok):
		if String(ok[t]) == "":
			first = t
			break
	assert_eq(_menu.supply_choice(), first, "the nearest town on our side pressed")
	if first != "":
		assert_eq(String(rows[1]["town"]), first, "and listed first after the current point")
		assert_true(bool(rows[1]["selected"]))
		assert_gt(_map.supply_preview.size(), 1, "its road to the end is drawn")
	for r: Dictionary in rows.slice(1):
		var t := String(r["town"])
		if not bool(r["disabled"]):
			var tb: Dictionary = Game.data.burgs[t]
			assert_false(SupplyLines.is_ahead(Game.data, rear, here, Vector2(float(tb["x"]), float(tb["y"]))), t + " is not ahead")
	panel.select_supply("")
	_map.route_bent.emit(PackedVector2Array())   # a re-open keeps the player's own choice
	assert_eq(_menu.supply_choice(), "", "the player's none is kept")
