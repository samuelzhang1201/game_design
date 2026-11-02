extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code: String = codes[0]
	assert_false(Personnel.replace(repo, state, code, 901).has("error"))
	state.regiments = {code: state.regiments[code]}
	state.army_roster = {code: state.army_roster[code]}
	state.foes = {}
	state.battles = []
	state.military_rosters = {code: state.military_rosters[code]}
	var cohorts := {}
	for id: String in state.military_rosters[code].cohort_ids:
		cohorts[id] = state.military_cohorts[id]
	state.military_cohorts = cohorts
	state.military_migration.body_version = 1
	state.regiments[code].group_next_slot = 20
	var rows: Array = []
	for i: int in 10:
		rows.append({"slot": i, "home_slot": i, "count": 100 if i < 9 else 1,
			"x_m": i * 10000, "y_m": 0, "facing_deg": 90, "role": "front",
			"path_m": [[i * 10000, 0], [i * 10000 + 2, 3]]})
	state.regiments[code].body_groups = rows
	return {"repo": repo, "state": state, "code": code}

func _day(state: GameState, stage: String = "contact") -> Dictionary:
	var tx := DayResolution.begin(state.day, false, state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(state.absolute_day()),
		"sequence": "0", "next_substep": "0", "substep_count": "10",
		"stage": stage, "battle_ids": [], "battle_index": "0", "processed_units": []}
	return tx

func _safe(state: GameState) -> Dictionary:
	return {"version": 1, "kind": "safe", "abs_day": str(state.absolute_day()), "sequence": "0"}

func test_ordinary_day_rejects_battle_marker() -> void:
	var f := _fixture()
	var tx := _day(f.state)
	assert_false(DayResolution.incompatibility_reason(tx).is_empty(), "candidate must never resume through production day")

func test_raw_round_envelope_survives_both_json_imports() -> void:
	var f := _fixture()
	for imported: bool in [false, true]:
		for bad: Variant in [true, 1.25, "i42", "f3ff0000000000000"]:
			var state := UnitBodies._copy(f.state)
			if imported: state.military_migration.import_main_v7 = {}
			else: state.military_migration.erase("import_main_v7")
			state.day_resolution = _day(state)
			state.day_resolution.body_battle.sequence = bad
			state.military_migration.body_battle = {"version": bad}
			state.battles = [{"body_round": {"version": bad, "contacts": [bad]}}]
			var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
			assert_eq(back.day_resolution.body_battle.sequence, bad)
			assert_eq(back.military_migration.body_battle.version, bad)
			assert_eq(back.battles[0].body_round, state.battles[0].body_round)

func test_raw_roundtrip_and_transfer() -> void:
	var api: GDScript = load("res://scripts/engine/unit_bodies.gd")
	assert_true(api.has_method("validate_battle_candidate"))
	assert_true(api.has_method("transfer_battle_candidate"))
	if not api.has_method("transfer_battle_candidate"): return
	var f := _fixture()
	var state: GameState = f.state
	var original: Array = state.regiments[f.code].body_groups.duplicate(true)
	_battles(f)
	state.day_resolution = _day(state)
	for imported: bool in [false, true]:
		if imported: state.military_migration.import_main_v7 = {}
		else: state.military_migration.erase("import_main_v7")
		for json_copy: bool in [false, true]:
			var source := _json(state) if json_copy else state
			var before := source.to_dict()
			var result := UnitBodies.transfer_battle_candidate(f.repo, source, f.code, 8, 3, "def", _boundary(source))
			assert_eq(result.status, "complete", result.reason)
			assert_true(source.to_dict() == before, "entire source, RNG, costs and personnel unchanged")
			if result.candidate == null: continue
			var candidate: GameState = result.candidate
			assert_eq(UnitBodies.rows(f.repo, candidate, f.code), original, "all ten exact identities/poses/paths/counts survive")
			assert_eq(candidate.regiments[f.code].group_next_slot, 20)
			assert_eq(UnitBodies._owners(candidate).owners[f.code].id, 3)
			assert_eq(candidate.battles[1].def, [f.code])
			assert_false(candidate.battles[0].groups.has(f.code))
			assert_false(candidate.regiments[f.code].has("body_groups"))
			assert_eq(candidate.battles[1].group_anchor_m[f.code], [17, 23])
			assert_eq(candidate.battles[1].group_facing[f.code], 90)
			assert_eq(candidate.military_cohorts, source.military_cohorts)
			assert_eq(candidate.military_events, source.military_events)
			assert_eq(candidate.metrics, source.metrics)
			assert_eq(candidate.rng.to_dict(), source.rng.to_dict())
			var restored := _json(candidate).to_dict()
			for key: String in restored:
				assert_eq(BodyMotion._hash(restored[key]), BodyMotion._hash(candidate.to_dict()[key]), "exact JSON values: " + key)
			candidate.battles[1].groups[f.code][0].path_m[0][0] = -44
			assert_true(source.to_dict() == before, "result is detached")

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _empty_battle(id: int) -> Dictionary:
	return {"id": id, "att": [], "def": [], "groups": {}, "body_version": 1,
		"group_size_version": 2, "group_size_men": 100}

