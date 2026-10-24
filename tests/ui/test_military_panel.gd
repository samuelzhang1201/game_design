extends GutTest
## The host (user requests 2026-09-09 / 2026-09-10): by arm with icons and
## bars, every regiment, and the neighbours' reported strength — in the LEFT
## column. Since 2026-09-27 (owner) there is no MILITARY tab: the regiments are
## always on the map and the host opens from a regiment's card.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _court() -> GameRoot:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	return r

func test_the_host_opens_from_a_regiments_card_and_closes_back() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	assert_false(screen.military_panel().visible, "the column shows the realm to begin with")
	assert_true(screen.dashboard().visible)
	var mine := Game.data.resolve_realm("player_realm")
	var first: Dictionary = MapObjects.regiments_of(Game.data, mine, Game.state)[0]
	var detail: MapDetailPanel = screen.find_child("DetailPanel", true, false)
	detail.show_entry({"title": "x", "obj": {"kind": "army", "code": String(first["regiment_code"])}})
	await wait_process_frames(1)
	var host: Button = detail.find_child("TheHost", true, false)
	assert_not_null(host, "a regiment's card offers the whole host")
	host.pressed.emit()
	await wait_process_frames(2)
	var panel := screen.military_panel()
	assert_true(panel.visible, "the host takes the left column")
	assert_false(detail.visible, "in place of the card")
	assert_false(screen.dashboard().visible, "and of the dashboard")
	assert_lt(panel.get_global_rect().position.x,
		screen.find_child("MapPanel", true, false).get_global_rect().position.x,
		"the left column, not the right slot")
	var units: Array = Game.data.world_table("military", "unit_types").keys()
	assert_eq(panel.arms_chart().rows.size(), units.size(), "one bar per arm")
	for row in panel.arms_chart().rows:
		assert_ne(String(row.get("dimension", "")), "", "each arm carries its dimension (its art)")
	var regiments := MapObjects.regiments_of(Game.data, mine, Game.state).size()
	assert_eq(panel.regiments_chart().rows.size(), regiments, "every regiment of the realm")
	var neighbours := String(Game.data.kingdoms[mine]["neighbor_codes"]).split("|", false).size()
	# Neighbours' strength is fogged (Intel, 2026-09-28): a text row each, not
	# a bar, so the seam is a box of rows rather than a chart's data.
	assert_eq(panel.neighbours_chart().get_child_count(), neighbours + 1, "each neighbour and the realm itself")
	(panel.find_child("Close", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_false(panel.visible)
	assert_true(screen.dashboard().visible, "the dashboard has the column back")
	assert_true(screen.map3d_view().military(), "and the regiments stay on the map")

## The regiments are on every screen's map, with no tab to light.
func test_the_regiments_are_on_every_screens_map() -> void:
	var r: GameRoot = await _court()
	assert_true(r.current_screen.map3d_view().military())
	r._switch_to(GameRoot.State.CONVERSATION)
	await wait_process_frames(2)
	assert_true(r.current_screen.map3d_view().military(),
		"the council stage's map draws the regiments too")

## The bars read the ledger when the host opens, and — as the table it
## replaced refreshed live — the column follows the state while it is up.
func test_the_column_follows_the_state_while_it_is_up() -> void:
	var r: GameRoot = await _court()
	var code := ""
	for row: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if MapObjects.regiment_arm(Game.data, row) == "infantry":
			code = String(row["regiment_code"])
			break
	var cohort_id := ""
	for id: String in Game.state.military_rosters[code]["cohort_ids"]:
		if int(Game.state.military_cohorts[id]["fit"]) >= 8:
			cohort_id = id
			break
	assert_ne(cohort_id, "")
	assert_false(MilitaryRoster.transition(Game.data, Game.state, "host:wounds", [
		{"cohort_id": cohort_id, "from": "fit", "to": "wounded", "count": 3}], "a bad winter").has("error"))
	r.set_army_view(true)
	await wait_process_frames(2)
	var panel: MilitaryPanel = r.current_screen.military_panel()
	var infantry := 0
	for row: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if MapObjects.regiment_arm(Game.data, row) == "infantry":
			infantry += ArmySystem.living_count(Game.data, Game.state, String(row["regiment_code"]))
	var before := -1.0
	for row in panel.arms_chart().rows:
		if String(row.get("dimension", "")) == "infantry":
			before = float(row["value"])
	assert_eq(int(before), infantry, "the host includes its wounded people")
	assert_false(MilitaryRoster.transition(Game.data, Game.state, "host:dead", [
		{"cohort_id": cohort_id, "from": "fit", "to": "dead", "count": 5}], "a hard march").has("error"))
	SignalHub.state_changed.emit()
	await wait_process_frames(2)
	for row in panel.arms_chart().rows:
		if String(row.get("dimension", "")) == "infantry":
			assert_eq(int(row["value"]), int(before) - 5, "the bar follows personnel losses with no click")
