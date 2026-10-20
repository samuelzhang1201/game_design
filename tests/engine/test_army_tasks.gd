extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## P6.1b (spec 2026-10-16-battle-system-design §13): the area-task preview is free,
## pure, and reads only what the crown knows. Towns it lists are the realm's own
## or ones a filed report covers (Intel); a hidden foe or an unknown town never
## changes a preview.

var repo: DataRepository
var s: GameState
var unit: String
var realm: String


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 61)
	realm = repo.resolve_realm("player_realm")
	unit = String(Play.land_regiments(repo)[0])
	Intel.dev_all = false


func _task(kind: String, at: Vector2i, radius: int, extra: Dictionary = {}) -> Dictionary:
	var t := {"kind": kind, "unit_codes": [unit], "center_x_m": at.x, "center_y_m": at.y,
		"radius_m": radius, "known_target_id": "", "encounter_policy": ""}
	t.merge(extra, true)
	return t


func _unit_m() -> Vector2i:
	return Vector2i(int(s.regiments[unit]["x_m"]), int(s.regiments[unit]["y_m"]))


func _town_m(t: String) -> Vector2i:
	return ArmyGround.town_point_m(repo, t)


## Two realm towns and a circle (centre, radius) that holds both; the radius cap
## is lifted so the pack's spacing never decides.
func _two_towns() -> Dictionary:
	repo.balance["task_max_radius_m"] = 400000.0
	var towns: Array = TownStores.realm_towns(repo, s)
	assert_gt(towns.size(), 1, "the realm has two towns")
	var a: String = towns[0]
	var b: String = towns[1]
	var at := _town_m(a)
	return {"a": a, "b": b, "at": at, "r": int(Vector2(at).distance_to(Vector2(_town_m(b)))) + 1}


func _unknown_town() -> String:
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for c: String in codes:
		var subj := {"kind": "burg", "code": c, "x": float(repo.burgs[c]["x"]), "y": float(repo.burgs[c]["y"])}
		if Intel.level(repo, s, subj) == "basic" and Intel.estimate(repo, s, subj, "town_people").is_empty():
			return c
	return ""


func test_refusals_use_the_csv_words() -> void:
	var at := _unit_m()
	var cases := [
		[{"unit_codes": []}, "no_units"],
		[{"unit_codes": ["no_such_unit"]}, "bad_unit"],
		[{"kind": "pillage"}, "bad_kind"],
		[{"radius_m": 0}, "bad_radius"],
		[{"radius_m": int(repo.bal("task_max_radius_m")) + 1}, "bad_radius"],
		[{"center_x_m": -1}, "off_map"],
		[{"kind": "raid", "encounter_policy": "keep_distance"}, "bad_policy"],
		[{"kind": "destroy"}, "destroy_no_kind"],
	]
	for c: Array in cases:
		var p := ArmyTasks.preview(repo, s, realm, _task("search", at, 3000, c[0]))
		assert_false(p["ok"], str(c[1]))
		assert_eq(p["reason"], repo.task_words[c[1]], str(c[1]))
	assert_ne(repo.task_words["bad_radius"], "")


func test_a_fleet_is_not_a_land_unit() -> void:
	var fleet := ""
	for reg: Dictionary in MapObjects.regiments_of(repo, realm, s):
		if String(reg.get("is_naval", "0")) == "1" and s.regiments.has(String(reg["regiment_code"])):
			fleet = String(reg["regiment_code"])
	if fleet == "":
		pending("no fleet in this pack")
		return
	var p := ArmyTasks.preview(repo, s, realm, _task("search", _unit_m(), 3000, {"unit_codes": [fleet]}))
	assert_eq(p["reason"], repo.task_words["bad_unit"])


func test_siege_needs_a_known_town_and_a_choice() -> void:
	var w := _two_towns()
	var none := ArmyTasks.preview(repo, s, realm, _task("siege", w["at"] + Vector2i(0, 90000), 1000))
	assert_eq(none["reason"], repo.task_words["siege_no_town"])
	var two := ArmyTasks.preview(repo, s, realm, _task("siege", w["at"], w["r"]))
	assert_false(two["ok"])
	assert_eq(two["reason"], repo.task_words["siege_choose"], "two known towns, no target named")
	var one := ArmyTasks.preview(repo, s, realm, _task("siege", w["at"], w["r"], {"known_target_id": w["b"]}))
	assert_true(one["ok"], str(one))
	assert_eq(one["target"], w["b"])
	assert_true(w["a"] in one["towns"] and w["b"] in one["towns"])
	var sorted: Array = one["towns"].duplicate()
	sorted.sort()
	assert_eq(one["towns"], sorted, "sorted")
	var bad := ArmyTasks.preview(repo, s, realm, _task("siege", w["at"], w["r"], {"known_target_id": "nowhere"}))
	assert_eq(bad["reason"], repo.task_words["siege_bad_target"])


