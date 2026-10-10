class_name MissiveWriter
extends RefCounted
## The routine letters (spec 2026-09-28 §1): a courier's delivery receipt
## (highly credible — the regiment's state that day, exact) and the steward's
## monthly report on the provinces the crown controls (ground truth, exact),
## and the marshal's supply dispatch and month (spec 2026-10-07-army-supply-lines),
## and a decree's two letters (spec 2026-10-08-laws-tab §3).
## Builds missives; MissiveLog files them.

static func receipt(repo: DataRepository, state: GameState, c: Dictionary, stale: bool) -> Dictionary:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code, state)
	var label := String(reg.get("label", code))
	var at := ArmySystem.position_of(repo, state, reg) if not reg.is_empty() else Vector2.ZERO
	var st := ArmySystem.state_of(repo, state, code)
	var order := String((c["order"] as Dictionary).get("action_code", ""))
	var said := "Newer orders stand: this one is set aside" if stale else \
		("March" if order == "ARMY_MARCH" else "Take the seat" if order == "ARMY_SEAT" else "Stand")
	if not stale and order == "ARMY_STANCE":
		var stance := String((c["order"] as Dictionary).get("stance", ""))
		said = "Stance: %s, from the next day" % String((repo.battle_stances.get(stance, {}) as Dictionary).get("label", stance))
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
	"cut": "The road from %s to %s is cut%s by %s.",
	"restored": "The road from %s to %s is open again.",
	"town_low": "%s can feed %s for only %d more days.",
	"low": "%s has under %d days of supplies (%s).",
	"empty": "%s has eaten its last supplies (%s).",
	"cancelled": "%s is no longer ours: the line to %s is gone.",
	"town_dry": "%s's stores are empty: %s is fed from %s.",
	"order_lost": "The supply orders for %s never reached %s.",
}


## The day's supply news in ONE letter (spec 2026-10-07-army-supply-lines
## §5.5): a fact per event, about the first event's regiment.
static func supply_dispatch(repo: DataRepository, state: GameState, events: Array) -> Dictionary:
	var facts: Array = []
	for i in events.size():
		var e: Dictionary = events[i]
		var reg := String(ArmySystem.regiment(repo, String(e["regiment"]), state).get("label", e["regiment"]))
		var town := String((repo.burgs.get(String(e.get("town", "")), {}) as Dictionary).get("label", e.get("town", "")))
		var text := ""
		var fact := String(e["type"]).capitalize().replace("_", " ")
		match String(e["type"]):
			"front", "front_cleared":
				# a line whose town lies ahead of its column (ruling 20 kept
				# daily): army_supply_orders.csv front_news / front_cleared_news
				var key := "front_news" if String(e["type"]) == "front" else "front_cleared_news"
				text = SupplyLines.event_words(repo, state, e, key) + "."
				fact = SupplyLines.words(repo, key, {}, "label", fact)
			"cut":
				var near := "" if not e.has("at") else " near " + Intel.place_label(repo, state, e["at"])
				text = _SUPPLY_WORDS["cut"] % [town, reg, near,
					String((repo.kingdoms.get(String(e["by"]), {}) as Dictionary).get("label", e["by"]))]
			"town_low":
				text = _SUPPLY_WORDS["town_low"] % [town, reg, int(e["days"])]
			"low":
				text = _SUPPLY_WORDS["low"] % [reg, int(repo.bal("army_supply_low_days")), _fed_from(town)]
			"empty":
				text = _SUPPLY_WORDS["empty"] % [reg, _fed_from(town)]
			"cancelled":
				text = _SUPPLY_WORDS["cancelled"] % [town, reg]
			"order_lost":
				text = _SUPPLY_WORDS["order_lost"] % [reg, town]
			"town_dry":
				text = _SUPPLY_WORDS["town_dry"] % [town, reg,
					SupplyLines.fed_from_words(repo, "" if bool(e.get("realm", false)) else String(e.get("depot", "")))]
			_:
				text = _SUPPLY_WORDS[String(e["type"])] % [town, reg]
		facts.append(MissiveLog.words("supply_%d" % i, fact, text))
	var first := String((events[0] as Dictionary)["regiment"])
	var at := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, first, state))
	return MissiveLog.make("supply", "credible", state.absolute_day(),
		MissiveLog.subject("regiment", first, -1, at), "Supply dispatch", facts)


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
		var label := String(ArmySystem.regiment(repo, String(r["code"]), state).get("label", r["code"]))
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
		var who := "an unheld town" if String(names[i]) == "" else "House %s" % names[i]
		facts.push_front(MissiveLog.exact("bought@" + String(names[i]), "Bought from %s (units)" % who, int(houses[names[i]])))
	facts.push_front(MissiveLog.exact("supply_buy", "Bought from the houses (gold)", buy))
	facts.push_front(MissiveLog.exact("supply_fee", "Cartage, all lines", fee))
	var home := MapManors.home_province(repo, state)
	var prov: Dictionary = repo.provinces.get(home, {})
	return MissiveLog.make("supply_month", "credible", state.absolute_day(),
		MissiveLog.subject("province", home, -1, Vector2(float(prov.get("center_x", 0)), float(prov.get("center_y", 0)))),
		"Marshal's supply report — %s, Year %d" % [Calendar.month_label(tick), Calendar.year_of(tick)], facts)


