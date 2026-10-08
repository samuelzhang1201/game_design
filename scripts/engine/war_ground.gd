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
	# the garrison is the unit on the seat; the rest of the camp round the town
	# a count (spec 2026-10-07-army-split-and-ground §4.1) — our own towns only
	var garrison: Array[String] = []
	var camped := 0
	if town != "":
		var b: Dictionary = repo.burgs[town]
		town_holder = MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))
		var feats := String(b.get("features", "")).split("|")
		works = "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "town")
		if town_holder == repo.resolve_realm("player_realm"):
			var seat := ArmyGround.seat_of(repo, state, town)
			if seat != "" and ArmyGround.seated_in(repo, state, seat) == town:
				garrison.append(String(ArmySystem.regiment(repo, seat, state).get("label", seat)))
			for r: Dictionary in MapObjects.regiments_of(repo, town_holder, state):
				var c := String(r["regiment_code"])
				if c != seat and ArmyGround.camped_by(repo, state, c) == town:
					camped += 1
	var out := {
		"place": Intel.place_label(repo, state, at),
		"holder": MapOwnership.owner_of(repo, state, prov) if prov != "" else "",
		"sea": sea,
		"terrain": "sea" if sea else ArmySystem.terrain_at(repo, at),
		"metres": Elevation.metres_of_cell(repo, cell),
		"road": "" if sea else ArmySystem.road_at(repo, at),
		"town": town, "works": works, "town_holder": town_holder, "garrison": garrison,
		"camped": camped,
		"weather": Weather.at(repo, state, at, state.absolute_day()) if state != null else Weather.CLEAR,
		"places": _places_near(repo, at),
		"hazards": Hazards.at_point(repo, state, at).filter(func(id: String) -> bool: return Hazards.known(repo, state, id)).map(
			func(id: String) -> Dictionary: return {"id": id, "label": String(state.hazards[id]["label"]),
				"kind": String(state.hazards[id]["kind"]), "months_left": Hazards.months_left(state, id)}) \
			if state != null else [],
		"regiment": {},
	}
	# the war economy at the point (spec 2026-10-07-war-room-p3 §1.3): public,
	# save a home works' live month
	out["trade"] = 0 if sea or String(out["road"]) == "" else WarEconomy.trade_at(repo, at)
	out["making"] = WarEconomy.works(repo).get(town, {}) if town != "" else {}
	out["making_live"] = -1
	if not (out["making"] as Dictionary).is_empty() and state != null and town_holder == repo.resolve_realm("player_realm"):
		var town_cell := int(MapEconomy.burg_cells(repo).get(town, -1))
		if town_cell >= 0:
			out["making_live"] = int(ManorEconomy.line_of(repo, state, town_cell, state.tick)["strategic"])
	out["market"] = {}
	var market := WarEconomy.market_of_town(repo, town) if town != "" else ""
	if market != "":
		out["market"] = {"id": market, "label": String(repo.burgs[town].get("label", town)),
			"holder": MarketSystem.kingdom_of_party(repo, state, "market", market) if state != null else "",
			"food_permille": WarEconomy.food_price_permille(repo, market)}
	if code != "":
		out["regiment"] = _for_regiment(repo, state, at, code, out)
	return out


static func _for_regiment(repo: DataRepository, state: GameState, at: Vector2, code: String, g: Dictionary) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code, state)
	var naval := String(reg.get("is_naval", "0")) == "1"
	var out := {"code": code, "label": String(reg.get("label", code)), "ashore": naval and not bool(g["sea"]),
		"afloat": not naval and bool(g["sea"])}   # ARMY_MARCH refuses the sea: no pace, no days
	if bool(out["ashore"]) or bool(out["afloat"]):
		return out
	# the town's works are the seat's alone (§4.1): the unit on it, or one
	# that would take it empty on arrival (§4.3); a camp fights on the field
	var works := ""
	if String(g["town"]) != "" and String(g["town_holder"]) == String(reg.get("kingdom_code", "")):
		var seat := ArmyGround.seat_of(repo, state, String(g["town"]))
		if seat == "" or seat == code:
			works = String(g["works"])
	out["defend"] = _factor(repo, state, code, "defend", String(g["terrain"]), works)
	out["attack"] = _factor(repo, state, code, "attack", String(g["terrain"]), "")
	out["delta_m"] = int(g["metres"]) - ArmySystem.elevation_of(repo, reg, state)
	out["height"] = ArmySystem.height_factor(repo, int(out["delta_m"]))
	out["ground"] = ArmySystem.ground_permille(repo, reg, at, state)
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
		_hazard_lines(repo, r, out)
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
		var camp := int(r.get("camped", 0))
		if not (r["garrison"] as Array).is_empty():
			_add(out, "Garrison: " + ", ".join(r["garrison"]) + (" · %d camped round it" % camp if camp > 0 else ""))
		elif camp > 0:
			_add(out, "No garrison · %d camped round it" % camp)
	_economy_lines(repo, r, out)
	_add(out, "Weather: " + Weather.describe_kind(repo, String(r["weather"])))
	_hazard_lines(repo, r, out)
	_place_lines(repo, r, out)
	_regiment_lines(repo, r, raking, out)
	return out


