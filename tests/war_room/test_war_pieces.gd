extends GutTest
## The tin pieces (spec 2026-10-01-war-room-design §3).

var repo: DataRepository
var state: GameState
var view: WarRoomView


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 42)
	WarSheets.forget()
	view = load("res://scenes/war_room/war_room.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1000, 600)
	add_child_autofree(view)
	view.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	view.set_active(true)


func _home_sheet() -> int:
	return int(WarRoom.pieces(repo, state)[0]["sheet"])


func _land_code() -> String:
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if not bool(p["naval"]):
			return String(p["code"])
	return ""


## The highest relief under a base's four corners, from the view's own heights.
func _corner_ys(xz: Vector2, naval: bool) -> Array:
	var side := repo.bal("war_piece_base_mm") / 1000.0
	var half := Vector2(side, side * (repo.bal("war_base_naval_depth") if naval else 1.0)) * 0.5
	var out: Array = []
	for dx in [-half.x, half.x]:
		for dz in [-half.y, half.y]:
			out.append(view.y_at(xz + Vector2(dx, dz)))
	return out


func _move_to(code: String, pack_px: Vector2) -> void:
	ArmySystem.ensure(repo, state)
	var m := ArmySystem.pack_to_metres(repo, pack_px)
	state.regiments[code]["x_m"] = m.x
	state.regiments[code]["y_m"] = m.y


func test_every_regiment_on_the_sheet_stands_as_a_piece_where_we_know_it_is() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var on := WarRoom.on_sheet(repo, state, _home_sheet())
	assert_eq(pieces.get_child_count(), on.size())
	for p: Dictionary in on:
		var node := pieces.piece(String(p["code"]))
		assert_not_null(node)
		var want := view.table_point(p["at"])
		assert_almost_eq(node.position.x, want.x, 0.0001)
		assert_almost_eq(node.position.z, want.z, 0.0001)


func test_a_land_piece_carries_its_figures_plate_and_tag() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var seen := 0
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if bool(p["naval"]):
			continue
		var node := pieces.piece(String(p["code"]))
		assert_eq(node.get_node("Figures/Formation").get_child_count(),
			WarFolio.figures(repo, state, String(p["code"])))
		assert_eq((node.get_node("Tag") as Label3D).text, WarRoom.tag_text(repo, state, String(p["code"])))
		assert_eq((node.get_node("Plate") as Label3D).text,
			String(ArmySystem.regiment(repo, String(p["code"]))["label"]))
		seen += 1
	assert_gt(seen, 0, "the home sheet holds a land regiment")


func test_the_figures_wear_the_tin_shader_over_their_own_albedo() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var checked := 0
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if bool(p["naval"]):
			continue
		for m: MeshInstance3D in Map3DUnits.meshes(pieces.piece(String(p["code"])).get_node("Figures")):
			for i in m.mesh.get_surface_count():
				var mat := m.get_surface_override_material(i) as ShaderMaterial
				assert_not_null(mat, "each surface is painted tin")
				assert_true(bool(mat.get_shader_parameter("has_tex")), "the Tripo atlas is read")
				assert_not_null(mat.get_shader_parameter("albedo_tex"))
				checked += 1
	assert_gt(checked, 0)


func test_a_moved_regiment_is_pushed_to_its_new_place() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var p: Dictionary = WarRoom.on_sheet(repo, state, _home_sheet())[0]
	var code := String(p["code"])
	ArmySystem.ensure(repo, state)
	var to: Vector2 = (p["at"] as Vector2) + Vector2(5.0, 0.0)
	var m := ArmySystem.pack_to_metres(repo, to)
	state.regiments[code]["x_m"] = m.x
	state.regiments[code]["y_m"] = m.y
	view.refresh()
	assert_ne(pieces.piece(code).position.x, view.table_point(to).x, "the push takes time")
	pieces.settle()
	assert_almost_eq(pieces.piece(code).position.x, view.table_point(to).x, 0.0001)


func test_a_changed_order_rebuilds_the_piece_in_its_new_pose() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var p: Dictionary = WarRoom.on_sheet(repo, state, _home_sheet())[0]
	var code := String(p["code"])
	var before := pieces.piece(code)
	ArmySystem.ensure(repo, state)
	var now := ArmySystem.order_of(repo, state, code)
	state.regiments[code]["order"] = ArmySystem.ORDER_MARCH if now != ArmySystem.ORDER_MARCH else ArmySystem.ORDER_GARRISON
	view.refresh()
	await wait_frames(1)
	assert_ne(pieces.piece(code), before, "a new pose is a new piece")
	assert_eq(pieces.get_child_count(), WarRoom.on_sheet(repo, state, _home_sheet()).size())


func test_screen_hits_name_each_piece() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var hits := pieces.screen_hits(view.get_node("%Camera"), 1.0)
	assert_eq(hits.size(), pieces.get_child_count())
	for h: Dictionary in hits:
		assert_not_null(pieces.piece(String(h["code"])))


func test_a_piece_is_frozen_in_its_orders_pose() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	var action := WarRoom.pose_action(ArmySystem.order_of(repo, state, code))
	var anims := Map3DFormation.anims_of(pieces.piece(code).get_node("Figures/Formation"))
	assert_gt(anims.size(), 0)
	for a: AnimationPlayer in anims:
		var clip := Map3DUnits.clip_named(a, action)
		assert_eq(String(a.assigned_animation), clip, "the order's clip is the one held")
		assert_false(a.is_playing(), "frozen, not running")
		assert_almost_eq(a.current_animation_position,
			a.get_animation(clip).length * repo.bal("war_pose_frame_" + action.to_lower()), 0.02)


func test_a_click_on_a_piece_picks_it_and_a_right_click_asks_for_its_orders() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var cam: Camera3D = view.get_node("%Camera")
	var hit: Dictionary = pieces.screen_hits(cam, view.window_scale())[0]
	var at: Vector2 = hit["at"]
	assert_eq(pieces.pick(cam, view.window_scale(), at, repo.bal("war_pick_px")), String(hit["code"]))
	assert_eq(pieces.pick(cam, view.window_scale(), at + Vector2(5000, 5000), repo.bal("war_pick_px")), "")
	watch_signals(view)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	view._gui_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	view._gui_input(up)
	assert_signal_emitted_with_parameters(view, "piece_selected", [String(hit["code"])])
	assert_eq(view.selected_army(), String(hit["code"]))
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = at
	view._gui_input(right)
	assert_signal_emitted_with_parameters(view, "army_menu_requested", [String(hit["code"]), at])


func test_a_piece_sits_level_on_the_highest_relief_under_its_base() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		var node := pieces.piece(String(p["code"]))
		var ys := _corner_ys(Vector2(node.position.x, node.position.z), bool(p["naval"]))
		assert_almost_eq(node.position.y, ys.max(), 0.00001)
		for y: float in ys:
			assert_lte(y, node.position.y + 0.00001, "no corner stands above the base's underside")


func test_a_piece_moved_onto_a_slope_rests_on_its_highest_corner() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	var rect: Rect2 = WarSheets.series(repo)[_home_sheet()]["rect"]
	var found := Vector2(-1, -1)
	var gain := 0.0
	for ix in 40:
		for iy in 40:
			var px := rect.position + rect.size * Vector2((ix + 0.5) / 40.0, (iy + 0.5) / 40.0)
			var xz := WarRoomTable.to_table(rect, repo.bal("war_table_w_m"), px)
			var ys := _corner_ys(xz, false)
			if ys.max() - view.y_at(xz) > gain:
				gain = ys.max() - view.y_at(xz)
				found = px
	assert_gt(gain, 0.0001, "the relief has a slope under a base")
	_move_to(code, found)
	view.refresh()
	pieces.settle()
	var node := pieces.piece(code)
	var ys := _corner_ys(Vector2(node.position.x, node.position.z), false)
	assert_almost_eq(node.position.y, ys.max(), 0.00001)
	assert_gt(node.position.y, view.y_at(Vector2(node.position.x, node.position.z)), "above the centre's own height")


func test_a_click_on_the_figures_top_picks_the_piece_and_the_nearer_one_wins() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var cam: Camera3D = view.get_node("%Camera")
	var sc: float = view.window_scale()
	var code := _land_code()
	var node := pieces.piece(code)
	var top := node.global_position + Vector3(0.0, (repo.bal("war_piece_base_h_mm") + repo.bal("war_piece_figure_mm")) / 1000.0, 0.0)
	var at := cam.unproject_position(top) / sc
	var centre := cam.unproject_position(node.global_position) / sc
	assert_gt(centre.distance_to(at), 1.0, "the figures' top is off the base's centre")
	assert_eq(pieces.pick(cam, sc, at, 0.0), code, "a click on the figures picks the piece")
	var near := Node3D.new()
	near.set_meta("code", "zz_nearer")
	pieces.add_child(near)
	near.global_position = node.global_position + Vector3(0.0, 0.0, 0.002)
	assert_eq(pieces.pick(cam, sc, centre, repo.bal("war_pick_px")), "zz_nearer", "the piece nearest the camera wins")
	pieces.remove_child(near)
	near.free()


func test_a_fleet_stands_as_a_flat_tin_token() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var seen := 0
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if bool(p["naval"]):
			var token := pieces.piece(String(p["code"])).get_node("Figures/Token") as MeshInstance3D
			assert_not_null(token)
			assert_true(token.material_override is ShaderMaterial, "under the tin shader")
			seen += 1
	assert_gt(seen, 0, "the home sheet holds a fleet")


func test_a_regiment_leaving_the_sheet_loses_its_piece() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var n := pieces.get_child_count()
	var code := _land_code()
	var other := (_home_sheet() + 1) % WarSheets.series(repo).size()
	var away: Rect2 = WarSheets.series(repo)[other]["rect"]
	var here: Rect2 = WarSheets.series(repo)[_home_sheet()]["rect"]
	var spot := away.get_center()
	assert_false(here.has_point(spot), "the spot is off this sheet")
	_move_to(code, spot)
	view.refresh()
	assert_null(pieces.piece(code))
	assert_eq(pieces.get_child_count(), n - 1)


func test_a_regiment_that_loses_men_is_rebuilt_with_fewer_figures() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	assert_eq(pieces.piece(code).get_node("Figures/Formation").get_child_count(), 9)
	var before := pieces.piece(code)
	ArmySystem.ensure(repo, state)
	@warning_ignore("integer_division")
	state.regiments[code]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, code)) * 4 / 10
	assert_eq(WarFolio.figures(repo, state, code), 6)
	view.refresh()
	assert_ne(pieces.piece(code), before)
	assert_eq(pieces.piece(code).get_node("Figures/Formation").get_child_count(), 6)


