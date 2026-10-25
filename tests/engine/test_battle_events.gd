extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 4301)
	var codes := state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var foe := String(state.foes.keys()[0])
	var battle := {"id": 430, "att": [code], "def": [foe], "rounds": 1,
		"place_x_m": 0, "place_y_m": 0}
	state.battles = [battle]
	state.regiments[code].morale = 35
	state.metrics.treasury = 100.0
	state.king_state.x_m = 0
	state.king_state.y_m = 0
	return {"repo": repo, "state": state, "battle": battle, "code": code}

func _fighting_day(state: GameState) -> Dictionary:
	var tx := DayResolution.begin(state.day, false, state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = DayResolution.PHASES.find(tx.phase)
	tx.battle_step = "fighting"
	tx.battle_ids = [430]
	tx.acknowledged_encounters = [430]
	return tx

func test_event_is_saved_and_reward_is_once() -> void:
	var api: GDScript = load("res://scripts/engine/battle_events.gd")
	assert_not_null(api)
	if api == null:
		return
	var f := _fixture()
	f.repo.battle_events = {"ev_31": f.repo.battle_events.ev_31}
	f.repo.battle_events.ev_31.chance_permille = 1000
	f.repo.battle_events.ev_31.weight = 100
	var expected_rng := Rng.from_dict(f.state.rng.to_dict())
	var draw := expected_rng.randi_range(0, 99999)
	var event: Dictionary = api.offer(f.repo, f.state, 430).decision
	assert_eq(event.event_id, "ev_31")
	assert_eq(int(event.draw), draw)
	assert_eq(int(f.state.battle_events[event.token].draw), draw)
	assert_eq(int(f.battle.event_checks[str(f.state.absolute_day())].draw), draw)
	assert_eq(f.state.rng.to_dict(), expected_rng.to_dict(), "one opportunity consumes exactly one shared-stream draw")
	var rng: Dictionary = f.state.rng.to_dict()
	assert_eq(api.offer(f.repo, f.state, 430).decision, event)
	assert_eq(f.state.rng.to_dict(), rng)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(api.offer(f.repo, restored, 430).decision, event)
	assert_eq(restored.rng.to_dict(), rng, "JSON replay consumes no additional opportunity draw")
	var result: Dictionary = api.choose(f.repo, restored, event.token, "rally")
	assert_eq(result.status, "accepted")
	assert_eq(int(restored.regiments[f.code].morale), 43)
	assert_eq(int(restored.metrics.treasury), 93)
	assert_eq(api.choose(f.repo, restored, event.token, "rally").status, "duplicate")
	assert_eq(int(restored.metrics.treasury), 93)
	assert_eq(restored.rng.to_dict(), rng, "reward and duplicate receipt consume no extra draw")

func test_invalid_choice_keeps_event_and_legal_fallback() -> void:
	var api: GDScript = load("res://scripts/engine/battle_events.gd")
	if api == null:
		return
	var f := _fixture()
	f.repo.battle_events = {"ev_31": f.repo.battle_events.ev_31}
	f.repo.battle_events.ev_31.chance_permille = 1000
	var event: Dictionary = api.offer(f.repo, f.state, 430).decision
	f.state.metrics.treasury = 0.0
	assert_eq(api.choose(f.repo, f.state, event.token, "rally").status, "invalid")
	assert_eq(f.state.battle_events[event.token].selected, "")
	assert_eq(api.choose(f.repo, f.state, event.token, "contract").status, "accepted")

func test_no_trigger_and_no_event_do_not_reroll() -> void:
	var api: GDScript = load("res://scripts/engine/battle_events.gd")
	if api == null:
		return
	var f := _fixture()
	f.repo.battle_events = {"ev_36": f.repo.battle_events.ev_36}
	assert_eq(api.offer(f.repo, f.state, 430).status, "none")
	var rng: Dictionary = f.state.rng.to_dict()
	assert_eq(api.offer(f.repo, f.state, 430).status, "none")
	assert_eq(f.state.rng.to_dict(), rng)

func _only(f: Dictionary, id: String) -> void:
	f.repo.battle_events = {id: f.repo.battle_events[id]}
	f.repo.battle_events[id].chance_permille = 1000

func test_reward_respects_reservations_and_reports_actual_clamp() -> void:
	var f := _fixture()
	_only(f, "ev_31")
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	f.state.metrics.treasury = 10.0
	f.state.battle_orders.test = {"status": "pending", "reserved_gold": 4}
	assert_eq(BattleOrders.available_gold(f.state), 6)
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "rally").status, "invalid")
	f.state.battle_orders.clear()
	f.state.regiments[f.code].morale = 96
	var result := BattleEvents.choose(f.repo, f.state, event.token, "rally")
	assert_eq(result.status, "accepted")
	assert_eq(int(f.state.regiments[f.code].morale), 100)
	assert_eq(int(result.receipt.effects[1].delta), 4)

