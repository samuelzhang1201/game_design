class_name BattleSystem
extends RefCounted
## One saved RNG draw per engaged day, whole-number losses through the atomic
## personnel writer, and actual route separation for a withdrawing unit.

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


## Pending personnel retries use the actual actions frozen with their casualty plan.
static func unit_action(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> Dictionary:
	var saved: Dictionary = battle.get("pending_round", {}).get("unit_actions", {}).get(code, {})
	if not saved.is_empty():
		return saved.duplicate(true)
	if not (battle.get("pending_round", {}) as Dictionary).is_empty() and not battle["pending_round"].has("unit_actions"):
		var kind := BattleOrders.kind(battle, BattleRules.side_of(battle, code))
		return {"kind": kind, "task_id": "", "reason": "Legacy pending round retains its delivered side action"}
	var action := BattleTaskSystem.combat_action(repo, state, battle, code)
	if action["kind"] == "attack" and action["task_id"] != "":
		var reg := ArmySystem.regiment(repo, code, state)
		var bite := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, state), state.day)
		var extra := _attack_supply(repo, bite)
		if ArmySystem.fit_count(repo, state, code) <= 0 or int(_stored(state, code).get("supplies", 0)) < bite + extra:
			action["kind"] = "hold"
			action["reason"] = "Unit task holds: insufficient personnel or carried supplies"
	return action


static func _attack_supply(repo: DataRepository, bite: int) -> int:
	@warning_ignore("integer_division")
	return (bite * int(repo.battle_orders["attack"]["extra_supply_permille"]) + 999) / 1000


## One side's power: each regiment's ArmySystem.power in the attack or defend
## stance on the ground it stands on, scaled by the height factor against the
## MEAN height of `enemy_codes` (none given: no height factor); a DEFENDING
## regiment's power is further scaled by its stance's defence_permille
## (`stance_fn` is a Callable code -> stance name; an unknown stance is 1000).
static func side_power(repo: DataRepository, state: GameState, codes: Array, stance_fn: Callable,
		attacking: bool, enemy_codes: Array = []) -> int:
	var total := 0
	for raw: Variant in codes:
		var battle := battle_of(state, String(raw))
		var active_attack := attacking
		if not battle.is_empty():
			var action := unit_action(repo, state, battle, String(raw))
			if action["task_id"] != "" or action["kind"] == "retreat":
				active_attack = action["kind"] == "attack"
		if active_attack and battle.get("reserves", {}).has(String(raw)) \
				and unit_action(repo, state, battle, String(raw))["task_id"] == "":
			continue
		var result := unit_strength(repo, state, String(raw), stance_fn, active_attack, enemy_codes)
		if result.has("error"):
			return 0
		total += int(result["power"])
	return total


static func unit_strength(repo: DataRepository, state: GameState, code: String, stance_fn: Callable,
		attacking: bool, enemy_codes: Array = []) -> Dictionary:
	var battle := battle_of(state, code)
	var action: Dictionary = {} if battle.is_empty() else unit_action(repo, state, battle, code)
	if not action.is_empty() and (action["task_id"] != "" or action["kind"] == "retreat"):
		attacking = action["kind"] == "attack"
	var factors: Array[Dictionary] = []
	var enemy_m := 0
	for enemy: String in enemy_codes:
		enemy_m += ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, enemy, state), state)
	if not enemy_codes.is_empty():
		@warning_ignore("integer_division")
		enemy_m /= enemy_codes.size()
		var delta := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, code, state), state) - enemy_m
		factors.append({"source": "ground:height", "category": "formation_terrain",
			"permille": ArmySystem.height_factor(repo, delta), "reason": "Height against the opposing line"})
	if not attacking:
		var stance := String(stance_fn.call(code)) if stance_fn.is_valid() else stance_of(state, code)
		factors.append({"source": "stance:defence", "category": "formation_terrain",
			"permille": int(_stance_row(repo, stance).get("defence_permille", 1000)), "reason": "Delivered defensive stance"})
		factors.append({"source": "camp:defence", "category": "formation_terrain",
			"permille": CampSystem.defence_factor(repo, state, code), "reason": "Camp at its real saved site"})
	if not battle.is_empty():
		var side := BattleRules.side_of(battle, code)
		if battle.has("formations"):
			for factor: Dictionary in BattleFormation.effects(repo, state, battle, side, attacking, code)["factors"]:
				var copy := factor.duplicate(true)
				copy["category"] = "formation_terrain"
				factors.append(copy)
		factors.append_array(BattleEvents.factors(state, battle, code))
		var kind := String(action["kind"])
		var row: Dictionary = repo.battle_orders.get(kind, {})
		factors.append({"source": "order:" + kind, "category": "action",
			"permille": int(row.get("attack_permille" if attacking else "defence_permille", 1000)),
			"reason": String(action["reason"])})
	return BattleStrength.unit(repo, state, code, attacking, factors)


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


