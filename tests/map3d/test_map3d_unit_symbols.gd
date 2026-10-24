extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const Play := preload("res://tests/invasion_play.gd")
var _fixture := RunDir.dir("unit_symbols").path_join("world.tscn")

class CountedSight extends Map3DContext:
	var calls := 0
	var ghost_calls := 0
	func ghosts() -> Array:
		ghost_calls += 1
		return super.ghosts()
	func regiments() -> Array:
		calls += 1
		return super.regiments()


class CountedPositionsView extends Map3DView:
	var position_calls := 0
	func unit_positions() -> Dictionary:
		position_calls += 1
		return {}


class CountedLegend extends Map3DMilitaryLegend:
	var mode_calls := 0
	func apply_mode(on: bool, military: bool) -> void:
		mode_calls += 1
		super.apply_mode(on, military)


func _view() -> Map3DView:
	var repo := SuiteData.repo()
	repo.balance["map3d_unit_symbol_enter_m"] = 2000.0
	repo.balance["map3d_unit_symbol_leave_m"] = 1600.0
	var state := SuiteData.campaign(repo, 7)
	var own := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state)
	var keep: Array = own.filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) != "1").slice(0, 2)
	var fleet: Dictionary = own.filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) == "1")[0]
	for code: String in state.army_roster.keys():
		if String(state.army_roster[code]["kingdom_code"]) == repo.resolve_realm("player_realm"): state.army_roster.erase(code)
	for i: int in keep.size():
		var row: Dictionary = keep[i]
		var code := String(row["regiment_code"])
		state.army_roster[code] = row
		assert_false(Personnel.replace(repo, state, code, 1000 if i == 0 else 1).has("error"))
	var root := Node3D.new()
	root.set_meta("map3d_world", {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0], "pack_px": [2560, 929], "sea_y": 5.0})
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()
	var view := Map3DView.create(repo, _fixture)
	view.set_meta("state_fn", func() -> GameState: return state)
	view.set_meta("fleet_fixture", fleet)
	view.size = Vector2(1280, 720)
	add_child_autofree(view)
	view.activate()
	var target := ArmySystem.position_of(repo, state, keep[0])
	view.look_at_pack(target, 1500)
	return view


func test_symbol_mode_uses_one_hysteresis_band() -> void:
	var rules: GDScript = load("res://scripts/map3d/map3d_units.gd")
	assert_true(rules.has_method("symbol_mode"), "the view needs a single pure mode decision")
	if not rules.has_method("symbol_mode"):
		return
	assert_false(rules.call("symbol_mode", false, 1999.0, 2000.0, 1600.0))
	assert_true(rules.call("symbol_mode", false, 2000.0, 2000.0, 1600.0))
	assert_true(rules.call("symbol_mode", true, 1790.0, 2000.0, 1600.0))
	assert_false(rules.call("symbol_mode", true, 1600.0, 2000.0, 1600.0))
	for previous: bool in [false, true]:
		for distance: float in [1790.0, 1810.0, 1790.0, 1810.0]:
			assert_eq(rules.call("symbol_mode", previous, distance, 2000.0, 1600.0), previous)


func test_invalid_symbol_thresholds_are_explicitly_refused() -> void:
	var rules: GDScript = load("res://scripts/map3d/map3d_units.gd")
	if not rules.has_method("symbol_mode"):
		pending("mode implementation absent")
		return
	for thresholds: Vector2 in [Vector2(1600, 2000), Vector2(2000, 0), Vector2(INF, 1600), Vector2(2000, NAN)]:
		assert_false(rules.call("symbol_mode", true, 1800.0, thresholds.x, thresholds.y))
	assert_false(rules.call("symbol_mode", true, NAN, 2000.0, 1600.0))


