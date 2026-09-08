extends GutTest
## The RTS-style world map embedded in the court screen's middle zone
## (user ruling 2026-09-03: the map IS the middle view; MAP tab returned
## to "close overlays" — that behavior is pinned by test_ui_rework).

func _view() -> WorldMapView:
	var v := WorldMapView.create()
	v.size = Vector2(320, 180)
	add_child_autofree(v)
	return v

func test_court_screen_embeds_the_world_map() -> void:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_not_null(screen.world_map(), "court builds a WorldMapView")
	assert_true(screen.world_map().visible, "map assets exist, so it shows")

func test_selecting_a_kingdom_opens_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	var row: Dictionary = Game.data.kingdoms["hetalia"]
	v.select_state(int(row["state_id"]))
	assert_true(v.card().visible)
	assert_eq(v.card_title().text, String(row["label"]))

func test_water_click_closes_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_state(int(Game.data.kingdoms["hetalia"]["state_id"]))
	v.select_state(-1)
	assert_false(v.card().visible, "water/no-state closes the card")

## The opening framing fills the frame — a contain fit would letterbox
## roughly half the column height on this 2.76:1 map and leave the dead
## band the middle column is meant to stop showing.
func test_opens_filling_the_frame() -> void:
	var v := _view()
	await wait_frames(2)
	var drawn := Rect2(v._offset, v._map_texture.get_size() * v._zoom)
	assert_true(drawn.position.x <= 1.0, "no gutter on the left")
	assert_true(drawn.position.y <= 1.0, "no gutter on the top")
	assert_true(drawn.end.x >= v.size.x - 1.0, "no gutter on the right")
	assert_true(drawn.end.y >= v.size.y - 1.0, "no gutter on the bottom")

## ...and the whole world stays one wheel-out away. Asserts the visible
## property, not the formula: a cover-fit floor would satisfy
## "_zoom == _zoom_min()" while cropping a quarter of the map off the sides.
func test_zooming_out_reaches_the_whole_map() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	var drawn := Rect2(v._offset, v._map_texture.get_size() * v._zoom)
	assert_true(drawn.position.x >= -1.0, "nothing cropped off the left")
	assert_true(drawn.position.y >= -1.0, "nothing cropped off the top")
	assert_true(drawn.end.x <= v.size.x + 1.0, "nothing cropped off the right")
	assert_true(drawn.end.y <= v.size.y + 1.0, "nothing cropped off the bottom")
	assert_almost_eq(drawn.get_center().x, v.size.x / 2.0, 1.0, "centered x")
	assert_almost_eq(drawn.get_center().y, v.size.y / 2.0, 1.0, "centered y")

func test_wheel_zoom_in_magnifies_and_out_floors_at_the_whole_map() -> void:
	var v := _view()
	await wait_frames(2)
	var opening := v._zoom
	v._zoom_at(v.size / 2.0, 4.0)
	assert_gt(v._zoom, opening, "wheel up magnifies")
	v._zoom_at(v.size / 2.0, 0.0001)
	assert_almost_eq(v._zoom, v._zoom_min(), 0.0001,
		"wheel down floors at the whole map, never smaller")
	assert_lt(v._zoom, opening, "the whole map sits wider out than the opening")

## Regression guard: the map shares the court screen with the log and
## council columns. If it ever covers or hides them there is no way to
## issue an order or end the turn.
func test_court_keeps_the_order_panels_beside_the_map() -> void:
	var screen: CourtScreen = load("res://scenes/court.tscn").instantiate()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_true(screen.get_node("%LogPanel").is_visible_in_tree(),
		"court log column stays visible")
	assert_true(screen.get_node("%SidePanel").is_visible_in_tree(),
		"council column stays visible")
	assert_true(screen.end_turn_button().is_visible_in_tree(),
		"End Turn stays reachable")

## Hover: the kingdom under the mouse gets its border outlined (user request
## 2026-09-08). Loops come from the pack's borders.csv; -1 (water/no state)
## clears the outline.
func test_hovering_a_kingdom_outlines_its_border() -> void:
	var v := _view()
	await wait_frames(1)
	var sid := int(Game.data.kingdoms["hetalia"]["state_id"])
	v.hover_state(sid)
	assert_eq(v.hovered_state(), sid)
	assert_gt(v.hover_loops().size(), 0, "hovered kingdom has border loops to draw")
	v.hover_state(-1)
	assert_eq(v.hovered_state(), -1, "water/no-state clears the hover")
	assert_eq(v.hover_loops().size(), 0)

func test_mouse_motion_over_a_kingdom_sets_the_hover() -> void:
	var v := _view()
	await wait_frames(2)
	var row: Dictionary = Game.data.kingdoms["hetalia"]
	var mm := InputEventMouseMotion.new()
	mm.position = v.map_to_screen(Vector2(float(row["center_x"]), float(row["center_y"])))
	v._gui_input(mm)
	assert_eq(v.hovered_state(), int(row["state_id"]))

