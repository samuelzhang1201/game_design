extends GutTest
## The 3D map is the default map (owner 2026-09-18, spec
## 2026-09-18-map3d-default-design.md): the map panel shows Map3DView
## whenever the pack has a built scene, and the 2D WorldMapView otherwise —
## no 2D-only layer is left (HEIGHTS draws on the 3D map too since
## 2026-09-19, spec 2026-09-19-map3d-heights).
## The scene is git-ignored, so every test forces its presence through
## GameRoot.force_map3d_scene; an unbuilt view still swaps in and shows its
## notice. The suite holds 2D (tests/pre_run.gd); these tests lift that.

func before_each() -> void:
	Game.data.balance["map3d_default"] = 1.0


func after_each() -> void:
	Game.data.balance["map3d_default"] = 0.0


func _court(has_scene: bool = true) -> GameRoot:
	Game.start_campaign(42)
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	r.force_map3d_scene(has_scene)
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r


func _shows_3d(r: GameRoot) -> bool:
	var v: Map3DView = r.current_screen.map3d_view()
	return v != null and v.visible and not r.current_screen.world_map().visible


func test_there_is_no_3d_tab() -> void:
	assert_false("3D MAP" in BottomBar.TABS)
	assert_false("3D MAP" in BottomBar.TOGGLES)


func test_the_court_opens_on_the_3d_map() -> void:
	var r: GameRoot = await _court()
	assert_true(r.map3d_view())
	assert_true(_shows_3d(r))


## HEIGHTS draws on the 3D map (owner 2026-09-19, spec 2026-09-19-map3d-heights).
func test_heights_stays_on_the_3d_map_and_reaches_it() -> void:
	var r: GameRoot = await _court()
	r.set_height_view(true)
	assert_true(_shows_3d(r))
	assert_eq(r.current_screen.map3d_view().manor_theme(), "heights")
	r.set_manor_view(true)
	assert_eq(r.current_screen.map3d_view().manor_theme(), "manors", "MANORS put HEIGHTS out")
	assert_false(r.height_view())
	r.set_manor_view(false)
	assert_eq(r.current_screen.map3d_view().manor_theme(), "")


## MANORS draws on the 3D map too, and ECONOMY is gone — folded into it
## (owner 2026-09-19).
func test_the_manors_theme_stays_on_the_3d_map_and_reaches_it() -> void:
	var r: GameRoot = await _court()
	assert_false("ECONOMY" in BottomBar.TABS, "no ECONOMY tab")
	assert_false(r.has_method("set_economy_view"))
	r.set_manor_view(true)
	assert_true(_shows_3d(r))
	assert_eq(r.current_screen.map3d_view().manor_theme(), "manors")
	r.set_manor_view(false)
	assert_eq(r.current_screen.map3d_view().manor_theme(), "")
	r.set_manor_view(true)
	r.set_height_view(true)
	assert_true(_shows_3d(r), "HEIGHTS stays on 3D")
	assert_eq(r.current_screen.map3d_view().manor_theme(), "heights")


func test_the_bottom_tab_routes_through_the_rule() -> void:
	var r: GameRoot = await _court()
	r._on_bottom_tab("HEIGHTS")
	assert_true(_shows_3d(r))
	r._on_bottom_tab("HEIGHTS")
	assert_true(_shows_3d(r))
	r._on_bottom_tab("MANORS")
	assert_true(_shows_3d(r))


func test_no_built_scene_keeps_the_2d_map() -> void:
	var r: GameRoot = await _court(false)
	assert_false(r.map3d_view())
	assert_null(r.current_screen.map3d_view(), "no 3D view is even made")
	assert_true(r.current_screen.world_map().visible)


func test_map3d_default_zero_keeps_the_2d_map() -> void:
	Game.data.balance["map3d_default"] = 0.0
	var r: GameRoot = await _court()
	assert_false(r.map3d_view())
	assert_true(r.current_screen.world_map().visible)


func test_the_choice_follows_the_player_to_the_next_screen() -> void:
	var r: GameRoot = await _court()
	r._switch_to(GameRoot.State.COURT)
	await wait_frames(2)
	assert_true(_shows_3d(r), "3D on the new screen")
	r.set_height_view(true)
	r._switch_to(GameRoot.State.COURT)
	await wait_frames(2)
	assert_true(_shows_3d(r), "HEIGHTS keeps the new screen 3D")
	assert_eq(r.current_screen.map3d_view().manor_theme(), "heights")


func test_the_real_scene_check_reads_the_pack() -> void:
	assert_false(Map3DView.has_scene("no_such_pack"))


func test_a_3d_selection_opens_the_card_in_the_left_column() -> void:
	var r: GameRoot = await _court()
	await wait_frames(1)
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	var code := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	view.object_selected.emit({"title": "x", "obj": {"kind": "burg", "code": code}})
	await wait_frames(1)
	assert_true(screen.detail_panel().visible, "the town's card, as a 2D click would open")
	assert_false(screen.dashboard().visible, "in place of the dashboard")
	var province := String(Game.data.burgs[code]["province_code"])
	view.province_selected.emit(province)
	await wait_frames(1)
	assert_true(screen.detail_panel().visible, "a province's card too")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
