# scripts/engine/war_folio.gd
class_name WarFolio
extends RefCounted
## The WAR ROOM folio's right page and drill tabs (owner 2026-10-01, spec
## 2026-10-01-war-room-design §4). Sections are data/war_folio_sections.csv
## rows, each with a builder here; every figure is gated by Intel (exact for
## the crown's own, so intel P2's blur reaches the folio unchanged). Training
## shows only as its grade word. No history: nothing stores it.

const BUILDERS := ["composition", "arms", "morale", "supply", "ground", "march"]


static func has_builder(key: String) -> bool:
	return key in BUILDERS


static func sections(repo: DataRepository, state: GameState, code: String) -> Array:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty():
		return []
	if Intel.level(repo, state, {"kind": "regiment", "code": code}) != "full":
		return [{"key": "composition", "label": _label_of(repo, "composition"),
			"rows": [_row("Under arms", Intel.magnitude(repo, ArmySystem.headcount(repo, reg)))]}]
	var out: Array = []
	for s: Dictionary in repo.war_folio_sections:
		var key := String(s["key"])
		var rows: Array = []
		match key:
			"composition":
				rows = _composition(repo, state, code, reg)
			"arms":
				rows = _arms(repo, state, code, reg)
			"morale":
				rows = _morale(repo, state, code, reg)
			"supply":
				rows = _supply(repo, state, code, reg)
			"ground":
				rows = _ground(repo, state, code, reg)
			"march":
				rows = _march(repo, state, code, reg)
			_:
				push_error("war_folio_sections.csv: no builder for " + key)
				continue
		out.append({"key": key, "label": String(s["label"]), "rows": rows})
	return out


