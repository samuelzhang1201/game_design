extends GutTest
## D-RECONCILE (CF06 case 7): a frozen round's settled losses reach the bodies without
## closing the round. The world: the crown unit (901 people, rows 9 x 100 + 1) and the enemy's
## single 100-person row, round-ready after B-ROUND's begin/move/contacts/acknowledge.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _frozen(own_fit: int = 901) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_motion.gd").new()
	var f: Dictionary = helper.call("_world", own_fit)
	var states: Array = helper.call("_to_ready", f, false)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var state: GameState = states.back()
	var battle: Dictionary = state.battles[0]
	var ready: Dictionary = battle.body_round
	battle.pending_round = {"day": state.absolute_day(), "round": int(ready.round), "att": battle.att.duplicate(), "def": battle.def.duplicate(),
		"tier": BattleSystem.tier_of(f.repo, 500).duplicate(true), "att_power": 1, "def_power": 1,
		"odds": 500, "roll": 500, "eff": 500, "contexts": {
			"att": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"},
			"def": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"}},
		"reason": "Frozen round", "costs": [], "unit_actions": {}, "body_round_receipt": BodyMotion._hash(ready)}
	f.state = state
	f.id = int(battle.id)
	return f

func _lose(f: Dictionary, losses: Dictionary, event := "") -> void:
	var orders: Array = []
	for code: String in losses:
		orders.append({"unit_code": code, "from": "fit", "to": "dead", "count": losses[code]})
	var id := event if event != "" else "battle:%d:round:1:personnel" % f.id
	var applied := MilitaryRoster.transfer_units(f.repo, f.state, id, orders, "Round losses")
	assert_false(applied.has("error"), str(applied.get("error", "")))

func _reconcile(f: Dictionary, request: Dictionary = {}) -> Dictionary:
	var before := BodyMotion._hash(f.state.to_dict())
	var proposed := request if not request.is_empty() else {"battle_id": f.id, "round": 1}
	var result := UnitBodies.reconcile_round_candidate(f.repo, f.state, proposed, BodyBattleMotion._boundary(f.state))
	assert_eq(result.keys().size(), 5, "UnitBodies' five-field result")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before, "the source never changes")
	return result

