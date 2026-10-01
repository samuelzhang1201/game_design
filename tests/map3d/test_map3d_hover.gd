extends GutTest
## Hovering the 3D map (owner 2026-09-18, the migration list's first item):
## the country under the pointer takes the left column's card, its live
## outline is drawn wider, and a settlement's name follows the cursor — what
## the 2D map's hover does. The built scene is git-ignored, so the view loads
## a flat fixture world carrying the same `map3d_world` metadata.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_hover").path_join("test_map3d_hover_world.tscn")
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


func _capital() -> String:
	return String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])


func _province_of(realm_slot: String) -> String:
	return String(MapOwnership.provinces_of(Game.data, Game.state,
		Game.data.resolve_realm(realm_slot))[0])


# --- the kingdom a pick names --------------------------------------------------

func test_a_settlement_names_the_kingdom_holding_its_province() -> void:
	var code := _capital()
	assert_eq(Map3DView.kingdom_of_pick(Game.data, Game.state, {"kind": "burg", "code": code}),
		Game.data.resolve_realm("player_realm"))


func test_a_province_names_its_holder_now_not_the_packs() -> void:
	var province := _province_of("raider_realm")
	var pick := {"kind": "province", "code": province}
	assert_eq(Map3DView.kingdom_of_pick(Game.data, Game.state, pick),
		Game.data.resolve_realm("raider_realm"))
	MapOwnership.set_owner(Game.data, Game.state, province,
		Game.data.resolve_realm("player_realm"), "test: conquest")
	assert_eq(Map3DView.kingdom_of_pick(Game.data, Game.state, pick),
		Game.data.resolve_realm("player_realm"), "a conquest moves the hover with it")


func test_the_sea_names_no_kingdom() -> void:
	assert_eq(Map3DView.kingdom_of_pick(Game.data, Game.state, {}), "")


# --- the view's hover ----------------------------------------------------------

func test_the_hover_signals_only_when_the_kingdom_changes() -> void:
	var v := _view()
	watch_signals(v)
	var mine := {"kind": "province", "code": _province_of("player_realm")}
	v.hover_pick(mine, Vector2(100, 100))
	v.hover_pick(mine, Vector2(120, 100))
	assert_signal_emit_count(v, "country_hovered", 1)
	assert_signal_emitted_with_parameters(v, "country_hovered",
		[Game.data.resolve_realm("player_realm")])
	v.hover_pick({}, Vector2(10, 10))
	assert_signal_emit_count(v, "country_hovered", 2)
	assert_eq(v.hovered_kingdom(), "")


func test_a_settlement_shows_its_name_beside_the_cursor() -> void:
	var v := _view()
	var code := _capital()
	v.hover_pick({"kind": "burg", "code": code}, Vector2(200, 150))
	assert_eq(v.hover_tooltip(), String(Game.data.burgs[code]["label"]))
	assert_true(v.tooltip_rect().position.x > 200.0, "beside the cursor, not under it")
	v.hover_pick({"kind": "province", "code": _province_of("player_realm")}, Vector2(200, 150))
	assert_eq(v.hover_tooltip(), "", "open land names nothing, as on the 2D map")


func test_the_tooltip_stays_inside_the_view() -> void:
	var v := _view()
	v.hover_pick({"kind": "burg", "code": _capital()}, v.size - Vector2(2, 2))
	var r := v.tooltip_rect()
	assert_true(r.end.x <= v.size.x + 0.5 and r.end.y <= v.size.y + 0.5, str(r))


func test_the_hovered_kingdom_is_outlined_from_its_live_outline() -> void:
	var v := _view()
	var mine := Game.data.resolve_realm("player_realm")
	v.hover_pick({"kind": "province", "code": _province_of("player_realm")}, Vector2.ZERO)
	var expected: PackedVector3Array = Map3DBorders.ribbon_arrays(
		Map3DBorders.kingdom_lines(Game.data, Game.state, WORLD, mine,
			Game.data.bal("map3d_line_step_m")),
		func(_xz: Vector2) -> float: return 5.0)[Mesh.ARRAY_VERTEX]
	var hover := v.line_mesh("Hover")
	assert_not_null(hover)
	assert_eq(hover.surface_get_array_len(0), expected.size())
	var mat := hover.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DView.PRIORITY_HOVER)
	assert_eq(String(mat.get_meta("width_key")), "map3d_hover_border_width_px")
	assert_gt(Game.data.bal("map3d_hover_border_width_px"), Game.data.bal("map3d_border_width_px"),
		"bolder than the border it follows")
	v.hover_pick({}, Vector2.ZERO)
	assert_null(v.line_mesh("Hover"), "gone with the hover")


func test_a_real_pointer_move_hovers_on_the_next_frame() -> void:
	var v := _view()
	var code := _capital()
	var burg: Dictionary = Game.data.burgs[code]
	v.set_military(false)  # the fleet lies at the capital; this is the town's hover
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])))
	watch_signals(v)
	var mm := InputEventMouseMotion.new()
	mm.position = v.size * 0.5
	v._gui_input(mm)
	assert_signal_not_emitted(v, "country_hovered", "resolved once a frame, not per event")
	await wait_process_frames(2)
	assert_eq(v.hovered_kingdom(), Game.data.resolve_realm("player_realm"))
	assert_eq(v.hover_tooltip(), String(burg["label"]))


func test_leaving_or_hiding_the_view_clears_the_hover() -> void:
	var v := _view()
	v.hover_pick({"kind": "burg", "code": _capital()}, Vector2(50, 50))
	watch_signals(v)
	v.deactivate()
	assert_signal_emitted_with_parameters(v, "country_hovered", [""])
	assert_eq(v.hover_tooltip(), "")
	v.activate()
	v.hover_pick({"kind": "burg", "code": _capital()}, Vector2(50, 50))
	v.mouse_exited.emit()
	assert_eq(v.hovered_kingdom(), "")


func test_a_drag_clears_the_hover() -> void:
	var v := _view()
	v.hover_pick({"kind": "burg", "code": _capital()}, Vector2(50, 50))
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(300, 200)
	mm.relative = Vector2(40, 0)
	mm.button_mask = MOUSE_BUTTON_MASK_RIGHT
	v._gui_input(mm)
	assert_eq(v.hovered_kingdom(), "")
	assert_eq(v.hover_tooltip(), "")


# --- the screen's left column --------------------------------------------------

func _court() -> GameRoot:
	Game.data.balance["map3d_default"] = 1.0
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	r.force_map3d_scene(true)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	Game.data.balance["map3d_default"] = 0.0
	return r


func test_hovering_the_3d_map_puts_the_country_card_in_the_left_column() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	assert_not_null(view)
	view.country_hovered.emit(Game.data.resolve_realm("raider_realm"))
	assert_true(screen.country_panel().visible, "the hovered country's card")
	assert_false(screen.dashboard().visible)
	view.country_hovered.emit("")
	assert_false(screen.country_panel().visible)
	assert_true(screen.dashboard().visible, "the column's own content returns")


func test_a_clicked_card_outranks_the_3d_hover() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	view.object_selected.emit({"title": "x", "obj": {"kind": "burg", "code": _capital()}})
	view.country_hovered.emit(Game.data.resolve_realm("raider_realm"))
	assert_true(screen.detail_panel().visible)
	assert_false(screen.country_panel().visible)


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DView.world_override = ""
	Map3DWorldCache.clear()
