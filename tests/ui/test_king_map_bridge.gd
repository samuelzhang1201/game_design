extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const Bridge := preload("res://scripts/ui/king_map_bridge.gd")

var _previous_data: DataRepository

func before_each() -> void:
	_previous_data = Game.data

func after_each() -> void:
	Game.restart()
	Game.data = _previous_data

func test_royal_popup_starts_closed_until_requested() -> void:
	var menu := load("res://scenes/panels/king_order_menu.tscn").instantiate() as KingOrderMenu
	add_child_autofree(menu)
	assert_false(menu.visible, "the exclusive royal popup must not intercept startup keyboard input")

func test_projection_keeps_route_corners_and_never_advances_live_king() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 993)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [[2000, 2000], [2000, 42000]],
		"follow_code": "", "travel_state": "travelling", "last_advanced_day": 0}
	var before := state.king_state.duplicate(true)
	var bridge := Bridge.new()
	var snapshot: Dictionary = bridge.make(repo, state)
	assert_eq(snapshot["king"], before)
	assert_eq(state.king_state, before)
	assert_eq(snapshot["king_path"][0], Vector2i(2000, 2000), "walk the corner, not its chord")
	assert_gt(snapshot["king_path"].size(), 1)
	snapshot["king"]["route"].clear()
	assert_eq(state.king_state, before, "the renderer owns only copied state")

func test_camps_hide_unseen_enemies_and_keep_attacked_packing_progress() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 994)
	var code := String(state.regiments.keys()[0])
	state.regiments[code]["camp_state"] = {"phase": "packing", "build_progress": 1, "pack_start_day": 3}
	state.battles = [{"id": 33, "att": [code], "def": [], "status": "active"}]
	var bridge := Bridge.new()
	var snapshot: Dictionary = bridge.make(repo, state)
	assert_true(snapshot["camps"].has(code))
	assert_eq(snapshot["camps"][code]["phase"], "packing")
	assert_true(snapshot["camps"][code]["under_attack"])
	var visible: Array = Map3DSight.new().regiments(repo, state, false).map(func(r: Dictionary) -> String: return String(r["regiment_code"]))
	for shown: String in snapshot["camps"]:
		assert_true(shown in visible)

func test_snapshot_rebuilds_when_a_paused_king_order_changes() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 995)
	var bridge := Bridge.new()
	bridge.make(repo, state)
	state.king_state["x_m"] += 17
	var snapshot: Dictionary = bridge.make(repo, state)
	assert_eq(snapshot["king"]["x_m"], state.king_state["x_m"])


class QuietMenu extends KingOrderMenu:
	func _pop(_where: Vector2) -> void:
		pass

func test_cancel_and_unpausing_discard_a_destination_confirmation() -> void:
	var repo := SuiteData.repo()
	Game.data = repo
	Game.state = SuiteData.campaign(repo, 997)
	Game.clock_speed = 0
	var before := Game.state.king_state.duplicate(true)
	var view := Map3DView.new()
	autofree(view)
	var menu := QuietMenu.new()
	autofree(menu)
	menu._map = view
	var here := KingSystem.position(Game.state)
	var order := {"action": "KING_MOVE", "params": {"x_m": here.x, "y_m": here.y, "route_m": [here]}}
	menu._confirm(order, Vector2.ZERO)
	menu._chosen(1)
	assert_eq(menu._mode, "")
	assert_false(view.aiming)
	assert_true(menu._pending.is_empty())
	menu._confirm(order, Vector2.ZERO)
	Game.clock_speed = 1
	menu._chosen(0)
	assert_true(menu._pending.is_empty())
	assert_eq(Game.state.king_state, before, "an expired plan cannot spend or move the king")
	Game.clock_speed = 0

class SnapshotView extends Map3DView:
	var received: Dictionary = {}
	var forwards := 0
	func apply_snapshot(snapshot: Dictionary) -> void:
		received = snapshot
		forwards += 1

class SnapshotScreen extends Control:
	var view: Map3DView
	func map3d_view() -> Map3DView:
		return view

func test_paused_root_binds_once_and_forwards_only_changed_snapshots() -> void:
	Game.data = SuiteData.repo()
	Game.state = SuiteData.campaign(Game.data, 998)
	Game.clock_speed = 0
	var root := GameRoot.new()
	autofree(root)
	var screen := SnapshotScreen.new()
	root.add_child(screen)
	var view := SnapshotView.new()
	screen.add_child(view)
	screen.view = view
	root.current_screen = screen
	root.state = GameRoot.State.COURT
	root._process(0.0)
	assert_eq(view.received["king"], Game.state.king_state)
	assert_eq(view.forwards, 1)
	root._process(0.0)
	assert_eq(view.forwards, 1, "unchanged paused frames reuse the projection")
	assert_eq(view.get_signal_connection_list("king_menu_requested").size(), 1)
	Game.state.king_state["x_m"] += 4
	root._process(0.0)
	assert_eq(view.forwards, 2)
	assert_eq(view.received["king"]["x_m"], Game.state.king_state["x_m"])