func test_losses_901_to_900_and_100_to_0_retire_only_required_rows() -> void:
	var f := _frozen()
	var rows: Array = f.state.battles[0].groups[f.unit].duplicate(true)
	assert_eq(rows.map(func(r: Dictionary) -> int: return r.count), [100, 100, 100, 100, 100, 100, 100, 100, 100, 1])
	var next: int = UnitBodies._entry(f.state, f.unit).group_next_slot
	_lose(f, {f.unit: 1, f.enemy: 100})
	var result := _reconcile(f)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var after: Array = result.candidate.battles[0].groups[f.unit]
	# 900 = 9 x 100: slots 0..8 survive verbatim (identity, home, position, path, facing); slot 9 retires.
	assert_eq(after.size(), 9)
	for i: int in 9:
		assert_eq(after[i], rows[i])
	assert_false(after.any(func(r: Dictionary) -> bool: return int(r.slot) == int(rows[9].slot)))
	assert_eq(UnitBodies._entry(result.candidate, f.unit).group_next_slot, next, "retired slots are never reused")
	# 100 -> 0: the enemy keeps an empty store under its battle owner.
	assert_eq(result.candidate.battles[0].groups[f.enemy], [])
	assert_true(f.enemy in result.candidate.battles[0].def or f.enemy in result.candidate.battles[0].att)
	assert_eq(int(UnitBodies._owners(result.candidate).owners[f.enemy].id), f.id)
	# Sums equal the ledger; the frozen round stays open with its envelope and payload.
	for code: String in [f.unit, f.enemy]:
		var total := 0
		for row: Dictionary in result.candidate.battles[0].groups[code]: total += int(row.count)
		assert_eq(total, MilitaryRoster.fit(result.candidate, code), code)
	assert_eq(result.candidate.battles[0].body_round, f.state.battles[0].body_round)
	assert_eq(result.candidate.battles[0].pending_round, f.state.battles[0].pending_round)
	assert_eq(result.candidate.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(result.candidate.military_cohorts, f.state.military_cohorts)
	assert_eq(UnitBodies._entry(result.candidate, f.enemy).group_next_slot, UnitBodies._entry(f.state, f.enemy).group_next_slot)
	assert_eq(UnitBodies._entry(result.candidate, f.other).body_groups, UnitBodies._entry(f.state, f.other).body_groups, "non-participants untouched")

func test_partial_loss_keeps_every_row_and_rewrites_counts() -> void:
	var f := _frozen(1000)
	var rows: Array = f.state.battles[0].groups[f.unit].duplicate(true)
	_lose(f, {f.unit: 99})
	var result := _reconcile(f)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	# 1000 - 99 = 901 = 9 x 100 + 1: all ten rows stay, the last now holds 1.
	var after: Array = result.candidate.battles[0].groups[f.unit]
	assert_eq(after.map(func(r: Dictionary) -> int: return r.count), [100, 100, 100, 100, 100, 100, 100, 100, 100, 1])
	for i: int in 10:
		for key: String in ["slot", "home_slot", "x_m", "y_m", "facing_deg"]:
			assert_eq(after[i][key], rows[i][key])

func test_retry_capture_and_json_are_exact() -> void:
	var f := _frozen()
	# A capture is a loss like a death: fit 901 -> 900.
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "battle:%d:round:1:personnel" % f.id,
		[{"unit_code": f.unit, "from": "fit", "to": "captured_current", "count": 1}], "Round captures").has("error"))
	var first := _reconcile(f)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	assert_eq(first.candidate.battles[0].groups[f.unit].size(), 9)
	var second := _reconcile(f)
	assert_eq(BodyMotion._hash(second.candidate.to_dict()), BodyMotion._hash(first.candidate.to_dict()), "two calls agree")
	# A retry on the reconciled stage (direct and through a JSON save) is an exact no-op.
	var json: GameState = GameState.from_dict(JSON.parse_string(JSON.stringify(first.candidate.to_dict())), false)
	for stage: GameState in [first.candidate, json]:
		var again := UnitBodies.reconcile_round_candidate(f.repo, stage, {"battle_id": f.id, "round": 1}, BodyBattleMotion._boundary(stage))
		assert_eq(again.status, "complete", again.reason)
		if again.candidate != null: assert_eq(BodyMotion._hash(again.candidate.to_dict()), BodyMotion._hash(first.candidate.to_dict()))

