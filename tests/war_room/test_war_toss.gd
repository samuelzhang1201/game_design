extends GutTest
## The war marker tossed onto the index chart (spec 2026-10-02-war-room-v2 §2.3):
## an arc, a tumble, a bounce or two, and it stands upright where it landed.

var rules := {"apex_m": 0.2, "fly_s": 0.6, "turns_min": 1.0, "turns_max": 2.0, "bounces": 2,
	"bounce_ratio": 0.3, "settle_s": 0.2}


func test_it_starts_in_the_hand_and_ends_standing_on_its_point() -> void:
	var from := Vector3(0.0, 1.0, 1.0)
	var to := Vector3(0.3, 0.0, -0.5)
	var p := WarToss.plan(from, to, 7, rules)
	assert_almost_eq(WarToss.pose(p, 0.0).origin.distance_to(from), 0.0, 0.0001)
	var end := WarToss.pose(p, float(p["duration"]))
	assert_almost_eq(end.origin.distance_to(to), 0.0, 0.0001)
	assert_almost_eq(end.basis.y.normalized().dot(Vector3.UP), 1.0, 0.0001, "upright")
	assert_almost_eq(WarToss.pose(p, float(p["duration"]) + 5.0).origin.distance_to(to), 0.0, 0.0001, "held after")


func test_the_flight_is_an_arc_over_the_straight_line() -> void:
	var p := WarToss.plan(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), 3, rules)
	var mid := WarToss.pose(p, float(p["fly_s"]) * 0.5).origin
	assert_almost_eq(mid.y, 0.2, 0.0001, "the apex at the middle: 4 * apex * 0.5 * 0.5")


func test_it_bounces_lower_each_time() -> void:
	var p := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 5, rules)
	var b: Array = p["bounces"]
	assert_eq(b.size(), 2)
	assert_almost_eq(float(b[0]["h"]), 0.2 * 0.3, 0.0001)
	assert_almost_eq(float(b[1]["h"]), 0.2 * 0.09, 0.0001)


func test_the_same_seed_throws_the_same_and_another_differs() -> void:
	var a := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 11, rules)
	var b := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 11, rules)
	var c := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 12, rules)
	assert_eq(a["turns"], b["turns"])
	assert_ne([a["turns"], a["yaw"]], [c["turns"], c["yaw"]])


func test_the_landing_lies_inside_the_cell_off_its_edges() -> void:
	var r := Rect2(0.2, 0.3, 0.1, 0.05)
	for s in 30:
		var at := WarToss.landing(r, s, 0.2)
		assert_true(r.grow_individual(-0.02, -0.01, -0.02, -0.01).has_point(at) or
			r.grow_individual(-0.02, -0.01, -0.02, -0.01).end.is_equal_approx(at), str(at))
