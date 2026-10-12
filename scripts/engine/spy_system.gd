class_name SpySystem
extends RefCounted
## Spies (owner 2026-09-28, spec 2026-09-28-missive-board-and-spies §1): a
## spy courier's arrival becomes a report. One quality roll per mission from
## GameState.rng, shifted by the place (data/intel/spy_difficulty.csv), decides the
## column — highly credible or rumour — and how wide and how biased every
## estimate is. Two spies to one place draw different rolls: their reports differ.

## Whether the point lies in a province the crown CONTROLS right now
## (MapManors.controlled_provinces): its facts are exact, so no spy rides there.
## ONE predicate for ActionSystem.validate and quality().
static func is_controlled(repo: DataRepository, state: GameState, at: Vector2) -> bool:
	var cell := MapEconomy.cell_at(repo, at)
	return cell >= 0 and province_controlled(repo, state, MapManors.province_of(repo, cell, state))


static func province_controlled(repo: DataRepository, state: GameState, province: String) -> bool:
	return province != "" and province in MapManors.controlled_provinces(repo, state)


static func quality(repo: DataRepository, state: GameState, at: Vector2, roll: int) -> int:
	var q := roll
	var cell := MapEconomy.cell_at(repo, at)
	if is_controlled(repo, state, at):
		q += int(repo.spy_difficulty.get("home", 0))
	else:
		q += int(repo.spy_difficulty.get("foreign", 0))
	if cell >= 0 and _walled(repo, cell):
		q += int(repo.spy_difficulty.get("walled", 0))
	q += int(repo.spy_difficulty.get("weather_" + Weather.at(repo, state, at, state.absolute_day()), 0))
	return clampi(q, 0, 999)


## Whether walls or a citadel stand in this cell, by MapEconomy.burg_cells
## (burg_code -> cell_id, so the cell is found by scanning for the burg whose
## cell matches, not looked up by cell).
static func _walled(repo: DataRepository, cell: int) -> bool:
	var cells := MapEconomy.burg_cells(repo)
	for code: String in cells:
		if int(cells[code]) != cell:
			continue
		var feats := String((repo.burgs.get(code, {}) as Dictionary).get("features", "")).split("|")
		if "walls" in feats or "citadel" in feats:
			return true
	return false


## The town standing in this cell (MapEconomy.burg_cells, the same map a
## town card's query resolves through), the first by code; "" for none.
static func town_at(repo: DataRepository, cell: int) -> String:
	var cells := MapEconomy.burg_cells(repo)
	var codes := cells.keys()
	codes.sort()
	for code: String in codes:
		if int(cells[code]) == cell:
			return code
	return ""


## [lo, hi] around the true value v: half-width by quality, centre moved by
## bias (per mille of v), rounded OUT to round_to, lo never below zero.
static func estimate(repo: DataRepository, v: int, q: int, bias: int, round_to: int) -> Array:
	var best := int(repo.bal("spy_width_best"))
	var worst := int(repo.bal("spy_width_worst"))
	@warning_ignore("integer_division")  # whole per mille
	var width := best + (worst - best) * (1000 - clampi(q, 0, 1000)) / 1000
	@warning_ignore("integer_division")  # whole heads / gold
	var half := v * width / 1000
	@warning_ignore("integer_division")
	var centre := v + v * bias / 1000
	var r := maxi(1, round_to)
	var lo := maxi(0, int(floor(float(centre - half) / float(r))) * r)
	var hi := int(ceil(float(centre + half) / float(r))) * r
	return [lo, maxi(lo, hi)]


static func _round_to(repo: DataRepository, key: String) -> int:
	return int((repo.intel_facts.get(key, {}) as Dictionary).get("round_to", 1))


static func _label(repo: DataRepository, key: String) -> String:
	return String((repo.intel_facts.get(key, {}) as Dictionary).get("label", key))


