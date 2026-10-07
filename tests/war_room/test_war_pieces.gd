extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The pieces (spec 2026-10-01-war-room-design §3): a land regiment is one
## wooden piece on a lacquered plinth (spec 2026-10-06-war-room-wooden-pieces),
## a fleet a flat tin token on its base.

var repo: DataRepository
var state: GameState
var view: WarRoomView


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


func _home_sheet() -> int:
	return int(WarRoom.pieces(repo, state)[0]["sheet"])


func _land_code() -> String:
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if not bool(p["naval"]):
			return String(p["code"])
	return ""


## The highest relief under a base's four corners (a plinth's square), from
## the view's own heights.
func _corner_ys(xz: Vector2, naval: bool) -> Array:
	var side := repo.bal("war_piece_base_mm") / 1000.0
	var half := Vector2(side, side * repo.bal("war_base_naval_depth")) * 0.5
	if not naval:
		half = Vector2.ONE * repo.bal("war_piece_plinth_mm") / 2000.0
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


## Stand `code` on the home sheet's point farthest from every other piece:
## the units camped round one town are spread plinth to plinth on the table
## (WarPieces._spread), well within a pick's war_pick_px reach, where the
## piece nearest the camera wins; a pick test wants its piece clear of them.
func _stand_alone(code: String) -> void:
	var rect: Rect2 = WarSheets.series(repo)[_home_sheet()]["rect"]
	var others: Array = []
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if String(p["code"]) != code:
			others.append(p["at"])
	var best := rect.get_center()
	var best_d := -1.0
	for i in range(1, 8):
		for j in range(1, 8):
			var at := rect.position + rect.size * Vector2(i / 8.0, j / 8.0)
			var d := INF
			for o: Vector2 in others:
				d = minf(d, at.distance_to(o))
			if d > best_d:
				best_d = d
				best = at
	_move_to(code, best)


func test_every_regiment_on_the_sheet_stands_as_a_piece_where_we_know_it_is() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var on := WarRoom.on_sheet(repo, state, _home_sheet())
	assert_eq(pieces.get_child_count(), on.size())
	for p: Dictionary in on:
		var node := pieces.piece(String(p["code"]))
		assert_not_null(node)
		# where we know it is, or stepped aside from a neighbour on the table
		# (spec 2026-10-07-army-split-and-ground §5.4)
		var want := view.table_point(p["at"])
		var off := Vector2(node.position.x - want.x, node.position.z - want.z)
		assert_lte(maxf(absf(off.x), absf(off.y)), repo.bal("war_spread_max_m") + 0.0001, String(p["code"]))
	_assert_apart(pieces)


## No two pieces' footprints (their plinth squares, a fleet's base) overlap
## on the table.
func _assert_apart(pieces: WarPieces) -> void:
	var boxes: Array = []
	for c: Node3D in pieces.get_children():
		var half: Vector2 = c.get_meta("half", Vector2.ZERO)
		boxes.append([String(c.get_meta("code")), Rect2(Vector2(c.position.x, c.position.z) - half, half * 2.0)])
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			assert_false((boxes[i][1] as Rect2).intersects(boxes[j][1]), "%s and %s" % [boxes[i][0], boxes[j][0]])


## Two units standing within a plinth of each other are spread on the table
## so their plinths stand clear (spec 2026-10-07-army-split-and-ground §5.4);
## the engine's positions are untouched.
func test_two_units_within_a_plinth_stand_apart() -> void:
	var codes: Array = []
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if not bool(p["naval"]):
			codes.append(String(p["code"]))
	assert_gte(codes.size(), 2, "premise: the home sheet holds two land units")
	var rect: Rect2 = WarSheets.series(repo)[_home_sheet()]["rect"]
	var plinth_px := repo.bal("war_piece_plinth_mm") / 1000.0 * rect.size.x / repo.bal("war_table_w_m")
	var spot := rect.get_center()
	_move_to(String(codes[0]), spot)
	_move_to(String(codes[1]), spot + Vector2(plinth_px * 0.3, plinth_px * 0.2))
	var engine := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, String(codes[1]), state))
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	_assert_apart(pieces)
	# and again after a refresh moves one onto the other
	_move_to(String(codes[0]), spot + Vector2(plinth_px * 0.1, 0.0))
	view.refresh()
	pieces.settle()
	_assert_apart(pieces)
	assert_eq(ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, String(codes[1]), state)), engine,
		"the spread is the table's only")