## A decree's letters (laws spec §3 "News and letters"): kind `law`, the
## credible column, about the realm's home province (its capital town's
## point). Kept apart from the column's count (missive_keep_law).
static func _law_subject(repo: DataRepository, state: GameState) -> Dictionary:
	var home := MapManors.home_province(repo, state)
	return MissiveLog.subject("province", home, -1, LawSystem.province_px(repo, home))


static func _law_said(repo: DataRepository, law: String, value: String) -> String:
	return "%s: %s" % [String(LawSystem.def(repo, law).get("label", law)), LawSystem.value_label(repo, value)]


## The chancery's letter as a decree is sealed: the law, its value and how
## many couriers carry it (`last_days`, when known: the longest ride).
static func law_decree(repo: DataRepository, state: GameState, law: String, couriers: int,
		last_days: int = -1) -> Dictionary:
	var value := LawSystem.decreed(repo, state, law)
	var label := String(LawSystem.def(repo, law).get("label", law))
	var facts: Array = [MissiveLog.words("decree", "Decree", _law_said(repo, law, value)),
		MissiveLog.exact("couriers", "Couriers sent", couriers)]
	if last_days >= 0:
		facts.append(MissiveLog.exact("last_days", "The last arrives in (days)", last_days))
	return MissiveLog.make("law", "credible", state.absolute_day(), _law_subject(repo, state),
		"Decree sent — " + label, facts)


## The chancery's letter when the decree's last courier is home or lost:
## "reached X of Y places in N days", and the places it has not reached.
static func law_reach(repo: DataRepository, state: GameState, law: String, reached: int, total: int,
		days: int) -> Dictionary:
	var value := LawSystem.decreed(repo, state, law)
	var label := String(LawSystem.def(repo, law).get("label", law))
	var facts: Array = [MissiveLog.words("decree", "Decree", _law_said(repo, law, value)),
		MissiveLog.exact("reached", "Places reached", reached),
		MissiveLog.exact("total", "Places it was for", total),
		MissiveLog.exact("days", "Days on the road", days)]
	var names: PackedStringArray = []
	for u: Dictionary in LawSystem.untold(repo, state, law):
		names.append(String(u["label"]))
	if not names.is_empty():
		facts.append(MissiveLog.words("not_reached", "Not reached", ", ".join(names)))
	var title := "Decree in force — " + label
	if reached < total:
		title = "Decree reached %d of %d — %s" % [reached, total, label]
	return MissiveLog.make("law", "credible", state.absolute_day(), _law_subject(repo, state), title, facts)


