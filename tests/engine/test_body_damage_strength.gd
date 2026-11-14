extends GutTest
## D-POWER: CF06 physical power arithmetic (cf06-power-contract §1-4, P1-P7) and the
## damage contract's case 1. Every expected value below is the contract's hand math.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()

func _arm(n: int, e: int, h: int, fit: int, capacity: int, base: int = 1000, dev: int = 1000) -> Array:
	return BattleStrength.arm_power(n, e, h, fit, capacity, base, dev)

func test_arm_chain_matches_the_contract_oracle() -> void:
	assert_eq(_arm(1000, 100, 1000, 1000, 1000), [100000, 100000, 100], "P1 pure melee M100 of F1000")
	assert_eq(_arm(1000, 0, 1000, 1000, 1000)[2], 0, "P1 M0 is zero")
	# P2: infantry600, archers320, artillery10 (crew 8): C1000; F901, M101 and disjoint J100.
	var p2: Array = []
	for pair: Array in [[600, 101], [320, 201], [10, 201]]:
		p2.append(_arm(pair[0], pair[1], 901, 901, 1000))
	assert_eq(p2.map(func(v: Array) -> int: return v[0]), [60600, 64320, 2010])
	assert_eq(p2.map(func(v: Array) -> int: return v[2]), [61, 65, 3])
	# Ceiling the melee and fire halves separately is forbidden: 34 and 3, not 33 and 2.
	assert_eq(_arm(320, 101, 901, 901, 1000)[2] + _arm(320, 1, 901, 901, 1000)[2], 34)
	assert_eq(_arm(320, 102, 901, 901, 1000)[2], 33)
	assert_eq(_arm(10, 101, 901, 901, 1000)[2] + _arm(10, 1, 901, 901, 1000)[2], 3)
	assert_eq(_arm(10, 102, 901, 901, 1000)[2], 2)
	# P3: N3 c1 F3 G1 (H2), M1: exact crew 2/3 -> m0 666; base1501 -> 999; dev1001 -> ceil 1.
	assert_eq(_arm(3, 1, 2, 3, 3, 1501, 1001), [666, 999, 1])
	assert_eq(_arm(3, 3, 2, 3, 3)[0], 2000, "all-fit M3 is exactly the old H2 chain")
	assert_eq(_arm(3, 3, 0, 3, 3)[2], 0, "H0 is outgoing zero")
	# P4: only the final 1 firing, then only the final 1 in melee.
	assert_eq([[600, 0], [320, 1], [10, 1]].map(func(p: Array) -> int: return _arm(p[0], p[1], 901, 901, 1000)[2]), [0, 1, 1])
	assert_eq([600, 320, 10].map(func(n: int) -> int: return _arm(n, 1, 901, 901, 1000)[2]), [1, 1, 1])

func test_exposure_oracle_and_rejections() -> void:
	# P5: A (P2 counts, R400, M101/J100) W141000; D (F300, R1000, J100) W100000.
	var a := {"fit": 901, "ranged_share": 400, "melee": 101, "firing": 100}
	var d := {"fit": 300, "ranged_share": 1000, "melee": 0, "firing": 100}
	assert_eq(BattleStrength.exposure([a, d]).exposure, 200, "trunc(241000/1201)")
	assert_eq(BattleStrength.exposure([{"fit": 901, "ranged_share": 400, "melee": 1, "firing": 0}]).exposure, 1)
	assert_eq(BattleStrength.exposure([]).exposure, 0, "no lawful source is 0, never 1000")
	# P6: R666 (C3/Cr2), F3 J3 -> 666; a lawful nonparty F1 R0 M1 -> trunc(2998/4) = 749.
	var p6 := {"fit": 3, "ranged_share": 666, "melee": 0, "firing": 3}
	assert_eq(BattleStrength.exposure([p6]).exposure, 666)
	assert_eq(BattleStrength.exposure([p6, {"fit": 1, "ranged_share": 0, "melee": 1, "firing": 0}]).exposure, 749)
	for bad: Dictionary in [{"fit": 3, "ranged_share": 666, "melee": 2, "firing": 2}, {"fit": 0, "ranged_share": 0, "melee": 0, "firing": 0},
		{"fit": 3, "ranged_share": 1001, "melee": 0, "firing": 0}, {"fit": 3, "ranged_share": 0, "melee": -1, "firing": 0},
		{"fit": 3.0, "ranged_share": 0, "melee": 0, "firing": 0}]:
		assert_true(BattleStrength.exposure([bad]).has("error"), str(bad))