func test_one_mode_swaps_models_legend_and_unit_rectangles_without_state_changes() -> void:
	assert_true(ResourceLoader.exists("res://assets/2D/ui/military/unit_symbols.tres"), "shared symbol resource must be authored")
	if not ResourceLoader.exists("res://assets/2D/ui/military/unit_symbols.tres"):
		return
	var view := _view()
	var st := view._ctx.state()
	var before := SaveLoad.state_hash(st)
	var geometry := st.battles.duplicate(true)
	assert_false(view.get("unit_symbol_mode"))
	assert_eq(view.unit_count(), 2)
	var layer := view.world().get_node("Units") as Map3DLayerUnits
	var figures := 0
	for piece: Dictionary in layer._pieces.values():
		figures += int(piece["figures"])
	assert_eq(figures, 11)
	var legend := view.get_node("Hud/LegendScroll/MilitaryLegend") as Control
	assert_same((view.get_node("Hud/Armies") as Map3DHudArmies).symbols, legend.get("symbols"), "one Resource supplies map and legend")
	assert_false(legend.visible)
	view.look_at_pack(view._ctx.to_pack(view.target()), 2000)
	assert_true(view.get("unit_symbol_mode"))
	assert_eq(view.unit_count(), 0)
	assert_true(legend.visible, "legend changes in the same update")
	assert_eq(view.army_markers().size(), 2)
	assert_eq(view.unit_rects().size(), 2)
	view._selection.select_box(Rect2(Vector2(-10000,-10000), Vector2(20000,20000)))
	assert_eq(view.selected_armies().size(), 2, "one selection per actual unit, not per soldier")
	for marker: Dictionary in view.army_markers():
		assert_false(marker.has("text"), "no private strength metadata")
		assert_eq(Map3DPicker._army_pick(marker)["code"], marker["code"])
		assert_eq(view.pick_at((marker["rect"] as Rect2).get_center()), {"kind": "army", "code": marker["code"]})
	view.set_military(false)
	assert_eq(view.army_markers(), [])
	assert_eq(view.unit_rects(), {})
	assert_false(legend.visible)
	view.set_military(true)
	assert_true(legend.visible)
	view.look_at_pack(view._ctx.to_pack(view.target()), 1600)
	assert_false(view.get("unit_symbol_mode"))
	assert_false(legend.visible)
	assert_eq(view.unit_count(), 2)
	assert_eq(SaveLoad.state_hash(st), before)
	assert_eq(st.battles, geometry)


func test_wounded_only_unit_remains_one_symbol_and_never_reads_strength() -> void:
	var view := _view()
	var st := view._ctx.state()
	var code := String(MapObjects.regiments_of(view._repo, view._repo.resolve_realm("player_realm"), st)[0]["regiment_code"])
	assert_false(Personnel.move(view._repo, st, code, "fit", "wounded", 1000).has("error"))
	view.look_at_pack(view._ctx.to_pack(view.target()), 2000)
	var markers := view.army_markers()
	assert_eq(markers.filter(func(m: Dictionary) -> bool: return m["code"] == code).size(), 1)
	for marker: Dictionary in markers:
		assert_false(marker.has("text"))
		assert_false(marker.has("size"))
		assert_false(marker.has("reg"), "do not pass live personnel into draw/pick metadata")


func test_shared_glyphs_and_declutter_keep_original_identity_without_strength_priority() -> void:
	var symbols: Resource = load("res://assets/2D/ui/military/unit_symbols.tres")
	var repo := SuiteData.repo()
	var mine := repo.resolve_realm("player_realm")
	var points := [
		{"reg": {"regiment_code": "a", "kingdom_code": mine, "is_naval": "1"}, "pos": Vector2(100, 100)},
		{"reg": {"regiment_code": "b", "kingdom_code": mine, "is_royal": "1", "organization_arm": "cavalry"}, "pos": Vector2(100, 100)},
		{"code": "ghost:last", "ghost": true, "pos": Vector2(100, 100)}]
	var markers: Array = symbols.call("layout", repo, points, [], [])
	assert_eq(markers.size(), 3)
	var boxes: Dictionary = {}
	for marker: Dictionary in markers: boxes[marker["code"]] = marker["rect"]
	for marker: Dictionary in markers:
		assert_eq(Map3DPicker._nearest_piece(boxes, (marker["rect"] as Rect2).get_center(), 0), marker["code"])
	assert_ne((boxes["a"] as Rect2).get_center(), (boxes["b"] as Rect2).get_center())
	var royal: Dictionary = markers.filter(func(m: Dictionary) -> bool: return m["code"] == "b")[0]
	assert_true(royal.has("symbol_rect"), "the crown's drawn bounds belong to the unit hit rectangle")
	if royal.has("symbol_rect"):
		assert_lt((royal["rect"] as Rect2).position.y, (royal["symbol_rect"] as Rect2).position.y)
	assert_eq((markers.filter(func(m: Dictionary) -> bool: return m["code"] == "a")[0] as Dictionary)["arm"], "fleet")
	assert_eq((markers.filter(func(m: Dictionary) -> bool: return m["code"] == "ghost:last")[0] as Dictionary)["frame"], "ghost")
	assert_eq(symbols.get("labels")["unknown"], "Unknown arm")
	assert_eq(symbols.call("arm_of", repo, {"organization_arm": "unknown_future_arm"}), "unknown")
	for key: String in ["infantry", "archers", "cavalry", "artillery", "fleet", "royal", "unknown"]:
		assert_true(symbols.get("glyphs").has(key))
		assert_true(symbols.get("labels").has(key))


