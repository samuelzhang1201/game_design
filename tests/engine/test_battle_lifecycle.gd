extends GutTest
const People := preload("res://tests/fixtures/military_people.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## A battle's life (spec 2026-10-07-enemy-ai-and-battle-design §4.1, §4.4):
## contact starts it, a round a day, reinforcements join up to the cap, the
## stances start real withdrawals, and it ends on a rout or a side
## emptied after physical separation. Regiments are placed by hand; the outcome table is replaced by
## hand-made tiers where a test needs exact numbers.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	# Lifecycle fixtures isolate tier/retreat arithmetic; deployment factors have their own hand tests.
	for formation: Dictionary in repo.battle_formations.values():
		for key: String in ["attack_permille", "defence_permille", "flank_permille", "missile_permille"]:
			formation[key] = 1000
	for order: Dictionary in repo.battle_orders.values():
		for key: String in ["attack_permille", "defence_permille", "morale_decay_permille"]:
			order[key] = 1000
	for context: String in ["ranged", "shock", "withdrawal", "pursuit"]:
		repo.balance["battle_context_" + context + "_permille"] = 1000
	Weather.forget()


## The player's land units of 400 men or more, in code order.
func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) >= 400:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


## The raider hosts' units (EnemyAi.host_units) of 400 men or more, in code order.
func _theirs() -> Array:
	var out: Array = []
	for h: Dictionary in repo.raid_hosts:
		for c: String in EnemyAi.host_units(repo, null, h):
			var reg := ArmySystem.regiment(repo, c)
			if String(reg.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, reg) >= 400:
				out.append(c)
	out.sort()
	return out


func _heads(code: String) -> int:
	return ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))


## The spot the tests fight on: the first unit's opening ground, in metres.
func _spot(_s: GameState = null) -> Vector2i:
	var r := ArmySystem.regiment(repo, _mine()[0])
	return ArmySystem.pack_to_metres(repo, Vector2(float(r["x"]), float(r["y"])))


## A suite campaign with the player's army out of the tests' way: every land
## unit leaves its seat and camp and stands far off (a camp round the spot's
## town would otherwise join, or garrison the town); a test brings its own up.
func _campaign(seed_value: int) -> GameState:
	var s := SuiteData.campaign(repo, seed_value)
	Play.park_army(repo, s, _spot())
	return s


## Stands a unit at `at`, standing by: out of any seat or camp (so it
## garrisons no town unless a test says so).
func _place(s: GameState, code: String, at: Vector2i) -> void:
	var e: Dictionary = s.regiments[code]
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = ArmySystem.ORDER_STANDBY
	e["camp_town"] = ""
	for t: Variant in s.town_seat.keys():
		if String(s.town_seat[t]) == code:
			s.town_seat.erase(t)


func _foe(s: GameState, code: String, at: Vector2i, host := "") -> Dictionary:
	var st := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, code))
	st["x_m"] = at.x
	st["y_m"] = at.y
	st["dest_x_m"] = at.x
	st["dest_y_m"] = at.y
	st["battle_plan"] = "attack"
	if host != "":
		st["host"] = host
	s.foes[code] = st
	return st


## A regiment's state, foe or not.
func _st(s: GameState, code: String) -> Dictionary:
	return s.foes.get(code, s.regiments.get(code, {}))


## One outcome row for every eff, so a round's result is known by hand; no
## variance; no regiment retreats on the odds (evade still starts a
## withdrawal on contact).
func _one_tier(att_loss: int, def_loss: int, share: int, att_morale: int, def_morale: int,
		rout := "none") -> void:
	repo.battle_outcomes.clear()
	repo.battle_outcomes.append({"tier": "hand_made", "eff_min": 0, "eff_max": 1000,
		"attacker_loss_permille": att_loss, "defender_loss_permille": def_loss,
		"wounded_share_permille": share, "attacker_morale": att_morale,
		"defender_morale": def_morale, "rout": rout})
	repo.balance["battle_variance_permille"] = 0.0
	for k: String in repo.battle_stances:
		repo.battle_stances[k]["retreat_odds_permille"] = 0


func _in_battle(s: GameState, code: String) -> bool:
	return not BattleSystem.battle_of(s, code).is_empty()


func _kinds(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == kind)


func _next_day(s: GameState) -> void:
	s.day = mini(s.day + 1, Calendar.DAYS_PER_TICK)


