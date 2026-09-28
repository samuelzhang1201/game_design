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

## LOD rule from balance.csv. view_scale = screen px per native map px.
static func min_burg_pop_for_scale(repo: DataRepository, view_scale: float) -> int:
	if view_scale >= repo.bal("map_lod_village_scale"):
		return 0
	if view_scale >= repo.bal("map_lod_town_scale"):
		return int(repo.bal("map_lod_town_pop"))
	return CAPITALS_ONLY

## Every land card — manor, province or burg — offers a spy to that point
## (owner 2026-09-28; fix round 1: its "error" is ActionSystem's own
## validation, exactly like the card's other actions, so a spy the treasury
## cannot afford shows disabled too — the engine still decides, this only
## reads its answer).
static func _spy_send_action(repo: DataRepository, state: GameState, centre: Vector2) -> Dictionary:
	var spec := {"action_code": "SPY_SEND", "label": "Send a spy",
		"params": {"x": centre.x, "y": centre.y}, "error": ""}
	if state != null:
		spec["error"] = ActionSystem.new(repo).validate(
			ActionRequest.make("SPY_SEND", spec["params"] as Dictionary), state)
	return spec

static func burg_visible(b: Dictionary, min_pop: int) -> bool:
	if String(b.get("is_capital", "0")) == "1":
		return true
	if min_pop < 0:
		return false
	return int(float(b.get("population", "0"))) >= min_pop


## The estate a manor wears in the MANORS view (owner 2026-09-13/14: ONE
## drawing per manor, its house and its INDUSTRY's workplace together —
## the scattered houses-and-fields marks it replaced were the owner's
## veto). The rows of data/manor_estates.csv for the manor's focus (the
## first industry's rows when its focus has none), and among them the
## last whose min_people the manor's ledger people reach: {} for no rows.
static func estate_tier(repo: DataRepository, focus_code: String, people: float) -> Dictionary:
	var rows := estate_rows(repo, focus_code)
	var out: Dictionary = {}
	for row: Dictionary in rows:
		if people >= float(row["min_people"]):
			out = row
	return out

## An industry's rows ascending by min_people; the first industry's when
## the code has none. Cached per repo.
static var _estate_rows_cache: Dictionary = {}

static func estate_rows(repo: DataRepository, focus_code: String) -> Array:
	var rkey := repo.get_instance_id()
	if not _estate_rows_cache.has(rkey):
		var grouped: Dictionary = {}
		var order: Array = []
		for row: Dictionary in repo.manor_estates:
			var code := String(row["focus_code"])
			if not grouped.has(code):
				grouped[code] = []
				order.append(code)
			(grouped[code] as Array).append(row)
		for code: String in grouped:
			(grouped[code] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["min_people"]) < float(b["min_people"]))
		_estate_rows_cache[rkey] = {"by": grouped, "first": String(order[0]) if not order.is_empty() else ""}
	var cache: Dictionary = _estate_rows_cache[rkey]
	var by: Dictionary = cache["by"]
	if by.has(focus_code):
		return by[focus_code]
	return by.get(String(cache["first"]), [])



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
static func label_of(repo: DataRepository, obj: Dictionary, state: GameState = null) -> String:
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
		"manor":
			return MapManors.label_of(repo, int(obj.get("cell", -1)))
		"landmark":
			var id := int(obj.get("cell", -1))
			var m := Elevation.landmark_at(repo, id)
			if m.is_empty():
				return ""
			return String(m["name"]) + "\n" + "\n".join(landmark_lines(repo, state, id))
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
			return _describe_army(repo, String(obj["code"]), state)
		"land":
			return _describe_land(repo, obj, state)
		"manor":
			return _describe_manor(repo, int(obj.get("cell", -1)), state)
	return {}

## A manor's entry: its card's title and a few lines, for the floating
## card; the detail column asks for manor_card itself.
static func _describe_manor(repo: DataRepository, cell: int, state: GameState) -> Dictionary:
	var card := manor_card(repo, state, cell)
	if card.is_empty():
		return {}
	var lines: Array[String] = []
	for f in card["fields"]:
		lines.append("%s: %s" % [String(f[0]), String(f[1])])
	return {"title": card["title"], "lines": lines, "ask": card["ask"]}

static func _kingdom_by_state(repo: DataRepository, sid: int) -> Dictionary:
	for row: Dictionary in repo.kingdoms.values():
		if int(row["state_id"]) == sid:
			return row
	return {}

static func _province_by_id(repo: DataRepository, pid: int) -> Dictionary:
	return repo.province_by_id(pid)

static func _label(table: Dictionary, code: String) -> String:
	return String(table.get(code, {}).get("label", code))

## "where — holder", collapsed: no "Wickhampia — Wickhampia" when the
## holder's house wears the province's own name, no leading " — " when
## there is no province to name (an off-pack cell) but a holder still
## reads, and just the province when there is no holder at all.
static func _landmark_where_line(where: String, holder: String) -> String:
	if holder == "":
		return where
	if where == "" or where == holder:
		return holder
	return "%s — %s" % [where, holder]