func test_a_push_in_flight_to_the_same_place_is_not_restarted() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	var at: Vector2 = WarRoom.on_sheet(repo, state, _home_sheet())[0]["at"]
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if String(p["code"]) == code:
			at = p["at"]
	_move_to(code, at + Vector2(5.0, 0.0))
	view.refresh()
	pieces._process(repo.bal("war_plot_push_s") * 0.5)
	var mid := pieces.piece(code).position
	view.refresh()   # same believed place again: the push carries on
	pieces._process(0.0)
	assert_eq(pieces.piece(code).position.x, mid.x, "the running push was not restarted")
	pieces._process(repo.bal("war_plot_push_s"))
	assert_almost_eq(pieces.piece(code).position.x, view.table_point(at + Vector2(5.0, 0.0)).x, 0.0001)


func test_a_figure_is_measured_through_its_transforms_and_never_taller_than_the_target() -> void:
	view.lay_sheet(_home_sheet())
	await wait_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var want := repo.bal("war_piece_figure_mm") / 1000.0
	var form := pieces.piece(_land_code()).get_node("Figures/Formation") as Node3D
	var tall := Map3DUnits.model_size(form.get_child(0) as Node3D).y * form.scale.y
	assert_lte(tall, want + 0.0001, "a figure is never taller than the target")
	assert_gt(tall, want * 0.5, "and not shrunk away")
