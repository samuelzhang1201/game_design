extends GutTest

class FakeMap extends Node:
	signal ground_menu_requested(pack_px: Vector2, at: Vector2)

var _menu: SpyOrderMenu
var _map: FakeMap


func before_each() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)
	_menu = SpyOrderMenu.new()
	add_child_autofree(_menu)
	_map = FakeMap.new()
	add_child_autofree(_map)
	_menu.follow(_map)


## A point on foreign ground on purpose: the crown's controlled provinces refuse a spy.
func _land() -> Vector2:
	var ids := Game.data.manors.keys()
	ids.sort()
	for id: int in ids:
		if not SpySystem.province_controlled(Game.data, Game.state, MapManors.province_of(Game.data, id, Game.state)):
			var p := MapTerrain.cell_center(Game.data, Game.data.cells[id])
			if CourierSystem.spy_eta_days(Game.data, Game.state, p) <= int(Game.data.bal("courier_max_days")):
				return p
	assert_true(false, "no reachable foreign point")
	return Vector2(-1, -1)


func test_a_right_click_on_the_ground_offers_a_spy_and_sends_him() -> void:
	var at := _land()
	_map.ground_menu_requested.emit(at, Vector2(20, 20))
	assert_true(_menu.visible)
	assert_string_contains(_menu.get_item_text(0), "spy")
	_menu.hide()
	_menu.id_pressed.emit(SpyOrderMenu.SEND)
	assert_eq(Game.state.couriers.size(), 1)
	assert_eq(String(Game.state.couriers[0]["kind"]), "spy")


func test_every_land_card_offers_a_spy() -> void:
	var s := Game.state
	# Not every manor of the pack sits in a province (a "wildlands" cell has
	# none, data/maps/beria/political/manors.csv) — the first one that does,
	# so the province_card branch is genuinely exercised.
	var cell := -1
	for c: int in Game.data.manors.keys():
		if MapManors.province_of(Game.data, c, s) != "":
			cell = c
			break
	for card: Dictionary in [MapObjects.manor_card(Game.data, s, cell),
			MapObjects.province_card(Game.data, s, MapManors.province_of(Game.data, cell, s))]:
		var codes: Array = (card.get("actions", []) as Array).map(func(a: Dictionary) -> String: return String(a["action_code"]))
		assert_has(codes, "SPY_SEND", String(card["kind"]))


class AimMap extends Node:
	signal ground_menu_requested(pack_px: Vector2, at: Vector2)
	signal army_menu_requested(code: String, at: Vector2)
	@warning_ignore("unused_signal")
	signal ground_clicked(pack_px: Vector2)
	@warning_ignore("unused_signal")
	signal route_clicked(code: String, at: Vector2)
	var aiming := false
	var aim_code := ""
	var aim_dest := Vector2(-1, -1)


## M14 (final review): while a march is being AIMED, a right click on the
## ground gives the aim up (as Escape does) rather than offering a spy.
func test_a_right_click_while_aiming_withdraws_the_aim_not_a_spy() -> void:
	var map := AimMap.new()
	add_child_autofree(map)
	var army := ArmyOrderMenu.new()
	add_child_autofree(army)
	army.follow(map)
	var spies := SpyOrderMenu.new()
	add_child_autofree(spies)
	spies.follow(map, army)
	var code := String(MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state)[0]["regiment_code"])
	map.army_menu_requested.emit(code, Vector2(10, 10))
	army.hide()
	army.id_pressed.emit(0)   # MARCH: aims
	assert_eq(army.aiming(), code, "the march is being aimed")
	map.ground_menu_requested.emit(_land(), Vector2(20, 20))
	assert_false(spies.visible, "no spy is offered mid-aim")
	assert_eq(army.aiming(), "", "the aim is given up")
	assert_false(map.aiming)
	map.ground_menu_requested.emit(_land(), Vector2(20, 20))
	assert_true(spies.visible, "with no aim, the ground offers a spy again")
