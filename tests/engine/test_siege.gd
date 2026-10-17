extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
const Play := preload("res://tests/invasion_play.gd")
## The siege (spec 2026-10-07-enemy-ai-and-battle-design §5.1-5.2): a host in
## SIEGE wears a garrisoned town down a day at a time (SiegeSystem.step),
## storms it every siege_assault_days through an ordinary town battle, starves
## it faster once its stores are spent, takes it at 1000 (or with its garrison
## gone to the last man) — the province and the town's manor change hands with
## a reason, the host HOLDs it — and lifts the siege when beaten, hungry, or
## when the town is no longer the crown's. A relief force in the open fights
## the besiegers; the garrison waits for the assault. Sieges are placed by hand
## for the rules and played on the real day loop for the whole of it.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

## The player's land units, in code order.
func _mine() -> Array:
	return Play.land_regiments(repo)


func _host(role: String) -> String:
	return Play.host(repo, role)


func _town_m(town: String) -> Vector2i:
	return Play.town_m(repo, town)


func _place(s: GameState, code: String, at: Vector2i, order: String) -> void:
	Play.place(repo, s, code, at, order)


## A town the campaign opens with one of the player's units on its seat that
## is not the depot (so a dry garrison could be fed from elsewhere): [town, unit].
func _town_and_garrison(s: GameState) -> Array:
	var dep := TownStores.depot(repo, s)
	for c: String in _mine():
		var t := ArmyGround.seated_in(repo, s, c)
		if t != "" and t != dep:
			return [t, c]
	return ["", ""]


## A siege by hand on the campaign `s`: the town's garrison is `garrison`
## (every other regiment of the player's sent off its quarters), `host`'s
## columns stand at the town's point, its mind SIEGE on the town. Returns the town.
func _besiege(s: GameState, host: String, garrison: Array) -> String:
	var town := String(_town_and_garrison(s)[0])
	assert_ne(town, "", "the pack quarters a regiment in a town of its own")
	var at := _town_m(town)
	# every other regiment stands at the depot, out of the siege's way
	var away := _town_m(TownStores.depot(repo, s))
	for c: String in s.regiments.keys():
		if not c in garrison:
			_place(s, c, away, ArmySystem.ORDER_STANDBY)
	for c: String in garrison:
		_place(s, c, at, ArmySystem.ORDER_GARRISON)
	for c: String in EnemyAi.regiments_of(s, host):
		_place(s, c, at, ArmySystem.ORDER_GARRISON)
	var mind: Dictionary = s.ai_hosts[host]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	assert_eq(EnemyAi.garrison_of(repo, s, town), garrison, "the garrison is the test's")
	return town


## A campaign with the town's stores full (no hunger in the town).
func _stocked(s: GameState, town: String) -> void:
	TownStores.add(s, town, "crown", 100000)
	TownStores.sync_metrics(repo, s)


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == kind)


## The host_mode events (EnemyAi.set_mode's) among `events` turning `host` to `mode`.
func _modes(events: Array, host: String, mode: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return String(e.get("type", "")) == "host_mode" and String(e["host"]) == host and String(e["mode"]) == mode)


## The pack's outcome row `tier` as the ONLY row, for every eff: a played
## assault's every round is that tier.
func _only_tier(tier: String) -> void:
	var row: Dictionary = {}
	for r: Dictionary in repo.battle_outcomes:
		if String(r["tier"]) == tier:
			row = r.duplicate()
	assert_false(row.is_empty(), "the pack has a tier " + tier)
	row["eff_min"] = 0
	row["eff_max"] = 1000
	repo.battle_outcomes.clear()
	repo.battle_outcomes.append(row)


## Plays an assault's day on the hand-made siege: the flag up, the day's
## battles, then the siege's day on their REAL events. The garrison holds
## (stance hold: it never leaves on the odds). Returns [battle events, siege events].
func _storm(s: GameState, main: String, g: String) -> Array:
	s.regiments[g]["stance"] = "hold"
	s.ai_hosts[main]["assault"] = 1
	var fight := BattleSystem.settle_day(repo, s)
	return [fight, SiegeSystem.settle_day(repo, s, fight)]


## The manors a capture of `town` takes: its own, and its province's within
## siege_capture_radius_km of the town's point, in cell order.
func _taken_cells(s: GameState, town: String) -> Array:
	var at := _town_m(town)
	var prov := String(repo.burgs[town]["province_code"])
	var r := int(round(repo.bal("siege_capture_radius_km") * 1000.0))
	var own := EnemyAi.target_cell(repo, s, "town", town)
	var out: Array = []
	for c: int in MapManors.manors_of_province(repo, prov, s):
		var m := ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, repo.cells[c]))
		var dx := m.x - at.x
		var dy := m.y - at.y
		if c == own or dx * dx + dy * dy <= r * r:
			out.append(c)
	out.sort()
	return out


## --- the day's wearing down (§5.1) -------------------------------------------

func test_siege_step() -> void:
	# 100 x 3000 / (3000 + 1000) = 75
	assert_eq(SiegeSystem.step(3000, 1000, 100), 75)
	assert_eq(SiegeSystem.step(0, 0, 100), 0, "no power on either side: nothing")
	# 40 x 1000 / 1000 = 40: an undefended wall gives the whole rate
	assert_eq(SiegeSystem.step(1000, 0, 40), 40)
	# 100 x 1 / 3 = 33.3 -> 33, rounded down
	assert_eq(SiegeSystem.step(1000, 2000, 100), 33)


func test_day_gain_with_hunger() -> void:
	# fed: the step; starving: the step + step x 500 / 1000 = 75 + 37
	assert_eq(SiegeSystem.day_gain(3000, 1000, 100, false, 500), 75)
	assert_eq(SiegeSystem.day_gain(3000, 1000, 100, true, 500), 112)
	assert_eq(SiegeSystem.day_gain(0, 0, 100, true, 500), 0)


func test_progress_accumulates_daily() -> void:
	repo.balance["siege_rate"] = 100.0
	repo.balance["siege_assault_days"] = 99.0
	var s := SuiteData.campaign(repo, 7)
	var main := _host("main")
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	var att := SiegeSystem.attack_power(repo, s, town)
	var def := SiegeSystem.defend_power(repo, s, town)
	var expect := 0
	for c: String in EnemyAi.live_regiments(repo, s, main):
		expect += ArmySystem.power(repo, s, c, "attack")
	assert_eq(att, expect, "the besiegers' power: their columns' attack")
	assert_eq(def, ArmySystem.power(repo, s, g, "defend"), "the garrison's: its defence, the town's works in it")
	assert_gt(att, 0)
	assert_gt(def, 0)
	var gain := SiegeSystem.step(att, def, 100)
	assert_gt(gain, 0)
	gut.p("attack %d, defence %d: %d a day" % [att, def, gain])
	var first := SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), gain, "the first day")
	assert_eq(_of(first, "siege_begin").size(), 1, "the siege begins, once")
	var day: Dictionary = _of(first, "siege_day")[0]
	assert_eq([int(day["attack"]), int(day["defend"]), int(day["gain"]), bool(day["starving"])],
		[att, def, gain, false], "the day's figures ride in its event")
	SiegeSystem.settle_day(repo, s, [])
	var third := SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 3 * gain, "a day's gain each day")
	assert_eq(int(s.ai_hosts[main]["siege_days"]), 3)
	assert_eq(_of(third, "siege_begin").size(), 0, "begun only once")
	assert_eq(s.territory_log.size(), 0, "nothing changes hands")