## --- contact -------------------------------------------------------------

func test_field_contact_starts_one_battle() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	var at := _spot(s)
	_place(s, p, at)
	# the column was marching on: it walked into the foe, so it attacks
	s.regiments[p]["order"] = ArmySystem.ORDER_MARCH
	s.regiments[p]["dest_x_m"] = at.x + 50_000
	_foe(s, f, at + Vector2i(1000, 0))
	var events := BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1, "one battle")
	var b: Dictionary = s.battles[0]
	assert_eq(b["att"], [p], "the marching side attacks")
	assert_eq(b["def"], [f])
	assert_eq(int(b["start_day"]), s.absolute_day())
	assert_eq(int(b["rounds"]), 1, "the first round is fought the day they meet")
	assert_eq(String(b["town"]), "", "in the open")
	assert_eq(Vector2i(int(b["place_x_m"]), int(b["place_y_m"])), at + Vector2i(1000, 0),
		"fought where the defender stands")
	assert_gt(int(b["id"]), 0)
	assert_ne(ArmySystem.order_of(repo, s, p), ArmySystem.ORDER_MARCH, "the column halts to fight")
	assert_ne(String(s.foes[f]["order"]), ArmySystem.ORDER_MARCH)
	assert_eq(_kinds(events, "start").size(), 1)
	assert_eq(_kinds(events, "round").size(), 1)
	# the next day: the same battle, no second one
	_next_day(s)
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1, "still one battle")
	assert_eq(int(s.battles[0]["rounds"]), 2)


func test_no_contact_no_battle() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	var reach := int(repo.bal("battle_contact_km")) * 1000
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(reach + 1, 0))
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 0, "a metre beyond battle_contact_km: no battle")
	_foe(s, f, _spot(s) + Vector2i(reach, 0))
	BattleSystem.detect_contacts(repo, s)
	assert_eq(s.battles.size(), 1, "at battle_contact_km exactly: contact")
	assert_eq(int(s.battles[0]["rounds"]), 0, "detect_contacts fights no round")


func test_town_contact_needs_a_garrison() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	repo.balance["battle_contact_km"] = 0.0   # only the town can bring them together
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	var town := String(ArmySystem.regiment(repo, p).get("camp_town", ""))
	assert_ne(town, "", "the split camps the unit by a town of its own")
	var b: Dictionary = repo.burgs[town]
	var town_m := ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
	var reach_m := int(float(repo.army_town_reach[String(b["group"])]) * 1000.0)
	_place(s, p, town_m)
	@warning_ignore("integer_division")
	_foe(s, f, town_m + Vector2i(reach_m / 2, 0))
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 0, "a column standing by in the town, off its seat and camp, is no garrison")
	s.regiments[p]["order"] = ArmySystem.ORDER_GARRISON
	assert_eq(ArmyGround.garrison_town(repo, s, p), town)
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1, "the garrison is attacked")
	var fight: Dictionary = s.battles[0]
	assert_eq(String(fight["town"]), town)
	assert_eq(fight["att"], [f], "the foe assaults the town")
	assert_eq(fight["def"], [p])
	assert_eq(Vector2i(int(fight["place_x_m"]), int(fight["place_y_m"])), town_m, "fought at the town")
	# the unit on the town's seat garrisons it standing by (ArmyGround.seated_in)
	var s2 := _campaign(7)
	_place(s2, p, town_m)
	s2.town_seat[town] = p
	@warning_ignore("integer_division")
	_foe(s2, f, town_m + Vector2i(reach_m / 2, 0))
	assert_eq(ArmyGround.garrison_town(repo, s2, p), town, "the seat is the garrison")
	BattleSystem.settle_day(repo, s2)
	assert_eq(s2.battles.size(), 1, "the seat's unit is attacked")
	assert_eq(String(s2.battles[0]["town"]), town)
	# and so does a unit camped round it, outside the town's reach (camp_town)
	var s3 := _campaign(7)
	_place(s3, p, town_m + Vector2i(reach_m * 2, 0))
	s3.regiments[p]["camp_town"] = town
	@warning_ignore("integer_division")
	_foe(s3, f, town_m + Vector2i(reach_m / 2, 0))
	assert_eq(ArmyGround.garrison_town(repo, s3, p), town, "the camp is invested with its town")
	BattleSystem.settle_day(repo, s3)
	assert_eq(s3.battles.size(), 1, "the camp defends the town")
	assert_eq(String(s3.battles[0]["town"]), town)
	assert_eq(s3.battles[0]["def"], [p])


