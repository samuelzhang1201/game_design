extends GutTest
## Game, the only writer of the WAR ROOM's plans (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.1): each write says
## `plans_changed`, never `state_changed` — a crayon stroke refreshes nothing else.

var at := Vector2.ZERO
var side := ""


func before_each() -> void:
	Game.start_campaign(44)
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			at = ArmySystem.position_of(Game.data, Game.state, r)
			break
	side = String(WarPlans.sides(Game.data)[0])


func test_a_piece_placed_moved_edited_and_removed_says_plans_changed_only() -> void:
	watch_signals(SignalHub)
	var id := Game.place_plan_piece("infantry", 1000, side, at, 0)
	assert_ne(id, "")
	assert_true(Game.move_plan_piece(id, at + Vector2(2, 0), 90))
	assert_true(Game.edit_plan_piece(id, "cavalry", 800, WarPlans.UNKNOWN))
	assert_true(Game.remove_plan(id))
	assert_signal_emit_count(SignalHub, "plans_changed", 4)
	assert_signal_not_emitted(SignalHub, "state_changed")


func test_a_refused_write_says_nothing() -> void:
	watch_signals(SignalHub)
	assert_eq(Game.place_plan_piece("fleet", 1000, side, at, 0), "")
	assert_false(Game.remove_plan("p999"))
	assert_signal_not_emitted(SignalHub, "plans_changed")


func test_strokes_and_undo() -> void:
	var before: Dictionary = Game.state.war_plans.duplicate(true)
	watch_signals(SignalHub)
	var id := Game.draw_plan("arrow", "blue", PackedVector2Array([at, at + Vector2(20, 0)]), 0.0, "", false)
	assert_ne(id, "")
	assert_true(Game.shift_plan(id, Vector2(1, 0)))
	assert_true(Game.reshape_plan(id, PackedVector2Array([at, at + Vector2(10, 5), at + Vector2(20, 0)])))
	assert_true(Game.restyle_plan(id, {"dashed": 1}))
	Game.restore_plans(before)
	assert_eq((Game.state.war_plans["strokes"] as Dictionary).size(), 0)
	assert_signal_emit_count(SignalHub, "plans_changed", 5)


func test_clear_by_rect() -> void:
	Game.place_plan_piece("infantry", 1000, side, at, 0)
	Game.draw_plan("front", "red", PackedVector2Array([at, at + Vector2(20, 0)]), 0.0, "", false)
	var rect := Rect2(at - Vector2(30, 30), Vector2(60, 60))
	assert_eq(Game.clear_plans(WarPlans.PIECES, rect), 1)
	assert_eq(Game.clear_plans(WarPlans.STROKES, rect), 1)
