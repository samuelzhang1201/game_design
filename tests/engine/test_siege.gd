extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
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

## The player's land regiments of 1000 men or more, in code order.
func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) >= 1000:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


func _host(role: String) -> String:
	for h: Dictionary in repo.raid_hosts:
		if String(h["role"]) == role:
			return String(h["host_code"])
	return ""


func _town_m(town: String) -> Vector2i:
	return EnemyAi.target_point_m(repo, "town", town)


func _place(s: GameState, code: String, at: Vector2i, order: String) -> void:
	var e: Dictionary = s.foes.get(code, s.regiments.get(code, {}))
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = order


## A town the pack quarters one of the player's regiments in that is not the
## depot (so a dry garrison could be fed from elsewhere): [town, regiment].
func _town_and_garrison(s: GameState) -> Array:
	var dep := TownStores.depot(repo, s)
	for c: String in _mine():
		var t := ArmySystem.held_town_of(repo, ArmySystem.regiment(repo, c), s)
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


func _kinds(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return String(e["kind"]))


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == kind)


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
	var fed := GameState.from_dict(s.to_dict())
	_stocked(fed, town)
	s.town_stock.erase(town)
	assert_true(SiegeSystem.starving(s, town), "a town with no stores starves")
	assert_false(SiegeSystem.starving(fed, town), "a stocked one does not")
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
	s.day += 2
	var fight := BattleSystem.settle_day(repo, s)
	assert_eq(_of(fight, "start").size(), 1, "tried again once the pause is over")
	# the siege ends: no flag outlives it
	s.ai_hosts[main]["mode"] = "RETREAT"
	SiegeSystem.settle_day(repo, s, fight)
	assert_eq(int(s.ai_hosts[main].get("assault", 0)), 0, "no flag on a host that left")
	assert_eq(int(s.ai_hosts[main].get("assault_due", 0)), 0)


## The events of an assault fought and ended today at `town`: the foes stormed
## (att), the garrison held (def); `winner` the side that kept the field.
func _assault(id: int, foes: Array, garrison: Array, town: String, winner: String) -> Array:
	var at := _town_m(town)
	var start := {"kind": "start", "battle_id": id, "att": foes, "def": garrison, "town": town,
		"place_x_m": at.x, "place_y_m": at.y}
	var end := {"kind": "end", "battle_id": id, "why": "rout_" + ("defender" if winner == "att" else "attacker"),
		"winner": winner, "att": foes if winner == "att" else [], "def": garrison if winner == "def" else [],
		"rounds": 1, "town": town, "place_x_m": at.x, "place_y_m": at.y}
	return [start, end]


func test_failed_assault_lowers_progress() -> void:
	repo.balance["siege_rate"] = 100.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	s.ai_hosts[main]["siege_progress"] = 500
	var gain := SiegeSystem.step(SiegeSystem.attack_power(repo, s, town), SiegeSystem.defend_power(repo, s, town), 100)
	var fail := int(repo.bal("siege_assault_fail_permille"))
	assert_gt(fail, 0, "a failed assault costs the besieger")
	var ev := SiegeSystem.settle_day(repo, s, _assault(41, EnemyAi.regiments_of(s, main), [g], town, "def"))
	# 500 - fail, then the day's gain
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 500 - fail + gain)
	var rep := _of(ev, "siege_repulsed")
	assert_eq(rep.size(), 1, "the repulse is news")
	if not rep.is_empty():
		assert_eq(int(rep[0]["lost"]), fail)
	# a drawn assault changes nothing but the day's gain
	var before := int(s.ai_hosts[main]["siege_progress"])
	var drawn := _assault(42, EnemyAi.regiments_of(s, main), [g], town, "def")
	drawn[1]["winner"] = ""
	drawn[1]["why"] = "rounds"
	SiegeSystem.settle_day(repo, s, drawn)
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), before + gain, "a draw: no change")
	# a failed assault never takes the progress below 0
	s.ai_hosts[main]["siege_progress"] = 10
	SiegeSystem.settle_day(repo, s, _assault(43, EnemyAi.regiments_of(s, main), [g], town, "def"))
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), gain, "held at 0, then the day's gain")


