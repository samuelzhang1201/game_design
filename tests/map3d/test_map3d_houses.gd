extends GutTest
## Map3DHouses: which baked houses are shown, and where (spec 2026-09-20 §3,
## redesign owner 2026-09-20). Pure — no world, no terrain, no Game beyond
## the data repository.

const CSV := "user://test_map3d_houses.csv"

var _houses: Dictionary = {}


func before_all() -> void:
	Game.start_campaign(42)
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale")
	f.store_line("alpha,0,100,200,10,chapel,1.0,1.5")
	f.store_line("alpha,1,120,200,90,cottage_a,0.95,1.1")
	f.store_line("alpha,2,140,220,180,barn,0.9,0.8")
	f.store_line("beta,0,5000,200,0,chapel,1.0,1.4")
	f.store_line("beta,1,5020,200,45,cottage_a,1.0,0.9")
	f.close()
	_houses = Map3DHouses.load_csv(CSV)


func test_the_csv_loads_grouped_by_burg_and_sorted_by_rank() -> void:
	assert_eq(_houses.size(), 2)
	var alpha: Array = _houses["alpha"]
	assert_eq(alpha.size(), 3)
	assert_eq(int(alpha[0]["rank"]), 0)
	assert_eq(alpha[0]["at"], Vector2(100, 200))
	assert_eq(String(alpha[2]["type"]), "barn")
	assert_almost_eq(float(alpha[0]["height_scale"]), 1.5, 0.001)


func test_a_missing_file_is_empty_not_an_error() -> void:
	assert_eq(Map3DHouses.load_csv("user://no_such_houses.csv"), {})


## shown_count() / max_houses() are gone (redesign owner 2026-09-20): a
## settlement's house count is now a bake-time target by its KIND
## (house_count_<group> in map3d_bake.csv), not something derived from its
## live population at runtime, so there is nothing left for either function
## to compute at this layer. visible_set() now shows every baked house of a
## settlement it decides to build at all.
func test_visible_set_shows_every_baked_house_of_a_built_settlement() -> void:
	var pos := {"alpha": Vector2(100, 200)}
	var out := Map3DHouses.visible_set(_houses, Game.data, pos,
		Vector2(100, 200), 1000.0, 9999)
	assert_eq(_total(out), 3, "all three of alpha's baked houses are shown, uncapped by people")


func test_a_settlement_out_of_range_is_not_instanced_at_all() -> void:
	var pos := {"alpha": Vector2(100, 200), "beta": Vector2(5000, 200)}
	var out := Map3DHouses.visible_set(_houses, Game.data, pos,
		Vector2(100, 200), 1000.0, 9999)
	var seen := _codes(out)
	assert_true(seen.has("alpha"), "the near settlement is built")
	assert_false(seen.has("beta"), "the far one is not built at all, not culled after")


func test_the_budget_drops_the_farthest_settlements_first() -> void:
	var pos := {"alpha": Vector2(100, 200), "beta": Vector2(5000, 200)}
	var out := Map3DHouses.visible_set(_houses, Game.data, pos,
		Vector2(100, 200), 100000.0, 3)
	var seen := _codes(out)
	assert_true(seen.has("alpha"), "the near settlement keeps its houses")
	assert_false(seen.has("beta"), "the far one is dropped whole, never half-built")


func test_the_result_is_bucketed_by_type() -> void:
	var pos := {"alpha": Vector2(100, 200)}
	var out := Map3DHouses.visible_set(_houses, Game.data, pos,
		Vector2(100, 200), 100000.0, 9999)
	for type: String in out:
		for h: Dictionary in out[type]:
			assert_eq(String(h["type"]), type, "every row is in its own bucket")


func test_footprint_radius_matches_the_bake_table() -> void:
	var r := Map3DHouses.footprint_radius_m(4900.0, Game.data)
	var want: float = clampf(
		Game.data.map3d_bake["footprint_m_per_sqrt_pop"] * sqrt(4900.0),
		Game.data.map3d_bake["footprint_min_m"], Game.data.map3d_bake["footprint_max_m"])
	assert_almost_eq(r, want, 0.001)


func _codes(buckets: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for type: String in buckets:
		for h: Dictionary in buckets[type]:
			out[String(h["burg_code"])] = true
	return out


func _total(buckets: Dictionary) -> int:
	var n := 0
	for type: String in buckets:
		n += (buckets[type] as Array).size()
	return n
