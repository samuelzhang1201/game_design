extends GutTest
## P4.4e3: an agreement binds and protects only its own parties, wherever they later
## fight. Battle 1 (f1 attacks p1) agreed a ceasefire; battle 2 (p2 attacks f2) none.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(merge := true) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var p3 := String(mine[2])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(0, 0), f1: Vector2i(0, 3000), p2: Vector2i(5000, 20000), f2: Vector2i(80, 0), p3: Vector2i(40000, 40000)}
	for code: String in at:
		var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
		e["x_m"] = at[code].x
		e["y_m"] = at[code].y
		Personnel.replace(repo, state, code, 40)
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	var b1 := {"id": 1, "att": [f1], "def": [p1], "rounds": 1, "start_day": 5, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {},
		"parley": {"battle_id": 1, "agreed": {"ceasefire": term}, "parties": {"att": [f1], "def": [p1]}}}
	var b2 := {"id": 2, "att": [p2], "def": [f2], "rounds": 3, "start_day": 3, "town": "",
		"place_x_m": 80, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 2, "agreed": {}, "parties": {"att": [p2], "def": [f2]}}}
	state.battles = [b1, b2]
	state.tick = 1
	state.day = 7
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleReport.enroll(state, b, String(b["att"][0]), "att")
		BattleReport.enroll(state, b, String(b["def"][0]), "def")
		BattleGroups.refresh(repo, state, b)
	if merge:
		BattleMerge.day(repo, state)
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "p3": p3, "f1": f1, "f2": f2}

func _legal(f: Dictionary, unit: String, target := "") -> Array[String]:
	var b := BattleSystem.battle_of(f.state, unit)
	return BattleRules.legal_actions(f.repo, f.state, int(b["id"]), BattleRules.side_of(b, unit), unit, target)

func test_ceasefire_binds_only_its_parties_after_the_merge() -> void:
	var f := _fixture()
	assert_eq(f.state.battles.size(), 1)
	assert_false("attack" in _legal(f, f.p1, f.f1), "p1 toward f1 is protected")
	assert_true("attack" in _legal(f, f.p1, f.f2), "f2 never agreed with p1")
	assert_true("attack" in _legal(f, f.p2, f.f2), "battle 2 agreed nothing")
	assert_true("attack" in _legal(f, f.p2, f.f1), "p2 was never a party of the ceasefire")
	assert_false("attack" in _legal(f, f.f1, f.p1), "the other party is bound too")

func test_no_target_cannot_confirm_the_object_so_the_agreement_applies() -> void:
	var f := _fixture()
	assert_false("attack" in _legal(f, f.p1), "possibly breaching action held")
	assert_true("attack" in _legal(f, f.p2), "p2 is no party of any agreement")

func test_protection_survives_the_other_battle_being_the_survivor() -> void:
	var f := _fixture(false)
	f.state.battles[1]["town"] = "T"   # survivor = 2, battle 1 is absorbed
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	assert_eq(int(f.state.battles[0].id), 2)
	assert_false("attack" in _legal(f, f.p1, f.f1), "still binds p1 toward f1 under the new record")
	assert_true("attack" in _legal(f, f.p2, f.f1))

func test_freeze_records_parties_and_join_appends() -> void:
	var f := _fixture(false)
	var b := {"id": 3, "att": [f.f1], "def": [f.p1]}
	f.state.battles = [b]
	BattleRules.freeze(f.repo, f.state, b)
	assert_eq(b.parley.parties, {"att": [f.f1], "def": [f.p1]})
	var e: Dictionary = f.state.regiments[f.p3]
	e["x_m"] = 0
	e["y_m"] = 100
	assert_true(BattleSystem.join(f.repo, f.state, 3, f.p3, "def"))
	assert_eq(b.parley.parties.def, [f.p1, f.p3])

func test_old_parley_without_parties_defaults_to_current_members_and_roundtrips() -> void:
	var f := _fixture(false)
	f.state.battles[0].parley.erase("parties")
	assert_false("attack" in _legal(f, f.p1, f.f1), "old save: members default to parties")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(f.state.battles[1].parley))
	assert_eq(copy.parties.att, [f.p2])


func _withdrawal_fixture(survivor: int) -> Dictionary:
	var f := _fixture(false)
	var b: Dictionary = f.state.battles[0]
	b.parley.agreed = {"safe_withdrawal": {"policy": "protect", "until_day": f.state.absolute_day()}}
	if survivor == 2:
		f.state.battles[1].town = "T"
	BattleMerge.day(f.repo, f.state)
	b = f.state.battles[0]
	b.town = ""
	b.actions = {"att": {"kind": "hold"}, "def": {"kind": "hold"}}
	f.repo.balance["battle_strength_factor_min_permille"] = 1000
	f.repo.balance["battle_strength_factor_max_permille"] = 1000
	f.repo.army_matchups.clear()
	for code: String in b.att + b.def:
		BattleSystem._stored(f.state, code)["battle_retreat"] = true
	return f

func _loss(f: Dictionary, unit: String) -> int:
	var b: Dictionary = f.state.battles[0]
	return int(BattleSystem.combat_context(f.repo, f.state, b, BattleRules.side_of(b, unit), unit).loss_permille)