## Pins: capitals always; towns and villages appear as the player zooms in
## (thresholds in balance.csv, rule in MapObjects).
func test_town_pins_appear_as_the_view_zooms_in() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	var far := v.visible_burg_count()
	assert_eq(far, 16, "zoomed all the way out: one pin per capital")
	v._zoom_at(v.size / 2.0, 1000.0)
	assert_gt(v.view_scale(), Game.data.bal("map_lod_village_scale"))
	assert_eq(v.visible_burg_count(), Game.data.burgs.size(), "zoomed in: every burg")

func test_hovering_a_capital_names_it() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	assert_eq(v.hovered_object().get("kind", ""), "burg")
	assert_eq(v.hovered_object().get("code", ""), "kuojarpan")
	assert_eq(v.hover_tooltip(), "Kuojarpan")
	assert_eq(v.hovered_state(), int(Game.data.kingdoms["hetalia"]["state_id"]),
		"the kingdom outline stays on under a pin")

func test_hovering_open_sea_clears_the_tooltip() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	v.hover_at(v.map_to_screen(Vector2(5.0, 5.0)))  # top-left ocean corner
	assert_eq(v.hovered_object().get("kind", ""), "water")
	assert_eq(v.hover_tooltip(), "")

## Cards per object kind (MapInfoCard renders what MapObjects.describe says).
func test_selecting_a_town_opens_its_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_true(v.card().visible)
	assert_eq(v.card_title().text, "Kuojarpan")
	assert_true(v.card().body_label().text.begins_with("Capital of Onjormaa, Hetalia"))

func test_selecting_land_leads_with_province_and_terrain() -> void:
	var v := _view()
	await wait_frames(1)
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	v.select_object({"kind": "land", "state_id": int(Game.data.kingdoms["hetalia"]["state_id"]),
		"province_id": 72, "biome_id": 6, "x": float(k["x"]), "y": float(k["y"])})
	assert_eq(v.card_title().text, "Onjormaa")
	var body := v.card().body_label().text
	assert_true(body.begins_with("Hetalia\nTerrain: Temperate deciduous forest"), body)
	assert_true(body.contains("Capital: Kuojarpan"), "kingdom overview follows")

func test_selecting_water_closes_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	v.select_object({"kind": "water"})
	assert_false(v.card().visible)

func test_ask_button_is_off_until_a_screen_enables_it() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_false(v.card().ask_button().visible, "no input box wired: no Ask")
	v.set_ask_enabled(true)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_true(v.card().ask_button().visible)

var _asked := ""

func test_ask_emits_the_question_for_the_selected_place() -> void:
	var v := _view()
	await wait_frames(1)
	v.set_ask_enabled(true)
	v.place_asked.connect(func(text: String) -> void: _asked = text)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	v.card().ask_button().pressed.emit()
	assert_eq(_asked, "What do we know of Kuojarpan?")

## The tooltip must stay readable at the frame's edge: a pin hovered in the
## bottom-right corner gets its label pushed back inside the view.
func test_tooltip_stays_inside_the_view_at_the_edge() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 1000.0)  # deep zoom: the map overflows every side
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	var kp := Vector2(float(k["x"]), float(k["y"]))
	var corner := v.size - Vector2(2.0, 2.0)
	v._offset = corner - kp * v.view_scale()  # park the capital in the corner
	v.hover_at(corner)
	assert_eq(v.hover_tooltip(), "Kuojarpan")
	var r := v.tooltip_rect()
	assert_true(Rect2(Vector2.ZERO, v.size).encloses(r),
		"tooltip %s stays inside the view %s" % [r, v.size])

## The map is a scene like every other view (character portraits, locations,
## user request 2026-09-08), not a bare .new() — so it can be opened and
## decorated in the editor, and every screen gets the same one.
func test_create_instantiates_from_the_scene_file() -> void:
	var v := WorldMapView.create()
	add_child_autofree(v)
	await wait_frames(1)
	assert_eq(v.scene_file_path, WorldMapView.SCENE_PATH, "came from the scene file")
	assert_not_null(v.card(), "and is fully wired")

func test_every_gameplay_screen_uses_the_map_scene() -> void:
	for path in ["res://scenes/court.tscn", "res://scenes/conversation.tscn",
			"res://scenes/day_run.tscn"]:
		var screen: Control = load(path).instantiate()
		add_child_autofree(screen)
		await wait_frames(1)
		var map: WorldMapView = screen.find_child("WorldMap", true, false)
		assert_not_null(map, "%s embeds the map" % path.get_file())
		assert_eq(map.scene_file_path, WorldMapView.SCENE_PATH,
			"%s builds it from the scene, not .new()" % path.get_file())
