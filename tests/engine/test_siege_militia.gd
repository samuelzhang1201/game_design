extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Town militia (player siege spec §5, step 4a): a besieged town with no
## defenders raises a militia from its population (town_militia.csv by works,
## capped, bounded by what its province can still mobilise), enlisted and
## released through the personnel model, so the people are conserved over
## raise -> dead -> stand down; militia never march.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

func _urban(s: GameState, prov: String) -> int:
	return int(WorldLedger.value_of(repo, s, MilitaryPopulation.path(prov, "urban_population")))


func _set_urban(s: GameState, prov: String, people: int) -> void:
	WorldLedger.apply(repo, s, MilitaryPopulation.path(prov, "urban_population"), people - _urban(s, prov),
		"test: the province's townsfolk", "test")


func _prov(town: String) -> String:
	return String(repo.burgs[town]["province_code"])


## A town held by `realm`, not the capital, with no unit on its seat and no
## unit of the realm's standing at it.
func _empty_town(s: GameState, realm: String) -> String:
	var towns: Array = repo.burgs.keys()
	towns.sort()
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) != realm or ArmyGround.seat_of(repo, s, t) != "" \
				or String(repo.burgs[t].get("is_capital", "0")) == "1":
			continue
		if SiegeSystem.defenders_of(repo, s, t).is_empty():
			return t
	return ""


## --- the size ---------------------------------------------------------------

func test_size_by_works_and_population() -> void:
	var town := String(repo.burgs.keys()[0])
	var b: Dictionary = repo.burgs[town]
	b["population"] = "12551"
	b["features"] = "walls"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 251, "archers": 125},
		"walls: 12551 x 20/1000, x 10/1000")
	b["features"] = "walls|citadel"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 376, "archers": 188},
		"a citadel: x 30/1000, x 15/1000")
	b["features"] = "temple"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 125, "archers": 62},
		"an open town: x 10/1000, x 5/1000")
	b["features"] = "walls"
	b["population"] = "40000"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 400, "archers": 200}, "the caps")


func test_size_bounded_by_what_the_province_can_mobilise() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _empty_town(s, repo.resolve_realm("raider_realm"))
	assert_ne(town, "", "an empty raider town")
	var prov := _prov(town)
	repo.burgs[town]["population"] = "40000"
	repo.burgs[town]["features"] = "walls"
	var held := MilitaryPopulation.occupied(s, prov, "urban_population") \
		+ MilitaryPopulation.restricted(s, prov, "urban_population")
	# available = people x 250/1000 - held = 100
	_set_urban(s, prov, (100 + held) * 4)
	assert_eq(MilitaryPopulation.available(repo, s, prov, "urban_population"), 100)
	assert_eq(TownMilitia.size(repo, s, town), {"infantry": 100}, "infantry first takes what is left")


## --- raised at the siege's open ---------------------------------------------

## A crown unit opens a siege of an empty raider town: {s, town, id, code (the
## militia), want (its size before), urban (the ledger before), held (the
## province's occupied before), unit}.
func _foreign() -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var town := _empty_town(s, repo.resolve_realm("raider_realm"))
	assert_ne(town, "", "an empty raider town")
	var unit := String(Play.land_regiments(repo)[0])
	Play.place(repo, s, unit, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	var prov := _prov(town)
	var want := TownMilitia.size(repo, s, town)
	var urban := _urban(s, prov)
	var held := MilitaryPopulation.occupied(s, prov, TownMilitia.FIELD)
	var id := SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [unit], "task_test")
	var militia: Array = s.sieges[id]["militia"]
	return {"s": s, "town": town, "id": id, "code": "" if militia.is_empty() else String(militia[0]),
		"want": want, "urban": urban, "held": held, "unit": unit, "prov": prov}


