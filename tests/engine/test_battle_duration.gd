extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
const Play := preload("res://tests/invasion_play.gd")

var repo: DataRepository

func before_each() -> void:
	repo = SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))

func _battle(attack := true) -> GameState:
	var state := Scenario.contact(repo, 10)
	BattleSystem.detect_contacts(repo, state)
	state.battles[0]["actions"] = {"att": {"kind": "attack" if attack else "hold"}, "def": {"kind": "hold"}}
	for entry: Dictionary in state.regiments.values() + state.foes.values():
		entry["morale"] = 80
		entry["supplies"] = 10000
	return state

func test_both_hold_for_three_days_without_rounds_or_rng_but_eat() -> void:
	var state := _battle(false)
	var id := int(state.battles[0]["id"])
	var before := state.rng.to_dict()
	var code := String(state.battles[0]["def"][0])
	var food := int(state.regiments[code]["supplies"])
	for day: int in 3:
		BattleSystem.settle_day(repo, state)
		ArmySystem.eat_day(repo, state)
		state.day += 1
	assert_eq(int(state.battles[0]["rounds"]), 0)
	assert_eq(int(state.battles[0]["id"]), id)
	assert_eq(state.rng.to_dict(), before)
	assert_lt(int(state.regiments[code]["supplies"]), food)
	state.battles[0]["actions"]["att"] = {"kind": "attack"}
	var events := BattleSystem.settle_day(repo, state)
	assert_eq(int(state.battles[0]["rounds"]), 1)
	assert_eq(int(state.battles[0]["id"]), id)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e["kind"] == "start").size(), 0)

func test_one_saved_rng_draw_per_round_and_same_day_retry_is_inert() -> void:
	var state := _battle()
	var expected := Rng.from_dict(state.rng.to_dict())
	var draw := expected.randi_range(0, 999)
	var events := BattleSystem.settle_day(repo, state)
	var round_event: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["kind"] == "round")[0]
	assert_eq(int(round_event["roll"]), draw)
	assert_eq(state.rng.to_dict(), expected.to_dict())
	var held := SaveLoad.state_hash(state)
	BattleSystem.settle_day(repo, state)
	assert_eq(SaveLoad.state_hash(state), held)
	var twin := Scenario.roundtrip(state)
	state.day += 1
	twin.day += 1
	assert_eq(BattleSystem.settle_day(repo, twin), BattleSystem.settle_day(repo, state))
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(state))

func test_supply_supported_engagement_continues_beyond_five_days_same_id() -> void:
	var state := _battle()
	repo.battle_outcomes[0]["attacker_loss_permille"] = 0
	repo.battle_outcomes[0]["defender_loss_permille"] = 0
	var id := int(state.battles[0]["id"])
	for day: int in 7:
		BattleSystem.settle_day(repo, state)
		assert_false(state.battles.is_empty(), "no round-count termination")
		if state.battles.is_empty():
			return
		assert_eq(int(state.battles[0]["id"]), id)
		state.day += 1
	assert_eq(int(state.battles[0]["rounds"]), 7)

func test_morale_collapse_ends_without_a_round_cap() -> void:
	var state := _battle()
	var b: Dictionary = state.battles[0]
	repo.battle_outcomes[0]["attacker_morale"] = -15
	repo.battle_outcomes[0]["defender_morale"] = 0
	BattleSystem._stored(state, String(b["att"][0]))["morale"] = 70
	var ended: Array = []
	for day: int in 4:
		ended = BattleSystem.settle_day(repo, state)
		if day < 3:
			assert_false(state.battles.is_empty())
		state.day += 1
	assert_eq(String(b.get("routed_side", "")), "att", "70 -> 55 -> 40 -> 25 -> 10: breaks on day four at threshold20")
	assert_eq(int(b["rounds"]), 4)
	assert_eq(BattleOrders.kind(b, "att"), "retreat")

func test_continue_acknowledges_contact_without_issuing_attack() -> void:
	var state := Scenario.contact(repo, 10)
	for entry: Dictionary in state.foes.values():
		entry.erase("battle_plan")
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(state)
	assert_eq(blocked["status"], "blocked")
	var id := int(blocked["decision"]["battle_id"])
	engine.resolve_decision(state, String(blocked["decision"]["token"]), "continue")
	assert_eq(engine.resolve_day(state)["status"], "complete")
	assert_eq(int(BattleSystem.battle_by_id(state, id)["rounds"]), 0)
	assert_eq(BattleOrders.kind(state.battles[0], "att"), "hold")

