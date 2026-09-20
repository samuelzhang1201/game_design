extends GutTest
## The baked houses of the default pack (spec 2026-09-20 §7). The headline
## assertion is the owner's: NO HOUSE STANDS IN THE SEA
## ("定居点的房屋模型不可以出现在海上"). A checkout with no 3D build skips.

var _rows: Array = []
var _meta: Dictionary = {}
var _picker: Map3DPicker


func before_all() -> void:
	Game.start_campaign(42)
	var dir := Game.data.map3d_dir()
	var path := dir + "/bake/houses.csv"
	if not FileAccess.file_exists(path):
		return
	_rows = DataRepository.parse_csv(path,
		["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale"])
	var manifest := dir + "/manifest.json"
	if FileAccess.file_exists(manifest):
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		_meta = m.get("meta", {})
	var ctx := Map3DContext.new(Game.data, _meta)
	# Map3DPicker has no _init; map3d_view.gd:77 is the pattern (ruling P3)
	_picker = Map3DPicker.new()
	_picker.ctx = ctx


func _skip() -> bool:
	if _rows.is_empty() or _meta.is_empty():
		pass_test("no 3D build in this checkout (tools/map3d/build_pack.sh) — skipped")
		return true
	return false


func test_no_house_stands_in_the_sea() -> void:
	if _skip():
		return
	var wet := 0
	var worst := ""
	for r: Dictionary in _rows:
		var pack := Map3DGeometry.world_to_pack(_meta,
			Vector2(float(r["x_m"]), float(r["z_m"])))
		if _picker.cell_at(pack) < 0:
			wet += 1
			if worst == "":
				worst = "%s rank %s at pack %s" % [r["burg_code"], r["rank"], pack]
	assert_eq(wet, 0, "every one of %d houses is on land; first wet: %s" % [_rows.size(), worst])


func test_every_house_is_inside_its_own_cluster() -> void:
	if _skip():
		return
	var ratio: float = Game.data.map3d_bake["house_radius_ratio"]
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		assert_true(Game.data.burgs.has(code), code + " is a burg of this pack")
		if not Game.data.burgs.has(code):
			continue
		var b: Dictionary = Game.data.burgs[code]
		var centre := Map3DGeometry.pack_to_world(_meta,
			Vector2(float(b["x"]), float(b["y"])))
		var at := Vector2(float(r["x_m"]), float(r["z_m"]))
		# Map3DHouses arrives in Task 5; until then this assertion cannot
		# parse (2026-09-20, task 4 note — restore in Task 5):
		# var r_foot := Map3DHouses.footprint_radius_m(float(b.get("population", 0)), Game.data)
		# assert_lte(at.distance_to(centre), ratio * r_foot + 0.5,
		# 	code + " rank " + String(r["rank"]) + " is inside the house radius")
		pass


func test_rank_is_dense_and_starts_at_a_landmark() -> void:
	if _skip():
		return
	var by_burg: Dictionary = {}
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		if not by_burg.has(code):
			by_burg[code] = []
		(by_burg[code] as Array).append(r)
	for code: String in by_burg:
		var rows: Array = by_burg[code]
		rows.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
		for i in rows.size():
			assert_eq(int(rows[i]["rank"]), i, code + "'s ranks are dense")
		var first := String(rows[0]["type"])
		assert_eq(String(Game.data.map3d_houses[first]["role"]), "landmark",
			code + " starts with its landmark")


func test_every_type_used_is_in_the_table() -> void:
	if _skip():
		return
	for r: Dictionary in _rows:
		assert_true(Game.data.map3d_houses.has(String(r["type"])),
			String(r["type"]) + " is a known house type")
