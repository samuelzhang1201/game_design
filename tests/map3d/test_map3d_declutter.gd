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


func _naive_least_overlap(box: Rect2, obstacles: Array[Rect2], offsets: Array) -> Vector2:
	var best := Vector2.ZERO
	var score := INF
	for offset: Vector2 in offsets:
		var moved := Rect2(box.position + offset, box.size)
		var area := 0.0
		for obstacle: Rect2 in obstacles:
			if moved.intersects(obstacle): area += moved.intersection(obstacle).get_area()
		if area < score:
			score = area
			best = offset
	return best


func test_crowded_fallback_keeps_exact_naive_offset_and_tie_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 714
	for step: float in [0.5, 2.0, 2.3, 4.0]:
		var offsets := Map3DDeclutter.spiral(step, step * 7)
		for sample: int in 20:
			var box := Rect2(Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), Vector2(8.25, 6.5))
			var obstacles: Array[Rect2] = [Rect2(-100, -100, 200, 200)]
			for i: int in 12:
				obstacles.append(Rect2(Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), Vector2(rng.randf_range(1, 20), rng.randf_range(1, 20))))
			assert_eq(Map3DDeclutter._least_covered(box, obstacles, offsets), _naive_least_overlap(box, obstacles, offsets))
	assert_eq(Map3DDeclutter._least_covered(Rect2(0,0,10,10), [Rect2(-100,-100,200,200)], [Vector2.ZERO]), Vector2.ZERO)
	assert_eq(Map3DDeclutter._least_covered(Rect2(0,0,2,2), [Rect2(-10,-10,20,20), Rect2(0,0,2,2)], Map3DDeclutter.spiral(1,1)), Vector2(1,-1), "diagonal overlap is 4+1; cardinal is 4+2, home is 4+4")


func test_first_clear_retains_subpixel_edges_across_the_lattice() -> void:
	var box := Rect2(0.25, 0.125, 30, 24)
	for edge: float in [92.0, 96.0, 100.0]:
		var obstacles: Array[Rect2] = [Rect2(-1000, -1000, 1000 + edge, 2000)]
		var offsets := Map3DDeclutter.spiral(4, 160)
		assert_eq(Map3DDeclutter._first_clear(box, obstacles, offsets, Callable()), Vector2(edge, 0))
		assert_eq(Map3DDeclutter._first_clear(box, obstacles, offsets, Callable()), _walk(box, obstacles, 4, 160))
	for step: float in [0.5, 2.3, 4.0]:
		var obstacles: Array[Rect2] = [box, Rect2(-5.375, -30.625, 20.125, 50.875)]
		assert_eq(Map3DDeclutter._first_clear(box, obstacles, Map3DDeclutter.spiral(step, step * 40), Callable()), _walk(box, obstacles, step, step * 40))


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
	var marks := ArmyCounters.layout(repo, points, 20.0, [], [picked])
	assert_eq(marks.size(), points.size(), "no counter is hidden or merged")
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			assert_false((marks[i]["rect"] as Rect2).intersects(marks[j]["rect"]),
				"%s and %s" % [marks[i]["code"], marks[j]["code"]])
	for m: Dictionary in marks:
		if String(m["code"]) == picked:
			assert_eq(m["pos"], Vector2(400.0, 300.0), "the selected counter never moves")
			assert_eq((m["count"] as Rect2).position.y, (m["rect"] as Rect2).position.y,
				"its parts follow its rect")


## A counter with no clear place takes the clearest it found: never hidden.
func test_a_counter_with_no_room_is_never_hidden() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var regs := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state)
	var points := [{"reg": regs[0], "pos": Vector2(400.0, 300.0)}, {"reg": regs[1], "pos": Vector2(400.0, 300.0)}]
	var wall := [Rect2(-1000, -1000, 3000, 3000)]
	assert_eq(ArmyCounters.layout(repo, points, 20.0, wall).size(), 2)


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


# --- the land and the gap (2026-10-08 visual review) -------------------------

## The first clear offset of the spiral that `ok` takes (or any, without it).
func _walk(b: Rect2, placed: Array, step: float, reach: float, ok: Callable = Callable()) -> Variant:
	for off: Vector2 in Map3DDeclutter.spiral(step, reach):
		var r := Rect2(b.position + off, b.size)
		if placed.any(func(p: Rect2) -> bool: return r.intersects(p)):
			continue
		if not ok.is_valid() or off == Vector2.ZERO or bool(ok.call(r.get_center())):
			return off
	return null


func test_allowed_is_honoured() -> void:
	var b := Rect2(0, 0, 10, 10)
	var east := func(c: Vector2) -> bool: return c.x > 20.0
	var offs := Map3DDeclutter.place([b, b], [false, false], [], 2.0, 50.0, east)
	assert_eq(offs[0], Vector2.ZERO, "the first stays home")
	var at := Rect2(b.position + (offs[1] as Vector2), b.size)
	assert_gt(at.get_center().x, 20.0, "the second goes where it is allowed")
	assert_false(at.intersects(b))
	assert_eq(offs[1], _walk(b, [b], 2.0, 50.0, east), "the first clear and allowed offset")
	assert_ne(offs[1], _walk(b, [b], 2.0, 50.0), "premise: the nearest clear one was not allowed")


