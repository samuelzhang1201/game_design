extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The enemy hosts' minds (spec 2026-10-07-enemy-ai-and-battle-design §3.2–3.5):
## one scoring formula over the player's manors and towns within reach, a
## decision every ai_think_days, hosts that split rather than pile on one
## target, the reserve behind the main host, the engage and retreat checks,
## what a host does on reaching its target, and the host's own daily meal.
## No random number anywhere: GameState.rng is never drawn.

var repo: DataRepository
var _balance: Dictionary
var _doctrines: Dictionary


func before_all() -> void:
	repo = SuiteData.repo()
	_balance = repo.balance.duplicate(true)
	_doctrines = repo.ai_doctrines.duplicate(true)


func after_each() -> void:
	repo.balance = _balance.duplicate(true)
	repo.ai_doctrines = _doctrines.duplicate(true)


## --- helpers ----------------------------------------------------------------

func _at_day(s: GameState, absolute: int) -> void:
	s.tick = 1 + (absolute - 1) / 30
	s.day = 1 + (absolute - 1) % 30
	assert_eq(s.absolute_day(), absolute)


func _host(role: String) -> String:
	for h: Dictionary in repo.raid_hosts:
		if String(h["role"]) == role:
			return String(h["host_code"])
	return ""


func _appear(host: String) -> int:
	for h: Dictionary in repo.raid_hosts:
		if String(h["host_code"]) == host:
			return int(h["appear_day"])
	return 0


## A campaign on `day`, its hosts set out as step_day turns them.
func _field(day: int) -> GameState:
	var s := SuiteData.campaign(repo, 11)
	_at_day(s, day)
	EnemyAi.step_day(repo, s)
	return s


func _home(host: String) -> Vector2i:
	for h: Dictionary in repo.raid_hosts:
		if String(h["host_code"]) == host:
			return ArmySystem.pack_to_metres(repo, Vector2(float(h["start_x"]), float(h["start_y"])))
	return Vector2i.ZERO


## Every foe of `host` standing at `at` (whole metres), halted.
func _place_host(s: GameState, host: String, at: Vector2i) -> void:
	for c: String in EnemyAi.regiments_of(s, host):
		var e: Dictionary = s.foes[c]
		e["x_m"] = at.x
		e["y_m"] = at.y
		e["dest_x_m"] = at.x
		e["dest_y_m"] = at.y
		e["order"] = ArmySystem.ORDER_GARRISON


func _place_mine(s: GameState, code: String, at: Vector2i, order: String) -> void:
	var e: Dictionary = s.regiments[code]
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = order


## The player's land regiments, in code order.
func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) > 0:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


func _town_m(town: String) -> Vector2i:
	var b: Dictionary = repo.burgs[town]
	return ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))


func _cell_m(cell: int) -> Vector2i:
	return ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, repo.cells[cell]))


func _far_from_mine(s: GameState, at: Vector2i, metres: int) -> bool:
	for c: String in _mine():
		var e: Dictionary = s.regiments[c]
		var dx := int(e["x_m"]) - at.x
		var dy := int(e["y_m"]) - at.y
		if dx * dx + dy * dy <= metres * metres:
			return false
	return true


## The first town of the player's realm (code order) with no regiment of the
## player's within 20 km: a town the pack leaves ungarrisoned.
func _empty_town(s: GameState) -> String:
	var player := repo.resolve_realm("player_realm")
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for t: String in codes:
		if MapOwnership.owner_of(repo, s, String(repo.burgs[t]["province_code"])) != player:
			continue
		if _far_from_mine(s, _town_m(t), 20000):
			return t
	return ""


## The first manor of the player's realm (cell order) with no town and no
## regiment of the player's within 20 km.
func _empty_manor(s: GameState) -> int:
	var player := repo.resolve_realm("player_realm")
	for prov: String in MapOwnership.provinces_of(repo, s, player):
		for cell: int in MapManors.manors_of_province(repo, prov, s):
			if MapManors.burg_of(repo, cell) == "" and _far_from_mine(s, _cell_m(cell), 20000):
				return cell
	return -1


func _cand(kind: String, id: String, value: int, days: int, defence: int) -> Dictionary:
	return {"kind": kind, "id": id, "value": value, "distance_days": days, "defence": defence}


## --- the formula --------------------------------------------------------------

func test_score_formula() -> void:
	var doc := {"greed_permille": 1000, "caution_permille": 500, "dist_cost": 200}
	# 5000 x 1000 / 1000 - 3 x 200 - 2000 x 500 / 1000 - 0 = 5000 - 600 - 1000
	assert_eq(EnemyAi.score(5000, 3, 2000, 0, doc), 3400)
	assert_eq(EnemyAi.score(5000, 3, 2000, 800, doc), 2600)
	# the per-mille terms are whole: 999 x 1500 / 1000 = 1498 (not 1498.5)
	assert_eq(EnemyAi.score(999, 0, 0, 0, {"greed_permille": 1500, "caution_permille": 0, "dist_cost": 0}), 1498)


func test_overlap_is_a_share_of_the_score_before_it() -> void:
	# a target another host holds loses ai_target_overlap_permille of its score
	assert_eq(EnemyAi.overlap_of(3400, 500), 1700)
	assert_eq(EnemyAi.overlap_of(3401, 500), 1700)
	assert_eq(EnemyAi.overlap_of(-200, 500), 0, "a losing target is never made better by sharing")


func test_target_value_adds_the_town_bonus_of_the_doctrine() -> void:
	var doc := {"town_bonus": 2000}
	assert_eq(EnemyAi.target_value(3000, "town", doc), 5000)
	assert_eq(EnemyAi.target_value(3000, "manor", doc), 3000)


