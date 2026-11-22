extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The siege's sides (player siege spec §5, §7, step 3): the record's attacker
## and defender drive the day, the fall and the occupation, so a crown
## besieger (a record with `units`) takes an occupied town back through the
## enemy's own rules; an occupation (GameState.occupations) is either side's,
## freed when its occupier leaves; a crown besieger waits for its assault
## before the town's defenders and storms them in the town battle.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == kind)


func _label(town: String) -> String:
	return String(repo.burgs[town]["label"])


## The last manor_log line of `cell`.
func _last_reason(s: GameState, cell: int) -> String:
	var lines: Array = s.manor_log.filter(func(m: Dictionary) -> bool: return int(m["cell"]) == cell)
	return "" if lines.is_empty() else String((lines[-1] as Dictionary)["reason"])


## A land unit of the crown's, not `but`, with men.
func _other_unit(s: GameState, but: Array) -> String:
	for c: String in Play.land_regiments(repo):
		if not c in but and s.regiments.has(c) and ArmySystem.fit_count(repo, s, c) > 0:
			return c
	return ""


## The main host takes a crown town by hand (as test_siege's siege at 1000):
## {s, town, main, g (the garrison, marched out), before (cell -> house before),
## crown (a second crown unit, at the depot)}.
func _occupied() -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.open_country(repo)
	var main := Play.host(repo, "main")
	var dep := TownStores.depot(repo, s)
	var town := ""
	var g := ""
	for c: String in Play.land_regiments(repo):
		var t := ArmyGround.seated_in(repo, s, c)
		if t != "" and t != dep:
			town = t
			g = c
			break
	assert_ne(town, "", "a crown town with a garrison of its own")
	var at := Play.town_m(repo, town)
	var away := Play.town_m(repo, dep)
	for c: String in s.regiments.keys():
		if c != g:
			Play.place(repo, s, c, away, ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, g, at, ArmySystem.ORDER_GARRISON)
	for c: String in EnemyAi.regiments_of(s, main):
		Play.place(repo, s, c, at, ArmySystem.ORDER_GARRISON)
	var mind: Dictionary = s.ai_hosts[main]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	EnemyAi.ensure_deployments(repo, s)
	var before := {}
	for cell: int in SiegeSystem.taken_cells(repo, s, town):
		before[cell] = MapManors.owner_of(repo, s, cell)
	SiegeRecord.ensure_for(repo, s, main)["progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(mind["mode"]), "HOLD", "the host holds the town")
	Play.place(repo, s, g, away, ArmySystem.ORDER_STANDBY)   # the garrison that marched out, gone
	return {"s": s, "town": town, "main": main, "g": g, "before": before, "crown": _other_unit(s, [g])}


## A crown unit stationed at `town` under a crown record: the record's id.
func _crown_besieges(s: GameState, town: String, unit: String) -> String:
	Play.place(repo, s, unit, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	return SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), [unit], "task_test")


## --- the occupation ---------------------------------------------------------

func test_capture_writes_one_occupation() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var town: String = f.town
	var raider := repo.resolve_realm("raider_realm")
	var player := repo.resolve_realm("player_realm")
	assert_true(s.occupations.has(town), "the town is occupied")
	var occ: Dictionary = s.occupations[town]
	assert_eq(String(occ["occupier"]), raider)
	assert_eq(String(occ["from"]), player)
	assert_eq(String(occ["host"]), f.main)
	assert_eq(String(occ["by"]), SiegeSystem.host_label(repo, f.main))
	var cells: Dictionary = occ["cells"]
	assert_eq(cells.size(), (f.before as Dictionary).size(), "every taken manor kept")
	for cell: int in f.before:
		assert_eq(String(cells.get(str(cell), "")), String(f.before[cell]), "manor %d's house before" % cell)
		assert_eq(_last_reason(s, cell), "taken by %s: siege of %s" % [SiegeSystem.host_label(repo, f.main),
			_label(town)], "the occupation's reason")
	assert_eq(SiegeSystem.holder_of(repo, s, town), raider, "held by its occupier")
	assert_true(ArmyGround.holds(repo, s, raider, town), "the occupier holds it")
	assert_false(ArmyGround.holds(repo, s, player, town), "the crown does not")
	assert_false((s.ai_hosts[f.main] as Dictionary).has("occupied"), "nothing on the mind")


func test_old_mind_occupation_migrates_once() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var town: String = f.town
	var occ: Dictionary = (s.occupations[town] as Dictionary).duplicate(true)
	var mind: Dictionary = s.ai_hosts[f.main]
	mind["occupied"] = (occ["cells"] as Dictionary).duplicate()
	mind["occupied_house"] = occ["house"]
	s.occupations.clear()
	SiegeRecord.migrate(repo, s)
	assert_eq(s.occupations, {town: occ}, "the mind's occupation, as capture writes it")
	assert_false(mind.has("occupied") or mind.has("occupied_house"), "the old keys go")
	assert_true(s.military_migration.has("occupation"), "logged")
	SiegeRecord.migrate(repo, s)
	assert_eq(s.occupations, {town: occ}, "a second run changes nothing")


