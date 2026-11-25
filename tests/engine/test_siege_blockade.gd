extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Player siege spec §4.1, step 6 (SiegeBlockade): a besieged town's entries
## close by men in descending share, its stores move by what the open entries
## let in, its defenders starve at none, and a starving garrison yields under
## the laws. A crown town's inflows (TownStores.deposit_month) and its
## garrison's supply lines (SupplyLines.siege_cut) are gated by the entries.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

## The town's routes are replaced by three made ones (pack px, straight): a
## road east, a trail drawn INTO the town from the south (its near end last),
## and a sea route west. Raw shares 400 / 200 / 300 and the countryside's 300
## (siege_entries.csv) over 1200: 333.3, 166.7, 250, 250 → 333, 167, 250, 250.
func _made_routes(town: String) -> void:
	var b: Dictionary = repo.burgs[town]
	var tp := Vector2(float(b["x"]), float(b["y"]))
	repo.routes.clear()
	for row: Array in [["zz_road", "roads", PackedVector2Array([tp, tp + Vector2(400, 0)])],
			["zz_trail", "trails", PackedVector2Array([tp + Vector2(0, 400), tp])],
			["zz_sea", "searoutes", PackedVector2Array([tp, tp + Vector2(-400, 0)])]]:
		repo.routes[row[0]] = {"route_code": row[0], "group": row[1], "from_burg": town, "to_burg": "",
			"polyline": row[2]}


## A crown unit besieges a raider town with the made routes: {s, town, id, unit}.
## The town raises its militia (or wakes its garrison) as the record opens.
func _foreign() -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var raider := repo.resolve_realm("raider_realm")
	var towns: Array = repo.burgs.keys()
	towns.sort()
	var town := ""
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) == raider:
			town = t
			break
	assert_ne(town, "", "a raider town")
	_made_routes(town)
	var unit := String(Play.land_regiments(repo)[0])
	Play.place(repo, s, unit, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	var id := SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [unit], "task_test")
	return {"s": s, "town": town, "id": id, "unit": unit}


## --- the stores (P6.2's fixture) ---------------------------------------------

func test_stores_fall_by_the_closed_share() -> void:
	# stores 100, need 10, open inflow 4 (an open share of 400): 100 − 10 + 4 = 94
	var st := 100
	var days: Array = []
	for d in 10:
		st = SiegeBlockade.stores_day(st, 10, 400)
		days.append(st)
	assert_eq(days[0], 94, "day 1")
	assert_eq(days[2], 82, "day 3: 100 − 3 × 6")
	assert_eq(days[9], 40, "day 10: 100 − 10 × 6")
	st = 100
	for d in 10:
		st = SiegeBlockade.stores_day(st, 10, 0)
	assert_eq(st, 0, "fully closed: 0 on day 10")
	assert_eq(SiegeBlockade.stores_day(st, 10, 0), 0, "never below 0")
	assert_eq(SiegeBlockade.stores_day(100, 10, 1000), 100, "every entry open: nothing lost")


## --- the entries ----------------------------------------------------------------

