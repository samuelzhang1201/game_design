extends GutTest
## D-PENDING (CF06 case 6): the first planning of a round-ready field freezes the pending
## payload, its exact effects and ONE RNG draw together; retries never redraw.
## World: B-ROUND's crown unit (1000 people, ten rows; only row 0 touches) holding against the
## enemy's single 100-person cavalry row, whose received plan is to attack.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _ready_world(supplies: int = 1000000, ceasefire: bool = false) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_motion.gd").new()
	var f: Dictionary = helper.call("_world", 1000)
	UnitBodies._entry(f.state, f.enemy).supplies = supplies
	var state: GameState = f.engine.begin_body_battle_candidate(f.state).candidate
	state = helper.call("_step", f, state, "complete")   # move
	state = helper.call("_step", f, state, "complete")   # contacts found the field
	# The enemy's received action is an attack; the crown unit holds.
	var field: Dictionary = state.battles[0]
	var enemy_side := "att" if f.enemy in field.att else "def"
	field.actions[enemy_side] = {"kind": "attack", "reason": "Received advance plan"}
	if ceasefire:
		var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
		field.parley.agreed = {"ceasefire": term}
		field.parley.parties = {"att": field.att.duplicate(), "def": field.def.duplicate()}
	BodyBattle._seal_private(f.repo, state)
	state = helper.call("_step", f, state, "blocked")    # encounter decision
	state = helper.call("_acknowledge", f, state)
	state = helper.call("_step", f, state, "blocked")    # round ready
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.ready = state
	f.id = int(state.battles[0].id)
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _plan(f: Dictionary, state: GameState) -> Dictionary:
	var before := BodyMotion._hash(state.to_dict())
	var result := BodyBattleRounds.plan_candidate(f.repo, state, f.id, BodyBattleMotion._boundary(state))
	assert_eq(result.keys().size(), 5, "the CF05 transaction result")
	assert_eq(BodyMotion._hash(state.to_dict()), before, "planning never mutates its source")
	return result

func test_one_draw_frozen_with_exact_payload_and_effects() -> void:
	var f := _ready_world()
	var battle: Dictionary = f.ready.battles[0]
	assert_eq(battle.body_round.unit_actions[f.enemy].kind, "attack")
	var result := _plan(f, f.ready)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var state: GameState = result.candidate
	var live: Dictionary = state.battles[0]
	var pending: Dictionary = live.pending_round
	assert_eq(pending.keys().size(), 15)
	assert_eq(pending.body_round_receipt, BodyMotion._hash(battle.body_round))
	# Exactly one engine draw: the ready state's RNG advanced once gives the frozen roll.
	var rng := Rng.from_dict(f.ready.rng.to_dict())
	var draw := rng.randi_range(0, 999)
	assert_eq(pending.roll, draw)
	assert_eq(state.rng.to_dict(), rng.to_dict())
	# odds = trunc(1000 A / (A + D)); eff = clamp(odds + trunc((roll - 500) v / 1000), 0, 1000).
	var a := int(pending.att_power)
	var d := int(pending.def_power)
	assert_gt(a, 0)
	assert_gt(d, 0)
	assert_eq(pending.odds, 1000 * a / (a + d))
	var variance := int(f.repo.bal("battle_variance_permille"))
	assert_eq(pending.eff, clampi(int(pending.odds) + (draw - 500) * variance / 1000, 0, 1000))
	assert_true(int(pending.tier.eff_min) <= int(pending.eff) and int(pending.eff) <= int(pending.tier.eff_max))
	# Per-unit contexts: the crown unit's only lawful source is the enemy's whole row (100 of 100):
	# exposure 1000; the enemy is exposed to the crown's one touching row of 1000: exposure 100.
	var base := BattleSystem.tier_of(f.repo, int(pending.eff))
	var side_of := func(code: String) -> String: return "att" if code in pending.att else "def"
	for row: Array in [[f.unit, 1000], [f.enemy, 100]]:
		var key := "attacker_loss_permille" if side_of.call(row[0]) == "att" else "defender_loss_permille"
		assert_eq(pending.tier.unit_morale_permille[row[0]], row[1], row[0])
		assert_eq(pending.tier.unit_loss_permille[row[0]], int(base[key]) * row[1] / 1000, row[0])
	# Costs: the attacking enemy's extra food once, ceil(day bite x extra permille / 1000).
	assert_eq(pending.costs.size(), 1)
	assert_eq(pending.costs[0].code, f.enemy)
	var reg := ArmySystem.regiment(f.repo, f.enemy, f.ready)
	var bite := ArmySystem.day_bite(ArmySystem.supply_use(f.repo, reg, f.ready), f.ready.day)
	assert_eq(pending.costs[0].supplies, (bite * int(f.repo.battle_orders.attack.extra_supply_permille) + 999) / 1000)
	assert_eq(pending.costs[0].reason, "Additional supplies for an actual all-out attack day")
	# Effects from the existing personnel planner: the crown unit loses trunc(1000 x rate / 1000).
	var plan: Dictionary = result.plan
	assert_eq(plan.pending, pending)
	var rate := int(pending.tier.unit_loss_permille[f.unit])
	var share := int(pending.tier.wounded_share_permille)
	var split := BattleSystem.split_losses(1000, rate, share)
	var mine: Array = plan.effects.personnel_orders.filter(func(o: Dictionary) -> bool: return o.unit_code == f.unit)
	var lost := 0
	for order: Dictionary in mine: lost += int(order.count)
	assert_eq(lost, int(split.lost))
	assert_eq(plan.effects.unit_results[f.unit].dead + plan.effects.unit_results[f.unit].wounded, int(split.lost))
	if int(split.lost) > 0: assert_true(("battle:%d:round:1:%s" % [f.id, f.unit]) in plan.effects.family_event_ids)
	assert_true(plan.effects.unit_results.has(f.enemy))
	assert_eq(plan.effects.charge_units, [])
	assert_true(String(pending.reason).contains("attacker "), pending.reason)
	# The wrapper, the outer round_pending operation and no personnel change yet.
	assert_eq(live.body_round_plan.receipt, BodyMotion._hash(plan))
	assert_eq(live.body_round, battle.body_round)
	assert_eq(state.military_migration.body_battle.sequence, f.ready.day_resolution.body_battle.sequence)
	assert_eq(int(state.day_resolution.body_battle.sequence), int(f.ready.day_resolution.body_battle.sequence) + 1)
	assert_eq(state.military_cohorts, f.ready.military_cohorts)
	for code: String in [f.unit, f.enemy]:
		assert_eq(UnitBodies._entry(state, code).supplies, UnitBodies._entry(f.ready, code).supplies)
		assert_eq(UnitBodies._entry(state, code).morale, UnitBodies._entry(f.ready, code).morale)

