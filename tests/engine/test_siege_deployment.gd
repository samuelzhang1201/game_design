extends GutTest
const People := preload("res://tests/fixtures/military_people.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
var repo: DataRepository
var s: GameState
var host: String
var town: String
var first: String
var late: String
var guard: String

func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	repo.balance["ai_retreat_supply_days"] = 0
	repo.balance["siege_assault_days"] = 99
	s = SuiteData.campaign(repo, 7)
	s.tick = 1
	s.day = 10
	host = Play.host(repo, "main")
	var units := EnemyAi.live_regiments(repo, s, host)
	first = units[0]
	late = units[1]
	guard = Play.land_regiments(repo)[0]
	town = TownStores.depot(repo, s)
	var at := Play.town_m(repo, town)
	Play.park_army(repo, s, at + Vector2i(500000, 0))
	for c: String in s.foes.keys():
		if c not in [first, late]:
			s.foes.erase(c)
	for h: String in s.ai_hosts.keys():
		if h != host:
			s.ai_hosts.erase(h)
	Play.place(repo, s, guard, at, ArmySystem.ORDER_GARRISON)
	Play.place(repo, s, first, at + Vector2i(3000, 0), ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, late, at + Vector2i(46000, 0), ArmySystem.ORDER_STANDBY)
	for c: String in [first, late]:
		s.foes[c]["supplies"] = 100000
		s.foes[c]["morale"] = 100
	s.ai_hosts[host]["mode"] = "ADVANCE"
	s.ai_hosts[host]["target_kind"] = "town"
	s.ai_hosts[host]["target_id"] = town

func test_columns_still_on_the_road_do_not_create_a_siege_or_blockade() -> void:
	Play.place(repo, s, first, Play.town_m(repo, town) + Vector2i(46000, 0), ArmySystem.ORDER_STANDBY)
	EnemyAi.step_day(repo, s)
	assert_eq(s.ai_hosts[host]["mode"], "ADVANCE")
	assert_false(SiegeSystem.besieged(repo, s, town))
	assert_true(SiegeSystem.capture(repo, s, host).is_empty())
	assert_true(SupplyLines.siege_cut(repo, s, guard).is_empty())
	SiegeSystem.settle_day(repo, s)
	assert_eq(int(s.ai_hosts[host].get("siege_days", 0)), 0)
	assert_eq(int(s.ai_hosts[host].get("siege_progress", 0)), 0)
	assert_eq(String(s.foes[late]["order"]), ArmySystem.ORDER_MARCH)
	assert_true(BattleSystem.prepare_day(repo, s).is_empty())

func test_established_deployment_survives_json_and_later_arrivals() -> void:
	EnemyAi.step_day(repo, s)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.ai_hosts, s.ai_hosts)
	var before := back.ai_hosts.duplicate(true)
	EnemyAi.ensure_deployments(repo, back)
	assert_eq(back.ai_hosts, before, "an existing deployment is not refrozen on restore")
	s = back
	Play.place(repo, s, late, Play.town_m(repo, town) + Vector2i(-3000, 0), ArmySystem.ORDER_STANDBY)
	s.day += 1
	EnemyAi.step_day(repo, s)
	assert_eq(s.ai_hosts[host]["mode"], "SIEGE")
	assert_true(SiegeSystem.besieged(repo, s, town))
	assert_eq(int(s.ai_hosts[host].get("assault", 0)), 0)

func test_destroyed_only_deployed_column_cannot_maintain_a_blockade() -> void:
	EnemyAi.step_day(repo, s)
	assert_true(SiegeSystem.besieged(repo, s, town))
	assert_false(People.move(repo, s, first, "fit", "dead", MilitaryRoster.fit(s, first), "deployed-slain").has("error"))
	assert_false(SiegeSystem.besieged(repo, s, town))
	assert_eq(SiegeSystem.attack_power(repo, s, town), 0)

func test_legacy_siege_without_deployed_columns_preserves_history_but_pauses() -> void:
	Play.place(repo, s, first, Play.town_m(repo, town) + Vector2i(46000, 0), ArmySystem.ORDER_STANDBY)
	s.ai_hosts[host]["mode"] = "SIEGE"
	s.ai_hosts[host]["siege_progress"] = 250
	s.ai_hosts[host]["siege_days"] = 4
	s.ai_hosts[host]["assault"] = 1
	EnemyAi.step_day(repo, s)
	assert_eq(s.ai_hosts[host]["mode"], "DEPLOYING")
	assert_eq(int(s.ai_hosts[host]["siege_progress"]), 250)
	assert_eq(int(s.ai_hosts[host]["siege_days"]), 4)
	assert_eq(int(s.ai_hosts[host]["assault"]), 0)
	assert_false(SiegeSystem.besieged(repo, s, town))