func _battles(f: Dictionary) -> void:
	var state: GameState = f.state
	var source := _empty_battle(8)
	source.att = [f.code]
	source.groups[f.code] = state.regiments[f.code].body_groups
	source.group_facing = {f.code: 90}
	source.group_anchor_m = {f.code: [17, 23]}
	state.regiments[f.code].erase("body_groups")
	var enemy := "boundary:foe"
	state.foes[enemy] = {"x_m": 0, "y_m": 100000, "group_next_slot": 0}
	state.army_roster[enemy] = state.army_roster[f.code].duplicate(true)
	state.army_roster[enemy].kingdom_code = f.repo.resolve_realm("raider_realm")
	state.military_rosters[enemy] = {"cohort_ids": []}
	var destination := _empty_battle(3)
	destination.att = [enemy]
	destination.groups[enemy] = []
	state.battles = [source, destination]

func _check(f: Dictionary, boundary: Dictionary, expected: String = "error") -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var result := UnitBodies.validate_battle_candidate(f.repo, f.state, boundary)
	assert_eq(result.status, expected, result.reason)
	assert_eq(result.size(), 5)
	assert_true(f.state.to_dict() == before, "validation never repairs or mutates input")
	if expected != "complete":
		assert_null(result.candidate)
		assert_eq(result.placement_requests, [])
	if expected == "error": assert_false(result.error.is_empty())
	return result

func _boundary(state: GameState) -> Dictionary:
	var control: Dictionary = state.day_resolution.body_battle
	return {"version": 1, "kind": "battle", "abs_day": control.abs_day,
		"sequence": control.sequence, "substep": control.next_substep, "stage": control.stage}

func test_malformed_raw_boundary_controls_and_owners_reject_without_mutation() -> void:
	var base := _fixture()
	_battles(base)
	var cases := ["duplicate", "missing", "reconciliation", "overlap", "counter", "fit", "battle_id", "day_unknown", "day_future", "day_bool", "outer_unknown", "outer_future", "round_future", "header_fraction", "mixed"]
	for change: String in cases:
		var f := {"repo": base.repo, "state": UnitBodies._copy(base.state), "code": base.code}
		var state: GameState = f.state
		state.day_resolution = _day(state)
		var boundary := _boundary(state)
		match change:
			"duplicate": state.regiments[f.code].body_groups = []
			"missing": state.battles[0].groups.erase(f.code)
			"reconciliation": state.regiments[f.code].body_reconciliation = {"version": 1, "basis_fit": 900, "target_fit": 901}
			"overlap": state.battles[0].groups[f.code][1].x_m = 1
			"counter": state.regiments[f.code].group_next_slot = true
			"fit": state.military_cohorts[state.military_rosters[f.code].cohort_ids[-1]].fit = 901.25
			"battle_id": state.battles[0].id = 9007199254740992
			"day_unknown": state.day_resolution.body_battle.extra = 0
			"day_future": state.day_resolution.body_battle.version = "2"
			"day_bool": state.day_resolution.body_battle.battle_index = true
			"outer_unknown": state.military_migration.body_battle = {"version": "1", "extra": 0}
			"outer_future": state.military_migration.body_battle = {"version": "2"}
			"round_future": state.battles[0].body_round = {"version": "2"}
			"header_fraction": state.day_resolution.substep_index = 0.5
			"mixed": state.day_resolution.body_march = {}
		_check(f, boundary)
		for imported: bool in [false, true]:
			if imported: state.military_migration.import_main_v7 = {}
			else: state.military_migration.erase("import_main_v7")
			_check({"repo": f.repo, "state": _json(state)}, boundary)
	for raw: Variant in [true, 1.25, "i42", "f3ff0000000000000", 9007199254740992]:
		var boundary := _safe(base.state)
		boundary.version = raw
		_check(base, boundary)
		boundary = _safe(base.state)
		boundary.sequence = raw
		_check(base, boundary)