func test_a_land_piece_is_its_arms_wooden_piece_with_its_tag() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var seen := 0
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		if bool(p["naval"]):
			continue
		var code := String(p["code"])
		var node := pieces.piece(code)
		var key := MapObjects.army_piece(repo, ArmySystem.regiment(repo, code))
		var piece := node.get_node("Piece") as Node3D
		assert_eq(piece.scene_file_path, GameArt.path(GameArt.WAR_PIECES, key), "%s stands as its %s piece" % [code, key])
		assert_null(node.get_node_or_null("Figures"), "no tin figures")
		assert_null(node.get_node_or_null("Base"), "the plinth is the piece's own")
		assert_eq((node.get_node("Tag") as Label3D).text, WarRoom.tag_text(repo, state, code))
		seen += 1
	assert_gt(seen, 0, "the home sheet holds a land regiment")


func test_the_war_pieces_table_draws_artillery_as_the_trebuchet_and_has_no_fleet() -> void:
	assert_eq(GameArt.path(GameArt.WAR_PIECES, "artillery"), "res://scenes/models/war_room/piece_trebuchet.tscn")
	for key: String in ["infantry", "archers", "cavalry", "royal"]:
		assert_eq(GameArt.path(GameArt.WAR_PIECES, key), "res://scenes/models/war_room/piece_%s.tscn" % key)
	assert_eq(GameArt.path(GameArt.WAR_PIECES, "fleet"), "", "a fleet keeps its tin token")


## The crown's piece is the household's (the roster's `is_royal`, spec
## 2026-10-07-army-split-and-ground §5.1).
func test_the_household_stands_as_the_royal_piece() -> void:
	var royal := ""
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_royal", "0")) == "1":
			royal = String(r["regiment_code"])
	assert_ne(royal, "", "the crown has a household")
	var sheet := -1
	for p: Dictionary in WarRoom.pieces(repo, state):
		if String(p["code"]) == royal:
			sheet = int(p["sheet"])
	assert_gte(sheet, 0, "the royal regiment is on a sheet")
	view.lay_sheet(sheet)
	await wait_process_frames(2)
	var piece := (view.get_node("%Pieces") as WarPieces).piece(royal).get_node("Piece") as Node3D
	assert_eq(piece.scene_file_path, "res://scenes/models/war_room/piece_royal.tscn")


func test_the_plinth_wears_the_realms_colour_as_its_lacquer() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	var want := MapPalette.color_of(repo, String(ArmySystem.regiment(repo, code)["kingdom_code"])) \
		.darkened(repo.bal("war_base_darken"))
	var checked := 0
	for m: MeshInstance3D in Map3DUnits.meshes(pieces.piece(code).get_node("Piece")):
		assert_eq(m.get_instance_shader_parameter("lacquer"), want)
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as ShaderMaterial
			assert_not_null(mat, "the piece wears the wood-piece shader")
			assert_not_null(mat.get_shader_parameter("lacquer_tex"), "with its lacquer mask")
		checked += 1
	assert_gt(checked, 0)


func test_the_plinth_is_war_piece_plinth_mm_across_and_the_pick_reaches_its_top() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var node := (view.get_node("%Pieces") as WarPieces).piece(_land_code())
	var piece := node.get_node("Piece") as Node3D
	assert_almost_eq(piece.scale.x, repo.bal("war_piece_plinth_mm") / 1000.0, 0.00001, "the .glb's plinth is 1 across")
	var tall := 0.0
	for m: MeshInstance3D in Map3DUnits.meshes(piece):
		tall = maxf(tall, (m.transform * m.mesh.get_aabb()).end.y * piece.scale.y)
	assert_almost_eq(float(node.get_meta("top_m")), tall, 0.0001)
	assert_gt(tall, repo.bal("war_piece_plinth_mm") / 1000.0, "a piece stands taller than its plinth is wide")


func test_a_moved_regiment_is_pushed_to_its_new_place() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
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


