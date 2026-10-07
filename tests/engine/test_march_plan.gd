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
