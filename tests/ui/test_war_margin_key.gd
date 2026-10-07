extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM margin's key (spec 2026-10-01-war-room-design §2): a compass
## rose, the shared scale bar in the pack's measure restated on zoom, and the
## legend of the sheet's ink.

var repo: DataRepository
var state: GameState
var view: WarRoomView
var key: WarMarginKey


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()
	view = load("res://scenes/war_room/war_room.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1000, 600)
	add_child_autofree(view)
	view.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	view.set_active(true)
	key = WarMarginKey.new()
	add_child_autofree(key)
	key.setup(repo, view)


func _is_125(d: float) -> bool:
	var mag := pow(10.0, floorf(log(d) / log(10.0)))
	var lead := d / mag
	for step: float in [1.0, 2.0, 5.0]:
		if absf(lead - step) < 0.001:
			return true
	return false


func test_the_legend_lists_the_sheets_inks() -> void:
	assert_eq(WarMarginKey.legend_keys(), PackedStringArray(
		["road", "trail", "river", "border", "seam", "town", "peak", "contour", "wood", "manor", "walls", "port", "bridge", "ford", "supply", "courier", "weather", "spy",
		"mark_brigands", "mark_pirates", "mark_mines", "mark_battlefields", "mark_lighthouses",
		"hazard_plague", "hazard_unrest", "hazard_water", "hazard_rock",
		"works_arms", "works_horses", "works_ore", "works_naval", "market", "trade"]))
	for e: Dictionary in WarMarginKey.LEGEND:
		assert_false(String(e["label"]).is_empty(), String(e["key"]))


func test_units_per_px_by_hand() -> void:
	# 1 m away, 90° fov over 200 px: 2·1·tan(45°)/200 = 0.01 m a px; the sheet's
	# 400 pack px over a 2 m table is 200 px a metre, at 0.5 units a pack px
	assert_almost_eq(WarRoomView.units_per_px_at(1.0, 90.0, 200.0, 400.0, 2.0, 0.5), 1.0, 0.0001)
	assert_eq(WarRoomView.units_per_px_at(1.0, 90.0, 0.0, 400.0, 2.0, 0.5), 0.0, "no view, no scale")


func test_no_sheet_no_bar() -> void:
	assert_true(key.bar().is_empty())


func test_the_bar_restates_on_zoom_on_the_125_ladder() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.lean_to(repo.bal("war_cam_max_m"))
	var far := key.bar()
	view.lean_to(repo.bal("war_cam_min_m"))
	var near := key.bar()
	assert_false(far.is_empty())
	assert_false(near.is_empty())
	assert_true(_is_125(float(far["distance"])), "far: %s" % far["text"])
	assert_true(_is_125(float(near["distance"])), "near: %s" % near["text"])
	assert_gt(float(far["distance"]), float(near["distance"]), "leaning in shortens the bar's distance")
	assert_lte(float(near["width_px"]), repo.bal("war_key_scale_max_px") + 0.001)
	assert_true(String(far["text"]).ends_with(String(repo.map_info.get("distance_unit", "km"))))


func test_the_key_sizes_itself_from_data() -> void:
	var m := key.get_combined_minimum_size()
	assert_eq(m.x, repo.bal("war_key_width_px"))
	var rows := ceili(float(WarMarginKey.LEGEND.size()) / repo.bal("war_key_columns"))
	assert_almost_eq(m.y, repo.bal("war_key_rose_px") + repo.bal("war_key_gap_px") + float(rows) * repo.bal("war_key_row_px"), 0.01)


func test_a_click_on_the_rose_asks_for_north_and_nowhere_else_is_taken() -> void:
	watch_signals(key)
	var r := key.rose_rect()
	assert_true(key._has_point(r.get_center()))
	assert_false(key._has_point(Vector2(r.end.x + 20.0, r.end.y + 20.0)), "the legend lets clicks through to the room")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = r.get_center()
	key._gui_input(e)
	assert_signal_emitted(key, "north_pressed")


func test_the_key_lists_every_sheet_mark() -> void:
	var keys := WarMarginKey.legend_keys()
	for type: String in repo.war_marks:
		if String(repo.war_marks[type]["layer"]) == "sheet":
			assert_true(keys.has("mark_" + type), type)


func test_the_key_lists_every_works_family() -> void:
	var keys := WarMarginKey.legend_keys()
	for good: String in repo.war_works:
		assert_true(keys.has("works_" + String(repo.war_works[good]["family"])), good)
