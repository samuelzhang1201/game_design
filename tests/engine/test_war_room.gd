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
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			return String(r["regiment_code"])
	return ""


## A land regiment on the march: the map draws it where it walks.
func _marching_code() -> String:
	var code := _land_code()
	ArmySystem.ensure(repo, state)
	var reg := ArmySystem.regiment(repo, code)
	ArmySystem.set_march(repo, state, code, ArmySystem.position_of(repo, state, reg) + Vector2(40.0, 0.0))
	return code


func test_the_table_believes_the_truth_until_intel_p2() -> void:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		assert_eq(WarRoom.believed_position(repo, state, r), ArmySystem.position_of(repo, state, r))
	assert_eq(WarRoom.believed_hosts(repo, state), [], "no enemy is on the table before P2")


func test_every_crown_regiment_is_a_piece_on_exactly_one_side_of_each_sheet() -> void:
	var all := WarRoom.pieces(repo, state)
	var seen: Dictionary = {}
	for p: Dictionary in all:
		assert_false(p.has("garrison"), "no piece stands for a garrison")
		assert_false(seen.has(String(p["code"])), "%s is one piece" % p["code"])
		seen[String(p["code"])] = true
	assert_eq(seen.size(), MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state).size(),
		"every unit is its own piece")
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
	var code := _marching_code()   # no town's garrison: its own tag, not its camp's
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


func test_a_regiment_in_a_sheets_collar_is_on_that_sheet_and_off_no_other_twice() -> void:
	var code := _land_code()
	var collar := repo.bal("war_sheet_collar_km") * 0.5 * WarSheets.px_per_unit(repo)
	var sheet := -1
	var pt := Vector2.ZERO
	for s: Dictionary in WarSheets.series(repo):
		var p: Vector2 = (s["cell"] as Rect2).position + Vector2(-collar, (s["cell"] as Rect2).size.y * 0.5)
		if p.x > 0.0:
			sheet = int(s["index"])
			pt = p
			break
	assert_gte(sheet, 0)
	var m := ArmySystem.pack_to_metres(repo, pt)
	state.regiments[code]["x_m"] = m.x
	state.regiments[code]["y_m"] = m.y
	var on: Array = WarRoom.on_sheet(repo, state, sheet).map(func(p: Dictionary) -> String: return String(p["code"]))
	assert_true(code in on, "drawn on the sheet whose collar holds it")
	var home := WarSheets.sheet_of(repo, pt)
	var off: Array = WarRoom.off_sheet(repo, state, home).map(func(p: Dictionary) -> String: return String(p["code"]))
	assert_false(code in off, "never listed as off its own home sheet")



## Owner 2026-10-02: war room的军队单位位置一定要和大地图一致 — a spot the 3D map
## draws wins over the engine's; a regiment it does not name keeps the engine's.
func test_a_drawn_spot_is_where_the_piece_stands() -> void:
	var code := _marching_code()
	var reg := ArmySystem.regiment(repo, code)
	var engine := ArmySystem.position_of(repo, state, reg)
	var drawn := {code: engine + Vector2(3.0, 2.0)}
	assert_eq(WarRoom.believed_position(repo, state, reg, drawn), engine + Vector2(3.0, 2.0))
	assert_eq(WarRoom.believed_position(repo, state, reg, {"someone_else": Vector2.ZERO}), engine)
	for p: Dictionary in WarRoom.pieces(repo, state, drawn):
		if String(p["code"]) == code:
			assert_eq(p["at"], engine + Vector2(3.0, 2.0))
			assert_eq(int(p["sheet"]), WarSheets.sheet_of(repo, engine + Vector2(3.0, 2.0)))