func test_rich_weak_beats_rich_strong() -> void:
	var doc := {"greed_permille": 1000, "caution_permille": 300, "dist_cost": 100}
	var weak := _cand("manor", "200", 10000, 5, 0)       # 10000 - 500 - 0   = 9500
	var strong := _cand("manor", "100", 10000, 5, 3000)  # 10000 - 500 - 900 = 8600
	var best := EnemyAi.rank([strong, weak], doc, {}, 500)
	assert_eq(String(best["id"]), "200")
	assert_eq(int(best["score"]), 9500)


func test_raider_prefers_undefended_manor_main_prefers_town() -> void:
	# The same two places through the two doctrines: a town (base value 3000,
	# a garrison of power 2000) and an open manor (2500, none), five days off.
	var main := {"greed_permille": 1000, "caution_permille": 300, "dist_cost": 100, "town_bonus": 2000}
	var raider := {"greed_permille": 1200, "caution_permille": 800, "dist_cost": 60, "town_bonus": 0}
	var pick := func(doc: Dictionary) -> Dictionary:
		return EnemyAi.rank([
			_cand("town", "t", EnemyAi.target_value(3000, "town", doc), 5, 2000),
			_cand("manor", "m", EnemyAi.target_value(2500, "manor", doc), 5, 0)], doc, {}, 500)
	# main:   town 5000 - 500 - 600 = 3900; manor 2500 - 500 - 0 = 2000
	var m: Dictionary = pick.call(main)
	assert_eq(String(m["kind"]), "town")
	assert_eq(int(m["score"]), 3900)
	# raider: town 3600 - 300 - 1600 = 1700; manor 3000 - 300 - 0 = 2700
	var r: Dictionary = pick.call(raider)
	assert_eq(String(r["kind"]), "manor")
	assert_eq(int(r["score"]), 2700)
	# and the data's own rows lean the same ways
	var pm: Dictionary = pick.call(repo.ai_doctrines["main"])
	var pr: Dictionary = pick.call(repo.ai_doctrines["raider"])
	assert_eq(String(pm["kind"]), "town", "ai_doctrines.csv main leans to towns")
	assert_eq(String(pr["kind"]), "manor", "ai_doctrines.csv raider leans to open manors")


func test_rank_ties_go_to_the_earlier_id_and_nothing_positive_is_no_target() -> void:
	var doc := {"greed_permille": 1000, "caution_permille": 0, "dist_cost": 0}
	var best := EnemyAi.rank([_cand("manor", "20", 500, 0, 0), _cand("town", "1x", 500, 0, 0),
		_cand("manor", "3", 500, 0, 0)], doc, {}, 500)
	assert_eq(String(best["id"]), "1x", "ties by id string order")
	assert_eq(EnemyAi.rank([_cand("manor", "1", 100, 1, 0)],
		{"greed_permille": 1000, "caution_permille": 0, "dist_cost": 100}, {}, 500), {},
		"a best score of 0 is no target")
	assert_eq(EnemyAi.rank([], doc, {}, 500), {})


func test_a_target_another_host_holds_is_discounted() -> void:
	var doc := {"greed_permille": 1000, "caution_permille": 0, "dist_cost": 0}
	var a := _cand("town", "a", 10000, 0, 0)
	var b := _cand("town", "b", 6000, 0, 0)
	assert_eq(String(EnemyAi.rank([a, b], doc, {}, 500)["id"]), "a", "alone, the richer")
	# taken: 10000 - 10000 x 500 / 1000 = 5000 < 6000
	var best := EnemyAi.rank([a, b], doc, {"town|a": true}, 500)
	assert_eq(String(best["id"]), "b", "the second host goes elsewhere")
	assert_eq(int(best["score"]), 6000)


## --- the candidates --------------------------------------------------------------

func test_candidates_are_the_players_within_reach() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	repo.balance["ai_target_reach_km"] = 60.0
	var cands := EnemyAi.candidates(repo, s, host)
	assert_gt(cands.size(), 0, "the pack puts some of the realm within reach of the main host")
	var player := repo.resolve_realm("player_realm")
	var from := Vector2i(int(s.foes[EnemyAi.regiments_of(s, host)[0]]["x_m"]),
		int(s.foes[EnemyAi.regiments_of(s, host)[0]]["y_m"]))
	var towns := 0
	for c: Dictionary in cands:
		for k: String in ["kind", "id", "value", "distance_days", "defence"]:
			assert_true(c.has(k), "a candidate has " + k)
		var at := EnemyAi.target_point_m(repo, String(c["kind"]), String(c["id"]))
		var dx := at.x - from.x
		var dy := at.y - from.y
		assert_lte(dx * dx + dy * dy, 60000 * 60000, "%s within reach" % c["id"])
		assert_true(EnemyAi.target_held(repo, s, String(c["kind"]), String(c["id"])), "the player's")
		assert_gte(int(c["distance_days"]), 0)
		if String(c["kind"]) == "town":
			towns += 1
			assert_true(repo.burgs.has(String(c["id"])))
			assert_eq(MapOwnership.owner_of(repo, s, String(repo.burgs[String(c["id"])]["province_code"])), player)
		else:
			assert_eq(MapManors.burg_of(repo, int(String(c["id"]))), "", "a town's cell is the town, not a manor")
	assert_gt(towns, 0, "towns are candidates too")


