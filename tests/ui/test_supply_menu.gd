extends GutTest
## The supply rows of the regiment's menu (spec 2026-10-07-army-supply-lines §5.1–5.2),
## driven in the engine's real order: right click, row, click on the ground, rate.

class FakeMap extends Node:
	signal army_menu_requested(code: String, at: Vector2)
	signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
	var aiming := false
	var aim_dest := Vector2(-1, -1)
	var supply_pick: Dictionary = {}
	var supply_preview := PackedVector2Array()
	var picked := "x"
	func selected_army() -> String:
		return picked
	func clear_selection() -> void:
		picked = ""

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

func _land() -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""

func _row(label_key: String) -> int:
	var label := String(Game.data.army_supply_orders[label_key]["label"])
	for i in _menu.item_count:
		if _menu.get_item_text(i) == label:
			return _menu.get_item_id(i)
	return -1

func test_add_supply_point_lights_the_eligible_towns() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	var id := _row("add")
	assert_ne(id, -1, "the Add supply point row is offered")
	_menu.hide()
	_menu.id_pressed.emit(id)
	assert_eq(_menu.supply_picking(), code)
	assert_eq(_map.supply_pick, SupplyLines.eligibility(Game.data, Game.state, code))
	assert_true(_map.aiming, "the next click only says where it landed")

func test_clicking_a_lit_town_then_a_rate_sends_the_order() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.hide()
	_menu.id_pressed.emit(_row("add"))
	var town := ""
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) == "":
			town = t
			break
	var b: Dictionary = Game.data.burgs[town]
	_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
	assert_eq(_menu.supply_town(), town)
	assert_true(_map.supply_preview.size() >= 2, "the road is drawn while the rate is asked")
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.RATE_BASE + 2)   # 1.2x
	assert_eq(String(SupplyLines.line(Game.state, code).get("state", "")), SupplyLines.ORDERED)
	assert_eq(int(SupplyLines.line(Game.state, code)["rate"]), 1200)
	assert_eq(_map.supply_pick, {}, "pick mode ends")
	assert_eq(_menu.supply_picking(), "")
	assert_false(_map.aiming)

func test_the_rate_rows_carry_the_fee_and_the_road() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	var town := ""
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) == "":
			town = t
			break
	var b: Dictionary = Game.data.burgs[town]
	_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
	var first := _menu.get_item_index(ArmyOrderMenu.RATE_BASE)
	assert_string_contains(_menu.get_item_text(first), "0.8")
	assert_string_contains(_menu.get_item_tooltip(first), String(b["label"]))
	# tenths of a gold a day (final review 4); the courier's ride to the TOWN (5)
	var re := RegEx.create_from_string("— \\d+\\.\\d gold a day$")
	assert_not_null(re.search(_menu.get_item_text(first)), _menu.get_item_text(first))
	var ride := CourierSystem.eta_days_to(Game.data, Game.state, CourierSystem.ORDINARY,
		Vector2(float(b["x"]), float(b["y"])))
	assert_string_contains(_menu.get_item_tooltip(first), "the courier rides %d days" % ride)
	assert_ne(_menu.get_item_index(ArmyOrderMenu.CANCEL), -1, "and a Cancel row")

func test_a_greyed_town_says_why_and_keeps_picking() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) != "":
			var b: Dictionary = Game.data.burgs[t]
			watch_signals(Game)
			_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
			assert_eq(_menu.supply_town(), "")
			assert_eq(_menu.supply_picking(), code)
			assert_signal_emitted_with_parameters(Game, "news_published", [String(_map.supply_pick[t])])
			return
	pending("every town is in reach on this pack")

func test_escape_leaves_pick_mode() -> void:
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	_menu._unhandled_input(ev)
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_pick, {})
	assert_false(_map.aiming)

func test_cancel_in_the_rate_menu_leaves_pick_mode() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	var town := ""
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) == "":
			town = t
			break
	var b: Dictionary = Game.data.burgs[town]
	_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.CANCEL)
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_preview.size(), 0)
	assert_true(SupplyLines.line(Game.state, code).is_empty(), "nothing was ordered")

func test_clicking_away_from_the_rates_gives_it_up() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	var town := ""
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) == "":
			town = t
			break
	var b: Dictionary = Game.data.burgs[town]
	_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
	_menu.hide()   # closed with no row chosen
	await wait_process_frames(2)
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_pick, {})

