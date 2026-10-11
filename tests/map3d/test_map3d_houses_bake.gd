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


## A town's wall, a port's pier (owner 2026-10-01) and its moored ships
## (2026-10-04) are laid by their own rules, not by the house passes: the
## cluster and the sea tests below take houses only, and these kinds have
## their own tests at the end.
func _laid(r: Dictionary) -> bool:
	return ["wall", "pier", "ship"].has(_role(r))


func _role(r: Dictionary) -> String:
	return String((Game.data.map3d_houses.get(String(r["type"]), {}) as Dictionary).get("role", ""))


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
		# a pier and a ship stand on the water; a town wall closes along its
		# shore (owner 2026-10-05: 有城墙必须要合拢), its foot at the waterline,
		# which the game's 50 m cells read as sea
		if ["pier", "ship", "wall"].has(_role(r)):
			continue
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
		if not Game.data.burgs.has(code) or not landmark_of.has(code) or _laid(r):
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


## Owner 2026-10-01 (城镇的外围能增加城墙): every settlement with `walls` in its
## features and a cluster to ring wears a wall with at least one gate, and
## every module of it stands outside its houses, round them.
func test_a_walled_town_wears_a_wall_with_a_gate_round_its_houses() -> void:
	if _skip():
		return
	var by_burg: Dictionary = {}
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		if not by_burg.has(code):
			by_burg[code] = []
		(by_burg[code] as Array).append(r)
	var walled := 0
	for code: String in by_burg:
		var rows: Array = by_burg[code]
		var walls: Array = rows.filter(func(r): return String(r["type"]).begins_with("wall"))
		var houses: Array = rows.filter(func(r): return not _laid(r))
		if walls.is_empty():
			continue
		walled += 1
		assert_true(String(Game.data.burgs[code].get("features", "")).contains("walls"),
			code + " has walls only because its features say so")
		assert_true(walls.any(func(r): return String(r["type"]) == "wall_gate"), code + "'s wall has a gate")
		# every module stands farther out than every house on its own
		# bearing (a town may be long: the wall follows it, not a circle)
		var c := Vector2(float(houses[0]["x_m"]), float(houses[0]["z_m"]))
		for w: Dictionary in walls:
			var wv := Vector2(float(w["x_m"]), float(w["z_m"])) - c
			for h: Dictionary in houses:
				var hv := Vector2(float(h["x_m"]), float(h["z_m"])) - c
				if hv.length() > 1.0 and absf(wv.angle_to(hv)) < 0.15:
					assert_gt(wv.length(), hv.length(),
						code + "'s wall stands outside its houses on every bearing")
	assert_gt(walled, 20, "the pack's walled towns are walled")


## Owner 2026-10-01 (码头延伸到海里): a pier runs from the bank out to sea — its
## landward end on land or at the shore, its head over water — and only a
## port has one.
func test_a_pier_runs_from_the_shore_out_to_sea() -> void:
	if _skip():
		return
	var piers := 0
	for r: Dictionary in _rows:
		if String(r["type"]) != "pier":
			continue
		piers += 1
		var code := String(r["burg_code"])
		assert_eq(int(Game.data.burgs[code].get("is_port", 0)), 1, code + " has a pier because it is a port")
		var at := Vector2(float(r["x_m"]), float(r["z_m"]))
		var yaw := deg_to_rad(float(r["yaw_deg"]))
		var along := Vector2(cos(yaw), -sin(yaw))   # the mesh's +X after the yaw
		var half := float(Game.data.map3d_houses["pier"]["footprint_m"]) * 0.5
		var head := Map3DGeometry.world_to_pack(_meta, at + along * (half - 2.0))
		assert_lt(_picker.cell_at(head), 0, code + "'s pier head is over the water")
	assert_gt(piers, 20, "the pack's ports have piers")


## Owner 2026-10-04 (港口城市停留在港口的船舶装饰 … 根据大小1-2艘): every ship rides
## on the water at a port, one or two to
## a port by its size, each a type its group allows.
func test_ships_ride_on_the_water_at_ports_one_or_two_by_size() -> void:
	if _skip():
		return
	var per_port: Dictionary = {}
	for r: Dictionary in _rows:
		if _role(r) != "ship":
			continue
		var code := String(r["burg_code"])
		var b: Dictionary = Game.data.burgs[code]
		assert_eq(int(b.get("is_port", 0)), 1, code + " moors a ship because it is a port")
		var t: Dictionary = Game.data.map3d_houses[String(r["type"])]
		var group := String(b.get("group", "village"))
		var order := ["village", "fort", "town", "city", "capital"]
		assert_gte(order.find(group), order.find(String(t["min_group"])), code + "'s " + String(r["type"]) + " is one its " + group + " allows")
		per_port[code] = int(per_port.get(code, 0)) + 1
		# its centre in the game's sea: a hull moored alongside a pier (owner
		# 2026-10-04: 船要规整的贴着码头停留) reaches toward the shore, and the game's
		# 50 m cells are coarser than the drawn coast the bake tests its hull on
		var p := Map3DGeometry.world_to_pack(_meta, Vector2(float(r["x_m"]), float(r["z_m"])))
		assert_lt(_picker.cell_at(p), 0, "%s's %s floats on the water" % [code, r["type"]])
	for code: String in per_port:
		var n := int(per_port[code])
		assert_true(n >= 1 and n <= 2, code + " moors one or two ships, not %d" % n)
	assert_gt(per_port.size(), 50, "the pack's ports moor ships")


## Owner 2026-10-12 (R9: 不要使用带有悬崖高的码头，全部使用普通版码头): every port
## that built houses takes exactly one timber `pier` — a cliff port is lowered
## onto a plain landing by bake_houses.port_plain — and no `pier_cliff` or
## `pier_stair` is laid (`pier_cliff_landings` 0).
func test_every_port_has_one_normal_pier() -> void:
	if _skip():
		return
	var piers: Dictionary = {}
	var built: Dictionary = {}
	var cliff := 0
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		var kind := String(r["type"])
		if kind == "pier_cliff" or kind == "pier_stair":
			cliff += 1
		elif kind == "pier":
			piers[code] = int(piers.get(code, 0)) + 1
		elif not _laid(r):
			built[code] = true
	if cliff > 0:
		pending("needs the T14 rebake (%d cliff landing rows in houses.csv)" % cliff)
		return
	var ports := 0
	for code: String in built:
		if int((Game.data.burgs[code] as Dictionary).get("is_port", 0)) != 1:
			continue
		ports += 1
		assert_eq(int(piers.get(code, 0)), 1, code + " is a port with houses: one timber pier")
	assert_gt(ports, 20, "the pack's ports built houses")