## A host never chooses what it cannot reach on what it carries: a candidate
## more march days away than its hungriest column's days in hand less
## ai_retreat_supply_days and ai_supply_margin_days is none (it would turn
## home hungry on the road; the margin covers the meals' whole-unit rounding).
func test_a_target_beyond_the_hosts_supplies_is_no_candidate() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	var full := EnemyAi.candidates(repo, s, host)
	assert_true(repo.balance.has("ai_supply_margin_days"), "the margin is a balance key")
	if not repo.balance.has("ai_supply_margin_days"):
		return
	var floor_days := int(repo.bal("ai_retreat_supply_days")) + int(repo.bal("ai_supply_margin_days"))
	var horizon := EnemyAi.supply_reach_days(repo, s, host)
	var least := -1
	for c: String in EnemyAi.live_regiments(repo, s, host):
		var days := ArmySystem.days_in_hand(int(s.foes[c]["supplies"]),
			ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s))
		least = days if least < 0 else mini(least, days)
	assert_eq(horizon, least - floor_days, "days in hand less the retreat floor and the margin")
	repo.balance["ai_supply_margin_days"] = float(repo.bal("ai_supply_margin_days")) + 2.0
	assert_eq(EnemyAi.supply_reach_days(repo, s, host), horizon - 2, "a wider margin, a shorter reach")
	repo.balance["ai_supply_margin_days"] = _balance["ai_supply_margin_days"]
	for c: Dictionary in full:
		assert_lte(int(c["distance_days"]), horizon, "%s within the host's supplies" % c["id"])
	# eight days in hand: only what lies within five days' march
	for c: String in EnemyAi.regiments_of(s, host):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s)
		s.foes[c]["supplies"] = (use * 8 + 29) / 30
	assert_eq(EnemyAi.supply_reach_days(repo, s, host), 8 - floor_days)
	var short := EnemyAi.candidates(repo, s, host)
	assert_gt(short.size(), 0, "the pack has something within five days of the main host")
	assert_lt(short.size(), full.size(), "and something beyond")
	for c: Dictionary in short:
		assert_lte(int(c["distance_days"]), 8 - floor_days, "%s within eight days' supplies" % c["id"])
	EnemyAi.think(repo, s, host)
	var mind: Dictionary = s.ai_hosts[host]
	var picked := false
	for c: Dictionary in short:
		picked = picked or (String(c["id"]) == String(mind["target_id"]) and String(c["kind"]) == String(mind["target_kind"]))
	assert_true(picked, "think chooses among the reachable")


func test_ai_sees_only_what_is_in_sight() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	var town := _empty_town(s)
	assert_ne(town, "", "the realm has a town no regiment stands in")
	var at := _town_m(town)
	# the host 60 km west of the town: within reach, beyond sight
	var sight_m := int(repo.bal("ai_sight_km") * 1000.0)
	assert_lt(sight_m, 60000, "the test needs sight under 60 km")
	_place_host(s, host, at - Vector2i(60000, 0))
	repo.balance["ai_target_reach_km"] = 65.0
	var mine: String = _mine()[0]
	_place_mine(s, mine, at, ArmySystem.ORDER_GARRISON)
	var defend := ArmySystem.power(repo, s, mine, "defend")
	assert_gt(defend, 0)
	var find := func() -> Dictionary:
		for c: Dictionary in EnemyAi.candidates(repo, s, host):
			if String(c["kind"]) == "town" and String(c["id"]) == town:
				return c
		return {}
	var far: Dictionary = find.call()
	assert_false(far.is_empty(), "the town is a candidate")
	assert_eq(int(far["defence"]), 0, "a garrison out of sight is no defence")
	assert_false(mine in EnemyAi.seen_by(repo, s, host))
	repo.balance["ai_sight_km"] = 61.0
	var near: Dictionary = find.call()
	assert_true(mine in EnemyAi.seen_by(repo, s, host))
	# power in the defend stance on the town's ground: the town's works
	# (army_town_defence.csv) are in it
	assert_eq(int(near["defence"]), defend, "in sight, its power behind the town's works")


## --- think: choosing, cadence, coordination ---------------------------------------

func test_think_sets_a_target_and_marches_the_whole_host_at_once() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	var couriers := s.couriers.size()
	EnemyAi.think(repo, s, host)
	var mind: Dictionary = s.ai_hosts[host]
	assert_eq(String(mind["mode"]), "ADVANCE")
	assert_ne(String(mind["target_id"]), "", "a target")
	assert_true(String(mind["target_kind"]) in ["town", "manor"])
	assert_eq(int(mind["think_day"]), s.absolute_day())
	var to := EnemyAi.target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
	for c: String in EnemyAi.regiments_of(s, host):
		var e: Dictionary = s.foes[c]
		assert_eq(String(e["order"]), ArmySystem.ORDER_MARCH, c + " marches")
		assert_eq(Vector2i(int(e["dest_x_m"]), int(e["dest_y_m"])), to, c + " for the target")
	assert_eq(s.couriers.size(), couriers, "no courier: the commander is in the column")


func test_think_picks_what_rank_picks_over_every_candidate() -> void:
	var s := _field(_appear(_host("main")))
	for role: String in ["main", "raider"]:
		var host := _host(role)
		var want := EnemyAi.rank(EnemyAi.candidates(repo, s, host), EnemyAi.doctrine_of(repo, host),
			EnemyAi.taken_by_others(repo, s, host), int(repo.bal("ai_target_overlap_permille")))
		EnemyAi.think(repo, s, host)
		assert_eq(String(s.ai_hosts[host]["target_kind"]), String(want["kind"]), role)
		assert_eq(String(s.ai_hosts[host]["target_id"]), String(want["id"]), role)