func test_a_sieging_host_fights_only_on_its_assault_day() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	var town := String(ArmySystem.regiment(repo, p).get("camp_town", ""))
	assert_ne(town, "", "the split camps the unit by a town of its own")
	var town_m := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	_place(s, p, town_m)
	s.regiments[p]["order"] = ArmySystem.ORDER_GARRISON
	assert_eq(ArmyGround.garrison_town(repo, s, p), town, "the town's garrison")
	s.town_seat[town] = p
	var gate_distance := ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, p, s)) + ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, f, s))
	var besieger := _foe(s, f, town_m + Vector2i(gate_distance, 0), "raid_main")
	besieger["order"] = ArmySystem.ORDER_GARRISON
	assert_eq(BattleSystem.town_contact(repo, s, town, f), town, "the deployed column stands at the physical gate")
	s.ai_hosts["raid_main"] = {"mode": "SIEGE", "assault": 0, "target_kind": "town", "target_id": town}
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 0, "a host sitting down to a siege does not fight its garrison every day")
	EnemyAi.ensure_deployments(repo, s)
	assert_true(SiegeSystem.active(repo, s, "raid_main"), "the assault requires a deployed host")
	s.ai_hosts["raid_main"]["assault"] = 1
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1, "its assault is an ordinary battle")
	# a column of the player's that is NOT the besieged town's garrison (a
	# relief in the open) meets the besiegers any day
	var s3 := _campaign(7)
	_place(s3, p, town_m)
	_foe(s3, f, town_m + Vector2i(500, 0), "raid_main")
	s3.ai_hosts["raid_main"] = {"mode": "SIEGE", "assault": 0, "target_kind": "town", "target_id": town}
	assert_eq(ArmyGround.garrison_town(repo, s3, p), "", "standing by off seat and camp: no garrison")
	BattleSystem.settle_day(repo, s3)
	assert_eq(s3.battles.size(), 1, "a relief is fought in the field")
	var s2 := _campaign(7)
	_place(s2, p, town_m)
	_foe(s2, f, town_m + Vector2i(500, 0), "raid_main")
	s2.ai_hosts["raid_main"] = {"mode": "ADVANCE"}
	BattleSystem.settle_day(repo, s2)
	assert_eq(s2.battles.size(), 1, "any other mode meets the enemy as it comes")


## --- a round -------------------------------------------------------------

func test_round_matches_hand_computed_tier() -> void:
	var s := _campaign(7)
	# attackers lose 100 per mille, defenders 50; 600 per mille of the lost wounded
	_one_tier(100, 50, 600, -5, -2)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	# exactly 400 fit men a side (a unit is at most army_split_cap_men)
	assert_false(People.move(repo, s, p, "fit", "dead", _heads(p) - 400, "prior_player_loss").has("error"))
	assert_false(People.move(repo, s, f, "fit", "dead", _heads(f) - 400, "prior_foe_loss").has("error"))
	var morale_p := int(s.regiments[p]["morale"])
	var morale_f := int(s.foes[f]["morale"])
	BattleSystem.settle_day(repo, s)
	# neither marched: the foe attacks
	assert_eq(s.battles[0]["att"], [f])
	# the foe: lost 400 x 100 / 1000 = 40, wounded 40 x 600 / 1000 = 24, dead 16
	assert_eq(People.count(s, f, "wounded"), 24)
	assert_eq(People.count(s, f, "dead"), _heads(f) - 400 + 16)
	assert_eq(int(s.foes[f]["morale"]), morale_f - 5)
	# the player: lost 400 x 50 / 1000 = 20, wounded 12, dead 8
	assert_eq(People.count(s, p, "wounded"), 12)
	assert_eq(People.count(s, p, "dead"), _heads(p) - 400 + 8)
	assert_eq(int(s.regiments[p]["morale"]), morale_p - 2)


