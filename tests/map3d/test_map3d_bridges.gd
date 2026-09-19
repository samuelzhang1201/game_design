extends GutTest
## Map3DBridges: where a road crosses a river it runs over a stone bridge —
## the span, the deck's profile and the stone mesh, from hand-computed cases.

const RULES := {
	"abut_m": 10.0, "clear_m": 5.0, "clear_per_width": 0.05, "hump_m": 1.0,
	"min_sin": 0.5, "merge_m": 40.0, "deck_step_m": 5.0, "deck_m": 1.5,
	"parapet_h_m": 1.0, "parapet_w_m": 0.5, "arch_max_m": 20.0, "pier_m": 3.0,
	"end_over_water_m": 0.5,
}


## A river running north-south along x = 0, water at 10 m, 20 m wide.
func _river() -> Array:
	return [{"pos": PackedVector3Array([Vector3(0, 10, -500), Vector3(0, 10, 500)]),
		"width": PackedFloat32Array([20.0, 20.0])}]


func _flat(y: float) -> Callable:
	return func(_xz: Vector2) -> float: return y


func test_a_road_square_across_a_river_crosses_it_once() -> void:
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])
	var hits := Map3DBridges.crossings(road, Map3DBridges.river_grid(_river()))
	assert_eq(hits.size(), 1)
	assert_almost_eq(float(hits[0]["arc"]), 100.0, 0.001)
	assert_almost_eq(float(hits[0]["water_y"]), 10.0, 0.001)
	assert_almost_eq(float(hits[0]["width"]), 20.0, 0.001)


func test_a_road_beside_a_river_has_no_bridge() -> void:
	var road := PackedVector2Array([Vector2(50, -100), Vector2(50, 100)])
	var plan := Map3DBridges.plan([road], _river(), _flat(12.0), RULES)
	assert_true((plan["bridges"] as Array).is_empty())
	assert_eq(plan["lines"][0], road, "the road is left as it was")


func test_the_span_is_the_river_seen_along_the_road_plus_both_abutments() -> void:
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])
	var plan := Map3DBridges.plan([road], _river(), _flat(12.0), RULES)
	var b: Dictionary = plan["bridges"][0]
	# square crossing: 20 m of water + 10 m each side = 40 m, centred on x = 0
	assert_almost_eq((b["a"] as Vector2).x, -20.0, 0.001)
	assert_almost_eq((b["b"] as Vector2).x, 20.0, 0.001)


func test_a_slanted_crossing_is_longer_but_capped_by_min_sin() -> void:
	# at 30 degrees to the river the sine is 0.5 (the cap): 20 / 0.5 = 40 m
	# of water along the road, + 20 m of abutments = 60 m
	var d := Vector2(cos(deg_to_rad(60.0)), sin(deg_to_rad(60.0)))
	var road := PackedVector2Array([-d * 200.0, d * 200.0])
	var plan := Map3DBridges.plan([road], _river(), _flat(12.0), RULES)
	var b: Dictionary = plan["bridges"][0]
	assert_almost_eq((b["a"] as Vector2).distance_to(b["b"]), 60.0, 0.01)


func test_the_deck_rises_from_the_banks_to_a_crown_clear_of_the_water() -> void:
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])
	var plan := Map3DBridges.plan([road], _river(), _flat(12.0), RULES)
	var b: Dictionary = plan["bridges"][0]
	assert_almost_eq(float(b["ya"]), 12.0, 0.001)
	assert_almost_eq(float(b["yb"]), 12.0, 0.001)
	# crown = max(banks 12, water 10 + 5 + 0.05 * 20 = 16) + hump 1 = 17
	assert_almost_eq(float(b["crown"]), 17.0, 0.001)
	assert_almost_eq(Map3DBridges.deck_y(12.0, 12.0, 17.0, 0.5), 17.0, 0.001)
	assert_almost_eq(Map3DBridges.deck_y(12.0, 12.0, 17.0, 0.0), 12.0, 0.001)
	# 4t(1-t) of the 5 m rise a quarter of the way: 12 + 5 * 0.75
	assert_almost_eq(Map3DBridges.deck_y(12.0, 12.0, 17.0, 0.25), 15.75, 0.001)


