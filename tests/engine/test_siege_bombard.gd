extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Player siege spec §4.2 and §4.4 "What the works give in the assault", step 8
## (SiegeTactics.bombard, BattleStrength town:works): the engines men build
## engines for gold, the bombard men crew them and the guns, each crewed engine
## knocks bombard_damage off the walls a day, the defenders mend them, a built
## engine wears out, and at siege_breach_integrity a section is down. In a town
## battle the defenders' works count as much as the walls still stand.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

## A walled raider town besieged by one crown unit of 300 fit men with no guns,
## its defenders trimmed to `defenders` fit men in all: {s, town, id, code, def}.
func _walled(defenders: int) -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var raider := repo.resolve_realm("raider_realm")
	var towns: Array = repo.burgs.keys()
	towns.sort()
	var town := ""
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) == raider and TownMilitia.works_of_town(repo, t) == "walls":
			town = t
			break
	assert_ne(town, "", "a walled raider town")
	var code := ""
	for c: String in Play.land_regiments(repo, 300):
		if int(float(ArmySystem.regiment(repo, c).get("artillery", 0))) == 0:
			code = c
			break
	assert_ne(code, "", "a crown unit with no guns")
	Play.place(repo, s, code, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	var id := SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [code], "task_test")
	_trim(s, code, 300)
	var def: Array = SiegeSystem.defenders_of(repo, s, town)
	assert_false(def.is_empty(), "the town has defenders (its militia)")
	_trim(s, def[0], defenders)
	for i in range(1, def.size()):
		_trim(s, def[i], 0)
	assert_eq(SiegeSystem.garrison_fit(repo, s, town), defenders)
	assert_eq(int(s.sieges[id]["integrity"]), 1000, "walls open whole")
	return {"s": s, "town": town, "id": id, "code": code, "def": def[0]}


## Leaves exactly `men` fit in unit `code`: the rest are wounded.
func _trim(s: GameState, code: String, men: int) -> void:
	var extra := ArmySystem.fit_count(repo, s, code) - men
	assert_true(extra >= 0, "%s has %d men" % [code, men])
	var changes: Array = []
	for cid: String in s.military_rosters[code]["cohort_ids"]:
		var take := mini(extra, int(s.military_cohorts[cid]["fit"]))
		if take > 0:
			changes.append({"cohort_id": cid, "from": "fit", "to": "wounded", "count": take})
			extra -= take
	if not changes.is_empty():
		assert_false(MilitaryRoster.transition(repo, s, "trim:%s:%d" % [code, men], changes, "test trim").has("error"))
	assert_eq(ArmySystem.fit_count(repo, s, code), men)


func _treasury(s: GameState) -> int:
	return int(float(WorldLedger.value_of(repo, s, "metrics.treasury")))


## --- the data ----------------------------------------------------------------

func test_the_rates_are_data() -> void:
	assert_eq(int(repo.siege_tactics["town"]["bombard_damage"]), 0, "an open town has no works to batter")
	assert_eq(int(repo.siege_tactics["walls"]["bombard_damage"]), 40)
	assert_eq(int(repo.siege_tactics["citadel"]["bombard_damage"]), 25, "a citadel's is smaller")
	for key: String in ["siege_engine_man_days", "siege_engine_gold", "siege_engine_crew",
			"siege_repair_per_100_men", "siege_engine_wear_days", "siege_breach_integrity"]:
		assert_true(int(repo.bal(key)) > 0, key)


## --- the hand fixture: engines × damage against repair ------------------------

func test_batter_against_repair() -> void:
	# walls 40 a crewed engine, 200 defenders would mend 20 a day
	assert_eq(SiegeTactics.batter(1000, 0, 40, 20), 1000, "never above 1000")
	assert_eq(SiegeTactics.batter(1000, 1, 40, 20), 980, "1000 − 40 + 20")
	assert_eq(SiegeTactics.batter(940, 2, 40, 20), 880, "940 − 80 + 20")
	assert_eq(SiegeTactics.batter(760, 3, 40, 20), 660, "760 − 120 + 20")
	assert_eq(SiegeTactics.batter(100, 3, 40, 20), 0, "never below 0, and no repair at 0")
	assert_eq(SiegeTactics.batter(0, 0, 40, 20), 0, "rubble is not mended")


