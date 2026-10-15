class_name BattleSystem
extends RefCounted
## Battles: one ROUND as pure whole-number arithmetic (below), and a
## battle's life — contact, rounds, who leaves, the end — further down
## (settle_day). The round (spec
## docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md §4.2-4.3):
##
##   A, D   = the sides' powers (ArmySystem.power, the height factor and the
##            defender's stance in), odds = 1000 x A / (A + D)
##   roll   = a hash of the two sides, the day and the round, 0..999 — never a
##            draw from GameState.rng, so a battle moves no other seeded roll
##   eff    = clamp(odds + (roll - 500) x battle_variance_permille / 1000)
##   tier   = the data/battle/battle_outcomes.csv row eff falls in
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


## The outcome row (`data/battle/battle_outcomes.csv`) with eff_min <= eff < eff_max;
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
## (`stance_fn` is a Callable code -> stance name; an unknown stance is 1000).
static func side_power(repo: DataRepository, state: GameState, codes: Array, stance_fn: Callable,
		attacking: bool, enemy_codes: Array = []) -> int:
	var enemy_m := 0
	for e: Variant in enemy_codes:
		enemy_m += ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, String(e), state), state)
	if not enemy_codes.is_empty():
		@warning_ignore("integer_division")  # whole metres
		enemy_m /= enemy_codes.size()
	var total := 0
	for c: Variant in codes:
		var code := String(c)
		var p := ArmySystem.power(repo, state, code, "attack" if attacking else "defend")
		if not enemy_codes.is_empty():
			var delta := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, code, state), state) - enemy_m
			@warning_ignore("integer_division")  # whole power, per-mille height factor
			p = p * ArmySystem.height_factor(repo, delta) / 1000
		if not attacking:
			var stance := String(stance_fn.call(code))
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
## 0..100 — a FALL scaled by the regiment's stance's morale_decay_permille
## when `stance_fn` (code -> stance) is given, toward zero. Writes `wounded`,
## `dead` and `morale` into each regiment's state and
## returns code -> {dead, wounded, morale (the change that really happened),
## reason}.
static func _apply_side(repo: DataRepository, state: GameState, codes: Array, loss_permille: int,
		wounded_share_permille: int, morale_delta: int, reason: String, out: Dictionary,
		stance_fn: Callable = Callable()) -> void:
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
		var fit := ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, code, state)), entry)
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
		var fall := morale_delta
		if fall < 0 and stance_fn.is_valid():
			@warning_ignore("integer_division")  # whole points, toward zero
			fall = fall * int(_stance_row(repo, String(stance_fn.call(code))).get("morale_decay_permille", 1000)) / 1000
		entry["morale"] = clampi(before + fall, 0, 100)
		out[code] = {"dead": dead, "wounded": wounded, "morale": int(entry["morale"]) - before,
			"reason": reason}


## Apply a tier to a round: the attackers take attacker_loss_permille and
## attacker_morale, the defenders the defender's. `reason` rides in each
## regiment's result (the battle report prints it, architecture invariant 4).
## `stance_fn` (code -> stance name), when given, slows each regiment's morale
## fall by its stance. Returns code -> {dead, wounded, morale, reason}.
static func apply_round(repo: DataRepository, state: GameState, codes_att: Array, codes_def: Array,
		tier: Dictionary, reason: String, stance_fn: Callable = Callable()) -> Dictionary:
	var out: Dictionary = {}
	var share := int(tier.get("wounded_share_permille", 0))
	_apply_side(repo, state, codes_att, int(tier.get("attacker_loss_permille", 0)), share,
		int(tier.get("attacker_morale", 0)), reason, out, stance_fn)
	_apply_side(repo, state, codes_def, int(tier.get("defender_loss_permille", 0)), share,
		int(tier.get("defender_morale", 0)), reason, out, stance_fn)
	return out