func test_round_uses_the_outcome_table_tier_of_the_odds() -> void:
	var s := _campaign(7)
	repo.balance["battle_variance_permille"] = 0.0   # eff = odds
	for k: String in repo.battle_stances:
		repo.battle_stances[k]["retreat_odds_permille"] = 0
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	BattleSystem.detect_contacts(repo, s)
	var steady := func(_c: String) -> String: return "steady"
	var a := BattleSystem.side_power(repo, s, [f], steady, true, [p])
	var d := BattleSystem.side_power(repo, s, [p], steady, false, [f])
	var odds := BattleSystem.odds_permille(a, d)
	var tier := BattleSystem.tier_of(repo, odds)
	var fit_f := ArmySystem.fit_count(repo, s, f)
	var fit_p := ArmySystem.fit_count(repo, s, p)
	var lost_f := BattleSystem.split_losses(fit_f, int(tier["attacker_loss_permille"]), int(tier["wounded_share_permille"]))
	var lost_p := BattleSystem.split_losses(fit_p, int(tier["defender_loss_permille"]), int(tier["wounded_share_permille"]))
	var events := BattleSystem.settle_day(repo, s)
	var round_ev: Dictionary = _kinds(events, "round")[0]
	assert_eq(int(round_ev["odds"]), odds)
	assert_eq(int(round_ev["eff"]), odds, "no dice")
	assert_eq(String(round_ev["tier"]), String(tier["tier"]))
	assert_eq(int(round_ev["att_power"]), a)
	assert_eq(int(round_ev["def_power"]), d)
	assert_eq(People.count(s, f, "wounded"), int(lost_f["wounded"]))
	assert_eq(People.count(s, f, "dead"), int(lost_f["dead"]))
	assert_eq(People.count(s, p, "wounded"), int(lost_p["wounded"]))
	assert_eq(People.count(s, p, "dead"), int(lost_p["dead"]))
	assert_ne(String((round_ev["results"] as Dictionary)[p]["reason"]), "", "every loss carries its reason")


func test_hold_loses_heart_slower() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, -8)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	s.regiments[p]["stance"] = "hold"
	var before := int(s.regiments[p]["morale"])
	BattleSystem.settle_day(repo, s)
	# -8 x morale_decay_permille / 1000, toward zero
	var decay := int(repo.battle_stances["hold"]["morale_decay_permille"])
	@warning_ignore("integer_division")
	assert_eq(int(s.regiments[p]["morale"]), before + (-8 * decay / 1000))
	assert_eq(int(s.regiments[p]["morale"]), before - 4, "hold: 500 per mille of the fall")


## --- the end -------------------------------------------------------------

func test_battle_keeps_its_id_beyond_five_rounds_and_rout_until_separation() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	var id := -1
	for day in 7:
		var events := BattleSystem.settle_day(repo, s)
		assert_eq(_kinds(events, "end").size(), 0)
		assert_eq(s.battles.size(), 1)
		if day == 0:
			id = int(s.battles[0]["id"])
		assert_eq(int(s.battles[0]["id"]), id)
		assert_eq(int(s.battles[0]["rounds"]), day + 1)
		_next_day(s)
	# A rout requests a route; the same battle remains until actual separation.
	var s2 := _campaign(7)
	_one_tier(30, 150, 600, 5, -20, "defender")
	_place(s2, p, _spot(s2))
	_foe(s2, f, _spot(s2) + Vector2i(1000, 0))
	var events := BattleSystem.settle_day(repo, s2)
	assert_eq(s2.battles.size(), 1, "the defender broke but remains exposed in contact")
	assert_eq(_kinds(events, "end").size(), 0)
	var battle: Dictionary = s2.battles[0]
	var routed_id := int(battle["id"])
	assert_eq(String(battle["routed_side"]), "def")
	assert_eq(BattleOrders.kind(battle, "def"), "retreat")
	assert_eq(int(BattleSystem.battle_of(s2, p)["id"]), routed_id)
	assert_eq(ArmySystem.order_of(repo, s2, p), ArmySystem.ORDER_MARCH, "the routed fall back to a town")
	assert_eq(int(s2.regiments[p].get("disengaging", 0)), 1)
	assert_eq(String(s2.foes[f]["order"]), ArmySystem.ORDER_GARRISON, "the winner holds the field")
	var reach := int(repo.bal("battle_contact_km")) * 1000
	s2.regiments[p]["x_m"] = int(s2.foes[f]["x_m"]) - reach - 1
	_next_day(s2)
	var separated := BattleSystem.settle_day(repo, s2)
	assert_eq(s2.battles.size(), 0, "actual separation ends the routed battle")
	var end: Dictionary = _kinds(separated, "end")[0]
	assert_eq(int(end["battle_id"]), routed_id)
	assert_eq(String(end["why"]), "rout_defender")
	assert_eq(String(end["winner"]), "att")
	assert_eq(_kinds(separated, "start").size(), 0, "no replacement encounter")
	assert_eq(_kinds(separated, "round").size(), 0, "no casualties after contact ends")


