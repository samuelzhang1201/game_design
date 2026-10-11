extends GutTest
const ConductHelpers := preload("res://tests/engine/conduct_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
## Supply missives (spec 2026-10-07-army-supply-lines §5.5).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func _row(rows: Array, code: String) -> Dictionary:
	return rows.filter(func(r: Dictionary) -> bool: return String(r["code"]) == code)[0]

func test_one_dispatch_gathers_the_days_events() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var m := MissiveWriter.supply_dispatch(repo, s, [
		{"type": "opened", "regiment": code, "town": town},
		{"type": "low", "regiment": code, "town": town}])
	assert_eq(String(m["kind"]), "supply")
	assert_eq(String(m["column"]), "credible")
	assert_eq((m["facts"] as Array).size(), 2)

func test_every_event_kind_reads_as_a_sentence() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var kingdom: String = String(repo.kingdoms.keys()[0])
	var events: Array = []
	for t: String in ["opened", "cut", "restored", "town_low", "low", "empty", "cancelled", "town_dry", "order_lost"]:
		events.append({"type": t, "regiment": code, "town": town, "by": kingdom, "days": 3, "depot": town,
			"at": Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))})
	var m := MissiveWriter.supply_dispatch(repo, s, events)
	for f: Dictionary in m["facts"]:
		assert_ne(String(f["text"]), "")
		assert_false(String(f["text"]).contains("%"), "no unfilled placeholder")

## Final review 1: a dry town's regiment fed from the depot says both towns.
func test_a_dry_town_names_the_depot_that_feeds_the_regiment() -> void:
	var code := _land()
	var towns := TownStores.realm_towns(repo, s)
	var dry := String(towns[0])
	var dep := TownStores.depot(repo, s)
	var m := MissiveWriter.supply_dispatch(repo, s, [{"type": "town_dry", "regiment": code, "town": dry, "depot": dep}])
	var reg := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(String((m["facts"] as Array)[0]["text"]), "%s's stores are empty: %s is fed from %s." % [
		String(repo.burgs[dry]["label"]), reg, String(repo.burgs[dep]["label"])])

## Owner 2026-10-07, option A: fed past the depot, it says the realm's stores.
func test_a_dry_town_fed_by_the_realm_says_so() -> void:
	var code := _land()
	var dry := String(TownStores.realm_towns(repo, s)[0])
	var m := MissiveWriter.supply_dispatch(repo, s, [{"type": "town_dry", "regiment": code, "town": dry,
		"depot": TownStores.depot(repo, s), "realm": true}])
	assert_eq(String((m["facts"] as Array)[0]["text"]), "%s's stores are empty: %s is fed from the realm's stores." % [
		String(repo.burgs[dry]["label"]), String(ArmySystem.regiment(repo, code)["label"])])

func test_a_low_event_with_no_town_reads_whole() -> void:
	var m := MissiveWriter.supply_dispatch(repo, s, [
		{"type": "low", "regiment": _land(), "town": ""}, {"type": "empty", "regiment": _land(), "town": ""}])
	for f: Dictionary in m["facts"]:
		var t := String(f["text"])
		assert_false(t.contains("%") or t.contains("{}"), t)
		assert_true(t.ends_with("(no supply point)."), t)

func test_a_day_with_events_files_one_letter_and_a_quiet_day_none() -> void:
	var engine := TickEngine.new(repo)
	var code := _land()
	# out in the field, so no town tops it up before the warnings are read
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(40.0, 0.0)
	ArmySystem.set_march(repo, s, code, at)   # it leaves its camp
	var mm := ArmySystem.pack_to_metres(repo, at)
	s.regiments[code]["x_m"] = mm.x
	s.regiments[code]["y_m"] = mm.y
	s.regiments[code]["dest_x_m"] = mm.x
	s.regiments[code]["dest_y_m"] = mm.y
	# every other unit carries more than it may take, so none of them (a
	# unit camped beyond its town's reach among them) runs low today
	for c in s.regiments.keys():
		if String(c) != code:
			var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, String(c), s), s)
			s.regiments[c]["supplies"] = ArmySystem.max_units(repo, use) + use
	var before := s.missives.size()
	s.regiments[code]["supplies"] = 0     # it goes hungry today: one "empty" event
	# the land under it yields no food, or it would forage and not be empty
	# (spec 2026-10-10-foraging-and-desertion §3.3: warnings read after foraging)
	ConductHelpers.set_food(repo, ArmySystem.province_of(repo, s, ArmySystem.regiment(repo, code, s)), 0)
	engine.advance_day(s)
	var supply: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply" and String(m["title"]) == "Supply dispatch")
	assert_eq(supply.size(), 1)
	engine.advance_day(s)                 # nothing new to say
	supply = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply" and String(m["title"]) == "Supply dispatch")
	assert_eq(supply.size(), 1)
	assert_true(s.missives.size() >= before + 1)
	var facts: Array = supply[0]["facts"]
	assert_eq(facts.filter(func(f: Dictionary) -> bool: return String(f["label"]) == "Empty").size(), 1,
		"the hungry regiment's 'empty' event is in the letter")