## --- A battle's life (spec §4.1, §4.4) --------------------------------------
##
## A battle is a Dictionary in GameState.battles: {id (from foe_next_id), att,
## def (regiment codes, in the order they came), start_day (absolute),
## rounds (fought so far), place_x_m, place_y_m (whole metres), town ("" in
## the open)}. Hostility is the player's regiments against GameState.foes.
## settle_day runs once a day, after the columns march and the couriers ride:
## contacts first, then a round for every battle in id order, then who leaves
## and which battles are over; last, the stances couriers delivered today take
## hold, so a stance landing on day N fights from day N+1. Every number is a
## whole number from data; the dice are roll(), never GameState.rng.

const SIDES := ["att", "def"]


## A regiment's stored state, a foe's or the player's; {} when it has none.
## Never seeds.
static func _stored(state: GameState, code: String) -> Dictionary:
	if state.foes.has(code):
		return state.foes[code]
	return state.regiments.get(code, {})


## The stance a regiment fights in today (ArmySystem.STANCE_DEFAULT when its
## state names none — an old save's, or a foe's the AI never set).
static func stance_of(state: GameState, code: String) -> String:
	return String(_stored(state, code).get("stance", ArmySystem.STANCE_DEFAULT))


## The battle stance of one of the CROWN's regiments in words, for its card
## and the folio: the battle_stances.csv label of today's stance, and a
## stance a courier has landed for tomorrow (`stance_next`) beside it
## ("Hold, Evade from tomorrow"); "" for a foe or a regiment with no state —
## a foe's stance is not the crown's to read.
static func stance_words(repo: DataRepository, state: GameState, code: String) -> String:
	if state == null or not state.regiments.has(code):
		return ""
	var now := String(_stance_row(repo, stance_of(state, code)).get("label", stance_of(state, code)))
	var e: Dictionary = state.regiments[code]
	if not e.has("stance_next") or String(e["stance_next"]) == stance_of(state, code):
		return now
	var next := String(e["stance_next"])
	return "%s, %s from tomorrow" % [now, String(_stance_row(repo, next).get("label", next))]


## A stance's row of data/battle/battle_stances.csv; the default stance's for an
## unknown name.
static func _stance_row(repo: DataRepository, stance: String) -> Dictionary:
	return repo.battle_stances.get(stance, repo.battle_stances.get(ArmySystem.STANCE_DEFAULT, {}))


## The battle `code` fights in, {} when none.
static func battle_of(state: GameState, code: String) -> Dictionary:
	for b: Dictionary in state.battles:
		if code in (b["att"] as Array) or code in (b["def"] as Array):
			return b
	return {}


## The battle with this id, {} when none.
static func battle_by_id(state: GameState, id: int) -> Dictionary:
	for b: Dictionary in state.battles:
		if int(b["id"]) == id:
			return b
	return {}


## Where a regiment stands, in whole metres.
static func _at_m(repo: DataRepository, state: GameState, code: String) -> Vector2i:
	var e := _stored(state, code)
	if e.has("x_m"):
		return Vector2i(int(e["x_m"]), int(e["y_m"]))
	return ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state)))


## True when two points are no more than `metres` apart (whole numbers).
static func _within(a: Vector2i, b: Vector2i, metres: int) -> bool:
	var dx := int(b.x) - int(a.x)
	var dy := int(b.y) - int(a.y)
	return dx * dx + dy * dy <= metres * metres


## A land regiment with state and fit men that is not falling back from a
## battle (`disengaging`, cleared when its march ends) nor drawing breath
## after one (`disengaged_until`: the LAST absolute day of its pause, so
## today <= it means no contact), nor a foe
## whose host is going home (`homeward`).
static func _can_fight(repo: DataRepository, state: GameState, code: String) -> bool:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return false
	if homeward(state, code):
		return false
	var e := _stored(state, code)
	if e.is_empty() or int(e.get("disengaging", 0)) == 1:
		return false
	if int(e.get("disengaged_until", 0)) >= state.absolute_day():
		return false
	return ArmySystem.fit_heads(ArmySystem.headcount(repo, reg), e) > 0


