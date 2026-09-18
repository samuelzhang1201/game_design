extends GutTest
## MILITARY on the 3D map (owner 2026-09-19: "迁移军事地图。注意兵棋大小" /
## "点击兵棋可以看到该部队信息"): the player's regiments as the 2D map's
## counters (ArmyCounters) on the 3D HUD, sized by the view but held between
## map3d_army_badge_min_px and map3d_army_badge_max_px so they read at every
## zoom and never swamp the map; a click on one opens the regiment's card.

const FIXTURE := "user://test_map3d_military_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func _first_regiment() -> Dictionary:
	return MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"))[0]


func _look_at_regiment(v: Map3DView, r: Dictionary, at_m: float) -> void:
	v.look_at_pack(Vector2(float(r["x"]), float(r["y"])), at_m)


func _click(v: Map3DView, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	v._gui_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	v._gui_input(up)


func test_no_counters_while_the_layer_is_off() -> void:
	var v := _view()
	_look_at_regiment(v, _first_regiment(), 20000.0)
	assert_eq(v.army_markers().size(), 0)


func test_the_players_regiments_stand_as_counters() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	_look_at_regiment(v, r, 20000.0)
	var mine: Dictionary = {}
	for m: Dictionary in v.army_markers():
		if String(m["code"]) == String(r["regiment_code"]):
			mine = m
	assert_false(mine.is_empty(), "the regiment under the camera has its counter")
	assert_almost_eq((mine["pos"] as Vector2).x, v.size.x * 0.5, 2.0)
	assert_eq(String(mine["text"]), str(int(MapObjects.regiment_size(Game.data, r))))


func test_a_counters_size_is_held_between_its_bounds() -> void:
	var v := _view()
	v.set_military(true)
	var lo := Game.data.bal("map3d_army_badge_min_px")
	var hi := Game.data.bal("map3d_army_badge_max_px")
	for at_m: float in [Game.data.bal("map3d_zoom_min_m"), 20000.0, Game.data.bal("map3d_zoom_max_m")]:
		_look_at_regiment(v, _first_regiment(), at_m)
		var h := v.army_badge_height()
		assert_between(h, lo, hi, "at %d m" % int(at_m))
	_look_at_regiment(v, _first_regiment(), Game.data.bal("map3d_zoom_max_m"))
	assert_eq(v.army_badge_height(), lo, "never smaller than the floor far out")
	_look_at_regiment(v, _first_regiment(), Game.data.bal("map3d_zoom_min_m"))
	assert_eq(v.army_badge_height(), hi, "never larger than the ceiling close in")


func test_counters_never_overlap() -> void:
	var v := _view()
	v.set_military(true)
	_look_at_regiment(v, _first_regiment(), 60000.0)
	var rects: Array = []
	for m: Dictionary in v.army_markers():
		for r: Rect2 in rects:
			assert_false(r.intersects(m["rect"]))
		rects.append(m["rect"])


func test_a_click_on_a_counter_opens_the_regiment() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	_look_at_regiment(v, r, 20000.0)
	var mine: Dictionary = {}
	for m: Dictionary in v.army_markers():
		if String(m["code"]) == String(r["regiment_code"]):
			mine = m
	watch_signals(v)
	_click(v, (mine["rect"] as Rect2).get_center())
	var code := String(r["regiment_code"])
	assert_signal_emitted_with_parameters(v, "object_selected",
		[{"title": String(r["label"]), "obj": {"kind": "army", "code": code}}])
	assert_eq(v.selected_army(), code)
	v.clear_selection()
	assert_eq(v.selected_army(), "")


func test_hovering_a_counter_names_the_regiment() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	v.hover_pick({"kind": "army", "code": String(r["regiment_code"])}, Vector2(50, 50))
	assert_eq(v.hover_tooltip(), String(r["label"]))
	assert_eq(v.hovered_kingdom(), Game.data.resolve_realm("player_realm"))


func test_the_hud_draws_the_counters() -> void:
	var v := _view()
	v.set_military(true)
	_look_at_regiment(v, _first_regiment(), 20000.0)
	await wait_process_frames(2)
	assert_gt(v.drawn_army_count(), 0)


# --- the rule ---------------------------------------------------------------------

func test_military_stays_on_the_3d_map() -> void:
	Game.data.balance["map3d_default"] = 1.0
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	r.force_map3d_scene(true)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	r.set_army_view(true)
	assert_true(r.map3d_view(), "MILITARY draws on the 3D map now")
	assert_true(r.current_screen.map3d_view().military())
	assert_true(r.current_screen.military_panel().visible, "the host in the left column")
	r.set_army_view(false)
	assert_false(r.current_screen.map3d_view().military())
	Game.data.balance["map3d_default"] = 0.0
