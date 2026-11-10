extends GutTest
## B-END: candidate end/cancel release. Field 8 holds the crown unit (att, 901 people in
## ten rows), the enemy (def, one row of 100) and `other` (def, zero fit: an empty store).
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_deploy.gd").new()
	var f: Dictionary = helper.call("_field", 901)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var state: GameState = f.state
	assert_false(Personnel.replace(f.repo, state, f.other, 0).has("error"))
	var battle: Dictionary = state.battles[0]
	battle.groups[f.other] = []
	battle.rounds = 2
	battle.town = ""
	for side: String in BattleSystem.SIDES:
		for code: String in battle[side]:
			BattleReport.enroll(state, battle, code, side)
	state.battle_orders = {"w1": {"status": "pending", "reserved_gold": 40,
		"request": {"battle_id": 8, "side": "att", "kind": "attack"}}}
	var tx := state.day_resolution
	tx.body_battle.stage = "advance"
	tx.battle_step = "fighting"
	tx.battle_ids = [8]
	tx.battle_index = 1
	tx.processed_battle_ids = [8]
	tx.body_battle.battle_ids = ["8"]
	tx.body_battle.battle_index = "1"
	BodyBattle._seal_private(f.repo, state)
	f.rows = {}
	for code: String in f.codes:
		f.rows[code] = battle.groups[code].duplicate(true)
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _request(kind: String = "cancel") -> Dictionary:
	return {"kind": kind, "battle_id": "8", "reason": "Received terminal release"}

func _run(f: Dictionary, request: Dictionary, state: GameState = null) -> Dictionary:
	if state == null: state = f.state
	var boundary := BodyBattleMotion._boundary(state)
	var before := BodyMotion._hash(state.to_dict())
	var plan := BodyBattle.plan_candidate(f.repo, state, request, boundary)
	assert_eq(BodyMotion._hash(state.to_dict()), before, "planning leaves the source unchanged")
	if plan.status != "complete": return plan
	var result := BodyBattle.commit_candidate(f.repo, state, plan.plan, boundary)
	assert_eq(BodyMotion._hash(state.to_dict()), before, "commit publishes a detached state")
	result.plan = plan.plan
	return result

func test_release_before_delete_and_rollback() -> void:
	var f := _fixture()
	# The zero-fit unit's empty store still has its battle owner before release.
	assert_eq(int(UnitBodies._owners(f.state).owners[f.other].id), 8)
	assert_eq(f.state.battles[0].groups[f.other], [])
	var result := _run(f, _request())
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var state: GameState = result.candidate
	assert_eq(state.battles, [], "the field is deleted only after every store left it")
	var anchors := {f.unit: [40000, 60000], f.enemy: [100000, 60000], f.other: [70000, 100000]}
	for code: String in f.codes:
		var entry := UnitBodies._entry(state, code)
		assert_eq(entry.body_groups, f.rows[code], code)
		assert_eq(entry.group_anchor_m, anchors[code])
		assert_eq(entry.group_facing, 0 if code == f.unit else 180)
		assert_eq(entry.group_next_slot, 20)
		assert_true(UnitBodies._owners(state).owners.get(code, {}).is_empty(), "owner zero")
	assert_eq(UnitBodies._entry(state, f.unit).body_groups.size(), 10)
	assert_eq(UnitBodies._entry(state, f.enemy).body_groups.map(func(r: Dictionary) -> int: return r.count), [100])
	# Report: participants are the enrolled fit 901 (att) and 100 + 0 (def); nothing died.
	var record: Dictionary = state.battle_records["8"]
	assert_eq(record.personnel.att.participants, 901)
	assert_eq(record.personnel.att.fit, 901)
	assert_eq(record.personnel.def.participants, 100)
	assert_eq(record.personnel.def.fit, 100)
	assert_eq(record.rounds, 2)
	assert_eq(record.end_day, f.state.absolute_day())
	var event: Dictionary = state.day_resolution.journal.battles.back()
	assert_eq(event.kind, "end")
	assert_eq(event.why, "called_off")
	assert_eq(event.winner, "")
	assert_eq(event.att, [f.unit])
	assert_eq(event.def, [f.enemy, f.other])
	assert_eq(event.reason, "Received terminal release")
	# Terminal warrant receipt: the reservation is released, the record kept.
	assert_eq(state.battle_orders.w1.status, "invalid")
	assert_eq(state.battle_orders.w1.reserved_gold, 0)
	assert_eq(state.battle_orders.w1.reason, "Battle ended: called_off")
	# The exhausted advance queue drops the deleted field; the day keeps it as processed.
	assert_eq(state.day_resolution.battle_ids, [])
	assert_eq(state.day_resolution.battle_index, 0)
	assert_eq(state.day_resolution.body_battle.battle_ids, [])
	assert_eq(state.day_resolution.body_battle.battle_index, "0")
	assert_eq(state.day_resolution.processed_battle_ids, [8])
	assert_eq(state.day_resolution.body_battle.stage, "advance")
	assert_eq(state.day_resolution.body_battle.sequence, "1")
	assert_eq(state.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(state.military_cohorts, f.state.military_cohorts)
	assert_eq(state.metrics, f.state.metrics)
	var boundary := BodyBattleMotion._boundary(f.state)
	for source: GameState in [state, _json(state)]:
		var file := BodyMotion._hash(source.to_dict())
		var retry := BodyBattle.commit_candidate(f.repo, source, result.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		assert_eq(BodyMotion._hash(source.to_dict()), file, "a retry leaves its source unchanged")
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(state.to_dict()))
	# Rollback: a forged or stale plan publishes nothing.
	var forged: Dictionary = result.plan.duplicate(true)
	forged.request.reason = "Another reason"
	var before := BodyMotion._hash(f.state.to_dict())
	var refused := BodyBattle.commit_candidate(f.repo, f.state, forged, boundary)
	assert_eq(refused.status, "error")
	assert_null(refused.candidate)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)