## A landmark's facts, one per line (spec 2026-09-19-map3d-heights §4):
## height · tier · biome; province — holder; the garrison's supply; the
## edge over the land round it and what it is worth in a fight.
static func landmark_lines(repo: DataRepository, state: GameState, cell: int) -> PackedStringArray:
	var c: Dictionary = repo.cells[cell]
	var tier := Elevation.tier_of(repo, float(c["height"]))
	var biome := String((repo.biomes.get(int(c["biome_id"]), {}) as Dictionary).get("label", ""))
	var province := MapManors.province_of(repo, cell, state)
	var where := _label(repo.provinces, province) if province != "" else ""
	var holder := MapManors.owner_of(repo, state, cell)
	var mult := float(int(tier["supply_permille"])) / 1000.0
	var edge := Elevation.local_edge_m(repo, cell)
	@warning_ignore("integer_division")  # whole percent from per-mille
	var pct := (ArmySystem.height_factor(repo, absi(edge)) - 1000) / 10
	var out := PackedStringArray()
	out.append("%d m · %s · %s" % [Elevation.metres_of_cell(repo, cell), String(tier["tier"]).capitalize(), biome])
	out.append(_landmark_where_line(where, holder))
	out.append("Garrison: supplies ×%.1f (%s)" % [mult, String(tier["tier"])])
	if edge >= 0:
		out.append("%d m above the land around — +%d%% in a fight against it" % [edge, pct])
	else:
		out.append("%d m below the land around — −%d%% fighting up out of it" % [-edge, pct])
	return out

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
	# A foreign kingdom's population is a word, not a figure (spec
	# 2026-09-28 §1) — but its provinces and towns stay exact: the map draws
	# every border and every town for all to see, so counting them leaks
	# nothing a spyglass would not (a deliberate deviation from the spec's
	# blanket "magnitude words" rule, per the task-5 controller ruling).
	var foreign := code != repo.resolve_realm("player_realm") and not Intel.dev_all
	var pop_text := Intel.magnitude(repo, int(float(row.get("population", 0)))) if foreign \
		else Intel.num(int(float(row.get("population", 0))))
	var lines: Array[String] = [
		"Capital: %s" % _label(repo.burgs, String(row.get("capital_burg", ""))),
		"Provinces: %d" % province_count,
		"Towns: %d" % town_count,
		"Population: %s" % pop_text,
		"Neighbors: %s" % (", ".join(neighbors) if not neighbors.is_empty() else "—"),
	]
	if foreign:
		lines.append("Stance: %s" % Intel.stance_of(repo, code))
		if state != null:
			lines.append("Wealth: %s" % Intel.wealth_word(repo, Intel.kingdom_wealth_tier(repo, state, code)))
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
	return "House " + house_name_of(repo, province_code)

## The same house as a bare family name — what Character.family_name and
## GameState.manor_owner carry (MapManors).
static func house_name_of(repo: DataRepository, province_code: String) -> String:
	var bound := String(repo.house_bindings.get(province_code, ""))
	if bound != "":
		return bound
	var prov: Dictionary = repo.provinces.get(province_code, {})
	var cap: Dictionary = repo.burgs.get(String(prov.get("capital_burg", "")), {})
	return String(cap.get("label", prov.get("label", province_code)))

## Whether the player's realm holds the province NOW.
static func province_is_players(repo: DataRepository, state: GameState,
		province_code: String) -> bool:
	return MapOwnership.owner_of(repo, state, province_code) == repo.resolve_realm("player_realm")

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
	var center := Vector2(float(b["x"]), float(b["y"]))
	var subj := MissiveLog.subject("burg", code, -1, center)
	var known := Intel.level(repo, state, subj)
	var card := {
		"kind": "burg", "code": code, "title": label,
		"subtitle": "%s, %s" % [String(prov.get("full_name", prov.get("label", ""))),
			String(kingdom.get("full_name", kingdom.get("label", "")))],
		"kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": fields, "features": features,
		"production": production_of(repo, [code]),
		"wealth": float(econ.get("product", 0.0)), "treasury": float(econ.get("treasury", 0.0)),
		"center": center,
		"ask": "What do we know of %s?" % label, "known": known,
	}
	if known != "full":
		card["production"] = []
		card["wealth"] = 0.0
		card["treasury"] = 0.0
		var true_pop := int(float(b.get("population", 0)))
		# The population is said ONCE, by the intel row (which carries its
		# source), not also as a plain field (final review M5).
		for i in range(fields.size() - 1, -1, -1):
			if String(fields[i][0]) == "Population":
				fields.remove_at(i)
		var facts: Array = [
			["town_people", "People", true_pop],
			["wealth", "Wealth", Intel.wealth_tier(repo, state, String(b["province_code"]))],
			["stance", "Stance", Intel.stance_of(repo, owner)]]
		card["intel"] = _intel_rows(repo, state, subj, facts)
	if not card.has("actions"):
		card["actions"] = []
	(card["actions"] as Array).append(_spy_send_action(repo, state, center))
	return card

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
	var center := Vector2(float(prov.get("center_x", 0.0)), float(prov.get("center_y", 0.0)))
	var subj := MissiveLog.subject("province", code, -1, center)
	var known := Intel.level(repo, state, subj)
	var card := {
		"kind": "province", "code": code, "title": title,
		"subtitle": String(kingdom.get("full_name", kingdom.get("label", ""))),
		"kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": [["Held by", house_of(repo, code)],
			["Seat", _label(repo.burgs, String(prov.get("capital_burg", "")))],
			["Weather", Weather.describe(repo, state, code)]],
		"features": [], "production": [], "wealth": 0.0, "treasury": 0.0,
		"actions": [_spy_send_action(repo, state, center)],
		"center": center,
		"ask": "What do we know of %s?" % label,
		"known": known,
	}
	if card["known"] != "full":
		var urban: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.urban_population" % code)
		var rural: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % code)
		var true_people := (int(urban) + int(rural)) if (urban != null and rural != null) \
			else int(float(prov.get("population", 0)))
		var facts: Array = [
			["people", "People", true_people],
			["wealth", "Wealth", Intel.wealth_tier(repo, state, code)],
			["stance", "Stance", Intel.stance_of(repo, owner)]]
		card["intel"] = _intel_rows(repo, state, subj, facts)
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
	# Who holds the province's manors (MANOR_SYSTEM.md §4) — the crown's
	# own land is known in this detail; abroad it is not.
	fields.append(["Manors", holdings_text(repo, state, code)])
	var controller := MapManors.controller_of(repo, state, code)
	fields.append(["Controlled by", "the crown" if controller == MapManors.crown(state)
		else ("House " + controller if controller != "" else "no one")])
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