func test_merged_withdrawal_removes_only_the_bound_opponents_share() -> void:
	for survivor: int in [1, 2]:
		var f := _withdrawal_fixture(survivor)
		var b: Dictionary = f.state.battles[0]
		var power1 := BattleSystem.side_power(f.repo, f.state, [f.f1], Callable(), false, b[BattleRules.side_of(b, f.p1)])
		var power2 := BattleSystem.side_power(f.repo, f.state, [f.f2], Callable(), false, b[BattleRules.side_of(b, f.p1)])
		assert_gt(power1, 0)
		assert_eq(power1, power2, "equal incoming power gives equal shares")
		# Withdrawal 600 * unbound half = 300; the unrelated ally keeps all 600.
		assert_eq(_loss(f, f.p1), 300, "the original agreement suppresses only f1's share")
		assert_eq(_loss(f, f.p2), 600, "p2 never signed")
		var twin := f.duplicate()
		twin.state = preload("res://tests/fixtures/battle_scenario.gd").roundtrip(f.state)
		assert_eq(_loss(twin, f.p1), 300, "source parties survive JSON")
		assert_eq(_loss(twin, f.p2), 600)
		f.state.day += 1
		assert_eq(_loss(f, f.p1), 600, "expiry restores the full incoming share")

func test_absorbed_withdrawal_protects_both_original_parties_without_spreading() -> void:
	for survivor: int in [1, 2]:
		var f := _withdrawal_fixture(survivor)
		var b: Dictionary = f.state.battles[0]
		# Remove new opponents from contact, retaining the unrelated withdrawing ally.
		b[BattleRules.side_of(b, f.f2)].erase(f.f2)
		assert_eq(_loss(f, f.p1), 0, "only the original bound opponent remains")
		assert_eq(_loss(f, f.p2), 600, "same-side ally cannot inherit protection")
		b[BattleRules.side_of(b, f.p2)].erase(f.p2)
		assert_eq(_loss(f, f.f1), 0, "the agreement protects its other original party too")

func test_scoped_withdrawal_rates_freeze_and_replay_without_another_rng_draw() -> void:
	var f := _withdrawal_fixture(2)
	var b: Dictionary = f.state.battles[0]
	for code: String in b.att + b.def:
		var e := BattleSystem._stored(f.state, code)
		e.x_m = 0
		e.y_m = 0
		e.morale = 100
		e.supplies = 100000
	for code: String in [f.f1, f.f2]:
		f.state.foes[code].erase("battle_retreat")
		f.state.law_in_force["unit:" + code] = {"battle_tactics": {"value": "unrestricted", "decree_id": 100}}
	b.actions[BattleRules.side_of(b, f.f1)] = {"kind": "attack"}
	f.repo.battle_outcomes.clear()
	f.repo.battle_outcomes.append({"tier": "fixture", "eff_min": 0, "eff_max": 1000,
		"attacker_loss_permille": 100, "defender_loss_permille": 100,
		"wounded_share_permille": 500, "attacker_morale": 0, "defender_morale": 0, "rout": "none"})
	var cohort := String(f.state.military_rosters[f.p2].cohort_ids.back())
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	var events: Array = []
	assert_true(BattleSystem._fight(f.repo, f.state, b, events).has("error"))
	# Pursuit 1500 * unbound half = 750; base 100 *750/1000 =75.
	assert_eq(int(b.pending_round.tier.unit_loss_permille[f.p1]), 75)
	assert_eq(int(b.pending_round.tier.unit_loss_permille[f.p2]), 150)
	var pending: Dictionary = b.pending_round.duplicate(true)
	var rng: Dictionary = f.state.rng.to_dict()
	assert_true(BattleSystem._fight(f.repo, f.state, b, events).has("error"))
	assert_eq(b.pending_round, pending)
	assert_eq(f.state.rng.to_dict(), rng)
	var twin := preload("res://tests/fixtures/battle_scenario.gd").roundtrip(f.state)
	f.state.military_cohorts[cohort].source_population_field = origin
	twin.military_cohorts[cohort].source_population_field = origin
	assert_false(BattleSystem._fight(f.repo, f.state, b, events).has("error"))
	assert_false(BattleSystem._fight(f.repo, twin, twin.battles[0], events).has("error"))
	assert_eq(MilitaryRoster.fit(f.state, f.p1), 37, "40 - floor(40 *75/1000)")
	assert_eq(MilitaryRoster.fit(f.state, f.p2), 34, "40 - floor(40 *150/1000)")
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(f.state))
	var after := SaveLoad.state_hash(f.state)
	BattleSystem._fight(f.repo, f.state, b, events)
	assert_eq(SaveLoad.state_hash(f.state), after, "same-day replay is inert")

func test_withdrawal_protection_uses_power_shares_and_zero_power_is_defined() -> void:
	var f := _withdrawal_fixture(2)
	var b: Dictionary = f.state.battles[0]
	Personnel.replace(f.repo, f.state, f.f1, 80)
	var own: Array = b[BattleRules.side_of(b, f.p1)]
	assert_eq(BattleSystem.side_power(f.repo, f.state, [f.f1], Callable(), false, own), 80)
	assert_eq(BattleSystem.side_power(f.repo, f.state, [f.f2], Callable(), false, own), 40)
	assert_eq(_loss(f, f.p1), 200, "600 *40/(80 +40) =200")
	assert_eq(_loss(f, f.p2), 600)
	Personnel.replace(f.repo, f.state, f.f1, 0)
	Personnel.replace(f.repo, f.state, f.f2, 0)
	assert_eq(_loss(f, f.p1), 600, "no power denominator keeps the ordinary withdrawal context")
	b[BattleRules.side_of(b, f.f2)].erase(f.f2)
	assert_eq(_loss(f, f.p1), 0, "an entirely bound opposing side remains protected even at zero power")
