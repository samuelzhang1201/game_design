extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM's plans (spec 2026-10-07-war-room-annotations-and-planning-pieces
## §1.1, §2.2): supposed enemy pieces and the staff's strokes — the player's
## paper, saved whole in whole metres, read by no engine rule.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)


func _land() -> Vector2:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return ArmySystem.position_of(repo, state, r)
	return Vector2(-1, -1)


func _sea() -> Vector2:
	for id: int in repo.cells:
		if MapTerrain.is_sea(repo.cells[id]):
			return MapTerrain.cell_center(repo, repo.cells[id])
	return Vector2(-1, -1)


func _foreign() -> String:
	var sides := WarPlans.sides(repo)
	return String(sides[0])


# --- supposed pieces ---------------------------------------------------------

func test_the_sides_are_the_foreign_kingdoms_then_unknown() -> void:
	var sides := WarPlans.sides(repo)
	assert_false(sides.has(repo.resolve_realm("player_realm")), "never the crown's own realm")
	assert_eq(sides.back(), WarPlans.UNKNOWN)
	for k: String in sides.slice(0, sides.size() - 1):
		assert_true(repo.kingdoms.has(k), k)


func test_a_piece_is_placed_in_whole_metres() -> void:
	var at := _land() + Vector2(3, 2)
	var id := WarPlans.place(repo, state, "cavalry", 2000, _foreign(), at, 90)
	assert_eq(id, "p1")
	var p: Dictionary = state.war_plans["pieces"][id]
	assert_eq(String(p["arm"]), "cavalry")
	assert_eq(int(p["heads"]), 2000)
	assert_eq(String(p["side"]), _foreign())
	assert_true(p["x_m"] is int and p["y_m"] is int and p["facing_deg"] is int)
	assert_almost_eq(WarPlans.at_px(repo, p).distance_to(at), 0.0, 0.01)


func test_heads_are_clamped_and_stepped() -> void:
	assert_eq(WarPlans.heads_of(repo, 37), 100)
	assert_eq(WarPlans.heads_of(repo, 25000), 20000)
	assert_eq(WarPlans.heads_of(repo, 1249), 1200)
	assert_eq(WarPlans.heads_of(repo, 1260), 1300)


func test_refusals() -> void:
	assert_eq(WarPlans.refusal(repo, state, "infantry", 1000, _foreign(), _sea()), "A supposed host stands on land")
	assert_ne(WarPlans.refusal(repo, state, "fleet", 1000, _foreign(), _land()), "", "no supposed fleet")
	assert_ne(WarPlans.refusal(repo, state, "infantry", 1000, "nowhere", _land()), "", "an unknown side")
	assert_ne(WarPlans.refusal(repo, state, "infantry", 1000, repo.resolve_realm("player_realm"), _land()), "",
		"never the crown's own realm")
	assert_eq(WarPlans.refusal(repo, state, "infantry", 1000, WarPlans.UNKNOWN, _land()), "")
	assert_eq(WarPlans.place(repo, state, "infantry", 1000, _foreign(), _sea()), "", "a refusal places nothing")
	assert_true((state.war_plans["pieces"] as Dictionary).is_empty())


func test_the_cap_holds() -> void:
	repo.balance["war_plan_pieces_max"] = 2
	WarPlans.place(repo, state, "infantry", 1000, _foreign(), _land())
	WarPlans.place(repo, state, "archers", 1000, _foreign(), _land())
	assert_ne(WarPlans.refusal(repo, state, "infantry", 1000, _foreign(), _land()), "")
	assert_eq(WarPlans.place(repo, state, "infantry", 1000, _foreign(), _land()), "")


func test_move_edit_and_remove_each_raise_the_revision() -> void:
	var id := WarPlans.place(repo, state, "infantry", 1000, _foreign(), _land())
	var rev := int(state.war_plans["rev"])
	assert_true(WarPlans.move_piece(repo, state, id, _land() + Vector2(5, 0), 180))
	assert_gt(int(state.war_plans["rev"]), rev)
	assert_almost_eq(WarPlans.at_px(repo, state.war_plans["pieces"][id]).distance_to(_land() + Vector2(5, 0)), 0.0, 0.01)
	assert_eq(int(state.war_plans["pieces"][id]["facing_deg"]), 180)
	assert_false(WarPlans.move_piece(repo, state, id, _sea(), 0), "never onto the sea")
	rev = int(state.war_plans["rev"])
	assert_true(WarPlans.edit_piece(repo, state, id, "archers", 3050, WarPlans.UNKNOWN))
	assert_gt(int(state.war_plans["rev"]), rev)
	assert_eq(String(state.war_plans["pieces"][id]["arm"]), "archers")
	assert_eq(int(state.war_plans["pieces"][id]["heads"]), 3100)
	assert_true(WarPlans.remove(state, id))
	assert_false(WarPlans.remove(state, id))