func _empty_att(f: Dictionary) -> void:
	# The crown unit already withdrew: its exact store stands at owner zero.
	var battle: Dictionary = f.state.battles[0]
	var entry := UnitBodies._entry(f.state, f.unit)
	entry.body_groups = battle.groups[f.unit]
	entry.group_anchor_m = battle.group_anchor_m[f.unit]
	entry.group_facing = battle.group_facing[f.unit]
	for field: String in ["groups", "group_anchor_m", "group_facing"]:
		battle[field].erase(f.unit)
	battle.att = []
	BodyBattle._seal_private(f.repo, f.state)

func test_end_needs_an_emptied_side_and_names_the_winner() -> void:
	var f := _fixture()
	var before := BodyMotion._hash(f.state.to_dict())
	var early := _run(f, _request("end"))
	assert_eq(early.status, "deferred")
	assert_eq(early.reason, "The battle has not ended")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	for routed: bool in [false, true]:
		f = _fixture()
		_empty_att(f)
		if routed: f.state.battles[0].routed_side = "att"
		BodyBattle._seal_private(f.repo, f.state)
		var result := _run(f, _request("end"))
		assert_eq(result.status, "complete", result.reason)
		if result.candidate == null: continue
		var event: Dictionary = result.candidate.day_resolution.journal.battles.back()
		assert_eq(event.why, "rout_attacker" if routed else "emptied")
		assert_eq(event.winner, "def")
		assert_eq(event.att, [])
		assert_eq(event.def, [f.enemy, f.other])
		assert_eq(result.candidate.battles, [])
		for code: String in [f.enemy, f.other]:
			assert_eq(UnitBodies._entry(result.candidate, code).body_groups, f.rows[code])

func test_pending_round_wrong_stage_no_repo_and_malformed_requests_publish_nothing() -> void:
	var f := _fixture()
	var boundary := BodyBattleMotion._boundary(f.state)
	var before := BodyMotion._hash(f.state.to_dict())
	var no_repo := BodyBattle.plan_candidate(null, f.state, _request(), boundary)
	assert_eq(no_repo.status, "error")
	assert_eq(f.state.battles.size(), 1, "a no-repo call deletes no field")
	for request: Dictionary in [{"kind": "cancel", "battle_id": "8", "reason": " "},
		{"kind": "end", "battle_id": "i8", "reason": "R"}, {"kind": "end", "battle_id": 8, "reason": "R"},
		{"kind": "cancel", "battle_id": "8", "reason": "R", "extra": true}, {"kind": "cancel", "battle_id": "12", "reason": "R"}]:
		assert_eq(BodyBattle.plan_candidate(f.repo, f.state, request, boundary).status, "error", str(request))
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	# Contact stage: a terminal release waits for advance.
	var contact := _fixture()
	var tx: Dictionary = contact.state.day_resolution
	tx.body_battle.stage = "contact"
	tx.battle_step = ""
	tx.battle_ids = []
	tx.battle_index = 0
	tx.body_battle.battle_ids = []
	tx.body_battle.battle_index = "0"
	BodyBattle._seal_private(contact.repo, contact.state)
	var waited := _run(contact, _request())
	assert_eq(waited.status, "deferred", waited.reason)
	# A frozen round defers the release unchanged.
	f = _fixture()
	var b: Dictionary = f.state.battles[0]
	var ready := {"version": "1", "token": "bodyround:8:%d:1" % f.state.absolute_day(),
		"abs_day": str(f.state.absolute_day()), "round": "1", "motion_receipt": "a".repeat(64),
		"contact_digest": BodyMotion._hash([]), "basis": "b".repeat(64), "contacts": [], "unit_actions": {}}
	b.body_round = ready
	b.pending_round = {"day": f.state.absolute_day(), "round": 1, "att": b.att.duplicate(), "def": b.def.duplicate(),
		"tier": BattleSystem.tier_of(f.repo, 500).duplicate(true), "att_power": 1, "def_power": 1,
		"odds": 500, "roll": 500, "eff": 500, "contexts": {
			"att": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"},
			"def": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"}},
		"reason": "Frozen round", "costs": [], "unit_actions": {}, "body_round_receipt": BodyMotion._hash(ready)}
	before = BodyMotion._hash(f.state.to_dict())
	var frozen := _run(f, _request())
	assert_eq(frozen.status, "deferred", frozen.reason)
	assert_null(frozen.candidate)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	assert_eq(f.state.battles.size(), 1)

func test_production_call_off_is_unchanged() -> void:
	var f := _fixture()
	var event: Dictionary = BattleSystem.call_off(f.state, 8, f.repo)
	assert_eq(event.why, "called_off")
	assert_eq(event.att, [f.unit])
	assert_eq(event.def, [f.enemy, f.other])
	assert_eq(f.state.battles, [])
