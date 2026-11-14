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
