extends GutTest
## MILITARY on the 3D map (owner 2026-09-19: "迁移军事地图。注意兵棋大小" /
## "点击兵棋可以看到该部队信息"): the player's regiments as the 2D map's
## counters (ArmyCounters) on the 3D HUD, sized by the view but held between
## map3d_army_badge_min_px and map3d_army_badge_max_px so they read at every
## zoom and never swamp the map; a click on one opens the regiment's card.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_military").path_join("test_map3d_military_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()
	Map3DView.world_override = _fixture  # GameRoot's own views open it too


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
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


## The regiments are always on (owner 2026-09-27); set_military(false) stays
## as the seam that hides them.
func test_no_counters_while_the_layer_is_off() -> void:
	var v := _view()
	v.set_military(false)
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
	assert_true(r.map3d_view())
	assert_true(r.current_screen.map3d_view().military(), "the regiments are always on (owner 2026-09-27)")
	r.set_army_view(true)
	assert_true(r.current_screen.military_panel().visible, "the host in the left column")
	r.set_army_view(false)
	assert_false(r.current_screen.military_panel().visible)
	assert_true(r.current_screen.map3d_view().military(), "the host closing leaves them on the map")
	Game.data.balance["map3d_default"] = 0.0


## The counters are cut once per camera pose (final review 2026-09-20): the
## HUD's draw, Map3DPicker.pick_at and the landmarks' clearance all ask for them
## every frame the pointer moves, so a second call at the same pose is the SAME
## array, and a moved camera a new one — Map3DHudLandmarks.marks()' rule.
func test_counters_are_cut_once_per_pose() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	_look_at_regiment(v, r, 20000.0)
	var a := v.army_markers()
	assert_gt(a.size(), 0)
	assert_true(is_same(a, v.army_markers()), "the same pose, the same cut")
	_look_at_regiment(v, r, 40000.0)
	assert_false(is_same(a, v.army_markers()), "a new pose, a new cut")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DView.world_override = ""
	Map3DWorldCache.clear()