func test_the_default_side() -> void:
	var at := _land()
	assert_eq(WarPlans.default_side(repo, state, at, ""), WarPlans.UNKNOWN, "our own ground: no holder to take")
	assert_eq(WarPlans.default_side(repo, state, at, _foreign()), _foreign(), "else the last side chosen")


func test_clear_takes_only_what_lies_in_the_rect() -> void:
	var a := WarPlans.place(repo, state, "infantry", 1000, _foreign(), _land())
	var far := Vector2(-1, -1)
	for id: int in repo.cells:
		var c: Dictionary = repo.cells[id]
		if not MapTerrain.is_water(c) and MapTerrain.cell_center(repo, c).distance_to(_land()) > 200.0:
			far = MapTerrain.cell_center(repo, c)
			break
	var b := WarPlans.place(repo, state, "infantry", 1000, _foreign(), far)
	var rect := Rect2(_land() - Vector2(50, 50), Vector2(100, 100))
	assert_eq(WarPlans.pieces_in(repo, state, rect).map(func(p: Dictionary) -> String: return String(p["id"])), [a])
	assert_eq(WarPlans.clear(repo, state, "pieces", rect), 1)
	assert_false((state.war_plans["pieces"] as Dictionary).has(a))
	assert_true((state.war_plans["pieces"] as Dictionary).has(b))


# --- strokes ----------------------------------------------------------------

func _path() -> PackedVector2Array:
	var o := _land()
	return PackedVector2Array([o, o + Vector2(10, 4), o + Vector2(25, 2)])


func test_a_stroke_is_drawn_in_whole_metres() -> void:
	var id := WarPlans.draw(repo, state, "arrow", "blue", _path(), 0.0, "")
	assert_eq(id, "s1")
	var s: Dictionary = state.war_plans["strokes"][id]
	assert_eq(String(s["kind"]), "arrow")
	assert_eq(String(s["colour"]), "blue")
	assert_eq((s["pts"] as Array).size(), 3)
	assert_true(s["pts"][1][0] is int)
	var pts := WarPlans.points_px(repo, s)
	for i in 3:
		assert_almost_eq(pts[i].distance_to(_path()[i]), 0.0, 0.01)


func test_stroke_refusals() -> void:
	assert_ne(WarPlans.stroke_refusal(repo, state, "doodle", "blue", _path(), 0.0, ""), "", "an unknown kind")
	assert_ne(WarPlans.stroke_refusal(repo, state, "arrow", "green", _path(), 0.0, ""), "", "an unknown colour")
	assert_ne(WarPlans.stroke_refusal(repo, state, "arrow", "blue", PackedVector2Array([_land()]), 0.0, ""), "",
		"a path needs two points")
	var many := PackedVector2Array()
	for i in int(repo.bal("war_plan_points_max")) + 1:
		many.append(_land() + Vector2(i, 0))
	assert_ne(WarPlans.stroke_refusal(repo, state, "arrow", "blue", many, 0.0, ""), "", "too many points")
	assert_ne(WarPlans.stroke_refusal(repo, state, "objective", "ink", PackedVector2Array([_land()]), 0.0, ""), "",
		"a ring needs a radius")
	assert_eq(WarPlans.stroke_refusal(repo, state, "objective", "ink", PackedVector2Array([_land()]), 4.0, "Obj. A"), "")
	assert_ne(WarPlans.stroke_refusal(repo, state, "phase", "ink", _path(), 0.0, "x".repeat(25)), "", "a name too long")
	repo.balance["war_plan_strokes_max"] = 1
	WarPlans.draw(repo, state, "arrow", "blue", _path(), 0.0, "")
	assert_ne(WarPlans.stroke_refusal(repo, state, "arrow", "blue", _path(), 0.0, ""), "", "the cap")


func test_default_names_count_on() -> void:
	assert_eq(WarPlans.next_name(repo, state, "phase"), "Line I")
	WarPlans.draw(repo, state, "phase", "ink", _path(), 0.0, WarPlans.next_name(repo, state, "phase"))
	assert_eq(WarPlans.next_name(repo, state, "phase"), "Line II")
	assert_eq(WarPlans.next_name(repo, state, "objective"), "Obj. A")
	WarPlans.draw(repo, state, "objective", "ink", PackedVector2Array([_land()]), 4.0, "Obj. A")
	assert_eq(WarPlans.next_name(repo, state, "objective"), "Obj. B")
	assert_eq(WarPlans.next_name(repo, state, "arrow"), "", "an arrow has no default name")