func test_bold_commander_obeys_law_and_hidden_enemy_changes_are_inert() -> void:
	var f := _fixture()
	_only(f, "ev_32")
	var commander := String(f.state.military_rosters[f.code].commander_id)
	assert_ne(commander, "", "fixture must use a real appointed commander")
	var person: Character = f.state.characters[commander]
	person.attributes.boldness = 100
	var battle: Dictionary = f.battle
	battle.parley = {"agreed": {"tactics": {"policy": "restrained"}}}
	f.state.king_state.x_m = 10000000
	var event := {"battle_id": 430, "event_id": "ev_32", "side": "att", "unit": f.code, "commander_id": commander}
	assert_eq(BattleEvents.commander_choice(f.repo, f.state, event), "organize")
	battle.erase("parley")
	var chosen := BattleEvents.commander_choice(f.repo, f.state, event)
	for foe: Dictionary in f.state.foes.values():
		foe.morale = 0
		foe.supplies = 0
		foe.x_m = 99999999
	assert_eq(BattleEvents.commander_choice(f.repo, f.state, event), chosen)
	battle.parley = {"agreed": {"ceasefire": {"policy": "protect"}}}
	var offered := BattleEvents.offer(f.repo, f.state, 430)
	assert_eq(offered.status, "resolved")
	assert_eq(offered.event.selected, "organize")
	assert_eq(offered.event.received_day, -1)

func test_authority_is_frozen_across_king_arrival_departure_and_save() -> void:
	var f := _fixture()
	_only(f, "ev_31")
	var first := BattleEvents.offer(f.repo, f.state, 430)
	assert_eq(first.status, "blocked")
	f.state.king_state.x_m = 10000000
	assert_eq(BattleEvents.offer(f.repo, f.state, 430).status, "blocked")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(BattleEvents.offer(f.repo, loaded, 430).decision, first.decision)
	f = _fixture()
	_only(f, "ev_31")
	f.state.king_state.x_m = 10000000
	var remote := BattleEvents.offer(f.repo, f.state, 430)
	assert_eq(remote.status, "resolved")
	var before := SaveLoad.state_hash(f.state)
	f.state.king_state.x_m = 0
	assert_eq(BattleEvents.offer(f.repo, f.state, 430).event.selected, remote.event.selected)
	assert_ne(SaveLoad.state_hash(f.state), before, "only king position changed")
	assert_eq(f.state.battle_events[remote.event.token].received_day, -1)

func test_local_decision_revalidates_before_consuming_day_token() -> void:
	var f := _fixture()
	_only(f, "ev_31")
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	f.state.day_resolution = _fighting_day(f.state)
	f.state.day_resolution.pending_decision = event
	var engine := TickEngine.new(f.repo)
	f.state.metrics.treasury = 0.0
	assert_eq(engine.resolve_decision(f.state, event.token, "rally").status, "invalid")
	assert_false(event.token in f.state.day_resolution.consumed_tokens)
	assert_eq(engine.resolve_decision(f.state, event.token, "contract").status, "accepted")
	assert_true(event.token in f.state.day_resolution.consumed_tokens)
	assert_eq(engine.resolve_decision(f.state, event.token, "contract").status, "duplicate")

