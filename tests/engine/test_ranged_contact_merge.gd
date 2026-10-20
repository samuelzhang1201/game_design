extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const BattleScenario := preload("res://tests/fixtures/battle_scenario.gd")

# One 40-person group per unit. p1 faces its distant opponent eastwards;
# f2 is 300 m east: 100^2 < 300^2 <= 400^2, unobstructed and inside the cone.
func _fixture(gap := 300) -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := SuiteData.campaign(repo, 9447)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var positions := {p1: Vector2i(1000, 1000), f1: Vector2i(5000, 1000),
		p2: Vector2i(5000, 5000), f2: Vector2i(1000 + gap, 1000)}
	for code: String in positions:
		for arm: String in repo.world_table("military", "unit_types"):
			state.army_roster[code][arm] = "0"
		state.army_roster[code]["archers" if code == p1 else "infantry"] = "40"
		Personnel.replace(repo, state, code, 40)
		var stored := BattleSystem._stored(state, code)
		stored["x_m"] = positions[code].x
		stored["y_m"] = positions[code].y
		stored["supplies"] = 100000
		stored["morale"] = 100
		stored["order"] = ArmySystem.ORDER_STANDBY
		stored.erase("camp_town")
	var a := {"id": 1, "att": [f1], "def": [p1], "rounds": 1, "start_day": 0,
		"town": "", "place_x_m": 1000, "place_y_m": 1000,
		"actions": {"def": {"kind": "attack"}, "att": {"kind": "hold"}}}
	var b := {"id": 2, "att": [p2], "def": [f2], "rounds": 3, "start_day": 0,
		"town": "", "place_x_m": 1300, "place_y_m": 1000, "actions": {}}
	state.battles = [a, b]
	for battle: Dictionary in state.battles:
		BattleFormation.ensure(battle)
		BattleRules.freeze(repo, state, battle)
		battle["deployed_day"] = state.absolute_day()
		BattleGroups.refresh(repo, state, battle)
	return {"repo": repo, "state": state, "a": a, "b": b, "p1": p1, "p2": p2, "f1": f1, "f2": f2}

func test_prepare_day_merges_real_cross_battle_fire_without_moving_units() -> void:
	var f := _fixture()
	var positions := {}
	for code: String in [f.p1, f.p2, f.f1, f.f2]:
		positions[code] = BattleSystem._at_m(f.repo, f.state, code)
	var events := BattleSystem.prepare_day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	assert_true(events.any(func(e: Dictionary) -> bool: return e.kind == "merge"))
	assert_eq(f.state.battle_aliases, {"2": 1})
	for code: String in positions:
		assert_eq(BattleSystem._at_m(f.repo, f.state, code), positions[code])

func test_range_alone_and_non_ranged_units_do_not_merge() -> void:
	var far := _fixture(401)
	assert_eq(BattleMerge.day(far.repo, far.state), [])
	var melee := _fixture()
	melee.state.army_roster[melee.p1].archers = "0"
	melee.state.army_roster[melee.p1].infantry = "40"
	assert_eq(BattleMerge.day(melee.repo, melee.state), [])

func test_retreating_shooter_does_not_merge() -> void:
	var f := _fixture()
	f.a.actions.def.kind = "retreat"
	assert_eq(BattleMerge.day(f.repo, f.state), [])

func test_cross_battle_friendly_group_obstructs_fire() -> void:
	var f := _fixture()
	f.state.regiments[f.p2].x_m = 1150
	f.state.regiments[f.p2].y_m = 1020
	BattleGroups.refresh(f.repo, f.state, f.b)
	assert_eq(BattleMerge.day(f.repo, f.state), [], "20 m tangency blocks the 300 m segment")

func test_json_and_retry_preserve_once_only_daily_receipt() -> void:
	var f := _fixture()
	f.b["last_resolved_day"] = f.state.absolute_day()
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	var loaded := BattleScenario.roundtrip(f.state)
	var before := JSON.stringify(loaded.to_dict())
	assert_eq(BattleMerge.day(f.repo, loaded), [])
	assert_eq(JSON.stringify(loaded.to_dict()).sha256_text(), before.sha256_text())
	var personnel := JSON.stringify(loaded.military_cohorts).sha256_text()
	var supplies := int(loaded.regiments[f.p1].supplies)
	BattleSystem.step_battle(f.repo, loaded, 2)
	assert_eq(int(loaded.battles[0].rounds), 3)
	assert_eq(JSON.stringify(loaded.military_cohorts).sha256_text(), personnel)
	assert_eq(int(loaded.regiments[f.p1].supplies), supplies)

func test_incompatible_enemy_relations_do_not_merge() -> void:
	var f := _fixture()
	# A host with crown allegiance cannot be folded into the raider side.
	f.state.army_roster[f.f2].kingdom_code = f.repo.resolve_realm("player_realm")
	assert_eq(BattleMerge.day(f.repo, f.state), [])

