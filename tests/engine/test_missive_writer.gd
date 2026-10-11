extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Receipts and the steward's report (spec 2026-09-28 §1).

var repo: DataRepository


## The pack's road graph is cached by map id and every test's repository
## carries the same routes and road speeds, so it is built once per script
## (and forgotten around it, so no other script's graph is read).
func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
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
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(s.missives.size(), 1)
	var m: Dictionary = s.missives[0]
	assert_eq(String(m["kind"]), "receipt")
	assert_eq(String(m["column"]), "truth", "the crown's own orders received: ground truth (owner 2026-10-10)")
	assert_eq(String(m["subject"]["code"]), code)
	var st := ArmySystem.state_of(repo, s, code)
	assert_eq(int(_fact(m, "morale")["exact"]), int(st["morale"]))
	assert_eq(int(_fact(m, "supplies")["exact"]), int(st["supplies"]))
	assert_eq(String(_fact(m, "orders")["text"]), "Stand")


func test_a_stale_order_writes_a_receipt_that_says_so() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	s.regiments[code]["order_id"] = 99
	var c := {"id": 3, "target": code, "orders": [{"action_code": "ARMY_GARRISON"}], "x_m": 0, "y_m": 0}
	s.couriers.append(c)
	var ev := CourierSystem._deliver(repo, s, c)
	assert_eq(String(ev["type"]), "stale")
	var m: Dictionary = s.missives.back()
	assert_string_contains(String(_fact(m, "orders")["text"]), "set aside")


## The reign's OPENING tick (tick 0, GameRoot's one call to Game.next_tick()
## right after start_campaign, before any day is played) settles no real
## month, so the very first engine.advance() files no report (fix round 1
## finding 3) — the "settled month" this test checks is the one after it.
func test_every_settled_month_files_one_steward_report_exact_to_the_economy() -> void:
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	engine.advance(s)   # the opening tick: no report
	var tick := s.tick
	var expect := 0
	for code: String in MapManors.controlled_provinces(repo, s):
		expect += int(RealmEconomy.province(repo, s, code)["tax"])
	engine.advance(s)
	var reports: Array = s.missives.filter(func(x: Dictionary) -> bool: return String(x["kind"]) == "monthly")
	assert_eq(reports.size(), 1)
	var m: Dictionary = reports[0]
	assert_eq(String(m["column"]), "truth")
	assert_eq(int(_fact(m, "tax_total")["exact"]), expect, "exact against RealmEconomy for the settled month")
	assert_string_contains(String(m["title"]), Calendar.month_label(tick))


## Fix round 1 finding 3: three months of the same season used to share one
## title ("Steward's report — Spring, Year 1"); each now names its own month.
func test_three_months_of_one_season_get_distinct_report_titles() -> void:
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	engine.advance(s)   # the opening tick: no report
	var titles: Dictionary = {}
	for i in 3:
		assert_eq(Calendar.season_name(s.tick), "Spring", "all three months share Spring")
		engine.advance(s)
		var reports: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "monthly")
		titles[String(reports[reports.size() - 1]["title"])] = true
	assert_eq(titles.size(), 3, "three distinct titles: %s" % [titles.keys()])