func test_blocked_encounter_keeps_the_committed_king_and_camp_stationary() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 994)
	state.day = 16
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [[1000, 202000]],
		"follow_code": "", "travel_state": "travelling", "last_advanced_day": 0}
	var mine := String(state.regiments.keys()[0])
	state.regiments[mine]["camp_state"] = {"phase": "packing", "build_progress": 1,
		"pack_start_day": state.absolute_day(), "move_not_before_day": state.absolute_day() + 1}
	var here := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state,
		ArmySystem.regiment(repo, mine, state)))
	var home_px := ArmySystem.metres_to_pack(repo, here)
	var foe_px := home_px + Vector2(0.2, 0.0)
	var foe_m := ArmySystem.pack_to_metres(repo, foe_px)
	var host: Dictionary = repo.raid_hosts[0]
	host["appear_day"] = state.absolute_day() - 10
	host["start_x"] = roundi(foe_px.x)
	host["start_y"] = roundi(foe_px.y)
	EnemyAi.spawn(repo, state, host)
	for code: String in state.foes:
		state.foes[code]["x_m"] = foe_m.x
		state.foes[code]["y_m"] = foe_m.y
		state.foes[code]["dest_x_m"] = foe_m.x
		state.foes[code]["dest_y_m"] = foe_m.y
		state.foes[code]["camp_town"] = ""
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(state)
	assert_eq(blocked.get("status"), "blocked")
	assert_true(state.day_resolution["journal"].get("king_advanced", false))
	assert_false((state.king_state["route"] as Array).is_empty(), "a further journey remains")
	var king_before := state.king_state.duplicate(true)
	var camp_before: Dictionary = state.regiments[mine]["camp_state"].duplicate(true)
	var snapshot := Bridge.new().make(repo, state)
	assert_eq(snapshot["king_path"], [KingSystem.position(state)], "the blocked day already moved the king")
	assert_eq(snapshot["camps"][mine]["phase"], camp_before["phase"])
	assert_eq(state.king_state, king_before)
	assert_eq(state.regiments[mine]["camp_state"], camp_before)

func test_day_journal_change_invalidates_the_cached_royal_forecast() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 993)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [[1000, 202000]],
		"follow_code": "", "travel_state": "travelling", "last_advanced_day": 0}
	var bridge := Bridge.new()
	var ahead := bridge.make(repo, state)
	assert_ne(ahead["king_path"], [KingSystem.position(state)])
	state.day_resolution = {"journal": {"king_advanced": true}}
	var committed := bridge.make(repo, state)
	assert_eq(committed["king_path"], [KingSystem.position(state)])

func test_legacy_transaction_phase_stops_projection_without_a_king_journal() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 993)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [[1000, 202000]],
		"follow_code": "", "travel_state": "travelling", "last_advanced_day": 0}
	state.day_resolution = {"phase": "prepare", "journal": {}}
	var bridge := Bridge.new()
	var ahead := bridge.make(repo, state)
	assert_false(ahead.get("day_committed", false))
	assert_ne(ahead["king_path"], [KingSystem.position(state)])
	state.day_resolution["phase"] = "encounters"
	var committed := bridge.make(repo, state)
	assert_true(committed.get("day_committed", false))
	assert_eq(committed["king_path"], [KingSystem.position(state)])

func test_saved_advance_stamp_stays_stationary_until_the_next_day() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 993)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [[1000, 202000]],
		"follow_code": "", "travel_state": "travelling", "last_advanced_day": state.absolute_day()}
	var bridge := Bridge.new()
	assert_eq(bridge.make(repo, state)["king_path"], [KingSystem.position(state)])
	state.day += 1
	assert_ne(bridge.make(repo, state)["king_path"], [KingSystem.position(state)])

func test_mounted_king_follow_menu_lists_field_armies_not_fleets() -> void:
	Game.data = SuiteData.repo()
	Game.state = SuiteData.campaign(Game.data, 999)
	Game.clock_speed = 0
	var view := Map3DView.new()
	autofree(view)
	var menu := QuietMenu.new()
	autofree(menu)
	menu._map = view
	for entry: Dictionary in Game.state.regiments.values():
		entry["camp_town"] = ""
	menu._open(Vector2.ZERO)
	var follows := 0
	for row: Dictionary in menu._rows:
		if String(row.get("action", "")) == "KING_FOLLOW":
			follows += 1
			var reg := ArmySystem.regiment(Game.data, row["params"]["regiment"], Game.state)
			assert_ne(String(reg.get("is_naval", "0")), "1", "mounted travel offers land rendezvous")
	assert_gt(follows, 0)