func test_a_changed_order_keeps_the_wooden_piece() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var p: Dictionary = WarRoom.on_sheet(repo, state, _home_sheet())[0]
	var code := String(p["code"])
	var before := pieces.piece(code)
	ArmySystem.ensure(repo, state)
	var now := ArmySystem.order_of(repo, state, code)
	state.regiments[code]["order"] = ArmySystem.ORDER_MARCH if now != ArmySystem.ORDER_MARCH else ArmySystem.ORDER_GARRISON
	view.refresh()
	await wait_process_frames(1)
	assert_eq(pieces.piece(code), before, "a solid piece has no pose to change")
	assert_eq(pieces.get_child_count(), WarRoom.on_sheet(repo, state, _home_sheet()).size())


func test_screen_hits_name_each_piece() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var hits := pieces.screen_hits(view.get_node("%Camera"), 1.0)
	assert_eq(hits.size(), pieces.get_child_count())
	for h: Dictionary in hits:
		assert_not_null(pieces.piece(String(h["code"])))


func test_a_click_on_a_piece_picks_it_and_a_right_click_asks_for_its_orders() -> void:
	# a unit set marching, standing clear of the others
	var mover := _land_code()
	_stand_alone(mover)
	ArmySystem.ensure(repo, state)
	ArmySystem.set_march(repo, state, mover,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, mover, state)) + Vector2(10.0, 0.0))
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var cam: Camera3D = view.get_node("%Camera")
	var hit: Dictionary = {}
	for h: Dictionary in pieces.screen_hits(cam, view.window_scale()):
		if String(h["code"]) == mover:
			hit = h
	assert_false(hit.is_empty(), "the marching unit's piece is on the sheet")
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
	assert_signal_not_emitted(view, "army_menu_requested", "the press alone is not yet a click (v2: a right drag turns)")
	var right_up := right.duplicate() as InputEventMouseButton
	right_up.pressed = false
	view._gui_input(right_up)
	assert_signal_emitted_with_parameters(view, "army_menu_requested", [String(hit["code"]), at])


func test_a_piece_sits_level_on_the_highest_relief_under_its_base() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	for p: Dictionary in WarRoom.on_sheet(repo, state, _home_sheet()):
		var node := pieces.piece(String(p["code"]))
		var ys := _corner_ys(Vector2(node.position.x, node.position.z), bool(p["naval"]))
		assert_almost_eq(node.position.y, ys.max(), 0.00001)
		for y: float in ys:
			assert_lte(y, node.position.y + 0.00001, "no corner stands above the base's underside")


func test_a_piece_moved_onto_a_slope_rests_on_its_highest_corner() -> void:
	# the sheet lies flat since 2026-10-02 (war_relief_exaggeration 0): the
	# seating rule still holds for any relief, so this test raises one
	repo.balance["war_relief_exaggeration"] = 5.0
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
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


func test_a_click_on_the_pieces_top_picks_it_and_the_nearer_one_wins() -> void:
	var code := _land_code()
	_stand_alone(code)
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var cam: Camera3D = view.get_node("%Camera")
	var sc: float = view.window_scale()
	var node := pieces.piece(code)
	var top := node.global_position + Vector3(0.0, float(node.get_meta("top_m")) * 0.95, 0.0)
	var at := cam.unproject_position(top) / sc
	var centre := cam.unproject_position(node.global_position) / sc
	assert_gt(centre.distance_to(at), 1.0, "the piece's top is off the plinth's centre")
	assert_eq(pieces.pick(cam, sc, at, 0.0), code, "a click on the piece's top picks it")
	var near := Node3D.new()
	near.set_meta("code", "zz_nearer")
	pieces.add_child(near)
	near.global_position = node.global_position + Vector3(0.0, 0.0, 0.002)
	assert_eq(pieces.pick(cam, sc, centre, repo.bal("war_pick_px")), "zz_nearer", "the piece nearest the camera wins")
	pieces.remove_child(near)
	near.free()