func test_failed_round_reuses_saved_draw_without_charging_attack_twice() -> void:
	var state := _battle()
	var battle: Dictionary = state.battles[0]
	var code := String(battle["def"][0])
	var cohort := String(state.military_rosters[code]["cohort_ids"][0])
	var origin := String(state.military_cohorts[cohort]["source_population_field"])
	state.military_cohorts[cohort]["source_population_field"] = "invalid"
	var food := int(BattleSystem._stored(state, String(battle["att"][0]))["supplies"])
	var failed := BattleSystem.step_battle(repo, state, int(battle["id"]))
	assert_eq(failed["status"], "error")
	assert_eq(int(battle["rounds"]), 0)
	assert_eq(int(BattleSystem._stored(state, String(battle["att"][0]))["supplies"]), food)
	var held := state.rng.to_dict()
	var pending: Dictionary = battle.get("pending_round", {}).duplicate(true)
	BattleSystem.step_battle(repo, state, int(battle["id"]))
	assert_eq(state.rng.to_dict(), held)
	assert_eq(battle.get("pending_round"), pending)
	var twin := Scenario.roundtrip(state)
	state.military_cohorts[cohort]["source_population_field"] = origin
	twin.military_cohorts[cohort]["source_population_field"] = origin
	assert_eq(BattleSystem.step_battle(repo, twin, int(battle["id"])), BattleSystem.step_battle(repo, state, int(battle["id"])))
	assert_eq(state.rng.to_dict(), held)
	assert_eq(SaveLoad.state_hash(state), SaveLoad.state_hash(twin))

const People := preload("res://tests/fixtures/military_people.gd")

func _force(state: GameState, code: String, heads: int, morale: int, token: String) -> void:
	var fit := MilitaryRoster.fit(state, code)
	if fit > 0:
		assert_false(People.move(repo, state, code, "fit", "released", fit, token + ":release").has("error"))
	assert_false(People.enlist(repo, state, code, heads, token + ":enlist").has("error"))
	for arm: String in repo.world_table("military", "unit_types"):
		state.army_roster[code][arm] = "0"
	state.army_roster[code]["infantry"] = str(heads)
	var entry := BattleSystem._stored(state, code)
	entry["morale"] = morale
	entry["training"] = 60
	entry["supplies"] = 10000
	entry["camp_state"] = {"phase": CampSystem.NONE}

func _benchmark(label: String, size: int, morale: int, reinforce := false) -> Dictionary:
	repo = SuiteData.no_clearance(SuiteData.flat_ground(SuiteData.repo()))
	var outcomes := repo.battle_outcomes.duplicate(true)
	var state := _battle()
	repo.battle_outcomes = outcomes
	repo.balance["battle_variance_permille"] = 0
	repo.balance["army_height_bonus_cap_permille"] = 0
	for row: Dictionary in repo.army_terrain.values():
		row["attack"] = 1000
		row["defend"] = 1000
	for row: Dictionary in repo.battle_formations.values():
		for key: String in ["attack_permille", "defence_permille", "flank_permille", "missile_permille"]:
			row[key] = 1000
	var battle: Dictionary = state.battles[0]
	var id := int(battle["id"])
	var attacker := String(battle["att"][0])
	var defender := String(battle["def"][0])
	_force(state, attacker, size, morale, label + ":att")
	_force(state, defender, 1000, morale, label + ":def")
	var start := state.absolute_day()
	var raw: Array = []
	for day: int in 15:
		if day > 0:
			ArmySystem.march_day(repo, state)
		if reinforce and day == 2:
			# Fresh units on both sides preserve equal numbers; their actual morale extends resistance.
			for side: String in ["att", "def"]:
				var is_foe := side == "att"
				var reserve := ""
				if is_foe:
					for host: Dictionary in repo.raid_hosts:
						for code: String in EnemyAi.host_units(repo, state, host):
							if code != attacker:
								reserve = code
				else:
					for code: String in Play.land_regiments(repo, 400):
						if code != defender:
							reserve = code
				if is_foe:
					state.foes[reserve] = ArmySystem.starting_state(repo, state.army_roster[reserve])
				_force(state, reserve, 1000, 100, label + ":reserve:" + side)
				var at := BattleSystem._at_m(repo, state, attacker if is_foe else defender)
				Play.place(repo, state, reserve, at, ArmySystem.ORDER_STANDBY)
				assert_true(BattleSystem.join(repo, state, id, reserve, side))
		var events := BattleSystem.settle_day(repo, state)
		for event: Dictionary in events:
			if event["kind"] == "round":
				raw.append({"day": state.absolute_day(), "round": event["round"], "losses": event["results"], "costs": event["costs"], "tier": event["tier"]})
		if state.battles.is_empty():
			var summary := {"case": label, "contact_day": start, "end_day": state.absolute_day(), "days": day + 1,
				"food": {"att": state.foes[attacker]["supplies"], "def": state.regiments[defender]["supplies"]}, "raw": raw}
			print("P42_DURATION ", JSON.stringify(summary))
			return summary
		assert_eq(int(state.battles[0]["id"]), id)
		ArmySystem.eat_day(repo, state)
		for code: String in state.foes:
			ArmySystem.eat_one(repo, state, state.army_roster[code], state.foes[code])
		state.day += 1
	return {"days": 16}

