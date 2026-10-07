extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The staff's strokes inked onto a sheet's plan layer (spec 2026-10-07-war-
## room-annotations-and-planning-pieces §2.5): in that sheet's texture px, a
## crossing stroke on both sheets, widths from table millimetres, crayon and
## pen apart, names where they belong.

var repo: DataRepository
var state: GameState
var sheet: Dictionary
const TEX := 1400   # 1 texture px per table mm on a 1.4 m table


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()
	sheet = WarSheets.series(repo)[0]


func _mid() -> Vector2:
	var r: Rect2 = sheet["rect"]
	return r.get_center()


func _k() -> float:
	return float(TEX) / (sheet["rect"] as Rect2).size.x


func test_nothing_drawn_draws_nothing() -> void:
	var ink := WarPlanInk.strokes(repo, state, sheet, TEX, 1.4)
	assert_eq((ink["crayon"] as Array).size() + (ink["pen"] as Array).size() + (ink["names"] as Array).size(), 0)


func test_an_arrow_is_crayon_in_this_sheets_px_widths_in_mm() -> void:
	var r: Rect2 = sheet["rect"]
	var a := _mid() - Vector2(r.size.x * 0.2, 0)
	var b := _mid() + Vector2(r.size.x * 0.2, 0)
	WarPlans.draw(repo, state, "arrow", "blue", PackedVector2Array([a, b]), 0.0, "")
	var ink := WarPlanInk.strokes(repo, state, sheet, TEX, 1.4)
	assert_eq((ink["pen"] as Array).size(), 0)
	var polys: Array = ink["crayon"]
	assert_eq(polys.size(), 2, "the band and the head")
	assert_eq(String(polys[0]["colour"]), "blue")
	var head: PackedVector2Array = polys[1]["poly"]
	var tip := (b - r.position) * _k()
	var best := INF
	for p in head:
		best = minf(best, p.distance_to(tip))
	assert_almost_eq(best, 0.0, 0.01, "the tip in texture px")
	var ys: Array = Array(head).map(func(p: Vector2) -> float: return p.y)
	assert_almost_eq(float(ys.max()) - float(ys.min()), repo.bal("war_plan_arrow_head_w_mm"), 0.01,
		"1 px a mm: the head is war_plan_arrow_head_w_mm across")


func test_a_front_has_its_line_and_its_teeth_and_flips() -> void:
	var r: Rect2 = sheet["rect"]
	var a := _mid()
	var b := _mid() + Vector2(r.size.x * 0.1, 0)
	var id := WarPlans.draw(repo, state, "front", "red", PackedVector2Array([a, b]), 0.0, "")
	var ink := WarPlanInk.strokes(repo, state, sheet, TEX, 1.4)
	var pts := WarPlans.points_px(repo, state.war_plans["strokes"][id])   # as stored: whole metres
	var length_mm := pts[0].distance_to(pts[1]) * _k()
	var teeth := int(floor(length_mm / repo.bal("war_plan_tooth_every_mm")))
	assert_eq((ink["crayon"] as Array).size(), 1 + teeth)
	var apex_y: float = (ink["crayon"][1]["poly"] as PackedVector2Array)[1].y
	WarPlans.restyle(repo, state, id, {"flip": 1})
	var flipped := WarPlanInk.strokes(repo, state, sheet, TEX, 1.4)
	var line_y := (a - r.position).y * _k()
	assert_almost_eq(signf(apex_y - line_y), -signf((flipped["crayon"][1]["poly"] as PackedVector2Array)[1].y - line_y), 0.001)


func test_a_phase_line_is_pen_named_at_both_ends_and_an_objective_once() -> void:
	var r: Rect2 = sheet["rect"]
	WarPlans.draw(repo, state, "phase", "ink", PackedVector2Array([_mid(), _mid() + Vector2(0, r.size.y * 0.2)]), 0.0, "Line I")
	WarPlans.draw(repo, state, "objective", "ink", PackedVector2Array([_mid()]), r.size.x * 0.03, "Obj. A")
	var ink := WarPlanInk.strokes(repo, state, sheet, TEX, 1.4)
	assert_eq((ink["crayon"] as Array).size(), 0, "pen kinds are not crayon")
	assert_gt((ink["pen"] as Array).size(), 2, "the phase line's dashes and the ring's two rims")
	var names: Array = ink["names"].map(func(n: Dictionary) -> String: return String(n["text"]))
	names.sort()
	assert_eq(names, ["Line I", "Line I", "Obj. A"])


func test_a_crossing_stroke_shows_on_both_sheets() -> void:
	var all: Array = WarSheets.series(repo)
	var other := {}
	for s: Dictionary in all:
		if (s["rect"] as Rect2).position.y == (sheet["rect"] as Rect2).position.y and s != sheet:
			other = s
			break
	assert_false(other.is_empty(), "a neighbour on the same row")
	var a := (sheet["rect"] as Rect2).get_center()
	var b := (other["rect"] as Rect2).get_center()
	WarPlans.draw(repo, state, "arrow", "red", PackedVector2Array([a, b]), 0.0, "")
	assert_eq((WarPlanInk.strokes(repo, state, sheet, TEX, 1.4)["crayon"] as Array).size(), 2)
	assert_eq((WarPlanInk.strokes(repo, state, other, TEX, 1.4)["crayon"] as Array).size(), 2)


func test_the_key_turns_with_the_plans_and_the_sheet() -> void:
	var k0 := WarPlanInk.cache_key(state, 0)
	WarPlans.draw(repo, state, "arrow", "red", PackedVector2Array([_mid(), _mid() + Vector2(5, 0)]), 0.0, "")
	assert_ne(WarPlanInk.cache_key(state, 0), k0)
	assert_ne(WarPlanInk.cache_key(state, 0), WarPlanInk.cache_key(state, 1))