func test_reserve_leaving_does_not_free_the_town() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var reserve := Play.host(repo, "reserve")
	var mind: Dictionary = s.ai_hosts[reserve]
	mind["mode"] = "HOLD"
	mind["target_kind"] = "town"
	mind["target_id"] = f.town
	EnemyAi.set_mode(s, reserve, "WITHDRAW", "test: the reserve goes home", [])
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_true(s.occupations.has(f.town), "the main host still occupies it")
	assert_eq(_of(ev, "siege_liberated").size(), 0, "nothing freed")


## --- the crown besieger's day -----------------------------------------------

func test_crown_record_day_gain_is_the_shared_formula() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var town: String = f.town
	var unit: String = f.crown
	var id := _crown_besieges(s, town, unit)
	var rec: Dictionary = s.sieges[id]
	assert_eq(String(rec["attacker"]), repo.resolve_realm("player_realm"))
	assert_eq(String(rec["defender"]), repo.resolve_realm("raider_realm"), "the occupier defends")
	assert_eq(rec["units"], [unit])
	assert_eq(rec["hosts"], [])
	assert_eq(SiegeSystem.stationed(repo, s, id), [unit], "the crown's unit stands at the town")
	var foes := SiegeSystem.defenders_of(repo, s, town)
	assert_eq(foes, EnemyAi.live_regiments(repo, s, f.main), "the occupying host's columns defend it")
	var a := ArmySystem.power(repo, s, unit, "attack")
	var d := 0
	for c: String in foes:
		d += ArmySystem.power(repo, s, c, "defend")
	assert_gt(a, 0)
	assert_gt(d, 0)
	@warning_ignore("integer_division")
	var gain := 100 * a / (a + d)   # siege_rate 100 (battle/balance.csv) x A / (A + D)
	assert_eq(int(repo.bal("siege_rate")), 100)
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_ours_begin").size(), 1, "begun")
	var days := _of(ev, "siege_ours_day")
	assert_eq(days.size(), 1)
	if days.size() == 1:
		assert_eq(int(days[0]["attack"]), a)
		assert_eq(int(days[0]["defend"]), d)
		assert_eq(int(days[0]["gain"]), gain)
	assert_eq(int(rec["progress"]), gain)
	assert_eq(int(rec["days"]), 1)
	assert_eq(SiegeSystem.news(ev).filter(func(e: Dictionary) -> bool:
		return String(e["kind"]).begins_with("siege_ours_")), [], "no letter of the crown's own yet")


func test_crown_record_has_no_assault_timer() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var id := _crown_besieges(s, f.town, f.crown)
	var rec: Dictionary = s.sieges[id]
	rec["days"] = int(repo.bal("siege_assault_days")) - 1
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(rec["days"]), int(repo.bal("siege_assault_days")))
	assert_eq(int(rec["assault_due"]), 0, "no assault without an order")
	assert_eq(int(rec["assault"]), 0)


## --- the fall, both ways ----------------------------------------------------

func test_foe_held_town_is_retaken_through_the_shared_path() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var town: String = f.town
	var id := _crown_besieges(s, town, f.crown)
	s.sieges[id]["progress"] = 1000
	var ev := SiegeSystem.settle_day(repo, s, [])
	var back := "liberated: %s's royal army retook %s from %s" % [repo.realm_label("player_realm"), _label(town),
		SiegeSystem.host_label(repo, f.main)]
	for cell: int in f.before:
		assert_eq(MapManors.owner_of(repo, s, cell), String(f.before[cell]), "manor %d back to its house" % cell)
		assert_eq(_last_reason(s, cell), back, "the liberation's reason")
	assert_false(s.occupations.has(town), "no longer occupied")
	assert_eq(SiegeRecord.of_town(s, town), "", "the siege is over")
	assert_true(EnemyAi.target_held(repo, s, "town", town), "the crown's again")
	assert_eq(String(s.ai_hosts[f.main]["mode"]), "RETREAT", "the occupier goes home")
	assert_eq(ev.filter(func(e: Dictionary) -> bool:
		return String(e.get("type", "")) == "host_mode" and String(e["host"]) == f.main \
			and String(e["mode"]) == "RETREAT" and String(e["why"]) == "the town was taken back").size(), 1)
	var taken := _of(ev, "siege_ours_taken")
	assert_eq(taken.size(), 1, "taken")
	if taken.size() == 1:
		assert_eq(String(taken[0]["reason"]), back)
		assert_eq(int(taken[0]["garrison_out"]), EnemyAi.live_regiments(repo, s, f.main).size())
	assert_eq(ev.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")).begins_with("defeat_")), [],
		"the crown lost nothing")
	assert_eq(s.town_takes, [], "a retake is no capture: it pays nothing (step 3b)")
	if taken.size() == 1:
		assert_eq(taken[0].get("opinion", []), [], "no seat moves for a retake")
	assert_eq(s.battles.filter(func(b: Dictionary) -> bool: return String(b["town"]) == town), [])