func test_starving_town_speeds_the_siege() -> void:
	repo.balance["siege_rate"] = 100.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.town_stock.erase(town)
	var carried := GameState.from_dict(s.to_dict())
	assert_gt(int(carried.regiments[g]["supplies"]), 0, "the garrison carries its own")
	assert_false(SiegeSystem.starving(repo, carried, town),
		"empty stores, but the garrison still eats what it carries: no hunger yet")
	s.regiments[g]["supplies"] = 0
	var fed := GameState.from_dict(s.to_dict())
	_stocked(fed, town)
	assert_true(SiegeSystem.starving(repo, s, town), "stores spent AND the garrison's own: the town starves")
	assert_false(SiegeSystem.starving(repo, fed, town), "a stocked town does not")
	var gain := SiegeSystem.step(SiegeSystem.attack_power(repo, s, town), SiegeSystem.defend_power(repo, s, town), 100)
	var ev := SiegeSystem.settle_day(repo, s, [])
	SiegeSystem.settle_day(repo, fed, [])
	@warning_ignore("integer_division")
	var hungry := gain + gain * int(repo.bal("siege_starve_bonus_permille")) / 1000
	assert_eq(int(fed.ai_hosts[main]["siege_progress"]), gain, "fed: the step")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), hungry, "starving: the step and the bonus")
	assert_gt(hungry, gain)
	assert_eq(_of(ev, "siege_starving").size(), 1, "the town's hunger is news")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_starving").size(), 0, "once")


func test_a_besieged_garrison_is_fed_only_by_its_town() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.town_stock.erase(town)
	s.regiments[g]["supplies"] = 0
	var free := GameState.from_dict(s.to_dict())
	free.ai_hosts[main]["mode"] = "ADVANCE"
	assert_true(SiegeSystem.besieged(s, town))
	assert_false(SiegeSystem.besieged(free, town))
	SupplyLines.day_step(repo, free)
	SupplyLines.day_step(repo, s)
	assert_gt(int(free.regiments[g]["supplies"]), 0, "unbesieged, the depot feeds a dry town's garrison")
	assert_eq(int(s.regiments[g]["supplies"]), 0, "besieged, nothing comes in from outside")


## --- the assault (Ruling 3: the ordinary town battle) -------------------------

func test_assault_cadence() -> void:
	repo.balance["siege_assault_days"] = 3.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	for n in 2:
		assert_eq(BattleSystem.settle_day(repo, s), [], "no assault on day %d" % (n + 1))
		SiegeSystem.settle_day(repo, s, [])
		assert_eq(int(s.ai_hosts[main].get("assault", 0)), 0, "not armed after day %d" % (n + 1))
	assert_eq(BattleSystem.settle_day(repo, s), [], "nor on day 3: the siege's third day arms the next")
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.ai_hosts[main]["assault"]), 1, "armed after siege_assault_days days")
	var fight := BattleSystem.settle_day(repo, s)
	var starts := _of(fight, "start")
	assert_eq(starts.size(), 1, "the assault is a battle")
	if starts.is_empty():
		return
	assert_eq(String(starts[0]["town"]), town, "fought at the town")
	assert_true(g in (starts[0]["def"] as Array), "against its garrison")
	SiegeSystem.settle_day(repo, s, fight)
	var running := not BattleSystem.battle_of(s, g).is_empty()
	assert_eq(int(s.ai_hosts[main]["assault"]), 1 if running else 0,
		"the flag stands while the assault's battle lasts, and no longer")


func test_an_assault_with_no_battle_is_tried_again_and_never_sticks() -> void:
	repo.balance["siege_assault_days"] = 1.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.ai_hosts[main]["assault"]), 1, "armed")
	# a draw's pause: the garrison makes no contact for two days
	s.regiments[g]["disengaged_until"] = s.absolute_day() + 2
	assert_eq(BattleSystem.settle_day(repo, s), [], "no battle while it draws breath")
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.ai_hosts[main]["assault_due"]), 1, "the assault is still owed")
	for n in 2:
		s.day += 1
		assert_eq(BattleSystem.settle_day(repo, s), [], "day %d of the pause: still none" % (n + 1))
	s.day += 1
	var fight := BattleSystem.settle_day(repo, s)
	assert_eq(_of(fight, "start").size(), 1, "tried again once the pause is over")
	# the siege ends: no flag outlives it
	EnemyAi.set_mode(s, main, "RETREAT", "test: gone home", [])
	SiegeSystem.settle_day(repo, s, fight)
	assert_eq(int(s.ai_hosts[main].get("assault", 0)), 0, "no flag on a host that left")
	assert_eq(int(s.ai_hosts[main].get("assault_due", 0)), 0)


## A checked assault (data/battle/battle_outcomes.csv `siege` repulsed: the pack's
## attacker_checked) costs the besieger siege_assault_fail_permille — read
## from the REAL round the day's battle fought.
func test_checked_assault_lowers_progress() -> void:
	repo.balance["siege_rate"] = 100.0
	_only_tier("attacker_checked")
	assert_eq(String(repo.battle_outcomes[0].get("siege", "")), "repulsed", "the tier's siege effect is data")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	s.ai_hosts[main]["siege_progress"] = 500
	var fail := int(repo.bal("siege_assault_fail_permille"))
	assert_gt(fail, 0, "a failed assault costs the besieger")
	var r := _storm(s, main, g)
	var rounds := _of(r[0], "round")
	assert_eq(rounds.size(), 1, "the assault fought a round today")
	assert_eq(String(rounds[0]["tier"]), "attacker_checked")
	assert_eq(_of(r[0], "end").size(), 0, "and goes on: no end event to read")
	# the round's gain is taken on the powers AFTER the round's losses
	var gain := SiegeSystem.step(SiegeSystem.attack_power(repo, s, town), SiegeSystem.defend_power(repo, s, town), 100)
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 500 - fail + gain, "500 - fail, then the day's gain")
	var rep := _of(r[1], "siege_repulsed")
	assert_eq(rep.size(), 1, "the check is news")
	if not rep.is_empty():
		assert_eq(int(rep[0]["lost"]), fail)
	# a check never takes the progress below 0
	s.ai_hosts[main]["siege_progress"] = 10
	var r2 := _storm(s, main, g)
	gain = SiegeSystem.step(SiegeSystem.attack_power(repo, s, town), SiegeSystem.defend_power(repo, s, town), 100)
	assert_eq(_of(r2[0], "round").size(), 1)
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), gain, "held at 0, then the day's gain")