func test_two_hosts_do_not_pick_the_same_target() -> void:
	var s := _field(_appear(_host("main")))
	EnemyAi.think_day(repo, s)
	var a: Dictionary = s.ai_hosts[_host("main")]
	var b: Dictionary = s.ai_hosts[_host("raider")]
	assert_ne(String(a["target_id"]), "")
	assert_ne(String(b["target_id"]), "")
	assert_ne("%s|%s" % [a["target_kind"], a["target_id"]], "%s|%s" % [b["target_kind"], b["target_id"]],
		"the hosts split")
	# the same frame, the other way round: the raider thinks first, the main host splits from it
	var t := _field(_appear(_host("main")))
	EnemyAi.think(repo, t, _host("raider"))
	EnemyAi.think(repo, t, _host("main"))
	assert_ne("%s|%s" % [t.ai_hosts[_host("main")]["target_kind"], t.ai_hosts[_host("main")]["target_id"]],
		"%s|%s" % [t.ai_hosts[_host("raider")]["target_kind"], t.ai_hosts[_host("raider")]["target_id"]])


func test_no_candidates_withdraws() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	var away := _home(host) + Vector2i(20000, 0)
	_place_host(s, host, away)
	repo.balance["ai_target_reach_km"] = 0.0
	assert_eq(EnemyAi.candidates(repo, s, host), [])
	EnemyAi.think(repo, s, host)
	assert_eq(String(s.ai_hosts[host]["mode"]), "WITHDRAW", "nothing to take: it goes home")
	for c: String in EnemyAi.regiments_of(s, host):
		var e: Dictionary = s.foes[c]
		assert_eq(String(e["order"]), ArmySystem.ORDER_MARCH)
		assert_eq(Vector2i(int(e["dest_x_m"]), int(e["dest_y_m"])), _home(host), "for its start point")
	# and a withdrawing host never chooses again
	repo.balance["ai_target_reach_km"] = 150.0
	_at_day(s, s.absolute_day() + 10)
	EnemyAi.think(repo, s, host)
	assert_eq(String(s.ai_hosts[host]["mode"]), "WITHDRAW")
	assert_eq(String(s.ai_hosts[host]["target_id"]), "")


func test_think_interval() -> void:
	var host := _host("main")
	var d0 := _appear(host)
	var s := _field(d0)
	EnemyAi.think(repo, s, host)
	var first := String(s.ai_hosts[host]["target_id"])
	var kind := String(s.ai_hosts[host]["target_kind"])
	assert_ne(first, "")
	# the target is lost to the raiders: no longer worth anything to them
	var prov := String(repo.burgs[first]["province_code"]) if kind == "town" \
		else MapManors.province_of(repo, int(first), s)
	s.province_owner[prov] = repo.resolve_realm("raider_realm")
	var every := int(repo.bal("ai_think_days"))
	assert_eq(every, 3, "the test walks a three-day cadence")
	for n in range(1, every):
		_at_day(s, d0 + n)
		EnemyAi.think(repo, s, host)
		assert_eq(String(s.ai_hosts[host]["target_id"]), first, "day %d keeps the target" % (n + 1))
		assert_eq(int(s.ai_hosts[host]["think_day"]), d0, "no new decision")
	_at_day(s, d0 + every)
	EnemyAi.think(repo, s, host)
	assert_ne(String(s.ai_hosts[host]["target_id"]), first, "day %d chooses again" % (every + 1))
	assert_eq(int(s.ai_hosts[host]["think_day"]), d0 + every)


func test_same_save_same_target() -> void:
	var a := _field(_appear(_host("main")))
	var b := GameState.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	var rng_before: Dictionary = a.rng.to_dict()
	EnemyAi.think_day(repo, a)
	EnemyAi.think_day(repo, b)
	assert_eq(a.ai_hosts, b.ai_hosts)
	assert_eq(a.foes, b.foes)
	assert_eq(a.rng.to_dict(), rng_before, "no random number is drawn")


func test_reserve_follows_main() -> void:
	var reserve := _host("reserve")
	var s := _field(_appear(reserve))
	assert_eq(String(s.ai_hosts[reserve]["mode"]), "ADVANCE")
	EnemyAi.think_day(repo, s)
	var main: Dictionary = s.ai_hosts[_host("main")]
	var mind: Dictionary = s.ai_hosts[reserve]
	assert_ne(String(main["target_id"]), "")
	assert_eq(String(mind["target_kind"]), String(main["target_kind"]))
	assert_eq(String(mind["target_id"]), String(main["target_id"]))
	var to := EnemyAi.target_point_m(repo, String(main["target_kind"]), String(main["target_id"]))
	for c: String in EnemyAi.regiments_of(s, reserve):
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), to)
	# the reserve's following is no overlap to the others
	assert_false(EnemyAi.taken_by_others(repo, s, _host("main")).has(
		"%s|%s" % [main["target_kind"], main["target_id"]]))
	# the main host going home takes the reserve with it at its next thought
	main["mode"] = "RETREAT"
	_at_day(s, s.absolute_day() + int(repo.bal("ai_think_days")))
	EnemyAi.think(repo, s, reserve)
	assert_eq(String(mind["mode"]), "WITHDRAW")


## --- engage and retreat ---------------------------------------------------------

