extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")

var repo: DataRepository
var s: GameState
var code: String
var id: String
var home := Vector2i(1000000, 1000000)
var center := Vector2i(1040000, 1000000)

func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	repo.balance["army_clearance_on"] = 0.0
	repo.map_info.merge({"width": "3000", "height": "3000", "distance_scale": "1", "distance_unit": "km"}, true)
	s = SuiteData.campaign(repo, 61041)
	s.tick = 1
	s.day = 10
	s.battles.clear()
	s.foes.clear()
	s.ai_hosts.clear()
	code = String(Play.land_regiments(repo)[0])
	var e: Dictionary = s.regiments[code]
	e["x_m"] = home.x
	e["y_m"] = home.y
	e["dest_x_m"] = home.x
	e["dest_y_m"] = home.y
	e["order"] = ArmySystem.ORDER_GARRISON
	e.erase("departure")
	e.erase("camp_town")
	e["camp_state"] = {"phase": CampSystem.NONE}
	id = _issue(center)

func after_each() -> void:
	MarchPath.forget()

func _issue(at: Vector2i, task_id := "") -> String:
	var out := ArmyTasks.issue(repo, s, {"id": task_id, "kind": "search", "unit_codes": [code],
		"center_x_m": at.x, "center_y_m": at.y, "radius_m": 2000})
	assert_true(out["ok"], str(out))
	return String(out.get("id", ""))

func _unit() -> Dictionary:
	return s.army_tasks[id]["units"][code]

func _at() -> Vector2i:
	return Vector2i(int(s.regiments[code]["x_m"]), int(s.regiments[code]["y_m"]))

func _dest() -> Vector2i:
	return Vector2i(int(s.regiments[code]["dest_x_m"]), int(s.regiments[code]["dest_y_m"]))

func _receive(revision := 1, status := "received") -> void:
	assert_eq(ArmyTasks.receive(repo, s, id, revision, code)["status"], status)

func test_pending_then_received_order_moves_through_daily_transaction() -> void:
	var engine := TickEngine.new(repo)
	assert_eq(engine.resolve_day(s)["status"], "complete")
	assert_eq(_at(), home, "pending task moves nothing")
	_receive()
	assert_eq(_at(), home, "receipt never teleports")
	assert_eq(engine.resolve_day(s)["status"], "complete")
	assert_ne(_at(), home, "received search travels on the next resolved day")
	assert_eq(_dest(), center)
	assert_true(s.army_tasks[id].get("coverage", {}).is_empty(), "travel never claims search coverage")

func test_received_revision_keeps_its_circle_until_replacement_arrives() -> void:
	_receive()
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), center)
	var changed := center + Vector2i(20000, 0)
	_issue(changed, id)
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), center)
	_receive(2)
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), changed)

func test_packing_and_json_retry_preserve_deadline() -> void:
	s.regiments[code]["camp_state"] = {"phase": CampSystem.CAMPED, "pack_start_day": -1,
		"move_not_before_day": -1, "site": {"x_m": home.x, "y_m": home.y}}
	_receive()
	ArmyTasks.step_day(repo, s)
	var day := s.absolute_day()
	assert_false(CampSystem.can_march(s, code, day))
	assert_true(CampSystem.can_march(s, code, day + 1))
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), false)
	var before := SaveLoad.state_hash(restored)
	ArmyTasks.step_day(repo, restored)
	assert_eq(SaveLoad.state_hash(restored), before)
	s = restored
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(int(s.regiments[code]["camp_state"]["move_not_before_day"]), day + 1)

func _grid(wall: bool) -> void:
	repo.balance["army_march_grid_px"] = 1.0
	var slopes := PackedByteArray()
	slopes.resize(120 * 120)
	slopes.fill(0)
	if wall:
		for y: int in 120:
			slopes[y * 120 + 102] = 255
	else:
		slopes[100 * 120 + 104] = 255
	MarchPath.use(repo, MarchPath.build(repo, 120, 120, 10000, slopes))

func test_closed_center_uses_reachable_ground_inside_circle() -> void:
	# Centre is at the closed cell's northwest corner. North and west
	# open neighbours tie at one metre; row-major order chooses north.
	_grid(false)
	_receive()
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), Vector2i(1040000, 999999))
	assert_false(MarchPath.of_pack(repo).is_closed(MarchPath.of_pack(repo).cell_of(_dest())))
	assert_eq(_unit().get("phase", ""), "travelling")

func test_disconnected_circle_fails_without_marching_or_marking_searched() -> void:
	_grid(true)
	_receive()
	ArmyTasks.step_day(repo, s)
	assert_eq(_at(), home)
	assert_eq(s.regiments[code]["order"], ArmySystem.ORDER_GARRISON)
	assert_eq(_unit().get("phase", ""), "failed")
	assert_ne(String(_unit().get("reason", "")), "")
	assert_true(s.army_tasks[id].get("coverage", {}).is_empty())