## The main host sits down before an empty crown town: {s, town, main, rec}.
func _crown_town() -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var town := _empty_town(s, repo.resolve_realm("player_realm"))
	assert_ne(town, "", "an empty crown town")
	var main := Play.host(repo, "main")
	for c: String in EnemyAi.regiments_of(s, main):
		Play.place(repo, s, c, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	var mind: Dictionary = s.ai_hosts[main]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	EnemyAi.ensure_deployments(repo, s)
	# the hand-set mind reads as an old save's (its `assault` key): forget that
	# conversion, so the siege opens as a fresh one does
	s.sieges.clear()
	mind.erase("siege_id")
	return {"s": s, "town": town, "main": main, "rec": SiegeRecord.ensure_for(repo, s, main)}


func _total(size: Dictionary) -> int:
	var n := 0
	for arm: String in size:
		n += int(size[arm])
	return n


func test_empty_foreign_town_raises_militia() -> void:
	var f := _foreign()
	var s: GameState = f.s
	var code: String = f.code
	var town: String = f.town
	assert_eq(code, "militia:" + String(f.id), "one unit, named by its siege")
	assert_true(s.foes.has(code) and not s.regiments.has(code), "a foe")
	assert_eq(String(s.foes[code]["host"]), "", "in no host")
	assert_eq(TownMilitia.town_of(s, code), town)
	assert_eq(ArmySystem.realm_of(repo, code, s), repo.resolve_realm("raider_realm"), "the defender's")
	assert_eq(ArmyGround.seat_of(repo, s, town), code, "on the seat")
	assert_eq(ArmyGround.seated_in(repo, s, code), town, "it fights from the works")
	assert_eq(SiegeSystem.defenders_of(repo, s, town), [code], "the town's defender")
	var row: Dictionary = s.army_roster[code]
	for arm: String in f.want:
		assert_eq(int(row[arm]), int(f.want[arm]), "%s by the table" % arm)
	assert_eq(String(row["figure"]), TownMilitia.FIGURE, "drawn with the militia's own figure")
	assert_eq(MapObjects.army_piece(repo, row), String(row["organization_arm"]), "its piece stays its first arm's")
	assert_eq(ArmySystem.fit_count(repo, s, code), _total(f.want), "every man fit")
	assert_eq(_urban(s, f.prov), int(f.urban), "no population debit for the levy")
	assert_eq(MilitaryPopulation.occupied(s, f.prov, TownMilitia.FIELD), int(f.held) + _total(f.want),
		"the men reserved at the town's province")
	assert_eq(MilitaryBootstrap._integrity_error(repo, s), "", "the personnel model holds")


func test_crown_town_militia_is_its_garrison() -> void:
	var f := _crown_town()
	var s: GameState = f.s
	var militia: Array = (f.rec as Dictionary)["militia"]
	assert_eq(militia.size(), 1, "a militia")
	var code := String(militia[0])
	assert_true(s.regiments.has(code), "the crown's own unit")
	assert_eq(ArmySystem.realm_of(repo, code, s), repo.resolve_realm("player_realm"))
	assert_eq(EnemyAi.garrison_of(repo, s, f.town), [code], "the town's garrison")
	assert_gt(SiegeSystem.defend_power(repo, s, f.town), 0, "it defends")


func test_a_garrison_raises_none() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var town := ""
	for c: String in Play.land_regiments(repo):
		town = ArmyGround.seated_in(repo, s, c)
		if town != "":
			break
	assert_ne(town, "", "a garrisoned crown town")
	var main := Play.host(repo, "main")
	var mind: Dictionary = s.ai_hosts[main]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	var rec := SiegeRecord.ensure_for(repo, s, main)
	assert_eq(rec["militia"], [], "a garrison raises no militia")
	assert_false(s.army_roster.keys().any(func(c: String) -> bool: return c.begins_with("militia:")))


func test_running_siege_from_an_old_save_raises_none() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _empty_town(s, repo.resolve_realm("player_realm"))
	var main := Play.host(repo, "main")
	var mind: Dictionary = s.ai_hosts[main]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	mind["siege_progress"] = 300
	mind["siege_days"] = 4
	SiegeRecord.migrate(repo, s)
	var rec := SiegeRecord.of_host(s, main)
	assert_eq(int(rec["days"]), 4, "the old siege carries on")
	assert_eq(rec.get("militia", []), [], "no militia for a siege already running")


## --- the people, conserved ----------------------------------------------------

func test_people_conserved_raise_dead_stand_down() -> void:
	var f := _foreign()
	var s: GameState = f.s
	var code: String = f.code
	var total := _total(f.want)
	var died := MilitaryRoster.transfer_units(repo, s, "test:deaths",
		[{"unit_code": code, "from": "fit", "to": "dead", "count": 10}], "test: ten fall on the walls")
	assert_false(died.has("error"), str(died))
	assert_eq(_urban(s, f.prov), int(f.urban) - 10, "a death is the only debit")
	s.sieges.erase(f.id)
	var events := TownMilitia.stand_down(repo, s)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["kind"]), "militia_stood_down")
	assert_eq(int(events[0]["released"]), total - 10, "the living released")
	assert_false(s.foes.has(code) or s.army_roster.has(code) or s.military_rosters.has(code), "the unit is gone")
	assert_false(s.military_cohorts.has(code + ":commoner"), "and its people's record")
	assert_eq(ArmyGround.seat_of(repo, s, f.town), "", "the seat empty again")
	assert_eq(_urban(s, f.prov), int(f.urban) - 10, "release adds no one")
	assert_eq(MilitaryPopulation.occupied(s, f.prov, TownMilitia.FIELD), int(f.held), "nobody still reserved")
	assert_eq(String(s.military_events[code + ":stood_down"]["request"]["reason"]),
		"militia of %s stood down" % String(repo.burgs[f.town]["label"]))
	assert_eq(MilitaryBootstrap._integrity_error(repo, s), "", "the personnel model holds")
	assert_eq(TownMilitia.stand_down(repo, s), [], "once")