func test_category_chain_after_eligible_base() -> void:
	# P2 continued: Q129 x quality1100 = 141; training1100 -> 155, morale900 -> 139,
	# formation_terrain 889+1100+1050 -> 1039 -> 144. No contact fraction follows.
	assert_eq(129 * 1100 / 1000, 141)
	var bounds := {"min_permille": 0, "max_permille": 3000}
	var factors: Array[Dictionary] = []
	for row: Array in [["unit:training", "training", 1100], ["unit:morale", "morale", 900], ["unit:discipline", "discipline", 1000],
		["unit:supply", "supply", 1000], ["unit:terrain", "formation_terrain", 889], ["ground:height", "formation_terrain", 1100],
		["event:one", "formation_terrain", 1050]]:
		factors.append({"source": row[0], "category": row[1], "permille": row[2], "reason": "P2"}.merged(bounds))
	var combined := BattleStrength.combine(141, factors)
	assert_eq(combined.power, 144)
	assert_eq(combined.steps.map(func(s: Dictionary) -> int: return s.power), [155, 139, 139, 139, 144])
	# A zero eligible base stays zero under a positive lower clamp.
	var floored: Array[Dictionary] = [{"source": "unit:training", "category": "training", "permille": 100, "reason": "P1",
		"min_permille": 500, "max_permille": 3000}]
	assert_eq(BattleStrength.combine(0, floored).power, 0)
	# P5 context: melee1000 x exposure200, then one event exposure1250 -> 250; tier125 -> rate 31.
	assert_eq(1000 * 200 / 1000 * 1250 / 1000, 250)
	assert_eq(BattleStrength.loss_rate(125, 250), 31)

## A campaign unit re-equipped by `arms` with `fit` personnel; neutral arm bases (no matchups).
func _unit(repo: DataRepository, state: GameState, code: String, arms: Dictionary, fit: int) -> void:
	for arm: String in repo.world_table("military", "unit_types"):
		state.army_roster[code][arm] = str(int(arms.get(arm, 0)))
	assert_false(Personnel.replace(repo, state, code, fit).has("error"))

func _world() -> Dictionary:
	var repo := SuiteData.repo()
	repo.army_matchups.clear()
	var state := SuiteData.campaign(repo, 319)
	var mine: Array = state.regiments.keys()
	mine.sort()
	var foes: Array = state.foes.keys()
	foes.sort()
	return {"repo": repo, "state": state, "a": foes[0], "d": foes[1], "b": mine[0]}

func _base(f: Dictionary, code: String, melee: int, firing: int) -> Dictionary:
	var result := BattleStrength.unit(f.repo, f.state, code, true, [], melee, firing)
	assert_false(result.has("error"), str(result.get("error", "")))
	return result

func test_eligible_personnel_through_the_original_equipment_chain() -> void:
	var f := _world()
	var quality := func(code: String) -> int: return int(MilitaryQuality.profile(f.repo, f.state, code).power_permille)
	# P1 / case 1: F1000 one 100-person row engaged; Q = 100 before quality.
	_unit(f.repo, f.state, f.b, {"infantry": 1000}, 1000)
	assert_eq(DevelopmentSystem.arm_permille(f.repo, f.state, ArmySystem.realm_of(f.repo, f.b, f.state)).infantry, 1000)
	assert_eq(_base(f, f.b, 100, 0).base, 100 * quality.call(f.b) / 1000)
	assert_eq(_base(f, f.b, 0, 0).power, 0, "no eligible personnel: zero before every clamp")
	var full := BattleStrength.unit(f.repo, f.state, f.b, true)
	assert_eq(full.base, 1000 * quality.call(f.b) / 1000, "defence keeps the full H chain")
	assert_eq(_base(f, f.b, 1000, 0).power, full.power, "E = F is exactly the original chain")
	# P2: Q = 61 + 65 + 3 = 129; P4: final 1 firing Q 0+1+1 = 2, final 1 in melee 1+1+1 = 3.
	_unit(f.repo, f.state, f.a, {"infantry": 600, "archers": 320, "artillery": 10}, 901)
	assert_eq(ArmySystem.personnel_capacity(f.repo, ArmySystem.regiment(f.repo, f.a, f.state)), 1000)
	assert_eq(_base(f, f.a, 101, 100).base, 129 * quality.call(f.a) / 1000)
	assert_eq(_base(f, f.a, 0, 1).base, 2 * quality.call(f.a) / 1000)
	assert_eq(_base(f, f.a, 1, 0).base, 3 * quality.call(f.a) / 1000)
	for bad: Array in [[900, 2], [0, -1], [902, 0]]:
		assert_true(BattleStrength.unit(f.repo, f.state, f.a, true, [], bad[0], bad[1]).has("error"), str(bad))

