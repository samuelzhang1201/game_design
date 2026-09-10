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
		min_burg_pop: int, state: GameState = null) -> Dictionary:
	var pin := nearest_pin(repo, native, pick_radius, min_burg_pop)
	if not pin.is_empty():
		return pin
	var line := nearest_line(repo, native, line_radius)
	if not line.is_empty():
		return line
	var px := Vector2i(native.floor())
	# The bitmaps are geometry and never go stale — provinces do not move.
	# Ownership does, so the kingdom here is the province's CURRENT holder
	# rather than the state id baked into the pack at import.
	var sid := MapIndex.state_at(state_img, px)
	if sid < 0:
		return {"kind": "water"}
	var pid := MapIndex.id_at(province_img, px)
	return {"kind": "land", "state_id": owner_state_id(repo, state, pid, sid),
		"province_id": pid,
		"biome_id": MapIndex.biome_at(biome_img, px),
		"x": native.x, "y": native.y}

## The state id of whoever holds province `pid` now; `fallback` when the
## province is unknown (an older pack, or a pixel outside every province).
static func owner_state_id(repo: DataRepository, state: GameState, pid: int,
		fallback: int) -> int:
	var prov: Dictionary = repo.province_by_id(pid)
	if prov.is_empty():
		return fallback
	var owner := MapOwnership.owner_of(repo, state, String(prov["province_code"]))
	var king: Dictionary = repo.kingdoms.get(owner, {})
	return int(king["state_id"]) if not king.is_empty() else fallback

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
		"army":
			return String(repo.world_table("military", "regiments")
				.get(obj["code"], {}).get("label", ""))
	return ""

## Card text per kind: {title, lines, ask}. {} means "nothing to show".
static func describe(repo: DataRepository, obj: Dictionary,
		state: GameState = null) -> Dictionary:
	match String(obj.get("kind", "")):
		"kingdom":
			return _describe_kingdom(repo,
				_kingdom_by_state(repo, int(obj.get("state_id", -1))), state)
		"burg":
			return _describe_burg(repo, String(obj["code"]))
		"route":
			return _describe_route(repo, String(obj["code"]))
		"river":
			return _describe_river(repo, String(obj["code"]))
		"marker":
			return _describe_marker(repo, String(obj["code"]))
		"army":
			return _describe_army(repo, String(obj["code"]))
		"land":
			return _describe_land(repo, obj, state)
	return {}

static func _kingdom_by_state(repo: DataRepository, sid: int) -> Dictionary:
	for row: Dictionary in repo.kingdoms.values():
		if int(row["state_id"]) == sid:
			return row
	return {}

static func _province_by_id(repo: DataRepository, pid: int) -> Dictionary:
	return repo.province_by_id(pid)

static func _label(table: Dictionary, code: String) -> String:
	return String(table.get(code, {}).get("label", code))

## Native px -> "N unit" via map_info.csv (falls back to px when absent).
static func format_distance(repo: DataRepository, native_px: float) -> String:
	var scale := float(repo.map_info.get("distance_scale", "1"))
	var unit := String(repo.map_info.get("distance_unit", "px"))
	return "%d %s" % [roundi(native_px * scale), unit]

## The kingdom overview lines (the pre-2026-09-08 card, unchanged in content).
static func _kingdom_lines(repo: DataRepository, row: Dictionary,
		state: GameState = null) -> Array[String]:
	var code := String(row["kingdom_code"])
	# Counted from who holds what NOW, not from the pack's starting map, so a
	# conquered province leaves one card and appears on the other's.
	var held := MapOwnership.provinces_of(repo, state, code)
	var province_count := held.size()
	var held_set: Dictionary = {}
	for pc in held:
		held_set[pc] = true
	var town_count := 0
	for b: Dictionary in repo.burgs.values():
		if held_set.has(String(b["province_code"])):
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