func test_legend_stays_in_the_map_below_council_controls_at_both_windows() -> void:
	var view := _view()
	var scroll := view.get_node("Hud/LegendScroll") as Control
	for window: Vector2 in [Vector2(1920, 1080), Vector2(2560, 1600)]:
		view.size = window / (window.x / 1280) - Vector2(280, 140)
		view.look_at_pack(view._ctx.to_pack(view.target()), 2000)
		await wait_process_frames(2)
		var rect := Rect2(scroll.position, scroll.size)
		assert_true(Rect2(Vector2.ZERO, view.size).encloses(rect))
		assert_gte(rect.position.y, 80.0, "below council portrait/control row")


func test_hidden_mutation_keeps_one_stale_unknown_symbol_and_no_unseen_symbol() -> void:
	var view := _view()
	var ctx := view._ctx
	var repo := ctx.repo
	var st := ctx.state()
	repo.balance["player_sight_km"] = 12.0
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, st, MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), st)[0]))
	var foes := st.foes.keys()
	foes.sort()
	for code: String in foes: Play.place(repo, st, code, at + Vector2i(0, 5000000), ArmySystem.ORDER_STANDBY)
	Play.place(repo, st, foes[0], at + Vector2i(100, 0), ArmySystem.ORDER_STANDBY)
	view.look_at_pack(ArmySystem.metres_to_pack(repo, at), 2000)
	assert_has(view.army_markers().map(func(m: Dictionary) -> String: return m["code"]), foes[0])
	Sighting.update(repo, st)
	Play.place(repo, st, foes[0], at + Vector2i(0, 5000000), ArmySystem.ORDER_STANDBY)
	var markers := view.army_markers()
	var codes: Array = markers.map(func(m: Dictionary) -> String: return m["code"])
	assert_has(codes, Sighting.GHOST_CODE + String(foes[0]))
	assert_does_not_have(codes, foes[0])
	assert_does_not_have(codes, foes[1])
	var before := SaveLoad.state_hash(st)
	view.army_markers()
	assert_eq(SaveLoad.state_hash(st), before, "drawing never publishes sightings")
	st.army_roster[foes[0]]["organization_arm"] = "cavalry"
	st.army_roster[foes[0]]["is_royal"] = "1"
	assert_eq(view.army_markers(), markers, "stale symbols never sample hidden live arm or royal metadata")


func test_fleet_counter_and_symbol_are_mutually_exclusive() -> void:
	var view := _view()
	var st := view._ctx.state()
	var reg: Dictionary = view.get_meta("fleet_fixture")
	var code := String(reg["regiment_code"])
	st.army_roster[code] = reg
	view.look_at_pack(ArmySystem.position_of(view._repo, st, reg), 1500)
	var near := view.army_markers().filter(func(m: Dictionary) -> bool: return m["code"] == code)
	assert_eq(near.size(), 1)
	assert_true(near[0].has("text"), "near retains the fleet counter")
	view.look_at_pack(ArmySystem.position_of(view._repo, st, reg), 2000)
	var far := view.army_markers().filter(func(m: Dictionary) -> bool: return m["code"] == code)
	assert_eq(far.size(), 1)
	assert_eq(far[0]["arm"], "fleet")
	assert_false(far[0].has("text"))