## Plan both sides before committing any casualties or morale. A failed
## originating population write leaves the entire round untouched.
static func _plan_side(repo: DataRepository, state: GameState, codes: Array, loss_permille: int,
		wounded_share_permille: int, morale_delta: int, reason: String, out: Dictionary,
		orders: Array, stance_fn: Callable, unit_losses: Dictionary = {}) -> Dictionary:
	if not unit_losses.is_empty():
		var groups := {}
		for code: String in codes:
			var rate := int(unit_losses.get(code, loss_permille))
			if not groups.has(rate):
				groups[rate] = []
			groups[rate].append(code)
		for rate: int in groups:
			var result := _plan_side(repo, state, groups[rate], rate, wounded_share_permille,
				morale_delta, reason, out, orders, stance_fn)
			if result.has("error"):
				return result
		return {"status": "planned"}
	var fits: Array = []
	var total_fit := 0
	for code: String in codes:
		var entry := _stored(state, code)
		if entry.is_empty() or not state.military_rosters.has(code):
			return {"error": "Battle participant has no active personnel record: " + code}
		var ids: Array = state.military_rosters[code].get("cohort_ids", [])
		if ids.is_empty():
			return {"error": "Battle participant has no personnel cohorts: " + code}
		for id: String in ids:
			if not state.military_cohorts.has(id):
				return {"error": "Battle participant is missing personnel cohort: " + id}
		var fit := MilitaryRoster.fit(state, code)
		fits.append(fit)
		total_fit += fit
	var split := split_losses(total_fit, loss_permille, wounded_share_permille)
	var lost_each := apportion(fits, int(split["lost"]))
	var wounded_each := apportion(lost_each, int(split["wounded"]))
	for i: int in codes.size():
		var code := String(codes[i])
		var entry := _stored(state, code)
		var wounded := int(wounded_each[i])
		var dead := int(lost_each[i]) - wounded
		if wounded > 0:
			orders.append({"unit_code": code, "from": "fit", "to": "wounded", "count": wounded})
		if dead > 0:
			orders.append({"unit_code": code, "from": "fit", "to": "dead", "count": dead})
		var before := int(entry.get("morale", 0))
		var fall := morale_delta
		if fall < 0 and stance_fn.is_valid():
			@warning_ignore("integer_division")
			fall = fall * int(_stance_row(repo, String(stance_fn.call(code))).get("morale_decay_permille", 1000)) / 1000
		var battle := battle_of(state, code)
		if fall < 0 and not battle.is_empty():
			var side := BattleRules.side_of(battle, code)
			var row: Dictionary = repo.battle_orders.get(unit_action(repo, state, battle, code)["kind"], {})
			@warning_ignore("integer_division")
			fall = fall * int(row.get("morale_decay_permille", 1000)) / 1000
			if state.absolute_day() < int(battle.get("inspire_until", {}).get(side, 0)):
				@warning_ignore("integer_division")
				fall = fall * int(repo.battle_orders.get("inspire", {}).get("inspire_morale_decay_permille", 1000)) / 1000
		out[code] = {"dead": dead, "wounded": wounded,
			"morale": clampi(before + fall, 0, 100) - before, "reason": reason}
	return {"status": "planned"}


## The round token is stable across saves, independent of surviving headcount.
## An exact retry returns its original result; conflicting reuse is refused.
static func apply_round(repo: DataRepository, state: GameState, codes_att: Array, codes_def: Array,
		tier: Dictionary, reason: String, stance_fn: Callable = Callable(), event_id: String = "") -> Dictionary:
	if event_id.strip_edges().is_empty() or reason.strip_edges().is_empty():
		return {"error": "A battle round needs a stable event ID and a reason."}
	var att := codes_att.duplicate()
	var def := codes_def.duplicate()
	att.sort()
	def.sort()
	var seen: Dictionary = {}
	for code: String in att + def:
		if seen.has(code):
			return {"error": "A unit cannot participate twice in the same battle round."}
		seen[code] = true
	var request := {"kind": "battle_round", "att": att, "def": def,
		"tier": tier.duplicate(true), "reason": reason}
	if state.military_events.has(event_id):
		var previous: Dictionary = state.military_events[event_id]
		if previous["request"] != request:
			return {"error": "Battle round ID was already used for a different outcome."}
		return previous["result"].duplicate(true)
	var out: Dictionary = {}
	var orders: Array = []
	var share := int(tier.get("wounded_share_permille", 0))
	var planned := _plan_side(repo, state, att, int(tier.get("attacker_loss_permille", 0)), share,
		int(tier.get("attacker_morale", 0)), reason, out, orders, stance_fn, tier.get("unit_loss_permille", {}))
	if planned.has("error"):
		return planned
	planned = _plan_side(repo, state, def, int(tier.get("defender_loss_permille", 0)), share,
		int(tier.get("defender_morale", 0)), reason, out, orders, stance_fn, tier.get("unit_loss_permille", {}))
	if planned.has("error"):
		return planned
	if not orders.is_empty():
		var applied := MilitaryRoster.transfer_units(repo, state, event_id + ":personnel", orders, reason)
		if applied.has("error"):
			return applied
	for code: String in out:
		var entry := _stored(state, code)
		entry["morale"] = int(entry.get("morale", 0)) + int(out[code]["morale"])
	# Zero-loss rounds still consume their morale effect exactly once.
	state.military_events[event_id] = {"request": request, "result": out.duplicate(true)}
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