## --- The battle report (spec 2026-10-07-enemy-ai-and-battle §4.5) -------------

## A `templates.csv` line of `key` (its trait-less rows; `pick` chooses among
## several, so a day's words are the same on every replay), `{vars}` filled with
## `vars` and the realm slots. The engine's numbers go in as vars; the
## wording is data, and never spells a kingdom.
static func battle_words(repo: DataRepository, key: String, vars: Dictionary, pick: int) -> String:
	var pool: Array = []
	for row: Dictionary in repo.templates:
		if String(row["key"]) == key and String(row["trait"]) == "":
			pool.append(String(row["text"]))
	if pool.is_empty():
		return "[missing template: %s]" % key
	var all_vars := repo.realm_vars()
	all_vars.merge(vars, true)
	return String(pool[pick % pool.size()]).format(all_vars)


## The day's battles in ONE letter, like supply_dispatch (a fact per event, in
## the order BattleSystem.settle_day gave them): where they met, who joined,
## each round's outcome and losses (each of OUR regiments' dead, wounded and
## morale WITH the reason the engine recorded for it, invariant 4; the enemy's
## losses only as our men's estimate, `_round_facts`), who left the field and
## how each battle ended. Numbers are the events' own; nothing is
## recomputed here. About the first of the player's regiments in the fights.
##
## The day's siege news (SiegeSystem.news: begin, starving, repulsed, fallen,
## undefended, lifted, liberated) rides in the same letter, a line each after the
## fighting, the town by name and the figures the events carry
## (templates.csv `siege_*`); a letter of siege news alone is about the town.
## The day's raid news (RaidSystem.news: raid_begin, raid_spoils) follows the
## same way (templates.csv `raid_*`, the place and the event's figures); a
## letter of raid news alone is about the first raid's place. A fall's cost
## (DefeatSystem: defeat_*) follows its siege_fallen line (`_defeat_fact`).
static func battle_report(repo: DataRepository, state: GameState, events: Array) -> Dictionary:
	var pick := state.absolute_day()
	var at: Dictionary = {}       # battle id -> an event that carries its place
	var rounds: Dictionary = {}   # battle id -> its round event today
	var first_battle := -1
	var siege_town := ""
	var raid_at: Dictionary = {}  # the first raid line's event (its place)
	for e: Dictionary in events:
		if String(e["kind"]).begins_with("raid_"):
			raid_at = e if raid_at.is_empty() else raid_at
			continue
		if String(e["kind"]).begins_with("siege_") or String(e["kind"]).begins_with("defeat_"):
			siege_town = String(e["town"]) if siege_town == "" else siege_town
			continue
		var id := int(e["battle_id"])
		first_battle = id if first_battle < 0 else first_battle
		if e.has("place_x_m") and not at.has(id):
			at[id] = e
		if String(e["kind"]) == "round":
			rounds[id] = e
	var facts: Array = []
	var first_mine := ""
	for e: Dictionary in events:
		if String(e["kind"]).begins_with("siege_"):
			facts.append(_siege_fact(repo, e, pick))
			continue
		if String(e["kind"]).begins_with("defeat_"):
			facts.append(_defeat_fact(repo, e, pick))
			continue
		if String(e["kind"]).begins_with("raid_"):
			facts.append(MissiveLog.words("%s@%s.%d" % [e["kind"], e["host"], int(e.get("day", 0))], "The raid",
				battle_words(repo, String(e["kind"]), {"place": String(e.get("place", "")),
					"spoils": int(e.get("spoils", 0)), "plunder": int(e.get("plunder", 0))}, pick)))
			continue
		var id := int(e["battle_id"])
		var place := battle_place(repo, state, at.get(id, {}))
		match String(e["kind"]):
			"start":
				facts.append(MissiveLog.words("start@%d" % id, "Contact", battle_words(repo, "battle_start",
					{"att": _battle_names(repo, e["att"]), "def": _battle_names(repo, e["def"]),
						"place": place}, pick)))
			"join":
				facts.append(MissiveLog.words("join@%d.%s" % [id, e["code"]], "Joined",
					battle_words(repo, "battle_join_" + String(e["side"]), {"unit": _unit_label(repo, String(e["code"])),
						"place": place}, pick)))
			"round":
				_round_facts(repo, state, e, place, pick, facts)
			"end":
				facts.append(MissiveLog.words("end@%d" % id, "Result",
					battle_words(repo, _end_key(state, e, rounds.get(id, {})),
						{"place": place, "rounds": int(e["rounds"])}, pick)))
		if first_mine == "":
			first_mine = _first_mine(state, e)
	var head: Dictionary = at.get(first_battle, {})
	if head.is_empty() and siege_town != "":
		var town_m := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, siege_town)
		head = {"town": siege_town, "place_x_m": town_m.x, "place_y_m": town_m.y}
	if head.is_empty() and not raid_at.is_empty():
		head = {"town": "", "place_x_m": int(raid_at["place_x_m"]), "place_y_m": int(raid_at["place_y_m"])}
	var pack := ArmySystem.metres_to_pack(repo, Vector2i(int(head.get("place_x_m", 0)), int(head.get("place_y_m", 0))))
	var subject := MissiveLog.subject("regiment", first_mine, -1, pack) if first_mine != "" \
		else MissiveLog.subject("point", "", -1, pack)
	return MissiveLog.make("battle", "credible", state.absolute_day(), subject,
		battle_words(repo, "battle_title", {"place": battle_place(repo, state, head)}, pick), facts)