func test_routed_defender_adds_the_rest() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 120
	var ev := SiegeSystem.settle_day(repo, s, _assault(51, EnemyAi.regiments_of(s, main), [g], town, "att"))
	assert_eq(_of(ev, "siege_fallen").size(), 1, "the garrison broken: the town falls that day")
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")


## --- the fall (§5.2) -----------------------------------------------------------

func test_capture_at_1000_changes_owner_with_a_reason() -> void:
	repo.balance["siege_rate"] = 100.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	_stocked(s, town)
	var prov := String(repo.burgs[town]["province_code"])
	var player := repo.resolve_realm("player_realm")
	var raider := repo.resolve_realm("raider_realm")
	assert_eq(MapOwnership.owner_of(repo, s, prov), player)
	s.ai_hosts[main]["siege_progress"] = 999
	var cell := EnemyAi.target_cell(repo, s, "town", town)
	assert_gt(cell, -1, "the town has a manor")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(MapOwnership.owner_of(repo, s, prov), raider, "the town's province is the raider realm's")
	assert_eq(s.territory_log.size(), 1, "one move")
	var town_label := String(repo.burgs[town]["label"])
	if s.territory_log.size() == 1:
		var log: Dictionary = s.territory_log[0]
		assert_eq([String(log["province"]), String(log["from"]), String(log["to"])], [prov, player, raider])
		assert_true(String(log["reason"]).begins_with("taken by "), "with its reason: " + String(log["reason"]))
		assert_true(String(log["reason"]).contains("siege of " + town_label), String(log["reason"]))
	var moved: Array = s.manor_log.filter(func(m: Dictionary) -> bool: return int(m["cell"]) == cell)
	assert_eq(moved.size(), 1, "the town's manor changes hands")
	if moved.size() == 1:
		assert_true(String(moved[0]["reason"]).contains("siege of " + town_label), "with the same reason")
		assert_ne(MapManors.owner_of(repo, s, cell), MapManors.crown(s))
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "the host holds the town")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0, "the siege is over")
	assert_eq(_of(ev, "siege_fallen").size(), 1, "the fall is news")
	assert_eq(String(s.regiments[g]["order"]), ArmySystem.ORDER_MARCH, "the garrison marches out")
	assert_eq(int(s.regiments[g].get("disengaging", 0)), 1, "unmolested on its way")
	assert_eq(SupplySystem.garrisoned_in(repo, s, g), "", "and garrisons the town no more")


func test_garrison_slain_to_the_last_man_loses_the_town() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.regiments[g]["dead"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, g))
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(MapOwnership.owner_of(repo, s, String(repo.burgs[town]["province_code"])),
		repo.resolve_realm("raider_realm"), "no fit man left: the town is taken")
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")


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
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "a host holding a town neither thinks nor starves home")
	assert_eq(String(s.ai_hosts[main]["target_id"]), town, "and keeps its town")
	for c: String in EnemyAi.regiments_of(s, main):
		assert_eq([int(s.foes[c]["x_m"]), int(s.foes[c]["y_m"]), String(s.foes[c]["order"])], before[c], c + " stays")


