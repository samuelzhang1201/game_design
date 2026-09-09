extends GutTest
## The MILITARY tab (user request 2026-09-09): the host by arm with icons and
## bars, every regiment, and the neighbours' reported strength.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_military_tab_shows_charts_instead_of_the_table() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(2)
	assert_true(r.info_screen().visible)
	var panel := r.info_screen().military_panel()
	assert_true(panel.visible, "the charts take the tab")
	assert_false(r.info_screen().table().visible, "the plain table steps aside")
	var units: Array = Game.data.world_table("military", "unit_types").keys()
	assert_eq(panel.arms_chart().rows.size(), units.size(), "one bar per arm")
	for row in panel.arms_chart().rows:
		assert_ne(String(row["icon"]), "", "each arm has its glyph")
	var mine := Game.data.resolve_realm("player_realm")
	var regiments := 0
	for reg: Dictionary in Game.data.world_table("military", "regiments").values():
		if String(reg["kingdom_code"]) == mine:
			regiments += 1
	assert_eq(panel.regiments_chart().rows.size(), regiments, "every regiment of the realm")
	var neighbours := String(Game.data.kingdoms[mine]["neighbor_codes"]).split("|", false).size()
	assert_eq(panel.neighbours_chart().rows.size(), neighbours + 1, "each neighbour and the realm itself")
	# Back to a table tab: the grid returns.
	r.bottom_bar().button("REALM").pressed.emit()
	await wait_frames(1)
	assert_false(panel.visible)
	assert_true(r.info_screen().table().visible)

func test_bars_follow_the_ledger() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	WorldLedger.apply(Game.data, Game.state, "military.kingdoms.player_realm.infantry", -300.0,
		"a bad winter", "test")
	r.bottom_bar().button("MILITARY").pressed.emit()
	await wait_frames(1)
	var infantry := float(WorldLedger.value_of(Game.data, Game.state,
		"military.kingdoms.player_realm.infantry"))
	var seen := false
	for row in r.info_screen().military_panel().arms_chart().rows:
		if String(row["icon"]) == "shield":
			seen = true
			assert_almost_eq(float(row["value"]), infantry, 0.5, "the bar reads the live count")
	assert_true(seen, "the infantry bar is there")