func test_engage_threshold() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	var at := _home(host)
	var mine: Array = _mine().slice(0, 2)
	for c: String in mine:
		_place_mine(s, c, at + Vector2i(3000, 0), ArmySystem.ORDER_STANDBY)
	var live := EnemyAi.live_regiments(repo, s, host)
	var stance := func(c: String) -> String: return BattleSystem.stance_of(s, c)
	var att := BattleSystem.side_power(repo, s, live, stance, true, mine)
	var def := BattleSystem.side_power(repo, s, mine, stance, false, live)
	var odds := BattleSystem.odds_permille(att, def)
	assert_gt(odds, 0)
	assert_lt(odds, 1000)
	repo.ai_doctrines["main"]["engage_odds_permille"] = odds
	assert_true(EnemyAi.engages(repo, s, host, mine), "at the threshold it fights")
	repo.ai_doctrines["main"]["engage_odds_permille"] = odds + 1
	assert_false(EnemyAi.engages(repo, s, host, mine), "below it, it does not")
	assert_true(EnemyAi.engages(repo, s, host, []), "nothing seen, nothing to fear")


func test_retreat_on_low_morale_and_on_hunger() -> void:
	var host := _host("main")
	var s := _field(_appear(host))
	assert_eq(EnemyAi.should_retreat(repo, s, host), "", "a fresh host stays")
	var live := EnemyAi.live_regiments(repo, s, host)
	var floor_morale := int(repo.ai_doctrines["main"]["retreat_morale"])
	for c: String in live:
		s.foes[c]["morale"] = floor_morale
	assert_eq(EnemyAi.should_retreat(repo, s, host), "", "at the floor it holds")
	for c: String in live:
		s.foes[c]["morale"] = floor_morale - 1
	assert_string_contains(EnemyAi.should_retreat(repo, s, host), "morale")
	for c: String in live:
		s.foes[c]["morale"] = 70
	# hunger: days in hand = supplies x 30 / use. With use 222, 23 units are
	# 690 / 222 = 3 days and 22 are 660 / 222 = 2 (ai_retreat_supply_days 3).
	assert_eq(ArmySystem.days_in_hand(23, 222), 3)
	assert_eq(ArmySystem.days_in_hand(22, 222), 2)
	assert_eq(int(repo.bal("ai_retreat_supply_days")), 3)
	var c0: String = live[0]
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c0), s)
	var three := (3 * use + 29) / 30          # the fewest units that last 3 days
	assert_eq(ArmySystem.days_in_hand(three, use), 3)
	assert_eq(ArmySystem.days_in_hand(three - 1, use), 2)
	s.foes[c0]["supplies"] = three
	assert_eq(EnemyAi.should_retreat(repo, s, host), "")
	s.foes[c0]["supplies"] = three - 1
	var why := EnemyAi.should_retreat(repo, s, host)
	assert_string_contains(why, "suppl")
	# step_day turns it about: RETREAT, every column marching for its start point
	_place_host(s, host, _home(host) + Vector2i(30000, 0))
	var use2 := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c0), s)
	var bite := use2 * s.day / 30 - use2 * (s.day - 1) / 30
	# the day's meal is eaten before the check: it leaves 2 days in hand
	s.foes[c0]["supplies"] = (3 * use2 + 29) / 30 - 1 + bite
	var events := EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "RETREAT")
	assert_true(events.any(func(e: Dictionary) -> bool:
		return String(e["type"]) == "host_mode" and String(e["host"]) == host \
			and String(e["mode"]) == "RETREAT" and String(e["why"]) != ""))
	for c: String in EnemyAi.regiments_of(s, host):
		assert_eq(String(s.foes[c]["order"]), ArmySystem.ORDER_MARCH)
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), _home(host))
	# a retreating host chooses nothing more
	_at_day(s, s.absolute_day() + 5)
	EnemyAi.think(repo, s, host)
	assert_eq(String(s.ai_hosts[host]["mode"]), "RETREAT")


func test_a_beaten_host_retreats() -> void:
	var host := _host("main")
	var s := _field(_appear(host))
	var c0: String = EnemyAi.regiments_of(s, host)[0]
	s.foes[c0]["disengaging"] = 1
	assert_string_contains(EnemyAi.should_retreat(repo, s, host), "beaten")


## --- arrival (Ruling 5) -------------------------------------------------------------

func _aim(s: GameState, host: String, kind: String, id: String) -> void:
	var mind: Dictionary = s.ai_hosts[host]
	mind["mode"] = "ADVANCE"
	mind["target_kind"] = kind
	mind["target_id"] = id
	mind["think_day"] = s.absolute_day()


func test_arrival_at_a_garrisoned_town_sits_down_to_a_siege() -> void:
	var host := _host("main")
	var s := _field(_appear(host))
	var town := _empty_town(s)
	var at := _town_m(town)
	_aim(s, host, "town", town)
	_place_host(s, host, at)
	var mine: String = _mine()[0]
	_place_mine(s, mine, at, ArmySystem.ORDER_GARRISON)
	assert_eq(SupplySystem.garrisoned_in(repo, s, mine), town)
	var events := EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "SIEGE")
	assert_true(events.any(func(e: Dictionary) -> bool:
		return String(e["type"]) == "host_mode" and String(e["mode"]) == "SIEGE"))


func test_arrival_at_an_undefended_manor_raids_it() -> void:
	var host := _host("raider")
	var s := _field(_appear(host))
	var cell := _empty_manor(s)
	assert_gte(cell, 0)
	_aim(s, host, "manor", str(cell))
	_place_host(s, host, _cell_m(cell))
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "RAID")
	assert_eq(EnemyAi.target_cell(repo, s, "manor", str(cell)), cell)


func test_arrival_at_an_ungarrisoned_town_raids_it() -> void:
	var host := _host("main")
	var s := _field(_appear(host))
	var town := _empty_town(s)
	_aim(s, host, "town", town)
	_place_host(s, host, _town_m(town))
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "RAID", "no garrison: the town is plundered, not besieged")
	assert_eq(MapManors.burg_of(repo, EnemyAi.target_cell(repo, s, "town", town)), town, "the town's own cell")