func test_stage_and_side_are_validated_before_transfer() -> void:
	var f := _fixture()
	_battles(f)
	var state: GameState = f.state
	for side: String in ["att", "", "other"]:
		var before := state.to_dict()
		var result := UnitBodies.transfer_battle_candidate(f.repo, state, f.code, 8, 3, side, _safe(state))
		assert_eq(result.status, "error", side)
		assert_null(result.candidate)
		assert_true(state.to_dict() == before)
	state.day_resolution = _day(state, "move")
	assert_eq(UnitBodies.transfer_battle_candidate(f.repo, state, f.code, 8, 3, "def", _boundary(state)).status, "deferred")
	state.day_resolution.body_battle.stage = "contact"
	assert_eq(UnitBodies.transfer_battle_candidate(f.repo, state, f.code, 8, 3, "def", _boundary(state)).status, "complete")
	assert_eq(UnitBodies.transfer_candidate(state, f.code, 8, 3).status, "deferred", "old transfer stays frozen")
	state.day_resolution = {}
	assert_eq(UnitBodies.transfer_battle_candidate(f.repo, state, f.code, 8, 3, "def", _safe(state)).status, "deferred", "safe boundary admits terminal operations, not enrollment")

func test_empty_destination_is_complete_and_final_validation_stays_strict() -> void:
	var f := _fixture()
	f.state.battles = [_empty_battle(3)]
	f.state.day_resolution = _day(f.state)
	var result := UnitBodies.transfer_battle_candidate(f.repo, f.state, f.code, 0, 3, "att", _boundary(f.state))
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, result.candidate, _boundary(result.candidate)).status, "complete")
	assert_eq(UnitBodies._owners(result.candidate).owners[f.code].id, 3)
	result.candidate.day_resolution.body_battle.stage = "advance"
	result.candidate.day_resolution.battle_step = "fighting"
	var back := UnitBodies.transfer_battle_candidate(f.repo, result.candidate, f.code, 3, 0, "", _boundary(result.candidate))
	assert_eq(back.status, "complete", back.reason)
	f.state.day_resolution = result.candidate.day_resolution.duplicate(true)
	if back.candidate != null: assert_true(back.candidate.to_dict() == f.state.to_dict())
	if back.candidate != null:
		var terminal: GameState = UnitBodies._copy(result.candidate)
		terminal.day_resolution = {}
		assert_eq(UnitBodies.transfer_battle_candidate(f.repo, terminal, f.code, 3, 0, "", _safe(terminal)).status, "complete")
	f.state.battles[0].erase("groups")
	assert_eq(UnitBodies.transfer_battle_candidate(f.repo, f.state, f.code, 0, 3, "att", _boundary(f.state)).status, "error")

func test_v6_v7_and_frozen_v1_march_are_unchanged() -> void:
	var f := _fixture()
	for version: int in [6, 7]:
		var saved: Dictionary = f.state.to_dict()
		saved.version = version
		var back := GameState.from_dict(JSON.parse_string(JSON.stringify(saved)), false)
		assert_eq(back.loaded_save_version, version)
		assert_true(back.to_dict() == f.state.to_dict())
		_check({"repo": f.repo, "state": back}, _safe(back), "complete")
	var tx := _day(f.state)
	tx.erase("body_battle")
	tx.body_march = {"version": "1", "abs_day": str(f.state.absolute_day()), "next_substep": "0", "substep_count": "10", "last": {}}
	f.state.day_resolution = tx
	assert_eq(DayResolution.body_march_incompatibility_reason(tx), "")
	_check(f, _safe(f.state), "deferred")
	assert_true(_json(f.state).to_dict() == f.state.to_dict())