func test_true_join_reserve_changes_only_attacking_contribution() -> void:
	var f := _fixture()
	SuiteData.no_clearance(f.repo) # hand-built event/power fixture, not a deployment test
	_only(f, "ev_33")
	var other := ""
	for code: String in f.state.regiments:
		if code != f.code and ArmySystem.fit_count(f.repo, f.state, code) > 0:
			other = code
			break
	assert_ne(other, "")
	assert_true(BattleSystem.join(f.repo, f.state, 430, other, "att"))
	assert_eq(f.battle.reinforcement_evidence[0].unit, other)
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	assert_eq(event.unit, other)
	var both: Array = f.battle.att
	var total_fit := ArmySystem.fit_count(f.repo, f.state, f.code) + ArmySystem.fit_count(f.repo, f.state, other)
	var before_attack := BattleSystem.side_power(f.repo, f.state, both, Callable(), true)
	var before_defence := BattleSystem.side_power(f.repo, f.state, both, Callable(), false)
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "reserve").status, "accepted")
	var front := BattleSystem.side_power(f.repo, f.state, [f.code], Callable(), true)
	assert_eq(BattleSystem.side_power(f.repo, f.state, both, Callable(), true), front)
	assert_lt(front, before_attack)
	assert_eq(BattleSystem.side_power(f.repo, f.state, both, Callable(), false), before_defence)
	assert_eq(ArmySystem.fit_count(f.repo, f.state, f.code) + ArmySystem.fit_count(f.repo, f.state, other), total_fit)
	BattleOrders.issue(f.repo, f.state, {"id": "commit-reserve", "battle_id": 430, "side": "att", "kind": "attack", "params": {"regiment": f.code}})
	BattleOrders.deliver(f.repo, f.state, "commit-reserve")
	assert_false(f.battle.reserves.has(other))
	assert_gt(BattleSystem.side_power(f.repo, f.state, both, Callable(), true), front)

func test_event_factor_hand_calculation_and_expiry() -> void:
	var f := _fixture()
	f.battle.event_modifiers = [{"unit": f.code, "token": "event-one", "until_day": f.state.absolute_day(), "permille": 1100, "exposure_permille": 1000, "reason": "An event reinforces the line."}]
	var factors := BattleEvents.factors(f.state, f.battle, f.code)
	for factor: Dictionary in factors:
		factor.min_permille = 0
		factor.max_permille = 3000
	assert_eq(BattleStrength.combine(630, factors).power, 693)
	factors.append({"source": "order", "category": "action", "permille": 900, "min_permille": 0, "max_permille": 3000, "reason": "An order diverts the same action category."})
	assert_eq(BattleStrength.combine(630, factors).power, 630)
	f.state.day += 1
	assert_eq(BattleEvents.factors(f.state, f.battle, f.code), [])

func test_wounded_delay_uses_real_march_gate() -> void:
	var f := _fixture()
	_only(f, "ev_34")
	var cohort: Dictionary = f.state.military_cohorts[f.state.military_rosters[f.code].cohort_ids[0]]
	cohort.fit = int(cohort.fit) - 1
	cohort.wounded = int(cohort.wounded) + 1
	f.battle.actions = {"att": {"kind": "retreat"}}
	f.state.regiments[f.code].order = "march"
	f.state.regiments[f.code].dest_x_m = 1000000
	f.state.regiments[f.code].dest_y_m = 1000000
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "wait").status, "accepted")
	assert_false(CampSystem.can_march(f.state, f.code, f.state.absolute_day()))
	assert_false(CampSystem.can_march(f.state, f.code, f.state.absolute_day() + 1))
	assert_true(CampSystem.can_march(f.state, f.code, f.state.absolute_day() + 2))
	assert_eq(int(f.state.regiments[f.code].morale), 33)