func test_the_marshals_report_has_a_row_per_land_regiment_and_resets_the_month() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["m_fee"] = 9
	var rows := SupplyLines.settle_month(repo, s)
	var row := _row(rows, code)
	assert_eq(int(row["fee"]), 9)
	assert_eq(int(s.supply_lines[code]["m_fee"]), 0, "the month starts afresh")
	var m := MissiveWriter.marshal_report(repo, s, 1, rows)
	assert_eq(String(m["kind"]), "supply_month")
	assert_true((m["facts"] as Array).size() >= rows.size())

func test_the_row_adds_the_regiments_own_refill_purchases_and_keeps_the_remainders() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	var ln: Dictionary = s.supply_lines[code]
	ln["m_buy"] = 4
	ln["m_bought"] = {"h1": 3}
	ln["fee_milli"] = 500
	s.regiments[code]["m_buy"] = 6
	s.regiments[code]["m_bought"] = {"h1": 2, "h2": 5}
	var row := _row(SupplyLines.settle_month(repo, s), code)
	assert_eq(int(row["buy"]), 10)
	assert_eq(row["bought"], {"h1": 5, "h2": 5})
	assert_eq(int(s.regiments[code]["m_buy"]), 0)
	assert_eq(s.regiments[code]["m_bought"], {})
	assert_eq(ln["m_bought"], {})
	assert_eq(int(ln["fee_milli"]), 500, "a fraction still owed crosses the month")

func test_a_regiment_without_a_line_still_has_a_row() -> void:
	var code := _land()
	s.supply_lines.erase(code)
	var row := _row(SupplyLines.settle_month(repo, s), code)
	assert_eq(String(row["town"]), "")
	assert_eq(int(row["km"]), 0)
	assert_eq(int(row["fee"]), 0)

func test_the_skim_is_banked_to_the_governor() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["m_skim"] = 100000
	var rows := SupplyLines.settle_month(repo, s)
	var row := _row(rows, code)
	assert_gt(int(row["skimmed"]), 0)
	var gov := String(row["governor"])
	assert_ne(gov, "")
	assert_eq(Governance.skimmed_on(s, gov, "supply_line"), int(row["skimmed"]))

func test_a_month_turn_files_the_marshals_report() -> void:
	var engine := TickEngine.new(repo)
	s.tick = 1
	engine.advance(s)
	var got: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply_month")
	assert_eq(got.size(), 1)

func test_the_opening_tick_files_no_marshals_report() -> void:
	var engine := TickEngine.new(repo)
	s.tick = 0
	engine.advance(s)
	var got: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply_month")
	assert_eq(got.size(), 0)

func test_the_report_tells_the_road_loss_and_who_was_bought_from() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var rows := [
		{"code": code, "town": town, "rate": 1000, "days": 9, "carry": 20, "km": 100, "claimed": 5, "fee": 3,
			"buy": 8, "bought": {"House B": 4, "House A": 2}},
		{"code": code, "town": "", "rate": 0, "days": 9, "carry": 20, "km": 0, "claimed": 0, "fee": 0,
			"buy": 1, "bought": {"House B": 1}}]
	var m := MissiveWriter.marshal_report(repo, s, 1, rows)
	var facts: Array = m["facts"]
	var by_key := {}
	for f: Dictionary in facts:
		by_key[String(f["key"])] = f
	assert_eq(int(by_key["bought@House A"]["exact"]), 2)
	assert_eq(int(by_key["bought@House B"]["exact"]), 5, "summed over the rows")
	assert_eq(String(by_key["bought@House A"]["label"]), "Bought from House House A (units)")
	var keys: Array = facts.map(func(f: Dictionary) -> String: return String(f["key"]))
	assert_lt(keys.find("bought@House A"), keys.find("bought@House B"), "houses in order")
	var pct := SupplySystem.loss_of(repo, 100) / 10
	assert_gt(pct, 0)
	var first := ""
	var second := ""
	for f: Dictionary in facts:
		if String(f["key"]) == "days@" + code:
			if first == "":
				first = String(f["text"])
			else:
				second = String(f["text"])
	assert_string_contains(first, "%d%% lost on the road" % pct)
	assert_false(second.contains("lost on the road"), "no road, no loss")

