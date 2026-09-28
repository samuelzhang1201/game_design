class_name MissiveWriter
extends RefCounted
## The two routine letters (spec 2026-09-28 §1): a courier's delivery receipt
## (highly credible — the regiment's state that day, exact) and the steward's
## monthly report on the provinces the crown controls (ground truth, exact).
## Builds missives; MissiveLog files them.

static func receipt(repo: DataRepository, state: GameState, c: Dictionary, stale: bool) -> Dictionary:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	var label := String(reg.get("label", code))
	var at := ArmySystem.position_of(repo, state, reg) if not reg.is_empty() else Vector2.ZERO
	var st := ArmySystem.state_of(repo, state, code)
	var order := String((c["order"] as Dictionary).get("action_code", ""))
	var said := "Newer orders stand: this one is set aside" if stale else \
		("March" if order == "ARMY_MARCH" else "Stand")
	var facts: Array = [MissiveLog.words("orders", "Orders", said)]
	if not st.is_empty():
		facts.append(MissiveLog.exact("morale", "Morale", int(st["morale"])))
		facts.append(MissiveLog.exact("supplies", "Supplies", int(st["supplies"])))
		facts.append(MissiveLog.exact("wounded", "Wounded", int(st["wounded"])))
		facts.append(MissiveLog.words("ground", "Ground", ArmySystem.terrain_of(repo, reg, state).capitalize()))
		facts.append(MissiveLog.words("weather", "Weather",
			Weather.label_of(repo, Weather.at(repo, state, at, state.absolute_day()))))
	return MissiveLog.make("receipt", "credible", state.absolute_day(),
		MissiveLog.subject("regiment", code, -1, at), "Receipt — " + label, facts)


## The settled month's report: each controlled province's tax, goods and
## people, their totals, and the change in tax against the last report.
static func monthly(repo: DataRepository, state: GameState, tick: int) -> Dictionary:
	var facts: Array = []
	var total := 0
	for code: String in MapManors.controlled_provinces(repo, state):
		var p: Dictionary = RealmEconomy.province(repo, state, code)
		var label := String(repo.provinces.get(code, {}).get("label", code))
		var people := RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % code) \
			+ RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % code)
		total += int(p["tax"])
		facts.append(MissiveLog.exact("tax@" + code, "%s — tax" % label, int(p["tax"])))
		facts.append(MissiveLog.exact("strategic@" + code, "%s — strategic goods" % label, int(p["strategic"])))
		facts.append(MissiveLog.exact("civil@" + code, "%s — civil goods" % label, int(p["civil"])))
		facts.append(MissiveLog.exact("people@" + code, "%s — people" % label, people))
	facts.push_front(MissiveLog.exact("tax_total", "Tax, all your provinces", total))
	var last := _last_total(state)
	if last >= 0:
		facts.insert(1, MissiveLog.words("tax_change", "Against last month", "%+d gold" % (total - last)))
	var home := MapManors.home_province(repo, state)
	var prov: Dictionary = repo.provinces.get(home, {})
	var centre := Vector2(float(prov.get("center_x", 0)), float(prov.get("center_y", 0)))
	return MissiveLog.make("monthly", "truth", state.absolute_day(),
		MissiveLog.subject("province", home, -1, centre),
		"Steward's report — %s, Year %d" % [Calendar.season_name(tick), Calendar.year_of(tick)], facts)


static func _last_total(state: GameState) -> int:
	var best := -1
	var best_id := -1
	for m: Dictionary in state.missives:
		if String(m["kind"]) != "monthly" or int(m["id"]) < best_id:
			continue
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == "tax_total":
				best = int(f["exact"])
				best_id = int(m["id"])
	return best