## True for a foe whose host (GameState.ai_hosts) is going home — mode RETREAT
## or WITHDRAW (EnemyAi.HOMEWARD): it makes no contact, joins no battle, and
## leaves any battle it is in before the day's round (`_withdraw_homeward`).
static func homeward(state: GameState, code: String) -> bool:
	var host := String((state.foes.get(code, {}) as Dictionary).get("host", ""))
	return host != "" and state.ai_hosts.has(host) \
		and String((state.ai_hosts[host] as Dictionary).get("mode", "")) in EnemyAi.HOMEWARD


## Takes every foe of a host going home out of the battles it is in, before
## the day's contacts and rounds, so the day it turns home it strikes no more
## blows. A battle left with no foe ENDS (why "withdrawn", the crown's side
## holding the field) and its survivors draw breath as after a draw (`_pause`);
## the homeward foes pause too. Battles in id order.
static func _withdraw_homeward(repo: DataRepository, state: GameState, events: Array) -> void:
	var order: Array = state.battles.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var over: Array = []
	for b: Dictionary in order:
		var gone: Array = []
		for side: String in SIDES:
			for c: Variant in (b[side] as Array).duplicate():
				if homeward(state, String(c)):
					(b[side] as Array).erase(c)
					gone.append(String(c))
		if gone.is_empty():
			continue
		for c: String in gone:
			_pause(repo, state, c)
		var foes_left := false
		for side: String in SIDES:
			for c: Variant in b[side]:
				foes_left = foes_left or ArmySystem.is_foe(state, String(c))
		if foes_left:
			continue
		_end(repo, state, b, "withdrawn", events)
		over.append(int(b["id"]))
	if not over.is_empty():
		state.battles = state.battles.filter(func(b: Dictionary) -> bool: return not int(b["id"]) in over)


## The town a foe's host besieges while it waits for its assault: its host
## (GameState.ai_hosts) in mode "SIEGE" with the `assault` flag down; "" any
## other time. Such a foe does not fight that town's GARRISON (the garrison
## waits behind its walls for the assault, the ordinary town battle that
## SiegeSystem lets through with the flag), but meets any other regiment of
## the player's as ever — a relief force in the open is fought in the field.
static func siege_town_of(state: GameState, code: String) -> String:
	var host := String((state.foes.get(code, {}) as Dictionary).get("host", ""))
	if host == "" or not state.ai_hosts.has(host):
		return ""
	var h: Dictionary = state.ai_hosts[host]
	if String(h.get("mode", "")) != "SIEGE" or int(h.get("assault", 0)) == 1:
		return ""
	return String(h.get("target_id", ""))


## The town a foe assaults when it stands within the reach
## (data/army/army_town_reach.csv) of `town`, the held town a player unit
## garrisons (ArmyGround.garrison_town: its seat or camp); "" otherwise.
static func _town_contact(repo: DataRepository, state: GameState, town: String, f: String) -> String:
	if town == "":
		return ""
	var b: Dictionary = repo.burgs[town]
	var at := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, f, state))
	var away := at.distance_to(Vector2(float(b["x"]), float(b["y"])))
	if away <= ArmySystem.town_reach_px(repo, b):
		return town
	# a column halted before the unit on a village's point stands the two arms'
	# radii off it, outside the village's reach: it touches within a few metres of that
	if ArmyGround.clearance_on(repo):
		var seat := ArmySystem.regiment(repo, ArmyGround.seat_of(repo, state, town), state)
		var r_seat := ArmyGround.max_radius(repo) if seat.is_empty() else ArmyGround.unit_radius(repo, seat)
		var limit := r_seat + ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, f, state)) \
			+ int(repo.bal("army_clearance_touch_m"))
		if roundi(away * float(ArmySystem.metres_per_pack_px(repo))) <= limit:
			return town
	return ""