static func _describe_kingdom(repo: DataRepository, row: Dictionary,
		state: GameState = null) -> Dictionary:
	if row.is_empty():
		return {}
	var label := String(row["label"])
	return {"title": label, "lines": _kingdom_lines(repo, row, state),
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
static func _describe_land(repo: DataRepository, obj: Dictionary,
		state: GameState = null) -> Dictionary:
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
	lines.append_array(_kingdom_lines(repo, kingdom, state))
	return {"title": title, "lines": lines, "ask": "What do we know of %s?" % title}

## "hot-springs" -> "Hot springs".
static func humanize(kind: String) -> String:
	var t := kind.replace("-", " ").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""

## The house holding a province: the pack's house_bindings.csv when it binds
## one, else a house named after the province's capital town (so foreign
## land always has a holder without authoring anything).
static func house_of(repo: DataRepository, province_code: String) -> String:
	var bound := String(repo.house_bindings.get(province_code, ""))
	if bound != "":
		return "House " + bound
	var prov: Dictionary = repo.provinces.get(province_code, {})
	var cap: Dictionary = repo.burgs.get(String(prov.get("capital_burg", "")), {})
	return "House " + String(cap.get("label", prov.get("label", province_code)))

## Whether the player's realm holds the province NOW.
static func province_is_players(repo: DataRepository, state: GameState,
		province_code: String) -> bool:
	return MapOwnership.owner_of(repo, state, province_code) == repo.resolve_realm("player_realm")

## The province panel's text (user request 2026-09-09). The player's own
## provinces get the full account; a foreign province shows only what is
## commonly known — its name, its kingdom, its house, its seat. "known" says
## which ("full" / "basic"). Follows live ownership.
static func describe_province(repo: DataRepository, state: GameState,
		province_code: String) -> Dictionary:
	var prov: Dictionary = repo.provinces.get(province_code, {})
	if prov.is_empty():
		return {}
	var label := String(prov["label"])
	var title := String(prov.get("full_name", ""))
	if title == "":
		title = label
	var owner := MapOwnership.owner_of(repo, state, province_code)
	var lines: Array[String] = [
		"Province of %s" % _label(repo.kingdoms, owner),
		"Held by %s" % house_of(repo, province_code),
		"Seat: %s" % _label(repo.burgs, String(prov.get("capital_burg", ""))),
	]
	var ask := "What do we know of %s?" % label
	if not province_is_players(repo, state, province_code):
		return {"title": title, "lines": lines, "ask": ask, "known": "basic"}
	# Towns, largest first.
	var towns: Array = []
	for b: Dictionary in repo.burgs.values():
		if String(b["province_code"]) == province_code:
			towns.append(b)
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(float(a["population"])) > int(float(b["population"])))
	var names: Array[String] = []
	for i in mini(towns.size(), int(repo.bal("province_card_max_towns"))):
		names.append(String(towns[i]["label"]))
	lines.append("Towns: %d%s" % [towns.size(), (" — " + ", ".join(names)) if not names.is_empty() else ""])
	# Population, live through the ledger.
	var urban: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.urban_population" % province_code)
	var rural: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % province_code)
	if urban != null and rural != null:
		lines.append("Population: %d (%d in towns, %d rural)" % [int(urban) + int(rural), int(urban), int(rural)])
	else:
		lines.append("Population: %s" % prov.get("population", "—"))
	var scale := float(repo.map_info.get("distance_scale", "1"))
	var unit := String(repo.map_info.get("distance_unit", "px"))
	lines.append("Area: %d %s²" % [roundi(float(prov.get("area", 0)) * scale * scale), unit])
	var biome: Dictionary = repo.biomes.get(int(float(prov.get("biome_id", "0"))), {})
	if not biome.is_empty():
		lines.append("Terrain: %s" % biome["label"])
	# Goods the province's towns produce, by units.
	var goods_units: Dictionary = {}
	for row: Dictionary in repo.world_table("economy", "production").values():
		var b: Dictionary = repo.burgs.get(String(row["burg_code"]), {})
		if String(b.get("province_code", "")) != province_code:
			continue
		var g := String(row["good_code"])
		goods_units[g] = float(goods_units.get(g, 0.0)) + float(row.get("units", 0))
	if not goods_units.is_empty():
		var gs := goods_units.keys()
		gs.sort_custom(func(a: String, b: String) -> bool:
			return float(goods_units[a]) > float(goods_units[b]) \
				or (float(goods_units[a]) == float(goods_units[b]) and a < b))
		var top: Array[String] = []
		for i in mini(gs.size(), int(repo.bal("province_card_max_goods"))):
			top.append(_label(repo.world_table("economy", "goods"), String(gs[i])))
		lines.append("Produces: %s" % ", ".join(top))
	# Regiments quartered here.
	var regs: Array[String] = []
	for row: Dictionary in repo.world_table("military", "regiments").values():
		if String(row.get("province_code", "")) == province_code:
			regs.append(String(row["label"]))
	if not regs.is_empty():
		lines.append("Regiments: %s" % ", ".join(regs))
	# Hazard zones touching it.
	for row: Dictionary in repo.world_table("society", "zones").values():
		if province_code in String(row.get("province_codes", "")).split("|", false):
			lines.append("Hazard: %s (%s)" % [row["label"], String(row["type"]).to_lower()])
	# The last time it changed hands.
	if state != null:
		for i in range(state.territory_log.size() - 1, -1, -1):
			var t: Dictionary = state.territory_log[i]
			if String(t["province"]) == province_code:
				lines.append("Changed hands: from %s to %s, tick %d (%s)" % [
					_label(repo.kingdoms, String(t["from"])), _label(repo.kingdoms, String(t["to"])),
					int(t["tick"]), String(t["reason"])])
				break
	return {"title": title, "lines": lines, "ask": ask, "known": "full"}