func test_a_standoff_assault_changes_nothing() -> void:
	repo.balance["siege_rate"] = 100.0
	_only_tier("stalemate")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	s.ai_hosts[main]["siege_progress"] = 500
	var r := _storm(s, main, g)
	assert_eq(_of(r[0], "round").size(), 1)
	var gain := SiegeSystem.step(SiegeSystem.attack_power(repo, s, town), SiegeSystem.defend_power(repo, s, town), 100)
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 500 + gain, "a standoff: the day's gain alone")
	assert_eq(_of(r[1], "siege_repulsed").size(), 0)


func test_routed_defender_adds_the_rest() -> void:
	_only_tier("defender_routed")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	_besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 120
	var r := _storm(s, main, g)
	assert_eq(String((_of(r[0], "round")[0] as Dictionary)["tier"]), "defender_routed")
	assert_eq(_of(r[1], "siege_fallen").size(), 1, "the garrison broken: the town falls that day")
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")


func test_routed_besiegers_go_home() -> void:
	_only_tier("attacker_routed")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 400
	var r := _storm(s, main, g)
	assert_eq(String((_of(r[0], "round")[0] as Dictionary)["tier"]), "attacker_routed")
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "routed: the host turns home")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0)
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_lifted").size(), 1)
	assert_true(EnemyAi.target_held(repo, s, "town", town), "the town is the crown's")


## --- the fall (§5.2: manor-level) -----------------------------------------------

func test_capture_at_1000_takes_the_towns_manors_with_a_reason() -> void:
	repo.balance["siege_rate"] = 100.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	var prov := String(repo.burgs[town]["province_code"])
	var player := repo.resolve_realm("player_realm")
	var cells := _taken_cells(s, town)
	assert_gt(cells.size(), 0, "the town has a manor")
	var before := {}
	for c: int in cells:
		before[c] = MapManors.owner_of(repo, s, c)
	s.ai_hosts[main]["siege_progress"] = 999
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(MapOwnership.owner_of(repo, s, prov), player, "no province moves")
	assert_eq(s.territory_log.size(), 0, "no border moves")
	var town_label := String(repo.burgs[town]["label"])
	var house := MapManors.owner_of(repo, s, EnemyAi.target_cell(repo, s, "town", town))
	assert_ne(house, String(before[cells[0]]), "the town's manor has a new house")
	for c: int in cells:
		assert_eq(MapManors.owner_of(repo, s, c), house, "manor %d to the raider's house" % c)
		var moved: Array = s.manor_log.filter(func(m: Dictionary) -> bool: return int(m["cell"]) == c)
		assert_eq(moved.size(), 1, "manor %d moved once" % c)
		if moved.size() == 1:
			assert_true(String(moved[0]["reason"]).begins_with("taken by "), String(moved[0]["reason"]))
			assert_true(String(moved[0]["reason"]).contains("siege of " + town_label), String(moved[0]["reason"]))
	assert_eq(s.manor_log.size(), cells.size(), "only the town's manors")
	assert_false(EnemyAi.target_held(repo, s, "town", town), "an occupied town is no target of the crown's")
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "the host holds the town")
	assert_eq(_modes(ev, main, "HOLD").size(), 1, "told as a host_mode, with its why")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0, "the siege is over")
	assert_eq(_of(ev, "siege_fallen").size(), 1, "the fall is news")
	assert_eq(String(s.regiments[g]["order"]), ArmySystem.ORDER_MARCH, "the garrison marches out")
	assert_eq(int(s.regiments[g].get("disengaging", 0)), 1, "unmolested on its way")


func test_hold_host_leaving_liberates_the_manors() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var cells := _taken_cells(s, town)
	var before := {}
	for c: int in cells:
		before[c] = MapManors.owner_of(repo, s, c)
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	# beaten in the town: a column falls back
	s.foes[EnemyAi.regiments_of(s, main)[0]]["disengaging"] = 1
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "beaten: home")
	var ev := SiegeSystem.settle_day(repo, s, [])
	for c: int in cells:
		assert_eq(MapManors.owner_of(repo, s, c), before[c], "manor %d back to its house" % c)
		var mlog: Array = s.manor_log.filter(func(m: Dictionary) -> bool: return int(m["cell"]) == c)
		assert_eq(mlog.size(), 2, "taken and given back")
		if mlog.size() == 2:
			assert_true(String(mlog[1]["reason"]).begins_with("liberated"), String(mlog[1]["reason"]))
	assert_true(EnemyAi.target_held(repo, s, "town", town), "the town is the crown's again")
	assert_eq(_of(ev, "siege_liberated").size(), 1, "told")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_liberated").size(), 0, "once")


## A manor of the town that had already left its province's house (the crown
## bought it) goes back to THAT holder when the town is freed, not to the
## province's default house.
func test_liberation_restores_a_non_default_prior_holder() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var cell: int = _taken_cells(s, town)[0]
	var default := MapManors.default_owner(repo, s, cell)
	var buyer := MapManors.crown(s)
	if buyer == default:
		for p: String in MapOwnership.provinces_of(repo, s, repo.resolve_realm("player_realm")):
			if MapObjects.house_name_of(repo, p) != default:
				buyer = MapObjects.house_name_of(repo, p)
				break
	assert_ne(buyer, default, "a holder other than the province's own")
	assert_true(MapManors.set_owner(repo, s, cell, buyer, "bought before the war"), "the manor changed hands")
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	assert_ne(MapManors.owner_of(repo, s, cell), buyer, "taken")
	assert_eq(String((s.ai_hosts[main]["occupied"] as Dictionary).get(str(cell), "")), buyer, "its holder kept")
	s.foes[EnemyAi.regiments_of(s, main)[0]]["disengaging"] = 1
	EnemyAi.step_day(repo, s)
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(MapManors.owner_of(repo, s, cell), buyer, "back to the house that held it, not " + default)
	var mlog: Array = s.manor_log.filter(func(m: Dictionary) -> bool: return int(m["cell"]) == cell)
	assert_eq(mlog.size(), 3, "bought, taken, liberated")
	if mlog.size() == 3:
		assert_eq(String(mlog[0]["to"]), buyer)
		assert_true(String(mlog[1]["reason"]).begins_with("taken by "), String(mlog[1]["reason"]))
		assert_eq(String(mlog[2]["from"]), String(mlog[1]["to"]), "from the raider's house")
		assert_eq(String(mlog[2]["to"]), buyer, "to the buyer")
		assert_true(String(mlog[2]["reason"]).begins_with("liberated"), String(mlog[2]["reason"]))