## A known hazard at the point: its name, months left and what it does.
static func _hazard_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	for h: Dictionary in r.get("hazards", []):
		var left := int(h["months_left"])
		var when := "" if left < 0 else " — %d month%s left" % [left, "" if left == 1 else "s"]
		_add(out, "%s%s: %s" % [String(h["label"]), when, hazard_words(repo, String(h["kind"]))])


## The war economy at the point (spec 2026-10-07-war-room-p3 §1.3): the trade
## passing on the road, a works' goods (at home with this month's gold), a
## market and its food price against the catalogue.
static func _economy_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	if int(r.get("trade", 0)) > 0:
		_add(out, "Trade: about %s gold a month passes" % Intel.num(int(r["trade"])))
	var mk: Dictionary = r.get("making", {})
	if not mk.is_empty():
		var parts: Array[String] = []
		for g: Dictionary in (mk["goods"] as Array).slice(0, 3):
			parts.append(WarEconomy.good_label(repo, String(g["good"])).to_lower())   # the pack's units mean nothing to a reader: the gold below says how much
		var text := "Works: %s (%s gold a month)" % [", ".join(parts), Intel.num(int(mk["gold"]))]
		if int(r.get("making_live", -1)) >= 0:
			text += " (this month: %s)" % Intel.num(int(r["making_live"]))
		_add(out, text)
	var m: Dictionary = r.get("market", {})
	if not m.is_empty():
		var holder := String(m["holder"])
		var whose := "ours" if holder == repo.resolve_realm("player_realm") \
			else String((repo.kingdoms.get(holder, {}) as Dictionary).get("label", holder))
		_add(out, "Market of %s (%s) — food at ×%s" % [String(m["label"]), whose,
			String.num(float(int(m["food_permille"])) / 1000.0, 2)])

## A kind's effects in words (data/hazard_kinds.csv).
static func hazard_words(repo: DataRepository, kind: String) -> String:
	var k := Hazards.kind_of(repo, kind)
	var parts: Array[String] = []
	if int(k.get("wounds_permille", 0)) > 0:
		parts.append("regiments here lose about %s%% a month" % String.num(float(k["wounds_permille"]) / 10.0, 1))
	if int(k.get("morale", 0)) < 0:
		parts.append("morale held %d lower here" % -int(k["morale"]))
	if int(k.get("supply_loss_permille", 0)) > 0:
		@warning_ignore("integer_division")
		parts.append("supply lines through it lose %d%%" % (int(k["supply_loss_permille"]) / 10))
	if int(k.get("pace_permille", 1000)) < 1000:
		parts.append("marches here go at ×%.2f" % (float(k["pace_permille"]) / 1000.0))
	return "; ".join(parts) if not parts.is_empty() else "no effect on a march"


## The marks the slip names: within war_mark_hover_km, or within a hazard's
## own reach (a pointer inside a brigands' dotted ring names them), nearest
## first, at most war_mark_hover_max.
static func _places_near(repo: DataRepository, at: Vector2) -> Array:
	var hover := repo.bal("war_mark_hover_km")
	var widest := hover
	for t: String in repo.war_mark_hazards:
		widest = maxf(widest, float(repo.war_mark_hazards[t]["reach_km"]))
	var out: Array = []
	for p: Dictionary in WarMarks.near(repo, at, widest, 1 << 20):
		var hz: Dictionary = repo.war_mark_hazards.get(String(p["type"]), {})
		var reach := float(hz["reach_km"]) if not hz.is_empty() else hover
		if float(p["distance_km"]) <= maxf(hover, reach):
			out.append(p)
	return out.slice(0, int(repo.bal("war_mark_hover_max")))


