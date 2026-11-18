class_name BodyBattleRounds
extends RefCounted
## CF06 D-PENDING: the first detached planning of a round-ready candidate field. It freezes
## the existing pending_round payload, the round's exact effects (through the existing
## personnel planner) and ONE engine RNG draw together, sealed by the outer `round_pending`
## operation. No personnel, morale, cost, impact or cursor change: that is D-SETTLE
## (`settle_candidate`), which commits that frozen plan atomically under `round_settle`.

const PENDING_KEYS: Array[String] = ["day", "round", "att", "def", "tier", "att_power", "def_power", "odds",
	"roll", "eff", "contexts", "reason", "costs", "unit_actions", "body_round_receipt"]

static func _result(status: String, reason: String, candidate: GameState = null, plan: Dictionary = {}) -> Dictionary:
	return BodyBattleMotion._result(status, reason, candidate, plan)

## Plan the current queued field's frozen round. Success carries a detached candidate with the
## frozen pending, the saved plan wrapper and one advanced RNG state; an exact repeat returns
## that frozen candidate unchanged. Tampering, a changed basis or malformed inputs error.
static func plan_candidate(repo: DataRepository, source: GameState, battle_id: int, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or battle_id <= 0: return _result("error", "Round planning requires data, source and a field")
	var admitted := UnitBodies.validate_battle_candidate(repo, source, boundary)
	if admitted.status == "error": return _result("error", admitted.reason)
	if boundary.get("kind") != "battle" or boundary.get("stage") != "round": return _result("error", "Round planning requires the round-stage boundary")
	var tx := source.day_resolution
	if int(tx.battle_index) >= tx.battle_ids.size() or int(tx.battle_ids[int(tx.battle_index)]) != battle_id:
		return _result("error", "Round planning names only the current queued field")
	var battle := UnitBodies._battle(source, battle_id)
	if battle.is_empty() or BattleSystem.canonical(source, battle_id) != battle_id or not battle.has("body_round"):
		return _result("error", "Round planning requires a canonical round-ready field")
	if admitted.reason != BodyBattle.FROZEN_ROUND: return _result("deferred", "Round planning requires a ready round")
	if not tx.pending_decision.is_empty(): return _result("deferred", "A pending decision comes first")
	if battle.body_round.basis != BodyBattle._round_basis(repo, source):
		return _result("error", "Readiness basis changed before planning")
	if battle.has("body_round_plan") or battle.has("pending_round"):
		var saved_error := _saved_error(battle)
		if not saved_error.is_empty(): return _result("error", saved_error)
		var plan: Dictionary = battle.body_round_plan.plan
		var outer: Dictionary = source.military_migration.get("body_battle", {})
		if outer.get("sequence") != plan.boundary.get("sequence") or outer.get("receipt") != BodyMotion._hash(_outer(plan, battle.body_round_plan.receipt, battle.body_round)):
			return _result("error", "The frozen round's outer round_pending receipt does not match")
		return _result("complete", "Already planned frozen round", UnitBodies._copy(source), plan.duplicate(true))
	var closed: Dictionary = source.military_migration.get("body_battle", {}).get("closed_motion", {})
	if closed.get("receipt") != battle.body_round.motion_receipt: return _result("error", "Readiness names another closed motion")
	# Physical queries need an unfrozen admission: a private probe without the envelope, resealed.
	var probe := UnitBodies._copy(source)
	UnitBodies._battle(probe, battle_id).erase("body_round")
	BodyBattle._seal_private(repo, probe)
	var probe_boundary := BodyBattleMotion._boundary(probe)
	var field := UnitBodies._battle(probe, battle_id)
	var actions: Dictionary = battle.body_round.unit_actions
	# The physical queries derive actions live; they must equal the frozen ones or nothing runs.
	for side: String in BattleSystem.SIDES:
		for code: String in field[side]:
			if BattleSystem.unit_action(repo, probe, field, code) != actions.get(code, {}):
				return _result("error", "Live action diverges from the frozen action: " + code)
	var powers := {"att": 0, "def": 0}
	var costs: Array = []
	for side: String in BattleSystem.SIDES:
		var enemies: Array = field["def" if side == "att" else "att"]
		for code: String in field[side]:
			var attacking: bool = actions.get(code, {}).get("kind", "") == "attack"
			# As production side_power: an uncommitted reserve's attack adds no power.
			if attacking and field.get("reserves", {}).has(code) and String(actions[code].get("task_id", "")) == "": continue
			var factors := _factors(repo, probe, field, code, attacking, enemies, actions.get(code, {}))
			var power: Dictionary = BattleSystem.candidate_power(repo, probe, battle_id, code, true, factors, probe_boundary) \
				if attacking else BattleStrength.unit(repo, probe, code, false, factors)
			if power.has("error"): return _result("error", String(power.error))
			powers[side] += int(power.power)
			if attacking:
				var reg := ArmySystem.regiment(repo, code, probe)
				var bite := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, probe), probe.day)
				var extra := BattleSystem._attack_supply(repo, bite)
				if int(BattleSystem._stored(probe, code).get("supplies", 0)) < bite + extra:
					return _result("error", "A frozen attack lacks its carried supplies: " + code)
				var by_task := String(actions[code].get("task_id", "")) != ""
				costs.append({"code": code, "supplies": extra,
					"reason": String(actions[code].get("reason", "")) if by_task else "Additional supplies for an actual all-out attack day"})
	var candidate := UnitBodies._copy(source)
	var odds := BattleSystem.odds_permille(int(powers.att), int(powers.def))
	var roll := candidate.rng.randi_range(0, 999)
	var eff := BattleSystem.eff_permille(odds, roll, int(repo.bal("battle_variance_permille")))
	var tier := BattleSystem.tier_of(repo, eff).duplicate(true)
	tier.unit_loss_permille = {}
	tier.unit_morale_permille = {}
	var contexts := {}
	for side: String in BattleSystem.SIDES:
		var key := "attacker_loss_permille" if side == "att" else "defender_loss_permille"
		var base := int(tier.get(key, 0))
		var members: Array = field[side].duplicate()
		members.sort()
		for code: String in members:
			var sources := BattleSystem.candidate_sources(repo, probe, battle_id, code, probe_boundary)
			if sources.has("error"): return _result("error", String(sources.error))
			var context := BattleSystem.candidate_context(repo, probe, field, code, sources.sources)
			if context.has("error"): return _result("error", String(context.error))
			tier.unit_loss_permille[code] = BattleStrength.loss_rate(base, int(context.loss_permille))
			tier.unit_morale_permille[code] = int(context.exposure)
			# The side record names its first member's context; every participant has its own rate.
			if not contexts.has(side): contexts[side] = {"kind": context.kind, "loss_permille": int(context.loss_permille), "reason": String(context.reason)}
		if not contexts.has(side): contexts[side] = {"kind": "melee", "loss_permille": 0, "reason": "No participant on this side"}
		tier[key] = BattleStrength.loss_rate(base, int(contexts[side].loss_permille))
	var round := int(battle.body_round.round)
	var reason := "%s at %s, battle day %d; attacker %s, defender %s" % [String(tier.get("tier", "")).replace("_", " "),
		BattleSystem.place_label(repo, source, battle), round, contexts.att.kind, contexts.def.kind]
	var pending := {"day": source.absolute_day(), "round": round, "att": battle.att.duplicate(), "def": battle.def.duplicate(),
		"tier": tier, "att_power": int(powers.att), "def_power": int(powers.def), "odds": odds, "roll": roll, "eff": eff,
		"contexts": contexts, "reason": reason, "costs": costs, "unit_actions": actions.duplicate(true),
		"body_round_receipt": BodyMotion._hash(battle.body_round)}
	# Effects read the FROZEN actions: the planner's unit_action takes them from pending_round.
	UnitBodies._battle(probe, battle_id).pending_round = pending.duplicate(true)
	var effects := _effects(repo, probe, battle_id, pending)
	if effects.has("error"): return _result("error", String(effects.error))
	var plan := {"version": 1, "battle_id": str(battle_id), "boundary": boundary.duplicate(true),
		"basis": {"source": BodyMotion._hash([source.to_dict(), boundary, BodyBattleMotion._context(repo, source)])},
		"body_round_receipt": pending.body_round_receipt, "pending": pending, "effects": effects}
	var live := UnitBodies._battle(candidate, battle_id)
	live.pending_round = pending.duplicate(true)
	live.body_round_plan = {"version": "1", "receipt": BodyMotion._hash(plan), "plan": plan.duplicate(true)}
	# One outer operation seals the draw and the frozen payload together.
	var outer := _outer(plan, live.body_round_plan.receipt, battle.body_round)
	candidate.day_resolution.body_battle.sequence = str(int(boundary.sequence) + 1)
	candidate.military_migration.body_battle = {"version": "1", "sequence": boundary.sequence, "receipt": BodyMotion._hash(outer),
		"result": "", "closed_motion": closed.duplicate(true)}
	candidate.military_migration.body_battle.result = UnitBodies._battle_result_hash(repo, candidate)
	var final := UnitBodies.validate_battle_candidate(repo, candidate, BodyBattleMotion._boundary(candidate))
	if final.status != "deferred" or final.reason != BodyBattle.FROZEN_ROUND: return _result("error", "Published pending failed admission: " + final.reason)
	var saved_error := _saved_error(live)
	if not saved_error.is_empty(): return _result("error", saved_error)
	return _result("complete", "Planned one frozen round", candidate, plan)