func test_entries_by_route_and_share() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := String(repo.burgs.keys()[0])
	_made_routes(town)
	var entries := SiegeBlockade.entries_of(repo, town)
	assert_eq(entries.keys().size(), 4, "three routes and the countryside")
	var shares := {}
	for e: String in entries:
		shares[e] = int(entries[e]["inflow_share"])
		assert_eq(String(entries[e]["closed_by"]), "", "all open")
	assert_eq(shares, {"zz_road": 333, "zz_trail": 167, "zz_sea": 250, SiegeBlockade.COUNTRYSIDE: 250})
	var b: Dictionary = repo.burgs[town]
	var tp := Vector2(float(b["x"]), float(b["y"]))
	var px := float(repo.bal("siege_entry_km")) * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var road := ArmySystem.pack_to_metres(repo, tp + Vector2(px, 0))
	assert_eq([int(entries["zz_road"]["x_m"]), int(entries["zz_road"]["y_m"])], [road.x, road.y],
		"siege_entry_km along the road from the town")
	var trail := ArmySystem.pack_to_metres(repo, tp + Vector2(0, px))
	assert_eq([int(entries["zz_trail"]["x_m"]), int(entries["zz_trail"]["y_m"])], [trail.x, trail.y],
		"measured from the trail's end at the town, though it is drawn into it")
	var home := ArmyGround.town_point_m(repo, town)
	assert_eq([int(entries[SiegeBlockade.COUNTRYSIDE]["x_m"]), int(entries[SiegeBlockade.COUNTRYSIDE]["y_m"])],
		[home.x, home.y], "the countryside at the town")
	repo.routes.clear()
	var alone := SiegeBlockade.entries_of(repo, town)
	assert_eq(alone.keys(), [SiegeBlockade.COUNTRYSIDE], "no route: the countryside alone")
	assert_eq(int(alone[SiegeBlockade.COUNTRYSIDE]["inflow_share"]), 1000)
	assert_not_null(s)


## --- closing ---------------------------------------------------------------------

func test_too_few_men_close_no_entry() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	var fit := ArmySystem.fit_count(repo, s, f["unit"])
	assert_gt(fit, 0)
	# the unit's men are short of one entry's need: the town keeps every share
	repo.balance["siege_blockade_men_per_entry"] = fit + 1
	SiegeBlockade.close(repo, s, f["id"])
	var rec: Dictionary = s.sieges[f["id"]]
	assert_eq(SiegeBlockade.open_share(rec), 1000, "nothing closed")
	# just enough for one: the largest entry (the road, 333) closes, no more
	repo.balance["siege_blockade_men_per_entry"] = fit
	SiegeBlockade.close(repo, s, f["id"])
	var entries: Dictionary = rec["entries"]
	assert_eq(String(entries["zz_road"]["closed_by"]), String(f["unit"]), "the road, by its unit")
	for e: String in ["zz_trail", "zz_sea", SiegeBlockade.COUNTRYSIDE]:
		assert_eq(String(entries[e]["closed_by"]), "", e + " open")
	assert_eq(SiegeBlockade.open_share(rec), 667, "1000 − 333")
	var at := BattleSystem._at_m(repo, s, f["unit"])
	var reach := int(repo.bal("siege_entry_reach_m"))
	assert_true(MarchClearance.dist2(at, Vector2i(int(entries["zz_road"]["x_m"]), int(entries["zz_road"]["y_m"]))) \
		<= reach * reach, "the unit camps at its entry")
	assert_true(SiegeSystem.deployed_at(repo, s, f["unit"], f["town"]), "and still besieges the town")