## The hard rule: with the near half-plane refused, the box goes to the far
## side although nearer overlap-free places exist — it falls back to a
## refused place only when no allowed one is clear within reach.
func test_a_refused_near_side_sends_the_box_to_the_far_side() -> void:
	var b := Rect2(0, 0, 20, 10)
	# the box's own row and all below it refused: only far north (y < -60) is "land"
	var far_north := func(c: Vector2) -> bool: return c.y < -60.0
	var crowd: Array = [Rect2(-30, -30, 80, 25)]   # a band over its head, overlap-free beside it
	var offs := Map3DDeclutter.place([b, b], [false, false], crowd, 4.0, 120.0, far_north)
	var nearest: Variant = _walk(b, crowd + [b], 4.0, 120.0)
	assert_not_null(nearest)
	assert_gt(Rect2(b.position + (nearest as Vector2), b.size).get_center().y, -60.0,
		"premise: the nearest overlap-free place is on the refused side")
	var at := Rect2(b.position + (offs[1] as Vector2), b.size)
	assert_lt(at.get_center().y, -60.0, "it crossed to the allowed side")
	assert_false(at.intersects(b) or at.intersects(crowd[0]), "and overlaps nothing")
	assert_gt((offs[1] as Vector2).length(), (nearest as Vector2).length(), "though nearer places were clear")
	# nothing allowed within reach: the nearest clear place, never lost
	var short := Map3DDeclutter.place([b, b], [false, false], crowd, 4.0, 40.0, far_north)
	assert_eq(short[1], _walk(b, crowd + [b], 4.0, 40.0), "the fallback is the nearest clear place")


func test_allowed_is_asked_only_off_home_of_clear_places() -> void:
	var asked: Array = []
	var spy := func(c: Vector2) -> bool:
		asked.append(c)
		return true
	Map3DDeclutter.place([Rect2(0, 0, 10, 10)], [false], [], 2.0, 50.0, spy)
	assert_eq(asked.size(), 0, "a box at home on clear ground asks nothing")
	Map3DDeclutter.place([Rect2(0, 0, 10, 10), Rect2(0, 0, 10, 10)], [false, false], [], 2.0, 50.0, spy)
	assert_eq(asked.size(), 1, "one ask: the first clear place off home is taken")
	assert_false(Rect2((asked[0] as Vector2) - Vector2(5, 5), Vector2(10, 10)).intersects(Rect2(0, 0, 10, 10)))


func test_a_fleet_is_never_asked() -> void:
	var b := Rect2(0, 0, 10, 10)
	var never := func(_c: Vector2) -> bool: return false
	var counted: Array = [0]
	var count := func(_c: Vector2) -> bool:
		counted[0] += 1
		return false
	var free := Map3DDeclutter.place([b, b], [false, false], [], 2.0, 50.0)
	var offs := Map3DDeclutter.place([b, b], [false, false], [], 2.0, 50.0, never, [false, true])
	assert_eq(offs, free, "a fleet takes the first clear place, the sea or not")
	Map3DDeclutter.place([b, b], [false, false], [], 2.0, 50.0, count, [false, true])
	assert_eq(counted[0], 0)


func test_with_nowhere_allowed_no_box_is_lost() -> void:
	var b := Rect2(0, 0, 10, 10)
	var never := func(_c: Vector2) -> bool: return false
	var boxes := [b, b, b, b]
	var offs := Map3DDeclutter.place(boxes, [false, true, false, true], [], 2.0, 50.0, never)
	var free := Map3DDeclutter.place(boxes, [false, true, false, true], [], 2.0, 50.0)
	assert_eq(offs, free, "each takes its nearest overlap-free place")
	for o: Variant in offs:
		assert_not_null(o, "a chip with room is never hidden for the sea")


## Two counters stand at least map_army_stack_gap_px apart, measured rim to
## rim on what is drawn — the counter's rect grown by its outline — not on the
## grown boxes the spreading used.
func test_counters_keep_the_gap_between_them() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var gap := repo.bal("map_army_stack_gap_px")
	var rim := ArmyCounters.outline_px(repo)
	assert_gte(gap, 8.0, "the gap reads as a gap")
	var points: Array = []
	var i := 0
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		points.append({"reg": r, "pos": Vector2(400.0 + float(i % 3) * 7.0, 300.0 + float(i % 2) * 5.0)})
		i += 1
	var marks := ArmyCounters.layout(repo, points, 20.0, [])
	assert_eq(marks.size(), points.size())
	for a in marks.size():
		for b in range(a + 1, marks.size()):
			var ra: Rect2 = (marks[a]["rect"] as Rect2).grow(rim)
			var rb: Rect2 = (marks[b]["rect"] as Rect2).grow(rim)
			assert_eq(ra.position.y + rim, (marks[a]["rect"] as Rect2).position.y, "premise")
			var apart := maxf(maxf(rb.position.x - ra.end.x, ra.position.x - rb.end.x),
				maxf(rb.position.y - ra.end.y, ra.position.y - rb.end.y))
			assert_gte(apart, gap - 0.001, "%s and %s" % [marks[a]["code"], marks[b]["code"]])
