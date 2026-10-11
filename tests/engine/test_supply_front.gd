extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A supply line whose town ends up AHEAD of its column breaks by itself and
## says so (owner 2026-10-10; spec 2026-10-08-war-room-draw-orders ruling 20
## kept daily). The column is laid on the straight ray from the crown's rear
## (CourierSystem.origin) to its supply town, so its distance to the rear is
## the town's less `excess` km and the town lies exactly `excess` km farther
## from the rear than the column. With supply_ahead_km 5 and
## supply_front_resume_km 1 (set here), by hand:
##   excess 6   -> 6 > 5        : a flowing line breaks (FRONT)
##   excess 4.5 -> 4.5 > 5 - 1  : a FRONT line stays broken; 4.5 <= 5, a flowing one flows
##   excess 3.5 -> 3.5 <= 4     : a FRONT line flows again

var repo: DataRepository
var s: GameState
var code := ""
var town := ""
var rear := Vector2.ZERO

func before_each() -> void:
	repo = SuiteData.repo()
	repo.balance["supply_ahead_km"] = 5.0
	repo.balance["supply_front_resume_km"] = 1.0
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()
	code = ""
	town = ""
	var m: Character = s.characters[String(s.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = []
	m.attributes["integrity"] = 50
	rear = CourierSystem.origin(repo, s)
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) != "1" and ArmyGround.seated_in(repo, s, String(c)) == "" \
				and ArmySystem.supply_use(repo, reg, s) >= Calendar.DAYS_PER_TICK:
			code = String(c)
			break
	assert_ne(code, "", "a land regiment off any seat")
	s.regiments[code]["camp_town"] = ""   # in the field: no town tops it up
	var towns: Array = TownStores.realm_towns(repo, s)
	towns.sort()
	for t: String in towns:
		var km := _px_km(SupplyLines._burg_px(repo, t).distance_to(rear))
		if km >= 20.0 and km <= 80.0:
			town = t
			break
	assert_ne(town, "", "a realm town 20-80 km from the capital")
	# every OTHER regiment carries more than it may take, so no refill touches the stores
	for c in codes:
		if String(c) != code:
			var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, String(c)), s)
			s.regiments[c]["supplies"] = ArmySystem.max_units(repo, use) + use
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	s.regiments[code]["supplies"] = 0
	s.day = 5
	s.metrics["treasury"] = 100000.0
	_stock(town, 100000)

func after_each() -> void:
	RealmEconomy.forget()

func _px_km(px: float) -> float:
	return px * float(ArmySystem.metres_per_pack_px(repo)) / 1000.0

## Stands the column on the ray from the rear to the town, `excess` km nearer the rear than the town.
func _place(excess: float) -> void:
	var t := SupplyLines._burg_px(repo, town)
	var d := t.distance_to(rear) - excess * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var at := ArmySystem.pack_to_metres(repo, rear + (t - rear).normalized() * d)
	s.regiments[code]["x_m"] = at.x
	s.regiments[code]["y_m"] = at.y

func _stock(t: String, crown: int) -> void:
	s.town_stock[t] = {"crown": crown, "lord": 0, "house": 0}
	TownStores.sync_metrics(repo, s)

func _of(ev: Array, type: String) -> Array:
	return ev.filter(func(e: Dictionary) -> bool: return String(e["type"]) == type and String(e["regiment"]) == code)

func _no_cut() -> void:
	assert_true(SupplyLines.cut_point(repo, s, SupplyLines.road_px(repo, s, code, town)).is_empty(), "no foe on the road")
	assert_true(SupplyLines.siege_cut(repo, s, code).is_empty(), "no siege")

func _ln() -> Dictionary:
	return s.supply_lines[code]


func test_a_town_ahead_breaks_the_line_once_and_it_delivers_nothing() -> void:
	_place(6.0)
	_no_cut()
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FRONT)
	assert_eq(_of(ev, "front").size(), 1, "said once")
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000, "nothing drawn")
	assert_eq(int(s.regiments[code]["supplies"]), 0, "nothing arrives")
	assert_eq(int(_ln()["m_drawn"]), 0)
	assert_eq(int(_ln()["m_fee"]), 0, "no cartage, as a cut line")
	assert_eq(float(s.metrics["treasury"]), 100000.0)
	var again := SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FRONT)
	assert_eq(_of(again, "front").size(), 0, "not said every day")
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000)


