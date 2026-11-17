extends GutTest
## D-SETTLE (CF06 cases 5–7): a frozen round's plan commits atomically on a clone — personnel,
## bodies, family losses, custody, costs and earned impact, the full receipt, the round closed
## and the queue advanced under one outer `round_settle`. A failed late writer leaves the frozen
## pending exactly; a settled retry is a no-op.
## World: D-PENDING's — the crown unit (1000 people, ten rows of 100) holds; the enemy's single
## 100-person cavalry row attacks.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _pending_world() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_round_pending.gd").new()
	var f: Dictionary = helper.call("_ready_world")
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var planned := BodyBattleRounds.plan_candidate(f.repo, f.ready, f.id, BodyBattleMotion._boundary(f.ready))
	assert_eq(planned.status, "complete", planned.reason)
	f.pending = planned.candidate
	f.plan = planned.plan
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _hash(state: GameState) -> String:
	return BodyMotion._hash(state.to_dict())

func _settle(f: Dictionary, state: GameState, plan: Dictionary = {}) -> Dictionary:
	var before := _hash(state)
	var result := BodyBattleRounds.settle_candidate(f.repo, state, f.plan if plan.is_empty() else plan, BodyBattleMotion._boundary(state))
	assert_eq(result.keys().size(), 5, "the CF05 transaction result")
	assert_eq(_hash(state), before, "settlement never mutates its source")
	return result

func _rows(state: GameState, code: String) -> Array:
	var battle: Dictionary = state.battles[0]
	var rows: Variant = battle.get("groups", {}).get(code)
	return (rows if rows is Array else UnitBodies._entry(state, code).body_groups).duplicate(true)

func test_settles_the_frozen_plan_exactly_once() -> void:
	var f := _pending_world()
	var source: GameState = f.pending
	var pending: Dictionary = source.battles[0].pending_round
	var fit_before := {f.unit: MilitaryRoster.fit(source, f.unit), f.enemy: MilitaryRoster.fit(source, f.enemy)}
	var morale_before := {f.unit: int(UnitBodies._entry(source, f.unit).morale), f.enemy: int(UnitBodies._entry(source, f.enemy).morale)}
	var food_before := int(UnitBodies._entry(source, f.enemy).supplies)
	var rows_before := _rows(source, f.unit)
	var result := _settle(f, source)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var state: GameState = result.candidate
	assert_eq(state.rng.to_dict(), source.rng.to_dict(), "settlement draws nothing")
	# Hand-computed casualties: each unit is its own rate group (1000 vs 100 exposure).
	# lost = trunc(fit x rate / 1000), wounded = trunc(lost x 600 / 1000), dead = the rest.
	assert_eq(int(pending.tier.wounded_share_permille), 600)
	for code: String in [f.unit, f.enemy]:
		var rate := int(pending.tier.unit_loss_permille[code])
		var lost: int = int(fit_before[code]) * rate / 1000
		var wounded: int = lost * 600 / 1000
		assert_eq(MilitaryRoster.fit(state, code), int(fit_before[code]) - lost, code)
		assert_eq(f.plan.effects.unit_results[code].dead, lost - wounded, code)
		assert_eq(f.plan.effects.unit_results[code].wounded, wounded, code)
		# Frozen morale applied once, including a zero-loss unit's.
		assert_eq(int(UnitBodies._entry(state, code).morale), clampi(int(morale_before[code]) + int(f.plan.effects.unit_results[code].morale), 0, 100), code)
	# The crown loses 30..150 of 1000 (base tier rate x full exposure), never nothing.
	var crown_lost: int = int(fit_before[f.unit]) - MilitaryRoster.fit(state, f.unit)
	assert_between(crown_lost, 30, 150)
	# Bodies: the first rows keep identity and position, counts are the canonical partition.
	var after := _rows(state, f.unit)
	var counts := BattleGroups.counts(MilitaryRoster.fit(state, f.unit), int(f.repo.bal("battle_group_size")))
	assert_eq(after.size(), counts.size())
	for i: int in after.size():
		assert_eq(after[i].slot, rows_before[i].slot)
		assert_eq([after[i].x_m, after[i].y_m], [rows_before[i].x_m, rows_before[i].y_m])
		assert_eq(int(after[i].count), counts[i])
	# The attacker's extra food once.
	assert_eq(int(UnitBodies._entry(state, f.enemy).supplies), food_before - int(pending.costs[0].supplies))
	# The ordinary round event ids and the full receipt.
	var n := int(pending.round)
	assert_true(state.military_events.has("battle:%d:round:%d" % [f.id, n]))
	assert_true(state.military_events.has("battle:%d:round:%d:personnel" % [f.id, n]))
	var receipt: Dictionary = state.military_events["bodyround:%d:%d:%d:settlement" % [f.id, int(pending.day), n]]
	assert_eq(receipt.request, {"kind": "body_round_settlement", "plan": f.plan})
	assert_eq(receipt.result.keys().size(), 4)
	assert_eq(receipt.result.pending, pending)
	assert_eq(receipt.result.effects, f.plan.effects)
	assert_eq(receipt.result.personnel_event_id, "battle:%d:round:%d:personnel" % [f.id, n])
	assert_eq(receipt.result.round_event.results, f.plan.effects.unit_results)
	assert_eq(receipt.result.round_event.roll, pending.roll)
	# The round closed; the field and its units processed; the one-field queue exhausted.
	var battle: Dictionary = state.battles[0]
	for key: String in ["body_round", "pending_round", "body_round_plan"]: assert_false(battle.has(key), key)
	assert_eq(int(battle.rounds), n)
	assert_eq(int(battle.last_resolved_day), state.absolute_day())
	assert_eq(battle.family_loss_ids, f.plan.effects.family_event_ids)
	assert_true(f.id in state.day_resolution.processed_battle_ids)
	var units := [f.unit, f.enemy]
	units.sort()
	assert_eq(state.day_resolution.body_battle.processed_units, units)
	assert_eq(state.day_resolution.body_battle.stage, "advance")
	assert_eq(int(state.day_resolution.body_battle.sequence), int(source.day_resolution.body_battle.sequence) + 1)
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, state, BodyBattleMotion._boundary(state)).status, "complete")