func test_abandoned_food_has_single_source_and_collection_conserves_it() -> void:
	var f := _fixture()
	_only(f, "ev_35")
	var foe := String(f.battle.def[0])
	var source: Dictionary = f.state.foes[foe]
	source.supplies = 100
	source.order = "march"
	f.repo.balance.battle_retreat_supply_loss_permille = 250
	var at := BattleSystem._at_m(f.repo, f.state, foe)
	f.state.regiments[f.code].x_m = at.x
	f.state.regiments[f.code].y_m = at.y
	assert_true(BattleSystem._start_retreat(f.repo, f.state, foe, f.battle))
	assert_eq(int(source.supplies), 75)
	var caches: Dictionary = f.battle.abandoned_supplies
	var key := String(caches.keys()[0])
	assert_eq(int(caches[key].amount), 25)
	BattleSystem._start_retreat(f.repo, f.state, foe, f.battle)
	assert_eq(int(caches[key].amount), 25, "retreat replay creates no second cache")
	var capacity := ArmySystem.max_units(f.repo, ArmySystem.supply_use(f.repo, ArmySystem.regiment(f.repo, f.code, f.state), f.state))
	f.state.regiments[f.code].supplies = capacity - 20
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	assert_eq(event.food_source, key)
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "collect").status, "accepted")
	assert_eq(int(f.state.regiments[f.code].supplies), capacity)
	assert_eq(int(caches[key].amount), 5)
	assert_eq(int(source.supplies), 75)
	assert_eq(int(source.supplies) + int(caches[key].amount) + int(f.state.regiments[f.code].supplies), capacity + 80)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(BattleEvents.choose(f.repo, restored, event.token, "collect").status, "duplicate")
	assert_eq(int(restored.regiments[f.code].supplies), capacity)
	f.state.day += 6
	var later: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	var result := BattleEvents.choose(f.repo, f.state, later.token, "destroy")
	assert_eq(result.status, "accepted")
	assert_eq(int(caches[key].amount), 0)
	assert_eq(int(result.receipt.effects[0].destroyed), 5)

func test_capture_revalidates_access_and_protected_withdrawal() -> void:
	var f := _fixture()
	_only(f, "ev_35")
	f.battle.abandoned_supplies = {"cache": {"unit": f.battle.def[0], "side": "def", "x_m": 0, "y_m": 0, "amount": 25, "reason": "Rear guard abandoned actual stores."}}
	f.state.regiments[f.code].x_m = 0
	f.state.regiments[f.code].y_m = 0
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	f.battle.parley = {"agreed": {"safe_withdrawal": {"policy": "protect"}}}
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "collect").status, "invalid")
	assert_eq(int(f.battle.abandoned_supplies.cache.amount), 25)
	# A lawful report/leave choice must remain available if seizure becomes barred.
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "leave").status, "accepted")
	assert_eq(int(f.battle.abandoned_supplies.cache.amount), 25)