func test_starting_the_clock_withdraws_the_pick() -> void:
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	Game.set_clock_speed(1)
	await wait_process_frames(2)
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_pick, {})
	Game.set_clock_speed(0)

func test_carry_rows_send_the_load_order() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.CARRY_BASE + 4)   # 30 days
	# pending_for passes SUPPLY_* orders by (they never move a march), so read the couriers
	assert_eq(Game.state.couriers.size(), 1, "a courier waits to ride")
	var order: Dictionary = Game.state.couriers[0]["order"]
	assert_eq(String(order["action_code"]), "SUPPLY_CARRY_SET")
	assert_eq(String(Game.state.couriers[0]["target"]), code)

func test_the_menu_greys_add_while_time_runs_and_says_why() -> void:
	Game.set_clock_speed(1)
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	var i := _menu.get_item_index(_row("add"))
	assert_true(_menu.is_item_disabled(i))
	assert_eq(_menu.get_item_tooltip(i), String(Game.data.army_route_orders["paused_only"]["hint"]))
	Game.set_clock_speed(0)

## Final review 9: Withdraw and the carry loads are paused-clock orders too.
func test_the_menu_greys_withdraw_and_carry_while_time_runs() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(Game.data, Game.state)[0]
	Game.state.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	Game.state.supply_lines[code]["state"] = SupplyLines.FLOWING
	Game.set_clock_speed(1)
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	var why := String(Game.data.army_route_orders["paused_only"]["hint"])
	var ids: Array = [_row("withdraw")]
	for i in Game.data.army_carry_loads.size():
		ids.append(ArmyOrderMenu.CARRY_BASE + i)
	for id: int in ids:
		var i := _menu.get_item_index(id)
		assert_ne(i, -1, "row %d is offered" % id)
		assert_true(_menu.is_item_disabled(i), "row %d is greyed" % id)
		assert_eq(_menu.get_item_tooltip(i), why)
	# a click that slips through still orders nothing
	var riding := Game.state.couriers.size()
	_menu.hide()
	_menu.id_pressed.emit(ArmyOrderMenu.CARRY_BASE + 4)
	_menu.id_pressed.emit(_row("withdraw"))
	assert_eq(Game.state.couriers.size(), riding, "nothing rides while time runs")
	Game.set_clock_speed(0)
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	for id: int in ids:
		assert_false(_menu.is_item_disabled(_menu.get_item_index(id)), "paused, row %d is offered" % id)

func test_a_fleet_has_no_supply_rows() -> void:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) == "1":
			_map.army_menu_requested.emit(String(r["regiment_code"]), Vector2(10, 10))
			assert_eq(_row("add"), -1)
			return
	pending("no fleet in the realm")

func _escape() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	return ev

func test_escape_ends_the_pick_before_it_lets_the_selection_go() -> void:
	# a left click selects the regiment before its menu opens
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	_menu._unhandled_input(_escape())
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_pick, {})
	assert_false(_map.aiming)
	assert_eq(_map.picked, "x", "the selection is untouched")
	_menu._unhandled_input(_escape())
	assert_eq(_map.picked, "", "the next Escape lets it go")

func _other_land(not_code: String) -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) != "1" and String(r["regiment_code"]) != not_code \
				and ArmySystem.base_pace_km(Game.data, r) > 0:
			return String(r["regiment_code"])
	return ""

func test_opening_another_regiments_menu_ends_the_pick() -> void:
	var first := _land()
	var second := _other_land(first)
	_map.army_menu_requested.emit(first, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	_map.army_menu_requested.emit(second, Vector2(10, 10))
	assert_eq(_menu.supply_picking(), "", "the pick is gone")
	assert_eq(_map.supply_pick, {})
	_menu.hide()
	_menu.id_pressed.emit(0)   # MARCH
	assert_eq(_menu.aiming(), second)
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, second))
	_map.ground_clicked.emit(here + Vector2(20.0, 0.0), Vector2(20, 20))
	assert_eq(_menu.supply_town(), "", "the click was the march's, not a supply pick")
	assert_ne(_menu.pending(), Vector2(-1, -1), "COMMIT is asked")

func test_withdraw_aim_ends_a_pick() -> void:
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	_menu.withdraw_aim()
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_pick, {})
	assert_false(_map.aiming)

func test_the_war_room_menu_offers_no_supply_rows() -> void:
	_menu.drafting = true
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	for i in _menu.item_count:
		assert_lt(_menu.get_item_id(i), ArmyOrderMenu.SUPPLY_ADD, "no supply row in the war room")