## Whether foe `f`'s host has the assault on `town` up (SIEGE, the flag raised).
static func _assaults(state: GameState, f: String, town: String) -> bool:
	if town == "":
		return false
	var host := String((state.foes.get(f, {}) as Dictionary).get("host", ""))
	var h: Dictionary = state.ai_hosts.get(host, {})
	return String(h.get("mode", "")) == "SIEGE" and int(h.get("assault", 0)) == 1 and String(h.get("target_id", "")) == town


## The battle fought at `town` (the earliest id), {} when none.
static func _battle_at(state: GameState, town: String) -> Dictionary:
	var out: Dictionary = {}
	for b: Dictionary in state.battles:
		if String(b["town"]) == town and (out.is_empty() or int(b["id"]) < int(out["id"])):
			out = b
	return out


## Halt a regiment where it stands: a column in a battle does not march. With
## `toward` (whole metres) a unit that faces nowhere yet turns to it (a halt
## in front of the enemy already faces it, and a held front keeps its own).
static func _halt(state: GameState, code: String, toward := Vector2i(-1, -1)) -> void:
	var e := _stored(state, code)
	if e.is_empty():
		return
	e["order"] = ArmySystem.ORDER_GARRISON
	e["dest_x_m"] = int(e.get("x_m", 0))
	e["dest_y_m"] = int(e.get("y_m", 0))
	ArmySystem.drop_hold(e)   # caught on the road: no front (front-line ruling 3)
	if toward != Vector2i(-1, -1) and not e.has("facing_deg"):
		e["facing_deg"] = WarFront.facing_deg(Vector2(toward - Vector2i(int(e.get("x_m", 0)), int(e.get("y_m", 0)))))


## The side of battle `b` that `code` would fight on: the side already
## holding its own allegiance, else the free one; "" when neither fits.
static func _side_for(state: GameState, b: Dictionary, code: String) -> String:
	var foe := ArmySystem.is_foe(state, code)
	for side: String in SIDES:
		for c: Variant in b[side]:
			if ArmySystem.is_foe(state, String(c)) == foe:
				return side
	for side: String in SIDES:
		if (b[side] as Array).is_empty():
			return side
	return ""


## Bring `code` into battle `battle_id` on `side` ("att" / "def"): refused
## (false) for an unknown battle or side, a regiment with no state, one
## already in a battle, a side of the other allegiance, and a side already
## holding battle_max_units regiments. A joiner halts.
static func join(repo: DataRepository, state: GameState, battle_id: int, code: String, side: String) -> bool:
	var b := battle_by_id(state, battle_id)
	if b.is_empty() or not side in SIDES or _stored(state, code).is_empty():
		return false
	if not battle_of(state, code).is_empty() or _side_for(state, b, code) != side:
		return false
	var list: Array = b[side]
	if list.size() >= int(repo.bal("battle_max_units")):
		return false
	list.append(code)
	_halt(state, code)
	return true


## Find the day's contacts (§4.1) and start or join battles; fights no round.
static func detect_contacts(repo: DataRepository, state: GameState) -> void:
	_detect(repo, state, [])