func test_reports_route_each_battle_and_only_arrival_publishes_frozen_receipts() -> void:
	var f := _fixture()
	var state: GameState = f.state
	state.day = 10
	state.couriers.clear()
	state.missives.clear()
	state.king_state.x_m = 0
	state.king_state.y_m = 0
	var fights: Array = []
	for id: int in [430, 431]:
		var token := "test-report-%d" % id
		var receipt := {"choice": "organize", "reason": "The commander obeyed the agreement.", "effects": [], "day": 10}
		state.battle_events[token] = {"token": token, "battle_id": id, "event_id": "ev_32", "selected": "organize", "authority": "commander", "received_day": -1, "receipt": receipt}
		fights.append({"kind": "battle_event", "battle_id": id, "token": token, "event_id": "ev_32", "receipt": receipt.duplicate(true),
			"att": [f.code], "def": [f.battle.def[0]], "unit": f.code, "town": "", "place_x_m": 120000, "place_y_m": id - 430})
	var engine := TickEngine.new(f.repo)
	engine._route_battle_reports(state, fights)
	assert_eq(state.couriers.size(), 2)
	assert_eq(state.missives.size(), 0, "remote decisions do not file immediate battle letters")
	assert_eq(state.king_state.get("battle_reports", []), [])
	for courier: Dictionary in state.couriers:
		var payload: Dictionary = CourierSystem.first_order(courier).report
		assert_eq(payload.event_tokens.size(), 1)
		assert_eq(int(payload.battle_id), int(CourierSystem.first_order(courier).battle_id))
		assert_eq(payload.facts.size(), 1, "no other battlefield's fact rides on this courier")
	# Mutation after dispatch cannot rewrite the letter already on the road.
	fights[0].receipt.reason = "CHANGED AFTER DISPATCH"
	var frozen: Dictionary = CourierSystem.first_order(state.couriers[0]).report
	assert_false(str(frozen).contains("CHANGED AFTER DISPATCH"))
	var courier: Dictionary = state.couriers[0]
	state.day = 12
	CourierSystem._deliver(f.repo, state, courier)
	assert_eq(state.king_state.battle_reports.size(), 1)
	assert_eq(state.battle_events["test-report-430"].received_day, 12)
	assert_eq(state.battle_events["test-report-431"].received_day, -1)
	state.battles.clear()
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.battle_events["test-report-430"].receipt.choice, "organize")

func test_report_rides_two_real_days_and_json_resume_does_not_publish_early() -> void:
	var f := _fixture()
	var state: GameState = f.state
	state.day = 10
	state.couriers.clear()
	state.missives.clear()
	state.king_state.x_m = 0
	state.king_state.y_m = 0
	for weather: Dictionary in f.repo.weather_kinds.values():
		weather.speed_permille = 1000
	f.repo.balance.courier_base_km_per_day = 100
	f.repo.road_speed.sea = 1000
	var token := "two-day-report"
	state.battle_events[token] = {"received_day": -1, "selected": "organize", "event_id": "ev_32", "receipt": {"reason": "The commander held the nobles."}}
	var payload := {"battle_id": 430, "day": 10, "event_tokens": [token], "title": "Frozen report", "facts": [MissiveLog.words("decision", "Decision", "The commander held the nobles.")]}
	var courier := CourierSystem.dispatch_king_report(f.repo, state, 430,
		{"place_x_m": 200000, "place_y_m": 0, "report": payload})
	courier.path = [[0, 0, "sea"]]
	assert_eq(CourierSystem.days_left(f.repo, state, courier), 2)
	state.day = 11
	CourierSystem.ride_day(f.repo, state)
	assert_eq(state.missives.size(), 0)
	assert_eq(state.battle_events[token].received_day, -1)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	state.battles.clear()
	state.day = 12
	CourierSystem.ride_day(f.repo, state)
	assert_eq(state.couriers.size(), 0)
	assert_eq(state.missives.size(), 1)
	assert_eq(state.battle_events[token].received_day, 12)
	assert_eq(state.king_state.battle_reports[0].title, "Frozen report")

func test_failed_round_retry_keeps_one_event_and_one_paid_receipt() -> void:
	var f := _fixture()
	_only(f, "ev_31")
	f.battle.town = ""
	f.battle.actions = {"att": {"kind": "attack"}}
	f.state.regiments[f.code].supplies = 100000
	f.state.day_resolution = _fighting_day(f.state)
	var engine := TickEngine.new(f.repo)
	var blocked := engine.resolve_day(f.state)
	assert_eq(blocked.status, "blocked")
	var token := String(blocked.decision.token)
	assert_eq(engine.resolve_decision(f.state, token, "rally").status, "accepted")
	f.state.military_events["battle:430:round:2"] = {"request": {"conflict": true}, "result": {}}
	assert_eq(engine.resolve_day(f.state).status, "error")
	var once := SaveLoad.state_hash(f.state)
	assert_eq(engine.resolve_day(f.state).status, "error")
	assert_eq(SaveLoad.state_hash(f.state), once)
	assert_eq(f.state.day_resolution.journal.battles.size(), 1)
	assert_eq(int(f.state.metrics.treasury), 93)

