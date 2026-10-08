extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## One round of a battle, resolved as pure whole-number arithmetic (spec
## 2026-10-07-enemy-ai-and-battle-design §4.2-4.3): the odds, the dice, the
## tier, the losses and their spread over the regiments. Expected values are
## worked by hand.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _land_codes() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


func _heads(code: String) -> int:
	return ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))


func test_odds_permille() -> void:
	assert_eq(BattleSystem.odds_permille(3000, 1000), 750)   # 1000 x 3000 / 4000
	assert_eq(BattleSystem.odds_permille(0, 0), 500)
	assert_eq(BattleSystem.odds_permille(0, 900), 0)
	assert_eq(BattleSystem.odds_permille(900, 0), 1000)


func test_eff_permille() -> void:
	assert_eq(BattleSystem.eff_permille(600, 700, 300), 660)    # 600 + 200 x 300 / 1000
	assert_eq(BattleSystem.eff_permille(900, 1000, 300), 1000)  # 900 + 150 = 1050, clamped
	assert_eq(BattleSystem.eff_permille(50, 0, 300), 0)         # 50 - 150, clamped
	assert_eq(BattleSystem.eff_permille(500, 500, 300), 500)


func test_tier_edges() -> void:
	assert_eq(BattleSystem.tier_of(repo, 0)["tier"], repo.battle_outcomes[0]["tier"])
	assert_eq(BattleSystem.tier_of(repo, 199)["tier"], repo.battle_outcomes[0]["tier"])
	assert_eq(BattleSystem.tier_of(repo, 200)["tier"], repo.battle_outcomes[1]["tier"])
	assert_eq(BattleSystem.tier_of(repo, 999)["tier"], repo.battle_outcomes[4]["tier"])
	assert_eq(BattleSystem.tier_of(repo, 1000)["tier"], repo.battle_outcomes[4]["tier"],
		"1000 belongs to the last tier")


func test_split_losses() -> void:
	assert_eq(BattleSystem.split_losses(1000, 100, 700), {"lost": 100, "wounded": 70, "dead": 30})
	var small := BattleSystem.split_losses(7, 100, 700)   # 7 x 100 / 1000 = 0
	assert_eq(int(small["lost"]), 0)
	assert_eq(int(small["dead"]) + int(small["wounded"]), int(small["lost"]))
	var odd := BattleSystem.split_losses(333, 150, 600)   # lost 49, wounded 29, dead 20
	assert_eq(odd, {"lost": 49, "wounded": 29, "dead": 20})


func test_largest_remainder() -> void:
	# 7 over 5:3:2 -> 3.5, 2.1, 1.4 -> floors 3,2,1 and the one left to .5
	assert_eq(BattleSystem.apportion([5, 3, 2], 7), [4, 2, 1])
	# ties go to the earlier: 2 over 1:1:1 -> the first two
	assert_eq(BattleSystem.apportion([1, 1, 1], 2), [1, 1, 0])
	assert_eq(BattleSystem.apportion([0, 0], 5), [0, 0], "no weight, nothing to give")
	assert_eq(BattleSystem.apportion([4, 6], 0), [0, 0])


func test_roll_is_deterministic_and_order_free() -> void:
	var a := ["b_reg", "a_reg", "c_reg"]
	var b := ["y_reg", "x_reg"]
	var r := BattleSystem.roll(7, a, b, 100, 1)
	assert_between(r, 0, 999)
	assert_eq(BattleSystem.roll(7, a, b, 100, 1), r)
	assert_eq(BattleSystem.roll(7, ["c_reg", "b_reg", "a_reg"], ["x_reg", "y_reg"], 100, 1), r,
		"the order the codes come in does not matter")
	assert_eq(a, ["b_reg", "a_reg", "c_reg"], "the caller's array is left as it was")
	var seen := {}
	for day in range(100, 112):
		seen[BattleSystem.roll(7, a, b, day, 1)] = true
	assert_gt(seen.size(), 1, "another day, another roll")
	var rounds := {}
	for n in range(1, 8):
		rounds[BattleSystem.roll(7, a, b, 100, n)] = true
	assert_gt(rounds.size(), 1, "another round, another roll")


func test_roll_leaves_game_rng_alone() -> void:
	var s := SuiteData.campaign(repo, 7)
	var before := s.rng.to_dict().duplicate(true)
	for day in range(1, 10):
		BattleSystem.roll(7, ["a"], ["b"], day, 1)
	assert_eq(s.rng.to_dict(), before, "the dice are a hash, never a draw")