func test_target_context_classification_and_exposure() -> void:
	var f := _world()
	_unit(f.repo, f.state, f.a, {"infantry": 600, "archers": 320, "artillery": 10}, 901)
	_unit(f.repo, f.state, f.d, {"archers": 300}, 300)
	var today: int = f.state.absolute_day()
	var battle := {"id": 8, "att": [f.a, f.d], "def": [f.b], "actions": {"att": {"kind": "attack", "reason": "A"}, "def": {"kind": "hold", "reason": "H"}},
		"event_modifiers": [{"unit": f.b, "until_day": today, "exposure_permille": 1250}]}
	# P5: ranged numerator 35 + 8 + 100 = 143 of crew 1300 < 500 permille: melee, exposure 200, event 250.
	var p5 := BattleSystem.candidate_context(f.repo, f.state, battle, f.b,
		[{"code": f.a, "melee": 101, "firing": 100, "impact": 0}, {"code": f.d, "melee": 0, "firing": 100, "impact": 0}])
	assert_eq(p5.kind, "melee", str(p5))
	assert_eq(p5.exposure, 200)
	assert_eq(p5.loss_permille, 250)
	assert_eq(BattleStrength.loss_rate(125, int(p5.loss_permille)), 31)
	battle.event_modifiers = []
	assert_eq(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, []).loss_permille, 0, "empty I(t): 0")
	# P7: pure ranged F1000 J600 -> ranged 800 x 600 = 480.
	_unit(f.repo, f.state, f.d, {"archers": 1000}, 1000)
	var ranged := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.d, "melee": 0, "firing": 600, "impact": 0}])
	assert_eq([ranged.kind, ranged.exposure, ranged.loss_permille], ["ranged", 600, 480])
	# P7: mounted F1000 (cavalry crew 2) M600 with earned impact 600 -> shock 1250 x 600 = 750;
	# a remote or consumed impact (0) is ordinary melee 600.
	_unit(f.repo, f.state, f.d, {"cavalry": 500}, 1000)
	assert_eq(BattleCharge.mounted_share(f.repo, f.state, f.d), 1000)
	var shock := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.d, "melee": 600, "firing": 0, "impact": 600}])
	assert_eq([shock.kind, shock.loss_permille], ["shock", 750])
	var plain := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.d, "melee": 600, "firing": 0, "impact": 0}])
	assert_eq([plain.kind, plain.loss_permille], ["melee", 600])
	# A withdrawing target: pursuit when a lawful source reaches it, withdrawal (and 0) when none.
	f.state.regiments[f.b].battle_retreat = true
	var pursued := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.d, "melee": 600, "firing": 0, "impact": 0}])
	assert_eq([pursued.kind, pursued.loss_permille], ["pursuit", int(f.repo.bal("battle_context_pursuit_permille")) * 600 / 1000])
	var alone := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [])
	assert_eq([alone.kind, alone.loss_permille], ["withdrawal", 0])
	assert_true(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.d, "melee": -1, "firing": 0, "impact": 0}]).has("error"))