## The manor card (MANOR_SYSTEM.md §3): the same shape as province_card,
## plus `cell`, `buildings` and `actions` — the orders the crown could give
## for this manor, each with ActionSystem's own reason when it cannot, so
## the column's buttons say why they are dim. Full inside the crown's
## realm, basic abroad.
static func manor_card(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	if not MapManors.is_manor(repo, cell):
		return {}
	var province := MapManors.province_of(repo, cell, state)
	var prov: Dictionary = repo.provinces.get(province, {})
	var owner := MapOwnership.owner_of(repo, state, province)
	var kingdom: Dictionary = repo.kingdoms.get(owner, {})
	var label := MapManors.label_of(repo, cell)
	var house := MapManors.owner_of(repo, state, cell)
	var crowns := MapManors.is_crowns(repo, state, cell)
	var subtitle := String(prov.get("full_name", prov.get("label", "")))
	if not kingdom.is_empty():
		# A comma, which reads at a line's end or not (a dot left hanging
		# there, or starting the next line, owner 2026-09-28).
		subtitle += ", " + String(kingdom.get("label", ""))
	var manor_code := MapManors.code_of(repo, cell)
	var center := MapTerrain.cell_center(repo, repo.cells.get(cell, {"vertex_ids": PackedInt32Array()}))
	var subj := MissiveLog.subject("manor", manor_code, cell, center)
	var known := Intel.level(repo, state, subj)
	var card := {
		"kind": "manor", "code": manor_code, "cell": cell, "title": label,
		"subtitle": subtitle, "kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": [["Held by", "The crown" if crowns else ("House " + house if house != "" else "no one")],
			["Province", String(prov.get("label", province))]],
		"features": [], "production": [], "wealth": 0.0, "treasury": 0.0,
		"buildings": [], "works": [], "slots": 0, "slot_actions": [], "actions": [],
		"center": center,
		"ask": "What do we know of %s?" % label,
		"known": known,
	}
	var fields: Array = card["fields"]
	var burg := MapManors.burg_of(repo, cell)
	if burg != "":
		fields.append(["Seat", _label(repo.burgs, burg)])
	# The card's face (owner 2026-09-14): the estate's painting over the card,
	# and the manor's facts as icons — a short value beside each, the whole
	# of it in its tooltip. `fields` stays for tools and tests.
	var stats: Array = []
	card["stats"] = stats
	card["rates"] = []
	card["painting"] = estate_painting(repo, state, cell)
	var wx := Weather.of(repo, state, province, state.absolute_day()) if state != null else Weather.CLEAR
	stats.append(_stat("weather_" + wx, Weather.label_of(repo, wx), "Weather — " + Weather.describe_kind(repo, wx)))
	stats.append(_stat("manor_owner", "The crown" if crowns else (house if house != "" else "no one"),
		"Held by — %s" % ("the crown" if crowns else ("House " + house if house != "" else "no one"))))
	stats.append(_stat("manor_province", String(prov.get("label", province)), "Province — %s" % subtitle))
	if burg != "":
		stats.append(_stat("manor_seat", _label(repo.burgs, burg),
			"Seat — the town of %s stands in it" % _label(repo.burgs, burg)))
	if card["known"] != "full":
		# The orders stand as they always did for realm land (owner 2026-09-14):
		# a general manor — the crown's own house holds it, or another
		# house's, either within a province the crown does not itself
		# control — offers manor_actions unconditionally, exactly as a
		# crown-controlled manor's card always has, each action's own error
		# saying when the purse, the border or (BUILD/FOCUS) the missing
		# control refuses it. Truly foreign land (known "basic") only
		# carries the one BUY order, and only when it touches the realm's
		# border at all, so a distant foreign manor does not carry a button
		# that can never fire.
		if state != null and (known == "general" or (not crowns \
				and String(MapManors.purchase_kind(repo, state, cell)["kind"]) == "foreign")):
			card["actions"] = manor_actions(repo, state, cell)
		stats.append(_manor_price_stat(repo, state, cell, crowns))
		var line := ManorEconomy.line_of(repo, state, cell, state.tick)
		var output_total := 0
		for g: String in (line["units"] as Dictionary):
			output_total += int((line["units"] as Dictionary)[g])
		# the chief good's units, named, as a spy's report measures them (N1)
		var made := SpySystem.chief_output(repo, state, cell, int(line["people"]), output_total)
		var facts: Array = [
			["people", "People", int(line["people"])],
			["tax", "Tax", int(line["tax"])],
			["output", String(made["label"]), int(made["units"])],
			["wealth", "Wealth", Intel.wealth_tier(repo, state, province)],
			["stance", "Stance", Intel.stance_of(repo, owner)]]
		card["intel"] = _intel_rows(repo, state, subj, facts)
		(card["actions"] as Array).append(_spy_send_action(repo, state, center))
		return card
	var cell_row: Dictionary = repo.cells.get(cell, {})
	var biome: Dictionary = repo.biomes.get(int(cell_row.get("biome_id", -1)), {})
	var terrain := String(biome.get("label", ""))
	for n: int in (cell_row.get("neighbor_ids", PackedInt32Array()) as PackedInt32Array):
		if MapTerrain.is_sea(repo.cells.get(n, {})):
			terrain += " · coast"
			break
	if terrain != "":
		fields.append(["Terrain", terrain])
	fields.append(["Land", "%d%%" % roundi(MapManors.land_value_of(repo, cell) * 100.0)])
	var scale := float(repo.map_info.get("distance_scale", "1"))
	fields.append(["Area", "%d %s²" % [roundi(MapManors.area_of(repo, cell) * scale * scale),
		String(repo.map_info.get("distance_unit", "px"))]])
	# One economy on the card (2026-09-14): people, tax and yield are all
	# ManorEconomy's whole-number month, the same figures the tick settles
	# and the ECONOMY column sums.
	var line := ManorEconomy.line_of(repo, state, cell, state.tick)
	var people := int(line["people"])
	var town := MapManors.burg_of(repo, cell)
	if town != "":
		fields.append(["People", "%d (%s stands in it)" % [people,
			String(repo.burgs.get(town, {}).get("label", town))]])
	else:
		fields.append(["People", str(people)])
	fields.append(["Tax", "%d gold a month" % int(line["tax"])])
	# The chief good (owner 2026-09-13): what the manor works at, what it
	# ships of that good in a month, and how far a switch has settled in.
	var focus_code := MapManors.focus_of(repo, state, cell)
	var focus: Dictionary = repo.manor_focus.get(focus_code, {})
	if not focus.is_empty():
		var good := String(focus.get("good_code", ""))
		var text := "%s — %d %s a month" % [String(focus.get("label", focus_code)),
			int((line["units"] as Dictionary).get(good, 0)),
			String(repo.world_row("economy", "goods", good).get("label", good)).to_lower()]
		var ramp := MapManors.focus_ramp(repo, state, cell)
		if ramp < 1.0:
			text += " (settling in, %d%%)" % roundi(ramp * 100.0)
		fields.append(["Chief good", text])
	else:
		fields.append(["Chief good", "none the land allows"])
	var tier := MapManors.burg_of(repo, cell) == ""
	if tier and not repo.manor_estates.is_empty():
		var est := estate_tier(repo, MapManors.focus_of(repo, state, cell), float(people))
		if not est.is_empty():
			var industry := String((repo.manor_focus.get(String(est["focus_code"]), {}) as Dictionary).get("label", est["focus_code"])).to_lower()
			# Its name says its size (owner 2026-09-28: "3 of 3" said nothing);
			# the field keeps the industry and the rank for tools and tooltips.
			var est_label := String(est.get("label", ""))
			fields.append(["Estate", "%s%s, size %d of %d" % [
				(est_label.to_lower() + " — ") if est_label != "" else "", industry,
				int(float(est["tier"])), estate_rows(repo, String(est["focus_code"])).size()]])
			card["estate_label"] = est_label
	fields.append(["Defence", str(roundi(MapManors.defence_of(repo, state, cell)))])
	var built: Array = MapManors.buildings_of(state, cell)
	card["buildings"] = built
	var names: Array[String] = []
	for b: String in built:
		names.append(String((repo.manor_buildings.get(b, {}) as Dictionary).get("label", b)))
	# Works in progress (2026-09-13): the slot row draws them dim with the
	# days left; the field names them too.
	var works: Array = []
	for w: Dictionary in MapManors.works_of(state, cell):
		var b := String(w["building"])
		var left := MapManors.work_days_left(state, cell, b)
		var name := String((repo.manor_buildings.get(b, {}) as Dictionary).get("label", b))
		works.append({"building": b, "label": name, "days_left": left,
			"progress": MapManors.work_progress(state, cell, b)})
		names.append("%s (%d days to go)" % [name, left])
	card["works"] = works
	card["slots"] = MapManors.slots_of(repo, cell)
	fields.append(["Buildings", ", ".join(names) if not names.is_empty() else "none"])
	fields.append(["Slots", "%d of %d taken" % [MapManors.slots_used(state, cell), MapManors.slots_of(repo, cell)]])
	fields.append(["Value", "%d gold" % roundi(MapManors.base_value_of(repo, state, cell))])
	if crowns:
		fields.append(["Sells for", "%d gold" % roundi(MapManors.sell_price_of(repo, state, cell))])
	else:
		fields.append(["Asking price", "%d gold" % roundi(MapManors.price_of(repo, state, cell))])
	var land_pct := roundi(MapManors.land_value_of(repo, cell) * 100.0)
	var area := roundi(MapManors.area_of(repo, cell) * scale * scale)
	var unit := String(repo.map_info.get("distance_unit", "px"))
	if terrain != "":
		stats.append(_stat("manor_terrain", terrain.split(" · ")[0], "Terrain — %s" % terrain))
	stats.append(_stat("manor_land", "%d%%" % land_pct,
		"Land — how kindly the ground is to farming: %d%%" % land_pct))
	stats.append(_stat("manor_area", "%d %s²" % [area, unit], "Area — %d %s²" % [area, unit]))
	stats.append(_stat("manor_people", _short_num(float(people)),
		"People — %d live on the manor%s" % [people, ", its town included" if town != "" else ""]))
	var tariff := int(line["tariff"])
	stats.append(_stat("manor_tax", "%d/mo" % int(line["tax"]), "Tax — %d gold a month%s" % [int(line["tax"]),
		(", %d of it the town's tariff" % tariff) if tariff > 0 else ""]))
	stats.append(_stat("manor_strategic", "%d/mo" % int(line["strategic"]),
		"Strategic goods — %d gold's worth a month" % int(line["strategic"])))
	stats.append(_stat("manor_civil", "%d/mo" % int(line["civil"]),
		"Civil goods — %d gold's worth a month" % int(line["civil"])))
	var focus_now: Dictionary = repo.manor_focus.get(MapManors.focus_of(repo, state, cell), {})
	stats.append(_stat("manor_focus", String(focus_now.get("label", "none")),
		"Chief good — %s" % _field_text(fields, "Chief good")))
	var estate_text := _field_text(fields, "Estate")
	if estate_text != "":
		var est_short := String(card.get("estate_label", ""))
		if est_short == "":
			est_short = estate_text.get_slice(", ", estate_text.get_slice_count(", ") - 1).replace("size ", "")
		stats.append(_stat("manor_estate", est_short, "Estate — %s" % estate_text))
	stats.append(_stat("manor_defence", str(roundi(MapManors.defence_of(repo, state, cell))),
		"Defence — how hard the manor is to take"))
	stats.append(_stat("manor_slots", "%d/%d" % [MapManors.slots_used(state, cell), MapManors.slots_of(repo, cell)],
		"Building slots — %s; buildings: %s" % [_field_text(fields, "Slots"), _field_text(fields, "Buildings")]))
	stats.append(_stat("manor_value", _short_num(MapManors.base_value_of(repo, state, cell)),
		"Value — %s" % _field_text(fields, "Value")))
	stats.append(_manor_price_stat(repo, state, cell, crowns))
	# What it makes a month, good by good (owner 2026-09-14): the same line
	# the month's settlement reads.
	card["rates"] = production_rates(repo, line)
	if state != null:
		for i in range(state.manor_log.size() - 1, -1, -1):
			var t: Dictionary = state.manor_log[i]
			if int(t.get("cell", -1)) == cell and t.has("to"):
				fields.append(["Changed hands", "to %s, tick %d (%s)" % [
					"the crown" if String(t["to"]) == MapManors.crown(state) else "House " + String(t["to"]),
					int(t["tick"]), String(t["reason"])]])
				break
	if burg != "":
		card["production"] = production_of(repo, [burg])
		var e: Dictionary = repo.world_row("economy", "burgs", burg)
		card["wealth"] = float(e.get("product", 0.0))
		card["treasury"] = float(e.get("treasury", 0.0))
	card["actions"] = manor_actions(repo, state, cell)
	(card["actions"] as Array).append(_spy_send_action(repo, state, center))
	card["slot_actions"] = slot_actions(repo, state, cell)
	return card

## One fact of a manor card: an icon key (data/resource_icons.csv), a short
## value for beside it, and the whole of it for the tooltip.
static func _stat(key: String, text: String, tooltip: String) -> Dictionary:
	return {"key": key, "text": text, "tooltip": tooltip}

## The manor's price stat (owner 2026-09-14): what the crown could sell it
## for, or what its house is asking. Used by both the full card and the
## fogged one — the price is not one of the fogged figures (people/tax/
## wealth/treasury), and the BUY/SELL button's own label already states it
## exactly regardless of `known`, so the stat beside it always agrees.
static func _manor_price_stat(repo: DataRepository, state: GameState, cell: int, crowns: bool) -> Dictionary:
	if crowns:
		var sell := roundi(MapManors.sell_price_of(repo, state, cell))
		return _stat("manor_price", _short_num(sell), "Sells for — %d gold" % sell)
	var ask := roundi(MapManors.price_of(repo, state, cell))
	return _stat("manor_price", _short_num(ask), "Asking price — %d gold" % ask)

## The rows a fogged card shows (spec 2026-09-28): each fact through Intel,
## tagged with where it came from.
static func _intel_rows(repo: DataRepository, state: GameState, subj: Dictionary, facts: Array) -> Array:
	var rows: Array = []
	for f: Array in facts:  # [key, label, true value]
		var got := Intel.fact(repo, state, subj, String(f[0]), f[2])
		var tag := ""
		if String(got["column"]) != "" and String(got["source"]) != "own records":
			tag = "%s · %s" % [String(got["source"]), CourierCard.date_of(int(got["day"]))]
		rows.append({"label": String(f[1]), "text": String(got["text"]), "tag": tag,
			"column": String(got["column"])})
	return rows

## The value of a named row in a card's fields, or "".
static func _field_text(fields: Array, name: String) -> String:
	for f: Array in fields:
		if String(f[0]) == name:
			return String(f[1])
	return ""

## 1234 -> "1234", 45678 -> "45.7k", 1234567 -> "1.2M": a value that fits
## beside an icon; the tooltip carries the exact figure.
static func _short_num(v: float) -> String:
	if absf(v) >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if absf(v) >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	# Grouped by thousands like every other whole figure (owner 2026-09-28).
	var n := roundi(v)
	var digits := str(absi(n))
	if digits.length() > 3:
		digits = digits.substr(0, digits.length() - 3) + "," + digits.substr(digits.length() - 3)
	return ("-" if n < 0 else "") + digits

## The painting of a manor's estate (library B-, owner 2026-09-14): the
## `painting` of the manor_estates.csv row its industry and people choose —
## the same row as its map drawing, so the card and the map show one estate.
## "" when there are no rows or the row names none.
static func estate_painting(repo: DataRepository, state: GameState, cell: int) -> String:
	var row := estate_tier(repo, MapManors.focus_of(repo, state, cell),
		float(MapManors.people_of(repo, state, cell)))
	return String(row.get("painting", ""))

## A manor's output a month, good by good, from its ManorEconomy line:
## [{good, label, units, gold, pool, tag, texture}], most units first, ties
## by code — every good its chief work, its buildings and its town make.
static func production_rates(repo: DataRepository, line: Dictionary) -> Array:
	var out: Array = []
	var units: Dictionary = line.get("units", {})
	for good: String in units:
		var n := int(units[good])
		if n <= 0:
			continue
		var ge := repo.goods_economy_of(good)
		out.append({"good": good, "units": n,
			"label": String(repo.world_row("economy", "goods", good).get("label", good)),
			"gold": n * int(ge["price_gold"]), "pool": String(ge["pool"]),
			"tag": good_tag(repo, good), "texture": String(repo.goods_art.get(good, "")),
			"icon": String(repo.goods_icons.get(good, ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["good"]) < String(b["good"]) if int(a["units"]) == int(b["units"]) \
			else int(a["units"]) > int(b["units"]))
	return out

## One DEMOLISH order per building standing or begun on a crown manor,
## validated — the slot row's cross buttons. [{action_code, params,
## building, label, refund, error}].
static func slot_actions(repo: DataRepository, state: GameState, cell: int) -> Array:
	if state == null or not MapManors.is_crowns(repo, state, cell):
		return []
	var code := MapManors.code_of(repo, cell)
	var specs: Array = []
	var all: Array = MapManors.buildings_of(state, cell)
	for w: Dictionary in MapManors.works_of(state, cell):
		all.append(String(w["building"]))
	var actions := ActionSystem.new(repo)
	for b: String in all:
		var row: Dictionary = repo.manor_buildings.get(b, {})
		var refund := roundf(float(row.get("civil_cost", 0)) * repo.bal("manor_demolish_refund"))
		var spec := {"action_code": "MANOR_DEMOLISH", "params": {"manor": code, "building": b},
			"building": b, "refund": refund,
			"label": "Pull down the %s — %d civil goods back" % [
				String(row.get("label", b)).to_lower(), int(refund)]}
		spec["error"] = actions.validate(ActionRequest.make("MANOR_DEMOLISH", spec["params"]), state)
		specs.append(spec)
	return specs

## The orders the crown could give for a manor, each validated: [{action_code,
## label, params, error}]. Buy or seize what another house holds; sell or
## build on the crown's own. Seizing appears only while manor_seize_enabled.
static func manor_actions(repo: DataRepository, state: GameState, cell: int) -> Array:
	if state == null:
		return []
	var code := MapManors.code_of(repo, cell)
	var specs: Array = []
	if MapManors.is_crowns(repo, state, cell):
		specs.append({"action_code": "MANOR_SELL", "params": {"manor": code},
			"label": "SELL — %d gold to your purse" % roundi(MapManors.sell_price_of(repo, state, cell))})
		# The chief goods the land allows, less the one it works (2026-09-13),
		# ahead of the buildings: the choice the economy turns on.
		var working := MapManors.focus_of(repo, state, cell)
		for f: String in MapManors.focuses_for(repo, cell):
			if f == working:
				continue
			var row_f: Dictionary = repo.manor_focus[f]
			specs.append({"action_code": "MANOR_FOCUS", "params": {"manor": code, "focus": f},
				"label": "WORK %s — %dg" % [String(row_f["label"]).to_upper(), int(float(row_f["switch_cost_gold"]))]})
		# Tier by tier (owner 2026-09-14), and only what the manor's ground takes:
		# a quay is not offered inland. What still needs another building is
		# offered with the reason as its error.
		var codes: Array = repo.manor_buildings.keys()
		codes.sort_custom(func(a: String, b2: String) -> bool:
			var ta := int(float((repo.manor_buildings[a] as Dictionary).get("tier", 1)))
			var tb := int(float((repo.manor_buildings[b2] as Dictionary).get("tier", 1)))
			return a < b2 if ta == tb else ta < tb)
		for b: String in codes:
			if MapManors.has_building(state, cell, b) or MapManors.is_building(state, cell, b):
				continue
			if not MapManors.building_land_ok(repo, state, cell, b):
				continue
			var row: Dictionary = repo.manor_buildings[b]
			# A building is paid for in CIVIL GOODS, not gold (spec §5), so
			# the button says so; gold only hurries it (HURRY below).
			specs.append({"action_code": "MANOR_BUILD", "params": {"manor": code, "building": b},
				"label": "BUILD %s — %d civil, %dd" % [String(row["label"]).to_upper(),
					int(float(row.get("civil_cost", 0))), int(float(row.get("build_days", 0)))]})
		# One HURRY per work in progress: gold off the days still to run.
		var per_click := int(repo.bal("manor_rush_days_per_click"))
		var rush_gold := per_click * int(repo.bal("build_rush_gold_per_day"))
		for w: Dictionary in MapManors.works_of(state, cell):
			var b_w := String(w["building"])
			var row_w: Dictionary = repo.manor_buildings.get(b_w, {})
			specs.append({"action_code": "MANOR_RUSH",
				"params": {"manor": code, "building": b_w, "days": per_click},
				"label": "HURRY %s — %dg" % [String(row_w.get("label", b_w)).to_upper(), rush_gold]})
	else:
		# The button says which purse pays (owner 2026-09-14): your own for
		# the realm, the crown's treasury across the border.
		var how := MapManors.purchase_kind(repo, state, cell)
		var purse := "the crown's treasury" if String(how["kind"]) == "foreign" else "your purse"
		specs.append({"action_code": "MANOR_BUY", "params": {"manor": code},
			"label": "BUY — %d gold from %s" % [roundi(MapManors.price_of(repo, state, cell)), purse]})
		if repo.bal("manor_seize_enabled") > 0.0:
			specs.append({"action_code": "MANOR_SEIZE", "params": {"manor": code},
				"label": "SEIZE BY FORCE"})
	var actions := ActionSystem.new(repo)
	for spec: Dictionary in specs:
		spec["error"] = actions.validate(ActionRequest.make(String(spec["action_code"]), spec["params"]), state)
	return specs

## "12 — the crown 7, House Weighhouse 5": a province's manors by holder.
static func holdings_text(repo: DataRepository, state: GameState, province_code: String) -> String:
	var counts := MapManors.holdings_of_province(repo, state, province_code)
	var total := 0
	var parts: Array[String] = []
	var houses: Array = counts.keys()
	houses.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	for h: String in houses:
		total += int(counts[h])
		parts.append("%s %d" % ["the crown" if h == MapManors.crown(state) else "House " + h, int(counts[h])])
	return "%d — %s" % [total, ", ".join(parts)] if total > 0 else "none"

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

## The regiment the crown's own banner flies over: the LAND regiment quartered
## nearest the kingdom's capital (ties to the earlier code). "" when the
## kingdom has no land regiment or no capital. The military layer draws it
## with a crown.
static func royal_regiment(repo: DataRepository, kingdom_code: String) -> String:
	var realm: Dictionary = repo.kingdoms.get(kingdom_code, {})
	var capital: Dictionary = repo.burgs.get(String(realm.get("capital_burg", "")), {})
	if capital.is_empty():
		return ""
	var seat := Vector2(float(capital["x"]), float(capital["y"]))
	var best := ""
	var best_d := INF
	for r: Dictionary in regiments_of(repo, kingdom_code):
		if String(r.get("is_naval", "0")) == "1":
			continue
		var code := String(r["regiment_code"])
		var d := seat.distance_squared_to(Vector2(float(r["x"]), float(r["y"])))
		if d < best_d or (d == best_d and code < best):
			best_d = d
			best = code
	return best

static func _describe_army(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:
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
	# The player's own regiment shows its state and its march (owner
	# 2026-09-19: a click on a counter shows the regiment).
	var st := ArmySystem.state_of(repo, state, code)
	if not st.is_empty():
		var use := ArmySystem.supply_use(repo, r)
		var supplies := int(st["supplies"])
		lines.append("Morale: %d / 100" % int(st["morale"]))
		lines.append("Wounded: %d" % int(st["wounded"]))
		lines.append("Supplies: %d (%s months)" % [supplies,
			("%.1f" % (float(supplies) / float(use))) if use > 0 else "-"])
		lines.append("Training: %s" % ArmySystem.training_grade(repo, int(st["training"])))
		lines.append("Strength: %s" % ArmySystem.strength_grade(repo, state, code))
		lines.append("Ground: %s" % ArmySystem.terrain_label(repo, r))
		lines.append("March: %.1f km a day" % ArmySystem.speed_km_per_day(repo, state, code))
	return {"title": label, "lines": lines,
		"ask": "What is the state of the %s?" % label}

## The painted piece a regiment is drawn with, whose painting heads its card
## (owner 2026-09-15, data/army_art.csv): the fleet for a naval regiment, the
## royal piece for the crown's own (royal_regiment), else its chief arm.
static func army_piece(repo: DataRepository, regiment: Dictionary) -> String:
	if String(regiment.get("is_naval", "0")) == "1":
		return "fleet"
	if String(regiment.get("regiment_code", "")) == royal_regiment(repo, String(regiment.get("kingdom_code", ""))):
		return "royal"
	return regiment_arm(repo, regiment)

## A regiment's fact card (owner 2026-09-15: "军队的 card info 还是 2D 彩绘风格"):
## its piece's painting over the card, and its facts as icons — each arm it
## musters, the whole host under arms, and where it is quartered, and, for
## the player's own regiment with a state, its terrain, morale, wounded,
## supplies, training and strength (ArmySystem, owner 2026-09-17).
static func army_card(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:
	var r: Dictionary = repo.world_table("military", "regiments").get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var kingdom := String(r["kingdom_code"])
	var naval := String(r.get("is_naval", "0")) == "1"
	var province := String(r.get("province_code", ""))
	var total := int(regiment_size(repo, r))
	var piece := army_piece(repo, r)
	var stats: Array = []
	# Only a regiment Intel.level calls "full" — the player's own for now,
	# and (once dev mode is wired to Intel.dev_all, task 7) any regiment
	# under dev mode — gets its arms told apart at a glance; everything else
	# reads the honest headcount word instead, everywhere the total would
	# otherwise show, not just the per-arm muster below.
	var reg_known := Intel.level(repo, state, {"kind": "regiment", "code": code})
	var total_text := str(total) if reg_known == "full" else Intel.magnitude(repo, total)
	if reg_known == "full":
		for unit: String in repo.world_table("military", "unit_types"):
			var n := int(float(r.get(unit, 0)))
			if n <= 0:
				continue
			var unit_label := String((repo.resource_icons.get(unit, {}) as Dictionary).get("label", unit.capitalize()))
			stats.append(_stat(unit, str(n), "%s — %d" % [unit_label, n]))
	else:
		stats.append(_stat("army_total", total_text, "Headcount — " + total_text))
	var st := ArmySystem.state_of(repo, state, code) if state != null else {}
	if st.is_empty():
		stats.append(_stat("army", total_text, "Under arms — %s" % total_text))
	else:
		var wounded := int(st["wounded"])
		stats.append(_stat("army", "%d (%d wounded)" % [total, wounded],
			"Under arms — %d, of whom %d are wounded" % [total, wounded]))
	var fields: Array = [["Under arms", total_text]]
	if province != "":
		var where := _label(repo.provinces, province)
		stats.append(_stat("manor_province", where, "Quartered in %s" % where))
		fields.append(["Quartered in", where])
	if not st.is_empty():
		# The ground, the height and the supply tier are the ground the
		# regiment is on NOW, not the one the pack quartered it on: a column
		# three days down the road fights on what it has reached.
		var ground := ArmySystem.terrain_label(repo, r, state)
		stats.append(_stat("army_terrain", ground, "Quartered on %s" % ground.to_lower()))
		var metres := ArmySystem.elevation_of(repo, r, state)
		var tier := ArmySystem.height_tier(repo, r)
		var mult := float(int(tier["supply_permille"])) / 1000.0
		@warning_ignore("integer_division")  # whole percent from per-mille
		stats.append(_stat("army_height", "%d m · ×%.1f" % [metres, mult],
			"Height — %d m, %s: supplies are used ×%.1f here. In a fight each 100 m above the foe is +%d%% (at most +%d%%), and below it as much less" % [
				metres, String(tier["tier"]), mult,
				int(repo.bal("army_height_bonus_permille_per_100m")) / 10,
				int(repo.bal("army_height_bonus_cap_permille")) / 10]))
		stats.append(_stat("army_morale", str(int(st["morale"])), "Morale — %d of 100" % int(st["morale"])))
		var back := ArmySystem.wound_recovery(repo, int(st["wounded"]))
		stats.append(_stat("army_wounded", "+%d / mo" % back,
			"%d wounded return to the ranks each month" % back))
		var use := ArmySystem.supply_use(repo, r)
		stats.append(_stat("army_supply", "%d (−%d / mo)" % [int(st["supplies"]), use],
			"Supplies — %d held, %d used each month" % [int(st["supplies"]), use]))
		var drill := ArmySystem.training_grade(repo, int(st["training"]))
		stats.append(_stat("army_training", drill, "Training — %s" % drill))
		var might := ArmySystem.strength_grade(repo, state, code)
		stats.append(_stat("army_strength", might, "Strength — %s against the realm's others of its kind" % might))
		var km := ArmySystem.speed_km_per_day(repo, state, code)
		var marching := ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_MARCH
		if marching:
			var days := ArmySystem.days_out(repo, state, code)
			stats.append(_stat("army_march", "%d day%s out" % [days, "" if days == 1 else "s"],
				"On the march — %.1f km a day in clear weather; %d day%s to go in today's weather" % [
					km, days, "" if days == 1 else "s"]))
		else:
			stats.append(_stat("army_march", "%.1f km/day" % km,
				"March — %.1f km a day: its slowest arm's pace, slowed by short supplies, low morale and little training" % km))
		# the base pace above is weather-free; the weather is its own line
		# (spec 2026-09-27-courier-core §1)
		var wx := Weather.at(repo, state, ArmySystem.position_of(repo, state, r), state.absolute_day())
		stats.append(_stat("army_weather", CourierCard.weather_short(repo, wx),
			"Weather here — %s" % Weather.describe_kind(repo, wx)))
	return {
		"kind": "army", "code": code, "title": label,
		"subtitle": "%s of %s" % ["Fleet" if naval else "Regiment", _label(repo.kingdoms, kingdom)],
		"kingdom_code": kingdom, "initial": label.substr(0, 1), "piece": piece,
		"painting": String((repo.army_art.get(piece, {}) as Dictionary).get("painting", "")),
		"stats": stats, "rates": [], "fields": fields, "features": [], "production": [],
		"actions": [], "known": "army", "center": ArmySystem.position_of(repo, state, r),
		"ask": "What is the state of the %s?" % label,
		# A regiment's values ("4564 (0 wounded)", "Hills (fortified)") are too
		# wide for the default 4-column (2-pair) grid in the 120px left column
		# (owner 2026-09-17 review); one icon+value pair per row instead.
		"stat_columns": 2,
	}