func test_source_terms_protect_actual_cross_battle_target() -> void:
	for source: String in ["a", "b"]:
		var f := _fixture()
		f[source].parley.parties = {"att": [f.p1], "def": [f.f2]}
		f[source].parley.agreed = {"ceasefire": {"policy": "protect"}}
		assert_eq(BattleMerge.day(f.repo, f.state), [], "Protection follows parties in either source")

func test_read_only_rejected_probe_and_wrong_facing() -> void:
	var f := _fixture()
	f.a.group_facing[f.p1] = 180
	var before := JSON.stringify(f.state.to_dict())
	assert_false(BattleMerge.mergeable(f.repo, f.state, f.a, f.b))
	assert_eq(JSON.stringify(f.state.to_dict()), before)

func test_cross_field_counts_use_actual_firing_personnel() -> void:
	var f := _fixture()
	var before := JSON.stringify(f.state.to_dict()).sha256_text()
	assert_eq(BattleRanged.counts(f.repo, f.state, f.a, f.p1, f.f2, f.b),
		{"firing": 40, "melee": 0, "fit": 40})
	assert_eq(JSON.stringify(f.state.to_dict()).sha256_text(), before)
	assert_eq(BattleRanged.counts(f.repo, f.state, f.a, f.p1).firing, 0,
		"The original field's opponent is 4000 m away")

func test_received_designated_task_cannot_authorize_other_field() -> void:
	var f := _fixture()
	var request := {"id": "merge-designated", "unit": f.p1, "battle_id": 1,
		"task": "advance", "target_unit": f.f1, "source": "player"}
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, request).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "merge-designated").status, "received")
	assert_eq(BattleMerge.day(f.repo, f.state), [])

func test_protected_withdrawal_reserve_and_captured_cannot_trigger_fire() -> void:
	var f := _fixture()
	f.b.parley.parties = {"att": [f.p1], "def": [f.f2]}
	f.b.parley.agreed = {"safe_withdrawal": {"policy": "protect"}}
	f.b.actions["def"] = {"kind": "retreat"}
	assert_eq(BattleMerge.day(f.repo, f.state), [])
	var reserve := _fixture()
	reserve.a["reserves"] = {reserve.p1: true}
	assert_eq(BattleMerge.day(reserve.repo, reserve.state), [])
	var captured := _fixture()
	captured.state.foes[captured.f2]["captured"] = true
	assert_eq(BattleMerge.day(captured.repo, captured.state), [])

func test_json_before_merge_and_reversed_battle_order_choose_same_survivor() -> void:
	var f := _fixture()
	var loaded := BattleScenario.roundtrip(f.state)
	loaded.battles.reverse()
	assert_eq(BattleMerge.day(f.repo, f.state), BattleMerge.day(f.repo, loaded))
	assert_eq(loaded.battle_aliases, f.state.battle_aliases)
	assert_eq(loaded.battles, f.state.battles)

func test_actual_merged_round_settles_once_through_either_alias() -> void:
	var f := _fixture()
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 100
		tier.defender_loss_permille = 100
		tier.attacker_morale = 0
		tier.defender_morale = 0
		tier.wounded_share_permille = 0
		tier.rout = "none"
	var request := {"id": "merge-advance", "unit": f.p1, "battle_id": 1,
		"task": "advance", "target_unit": "", "source": "player"}
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, request).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "merge-advance").status, "received")
	var tasks: Dictionary = f.state.unit_tasks.duplicate(true)
	var gold := int(f.state.metrics.treasury)
	var supplies := int(f.state.regiments[f.p1].supplies)
	assert_eq(BattleMerge.day(f.repo, f.state).size(), 1)
	assert_eq(f.state.unit_tasks, tasks)
	assert_eq(int(f.state.metrics.treasury), gold)
	assert_eq(int(f.state.regiments[f.p1].supplies), supplies)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 2).status, "complete")
	assert_gt(Personnel.count(f.state, f.f2, "dead"), 0, "Cross-field fire reaches actual personnel settlement")
	var after := JSON.stringify(f.state.to_dict()).sha256_text()
	BattleSystem.step_battle(f.repo, f.state, 1)
	assert_eq(JSON.stringify(f.state.to_dict()).sha256_text(), after)

func test_target_source_restrained_agreement_bars_cross_field_pursuit() -> void:
	var f := _fixture()
	f.b.parley.parties = {"att": [f.p1], "def": [f.f2]}
	f.b.parley.agreed = {"tactics": {"policy": "restrained"}}
	f.b.actions["def"] = {"kind": "retreat"}
	assert_eq(BattleMerge.day(f.repo, f.state), [])