func test_both_hold_preserves_round_zero_and_rng() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))["battle_plan"] = "hold"
	var rng_before := s.rng.to_dict().duplicate(true)
	for day in 3:
		var events := BattleSystem.settle_day(repo, s)
		assert_eq(_kinds(events, "round").size(), 0)
		assert_eq(int(s.battles[0]["rounds"]), 0)
		assert_eq(s.rng.to_dict(), rng_before)
		_next_day(s)


func test_evade_stance_starts_route_but_stays_exposed_in_contact() -> void:
	var s := _campaign(7)
	_one_tier(50, 50, 600, 0, 0)
	assert_true(bool(repo.battle_stances["evade"]["retreats_on_contact"]), "the table says evade leaves at once")
	var mine := _mine()
	var p: String = mine[0]
	var q: String = mine[1]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_place(s, q, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	s.regiments[p]["stance"] = "evade"
	var events := BattleSystem.settle_day(repo, s)
	assert_gt(People.count(s, p, "wounded"), 0, "it fought the first day's round")
	assert_true(_in_battle(s, p), "the route has not yet carried it clear")
	assert_true(_in_battle(s, q), "its steady neighbour stays")
	assert_eq(ArmySystem.order_of(repo, s, p), ArmySystem.ORDER_MARCH)
	assert_true(bool(s.regiments[p].get("battle_retreat", false)))
	assert_eq((_kinds(events, "round")[0]["left"] as Array).size(), 0)
	_next_day(s)
	BattleSystem.settle_day(repo, s)
	assert_true(_in_battle(s, p), "no movement: still exposed the next day")
	assert_false(s.regiments[p].has("disengaged_until"))


func test_hold_stance_never_retreats() -> void:
	assert_eq(int(repo.battle_stances["hold"]["retreat_odds_permille"]), 0, "the table: hold never retreats")
	assert_false(bool(repo.battle_stances["hold"]["retreats_on_contact"]))
	for stance: String in ["hold", "steady"]:
		var s := _campaign(7)
		repo.balance["battle_variance_permille"] = 0.0
		repo.battle_outcomes.clear()
		repo.battle_outcomes.append({"tier": "hand_made", "eff_min": 0, "eff_max": 1000,
			"attacker_loss_permille": 0, "defender_loss_permille": 0, "wounded_share_permille": 600,
			"attacker_morale": 0, "defender_morale": 0, "rout": "none"})
		var p: String = _mine()[0]
		var f: String = _theirs()[0]
		_place(s, p, _spot(s))
		_foe(s, f, _spot(s) + Vector2i(1000, 0))
		assert_false(People.move(repo, s, p, "fit", "dead", _heads(p) - 20, "hopeless_odds").has("error"))   # a handful left: hopeless odds
		s.regiments[p]["stance"] = stance
		BattleSystem.settle_day(repo, s)
		if stance == "hold":
			assert_true(_in_battle(s, p), "hold stands whatever the odds")
			assert_eq(s.battles.size(), 1)
		else:
			assert_true(_in_battle(s, p), "steady remains exposed until it moves clear")
			assert_true(bool(s.regiments[p].get("battle_retreat", false)))


func test_steady_retreats_below_retreat_odds() -> void:
	var outcomes := {}
	for margin: int in [1, 0]:
		var s := _campaign(7)
		_one_tier(0, 0, 600, 0, 0)
		var p: String = _mine()[0]
		var f: String = _theirs()[0]
		_place(s, p, _spot(s))
		_foe(s, f, _spot(s) + Vector2i(1000, 0))
		s.foes[f]["stance"] = "hold"   # the foe never gives way, whatever the pack's numbers
		var steady := func(_c: String) -> String: return "steady"
		# P4.4d4: the odds the day settles on include the contact factor, which exists only
		# once the battle has begun and its groups stand; open the day first, then read them.
		BattleSystem.prepare_day(repo, s)
		var a := BattleSystem.side_power(repo, s, [f], steady, true, [p])
		var d := BattleSystem.side_power(repo, s, [p], steady, false, [f])
		var mine_odds := 1000 - BattleSystem.odds_permille(a, d)   # the defender's share
		repo.battle_stances["steady"]["retreat_odds_permille"] = mine_odds + margin
		BattleSystem.settle_day(repo, s)
		outcomes[margin] = bool(s.regiments[p].get("battle_retreat", false))
	assert_true(bool(outcomes[1]), "odds one below retreat_odds_permille: withdrawal starts")
	assert_false(bool(outcomes[0]), "odds at retreat_odds_permille: no withdrawal")


func test_no_safe_town_leaves_withdrawing_army_exposed() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	s.regiments[p]["stance"] = "evade"
	# the realm has lost every town: nowhere to fall back to
	var raider := repo.resolve_realm("raider_realm")
	for t: String in repo.burgs:
		s.province_owner[String(repo.burgs[t].get("province_code", ""))] = raider
	BattleSystem.settle_day(repo, s)
	assert_true(_in_battle(s, p), "no destination: it stays in contact")
	assert_ne(ArmySystem.order_of(repo, s, p), ArmySystem.ORDER_MARCH, "no town to march for: it halts")
	assert_false(s.regiments[p].has("disengaged_until"))
	assert_ne(String(s.regiments[p].get("withdrawal_reason", "")), "")
	_next_day(s)
	BattleSystem.settle_day(repo, s)
	assert_true(_in_battle(s, p), "still exposed next morning")
	assert_eq(s.battles.size(), 1)


## --- reinforcements and leaving ------------------------------------------

func test_reinforcement_joins_and_is_capped() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	repo.balance["battle_max_units"] = 2.0
	var mine := _mine()
	var f: String = _theirs()[0]
	var far := _spot(s) + Vector2i(40_000, 0)
	_place(s, mine[0], _spot(s))
	_place(s, mine[1], far)
	_place(s, mine[2], far)
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1)
	var id := int(s.battles[0]["id"])
	assert_false(BattleSystem.join(repo, s, id, mine[0], "def"), "already in it")
	assert_false(BattleSystem.join(repo, s, id + 99, mine[1], "def"), "no such battle")
	assert_false(BattleSystem.join(repo, s, id, mine[1], "att"), "never on the enemy's side")
	# two columns come up to the field
	_place(s, mine[1], _spot(s))
	_place(s, mine[2], _spot(s))
	_next_day(s)
	var events := BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1, "they join; no second battle")
	assert_eq(s.battles[0]["def"], [mine[0], mine[1]], "the first in code order joins; the cap is 2")
	assert_false(_in_battle(s, mine[2]), "the side is full")
	assert_eq(_kinds(events, "join").size(), 1)
	assert_false(BattleSystem.join(repo, s, id, mine[2], "def"), "capped at battle_max_units")


