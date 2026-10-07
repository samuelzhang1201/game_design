extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A courier sets out from the palace at the centre of the crown's seat and
## rides home into it (owner 2026-10-07: 信使必须一直在王都正中央的宫殿出现):
## Map3DCourierPalace dresses his drawn road; the engine is untouched.

## A 60 m palace (half 30) at the origin, unturned, the town's point 100 m east.
func _seat(yaw: float = 0.0) -> Dictionary:
	return {"centre": Vector2.ZERO, "half": 30.0, "yaw_deg": yaw, "town": Vector2(100, 0)}


func test_the_door_is_on_the_face_toward_the_road_and_the_gap_out() -> void:
	var s := _seat()
	assert_eq(Map3DCourierPalace.door(s, Vector2(100, 0), 10.0), Vector2(40, 0))
	assert_eq(Map3DCourierPalace.door(s, Vector2(0, -500), 10.0), Vector2(0, -40))
	# toward a corner the square's face is met farther out than its side
	var corner := Map3DCourierPalace.door(s, Vector2(100, 50), 0.0)
	assert_almost_eq(corner.x, 30.0, 0.001, "met on the east face")
	assert_almost_eq(corner.y, 15.0, 0.001)


func test_a_turned_palace_turns_its_footprint() -> void:
	var s := _seat(45.0)
	# turned 45 degrees, its corner points east: 30 * sqrt(2) out
	assert_almost_eq(Map3DCourierPalace.door(s, Vector2(100, 0), 0.0).x, 30.0 * sqrt(2.0), 0.01)
	assert_true(Map3DCourierPalace.inside(s, Vector2(40, 0)), "within the turned corner")
	assert_false(Map3DCourierPalace.inside(_seat(), Vector2(40, 0)), "past the unturned face")


func test_setting_out_he_waits_at_the_door_and_rides_by_the_town_point() -> void:
	var s := _seat()
	var town: Vector2 = s["town"]
	var road := Map3DCourierPalace.dress(s, town, [Vector2(300, 0)], [Vector2(300, 0), Vector2(600, 0)], 10.0)
	assert_eq(road["from"], Vector2(40, 0), "he starts at the door, not inside the palace")
	assert_eq(road["ahead"], [town, Vector2(300, 0)], "to the town's point, then his road")
	assert_eq(road["rest"], [Vector2(300, 0), Vector2(600, 0)])
	assert_almost_eq(Map3DCourierRide.length_along(road["from"], road["ahead"]), 260.0, 0.001,
		"no jump: the day's ride is measured from the door")


func test_a_town_point_inside_the_palace_is_never_ridden_through() -> void:
	var s := _seat()
	s["town"] = Vector2(5, 0)
	var road := Map3DCourierPalace.dress(s, Vector2(5, 0), [Vector2(-300, 0)], [], 10.0)
	assert_true((road["from"] as Vector2).is_equal_approx(Vector2(-40, 0)), "the door facing where he rides")
	assert_eq(road["ahead"], [Vector2(-300, 0)])


func test_riding_home_he_rides_on_into_the_door() -> void:
	var s := _seat()
	var road := Map3DCourierPalace.dress(s, Vector2(900, 0), [Vector2(500, 0), Vector2(100, 0)], [Vector2(100, 0)], 10.0)
	assert_eq(road["from"], Vector2(900, 0), "out on the road: drawn where he is")
	assert_eq(road["rest"], [Vector2(100, 0), Vector2(40, 0)], "his road ends at the door")
	var today := Map3DCourierPalace.dress(s, Vector2(900, 0), [Vector2(500, 0), Vector2(100, 0)], [], 10.0)
	assert_eq(today["ahead"], [Vector2(500, 0), Vector2(100, 0), Vector2(40, 0)], "he delivers at the door")


func test_no_seat_leaves_the_road_as_it_is() -> void:
	var road := Map3DCourierPalace.dress({}, Vector2(1, 2), [Vector2(3, 4)], [], 10.0)
	assert_eq(road, {"from": Vector2(1, 2), "ahead": [Vector2(3, 4)], "rest": []})


func test_the_capital_seat_is_its_palace() -> void:
	var repo := SuiteData.repo()
	var realm := repo.resolve_realm("player_realm")
	var cap := String((repo.kingdoms[realm] as Dictionary)["capital_burg"])
	var b: Dictionary = repo.burgs[cap]
	var px := Vector2(float(b["x"]), float(b["y"]))
	var houses := {cap: [{"rank": 0, "type": "palace", "at": Vector2(7, 8), "yaw_deg": 30.0, "scale": 1.0}]}
	var seat := Map3DCourierPalace.seat_of(repo, houses, px, Vector2(1, 1))
	assert_eq(seat["centre"], Vector2(7, 8))
	assert_almost_eq(float(seat["half"]), 0.5 * maxf(float(repo.map3d_houses["palace"]["width_m"]),
		float(repo.map3d_houses["palace"]["depth_m"])), 0.001)
	assert_eq(seat["town"], Vector2(1, 1))
	houses[cap][0]["type"] = "cottage_a"
	assert_eq(Map3DCourierPalace.seat_of(repo, houses, px, Vector2.ZERO), {}, "no landmark at its centre: no seat")
	assert_eq(Map3DCourierPalace.seat_of(repo, {}, px, Vector2.ZERO), {}, "no bake: no seat")
