extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The battle and enemy-AI tables and the foe container (spec
## 2026-10-07-enemy-ai-and-battle-design §2, §3.3, §4.3, §4.4, §7): the five
## outcome tiers tile the whole eff range, every stance and host role has its
## row, every new balance key exists, the pack's raid hosts name real regiments
## of the raider realm, and a foe lives in GameState.foes — readable through
## ArmySystem.state_of, never in the player's regiments.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

func test_outcomes_tile_the_whole_range() -> void:
	var rows := repo.battle_outcomes
	assert_eq(rows.size(), 5, "five tiers")
	assert_eq(int(rows[0]["eff_min"]), 0)
	assert_eq(int(rows[rows.size() - 1]["eff_max"]), 1000)
	for i in rows.size():
		assert_lt(int(rows[i]["eff_min"]), int(rows[i]["eff_max"]), "tier %d is not empty" % i)
		if i > 0:
			assert_eq(int(rows[i]["eff_min"]), int(rows[i - 1]["eff_max"]),
				"tier %d starts where tier %d ends" % [i, i - 1])
	for k: String in ["tier", "eff_min", "eff_max", "attacker_loss_permille", "defender_loss_permille",
			"wounded_share_permille", "attacker_morale", "defender_morale", "rout"]:
		assert_true(rows[0].has(k), "outcome column " + k)

func test_every_stance_row_complete() -> void:
	for s: String in ["hold", "steady", "evade"]:
		assert_true(repo.battle_stances.has(s), "stance " + s)
		var row: Dictionary = repo.battle_stances.get(s, {})
		for k: String in ["label", "defence_permille", "morale_decay_permille",
				"retreat_odds_permille", "retreats_on_contact"]:
			assert_true(row.has(k), "%s has %s" % [s, k])
	# hold never retreats of its own accord; evade leaves on the first day.
	assert_eq(int(repo.battle_stances["hold"]["retreat_odds_permille"]), 0)
	assert_false(bool(repo.battle_stances["hold"]["retreats_on_contact"]))
	assert_true(bool(repo.battle_stances["evade"]["retreats_on_contact"]))

func test_doctrines_cover_every_host_role() -> void:
	assert_false(repo.raid_hosts.is_empty())
	for h: Dictionary in repo.raid_hosts:
		assert_true(repo.ai_doctrines.has(String(h["role"])), "doctrine for role " + String(h["role"]))
	for role: String in ["main", "raider", "reserve"]:
		var row: Dictionary = repo.ai_doctrines.get(role, {})
		for k: String in ["greed_permille", "caution_permille", "dist_cost", "engage_odds_permille",
				"retreat_morale", "town_bonus"]:
			assert_true(row.has(k), "%s has %s" % [role, k])

func test_balance_keys_present() -> void:
	for k: String in ["battle_contact_km", "battle_max_rounds", "battle_max_units",
			"battle_variance_permille", "battle_spoils_permille", "battle_defeat_treasury_permille",
			"battle_defeat_morale", "battle_defeat_opinion", "ai_think_days", "ai_sight_km", "ai_target_reach_km",
			"ai_target_overlap_permille", "ai_retreat_supply_days", "ai_supply_margin_days", "siege_rate", "siege_assault_days",
			"siege_starve_bonus_permille", "siege_assault_fail_permille", "raid_appear_day", "raid_rumour_lead_days",
			"raid_plunder_permille"]:
		assert_true(repo.balance.has(k), "balance key " + k)
		assert_gt(repo.bal(k), 0.0, "balance key %s reads positive through bal()" % k)

func test_raid_hosts_name_real_regiments() -> void:
	var raiders := repo.resolve_realm("raider_realm")
	assert_eq(repo.raid_hosts.size(), 3, "a main, a raider, a reserve")
	var days: Array = []
	for h: Dictionary in repo.raid_hosts:
		days.append(int(h["appear_day"]))
		assert_false((h["regiments"] as Array).is_empty(), String(h["host_code"]) + " has regiments")
		for code: String in h["regiments"]:
			# a pack regiment code: the host raises the units split from it
			var units := EnemyAi.host_units(repo, null, {"regiments": [code]})
			assert_false(units.is_empty(), "regiment " + code + " raises units")
			for u: String in units:
				var reg := ArmySystem.regiment(repo, u)
				assert_eq(String(reg.get("parent_code", "")), code, u + " is split from " + code)
				assert_eq(String(reg.get("kingdom_code", "")), raiders, u + " is the raider realm's")
	assert_eq(days, [15, 15, 18])

func test_state_of_reads_foes() -> void:
	var s := SuiteData.campaign(repo, 11)
	var code := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	s.foes.erase(code)   # the campaign spawns every host's regiments (EnemyAi.spawn)
	assert_eq(ArmySystem.state_of(repo, s, code), {}, "not a foe yet, not the player's: nothing")
	assert_false(ArmySystem.is_foe(s, code))
	var entry := {"morale": 80, "wounded": 0, "supplies": 40, "x_m": 5, "y_m": 6}
	s.foes[code] = entry
	assert_true(ArmySystem.is_foe(s, code))
	assert_eq(ArmySystem.state_of(repo, s, code), entry)
	assert_eq(ArmySystem.state_of(repo, s, "no_such_regiment"), {})

func test_foes_never_in_player_iteration() -> void:
	var s := SuiteData.campaign(repo, 11)
	var code := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	s.foes[code] = {"morale": 80}
	assert_false(s.regiments.has(code))

func test_foe_fields_survive_the_save() -> void:
	var s := SuiteData.campaign(repo, 11)
	assert_false(s.foes.is_empty(), "the hosts are spawned with the campaign")
	assert_false(s.ai_hosts.is_empty())
	s.foes.clear()
	s.ai_hosts.clear()
	assert_eq(s.battles, [])
	assert_eq(s.foe_next_id, 0)
	s.foes["a"] = {"morale": 80, "x_m": 12}
	s.ai_hosts["h"] = {"mode": "ADVANCE", "plunder": 3}
	s.battles.append({"id": 1, "rounds": 2})
	s.foe_next_id = 4
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.foes, s.foes)
	assert_eq(back.ai_hosts, s.ai_hosts)
	assert_eq(back.battles, s.battles)
	assert_eq(back.foe_next_id, 4)
	# an old save with none of the keys
	var d := s.to_dict()
	for k: String in ["foes", "ai_hosts", "battles", "foe_next_id"]:
		d.erase(k)
	var old := GameState.from_dict(d)
	assert_eq(old.foes, {})
	assert_eq(old.ai_hosts, {})
	assert_eq(old.battles, [])
	assert_eq(old.foe_next_id, 0)
