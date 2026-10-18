extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The march confirm's rows (spec 2026-10-07-march-waypoints ruling 6): one per
## carried load — the arrival day at its pace, the supplies a train of it holds,
## the days they last, and how many days short the column would fall.

var repo: DataRepository


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _marcher() -> Dictionary:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return r
	return {}


func _far(s: GameState, r: Dictionary) -> Vector2:
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	for i in range(80, 3, -1):
		var p := home + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(repo, p) >= 0:
			return p
	return home + Vector2(4, 0)


func test_one_row_a_load_in_the_tables_order() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var rows := MarchPlan.carry_rows(repo, s, code, _far(s, r), [])
	assert_eq(rows.size(), repo.army_carry_loads.size())
	for i in rows.size():
		assert_eq(int(rows[i]["days"]), int(repo.army_carry_loads[i]["days"]))
		assert_eq(String(rows[i]["label"]), String(repo.army_carry_loads[i]["label"]))


## A train of N days holds ceil(use × N / 30) supplies (the in-town top-up's
## own target) and they last days_in_hand of that.
func test_a_loads_supplies_and_their_days_are_the_refills_own_sums() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var use := ArmySystem.supply_use(repo, r, s)
	for row: Dictionary in MarchPlan.carry_rows(repo, s, code, _far(s, r), []):
		var n := int(row["days"])
		@warning_ignore("integer_division")
		var units := (use * n + 29) / 30
		assert_eq(int(row["units"]), units, "%d days" % n)
		assert_eq(int(row["lasts"]), ArmySystem.days_in_hand(units, use))


func test_the_arrival_is_the_ride_and_the_march_at_the_loads_pace() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var to := _far(s, r)
	var rows := MarchPlan.carry_rows(repo, s, code, to, [])
	for row: Dictionary in rows:
		assert_eq(int(row["arrive"]), CourierSystem.arrival_days(repo, s, code, to, Vector2(-1, -1), -1, [],
			int(row["days"])))
		assert_eq(int(row["arrive"]) - int(row["march"]), CourierSystem.eta_days(repo, s, CourierSystem.ORDINARY, code),
			"the ride, then the march")
	assert_gte(int(rows.back()["march"]), int(rows[0]["march"]), "the heaviest train is never the quicker")


func test_local_command_march_rows_do_not_add_a_courier_day() -> void:
	var s := SuiteData.campaign(repo, 8)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var pos := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, r))
	s.king_state["x_m"] = pos.x
	s.king_state["y_m"] = pos.y
	var to := _far(s, r)
	for row: Dictionary in MarchPlan.carry_rows(repo, s, code, to, []):
		assert_eq(int(row["arrive"]), CourierSystem.arrival_days(repo, s, code, to,
			Vector2(-1, -1), 0, [], int(row["days"])))


## In the field the column sets out with what it holds: with nothing it falls
## short by every day of the march. In a town of the realm it is topped up to
## the load first.
func test_short_counts_the_days_the_stores_will_not_cover() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	s.regiments[code]["supplies"] = 0
	var to := _far(s, r)
	var in_town := SupplyLines.home_town(repo, s, code) != ""
	for row: Dictionary in MarchPlan.carry_rows(repo, s, code, to, []):
		if in_town:
			assert_eq(int(row["set_out"]), int(row["lasts"]), "a town tops it up to the load")
		else:
			assert_eq(int(row["set_out"]), 0)
		assert_eq(int(row["short"]), maxi(0, int(row["march"]) - int(row["set_out"])))


func test_a_march_of_several_reads_the_last_arrival_the_trains_together_and_the_worst_shortfall() -> void:
	var a := [{"days": 10, "label": "10 days", "arrive": 9, "march": 7, "units": 100, "lasts": 10, "set_out": 10, "short": 0},
		{"days": 20, "label": "20 days", "arrive": 11, "march": 9, "units": 200, "lasts": 20, "set_out": 20, "short": 0}]
	var b := [{"days": 10, "label": "10 days", "arrive": 12, "march": 10, "units": 50, "lasts": 10, "set_out": 6, "short": 4},
		{"days": 20, "label": "20 days", "arrive": 14, "march": 12, "units": 100, "lasts": 20, "set_out": 6, "short": 6}]
	var g := MarchPlan.group_rows({"r2": b, "r1": a})
	assert_eq(g.size(), 2)
	assert_eq([int(g[0]["days"]), int(g[0]["arrive"]), int(g[0]["units"]), int(g[0]["short"])], [10, 12, 150, 4])
	assert_eq([int(g[1]["arrive"]), int(g[1]["units"]), int(g[1]["short"]), int(g[1]["set_out"])], [14, 300, 6, 6])
	assert_eq(a[0]["arrive"], 9, "the regiments' own rows are left alone")
