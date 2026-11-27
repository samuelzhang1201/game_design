extends RefCounted
## The opening regiments of the game's own arms (data/army/game_arm_starts.csv; spec
## docs/superpowers/specs/2026-11-20-heavy-infantry-arm-design.md, "Opening regiments"; the share
## rule: 2026-11-26-militia-arm-design.md): which
## kingdom gets how many, how large, standing where. Pure and deterministic (fixed order, whole
## numbers but for the pack's own coordinates), so tools/import_azgaar.gd writes the same rows on
## every import and `--starts-only` re-derives them on a committed pack. The rule itself is the
## table's notes.

const COLUMNS: Array[String] = ["arm", "units_min", "units_max", "men_min", "men_max", "men_step",
	"avg_strongest", "avg_weakest", "share_permille", "total_min", "place", "offset_km", "bearings", "code_word", "label_word"]
## How many rings of `offset_km` a regiment may move out before the rule gives up.
const MAX_RINGS := 64


## The table's rows, typed: {"rules": [...]} or {"error": ...}.
static func rules(data: String) -> Dictionary:
	DataRepository.last_error = ""
	var path := DataRepository.table_path(data, "game_arm_starts")
	var rows := DataRepository.parse_csv(path, COLUMNS)
	if DataRepository.last_error != "":
		return {"error": "cannot read %s: %s" % [path, DataRepository.last_error]}
	var out: Array = []
	for row: Dictionary in rows:
		var rule := {"arm": String(row["arm"]), "place": String(row["place"]),
			"code_word": String(row["code_word"]), "label_word": String(row["label_word"]),
			"offset_km": float(row["offset_km"]), "bearings": []}
		for key: String in ["units_min", "units_max", "men_min", "men_max", "men_step", "avg_strongest", "avg_weakest",
				"share_permille", "total_min"]:
			rule[key] = int(row[key])
		for b: String in String(row["bearings"]).split(";", false):
			rule["bearings"].append(float(b))
		if rule["place"] != "largest_towns" or int(rule["men_step"]) <= 0 or rule["bearings"].is_empty() \
				or int(rule["units_min"]) > int(rule["units_max"]) or int(rule["men_min"]) > int(rule["men_max"]) \
				or int(rule["share_permille"]) < 0 or int(rule["total_min"]) < 0:
			return {"error": "%s: malformed rule for %s" % [path, rule["arm"]]}
		out.append(rule)
	return {"rules": out}


## The regiments the rules add. `kingdoms`: [{code, strength, army}] in table order (strength the
## export's, before these regiments; army the men of its non-naval regiments already written, read
## only by a share rule, which also counts the rows of the rules before it); `burgs`: [{burg_code, label, province_code, kingdom_code,
## population, x, y}]; `taken`: the positions (pack px) of the regiments already written;
## `codes`: the regiment codes already used. Returns {"rows": [{regiment_code, kingdom_code,
## province_code, label, x, y, arm, men}], "skipped": [kingdom codes with no town]} or {"error"}.
static func plan(rules: Array, kingdoms: Array, burgs: Array, taken: Array, metres_per_px: int,
		codes: Dictionary) -> Dictionary:
	var placed: Array = taken.duplicate()
	var rows: Array = []
	var skipped: Array = []
	var towns := {}  # kingdom -> its burgs, largest first, ties by code
	for b: Dictionary in burgs:
		var k := String(b["kingdom_code"])
		if not towns.has(k):
			towns[k] = []
		towns[k].append(b)
	for k: String in towns:
		(towns[k] as Array).sort_custom(func(a: Dictionary, z: Dictionary) -> bool:
			return int(a["population"]) > int(z["population"]) or (int(a["population"]) == int(z["population"])
				and String(a["burg_code"]) < String(z["burg_code"])))
	var hundredths := {}
	for king: Dictionary in kingdoms:
		hundredths[String(king["code"])] = roundi(float(king["strength"]) * 100.0)
	var ranked: Array = kingdoms.map(func(king: Dictionary) -> String: return String(king["code"]))
	ranked.sort_custom(func(a: String, z: String) -> bool:
		return int(hundredths[a]) > int(hundredths[z]) or (int(hundredths[a]) == int(hundredths[z]) and a < z))
	var upper := (ranked.size() + 1) / 2
	var top: int = hundredths[ranked[0]] if not ranked.is_empty() else 0
	var bottom: int = hundredths[ranked[-1]] if not ranked.is_empty() else 0
	var army := {}
	for king: Dictionary in kingdoms:
		army[String(king["code"])] = int(king.get("army", 0))
	for rule: Dictionary in rules:
		var share := int(rule.get("share_permille", 0)) > 0
		var raised := {}  # this rule's men, counted into the army only for the rules after it
		for king: Dictionary in kingdoms:
			var k := String(king["code"])
			var list: Array = towns.get(k, [])
			if list.is_empty():
				if not skipped.has(k):
					skipped.append(k)
				continue
			var n := int(rule["units_max"]) if ranked.find(k) < upper else int(rule["units_min"])
			for i in n:
				var town: Dictionary = list[i] if i < list.size() else list[0]
				var men := share_size_of(rule, int(army[k]), i, n) if share \
					else size_of(rule, int(hundredths[k]), top, bottom, i, n)
				raised[k] = int(raised.get(k, 0)) + men
				var at := spot(Vector2(float(town["x"]), float(town["y"])), placed, rule, metres_per_px)
				if at.x < 0.0:
					return {"error": "no clear place near %s for %s" % [town["burg_code"], k]}
				var ordinal := ordinal_of(i + 1)
				var code := "%s_%s_%s_%s" % [k, ordinal, rule["code_word"], town["burg_code"]]
				if codes.has(code):
					return {"error": "regiment code %s is taken" % code}
				codes[code] = true
				placed.append(at)
				rows.append({"regiment_code": code, "kingdom_code": k, "province_code": String(town["province_code"]),
					"label": "%s (%s) %s" % [ordinal, town["label"], rule["label_word"]], "x": at.x, "y": at.y,
					"arm": String(rule["arm"]), "men": men})
		for k: String in raised:
			army[k] = int(army[k]) + int(raised[k])
	return {"rows": rows, "skipped": skipped}


