class_name BattleSystem
extends RefCounted
## One ROUND of a battle as pure whole-number arithmetic (spec
## docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md §4.2-4.3):
##
##   A, D   = the sides' powers (ArmySystem.power, the height factor and the
##            defender's stance in), odds = 1000 x A / (A + D)
##   roll   = a hash of the two sides, the day and the round, 0..999 — never a
##            draw from GameState.rng, so a battle moves no other seeded roll
##   eff    = clamp(odds + (roll - 500) x battle_variance_permille / 1000)
##   tier   = the data/battle_outcomes.csv row eff falls in
##
## A tier's losses first become WOUNDED (they return a share a month), the rest
## are DEAD. Both are counts beside the pack's immutable headcount
## (regiment state `wounded` and `dead`); the arms scale through the fit heads
## (ArmySystem.fit_heads), so nothing is split per arm. Every number is whole,
## every spread is by largest remainder in code order.


## 0..999: a hash of (seed, the two sides' codes SORTED, the absolute day, the
## round). The inputs are sorted copies, so the order the caller lists a side
## in is never a different battle. Touches no engine RNG.
static func roll(seed_value: int, side_a: Array, side_b: Array, day: int, round_no: int) -> int:
	var a := side_a.duplicate()
	var b := side_b.duplicate()
	a.sort()
	b.sort()
	return posmod(hash([seed_value, a, b, day, round_no]), 1000)


## The roll's pull on the odds, per mille: odds + (roll - 500) x variance / 1000,
## held to 0..1000.
static func eff_permille(odds_permille_value: int, roll_value: int, variance_permille: int) -> int:
	@warning_ignore("integer_division")  # whole per-mille
	return clampi(odds_permille_value + (roll_value - 500) * variance_permille / 1000, 0, 1000)


## The outcome row (`data/battle_outcomes.csv`) with eff_min <= eff < eff_max;
## 1000 belongs to the last row. {} with no table.
static func tier_of(repo: DataRepository, eff: int) -> Dictionary:
	var rows := repo.battle_outcomes
	for row: Dictionary in rows:
		if eff >= int(row["eff_min"]) and eff < int(row["eff_max"]):
			return row
	return {} if rows.is_empty() else rows.back()


## The attacker's share of the two sides' power, per mille; 500 when neither
## side has any.
static func odds_permille(attack_power: int, defend_power: int) -> int:
	if attack_power + defend_power <= 0:
		return 500
	@warning_ignore("integer_division")  # whole per-mille
	return 1000 * attack_power / (attack_power + defend_power)


## One side's power: each regiment's ArmySystem.power in the attack or defend
## stance on the ground it stands on, scaled by the height factor against the
## MEAN height of `enemy_codes` (none given: no height factor); a DEFENDING
## regiment's power is further scaled by its stance's defence_permille
## (`stance_of` is a Callable code -> stance name; an unknown stance is 1000).
static func side_power(repo: DataRepository, state: GameState, codes: Array, stance_of: Callable,
		attacking: bool, enemy_codes: Array = []) -> int:
	var enemy_m := 0
	for e: Variant in enemy_codes:
		enemy_m += ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, String(e)), state)
	if not enemy_codes.is_empty():
		@warning_ignore("integer_division")  # whole metres
		enemy_m /= enemy_codes.size()
	var total := 0
	for c: Variant in codes:
		var code := String(c)
		var p := ArmySystem.power(repo, state, code, "attack" if attacking else "defend")
		if not enemy_codes.is_empty():
			var delta := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, code), state) - enemy_m
			@warning_ignore("integer_division")  # whole power, per-mille height factor
			p = p * ArmySystem.height_factor(repo, delta) / 1000
		if not attacking:
			var stance := String(stance_of.call(code))
			var def_permille := int((repo.battle_stances.get(stance, {}) as Dictionary).get("defence_permille", 1000))
			@warning_ignore("integer_division")  # whole power, per-mille stance
			p = p * def_permille / 1000
		total += p
	return total


