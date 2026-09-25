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
		["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale", "height_scale"])
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


## Owner 2026-09-25 (标志性建筑要在中间附近): a settlement is laid out round
## its LANDMARK's own spot (rank 0), which moves off water or a slope, and
## its cluster is the group's house radius grown by the landmark's square.
func test_every_house_is_inside_its_own_cluster() -> void:
	if _skip():
		return
	var landmark_of: Dictionary = {}
	for r: Dictionary in _rows:
		if int(r["rank"]) == 0:
			landmark_of[String(r["burg_code"])] = r
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		assert_true(Game.data.burgs.has(code), code + " is a burg of this pack")
		if not Game.data.burgs.has(code) or not landmark_of.has(code):
			continue
		var b: Dictionary = Game.data.burgs[code]
		var lm: Dictionary = landmark_of[code]
		var centre := Vector2(float(lm["x_m"]), float(lm["z_m"]))
		var at := Vector2(float(r["x_m"]), float(r["z_m"]))
		# the bake's own cluster radius: the group's fixed house count at that
		# group's density plus the landmark's square — the runtime and the
		# bake read the ONE formula, which is what this re-derivation holds
		var r_cluster := Map3DHouses.cluster_radius_m(b, Game.data, String(lm["type"]))
		assert_lte(at.distance_to(centre), r_cluster + 0.5,
			code + " rank " + String(r["rank"]) + " is inside its cluster round the landmark")


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