func test_a_held_entry_stays_with_its_unit() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	var town: String = f["town"]
	# the record's unit is the later code; an arrival sorting before it comes next
	var units: Array = Play.land_regiments(repo).slice(0, 4)
	units.sort()
	var held := String(f["unit"])
	var early := String(units[0]) if String(units[0]) != held else String(units[1])
	if early > held:
		var swap := held
		held = early
		early = swap
		s.sieges[f["id"]]["units"] = [held]
		Play.place(repo, s, held, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
		Play.place(repo, s, f["unit"], Play.town_m(repo, town) + Vector2i(0, 400000), ArmySystem.ORDER_STANDBY)
	repo.balance["siege_blockade_men_per_entry"] = mini(ArmySystem.fit_count(repo, s, held), ArmySystem.fit_count(repo, s, early))
	SiegeBlockade.close(repo, s, f["id"])
	var entries: Dictionary = s.sieges[f["id"]]["entries"]
	assert_eq(String(entries["zz_road"]["closed_by"]), held, "the road, by the first unit there")
	Play.place(repo, s, early, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [early], "task_test")
	SiegeBlockade.close(repo, s, f["id"])
	assert_eq(String(entries["zz_road"]["closed_by"]), held, "the arrival sorting first does not take it over")
	assert_eq(String(entries[SiegeBlockade.COUNTRYSIDE]["closed_by"]), early, "the arrival closes the next entry")


func test_a_sea_entry_never_closes() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	repo.balance["siege_blockade_men_per_entry"] = 1
	var units: Array = Play.land_regiments(repo).slice(0, 4)
	for c: String in units:
		Play.place(repo, s, c, Play.town_m(repo, f["town"]), ArmySystem.ORDER_GARRISON)
	SiegeRecord.open_units(repo, s, f["town"], repo.resolve_realm("player_realm"), units, "task_test")
	SiegeBlockade.close(repo, s, f["id"])
	var rec: Dictionary = s.sieges[f["id"]]
	assert_eq(String(rec["entries"]["zz_sea"]["closed_by"]), "", "the sea stays open")
	assert_eq(SiegeBlockade.open_share(rec), 250, "the port keeps its sea share")


func test_relief_requires_an_open_route() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	repo.balance["siege_blockade_men_per_entry"] = ArmySystem.fit_count(repo, s, f["unit"])
	SiegeBlockade.close(repo, s, f["id"])
	var rec: Dictionary = s.sieges[f["id"]]
	assert_eq(SiegeBlockade.open_share(rec), 667)
	# a relief column of the town's kingdom comes up beside the entry: flags on
	# the horizon reopen nothing
	var relief := String(EnemyAi.live_regiments(repo, s, Play.host(repo, "main"))[0])
	var road := Vector2i(int(rec["entries"]["zz_road"]["x_m"]), int(rec["entries"]["zz_road"]["y_m"]))
	Play.place(repo, s, relief, road + Vector2i(1000, 0), ArmySystem.ORDER_GARRISON)
	SiegeBlockade.close(repo, s, f["id"])
	assert_eq(String(rec["entries"]["zz_road"]["closed_by"]), String(f["unit"]), "still closed")
	assert_eq(SiegeBlockade.open_share(rec), 667)
	# only when the closing unit is driven off (it falls back) does the road open
	s.regiments[f["unit"]]["disengaging"] = 1
	SiegeBlockade.close(repo, s, f["id"])
	assert_eq(String(rec["entries"]["zz_road"]["closed_by"]), "", "reopened")
	assert_eq(SiegeBlockade.open_share(rec), 1000)


## --- a foreign town's food and hunger ---------------------------------------------

func test_a_foreign_town_opens_with_its_stores_and_starves() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	var town: String = f["town"]
	var rec: Dictionary = s.sieges[f["id"]]
	var defs := SiegeSystem.defenders_of(repo, s, town)
	assert_false(defs.is_empty(), "the town has defenders")
	var ration := 0
	for c: String in defs:
		ration += ArmySystem.day_bite(ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, s), s), s.day)
	@warning_ignore("integer_division")
	var civil := int(repo.burgs[town]["population"]) * int(repo.bal("siege_civil_need_permille")) / 1000
	var need := ration + civil
	assert_eq(SiegeBlockade.need(repo, s, town), need, "the defenders' ration and the people's")
	var days := int(repo.siege_tactics[TownMilitia.works_of_town(repo, town)]["stores_days"])
	assert_eq(int(rec["stores"]), need * days, "need × stores_days by works at open")
	repo.balance["siege_blockade_men_per_entry"] = ArmySystem.fit_count(repo, s, f["unit"])
	var before := int(rec["stores"])
	SiegeBlockade.day(repo, s, f["id"])
	@warning_ignore("integer_division")
	assert_eq(int(rec["stores"]), maxi(0, before - need + need * 667 / 1000), "the day: the road closed")
	assert_false(SiegeSystem.starving(repo, s, town))
	rec["stores"] = 0
	var morale := {}
	for c: String in defs:
		morale[c] = int(s.foes[c]["morale"])
	SiegeBlockade.day(repo, s, f["id"])
	assert_true(SiegeSystem.starving(repo, s, town), "no stores, defenders standing")
	for c: String in defs:
		assert_eq(int(s.foes[c]["morale"]), maxi(0, int(morale[c]) - int(repo.bal("army_morale_starving_day"))),
			c + " goes hungry")


