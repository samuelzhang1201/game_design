extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The staff's tools (spec 2026-10-07-war-room-annotations-and-planning-pieces
## §2.4, rulings 15-17): the stick in hand, a drag drawn and smoothed, a ring
## by compass, a short drag nothing, picking a stroke or its handle, undo.

var repo: DataRepository
var tool: WarPlanTool


func before_each() -> void:
	repo = SuiteData.repo()
	tool = WarPlanTool.new(repo)


func _drag(points: Array, shift := false) -> Dictionary:
	# 1 pack px = 2 screen px
	tool.press(points[0], points[0] * 2.0)
	for p: Vector2 in points.slice(1):
		tool.move(p, p * 2.0)
	return tool.release(points[points.size() - 1], points[points.size() - 1] * 2.0, shift, 2.0)


func test_the_hand_holds_nothing() -> void:
	assert_false(tool.in_hand())
	tool.press(Vector2.ZERO, Vector2.ZERO)
	assert_false(tool.drawing)
	assert_eq(tool.release(Vector2(50, 0), Vector2(100, 0), false, 2.0), {})


## Spec 2026-10-08-war-room-draw-orders rulings 1-3: a side first, then a kind.
func test_no_side_no_kind_and_each_side_keeps_its_last() -> void:
	assert_false(tool.pick_kind("front"), "no side chosen yet: nothing is taken")
	assert_false(tool.in_hand())
	assert_true(tool.pick("red", "front"))
	assert_eq([tool.side, tool.kind, tool.stick], ["red", "front", "red"])
	assert_true(tool.pick_kind("phase"))
	assert_eq(tool.stick, "red", "the pen is retired: a phase line is the side's colour")
	tool.switch_side()
	assert_eq([tool.side, tool.kind], ["blue", "phase"], "Tab: the other side, the same kind")
	tool.put_down()
	assert_false(tool.in_hand())
	assert_eq(tool.side, "blue", "the hand keeps the side lit")
	tool.pick_stick("red")
	assert_eq(tool.kind, "phase", "a row's crayon takes that side's last kind")
	assert_false(tool.pick("ink", "front"), "no ink stick any more")
	tool.put_down()
	tool.switch_side()
	assert_eq([tool.side, tool.kind], ["blue", "phase"], "Tab with nothing in hand takes the other side's last kind")


func test_a_drag_is_smoothed_to_a_few_points() -> void:
	tool.pick("blue", "arrow")
	var pts: Array = []
	for i in 60:
		pts.append(Vector2(i * 2.0, sin(i * 0.1) * 10.0))
	var d := _drag(pts)
	assert_eq(String(d["kind"]), "arrow")
	assert_eq(String(d["colour"]), "blue")
	var ctrl: PackedVector2Array = d["pts"]
	assert_lte(ctrl.size(), int(repo.bal("war_plan_points_max")))
	assert_gte(ctrl.size(), 3, "a wave keeps its bends")
	assert_eq(ctrl[0], pts[0])
	assert_eq(ctrl[ctrl.size() - 1], pts[pts.size() - 1])
	assert_gte((d["samples"] as PackedVector2Array).size(), pts.size(), "the raw samples too (an order's fit)")
	assert_true(tool.in_hand(), "the stick stays in hand")


func test_shift_draws_it_straight() -> void:
	tool.pick("red", "front")
	var d := _drag([Vector2(0, 0), Vector2(10, 8), Vector2(30, 0)], true)
	assert_eq(d["pts"], PackedVector2Array([Vector2(0, 0), Vector2(30, 0)]))


func test_a_short_drag_draws_nothing() -> void:
	tool.pick("blue", "arrow")
	var px := repo.bal("war_plan_min_len_px")
	assert_eq(_drag([Vector2(0, 0), Vector2(px * 0.25, 0)]), {}, "shorter than war_plan_min_len_px on the screen")


func test_a_ring_is_a_compass() -> void:
	tool.pick("blue", "objective")
	var d := _drag([Vector2(10, 10), Vector2(20, 10), Vector2(40, 10)])
	assert_eq(d["pts"], PackedVector2Array([Vector2(10, 10)]))
	assert_almost_eq(float(d["r"]), 30.0, 0.0001)
	assert_eq(String(d["colour"]), "blue")