func test_settled_retries_are_no_ops_and_saves_round_trip() -> void:
	var f := _pending_world()
	var first := _settle(f, f.pending)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	var settled: GameState = first.candidate
	# Settling a JSON save of the pending state gives the identical world.
	assert_eq(_hash(_settle(f, _json(f.pending)).candidate), _hash(settled))
	for source: GameState in [settled, _json(settled)]:
		var again := _settle(f, source)
		assert_eq(again.status, "complete", again.reason)
		assert_eq(_hash(again.candidate), _hash(source), "one round event, one cost, one queue advance")
		# The caller's pre-settlement boundary is a retry of the same settlement too.
		var old := BodyBattleRounds.settle_candidate(f.repo, source, f.plan, BodyBattleMotion._boundary(f.pending))
		assert_eq(old.status, "complete", old.reason)
		assert_eq(_hash(old.candidate), _hash(source))
	# A conflicting plan for the settled round rejects.
	var other: Dictionary = f.plan.duplicate(true)
	other.pending.reason = "forged"
	assert_eq(_settle(f, settled, other).status, "error")
	# The day moves on from the advanced queue.
	var engine := TickEngine.new(f.repo)
	var next: Dictionary = engine.step_body_battle_candidate(settled)
	assert_ne(next.status, "error", next.reason)

func test_a_failed_late_writer_keeps_the_frozen_pending() -> void:
	var f := _pending_world()
	var n := int(f.plan.pending.round)
	# A stale conflicting receipt outside the round's basis: personnel origin, then family losses.
	for injected: String in ["battle:%d:round:%d:personnel" % [f.id, n], "family:battle:%d:round:%d:%s" % [f.id, n, f.unit]]:
		var broken := _json(f.pending)
		broken.military_events[injected] = {"request": {"kind": "stale"}, "result": {}}
		BodyBattle._seal_private(f.repo, broken)
		var failed := _settle(f, broken)
		assert_eq(failed.status, "blocked", injected)
		assert_eq(failed.error, "")
		assert_ne(failed.reason, "")
		assert_eq(failed.plan, f.plan, "the identical plan")
		assert_eq(_hash(failed.candidate), _hash(broken), "no partial personnel, morale, food, bodies, impact or cursor")
		assert_eq(_hash(_json(failed.candidate)), _hash(broken), "the retryable state saves verbatim")
		# Repairing only the external prerequisite settles the same frozen draw.
		var repaired := _json(failed.candidate)
		repaired.military_events.erase(injected)
		BodyBattle._seal_private(f.repo, repaired)
		var settled := _settle(f, repaired)
		assert_eq(settled.status, "complete", settled.reason)
		assert_eq(_hash(settled.candidate), _hash(_settle(f, f.pending).candidate))

func test_tampering_changed_basis_and_wrong_stage_reject() -> void:
	var f := _pending_world()
	# Unsealed tampering: the endpoint proof catches it.
	var bad := _json(f.pending)
	bad.battles[0].pending_round.roll += 1
	assert_eq(_settle(f, bad).status, "error")
	# Resealed forgeries: the saved plan, the outer receipt and the basis catch them.
	for forge: String in ["pending", "wrapper", "outer", "basis", "rounds"]:
		var forged := _json(f.pending)
		var live: Dictionary = forged.battles[0]
		match forge:
			"pending": live.pending_round.eff += 1
			"wrapper": live.body_round_plan.plan.effects.charge_units = ["forged"]
			"outer": forged.military_migration.body_battle.receipt = "0".repeat(64)
			"basis": UnitBodies._entry(forged, f.unit).morale = int(UnitBodies._entry(forged, f.unit).morale) - 1
			"rounds": live.rounds = 3
		BodyBattle._seal_private(f.repo, forged)
		var refused := _settle(f, forged)
		assert_eq(refused.status, "error", forge)
		assert_null(refused.candidate, forge)
	# A plan other than the saved one, a malformed plan, a wrong stage.
	var other: Dictionary = f.plan.duplicate(true)
	other.effects.unit_results[f.enemy].morale -= 1
	assert_eq(_settle(f, f.pending, other).status, "error")
	assert_eq(_settle(f, f.pending, {"version": 1}).status, "error")
	var wrong := BodyBattleMotion._boundary(f.pending)
	wrong.stage = "advance"
	assert_eq(BodyBattleRounds.settle_candidate(f.repo, f.pending, f.plan, wrong).status, "error")
	# A ready round not yet planned waits for its planning.
	var helper: GutTest = load("res://tests/engine/test_body_round_pending.gd").new()
	var g: Dictionary = helper.call("_ready_world")
	helper.free()
	var waiting := BodyBattleRounds.settle_candidate(g.repo, g.ready, f.plan, BodyBattleMotion._boundary(g.ready))
	assert_eq(waiting.status, "deferred", waiting.reason)