func test_a_starving_town_yields_under_quarter() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	var town: String = f["town"]
	var defs := SiegeSystem.defenders_of(repo, s, town)
	var men := 0
	for c: String in defs:
		men += ArmySystem.living_count(repo, s, c)
		s.foes[c]["morale"] = 10
	s.sieges[f["id"]]["stores"] = 0
	var events := SiegeSystem.settle_day(repo, s)
	var taken := events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "siege_ours_taken")
	assert_eq(taken.size(), 1, "the town is handed over")
	assert_eq(int(taken[0].get("yielded", 0)), 1, "by hunger")
	assert_eq(String(s.occupations[town]["occupier"]), repo.resolve_realm("player_realm"))
	var held := 0
	for b: String in s.prisoner_batches:
		if String(s.prisoner_batches[b]["holder_code"]) == String(f["unit"]):
			held += int(s.prisoner_batches[b]["commoners"]) + int(s.prisoner_batches[b]["nobles"])
	assert_gt(held, 0)
	assert_eq(held, men, "the garrison, fit and wounded, are the besieger's captives")


func test_no_yield_under_refused_quarter() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	var town: String = f["town"]
	for c: String in SiegeSystem.defenders_of(repo, s, town):
		s.foes[c]["morale"] = 10
	s.sieges[f["id"]]["stores"] = 0
	s.law_in_force["unit:" + String(f["unit"])] = {"quarter": {"value": "refuse", "decree_id": 1}}
	assert_eq(LawSystem.value(repo, s, "quarter", f["unit"]), "refuse")
	SiegeSystem.settle_day(repo, s)
	assert_false(s.occupations.has(town), "no yield is accepted")
	assert_true(s.sieges.has(f["id"]), "the siege goes on")
	assert_true(SiegeSystem.starving(repo, s, town), "the town holds on, starving")


## --- a crown town's inflows ----------------------------------------------------------

## The main host besieges the depot, its first column at the town; `guard`
## garrisons it. {s, town, host, first, guard, id}.
func _crown_besieged() -> Dictionary:
	repo = SuiteData.flat_ground(repo)
	repo.balance["ai_retreat_supply_days"] = 0
	repo.balance["siege_assault_days"] = 99
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 10
	var host := Play.host(repo, "main")
	var units := EnemyAi.live_regiments(repo, s, host)
	var first := String(units[0])
	var guard := String(Play.land_regiments(repo)[0])
	var town := TownStores.depot(repo, s)
	var at := Play.town_m(repo, town)
	Play.park_army(repo, s, at + Vector2i(500000, 0))
	for c: String in s.foes.keys():
		if c != first:
			s.foes.erase(c)
	for h: String in s.ai_hosts.keys():
		if h != host:
			s.ai_hosts.erase(h)
	Play.place(repo, s, guard, at, ArmySystem.ORDER_GARRISON)
	Play.place(repo, s, first, at + Vector2i(3000, 0), ArmySystem.ORDER_STANDBY)
	s.foes[first]["supplies"] = 100000
	s.foes[first]["morale"] = 100
	s.ai_hosts[host]["mode"] = "ADVANCE"
	s.ai_hosts[host]["target_kind"] = "town"
	s.ai_hosts[host]["target_id"] = town
	EnemyAi.step_day(repo, s)
	s.day += 1
	EnemyAi.step_day(repo, s)
	assert_true(SiegeSystem.besieged(repo, s, town), "the depot is besieged")
	var id := SiegeRecord.of_town(s, town)
	SiegeBlockade.ensure(repo, s, id)
	return {"s": s, "town": town, "host": host, "first": first, "guard": guard, "id": id}


