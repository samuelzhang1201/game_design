extends GutTest
## Receipts and the steward's report (spec 2026-09-28 §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _fact(m: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in m["facts"]:
		if String(f["key"]) == key:
			return f
	return {}


func test_a_delivery_files_one_credible_receipt_with_the_regiments_state() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(s.missives.size(), 1)
	var m: Dictionary = s.missives[0]
	assert_eq(String(m["kind"]), "receipt")
	assert_eq(String(m["column"]), "credible")
	assert_eq(String(m["subject"]["code"]), code)
	var st := ArmySystem.state_of(repo, s, code)
	assert_eq(int(_fact(m, "morale")["exact"]), int(st["morale"]))
	assert_eq(int(_fact(m, "supplies")["exact"]), int(st["supplies"]))
	assert_eq(String(_fact(m, "orders")["text"]), "Stand")


func test_a_stale_order_writes_a_receipt_that_says_so() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	s.regiments[code]["order_id"] = 99
	var m := MissiveWriter.receipt(repo, s, {"id": 3, "target": code, "order": {"action_code": "ARMY_GARRISON"},
		"x_m": 0, "y_m": 0}, true)
	assert_string_contains(String(_fact(m, "orders")["text"]), "set aside")


func test_every_settled_month_files_one_steward_report_exact_to_the_economy() -> void:
	var s := GameState.new_campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var tick := s.tick
	var expect := 0
	for code: String in MapManors.controlled_provinces(repo, s):
		expect += int(RealmEconomy.province(repo, s, code)["tax"])
	engine.advance(s)
	var reports: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "monthly")
	assert_eq(reports.size(), 1)
	var m: Dictionary = reports[0]
	assert_eq(String(m["column"]), "truth")
	assert_eq(int(_fact(m, "tax_total")["exact"]), expect, "exact against RealmEconomy for the settled month")
	assert_string_contains(String(m["title"]), Calendar.season_name(tick))