func test_engines_against_repair_day_by_day_to_a_breach() -> void:
	# 300 men: engines 100 (an engine every 300 man-days = 3 days, 50 gold
	# each), bombard 60 (3 crews of 20), blockade 140. 100 defenders mend 10 a
	# day. No guns. Walls take 40 a crewed engine. Hand-computed:
	#  day  built  crewed  integrity
	#   1     0      0     1000          (work 100)
	#   2     0      0     1000          (work 200)
	#   3     1      1      970          1000 − 40 + 10
	#   4,5   1      1      940, 910
	#   6     2      2      840          910 − 80 + 10
	#   7,8   2      2      770, 700
	#   9     3      3      590          700 − 120 + 10
	#  10,11  3      3      480, 370
	#  12     4      3      260          four engines, three crews
	#  13     4      3      150          ≤ 200: the breach
	var f := _walled(100)
	var s: GameState = f["s"]
	var id: String = f["id"]
	WorldLedger.apply(repo, s, "metrics.treasury", 1000.0, "test purse", "test")
	var gold := _treasury(s)
	assert_false(SiegeTactics.allocate(repo, s, id, {"engines": 100, "bombard": 60, "blockade": 140}).has("error"))
	var want := [1000, 1000, 970, 940, 910, 840, 770, 700, 590, 480, 370, 260, 150]
	var built := [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4]
	var rec: Dictionary = s.sieges[id]
	for d in want.size():
		SiegeTactics.bombard(repo, s, id)
		assert_eq(int(rec["integrity"]), int(want[d]), "integrity on day %d" % (d + 1))
		assert_eq(int(rec["engines_built"]), int(built[d]), "engines on day %d" % (d + 1))
		assert_eq(int(rec["breach"]), 1 if d == 12 else 0, "breach on day %d" % (d + 1))
	assert_eq(gold - _treasury(s), 4 * 50, "four engines at 50 gold")
	assert_eq(int(rec["engine_wear"]), 11, "built engines fired days 3..13, none worn yet")
	var kinds: Array = (rec["history"] as Array).map(func(h: Dictionary) -> String: return String(h["kind"]))
	assert_eq(kinds.count("engine_built"), 4)
	assert_eq(kinds.count("breach"), 1)
	var line: Dictionary = (rec["history"] as Array).filter(func(h: Dictionary) -> bool: return h["kind"] == "breach")[0]
	assert_string_contains(String(line["reason"]), "150/1000")
	SiegeTactics.bombard(repo, s, id)
	assert_eq(int(rec["integrity"]), 40, "the engines keep firing: 150 − 120 + 10")
	assert_eq(int(rec["breach"]), 1, "the breach stays")
	kinds = (rec["history"] as Array).map(func(h: Dictionary) -> String: return String(h["kind"]))
	assert_eq(kinds.count("breach"), 1, "the breach is told once")


func test_an_engine_waits_for_its_gold() -> void:
	var f := _walled(100)
	var s: GameState = f["s"]
	var id: String = f["id"]
	WorldLedger.apply(repo, s, "metrics.treasury", -float(_treasury(s)) + 49.0, "test purse", "test")
	assert_eq(_treasury(s), 49)
	SiegeTactics.allocate(repo, s, id, {"engines": 300})
	SiegeTactics.bombard(repo, s, id)
	var rec: Dictionary = s.sieges[id]
	assert_eq(int(rec["engines_built"]), 0, "49 gold buys no engine")
	assert_eq(int(rec["engine_work"]), 300, "the finished work waits, never banked past one engine")
	assert_eq(_treasury(s), 49)
	WorldLedger.apply(repo, s, "metrics.treasury", 1.0, "test purse", "test")
	SiegeTactics.bombard(repo, s, id)
	assert_eq(int(rec["engines_built"]), 1, "paid: 300 + 300 work, one engine, the rest waits")
	assert_eq(int(rec["engine_work"]), 300)
	assert_eq(_treasury(s), 0)


func test_a_built_engine_wears_out() -> void:
	repo.balance["siege_engine_wear_days"] = 2.0
	var f := _walled(100)
	var s: GameState = f["s"]
	var id: String = f["id"]
	var rec: Dictionary = s.sieges[id]
	rec["engines_built"] = 2
	SiegeTactics.allocate(repo, s, id, {"bombard": 20})
	SiegeTactics.bombard(repo, s, id)
	assert_eq(int(rec["engines_built"]), 2, "one day of firing")
	SiegeTactics.bombard(repo, s, id)
	assert_eq(int(rec["engines_built"]), 1, "two days: one engine lost")
	assert_eq(int(rec["engine_wear"]), 0, "the count restarts")
	var last: Dictionary = (rec["history"] as Array).back()
	assert_eq(String(last["kind"]), "engine_worn")


