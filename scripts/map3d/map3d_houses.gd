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


## The built ground's radius in metres — the bake's own formula, so the
## runtime and the bake agree on where a cluster ends.
static func footprint_radius_m(population: float, repo: DataRepository) -> float:
	var t: Dictionary = repo.map3d_bake
	return clampf(float(t["footprint_m_per_sqrt_pop"]) * sqrt(maxf(population, 0.0)),
		float(t["footprint_min_m"]), float(t["footprint_max_m"]))


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