func test_crown_occupation_and_liberation_reasons() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.open_country(repo)
	var raider := repo.resolve_realm("raider_realm")
	var player := repo.resolve_realm("player_realm")
	var town := ""
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for t: String in codes:
		if SiegeSystem.holder_of(repo, s, t) == raider and SiegeSystem.defenders_of(repo, s, t).is_empty() \
				and not SiegeSystem.taken_cells(repo, s, t).is_empty():
			town = t
			break
	assert_ne(town, "", "an undefended town of the raider realm")
	var unit := _other_unit(s, [])
	var away := Play.town_m(repo, TownStores.depot(repo, s))
	for c: String in s.regiments.keys():
		if c != unit:
			Play.place(repo, s, c, away, ArmySystem.ORDER_STANDBY)
	var before := {}
	for cell: int in SiegeSystem.taken_cells(repo, s, town):
		before[cell] = MapManors.owner_of(repo, s, cell)
	_crown_besieges(s, town, unit)
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_ours_taken").size(), 1, "an undefended town falls to a unit at its gate")
	var taken := "taken by %s's royal army: siege of %s" % [repo.realm_label("player_realm"), _label(town)]
	for cell: int in before:
		assert_eq(MapManors.owner_of(repo, s, cell), MapManors.crown(s), "manor %d to the crown's house" % cell)
		assert_eq(_last_reason(s, cell), taken)
	assert_eq(SiegeSystem.holder_of(repo, s, town), player, "the crown occupies it")
	assert_eq(String(s.occupations[town]["from"]), raider)
	assert_eq(String(s.occupations[town]["host"]), "")
	assert_eq(MapOwnership.owner_of(repo, s, String(repo.burgs[town]["province_code"])), raider, "no province moves")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_ours_liberated").size(), 0, "a quiet day held")
	Play.place(repo, s, unit, away, ArmySystem.ORDER_STANDBY)
	ev = SiegeSystem.settle_day(repo, s, [])
	var freed := "liberated: %s's royal army left %s" % [repo.realm_label("player_realm"), _label(town)]
	for cell: int in before:
		assert_eq(MapManors.owner_of(repo, s, cell), String(before[cell]), "manor %d back" % cell)
		assert_eq(_last_reason(s, cell), freed)
	assert_eq(_of(ev, "siege_ours_liberated").size(), 1, "told once")
	assert_false(s.occupations.has(town))
	assert_eq(SiegeSystem.holder_of(repo, s, town), raider)


## --- contact: the mirror ----------------------------------------------------

func test_crown_besieger_does_not_fight_the_defenders_before_the_assault() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var town: String = f.town
	_crown_besieges(s, town, f.crown)
	BattleSystem.detect_contacts(repo, s)
	assert_eq(s.battles, [], "the besiegers wait for the order to storm")
	var relief := _other_unit(s, [f.g, f.crown])
	Play.place(repo, s, relief, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	BattleSystem.detect_contacts(repo, s)
	assert_eq(s.battles.size(), 1, "a unit outside the record fights them")
	if s.battles.size() == 1:
		var b: Dictionary = s.battles[0]
		assert_eq(String(b["town"]), "", "in the field")
		assert_false(f.crown in (b["att"] as Array) or f.crown in (b["def"] as Array), "the besieger stays out")


func test_raised_flag_gives_the_town_battle_with_the_crown_attacking() -> void:
	var f := _occupied()
	var s: GameState = f.s
	var town: String = f.town
	var id := _crown_besieges(s, town, f.crown)
	s.sieges[id]["assault_due"] = 1
	s.sieges[id]["assault"] = 1
	BattleSystem.detect_contacts(repo, s)
	assert_eq(s.battles.size(), 1, "one battle a town")
	if s.battles.size() == 1:
		var b: Dictionary = s.battles[0]
		assert_eq(String(b["town"]), town, "the town battle")
		assert_eq(b["att"], [f.crown], "the crown storms")
		assert_false((b["def"] as Array).is_empty())
		for c: String in b["def"]:
			assert_true(c in SiegeSystem.defenders_of(repo, s, town), c + " holds the works")
		assert_eq(String((b["actions"] as Dictionary)["att"]["kind"]), "attack", "the ordered assault")