func test_camera_jitter_and_json_reload_preserve_full_campaign_and_physical_groups() -> void:
	var view := _view()
	var st := view._ctx.state()
	var before := SaveLoad.state_hash(st)
	var groups := st.battles.duplicate(true)
	var target := view._ctx.to_pack(view.target())
	for sample: Array in [[2000.0, true], [1790.0, true], [1810.0, true], [1600.0, false], [1790.0, false], [1810.0, false]]:
		view.look_at_pack(target, sample[0])
		assert_eq(view.unit_symbol_mode, sample[1])
		assert_eq(SaveLoad.state_hash(st), before)
		assert_eq(st.battles, groups)
	var reloaded := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())), false)
	view._ctx.state_fn = func() -> GameState: return reloaded
	view.look_at_pack(target, 2000)
	assert_eq(SaveLoad.state_hash(reloaded), before)
	assert_eq(view.unit_count(), 0)
	view.look_at_pack(target, 1600)
	assert_eq(view.unit_count(), 2)
	assert_eq(SaveLoad.state_hash(reloaded), before)


func test_camera_only_model_refresh_does_not_rescan_admission_per_unit() -> void:
	var repo := SuiteData.repo()
	var st := SuiteData.campaign(repo, 7)
	var ctx := CountedSight.new(repo, {})
	ctx.state_fn = func() -> GameState: return st
	var units := Map3DLayerUnits.new()
	autofree(units)
	units.bind(ctx)
	var key := units._roster_key()
	for i: int in 10:
		ctx.distance = 100 + i
		assert_eq(units._roster_key(), key, "camera moves do not change roster inputs")
	assert_lt(ctx.calls, 3, "render refresh must not multiply the public sight scan by the unit count")


func test_symbol_admission_cache_is_independent_of_camera_and_refreshes_same_day() -> void:
	var repo := SuiteData.repo()
	var st := SuiteData.campaign(repo, 7)
	var ctx := CountedSight.new(repo, {})
	ctx.state_fn = func() -> GameState: return st
	var hud := Map3DHudArmies.new()
	autofree(hud)
	hud.ctx = ctx
	assert_true(hud.has_method("_symbol_observations"))
	if not hud.has_method("_symbol_observations"): return
	var expected := ctx.regiments()
	ctx.calls = 0
	var initial: Dictionary = hud.call("_symbol_observations")
	assert_eq(initial["regiments"], expected)
	for i: int in 10:
		ctx.distance = 100 + i
		assert_eq(hud.call("_symbol_observations"), initial)
	assert_eq(ctx.calls, 1, "panning must not repeat admission")
	assert_eq(ctx.ghost_calls, 1, "panning must not repeat last-known sight queries")
	var code: String = st.regiments.keys()[0]
	st.regiments[code]["x_m"] = int(st.regiments[code].get("x_m", 0)) + 1
	hud.call("_symbol_observations")
	assert_eq(ctx.calls, 2, "a same-day move invalidates admission")
	st.day += 1
	hud.call("_symbol_observations")
	assert_eq(ctx.ghost_calls, 3, "a new day invalidates last-known age")
	ctx.dev = true
	hud.call("_symbol_observations")
	assert_eq(ctx.calls, 4, "DEV mode invalidates public admission")
	repo.balance["map3d_declutter_step_px"] = repo.bal("map3d_declutter_step_px") + 1.0
	hud.call("_symbol_observations")
	assert_eq(ctx.calls, 4, "a layout-only setting does not invalidate public admission")
	repo.balance["ghost_keep_days"] = repo.bal("ghost_keep_days") + 1.0
	hud.call("_symbol_observations")
	assert_eq(ctx.calls, 5, "last-known expiry is an admission input")
	var arm: String = repo.army_scouting.keys()[0]
	repo.army_scouting[arm]["scout_km"] = int(repo.army_scouting[arm]["scout_km"]) + 1
	hud.call("_symbol_observations")
	assert_eq(ctx.calls, 6, "scouting definitions are admission inputs")


func test_offscreen_near_piece_stops_animation_and_returns_with_same_identity() -> void:
	var view := _view()
	var units := view.world().get_node("Units") as Map3DLayerUnits
	var code: String = units._pieces.keys()[0]
	var piece: Dictionary = units._pieces[code]
	var node: Node3D = piece["node"]
	var target := view._ctx.to_pack(view.target())
	var before := SaveLoad.state_hash(view._ctx.state())
	view.look_at_pack(target + Vector2(100, 0), 100)
	assert_true(node.visible, "clip culling preserves scouting fans, sound and render culling")
	for anim: AnimationPlayer in piece["anims"]: assert_false(anim.active)
	view.look_at_pack(target, 1500)
	assert_same(units._pieces[code]["node"], node)
	assert_true(node.visible)
	for anim: AnimationPlayer in piece["anims"]: assert_true(anim.active)
	assert_eq(SaveLoad.state_hash(view._ctx.state()), before)


