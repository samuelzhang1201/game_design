extends GutTest
## Map3DHouses: which baked houses are shown, and where (spec 2026-09-20 §3).
## Pure — no world, no terrain, no Game beyond the data repository.

const CSV := "user://test_map3d_houses.csv"

var _houses: Dictionary = {}


func before_all() -> void:
	Game.start_campaign(42)
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale")
	f.store_line("alpha,0,100,200,10,chapel,1.0")
	f.store_line("alpha,1,120,200,90,cottage_a,0.95")
	f.store_line("alpha,2,140,220,180,barn,0.9")
	f.store_line("beta,0,5000,200,0,chapel,1.0")
	f.store_line("beta,1,5020,200,45,cottage_a,1.0")
	f.close()
	_houses = Map3DHouses.load_csv(CSV)


func test_the_csv_loads_grouped_by_burg_and_sorted_by_rank() -> void:
	assert_eq(_houses.size(), 2)
	var alpha: Array = _houses["alpha"]
	assert_eq(alpha.size(), 3)
	assert_eq(int(alpha[0]["rank"]), 0)
	assert_eq(alpha[0]["at"], Vector2(100, 200))
	assert_eq(String(alpha[2]["type"]), "barn")


func test_a_missing_file_is_empty_not_an_error() -> void:
	assert_eq(Map3DHouses.load_csv("user://no_such_houses.csv"), {})


func test_shown_count_follows_people_and_its_cap() -> void:
	var town := {"group": "town"}
	var per: float = Game.data.map3d_bake["house_people_per_house"]
	assert_eq(Map3DHouses.shown_count(town, per * 10.0, Game.data), 10)
	assert_eq(Map3DHouses.shown_count(town, 1.0, Game.data),
		int(Game.data.map3d_bake["house_min"]), "never fewer than house_min")
	assert_eq(Map3DHouses.shown_count({"group": "village"}, 1.0e9, Game.data),
		int(Game.data.map3d_bake["house_max_village"]), "capped by its group")


func test_a_settlement_out_of_range_is_not_instanced_at_all() -> void:
	var pos := {"alpha": Vector2(100, 200), "beta": Vector2(5000, 200)}
	var people := func(_c: String) -> float: return 100000.0
	var out := Map3DHouses.visible_set(_houses, Game.data, pos, people,
		Vector2(100, 200), 1000.0, 9999)
	var seen := _codes(out)
	assert_true(seen.has("alpha"), "the near settlement is built")
	assert_false(seen.has("beta"), "the far one is not built at all, not culled after")


func test_the_budget_drops_the_farthest_settlements_first() -> void:
	var pos := {"alpha": Vector2(100, 200), "beta": Vector2(5000, 200)}
	var people := func(_c: String) -> float: return 100000.0
	var out := Map3DHouses.visible_set(_houses, Game.data, pos, people,
		Vector2(100, 200), 100000.0, 3)
	var seen := _codes(out)
	assert_true(seen.has("alpha"), "the near settlement keeps its houses")
	assert_false(seen.has("beta"), "the far one is dropped whole, never half-built")


func test_the_result_is_bucketed_by_type() -> void:
	var pos := {"alpha": Vector2(100, 200)}
	var people := func(_c: String) -> float: return 100000.0
	var out := Map3DHouses.visible_set(_houses, Game.data, pos, people,
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