func test_side_power_sums_and_stance_scales_the_defender_only() -> void:
	var s := SuiteData.campaign(repo, 7)
	var codes := _land_codes().slice(0, 2)
	var steady := func(_c: String) -> String: return "steady"
	var hold := func(_c: String) -> String: return "hold"
	var sum_def := 0
	var sum_att := 0
	for c: String in codes:
		sum_def += ArmySystem.power(repo, s, c, "defend")
		sum_att += ArmySystem.power(repo, s, c, "attack")
	assert_gt(sum_def, 0)
	assert_eq(BattleSystem.side_power(repo, s, codes, steady, false), sum_def)
	assert_eq(BattleSystem.side_power(repo, s, codes, steady, true), sum_att)
	# hold: defence x 1150 / 1000, per regiment, whole
	var held := 0
	for c: String in codes:
		@warning_ignore("integer_division")
		held += ArmySystem.power(repo, s, c, "defend") * int(repo.battle_stances["hold"]["defence_permille"]) / 1000
	assert_eq(BattleSystem.side_power(repo, s, codes, hold, false), held)
	assert_eq(BattleSystem.side_power(repo, s, codes, hold, true), sum_att, "the attacker's power ignores the stance")


func test_apply_round_conserves_heads() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code: String = _land_codes()[0]
	var heads := _heads(code)
	var tier := {"attacker_loss_permille": 100, "defender_loss_permille": 0, "wounded_share_permille": 700,
		"attacker_morale": -10, "defender_morale": 4}
	var morale_before := int(s.regiments[code]["morale"])
	var res := BattleSystem.apply_round(repo, s, [code], [], tier, "lost the field at the ford")
	var st: Dictionary = s.regiments[code]
	var lost := heads * 100 / 1000
	var wounded := lost * 700 / 1000
	assert_eq(int(st["wounded"]), wounded)
	assert_eq(int(st["dead"]), lost - wounded)
	assert_eq(int(st["morale"]), morale_before - 10)
	var fit := ArmySystem.fit_heads(heads, st)
	assert_gte(fit, 0)
	assert_eq(int(st["dead"]) + int(st["wounded"]) + fit, heads)
	assert_eq(int(res[code]["dead"]), lost - wounded)
	assert_eq(int(res[code]["wounded"]), wounded)
	assert_eq(int(res[code]["morale"]), -10)
	assert_eq(String(res[code]["reason"]), "lost the field at the ford")
	# the arms scale through fit: a thinner regiment has less power
	assert_lt(ArmySystem.fit_permille(repo, s, code), 1000)


func test_apply_round_spreads_a_side_by_fit_heads() -> void:
	var s := SuiteData.campaign(repo, 7)
	var codes := _land_codes().slice(0, 3)
	var total := 0
	var weights: Array = []
	for c: String in codes:
		weights.append(_heads(c))
		total += _heads(c)
	var tier := {"attacker_loss_permille": 0, "defender_loss_permille": 130, "wounded_share_permille": 500,
		"attacker_morale": 0, "defender_morale": -5}
	var lost_total := total * 130 / 1000
	var lost_each := BattleSystem.apportion(weights, lost_total)
	var wounded_each := BattleSystem.apportion(lost_each, lost_total * 500 / 1000)
	BattleSystem.apply_round(repo, s, [], codes, tier, "held the ridge")
	var dead_sum := 0
	var wounded_sum := 0
	for i in codes.size():
		var st: Dictionary = s.regiments[codes[i]]
		assert_eq(int(st["wounded"]), int(wounded_each[i]), "wounded of %s" % codes[i])
		assert_eq(int(st["dead"]), int(lost_each[i]) - int(wounded_each[i]), "dead of %s" % codes[i])
		assert_eq(int(st["dead"]) + int(st["wounded"]) + ArmySystem.fit_heads(_heads(codes[i]), st), _heads(codes[i]))
		dead_sum += int(st["dead"])
		wounded_sum += int(st["wounded"])
	assert_eq(dead_sum + wounded_sum, lost_total, "the side's loss is exactly what the tier says")


func test_apply_round_zero_heads_no_divide() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code: String = _land_codes()[0]
	var reg := ArmySystem.regiment(repo, code, s)   # the campaign's own row
	for arm: String in repo.world_table("military", "unit_types"):
		reg[arm] = 0
	var tier := {"attacker_loss_permille": 150, "defender_loss_permille": 30, "wounded_share_permille": 600,
		"attacker_morale": -20, "defender_morale": 5}
	var res := BattleSystem.apply_round(repo, s, [code], [], tier, "nothing to lose")
	var st: Dictionary = s.regiments[code]
	assert_eq(int(st["wounded"]), 0)
	assert_eq(int(st.get("dead", 0)), 0)
	assert_eq(int(res[code]["dead"]), 0)
	assert_gte(int(st["morale"]), 0)


