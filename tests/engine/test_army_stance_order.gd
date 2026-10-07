extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## ARMY_STANCE (spec 2026-10-07-enemy-ai-and-battle-design §4.4): a regiment's
## standing battle order, set by courier like ARMY_GARRISON; it takes effect
## from the day AFTER he arrives, in battle or out of it.

var repo: DataRepository


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _mine() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			return String(r["regiment_code"])
	return ""


func _foe_code() -> String:
	return String((repo.raid_hosts[0]["regiments"] as Array)[0])


func _stance(code: String, stance: String) -> ActionRequest:
	return ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": stance})


func test_the_order_is_a_real_order_with_a_cost() -> void:
	assert_true(repo.actions.has("ARMY_STANCE"), "an action row")
	assert_true(repo.order_costs.has("ARMY_STANCE"), "a cost row (invariant 8)")
	assert_true(repo.signatures.any(func(r: Dictionary) -> bool:
		return String(r["action_code"]) == "ARMY_STANCE"), "an opinion signature")


func test_a_stance_must_be_a_row_of_the_table() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := _mine()
	for stance: String in repo.battle_stances:
		assert_eq(actions.validate(_stance(code, stance), s), "", stance + " is a stance")
	assert_string_contains(actions.validate(_stance(code, "berserk"), s), "No such stance")
	assert_string_contains(actions.validate(_stance(code, ""), s), "No such stance")


func test_a_foe_takes_no_stance() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var theirs := _foe_code()
	var label := String(ArmySystem.regiment(repo, theirs)["label"])
	assert_eq(actions.validate(_stance(theirs, "hold"), s), "%s is not yours to command" % label,
		"another realm's regiment")
	# the player's own code standing in the foes' table: only is_foe refuses it
	var code := _mine()
	s.foes[code] = {"morale": 80, "wounded": 0, "supplies": 40, "x_m": 1, "y_m": 1}
	assert_eq(actions.validate(_stance(code, "hold"), s),
		"%s is not yours to command" % String(ArmySystem.regiment(repo, code)["label"]))
	assert_string_contains(actions.validate(_stance("no_such_regiment", "hold"), s), "No such regiment")


func test_the_chest_must_pay_the_courier() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var req := _stance(_mine(), "hold")
	var needs := OrderCosts.gold_of(repo, "ARMY_STANCE") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs - 0.5
	assert_string_contains(actions.validate(req, s), "courier")
	s.metrics["treasury"] = needs
	assert_eq(actions.validate(req, s), "")


func test_the_stance_rides_by_courier_and_waits_for_the_day_to_end() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := _mine()
	assert_eq(String(s.regiments[code]["stance"]), "steady", "a regiment starts steady")
	var before: float = s.metrics["treasury"]
	var out: Dictionary = actions.execute(_stance(code, "hold"), s)
	assert_eq(s.couriers.size(), 1, "one courier rides")
	var c: Dictionary = s.couriers[0]
	assert_eq(String(c["order"]["action_code"]), "ARMY_STANCE")
	assert_eq(String(c["order"]["stance"]), "hold")
	assert_lt(float(s.metrics["treasury"]), before)
	var fee := false
	for e: Dictionary in out.get("effects", []):
		if String(e["metric"]) == "treasury" and String(e["reason"]).begins_with("a courier rides for"):
			fee = true
	assert_true(fee, "the fee is a ledger line with its reason")
	var card := CourierCard.card(repo, s, int(c["id"]))
	assert_eq(String(card["fields"][0][1]), "Stance orders: " + String(repo.battle_stances["hold"]["label"]),
		"his card says what he carries")
	assert_eq(String(s.regiments[code]["stance"]), "steady", "nothing changes until he arrives")
	# a standing order is not a halt: the march's arrival day ignores him
	assert_eq(CourierSystem.pending_for(s, code), {}, "not a march or halt courier")
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_true(s.couriers.is_empty(), "delivered")
	assert_eq(String(s.regiments[code]["stance"]), "steady", "the day he lands still runs on the old stance")
	assert_eq(String(s.regiments[code]["stance_next"]), "hold")
	var receipt: Dictionary = s.missives.back()
	assert_string_contains(str(receipt["facts"]), String(repo.battle_stances["hold"]["label"]),
		"the receipt names the stance")
	BattleSystem.settle_day(repo, s)
	assert_eq(String(s.regiments[code]["stance"]), "hold", "from the next day on")
	assert_false(s.regiments[code].has("stance_next"))