## An occupation saved to disk and loaded plays on exactly as the one that
## never stopped: the occupied manors and their holders before survive the
## save, and the host's leaving frees them the same.
func test_save_and_load_mid_occupation_continues_identically() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var before := {}
	for c: int in _taken_cells(s, town):
		before[c] = MapManors.owner_of(repo, s, c)
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "occupied")
	var path := RunDir.dir("siege").path_join("mid_occupation.json")
	assert_true(SaveLoad.save_game(s, path), "saved")
	var c := SaveLoad.load_game(path)
	assert_eq(SaveLoad.state_hash(c), SaveLoad.state_hash(s), "the same state loaded")
	assert_eq(c.ai_hosts[main]["occupied"], s.ai_hosts[main]["occupied"], "the holders before, kept")
	for st: GameState in [s, c]:
		SiegeSystem.settle_day(repo, st, [])  # a day held
		st.foes[EnemyAi.regiments_of(st, main)[0]]["disengaging"] = 1
		EnemyAi.step_day(repo, st)
		SiegeSystem.settle_day(repo, st, [])
	assert_eq(String(c.ai_hosts[main]["mode"]), "RETREAT")
	for cell: int in before:
		assert_eq(MapManors.owner_of(repo, c, cell), before[cell], "manor %d freed after the load" % cell)
	assert_eq(SaveLoad.state_hash(c), SaveLoad.state_hash(s), "and the same state after")


## The shipped data/battle/battle_outcomes.csv (the file, not the loaded table) maps
## SiegeSystem's two assault tiers: `breach` on defender_routed, `repulsed` on
## attacker_checked, and no other row moves a siege.
func test_shipped_outcomes_map_breach_and_repulsed() -> void:
	var f := FileAccess.open("res://data/battle/battle_outcomes.csv", FileAccess.READ)
	assert_not_null(f, "the shipped table")
	if f == null:
		return
	var head := f.get_csv_line()
	var tier_at := head.find("tier")
	var siege_at := head.find("siege")
	assert_true(tier_at >= 0 and siege_at >= 0, "tier and siege columns")
	var by_siege := {}
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= siege_at or row[tier_at] == "":
			continue
		if row[siege_at] != "":
			by_siege[row[siege_at]] = row[tier_at]
	assert_eq(SiegeSystem.TIER_BREACH, "breach")
	assert_eq(SiegeSystem.TIER_REPULSED, "repulsed")
	assert_eq(by_siege, {"breach": "defender_routed", "repulsed": "attacker_checked"}, "the two siege rows")


func test_hold_host_with_no_column_left_frees_the_town() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	for c: String in EnemyAi.regiments_of(s, main):
		s.foes[c]["dead"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, c))
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "no column left to hold it")
	assert_eq(_modes(ev, main, "RETREAT").size(), 1)
	assert_true(EnemyAi.target_held(repo, s, "town", town), "liberated")


func test_garrison_slain_to_the_last_man_loses_the_town() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.regiments[g]["dead"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, g))
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_false(EnemyAi.target_held(repo, s, "town", town), "no fit man left: the town is taken")
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	var fallen := _of(ev, "siege_fallen")
	assert_eq(fallen.size(), 1)
	if fallen.is_empty():
		return
	assert_eq(int(fallen[0]["garrison_out"]), 0, "no one marched out")
	var text := " ".join((MissiveWriter.battle_report(repo, s, SiegeSystem.news(ev))["facts"] as Array).map(
		func(f: Dictionary) -> String: return String(f["text"])))
	assert_false(text.contains("marches out"), "no survivor marches out of a garrison slain: " + text)
	assert_false(text.contains("[missing template"), text)


func test_hold_host_stays_and_is_not_rethought() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	for c: String in EnemyAi.regiments_of(s, main):
		s.foes[c]["supplies"] = 0           # it lives off the town it took
	var before := {}
	for c: String in EnemyAi.regiments_of(s, main):
		before[c] = [int(s.foes[c]["x_m"]), int(s.foes[c]["y_m"]), String(s.foes[c]["order"])]
	s.ai_hosts[main]["think_day"] = -999
	EnemyAi.step_day(repo, s)
	EnemyAi.think_day(repo, s)
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "a host holding a town neither thinks nor starves home")
	assert_eq(String(s.ai_hosts[main]["target_id"]), town, "and keeps its town")
	for c: String in EnemyAi.regiments_of(s, main):
		assert_eq([int(s.foes[c]["x_m"]), int(s.foes[c]["y_m"]), String(s.foes[c]["order"])], before[c], c + " stays")


func test_other_hosts_skip_an_occupied_town() -> void:
	repo.balance["ai_target_reach_km"] = 1000.0
	var main := _host("main")
	var raiders := _host("raider")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	for c: String in EnemyAi.regiments_of(s, raiders):
		_place(s, c, _town_m(town) + Vector2i(1000, 0), ArmySystem.ORDER_GARRISON)
	s.ai_hosts[raiders]["mode"] = "ADVANCE"
	var ids := func() -> Array:
		return EnemyAi.candidates(repo, s, raiders).map(func(c: Dictionary) -> String: return String(c["id"]))
	assert_true(town in ids.call(), "the town is a candidate before it falls")
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_false(town in ids.call(), "an occupied town is no other host's target")
	for c: int in _taken_cells(s, town):
		assert_false(str(c) in ids.call(), "nor an occupied manor")


func test_no_double_capture_and_no_progress_after_loss() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	_besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	var manor_moves := s.manor_log.size()
	assert_gt(manor_moves, 0)
	assert_eq(SiegeSystem.capture(repo, s, main), {}, "a town taken is not taken twice")
	s.ai_hosts[main]["mode"] = "SIEGE"           # even a host put back to the siege
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(s.manor_log.size(), manor_moves, "no manor moves twice")
	# a town lost some other way mid-siege: no progress, no capture
	var s2 := SuiteData.campaign(repo, 7)
	var town2 := _besiege(s2, main, [String(_town_and_garrison(s2)[1])])
	s2.ai_hosts[main]["siege_progress"] = 300
	MapOwnership.set_owner(repo, s2, String(repo.burgs[town2]["province_code"]), repo.resolve_realm("raider_realm"),
		"test: lost elsewhere")
	var ev := SiegeSystem.settle_day(repo, s2, [])
	assert_eq(s2.manor_log.size(), 0, "nothing taken by the siege")
	assert_eq(_of(ev, "siege_day").size(), 0, "no day's progress")
	assert_eq(int(s2.ai_hosts[main]["siege_progress"]), 0)
	assert_eq(String(s2.ai_hosts[main]["mode"]), "WITHDRAW")
	assert_eq(_modes(ev, main, "WITHDRAW").size(), 1, "told as a host_mode")


func test_garrison_marched_off_ends_the_siege_without_progress() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 300
	s.regiments[g]["order"] = ArmySystem.ORDER_MARCH
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_day").size(), 0, "no progress on an empty town")
	assert_eq(s.manor_log.size(), 0, "and no capture: no siege took it")
	assert_eq(String(s.ai_hosts[main]["mode"]), "RAID", "an open town is raided, as on arrival")
	assert_eq(_modes(ev, main, "RAID").size(), 1, "told as a host_mode")
	assert_eq(String(s.ai_hosts[main]["target_id"]), town)
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0)
	assert_eq(_of(ev, "siege_undefended").size(), 1)


