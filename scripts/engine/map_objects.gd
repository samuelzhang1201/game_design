class_name MapObjects
extends RefCounted
## The world map's interactive objects (spec 2026-09-08): what lies under a
## point, which town pins show at a given zoom, and the text on each info
## card. Pure functions over a DataRepository and the pack's index bitmaps —
## no Nodes, no RNG, no game state — so GUT can pin every rule headless.
## Coordinates are native map px; the view converts screen radii by its scale.

## min_burg_pop sentinel: only capitals get pins.
const CAPITALS_ONLY := -1

const GROUP_WORDS := {"roads": "Road", "trails": "Trail", "searoutes": "Sea route"}
const FEATURE_WORDS := {"walls": "Walled", "citadel": "Citadel", "temple": "Temple",
	"plaza": "Plaza", "shanty": "Shanty town"}
## Tie-break among lines at the same distance: the more significant one wins.
const LINE_RANK := {"roads": 0, "trails": 1, "searoutes": 2}
const RIVER_RANK := 3
## Distances closer than this are "the same" for the tie-break (native px).
const LINE_TIE_EPS := 0.001

## LOD rule from balance.csv. view_scale = screen px per native map px.
static func min_burg_pop_for_scale(repo: DataRepository, view_scale: float) -> int:
	if view_scale >= repo.bal("map_lod_village_scale"):
		return 0
	if view_scale >= repo.bal("map_lod_town_scale"):
		return int(repo.bal("map_lod_town_pop"))
	return CAPITALS_ONLY

static func burg_visible(b: Dictionary, min_pop: int) -> bool:
	if String(b.get("is_capital", "0")) == "1":
		return true
	if min_pop < 0:
		return false
	return int(float(b.get("population", "0"))) >= min_pop

## Priority: nearest pin (markers, then LOD-visible burgs) within pick_radius,
## else nearest line (routes, then rivers) within line_radius, else the land
## under the point (ids from the three bitmaps), else water.
static func object_at(repo: DataRepository, state_img: Image, province_img: Image,
		biome_img: Image, native: Vector2, pick_radius: float, line_radius: float,
		min_burg_pop: int) -> Dictionary:
	var pin := nearest_pin(repo, native, pick_radius, min_burg_pop)
	if not pin.is_empty():
		return pin
	var line := nearest_line(repo, native, line_radius)
	if not line.is_empty():
		return line
	var px := Vector2i(native.floor())
	var sid := MapIndex.state_at(state_img, px)
	if sid < 0:
		return {"kind": "water"}
	return {"kind": "land", "state_id": sid,
		"province_id": MapIndex.id_at(province_img, px),
		"biome_id": MapIndex.biome_at(biome_img, px),
		"x": native.x, "y": native.y}

static func nearest_pin(repo: DataRepository, native: Vector2, radius: float,
		min_burg_pop: int) -> Dictionary:
	var best := {}
	var best_d := radius
	for code: String in repo.markers:
		var m: Dictionary = repo.markers[code]
		var d := native.distance_to(Vector2(float(m["x"]), float(m["y"])))
		if d <= best_d:
			best_d = d
			best = {"kind": "marker", "code": code}
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if not burg_visible(b, min_burg_pop):
			continue
		var d := native.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if d < best_d:  # strict: a marker on the same spot keeps priority
			best_d = d
			best = {"kind": "burg", "code": code}
	return best