## The physical world of test_body_battle_contact: crown infantry (fit 1000, ten rows), the
## enemy's single 100-person row touching row 0, `other` 40 km away.
func _physical() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
	var f: Dictionary = helper.call("_fixture", 1000, 100)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.repo.army_matchups.clear()
	for code: String in f.state.battles[0].groups:
		var entry := UnitBodies._entry(f.state, code)
		entry.x_m = int(f.state.battles[0].groups[code][0].x_m)
		entry.y_m = int(f.state.battles[0].groups[code][0].y_m)
	f.state.battles[0].actions = {"att": {"kind": "attack", "reason": "Advance"}, "def": {"kind": "attack", "reason": "Advance"}}
	f.boundary = {"version": 1, "kind": "safe", "abs_day": str(f.state.absolute_day()), "sequence": "0"}
	return f

func test_physical_sources_and_union_power() -> void:
	var f := _physical()
	var before := BodyMotion._hash(f.state.to_dict())
	# Case 1: F1000 with one 100-person row in contact: eligible 100, so Q = 100 (infantry 100, C100).
	var power := BattleSystem.candidate_power(f.repo, f.state, 8, f.unit, true, [], f.boundary)
	assert_false(power.has("error"), str(power.get("error", "")))
	var quality := int(MilitaryQuality.profile(f.repo, f.state, f.unit).power_permille)
	assert_eq(power.base, 100 * quality / 1000)
	# Sources of the crown unit: only the touching enemy; the remote `other` is absent, so it
	# cannot dilute the exposure (100 of 100 -> 1000, not 100000/200 = 500).
	var sources := BattleSystem.candidate_sources(f.repo, f.state, 8, f.unit, f.boundary)
	assert_eq(sources.sources.map(func(s: Dictionary) -> String: return s.code), [f.enemy])
	assert_eq(sources.sources[0].melee, 100)
	var context := BattleSystem.candidate_context(f.repo, f.state, f.state.battles[0], f.unit, sources.sources)
	assert_eq(context.exposure, 1000)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before, "planning reads never mutate")
	# A legacy contact factor is refused on the candidate path.
	var legacy: Array[Dictionary] = [{"source": "contact:engaged", "category": "contact", "permille": 100, "reason": "Legacy"}]
	assert_true(BattleSystem.candidate_power(f.repo, f.state, 8, f.unit, true, legacy, f.boundary).has("error"))
	# A ceasefire with the enemy removes its pair: no lawful source, exposure 0, outgoing 0 under a floor.
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	f.state.battles[0].parley = {"battle_id": 8, "agreed": {"ceasefire": term}, "parties": {"att": [f.unit], "def": [f.enemy]}}
	assert_eq(BattleSystem.candidate_sources(f.repo, f.state, 8, f.unit, f.boundary).sources, [])
	f.repo.balance.battle_strength_factor_min_permille = 500
	assert_eq(BattleSystem.candidate_power(f.repo, f.state, 8, f.unit, true, [], f.boundary).power, 0)

func test_context_rejects_duplicate_hostility_and_empty_sources() -> void:
	var f := _world()
	# P6: C3/Cr2 gives R666 straight from BattleRanged.share, not 667.
	_unit(f.repo, f.state, f.a, {"archers": 2, "infantry": 1}, 3)
	assert_eq(BattleRanged.share(f.repo, f.state, f.a), 666)
	_unit(f.repo, f.state, f.d, {"infantry": 1}, 1)
	var battle := {"id": 8, "att": [f.a, f.d], "def": [f.b], "actions": {}}
	var p6 := {"code": f.a, "melee": 0, "firing": 3, "impact": 0}
	var nonparty := {"code": f.d, "melee": 1, "firing": 0, "impact": 0}
	assert_eq(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [p6, nonparty]).exposure, 749)
	# Duplicate rows cannot raise W (P6: [p6, p6, nonparty] would read 713); they are rejected.
	assert_true(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [p6, p6, nonparty]).has("error"))
	# A zero row would dilute exposure like a remote source; a friendly code is not a source.
	assert_true(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [p6, {"code": f.d, "melee": 0, "firing": 0, "impact": 0}]).has("error"))
	var mine: Array = f.state.regiments.keys()
	mine.sort()
	assert_true(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": mine[1], "melee": 1, "firing": 0, "impact": 0}]).has("error"))
	assert_true(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.d, "melee": 1, "firing": 0, "impact": 2}]).has("error"), "impact is melee personnel")