func test_apply_round_hits_a_foe_in_its_own_state() -> void:
	var s := SuiteData.campaign(repo, 7)
	var foe := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	var heads := _heads(foe)
	s.foes[foe] = ArmySystem.starting_state(repo, ArmySystem.regiment(repo, foe))
	var tier := {"attacker_loss_permille": 0, "defender_loss_permille": 200, "wounded_share_permille": 600,
		"attacker_morale": 0, "defender_morale": -20}
	BattleSystem.apply_round(repo, s, [], [foe], tier, "broken at the ford")
	var lost := heads * 200 / 1000
	assert_eq(int(s.foes[foe]["wounded"]), lost * 600 / 1000)
	assert_eq(int(s.foes[foe]["dead"]), lost - lost * 600 / 1000)
	assert_false(s.regiments.has(foe), "a foe is never written into the player's regiments")


func test_morale_stays_within_bounds() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code: String = _land_codes()[0]
	s.regiments[code]["morale"] = 3
	var tier := {"attacker_loss_permille": 0, "defender_loss_permille": 0, "wounded_share_permille": 0,
		"attacker_morale": -20, "defender_morale": 5}
	var res := BattleSystem.apply_round(repo, s, [code], [], tier, "rout")
	assert_eq(int(s.regiments[code]["morale"]), 0)
	assert_eq(int(res[code]["morale"]), -3, "the change that really happened")
	s.regiments[code]["morale"] = 98
	BattleSystem.apply_round(repo, s, [], [code], tier, "rally")
	assert_eq(int(s.regiments[code]["morale"]), 100)


func test_a_foe_stands_where_its_own_state_says() -> void:
	var s := SuiteData.campaign(repo, 7)
	var foe := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	var st := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, foe))
	st["x_m"] = 12_000
	st["y_m"] = 34_000
	s.foes[foe] = st
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, foe))
	assert_eq(ArmySystem.pack_to_metres(repo, at), Vector2i(12_000, 34_000))


func test_side_power_scales_by_height_against_the_mean_of_the_enemy() -> void:
	var s := SuiteData.campaign(repo, 7)
	var codes := _land_codes()
	var steady := func(_c: String) -> String: return "steady"
	var pair: Array = []
	for a: String in codes:
		for b: String in codes:
			var delta := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, a), s) \
				- ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, b), s)
			if absi(delta) >= 100 and pair.is_empty():
				pair = [a, b, delta]
	if pair.is_empty():
		pending("no two land regiments of the pack stand 100 m apart")
		return
	var a: String = pair[0]
	var b: String = pair[1]
	var factor := ArmySystem.height_factor(repo, int(pair[2]))
	assert_ne(factor, 1000)
	@warning_ignore("integer_division")
	var want := ArmySystem.power(repo, s, a, "attack") * factor / 1000
	assert_eq(BattleSystem.side_power(repo, s, [a], steady, true, [b]), want)
	assert_eq(BattleSystem.side_power(repo, s, [a], steady, true), ArmySystem.power(repo, s, a, "attack"),
		"with no enemy named there is no height factor")


func test_a_tie_goes_to_the_earlier_code_whatever_order_the_side_is_listed_in() -> void:
	var s := SuiteData.campaign(repo, 7)
	var two := _land_codes().slice(0, 2)   # sorted: two[0] < two[1]
	for c: String in two:
		var reg := ArmySystem.regiment(repo, c, s)   # the campaign's own row
		var kept := false
		for arm: String in repo.world_table("military", "unit_types"):
			if not kept and int(float(reg.get(arm, 0))) > 0:
				reg[arm] = 500
				kept = true
			else:
				reg[arm] = 0
		assert_eq(ArmySystem.headcount(repo, reg), 500)
	# 1000 fit x 1 / 1000 = ONE man lost, all dead: two equal shares of 0.5
	var tier := {"attacker_loss_permille": 1, "defender_loss_permille": 0, "wounded_share_permille": 0,
		"attacker_morale": 0, "defender_morale": 0}
	BattleSystem.apply_round(repo, s, [two[1], two[0]], [], tier, "a tie")
	assert_eq(int(s.regiments[two[0]].get("dead", 0)), 1, "the earlier code takes the man")
	assert_eq(int(s.regiments[two[1]].get("dead", 0)), 0)