static func _detect(repo: DataRepository, state: GameState, events: Array) -> void:
	ArmySystem.ensure(repo, state)
	# a column that fell back is fair game again once its march has ended
	for table: Dictionary in [state.regiments, state.foes]:
		for code: Variant in table:
			var e: Dictionary = table[code]
			if e.has("disengaging") and String(e.get("order", "")) != ArmySystem.ORDER_MARCH:
				e.erase("disengaging")
	var mine: Array = state.regiments.keys().filter(func(c: Variant) -> bool:
		return _can_fight(repo, state, String(c)))
	var theirs: Array = state.foes.keys().filter(func(c: Variant) -> bool:
		return _can_fight(repo, state, String(c)))
	mine.sort()
	theirs.sort()
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	var garrisons: Dictionary = {}   # the town each of mine garrisons ("" none), read once
	for pc: Variant in mine:
		garrisons[pc] = ArmyGround.garrison_town(repo, state, String(pc))
	for fc: Variant in theirs:
		var f := String(fc)
		var held_off := siege_town_of(state, f)
		for pc: Variant in mine:
			var p := String(pc)
			if held_off != "" and String(garrisons[pc]) == held_off:
				continue    # a besieged town's garrison waits for the assault
			# read fresh: a column halted in a town's reach today is its garrison now
			var town := _town_contact(repo, state, ArmyGround.garrison_town(repo, state, p), f)
			if town == "" and _assaults(state, f, String(garrisons[pc])) \
					and _within(_at_m(repo, state, f), _at_m(repo, state, p), reach):
				town = String(garrisons[pc])   # the assault is up: a besieger at hand of the garrison storms it, never a field battle
			if town == "" and not _within(_at_m(repo, state, f), _at_m(repo, state, p), reach):
				continue
			var bf := battle_of(state, f)
			var bp := battle_of(state, p)
			var at_town := _battle_at(state, town) if town != "" else {}
			if not at_town.is_empty() and bf.is_empty() and bp.is_empty():
				# one battle a town: a town contact joins the assault already
				# fought there (each side's cap holding); one left out waits
				_join_event(repo, state, at_town, f, events)
				_join_event(repo, state, at_town, p, events)
			elif bf.is_empty() and bp.is_empty():
				_start(repo, state, p, f, town, events)
			elif bf.is_empty():
				_join_event(repo, state, bp, f, events)
			elif bp.is_empty():
				_join_event(repo, state, bf, p, events)


static func _join_event(repo: DataRepository, state: GameState, b: Dictionary, code: String, events: Array) -> void:
	var side := _side_for(state, b, code)
	if side != "" and join(repo, state, int(b["id"]), code, side):
		events.append({"kind": "join", "battle_id": int(b["id"]), "code": code, "side": side})


## A new battle between player regiment `p` and foe `f`: at a town the foe
## assaults; in the open the side that marched into a standing enemy attacks,
## else the foe. Fought where the defender stands (the town's point at a town).
static func _start(repo: DataRepository, state: GameState, p: String, f: String, town: String,
		events: Array) -> void:
	var pe := _stored(state, p)
	# the side that marched into a standing enemy attacks: a column that halted
	# in front of one today (halt_day, ArmySystem._halt_before) did exactly that
	var marched := String(pe.get("order", "")) == ArmySystem.ORDER_MARCH \
		or (pe.has("halt_day") and int(pe["halt_day"]) == state.absolute_day())
	var player_attacks := town == "" and marched \
		and String(_stored(state, f).get("order", "")) != ArmySystem.ORDER_MARCH
	var att: Array = [p] if player_attacks else [f]
	var def: Array = [f] if player_attacks else [p]
	var place := _at_m(repo, state, String(def[0]))
	if town != "":
		var bu: Dictionary = repo.burgs[town]
		place = ArmySystem.pack_to_metres(repo, Vector2(float(bu["x"]), float(bu["y"])))
	state.foe_next_id += 1
	var b := {"id": state.foe_next_id, "att": att, "def": def, "start_day": state.absolute_day(),
		"rounds": 0, "place_x_m": place.x, "place_y_m": place.y, "town": town}
	state.battles.append(b)
	var turn := ArmyGround.clearance_on(repo)   # the clearance's facing; none with the rule off
	_halt(state, p, _at_m(repo, state, f) if turn else Vector2i(-1, -1))
	_halt(state, f, _at_m(repo, state, p) if turn else Vector2i(-1, -1))
	events.append({"kind": "start", "battle_id": int(b["id"]), "att": att.duplicate(), "def": def.duplicate(),
		"town": town, "place_x_m": place.x, "place_y_m": place.y})


