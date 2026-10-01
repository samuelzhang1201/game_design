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
	var p: Dictionary = WarRoom.on_sheet(repo, state, _home_sheet())[0]
	var code := String(p["code"])
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
	var hit: Dictionary = pieces.screen_hits(cam, view._window_scale())[0]
	var at: Vector2 = hit["at"]
	assert_eq(pieces.pick(cam, view._window_scale(), at, repo.bal("war_pick_px")), String(hit["code"]))
	assert_eq(pieces.pick(cam, view._window_scale(), at + Vector2(5000, 5000), repo.bal("war_pick_px")), "")
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