func test_unrelated_staged_changes_and_bad_provenance_reject() -> void:
	# A loss outside the round's event: `other` is no participant and its bodies now disagree.
	var f := _frozen()
	_lose(f, {f.unit: 1})
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "unrelated:1",
		[{"unit_code": f.other, "from": "fit", "to": "dead", "count": 1}], "Elsewhere").has("error"))
	var unrelated := _reconcile(f)
	assert_eq(unrelated.status, "error")
	assert_true(unrelated.reason.contains("validation"), unrelated.reason)
	# A participant's extra loss outside the round's event is not the round's result.
	f = _frozen()
	_lose(f, {f.unit: 1})
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "unrelated:2",
		[{"unit_code": f.unit, "from": "fit", "to": "dead", "count": 100}], "Elsewhere").has("error"))
	var extra := _reconcile(f)
	assert_eq(extra.status, "error")
	assert_true(extra.reason.contains("round's own losses"), extra.reason)
	# A forged receipt (empty changes, a healing direction) is not an applied round event.
	f = _frozen()
	f.state.military_events["battle:%d:round:1:personnel" % f.id] = {"request": {"kind": "transfer_units"}, "result": {"status": "applied", "changes": []}}
	assert_eq(_reconcile(f).status, "error")
	f = _frozen()
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "battle:%d:round:1:personnel" % f.id,
		[{"unit_code": f.unit, "from": "fit", "to": "released", "count": 1}], "Not a casualty").has("error"))
	assert_true(_reconcile(f).reason.contains("casualty"))
	# A change with no whole positive count is not a casualty movement.
	f = _frozen()
	_lose(f, {f.unit: 1})
	var event: Dictionary = f.state.military_events["battle:%d:round:1:personnel" % f.id]
	event.result.changes[0].erase("count")
	assert_true(_reconcile(f).reason.contains("casualty"))
	# The field must be the current queued one.
	f = _frozen()
	_lose(f, {f.unit: 1})
	f.state.day_resolution.battle_ids = [f.id + 1]
	assert_eq(_reconcile(f).status, "error")
	# The round's own event touching a non-participant.
	f = _frozen()
	_lose(f, {f.unit: 1, f.other: 1})
	assert_true(_reconcile(f).reason.contains("non-participant"))
	# No settled personnel event, another round, a malformed request, no pending round.
	f = _frozen()
	assert_true(_reconcile(f).reason.contains("personnel event"))
	_lose(f, {f.unit: 1})
	assert_true(_reconcile(f, {"battle_id": f.id, "round": 2}).reason.contains("frozen round"))
	for bad: Dictionary in [{"battle_id": f.id}, {"battle_id": str(f.id), "round": 1}, {"battle_id": 0, "round": 1},
		{"battle_id": f.id, "round": 1, "extra": true}, {"battle_id": 99, "round": 1}]:
		assert_eq(_reconcile(f, bad).status, "error", str(bad))
	var stripped := UnitBodies._copy(f.state)
	stripped.battles[0].erase("pending_round")
	assert_eq(UnitBodies.reconcile_round_candidate(f.repo, stripped, {"battle_id": f.id, "round": 1}, BodyBattleMotion._boundary(stripped)).status, "error")
	# The boundary must be the saved round boundary.
	var boundary := BodyBattleMotion._boundary(f.state)
	for key: String in ["stage", "abs_day", "substep", "sequence", "version"]:
		var bad := BodyBattleMotion._boundary(f.state)
		bad[key] = 2 if key == "version" else ("advance" if key == "stage" else "9")
		assert_eq(UnitBodies.reconcile_round_candidate(f.repo, f.state, {"battle_id": f.id, "round": 1}, bad).status, "error", key)
	assert_eq(UnitBodies.reconcile_round_candidate(null, f.state, {"battle_id": f.id, "round": 1}, BodyBattleMotion._boundary(f.state)).status, "error")

func test_stored_order_is_kept_and_no_row_grows() -> void:
	# A store saved in a non-slot order: the canonical counts follow stored order, so the
	# loss trims the stored tail and no 1-person row ever becomes a 100-person row.
	var f := _frozen()
	var rows: Array = f.state.battles[0].groups[f.unit]
	var last: Dictionary = rows[9]
	rows.remove_at(9)
	rows.push_front(last)   # stored order now [slot 9 (1), slot 0..8 (100 each)]
	BodyBattle._seal_private(f.repo, f.state)
	_lose(f, {f.unit: 1})
	var result := _reconcile(f)
	assert_eq(result.status, "error", "stored order is not canonical: no row may grow")
	assert_true(result.reason.contains("move personnel"), result.reason)
	# Malformed participant rows reject rather than crash.
	f = _frozen()
	f.state.battles[0].groups[f.unit][0].erase("count")
	_lose(f, {f.unit: 1})
	assert_eq(_reconcile(f).status, "error")

func test_growth_is_never_a_round_result() -> void:
	var f := _frozen()
	_lose(f, {f.unit: 1})
	# A participant whose fit rose above its bodies (a forged recruit in the stage) rejects.
	var forged := UnitBodies._copy(f.state)
	var personnel: GDScript = load("res://tests/engine/personnel_helpers.gd")
	assert_false(personnel.replace(f.repo, forged, f.enemy, 150).has("error"))
	var result := UnitBodies.reconcile_round_candidate(f.repo, forged, {"battle_id": f.id, "round": 1}, BodyBattleMotion._boundary(forged))
	assert_eq(result.status, "error")
	assert_true(result.reason.contains("grow"), result.reason)