func test_retries_never_redraw_and_saves_round_trip() -> void:
	var f := _ready_world()
	var first := _plan(f, f.ready)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	var published: GameState = first.candidate
	# Before the draw: a JSON save of the ready state plans the identical frozen payload.
	var again := _plan(f, _json(f.ready))
	assert_eq(BodyMotion._hash(again.plan), BodyMotion._hash(first.plan))
	assert_eq(BodyMotion._hash(again.candidate.to_dict()), BodyMotion._hash(published.to_dict()))
	# After the draw: a repeat, direct and through JSON, returns the frozen state with no second draw.
	for source: GameState in [published, _json(published)]:
		var repeat := _plan(f, source)
		assert_eq(repeat.status, "complete", repeat.reason)
		assert_eq(repeat.plan, first.plan)
		assert_eq(repeat.candidate.rng.to_dict(), published.rng.to_dict())
		assert_eq(BodyMotion._hash(repeat.candidate.to_dict()), BodyMotion._hash(published.to_dict()))
		assert_eq(BodyMotion._hash(_json(source).to_dict()), BodyMotion._hash(source.to_dict()), "the plan survives saves verbatim")
	# The frozen round still waits for settlement: a step is a blocked no-op.
	var engine := TickEngine.new(f.repo)
	var held: Dictionary = engine.step_body_battle_candidate(published)
	assert_eq(held.status, "blocked", held.reason)

