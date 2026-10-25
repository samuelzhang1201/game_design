class_name ClusterLayout
extends RefCounted
## Pure planning queries over approved projections; no state, movement or combat effects.

const ARMS: Array[String] = ["infantry", "archers", "cavalry", "artillery"]
const ARM_WORDS: Dictionary = {"infantry": "步兵", "archers": "弓兵", "cavalry": "骑兵", "artillery": "炮兵", "units": "作战单位"}

static func options(repo: DataRepository, units: Array) -> Array:
	var members: Array = _members(units)
	var counts: Dictionary = {}
	for unit: Dictionary in members:
		var arm: String = unit["arm"]
		counts[arm] = int(counts.get(arm, 0)) + 1
	var out: Array = []
	for code: String in repo.cluster_formations:
		var row: Dictionary = repo.cluster_formations[code]
		var missing: Dictionary = _missing(String(row["recipe"]), counts)
		if members.size() < 3:
			missing["units"] = 3 - members.size()
		var words: Array[String] = []
		for arm: String in missing:
			words.append("缺%d支%s" % [int(missing[arm]), String(ARM_WORDS.get(arm, arm))])
		out.append({"formation": code, "label": row["label"], "behavior": row["behavior"],
			"eligible": missing.is_empty(), "missing": missing, "reason": "；".join(words)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["eligible"] != b["eligible"]:
			return bool(a["eligible"])
		return String(a["formation"]) < String(b["formation"]))
	return out

static func layout(repo: DataRepository, formation: String, units: Array,
		origin: Vector2i, facing: int, strong_side: String) -> Dictionary:
	var out: Dictionary = {"slots": {}, "roles": {}, "missing": {}, "blocked": {}, "reason": "未知集群阵型"}
	var choice: Dictionary = {}
	for row: Dictionary in options(repo, units):
		if row["formation"] == formation:
			choice = row
	if choice.is_empty():
		return out
	out["missing"] = choice["missing"].duplicate()
	out["reason"] = choice["reason"]
	if not choice["eligible"]:
		return out
	if not strong_side in ["", "left", "right"]:
		out["reason"] = "未知强翼方向"
		return out
	var members: Array = _members(units)
	var width: int = 0
	var depth: int = 0
	for unit: Dictionary in members:
		var footprint: Variant = unit.get("footprint")
		if not footprint is Vector2i or footprint.x <= 0 or footprint.y <= 0:
			out["blocked"][unit["unit"]] = "缺少有效固定占地"
			continue
		width = maxi(width, footprint.x)
		depth = maxi(depth, footprint.y)
	var templates: Dictionary = {}
	var min_depth: int = 0
	var max_depth: int = 0
	for row: Dictionary in repo.cluster_slots:
		if row["formation"] != formation:
			continue
		var arm: String = row["arm"]
		if not templates.has(arm):
			templates[arm] = []
		templates[arm].append(row)
		min_depth = mini(min_depth, int(row["depth"]))
		max_depth = maxi(max_depth, int(row["depth"]))
	for arm: String in templates:
		templates[arm].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			for key: String in ["priority", "lateral", "depth"]:
				if int(a[key]) != int(b[key]):
					return int(a[key]) < int(b[key])
			return String(a["role"]) < String(b["role"]))
	var used: Dictionary = {}
	for unit: Dictionary in members:
		var code: String = unit["unit"]
		if out["blocked"].has(code):
			continue
		var arm: String = unit["arm"]
		var rows: Array = templates.get(arm, [])
		if rows.is_empty():
			out["blocked"][code] = "缺少兵种阵位"
			continue
		var index: int = int(used.get(arm, 0))
		used[arm] = index + 1
		var row: Dictionary = rows[index % rows.size()]
		@warning_ignore("integer_division")
		var band: int = index / rows.size()
		var lateral: int = int(row["lateral"])
		if formation == "strong_wing" and strong_side == "right":
			lateral = -lateral
		# Whole extra template bands retain roles and sit adjacent behind the original.
		var rear: int = int(row["depth"]) - band * (max_depth - min_depth + 1)
		var local: Vector2 = Vector2(rear * depth * 2, lateral * width * 2)
		var rotated: Vector2 = local.rotated(deg_to_rad(float(posmod(facing, 360))))
		out["slots"][code] = origin + Vector2i(roundi(rotated.x), roundi(rotated.y))
		out["roles"][code] = row["role"]
	if not out["blocked"].is_empty():
		out["reason"] = "部分单位没有有效规划阵位"
	return out

static func _members(units: Array) -> Array:
	var by_code: Dictionary = {}
	var conflicts: Dictionary = {}
	for value: Variant in units:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var code: String = String(row.get("unit", ""))
		if code.is_empty() or not String(row.get("arm", "")) in ARMS \
				or not bool(row.get("controllable", false)) or int(row.get("fit", 0)) <= 0:
			continue
		if by_code.has(code) and by_code[code] != row:
			conflicts[code] = true
		by_code[code] = row
	var codes: Array = by_code.keys()
	codes.sort()
	var out: Array = []
	for code: String in codes:
		if not conflicts.has(code):
			out.append(by_code[code])
	return out

static func _missing(recipe: String, counts: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_count: int = -1
	for alternative: String in recipe.split("|"):
		var missing: Dictionary = {}
		var total: int = 0
		for term: String in alternative.split("+"):
			var pair: PackedStringArray = term.split(":")
			if pair.size() != 2 or not pair[0] in ARMS or not pair[1].is_valid_int() or int(pair[1]) <= 0:
				return {"recipe": 1}
			var deficit: int = maxi(0, int(pair[1]) - int(counts.get(pair[0], 0)))
			if deficit > 0:
				missing[pair[0]] = deficit
				total += deficit
		if best_count < 0 or total < best_count:
			best = missing
			best_count = total
	return best