## The day's battles (§4.1): contacts, then one round for every battle in id
## order, then who leaves and which battles end; then today's delivered
## stances take hold. Returns the day's events, for the battle report:
## {kind: "start", battle_id, att, def, town, place_x_m, place_y_m},
## {kind: "join", battle_id, code, side},
## {kind: "round", battle_id, round, att_power, def_power, odds, roll, eff, tier,
##  results (apply_round's), left [{code, side, why}], att, def (who fought it,
##  before anyone left), town, place_x_m, place_y_m} and
## {kind: "end", battle_id, why ("rout_attacker" / "rout_defender" / "emptied" /
##  "rounds" / "withdrawn": the foes' host went home), winner ("att" / "def" / ""), att, def (the survivors), rounds,
##  town, place_x_m, place_y_m}.
static func prepare_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	_withdraw_homeward(repo, state, events)
	_detect(repo, state, events)
	return events


static func step_battle(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
	var events: Array = []
	var battle := battle_by_id(state, battle_id)
	if not battle.is_empty() and _fight(repo, state, battle, events):
		state.battles = state.battles.filter(func(b: Dictionary) -> bool: return int(b["id"]) != battle_id)
	return {"status": "complete", "events": events}


static func finish_day(_repo: DataRepository, state: GameState) -> void:
	settle_stances(state)


## Non-interactive battle arithmetic helper. The game uses TickEngine's
## transaction and confirms all contacts before invoking step_battle.
static func settle_day(repo: DataRepository, state: GameState) -> Array:
	if not state.day_resolution.is_empty():
		return []  # an active daily transaction exclusively owns battle stepping
	var events := prepare_day(repo, state)
	var order: Array = state.battles.map(func(b: Dictionary) -> int: return int(b["id"]))
	order.sort()
	for id: int in order:
		events.append_array(step_battle(repo, state, id)["events"])
	finish_day(repo, state)
	return events


## A stance a courier delivered (`stance_next`) becomes the regiment's stance
## — at the end of the day's battles, so it fights from the next day.
static func settle_stances(state: GameState) -> void:
	for table: Dictionary in [state.regiments, state.foes]:
		for code: Variant in table:
			var e: Dictionary = table[code]
			if e.has("stance_next"):
				e["stance"] = String(e["stance_next"])
				e.erase("stance_next")


## The battle's place in words, for the reasons and the report: `b` is a
## battle or any event carrying town, place_x_m and place_y_m.
static func place_label(repo: DataRepository, state: GameState, b: Dictionary) -> String:
	if String(b["town"]) != "":
		return String((repo.burgs.get(String(b["town"]), {}) as Dictionary).get("label", b["town"]))
	return Intel.place_label(repo, state, ArmySystem.metres_to_pack(repo,
		Vector2i(int(b["place_x_m"]), int(b["place_y_m"]))))


## One battle's day; true when it is over.
static func _fight(repo: DataRepository, state: GameState, b: Dictionary, events: Array) -> bool:
	# a regiment whose state is gone (a host taken off the map) is no longer in it
	for side: String in SIDES:
		b[side] = (b[side] as Array).filter(func(c: Variant) -> bool:
			return not _stored(state, String(c)).is_empty())
	var att: Array = b["att"]
	var def: Array = b["def"]
	if att.is_empty() or def.is_empty():
		_end(repo, state, b, "emptied", events)
		return true
	var n := int(b["rounds"]) + 1
	var stance := func(c: String) -> String: return stance_of(state, c)
	var a_pow := side_power(repo, state, att, stance, true, def)
	var d_pow := side_power(repo, state, def, stance, false, att)
	var odds := odds_permille(a_pow, d_pow)
	var r := roll(state.rng.seed_value(), att, def, state.absolute_day(), n)
	var eff := eff_permille(odds, r, int(repo.bal("battle_variance_permille")))
	var tier := tier_of(repo, eff)
	var reason := "%s at %s, the battle's day %d" % [String(tier.get("tier", "")).replace("_", " "),
		place_label(repo, state, b), n]
	var results := apply_round(repo, state, att, def, tier, reason, stance)
	b["rounds"] = n
	var left := _exits(repo, state, b, String(tier.get("rout", "none")), odds)
	events.append({"kind": "round", "battle_id": int(b["id"]), "round": n, "att_power": a_pow,
		"def_power": d_pow, "odds": odds, "roll": r, "eff": eff, "tier": String(tier.get("tier", "")),
		"results": results, "left": left, "att": att.duplicate(), "def": def.duplicate(),
		"town": String(b["town"]), "place_x_m": int(b["place_x_m"]), "place_y_m": int(b["place_y_m"])})
	var rout := String(tier.get("rout", "none"))
	if rout == "attacker" or rout == "defender":
		_end(repo, state, b, "rout_" + rout, events)
		return true
	if (b["att"] as Array).is_empty() or (b["def"] as Array).is_empty():
		_end(repo, state, b, "emptied", events)
		return true
	if n >= int(repo.bal("battle_max_rounds")):
		_end(repo, state, b, "rounds", events)
		return true
	return false


## Why a regiment leaves the battle after today's round, "" when it stays:
## "ordered" (a march order reached it), "broken" (no fit man left), "rout"
## (its side broke), "evade" (its stance leaves on contact), "retreat" (its
## side's odds below its stance's retreat_odds_permille).
static func _exit_why(repo: DataRepository, state: GameState, code: String, side: String, rout: String,
		side_odds: int) -> String:
	var e := _stored(state, code)
	if String(e.get("order", "")) == ArmySystem.ORDER_MARCH:
		return "ordered"
	if ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, code, state)), e) <= 0:
		return "broken"
	if rout == ("attacker" if side == "att" else "defender"):
		return "rout"
	var row := _stance_row(repo, stance_of(state, code))
	if bool(row.get("retreats_on_contact", false)):
		return "evade"
	if side_odds < int(row.get("retreat_odds_permille", 0)):
		return "retreat"
	return ""