func test_retaken_town_sends_hold_host_retreating() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var cell := EnemyAi.target_cell(repo, s, "town", town)
	var was := MapManors.owner_of(repo, s, cell)
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_liberated").size(), 0, "a quiet day in the town")
	MapManors.set_owner(repo, s, cell, was, "test: retaken")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "the town's manor is its house's again: home")
	assert_eq(_of(ev, "siege_liberated").size(), 1)
	var home := EnemyAi.home_m(repo, main)
	for c: String in EnemyAi.live_regiments(repo, s, main):
		assert_eq(String(s.foes[c]["order"]), ArmySystem.ORDER_MARCH, c + " marches")
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), home, c + " for home")


func test_capture_mid_assault_ends_the_assault() -> void:
	_only_tier("stalemate")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.regiments[g]["stance"] = "hold"
	s.ai_hosts[main]["assault"] = 1
	var fight := BattleSystem.settle_day(repo, s)
	assert_eq(_of(fight, "round").size(), 1)
	assert_false(BattleSystem.battle_of(s, g).is_empty(), "the assault goes on")
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, fight)
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	for b: Dictionary in s.battles:
		assert_ne(String(b["town"]), town, "no assault goes on in a fallen town")
	assert_true(BattleSystem.battle_of(s, g).is_empty(), "the garrison is out of it")
	assert_eq(_of(BattleSystem.settle_day(repo, s), "round").size(), 0, "no further round")


## --- the besieger lifts the siege (§5.1 relief, §3.4) ---------------------------

func test_starving_besieger_retreats() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 400
	SiegeSystem.settle_day(repo, s, [])          # the siege is under way
	s.ai_hosts[main]["assault"] = 1              # and an assault armed
	for c: String in EnemyAi.regiments_of(s, main):
		s.foes[c]["supplies"] = 0
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "a hungry besieger goes home")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0, "its siege is over")
	assert_eq(int(s.ai_hosts[main].get("assault", 0)), 0, "no assault flag left")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_lifted").size(), 1, "the siege lifted is news")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_lifted").size(), 0, "once")
	assert_eq(MapOwnership.owner_of(repo, s, String(repo.burgs[town]["province_code"])),
		repo.resolve_realm("player_realm"))


func test_relief_force_joins_battle_and_can_lift_siege() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 400
	# a battered host: fifty fit men a column
	for c: String in EnemyAi.regiments_of(s, main):
		s.foes[c]["dead"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, c)) - 50
	# the relief: three km off the town's point, in the open (no garrison)
	var relief: Array = _mine().filter(func(c: String) -> bool: return c != g).slice(0, 3)
	var at := _town_m(town) + Vector2i(3000, 0)
	for c: String in relief:
		_place(s, c, at, ArmySystem.ORDER_STANDBY)
		assert_eq(ArmyGround.garrison_town(repo, s, c), "", c + " is no garrison")
	var ev := BattleSystem.settle_day(repo, s)
	var starts := _of(ev, "start")
	assert_eq(starts.size(), 1, "the relief meets the besiegers in the field")
	if starts.is_empty():
		return
	assert_eq(String(starts[0]["town"]), "", "a field battle, not the assault")
	for e: Dictionary in ev:
		for k: String in ["att", "def"]:
			assert_false(g in (e.get(k, []) as Array), "the garrison does not sortie")
		assert_ne(String(e.get("code", "")), g, "nor joins")
	var fell_back := false
	for c: String in EnemyAi.regiments_of(s, main):
		fell_back = fell_back or int(s.foes[c].get("disengaging", 0)) == 1
	assert_true(fell_back, "the battered besiegers are driven off")
	SiegeSystem.settle_day(repo, s, ev)
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "beaten: the host turns home")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0, "the siege is lifted")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, []), "siege_lifted").size(), 1)


func test_a_garrison_waits_for_the_assault() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	_besiege(s, main, [g])
	assert_eq(BattleSystem.settle_day(repo, s), [], "besiegers and garrison face each other, no battle")
	s.ai_hosts[main]["assault"] = 1
	assert_eq(_of(BattleSystem.settle_day(repo, s), "start").size(), 1, "the assault day's battle")


## A supply line into a besieged town is CUT (spec §5.1: the siege starves the
## town): the line's regiment garrisons the town, its line is flowing from the
## depot — the day's step delivers nothing, says `cut` by the besiegers'
## kingdom (the host named), and the line flows again once the siege is gone.
func test_a_supply_line_into_a_besieged_town_is_cut() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	assert_true(SiegeSystem.besieged(s, town), "besieged")
	var dep := TownStores.depot(repo, s)
	TownStores.add(s, dep, "crown", 100000)
	for k: String in ["crown", "lord", "house"]:
		TownStores.take(s, town, k, 1000000)   # the town itself has nothing left to give
	TownStores.sync_metrics(repo, s)
	s.supply_lines[g] = SupplyLines._new_record(dep, 1000, 1)
	s.supply_lines[g]["state"] = SupplyLines.FLOWING
	s.regiments[g]["supplies"] = 0
	var ev := SupplyLines.day_step(repo, s)
	var cut: Array = ev.filter(func(e: Dictionary) -> bool:
		return String(e["type"]) == "cut" and String(e["regiment"]) == g)
	assert_eq(cut.size(), 1, "the line is cut")
	if cut.size() == 1:
		var kingdom := String(ArmySystem.regiment(repo, EnemyAi.regiments_of(s, main)[0])["kingdom_code"])
		assert_eq(String(cut[0]["by"]), kingdom, "by the besiegers' kingdom")
		assert_eq(String(cut[0].get("host", "")), main, "the host that holds the road")
	assert_eq(String(s.supply_lines[g]["state"]), SupplyLines.CUT)
	assert_eq(int(s.regiments[g]["supplies"]), 0, "nothing came through")
	assert_eq(SupplyLines.day_step(repo, s).filter(func(e: Dictionary) -> bool:
		return String(e["type"]) == "cut").size(), 0, "said once")
	# the host goes home: the road is open again
	EnemyAi.set_mode(s, main, "RETREAT", "test", [])
	var after := SupplyLines.day_step(repo, s)
	assert_eq(after.filter(func(e: Dictionary) -> bool:
		return String(e["type"]) == "restored" and String(e["regiment"]) == g).size(), 1, "restored")
	assert_gt(int(s.regiments[g]["supplies"]), 0, "and it delivers")


## --- a host going home fights no more (RETREAT / WITHDRAW) ------------------------

## The "start" and "round" events among `events`.
func _fighting(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) in ["start", "round"])