func test_march_away_mid_battle_removes_unit() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var mine := _mine()
	var f: String = _theirs()[0]
	_place(s, mine[0], _spot(s))
	_place(s, mine[1], _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles[0]["def"], [mine[0], mine[1]])
	# a courier's march order lands (CourierSystem._deliver -> set_march)
	var away := ArmySystem.metres_to_pack(repo, _spot(s) - Vector2i(30_000, 0))
	ArmySystem.set_march(repo, s, mine[0], away)
	_next_day(s)
	var events := BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1, "the battle goes on")
	assert_eq(s.battles[0]["def"], [mine[0], mine[1]], "an order alone does not move the column clear")
	assert_eq(ArmySystem.order_of(repo, s, mine[0]), ArmySystem.ORDER_MARCH, "on its own orders")
	assert_eq(int(s.regiments[mine[0]]["dest_x_m"]), _spot(s).x - 30_000, "to where it was sent")
	var left: Array = (_kinds(events, "round")[0] as Dictionary)["left"]
	assert_eq(left.size(), 0, "still within contact range")
	# Place it at its route endpoint to isolate the physical exit condition.
	_next_day(s)
	s.regiments[mine[0]]["x_m"] = _spot(s).x - 30_000
	BattleSystem.settle_day(repo, s)
	assert_false(_in_battle(s, mine[0]), "physical separation completes withdrawal")