## Who leaves after the round, in side then code order: each is taken out of
## the battle; one that falls back (rout, evade, retreat) marches for the
## nearest town of its own kingdom beyond battle_contact_km of the battle,
## one ordered away keeps its own march; both are `disengaging` until that
## march ends, so the same enemy does not catch them on the way.
static func _exits(repo: DataRepository, state: GameState, b: Dictionary, rout: String, odds: int) -> Array:
	var left: Array = []
	for side: String in SIDES:
		var side_odds := odds if side == "att" else 1000 - odds
		var keep: Array = []
		var codes: Array = (b[side] as Array).duplicate()
		codes.sort()
		for c: Variant in codes:
			var code := String(c)
			var why := _exit_why(repo, state, code, side, rout, side_odds)
			if why == "":
				continue
			left.append({"code": code, "side": side, "why": why})
			if why in ["rout", "evade", "retreat"]:
				_fall_back(repo, state, code, b)
			if why != "broken":
				_stored(state, code)["disengaging"] = 1
		for c: Variant in b[side]:
			if not left.any(func(l: Dictionary) -> bool: return String(l["code"]) == String(c)):
				keep.append(String(c))
		b[side] = keep
	return left


## March a regiment for the nearest town its own kingdom holds (MapOwnership)
## that lies beyond battle_contact_km of the battle's place (ties to the
## earlier town code); it halts where it is when there is none.
static func _fall_back(repo: DataRepository, state: GameState, code: String, b: Dictionary) -> void:
	var e := _stored(state, code)
	var kingdom := String(ArmySystem.regiment(repo, code, state).get("kingdom_code", ""))
	var place := Vector2i(int(b["place_x_m"]), int(b["place_y_m"]))
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	var here := _at_m(repo, state, code)
	var best := ""
	var best_d := -1
	var best_m := Vector2i.ZERO
	for t: Variant in repo.burgs:
		var town := String(t)
		var bu: Dictionary = repo.burgs[town]
		if MapOwnership.owner_of(repo, state, String(bu.get("province_code", ""))) != kingdom:
			continue
		var m := ArmySystem.pack_to_metres(repo, Vector2(float(bu["x"]), float(bu["y"])))
		if _within(place, m, reach):
			continue
		var dx := int(m.x) - int(here.x)
		var dy := int(m.y) - int(here.y)
		var d := dx * dx + dy * dy
		if best_d < 0 or d < best_d or (d == best_d and town < best):
			best = town
			best_d = d
			best_m = m
	if best == "":
		# nowhere to go: it halts, and draws breath as after a draw, so the
		# same enemy does not take it again the next morning
		_halt(state, code)
		_pause(repo, state, code)
		return
	ArmySystem.aim_entry(repo, e, best_m, ArmySystem.is_naval(repo, state, code))
	if not ArmySystem.is_foe(state, code):
		# a unit of the crown's leaves its camp and, holding a seat, empties it
		# (refilled from the camp; spec 2026-10-07-army-split-and-ground §4.4)
		ArmyGround.leave(repo, state, code)