func test_a_fleet_stands_as_a_flat_tin_token() -> void:
	var fleet_sheet := -1
	for p: Dictionary in WarRoom.pieces(repo, state):
		if bool(p["naval"]):
			fleet_sheet = int(p["sheet"])
			break
	assert_gte(fleet_sheet, 0, "the crown has a fleet")
	view.lay_sheet(fleet_sheet)
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var seen := 0
	for p: Dictionary in WarRoom.on_sheet(repo, state, fleet_sheet):
		if bool(p["naval"]):
			var token := pieces.piece(String(p["code"])).get_node("Figures/Token") as MeshInstance3D
			assert_not_null(token)
			assert_true(token.material_override is ShaderMaterial, "under the tin shader")
			seen += 1
	assert_gt(seen, 0, "the fleet's sheet holds it")


func test_a_regiment_leaving_the_sheet_loses_its_piece() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var n := pieces.get_child_count()
	var code := _land_code()
	var other := (_home_sheet() + 1) % WarSheets.series(repo).size()
	var away: Rect2 = WarSheets.series(repo)[other]["rect"]
	var here: Rect2 = WarSheets.series(repo)[_home_sheet()]["rect"]
	var spot := away.get_center()
	assert_false(here.has_point(spot), "the spot is off this sheet")
	# one piece a unit: only this one leaves
	_move_to(code, spot)
	view.refresh()
	assert_null(pieces.piece(code))
	assert_eq(pieces.get_child_count(), n - 1)


func test_a_regiment_that_loses_men_keeps_its_piece_and_its_tag_says_so() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	var before := pieces.piece(code)
	ArmySystem.ensure(repo, state)
	@warning_ignore("integer_division")
	state.regiments[code]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, code)) * 4 / 10
	view.refresh()
	assert_eq(pieces.piece(code), before, "one piece a regiment, whatever its strength")
	assert_eq((before.get_node("Tag") as Label3D).text, WarRoom.tag_text(repo, state, code))

func test_a_push_in_flight_to_the_same_place_is_not_restarted() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
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


func test_the_tags_show_only_near_the_table() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var code := _land_code()
	var tag := pieces.piece(code).get_node("Tag") as Label3D
	assert_false(tag.visible, "the opening view is beyond war_tag_view_m: no slips")
	view.lean_to(repo.bal("war_tag_view_m") * 0.5)
	assert_true(tag.visible, "leaning in shows the slip")
	view.lean_to(repo.bal("war_cam_max_m"))
	assert_false(tag.visible)
	view.lean_to(repo.bal("war_tag_view_m") * 0.5)
	view.swap_to((_home_sheet() + 1) % WarSheets.series(repo).size())
	view._process(10.0)
	await wait_process_frames(2)
	view.lay_sheet(_home_sheet())
	view.lean_to(repo.bal("war_tag_view_m") * 0.5)
	assert_true((pieces.piece(code).get_node("Tag") as Label3D).visible, "a rebuilt piece wears the current setting")


func test_the_chalk_ring_follows_a_pushed_piece() -> void:
	view.lay_sheet(_home_sheet())
	await wait_process_frames(2)
	var pieces: WarPieces = view.get_node("%Pieces")
	var hud: WarHud = view.get_node("%Hud")
	var p: Dictionary = WarRoom.on_sheet(repo, state, _home_sheet())[0]
	var code := String(p["code"])
	view.select(code)
	var before: Vector2 = hud._chalk
	ArmySystem.ensure(repo, state)
	var to: Vector2 = (p["at"] as Vector2) + Vector2(20.0, 0.0)
	var m := ArmySystem.pack_to_metres(repo, to)
	state.regiments[code]["x_m"] = m.x
	state.regiments[code]["y_m"] = m.y
	view.refresh()
	assert_true(pieces.pushing())
	await wait_seconds(repo.bal("war_plot_push_s") * 0.5)
	assert_true(pieces.pushing(), "half way")
	var cam: Camera3D = view.get_node("%Camera")
	var now := cam.unproject_position(pieces.piece(code).global_position) / view.window_scale()
	assert_almost_eq(hud._chalk.x, now.x, 0.5, "the ring stands where the piece is mid-push")
	assert_ne(hud._chalk.x, before.x, "and it has moved with it")
	await wait_until(func() -> bool: return not pieces.pushing(), repo.bal("war_plot_push_s") * 2.0)
	assert_false(pieces.pushing(), "the push is over and the redraws stop")
