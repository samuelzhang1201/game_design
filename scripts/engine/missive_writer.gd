class_name MissiveWriter
extends RefCounted
## The routine letters (spec 2026-09-28 §1): a courier's delivery receipt
## (highly credible — the regiment's state that day, exact) and the steward's
## monthly report on the provinces the crown controls (ground truth, exact),
## and the marshal's supply dispatch and month (spec 2026-10-07-army-supply-lines).
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
		# Titled by the MONTH (fix round 1 finding 3), not just the season —
		# three months a season shared "Steward's report — Spring, Year 1".
		"Steward's report — %s, Year %d" % [Calendar.month_label(tick), Calendar.year_of(tick)], facts)


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


const _SUPPLY_WORDS := {
	"opened": "The wagons from %s have reached %s.",
	"cut": "The road from %s to %s is cut by %s.",
	"restored": "The road from %s to %s is open again.",
	"town_low": "%s can feed %s for only %d more days.",
	"low": "%s has under %d days of supplies (%s).",
	"empty": "%s has eaten its last supplies (%s).",
	"cancelled": "%s is no longer ours: the line to %s is gone.",
	"town_dry": "%s's stores are empty: %s is fed from %s.",
}


## The day's supply news in ONE letter (spec 2026-10-07-army-supply-lines
## §5.5): a fact per event, about the first event's regiment.
static func supply_dispatch(repo: DataRepository, state: GameState, events: Array) -> Dictionary:
	var facts: Array = []
	for i in events.size():
		var e: Dictionary = events[i]
		var reg := String(ArmySystem.regiment(repo, String(e["regiment"])).get("label", e["regiment"]))
		var town := String((repo.burgs.get(String(e.get("town", "")), {}) as Dictionary).get("label", e.get("town", "")))
		var text := ""
		match String(e["type"]):
			"cut":
				text = _SUPPLY_WORDS["cut"] % [town, reg, String((repo.kingdoms.get(String(e["by"]), {}) as Dictionary).get("label", e["by"]))]
			"town_low":
				text = _SUPPLY_WORDS["town_low"] % [town, reg, int(e["days"])]
			"low":
				text = _SUPPLY_WORDS["low"] % [reg, int(repo.bal("army_supply_low_days")), _fed_from(town)]
			"empty":
				text = _SUPPLY_WORDS["empty"] % [reg, _fed_from(town)]
			"cancelled":
				text = _SUPPLY_WORDS["cancelled"] % [town, reg]
			"town_dry":
				text = _SUPPLY_WORDS["town_dry"] % [town, reg, _town_label(repo, String(e.get("depot", "")))]
			_:
				text = _SUPPLY_WORDS[String(e["type"])] % [town, reg]
		facts.append(MissiveLog.words("supply_%d" % i, String(e["type"]).capitalize().replace("_", " "), text))
	var first := String((events[0] as Dictionary)["regiment"])
	var at := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, first))
	return MissiveLog.make("supply", "credible", state.absolute_day(),
		MissiveLog.subject("regiment", first, -1, at), "Supply dispatch", facts)


static func _town_label(repo: DataRepository, burg: String) -> String:
	return String((repo.burgs.get(burg, {}) as Dictionary).get("label", burg))


static func _fed_from(town: String) -> String:
	return "fed from %s" % town if town != "" else "no supply point"


## The marshal's month (spec §5.5): a row per land regiment — his CLAIM of
## what arrived, beside days in hand, load, point, rate, road, cartage and
## purchases.
static func marshal_report(repo: DataRepository, state: GameState, tick: int, rows: Array) -> Dictionary:
	var facts: Array = []
	var fee := 0
	var buy := 0
	var houses: Dictionary = {}
	for r: Dictionary in rows:
		var label := String(ArmySystem.regiment(repo, String(r["code"])).get("label", r["code"]))
		var town := String((repo.burgs.get(String(r["town"]), {}) as Dictionary).get("label", ""))
		var where := "no supply point" if town == "" else "%s · %.1f× · %d km" % [town, float(int(r["rate"])) / 1000.0, int(r["km"])]
		@warning_ignore("integer_division")  # whole per cent of the permille
		var lost := int(r.get("loss_permille", SupplySystem.loss_of(repo, int(r["km"])))) / 10
		var robbers: Array = r.get("robbers", [])
		var to_whom := "" if robbers.is_empty() else " (%s)" % ", ".join(robbers)
		facts.append(MissiveLog.words("days@" + String(r["code"]), label,
			"%d days in hand of %d · %s%s · %d arrived · %d gold cartage" % [int(r["days"]), int(r["carry"]), where,
				"" if town == "" else " · %d%% lost on the road%s" % [lost, to_whom],
				int(r["claimed"]), int(r["fee"])]))
		fee += int(r["fee"])
		buy += int(r["buy"])
		for h: String in (r["bought"] as Dictionary):
			houses[h] = int(houses.get(h, 0)) + int((r["bought"] as Dictionary)[h])
	var names: Array = houses.keys()
	names.sort()
	for i in range(names.size() - 1, -1, -1):
		facts.push_front(MissiveLog.exact("bought@" + String(names[i]), "Bought from House %s" % names[i], int(houses[names[i]])))
	facts.push_front(MissiveLog.exact("supply_buy", "Bought from the houses", buy))
	facts.push_front(MissiveLog.exact("supply_fee", "Cartage, all lines", fee))
	var home := MapManors.home_province(repo, state)
	var prov: Dictionary = repo.provinces.get(home, {})
	return MissiveLog.make("supply_month", "credible", state.absolute_day(),
		MissiveLog.subject("province", home, -1, Vector2(float(prov.get("center_x", 0)), float(prov.get("center_y", 0)))),
		"Marshal's supply report — %s, Year %d" % [Calendar.month_label(tick), Calendar.year_of(tick)], facts)
