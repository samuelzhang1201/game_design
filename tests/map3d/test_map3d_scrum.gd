extends GutTest
## The mixed fight's pure geometry (Map3DScrum; spec 2026-11-21-infantry-melee-scrum-design.md):
## one fighting area between two fronts, hashed targets inside it, a bounded
## separation pass and greedy nearest pairing. Hand-computed values.


func _row(y: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for x in [0.0, 2.0, 4.0]:
		out.append(Vector2(x, y))
	return out


func test_area_spans_both_fronts() -> void:
	var area := Map3DScrum.area(_row(-2.0), _row(2.0), Vector2(0, 1), 4.0)
	assert_almost_eq((area["centre"] as Vector2).distance_to(Vector2(2, 0)), 0.0, 1e-5, "between the two sides' means")
	assert_almost_eq(float(area["half_len"]), 2.0, 1e-5, "both fronts' extent along the line")
	assert_almost_eq(float(area["half_depth"]), 2.0, 1e-5, "half the depth across it")
	assert_almost_eq(absf((area["along"] as Vector2).dot(Vector2(1, 0))), 1.0, 1e-5, "along = across turned 90°")


func test_an_area_with_no_facing_takes_the_sides_line() -> void:
	var area := Map3DScrum.area(_row(-2.0), _row(2.0), Vector2.ZERO, 4.0)
	assert_almost_eq(absf((area["across"] as Vector2).dot(Vector2(0, 1))), 1.0, 1e-5, "across from one side's mean to the other's")
	assert_almost_eq(float(area["half_len"]), 2.0, 1e-5)


func _inside(p: Vector2, area: Dictionary) -> bool:
	var d: Vector2 = p - area["centre"]
	return absf(d.dot(area["along"])) <= float(area["half_len"]) + 1e-4 \
		and absf(d.dot(area["across"])) <= float(area["half_depth"]) + 1e-4


func test_targets_stay_inside() -> void:
	var area := Map3DScrum.area(_row(-2.0), _row(2.0), Vector2(0, 1), 4.0)
	for i in 100:
		assert_true(_inside(Map3DScrum.target("A:%d" % i, area), area), "A:%d inside the area" % i)


func test_targets_are_stable() -> void:
	var area := Map3DScrum.area(_row(-2.0), _row(2.0), Vector2(0, 1), 4.0)
	assert_eq(Map3DScrum.target("A:3", area), Map3DScrum.target("A:3", area))
	assert_ne(Map3DScrum.target("A:3", area), Map3DScrum.target("A:4", area), "neighbours spread")


func test_separate_pushes_overlaps_apart() -> void:
	var out := Map3DScrum.separate({"p": Vector2(0, 0), "q": Vector2(0.5, 0)}, 0.8, 0.2)
	assert_almost_eq((out["p"] as Vector2).distance_to(Vector2(-0.15, 0)), 0.0, 1e-5, "each half the overlap 0.3")
	assert_almost_eq((out["q"] as Vector2).distance_to(Vector2(0.65, 0)), 0.0, 1e-5)


func test_separate_moves_at_most_push() -> void:
	var pts := {"p": Vector2(0, 0), "q": Vector2(0.1, 0), "r": Vector2(0.05, 0.05), "far": Vector2(5, 5)}
	var out := Map3DScrum.separate(pts, 0.8, 0.2)
	for key: String in pts:
		assert_lte((out[key] as Vector2).distance_to(pts[key]), 0.2 + 1e-5, "%s moves at most push" % key)
	assert_eq(out["far"], pts["far"], "a figure with room stays")
	var same := Map3DScrum.separate({"p": Vector2(1, 1), "q": Vector2(1, 1)}, 0.8, 0.2)
	assert_almost_eq((same["p"] as Vector2).distance_to(same["q"]), 0.4, 1e-5, "two on one spot part along a fixed line")


func test_pairs_nearest_is_greedy_and_stable() -> void:
	var a := [{"key": "A:0", "xz": Vector2(0, 0)}, {"key": "A:1", "xz": Vector2(3, 0)}, {"key": "A:2", "xz": Vector2(10, 0)}]
	var b := [{"key": "B:0", "xz": Vector2(2, 0)}, {"key": "B:1", "xz": Vector2(0, 1.5)}]
	# distances: A:1-B:0 1, A:0-B:1 1.5, A:0-B:0 2, … A:2 is 8 from B:0, past the reach
	var pairs := Map3DScrum.pairs_nearest(a, b, 5.0)
	assert_eq(pairs, [{"a": "A:1", "b": "B:0"}, {"a": "A:0", "b": "B:1"}], "nearest first, each once, none past reach")
	var tie := Map3DScrum.pairs_nearest([{"key": "A:1", "xz": Vector2(1, 0)}, {"key": "A:0", "xz": Vector2(-1, 0)}],
		[{"key": "B:0", "xz": Vector2(0, 0)}], 5.0)
	assert_eq(tie, [{"a": "A:0", "b": "B:0"}], "a tie goes to the smaller key")


func test_inside_holds_a_point_in_the_area() -> void:
	var area := Map3DScrum.area(_row(-2.0), _row(2.0), Vector2(0, 1), 4.0)
	assert_almost_eq(Map3DScrum.inside(Vector2(7, 5), area).distance_to(Vector2(4, 2)), 0.0, 1e-5, "clamped to the corner")
	assert_eq(Map3DScrum.inside(Vector2(1, 1), area), Vector2(1, 1), "a point inside stays")