## Every live land unit can be contacted, including a withdrawing host.
static func _can_fight(repo: DataRepository, state: GameState, code: String) -> bool:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return false
	var e := _stored(state, code)
	if e.is_empty():
		return false
	return ArmySystem.fit_count(repo, state, code) > 0


## A host's homeward intent initiates a real retreat, never contact immunity.
static func homeward(state: GameState, code: String) -> bool:
	var host := String((state.foes.get(code, {}) as Dictionary).get("host", ""))
	return host != "" and state.ai_hosts.has(host) \
		and String((state.ai_hosts[host] as Dictionary).get("mode", "")) in EnemyAi.HOMEWARD


## Turning home requests withdrawal while leaving the army exposed in contact.
static func _withdraw_homeward(repo: DataRepository, state: GameState, _events: Array) -> void:
	for battle: Dictionary in state.battles:
		for side: String in SIDES:
			if (battle[side] as Array).any(func(code: String) -> bool: return homeward(state, code)):
				if not battle.has("actions"):
					battle["actions"] = {}
				battle["actions"][side] = {"kind": "retreat", "reason": "The host orders a withdrawal"}


## The town a foe's host besieges while it waits for its assault: its host
## (GameState.ai_hosts) deploying or in an active siege without an assault; "" any
## other time. Such a foe does not fight that town's GARRISON (the garrison
## waits behind its walls for the assault, the ordinary town battle that
## SiegeSystem lets through with the flag), but meets any other regiment of
## the player's as ever — a relief force in the open is fought in the field.
static func siege_town_of(repo: DataRepository, state: GameState, code: String) -> String:
	var host := String((state.foes.get(code, {}) as Dictionary).get("host", ""))
	if host == "" or not state.ai_hosts.has(host):
		return ""
	var h: Dictionary = state.ai_hosts[host]
	if String(h.get("mode", "")) not in ["DEPLOYING", "SIEGE"] or (SiegeSystem.active(repo, state, host) and SiegeSystem.deployed_at(repo, state, code, String(h.get("target_id", ""))) and int(h.get("assault", 0)) == 1):
		return ""
	return String(h.get("target_id", ""))


## The town a foe assaults when it stands within the reach
## (data/army/army_town_reach.csv) of `town`, the held town a player unit
## garrisons (ArmyGround.garrison_town: its seat or camp); "" otherwise.
static func town_contact(repo: DataRepository, state: GameState, town: String, f: String) -> String:
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
	BattleReport.enroll(state, b, code, side)
	if not b.has("event_reinforcements"):
		b["event_reinforcements"] = []
	b.event_reinforcements.append(code)
	if not b.has("reinforcement_evidence"):
		b["reinforcement_evidence"] = []
	b.reinforcement_evidence.append({"unit": code, "side": side, "day": state.absolute_day(),
		"reason": "This regiment physically joined the existing battle."})
	_halt(state, code)
	BattleGroups.refresh(repo, state, b)
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
		var held_off := siege_town_of(repo, state, f)
		for pc: Variant in mine:
			var p := String(pc)
			if held_off != "" and String(garrisons[pc]) == held_off:
				continue    # a besieged town's garrison waits for the assault
			# read fresh: a column halted in a town's reach today is its garrison now
			var town := town_contact(repo, state, ArmyGround.garrison_town(repo, state, p), f)
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
		"rounds": 0, "place_x_m": place.x, "place_y_m": place.y, "town": town,
		"deployed_day": state.absolute_day()}   # the day of contact deploys nothing; the next prepare_day does
	b["actions"] = {}
	for side: String in SIDES:
		var actor := String(b[side][0])
		var entry := _stored(state, actor)
		var kind := String(entry.get("battle_plan", "hold"))
		var advanced := String(entry.get("order", "")) == ArmySystem.ORDER_MARCH \
			or int(entry.get("halt_day", -1)) == state.absolute_day()
		if advanced:
			kind = "attack"
		if homeward(state, actor) or bool(entry.get("battle_retreat", false)):
			kind = "retreat"
		b["actions"][side] = {"kind": kind, "reason": "Received advance plan" if kind == "attack" else "Maintain distance at contact"}
	BattleRules.freeze(repo, state, b)
	BattleFormation.ensure(b)
	state.battles.append(b)
	for entry_side: String in SIDES:
		for member: String in b[entry_side]:
			BattleReport.enroll(state, b, member, entry_side)
	BattleGroups.refresh(repo, state, b)
	for side: String in SIDES:
		var actor := String(b[side][0])
		if ArmySystem.is_foe(state, actor):
			var host := String(_stored(state, actor).get("host", ""))
			if host != "" and not homeward(state, actor):
				var opposition: Array = b["def" if side == "att" else "att"]
				var seen := EnemyAi.seen_by(repo, state, host)
				var visible := opposition.filter(func(c: String) -> bool: return c in seen)
				var take_fight := not visible.is_empty() and EnemyAi.engages(repo, state, host, visible)
				b["actions"][side] = {"kind": "attack" if take_fight else "hold", "reason": "Commander follows received doctrine and visible opposition"}
	var turn := ArmyGround.clearance_on(repo)   # the clearance's facing; none with the rule off
	if not bool(_stored(state, p).get("battle_retreat", false)):
		_halt(state, p, _at_m(repo, state, f) if turn else Vector2i(-1, -1))
	if not bool(_stored(state, f).get("battle_retreat", false)):
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
	for battle: Dictionary in state.battles:
		BattleRules.freeze(repo, state, battle)
		BattleFormation.ensure(battle)
		BattleGroups.deploy_day(repo, state, battle)
		BattleGroups.refresh(repo, state, battle)
	_withdraw_homeward(repo, state, events)
	_detect(repo, state, events)
	return events


