class_name WarGround
extends RefCounted
## What the ground under the WAR ROOM's pointer means (spec
## 2026-10-07-war-room-scale-hover §4.1): the place, the ground, the town and
## the weather; with a regiment chosen, its defend and attack against open
## plains, its height against where it stands, its pace and the days to get
## there. Read-only; never a foreign force or a foreign garrison.


static func reading(repo: DataRepository, state: GameState, at: Vector2, code: String) -> Dictionary:
	var cell := MapEconomy.cell_at(repo, at)
	var sea := cell < 0 or MapTerrain.is_water(repo.cells[cell])
	var prov := MapManors.province_of(repo, cell, state) if cell >= 0 else ""
	var town := "" if sea else ArmySystem.town_at(repo, at)
	var town_holder := ""
	var works := ""
	var garrison: Array[String] = []
	if town != "":
		var b: Dictionary = repo.burgs[town]
		town_holder = MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))
		var feats := String(b.get("features", "")).split("|")
		works = "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "town")
		if town_holder == repo.resolve_realm("player_realm"):
			for r: Dictionary in MapObjects.regiments_of(repo, town_holder):
				if ArmySystem.town_of(repo, r, state) == town:
					garrison.append(String(r.get("label", r["regiment_code"])))
	var out := {
		"place": Intel.place_label(repo, state, at),
		"holder": MapOwnership.owner_of(repo, state, prov) if prov != "" else "",
		"sea": sea,
		"terrain": "sea" if sea else ArmySystem.terrain_at(repo, at),
		"metres": Elevation.metres_of_cell(repo, cell),
		"road": "" if sea else ArmySystem.road_at(repo, at),
		"town": town, "works": works, "town_holder": town_holder, "garrison": garrison,
		"weather": Weather.at(repo, state, at, state.absolute_day()) if state != null else Weather.CLEAR,
		"places": WarMarks.near(repo, at, repo.bal("war_mark_hover_km"), int(repo.bal("war_mark_hover_max"))),
		"regiment": {},
	}
	if code != "":
		out["regiment"] = _for_regiment(repo, state, at, code, out)
	return out


static func _for_regiment(repo: DataRepository, state: GameState, at: Vector2, code: String, g: Dictionary) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code)
	var naval := String(reg.get("is_naval", "0")) == "1"
	var out := {"code": code, "label": String(reg.get("label", code)), "ashore": naval and not bool(g["sea"]),
		"afloat": not naval and bool(g["sea"])}   # ARMY_MARCH refuses the sea: no pace, no days
	if bool(out["ashore"]) or bool(out["afloat"]):
		return out
	var works := String(g["works"]) if String(g["town"]) != "" and String(g["town_holder"]) == String(reg.get("kingdom_code", "")) else ""
	out["defend"] = _factor(repo, state, code, "defend", String(g["terrain"]), works)
	out["attack"] = _factor(repo, state, code, "attack", String(g["terrain"]), "")
	out["delta_m"] = int(g["metres"]) - ArmySystem.elevation_of(repo, reg, state)
	out["height"] = ArmySystem.height_factor(repo, int(out["delta_m"]))
	out["ground"] = ArmySystem.ground_permille(repo, reg, at)
	var step := ArmySystem.day_march_at(repo, state, code, at)
	out["km_day"] = float(maxi(step, 0)) / 1000.0
	out["days"] = ArmySystem.march_days_between(repo, state, code, ArmySystem.position_of(repo, state, reg), at) if step > 0 else 0
	return out


## Power on this ground over power on open plains with no works, per mille;
## 0 for a regiment with no power.
static func _factor(repo: DataRepository, state: GameState, code: String, stance: String, terrain: String, works: String) -> int:
	var base := ArmySystem.power_on(repo, state, code, stance, "plains", "")
	if base <= 0:
		return 0
	@warning_ignore("integer_division")  # whole per mille
	return ArmySystem.power_on(repo, state, code, stance, terrain, works) * 1000 / base


