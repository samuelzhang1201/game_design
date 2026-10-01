# tests/engine/test_war_room.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## What the plotting table draws (spec 2026-10-01-war-room-design §3).

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func _land_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			return String(r["regiment_code"])
	return ""


func test_the_table_believes_the_truth_until_intel_p2() -> void:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		assert_eq(WarRoom.believed_position(repo, state, r), ArmySystem.position_of(repo, state, r))
	assert_eq(WarRoom.believed_hosts(repo, state), [], "no enemy is on the table before P2")


func test_every_crown_regiment_is_a_piece_on_exactly_one_side_of_each_sheet() -> void:
	var all := WarRoom.pieces(repo, state)
	assert_eq(all.size(), MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).size())
	for s: Dictionary in WarSheets.series(repo):
		var on := WarRoom.on_sheet(repo, state, int(s["index"]))
		var off := WarRoom.off_sheet(repo, state, int(s["index"]))
		assert_eq(on.size() + off.size(), all.size())
		var split := WarRoom.partition(repo, state, int(s["index"]))
		assert_eq(split["on"].size(), on.size())
		assert_eq(split["off"].size(), off.size())
	for p: Dictionary in all:
		var codes := WarRoom.on_sheet(repo, state, int(p["sheet"])).map(
			func(q: Dictionary) -> String: return String(q["code"]))
		assert_true(String(p["code"]) in codes, "%s is on its own sheet" % p["code"])


func test_a_piece_on_no_sheet_goes_to_the_nearest() -> void:
	var code := _land_code()
	ArmySystem.ensure(repo, state)
	var far := ArmySystem.pack_to_metres(repo, Vector2(-4000.0, -4000.0))
	state.regiments[code]["x_m"] = far.x
	state.regiments[code]["y_m"] = far.y
	var nearest := WarSheets.sheet_of(repo, Vector2(-4000.0, -4000.0))
	var codes := WarRoom.on_sheet(repo, state, nearest).map(func(p: Dictionary) -> String: return String(p["code"]))
	assert_true(code in codes)


func test_the_pose_follows_the_order() -> void:
	assert_eq(WarRoom.pose_action(ArmySystem.ORDER_MARCH), "MARCH")
	assert_eq(WarRoom.pose_action(ArmySystem.ORDER_GARRISON), "GARRISON")
	assert_eq(WarRoom.pose_action(ArmySystem.ORDER_STANDBY), "STANDBY")
	assert_eq(WarRoom.pose_action("anything else"), "STANDBY")


func test_no_order_no_pennant_then_riding_then_received() -> void:
	var code := _land_code()
	assert_eq(WarRoom.pennant_of(repo, state, code), {})
	var here := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var to := here + Vector2(20.0, 0.0)
	var dest_m := ArmySystem.pack_to_metres(repo, to)
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": dest_m.x, "dest_y_m": dest_m.y})
	var p := WarRoom.pennant_of(repo, state, code)
	assert_eq(String(p["status"]), "riding")
	assert_almost_eq((p["at"] as Vector2).x, to.x, 0.01)
	state.couriers.clear()
	ArmySystem.set_march(repo, state, code, to)
	p = WarRoom.pennant_of(repo, state, code)
	assert_eq(String(p["status"]), "received")
	assert_almost_eq((p["at"] as Vector2).x, to.x, 0.01)


func test_a_newer_garrison_courier_countermands_a_riding_march_and_a_received_one() -> void:
	var code := _land_code()
	var here := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var to := here + Vector2(20.0, 0.0)
	var dest_m := ArmySystem.pack_to_metres(repo, to)
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": dest_m.x, "dest_y_m": dest_m.y})
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	var p := WarRoom.pennant_of(repo, state, code)
	assert_eq(String(p["status"]), "countermanded", "the older march still rides under a newer garrison, countermanded")
	assert_almost_eq((p["at"] as Vector2).x, to.x, 0.01, "the pennant stays where the march was bound")
	state.couriers.clear()
	ArmySystem.set_march(repo, state, code, to)
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	p = WarRoom.pennant_of(repo, state, code)
	assert_eq(String(p["status"]), "countermanded", "a received march under a garrison courier is countermanded too")
	assert_almost_eq((p["at"] as Vector2).x, to.x, 0.01)


func test_a_march_older_than_a_delivered_order_plants_no_pennant() -> void:
	var code := _land_code()
	var here := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var dest_m := ArmySystem.pack_to_metres(repo, here + Vector2(20.0, 0.0))
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": dest_m.x, "dest_y_m": dest_m.y})
	state.regiments[code]["order_id"] = int(state.next_courier_id) + 1   # a newer order already arrived
	assert_eq(WarRoom.pennant_of(repo, state, code), {}, "set aside: it will plant nothing")


func test_a_garrison_courier_alone_strikes_no_pennant() -> void:
	var code := _land_code()
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	assert_eq(WarRoom.pennant_of(repo, state, code), {})


func test_the_tag_reads_heads_and_months_of_stores() -> void:
	var code := _land_code()
	var reg := ArmySystem.regiment(repo, code)
	var st := ArmySystem.state_of(repo, state, code)
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")
	var months := int(st["supplies"]) / use
	assert_eq(WarRoom.tag_text(repo, state, code),
		"%s · stores %d mo" % [WarRoom.group(ArmySystem.headcount(repo, reg)), months])


func test_grouping() -> void:
	assert_eq(WarRoom.group(0), "0")
	assert_eq(WarRoom.group(999), "999")
	assert_eq(WarRoom.group(6448), "6,448")
	assert_eq(WarRoom.group(1234567), "1,234,567")
	assert_eq(WarRoom.group(-6448), "-6,448")


func test_a_riding_pennant_carries_the_day_its_courier_left() -> void:
	var code := _land_code()
	var here := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var dest_m := ArmySystem.pack_to_metres(repo, here + Vector2(20.0, 0.0))
	var c := CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": dest_m.x, "dest_y_m": dest_m.y})
	assert_eq(int(WarRoom.pennant_of(repo, state, code)["issued"]), int(c["issued"]))
	var h := CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	assert_eq(int(WarRoom.pennant_of(repo, state, code)["issued"]), int(h["issued"]), "a countermand is dated by its own courier")