## A side's `fit` heads lost at `loss_permille`, and the lost part's split:
## {lost, wounded, dead} with lost = fit x permille / 1000, wounded = lost x
## share / 1000 and dead the rest.
static func split_losses(fit: int, loss_permille: int, wounded_share_permille: int) -> Dictionary:
	@warning_ignore("integer_division")  # whole heads
	var lost := maxi(0, fit) * loss_permille / 1000
	@warning_ignore("integer_division")  # whole heads
	var wounded := lost * wounded_share_permille / 1000
	return {"lost": lost, "wounded": wounded, "dead": lost - wounded}


## `total` shared out over `weights` by largest remainder (the method of
## MapManors.apportion, in whole numbers only): each gets the floor of its
## share, the units left go to the largest remainders, ties to the earlier
## index. All zeros when there is nothing to give or no weight to give by.
static func apportion(weights: Array, total: int) -> Array:
	var out: Array = []
	var sum := 0
	for w: Variant in weights:
		sum += maxi(0, int(w))
	out.resize(weights.size())
	out.fill(0)
	if total <= 0 or sum <= 0:
		return out
	var rem: Array = []
	var given := 0
	for i in weights.size():
		var share := total * maxi(0, int(weights[i]))
		@warning_ignore("integer_division")  # the floor of the share
		out[i] = share / sum
		rem.append(share % sum)
		given += int(out[i])
	var order: Array = range(weights.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return a < b if rem[a] == rem[b] else rem[a] > rem[b])
	for k in total - given:
		out[order[k]] += 1
	return out


## The state entry a round writes: a foe's own, else the player's regiment's
## (seeded if it has none yet); {} for a code that is neither.
static func _entry_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	if ArmySystem.is_foe(state, code):
		return state.foes[code]
	ArmySystem.ensure(repo, state)
	return state.regiments.get(code, {})


## One side's round: `loss_permille` of its fit heads lost, spread over its
## regiments by fit heads (a regiment with no fit men is spared), the wounded
## of it by what each lost; then morale moves by `morale_delta`, held to
## 0..100. Writes `wounded`, `dead` and `morale` into each regiment's state and
## returns code -> {dead, wounded, morale (the change that really happened),
## reason}.
static func _apply_side(repo: DataRepository, state: GameState, codes: Array, loss_permille: int,
		wounded_share_permille: int, morale_delta: int, reason: String, out: Dictionary) -> void:
	var live: Array = []
	var fits: Array = []
	var total_fit := 0
	# code order, not the order the caller listed them in: a tie in the spread
	# goes to the earlier code whatever dictionary the side came from
	var ordered: Array = []
	for c: Variant in codes:
		ordered.append(String(c))
	ordered.sort()
	for c: Variant in ordered:
		var code := String(c)
		var entry := _entry_of(repo, state, code)
		if entry.is_empty():
			continue
		var fit := ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, code)), entry)
		live.append(code)
		fits.append(fit)
		total_fit += fit
	var split := split_losses(total_fit, loss_permille, wounded_share_permille)
	var lost_each := apportion(fits, int(split["lost"]))
	var wounded_each := apportion(lost_each, int(split["wounded"]))
	for i in live.size():
		var code := String(live[i])
		var entry := _entry_of(repo, state, code)
		var wounded := int(wounded_each[i])
		var dead := int(lost_each[i]) - wounded
		entry["wounded"] = int(entry.get("wounded", 0)) + wounded
		entry["dead"] = int(entry.get("dead", 0)) + dead
		var before := int(entry.get("morale", 0))
		entry["morale"] = clampi(before + morale_delta, 0, 100)
		out[code] = {"dead": dead, "wounded": wounded, "morale": int(entry["morale"]) - before,
			"reason": reason}


## Apply a tier to a round: the attackers take attacker_loss_permille and
## attacker_morale, the defenders the defender's. `reason` rides in each
## regiment's result (the battle report prints it, architecture invariant 4).
## Returns code -> {dead, wounded, morale, reason}.
static func apply_round(repo: DataRepository, state: GameState, codes_att: Array, codes_def: Array,
		tier: Dictionary, reason: String) -> Dictionary:
	var out: Dictionary = {}
	var share := int(tier.get("wounded_share_permille", 0))
	_apply_side(repo, state, codes_att, int(tier.get("attacker_loss_permille", 0)), share,
		int(tier.get("attacker_morale", 0)), reason, out)
	_apply_side(repo, state, codes_def, int(tier.get("defender_loss_permille", 0)), share,
		int(tier.get("defender_morale", 0)), reason, out)
	return out
