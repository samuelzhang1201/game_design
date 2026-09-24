class_name Map3DHouses
extends RefCounted
## Which of a settlement's baked houses are shown, and where (spec
## 2026-09-20 §3, redesign owner 2026-09-20). Pure and static: the bake
## decided WHERE every house stands AND HOW MANY — a settlement's house
## count is now a target picked at bake time by its KIND (village / fort /
## town / city / capital, `house_count_<group>` in map3d_bake.csv), never by
## its live population — so this only decides WHICH settlements are near
## enough to build at all, and drops whole settlements, farthest first, to
## stay inside the instance budget.
##
## Never reaches for the Game autoload — tests/map3d/test_map3d_preview.gd
## scans this directory for it.

const COLUMNS := ["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale", "height_scale"]


## The bake's houses.csv, grouped by burg and sorted by rank. A missing file
## is {} — a build without houses draws none, as the other optional bake
## inputs do.
static func load_csv(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var rows := DataRepository.parse_csv(path, COLUMNS)
	if DataRepository.last_error != "":
		return {}
	var out: Dictionary = {}
	for r: Dictionary in rows:
		var code := String(r["burg_code"])
		if not out.has(code):
			out[code] = []
		(out[code] as Array).append({
			"burg_code": code,
			"rank": int(r["rank"]),
			"at": Vector2(float(r["x_m"]), float(r["z_m"])),
			"yaw_deg": float(r["yaw_deg"]),
			"type": String(r["type"]),
			"scale": float(r["scale"]),
			"height_scale": float(r["height_scale"]),
		})
	for code: String in out:
		(out[code] as Array).sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	return out


## A settlement's house-cluster radius in metres — the bake's own formula
## (tools/map3d/bake_houses.py's house_radius_m), so the runtime and the
## bake agree on where a cluster ends: sqrt(count * m2_each / pi), both the
## count (house_count_<group>) and the ground per house
## (house_m2_each_<group>) fixed by the burg's own GROUP, never by its
## population (owner 2026-09-21, density v4).
static func house_radius_m(burg: Dictionary, repo: DataRepository) -> float:
	var t: Dictionary = repo.map3d_bake
	var group := String(burg.get("group", "village"))
	var n := float(t.get("house_count_%s" % group, t["house_count_village"]))
	var m2 := float(t.get("house_m2_each_%s" % group, t["house_m2_each_village"]))
	return sqrt(maxf(n, 0.0) * m2 / PI)


## The built ground's radius in metres — the house cluster grown out by its
## buffer ring, `house_built_share` the cluster's own share of it, as the
## bake paints it.
static func footprint_radius_m(burg: Dictionary, repo: DataRepository) -> float:
	return house_radius_m(burg, repo) / float(repo.map3d_bake["house_built_share"])


## The houses to instance now, bucketed by type. `burg_pos` is {code: world
## XZ}. A settlement past `view_m` is not built at all; over `budget`, whole
## settlements are dropped farthest first — never half a village. Every
## settlement that IS built shows every house the bake gave it: the bake's
## own house_count_<group> already decided how many that is, so there is no
## further thinning by population here (redesign owner 2026-09-20).
static func visible_set(houses: Dictionary, repo: DataRepository, burg_pos: Dictionary,
		camera_xz: Vector2, view_m: float, budget: int) -> Dictionary:
	var near: Array = []
	for code: String in houses:
		if not burg_pos.has(code):
			continue
		var d: float = (burg_pos[code] as Vector2).distance_to(camera_xz)
		if d > view_m:
			continue
		near.append({"code": code, "d": d})
	near.sort_custom(func(a, b): return a["d"] < b["d"] if a["d"] != b["d"] else a["code"] < b["code"])
	var out: Dictionary = {}
	var used := 0
	for e: Dictionary in near:
		var code: String = e["code"]
		var rows: Array = houses[code]
		var want := rows.size()
		if used + want > budget:
			break
		for i in want:
			var h: Dictionary = rows[i]
			var type: String = h["type"]
			if not out.has(type):
				out[type] = []
			(out[type] as Array).append(h)
		used += want
	return out


## The ground under a house (owner 2026-09-24: on a slope part of the house
## was buried in the hill, as the wargame pieces had been). A building cannot
## tilt with the ground as a piece does — walls stand plumb — so it stands on
## the HIGHEST of its footprint's four corners and its centre, and nothing of
## it is buried beyond map3d_house_sink_m; the downhill side, which that
## leaves in the air, stands on a stone foundation (plinth_of) reaching below
## the LOWEST of them, as a house on a real hillside does. Returns
## Vector3(lowest, highest, the centre's). The footprint is the mesh's own AABB shrunk by
## `inset`, turned and scaled as the house is. Pure: `height_at` is world XZ
## -> metres.
static func ground_under(h: Dictionary, box: AABB, inset: float,
		height_at: Callable) -> Vector3:
	var lo := INF
	var hi := -INF
	var pts := footprint_of(h, box, inset)
	for c in pts:
		var y := float(height_at.call(c))
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector3(lo, hi, float(height_at.call(pts[0])))


## Where a house stands on ground_under's Vector3(lowest, highest, centre):
## the highest corner, but never more than `max_rise` above the lowest, and
## never below its own centre's ground (where every house stood before). On a
## steep site (the capital's palace on a sea cliff: 20 m and more across its
## footprint) standing on the top corner lifted the whole building onto a
## tower of stone, and "lowest + max_rise" alone sank it towards the sea;
## there the uphill wall bites into the hill instead, as a real hillside
## building's does. Returns Vector2(lowest, seat).
static func seat(ground: Vector3, max_rise: float) -> Vector2:
	return Vector2(ground.x, minf(ground.y, maxf(ground.z, ground.x + max_rise)))


## The world XZ of a house's footprint corners and centre (see ground_under).
static func footprint_of(h: Dictionary, box: AABB, inset: float) -> PackedVector2Array:
	var at: Vector2 = h["at"]
	var s: float = float(h["scale"])
	var turn := Basis(Vector3.UP, deg_to_rad(float(h["yaw_deg"])))
	var c := box.get_center()
	var hx := box.size.x * 0.5 * inset
	var hz := box.size.z * 0.5 * inset
	var out := PackedVector2Array()
	for local in [Vector3(c.x, 0, c.z), Vector3(c.x - hx, 0, c.z - hz), Vector3(c.x + hx, 0, c.z - hz),
			Vector3(c.x + hx, 0, c.z + hz), Vector3(c.x - hx, 0, c.z + hz)]:
		var w: Vector3 = turn * (local * s)
		out.append(at + Vector2(w.x, w.z))
	return out


## The foundation under a house on a slope: a unit box turned with the house,
## `inset` of its footprint (so its faces stay under the walls — a
## foundation, never a base plate out past them), from just inside the
## house's floor down to `below` metres under the lowest corner.
static func plinth_of(h: Dictionary, box: AABB, inset: float, ground: Vector2,
		sink: float, below: float) -> Transform3D:
	var at: Vector2 = h["at"]
	var s: float = float(h["scale"])
	var turn := Basis(Vector3.UP, deg_to_rad(float(h["yaw_deg"])))
	var top := ground.y - sink + 0.25
	var bottom := ground.x - below
	var centre: Vector3 = turn * (Vector3(box.get_center().x, 0, box.get_center().z) * s)
	var basis := turn.scaled(Vector3(box.size.x * s * inset, top - bottom, box.size.z * s * inset))
	return Transform3D(basis, Vector3(at.x + centre.x, (top + bottom) * 0.5, at.y + centre.z))