## A mark's legend as the slip shows it: the export's markup stripped, cut at
## a word within war_mark_legend_chars with an ellipsis.
static func legend_of(repo: DataRepository, text: String) -> String:
	var plain := RegEx.create_from_string("<[^>]*>").sub(text, " ", true)
	plain = RegEx.create_from_string("<.*$").sub(plain, "")   # a tag the cut left open
	plain = RegEx.create_from_string("\\s+").sub(plain, " ", true).strip_edges()
	var cap := int(repo.bal("war_mark_legend_chars"))
	if plain.length() <= cap:
		return plain
	var cut := plain.substr(0, cap)
	var space := cut.rfind(" ")
	@warning_ignore("integer_division")  # half the cap, whole
	if space > cap / 2:
		cut = cut.substr(0, space)
	return cut.rstrip(" ,;:—-") + "…"


## The marks near the pointer (spec 2026-10-07-war-room-p2 §1.3): one line
## each, nearest first, a hazard's toll on supply; the nearest one's legend.
static func _place_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	var places: Array = r.get("places", [])
	for p: Dictionary in places:
		var hz: Dictionary = repo.war_mark_hazards.get(String(p["type"]), {})
		# a hazard's own words are its toll, on a line of its own (its legend
		# below says what it is); figures and units never broken apart
		var what := "" if not hz.is_empty() and String(p["legend"]) != "" else " — " + String(p["note"])
		_add(out, "%s, %d\u00a0km%s" % [String(p["label"]), roundi(float(p["distance_km"])), what])
		if not hz.is_empty():
			@warning_ignore("integer_division")
			_add(out, "Supply lines within %d\u00a0km lose %d%%" % [int(hz["reach_km"]), int(hz["permille"]) / 10])
	if not places.is_empty():
		var legend := legend_of(repo, String(places[0]["legend"]))
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


# --- a supposed piece (spec 2026-10-07-war-room-annotations-and-planning-pieces §1.2)

## What the slip says of a supposed piece (WarPlans): the ground under it (as
## `reading`), and in `plan` its men on this ground — heads × its power here
## over its power on open plains with no works, at the ASSUMED training and
## morale (war_plan_training / war_plan_morale, no hidden float); works only in
## a town its side holds. With a crown regiment chosen (`code`), `regiment`
## sets them side by side: ours attacking on its ground, theirs defending,
## each scaled by the height between them — figures, never an odds (the
## battle formula is open). `piece`: {arm, heads, side} and `at` (pack px) or
## x_m / y_m. Read-only.
static func plan_reading(repo: DataRepository, state: GameState, piece: Dictionary, code: String) -> Dictionary:
	var at: Vector2 = piece["at"] if piece.has("at") else WarPlans.at_px(repo, piece)
	var out := reading(repo, state, at, "")
	var arm := String(piece["arm"])
	var heads := int(piece["heads"])
	var side := String(piece["side"])
	var works := String(out["works"]) if String(out["town"]) != "" and side != WarPlans.UNKNOWN \
		and String(out["town_holder"]) == side else ""
	var terrain := String(out["terrain"])
	var defend_f := _plan_factor(repo, arm, heads, "defend", terrain, works)
	var attack_f := _plan_factor(repo, arm, heads, "attack", terrain, "")
	@warning_ignore("integer_division")  # whole men
	var defend := heads * defend_f / 1000
	@warning_ignore("integer_division")  # whole men
	var attack := heads * attack_f / 1000
	out["plan"] = {"arm": arm, "heads": heads, "side": side, "works": works,
		"defend_f": defend_f, "attack_f": attack_f, "defend": defend, "attack": attack}
	out["regiment"] = {}
	if code == "" or bool(out["sea"]):
		return out
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return out
	var delta := ArmySystem.elevation_of(repo, reg, state) - int(out["metres"])
	var heads_ours := ArmySystem.headcount(repo, reg)
	var fit := heads_ours - clampi(int(ArmySystem.state_of(repo, state, code).get("wounded", 0)), 0, heads_ours)
	@warning_ignore("integer_division")  # whole men, per-mille factors
	var ours := fit * _factor(repo, state, code, "attack", terrain, "") / 1000 * ArmySystem.height_factor(repo, delta) / 1000
	@warning_ignore("integer_division")  # whole men, per-mille height
	var theirs := defend * ArmySystem.height_factor(repo, -delta) / 1000
	var step := ArmySystem.day_march_at(repo, state, code, at)
	out["regiment"] = {"code": code, "label": String(reg.get("label", code)), "delta_m": delta,
		"height": ArmySystem.height_factor(repo, delta), "ours": ours, "theirs": theirs,
		"days": ArmySystem.march_days_between(repo, state, code, ArmySystem.position_of(repo, state, reg), at) if step > 0 else 0}
	return out