## What a manor's "output" fact measures — the one measure the spy's report
## and the fogged manor card share (Ruling 18 N1): its CHIEF good, named,
## and that good's units a month; land that works nothing keeps the plain
## output label over `all_units`, every unit it makes. {label, units}.
static func chief_output(repo: DataRepository, state: GameState, cell: int, people: int,
		all_units: int) -> Dictionary:
	var chief := ManorEconomy.focus_units(repo, state, cell, people, state.tick)
	var good_label := String((repo.world_table("economy", "goods").get(String(chief["good"]), {}) \
		as Dictionary).get("label", ""))
	if good_label == "":
		return {"label": _label(repo, "output"), "units": all_units}
	return {"label": "%s a month" % good_label, "units": int(chief["units"])}


## The report a spy at `at` files for quality q and bias (per mille). Pure.
static func report(repo: DataRepository, state: GameState, at: Vector2, q: int, bias: int) -> Dictionary:
	var credible := q >= int(repo.bal("spy_credible_threshold"))
	var sees_words := q >= int(repo.bal("spy_text_threshold"))
	var facts: Array = []
	var cell := MapEconomy.cell_at(repo, at)
	var subj := MissiveLog.subject("point", "", -1, at)
	if cell >= 0 and MapManors.is_manor(repo, cell):
		subj = MissiveLog.subject("manor", MapManors.code_of(repo, cell), cell, at)
		var line := RealmEconomy.line_of(repo, state, cell)
		for key in ["people", "tax"]:
			var lh := estimate(repo, int(line[key]), q, bias, _round_to(repo, key))
			facts.append(MissiveLog.span(key, _label(repo, key), int(lh[0]), int(lh[1])))
			# A town in the cell: its own people too, under their own key
			# (Ruling 12) — the town card reads this, never the manor's.
			var town := town_at(repo, cell) if key == "people" else ""
			if town != "":
				var tp := estimate(repo, int(float((repo.burgs[town] as Dictionary).get("population", 0))),
					q, bias, _round_to(repo, "town_people"))
				facts.append(MissiveLog.span("town_people", _label(repo, "town_people"), int(tp[0]), int(tp[1])))
		# Its worth a month, tax and goods in gold — the MANORS bars read it
		# for land the crown does not hold (owner 2026-10-04).
		var wl := estimate(repo, ManorBars.worth_of(line), q, bias, _round_to(repo, "worth"))
		facts.append(MissiveLog.span("worth", _label(repo, "worth"), int(wl[0]), int(wl[1])))
		# The chief good by name and ITS units a month (final review M2).
		var made := chief_output(repo, state, cell, int(line["people"]), int(line.get("units", 0)))
		var units := estimate(repo, int(made["units"]), q, bias, _round_to(repo, "output"))
		facts.append(MissiveLog.span("output", String(made["label"]), int(units[0]), int(units[1])))
		var prov := MapManors.province_of(repo, cell, state)
		var holder := MapManors.owner_of(repo, state, cell)
		facts.append(MissiveLog.words("holder", _label(repo, "holder"),
			("House " + holder) if sees_words and holder != "" else Intel.UNCLEAR))
		facts.append(MissiveLog.words("stance", _label(repo, "stance"),
			Intel.stance_of(repo, MapOwnership.owner_of(repo, state, prov)) if sees_words else Intel.UNCLEAR))
		facts.append(MissiveLog.words("wealth", _label(repo, "wealth"),
			Intel.wealth_word(repo, Intel.wealth_tier(repo, state, prov)) if sees_words else Intel.UNCLEAR))
	var troops := troops_near(repo, state, at)
	for key in ["troops_own", "troops_foreign"]:
		var tl := estimate(repo, int(troops[key]), q, bias, _round_to(repo, key))
		facts.append(MissiveLog.span(key, _label(repo, key), int(tl[0]), int(tl[1])))
	# The enemy hosts' columns he can count (spec 2026-10-07-enemy-ai-and-battle
	# §2: "how many, about how many men"), only when there is one in reach.
	var foes := foes_near(repo, state, at)
	if int(foes["foe_columns"]) > 0:
		for key in ["foe_columns", "foe_troops"]:
			var fl := estimate(repo, int(foes[key]), q, bias, _round_to(repo, key))
			facts.append(MissiveLog.span(key, _label(repo, key), int(fl[0]), int(fl[1])))
	return MissiveLog.make("spy", "credible" if credible else "rumour", state.absolute_day(), subj,
		"Spy report — " + Intel.place_label(repo, state, at), facts)