## A host turned home before a garrisoned town, its columns standing in the
## town's reach and free to fight, starts no battle there, day after day.
func test_a_homeward_host_starts_no_battle_with_the_garrison() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	for mode: String in ["RETREAT", "WITHDRAW"]:
		EnemyAi.set_mode(s, main, mode, "test", [])
		for n in 3:
			s.day = 20 + n
			var fight := BattleSystem.settle_day(repo, s)
			assert_eq(_fighting(fight), [], "%s day %d: no battle at %s" % [mode, n, town])
			assert_eq(s.battles, [], "none kept")
		# a column of it that is no garrison's business: in the open, the same
		var mine := String(_mine()[0]) if String(_mine()[0]) != g else String(_mine()[1])
		_place(s, mine, _town_m(town) + Vector2i(500, 0), ArmySystem.ORDER_STANDBY)
		assert_eq(_fighting(BattleSystem.settle_day(repo, s)), [], mode + ": nor in the open")
		_place(s, mine, _town_m(TownStores.depot(repo, s)), ArmySystem.ORDER_STANDBY)


## An assault under way when its host turns home is called off THAT day,
## before its round: no more blows, the garrison's dead stay as they were,
## the battle ends with the crown's men holding the field and every survivor
## draws breath (battle_disengage_days); the siege is lifted.
func test_a_running_assault_is_called_off_the_day_its_host_turns_home() -> void:
	_only_tier("stalemate")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	_besiege(s, main, [g])
	s.ai_hosts[main]["siege_days"] = 3
	var first := _storm(s, main, g)
	assert_eq(_of(first[0], "round").size(), 1, "the assault fought its first round")
	assert_eq(s.battles.size(), 1, "and runs on")
	var dead := int(s.regiments[g].get("dead", 0))
	assert_gt(dead, 0, "the first round cost the garrison")
	# the besiegers' food runs out: the hosts' minds turn them home
	for c: String in EnemyAi.regiments_of(s, main):
		s.foes[c]["supplies"] = 0
	s.day = 21
	var ai := EnemyAi.step_day(repo, s)
	assert_eq(_modes(ai, main, "RETREAT").size(), 1, "hungry: home")
	var fight := BattleSystem.settle_day(repo, s)
	assert_eq(_of(fight, "round"), [], "no round the day it turns home")
	var ends := _of(fight, "end")
	assert_eq(ends.size(), 1, "the assault ends")
	if ends.size() == 1:
		assert_eq(String(ends[0]["why"]), "withdrawn", "the host withdrew from it")
		assert_eq(String(ends[0]["winner"]), "def", "the garrison holds the field")
		assert_eq(String(MissiveWriter._end_key(s, ends[0], {})), "battle_end_withdrawn",
			"told as the enemy drawing off, not a fought win")
		var words := MissiveWriter.battle_words(repo, "battle_end_withdrawn", {"place": "X", "rounds": 1}, 0)
		assert_false(words.contains("[missing") or words.contains("{"), words)
	assert_eq(s.battles, [], "no battle kept")
	assert_eq(int(s.regiments[g].get("dead", 0)), dead, "the garrison's casualties stop")
	var pause := s.absolute_day() + int(repo.bal("battle_disengage_days"))
	assert_eq(int(s.regiments[g].get("disengaged_until", 0)), pause, "the garrison draws breath")
	for c: String in EnemyAi.regiments_of(s, main):
		assert_eq(BattleSystem.battle_of(s, c), {}, c + " is out of it")
	assert_eq(_of(SiegeSystem.settle_day(repo, s, fight), "siege_lifted").size(), 1, "the siege is lifted")
	# and the next days: its columns march home, no battle
	for n in 3:
		s.day = 22 + n
		EnemyAi.step_day(repo, s)
		ArmySystem.march_day(repo, s)
		assert_eq(_fighting(BattleSystem.settle_day(repo, s)), [], "no battle on its way home, day %d" % n)
	assert_eq(int(s.regiments[g].get("dead", 0)), dead, "still no more dead")


## Regression: a host BEATEN in a battle still turns RETREAT the next day,
## pays its spoils on the day it is beaten (RaidSystem) and gives the town it
## held back (liberation, SiegeSystem).
func test_a_beaten_holding_host_still_pays_spoils_and_frees_the_town() -> void:
	repo.balance["battle_spoils_permille"] = 500.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 20
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var before := {}
	for c: int in _taken_cells(s, town):
		before[c] = MapManors.owner_of(repo, s, c)
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "the town taken")
	s.ai_hosts[main]["plunder"] = 600
	# a fresh regiment of the crown's stands at the town; the foes attack it
	# and the table routs them
	_only_tier("attacker_routed")
	var mine := String(_mine()[0]) if String(_mine()[0]) != g else String(_mine()[1])
	_place(s, mine, _town_m(town) + Vector2i(500, 0), ArmySystem.ORDER_STANDBY)
	s.day = 21
	var fight := BattleSystem.settle_day(repo, s)
	assert_gt(_of(fight, "round").size(), 0, "a battle")
	var strategic := float(s.metrics["strategic"])
	var raid := RaidSystem.settle_day(repo, s, fight)
	assert_eq(_of(raid, "raid_spoils").size(), 1, "the beaten host's spoils, the day it is beaten")
	assert_eq(float(s.metrics["strategic"]), strategic + 300.0, "600 x 500 / 1000")
	s.day = 22
	var ai := EnemyAi.step_day(repo, s)
	assert_eq(_modes(ai, main, "RETREAT").size(), 1, "beaten: home")
	var ev := SiegeSystem.settle_day(repo, s, BattleSystem.settle_day(repo, s))
	assert_eq(_of(ev, "siege_liberated").size(), 1, "the town freed")
	for c: int in before:
		assert_eq(MapManors.owner_of(repo, s, c), before[c], "manor %d back to its house" % c)


## --- the reserve and several hosts ----------------------------------------------

func _with_reserve(s: GameState) -> Array:
	var main := _host("main")
	var reserve := _host("reserve")
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	for c: String in EnemyAi.regiments_of(s, reserve):
		_place(s, c, _town_m(town), ArmySystem.ORDER_GARRISON)
	var m: Dictionary = s.ai_hosts[reserve]
	m["mode"] = "SIEGE"
	m["target_kind"] = "town"
	m["target_id"] = town
	return [main, reserve, town, g]


func test_one_siege_a_town_with_the_reserve_beside_its_main_host() -> void:
	repo.balance["siege_rate"] = 100.0
	var s := SuiteData.campaign(repo, 7)
	var r := _with_reserve(s)
	var main: String = r[0]
	var reserve: String = r[1]
	var town: String = r[2]
	_stocked(s, town)
	var att := 0
	for h: String in [main, reserve]:
		for c: String in EnemyAi.live_regiments(repo, s, h):
			att += ArmySystem.power(repo, s, c, "attack")
	assert_eq(SiegeSystem.attack_power(repo, s, town), att, "both hosts' columns press the town")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_day").size(), 1, "one siege, not two")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), SiegeSystem.step(att, SiegeSystem.defend_power(repo, s, town), 100),
		"kept on the main host")
	assert_eq(int(s.ai_hosts[reserve].get("siege_progress", 0)), 0, "the reserve keeps none of its own")
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	assert_eq(String(s.ai_hosts[reserve]["mode"]), "HOLD", "the reserve holds the town with it")
	assert_eq(s.manor_log.size(), _taken_cells(s, town).size(), "taken once")


