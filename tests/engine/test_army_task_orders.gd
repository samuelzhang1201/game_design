extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## P6.1c (spec 2026-10-16 battle-system §13.1/.6): ARMY_TASK turns a legal preview
## into a paid, saved order; each unit acts only on the revision it has RECEIVED
## (locally within the king's range, else by its own courier). Nothing moves yet.

var repo: DataRepository
var s: GameState
var a: String
var b: String
var actions: ActionSystem


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 61)
	var codes := Play.land_regiments(repo)
	a = String(codes[0])
	b = String(codes[1])
	Intel.dev_all = false
	actions = ActionSystem.new(repo)
	repo.courier_kinds["ordinary"]["gold"] = 2
	repo.balance["king_command_radius_m"] = 1.0
	s.metrics["treasury"] = 100
	var at := _at(a)
	s.king_state["x_m"] = at.x
	s.king_state["y_m"] = at.y
	# B stands 50 km from A, beyond the (shrunk) command radius
	s.regiments[b]["x_m"] = at.x + 50000
	s.regiments[b]["y_m"] = at.y


func _at(code: String) -> Vector2i:
	return Vector2i(int(s.regiments[code]["x_m"]), int(s.regiments[code]["y_m"]))


func _req(id: String, extra: Dictionary = {}) -> ActionRequest:
	var at := _at(a)
	var p := {"request_id": id, "kind": "search", "unit_codes": [a, b], "center_x_m": at.x,
		"center_y_m": at.y, "radius_m": 3000, "known_target_id": "", "encounter_policy": ""}
	p.merge(extra, true)
	return ActionRequest.make("ARMY_TASK", p)


func _ride_all() -> void:
	var guard := 0
	while not s.couriers.is_empty() and guard < 400:
		CourierSystem.ride_day(repo, s)
		guard += 1


func _unit(id: String, code: String) -> Dictionary:
	return s.army_tasks[id]["units"][code]


func test_issue_pays_once_local_unit_receives_far_unit_waits_for_its_courier() -> void:
	assert_true(KingSystem.can_command(repo, s, a))
	assert_false(KingSystem.can_command(repo, s, b))
	var req := _req("r1")
	assert_eq(actions.validate(req, s), "")
	var out := actions.execute(req, s)
	assert_true(out["ok"], str(out))
	assert_eq(int(s.metrics["treasury"]), 100 - 1 - 2, "one filing gold plus one courier fee (only B rides)")
	assert_eq(s.couriers.size(), 1)
	var id := String(s.army_tasks.keys()[0])
	assert_eq(_unit(id, a)["status"], "received")
	assert_eq(_unit(id, a)["received_revision"], 1)
	assert_eq(_unit(id, b)["status"], "pending")
	assert_eq(_unit(id, b)["received_revision"], 0)
	_ride_all()
	assert_eq(_unit(id, b)["status"], "received")
	assert_eq(_unit(id, b)["received_revision"], 1)
	assert_gt(_unit(id, b)["received_day"], 0 - 1)
	for h: Dictionary in s.army_tasks[id]["history"]:
		assert_ne(String(h["reason"]), "", "every move has a reason")


func test_reissue_gives_revision_two_and_a_late_revision_one_is_superseded() -> void:
	actions.execute(_req("r1"), s)
	var id := String(s.army_tasks.keys()[0])
	var again := _req("r2", {"task_id": id, "radius_m": 4000})
	assert_eq(actions.validate(again, s), "")
	assert_true(actions.execute(again, s)["ok"])
	assert_eq(s.army_tasks.size(), 1, "same task, next revision")
	assert_eq(s.army_tasks[id]["revision"], 2)
	assert_eq(_unit(id, a)["received_revision"], 2, "the near unit has the new circle at once")
	assert_eq(_unit(id, b)["received_revision"], 0)
	_ride_all()
	assert_eq(_unit(id, b)["received_revision"], 2)
	assert_eq(_unit(id, b)["status"], "received")
	# a revision-1 courier arriving after revision 2 changes nothing
	var r := ArmyTasks.receive(repo, s, id, 1, b)
	assert_eq(r["status"], "superseded")
	assert_eq(_unit(id, b)["received_revision"], 2)
	assert_eq(ArmyTasks.acting(s, id, b)["radius_m"], 4000)


func test_an_older_revision_keeps_acting_until_the_new_one_arrives() -> void:
	actions.execute(_req("r1"), s)
	var id := String(s.army_tasks.keys()[0])
	_ride_all()
	actions.execute(_req("r2", {"task_id": id, "radius_m": 5000}), s)
	assert_eq(_unit(id, b)["status"], "pending")
	assert_eq(_unit(id, b)["received_revision"], 1)
	assert_eq(ArmyTasks.acting(s, id, b)["radius_m"], 3000)
	_ride_all()
	assert_eq(ArmyTasks.acting(s, id, b)["radius_m"], 5000)