## Men under arms within spy_radius_km of a point (PACK px), each regiment at
## its live place (ArmySystem.position_of: a foe where its host has marched
## it): ours and foreign — headcount less the regiment's `dead` and `deserted`, never below
## 0, so beside an enemy host troops_foreign and foe_troops count the same men.
static func troops_near(repo: DataRepository, state: GameState, at: Vector2) -> Dictionary:
	var reach := repo.bal("spy_radius_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var realm := repo.resolve_realm("player_realm")
	var own := 0
	var foreign := 0
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	for code: String in codes:
		var reg: Dictionary = all[code]
		if ArmySystem.position_of(repo, state, reg).distance_to(at) > reach:
			continue
		var men := ArmySystem.under_arms(ArmySystem.headcount(repo, reg), ArmySystem.state_of(repo, state, code))
		if String(reg.get("kingdom_code", "")) == realm:
			own += men
		else:
			foreign += men
	return {"troops_own": own, "troops_foreign": foreign}


## The enemy hosts' columns (GameState.foes) within spy_radius_km of a point
## (PACK px), by their live place in whole metres: how many, and their men
## under arms (headcount less the dead). {foe_columns, foe_troops}.
static func foes_near(repo: DataRepository, state: GameState, at: Vector2) -> Dictionary:
	var cols := 0
	var men := 0
	for c: String in foe_codes_near(repo, state, at):
		cols += 1
		men += ArmySystem.headcount(repo, ArmySystem.regiment(repo, c, state)) - int(state.foes[c].get("dead", 0))
	return {"foe_columns": cols, "foe_troops": men}


## The foe columns foes_near counts — within spy_radius_km of a point (PACK
## px) by their live place in whole metres, with men under arms — in code
## order. A spy's ghosts are these (Sighting.on_spy).
static func foe_codes_near(repo: DataRepository, state: GameState, at: Vector2) -> Array:
	var here := ArmySystem.pack_to_metres(repo, at)
	var reach := int(round(repo.bal("spy_radius_km") * 1000.0))
	var out: Array = []
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: Variant in codes:
		var e: Dictionary = state.foes[c]
		var dx := int(e["x_m"]) - here.x
		var dy := int(e["y_m"]) - here.y
		if dx * dx + dy * dy > reach * reach:
			continue
		if ArmySystem.headcount(repo, ArmySystem.regiment(repo, String(c), state)) - int(e.get("dead", 0)) <= 0:
			continue
		out.append(String(c))
	return out


## A spy has arrived: draw his rolls (quality, then — for a rumour — the
## bias), file the report, and say so for the news bar and GameRoot.
static func observe(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var at := ArmySystem.metres_to_pack(repo, Vector2i(int(c["x_m"]), int(c["y_m"])))
	var q := quality(repo, state, at, state.rng.randi_range(0, 999))
	var bias := 0
	if q < int(repo.bal("spy_credible_threshold")):
		var most := int(repo.bal("spy_bias_max"))
		bias = state.rng.randi_range(-most, most)
	var id := MissiveLog.add(repo, state, report(repo, state, at, q, bias))
	# what he saw of the enemy's columns stays on the map as their ghosts
	# (spec 2026-10-10-player-sight-and-ghosts §2): his own estimate, no new roll
	Sighting.on_spy(repo, state, at, q, bias)
	return {"type": "spy_report", "courier": int(c["id"]), "missive": id, "regiment": "",
		"place": Intel.place_label(repo, state, at), "weather": ""}
