extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A march stays its blue crayon arrow after Confirm (owner 2026-10-08, spec
## 2026-10-08-war-room-draw-orders rulings 10, 19): columns on one drawn path
## are one arrow — the lead with its head, the others feeders — else each its
## own; drafts and sealed marches never share an arrow.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _row(code: String, kind: String, dest: Vector2, wps: Array) -> Dictionary:
	return {"code": code, "kind": kind, "dest": dest, "wps": wps}


func test_columns_on_one_drawn_path_are_one_arrow_led_by_the_most_bends() -> void:
	var end := Vector2(300, 100)
	var path := [Vector2(100, 100), Vector2(200, 150)]
	var arrows := WarOrderArrows.group([
		_row("b", WarOrderArrows.DRAFT, end, [Vector2(200, 150)]),   # joined at the second bend
		_row("a", WarOrderArrows.DRAFT, end, path),                   # the whole path
		_row("c", WarOrderArrows.DRAFT, end, []),                     # straight to the end
	])
	assert_eq(arrows.size(), 1, "one arrow")
	assert_eq(String(arrows[0]["lead"]), "a", "the most bends lead (the head is its)")
	assert_eq(arrows[0]["members"], ["a", "b", "c"], "the others feed it, fewer bends after")
	assert_eq(arrows[0]["dest"], end)


func test_another_path_or_another_end_or_kind_is_its_own_arrow() -> void:
	var end := Vector2(300, 100)
	var arrows := WarOrderArrows.group([
		_row("a", WarOrderArrows.DRAFT, end, [Vector2(100, 100), Vector2(200, 150)]),
		_row("b", WarOrderArrows.DRAFT, end, [Vector2(150, 40)]),            # a bend not on a's path
		_row("c", WarOrderArrows.DRAFT, Vector2(300, 101), []),              # another end
		_row("d", WarOrderArrows.SEALED, end, [Vector2(200, 150)]),          # sealed: never with a draft
	])
	var leads: Array = arrows.map(func(g: Dictionary) -> String: return String(g["lead"]))
	leads.sort()
	assert_eq(leads, ["a", "b", "c", "d"], "four arrows, each with its own head")


func test_a_tie_in_bends_leads_by_code_and_the_order_is_stable() -> void:
	var end := Vector2(50, 50)
	var rows := [_row("z", WarOrderArrows.SEALED, end, []), _row("m", WarOrderArrows.SEALED, end, [])]
	assert_eq(WarOrderArrows.group(rows)[0]["members"], ["m", "z"])
	rows.reverse()
	assert_eq(WarOrderArrows.group(rows)[0]["members"], ["m", "z"], "the rows' order does not matter")


func test_the_lead_is_an_arrow_with_a_head_and_a_feeder_a_band() -> void:
	var ink := {"crayon": [], "pen": [], "names": []}
	var lead := PackedVector2Array([Vector2(0, 0), Vector2(200, 0)])
	WarOrderArrows.add(repo, ink, [lead], "blue", 0.0, 2.0)
	var alone := (ink["crayon"] as Array).size()
	assert_eq(alone, 2, "a band and its barbed head")
	WarOrderArrows.add(repo, ink, [PackedVector2Array(), PackedVector2Array([Vector2(0, 40), Vector2(150, 0)])],
		"blue_draft", 0.0, 2.0)
	assert_eq((ink["crayon"] as Array).size(), alone + 1, "a lead off the screen draws nothing; the feeder one band, no head")
	assert_eq(String(ink["crayon"][alone]["colour"]), "blue_draft")
	var cut := {"crayon": [], "pen": [], "names": []}
	WarOrderArrows.add(repo, cut, [PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])], "blue", 12.0, 2.0)
	assert_true((cut["crayon"] as Array).is_empty(), "a line shorter than the plinth's edge leaves no crayon")


func test_the_arrow_is_one_outline_overlaps_merged_apart_kept() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var b := PackedVector2Array([Vector2(5, 5), Vector2(15, 5), Vector2(15, 15), Vector2(5, 15)])
	var far := PackedVector2Array([Vector2(50, 50), Vector2(60, 50), Vector2(60, 60), Vector2(50, 60)])
	var u := WarOrderArrows.union([a, far, b], 0.0)
	assert_eq(u.size(), 2, "the two overlapping squares are one, the far one its own")
	var area := 0.0
	for poly: PackedVector2Array in u:
		for i in poly.size():
			area += poly[i].cross(poly[(i + 1) % poly.size()]) * 0.5
	assert_almost_eq(absf(area), 100.0 + 100.0 + 100.0 - 25.0, 0.01, "175 merged + 100 apart")
	var ink := {"crayon": [], "pen": [], "names": []}
	WarOrderArrows.add(repo, ink, [PackedVector2Array([Vector2(0, 0), Vector2(200, 0)]),
		PackedVector2Array([Vector2(60, 40), Vector2(120, 0)])], "blue", 0.0, 2.0)
	assert_eq((ink["crayon"] as Array).size(), 2, "a feeder joining the lead's band is the band's own outline")
	assert_eq(WarOrderArrows.union([a, PackedVector2Array([Vector2(10, 0), Vector2(20, 0), Vector2(20, 10), Vector2(10, 10)])]).size(),
		1, "squares touching at an edge close up at the half-px seam")