func test_arrival_at_a_lost_target_withdraws() -> void:
	var host := _host("main")
	var s := _field(_appear(host))
	var town := _empty_town(s)
	_aim(s, host, "town", town)
	_place_host(s, host, _town_m(town))
	s.province_owner[String(repo.burgs[town]["province_code"])] = repo.resolve_realm("raider_realm")
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "WITHDRAW")
	for c: String in EnemyAi.regiments_of(s, host):
		assert_eq(String(s.foes[c]["order"]), ArmySystem.ORDER_MARCH)
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), _home(host))


func test_no_arrival_while_every_column_is_still_on_the_road() -> void:
	var host := _host("raider")
	var s := _field(_appear(host))
	var cell := _empty_manor(s)
	var at := _cell_m(cell)
	_aim(s, host, "manor", str(cell))
	_place_host(s, host, at - Vector2i(30000, 0))
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "ADVANCE", "no column has reached it")


func test_raid_begins_when_the_first_column_reaches_the_manor() -> void:
	var host := _host("raider")
	var s := _field(_appear(host))
	var cell := _empty_manor(s)
	var at := _cell_m(cell)
	_aim(s, host, "manor", str(cell))
	_place_host(s, host, at - Vector2i(30000, 0))
	var cols := EnemyAi.regiments_of(s, host)
	assert_gte(cols.size(), 2, "the test needs a host of two columns")
	var c0: String = cols[0]
	s.foes[c0]["x_m"] = at.x
	s.foes[c0]["y_m"] = at.y
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["mode"]), "RAID", "the first column on the manor starts the raid")
	for c: String in cols.slice(1):
		assert_eq(String(s.foes[c]["order"]), ArmySystem.ORDER_MARCH, c + " still comes on")
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), at)


## I1: the columns come on at their own paces from their own places; the
## first to touch the garrisoned town puts the HOST in SIEGE before the day's
## battles, so no lone column ever starts a town battle of its own.
func test_siege_begins_with_the_first_column_and_no_lone_battle() -> void:
	var host := _host("main")
	var s := _field(_appear(host))
	var town := _empty_town(s)
	var at := _town_m(town)
	var mine: Array = _mine()
	_place_mine(s, mine[0], at, ArmySystem.ORDER_GARRISON)
	for c: String in mine.slice(1):     # the rest of the realm's army far away
		_place_mine(s, c, at + Vector2i(0, 400000), ArmySystem.ORDER_GARRISON)
	_aim(s, host, "town", town)
	var cols := EnemyAi.regiments_of(s, host)
	assert_gte(cols.size(), 2)
	for i in cols.size():
		var e: Dictionary = s.foes[cols[i]]
		e["x_m"] = at.x - 20000 - 25000 * i      # 20 km, 45 km, 70 km out
		e["y_m"] = at.y
		e["order"] = ArmySystem.ORDER_GARRISON
	EnemyAi.step_day(repo, s)          # the host sends its columns on
	for c: String in cols:
		assert_eq(String(s.foes[c]["order"]), ArmySystem.ORDER_MARCH)
	var siege_day := 0
	for n in range(1, 10):      # nine days: the 70 km column is up, the stores still hold
		_at_day(s, s.absolute_day() + 1)
		ArmySystem.march_day(repo, s)
		EnemyAi.step_day(repo, s)
		if siege_day == 0 and String(s.ai_hosts[host]["mode"]) == "SIEGE":
			siege_day = n
			var near := 0
			for c: String in cols:
				var e: Dictionary = s.foes[c]
				var dx := int(e["x_m"]) - at.x
				near += 1 if dx * dx < 5000 * 5000 * 4 else 0
			assert_lt(near, cols.size(), "the siege began before the last column came up")
		var fought := BattleSystem.settle_day(repo, s)
		assert_false(fought.any(func(e: Dictionary) -> bool: return String(e["kind"]) == "start"),
			"day %d: no lone column fights the town" % n)
		assert_eq(s.battles, [], "day %d: no battle stands" % n)
	assert_gt(siege_day, 0, "the host sat down to the siege")
	for c: String in cols:
		var e: Dictionary = s.foes[c]
		assert_eq(Vector2i(int(e["dest_x_m"]), int(e["dest_y_m"])), at, c + " came on for the town")


## I2: a target another host holds is BANNED (ai_target_overlap_permille is
## 1000: it scores 0), however rich.
func test_a_taken_target_is_banned_however_rich() -> void:
	var doc := {"greed_permille": 1000, "caution_permille": 0, "dist_cost": 0}
	var permille := int(repo.bal("ai_target_overlap_permille"))
	var rich := _cand("town", "a", 1000000, 0, 0)
	var poor := _cand("manor", "b", 100, 0, 0)
	var best := EnemyAi.rank([rich, poor], doc, {"town|a": true}, permille)
	assert_eq(String(best["id"]), "b", "the second host never takes the first's target")
	assert_eq(EnemyAi.rank([rich], doc, {"town|a": true}, permille), {}, "taken and alone: nothing")