func test_it_flows_again_past_the_hysteresis_with_one_event() -> void:
	_place(6.0)
	_no_cut()
	SupplyLines.day_step(repo, s)
	_place(4.5)   # 4.5 > 5 - 1: still broken
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FRONT)
	assert_eq(ev.filter(func(e: Dictionary) -> bool: return String(e["regiment"]) == code).size(), 0)
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000)
	_place(3.5)   # 3.5 <= 4: flows again
	ev = SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FLOWING)
	assert_eq(_of(ev, "front_cleared").size(), 1)
	assert_eq(_of(ev, "restored").size(), 0, "never the cut road's word")
	assert_gt(int(_ln()["m_drawn"]), 0, "the wagons roll again")
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000 - int(_ln()["m_drawn"]))
	assert_eq(_of(SupplyLines.day_step(repo, s), "front_cleared").size(), 0, "said once")


func test_a_flowing_line_inside_the_tolerance_does_not_break() -> void:
	_place(4.5)   # 4.5 <= 5: a line never broken keeps flowing
	_no_cut()
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FLOWING)
	assert_eq(_of(ev, "front").size(), 0)
	assert_gt(int(_ln()["m_drawn"]), 0)


func test_wagons_reaching_a_column_behind_their_town_say_only_the_break() -> void:
	_place(6.0)
	_no_cut()
	_ln()["state"] = SupplyLines.RIDING
	_ln()["ready_day"] = s.absolute_day()
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FRONT)
	assert_eq(_of(ev, "opened").size(), 0)
	assert_eq(_of(ev, "front").size(), 1)


## A regiment camped by a realm town is still topped up by its town when its
## line breaks: the refill is no line (ruling: only a chosen town's line breaks).
func test_the_home_town_refill_is_not_touched() -> void:
	s.supply_lines.clear()
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var held := SupplyLines.home_town(repo, s, String(c))
		if held == "" or String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) == "1":
			continue
		var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, String(c), s))
		var ahead := ""
		var towns: Array = TownStores.realm_towns(repo, s)
		towns.sort()
		for t: String in towns:
			if _px_km(SupplyLines._burg_px(repo, t).distance_to(rear)) > _px_km(at.distance_to(rear)) + 6.0:
				ahead = t
				break
		if ahead == "":
			continue
		s.regiments[c]["supplies"] = 0
		_stock(held, 100000)
		if ahead != held:
			_stock(ahead, 100000)
		s.supply_lines[c] = SupplyLines._new_record(ahead, 1000, 1)
		s.supply_lines[c]["state"] = SupplyLines.FLOWING
		var ev := SupplyLines.day_step(repo, s)
		assert_eq(String(s.supply_lines[c]["state"]), SupplyLines.FRONT)
		assert_true(ev.any(func(e: Dictionary) -> bool: return String(e["type"]) == "front" and String(e["regiment"]) == String(c)))
		assert_gt(int(s.regiments[c]["supplies"]), 0, "its town still tops it up")
		assert_eq(int(s.supply_lines[c]["m_drawn"]), 0, "the line draws nothing")
		return
	fail_test("no camped regiment with a realm town ahead of it")


## An old save's line (the record as it was, no new field) loads and behaves;
## a broken one is saved as the string "front".
func test_an_old_save_line_loads_and_breaks() -> void:
	_place(3.5)
	_no_cut()
	var old := GameState.from_dict(s.to_dict())
	assert_eq(String(old.supply_lines[code]["state"]), SupplyLines.FLOWING)
	SupplyLines.day_step(repo, old)
	assert_eq(String(old.supply_lines[code]["state"]), SupplyLines.FLOWING)
	assert_gt(int(old.supply_lines[code]["m_drawn"]), 0)
	_place(6.0)
	var later := GameState.from_dict(s.to_dict())
	SupplyLines.day_step(repo, later)
	assert_eq(String(later.supply_lines[code]["state"]), SupplyLines.FRONT)
	var back := GameState.from_dict(later.to_dict())
	assert_eq(String(back.supply_lines[code]["state"]), "front")


func test_the_order_refuses_a_town_ahead_where_the_column_stands_when_run() -> void:
	s.supply_lines.clear()
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1000})
	_place(3.5)
	assert_eq(String(SupplyLines.eligibility(repo, s, code)[town]), "", "within the wagons' reach")
	assert_eq(actions.validate(req, s), "", "behind the column: allowed")
	_place(6.0)
	assert_eq(String(SupplyLines.eligibility(repo, s, code)[town]), "", "within the wagons' reach")
	assert_eq(actions.validate(req, s), "%s: on the frontier side of the column" % String(repo.burgs[town]["label"]))


