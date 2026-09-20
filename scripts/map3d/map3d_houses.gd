class_name Map3DHouses
extends RefCounted
## Which of a settlement's baked houses are shown, and where (spec
## 2026-09-20 §3). Pure and static: the bake decided WHERE every house
## stands; this decides HOW MANY of them a settlement shows right now (its
## people) and WHICH settlements are near enough to build at all.
##
## Never reaches for the Game autoload — tests/map3d/test_map3d_preview.gd
## scans this directory for it.

const COLUMNS := ["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale"]


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


## The most houses this settlement's group ever shows.
static func max_houses(group: String, repo: DataRepository) -> int:
	var t: Dictionary = repo.map3d_bake
	var key := "house_max_" + group
	return int(t[key]) if t.has(key) else int(t["house_max_village"])


## How many of the baked houses a settlement shows: one per
## house_people_per_house souls, at least house_min, capped by its group. A
## settlement that grows sprouts more houses with no re-bake.
static func shown_count(burg: Dictionary, people: float, repo: DataRepository) -> int:
	var t: Dictionary = repo.map3d_bake
	var n := int(round(people / maxf(float(t["house_people_per_house"]), 1.0)))
	return mini(maxi(n, int(t["house_min"])),
		max_houses(String(burg.get("group", "village")), repo))


## The houses to instance now, bucketed by type.
## `burg_pos` is {code: world XZ}, `people_of` a Callable(String) -> float.
## A settlement past `view_m` is not built at all; over `budget`, whole
## settlements are dropped farthest first — never half a village.
static func visible_set(houses: Dictionary, repo: DataRepository, burg_pos: Dictionary,
		people_of: Callable, camera_xz: Vector2, view_m: float, budget: int) -> Dictionary:
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
		var burg: Dictionary = repo.burgs.get(code, {})
		var rows: Array = houses[code]
		var want := mini(shown_count(burg, float(people_of.call(code)), repo), rows.size())
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