## --- Info cards (user request 2026-09-09, after Azgaar's burg editor) ------
## A card is structured, not lines: {title, subtitle, kingdom_code, initial,
## fields: [[label, value], ...], features: [feature keys], production:
## [{label, units, tag}], wealth, treasury, center: Vector2, known}. The
## detail column renders it with heraldry, a field grid, glyph rows, and a
## map preview around `center`.

## The tag a good is shown under: the first of its tags that has a glyph row
## (tag_<name> in resource_icons.csv), else "".
static func good_tag(repo: DataRepository, good_code: String) -> String:
	var g: Dictionary = repo.world_row("economy", "goods", good_code)
	for t: String in String(g.get("tags", "")).split("|", false):
		if repo.resource_icons.has("tag_" + t):
			return "tag_" + t
	return ""

## Goods produced by these burgs, summed by good, largest first.
static func production_of(repo: DataRepository, burg_codes: Array) -> Array:
	var units: Dictionary = {}
	var wanted: Dictionary = {}
	for b in burg_codes:
		wanted[String(b)] = true
	for row: Dictionary in repo.world_table("economy", "production").values():
		if not wanted.has(String(row["burg_code"])):
			continue
		var g := String(row["good_code"])
		units[g] = float(units.get(g, 0.0)) + float(row.get("units", 0))
	var out: Array = []
	for g: String in units:
		out.append({"good": g, "label": _label(repo.world_table("economy", "goods"), g),
			"units": float(units[g]), "tag": good_tag(repo, g)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["units"]) > float(b["units"]) \
			or (float(a["units"]) == float(b["units"]) and String(a["good"]) < String(b["good"])))
	return out

static func burg_card(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(code, {})
	if b.is_empty():
		return {}
	var prov: Dictionary = repo.provinces.get(String(b["province_code"]), {})
	var owner := MapOwnership.owner_of(repo, state, String(b["province_code"]))
	var kingdom: Dictionary = repo.kingdoms.get(owner, {})
	var econ: Dictionary = repo.world_row("economy", "burgs", code)
	var culture: Dictionary = repo.world_row("society", "cultures", String(b.get("culture_code", "")))
	var fields: Array = [
		["Group", String(b.get("group", "")).replace("_", " ").capitalize()],
		["Type", String(b.get("type", ""))],
		["Culture", String(culture.get("label", b.get("culture_code", "")))],
		["Population", String(b.get("population", "—"))],
	]
	var features: Array = []
	if String(b.get("is_port", "0")) == "1":
		features.append("port")
	for f: String in String(b.get("features", "")).split("|", false):
		features.append(f)
	var label := String(b["label"])
	return {
		"kind": "burg", "code": code, "title": label,
		"subtitle": "%s, %s" % [String(prov.get("full_name", prov.get("label", ""))),
			String(kingdom.get("full_name", kingdom.get("label", "")))],
		"kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": fields, "features": features,
		"production": production_of(repo, [code]),
		"wealth": float(econ.get("product", 0.0)), "treasury": float(econ.get("treasury", 0.0)),
		"center": Vector2(float(b["x"]), float(b["y"])),
		"ask": "What do we know of %s?" % label, "known": "full",
	}

## The player's own province in full; foreign land only by what is commonly
## known (name, kingdom, house, seat).
static func province_card(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var prov: Dictionary = repo.provinces.get(code, {})
	if prov.is_empty():
		return {}
	var owner := MapOwnership.owner_of(repo, state, code)
	var kingdom: Dictionary = repo.kingdoms.get(owner, {})
	var label := String(prov["label"])
	var title := String(prov.get("full_name", ""))
	if title == "":
		title = label
	var card := {
		"kind": "province", "code": code, "title": title,
		"subtitle": String(kingdom.get("full_name", kingdom.get("label", ""))),
		"kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": [["Held by", house_of(repo, code)],
			["Seat", _label(repo.burgs, String(prov.get("capital_burg", "")))]],
		"features": [], "production": [], "wealth": 0.0, "treasury": 0.0,
		"center": Vector2(float(prov.get("center_x", 0.0)), float(prov.get("center_y", 0.0))),
		"ask": "What do we know of %s?" % label,
		"known": "full" if province_is_players(repo, state, code) else "basic",
	}
	if card["known"] == "basic":
		return card
	var towns: Array = []
	for b: Dictionary in repo.burgs.values():
		if String(b["province_code"]) == code:
			towns.append(b)
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(float(a["population"])) > int(float(b["population"])))
	var names: Array[String] = []
	var codes: Array = []
	for t: Dictionary in towns:
		codes.append(String(t["burg_code"]))
	for i in mini(towns.size(), int(repo.bal("province_card_max_towns"))):
		names.append(String(towns[i]["label"]))
	var urban: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.urban_population" % code)
	var rural: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % code)
	var fields: Array = card["fields"]
	if urban != null and rural != null:
		fields.append(["Population", "%d (%d in towns)" % [int(urban) + int(rural), int(urban)]])
	else:
		fields.append(["Population", String(prov.get("population", "—"))])
	var scale := float(repo.map_info.get("distance_scale", "1"))
	fields.append(["Area", "%d %s²" % [roundi(float(prov.get("area", 0)) * scale * scale),
		String(repo.map_info.get("distance_unit", "px"))]])
	var biome: Dictionary = repo.biomes.get(int(float(prov.get("biome_id", "0"))), {})
	if not biome.is_empty():
		fields.append(["Terrain", String(biome["label"])])
	fields.append(["Towns", "%d%s" % [towns.size(), (": " + ", ".join(names)) if not names.is_empty() else ""]])
	var regs: Array[String] = []
	for row: Dictionary in repo.world_table("military", "regiments").values():
		if String(row.get("province_code", "")) == code:
			regs.append(String(row["label"]))
	if not regs.is_empty():
		fields.append(["Regiments", ", ".join(regs)])
	for row: Dictionary in repo.world_table("society", "zones").values():
		if code in String(row.get("province_codes", "")).split("|", false):
			fields.append(["Hazard", "%s (%s)" % [row["label"], String(row["type"]).to_lower()]])
	if state != null:
		for i in range(state.territory_log.size() - 1, -1, -1):
			var t: Dictionary = state.territory_log[i]
			if String(t["province"]) == code:
				fields.append(["Changed hands", "from %s to %s, tick %d (%s)" % [
					_label(repo.kingdoms, String(t["from"])), _label(repo.kingdoms, String(t["to"])),
					int(t["tick"]), String(t["reason"])]])
				break
	var wealth := 0.0
	var treasury := 0.0
	for c in codes:
		var e: Dictionary = repo.world_row("economy", "burgs", String(c))
		wealth += float(e.get("product", 0.0))
		treasury += float(e.get("treasury", 0.0))
	card["production"] = production_of(repo, codes)
	card["wealth"] = wealth
	card["treasury"] = treasury
	return card

