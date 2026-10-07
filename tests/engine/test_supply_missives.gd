extends GutTest
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
	for t: String in ["opened", "cut", "restored", "town_low", "low", "empty", "cancelled"]:
		events.append({"type": t, "regiment": code, "town": town, "by": kingdom, "days": 3})
	var m := MissiveWriter.supply_dispatch(repo, s, events)
	for f: Dictionary in m["facts"]:
		assert_ne(String(f["text"]), "")
		assert_false(String(f["text"]).contains("%"), "no unfilled placeholder")

func test_a_day_with_events_files_one_letter_and_a_quiet_day_none() -> void:
	var engine := TickEngine.new(repo)
	var code := _land()
	# out in the field, so no town tops it up before the warnings are read
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(40.0, 0.0)
	var mm := ArmySystem.pack_to_metres(repo, at)
	s.regiments[code]["x_m"] = mm.x
	s.regiments[code]["y_m"] = mm.y
	s.regiments[code]["dest_x_m"] = mm.x
	s.regiments[code]["dest_y_m"] = mm.y
	var before := s.missives.size()
	s.regiments[code]["supplies"] = 0     # it goes hungry today: one "empty" event
	engine.advance_day(s)
	var supply: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply")
	assert_eq(supply.size(), 1)
	engine.advance_day(s)                 # nothing new to say
	supply = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply")
	assert_eq(supply.size(), 1)
	assert_true(s.missives.size() >= before + 1)

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
