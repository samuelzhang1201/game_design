extends GutTest
## The Manor Master (MANOR_SYSTEM.md §6): every manor in a sortable table in
## the LEFT column while the MANORS tab is lit; a row centres and rings the
## manor on the map, activating it opens the card.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _court() -> GameRoot:
	Game.start_campaign(42)
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r

func test_the_manors_tab_lists_the_realms_manors_biggest_first() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var panel: ManorMasterPanel = screen.manor_master()
	assert_false(panel.visible, "off by default")
	r.bottom_bar().button("MANORS").pressed.emit()
	await wait_frames(1)
	assert_true(panel.visible, "the tab drives it")
	assert_false(screen.dashboard().visible, "in place of the dashboard")
	var realm := Game.data.resolve_realm("player_realm")
	var expected := 0
	for province: String in MapOwnership.provinces_of(Game.data, Game.state, realm):
		expected += MapManors.manors_of_province(Game.data, province).size()
	var cap := int(Game.data.bal("manor_master_max_rows"))
	assert_eq(panel.rows().size(), mini(expected, cap), "the realm's manors, capped")
	assert_eq(panel.left_out(), maxi(expected - cap, 0))
	assert_string_contains(panel.summary_text(), "%d manors in the realm" % expected)
	var rows := panel.rows()
	for i in range(1, rows.size()):
		assert_true(float(rows[i - 1]["value"]) >= float(rows[i]["value"]), "value, biggest first")
	assert_eq(panel.table().get_root().get_child_count(), rows.size(), "one table row each")
	# The crown's manors are named as the crown's, the others as their house.
	var crowns := 0
	for row: Dictionary in rows:
		if String(row["house"]) == "The crown":
			crowns += 1
		else:
			assert_ne(String(row["family"]), MapManors.crown(Game.state))
	assert_gt(crowns, 0)
	# Sorting by name, then by name again, flips the order.
	panel.sort_by(0)
	var first := String(panel.rows()[0]["label"])
	assert_true(first <= String(panel.rows()[1]["label"]))
	panel.sort_by(0)
	assert_true(String(panel.rows()[0]["label"]) >= first)

## Each row's house carries its arms before its name (owner 2026-09-15).
func test_each_row_wears_its_houses_arms() -> void:
	var r: GameRoot = await _court()
	var panel: ManorMasterPanel = (r.current_screen as CourtScreen).manor_master()
	r.bottom_bar().button("MANORS").pressed.emit()
	await wait_frames(1)
	var item := panel.table().get_root().get_first_child()
	var i := 0
	while item != null:
		var arms := HouseArms.texture_of_house(Game.data, Game.state, String(panel.rows()[i]["family"]))
		assert_not_null(arms, String(panel.rows()[i]["family"]))
		assert_same(item.get_icon(1), arms)
		item = item.get_next()
		i += 1
	assert_gt(i, 0)

func test_scope_and_house_narrow_or_widen_the_table() -> void:
	var r: GameRoot = await _court()
	var panel: ManorMasterPanel = r.current_screen.manor_master()
	r.bottom_bar().button("MANORS").pressed.emit()
	await wait_frames(1)
	var realm_rows := panel.rows().size()
	panel.set_scope(true)
	var cap := int(Game.data.bal("manor_master_max_rows"))
	assert_eq(panel.rows().size(), mini(Game.data.manors.size(), cap), "every manor on the map, capped")
	assert_eq(panel.left_out(), Game.data.manors.size() - cap)
	assert_string_contains(panel.summary_text(), "in the map")
	panel.set_scope(false)
	assert_eq(panel.rows().size(), realm_rows)
	# The house filter: pick the biggest house other than the crown.
	var crown := MapManors.crown(Game.state)
	var family := ""
	for i in range(1, panel.house_button().item_count):
		var f := String(panel.house_button().get_item_metadata(i))
		if f != crown:
			family = f
			break
	assert_ne(family, "")
	panel.set_house(family)
	assert_gt(panel.rows().size(), 0)
	assert_lt(panel.rows().size(), realm_rows)
	for row: Dictionary in panel.rows():
		assert_eq(String(row["family"]), family)
	panel.set_house("")
	assert_eq(panel.rows().size(), realm_rows)

func test_activating_a_row_opens_its_card() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var panel: ManorMasterPanel = screen.manor_master()
	r.bottom_bar().button("MANORS").pressed.emit()
	await wait_frames(1)
	var cell: int = panel.rows()[3]["cell"]
	# (Centring and ringing it are the 3D map's, which a headless run does
	# not load: tests/map3d cover the selection outline.)
	assert_true(panel.choose(cell), "the row is in the table")
	await wait_frames(1)
	assert_true(panel.visible, "a click keeps the table")
	panel.manor_activated.emit(cell)
	await wait_frames(1)
	assert_eq(screen.detail_panel().shown_manor(), cell, "activating opens the card")
	assert_false(panel.visible, "which takes the column until it closes")
	screen.detail_panel().close_button().pressed.emit()
	await wait_frames(1)
	assert_true(panel.visible, "and the table returns")