static func nearest_line(repo: DataRepository, native: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	var best_rank := 99
	for code: String in repo.routes:
		var row: Dictionary = repo.routes[code]
		var d := _line_distance(row, native, radius)
		var rank := int(LINE_RANK.get(String(row.get("group", "")), 2))
		if _closer(d, rank, best_d, best_rank):
			best_d = d
			best_rank = rank
			best = {"kind": "route", "code": code}
	for code: String in repo.rivers:
		var d := _line_distance(repo.rivers[code], native, radius)
		if _closer(d, RIVER_RANK, best_d, best_rank):
			best_d = d
			best_rank = RIVER_RANK
			best = {"kind": "river", "code": code}
	return best

## Nearer wins; at (float-)equal distance the higher-ranked line does
## (road > trail > sea route > river), so a trail stub ending on a road never
## steals the road's click. A candidate exactly at the radius still counts.
static func _closer(d: float, rank: int, best_d: float, best_rank: int) -> bool:
	if d > best_d + LINE_TIE_EPS:
		return false
	if d < best_d - LINE_TIE_EPS:
		return true
	return rank < best_rank

static func _line_distance(row: Dictionary, native: Vector2, radius: float) -> float:
	var bbox: Rect2 = row["bbox"]
	if not bbox.grow(radius).has_point(native):
		return INF
	return MapGeometry.distance_to_polyline(native, row["polyline"])

## Closest burg regardless of LOD ("" if the pack has none).
static func nearest_burg(repo: DataRepository, native: Vector2) -> String:
	var best := ""
	var best_d := INF
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		var d := native.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if d < best_d:
			best_d = d
			best = code
	return best

## Tooltip text: the object's name ("" for land/water, which have no pin).
static func label_of(repo: DataRepository, obj: Dictionary) -> String:
	match String(obj.get("kind", "")):
		"burg":
			return String(repo.burgs.get(obj["code"], {}).get("label", ""))
		"marker":
			return String(repo.markers.get(obj["code"], {}).get("label", ""))
		"route":
			return String(repo.routes.get(obj["code"], {}).get("label", ""))
		"river":
			return String(repo.rivers.get(obj["code"], {}).get("label", ""))
	return ""

## Card text per kind: {title, lines, ask}. {} means "nothing to show".
static func describe(repo: DataRepository, obj: Dictionary) -> Dictionary:
	match String(obj.get("kind", "")):
		"kingdom":
			return _describe_kingdom(repo, _kingdom_by_state(repo, int(obj.get("state_id", -1))))
		"burg":
			return _describe_burg(repo, String(obj["code"]))
		"route":
			return _describe_route(repo, String(obj["code"]))
		"river":
			return _describe_river(repo, String(obj["code"]))
		"marker":
			return _describe_marker(repo, String(obj["code"]))
		"land":
			return _describe_land(repo, obj)
	return {}

static func _kingdom_by_state(repo: DataRepository, sid: int) -> Dictionary:
	for row: Dictionary in repo.kingdoms.values():
		if int(row["state_id"]) == sid:
			return row
	return {}

static func _province_by_id(repo: DataRepository, pid: int) -> Dictionary:
	for row: Dictionary in repo.provinces.values():
		if int(row.get("province_id", -1)) == pid:
			return row
	return {}

static func _label(table: Dictionary, code: String) -> String:
	return String(table.get(code, {}).get("label", code))

## Native px -> "N unit" via map_info.csv (falls back to px when absent).
static func format_distance(repo: DataRepository, native_px: float) -> String:
	var scale := float(repo.map_info.get("distance_scale", "1"))
	var unit := String(repo.map_info.get("distance_unit", "px"))
	return "%d %s" % [roundi(native_px * scale), unit]

## The kingdom overview lines (the pre-2026-09-08 card, unchanged in content).
static func _kingdom_lines(repo: DataRepository, row: Dictionary) -> Array[String]:
	var code := String(row["kingdom_code"])
	var province_count := 0
	for p: Dictionary in repo.provinces.values():
		if String(p["kingdom_code"]) == code:
			province_count += 1
	var town_count := 0
	for b: Dictionary in repo.burgs.values():
		if String(b["kingdom_code"]) == code:
			town_count += 1
	var neighbors: Array[String] = []
	for n: String in String(row.get("neighbor_codes", "")).split("|", false):
		neighbors.append(_label(repo.kingdoms, n))
	var court: Array[String] = []
	for role: Dictionary in repo.roles:
		if String(role.get("kingdom", "")) == code:
			court.append(String(role["display_name"]))
	var lines: Array[String] = [
		"Capital: %s" % _label(repo.burgs, String(row.get("capital_burg", ""))),
		"Provinces: %d" % province_count,
		"Towns: %d" % town_count,
		"Population: %s" % row.get("population", "—"),
		"Neighbors: %s" % (", ".join(neighbors) if not neighbors.is_empty() else "—"),
	]
	if not court.is_empty():
		lines.append("Court: %s" % ", ".join(court))
	return lines

static func _describe_kingdom(repo: DataRepository, row: Dictionary) -> Dictionary:
	if row.is_empty():
		return {}
	var label := String(row["label"])
	return {"title": label, "lines": _kingdom_lines(repo, row),
		"ask": "What do we know of %s?" % label}

static func _describe_burg(repo: DataRepository, code: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(code, {})
	if b.is_empty():
		return {}
	var label := String(b["label"])
	var where := "%s, %s" % [_label(repo.provinces, String(b["province_code"])),
		_label(repo.kingdoms, String(b["kingdom_code"]))]
	var lines: Array[String] = []
	lines.append(("Capital of %s" if String(b.get("is_capital", "0")) == "1" else "Town in %s") % where)
	lines.append("Population: %s" % b.get("population", "—"))
	var traits: Array[String] = []
	if String(b.get("is_port", "0")) == "1":
		traits.append("Port")
	for f: String in String(b.get("features", "")).split("|", false):
		traits.append(String(FEATURE_WORDS.get(f, f.capitalize())))
	if not traits.is_empty():
		lines.append(", ".join(traits))
	var roads := 0
	for r: Dictionary in repo.routes.values():
		if String(r["from_burg"]) == code or String(r["to_burg"]) == code:
			roads += 1
	if roads > 0:
		lines.append("Roads: %d" % roads)
	return {"title": label, "lines": lines, "ask": "What do we know of %s?" % label}

static func _describe_route(repo: DataRepository, code: String) -> Dictionary:
	var r: Dictionary = repo.routes.get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var lines: Array[String] = [String(GROUP_WORDS.get(String(r["group"]), "Route"))]
	var from := String(r["from_burg"])
	var to := String(r["to_burg"])
	if from != "" and to != "":
		lines.append("From %s to %s" % [_label(repo.burgs, from), _label(repo.burgs, to)])
	elif from != "" or to != "":
		lines.append("Ends at %s" % _label(repo.burgs, from if from != "" else to))
	lines.append("Length: %s" % format_distance(repo, float(r["length"])))
	return {"title": label, "lines": lines, "ask": "What do we know of the %s?" % label}

static func _describe_river(repo: DataRepository, code: String) -> Dictionary:
	var rv: Dictionary = repo.rivers.get(code, {})
	if rv.is_empty():
		return {}
	var label := String(rv["label"])
	var lines: Array[String] = [String(rv.get("type", "River")),
		"Length: %s" % format_distance(repo, float(rv["length"]))]
	var through: Array[String] = []
	for k: String in String(rv.get("kingdom_codes", "")).split("|", false):
		through.append(_label(repo.kingdoms, k))
	if not through.is_empty():
		lines.append("Flows through: %s" % ", ".join(through))
	return {"title": label, "lines": lines, "ask": "What do we know of the %s?" % label}

static func _describe_marker(repo: DataRepository, code: String) -> Dictionary:
	var m: Dictionary = repo.markers.get(code, {})
	if m.is_empty():
		return {}
	var label := String(m["label"])
	var lines: Array[String] = [humanize(String(m.get("type", "")))]
	var legend := String(m.get("legend", ""))
	if legend != "":
		lines.append(legend)
	return {"title": label, "lines": lines, "ask": "What is known of %s?" % label}

## Land: the province first, then terrain and the nearest town, then the
## kingdom overview so the old kingdom card stays one click away.
static func _describe_land(repo: DataRepository, obj: Dictionary) -> Dictionary:
	var kingdom := _kingdom_by_state(repo, int(obj.get("state_id", -1)))
	if kingdom.is_empty():
		return {}
	var province := _province_by_id(repo, int(obj.get("province_id", -1)))
	var title := String(province.get("label", kingdom["label"]))
	var lines: Array[String] = [String(kingdom["label"])]
	var biome: Dictionary = repo.biomes.get(int(obj.get("biome_id", -1)), {})
	if not biome.is_empty():
		lines.append("Terrain: %s" % biome["label"])
	var here := Vector2(float(obj.get("x", 0.0)), float(obj.get("y", 0.0)))
	var near := nearest_burg(repo, here)
	if near != "":
		var b: Dictionary = repo.burgs[near]
		var dist := here.distance_to(Vector2(float(b["x"]), float(b["y"])))
		lines.append("Nearest town: %s (%s)" % [b["label"], format_distance(repo, dist)])
	lines.append_array(_kingdom_lines(repo, kingdom))
	return {"title": title, "lines": lines, "ask": "What do we know of %s?" % title}

## "hot-springs" -> "Hot springs".
static func humanize(kind: String) -> String:
	var t := kind.replace("-", " ").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""