func test_the_live_preview_follows_the_drag() -> void:
	tool.pick("red", "front")
	tool.press(Vector2.ZERO, Vector2.ZERO)
	tool.move(Vector2(20, 0), Vector2(40, 0))
	assert_eq(tool.preview().size(), 2)


## Strokes in screen px: {id, kind, ctrl, r}.
func test_picking_a_handle_before_the_line() -> void:
	var strokes := [
		{"id": "s1", "kind": "arrow", "ctrl": PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), "r": 0.0},
		{"id": "s2", "kind": "objective", "ctrl": PackedVector2Array([Vector2(300, 300)]), "r": 40.0}]
	assert_eq(WarPlanTool.hit(repo, strokes, Vector2(50, 4), "", 8.0), {"id": "s1", "handle": -1})
	assert_eq(WarPlanTool.hit(repo, strokes, Vector2(50, 30), "", 8.0), {})
	assert_eq(WarPlanTool.hit(repo, strokes, Vector2(340, 302), "", 8.0), {"id": "s2", "handle": -1}, "a ring by its rim")
	assert_eq(WarPlanTool.hit(repo, strokes, Vector2(98, 1), "s1", 8.0), {"id": "s1", "handle": 1},
		"the chosen stroke's handle first")
	assert_eq(WarPlanTool.hit(repo, strokes, Vector2(341, 300), "s2", 8.0), {"id": "s2", "handle": 1},
		"a ring's rim handle is its radius")


func _same(e: Dictionary) -> Dictionary:
	return e


func test_undo_and_redo() -> void:
	var a := {"rev": 1}
	var b := {"rev": 2}
	var now := func(e: Dictionary) -> Dictionary: return {"plans": {"rev": int(e["plans"]["rev"]) + 1}}
	tool.remember(a)
	tool.remember(b)
	assert_eq(tool.undo(now), {"plans": b})
	assert_eq(tool.undo(now), {"plans": a})
	assert_eq(tool.undo(now), {}, "nothing further back")
	assert_eq(tool.redo(now), {"plans": {"rev": 2}})
	tool.remember(b)
	assert_eq(tool.redo(now), {}, "a new edit forgets the redo")


func test_undo_is_capped() -> void:
	repo.balance["war_plan_undo_max"] = 2
	tool = WarPlanTool.new(repo)
	for i in 5:
		tool.remember({"rev": i})
	assert_eq(tool.undo(_same), {"plans": {"rev": 4}})
	assert_eq(tool.undo(_same), {"plans": {"rev": 3}})
	assert_eq(tool.undo(_same), {})


func test_undo_holds_plans_and_drafts_in_one_stack() -> void:
	tool.remember({"rev": 1})
	tool.remember_drafts({"u1": {}}, {"u1": {"order": "march"}})
	var now := func(e: Dictionary) -> Dictionary: return {"drafts": {"u1": {"order": "march"}}} if e.has("drafts") else {"plans": {"rev": 2}}
	assert_eq(tool.undo(now), {"drafts": {"u1": {}}, "expect": {"u1": {"order": "march"}}})
	assert_eq(tool.undo(now), {"plans": {"rev": 1}})
	assert_eq(tool.redo(now), {"plans": {"rev": 2}})


func test_a_new_state_empties_the_stacks() -> void:
	tool.own(1)
	tool.remember({"rev": 1})
	tool.own(2)
	assert_eq(tool.undo(_same), {})


func test_a_step_that_no_longer_holds_is_dropped() -> void:
	tool.remember({"rev": 1})
	tool.remember_drafts({"u1": {}}, {"u1": {"order": "march"}})
	var never := func(_e: Dictionary) -> bool: return false
	assert_eq(tool.undo(_same, never), {"stale": true}, "the step is dropped, said stale")
	assert_eq(tool.redo(_same), {}, "a dropped step leaves no redo")
	assert_eq(tool.undo(_same), {"plans": {"rev": 1}}, "the next step is the one before")
	var holds := func(_e: Dictionary) -> bool: return true
	assert_eq(tool.redo(_same, never), {"stale": true}, "a redo that no longer holds is dropped too")
	assert_eq(tool.undo(_same, holds), {}, "and leaves no undo")