## I2: a host that reaches a town another (non-reserve) host already besieges
## does not sit down to a second siege: it drops the target and chooses again.
func test_a_host_reaching_a_town_another_besieges_rethinks() -> void:
	var host := _host("main")
	var other := _host("raider")
	var s := _field(_appear(host))
	var town := _empty_town(s)
	var at := _town_m(town)
	_place_mine(s, _mine()[0], at, ArmySystem.ORDER_GARRISON)
	s.ai_hosts[other]["mode"] = "SIEGE"
	s.ai_hosts[other]["target_kind"] = "town"
	s.ai_hosts[other]["target_id"] = town
	_aim(s, host, "town", town)
	_place_host(s, host, at)
	EnemyAi.step_day(repo, s)
	var mind: Dictionary = s.ai_hosts[host]
	assert_eq(String(mind["mode"]), "ADVANCE", "no second siege")
	assert_eq(String(mind["target_id"]), "", "the target is dropped")
	EnemyAi.think(repo, s, host)
	assert_ne(String(mind["target_id"]), town, "it chooses again, and not the besieged town")


## N2: a host that finds its town besieged by another halts and stands aside
## that day: none of its columns, though in reach of the garrison, starts a
## battle of its own.
func test_a_rethinking_host_halts_and_fights_nothing_that_day() -> void:
	var host := _host("main")
	var other := _host("raider")
	var s := _field(_appear(host))
	var town := _empty_town(s)
	var at := _town_m(town)
	_place_mine(s, _mine()[0], at, ArmySystem.ORDER_GARRISON)
	s.ai_hosts[other]["mode"] = "SIEGE"
	s.ai_hosts[other]["target_kind"] = "town"
	s.ai_hosts[other]["target_id"] = town
	_aim(s, host, "town", town)
	_place_host(s, host, at - Vector2i(2000, 0))
	for c: String in EnemyAi.regiments_of(s, host):
		s.foes[c]["dest_x_m"] = at.x
		s.foes[c]["order"] = ArmySystem.ORDER_MARCH
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[host]["target_id"]), "")
	for c: String in EnemyAi.regiments_of(s, host):
		var e: Dictionary = s.foes[c]
		assert_ne(String(e["order"]), ArmySystem.ORDER_MARCH, c + " halts")
		assert_eq(Vector2i(int(e["dest_x_m"]), int(e["dest_y_m"])), Vector2i(int(e["x_m"]), int(e["y_m"])))
	var fought := BattleSystem.settle_day(repo, s)
	assert_false(fought.any(func(e: Dictionary) -> bool: return String(e["kind"]) == "start"),
		"no column of it fights the besieged town alone")
	assert_eq(s.battles, [])


## N1: the reserve follows the main host to its siege and SITS DOWN to it (the
## guard is for non-reserve hosts only), so its columns are left to the
## assaults and no lone battle starts.
func test_reserve_joins_its_main_hosts_siege() -> void:
	var reserve := _host("reserve")
	var main := _host("main")
	var s := _field(_appear(reserve))
	var town := _empty_town(s)
	var at := _town_m(town)
	_place_mine(s, _mine()[0], at, ArmySystem.ORDER_GARRISON)
	s.ai_hosts[main]["mode"] = "SIEGE"
	s.ai_hosts[main]["target_kind"] = "town"
	s.ai_hosts[main]["target_id"] = town
	_place_host(s, main, at)
	_aim(s, reserve, "town", town)
	_place_host(s, reserve, at)
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.ai_hosts[reserve]["mode"]), "SIEGE", "the reserve joins the siege")
	assert_eq(String(s.ai_hosts[reserve]["target_id"]), town)
	var fought := BattleSystem.settle_day(repo, s)
	assert_false(fought.any(func(e: Dictionary) -> bool: return String(e["kind"]) == "start"),
		"no assault day: nobody fights")
	assert_eq(s.battles, [])
	EnemyAi.think_day(repo, s)
	assert_eq(String(s.ai_hosts[reserve]["mode"]), "SIEGE", "and stays at it")


## Nit: the ban holds in think, not only in rank: the host's own best target,
## once another host holds it, is not chosen.
func test_think_never_takes_a_target_another_host_holds() -> void:
	var host := _host("main")
	var other := _host("raider")
	var alone := _field(_appear(host))
	EnemyAi.think(repo, alone, host)
	var best := String(alone.ai_hosts[host]["target_id"])
	var kind := String(alone.ai_hosts[host]["target_kind"])
	assert_ne(best, "")
	var s := _field(_appear(host))
	s.ai_hosts[other]["target_kind"] = kind
	s.ai_hosts[other]["target_id"] = best
	EnemyAi.think(repo, s, host)
	assert_ne(String(s.ai_hosts[host]["target_id"]), best, "its best, taken, is not chosen")
	assert_ne(String(s.ai_hosts[host]["target_id"]), "", "it goes elsewhere")


## Minor (a): the town -> cell table follows the repository's map.
func test_town_cells_follow_the_map() -> void:
	var r := SuiteData.repo()
	var s := SuiteData.campaign(repo, 11)
	var town := _empty_town(s)
	var cell := EnemyAi.target_cell(r, s, "town", town)
	assert_eq(MapManors.burg_of(r, cell), town)
	# another map in the same repository: the town now stands on another cell
	var other := -1
	for c: int in r.manors:
		if MapManors.burg_of(r, c) == "" and c != cell:
			other = c
			break
	r.manors[cell]["burg_code"] = ""
	r.manors[other]["burg_code"] = town
	r.map_id = r.map_id + "_other"
	assert_eq(EnemyAi.target_cell(r, s, "town", town), other, "not the old map's cell")