func test_a_deck_end_never_lies_under_the_water() -> void:
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])
	var plan := Map3DBridges.plan([road], _river(), _flat(4.0), RULES)
	var b: Dictionary = plan["bridges"][0]
	assert_almost_eq(float(b["ya"]), 10.5, 0.001, "water 10 + end_over_water 0.5")
	assert_almost_eq(float(b["foot"]), 2.0, 0.001, "under the lower of bank 4 and water 10, by 2")


func test_the_road_is_straightened_over_the_span_and_carries_the_deck_heights() -> void:
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(-50, 0), Vector2(0, 3),
		Vector2(50, 0), Vector2(100, 0)])
	var plan := Map3DBridges.plan([road], _river(), _flat(12.0), RULES)
	var line: PackedVector2Array = plan["lines"][0]
	var hs: PackedFloat32Array = plan["heights"][0]
	assert_eq(line.size(), hs.size())
	var on_deck := 0
	for i in line.size():
		if is_nan(hs[i]):
			assert_true(absf(line[i].x) > 19.0, "off the span the road keeps its own points")
		else:
			on_deck += 1
			assert_true(absf(line[i].x) <= 20.5, "the deck's points lie on the span")
			assert_true(hs[i] >= 12.0 - 0.001, "and never under the banks")
	# 40 m at a point every 5 m at most: 9 points
	assert_eq(on_deck, 9)


func test_a_road_crossing_a_meander_twice_gets_one_bridge() -> void:
	var river := [{"pos": PackedVector3Array([Vector3(-10, 10, -500), Vector3(-10, 10, 500)]),
			"width": PackedFloat32Array([10.0, 10.0])},
		{"pos": PackedVector3Array([Vector3(15, 10, -500), Vector3(15, 10, 500)]),
			"width": PackedFloat32Array([10.0, 10.0])}]
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])
	var plan := Map3DBridges.plan([road], river, _flat(12.0), RULES)
	assert_eq((plan["bridges"] as Array).size(), 1, "the spans overlap: one bridge")


func test_the_soffit_is_arches_on_piers_over_the_water_and_solid_on_the_banks() -> void:
	var b := {"ya": 12.0, "yb": 12.0, "crown": 17.0, "water_y": 10.0, "foot": 8.0}
	var span := 100.0
	# abutments: the first 10 m and the last 10 m stand on the foot
	assert_almost_eq(Map3DBridges.soffit_y(b, RULES, 0.05, span), 8.0, 0.001)
	assert_almost_eq(Map3DBridges.soffit_y(b, RULES, 0.95, span), 8.0, 0.001)
	# 80 m of water at most 20 m an arch: 4 arches of 20 m, piers between
	# them at t = 0.3, 0.5, 0.7 standing on the foot
	assert_almost_eq(Map3DBridges.soffit_y(b, RULES, 0.5, span), 8.0, 0.001)
	# an arch's middle rises toward the deck's underside, never above it
	var mid := Map3DBridges.soffit_y(b, RULES, 0.2, span)
	var under := Map3DBridges.deck_y(12.0, 12.0, 17.0, 0.2) - 1.5
	assert_true(mid > 10.0 and mid <= under + 0.001, "arch crown %f under deck %f" % [mid, under])


func test_the_mesh_is_one_surface_of_lit_quads() -> void:
	var road := PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])
	var plan := Map3DBridges.plan([road], _river(), _flat(12.0), RULES)
	var arrays := Map3DBridges.mesh_arrays(plan["bridges"], 9.0, RULES, 4.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_true(verts.size() > 0)
	assert_eq(verts.size() % 3, 0, "triangles")
	assert_eq(normals.size(), verts.size())
	for p in verts:
		assert_true(absf(p.z) <= 4.5 + 0.001, "inside the 9 m width")
	assert_true(Map3DBridges.mesh_arrays([], 9.0, RULES, 4.0).is_empty())


func test_a_ribbon_takes_the_deck_heights_where_given() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	var hs := PackedFloat32Array([NAN, 25.0, NAN])
	var arrays := Map3DBorders.ribbon_arrays([line], func(_xz: Vector2) -> float: return 7.0, [hs])
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts[0].y, 7.0, "the ground off the deck")
	assert_eq(verts[2].y, 25.0, "the deck's height on it")
	assert_eq(verts[4].y, 7.0)