## One line of a fall's cost (DefeatSystem.on_town_lost): templates.csv
## `<kind>` (defeat_town_lost) with the town's name and the event's own
## figures: the gold the treasury lost and the contentment's points. A figure
## of 0 has no clause: `_gold` (only gold lost), `_people` (only contentment),
## `_bare` (neither).
static func _defeat_fact(repo: DataRepository, e: Dictionary, pick: int) -> Dictionary:
	var kind := String(e["kind"])
	var gold := int(e.get("gold", 0)) > 0
	var people := int(e.get("morale", 0)) > 0
	var key := kind if gold and people else kind + ("_gold" if gold else ("_people" if people else "_bare"))
	var town := String(e["town"])
	var vars := {"town": String((repo.burgs.get(town, {}) as Dictionary).get("label", town)),
		"gold": int(e.get("gold", 0)), "morale": int(e.get("morale", 0))}
	return MissiveLog.words("%s@%s.%d" % [kind, town, int(e.get("day", 0))], "The cost",
		battle_words(repo, key, vars, pick))


## One line of siege news: templates.csv `<kind>` (siege_begin, siege_starving,
## siege_repulsed, siege_fallen (siege_fallen_slain when no one of the
## garrison marched out), siege_undefended, siege_lifted, siege_liberated) with
## the town's name and the event's own figures.
static func _siege_fact(repo: DataRepository, e: Dictionary, pick: int) -> Dictionary:
	var kind := String(e["kind"])
	if kind == "siege_fallen" and int(e.get("garrison_out", 1)) == 0:
		kind = "siege_fallen_slain"     # no one of the garrison left to march out
	var town := String(e["town"])
	var vars := {"town": String((repo.burgs.get(town, {}) as Dictionary).get("label", town)),
		"progress": int(e.get("progress", 0)), "attack": int(e.get("attack", 0)), "defend": int(e.get("defend", 0)),
		"gain": int(e.get("gain", 0)), "lost": int(e.get("lost", 0)), "days": int(e.get("days", 0))}
	return MissiveLog.words("%s@%s.%d" % [kind, town, int(e.get("day", 0))], "The siege",
		battle_words(repo, kind, vars, pick))


## --- Word of the enemy (spec 2026-10-07-enemy-ai-and-battle §2) ---------------