## A supposed host's power on a ground over its power on open plains with no
## works, per mille; 0 for none.
static func _plan_factor(repo: DataRepository, arm: String, heads: int, stance: String, terrain: String, works: String) -> int:
	var t := int(repo.bal("war_plan_training"))
	var m := int(repo.bal("war_plan_morale"))
	var base := ArmySystem.power_of_arms(repo, {arm: heads}, heads, t, m, stance, "plains", "")
	if base <= 0:
		return 0
	@warning_ignore("integer_division")  # whole per mille
	return ArmySystem.power_of_arms(repo, {arm: heads}, heads, t, m, stance, terrain, works) * 1000 / base


## The side's name: its kingdom's label, or "Unknown".
static func side_label(repo: DataRepository, side: String) -> String:
	if side == WarPlans.UNKNOWN:
		return "Unknown"
	return String((repo.kingdoms.get(side, {}) as Dictionary).get("label", side))


## The arm's short word on a tag and a title ("foot", "horse").
static func arm_word(repo: DataRepository, arm: String) -> String:
	return String(repo.war_order_words.get("arm_" + arm, arm))


## The slip's lines for a supposed piece.
static func plan_lines(repo: DataRepository, r: Dictionary) -> Array:
	var p: Dictionary = r["plan"]
	var out: Array = []
	out.append({"text": "Supposed %s" % arm_word(repo, String(p["arm"])), "kind": "title"})
	out.append({"text": side_label(repo, String(p["side"])), "kind": "sub"})
	var types: Dictionary = repo.world_table("military", "unit_types")
	var arm_label := String((types.get(String(p["arm"]), {}) as Dictionary).get("label", p["arm"])).to_lower()
	var grade := ArmySystem.training_grade(repo, int(repo.bal("war_plan_training"))).to_lower()
	_add(out, "%s %s · assumed %s" % [Intel.num(int(p["heads"])), arm_label, grade])
	var ground := "%s · %s m" % [String(r["terrain"]).capitalize(), Intel.num(int(r["metres"]))]
	match String(r["road"]):
		"road":
			ground += " · on a road"
		"trail":
			ground += " · on a trail"
	_add(out, ground)
	if String(p["works"]) != "":
		var name := String((repo.burgs[r["town"]] as Dictionary).get("label", r["town"]))
		_add(out, ({"citadel": "In the citadel of %s", "walls": "Behind the walls of %s"} as Dictionary).get(
			String(p["works"]), "In %s") % name + " (theirs)")
	_add(out, "Defends as %s (×%.2f %s)" % [Intel.num(int(p["defend"])), float(p["defend_f"]) / 1000.0, String(r["terrain"])])
	_add(out, "Attacks as %s (×%.2f)" % [Intel.num(int(p["attack"])), float(p["attack_f"]) / 1000.0])
	_add(out, "Weather: " + Weather.describe_kind(repo, String(r["weather"])))
	var g: Dictionary = r["regiment"]
	if g.is_empty():
		return out
	out.append({"text": "", "kind": "rule"})
	out.append({"text": "%s against it" % g["label"], "kind": "rubric"})
	var d := int(g["delta_m"])
	if d == 0:
		_add(out, "It attacks level with them")
	else:
		_add(out, "It attacks from %d m %s (×%.2f)" % [absi(d), "above" if d > 0 else "below", float(g["height"]) / 1000.0])
	_add(out, "Theirs %s · ours %s on this ground" % [Intel.num(int(g["theirs"])), Intel.num(int(g["ours"]))])
	if int(g["days"]) > 0:
		_add(out, "About a day's march" if int(g["days"]) == 1 else "About %d days' march" % int(g["days"]))
	return out


static func _add(out: Array, text: String) -> void:
	out.append({"text": text, "kind": "line"})
