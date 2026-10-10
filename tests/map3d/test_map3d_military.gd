extends GutTest
## MILITARY on the 3D map (owner 2026-09-19: "点击兵棋可以看到该部队信息";
## 2026-10-10: 请移除大地图上军事单位的所有标记和数字的mark): a land regiment is
## its 3D piece at every zoom with nothing drawn over it; a unit with no piece
## (a fleet) keeps its flat counter (ArmyCounters), sized by the view but held
## between the Armies piece's badge_min_px and badge_max_px; a click on either
## opens the regiment's card.

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
	return MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state)[0]


func _fleet() -> Dictionary:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) == "1":
			return r
	return {}


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


func test_a_land_regiment_is_its_piece_at_every_zoom_with_no_counter() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	var code := String(r["regiment_code"])
	assert_ne(String(r.get("is_naval", "0")), "1", "premise: a land regiment")
	for at_m: float in [Game.data.bal("map3d_zoom_min_m"), 20000.0, 30000.0]:
		_look_at_regiment(v, r, at_m)
		assert_true(v.unit_rects().has(code), "its piece stands at %d m" % int(at_m))
		for m: Dictionary in v.army_markers():
			assert_true(v.unit_has_piece(String(m["code"])) == false, "a counter only for a unit with no piece")
			assert_ne(String(m["code"]), code, "no counter over the piece at %d m" % int(at_m))


func test_a_fleet_keeps_its_counter() -> void:
	var v := _view()
	v.set_military(true)
	var f := _fleet()
	assert_false(f.is_empty(), "premise: the crown has a fleet")
	_look_at_regiment(v, f, 20000.0)
	assert_false(v.unit_has_piece(String(f["regiment_code"])), "a fleet has no 3D piece")
	var mine: Dictionary = _marker(v, String(f["regiment_code"]))
	assert_false(mine.is_empty(), "the fleet under the camera has its counter")
	assert_eq(String(mine["text"]), str(int(MapObjects.regiment_size(Game.data, f))))


func test_a_counters_size_is_held_between_its_bounds() -> void:
	var v := _view()
	v.set_military(true)
	var armies := v.get_node("Hud/Armies") as Map3DHudArmies
	var lo := armies.badge_min_px
	var hi := armies.badge_max_px
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


## Far out a piece is a few px: a click on it, or within map_army_pick_px of
## it, still opens the regiment.
func test_a_click_on_a_far_piece_opens_the_regiment() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	var code := String(r["regiment_code"])
	_look_at_regiment(v, r, 30000.0)
	var box := v.unit_rects()[code] as Rect2
	assert_eq(v.pick_at(box.get_center()), {"kind": "army", "code": code}, "on its box")
	watch_signals(v)
	_click(v, box.get_center())
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


func test_the_hud_draws_only_the_fleets_counters() -> void:
	var v := _view()
	v.set_military(true)
	_look_at_regiment(v, _fleet(), 20000.0)
	await wait_process_frames(2)
	assert_gt(v.drawn_army_count(), 0)
	assert_eq(v.drawn_army_count(), v.army_markers().size())
	for m: Dictionary in v.army_markers():
		assert_true(bool(m["naval"]), "%s is a fleet" % m["code"])


## A selected piece is shown by a glow on the ground under it, not a box or a
## number (owner 2026-10-10); none while nothing is selected.
func test_a_selected_piece_glows_on_the_ground() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	var code := String(r["regiment_code"])
	_look_at_regiment(v, r, 2500.0)
	var hud := v._hud.piece("Armies") as Map3DHudArmies
	await wait_process_frames(2)
	assert_eq(hud.glow_count(), 0, "nothing selected, nothing glows")
	_click(v, (v.unit_rects()[code] as Rect2).get_center())
	assert_eq(v.selected_armies(), [code])
	hud.queue_redraw()
	await wait_process_frames(2)
	assert_eq(hud.glow_count(), 1, "the selected piece glows")
	var g: Dictionary = v.unit_rings()[code]
	var ring := Map3DHudArmies.ground_ring(v.camera(), g["at"], g["up"], float(g["r"]), 8,
		hud.ctx.viewport_px_scale())
	assert_eq(ring.size(), 8, "the ring lies before the camera")
	var box := v.unit_rects()[code] as Rect2
	assert_true(box.grow(box.size.length()).has_point(ring[0]), "and round the piece's feet")