## CF06 D-SETTLE: commit the field's frozen plan atomically on a clone. Personnel through the
## existing round writer (`battle:<id>:round:<n>` and its `:personnel` transfer), the bodies
## through `BodyRoundReconcile`, family losses and custody, the frozen costs, reserves and earned
## impact; then the full receipt, the round closed, the field and its units processed and the
## queue advanced, sealed by one outer `round_settle`. A failed late writer returns blocked with
## the unchanged pending source; an exact settled retry is a detached no-op. Exits, routs and
## ends stay with the advance stage's lifecycle requests.
static func settle_candidate(repo: DataRepository, source: GameState, plan: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or not BodyMotion._keys(plan, ["version", "battle_id", "boundary", "basis", "body_round_receipt", "pending", "effects"]) \
		or not plan.battle_id is String or not String(plan.battle_id).is_valid_int() or int(plan.battle_id) <= 0 \
		or not plan.pending is Dictionary or not BodyMotion._keys(plan.pending, PENDING_KEYS) or not plan.effects is Dictionary:
		return _result("error", "Round settlement requires data, source and a frozen plan")
	var id := int(plan.battle_id)
	var key := "bodyround:%d:%d:%d:settlement" % [id, int(plan.pending.day), int(plan.pending.round)]
	var request := {"kind": "body_round_settlement", "plan": plan}
	if source.military_events.has(key):
		var saved: Variant = source.military_events[key]
		if not saved is Dictionary or BodyMotion._hash(saved.get("request")) != BodyMotion._hash(request):
			return _result("error", "The round was settled under another plan")
		var current := UnitBodies.validate_battle_candidate(repo, source, BodyBattleMotion._boundary(source))
		if current.status == "error": return _result("error", current.reason)
		return _result("complete", "Already settled round", UnitBodies._copy(source), plan.duplicate(true))
	var admitted := UnitBodies.validate_battle_candidate(repo, source, boundary)
	if admitted.status == "error": return _result("error", admitted.reason)
	if boundary.get("kind") != "battle" or boundary.get("stage") != "round": return _result("error", "Round settlement requires the round-stage boundary")
	var tx := source.day_resolution
	if int(tx.battle_index) >= tx.battle_ids.size() or int(tx.battle_ids[int(tx.battle_index)]) != id:
		return _result("error", "Round settlement names only the current queued field")
	var battle := UnitBodies._battle(source, id)
	if battle.is_empty() or BattleSystem.canonical(source, id) != id or not battle.has("body_round"):
		return _result("error", "Round settlement requires a canonical round-ready field")
	if admitted.reason != BodyBattle.FROZEN_ROUND: return _result("deferred", "Round settlement requires a frozen round")
	if not tx.pending_decision.is_empty(): return _result("deferred", "A pending decision comes first")
	if not battle.has("body_round_plan") and not battle.has("pending_round"): return _result("deferred", "The ready round awaits its planning")
	var saved_error := _saved_error(battle)
	if not saved_error.is_empty(): return _result("error", saved_error)
	var wrapper: Dictionary = battle.body_round_plan
	if BodyMotion._hash(wrapper.plan) != BodyMotion._hash(plan): return _result("error", "Settlement names another frozen plan")
	var outer: Dictionary = source.military_migration.get("body_battle", {})
	if outer.get("sequence") != plan.boundary.get("sequence") or outer.get("receipt") != BodyMotion._hash(_outer(plan, wrapper.receipt, battle.body_round)):
		return _result("error", "The frozen round's round_pending is not the last outer operation")
	# The basis proof on the admitted pre-settlement world: nothing the round read has moved.
	if battle.body_round.basis != BodyBattle._round_basis(repo, source): return _result("error", "Readiness basis changed before settlement")
	var pending: Dictionary = battle.pending_round
	var n := int(pending.round)
	if int(pending.day) != source.absolute_day() or n != int(battle.get("rounds", 0)) + 1:
		return _result("error", "The frozen round is not today's next round")
	var blocked := func(reason: String) -> Dictionary:
		return _result("blocked", "Round settlement failed; the frozen round stays pending: " + reason, UnitBodies._copy(source), plan.duplicate(true))
	var candidate := UnitBodies._copy(source)
	var stance := func(code: String) -> String: return BattleSystem.stance_of(candidate, code)
	var results := BattleSystem.apply_round(repo, candidate, pending.att, pending.def, pending.tier, pending.reason, stance,
		"battle:%d:round:%d" % [id, n])
	if results.has("error"): return blocked.call(String(results.error))
	if BodyMotion._hash(results) != BodyMotion._hash(plan.effects.unit_results): return _result("error", "Settled personnel diverge from the frozen effects")
	var personnel_id := ""
	if not (plan.effects.personnel_orders as Array).is_empty():
		personnel_id = "battle:%d:round:%d:personnel" % [id, n]
		var bodies := BodyRoundReconcile.reconcile_round_candidate(repo, candidate, {"battle_id": id, "round": n}, boundary)
		if bodies.status != "complete": return blocked.call(String(bodies.reason))
		candidate = bodies.candidate
	var live := UnitBodies._battle(candidate, id)
	var losses_before: Array = live.get("family_loss_ids", []).duplicate()
	var family := BattleSystem._settle_family_losses(repo, candidate, live, pending, n)
	if family.has("error"): return blocked.call(String(family.error))
	var added: Array = live.get("family_loss_ids", []).filter(func(loss: String) -> bool: return loss not in losses_before)
	added.sort()
	if added != plan.effects.family_event_ids: return _result("error", "Settled family losses diverge from the frozen effects")
	var custody := BattleSystem._settle_defeated_holders(repo, candidate, live)
	if custody.has("error"): return blocked.call(String(custody.error))
	for cost: Dictionary in pending.costs:
		var entry := BattleSystem._stored(candidate, String(cost.code))
		entry.supplies = maxi(0, int(entry.supplies) - int(cost.supplies))
	for code: String in pending.unit_actions:
		var action: Dictionary = pending.unit_actions[code]
		if action.kind == "attack" and action.task_id != "": live.get("reserves", {}).erase(code)
	var charged: Array = (pending.att + pending.def).filter(func(code: String) -> bool:
		var charge: Dictionary = BattleSystem._stored(candidate, code).get("charge", {})
		return charge.get("phase", "") == "impact" and int(charge.get("impact_day", -1)) == int(pending.day))
	charged.sort()
	if charged != plan.effects.charge_units: return _result("error", "Earned impact diverges from the frozen effects")
	BattleCharge.consume(candidate, pending.att + pending.def, int(pending.day))
	live.rounds = n
	live.last_resolved_day = int(pending.day)
	var round_event := {"kind": "round", "battle_id": id, "round": n, "att_power": pending.att_power,
		"def_power": pending.def_power, "odds": pending.odds, "roll": pending.roll, "eff": pending.eff,
		"tier": pending.tier.get("tier", ""), "contexts": pending.contexts, "costs": pending.costs,
		"unit_actions": pending.unit_actions, "results": results, "att": pending.att, "def": pending.def,
		"town": String(live.town), "place_x_m": int(live.place_x_m), "place_y_m": int(live.place_y_m), "left": []}
	candidate.military_events[key] = {"request": request.duplicate(true), "result": {"pending": pending.duplicate(true),
		"effects": plan.effects.duplicate(true), "personnel_event_id": personnel_id, "round_event": round_event.duplicate(true)}}
	for erased: String in ["body_round", "pending_round", "body_round_plan"]: live.erase(erased)
	var ctx := candidate.day_resolution
	ctx.journal.battles.append(round_event.duplicate(true))   # the day's ordinary round event
	if id not in ctx.processed_battle_ids: ctx.processed_battle_ids.append(id)
	ctx.processed_battle_ids.sort()
	for code: String in pending.att + pending.def:
		if code not in ctx.body_battle.processed_units: ctx.body_battle.processed_units.append(code)
	ctx.body_battle.processed_units.sort()
	ctx.battle_index = int(ctx.battle_index) + 1
	ctx.body_battle.battle_index = str(ctx.battle_index)
	if int(ctx.battle_index) >= ctx.battle_ids.size(): ctx.body_battle.stage = "advance"
	var settle := {"version": 1, "request": {"kind": "round_settle", "battle_id": String(plan.battle_id), "plan_receipt": wrapper.receipt},
		"boundary": boundary.duplicate(true), "basis": {"source": BodyMotion._hash([source.to_dict(), boundary, BodyBattleMotion._context(repo, source)])},
		"motion": {}, "contacts": battle.body_round.contacts.duplicate(true)}
	ctx.body_battle.sequence = str(int(boundary.sequence) + 1)
	candidate.military_migration.body_battle = {"version": "1", "sequence": boundary.sequence, "receipt": BodyMotion._hash(settle),
		"result": "", "closed_motion": outer.get("closed_motion", {}).duplicate(true)}
	candidate.military_migration.body_battle.result = UnitBodies._battle_result_hash(repo, candidate)
	var final := UnitBodies.validate_battle_candidate(repo, candidate, BodyBattleMotion._boundary(candidate))
	if final.status != "complete": return _result("error", "Settled round failed admission: " + final.reason)
	return _result("complete", "Settled one frozen round", candidate, plan.duplicate(true))

## The outer `round_pending` operation, rebuilt identically for its receipt check.
static func _outer(plan: Dictionary, plan_receipt: String, ready: Dictionary) -> Dictionary:
	return {"version": 1, "request": {"kind": "round_pending", "battle_id": String(plan.battle_id), "plan_receipt": plan_receipt},
		"boundary": plan.boundary.duplicate(true), "basis": {"source": plan.basis.source}, "motion": {}, "contacts": ready.contacts.duplicate(true)}

## The existing non-contact strength sources (height, defence stance and camp, events, order).
static func _factors(repo: DataRepository, state: GameState, battle: Dictionary, code: String, attacking: bool,
		enemies: Array, action: Dictionary) -> Array[Dictionary]:
	var factors: Array[Dictionary] = []
	if not enemies.is_empty():
		var enemy_m := 0
		for enemy: String in enemies:
			enemy_m += ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, enemy, state), state)
		@warning_ignore("integer_division")
		enemy_m /= enemies.size()
		factors.append({"source": "ground:height", "category": "formation_terrain",
			"permille": ArmySystem.height_factor(repo, ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, code, state), state) - enemy_m),
			"reason": "Height against the opposing line"})
		factors.append(BattleMatchup.factor(repo, state, code, enemies, attacking))
	if not attacking:
		factors.append({"source": "stance:defence", "category": "formation_terrain",
			"permille": int(BattleSystem._stance_row(repo, BattleSystem.stance_of(state, code)).get("defence_permille", 1000)), "reason": "Delivered defensive stance"})
		factors.append({"source": "camp:defence", "category": "formation_terrain",
			"permille": CampSystem.defence_factor(repo, state, code), "reason": "Camp at its real saved site"})
	factors.append_array(BattleEvents.factors(state, battle, code))
	var kind := String(action.get("kind", "hold"))
	var row: Dictionary = repo.battle_orders.get(kind, {})
	factors.append({"source": "order:" + kind, "category": "action",
		"permille": int(row.get("attack_permille" if attacking else "defence_permille", 1000)), "reason": String(action.get("reason", "Frozen action"))})
	return factors

