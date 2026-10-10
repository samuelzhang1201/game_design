extends GutTest
## Map3DHouses: which baked houses are shown, and where (spec 2026-09-20 §3,
## redesign owner 2026-09-20). Pure — no world, no terrain, no Game beyond
## the data repository.

const RunDir := preload("res://tests/run_dir.gd")
var _csv := RunDir.dir("map3d_houses").path_join("test_map3d_houses.csv")

var _houses: Dictionary = {}


func before_all() -> void:
	Game.start_campaign(42)
	var f := FileAccess.open(_csv, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale")
	f.store_line("alpha,0,100,200,10,chapel,1.0,1.5")
	f.store_line("alpha,1,120,200,90,cottage_a,0.95,1.1")
	f.store_line("alpha,2,140,220,180,barn,0.9,0.8")
	f.store_line("beta,0,5000,200,0,chapel,1.0,1.4")
	f.store_line("beta,1,5020,200,45,cottage_a,1.0,0.9")
	f.close()
	_houses = Map3DHouses.load_csv(_csv)


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


## density v4 (owner 2026-09-21): a cluster's radius is the group's fixed
## house COUNT at that group's own ground-per-house, and the footprint is
## that radius over the built share — population plays no part in either.
func test_the_cluster_and_footprint_radius_match_the_bake_table() -> void:
	var t: Dictionary = Game.data.map3d_bake
	for group: String in ["capital", "city", "town", "fort", "village"]:
		var b := {"group": group, "population": 4900.0}
		var want: float = sqrt(float(t["house_count_%s" % group])
			* float(t["house_m2_each_%s" % group]) / PI)
		assert_almost_eq(Map3DHouses.house_radius_m(b, Game.data), want, 0.001)
		assert_almost_eq(Map3DHouses.footprint_radius_m(b, Game.data),
			want / float(t["house_built_share"]), 0.001)
		assert_eq(Map3DHouses.house_radius_m({"group": group, "population": 1.0}, Game.data),
			Map3DHouses.house_radius_m({"group": group, "population": 1e7}, Game.data),
			"the radius never moves with population")
	assert_almost_eq(Map3DHouses.house_radius_m({"group": "nonesuch"}, Game.data),
		Map3DHouses.house_radius_m({"group": "village"}, Game.data), 0.001,
		"an unknown group falls back to the village row, as the bake does")


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


## Owner 2026-10-10 (more house variants): the bake's width stretch and tint
## indices load, and a blank cell means "no stretch, hash the tint".
func test_the_bakes_stretch_and_tint_columns_load() -> void:
	var path := RunDir.dir("map3d_houses").path_join("variants.csv")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale,stretch,wall,roof")
	f.store_line("a,0,0,0,0,cottage_a,1.0,1.0,1.2,9,14")
	f.store_line("a,1,50,0,0,cottage_a,1.0,1.0,,,")
	f.close()
	var rows: Array = Map3DHouses.load_csv(path)["a"]
	assert_almost_eq(float(rows[0]["stretch"]), 1.2, 0.0001)
	assert_eq(int(rows[0]["wall"]), 9)
	assert_eq(int(rows[0]["roof"]), 14)
	assert_eq(float(rows[1]["stretch"]), 1.0)
	assert_eq(int(rows[1]["wall"]), -1)


func test_a_baked_tint_wins_over_the_position_hash() -> void:
	var h := {"at": Vector2(123.4, 567.8), "wall": 9, "roof": 14}
	assert_eq(Map3DHouses.variant_of(h, 16, 0), 9)
	assert_eq(Map3DHouses.variant_of(h, 16, 1), 14 % 16)
	assert_eq(Map3DHouses.variant_of(h, 8, 0), 1, "wrapped into a smaller table")
	assert_eq(Map3DHouses.variant_of({"at": h["at"], "wall": -1}, 16, 0), Map3DHouses.variant_of({"at": h["at"]}, 16, 0))


## The stretch widens the house along ITS OWN x (turned with the yaw), by
## hand: yaw 90 degrees puts local x on world -z... the basis x column is
## scale * stretch long, the z column scale long, the y scale * height_scale.
func test_the_stretch_widens_the_house_along_its_own_x() -> void:
	var h := {"at": Vector2.ZERO, "yaw_deg": 90.0, "scale": 2.0, "height_scale": 1.5, "stretch": 1.2}
	var t := Map3DHouses.transform_of(h, 0.0)
	assert_almost_eq(t.basis.x.length(), 2.4, 0.0001)
	assert_almost_eq(t.basis.y.length(), 3.0, 0.0001)
	assert_almost_eq(t.basis.z.length(), 2.0, 0.0001)
	assert_almost_eq(absf(t.basis.x.z), 2.4, 0.0001, "yawed a quarter turn: local x along world z")
	assert_gt(t.basis.determinant(), 0.0, "never mirrored")
	var plain := Map3DHouses.transform_of({"at": Vector2.ZERO, "yaw_deg": 90.0, "scale": 2.0, "height_scale": 1.5}, 0.0)
	assert_almost_eq(plain.basis.x.length(), 2.0, 0.0001)