## A standing piece keeps its facing when the camera moves (owner 2026-10-10:
## 他会经常乱改变朝向): no camera term in its yaw.
func test_a_standing_piece_does_not_turn_with_the_camera() -> void:
	var v := _view()
	v.set_military(true)
	var r := _first_regiment()
	var code := String(r["regiment_code"])
	_look_at_regiment(v, r, 2500.0)
	var units := v._units as Map3DLayerUnits
	var yaw := float(units._want_yaw[code])
	v.look_at_pack(Vector2(float(r["x"]) + 40.0, float(r["y"]) - 30.0), 6000.0)
	units.refresh()
	assert_almost_eq(float(units._want_yaw[code]), yaw, 0.0001, "the pan turned nothing")


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
	var r := _fleet()
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


## Every unit holds its own ground (spec 2026-10-07-army-split-and-ground §5.1,
## overturning 2026-10-06's garrison counter): the units round the capital
## each stand as their own counter or piece, nothing merged into one.
func _capital() -> String:
	return String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])


func _capital_units() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if ArmyGround.camped_by(Game.data, Game.state, String(r["regiment_code"])) == _capital():
			out.append(String(r["regiment_code"]))
	return out


func _capital_xy() -> Vector2:
	var b: Dictionary = Game.data.burgs[_capital()]
	return Vector2(float(b["x"]), float(b["y"]))


func _marker(v: Map3DView, code: String) -> Dictionary:
	for m: Dictionary in v.army_markers():
		if String(m["code"]) == code:
			return m
	return {}


func test_every_unit_round_a_town_stands_as_its_own_piece() -> void:
	var v := _view()
	v.set_military(true)
	var codes := _capital_units()
	assert_gt(codes.size(), 1, "more than one unit stands round the capital")
	v.look_at_pack(_capital_xy(), 20000.0)
	for c: String in codes:
		assert_true(v.unit_rects().has(c), "%s stands as its own piece" % c)
		assert_true(_marker(v, c).is_empty(), "%s has no counter" % c)


func test_only_the_household_wears_the_crown() -> void:
	var points: Array = []
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		points.append({"reg": r, "pos": Vector2(40.0 * points.size(), 0.0)})
	var crowned: Array = []
	for m: Dictionary in ArmyCounters.layout(Game.data, points, 20.0, []):
		if bool(m["royal"]):
			crowned.append(String(m["code"]))
			assert_eq(String(m["glyph"]), "crown")
			assert_eq(String(m["piece"]), "royal")
		else:
			assert_ne(String(m["glyph"]), "crown", "%s wears no crown" % m["code"])
	assert_eq(crowned.size(), 1, "one household")
	assert_eq(String(ArmySystem.regiment(Game.data, String(crowned[0]), Game.state)["is_royal"]), "1")


func test_the_seated_unit_stands_as_its_own_piece() -> void:
	var v := _view()
	v.set_military(true)
	var seat := ArmyGround.seat_of(Game.data, Game.state, _capital())
	assert_ne(seat, "", "the capital's seat is held")
	v.look_at_pack(_capital_xy(), 2500.0)
	await wait_process_frames(2)
	assert_true(v.unit_rects().has(seat), "the seat's unit stands in a piece of its own")


func test_a_click_on_a_units_piece_selects_that_unit() -> void:
	var v := _view()
	v.set_military(true)
	var seat := ArmyGround.seat_of(Game.data, Game.state, _capital())
	v.look_at_pack(_capital_xy(), 2500.0)
	var at := (v.unit_rects()[seat] as Rect2).get_center()
	assert_eq(v.pick_at(at), {"kind": "army", "code": seat})
	watch_signals(v)
	_click(v, at)
	assert_signal_emitted_with_parameters(v, "army_menu_requested", [seat, at])
	assert_eq(v.selected_armies(), [seat], "the one unit is selected")
	v.clear_selection()
	assert_eq(v.selected_armies(), [], "and let go")