func test_no_double_capture_and_no_progress_after_loss() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	var moves := s.territory_log.size()
	var manor_moves := s.manor_log.size()
	assert_eq(moves, 1)
	assert_eq(SiegeSystem.capture(repo, s, main), {}, "a town taken is not taken twice")
	s.ai_hosts[main]["mode"] = "SIEGE"           # even a host put back to the siege
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(s.territory_log.size(), moves, "no second move of the province")
	assert_eq(s.manor_log.size(), manor_moves, "nor of the manor")
	assert_eq(String(s.ai_hosts[main]["mode"]), "WITHDRAW", "the town is no longer the crown's: home")
	# a town lost some other way mid-siege: no progress, no capture
	var s2 := SuiteData.campaign(repo, 7)
	var town2 := _besiege(s2, main, [String(_town_and_garrison(s2)[1])])
	s2.ai_hosts[main]["siege_progress"] = 300
	MapOwnership.set_owner(repo, s2, String(repo.burgs[town2]["province_code"]), repo.resolve_realm("raider_realm"),
		"test: lost elsewhere")
	var ev := SiegeSystem.settle_day(repo, s2, [])
	assert_eq(s2.territory_log.size(), 1, "only the test's move")
	assert_eq(_of(ev, "siege_day").size(), 0, "no day's progress")
	assert_eq(int(s2.ai_hosts[main]["siege_progress"]), 0)
	assert_eq(String(s2.ai_hosts[main]["mode"]), "WITHDRAW")


func test_garrison_marched_off_ends_the_siege_without_progress() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 300
	s.regiments[g]["order"] = ArmySystem.ORDER_MARCH
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_day").size(), 0, "no progress on an empty town")
	assert_eq(s.territory_log.size(), 0, "and no capture: no siege took it")
	assert_eq(String(s.ai_hosts[main]["mode"]), "RAID", "an open town is raided, as on arrival")
	assert_eq(String(s.ai_hosts[main]["target_id"]), town)
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0)
	assert_eq(_of(ev, "siege_undefended").size(), 1)


func test_recaptured_town_sends_hold_host_retreating() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD")
	assert_eq(SiegeSystem.settle_day(repo, s, []).size(), 0, "a quiet day in the town")
	MapOwnership.set_owner(repo, s, String(repo.burgs[town]["province_code"]), repo.resolve_realm("player_realm"),
		"test: retaken")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT", "the town is the crown's again: home")
	assert_eq(int(s.ai_hosts[main]["siege_progress"]), 0)
	assert_eq(_of(ev, "siege_retaken").size(), 1)
	var home := EnemyAi.home_m(repo, main)
	for c: String in EnemyAi.live_regiments(repo, s, main):
		assert_eq(String(s.foes[c]["order"]), ArmySystem.ORDER_MARCH, c + " marches")
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), home, c + " for home")


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
		assert_eq(SupplySystem.garrisoned_in(repo, s, c), "", c + " is no garrison")
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
	assert_eq(s.territory_log.size(), 1, "taken once")


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
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var g := String(_town_and_garrison(s)[1])
	var town := _besiege(s, main, [g])
	var ev := SiegeSystem.settle_day(repo, s, [])
	ev.append_array(SiegeSystem.settle_day(repo, s, _assault(61, EnemyAi.regiments_of(s, main), [g], town, "def")))
	s.ai_hosts[main]["siege_progress"] = 1000
	ev.append_array(SiegeSystem.settle_day(repo, s, []))
	var news := SiegeSystem.news(ev)
	assert_eq(_of(news, "siege_day").size(), 0, "a day's wearing down is no news")
	for k: String in ["siege_begin", "siege_repulsed", "siege_fallen"]:
		assert_eq(_of(news, k).size(), 1, k + " is")
	var m := MissiveWriter.battle_report(repo, s, news)
	assert_eq(String(m["kind"]), "battle")
	assert_eq(String(m["column"]), "credible")
	var text := " ".join((m["facts"] as Array).map(func(f: Dictionary) -> String: return String(f["text"])))
	assert_eq((m["facts"] as Array).size(), news.size(), "a line an event")
	assert_false(text.contains("[missing template"), text)
	assert_false(text.contains("{"), "every slot filled: " + text)
	assert_true(text.contains(String(repo.burgs[town]["label"])), "names the town")
	assert_true(text.contains(repo.realm_label("raider_realm")), "the raider realm through its slot")
	var fallen: Dictionary = _of(news, "siege_fallen")[0]
	assert_true(text.contains(str(int(fallen["days"]))), "the figures are the events'")