func test_a_crown_towns_month_comes_in_by_its_open_share() -> void:
	var c := _crown_besieged()
	var s: GameState = c["s"]
	var town: String = c["town"]
	var rec: Dictionary = s.sieges[c["id"]]
	var entries: Dictionary = rec["entries"]
	entries[SiegeBlockade.COUNTRYSIDE]["closed_by"] = c["first"]
	var share := 1000 - int(entries[SiegeBlockade.COUNTRYSIDE]["inflow_share"])
	assert_eq(SiegeBlockade.open_share(rec), share)
	var outside := TownStores._outside(repo, s, town)
	assert_ne(outside, town, "another realm town takes what is kept out")
	var inflow := TownStores.month_inflow(repo, s)
	var row: Dictionary = inflow.get(town, {"lord": 0, "crown": 0, "house": 0})
	var other: Dictionary = inflow.get(outside, {"lord": 0, "crown": 0, "house": 0})
	assert_gt(int(row["lord"]) + int(row["crown"]), 0, "the town has a month")
	var upg := TownStores.units_per_gold(repo)
	var was := TownStores.stock_of(s, town).duplicate()
	var was_out := TownStores.stock_of(s, outside).duplicate()
	TownStores.deposit_month(repo, s)
	for pool: String in ["lord", "crown"]:
		@warning_ignore("integer_division")
		var got := int(row[pool]) * share / 1000
		assert_eq(int(TownStores.stock_of(s, town)[pool]) - int(was[pool]), got * upg, pool + " at the open share")
		assert_eq(int(TownStores.stock_of(s, outside)[pool]) - int(was_out[pool]),
			(int(other[pool]) + int(row[pool]) - got) * upg, pool + ": the rest lands outside")


func test_a_line_is_cut_only_through_a_closed_entry() -> void:
	var c := _crown_besieged()
	var s: GameState = c["s"]
	var town: String = c["town"]
	var rec: Dictionary = s.sieges[c["id"]]
	var home := ArmyGround.town_point_m(repo, town)
	var point := home + Vector2i(3000, 0)
	rec["entries"] = {"zz_road": {"group": "roads", "x_m": point.x, "y_m": point.y, "inflow_share": 700, "closed_by": ""},
		SiegeBlockade.COUNTRYSIDE: {"group": SiegeBlockade.COUNTRYSIDE, "x_m": home.x, "y_m": home.y,
			"inflow_share": 300, "closed_by": c["first"]}}
	var p := ArmySystem.metres_to_pack(repo, point)
	var through := PackedVector2Array([p + Vector2(0, -1), p + Vector2(0, 1), ArmySystem.metres_to_pack(repo, home)])
	assert_eq(ArmyGround.garrison_town(repo, s, c["guard"]), town, "the guard garrisons it")
	assert_true(SupplyLines.siege_cut(repo, s, c["guard"], through).is_empty(),
		"a closed countryside cuts no road, an open road lets the line through")
	rec["entries"]["zz_road"]["closed_by"] = c["first"]
	var cut := SupplyLines.siege_cut(repo, s, c["guard"], through)
	assert_false(cut.is_empty(), "the road's closed entry cuts it")
	assert_eq(cut["at"], p, "at the entry")
	var away := PackedVector2Array([p + Vector2(0, -400), p + Vector2(0, -300)])
	assert_true(SupplyLines.siege_cut(repo, s, c["guard"], away).is_empty(), "a road that passes no closed entry flows")


func test_a_record_round_trips_its_blockade() -> void:
	var f := _foreign()
	var s: GameState = f["s"]
	repo.balance["siege_blockade_men_per_entry"] = ArmySystem.fit_count(repo, s, f["unit"])
	SiegeBlockade.day(repo, s, f["id"])
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var rec: Dictionary = back.sieges[f["id"]]
	assert_eq(SiegeBlockade.open_share(rec), 667)
	assert_eq(int(rec["stores"]), int(s.sieges[f["id"]]["stores"]))
	var floats: Array = []
	Play.floats_in(s.sieges, "sieges", floats)
	assert_eq(floats, [], "whole numbers")