## Exact effects through the existing personnel planner: grouped orders, per-unit results,
## earned-impact charge units and the stable family-loss event IDs.
static func _effects(repo: DataRepository, state: GameState, battle_id: int, pending: Dictionary) -> Dictionary:
	var out := {}
	var orders: Array = []
	var stance := func(code: String) -> String: return BattleSystem.stance_of(state, code)
	var tier: Dictionary = pending.tier
	var share := int(tier.get("wounded_share_permille", 0))
	for side: String in BattleSystem.SIDES:
		var codes: Array = pending[side].duplicate()
		codes.sort()
		var planned := BattleSystem._plan_side(repo, state, codes, int(tier.get("attacker_loss_permille" if side == "att" else "defender_loss_permille", 0)),
			share, int(tier.get("attacker_morale" if side == "att" else "defender_morale", 0)), String(pending.reason), out, orders, stance,
			tier.unit_loss_permille, tier.unit_morale_permille)
		if planned.has("error"): return planned
	var charged: Array = []
	var losses: Array = []
	for code: String in pending.att + pending.def:
		var charge: Dictionary = BattleSystem._stored(state, code).get("charge", {})
		if charge.get("phase", "") == "impact" and int(charge.get("impact_day", -1)) == int(pending.day): charged.append(code)
	for order: Dictionary in orders:
		var id := "battle:%d:round:%d:%s" % [battle_id, int(pending.round), String(order.unit_code)]
		if id not in losses: losses.append(id)
	charged.sort()
	losses.sort()
	return {"personnel_orders": orders, "unit_results": out, "charge_units": charged, "family_event_ids": losses}