## A regiment leaves a place it can no longer hold (a town that fell,
## SiegeSystem.capture): it marches for the nearest town of its own kingdom
## beyond battle_contact_km of `place_m`, as a column falling back from a
## battle does (`disengaging` until its march ends; it halts and pauses with
## nowhere to go).
static func march_out(repo: DataRepository, state: GameState, code: String, place_m: Vector2i) -> void:
	if _stored(state, code).is_empty():
		return
	_fall_back(repo, state, code, {"place_x_m": place_m.x, "place_y_m": place_m.y})
	_stored(state, code)["disengaging"] = 1


## Takes battle `id` off the field with no end of its own (SiegeSystem.capture:
## the town it was fought for fell under it); its regiments stay where they
## stand, halted.
static func call_off(state: GameState, id: int) -> void:
	state.battles = state.battles.filter(func(b: Dictionary) -> bool: return int(b["id"]) != id)


## No contact for `code` for exactly battle_disengage_days days after today
## (`disengaged_until` = today + N, the last day of the pause: N = 1 keeps it
## out of the next day's battles only); its orders still work.
static func _pause(repo: DataRepository, state: GameState, code: String) -> void:
	var e := _stored(state, code)
	if not e.is_empty():
		e["disengaged_until"] = state.absolute_day() + int(repo.bal("battle_disengage_days"))


## End battle `b`: its survivors stay halted where they stand (the player's
## await orders; a foe's host decides its own, EnemyAi). A battle that ran to
## battle_max_rounds is a DRAW: every survivor pauses (_pause), and if the
## two are still in contact after it a new battle starts. One its foes' host
## left ("withdrawn", `_withdraw_homeward`) goes to the side left standing,
## whose survivors pause the same.
static func _end(repo: DataRepository, state: GameState, b: Dictionary, why: String, events: Array) -> void:
	var att: Array = b["att"]
	var def: Array = b["def"]
	if why == "rounds" or why == "withdrawn":
		for side: String in SIDES:
			for c: Variant in b[side]:
				_pause(repo, state, String(c))
	var winner := ""
	match why:
		"rout_attacker":
			winner = "def"
		"rout_defender":
			winner = "att"
		"emptied", "withdrawn":
			if att.is_empty() and not def.is_empty():
				winner = "def"
			elif def.is_empty() and not att.is_empty():
				winner = "att"
	events.append({"kind": "end", "battle_id": int(b["id"]), "why": why, "winner": winner,
		"att": att.duplicate(), "def": def.duplicate(), "rounds": int(b["rounds"]), "town": String(b["town"]),
		"place_x_m": int(b["place_x_m"]), "place_y_m": int(b["place_y_m"])})