func test_cancel_is_a_revision_delivered_like_any_other() -> void:
	actions.execute(_req("r1"), s)
	var id := String(s.army_tasks.keys()[0])
	_ride_all()
	var cancel := ActionRequest.make("ARMY_TASK_CANCEL", {"request_id": "c1", "task_id": id})
	assert_eq(actions.validate(cancel, s), "")
	var before := int(s.metrics["treasury"])
	assert_true(actions.execute(cancel, s)["ok"])
	assert_eq(before - int(s.metrics["treasury"]), 1 + 2, "filing plus B's courier")
	assert_eq(_unit(id, a)["status"], "cancelled")
	assert_eq(_unit(id, b)["status"], "pending", "the recall is still riding")
	assert_false(ArmyTasks.acting(s, id, b).is_empty(), "B still acts on revision 1")
	_ride_all()
	assert_eq(_unit(id, b)["status"], "cancelled")
	assert_true(ArmyTasks.acting(s, id, b).is_empty())


func test_a_refused_preview_changes_nothing_and_pays_nothing() -> void:
	var fleet := ""
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		if String(reg.get("is_naval", "0")) == "1" and s.regiments.has(String(reg["regiment_code"])):
			fleet = String(reg["regiment_code"])
	if fleet == "":
		pending("no fleet in this pack")
		return
	var req := _req("bad", {"unit_codes": [fleet]})
	assert_ne(actions.validate(req, s), "")
	var before := s.to_dict()
	assert_false(actions.execute(req, s)["ok"])
	assert_eq(s.to_dict(), before)
	var empty := _req("bad2", {"unit_codes": []})
	assert_eq(actions.validate(empty, s), repo.task_words["no_units"])


func test_exact_retry_returns_the_saved_result_without_paying_twice() -> void:
	var req := _req("r1")
	var out := actions.execute(req, s)
	var paid := int(s.metrics["treasury"])
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	saved.metrics["treasury"] = 0
	assert_eq(actions.execute(_req("r1"), saved), out)
	assert_eq(int(saved.metrics["treasury"]), 0)
	assert_eq(actions.execute(req, s), out)
	assert_eq(int(s.metrics["treasury"]), paid)
	assert_eq(s.army_tasks.size(), 1)
	assert_false(actions.execute(_req("r1", {"radius_m": 3500}), s)["ok"], "same id, other params")


func test_json_roundtrip_mid_ride_keeps_the_task_and_the_courier() -> void:
	actions.execute(_req("r1"), s)
	var id := String(s.army_tasks.keys()[0])
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(saved.army_tasks, s.army_tasks)
	assert_eq(saved.army_task_next_id, s.army_task_next_id)
	assert_eq(saved.couriers.size(), 1)
	s = saved
	_ride_all()
	assert_eq(_unit(id, b)["status"], "received")
	var raw := s.to_dict()
	raw.erase("army_tasks")
	raw.erase("army_task_next_id")
	var old := GameState.from_dict(JSON.parse_string(JSON.stringify(raw)))
	assert_eq(old.army_tasks, {}, "older saves carry none")
	assert_eq(old.army_task_next_id, 0)


func test_a_lost_courier_leaves_the_unit_pending_with_a_reason() -> void:
	actions.execute(_req("r1"), s)
	var id := String(s.army_tasks.keys()[0])
	s.couriers[0]["days"] = int(repo.bal("courier_max_days"))
	CourierSystem.ride_day(repo, s)
	assert_true(s.couriers.is_empty())
	assert_eq(_unit(id, b)["status"], "pending")
	assert_eq(_unit(id, b)["received_revision"], 0)
	var last: Dictionary = s.army_tasks[id]["history"].back()
	assert_eq(last["unit"], b)
	assert_eq(last["status"], "lapsed")
	assert_ne(String(last["reason"]), "")


func test_two_remote_units_pay_a_courier_each_and_the_preview_agrees() -> void:
	var at := _at(a)
	s.regiments[a]["x_m"] = at.x + 90000
	var req := _req("r1")
	var quote := ArmyTasks.preview(repo, s, repo.resolve_realm("player_realm"), req.params)
	assert_true(quote["ok"], str(quote))
	var before := int(s.metrics["treasury"])
	assert_true(actions.execute(req, s)["ok"])
	assert_eq(s.couriers.size(), 2)
	assert_eq(before - int(s.metrics["treasury"]), int(quote["cost"]["gold"]))
	assert_eq(before - int(s.metrics["treasury"]), 1 + 2 * 2)
