extends GutTest
## The world-map overlay (user ruling 2026-09-03: the bottom bar's MAP tab
## toggles it, superseding "MAP closes overlays").

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _started_root() -> GameRoot:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	return r

func test_map_hidden_on_menu_and_toggle_refused() -> void:
	var r := _root()
	await wait_frames(2)
	assert_false(r.map_screen().visible)
	r.toggle_map()
	assert_false(r.map_screen().visible, "no map on the main menu")

func test_map_tab_toggles_overlay() -> void:
	var r := await _started_root()
	r._on_bottom_tab("MAP")
	assert_true(r.map_screen().visible)
	r._on_bottom_tab("MAP")
	assert_false(r.map_screen().visible)

func test_other_tabs_hide_the_map() -> void:
	var r := await _started_root()
	r._on_bottom_tab("MAP")
	r._on_bottom_tab("REALM")
	assert_false(r.map_screen().visible, "info tab closes the map")
	assert_true(r.info_screen().visible)
	r._on_bottom_tab("MAP")
	r._on_bottom_tab("RELATIONSHIP")
	assert_false(r.map_screen().visible, "relations tab closes the map")

func test_map_tab_closes_other_overlays() -> void:
	var r := await _started_root()
	r._on_bottom_tab("REALM")
	r._on_bottom_tab("MAP")
	assert_false(r.info_screen().visible)
	assert_true(r.map_screen().visible)

func test_selecting_a_kingdom_fills_the_panel() -> void:
	var r := await _started_root()
	r._on_bottom_tab("MAP")
	var screen := r.map_screen()
	var row: Dictionary = Game.data.kingdoms.values()[0]
	screen.select_state(int(row["state_id"]))
	assert_eq(screen.panel_title().text, String(row["label"]))
	screen.select_state(-1)
	assert_eq(screen.panel_title().text, "", "water click clears the panel")