## The slip's lines, in order. `raking`: the arrow's reading already carries
## the days, so they are left out.
static func lines(repo: DataRepository, r: Dictionary, raking := false) -> Array:
	var out: Array = []
	out.append({"text": String(r["place"]), "kind": "title"})
	if bool(r["sea"]):
		_add(out, "Weather: " + Weather.describe_kind(repo, String(r["weather"])))
		_place_lines(repo, r, out)
		_regiment_lines(repo, r, raking, out)
		return out
	if String(r["holder"]) != "":
		out.append({"text": String((repo.kingdoms.get(r["holder"], {}) as Dictionary).get("label", r["holder"])), "kind": "sub"})
	_add(out, "%s · %s m" % [String(r["terrain"]).capitalize(), Intel.num(int(r["metres"]))])
	match String(r["road"]):
		"road":
			_add(out, "On a road")
		"trail":
			_add(out, "On a trail")
		_:
			_add(out, "Open field — no road within %s km" % String.num(repo.bal("army_road_reach_m") / 1000.0, 1))
	if String(r["town"]) != "":
		var b: Dictionary = repo.burgs[r["town"]]
		var name := String(b.get("label", r["town"]))
		var text: String = {"citadel": "In the citadel of %s", "walls": "Behind the walls of %s"}.get(String(r["works"]), "In %s") % name
		if String(r["town_holder"]) != "" and String(r["town_holder"]) != repo.resolve_realm("player_realm"):
			text += " — held by " + String((repo.kingdoms.get(r["town_holder"], {}) as Dictionary).get("label", r["town_holder"]))
		_add(out, text)
		if not (r["garrison"] as Array).is_empty():
			_add(out, "Garrison: " + ", ".join(r["garrison"]))
	_add(out, "Weather: " + Weather.describe_kind(repo, String(r["weather"])))
	_place_lines(repo, r, out)
	_regiment_lines(repo, r, raking, out)
	return out


## The marks near the pointer (spec 2026-10-07-war-room-p2 §1.3): one line
## each, nearest first, a hazard's toll on supply; the nearest one's legend.
static func _place_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	var places: Array = r.get("places", [])
	for p: Dictionary in places:
		var text := "%s, %d km — %s" % [String(p["label"]), roundi(float(p["distance_km"])), String(p["note"])]
		var hz: Dictionary = repo.war_mark_hazards.get(String(p["type"]), {})
		if not hz.is_empty():
			@warning_ignore("integer_division")
			text += "; supply lines within %d km lose %d%%" % [int(hz["reach_km"]), int(hz["permille"]) / 10]
		_add(out, text)
	if not places.is_empty():
		var legend := String(places[0]["legend"]).substr(0, int(repo.bal("war_mark_legend_chars")))
		if legend != "":
			out.append({"text": legend, "kind": "sub"})

static func _regiment_lines(_repo: DataRepository, r: Dictionary, raking: bool, out: Array) -> void:
	var g: Dictionary = r["regiment"]
	if g.is_empty():
		return
	out.append({"text": "", "kind": "rule"})
	out.append({"text": "%s here" % g["label"], "kind": "rubric"})
	if bool(g["ashore"]):
		_add(out, "A fleet cannot go ashore")
		return
	if bool(g.get("afloat", false)):
		_add(out, "It cannot march into the sea")
		return
	_add(out, "Defend ×%.2f · Attack ×%.2f" % [float(g["defend"]) / 1000.0, float(g["attack"]) / 1000.0])
	var d := int(g["delta_m"])
	if d == 0:
		_add(out, "Level with its ground now")
	else:
		_add(out, "%d m %s its ground now (×%.2f)" % [absi(d), "above" if d > 0 else "below", float(g["height"]) / 1000.0])
	if float(g["km_day"]) <= 0.0:
		_add(out, "It cannot march")
		return
	var pace := "Pace ×%.2f · about %d km a day" % [float(g["ground"]) / 1000.0, roundi(float(g["km_day"]))]
	if not raking:
		pace += " · %d day%s away" % [int(g["days"]), "" if int(g["days"]) == 1 else "s"]
	_add(out, pace)


static func _add(out: Array, text: String) -> void:
	out.append({"text": text, "kind": "line"})