func test_the_cards_the_slip_and_the_news_say_it_plainly() -> void:
	_place(6.0)
	_no_cut()
	var ev := SupplyLines.day_step(repo, s)
	var label := String(repo.burgs[town]["label"])
	var reg := String(ArmySystem.regiment(repo, code, s)["label"])
	var broken := "Broken: %s lies ahead of the column, on the frontier side — choose a supply town behind it" % label
	var stat: Dictionary = (MapObjects.army_card(repo, code, s)["stats"] as Array).filter(
		func(x: Dictionary) -> bool: return String(x["key"]) == "army_supply_line")[0]
	assert_eq(String(stat["text"]), "Line broken: town ahead")
	assert_eq(String(stat["tooltip"]), broken)
	assert_eq(String(stat.get("tone", "")), "warn", "the card writes a broken line in its warning ink")
	var brief: Array = (WarFolio.brief(repo, s, code)["rows"] as Array).filter(
		func(r: Dictionary) -> bool: return String(r["label"]) == "Line")
	assert_eq(String(brief[0]["text"]), broken)
	var supply: Dictionary = WarFolio.sections(repo, s, code).filter(
		func(x: Dictionary) -> bool: return String(x["key"]) == "supply")[0]
	var row: Array = (supply["rows"] as Array).filter(func(r: Dictionary) -> bool: return String(r["label"]) == "Line")
	assert_true(String(row[0]["text"]).begins_with(broken), String(row[0]["text"]))
	var slip := WarPieceSlip.lines(repo, WarPieceSlip.reading(repo, s, [code]))
	assert_eq(String(slip[slip.size() - 2]["text"]), "Line broken")
	assert_eq(String(slip[slip.size() - 2]["kind"]), "rubric")
	assert_eq(String(slip.back()["text"]),
		"%s lies ahead of the column — choose a supply town behind it" % label)
	assert_eq(String(slip.back()["kind"]), "line")
	var said := "The supply line of %s from %s is broken: the town now lies on the frontier side of the column — choose a supply town behind it" % [reg, label]
	assert_eq(SupplyLines.news(repo, s, ev), [said])
	var letter := MissiveWriter.supply_dispatch(repo, s, _of(ev, "front"))
	assert_eq(String(letter["facts"][0]["label"]), "Line broken")
	assert_eq(String(letter["facts"][0]["text"]), said + ".")
	_place(3.5)
	ev = SupplyLines.day_step(repo, s)
	assert_eq(SupplyLines.news(repo, s, ev),
		["The supply line of %s from %s flows again: the town lies behind the column once more" % [reg, label]])
	assert_eq(SupplyLines.front_words(repo, s, code), "", "a flowing line has no broken words")
	assert_false(WarPieceSlip.lines(repo, WarPieceSlip.reading(repo, s, [code])).any(
		func(l: Dictionary) -> bool: return String(l["kind"]) == "rubric"), "a flowing line says nothing")


## Cut wins over front: the foe and the place are the news; once the road is
## clear the line still ahead turns FRONT, never `restored`.
func test_a_cut_road_wins_and_clears_into_front() -> void:
	_place(6.0)
	var route := SupplyLines.road_px(repo, s, code, town)
	var realm := repo.resolve_realm("player_realm")
	var dip: Dictionary = repo.world_table("political", "diplomacy")
	var army := ArmySystem.roster(repo, s)
	var foe: Dictionary = {}
	var keys: Array = army.keys()
	keys.sort()
	for c: String in keys:
		if String(army[c]["kingdom_code"]) != realm:
			foe = army[c]
			dip["%s>%s" % [realm, String(foe["kingdom_code"])]] = {"stance": "Enemy"}
			break
	assert_false(foe.is_empty(), "the pack has a foreign regiment")
	var was := [foe["x"], foe["y"]]
	@warning_ignore("integer_division")
	var mid := route[route.size() / 2]
	foe["x"] = mid.x
	foe["y"] = mid.y
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.CUT)
	assert_eq(_of(ev, "cut").size(), 1)
	assert_eq(_of(ev, "front").size(), 0)
	foe["x"] = was[0]
	foe["y"] = was[1]
	ev = SupplyLines.day_step(repo, s)
	assert_eq(String(_ln()["state"]), SupplyLines.FRONT)
	assert_eq(_of(ev, "front").size(), 1)
	assert_eq(_of(ev, "restored").size(), 0)
	assert_eq(String(_ln()["cut_by"]), "")