## The settlement drawing for a burg (data/settlement_art.csv): its group,
## and for groups that distinguish it, whether it has walls. {} when the
## pack's group has no art.
static func settlement_art(repo: DataRepository, b: Dictionary) -> Dictionary:
	var group := String(b.get("group", ""))
	var walled := "walls" in String(b.get("features", "")).split("|", false)
	for row: Dictionary in repo.settlement_art:
		if String(row["group"]) != group:
			continue
		var want := String(row.get("walled", ""))
		if want == "" or (want == "1") == walled:
			return row
	return {}

## --- Regiments (user request 2026-09-10) -------------------------------
## The military layer draws the realm's own regiments where the pack puts
## them. The counts per arm live in data/maps/<id>/military/regiments.csv;
## these read them so the map and the MILITARY panel agree on every number.

## Every regiment of a kingdom, in the pack's order.
static func regiments_of(repo: DataRepository, kingdom_code: String) -> Array:
	var out: Array = []
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) == kingdom_code:
			out.append(r)
	return out

## Heads under a regiment's banner: every arm in unit_types added up.
static func regiment_size(repo: DataRepository, regiment: Dictionary) -> float:
	var total := 0.0
	for unit: String in repo.world_table("military", "unit_types"):
		total += float(regiment.get(unit, 0))
	return total

## The arm a regiment is mostly made of — what its map marker wears. Ties go
## to the earlier arm in unit_types, so the choice is data-ordered.
static func regiment_arm(repo: DataRepository, regiment: Dictionary) -> String:
	var best := ""
	var most := -1.0
	for unit: String in repo.world_table("military", "unit_types"):
		var n := float(regiment.get(unit, 0))
		if n > most:
			most = n
			best = unit
	return best

static func _describe_army(repo: DataRepository, code: String) -> Dictionary:
	var r: Dictionary = repo.world_table("military", "regiments").get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var lines: Array[String] = ["%s of %s" % [
		"Fleet" if String(r.get("is_naval", "0")) == "1" else "Regiment",
		_label(repo.kingdoms, String(r["kingdom_code"]))]]
	var province := String(r.get("province_code", ""))
	if province != "":
		lines.append("Quartered in %s" % _label(repo.provinces, province))
	for unit: String in repo.world_table("military", "unit_types"):
		var n := float(r.get(unit, 0))
		if n > 0.0:
			lines.append("%s: %d" % [String((repo.resource_icons.get(unit, {}) as Dictionary)
				.get("label", unit.capitalize())), int(n)])
	lines.append("Under arms: %d" % int(regiment_size(repo, r)))
	return {"title": label, "lines": lines,
		"ask": "What is the state of the %s?" % label}