func test_a_line_cancelled_mid_month_still_reports_its_fee_and_banks_its_skim() -> void:
	var code := _land()
	var realm: Array = TownStores.realm_towns(repo, s)
	var far := ""
	for b: String in repo.burgs.keys():
		if not b in realm:
			far = b
			break
	assert_ne(far, "")
	s.supply_lines[code] = SupplyLines._new_record(far, 1000, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	s.supply_lines[code]["m_fee"] = 7
	s.supply_lines[code]["m_skim"] = 100000
	s.supply_lines[code]["m_bought"] = {"House A": 3}
	SupplyLines.day_step(repo, s)
	assert_false(s.supply_lines.has(code), "the line is cancelled")
	var rows := SupplyLines.settle_month(repo, s)
	var row := _row(rows, code)
	assert_eq(int(row["fee"]), 7)
	assert_eq(row["bought"], {"House A": 3})
	assert_gt(int(row["skimmed"]), 0)
	assert_eq(Governance.skimmed_on(s, String(row["governor"]), "supply_line"), int(row["skimmed"]))
	assert_eq(int(s.regiments[code]["m_fee"]), 0)

func test_the_skims_odd_units_carry_to_next_month() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var upg := TownStores.units_per_gold(repo)
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["m_skim"] = upg * 3 + 1
	var row := _row(SupplyLines.settle_month(repo, s), code)
	assert_eq(int(row["skimmed"]), 3)
	s.supply_lines[code]["m_skim"] = upg - 1
	row = _row(SupplyLines.settle_month(repo, s), code)
	assert_eq(int(row["skimmed"]), 1, "last month's odd unit and this month's make a gold")

func test_the_report_names_the_robbers_of_a_line() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var rows := [{"code": code, "town": town, "rate": 1000, "days": 9, "carry": 20, "km": 100,
		"loss_permille": 170, "robbers": ["Test Brigands"], "claimed": 5, "fee": 3, "buy": 0, "bought": {}}]
	var m := MissiveWriter.marshal_report(repo, s, 1, rows)
	var text := ""
	for f: Dictionary in m["facts"]:
		if String(f["key"]) == "days@" + code:
			text = String(f["text"])
	assert_string_contains(text, "17% lost on the road (Test Brigands)")


## Final review 10: the houses' facts say units, the total says gold, and a
## town no house holds is not "House ".
func test_the_marshals_purchases_say_units_and_gold() -> void:
	var code := _land()
	var rows := SupplyLines.settle_month(repo, s)
	var row := _row(rows, code)
	row["bought"] = {"Ashvale": 30, "": 4}
	row["buy"] = 9
	var m := MissiveWriter.marshal_report(repo, s, 1, rows)
	var by_key := {}
	for f: Dictionary in m["facts"]:
		by_key[String(f["key"])] = f
	assert_eq(String(by_key["supply_buy"]["label"]), "Bought from the houses (gold)")
	assert_eq(int(by_key["supply_buy"]["exact"]), 9)
	assert_eq(String(by_key["bought@Ashvale"]["label"]), "Bought from House Ashvale (units)")
	assert_eq(int(by_key["bought@Ashvale"]["exact"]), 30)
	assert_eq(String(by_key["bought@"]["label"]), "Bought from an unheld town (units)")
	for f: Dictionary in m["facts"]:
		assert_false(String(f.get("label", "")).contains("House  ") or String(f.get("label", "")).ends_with("House "))


## Final review 12: the cut letter says where on the road.
func test_the_cut_letter_says_where() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var kingdom: String = String(repo.kingdoms.keys()[0])
	var at := Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))
	var m := MissiveWriter.supply_dispatch(repo, s, [{"type": "cut", "regiment": code, "town": town,
		"by": kingdom, "at": at}])
	assert_eq(String((m["facts"] as Array)[0]["text"]), "The road from %s to %s is cut near %s by %s." % [
		String(repo.burgs[town]["label"]), String(ArmySystem.regiment(repo, code)["label"]),
		Intel.place_label(repo, s, at), String(repo.kingdoms[kingdom]["label"])])