func test_newly_affordable_choice_revalidates_without_partial_consumption() -> void:
	var f := _fixture()
	_only(f, "ev_31")
	f.state.metrics.treasury = 0.0
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	assert_false("rally" in event.choices)
	f.state.day_resolution = _fighting_day(f.state)
	f.state.day_resolution.pending_decision = event
	f.state.metrics.treasury = 100.0
	var engine := TickEngine.new(f.repo)
	assert_eq(engine.resolve_decision(f.state, event.token, "rally").status, "accepted")
	assert_true(event.token in f.state.day_resolution.consumed_tokens)
	assert_eq(int(f.state.metrics.treasury), 93)

func test_commander_score_hand_values_and_stable_choice_tie() -> void:
	var f := _fixture()
	var commander := String(f.state.military_rosters[f.code].commander_id)
	var person: Character = f.state.characters[commander]
	person.attributes.boldness = 10
	person.attributes.compassion = 0
	person.skills.sk_martial = 5
	var event := {"battle_id": 430, "event_id": "ev_32", "side": "att", "unit": f.code, "known_context": {"morale": 100}}
	assert_eq(BattleEvents.commander_choice(f.repo, f.state, event), "charge", "charge 0+2*10+1*5=25; organize 2-10+5=-3")
	for row: Dictionary in f.repo.battle_event_choices:
		if row.event_id == "ev_32":
			row.score = 0
			row.boldness = 0
			row.martial = 0
			row.compassion = 0
	f.repo.battle_event_choices.reverse()
	assert_eq(BattleEvents.commander_choice(f.repo, f.state, event), "charge", "Stable ID sorts charge before organize when both score zero")

func test_charge_exposure_hand_calculation_and_protection() -> void:
	var f := _fixture()
	for key: String in ["melee", "ranged", "shock", "withdrawal", "pursuit"]:
		f.repo.balance["battle_context_" + key + "_permille"] = 1000
	f.battle.event_modifiers = [{"unit": f.code, "token": "charge", "until_day": f.state.absolute_day(), "permille": 1150, "exposure_permille": 1150, "reason": "Nobles expose the charging line."}]
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "att").loss_permille, 1150, "1000 * 1150 / 1000 = 1150 incoming exposure")
	f.battle.actions = {"att": {"kind": "retreat"}, "def": {"kind": "attack"}}
	f.battle.parley = {"agreed": {"safe_withdrawal": {"policy": "protect"}}}
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "att").loss_permille, 0, "Exposure cannot revive casualties forbidden by safe withdrawal")

func test_missing_or_captured_target_has_contextual_zero_cost_report_fallback() -> void:
	for change: String in ["removed", "captured", "battle_ended"]:
		var f := _fixture()
		_only(f, "ev_31")
		var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
		f.state.day_resolution = _fighting_day(f.state)
		f.state.day_resolution.pending_decision = event
		match change:
			"removed": f.state.regiments.erase(f.code)
			"captured": f.state.regiments[f.code].captured = true
			"battle_ended": f.state.battles.clear()
		var options := BattleEvents.choices_for(f.repo, f.state, event)
		var legal: Array = options.filter(func(option: Dictionary) -> bool: return option.legal)
		assert_eq(options.size(), 1, change + " projects only the terminal report")
		assert_eq(legal.size(), 1, change)
		assert_eq(legal[0].id, "report", change)
		var engine := TickEngine.new(f.repo)
		assert_eq(engine.resolve_decision(f.state, event.token, "rally").status, "invalid")
		assert_eq(int(f.state.metrics.treasury), 100)
		assert_eq(engine.resolve_decision(f.state, event.token, "report").status, "accepted")
		assert_eq(int(f.state.metrics.treasury), 100)
		assert_eq(f.state.battle_events[event.token].receipt.effects[0].cancelled, true)
		assert_true(event.token in f.state.day_resolution.consumed_tokens)