## Men in the `i`-th of a kingdom's `n` regiments: its average (linear in strength, in hundredths,
## from avg_weakest at `bottom` to avg_strongest at `top`), the first one men_step above it and the
## last one below, rounded half up to men_step and clamped. Whole numbers throughout.
static func size_of(rule: Dictionary, strength: int, top: int, bottom: int, i: int, n: int) -> int:
	var step := int(rule["men_step"])
	var offset := 0
	if n > 1 and i == 0:
		offset = step
	elif n > 1 and i == n - 1:
		offset = -step
	var span := top - bottom
	var weak := int(rule["avg_weakest"])
	var strong := int(rule["avg_strongest"])
	var size := strong + offset
	if span > 0:  # size = (weak * span + (strong - weak) * (strength - bottom) + offset * span) / span
		var num := (weak + offset) * span + (strong - weak) * (strength - bottom)
		@warning_ignore("integer_division")
		size = (2 * num + step * span) / (2 * step * span) * step
	else:
		@warning_ignore("integer_division")
		size = (2 * size + step) / (2 * step) * step
	return clampi(size, int(rule["men_min"]), int(rule["men_max"]))


## Men in the `i`-th of a kingdom's `n` regiments under a share rule (share_permille > 0): the
## kingdom's total T = max(army x share_permille / 1000, total_min) rounded half up to men_step,
## base = T / n rounded half up to men_step, the first regiment men_step above it and the last one
## below, each clamped. Whole numbers throughout.
static func share_size_of(rule: Dictionary, army: int, i: int, n: int) -> int:
	var step := int(rule["men_step"])
	var thousandths := maxi(army * int(rule["share_permille"]), int(rule["total_min"]) * 1000)
	@warning_ignore("integer_division")
	var total := (2 * thousandths + step * 1000) / (2 * step * 1000) * step
	@warning_ignore("integer_division")
	var size := (2 * total + step * n) / (2 * step * n) * step
	if n > 1 and i == 0:
		size += step
	elif n > 1 and i == n - 1:
		size -= step
	return clampi(size, int(rule["men_min"]), int(rule["men_max"]))


## The first place, from `town` outward, no nearer than offset_km to any of `placed`: ring k = 0
## (the town itself), then k = 1, 2, ... at k x offset_km along each bearing in order; coordinates
## rounded to hundredths, as the pack writes them. (-1, -1) when MAX_RINGS are full.
static func spot(town: Vector2, placed: Array, rule: Dictionary, metres_per_px: int) -> Vector2:
	var gap := float(rule["offset_km"]) * 1000.0 / float(maxi(1, metres_per_px))
	for k in MAX_RINGS + 1:
		var bearings: Array = [0.0] if k == 0 else rule["bearings"]
		for deg: float in bearings:
			var a := deg_to_rad(deg)
			var p := town + Vector2(cos(a), sin(a)) * gap * k
			p = Vector2(roundf(p.x * 100.0) / 100.0, roundf(p.y * 100.0) / 100.0)
			var clear := true
			for q: Vector2 in placed:
				if p.distance_to(q) < gap:
					clear = false
					break
			if clear:
				return p
	return Vector2(-1, -1)


## 1 -> "1st", 2 -> "2nd", 11 -> "11th", 22 -> "22nd".
static func ordinal_of(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]