## M3: a siege the reserve began alone is the main host's when it comes up —
## the progress follows the lead, none is left behind on the reserve.
func test_progress_follows_the_lead_host() -> void:
	repo.balance["siege_rate"] = 100.0
	var s := SuiteData.campaign(repo, 7)
	var r := _with_reserve(s)
	var main: String = r[0]
	var reserve: String = r[1]
	var town: String = r[2]
	_stocked(s, town)
	s.ai_hosts[main]["mode"] = "ADVANCE"         # the reserve sits alone
	SiegeSystem.settle_day(repo, s, [])
	SiegeSystem.settle_day(repo, s, [])
	var so_far := int(s.ai_hosts[reserve]["siege_progress"])
	assert_gt(so_far, 0, "the reserve keeps the siege while alone")
	assert_eq(int(s.ai_hosts[reserve]["siege_days"]), 2)
	s.ai_hosts[main]["mode"] = "SIEGE"           # the main host sits down beside it
	var gain := SiegeSystem.step(SiegeSystem.attack_power(repo, s, town), SiegeSystem.defend_power(repo, s, town), 100)
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), so_far + gain, "the progress moved to the main host")
	assert_eq(int(s.ai_hosts[main]["siege_days"]), 3, "and its days")
	assert_eq(int(s.ai_hosts[reserve]["siege_progress"]), 0, "none orphaned on the reserve")
	assert_eq(_of(ev, "siege_begin").size(), 0, "the same siege, not a new one")
	assert_eq(_of(ev, "siege_lifted").size(), 0)


func test_siege_reserve_follows_its_main_host_home() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _with_reserve(s)
	var main: String = r[0]
	var reserve: String = r[1]
	SiegeSystem.settle_day(repo, s, [])
	s.ai_hosts[main]["mode"] = "RETREAT"
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[reserve]["mode"]), "RETREAT", "the reserve goes home with its main host")
	var home := EnemyAi.home_m(repo, reserve)
	for c: String in EnemyAi.live_regiments(repo, s, reserve):
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), home, c + " marches home")
	var s2 := SuiteData.campaign(repo, 7)
	var r2 := _with_reserve(s2)
	s2.ai_hosts[String(r2[0])]["mode"] = "WITHDRAW"
	SiegeSystem.settle_day(repo, s2, [])
	assert_eq(String(s2.ai_hosts[String(r2[1])]["mode"]), "WITHDRAW", "and withdraws with it")


## --- the letter ------------------------------------------------------------------

func test_siege_news_is_a_battle_letter_in_fixed_words() -> void:
	_only_tier("attacker_checked")
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var ev := SiegeSystem.settle_day(repo, s, [])
	ev.append_array(_storm(s, main, g)[1])
	s.ai_hosts[main]["siege_progress"] = 1000
	ev.append_array(SiegeSystem.settle_day(repo, s, []))
	var news := SiegeSystem.news(ev)
	assert_eq(_of(news, "siege_day").size(), 0, "a day's wearing down is no news")
	for k: String in ["siege_begin", "siege_repulsed", "siege_fallen"]:
		assert_eq(_of(news, k).size(), 1, k + " is")
	var m := MissiveWriter.battle_report(repo, s, news)
	assert_eq(String(m["kind"]), "battle")
	assert_eq(String(m["column"]), "credible", "battle news stays credible (owner 2026-10-10)")
	var text := " ".join((m["facts"] as Array).map(func(f: Dictionary) -> String: return String(f["text"])))
	assert_eq((m["facts"] as Array).size(), news.size(), "a line an event")
	assert_false(text.contains("[missing template"), text)
	assert_false(text.contains("{"), "every slot filled: " + text)
	assert_true(text.contains(String(repo.burgs[town]["label"])), "names the town")
	assert_true(text.contains(repo.realm_label("raider_realm")), "the raider realm through its slot")
	var fallen: Dictionary = _of(news, "siege_fallen")[0]
	assert_true(text.contains(str(int(fallen["days"]))), "the figures are the events'")


func test_siege_templates_spell_no_kingdom() -> void:
	var raw := FileAccess.get_file_as_string("res://data/council/templates.csv")
	var found := 0
	for line: String in raw.split("\n"):
		if not line.begins_with("siege_"):
			continue
		found += 1
		assert_true(line.contains("{raider_realm}") or line.contains("{player_realm}"), "a realm by its slot: " + line)
		for k: Variant in repo.kingdoms:
			var label := String((repo.kingdoms[k] as Dictionary).get("label", ""))
			if label != "":
				assert_false(line.contains(label), "no kingdom spelled: " + line)
	assert_gte(found, 8, "begin, starving, repulsed, fallen, fallen_slain, lifted, undefended, liberated")


## --- the real day loop ---------------------------------------------------------

func _opened(engine: TickEngine) -> GameState:
	return Play.opened(repo, engine)


func _day(engine: TickEngine, s: GameState) -> void:
	Play.day(engine, s)


func _first_appear() -> int:
	return Play.first_appear(repo)


## The day loop to the main host's crossing, its target held from then on, the
## town garrisoned by the units of `n` of the player's pack regiments
## (`weakest`: the smallest first, else the largest first; Play.regiment_units),
## sent there as arrivals (Play.arrive: the seat, then the camp round it).
## [state, town, garrison].
func _invaded(engine: TickEngine, n: int, weakest: bool) -> Array:
	repo.balance["ai_think_days"] = 999.0
	var s := _opened(engine)
	while s.absolute_day() <= _first_appear():
		_day(engine, s)
	var mind: Dictionary = s.ai_hosts[_host("main")]
	assert_eq(String(mind["target_kind"]), "town", "the main host goes for a town")
	var town := String(mind["target_id"])
	var garrison: Array = Play.regiment_units(repo, weakest, n)
	for c: String in garrison:
		Play.arrive(repo, s, c, _town_m(town))
	return [s, town, garrison]


## Plays until the main host's siege ends or `days` have passed; returns
## {begun (absolute day), fell (day), lifted (day), events}.
func _siege_run(engine: TickEngine, s: GameState, days: int) -> Dictionary:
	var main := _host("main")
	var out := {"begun": -1, "fell": -1, "lifted": -1, "events": []}
	for n in days:
		var today := s.absolute_day()
		_day(engine, s)
		(out["events"] as Array).append_array(engine.day_siege)
		for e: Dictionary in engine.day_siege:
			var k := String(e.get("kind", ""))
			if k == "siege_begin" and int(out["begun"]) < 0:
				out["begun"] = today
			if k == "siege_fallen":
				out["fell"] = today
			if k == "siege_lifted":
				out["lifted"] = today
		if int(out["begun"]) > 0 and String(s.ai_hosts[main]["mode"]) != "SIEGE":
			break
	return out