## A drawn spot on another sheet moves the piece to that sheet's side.
func test_the_sheets_split_by_the_drawn_spot() -> void:
	var code := _marching_code()
	var reg := ArmySystem.regiment(repo, code)
	var home := WarSheets.sheet_of(repo, ArmySystem.position_of(repo, state, reg))
	var far := Vector2.ZERO
	for s: Dictionary in WarSheets.series(repo):
		if not (s["rect"] as Rect2).intersects(WarSheets.series(repo)[home]["rect"]):
			far = (s["cell"] as Rect2).get_center()
			break
	var drawn := {code: far}
	var on: Array = WarRoom.on_sheet(repo, state, home, drawn).map(func(p: Dictionary) -> String: return String(p["code"]))
	assert_false(code in on, "drawn far away, it is off its old sheet")
	var there: Array = WarRoom.on_sheet(repo, state, WarSheets.sheet_of(repo, far), drawn).map(
		func(p: Dictionary) -> String: return String(p["code"]))
	assert_true(code in there, "and on the sheet the map draws it on")


## Every unit holds its own ground (spec 2026-10-07-army-split-and-ground §5.4):
## the units round the capital are each their own piece, the seat's on the
## town's point, every tag one unit's own.
func test_every_unit_round_a_town_is_its_own_piece() -> void:
	var realm := repo.resolve_realm("player_realm")
	var capital := String(repo.kingdoms[realm]["capital_burg"])
	var b: Dictionary = repo.burgs[capital]
	var seat := ArmyGround.seat_of(repo, state, capital)
	assert_ne(seat, "", "the capital's seat is held")
	var around: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, realm, state):
		if ArmyGround.camped_by(repo, state, String(r["regiment_code"])) == capital:
			around.append(String(r["regiment_code"]))
	assert_gt(around.size(), 1, "more than one unit stands round the capital")
	var pieces: Dictionary = {}
	for p: Dictionary in WarRoom.pieces(repo, state):
		pieces[String(p["code"])] = p
	for c: String in around:
		assert_true(pieces.has(c), "%s has its own piece" % c)
		var reg := ArmySystem.regiment(repo, c, state)
		assert_eq(pieces[c]["at"], WarRoom.believed_position(repo, state, reg), "%s where it stands" % c)
		assert_false(WarRoom.tag_text(repo, state, c).contains("regiments"), "%s's tag is its own" % c)
	assert_eq(pieces[seat]["at"], Vector2(float(b["x"]), float(b["y"])), "the seat on the town's point")


# --- intel hints (spec 2026-10-08-war-room-draw-orders ruling 18) ------------

func _spy_report(at: Vector2, lo: int, hi: int, day: int) -> int:
	var facts: Array = [MissiveLog.span("troops_own", "Our men", 0, 0), MissiveLog.span("troops_foreign", "Foreign men", lo, hi)]
	return MissiveLog.add(repo, state, MissiveLog.make("spy", "credible", day, MissiveLog.subject("point", "", -1, at),
		"Spy report — somewhere", facts))


func test_a_spy_report_of_foreign_men_is_a_hint_where_it_saw_them() -> void:
	assert_eq(WarRoom.intel_hints(repo, state), [], "no report, no hint")
	var id := _spy_report(Vector2(400, 300), 800, 1200, 50)
	_spy_report(Vector2(500, 300), 0, 0, 51)   # nobody there: no hint
	var hints := WarRoom.intel_hints(repo, state)
	assert_eq(hints.size(), 1)
	var h: Dictionary = hints[0]
	assert_eq(String(h["id"]), "h%d" % id)
	assert_eq(h["at"], Vector2(400, 300))
	assert_eq([int(h["lo"]), int(h["hi"]), int(h["day"])], [800, 1200, 50])
	var newer := _spy_report(Vector2(400, 300), 0, 100, 60)
	hints = WarRoom.intel_hints(repo, state)
	assert_eq(hints.size(), 1, "the newest report about a place stands for it")
	assert_eq(String(hints[0]["id"]), "h%d" % newer)
	assert_eq(WarRoom.hint_of(repo, state, "h%d" % newer)["at"], Vector2(400, 300))
	assert_eq(WarRoom.hint_of(repo, state, "h999"), {})


func test_a_report_below_the_threshold_hints_nothing() -> void:
	repo.balance["war_intel_hint_min_heads"] = 500
	_spy_report(Vector2(400, 300), 100, 400, 50)
	assert_eq(WarRoom.intel_hints(repo, state), [])