func test_battle_with_one_side_emptied_ends() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	_place(s, p, _spot(s))
	_foe(s, f, _spot(s) + Vector2i(1000, 0))
	BattleSystem.settle_day(repo, s)
	ArmySystem.set_march(repo, s, p, ArmySystem.metres_to_pack(repo, _spot(s) - Vector2i(30_000, 0)))
	s.regiments[p]["x_m"] = _spot(s).x - 30_000
	_next_day(s)
	var events := BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 0, "no battle is left with one side")
	var end: Dictionary = _kinds(events, "end")[0]
	assert_eq(String(end["why"]), "emptied")
	assert_eq(String(end["winner"]), "att")
	# a foe that vanishes (taken off by its host) leaves an empty side too
	var s2 := _campaign(7)
	_place(s2, p, _spot(s2))
	_foe(s2, f, _spot(s2) + Vector2i(1000, 0))
	BattleSystem.settle_day(repo, s2)
	s2.foes.erase(f)
	_next_day(s2)
	var ev2 := BattleSystem.settle_day(repo, s2)
	assert_eq(s2.battles.size(), 0)
	assert_eq(_kinds(ev2, "round").size(), 0, "no round with nobody to fight")
	assert_eq(String((_kinds(ev2, "end")[0] as Dictionary)["why"]), "emptied")


## --- determinism and the save ---------------------------------------------

func _five_days(s: GameState) -> Array:
	var all: Array = []
	for n in 5:
		all.append(BattleSystem.settle_day(repo, s))
		_next_day(s)
	return all


func _melee(s: GameState) -> void:
	var mine := _mine()
	var theirs := _theirs()
	_place(s, mine[0], _spot(s))
	_place(s, mine[1], _spot(s))
	_foe(s, theirs[0], _spot(s) + Vector2i(1000, 0))
	_foe(s, theirs[1], _spot(s) + Vector2i(2000, 0))


func test_battle_state_is_deterministic() -> void:
	var s := _campaign(7)
	_melee(s)
	var twin := GameState.from_dict(s.to_dict())
	var a := _five_days(s)
	var b := _five_days(twin)
	assert_gt(_kinds(a[0], "start").size(), 0, "they fought")
	assert_eq(a, b, "the same events")
	assert_eq(s.battles, twin.battles)
	assert_eq(s.regiments, twin.regiments)
	assert_eq(s.foes, twin.foes)
	assert_eq(s.foe_next_id, twin.foe_next_id)


func test_each_engaged_round_draws_once_and_same_day_retry_is_inert() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	_melee(s)
	var expected := Rng.from_dict(s.rng.to_dict())
	var draw := expected.randi_range(0, 999)
	var events := BattleSystem.settle_day(repo, s)
	assert_eq(_kinds(events, "round")[0]["roll"], draw)
	assert_eq(s.rng.to_dict(), expected.to_dict())
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var before := SaveLoad.state_hash(s)
	assert_eq(_kinds(BattleSystem.settle_day(repo, s), "round").size(), 0)
	assert_eq(SaveLoad.state_hash(s), before)
	assert_eq(_kinds(BattleSystem.settle_day(repo, saved), "round").size(), 0)
	assert_eq(saved.rng.to_dict(), expected.to_dict())
	_next_day(s)
	_next_day(saved)
	draw = expected.randi_range(0, 999)
	var next_events := BattleSystem.settle_day(repo, s)
	assert_eq(_kinds(next_events, "round")[0]["roll"], draw)
	assert_eq(next_events, BattleSystem.settle_day(repo, saved))
	assert_eq(s.rng.to_dict(), expected.to_dict())


func _no_floats(v: Variant, where: String) -> void:
	if v is float:
		fail_test("a float in the battle state at " + where)
	elif v is Dictionary:
		for k: Variant in v:
			_no_floats(v[k], "%s.%s" % [where, str(k)])
	elif v is Array:
		for i in (v as Array).size():
			_no_floats(v[i], "%s[%d]" % [where, i])


func test_a_battle_saves_whole_numbers_and_loads_back() -> void:
	var s := _campaign(7)
	_one_tier(0, 0, 600, 0, 0)
	_melee(s)
	BattleSystem.settle_day(repo, s)
	assert_eq(s.battles.size(), 1)
	_no_floats(s.battles, "battles")
	for code: String in s.foes:
		_no_floats(s.foes[code], code)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.battles, s.battles, "the battle survives the save")
	_next_day(s)
	_next_day(back)
	assert_eq(BattleSystem.settle_day(repo, back), BattleSystem.settle_day(repo, s),
		"and fights on the same after it")