func test_stand_down_waits_for_the_battle() -> void:
	var f := _foreign()
	var s: GameState = f.s
	s.battles.append({"id": 999, "att": [f.unit], "def": [f.code], "town": f.town})
	s.sieges.erase(f.id)
	assert_eq(TownMilitia.stand_down(repo, s), [], "not while it fights")
	assert_true(s.foes.has(f.code))
	s.battles.clear()
	assert_eq(TownMilitia.stand_down(repo, s).size(), 1, "once the battle is over")
	assert_false(s.foes.has(f.code))


func test_captives_keep_the_unit_row() -> void:
	var f := _foreign()
	var s: GameState = f.s
	var code: String = f.code
	MilitaryRoster.transfer_units(repo, s, "test:taken",
		[{"unit_code": code, "from": "fit", "to": "captured_current", "count": 5}], "test: five taken")
	s.sieges.erase(f.id)
	TownMilitia.stand_down(repo, s)
	assert_true(s.army_roster.has(code) and s.military_rosters.has(code), "kept for its captives")
	assert_eq(ArmySystem.fit_count(repo, s, code), 0, "the rest released")
	assert_eq(int(s.military_cohorts[code + ":commoner"]["captured_current"]), 5)
	assert_eq(TownMilitia.stand_down(repo, s), [], "nothing more to release")


func test_fall_stands_the_militia_down() -> void:
	var f := _crown_town()
	var s: GameState = f.s
	var code := String((f.rec as Dictionary)["militia"][0])
	(f.rec as Dictionary)["progress"] = 1000
	var events := SiegeSystem.settle_day(repo, s, [])
	var fallen := events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "siege_fallen")
	assert_eq(fallen.size(), 1, "the town falls")
	assert_eq(int(fallen[0]["garrison_out"]), 0, "the militia marches nowhere")
	assert_false(s.regiments.has(code) or s.army_roster.has(code), "it stood down")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "militia_stood_down").size(), 1)


func test_militia_round_trips_the_save() -> void:
	var f := _foreign()
	var s2 := GameState.from_dict((f.s as GameState).to_dict())
	assert_eq(TownMilitia.town_of(s2, f.code), f.town)
	assert_eq(s2.sieges[f.id]["militia"], [f.code])
	assert_true(s2.army_roster.has(f.code) and s2.military_rosters.has(f.code))


## --- militia never march ----------------------------------------------------

func test_militia_never_march() -> void:
	var f := _crown_town()
	var s: GameState = f.s
	var code := String((f.rec as Dictionary)["militia"][0])
	var words := String(repo.task_words["militia"])
	var actions := ActionSystem.new(repo)
	var home: Vector2 = ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	for kind: String in ["ARMY_MARCH", "ARMY_SEAT"]:
		var req := ActionRequest.new()
		req.action_code = kind
		req.params = {"regiment": code, "x": home.x + 40.0, "y": home.y}
		assert_eq(actions.validate(req, s), words, kind + " refused")
	var at := Play.town_m(repo, f.town)
	var shown := ArmyTasks.preview(repo, s, repo.resolve_realm("player_realm"), {"kind": "search",
		"unit_codes": [code], "center_x_m": at.x, "center_y_m": at.y, "radius_m": 5000})
	assert_false(bool(shown["ok"]))
	assert_eq(String(shown["reason"]), words, "no area task either")


## --- a beaten militia breaks up ----------------------------------------------

func test_a_beaten_militia_breaks_up_instead_of_marching() -> void:
	var f := _crown_town()
	var s: GameState = f.s
	var code := String((f.rec as Dictionary)["militia"][0])
	var foe := String(EnemyAi.regiments_of(s, f.main)[0])
	var fit := ArmySystem.fit_count(repo, s, code)
	var battle := {"id": 999, "att": [foe], "def": [code], "town": "", "place_x_m": 0, "place_y_m": 0}
	s.battles.append(battle)
	assert_false(BattleSystem._start_retreat(repo, s, code, battle), "it withdraws nowhere")
	assert_ne(String(s.regiments[code]["order"]), ArmySystem.ORDER_MARCH, "and never marches")
	assert_eq(ArmySystem.fit_count(repo, s, code), 0, "its men go home")
	assert_gt(fit, 0)
	assert_eq(String(s.military_events[code + ":broke"]["request"]["reason"]),
		"militia of %s broke" % String(repo.burgs[f.town]["label"]))
	assert_eq(BattleSystem._exit_why(repo, s, code, "def", "none", 0), "broken", "the battle reads it broken")
	assert_eq(TownMilitia.disperse(repo, s, code), 0, "once")
	assert_eq(MilitaryBootstrap._integrity_error(repo, s), "", "the personnel model holds")