## Minor (c): the reserve follows the main host every day, not on a cadence.
func test_reserve_follows_main_every_day() -> void:
	var reserve := _host("reserve")
	var s := _field(_appear(reserve))
	EnemyAi.think_day(repo, s)
	var main: Dictionary = s.ai_hosts[_host("main")]
	var town := _empty_town(s)
	assert_ne(String(main["target_id"]), town)
	_at_day(s, s.absolute_day() + 1)
	main["target_kind"] = "town"
	main["target_id"] = town
	EnemyAi.think(repo, s, reserve)
	assert_eq(String(s.ai_hosts[reserve]["target_id"]), town, "the next day, not three days on")
	for c: String in EnemyAi.regiments_of(s, reserve):
		assert_eq(Vector2i(int(s.foes[c]["dest_x_m"]), int(s.foes[c]["dest_y_m"])), _town_m(town))


func test_a_halted_column_of_an_advancing_host_marches_on() -> void:
	# a battle halts a column where it stands (BattleSystem._halt); once free,
	# its host sends it on for the target the next day
	var host := _host("main")
	var s := _field(_appear(host))
	EnemyAi.think(repo, s, host)
	var mind: Dictionary = s.ai_hosts[host]
	var to := EnemyAi.target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
	var c0: String = EnemyAi.regiments_of(s, host)[0]
	s.foes[c0]["order"] = ArmySystem.ORDER_GARRISON
	s.foes[c0]["dest_x_m"] = int(s.foes[c0]["x_m"])
	s.foes[c0]["dest_y_m"] = int(s.foes[c0]["y_m"])
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.foes[c0]["order"]), ArmySystem.ORDER_MARCH)
	assert_eq(Vector2i(int(s.foes[c0]["dest_x_m"]), int(s.foes[c0]["dest_y_m"])), to)
	# but never one still in a battle: an order would take it out of the fight
	s.foes[c0]["order"] = ArmySystem.ORDER_GARRISON
	s.battles.append({"id": 99, "att": [c0], "def": [_mine()[0]], "start_day": 1, "rounds": 1,
		"place_x_m": 0, "place_y_m": 0, "town": ""})
	EnemyAi.step_day(repo, s)
	assert_eq(String(s.foes[c0]["order"]), ArmySystem.ORDER_GARRISON, "it stays in the fight")


## --- the host's meal ------------------------------------------------------------------

func test_a_host_in_the_field_eats_a_day_and_an_assembling_one_does_not() -> void:
	var main := _host("main")
	var reserve := _host("reserve")
	var s := _field(_appear(main))
	assert_eq(String(s.ai_hosts[reserve]["mode"]), "ASSEMBLE")
	var before := {}
	for c: Variant in s.foes:
		before[c] = int(s.foes[c]["supplies"])
	_at_day(s, _appear(main) + 1)
	EnemyAi.step_day(repo, s)
	for c: String in EnemyAi.regiments_of(s, main):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s)
		# day d of the month eats use x d / 30 - use x (d - 1) / 30, whole units
		var bite := use * s.day / 30 - use * (s.day - 1) / 30
		assert_eq(int(s.foes[c]["supplies"]), int(before[c]) - bite, c + " ate the day's share")
	for c: String in EnemyAi.regiments_of(s, reserve):
		assert_eq(int(s.foes[c]["supplies"]), int(before[c]), c + " is fed at home while it assembles")


func test_a_month_in_the_field_eats_exactly_the_months_use() -> void:
	var main := _host("main")
	var s := _field(_appear(main))
	var c0: String = EnemyAi.regiments_of(s, main)[0]
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c0), s)
	s.foes[c0]["supplies"] = use * 5
	repo.balance["ai_retreat_supply_days"] = 0.0   # keep it in the field for the month
	for d in range(1, 31):
		s.tick = 2
		s.day = d
		EnemyAi.step_day(repo, s)
	assert_eq(int(s.foes[c0]["supplies"]), use * 4, "thirty days eat one month's use, to the unit")


## --- determinism ----------------------------------------------------------------------

func _run(s: GameState, days: int) -> void:
	for n in days:
		EnemyAi.step_day(repo, s)
		EnemyAi.think_day(repo, s)
		ArmySystem.march_day(repo, s)
		_at_day(s, s.absolute_day() + 1)


func test_the_minds_are_deterministic() -> void:
	var a := _field(_appear(_host("main")))
	var b := GameState.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	var rng_before: Dictionary = a.rng.to_dict()
	_run(a, 8)
	_run(b, 8)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "same save, same days, same state")
	assert_eq(a.rng.to_dict(), rng_before, "GameState.rng untouched")
	var moved := false
	for c: Variant in a.foes:
		var h := String(a.foes[c]["host"])
		if Vector2i(int(a.foes[c]["x_m"]), int(a.foes[c]["y_m"])) != _home(h):
			moved = true
	assert_true(moved, "the hosts did something")
	for h: String in EnemyAi.host_codes(a):
		for k: Variant in a.ai_hosts[h]:
			var v: Variant = a.ai_hosts[h][k]
			assert_true(v is int or v is String, "%s.%s is whole or a word" % [h, k])


## Minor (b): think's WITHDRAW is a mode change like any other: an event with
## its reason.
func test_think_withdraw_is_an_event() -> void:
	var s := _field(_appear(_host("main")))
	var host := _host("main")
	repo.balance["ai_target_reach_km"] = 0.0
	var events: Array = EnemyAi.think(repo, s, host)
	assert_eq(String(s.ai_hosts[host]["mode"]), "WITHDRAW")
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["type"]), "host_mode")
	assert_eq(String(events[0]["host"]), host)
	assert_eq(String(events[0]["mode"]), "WITHDRAW")
	assert_ne(String(events[0]["why"]), "", "with its reason")
	assert_eq(int(events[0]["day"]), s.absolute_day())
	assert_eq(EnemyAi.think(repo, s, host), [], "a host already going home thinks no more")