## Contact discovery after another substep never repeats daily withdrawals.
static func discover_contacts(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	_detect(repo, state, events)
	return events


static func step_battle(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
	var events: Array = []
	var battle := battle_by_id(state, battle_id)
	if not battle.is_empty():
		var had_commanders := battle.has("commanders")
		var previous: Dictionary = battle.get("commanders", {}).duplicate(true)
		var leadership := BattleCommand.update_battle(repo, state, battle)
		if leadership.has("error"):
			return {"status": "error", "error": leadership["error"], "events": []}
		var result := _fight(repo, state, battle, events)
		if result.has("error"):
			if had_commanders:
				battle["commanders"] = previous
			else:
				battle.erase("commanders")
			return {"status": "error", "error": result["error"], "events": []}
		if not bool(result["ended"]):
			BattleReport.note(battle, events)
			BattleGroups.refresh(repo, state, battle)   # the round's losses and exits, so a same-day retry is inert
		if bool(result["ended"]):
			state.battles = state.battles.filter(func(b: Dictionary) -> bool: return int(b["id"]) != battle_id)
	return {"status": "complete", "events": events}


static func finish_day(repo: DataRepository, state: GameState) -> void:
	for battle: Dictionary in state.battles:
		BattleFormation.advance(repo, state, battle)
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
		var result := step_battle(repo, state, id)
		if result["status"] != "complete":
			events.append({"kind": "error", "battle_id": id, "reason": result.get("error", "Battle did not complete.")})
			return events
		events.append_array(result["events"])
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


## One battle's day; errors preserve the round and the daily cursor.
static func _fight(repo: DataRepository, state: GameState, b: Dictionary, events: Array) -> Dictionary:
	for side: String in SIDES:
		for code: String in b[side]:
			BattleReport.enroll(state, b, code, side)
	var today := state.absolute_day()
	if int(b.get("last_resolved_day", -1)) == today:
		return {"ended": false}
	for side: String in SIDES:
		b[side] = (b[side] as Array).filter(func(c: String) -> bool: return not _stored(state, c).is_empty())
	var custody := _settle_defeated_holders(repo, state, b)
	if custody.has("error"):
		return custody
	var left := _exits(repo, state, b, "none", 500)
	if (b["att"] as Array).is_empty() or (b["def"] as Array).is_empty():
		_end(repo, state, b, "rout_" + ("attacker" if b["routed_side"] == "att" else "defender") if b.has("routed_side") else "emptied", events, left)
		return {"ended": true}
	if not b.has("routed_side"):
		for side: String in SIDES:
			if _broken(repo, state, b[side]):
				_mark_rout(repo, state, b, side)
				break
	var costs: Array = []
	for side: String in SIDES:
		var kind := BattleOrders.kind(b, side)
		if kind == "attack" and not "attack" in BattleRules.legal_actions(repo, state, int(b["id"]), side):
			b["actions"][side] = {"kind": "hold", "reason": "Attack is barred by current laws or the frozen agreement"}
			kind = "hold"
		if kind == "retreat":
			for code: String in b[side]:
				_start_retreat(repo, state, code, b)
		if kind != "attack":
			continue
		var planned: Array = []
		var sufficient := true
		for code: String in b[side]:
			var action := BattleTaskSystem.combat_action(repo, state, b, code)
			if action["task_id"] != "" or action["kind"] != "attack":
				continue
			var entry := _stored(state, code)
			var reg := ArmySystem.regiment(repo, code, state)
			var bite := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, state), state.day)
			var extra := _attack_supply(repo, bite)
			if ArmySystem.fit_count(repo, state, code) <= 0 or int(entry.get("supplies", 0)) < bite + extra:
				sufficient = false
			planned.append({"code": code, "supplies": extra, "reason": "Additional supplies for an actual all-out attack day"})
		if sufficient:
			costs.append_array(planned)
		else:
			b["actions"][side] = {"kind": "hold", "reason": "Attack falls back to hold: insufficient personnel or carried supplies"}
	var engaging := false
	var unit_actions := {}
	for side: String in SIDES:
		for code: String in b[side]:
			var action := unit_action(repo, state, b, code)
			unit_actions[code] = action
			engaging = engaging or action["kind"] == "attack"
			if action["kind"] == "attack" and action["task_id"] != "":
				var reg := ArmySystem.regiment(repo, code, state)
				var bite := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, state), state.day)
				costs.append({"code": code, "supplies": _attack_supply(repo, bite), "reason": String(action["reason"])})
	if not engaging and not b.has("pending_round"):
		b["last_resolved_day"] = today
		return {"ended": false}
	var att: Array = b["att"]
	var def: Array = b["def"]
	var n := int(b["rounds"]) + 1
	var stance := func(c: String) -> String: return stance_of(state, c)
	var pending: Dictionary = b.get("pending_round", {})
	if pending.is_empty():
		var a_pow := side_power(repo, state, att, stance, BattleOrders.kind(b, "att") == "attack", def)
		var d_pow := side_power(repo, state, def, stance, BattleOrders.kind(b, "def") == "attack", att)
		var odds := odds_permille(a_pow, d_pow)
		var draw := state.rng.randi_range(0, 999)
		var eff := eff_permille(odds, draw, int(repo.bal("battle_variance_permille")))
		var tier := tier_of(repo, eff).duplicate(true)
		var contexts := {}
		for side: String in SIDES:
			var context := combat_context(repo, state, b, side)
			contexts[side] = context
			var key := "attacker_loss_permille" if side == "att" else "defender_loss_permille"
			var base_loss := int(tier.get(key, 0))
			var withdrawing := 0
			for code: String in b[side]:
				if bool(_stored(state, code).get("battle_retreat", false)):
					withdrawing += 1
			if withdrawing > 0 or BattleOrders.kind(b, side) == "retreat":
				if not tier.has("unit_loss_permille"):
					tier["unit_loss_permille"] = {}
				for code: String in b[side]:
					var unit_context := combat_context(repo, state, b, side, code)
					@warning_ignore("integer_division")
					tier["unit_loss_permille"][code] = base_loss * int(unit_context["loss_permille"]) / 1000
			@warning_ignore("integer_division")
			tier[key] = base_loss * int(context["loss_permille"]) / 1000
		var reason := "%s at %s, battle day %d; attacker %s, defender %s" % [String(tier.get("tier", "")).replace("_", " "),
			place_label(repo, state, b), n, contexts["att"]["kind"], contexts["def"]["kind"]]
		pending = {"day": today, "round": n, "att": att.duplicate(), "def": def.duplicate(), "tier": tier,
			"att_power": a_pow, "def_power": d_pow, "odds": odds, "roll": draw, "eff": eff,
			"contexts": contexts, "reason": reason, "costs": costs, "unit_actions": unit_actions}
		b["pending_round"] = pending
	var results := apply_round(repo, state, pending["att"], pending["def"], pending["tier"], pending["reason"], stance,
		"battle:%d:round:%d" % [int(b["id"]), n])
	if results.has("error"):
		return results
	custody = _settle_defeated_holders(repo, state, b)
	if custody.has("error"):
		return custody
	for cost: Dictionary in pending["costs"]:
		var entry := _stored(state, String(cost["code"]))
		entry["supplies"] = maxi(0, int(entry["supplies"]) - int(cost["supplies"]))
	for code: String in pending.get("unit_actions", {}):
		var action: Dictionary = pending["unit_actions"][code]
		if action["kind"] == "attack" and action["task_id"] != "":
			b.get("reserves", {}).erase(code)
	b["rounds"] = n
	b["last_resolved_day"] = today
	b.erase("pending_round")
	var rout := String(pending["tier"].get("rout", "none"))
	if rout == "none":
		for side: String in SIDES:
			if _broken(repo, state, b[side]):
				rout = "attacker" if side == "att" else "defender"
				break
	left.append_array(_exits(repo, state, b, rout, int(pending["odds"])))
	events.append({"kind": "round", "battle_id": int(b["id"]), "round": n, "att_power": pending["att_power"],
		"def_power": pending["def_power"], "odds": pending["odds"], "roll": pending["roll"], "eff": pending["eff"],
		"tier": pending["tier"].get("tier", ""), "contexts": pending["contexts"], "costs": pending["costs"],
		"unit_actions": pending.get("unit_actions", {}),
		"results": results, "att": pending["att"], "def": pending["def"],
		"town": String(b["town"]), "place_x_m": int(b["place_x_m"]), "place_y_m": int(b["place_y_m"]), "left": left.duplicate(true)})
	if (b["att"] as Array).is_empty() or (b["def"] as Array).is_empty():
		_end(repo, state, b, "rout_" + ("attacker" if b["routed_side"] == "att" else "defender") if b.has("routed_side") else "emptied", events, left)
		return {"ended": true}
	return {"ended": false}