func test_encounter_policy_follows_the_kind() -> void:
	var at := _unit_m()
	assert_eq(ArmyTasks.preview(repo, s, realm, _task("search", at, 3000))["encounter_policy"], "keep_distance")
	assert_true(ArmyTasks.preview(repo, s, realm, _task("search", at, 3000, {"encounter_policy": "approach"}))["ok"])
	assert_eq(ArmyTasks.preview(repo, s, realm, _task("raid", at, 3000))["encounter_policy"], "approach")
	assert_false(ArmyTasks.preview(repo, s, realm, _task("raid", at, 3000, {"encounter_policy": "keep_distance"}))["ok"])


func test_courier_only_beyond_the_kings_range() -> void:
	var at := _unit_m()
	s.king_state["x_m"] = at.x
	s.king_state["y_m"] = at.y
	var near := ArmyTasks.preview(repo, s, realm, _task("search", at, 3000))
	assert_false(near["cost"]["courier"])
	assert_eq(near["cost"]["gold"], int(OrderCosts.gold_of(repo, "ARMY_TASK")), "the row's gold, no courier fee")
	assert_gt(near["cost"]["gold"], 0)
	s.king_state["x_m"] = at.x + int(repo.bal("king_command_radius_m")) + 1
	var far := ArmyTasks.preview(repo, s, realm, _task("search", at, 3000))
	assert_true(far["cost"]["courier"])
	assert_eq(far["cost"]["gold"], near["cost"]["gold"] + CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	assert_eq(far["cells"], TaskCoverage.cells_in_circle(repo, at, 3000).size())
	assert_eq(far["units"][0]["code"], unit)


func test_a_forbidding_law_is_listed_for_a_raid_only() -> void:
	var at := _unit_m()
	var row: Dictionary = s.law_in_force.get(LawSystem.UNIT_PREFIX + unit, {})
	row["plunder"] = {"value": "forbid", "decree_id": 1}
	s.law_in_force[LawSystem.UNIT_PREFIX + unit] = row
	assert_eq(ArmyTasks.preview(repo, s, realm, _task("raid", at, 3000))["law_limits"], [repo.task_words["law_plunder"]])
	assert_eq(ArmyTasks.preview(repo, s, realm, _task("search", at, 3000))["law_limits"], [])
	row["plunder"] = {"value": "allow", "decree_id": 2}
	assert_eq(ArmyTasks.preview(repo, s, realm, _task("raid", at, 3000))["law_limits"], [])


func test_task_preview_does_not_reveal_hidden_state() -> void:
	var hidden := _unknown_town()
	assert_ne(hidden, "", "the pack has a town the crown does not know")
	var at := _town_m(hidden)
	var before := s.to_dict().duplicate(true)
	var a := ArmyTasks.preview(repo, s, realm, _task("search", at, 1500))
	assert_true(a["ok"], str(a))
	assert_false(hidden in a["towns"], "an unknown town is not listed")
	assert_eq(ArmyTasks.preview(repo, s, realm, _task("siege", at, 1500))["reason"], repo.task_words["siege_no_town"])
	assert_eq(s.to_dict(), before, "the preview never mutates the state")
	# the same crown knowledge, a hidden foe now standing inside the circle
	var s2 := SuiteData.campaign(repo, 61)
	var raider := repo.resolve_realm("raider_realm")
	var roster := ArmySystem.roster(repo, s2)
	var codes: Array = roster.keys()
	codes.sort()
	var foe := ""
	for c: String in codes:
		if String(roster[c].get("kingdom_code", "")) == raider and String(roster[c].get("is_naval", "0")) != "1":
			foe = c
			break
	assert_ne(foe, "")
	s2.foes[foe] = ArmySystem.starting_state(repo, ArmySystem.regiment(repo, foe))
	s2.foes[foe]["x_m"] = at.x
	s2.foes[foe]["y_m"] = at.y
	assert_eq(ArmyTasks.preview(repo, s2, realm, _task("search", at, 1500)), a, "a hidden foe changes nothing")
