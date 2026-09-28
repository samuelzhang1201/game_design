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


func _land() -> Vector2:
	var ids := Game.data.manors.keys()
	ids.sort()
	return MapTerrain.cell_center(Game.data, Game.data.cells[int(ids[ids.size() / 2])])


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
