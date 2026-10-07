extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A drawn blue arrow as a march's route (spec 2026-10-08-war-room-draw-orders
## ruling 7): the stroke smoothed into whole-metre control points, its tip the
## end; each selected regiment joins it at its nearest point.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _line(a: Vector2, b: Vector2, step := 2.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := int(ceil(a.distance_to(b) / step))
	for i in n + 1:
		out.append(a.lerp(b, float(i) / float(n)))
	return out


func _whole(p: Vector2) -> bool:
	var m := ArmySystem.pack_to_metres(repo, p)
	return ArmySystem.metres_to_pack(repo, m).distance_to(p) < 0.000001


func test_a_straight_stroke_is_its_two_ends() -> void:
	var path := WarOrderSketch.fit(repo, _line(Vector2(100, 100), Vector2(200, 100)), 1.0)
	assert_eq(path.size(), 2)
	assert_almost_eq(path[0].distance_to(Vector2(100, 100)), 0.0, 0.01)
	assert_almost_eq(path[1].distance_to(Vector2(200, 100)), 0.0, 0.01, "the tip is the end")
	assert_true(_whole(path[0]) and _whole(path[1]), "whole metres")


func test_a_bent_stroke_keeps_its_corner() -> void:
	var s := _line(Vector2(100, 100), Vector2(200, 100))
	s.append_array(_line(Vector2(200, 100), Vector2(200, 200)).slice(1))
	var path := WarOrderSketch.fit(repo, s, 1.0)
	assert_eq(path.size(), 3)
	assert_almost_eq(path[1].distance_to(Vector2(200, 100)), 0.0, 0.01)


func test_a_wiggling_stroke_keeps_at_most_the_waypoints_a_march_takes() -> void:
	var s := PackedVector2Array()
	for i in 40:
		s.append(Vector2(100 + i * 10, 100 + (30 if i % 2 == 1 else 0)))
	var path := WarOrderSketch.fit(repo, s, 0.5)
	assert_lte(path.size(), int(repo.bal("army_march_waypoints_max")) + 1, "the waypoints and the end")
	assert_almost_eq(path[path.size() - 1].distance_to(s[s.size() - 1]), 0.0, 0.01)


func test_points_closer_than_a_route_sample_are_one() -> void:
	var step := float(repo.bal("army_route_sample_m")) / float(ArmySystem.metres_per_pack_px(repo))
	var s := PackedVector2Array([Vector2(100, 100), Vector2(100 + step * 0.3, 140), Vector2(300, 100)])
	var path := WarOrderSketch.fit(repo, s, 0.01)
	for i in range(1, path.size()):
		assert_gt(path[i - 1].distance_to(path[i]), step * 0.99)


func test_a_regiment_joins_the_path_at_its_nearest_point() -> void:
	var path := PackedVector2Array([Vector2(100, 100), Vector2(200, 100), Vector2(300, 100), Vector2(400, 200)])
	var reach := repo.bal("war_order_join_km") * WarSheets.px_per_unit(repo)
	assert_eq(WarOrderSketch.route_for(repo, Vector2(100, 100) + Vector2(reach * 0.5, 0), path),
		[Vector2(200, 100), Vector2(300, 100)], "standing at the start: it joins there, no waypoint for it")
	assert_eq(WarOrderSketch.route_for(repo, Vector2(40, 100), path),
		[Vector2(100, 100), Vector2(200, 100), Vector2(300, 100)], "standing short of the start: it marches to it")
	assert_eq(WarOrderSketch.route_for(repo, Vector2(200, 100) + Vector2(0, reach * 0.5), path), [Vector2(300, 100)],
		"standing by the second point: it joins there")
	assert_eq(WarOrderSketch.route_for(repo, Vector2(200, 100) + Vector2(0, reach * 3.0), path),
		[Vector2(200, 100), Vector2(300, 100)], "a little off it: it marches onto the path first")
	assert_eq(WarOrderSketch.route_for(repo, Vector2(390, 210), path), [], "beyond the last bend: straight to the end")