## The saved plan wrapper is exact: closed keys, its receipt over the whole plan, and the
## live pending equal to the plan's pending with this body_round's receipt.
static func _saved_error(battle: Dictionary) -> String:
	var wrapper: Variant = battle.get("body_round_plan")
	if not wrapper is Dictionary or not BodyMotion._keys(wrapper, ["version", "receipt", "plan"]) or wrapper.version != "1" \
		or not wrapper.plan is Dictionary or wrapper.receipt != BodyMotion._hash(wrapper.plan): return "Invalid saved round plan"
	var plan: Dictionary = wrapper.plan
	if not BodyMotion._keys(plan, ["version", "battle_id", "boundary", "basis", "body_round_receipt", "pending", "effects"]) \
		or not plan.pending is Dictionary or not BodyMotion._keys(plan.pending, PENDING_KEYS) \
		or not plan.effects is Dictionary or not BodyMotion._keys(plan.effects, ["personnel_orders", "unit_results", "charge_units", "family_event_ids"]):
		return "Invalid saved round plan schema"
	if not battle.has("body_round") or plan.body_round_receipt != BodyMotion._hash(battle.body_round) \
		or BodyMotion._hash(battle.get("pending_round", {})) != BodyMotion._hash(plan.pending):
		return "Saved round plan disagrees with its frozen pending"
	return ""