func test_fixed_seed_duration_benchmarks_use_depletion_not_round_count() -> void:
	var equal := _benchmark("equal", 1000, 70)
	var larger := _benchmark("larger", 2000, 70)
	var supplied := _benchmark("supplied_high_morale", 1000, 100)
	var reinforced := _benchmark("third_day_reinforcement", 1000, 70, true)
	var advantage := _benchmark("overwhelming", 6000, 70)
	assert_between(int(equal["days"]), 3, 5)
	assert_between(int(larger["days"]), 3, 5)
	assert_gt(int(supplied["days"]), 5)
	assert_gt(int(reinforced["days"]), 5)
	assert_lt(int(advantage["days"]), int(equal["days"]))

func test_withdrawal_walks_real_route_through_camp_gate_before_leaving() -> void:
	var state := _battle()
	var battle: Dictionary = state.battles[0]
	var code := String(battle["def"][0])
	var entry := BattleSystem._stored(state, code)
	var origin := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	entry["camp_state"] = {"phase": CampSystem.CAMPED, "site": {"x_m": origin.x, "y_m": origin.y}}
	entry["order"] = ArmySystem.ORDER_MARCH
	ArmySystem.aim_entry(repo, entry, origin + Vector2i(100000, 0))
	CampSystem.request_departure(state, code, state.absolute_day(), true)
	battle["actions"]["def"] = {"kind": "retreat"}
	var id := int(battle["id"])
	BattleSystem.settle_day(repo, state)
	assert_true(code in battle["def"], "ordering retreat does not remove contact")
	var exposed := int(entry["morale"])
	ArmySystem.march_day(repo, state)
	assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])), origin)
	state.day += 1
	ArmySystem.march_day(repo, state)
	assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])), origin, "one full packing day")
	state.day += 1
	ArmySystem.march_day(repo, state)
	assert_ne(Vector2i(int(entry["x_m"]), int(entry["y_m"])), origin, "retreating battle member actually marches")
	BattleSystem.settle_day(repo, state)
	assert_true(BattleSystem.battle_by_id(state, id).is_empty(), "actual separation ends this battle")
	assert_lte(int(entry["morale"]), exposed)

func test_context_losses_and_protected_withdrawal_hand_values() -> void:
	var state := _battle()
	var b: Dictionary = state.battles[0]
	b["actions"]["def"] = {"kind": "retreat"}
	b["parley"]["agreed"].erase("safe_withdrawal")
	b["parley"]["agreed"].erase("tactics")
	for code: String in b["att"]:
		if state.foes.has(code):
			state.foes[code]["received_laws"] = {"battle_tactics": {"value": "unrestricted", "decree_id": 0}}
	var context := BattleSystem.combat_context(repo, state, b, "def")
	assert_eq(context["kind"], "pursuit")
	assert_eq(context["loss_permille"], 1500)
	# 150 *1500/1000 =225; 333 *225/1000 =74; 74 *600/1000 =44 wounded,30 dead.
	assert_eq(BattleSystem.split_losses(333, 225, 600), {"lost": 74, "wounded": 44, "dead": 30})
	b["parley"]["agreed"]["safe_withdrawal"] = {"policy": "protect", "until_day": 0}
	assert_eq(BattleSystem.combat_context(repo, state, b, "def")["loss_permille"], 0)
	b["parley"]["agreed"].erase("safe_withdrawal")
	b["actions"]["att"] = {"kind": "hold"}
	assert_eq(BattleSystem.combat_context(repo, state, b, "def")["loss_permille"], 600)

func test_rout_keeps_same_battle_until_actual_separation() -> void:
	var state := _battle()
	var b: Dictionary = state.battles[0]
	repo.battle_outcomes[0]["rout"] = "attacker"
	var id := int(b["id"])
	BattleSystem.settle_day(repo, state)
	assert_false(BattleSystem.battle_by_id(state, id).is_empty(), "routing still needs a real exit")
	state.day += 1
	BattleSystem.prepare_day(repo, state)
	assert_eq(state.battles.size(), 1)
	assert_eq(int(state.battles[0]["id"]), id, "no fresh encounter with the same touching armies")