func test_arrival_waits_for_search_without_claiming_completion() -> void:
	_receive()
	s.regiments[code]["x_m"] = center.x
	s.regiments[code]["y_m"] = center.y
	s.regiments[code]["order"] = ArmySystem.ORDER_MARCH
	s.regiments[code]["dest_x_m"] = center.x + 50000
	ArmyTasks.step_day(repo, s)
	assert_eq(_unit().get("phase", ""), "awaiting_search")
	assert_eq(s.regiments[code]["order"], ArmySystem.ORDER_GARRISON, "arrival replaces an existing march")
	assert_false(s.army_tasks[id].has("completed_day"))
	assert_true(s.army_tasks[id].get("coverage", {}).is_empty())

func test_battle_gates_travel_and_recall_stops_its_departure() -> void:
	_receive()
	s.battles.append({"id": 1, "att": [code], "def": ["foe"]})
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), home)
	assert_eq(_unit().get("phase", ""), "paused_battle")
	s.battles.clear()
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), home, "post-battle capability/return decision belongs to P6.1f")
	_issue(center, id)
	_receive(2)
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), center)
	ArmyTasks.cancel(repo, s, id)
	_receive(3, "cancelled")
	assert_eq(s.regiments[code]["order"], ArmySystem.ORDER_GARRISON)
	assert_false(s.regiments[code].has("departure"))

func test_newest_received_task_owns_unit_even_after_its_recall() -> void:
	_receive()
	var old := id
	id = _issue(center + Vector2i(30000, 0))
	_receive()
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), center + Vector2i(30000, 0))
	ArmyTasks.cancel(repo, s, id)
	_receive(2, "cancelled")
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(s.regiments[code]["order"], ArmySystem.ORDER_GARRISON)
	assert_false(ArmyTasks.acting(s, old, code).is_empty(), "old receipt retained, not reactivated")

func test_hidden_positions_do_not_change_travel_choice() -> void:
	_receive()
	var hidden := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), false)
	hidden.sightings.clear()
	hidden.foes["unseen"] = {"x_m": center.x, "y_m": center.y}
	ArmyTasks.step_day(repo, s)
	ArmyTasks.step_day(repo, hidden)
	assert_eq(hidden.army_tasks, s.army_tasks)
	assert_eq(hidden.regiments[code], s.regiments[code])

func test_real_daily_march_reaches_circle_and_waits_without_search_completion() -> void:
	_receive()
	var engine := TickEngine.new(repo)
	var guard := 0
	while String(_unit().get("phase", "")) != "awaiting_search" and guard < 15:
		assert_eq(engine.resolve_day(s)["status"], "complete")
		guard += 1
	assert_eq(_unit().get("phase", ""), "awaiting_search")
	var delta := _at() - center
	assert_true(delta.x * delta.x + delta.y * delta.y <= 2000 * 2000)
	assert_eq(s.regiments[code]["order"], ArmySystem.ORDER_GARRISON)
	assert_true(s.army_tasks[id].get("coverage", {}).is_empty())
	assert_false(s.army_tasks[id].has("completed_day"))

func test_recall_during_packing_cannot_restore_departure_on_later_day() -> void:
	s.regiments[code]["camp_state"] = {"phase": CampSystem.CAMPED, "pack_start_day": -1,
		"move_not_before_day": -1, "site": {"x_m": home.x, "y_m": home.y}}
	_receive()
	var engine := TickEngine.new(repo)
	assert_eq(engine.resolve_day(s)["status"], "complete")
	assert_eq(_at(), home, "the full packing day moves nothing")
	assert_true(s.regiments[code].has("departure"))
	ArmyTasks.cancel(repo, s, id)
	_receive(2, "cancelled")
	assert_false(s.regiments[code].has("departure"))
	assert_eq(engine.resolve_day(s)["status"], "complete")
	assert_eq(_at(), home)
	assert_eq(s.regiments[code]["order"], ArmySystem.ORDER_GARRISON)

func test_new_revision_of_older_task_can_replace_newer_task_after_receipt() -> void:
	_receive()
	var first := id
	id = _issue(center + Vector2i(30000, 0))
	_receive()
	ArmyTasks.step_day(repo, s)
	id = first
	var revised := center + Vector2i(50000, 0)
	_issue(revised, id)
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), center + Vector2i(30000, 0), "new revision is still riding")
	_receive(2)
	s.day += 1
	ArmyTasks.step_day(repo, s)
	assert_eq(_dest(), revised, "issuance order includes revisions, not just task IDs")