## The border rumour (EnemyAi.warnings): men gathering beyond the border near
## `at_m` (a host's assembly point, whole metres), under the raider realm's
## banners — no figure, column and source `rumour`. Fixed prose, the
## templates.csv `raid_rumour*` rows.
static func raid_rumour(repo: DataRepository, state: GameState, at_m: Vector2i) -> Dictionary:
	var pick := state.absolute_day()
	var at := ArmySystem.metres_to_pack(repo, at_m)
	var place := Intel.place_label(repo, state, at)
	return MissiveLog.make("rumour", "rumour", state.absolute_day(), MissiveLog.subject("point", "", -1, at),
		battle_words(repo, "raid_rumour_title", {}, pick),
		[MissiveLog.words("word", "Word from the border", battle_words(repo, "raid_rumour", {"place": place}, pick))])


## The hosts' day (EnemyAi.step_day / think_day events) in ONE letter, a line
## per host that crossed the border (`host_advance`) or changed its mode
## (`host_mode`: SIEGE, RAID, WITHDRAW, RETREAT — templates.csv `host_news_*`);
## {} when none of them is news. Where: a siege's or a raid's target, else the
## host's first column. No figure and no engine reason (the enemy's morale and
## stores are not the crown's to read). Column `credible` when a siege or a raid
## is in it (the crown's own people see it), else `rumour`.
static func host_news(repo: DataRepository, state: GameState, events: Array) -> Dictionary:
	var pick := state.absolute_day()
	var facts: Array = []
	var seen_close := false
	var first_at := Vector2.ZERO
	for e: Dictionary in events:
		var host := String(e.get("host", ""))
		var mode := "ADVANCE" if String(e["type"]) == "host_advance" else String(e.get("mode", ""))
		if String(e["type"]) == "host_mode" and mode == "ADVANCE":
			continue                    # setting out again from a stripped manor is no crossing
		if not mode in ["ADVANCE", "SIEGE", "RAID", "WITHDRAW", "RETREAT"]:
			continue
		var mind: Dictionary = state.ai_hosts.get(host, {})
		var at_m := _host_at_m(repo, state, host)
		if mode in ["SIEGE", "RAID"] and String(mind.get("target_id", "")) != "":
			at_m = EnemyAi.target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
			seen_close = true
		var at := ArmySystem.metres_to_pack(repo, at_m)
		if facts.is_empty():
			first_at = at
		facts.append(MissiveLog.words("host@%s.%s" % [host, mode.to_lower()], "The enemy",
			battle_words(repo, "host_news_" + mode.to_lower(), {"place": Intel.place_label(repo, state, at)}, pick)))
	if facts.is_empty():
		return {}
	return MissiveLog.make("host_news", "credible" if seen_close else "rumour", state.absolute_day(),
		MissiveLog.subject("point", "", -1, first_at), battle_words(repo, "host_news_title", {}, pick), facts)


## A host's first foe's place in whole metres (code order); its home with none.
static func _host_at_m(repo: DataRepository, state: GameState, host: String) -> Vector2i:
	for c: String in EnemyAi.regiments_of(state, host):
		var e: Dictionary = state.foes[c]
		return Vector2i(int(e["x_m"]), int(e["y_m"]))
	return EnemyAi.home_m(repo, host)


## Where a battle was fought, in words ("" with no event to ask).
static func battle_place(repo: DataRepository, state: GameState, e: Dictionary) -> String:
	return "" if e.is_empty() else BattleSystem.place_label(repo, state, e)