func test_day_queue_mirrors_processed_prefix_and_never_requeues_a_processed_unit() -> void:
	var f := _fixture()
	_battles(f)
	f.state.day_resolution = _day(f.state, "round")
	var tx: Dictionary = f.state.day_resolution
	tx.battle_step = "fighting"
	tx.battle_ids = [3, 8]
	tx.body_battle.battle_ids = ["3", "8"]
	_check(f, _boundary(f.state), "complete")
	for change: String in ["mirror", "prefix", "processed_unit", "unknown_unit", "alias", "resolved", "fraction", "zero", "new_encounter"]:
		var state := UnitBodies._copy(f.state)
		match change:
			"mirror": state.day_resolution.body_battle.battle_index = "1"
			"prefix": state.day_resolution.processed_battle_ids = [3]
			"processed_unit": state.day_resolution.body_battle.processed_units = [f.code]
			"unknown_unit": state.day_resolution.body_battle.processed_units = ["missing"]
			"alias": state.battle_aliases = {"3": 8}
			"resolved": state.battles[1].last_resolved_day = state.absolute_day()
			"fraction": state.day_resolution.body_battle.battle_index = "0.5"
			"zero": state.day_resolution.body_battle.battle_ids = ["0", "8"]
			"new_encounter": state.day_resolution.substep_battle_ids = [9]
		_check({"repo": f.repo, "state": state}, _boundary(state))
	tx.processed_battle_ids = [3]
	tx.battle_index = 1
	tx.body_battle.battle_index = "1"
	_check(f, _boundary(f.state), "complete")
	tx.processed_battle_ids = [3, 8]
	tx.battle_index = 2
	tx.body_battle.battle_index = "2"
	tx.body_battle.stage = "advance"
	_check(f, _boundary(f.state), "complete")
	tx.battle_ids = []
	tx.body_battle.battle_ids = []
	tx.battle_index = 0
	tx.body_battle.battle_index = "0"
	tx.battle_step = ""
	tx.substep_index = 10
	tx.body_battle.next_substep = "10"
	tx.body_battle.stage = "complete"
	_check(f, _boundary(f.state), "complete")
	tx.body_battle.stage = "move"
	_check(f, _boundary(f.state))

func _seal(f: Dictionary) -> void:
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
		"turn_q": 400000, "contact_um": 100, "radius_m": f.repo.unit_footprints[piece].radius_m,
		"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
	f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
	f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	var grid := MarchPath.new()
	grid.cols = 2
	grid.rows = 2
	grid.cell_m = 100000
	grid.closed = PackedByteArray([0, 0, 0, 0])
	grid.water = PackedByteArray([0, 0, 0, 0])
	MarchPath.use(f.repo, grid)
	f.state.military_migration.body_battle = {"version": "1", "sequence": "0",
		"receipt": "b".repeat(64), "result": "", "closed_motion": {}}
	f.state.military_migration.body_battle.result = UnitBodies._battle_result_hash(f.repo, f.state)

func test_outer_endpoint_binds_source_and_context_in_both_imports() -> void:
	for imported: bool in [false, true]:
		var f := _fixture()
		if imported: f.state.military_migration.import_main_v7 = {}
		else: f.state.military_migration.erase("import_main_v7")
		_seal(f)
		var boundary := _safe(f.state)
		boundary.sequence = "1"
		_check(f, boundary, "complete")
		_check({"repo": f.repo, "state": _json(f.state)}, boundary, "complete")
		for change: String in ["receipt", "result", "cost", "rng", "row", "counter", "unknown", "future", "closed", "sequence", "raw"]:
			var state := UnitBodies._copy(f.state)
			match change:
				"receipt": state.military_migration.body_battle.receipt = "c".repeat(64)
				"result": state.military_migration.body_battle.result = "c".repeat(64)
				"cost": state.metrics.treasury += 1
				"rng": state.rng.randi_range(0, 100)
				"row": state.regiments[f.code].body_groups[0].x_m += 1
				"counter": state.regiments[f.code].group_next_slot += 1
				"unknown": state.military_migration.body_battle.extra = ""
				"future": state.military_migration.body_battle.version = "2"
				"closed": state.military_migration.body_battle.closed_motion = {"version": "3"}
				"sequence": state.military_migration.body_battle.sequence = "00"
				"raw": state.military_migration.body_battle.sequence = "i0"
			_check({"repo": f.repo, "state": state}, boundary)
			_check({"repo": f.repo, "state": _json(state)}, boundary)
		f.repo.balance.battle_group_contact_m += 1
		_check(f, boundary)