func test_reshape_shift_and_restyle() -> void:
	var id := WarPlans.draw(repo, state, "front", "red", _path(), 0.0, "")
	var moved := _path()
	moved[1] += Vector2(0, 6)
	assert_true(WarPlans.reshape(repo, state, id, moved))
	assert_almost_eq(WarPlans.points_px(repo, state.war_plans["strokes"][id])[1].distance_to(moved[1]), 0.0, 0.01)
	assert_true(WarPlans.shift(repo, state, id, Vector2(10, 0)))
	assert_almost_eq(WarPlans.points_px(repo, state.war_plans["strokes"][id])[0].distance_to(_path()[0] + Vector2(10, 0)), 0.0, 0.01)
	assert_true(WarPlans.restyle(repo, state, id, {"colour": "blue", "dashed": 1, "flip": 1, "name": "Brackwood"}))
	var s: Dictionary = state.war_plans["strokes"][id]
	assert_eq([String(s["colour"]), int(s["dashed"]), int(s["flip"]), String(s["name"])], ["blue", 1, 1, "Brackwood"])
	assert_false(WarPlans.restyle(repo, state, id, {"colour": "green"}), "an unknown colour")


func test_strokes_in_reads_bounds_so_a_crossing_stroke_shows_on_both_rects() -> void:
	var o := _land()
	var id := WarPlans.draw(repo, state, "arrow", "blue", PackedVector2Array([o, o + Vector2(100, 0)]), 0.0, "")
	var left := Rect2(o - Vector2(10, 10), Vector2(50, 20))
	var right := Rect2(o + Vector2(60, -10), Vector2(50, 20))
	var away := Rect2(o + Vector2(0, 100), Vector2(50, 20))
	assert_eq(WarPlans.strokes_in(repo, state, left).size(), 1)
	assert_eq(WarPlans.strokes_in(repo, state, right).size(), 1)
	assert_eq(WarPlans.strokes_in(repo, state, away).size(), 0)
	assert_eq(String(WarPlans.strokes_in(repo, state, left)[0]["id"]), id)
	var ring := WarPlans.draw(repo, state, "objective", "ink", PackedVector2Array([o + Vector2(0, 130)]), 40.0, "Obj. A")
	assert_eq(WarPlans.strokes_in(repo, state, away).map(func(s: Dictionary) -> String: return String(s["id"])), [ring],
		"a ring is found by its rim")


# --- the save ---------------------------------------------------------------

func test_plans_survive_the_json_save_whole() -> void:
	WarPlans.place(repo, state, "infantry", 1500, _foreign(), _land(), 45)
	WarPlans.draw(repo, state, "phase", "ink", _path(), 0.0, "i5")   # a name shaped like the save's int code
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(back.war_plans, state.war_plans)
	assert_eq(String(back.war_plans["strokes"]["s2"]["name"]), "i5")
	assert_true(back.war_plans["pieces"]["p1"]["x_m"] is int)


func test_an_old_save_loads_with_no_plans() -> void:
	var d := state.to_dict()
	d.erase("war_plans")
	var back := GameState.from_dict(d)
	assert_eq((back.war_plans["pieces"] as Dictionary).size(), 0)
	assert_eq((back.war_plans["strokes"] as Dictionary).size(), 0)
	assert_eq(WarPlans.place(repo, back, "infantry", 1000, _foreign(), _land()), "p1")


func test_restore_puts_a_snapshot_back() -> void:
	var before: Dictionary = state.war_plans.duplicate(true)
	WarPlans.place(repo, state, "infantry", 1000, _foreign(), _land())
	WarPlans.restore(state, before)
	assert_eq((state.war_plans["pieces"] as Dictionary).size(), 0)
	assert_gt(int(state.war_plans["rev"]), int(before["rev"]), "a restore is a change the caches must see")


func test_no_engine_rule_reads_the_plans() -> void:
	var a := SuiteData.campaign(repo, 42)
	var b := SuiteData.campaign(repo, 42)
	WarPlans.place(repo, b, "cavalry", 5000, _foreign(), _land())
	WarPlans.draw(repo, b, "arrow", "red", _path(), 0.0, "")
	var engine_a := TickEngine.new(repo)
	var engine_b := TickEngine.new(repo)
	for i in 3:
		engine_a.advance(a)
		engine_b.advance(b)
	var da := a.to_dict()
	var db := b.to_dict()
	da.erase("war_plans")
	db.erase("war_plans")
	assert_eq(JSON.stringify(da), JSON.stringify(db))
