extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Spreading boxes so none overlaps (spec 2026-10-07-army-split-and-ground §5.2).


func test_the_spiral_starts_at_home_and_grows() -> void:
	var s := Map3DDeclutter.spiral(4.0, 12.0)
	assert_eq(s[0], Vector2.ZERO)
	for i in range(1, s.size()):
		assert_gte((s[i] as Vector2).length(), (s[i - 1] as Vector2).length() - 0.001)
	assert_true(s.all(func(v: Vector2) -> bool: return maxf(absf(v.x), absf(v.y)) <= 12.0 + 0.001))


func test_no_two_placed_boxes_overlap() -> void:
	var boxes: Array = []
	for i in 12:
		boxes.append(Rect2(Vector2(100.0, 100.0) + Vector2(i, i), Vector2(20.0, 10.0)))
	var offs := Map3DDeclutter.place(boxes, boxes.map(func(_b: Rect2) -> bool: return false), [], 4.0, 400.0)
	var placed: Array = []
	for i in boxes.size():
		assert_not_null(offs[i])
		placed.append(Rect2((boxes[i] as Rect2).position + (offs[i] as Vector2), (boxes[i] as Rect2).size))
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			assert_false((placed[i] as Rect2).intersects(placed[j]), "%d and %d" % [i, j])


func test_the_first_never_moves() -> void:
	var boxes := [Rect2(0, 0, 10, 10), Rect2(2, 2, 10, 10)]
	var offs := Map3DDeclutter.place(boxes, [false, false], [], 2.0, 50.0)
	assert_eq(offs[0], Vector2.ZERO)
	assert_ne(offs[1], Vector2.ZERO)


func test_obstacles_are_kept_clear() -> void:
	var offs := Map3DDeclutter.place([Rect2(0, 0, 10, 10)], [false], [Rect2(0, 0, 10, 10)], 2.0, 50.0)
	assert_false(Rect2(Vector2.ZERO + (offs[0] as Vector2), Vector2(10, 10)).intersects(Rect2(0, 0, 10, 10)))


func test_a_hideable_box_with_no_room_hides_a_counter_never() -> void:
	var wall := [Rect2(-100, -100, 200, 200)]
	var offs := Map3DDeclutter.place([Rect2(0, 0, 10, 10), Rect2(0, 0, 10, 10)], [true, false], wall, 2.0, 20.0)
	assert_null(offs[0], "a chip hides")
	assert_not_null(offs[1], "a counter takes the clearest place it found")


func test_deterministic() -> void:
	var boxes := [Rect2(0, 0, 10, 10), Rect2(1, 0, 10, 10), Rect2(0, 1, 10, 10)]
	assert_eq(Map3DDeclutter.place(boxes, [false, false, false], [], 3.0, 60.0),
		Map3DDeclutter.place(boxes, [false, false, false], [], 3.0, 60.0))


## Every unit of the crown stacked on one screen point: each keeps its own
## counter, none covers another, and the selected one stays on its point.
func test_counters_on_one_point_spread_and_the_selected_stays_home() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var points: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		points.append({"reg": r, "pos": Vector2(400.0, 300.0)})
	assert_gt(points.size(), 2, "premise: the crown has several units")
	var picked := String((points[points.size() - 1]["reg"] as Dictionary)["regiment_code"])
	var marks := ArmyCounters.layout(repo, points, 20.0, [], {}, [picked])
	assert_eq(marks.size(), points.size(), "no counter is hidden or merged")
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			assert_false((marks[i]["rect"] as Rect2).intersects(marks[j]["rect"]),
				"%s and %s" % [marks[i]["code"], marks[j]["code"]])
	for m: Dictionary in marks:
		if String(m["code"]) == picked:
			assert_eq(m["pos"], Vector2(400.0, 300.0), "the selected counter never moves")
			assert_eq((m["count"] as Rect2).position.y, (m["rect"] as Rect2).position.y
				+ ArmyCounters.bars_height(repo), "its parts follow its rect")


## A chip over a 3D piece hides when it finds no clear place; a counter never.
func test_a_chip_with_no_room_hides() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var regs := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state)
	var a := String(regs[0]["regiment_code"])
	var points := [{"reg": regs[0], "pos": Vector2(400.0, 300.0)}, {"reg": regs[1], "pos": Vector2(400.0, 300.0)}]
	var wall := [Rect2(-1000, -1000, 3000, 3000)]
	var marks := ArmyCounters.layout(repo, points, 20.0, wall, {a: true})
	assert_eq(marks.size(), 1, "the chip hides")
	assert_ne(String(marks[0]["code"]), a, "the counter stays")


## place() tries the last blocker first and skips what lies out of reach;
## each offset must still be exactly the first clear one of the spiral.
func test_each_offset_is_the_first_clear_one_of_the_spiral() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for trial in 40:
		var boxes: Array = []
		for k in rng.randi_range(2, 9):
			boxes.append(Rect2(Vector2(rng.randf_range(0.0, 30.0), rng.randf_range(0.0, 30.0)),
				Vector2(rng.randf_range(8.0, 40.0), rng.randf_range(6.0, 20.0))))
		var obstacles: Array = []
		for k in rng.randi_range(0, 4):
			obstacles.append(Rect2(Vector2(rng.randf_range(-20.0, 50.0), rng.randf_range(-20.0, 50.0)),
				Vector2(rng.randf_range(2.0, 12.0), rng.randf_range(2.0, 12.0))))
		var offs := Map3DDeclutter.place(boxes, boxes.map(func(_b: Rect2) -> bool: return true), obstacles, 3.0, 90.0)
		var placed: Array = obstacles.duplicate()
		for i in boxes.size():
			var b: Rect2 = boxes[i]
			var walked: Variant = null
			for off: Vector2 in Map3DDeclutter.spiral(3.0, 90.0):
				var r := Rect2(b.position + off, b.size)
				if not placed.any(func(p: Rect2) -> bool: return r.intersects(p)):
					walked = off
					break
			assert_eq(offs[i], walked, "trial %d box %d" % [trial, i])
			if walked != null:
				placed.append(Rect2(b.position + (walked as Vector2), b.size))


## Two counters stand at least map_army_stack_gap_px apart, measured on the
## counters themselves (not the grown boxes the spreading used).
func test_counters_keep_the_gap_between_them() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var gap := repo.bal("map_army_stack_gap_px")
	assert_gte(gap, 6.0, "the gap reads as a gap")
	var points: Array = []
	var i := 0
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		points.append({"reg": r, "pos": Vector2(400.0 + float(i % 3) * 7.0, 300.0 + float(i % 2) * 5.0)})
		i += 1
	var marks := ArmyCounters.layout(repo, points, 20.0, [])
	assert_eq(marks.size(), points.size())
	for a in marks.size():
		for b in range(a + 1, marks.size()):
			var ra: Rect2 = marks[a]["rect"]
			var rb: Rect2 = marks[b]["rect"]
			var apart := maxf(maxf(rb.position.x - ra.end.x, ra.position.x - rb.end.x),
				maxf(rb.position.y - ra.end.y, ra.position.y - rb.end.y))
			assert_gte(apart, gap - 0.001, "%s and %s" % [marks[a]["code"], marks[b]["code"]])