## One round, told through the fog (spec §2): the tier, OUR side's dead and
## wounded exactly, the enemy's dead and wounded together as our men count them
## (SpySystem.estimate at battle_foe_estimate_quality, rounded out to
## intel_facts `foe_losses`); no side's strength and no odds (they would give
## the enemy's strength away). Then a line per regiment of OURS (its dead,
## wounded and morale change, and why) — never a foe's — and one per departure.
static func _round_facts(repo: DataRepository, state: GameState, e: Dictionary, place: String, pick: int,
		facts: Array) -> void:
	var id := int(e["battle_id"])
	var n := int(e["round"])
	var results: Dictionary = e["results"]
	var ours: Array = []
	var theirs: Array = []
	var own := [0, 0]
	var foe_men := 0
	for side: String in BattleSystem.SIDES:
		for c: Variant in e[side]:
			var r: Dictionary = results.get(String(c), {})
			if ArmySystem.is_foe(state, String(c)):
				theirs.append(c)
				foe_men += int(r.get("dead", 0)) + int(r.get("wounded", 0))
			else:
				ours.append(c)
				own[0] += int(r.get("dead", 0))
				own[1] += int(r.get("wounded", 0))
	var span := SpySystem.estimate(repo, foe_men, int(repo.bal("battle_foe_estimate_quality")), 0,
		int((repo.intel_facts.get("foe_losses", {}) as Dictionary).get("round_to", 1)))
	facts.append(MissiveLog.words("round@%d.%d" % [id, n], "Day %d" % n, battle_words(repo, "battle_round", {
		"round": n, "place": place, "tier": String(e["tier"]).replace("_", " "),
		"ours": _battle_names(repo, ours), "theirs": _battle_names(repo, theirs),
		"own_dead": own[0], "own_wounded": own[1], "foe_lo": int(span[0]), "foe_hi": int(span[1])}, pick)))
	var codes: Array = results.keys()
	codes.sort()
	for code: String in codes:
		if ArmySystem.is_foe(state, code):
			continue
		var r: Dictionary = results[code]
		var morale := int(r["morale"])
		facts.append(MissiveLog.words("loss@%d.%d.%s" % [id, n, code], "Losses", battle_words(repo, "battle_loss", {
			"unit": _unit_label(repo, code), "dead": int(r["dead"]), "wounded": int(r["wounded"]),
			"morale": ("%+d" % morale) if morale != 0 else "0", "reason": String(r["reason"])}, pick)))
	for l: Dictionary in e["left"]:
		facts.append(MissiveLog.words("left@%d.%d.%s" % [id, n, l["code"]], "Left the field",
			battle_words(repo, "battle_left_" + String(l["why"]), {"unit": _unit_label(repo, String(l["code"]))}, pick)))


## How a battle ended, from the player's side: the template key.
static func _end_key(state: GameState, e: Dictionary, round_ev: Dictionary) -> String:
	var winner := String(e["winner"])
	if String(e["why"]) == "rounds":
		return "battle_end_draw"
	if String(e["why"]) == "withdrawn":
		return "battle_end_withdrawn"   # the foe drew off for home: held, not won
	if winner == "":
		return "battle_end_none"
	# who held the field: the winning side's regiments, as they fought (the
	# round's list) or, with no round today, as they stood at the end
	var codes: Array = round_ev.get(winner, e[winner])
	if codes.is_empty():
		return "battle_end_none"
	return "battle_end_lost" if ArmySystem.is_foe(state, String(codes[0])) else "battle_end_won"


static func _first_mine(state: GameState, e: Dictionary) -> String:
	var seen: Array = []
	for k: String in ["att", "def"]:
		seen.append_array(e.get(k, []))
	if e.has("code"):
		seen.append(e["code"])
	for c: Variant in seen:
		if not ArmySystem.is_foe(state, String(c)):
			return String(c)
	return ""


static func _unit_label(repo: DataRepository, code: String) -> String:
	return String(ArmySystem.regiment(repo, code).get("label", code))


## "A", "A and B", "A, B and C", in code order.
static func _battle_names(repo: DataRepository, codes: Array) -> String:
	var sorted: Array = codes.duplicate()
	sorted.sort()
	var labels: Array = sorted.map(func(c: Variant) -> String: return _unit_label(repo, String(c)))
	if labels.size() <= 1:
		return "" if labels.is_empty() else String(labels[0])
	return ", ".join(labels.slice(0, labels.size() - 1)) + " and " + String(labels[labels.size() - 1])