func test_an_open_town_is_not_bombarded() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var raider := repo.resolve_realm("raider_realm")
	var towns: Array = repo.burgs.keys()
	towns.sort()
	var town := ""
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) == raider and TownMilitia.works_of_town(repo, t) == "town":
			town = t
			break
	assert_ne(town, "", "an open raider town")
	var code: String = Play.land_regiments(repo, 300)[0]
	Play.place(repo, s, code, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	var id := SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [code], "task_test")
	WorldLedger.apply(repo, s, "metrics.treasury", 1000.0, "test purse", "test")
	var gold := _treasury(s)
	SiegeTactics.allocate(repo, s, id, {"engines": 200})
	for i in 3:
		SiegeTactics.bombard(repo, s, id)
	assert_eq(int(s.sieges[id].get("engines_built", 0)), 0, "no engines for an open town")
	assert_eq(_treasury(s), gold, "no gold spent")
	assert_eq(int(s.sieges[id]["integrity"]), 0)


func test_fit_guns() -> void:
	var code := ""
	for c: String in Play.land_regiments(repo, 1):
		if int(float(ArmySystem.regiment(repo, c).get("artillery", 0))) > 0:
			code = c
			break
	if code == "":
		pass_test("no artillery unit on this pack")
		return
	var s := SuiteData.campaign(repo, 7)
	var reg := ArmySystem.regiment(repo, code, s)
	var guns := int(float(reg["artillery"]))
	assert_eq(SiegeTactics.fit_guns(repo, s, code), guns, "every gun crewed at full strength")
	var cap := ArmySystem.personnel_capacity(repo, reg)
	_trim(s, code, cap / 2)
	@warning_ignore("integer_division")
	assert_eq(SiegeTactics.fit_guns(repo, s, code), guns * (cap / 2) / cap, "half the men, half the guns")


## --- the works factor ---------------------------------------------------------------

func test_works_permille_hand_fixture() -> void:
	# walls infantry defend 1300: scaled = 1000 + 300 × I / 1000
	assert_eq(SiegeTactics.works_permille(1300, 1000, false), 1300, "whole walls: the full works")
	assert_eq(SiegeTactics.works_permille(1300, 500, false), 1150, "half the walls: half the bonus")
	assert_eq(SiegeTactics.works_permille(1300, 0, false), 1000, "a breach: none")
	# a seat holder already has the full works: scaled / full
	assert_eq(SiegeTactics.works_permille(1300, 1000, true), 1000, "nothing taken from whole walls")
	assert_eq(SiegeTactics.works_permille(1300, 500, true), 884, "1150000 / 1300 = 884")
	assert_eq(SiegeTactics.works_permille(1300, 0, true), 769, "1000000 / 1300 = 769")
	assert_eq(SiegeTactics.works_permille(1000, 0, true), 1000, "an arm the walls do not help")


func _works_factor(s: GameState, code: String) -> Dictionary:
	var out := BattleStrength.unit(repo, s, code, false)
	assert_false(out.has("error"), str(out.get("error", "")))
	for fac: Dictionary in out["factors"]:
		if String(fac["source"]) == "town:works":
			return fac
	return {}


func test_the_works_factor_follows_the_walls() -> void:
	var f := _walled(100)
	var s: GameState = f["s"]
	var def: String = f["def"]
	var rec: Dictionary = s.sieges[f["id"]]
	assert_true(_works_factor(s, def).is_empty(), "no battle at the town: no factor")
	s.battles.append({"id": 9999, "att": [f["code"]], "def": [def], "town": f["town"]})
	assert_ne(ArmySystem.works_of(repo, ArmySystem.regiment(repo, def, s), s), "", "the militia holds the seat")
	var whole := _works_factor(s, def)
	assert_eq(int(whole.get("permille", -1)), 1000, "whole walls: the seat's works as they are")
	assert_string_contains(String(whole["reason"]), "1000/1000")
	rec["integrity"] = 500
	var half := int(_works_factor(s, def)["permille"])
	assert_true(half >= 884 and half <= 900, "between the arms' 884 and 900 (archers 1250): %d" % half)
	rec["breach"] = 1
	var broken := int(_works_factor(s, def)["permille"])
	assert_true(broken >= 769 and broken <= 800, "a breach: between 769 and 800: %d" % broken)
	assert_true(_works_factor(s, f["code"]).is_empty(), "the attacker gets no works")