## The DOCKED folio's single page (owner 2026-10-08: the book shrinks to the
## room's upper-left): the regiment's name and the rows an officer reads at a
## glance — heads by arm, morale, stores with their days, the line, the ground,
## the order and the pace. {title, rows: [{label, text}]}; gated by Intel like
## sections (a regiment not fully known gives only its headcount word).
static func brief(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty():
		return {"title": "", "rows": []}
	var title := String(reg.get("label", code))
	var heads := ArmySystem.headcount(repo, reg)
	if Intel.level(repo, state, {"kind": "regiment", "code": code}) != "full":
		return {"title": title, "rows": [_row("Under arms", Intel.magnitude(repo, heads))]}
	var st := _state_of(repo, state, code, reg)
	var wounded := clampi(int(st.get("wounded", 0)), 0, heads)
	var dead := clampi(int(st.get("dead", 0)), 0, heads)
	var under := WarRoom.group(ArmySystem.under_arms(heads, st))
	if wounded > 0:
		under += " · %s fit" % WarRoom.group(ArmySystem.fit_heads(heads, st))
	var arms: Array[String] = []
	for a: Dictionary in arms_of(repo, code):
		arms.append("%s %s" % [_arm_label(repo, String(a["arm"])), WarRoom.group(int(a["heads"]))])
	var use := ArmySystem.supply_use(repo, reg, state)
	var supplies := int(st["supplies"])
	var score := ArmySystem.supply_score(repo, supplies, use)
	var stores := WarRoom.group(supplies)
	if use > 0:
		var days := mini(ArmySystem.days_in_hand(supplies, use), 999)
		stores += " (≈ %d day%s)" % [days, "" if days == 1 else "s"]
	var rows: Array = [_row("Under arms", under), _row("Arms", " · ".join(arms)),
		_row("Morale", "%d / 100 — %s" % [int(st["morale"]), ArmySystem.morale_word(repo, score)]),
		_row("Supplies", stores)]
	rows.append_array(conduct_rows(repo, st))
	if state.regiments.has(code):
		var line := SupplySystem.line_of(repo, state, code)
		var town := String(line["town"])
		rows.append(_row("Line", "no supply point" if town == "" else "%s from %s, %d km" % [
			String(line["state"]), String((repo.burgs.get(town, {}) as Dictionary).get("label", "")),
			int(line["length_km"])]))
	rows.append(_row("Ground", "%s, %d m" % [ArmySystem.terrain_label(repo, reg, state),
		ArmySystem.elevation_of(repo, reg, state)]))
	var order := ArmySystem.order_of(repo, state, code)
	var shown := order
	# the garrison is the seat's alone (spec 2026-10-07-army-split-and-ground §4.1)
	if order == ArmySystem.ORDER_GARRISON and ArmyGround.seated_in(repo, state, code) == "":
		shown = "camped" if ArmyGround.camped_by(repo, state, code) != "" else "camp"
	var said := order_word(repo, shown)
	if order == ArmySystem.ORDER_MARCH:
		var dest := ArmySystem.destination_of(repo, state, code)
		var si := WarSheets.sheet_of(repo, dest)
		if si >= 0:
			said += " to " + WarSheets.grid_ref(repo, WarSheets.series(repo)[si], dest)
		var days := CourierSystem.days_to_arrival(repo, state, code)
		said += ", in %d day%s" % [days, "" if days == 1 else "s"]
	rows.append(_row("Order", said))
	@warning_ignore("integer_division")
	var readiness := ArmySystem.bars_of(repo, state, code).x / 10
	rows.append(_row("Pace", "%.1f km a day · ready %d%%" % [
		ArmySystem.speed_km_per_day(repo, state, code), readiness]))
	return {"title": title, "rows": rows}


static func _label_of(repo: DataRepository, key: String) -> String:
	for s: Dictionary in repo.war_folio_sections:
		if String(s["key"]) == key:
			return String(s["label"])
	return key.capitalize()


## A regiment's state for the page: the stored one, else what it would start
## with (a foreign regiment under DEV MODE has none; ArmySystem.bars_of does the same).
static func _state_of(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Dictionary:
	var st := ArmySystem.state_of(repo, state, code)
	return st if not st.is_empty() else ArmySystem.starting_state(repo, reg)


## The rows foraging and desertion add (spec 2026-10-10-foraging-and-desertion
## §4; words in data/conduct_words.csv): how the unit is living, and its deserters.
static func conduct_rows(repo: DataRepository, st: Dictionary) -> Array:
	var rows: Array = []
	var forage := String(st.get("forage", ""))
	if forage != "":
		var said := String(repo.conduct_words.get("state_law", "")) if forage == "law" \
			else String(repo.conduct_words.get("state_desperate", ""))
		rows.append(_row(String(repo.conduct_words.get("row_foraging", "")), said))
	if int(st.get("deserted", 0)) > 0:
		rows.append(_row(String(repo.conduct_words.get("row_deserted", "")), str(int(st["deserted"]))))
	return rows


static func _row(label: String, text: String) -> Dictionary:
	return {"label": label, "text": text}


static func arms_of(repo: DataRepository, code: String) -> Array:
	var reg := ArmySystem.regiment(repo, code)
	var out: Array = []
	for arm: String in repo.world_table("military", "unit_types"):
		var n := int(float(reg.get(arm, 0)))
		if n > 0:
			out.append({"arm": arm, "heads": n})
	return out


static func _arm_label(repo: DataRepository, arm: String) -> String:
	return String((repo.resource_icons.get(arm, {}) as Dictionary).get("label", arm.capitalize()))


static func figures(repo: DataRepository, state: GameState, code: String) -> int:
	var fit := ArmySystem.fit_permille(repo, state, code)
	var best := 1
	for row: Dictionary in repo.army_formations:
		if fit >= int(row["min_fit_permille"]):
			best = int(row["figures"])
	return best


static func _tier_word(n: int) -> String:
	match n:
		9:
			return "full strength"
		6:
			return "depleted"
	return "remnants"


static func _composition(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Array:
	var st := _state_of(repo, state, code, reg)
	# the dead and the deserted are no longer under arms
	var heads := ArmySystem.headcount(repo, reg)
	var rows: Array = [_row("Under arms", WarRoom.group(ArmySystem.under_arms(heads, st)))]
	for a: Dictionary in arms_of(repo, code):
		rows.append(_row(_arm_label(repo, String(a["arm"])), WarRoom.group(int(a["heads"]))))
	var wounded := int(st.get("wounded", 0))
	rows.append(_row("Fit", WarRoom.group(ArmySystem.fit_heads(ArmySystem.headcount(repo, reg), st))))
	rows.append(_row("Wounded", WarRoom.group(wounded)))
	var n := figures(repo, state, code)
	rows.append(_row("Formation", "%d figures — %s" % [n, _tier_word(n)]))
	return rows


static func kit_of(repo: DataRepository, arm: String) -> Array:
	return repo.war_equipment.filter(func(r: Dictionary) -> bool: return String(r["arm"]) == arm)


static func _arms(repo: DataRepository, _state: GameState, code: String, _reg: Dictionary) -> Array:
	var rows: Array = []
	var seen: Dictionary = {}   # two arms that share a piece of kit show it once, the first arm's
	for a: Dictionary in arms_of(repo, code):
		var arm := String(a["arm"])
		for k: Dictionary in kit_of(repo, arm):
			if seen.has(String(k["label"])):
				continue
			seen[String(k["label"])] = true
			rows.append(_row(String(k["label"]), String(k["note"])))
		var good: Array[String] = []
		var holds: Array[String] = []
		var wary: Array[String] = []
		for m: Dictionary in repo.army_matchups.get(arm, []):
			var vs := _arm_label(repo, String(m["vs"])).to_lower()
			if int(m["attack"]) > 1000:
				good.append(vs)
			if int(m["defense"]) > 1000:
				holds.append(vs)
			if int(m["defense"]) < 1000:
				wary.append(vs)
		var parts: Array[String] = []
		if not good.is_empty():
			parts.append("good against " + ", ".join(good))
		if not holds.is_empty():
			parts.append("holds against " + ", ".join(holds))
		if not wary.is_empty():
			parts.append("wary of " + ", ".join(wary))
		if not parts.is_empty():
			rows.append(_row("Matchups — " + _arm_label(repo, arm), "; ".join(parts)))
	return rows


static func _morale(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Array:
	var st := _state_of(repo, state, code, reg)
	var score := ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, reg, state))
	var garrison := ArmyGround.seated_in(repo, state, code) != ""
	# the camp laws it follows add their mark (laws spec §4.1), as settle_month does
	var laws := LawEffects.unit_mark(repo, state, code)
	var mark := clampi(ArmySystem.morale_mark(repo, score, garrison) + laws, 0, 100)
	var rows: Array = [_row("Morale", "%d / 100" % int(st["morale"])),
		_row("Heading for (by today's stores)", "%d — the ranks are %s" % [mark, ArmySystem.morale_word(repo, score)])]
	if garrison:
		rows.append(_row("In garrison", "+%d" % int(repo.bal("army_morale_garrison_bonus"))))
	if laws != 0:
		rows.append(_row("The camp laws", ("%+d" % laws).replace("-", "−")))
	rows.append(_row("Drift", "%d a month" % int(repo.bal("army_morale_drift_per_month"))))
	return rows


static func _supply(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Array:
	var st := _state_of(repo, state, code, reg)
	var use := ArmySystem.supply_use(repo, reg, state)
	var supplies := int(st["supplies"])
	var rows: Array = [
		_row("In hand", "%s (%d days of %d)" % [WarRoom.group(supplies),
			mini(ArmySystem.days_in_hand(supplies, use), 999), ArmySystem.carry_of(repo, st)]),
		_row("Eaten today", WarRoom.group(ArmySystem.day_bite(use, state.day)))]
	if state.regiments.has(code):
		var line := SupplySystem.line_of(repo, state, code)
		var from := String((repo.burgs.get(String(line["town"]), {}) as Dictionary).get("label", ""))
		var refill := SupplyLines.refill_words(repo, state, code)
		var text := "no supply point"
		if String(line["town"]) != "":
			@warning_ignore("integer_division")
			var lost := int(line["loss_permille"]) / 10
			text = "%s from %s, %.1f×, %d km, %d%% lost" % [String(line["state"]), from,
				float(int(line["rate"])) / 1000.0, int(line["length_km"]), lost]
			var named: Array = (line.get("hazards", []) as Array).map(func(h: Dictionary) -> String:
				@warning_ignore("integer_division")
				return "%d%% to the %s" % [int(h["permille"]) / 10, String(h["label"])])
			if not named.is_empty():
				text += " (%s)" % ", ".join(named)
		if refill != "":
			text += "; " + refill
		rows.append(_row("Line", text))
	rows.append_array(conduct_rows(repo, st))
	var f := Governance.factors(repo, state, "supply_line")
	var gid := String(f["governor"])
	if gid == "":
		rows.append(_row("Governed by", "no one"))
	else:
		@warning_ignore("integer_division")
		var runs := int(f["efficiency"]) / 10
		rows.append(_row("Governed by", "%s — runs it at %d%%, skill %d" % [
			(state.characters[gid] as Character).display_name, runs, int(f["skill"])]))
	return rows


static func _ground(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Array:
	var at := WarRoom.believed_position(repo, state, reg)
	var all := WarSheets.series(repo)
	var si := WarSheets.sheet_of(repo, at)
	var rows: Array = []
	if si >= 0:
		rows.append(_row("Place", WarSheets.grid_ref(repo, all[si], at)))
	var terrain := ArmySystem.terrain_of(repo, reg, state)
	rows.append(_row("Ground", ArmySystem.terrain_label(repo, reg, state)))
	var tier := ArmySystem.height_tier(repo, reg, state)
	rows.append(_row("Height", "%d m, %s" % [ArmySystem.elevation_of(repo, reg, state), String(tier["tier"])]))
	rows.append(_row("Supplies used", "×%.1f" % (float(int(tier["supply_permille"])) / 1000.0)))
	for a: Dictionary in arms_of(repo, code):
		var t: Dictionary = repo.army_terrain.get("%s|%s" % [terrain, String(a["arm"])], {})
		if not t.is_empty():
			@warning_ignore("integer_division")
			var defends := int(t["defend"]) / 10
			@warning_ignore("integer_division")
			var attacks := int(t["attack"]) / 10
			rows.append(_row(_arm_label(repo, String(a["arm"])), "defends at %d%%, attacks at %d%%" % [
				defends, attacks]))
	rows.append(_row("Weather", Weather.describe_kind(repo, Weather.at(repo, state, at, state.absolute_day()))))
	return rows


static func _march(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Array:
	var st := _state_of(repo, state, code, reg)
	var bars := ArmySystem.bars_of(repo, state, code)
	var score := ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, reg, state))
	@warning_ignore("integer_division")
	var readiness := bars.x / 10
	@warning_ignore("integer_division")
	var supplies_pct := clampi(score, 0, 1000) / 10
	var grade := ArmySystem.training_grade(repo, int(st["training"]))
	# the four parts of readiness (ArmySystem.readiness_permille): the arm is
	# always whole; training stays hidden, its grade word only (spec §4)
	var rows: Array = [_row("Pace", "%.1f km a day" % ArmySystem.speed_km_per_day(repo, state, code)),
		_row("Ground pace", ArmySystem.ground_word(repo, state, reg)),
		_row("Readiness", "%d%%" % readiness),
		_row("Readiness parts", "arm 100%%, supplies %d%%, morale %d%%, training %s" % [
			supplies_pct, clampi(int(st["morale"]), 0, 100), grade]),
		_row("Readiness weights", "arm %d, supplies %d, morale %d, training %d" % [
			int(repo.bal("army_speed_w_arm")), int(repo.bal("army_speed_w_supply")),
			int(repo.bal("army_speed_w_morale")), int(repo.bal("army_speed_w_training"))]),
		_row("Supplies score", "%d%%" % supplies_pct),
		_row("Training", grade)]
	var order := ArmySystem.order_of(repo, state, code)
	# a standing unit: the garrison is the seat's alone, the rest are camped
	# round its town or in the field (spec 2026-10-07-army-split-and-ground §4.1)
	var shown := order
	if order == ArmySystem.ORDER_GARRISON and ArmyGround.seated_in(repo, state, code) == "":
		shown = "camped" if ArmyGround.camped_by(repo, state, code) != "" else "camp"
	rows.append(_row("Order", order_word(repo, shown)))
	var stance := BattleSystem.stance_words(repo, state, code)
	if stance != "":
		rows.append(_row("Battle stance", stance))
	if order == ArmySystem.ORDER_MARCH:
		var dest := ArmySystem.destination_of(repo, state, code)
		var si := WarSheets.sheet_of(repo, dest)
		if si >= 0:
			rows.append(_row("Bound for", WarSheets.grid_ref(repo, WarSheets.series(repo)[si], dest)))
		var days := CourierSystem.days_to_arrival(repo, state, code)
		rows.append(_row("Arrives", "in %d day%s" % [days, "" if days == 1 else "s"]))
	return rows


## The folio's word for a standing order (data/war_order_words.csv).
static func order_word(repo: DataRepository, order: String) -> String:
	return String(repo.war_order_words.get(order, order.capitalize()))


## Whether an arm has a figure of its own to drill: some war_drills row lists
## it. The guns have none (army_art gives them the spearman as a map stand-in,
## which the folio never shows), so the folio draws their icon instead.
static func modelled(repo: DataRepository, arm: String) -> bool:
	for d: Dictionary in repo.war_drills:
		if arm in (d["arms"] as PackedStringArray):
			return true
	return false


static func drills_for(repo: DataRepository, arm: String, clips: PackedStringArray) -> Array:
	var out: Array = []
	for d: Dictionary in repo.war_drills:
		if not arm in (d["arms"] as PackedStringArray):
			continue
		for name: String in clips:
			if name.to_upper().ends_with(String(d["clip"])):
				out.append({"key": String(d["key"]), "label": String(d["label"]), "clip_name": name})
				break
	return out


static func current_drill(drills: Array, order: String) -> int:
	var want := WarRoom.pose_action(order)
	for i in drills.size():
		if String(drills[i]["clip_name"]).to_upper().ends_with(want):
			return i
	return 0