func test_siege_templates_spell_no_kingdom() -> void:
	var raw := FileAccess.get_file_as_string("res://data/templates.csv")
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
	assert_gte(found, 7, "begin, starving, repulsed, fallen, lifted, undefended, retaken")


## --- the real day loop ---------------------------------------------------------

func _opened(engine: TickEngine) -> GameState:
	var s := SuiteData.campaign(repo, 11)
	engine.advance(s)
	return s


func _day(engine: TickEngine, s: GameState) -> void:
	if s.day >= Calendar.DAYS_PER_TICK:
		engine.advance(s)
	else:
		engine.advance_day(s)


func _first_appear() -> int:
	var first := -1
	for h: Dictionary in repo.raid_hosts:
		var d := int(h["appear_day"])
		first = d if first < 0 else mini(first, d)
	return first


## The day loop to the main host's crossing, its target held from then on, the
## town garrisoned by `n` of the player's regiments (`weakest`: the smallest
## first, else the largest first). [state, town, garrison].
func _invaded(engine: TickEngine, n: int, weakest: bool) -> Array:
	repo.balance["ai_think_days"] = 999.0
	var s := _opened(engine)
	while s.absolute_day() <= _first_appear():
		_day(engine, s)
	var mind: Dictionary = s.ai_hosts[_host("main")]
	assert_eq(String(mind["target_kind"]), "town", "the main host goes for a town")
	var town := String(mind["target_id"])
	var by_size := _mine()
	by_size.sort_custom(func(a: String, b: String) -> bool:
		var ha := ArmySystem.headcount(repo, ArmySystem.regiment(repo, a))
		var hb := ArmySystem.headcount(repo, ArmySystem.regiment(repo, b))
		return (ha < hb if weakest else ha > hb) or (ha == hb and a < b))
	var garrison: Array = by_size.slice(0, n)
	for c: String in garrison:
		_place(s, c, _town_m(town), ArmySystem.ORDER_GARRISON)
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
			var k := String(e["kind"])
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
		match String(e["kind"]):
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
	var prov := String(repo.burgs[town]["province_code"])
	assert_eq(MapOwnership.owner_of(repo, s, prov), repo.resolve_realm("raider_realm"))
	var log: Array = s.territory_log.filter(func(l: Dictionary) -> bool: return String(l["province"]) == prov)
	assert_eq(log.size(), 1, "moved once, with its reason")
	if log.size() == 1:
		assert_true(String(log[0]["reason"]).contains("siege of"), String(log[0]["reason"]))
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
	_stocked(s, town)
	var run := _siege_run(engine, s, 40)
	var main := _host("main")
	assert_gt(int(run["begun"]), 0, "the host sat down before the town")
	assert_eq(int(run["fell"]), -1, "the town does not fall")
	assert_gt(int(run["lifted"]), 0, "the siege is lifted")
	assert_true(String(s.ai_hosts[main]["mode"]) in ["RETREAT", "WITHDRAW"], "the host goes home")
	assert_eq(MapOwnership.owner_of(repo, s, String(repo.burgs[town]["province_code"])),
		repo.resolve_realm("player_realm"), "the town is still the crown's")
	var best := 0
	for e: Dictionary in run["events"]:
		if String(e["kind"]) == "siege_day":
			best = maxi(best, int(e["progress"]))
	gut.p("strong walled town: siege from day %d, lifted day %d, best progress %d" % [int(run["begun"]),
		int(run["lifted"]), best])


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
	if typeof(v) == TYPE_FLOAT:
		out.append(path)
	elif v is Dictionary:
		for k in v:
			_floats_in(v[k], path + "/" + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_floats_in(v[i], path + "[%d]" % i, out)


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