func test_earned_impact_only_through_the_production_charge_target() -> void:
	var f := _physical()
	var types: Array = f.repo.world_table("military", "unit_types").keys()
	for arm: String in types:
		f.state.army_roster[f.enemy][arm] = "0"
	f.state.army_roster[f.enemy].cavalry = "50"
	var entry := UnitBodies._entry(f.state, f.enemy)
	entry.supplies = 1000000
	entry.charge = {"phase": "impact", "target": f.unit, "origin_x_m": 0, "origin_y_m": 0, "x_m": 0, "y_m": 0,
		"runup_m": 300, "impact_day": f.state.absolute_day(), "heading_deg": 180}
	assert_eq(BattleCharge.target(f.repo, f.state, f.state.battles[0], f.enemy), f.unit)
	var earned := BattleSystem.candidate_sources(f.repo, f.state, 8, f.unit, f.boundary)
	assert_eq(earned.sources[0].impact, 100)
	assert_eq(BattleSystem.candidate_context(f.repo, f.state, f.state.battles[0], f.unit, earned.sources).kind, "shock")
	# A received flank task earns no impact: no second charge factor beside the flank's own.
	f.state.unit_tasks = {f.enemy: {"current_id": "fl", "received_sequence": 1, "orders": {"fl": {
		"sequence": 1, "status": "received", "reason": "Received", "history": [],
		"request": {"id": "fl", "unit": f.enemy, "battle_id": 8, "task": "flank", "formation": "",
			"target_unit": f.unit, "source": "ai", "issuer": "", "max_route_m": 0, "region": ""}}}}}
	var flank := BattleSystem.candidate_sources(f.repo, f.state, 8, f.unit, f.boundary)
	assert_eq(flank.sources.size(), 1)
	assert_eq(flank.sources[0].impact, 0)
	# A saved impact on another day is not earned either.
	f.state.unit_tasks = {}
	entry.charge.impact_day = f.state.absolute_day() - 1
	assert_eq(BattleSystem.candidate_sources(f.repo, f.state, 8, f.unit, f.boundary).sources[0].impact, 0)

func test_every_contact_category_factor_is_refused() -> void:
	var f := _physical()
	var other: Array[Dictionary] = [{"source": "custom:participation", "category": "contact", "permille": 100, "reason": "Renamed"}]
	assert_true(BattleSystem.candidate_power(f.repo, f.state, 8, f.unit, true, other, f.boundary).has("error"))
	var fine: Array[Dictionary] = [{"source": "ground:height", "category": "formation_terrain", "permille": 1000, "reason": "Flat"}]
	assert_false(BattleSystem.candidate_power(f.repo, f.state, 8, f.unit, true, fine, f.boundary).has("error"))

func test_sources_from_another_live_field_are_admitted() -> void:
	# D-FIRE's cross-field world: archer C (field 9) fires 100 at A (field 8); B (A's
	# opponent in field 8) has no eligible pair, so I(A) = {C}.
	var helper: GutTest = load("res://tests/engine/test_body_direct_fire.gd").new()
	var f: Dictionary = helper.call("_cross")
	helper.free()
	var sources := BattleSystem.candidate_sources(f.repo, f.state, 8, f.a, BodyBattleMotion._boundary(f.state))
	assert_false(sources.has("error"), str(sources.get("error", "")))
	assert_eq(sources.sources.map(func(s: Dictionary) -> String: return s.code), [f.c])
	assert_eq(sources.sources[0].firing, 100)
	assert_eq(sources.sources[0].melee, 0)

func test_outgoing_union_spans_fields_without_double_counting() -> void:
	var helper: GutTest = load("res://tests/engine/test_body_direct_fire.gd").new()
	var f: Dictionary = helper.call("_cross")
	helper.free()
	var boundary := BodyBattleMotion._boundary(f.state)
	# C (field 9) fires 100 only across the fronts at A (field 8): the union carries that J.
	var union := BattleSystem.candidate_union(f.repo, f.state, 9, f.c, boundary)
	assert_eq([union.melee, union.firing], [0, 100])
	var power := BattleSystem.candidate_power(f.repo, f.state, 9, f.c, true, [], boundary)
	assert_false(power.has("error"), str(power.get("error", "")))
	assert_gt(int(power.base), 0, "an admitted cross-field source has its real union power")
	assert_true(BattleSystem.candidate_power(f.repo, f.state, 9, f.c, false, [], boundary).has("error"), "defence is not this path")