func test_a_siege_on_the_day_loop_wears_down_storms_and_takes_the_town() -> void:
	var engine := TickEngine.new(repo)
	var r := _invaded(engine, 1, true)
	var s: GameState = r[0]
	var town: String = r[1]
	var run := _siege_run(engine, s, 25)
	var main := _host("main")
	assert_gt(int(run["begun"]), 0, "the host sat down before the town")
	# every day's gain is the hand formula on that day's figures, added up
	var progress := 0
	var rate := int(repo.bal("siege_rate"))
	var bonus := int(repo.bal("siege_starve_bonus_permille"))
	var days := 0
	for e: Dictionary in run["events"]:
		match String(e.get("kind", "")):
			"siege_repulsed":
				progress = maxi(0, progress - int(e["lost"]))
			"siege_day":
				days += 1
				assert_eq(int(e["gain"]), SiegeSystem.day_gain(int(e["attack"]), int(e["defend"]), rate,
					bool(e["starving"]), bonus), "the day's gain is the formula's")
				progress = mini(1000, progress + int(e["gain"]))
				assert_eq(int(e["progress"]), progress, "accumulated day by day")
	assert_gt(days, 0)
	assert_gt(int(run["fell"]), 0, "a weakly held town falls")
	var fell_after := int(run["fell"]) - int(run["begun"]) + 1
	assert_lte(fell_after, 10, "inside ten days of siege (fell on its day %d)" % fell_after)
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	assert_false(EnemyAi.target_held(repo, s, "town", town), "the town is occupied")
	var cell := EnemyAi.target_cell(repo, s, "town", town)
	var mlog: Array = s.manor_log.filter(func(l: Dictionary) -> bool: return int(l["cell"]) == cell)
	assert_eq(mlog.size(), 1, "its manor moved once, with its reason")
	if mlog.size() == 1:
		assert_true(String(mlog[0]["reason"]).contains("siege of"), String(mlog[0]["reason"]))
	assert_eq(s.territory_log.size(), 0, "no border moved")
	var letters: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "battle")
	var said := false
	for m: Dictionary in letters:
		for f: Dictionary in m["facts"]:
			said = said or String(f.get("key", "")).begins_with("siege_fallen")
	assert_true(said, "the fall is in a battle letter")
	gut.p("weak garrison: siege from day %d, fell day %d (%d days), assaults %d" % [int(run["begun"]),
		int(run["fell"]), fell_after, _of(run["events"], "siege_repulsed").size()])


func test_a_strongly_held_walled_town_outlasts_the_besiegers_supplies() -> void:
	var engine := TickEngine.new(repo)
	repo.balance["ai_think_days"] = 999.0
	# the main host's town, given walls and a citadel before the campaign starts
	var probe_engine := TickEngine.new(repo)
	var probe := _opened(probe_engine)
	while probe.absolute_day() <= _first_appear():
		_day(probe_engine, probe)
	var town := String(probe.ai_hosts[_host("main")]["target_id"])
	repo.burgs[town]["features"] = "walls|citadel"
	ArmySystem.forget_grids()
	var r := _invaded(engine, 3, false)
	var s: GameState = r[0]
	assert_eq(String(r[1]), town, "the same town")
	# as played: the town's own stores are empty (only the depot has stock)
	assert_eq(TownStores.stock_of(s, town), {"crown": 0, "lord": 0, "house": 0}, "the town holds no stores")
	var run := _siege_run(engine, s, 40)
	var main := _host("main")
	assert_gt(int(run["begun"]), 0, "the host sat down before the town")
	assert_eq(int(run["fell"]), -1, "the town does not fall")
	assert_gt(int(run["lifted"]), 0, "the siege is lifted")
	assert_true(String(s.ai_hosts[main]["mode"]) in ["RETREAT", "WITHDRAW"], "the host goes home")
	assert_true(EnemyAi.target_held(repo, s, "town", town), "the town is still the crown's")
	assert_eq(s.manor_log.size(), 0, "no manor taken")
	var best := 0
	var hungry := 0
	for e: Dictionary in run["events"]:
		if String(e.get("kind", "")) == "siege_day":
			best = maxi(best, int(e["progress"]))
			hungry += 1 if bool(e["starving"]) else 0
	assert_eq(hungry, 0, "the garrison does not starve during the siege")
	gut.p("strong walled town, unstocked: siege from day %d, lifted day %d, best progress %d, starving days %d, checked assault rounds %d" % [
		int(run["begun"]), int(run["lifted"]), best, hungry, _of(run["events"], "siege_repulsed").size()])


func test_siege_is_deterministic() -> void:
	var a_engine := TickEngine.new(repo)
	var r := _invaded(a_engine, 1, true)
	var a: GameState = r[0]
	var b := GameState.from_dict(a.to_dict())
	var b_engine := TickEngine.new(repo)
	for n in 14:
		_day(a_engine, a)
	# into the siege, then saved
	var main := _host("main")
	var played := 0
	while String(b.ai_hosts[main]["mode"]) != "SIEGE" and played < 14:
		_day(b_engine, b)
		played += 1
	_day(b_engine, b)
	played += 1
	assert_eq(String(b.ai_hosts[main]["mode"]), "SIEGE", "saved mid-siege")
	assert_gt(int(b.ai_hosts[main]["siege_progress"]), 0, "with progress made")
	var mid := b.to_dict()
	var path := RunDir.dir("siege").path_join("mid_siege.json")
	SaveLoad.save_game(b, path)
	var c := SaveLoad.load_game(path)
	var c_engine := TickEngine.new(repo)
	for n in 14 - played:
		_day(c_engine, c)
	var d := GameState.from_dict(mid)
	var d_engine := TickEngine.new(repo)
	for n in 14 - played:
		_day(d_engine, d)
	assert_eq(SaveLoad.state_hash(d), SaveLoad.state_hash(a), "same save, same days, same state")
	assert_eq(SaveLoad.state_hash(c), SaveLoad.state_hash(a), "a save mid-siege plays on the same")
	var floats: Array = []
	_floats_in(a.ai_hosts, "ai_hosts", floats)
	assert_eq(floats, [], "no float in the minds")


func _floats_in(v: Variant, path: String, out: Array) -> void:
	Play.floats_in(v, path, out)


func test_siege_draws_no_random_number() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var before: Dictionary = s.rng.to_dict()
	for n in 3:
		SiegeSystem.settle_day(repo, s, [])
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(s.rng.to_dict(), before, "GameState.rng untouched")
	assert_eq(String(s.ai_hosts[main]["target_id"]), town)
