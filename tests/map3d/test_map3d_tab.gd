extends GutTest
## The 3D MAP tab (owner 2026-09-18): a bottom-bar toggle that swaps the map
## panel's 2D WorldMapView for Map3DView, exclusive with the 2D themes, and
## following the player from screen to screen. Nothing here depends on the
## built scene (git-ignored): an unbuilt map still swaps in the view, which
## then shows its notice.

func _court() -> GameRoot:
	Game.start_campaign(42)
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r


func test_the_tab_is_a_toggle_on_the_bar() -> void:
	assert_true("3D MAP" in BottomBar.TABS)
	assert_true("3D MAP" in BottomBar.TOGGLES)


func test_the_tab_swaps_the_2d_map_for_the_3d_view_and_back() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	assert_null(screen.map3d_view(), "nothing is made until the tab is lit")
	r.bottom_bar().button("3D MAP").pressed.emit()
	await wait_frames(1)
	assert_true(r.map3d_view())
	assert_true(r.bottom_bar().button("3D MAP").button_pressed, "the tab stays lit")
	assert_not_null(screen.map3d_view())
	assert_true(screen.map3d_view().visible)
	assert_false(screen.world_map().visible, "the 2D map gives the panel up")
	r.bottom_bar().button("3D MAP").pressed.emit()
	await wait_frames(1)
	assert_false(r.map3d_view())
	assert_false(screen.map3d_view().visible)
	assert_true(screen.world_map().visible)


func test_the_2d_themes_and_the_3d_map_put_each_other_out() -> void:
	var r: GameRoot = await _court()
	r.set_height_view(true)
	r.set_map3d_view(true)
	assert_false(r.height_view(), "3D puts HEIGHTS out")
	r.set_economy_view(true)
	assert_false(r.map3d_view(), "ECONOMY puts 3D out")
	assert_true(r.current_screen.world_map().visible)
	r.set_map3d_view(true)
	assert_false(r.economy_view())
	r.set_manor_view(true)
	assert_false(r.map3d_view(), "MANORS puts 3D out")


func test_the_3d_map_follows_the_player_to_the_next_screen() -> void:
	var r: GameRoot = await _court()
	r.set_map3d_view(true)
	r._switch_to(GameRoot.State.COURT)
	await wait_frames(2)
	var screen: CourtScreen = r.current_screen
	assert_not_null(screen.map3d_view())
	assert_true(screen.map3d_view().visible)
	assert_false(screen.world_map().visible)


func test_a_3d_selection_opens_the_card_in_the_left_column() -> void:
	var r: GameRoot = await _court()
	r.set_map3d_view(true)
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