func test_contact_in_another_field_suppresses_per_target_fire() -> void:
	# C (field 9) shoots D in its own field 9 (D 300 m of open gap ahead); its contact with A
	# of field 8 is invisible to that same-field query. Close contact anywhere means no fire:
	# with A touching C, J_t for D is 0 and C is not one of D's sources.
	var helper: GutTest = load("res://tests/engine/test_body_direct_fire.gd").new()
	var f: Dictionary = helper.call("_cross")
	helper.call("_put", f, f.d, 0, 10340, 10000, 1)
	f.state.battles[1].group_anchor_m[f.d] = [10340, 10000]
	helper.call("_put", f, f.a, 0, 10000, 30000, 0)
	f.state.battles[0].group_anchor_m[f.a] = [10000, 30000]
	f.state.battles[0].actions.att = {"kind": "attack", "reason": "Received advance plan"}
	BodyBattle._seal_private(f.repo, f.state)
	var boundary := BodyBattleMotion._boundary(f.state)
	var free := BattleSystem.candidate_sources(f.repo, f.state, 9, f.d, boundary)
	assert_eq(free.sources.map(func(s: Dictionary) -> String: return s.code), [f.c], "baseline: C fires at D")
	assert_eq(free.sources[0].firing, 100)
	helper.call("_put", f, f.a, 0, 10000 - 2 * 20 - 50, 10000, 0)
	f.state.battles[0].group_anchor_m[f.a] = [10000 - 2 * 20 - 50, 10000]
	BodyBattle._seal_private(f.repo, f.state)
	helper.free()
	boundary = BodyBattleMotion._boundary(f.state)
	var union := BattleSystem.candidate_union(f.repo, f.state, 9, f.c, boundary)
	assert_eq(union.firing, 0)
	assert_gt(int(union.melee), 0, "close defence against the attacking A")
	assert_eq(BattleSystem.candidate_sources(f.repo, f.state, 9, f.d, boundary).sources, [])

func test_classification_order_denominators_and_events_after_exposure() -> void:
	var f := _world()
	var today: int = f.state.absolute_day()
	var battle := {"id": 8, "att": [f.a, f.d], "def": [f.b], "actions": {}}
	# Both qualify: ranged 1000*1000 >= 2000*500 and shock (cavalry crew 2) 1000*1000 >= 2000*500.
	_unit(f.repo, f.state, f.a, {"archers": 1000}, 1000)
	_unit(f.repo, f.state, f.d, {"cavalry": 500}, 1000)
	var both := [{"code": f.a, "melee": 0, "firing": 1000, "impact": 0}, {"code": f.d, "melee": 1000, "firing": 0, "impact": 1000}]
	assert_eq(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, both).kind, "ranged", "ranged precedes shock")
	f.state.regiments[f.b].battle_retreat = true
	assert_eq(BattleSystem.candidate_context(f.repo, f.state, battle, f.b, both).kind, "pursuit", "withdrawal precedes both")
	f.state.regiments[f.b].erase("battle_retreat")
	# Crew denominator: archers 400 (C400), F1000, J600 -> trunc(400*600/1000) = 240;
	# 240*1000 >= 400*500 is ranged; a fit denominator (1000*500) would wrongly say melee.
	_unit(f.repo, f.state, f.a, {"archers": 400}, 1000)
	var crew := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.a, "melee": 0, "firing": 600, "impact": 0}])
	assert_eq([crew.kind, crew.exposure], ["ranged", 600])
	# Events after exposure: F1000 J667 -> exposure 667, ranged 800*667/1000 = 533, event 1250 -> 666
	# (the other order would give 667).
	_unit(f.repo, f.state, f.a, {"archers": 1000}, 1000)
	battle.event_modifiers = [{"unit": f.b, "until_day": today, "exposure_permille": 1250}]
	var ordered := BattleSystem.candidate_context(f.repo, f.state, battle, f.b, [{"code": f.a, "melee": 0, "firing": 667, "impact": 0}])
	assert_eq([ordered.kind, ordered.exposure, ordered.loss_permille], ["ranged", 667, 666])