func test_changed_basis_tampering_and_wrong_field_reject() -> void:
	var f := _ready_world()
	# A row moved after readiness: the basis changed (resealed, so only the basis catches it).
	var moved := UnitBodies._copy(f.ready)
	moved.battles[0].groups[f.unit][5].y_m += 1
	BodyBattle._seal_private(f.repo, moved)
	var changed := _plan(f, moved)
	assert_eq(changed.status, "error")
	assert_true(changed.reason.contains("basis"), changed.reason)
	# Tampered frozen payloads in a published state reject.
	var published: GameState = _plan(f, f.ready).candidate
	for tamper: String in ["roll", "cost", "plan", "rng"]:
		var bad := _json(published)
		match tamper:
			"roll": bad.battles[0].pending_round.roll += 1
			"cost": bad.battles[0].pending_round.costs[0].supplies += 1
			"plan": bad.battles[0].body_round_plan.plan.effects.charge_units = ["forged"]
			"rng": bad.rng.randi_range(0, 9)
		assert_eq(_plan(f, bad).status, "error", tamper)
	# Resealed forgeries: the endpoint hash no longer catches them, the saved-plan checks do.
	for forge: String in ["pending", "stale_receipt", "consistent", "basis"]:
		var bad := _json(published)
		var live: Dictionary = bad.battles[0]
		match forge:
			"pending": live.pending_round.eff += 1
			"stale_receipt": live.body_round_plan.plan.effects.charge_units = ["forged"]
			"consistent":
				live.pending_round.roll += 1
				live.body_round_plan.plan.pending.roll += 1
				live.body_round_plan.receipt = BodyMotion._hash(live.body_round_plan.plan)
			"basis": live.groups[f.unit][5].y_m += 1
		BodyBattle._seal_private(f.repo, bad)
		var forged := _plan(f, bad)
		assert_eq(forged.status, "error", forge)
		assert_null(forged.candidate)
	# Only the current queued field, with real inputs.
	assert_eq(BodyBattleRounds.plan_candidate(f.repo, f.ready, f.id + 1, BodyBattleMotion._boundary(f.ready)).status, "error")
	assert_eq(BodyBattleRounds.plan_candidate(null, f.ready, f.id, BodyBattleMotion._boundary(f.ready)).status, "error")
	var wrong := BodyBattleMotion._boundary(f.ready)
	wrong.stage = "advance"
	assert_eq(BodyBattleRounds.plan_candidate(f.repo, f.ready, f.id, wrong).status, "error")

func test_readiness_holds_a_law_barred_attack() -> void:
	# Production's side fallback runs before the freeze: a side attack the frozen agreement bars
	# is frozen as hold, so planning never prices or powers an unlawful attack.
	var f := _ready_world(1000000, true)
	var battle: Dictionary = f.ready.battles[0]
	assert_eq(battle.body_round.unit_actions[f.enemy].kind, "hold")
	var enemy_side := "att" if f.enemy in battle.att else "def"
	assert_true(String(battle.actions[enemy_side].reason).contains("barred"), str(battle.actions[enemy_side]))
	var result := _plan(f, f.ready)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate != null: assert_eq(result.candidate.battles[0].pending_round.costs, [])

func test_an_uncommitted_reserve_adds_no_attack_power() -> void:
	# The attacking enemy sits in reserve with no task: like production side_power, its side
	# adds no power (odds 0 against the holding crown unit) and pays no attack food.
	var f := _ready_world()
	var reserved := UnitBodies._copy(f.ready)
	reserved.battles[0].reserves = {f.enemy: {"reason": "Held back"}}
	BodyBattle._seal_private(f.repo, reserved)
	# The reserve changes the basis: readiness must be re-earned, so plan from a fresh ready day.
	assert_eq(_plan(f, reserved).status, "error", "a reserve set after readiness changes the basis")
	var helper: GutTest = load("res://tests/engine/test_body_battle_motion.gd").new()
	var g: Dictionary = helper.call("_world", 1000)
	UnitBodies._entry(g.state, g.enemy).supplies = 1000000
	var state: GameState = g.engine.begin_body_battle_candidate(g.state).candidate
	state = helper.call("_step", g, state, "complete")
	state = helper.call("_step", g, state, "complete")
	var field: Dictionary = state.battles[0]
	var enemy_side := "att" if g.enemy in field.att else "def"
	field.actions[enemy_side] = {"kind": "attack", "reason": "Received advance plan"}
	field.reserves = {g.enemy: {"reason": "Held back"}}
	BodyBattle._seal_private(g.repo, state)
	state = helper.call("_step", g, state, "blocked")
	state = helper.call("_acknowledge", g, state)
	state = helper.call("_step", g, state, "blocked")
	helper.free()
	var result := BodyBattleRounds.plan_candidate(g.repo, state, int(state.battles[0].id), BodyBattleMotion._boundary(state))
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var pending: Dictionary = result.candidate.battles[0].pending_round
	assert_eq(pending[enemy_side + "_power"], 0)
	assert_eq(pending.costs, [])
