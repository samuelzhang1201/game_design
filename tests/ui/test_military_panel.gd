extends GutTest
## The MILITARY tab (user requests 2026-09-09 / 2026-09-10): the host by arm
## with icons and bars, every regiment, and the neighbours' reported strength
## — in the LEFT column, beside the realm's regiments drawn on the map with a
## strength bar under each. The tab is a toggle now, not a dimming overlay.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _court() -> GameRoot:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r

func test_military_tab_shows_the_host_in_the_left_column() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	assert_false(screen.military_panel().visible, "the tab is dark to begin with")
	assert_true(screen.dashboard().visible, "the column shows the realm")
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(2)
	assert_false(r.info_screen().visible, "no overlay dims the map any more")
	assert_true(r.army_view(), "the layer is on")
	assert_true(r.bottom_bar().button("MILITARY").button_pressed, "and the tab is lit")
	var panel := screen.military_panel()
	assert_true(panel.visible, "the host takes the left column")
	assert_false(screen.dashboard().visible, "in place of the dashboard")
	assert_lt(panel.get_global_rect().position.x,
		screen.find_child("MapPanel", true, false).get_global_rect().position.x,
		"the left column, not the right slot")
	var units: Array = Game.data.world_table("military", "unit_types").keys()
	assert_eq(panel.arms_chart().rows.size(), units.size(), "one bar per arm")
	for row in panel.arms_chart().rows:
		assert_ne(String(row["icon"]), "", "each arm has its glyph")
	var mine := Game.data.resolve_realm("player_realm")
	var regiments := MapObjects.regiments_of(Game.data, mine).size()
	assert_eq(panel.regiments_chart().rows.size(), regiments, "every regiment of the realm")
	var neighbours := String(Game.data.kingdoms[mine]["neighbor_codes"]).split("|", false).size()
	assert_eq(panel.neighbours_chart().rows.size(), neighbours + 1, "each neighbour and the realm itself")
	# Pressing it again puts the realm back and clears the map.
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(2)
	assert_false(r.army_view())
	assert_false(panel.visible)
	assert_true(screen.dashboard().visible, "the dashboard has the column back")
	assert_false(screen.map3d_view().military(), "and the map drops the layer")

func test_bars_follow_the_ledger() -> void:
	var r: GameRoot = await _court()
	WorldLedger.apply(Game.data, Game.state, "military.kingdoms.player_realm.infantry", -300.0,
		"a bad winter", "test")
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(1)
	var infantry := float(WorldLedger.value_of(Game.data, Game.state,
		"military.kingdoms.player_realm.infantry"))
	var seen := false
	for row in r.current_screen.military_panel().arms_chart().rows:
		if String(row["icon"]) == "shield":
			seen = true
			assert_almost_eq(float(row["value"]), infantry, 0.5, "the bar reads the live count")
	assert_true(seen, "the infantry bar is there")

## The layer follows the player from screen to screen, like the province view.
func test_the_layer_survives_a_screen_change() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(2)
	r._switch_to(GameRoot.State.CONVERSATION)
	await wait_frames(2)
	assert_true(r.current_screen.map3d_view().military(),
		"the council stage's map draws the regiments too")

## The table it replaced refreshed live; the column does too.
func test_the_column_follows_the_state_while_it_is_up() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(2)
	var panel: MilitaryPanel = r.current_screen.military_panel()
	var before := 0.0
	for row in panel.arms_chart().rows:
		if String(row["icon"]) == "shield":
			before = float(row["value"])
	WorldLedger.apply(Game.data, Game.state, "military.kingdoms.player_realm.infantry", -500.0,
		"a hard march", "test")
	# The same contract the dashboard has: the column redraws on the signal
	# the engine raises after a tick or an order, not on every ledger write.
	Game.state_changed.emit()
	await wait_frames(2)
	for row in panel.arms_chart().rows:
		if String(row["icon"]) == "shield":
			assert_almost_eq(float(row["value"]), before - 500.0, 0.5,
				"the bar followed the ledger with no click")