func test_malformed_ready_envelopes_error_before_frozen_deferral() -> void:
	var f := _fixture()
	_battles(f)
	var ready := {"version": "1", "token": "bodyround:8:%d:1" % f.state.absolute_day(),
		"abs_day": str(f.state.absolute_day()), "round": "1", "motion_receipt": "a".repeat(64),
		"contact_digest": BodyMotion._hash([]), "basis": "b".repeat(64), "contacts": [], "unit_actions": {}}
	f.state.battles[0].body_round = ready
	_check(f, _safe(f.state), "deferred")
	for field: String in ["version", "token", "abs_day", "round", "motion_receipt", "contact_digest", "basis", "contacts", "unit_actions"]:
		for raw: Variant in [null, true, 1.5, "i42", "f3ff0000000000000"]:
			for imported: bool in [false, true]:
				var state := UnitBodies._copy(f.state)
				if imported: state.military_migration.import_main_v7 = {}
				else: state.military_migration.erase("import_main_v7")
				state.battles[0].body_round[field] = raw
				_check({"repo": f.repo, "state": state}, _safe(state))
				_check({"repo": f.repo, "state": _json(state)}, _safe(state))
	var state := UnitBodies._copy(f.state)
	state.battles[0].body_round.future = ""
	_check({"repo": f.repo, "state": state}, _safe(state))
	state = UnitBodies._copy(f.state)
	state.battles[0].pending_round = {"body_round_receipt": "c".repeat(64)}
	_check({"repo": f.repo, "state": state}, _safe(state))
	assert_eq(UnitBodies.transfer_battle_candidate(f.repo, f.state, f.code, 8, 3, "other", _safe(f.state)).status, "error")
	assert_eq(UnitBodies.transfer_battle_candidate(f.repo, f.state, f.code, 8, 3, "att", _safe(f.state)).status, "error")

func test_every_raw_day_field_rejects_malformed_types_after_json() -> void:
	var f := _fixture()
	f.state.day_resolution = _day(f.state)
	var boundary := _boundary(f.state)
	for field: String in f.state.day_resolution.body_battle:
		for raw: Variant in [null, true, 0.25, "i0", "f3ff0000000000000"]:
			var state := UnitBodies._copy(f.state)
			state.day_resolution.body_battle[field] = raw
			_check({"repo": f.repo, "state": state}, boundary)
			_check({"repo": f.repo, "state": _json(state)}, boundary)
	for field: String in boundary:
		for raw: Variant in [null, true, 0.25, "i0", "f3ff0000000000000"]:
			var bad := boundary.duplicate(true)
			bad[field] = raw
			_check(f, bad)

func test_accepted_v2_placement_proof_is_validated_before_safe_deferral() -> void:
	# Reuse the accepted real completed-march fixture, not a synthetic proof.
	var fixture: GutTest = load("res://tests/engine/test_body_placement.gd").new()
	for imported: bool in [false, true]:
		var f: Dictionary = fixture.call("_completion_fixture", imported)
		assert_false(f.is_empty())
		if f.is_empty(): continue
		var applied: Dictionary = fixture.call("_completion_operation", f)
		assert_eq(applied.status, "complete", applied.reason)
		if applied.candidate == null: continue
		for state: GameState in [applied.candidate, _json(applied.candidate)]:
			_check({"repo": f.repo, "state": state}, _safe(state), "deferred")
			var corrupt := UnitBodies._copy(state)
			corrupt.military_migration.body_placement.completion_json += " "
			_check({"repo": f.repo, "state": corrupt}, _safe(corrupt))
	assert_eq(fixture.get_fail_count(), 0, "accepted fixture setup succeeded")
	fixture.free()