## The day's order as TickEngine runs it (Task 5 hooks BattleSystem there):
## the columns march, the couriers ride, then the battles are settled.
func _end_day(s: GameState) -> Array:
	ArmySystem.march_day(repo, s)
	CourierSystem.ride_day(repo, s)
	return BattleSystem.settle_day(repo, s)


func test_stance_order_lands_after_day_end_and_applies_next_day() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	# a long, bloodless, dice-free battle nobody leaves
	repo.battle_outcomes.clear()
	repo.battle_outcomes.append({"tier": "hand_made", "eff_min": 0, "eff_max": 1000,
		"attacker_loss_permille": 0, "defender_loss_permille": 0, "wounded_share_permille": 600,
		"attacker_morale": 0, "defender_morale": 0, "rout": "none"})
	repo.balance["battle_variance_permille"] = 0.0
	repo.balance["battle_max_rounds"] = 60.0
	for k: String in repo.battle_stances:
		repo.battle_stances[k]["retreat_odds_permille"] = 0
	var p := _mine()
	var f := _foe_code()
	var e: Dictionary = s.regiments[p]
	var at := Vector2i(int(e["x_m"]), int(e["y_m"]))
	var st := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, f))
	st["x_m"] = at.x + 1000
	st["y_m"] = at.y
	st["dest_x_m"] = at.x + 1000
	st["dest_y_m"] = at.y
	s.foes[f] = st
	actions.execute(_stance(p, "hold"), s)
	var steady := func(_c: String) -> String: return "steady"
	var hold := func(_c: String) -> String: return "hold"
	var landed := false
	for n in int(repo.bal("courier_max_days")) + 1:
		ArmySystem.march_day(repo, s)
		CourierSystem.ride_day(repo, s)
		var d_steady := BattleSystem.side_power(repo, s, [p], steady, false, [f])
		var d_hold := BattleSystem.side_power(repo, s, [p], hold, false, [f])
		assert_ne(d_steady, d_hold, "the stance changes the defence")
		landed = s.couriers.is_empty()
		var rounds: Array = BattleSystem.settle_day(repo, s).filter(func(x: Dictionary) -> bool:
			return String(x["kind"]) == "round")
		assert_eq((s.battles[0]["def"] as Array), [p], "the column defends")
		assert_eq(int(rounds[0]["def_power"]), d_steady,
			"day %d (courier %s): the old stance fights" % [n + 1, "lands" if landed else "rides"])
		s.day = mini(s.day + 1, Calendar.DAYS_PER_TICK)
		if landed:
			break
	assert_true(landed, "he arrived")
	ArmySystem.march_day(repo, s)
	CourierSystem.ride_day(repo, s)
	var d_next := BattleSystem.side_power(repo, s, [p], hold, false, [f])
	var ev: Array = BattleSystem.settle_day(repo, s).filter(func(x: Dictionary) -> bool:
		return String(x["kind"]) == "round")
	assert_eq(int(ev[0]["def_power"]), d_next, "the day after he lands, the new stance fights")


func test_an_old_save_regiment_is_steady() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _mine()
	s.regiments[code].erase("stance")
	assert_eq(BattleSystem.stance_of(s, code), "steady", "read as steady")
	var back := GameState.from_dict(s.to_dict())
	ArmySystem.ensure(repo, back)
	assert_eq(String(back.regiments[code]["stance"]), "steady", "and seeded steady")


func test_the_menu_offers_every_stance() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var offered: Array = []
	for row: Dictionary in repo.army_orders:
		if String(row["action_code"]) != "ARMY_STANCE":
			continue
		var params: Dictionary = row["params"]
		offered.append(String(params["stance"]))
		var req := ActionRequest.make("ARMY_STANCE", params.merged({"regiment": _mine()}))
		assert_eq(actions.validate(req, s), "", String(row["label"]) + " is an order the engine takes")
	offered.sort()
	var table: Array = repo.battle_stances.keys()
	table.sort()
	assert_eq(offered, table, "a row for each stance of data/battle_stances.csv")