func test_local_charge_law_revoked_keeps_ordered_safe_fallback() -> void:
	var f := _fixture()
	_only(f, "ev_32")
	f.battle.actions = {"att": {"kind": "attack"}}
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	assert_true("charge" in event.choices)
	f.battle.parley = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "charge").status, "invalid")
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "organize").status, "accepted")
	assert_eq(BattleOrders.kind(f.battle, "att"), "hold")

func test_tunnel_authorship_defines_material_reroute_and_declared_risk_boundary() -> void:
	var f := _fixture()
	var choices: Dictionary = {}
	for row: Dictionary in f.repo.battle_event_choices:
		if row.event_id == "ev_36": choices[row.choice_id] = row
	assert_eq(choices.shore.material, "timber")
	assert_gt(int(choices.shore.material_units), 0)
	assert_gt(int(choices.reroute.progress_loss), 0)
	assert_gt(int(choices.continue.risk_permille), 0)
	assert_ne(String(choices.continue.risk_text), "")
	_only(f, "ev_36")
	assert_eq(BattleEvents.offer(f.repo, f.state, 430).status, "none", "P6 connects the real engineering trigger")


func test_destroy_abandoned_food_respects_authored_amount_cap() -> void:
	var f := _fixture()
	_only(f, "ev_35")
	f.battle.abandoned_supplies = {"cache": {"unit": f.battle.def[0], "side": "def", "x_m": 0, "y_m": 0, "amount": 250, "reason": "The departing column abandoned its stores."}}
	f.state.regiments[f.code].x_m = 0
	f.state.regiments[f.code].y_m = 0
	var supplies := int(f.state.regiments[f.code].supplies)
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	var result := BattleEvents.choose(f.repo, f.state, event.token, "destroy")
	assert_eq(result.status, "accepted")
	assert_eq(int(f.battle.abandoned_supplies.cache.amount), 150, "250 cache - 100 authored destruction cap")
	assert_eq(int(result.receipt.effects[0].destroyed), 100)
	assert_eq(int(result.receipt.effects[0].cache_delta), -100)
	assert_eq(int(f.state.regiments[f.code].supplies), supplies, "Destruction credits no food")
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "destroy").status, "duplicate")
	assert_eq(int(f.battle.abandoned_supplies.cache.amount), 150)


func test_noble_charge_cannot_resume_a_routed_line_and_fallback_preserves_retreat() -> void:
	var f := _fixture()
	_only(f, "ev_32")
	f.battle.routed_side = "att"
	f.battle.actions = {"att": {"kind": "retreat", "reason": "The line broke and must withdraw."}}
	f.state.regiments[f.code].battle_retreat = true
	var warrant := {"id": "routed-charge", "battle_id": 430, "side": "att", "kind": "attack", "params": {"regiment": f.code}}
	var refusal := BattleOrders.refusal(f.repo, f.state, warrant)
	assert_ne(refusal, "")
	var event: Dictionary = BattleEvents.offer(f.repo, f.state, 430).decision
	var options := BattleEvents.choices_for(f.repo, f.state, event)
	var charge: Dictionary = options.filter(func(option: Dictionary) -> bool: return option.id == "charge")[0]
	assert_false(charge.legal)
	assert_eq(String(charge.reason), refusal)
	var before := SaveLoad.state_hash(f.state)
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "charge").status, "invalid")
	assert_eq(SaveLoad.state_hash(f.state), before, "The refused charge applies no cost, modifier or action")
	assert_eq(BattleEvents.commander_choice(f.repo, f.state, event), "organize")
	assert_eq(BattleEvents.choose(f.repo, f.state, event.token, "organize").status, "accepted")
	assert_eq(BattleOrders.kind(f.battle, "att"), "retreat")
	assert_true(f.state.regiments[f.code].battle_retreat)