func test_zero_morale_holding_side_collapses_without_a_combat_round() -> void:
	var state := _battle(false)
	var b: Dictionary = state.battles[0]
	for code: String in b["att"]:
		BattleSystem._stored(state, code)["morale"] = 0
	var rng := state.rng.to_dict()
	BattleSystem.settle_day(repo, state)
	assert_eq(String(b.get("routed_side", "")), "att")
	assert_eq(BattleOrders.kind(b, "att"), "retreat")
	assert_eq(int(b["rounds"]), 0)
	assert_eq(state.rng.to_dict(), rng)

func test_empty_attack_stores_fall_back_without_free_bonus_or_draw() -> void:
	var state := _battle()
	var b: Dictionary = state.battles[0]
	for code: String in b["att"]:
		BattleSystem._stored(state, code)["supplies"] = 0
	var before := state.rng.to_dict()
	BattleSystem.settle_day(repo, state)
	assert_eq(BattleOrders.kind(b, "att"), "hold")
	assert_string_contains(String(b["actions"]["att"]["reason"]), "insufficient")
	assert_eq(int(b["rounds"]), 0)
	assert_eq(state.rng.to_dict(), before)

func test_defender_can_attack_while_original_attacker_holds() -> void:
	var state := _battle(false)
	var b: Dictionary = state.battles[0]
	b["actions"]["def"] = {"kind": "attack"}
	var stance := func(code: String) -> String: return BattleSystem.stance_of(state, code)
	var expect_att := BattleSystem.side_power(repo, state, b["att"], stance, false, b["def"])
	var expect_def := BattleSystem.side_power(repo, state, b["def"], stance, true, b["att"])
	var rounds := BattleSystem.settle_day(repo, state).filter(func(e: Dictionary) -> bool: return e["kind"] == "round")
	assert_eq(rounds.size(), 1)
	assert_eq(int(rounds[0]["att_power"]), expect_att)
	assert_eq(int(rounds[0]["def_power"]), expect_def)

func test_withdrawal_has_no_straight_line_fallback_across_water() -> void:
	var state := _battle()
	var b: Dictionary = state.battles[0]
	var code := String(b["def"][0])
	var enemy := String(b["att"][0])
	Play.place(repo, state, code, Vector2i(1000, 1000), ArmySystem.ORDER_STANDBY)
	Play.place(repo, state, enemy, Vector2i(2000, 1000), ArmySystem.ORDER_STANDBY)
	var town := ""
	for candidate: String in repo.burgs:
		if MapOwnership.owner_of(repo, state, String(repo.burgs[candidate]["province_code"])) == repo.resolve_realm("player_realm"):
			town = candidate
			break
	assert_ne(town, "")
	var target: Dictionary = repo.burgs[town].duplicate(true)
	var pack := ArmySystem.metres_to_pack(repo, Vector2i(21000, 1000))
	target["x"] = pack.x
	target["y"] = pack.y
	repo.burgs = {town: target}
	repo.balance["army_march_grid_px"] = 1
	var grid := MarchPath.build(repo, 3, 1, 10000, PackedByteArray([0, 255, 0]))
	MarchPath.use(repo, grid)
	assert_false(BattleSystem._start_retreat(repo, state, code, b))
	assert_ne(String(state.regiments[code]["order"]), ArmySystem.ORDER_MARCH)
	assert_false(bool(state.regiments[code].get("battle_retreat", false)))
	assert_string_contains(String(state.regiments[code].get("withdrawal_reason", "")), "No reachable")

func test_a_blocked_withdrawal_replans_without_charging_its_cost_again() -> void:
	var state := _battle()
	var b: Dictionary = state.battles[0]
	var code := String(b["def"][0])
	var entry := BattleSystem._stored(state, code)
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	ArmySystem.aim_entry(repo, entry, here + Vector2i(100000, 0))
	assert_true(BattleSystem._start_retreat(repo, state, code, b))
	var food := int(entry["supplies"])
	var morale := int(entry["morale"])
	BattleSystem._halt(state, code)
	assert_true(BattleSystem._start_retreat(repo, state, code, b))
	assert_eq(String(entry["order"]), ArmySystem.ORDER_MARCH, "a clearance halt must not permanently strand a withdrawal")
	assert_eq(int(entry["supplies"]), food)
	assert_eq(int(entry["morale"]), morale)