func test_symbol_ink_is_retained_while_projection_moves() -> void:
	var view := _view()
	view.look_at_pack(view._ctx.to_pack(view.target()), 2000)
	var hud := view.get_node("Hud/Armies") as Map3DHudArmies
	assert_true(hud.has_method("_sync_symbol_nodes"))
	if not hud.has_method("_sync_symbol_nodes"): return
	hud.call("_sync_symbol_nodes", view.army_markers())
	var nodes: Dictionary = hud.get("_symbol_nodes")
	var code: String = nodes.keys()[0]
	var ink: Node2D = nodes[code]
	var before := ink.position
	view.look_at_pack(view._ctx.to_pack(view.target()) + Vector2(0.1, 0), 2000)
	hud.call("_sync_symbol_nodes", view.army_markers())
	assert_same((hud.get("_symbol_nodes") as Dictionary)[code], ink)
	assert_ne(ink.position, before, "pan moves the retained ink without rebuilding it")
	view.set_military(false)
	assert_true((hud.get("_symbol_nodes") as Dictionary).is_empty(), "mode commit clears retained ink immediately")
	hud.call("_sync_symbol_nodes", view.army_markers())
	assert_true((hud.get("_symbol_nodes") as Dictionary).is_empty())
	assert_true(ink.is_queued_for_deletion(), "military off removes retained commands")


func test_standing_units_do_not_build_march_route_origins() -> void:
	var view := _view()
	var st := view.context().state()
	for code: String in st.regiments: st.regiments[code]["order"] = ArmySystem.ORDER_STANDBY
	for code: String in st.foes: st.foes[code]["order"] = ArmySystem.ORDER_STANDBY
	var counted := CountedPositionsView.new()
	autofree(counted)
	var hud := view.get_node("Hud/Armies") as Map3DHudArmies
	hud.view = counted
	hud._draw_routes(hud.ctx.regiments())
	assert_eq(counted.position_calls, 0, "route-origin projection is unnecessary when every admitted unit stands")
	hud.view = view


func test_route_draw_reuses_the_admitted_units_from_symbol_layout() -> void:
	var view := _view()
	var st := view.context().state()
	for code: String in st.regiments: st.regiments[code]["order"] = ArmySystem.ORDER_STANDBY
	for code: String in st.foes: st.foes[code]["order"] = ArmySystem.ORDER_STANDBY
	var counted := CountedSight.new(view.context().repo, view.context().meta)
	counted.state_fn = func() -> GameState: return st
	var admitted := counted.regiments()
	counted.calls = 0
	var hud := view.get_node("Hud/Armies") as Map3DHudArmies
	var original := hud.ctx
	hud.ctx = counted
	hud.call("_draw_routes", admitted)
	assert_eq(counted.calls, 0, "route paint must not repeat admission already obtained for symbol layout")
	hud.ctx = original


func test_camera_pan_does_not_reapply_an_unchanged_legend_mode() -> void:
	var view := _view()
	var scroll := view.get_node("Hud/LegendScroll") as ScrollContainer
	var old := scroll.get_node("MilitaryLegend") as Map3DMilitaryLegend
	var legend := CountedLegend.new()
	for field: String in ["symbols", "row_size", "icon_size", "text_offset", "panel", "text_ink"]: legend.set(field, old.get(field))
	scroll.remove_child(old)
	old.queue_free()
	legend.name = "MilitaryLegend"
	scroll.add_child(legend)
	var target := view.context().to_pack(view.target())
	view.look_at_pack(target, 2000)
	var calls := legend.mode_calls
	assert_true(legend.visible)
	view.look_at_pack(target + Vector2(1, 0), 2000)
	assert_eq(legend.mode_calls, calls, "camera-only movement retains static legend commands")
	view.set_military(false)
	assert_false(legend.visible)
	assert_gt(legend.mode_calls, calls, "military off commits immediately")


func after_all() -> void:
	Map3DWorldCache.clear()