## Resolve custody while the defeated unit still has its battlefield context.
static func _settle_defeated_holders(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	for side: String in SIDES:
		var codes: Array = battle[side].duplicate()
		codes.sort()
		for code: String in codes:
			if MilitaryRoster.fit(state, code) > 0 or int(PrisonerSystem.held_counts(state, code)["total"]) == 0:
				continue
			var other := "def" if side == "att" else "att"
			var receivers: Array = battle[other].filter(func(member: String) -> bool: return MilitaryRoster.fit(state, member) > 0)
			if receivers.is_empty():
				receivers = battle[side].filter(func(member: String) -> bool: return member != code and MilitaryRoster.fit(state, member) > 0)
			receivers.sort_custom(func(a: String, b: String) -> bool:
				var origin := _at_m(repo, state, code)
				var da := origin.distance_squared_to(_at_m(repo, state, a))
				var db := origin.distance_squared_to(_at_m(repo, state, b))
				return a < b if da == db else da < db)
			var controllers: Array[String] = []
			if not receivers.is_empty():
				controllers.append(String(receivers[0]))
			var result := PrisonerSystem.holder_defeated(repo, state, code, controllers,
				"battle_holder:%d:%d:%s" % [int(battle["id"]), int(battle.get("rounds", 0)), code])
			if result.has("error"):
				return result
	return {"status": "applied"}


static func _broken(repo: DataRepository, state: GameState, codes: Array) -> bool:
	var fit := 0
	var morale := 0
	for code: String in codes:
		var count := ArmySystem.fit_count(repo, state, code)
		fit += count
		morale += count * int(_stored(state, code).get("morale", 0))
	return fit == 0 or morale <= fit * int(repo.bal("battle_break_morale"))


## The incoming-loss context follows real equipment, action and binding terms.
static func combat_context(repo: DataRepository, state: GameState, battle: Dictionary, side: String, unit := "") -> Dictionary:
	var other := "def" if side == "att" else "att"
	var kind := "melee"
	var scale := 1000
	var members: Array = battle[side] if unit == "" else [unit]
	if BattleOrders.kind(battle, side) == "retreat" or members.any(func(code: String) -> bool:
		return bool(_stored(state, code).get("battle_retreat", false))):
		var pursued := false
		for code: String in battle[other]:
			var action := unit_action(repo, state, battle, code)
			if action["kind"] != "attack" or not _can_fight(repo, state, code) \
					or bool(_stored(state, code).get("captured", false)):
				continue
			if not "pursue" in BattleRules.legal_actions(repo, state, int(battle["id"]), other, code):
				continue
			if action.has("pursuit_target"):
				pursued = pursued or action["pursuit_target"] == "" or action["pursuit_target"] in members
			elif action["task_id"] == "" and BattleOrders.kind(battle, other) == "attack" \
					and "pursue" in BattleRules.legal_actions(repo, state, int(battle["id"]), other):
				pursued = true
		kind = "pursuit" if pursued else "withdrawal"
		scale = int(repo.bal("battle_context_" + kind + "_permille"))
		if BattleRules._policy(battle, "safe_withdrawal", state.absolute_day()) == "protect":
			scale = 0
	else:
		var ranged := 0
		var mounted := 0
		var heads := 0
		for code: String in battle[other]:
			var row := ArmySystem.regiment(repo, code, state)
			for arm: String in repo.world_table("military", "unit_types"):
				var arm_row: Dictionary = repo.world_table("military", "unit_types")[arm]
				var people := int(row.get(arm, 0)) * int(arm_row["crew"])
				heads += people
				if String(arm_row["type"]) in ["ranged", "machinery"]:
					ranged += people
				if String(arm_row["type"]) == "mounted" and unit_action(repo, state, battle, code)["kind"] == "attack":
					mounted += people
		var threshold := int(repo.bal("battle_context_arm_threshold_permille"))
		if heads > 0 and ranged * 1000 >= heads * threshold:
			kind = "ranged"
		elif heads > 0 and mounted * 1000 >= heads * threshold:
			kind = "shock"
		if kind != "melee":
			scale = int(repo.bal("battle_context_" + kind + "_permille"))
	for code: String in members:
		for modifier: Dictionary in battle.get("event_modifiers", []):
			if modifier.unit == code and int(modifier.until_day) >= state.absolute_day():
				@warning_ignore("integer_division")
				scale = scale * int(modifier.exposure_permille) / 1000
	return {"kind": kind, "loss_permille": scale, "reason": "Incoming casualties in " + kind + " under current actions, events and agreements"}


static func _mark_rout(repo: DataRepository, state: GameState, battle: Dictionary, side: String) -> void:
	battle["routed_side"] = side
	for code: String in battle[side]:
		_stored(state, code)["withdrawal_cause"] = "rout"
	if not battle.has("actions"):
		battle["actions"] = {}
	battle["actions"][side] = {"kind": "retreat", "reason": "The side collapses and must leave by a real route"}
	for code: String in battle[side]:
		_start_retreat(repo, state, code, battle)


static func stop_withdrawal(state: GameState, code: String) -> void:
	var entry := _stored(state, code)
	if not bool(entry.get("battle_retreat", false)):
		return
	entry.erase("battle_retreat")
	entry.erase("withdrawal_cause")
	entry.erase("disengaging")
	entry.erase("departure")
	_halt(state, code)


static func may_withdraw(state: GameState, code: String) -> bool:
	var battle := battle_of(state, code)
	return battle.is_empty() or bool(_stored(state, code).get("battle_retreat", false))


static func _separated(repo: DataRepository, state: GameState, code: String, enemies: Array) -> bool:
	var reach := int(repo.bal("battle_contact_km") * 1000)
	for enemy: String in enemies:
		if _within(_at_m(repo, state, code), _at_m(repo, state, enemy), reach):
			return false
	return true


static func _start_retreat(repo: DataRepository, state: GameState, code: String, battle: Dictionary) -> bool:
	var entry := _stored(state, code)
	if bool(entry.get("battle_retreat", false)):
		return true if String(entry.get("order", "")) == ArmySystem.ORDER_MARCH else _fall_back(repo, state, code, battle)
	if String(entry.get("order", "")) != ArmySystem.ORDER_MARCH and not _fall_back(repo, state, code, battle):
		return false
	entry["battle_retreat"] = true
	entry["disengaging"] = 1
	var loss := int(repo.bal("battle_retreat_morale_loss"))
	entry["morale"] = maxi(0, int(entry.get("morale", 0)) - loss)
	@warning_ignore("integer_division")
	var abandoned := int(entry.get("supplies", 0)) * int(repo.bal("battle_retreat_supply_loss_permille")) / 1000
	entry["supplies"] = int(entry.get("supplies", 0)) - abandoned
	if abandoned > 0:
		if not battle.has("abandoned_supplies"):
			battle["abandoned_supplies"] = {}
		var at := _at_m(repo, state, code)
		var source := "withdrawal:%d:%s:%d" % [int(battle.id), code, state.absolute_day()]
		battle.abandoned_supplies[source] = {"unit": code, "side": BattleRules.side_of(battle, code),
			"x_m": at.x, "y_m": at.y, "amount": abandoned,
			"reason": "Food physically abandoned by the withdrawing rear guard."}
	if not battle.has("withdrawal_costs"):
		battle["withdrawal_costs"] = []
	battle["withdrawal_costs"].append({"code": code, "morale": -loss, "supplies": -abandoned,
		"reason": "Rear guard abandons stores and morale while yielding the field"})
	return true


## Why a regiment leaves the battle after today's round, "" when it stays:
## "ordered" (a march order reached it), "broken" (no fit man left), "rout"
## (its side broke), "evade" (its stance leaves on contact), "retreat" (its
## side's odds below its stance's retreat_odds_permille).
static func _exit_why(repo: DataRepository, state: GameState, code: String, side: String, rout: String,
		side_odds: int) -> String:
	var e := _stored(state, code)
	if String(e.get("order", "")) == ArmySystem.ORDER_MARCH \
			and CampSystem.can_march(state, code, state.absolute_day()):
		return "ordered"
	if ArmySystem.fit_count(repo, state, code) <= 0:
		return "broken"
	if rout == ("attacker" if side == "att" else "defender"):
		return "rout"
	var row := _stance_row(repo, stance_of(state, code))
	if bool(row.get("retreats_on_contact", false)):
		return "evade"
	if side_odds < int(row.get("retreat_odds_permille", 0)):
		return "retreat"
	return ""


## Withdrawals keep membership until actual separation; a rout ends combat.
static func _exits(repo: DataRepository, state: GameState, b: Dictionary, rout: String, odds: int) -> Array:
	var left: Array = []
	for side: String in SIDES:
		var keep: Array = []
		var codes: Array = b[side].duplicate()
		codes.sort()
		var other := "def" if side == "att" else "att"
		for code: String in codes:
			var why := _exit_why(repo, state, code, side, rout, odds if side == "att" else 1000 - odds)
			if why in ["ordered", "evade", "retreat"] or unit_action(repo, state, b, code)["kind"] == "retreat":
				var entry := _stored(state, code)
				if not entry.has("withdrawal_cause"):
					entry["withdrawal_cause"] = "withdrawn" if homeward(state, code) else (why if why in ["ordered", "evade", "retreat"] else "retreat")
				_start_retreat(repo, state, code, b)
				if not _separated(repo, state, code, b[other]):
					keep.append(code)
					continue
				why = String(_stored(state, code).get("withdrawal_cause", "withdrawn"))
			elif why == "rout":
				_mark_rout(repo, state, b, side)
				if not _separated(repo, state, code, b[other]):
					keep.append(code)
					continue
			if why == "":
				keep.append(code)
			else:
				_stored(state, code).erase("battle_retreat")
				_stored(state, code).erase("withdrawal_cause")
				BattleReport.leave(state, b, code)
				left.append({"code": code, "side": side, "why": why})
		b[side] = keep
	return left


## March a regiment for the nearest town its own kingdom holds (MapOwnership)
## that lies beyond battle_contact_km of the battle's place (ties to the
## earlier town code); it halts where it is when there is none.
static func _fall_back(repo: DataRepository, state: GameState, code: String, b: Dictionary) -> bool:
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
		var side := BattleRules.side_of(b, code)
		if side != "":
			var other := "def" if side == "att" else "att"
			if (b[other] as Array).any(func(enemy: String) -> bool: return _within(m, _at_m(repo, state, enemy), reach)):
				continue
		var grid := MarchPath.of_pack(repo)
		if grid != null and not grid.clear(here, m, [grid.cell_of(here), grid.cell_of(m)]):
			var start := grid.nearest_open(grid.cell_of(here))
			var goal := grid.nearest_open(grid.cell_of(m))
			if start.x < 0 or goal.x < 0 or grid._cells(start, goal).is_empty():
				continue
		var dx := int(m.x) - int(here.x)
		var dy := int(m.y) - int(here.y)
		var d := dx * dx + dy * dy
		if best_d < 0 or d < best_d or (d == best_d and town < best):
			best = town
			best_d = d
			best_m = m
	if best == "":
		e["withdrawal_reason"] = "No reachable safe destination: the army remains exposed in contact"
		return false
	CampSystem.ensure_legacy(repo, state, code)
	CampSystem.request_departure(state, code, state.absolute_day(), true)
	ArmySystem.aim_entry(repo, e, best_m, ArmySystem.is_naval(repo, state, code))
	if not ArmySystem.is_foe(state, code) and CampSystem.can_march(state, code, state.absolute_day()):
		# a unit of the crown's leaves its camp and, holding a seat, empties it
		# (refilled from the camp; spec 2026-10-07-army-split-and-ground §4.4)
		ArmyGround.leave(repo, state, code)
	return true


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


## Takes battle `id` off the field with a terminal report (SiegeSystem.capture:
## the town it was fought for fell under it); its regiments stay where they
## stand, halted.
static func call_off(state: GameState, id: int, repo: DataRepository = null, victorious_side := "") -> Dictionary:
	var battle := battle_by_id(state, id)
	if battle.is_empty(): return {}
	var events: Array = []
	_end(repo, state, battle, "town_fallen" if victorious_side != "" else "called_off", events, [], victorious_side)
	state.battles = state.battles.filter(func(b: Dictionary) -> bool: return int(b["id"]) != id)
	return events[0]


## Preserve terminal warrant receipts while releasing every unspent reservation.
static func _end(repo: DataRepository, state: GameState, b: Dictionary, why: String, events: Array, left: Array = [], victorious_side := "") -> void:
	BattleOrders.end_battle(repo, state, int(b["id"]), "Battle ended: " + why)
	var att: Array = b["att"]
	var def: Array = b["def"]
	var winner := victorious_side
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
		"place_x_m": int(b["place_x_m"]), "place_y_m": int(b["place_y_m"]), "left": left.duplicate(true)})
	b["report_outcome"] = {"why": why, "winner": winner, "town": String(b["town"])}
	BattleReport.note(b, events)
	BattleReport.snapshot(repo, state, int(b["id"]))