func test_deployed_columns_can_be_attacked_in_the_field() -> void:
	EnemyAi.step_day(repo, s)
	var relief := String(Play.land_regiments(repo)[1])
	Play.place(repo, s, relief, Play.town_m(repo, town) + Vector2i(6000, 0), ArmySystem.ORDER_STANDBY)
	var events := BattleSystem.prepare_day(repo, s)
	assert_false(events.is_empty())
	assert_false(BattleSystem.battle_of(s, relief).is_empty())

func _plain_power(code: String, men: int) -> void:
	var row: Dictionary = s.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		row[arm] = "0"
	row["infantry"] = str(men)
	assert_false(People.move(repo, s, code, "fit", "released", MilitaryRoster.fit(s, code), "resize:" + code).has("error"))
	assert_false(People.enlist(repo, s, code, men, "raise:" + code).has("error"))

func test_only_arrived_personnel_contribute_and_late_reinforcements_do_not_reset_deployment() -> void:
	repo.army_matchups.clear()
	repo.army_terrain.clear()
	repo.army_town_defence.clear()
	repo.balance["army_training_base_permille"] = 1000
	repo.balance["army_training_step_permille"] = 0
	repo.balance["army_morale_base_permille"] = 1000
	repo.balance["army_morale_step_permille"] = 0
	repo.balance["siege_rate"] = 100
	_plain_power(first, 100)
	_plain_power(late, 200)
	_plain_power(guard, 200)
	TownStores.add(s, town, "crown", 100000)
	TownStores.sync_metrics(repo, s)
	EnemyAi.step_day(repo, s)
	SiegeSystem.settle_day(repo, s)
	assert_eq(int(s.ai_hosts[host]["siege_progress"]), 33)
	Play.place(repo, s, late, Play.town_m(repo, town) + Vector2i(-3000, 0), ArmySystem.ORDER_STANDBY)
	s.day += 1
	EnemyAi.step_day(repo, s)
	assert_eq(SiegeSystem.attack_power(repo, s, town), 300)
	assert_eq(SiegeSystem.defend_power(repo, s, town), 200)
	SiegeSystem.settle_day(repo, s)
	assert_eq(int(s.ai_hosts[host]["siege_progress"]), 93)
	var deployment: Dictionary = s.ai_hosts[host]["deployment"].duplicate(true)
	var reserve := "deployment_reinforcement"
	s.army_roster[reserve] = s.army_roster[first].duplicate(true)
	s.army_roster[reserve]["regiment_code"] = reserve
	s.foes[reserve] = s.foes[first].duplicate(true)
	_plain_power(reserve, 1000)
	Play.place(repo, s, reserve, Play.town_m(repo, town) + Vector2i(46000, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(SiegeSystem.attack_power(repo, s, town), 300, "remote reinforcement contributes no power")
	assert_eq(s.ai_hosts[host]["deployment"], deployment)
	Play.place(repo, s, reserve, Play.town_m(repo, town) + Vector2i(0, 3000), ArmySystem.ORDER_GARRISON)
	s.day += 1
	EnemyAi.step_day(repo, s)
	assert_eq(s.ai_hosts[host]["mode"], "SIEGE")
	assert_eq(SiegeSystem.attack_power(repo, s, town), 1300)
	SiegeSystem.settle_day(repo, s)
	assert_eq(int(s.ai_hosts[host]["siege_progress"]), 179, "33 + 60 + floor(100*1300/1500)")
	assert_eq(s.ai_hosts[host]["deployment"], deployment)

func test_legacy_restore_keeps_transaction_cursor_and_defers_assault() -> void:
	Play.place(repo, s, first, Play.town_m(repo, town) + Vector2i(46000, 0), ArmySystem.ORDER_STANDBY)
	s.ai_hosts[host]["mode"] = "SIEGE"
	s.ai_hosts[host]["siege_progress"] = 250
	s.ai_hosts[host]["siege_days"] = 4
	s.ai_hosts[host]["assault"] = 1
	s.day_resolution = {"phase": "battles", "battle_index": 2, "consumed_tokens": ["known"]}
	var cursor := s.day_resolution.duplicate(true)
	EnemyAi.ensure_deployments(repo, s)
	assert_eq(s.day_resolution, cursor)
	assert_eq(int(s.ai_hosts[host]["assault_due"]), 1)
	Play.place(repo, s, late, Play.town_m(repo, town) + Vector2i(-3000, 0), ArmySystem.ORDER_STANDBY)
	s.day += 1
	EnemyAi.step_day(repo, s)
	assert_eq(int(s.ai_hosts[host]["assault"]), 0, "deployment completed before battles; no immediate assault")
	assert_true(BattleSystem.prepare_day(repo, s).is_empty())
	assert_eq(int(s.ai_hosts[host]["siege_progress"]), 250)
	assert_eq(int(s.ai_hosts[host]["siege_days"]), 4)
	SiegeSystem.settle_day(repo, s)
	assert_eq(int(s.ai_hosts[host]["assault"]), 1, "owed assault armed after today's battles")
	assert_eq(s.day_resolution, cursor)

func test_completed_deployment_with_no_column_present_cannot_blockade_or_capture() -> void:
	Play.place(repo, s, late, Play.town_m(repo, town) + Vector2i(-3000, 0), ArmySystem.ORDER_STANDBY)
	EnemyAi.step_day(repo, s)
	assert_true(SiegeSystem.besieged(repo, s, town))
	for code: String in [first, late]:
		Play.place(repo, s, code, Play.town_m(repo, town) + Vector2i(46000, 0), ArmySystem.ORDER_STANDBY)
	assert_false(SiegeSystem.besieged(repo, s, town))
	assert_true(SupplyLines.siege_cut(repo, s, guard).is_empty())
	s.ai_hosts[host]["siege_progress"] = 1000
	assert_true(SiegeSystem.capture(repo, s, host).is_empty())
	var days := int(s.ai_hosts[host].get("siege_days", 0))
	SiegeSystem.settle_day(repo, s)
	assert_eq(int(s.ai_hosts[host].get("siege_days", 0)), days)

func test_routing_an_outer_camp_is_a_field_victory_not_a_breach_of_the_town() -> void:
	var at := Play.town_m(repo, town)
	var outer := String(Play.land_regiments(repo)[1])
	Play.place(repo, s, outer, at + Vector2i(12000, 0), ArmySystem.ORDER_GARRISON)
	s.regiments[outer]["camp_town"] = town
	Play.place(repo, s, first, at + Vector2i(15000, 0), ArmySystem.ORDER_GARRISON)
	EnemyAi.step_day(repo, s)
	assert_eq(s.ai_hosts[host]["mode"], "SIEGE")
	assert_eq(BattleSystem.town_contact(repo, s, town, first), "", "the attacker has not reached the town's actual defences")
	s.ai_hosts[host]["assault"] = 1
	var rout: Dictionary = {}
	for row: Dictionary in repo.battle_outcomes:
		if String(row["tier"]) == "defender_routed":
			rout = row.duplicate(true)
	rout["eff_min"] = 0
	rout["eff_max"] = 1000
	repo.battle_outcomes = [rout]
	var events := BattleSystem.settle_day(repo, s)
	var rounds := 0
	for event: Dictionary in events:
		if String(event.get("kind", "")) == "round":
			rounds += 1
			assert_eq(String(event["tier"]), "defender_routed")
			assert_eq(String(event["town"]), "", "a camp skirmish is not a wall assault")
	assert_eq(rounds, 1)
	assert_true(guard in EnemyAi.garrison_of(repo, s, town), "the town's own defender still holds")
	var siege_events := SiegeSystem.settle_day(repo, s, events)
	assert_true(siege_events.filter(func(e: Dictionary) -> bool: return e.get("kind", "") == "siege_fallen").is_empty())
	assert_true(EnemyAi.target_held(repo, s, "town", town))
	assert_lt(int(s.ai_hosts[host]["siege_progress"]), 1000)

func test_a_column_held_in_a_field_battle_cannot_remotely_occupy_the_empty_town() -> void:
	EnemyAi.step_day(repo, s)
	assert_eq(s.ai_hosts[host]["mode"], "SIEGE")
	var at := Play.town_m(repo, town)
	Play.place(repo, s, first, at + Vector2i(15000, 0), ArmySystem.ORDER_GARRISON)
	s.foes.erase(late)
	EnemyAi.step_day(repo, s)
	var relief := String(Play.land_regiments(repo)[1])
	Play.place(repo, s, relief, at + Vector2i(16000, 0), ArmySystem.ORDER_STANDBY)
	BattleSystem.prepare_day(repo, s)
	assert_false(BattleSystem.battle_of(s, first).is_empty())
	Play.place(repo, s, guard, at + Vector2i(-50000, 0), ArmySystem.ORDER_MARCH)
	var before := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, first, s))
	s.ai_hosts[host]["siege_progress"] = 300
	for day in 3:
		ArmySystem.march_day(repo, s)
		EnemyAi.step_day(repo, s)
		SiegeSystem.settle_day(repo, s)
		s.day += 1
	assert_eq(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, first, s)), before)
	assert_eq(s.ai_hosts[host]["mode"], "SIEGE")
	assert_eq(int(s.ai_hosts[host]["siege_progress"]), 300)
	assert_true(s.manor_log.is_empty())
