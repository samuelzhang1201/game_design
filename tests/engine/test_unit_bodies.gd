extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _api() -> GDScript:
	var path := "res://scripts/engine/unit_bodies.gd"
	assert_true(FileAccess.file_exists(path), "passive foundation API exists")
	return load(path) if FileAccess.file_exists(path) else null

func _fixture(n: int = 901) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	_replace(repo, state, code, n)
	var entry: Dictionary = state.regiments[code]
	var definition: Dictionary = state.army_roster[code]
	state.regiments = {code: entry}
	state.army_roster = {code: definition}
	state.foes = {}
	state.battles = []
	state.military_rosters = {code: state.military_rosters[code]}
	var cohorts := {}
	for id: String in state.military_rosters[code].cohort_ids:
		cohorts[id] = state.military_cohorts[id]
	state.military_cohorts = cohorts
	state.military_events["fixture:retained"] = {"costs": [18], "receipt": {"paid": 1}}
	state.military_migration.body_version = 1
	entry.group_next_slot = 20
	entry.body_groups = _rows(n)
	return {"repo": repo, "state": state, "code": code}

func _rows(n: int, size: int = 100, current: bool = true) -> Array:
	var out: Array = []
	for i: int in BattleGroups.counts(n, size).size():
		var row := {"slot": i, "count": mini(size, n - i * size), "x_m": i * 10000,
			"y_m": 0, "role": "front", "path_m": [[i * 10000, 0], [i * 10000 + 2, 3]],
			"extension": {"receipt": [7, "paid"]}}
		if current:
			row.home_slot = i
			row.facing_deg = 90
		out.append(row)
	return out

func _battle(f: Dictionary, id: int = 1, legacy: bool = false) -> Dictionary:
	var entry: Dictionary = f.state.regiments[f.code]
	var rows: Array = entry.get("body_groups", [])
	entry.erase("body_groups")
	var battle := {"id": id, "att": [f.code], "def": [], "groups": {f.code: rows},
		"group_facing": {f.code: 90}, "group_anchor_m": {f.code: [17, 23]},
		"group_size_version": 2, "group_size_men": 100, "unrelated": {"terms": ["paid"]}}
	if not legacy: battle.body_version = 1
	f.state.battles.append(battle)
	return battle

func _migrate(api: GDScript, f: Dictionary, expected: String) -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var rng: Dictionary = f.state.rng.to_dict()
	var result: Dictionary = api.migrate_candidate(f.repo, f.state)
	assert_eq(result.keys().size(), 5)
	assert_eq(result.status, expected, result.get("error", "") + result.get("reason", ""))
	assert_eq(f.state.to_dict(), before, "source state stays exact")
	assert_eq(f.state.rng.to_dict(), rng)
	if expected == "error":
		assert_null(result.candidate)
		assert_false(result.error.is_empty())
		assert_false(result.reason.is_empty())
		assert_eq(result.placement_requests, [])
	return result

func _reconcile(api: GDScript, f: Dictionary, previous: Variant, expected: String) -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = api.reconcile_candidate(f.repo, f.state, f.code, previous)
	assert_eq(result.status, expected, result.reason)
	assert_eq(f.state.to_dict(), before)
	assert_eq(f.state.rng.to_dict(), before.rng)
	assert_eq(result.keys().size(), 5)
	if expected in ["error", "deferred"]:
		assert_null(result.candidate)
		assert_eq(result.placement_requests, [])
	return result

func test_queries_are_detached_and_never_materialize() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var before: Dictionary = f.state.to_dict()
	var rows: Array = api.rows(null, f.state, f.code)
	rows[0].path_m[0][0] = -99
	rows[0].extension.receipt.append("changed")
	assert_eq(f.state.to_dict(), before)
	assert_eq(api.rows(null, f.state, "unknown"), [])
	var extent: Vector2i = api.footprint(f.repo, f.code, f.state)
	assert_true(extent.x > 0 and extent.y > 0)
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	var config: Dictionary = f.repo.unit_footprints[piece]
	assert_eq(extent, Vector2i(config.width_m, config.depth_m))
	var homes: Array = api.home_slots(f.repo, f.state, f.code)
	assert_eq(homes[4].x - homes[0].x + 2 * int(config.radius_m), extent.x)
	assert_eq(homes[5].y - homes[0].y + 2 * int(config.radius_m), extent.y)
	for fit: int in [1000, 901, 900, 1, 0]:
		_replace(f.repo, f.state, f.code, fit)
		assert_eq(api.footprint(f.repo, f.code, f.state), extent)
		assert_eq(api.home_slots(f.repo, f.state, f.code).size(), 10)
	assert_eq(api.footprint(null, f.code, f.state), Vector2i.ZERO)
	assert_eq(api.home_slots(null, f.state, f.code), [])
	var battle := _battle(f)
	assert_eq(api.rows(null, f.state, f.code), battle.groups[f.code])
	f.state.regiments[f.code].body_groups = []
	assert_eq(api.rows(null, f.state, f.code), [], "two stores are ambiguous, even if empty")
	f.state.regiments[f.code].erase("body_groups")
	battle.erase("groups")
	assert_eq(api.rows(null, f.state, f.code), [])
	f.state.army_roster[f.code].is_naval = "1"
	assert_eq(api.home_slots(f.repo, f.state, f.code), [])
	assert_eq(api.rows(null, f.state, f.code), [])

func test_counts_survivors_and_retired_slots() -> void:
	_reconciliation_boundaries()
	var api := _api()
	if api == null: return
	for n: int in [1000, 901, 900, 1, 0]:
		var f := _fixture(n)
		var result := _migrate(api, f, "complete")
		assert_eq(api.rows(null, result.candidate, f.code).size(), {1000: 10, 901: 10, 900: 9, 1: 1, 0: 0}[n])
	var f := _fixture()
	var original: Array = f.state.regiments[f.code].body_groups.duplicate(true)
	_replace(f.repo, f.state, f.code, 900)
	var reduced := _reconcile(api, f, 901, "complete")
	assert_eq(reduced.candidate.regiments[f.code].body_groups, original.slice(0, 9))
	assert_eq(reduced.candidate.regiments[f.code].group_next_slot, 20)
	_replace(f.repo, reduced.candidate, f.code, 901)
	f.state = reduced.candidate
	var growth := _reconcile(api, f, 900, "needs_placement")
	assert_eq(growth.candidate.regiments[f.code].body_groups, original.slice(0, 9))
	assert_eq(growth.placement_requests[0].missing_home_slots, [9])
	assert_eq(growth.candidate.regiments[f.code].group_next_slot, 20)
	var retry: Dictionary = api.migrate_candidate(f.repo, growth.candidate)
	assert_eq(retry.status, "needs_placement", "partial-candidate retry is idempotent: " + retry.error)
	var partial_saved: Dictionary = growth.candidate.to_dict()
	var partial_back := GameState.from_dict(JSON.parse_string(JSON.stringify(partial_saved)), false)
	assert_eq(partial_back.to_dict(), partial_saved, "JSON preserves the partial candidate exactly")
	var json_retry: Dictionary = api.migrate_candidate(f.repo, partial_back)
	assert_eq(json_retry.status, "needs_placement", "JSON partial retry is idempotent: " + json_retry.error)
	if retry.candidate != null:
		assert_eq(retry.candidate.to_dict(), growth.candidate.to_dict())
		assert_eq(retry.placement_requests, growth.placement_requests)

	var small := _fixture(1)
	_replace(small.repo, small.state, small.code, 100)
	var grown := _reconcile(api, small, 1, "complete")
	assert_eq(grown.candidate.regiments[small.code].body_groups[0].slot, 0)
	assert_eq(grown.candidate.regiments[small.code].body_groups[0].count, 100)

func test_candidate_migration_isolated_and_idempotent() -> void:
	_legacy_slot_allocation()
	_pending_isolation()
	var api := _api()
	if api == null: return
	for legacy: bool in [false, true]:
		var f := _fixture(100)
		if legacy:
			f.state.military_migration.erase("body_version")
			var b := _battle(f, 1, true)
			b.groups[f.code][0].erase("home_slot")
			b.groups[f.code][0].erase("facing_deg")
		else:
			var b := _battle(f)
			b.group_size_regroup_pending = true
		var result := _migrate(api, f, "complete")
		var candidate: GameState = result.candidate
		if not legacy: assert_eq(candidate.battles, f.state.battles, "Current metadata is not a legacy regroup request")
		assert_eq(api.rows(null, candidate, f.code)[0].path_m, [[0, 0], [2, 3]])
		var saved := candidate.to_dict()
		var back := GameState.from_dict(JSON.parse_string(JSON.stringify(saved)), false)
		var again: Dictionary = api.migrate_candidate(f.repo, back)
		assert_eq(again.status, "complete")
		assert_eq(again.candidate.to_dict(), saved)
		candidate.world["detachment"] = {"nested": [1]}
		assert_false(f.state.world.has("detachment"))
		var detached: Array = api.rows(null, candidate, f.code)
		detached[0].extension.receipt[0] = -1
		assert_eq(api.rows(null, candidate, f.code)[0].extension.receipt[0], 7)
		f.state.regiments[f.code].new_extension = [123]
		assert_false(candidate.regiments[f.code].has("new_extension"))
	var f := _fixture(100)
	for key: String in ["slot", "count", "x_m", "y_m", "home_slot", "facing_deg"]:
		f.state.regiments[f.code].body_groups[0][key] = float(f.state.regiments[f.code].body_groups[0][key])
	var result := _migrate(api, f, "complete")
	assert_typeof(result.candidate.regiments[f.code].body_groups[0].x_m, TYPE_INT)

func _legacy_slot_allocation() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture(100)
	f.state.military_migration.erase("body_version")
	var b := _battle(f, 1, true)
	for row: Dictionary in b.groups[f.code]:
		row.erase("slot")
		row.erase("home_slot")
		row.erase("facing_deg")
	f.state.regiments[f.code].group_next_slot = 0
	var result := _migrate(api, f, "complete")
	if result.candidate != null:
		assert_eq(result.candidate.battles[0].groups[f.code][0].slot, 0)
		assert_eq(result.candidate.regiments[f.code].group_next_slot, 1)

func test_legacy_missing_pose_requests() -> void:
	var api := _api()
	if api == null: return
	var repo := SuiteData.repo()
	var fresh := SuiteData.campaign(repo, 319)
	var before := fresh.to_dict()
	var result: Dictionary = api.migrate_candidate(repo, fresh)
	assert_eq(result.status, "needs_placement")
	assert_eq(fresh.to_dict(), before)
	assert_eq(fresh.rng.to_dict(), result.candidate.rng.to_dict())
	assert_false(result.candidate.military_migration.has("body_version"))
	var previous := ""
	for request: Dictionary in result.placement_requests:
		assert_true(request.unit >= previous)
		previous = request.unit
		assert_eq(request.keys().size(), 6)
		assert_eq(request.reason, "legacy_missing_pose")
	for version: int in [6, 7]:
		var f := _fixture(100)
		f.state.military_migration.erase("body_version")
		f.state.regiments[f.code].erase("body_groups")
		f.state.regiments[f.code].x_m = 17
		f.state.regiments[f.code].y_m = 23
		var saved: Dictionary = f.state.to_dict()
		saved.version = version
		f.state = GameState.from_dict(saved, false)
		result = _migrate(api, f, "needs_placement")
		assert_eq(result.placement_requests, [{"unit": f.code, "battle_id": 0, "reason": "legacy_missing_pose",
			"anchor_m": [17, 23], "facing_deg": 0, "missing_home_slots": [0]}])
		var b := _battle(f, 1, true)
		b.erase("groups")
		result = _migrate(api, f, "needs_placement")
		assert_eq(result.placement_requests[0].battle_id, 1)
		assert_eq(result.placement_requests[0].anchor_m, [17, 23])

func test_malformed_is_not_legacy() -> void:
	_reconciliation_rejections()
	var api := _api()
	if api == null: return
	for field: String in ["slot", "count", "x_m", "y_m", "home_slot", "facing_deg", "role"]:
		var f := _fixture(100)
		f.state.regiments[f.code].body_groups[0].erase(field)
		_migrate(api, f, "error")
	for bad: Variant in [0.5, INF, NAN, true, "1", null]:
		for field: String in ["slot", "count", "x_m", "home_slot", "facing_deg"]:
			var f := _fixture(100)
			f.state.regiments[f.code].body_groups[0][field] = bad
			_migrate(api, f, "error")
	for change: Dictionary in [{"path_m": "bad"}, {"path_m": [[1, 2.5]]}, {"path_m": [[true, 2]]},
		{"path_m": [[1]]}, {"facing_deg": 360}, {"home_slot": 10}, {"role": "bad"}, {"count": 101}, {"slot": -1}]:
		var f := _fixture(100)
		f.state.regiments[f.code].body_groups[0].merge(change, true)
		_migrate(api, f, "error")
	for field: String in ["count", "x_m", "y_m", "role"]:
		var legacy := _fixture(100)
		legacy.state.military_migration.erase("body_version")
		var b := _battle(legacy, 1, true)
		b.groups[legacy.code][0].erase(field)
		_migrate(api, legacy, "error")
	for issue: String in ["missing", "empty", "counter", "slot", "home", "overlap", "future", "marker", "duplicate", "overflow", "legacy_empty", "legacy_total", "legacy_size"]:
		var f := _fixture(1000)
		var entry: Dictionary = f.state.regiments[f.code]
		match issue:
			"missing": entry.erase("body_groups")
			"empty": entry.body_groups = []
			"counter": entry.group_next_slot = 9
			"slot": entry.body_groups[1].slot = 0
			"home": entry.body_groups[1].home_slot = 0
			"overlap": entry.body_groups[1].x_m = 1
			"future": f.state.military_migration.body_version = 2
			"marker": f.state.military_migration.body_version = true
			"duplicate":
				var b := _battle(f)
				entry.body_groups = b.groups[f.code].duplicate(true)
			"overflow": entry.body_groups.append(entry.body_groups[0].duplicate(true))
			_:
				f.state.military_migration.erase("body_version")
				var b := _battle(f, 1, true)
				b.group_size_version = 1
				b.group_size_men = 50
				b.groups[f.code] = _rows(1000, 50, false)
				if issue == "legacy_empty": b.groups[f.code] = []
				if issue == "legacy_total": b.groups[f.code][0].count = 49
				if issue == "legacy_size": b.group_size_men = 51
		_migrate(api, f, "error")

func _transfer(api: GDScript, state: GameState, code: String, from_id: int, to_id: int, expected: String) -> Dictionary:
	var before := state.to_dict()
	var result: Dictionary = api.transfer_candidate(state, code, from_id, to_id)
	assert_eq(result.status, expected, result.reason)
	assert_eq(state.to_dict(), before)
	assert_eq(state.rng.to_dict(), before.rng)
	return result

func test_candidate_transfer_lifecycle() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture(100)
	var other: String = f.code + "-other"
	f.state.army_roster[other] = f.state.army_roster[f.code].duplicate(true)
	f.state.regiments[other] = {"group_next_slot": 0, "body_groups": []}
	var b := {"id": 1, "att": [other], "def": [], "groups": {other: []}, "body_version": 1,
		"group_size_version": 2, "group_size_men": 100, "terms": {"receipt": [12]}}
	var other2 := other + "2"
	f.state.army_roster[other2] = f.state.army_roster[f.code].duplicate(true)
	f.state.regiments[other2] = {"group_next_slot": 0, "body_groups": []}
	f.state.battles = [b, {"id": 2, "att": [other2], "def": [], "groups": {other2: []},
		"body_version": 1, "group_size_version": 2, "group_size_men": 100}]
	f.state.regiments[other].erase("body_groups")
	f.state.regiments[other2].erase("body_groups")
	var valid := _migrate(api, f, "complete")
	var original: Array = api.rows(null, valid.candidate, f.code)
	var entered := _transfer(api, valid.candidate, f.code, 0, 1, "complete")
	assert_eq(entered.candidate.battles[0].terms, b.terms)
	var replay := _transfer(api, entered.candidate, f.code, 0, 1, "complete")
	assert_eq(replay.candidate.to_dict(), entered.candidate.to_dict())
	entered.candidate.battles[0].group_anchor_m = {f.code: [17, 23]}
	entered.candidate.battles[0].group_facing = {f.code: 90}
	var merged := _transfer(api, entered.candidate, f.code, 1, 2, "complete")
	assert_eq(merged.candidate.battles.size(), 2)
	assert_eq(merged.candidate.battles[0].att, [other])
	for from_state: GameState in [entered.candidate, merged.candidate]:
		var id: int = 1 if from_state == entered.candidate else 2
		var exited := _transfer(api, from_state, f.code, id, 0, "complete")
		assert_eq(exited.candidate.regiments[f.code].body_groups, original)
		assert_eq(exited.candidate.regiments[f.code].group_next_slot, 20)
		assert_eq(exited.candidate.regiments[f.code].group_anchor_m, [17, 23])
		assert_eq(exited.candidate.regiments[f.code].group_facing, 90)
		assert_eq(exited.candidate.military_cohorts, valid.candidate.military_cohorts)
		assert_eq(api.rows(null, exited.candidate, f.code), original)
		assert_eq(api.migrate_candidate(f.repo, exited.candidate).status, "complete")
	for endpoints: Vector2i in [Vector2i(-1, 1), Vector2i(0, 99), Vector2i(0, 0), Vector2i(2, 1)]:
		_transfer(api, valid.candidate, f.code, endpoints.x, endpoints.y, "error")
	var bad := _fixture(100)
	bad.state.battles = [{"id": 1, "att": [], "def": [], "body_version": 1, "groups": {}}]
	_transfer(api, bad.state, bad.code, 0, 1, "error")
	for issue: String in ["duplicate", "schema", "size", "save", "counter", "occupied", "side", "missing"]:
		var broken: GameState = GameState.from_dict(valid.candidate.to_dict(), false)
		match issue:
			"duplicate": broken.battles[0].att.append(f.code)
			"schema": broken.battles[0].body_version = 9
			"size": broken.battles[0].group_size_men = 200
			"save": broken.loaded_save_version = 8
			"counter": broken.regiments[f.code].group_next_slot = 0
			"occupied": broken.battles[0].groups[f.code] = original.duplicate(true)
			"side": broken.battles[0].def.append(other2)
			"missing": broken.regiments[f.code].erase("body_groups")
		_transfer(api, broken, f.code, 0, 1, "error")
	for field: String in ["body_version", "group_size_version", "groups"]:
		var broken := _json(entered.candidate)
		broken.battles[1].att.clear()
		broken.battles[1].groups.clear()
		broken.regiments[other2].body_groups = []
		broken.battles[1].erase(field)
		_transfer(api, broken, f.code, 1, 2, "error")
	var single := _fixture(100)
	_battle(single)
	var single_valid := _migrate(api, single, "complete")
	var single_exit := _transfer(api, single_valid.candidate, single.code, 1, 0, "complete")
	assert_eq(single_exit.candidate.battles.size(), 1)
	assert_eq(single_exit.candidate.battles[0].att, [])
	assert_eq(single_exit.candidate.battles[0].groups, {})
	assert_eq(single_exit.candidate.regiments[single.code].body_groups, _rows(100))
	var frozen_state := GameState.from_dict(entered.candidate.to_dict(), false)
	frozen_state.day_resolution = {"phase": "battles", "costs": [18]}
	_transfer(api, frozen_state, f.code, 1, 0, "deferred")
	var wider := SuiteData.repo()
	for arm: String in wider.unit_footprints:
		for key: String in ["radius_m", "pitch_m", "width_m", "depth_m"]:
			wider.unit_footprints[arm][key] *= 100
	var spaced := _fixture(200)
	var narrow_valid := _migrate(api, spaced, "complete")
	var wider_result: Dictionary = api.migrate_candidate(wider, narrow_valid.candidate)
	assert_eq(wider_result.status, "error")
	assert_true(wider_result.error.contains("overlap"), wider_result.error)
	var peer: String = spaced.code + "-peer"
	spaced.state.army_roster[peer] = spaced.state.army_roster[spaced.code].duplicate(true)
	spaced.state.regiments[peer] = {"group_next_slot": 0, "body_groups": []}
	spaced.state.battles = [{"id": 1, "att": [peer], "def": [], "groups": {peer: []},
		"body_version": 1, "group_size_version": 2, "group_size_men": 100}]
	spaced.state.regiments[peer].erase("body_groups")
	var physical := _migrate(api, spaced, "complete")
	var moved := _transfer(api, physical.candidate, spaced.code, 0, 1, "complete")
	assert_eq(api.rows(null, moved.candidate, spaced.code), api.rows(null, physical.candidate, spaced.code))
	assert_eq(api.migrate_candidate(wider, moved.candidate).status, "error")
	assert_eq(api.migrate_candidate(spaced.repo, moved.candidate).status, "complete")
	# Transfer is structurally identical with either caller repo: it accepts none.
	assert_eq(api.transfer_candidate(narrow_valid.candidate, spaced.code, 0, 99).status, "error")

func test_frozen_candidate_defers_without_replay() -> void:
	var api := _api()
	if api == null: return
	for day: bool in [true, false]:
		var f := _fixture(1000)
		f.state.military_migration.erase("body_version")
		var b := _battle(f, 1, true)
		b.group_size_version = 1
		b.group_size_men = 50
		b.groups[f.code] = _rows(1000, 50, false)
		f.state.regiments[f.code].group_next_slot = 27
		var frozen := {"cursor": [2, 9], "costs": {f.code: 18}, "frozen": [50, 50]}
		if day: f.state.day_resolution = frozen
		else: b.pending_round = frozen
		var deferred := _migrate(api, f, "deferred")
		assert_null(deferred.candidate)
		assert_eq(b.groups[f.code].size(), 20)
		assert_false(b.groups[f.code][0].has("home_slot"))
		var saved_rows: Array = b.groups[f.code].duplicate(true)
		b.groups[f.code][0].x_m = 0.5
		_migrate(api, f, "error")
		b.groups[f.code] = saved_rows.duplicate(true)
		b.groups[f.code][0].count = 49
		_migrate(api, f, "error")
		b.groups[f.code] = saved_rows
		f.state.military_migration.body_version = 3
		_migrate(api, f, "error")
		f.state.military_migration.erase("body_version")
		f.state.day_resolution.clear()
		b.erase("pending_round")
		var converted := _migrate(api, f, "complete")
		var rows: Array = converted.candidate.battles[0].groups[f.code]
		assert_eq(rows.size(), 10)
		for i: int in 10:
			assert_eq(rows[i].slot, i * 2)
			assert_eq(rows[i].home_slot, i)
			assert_eq(rows[i].count, 100)
			assert_eq(rows[i].x_m, saved_rows[i * 2].x_m)
			assert_eq(rows[i].path_m, saved_rows[i * 2].path_m)
		assert_eq(converted.candidate.regiments[f.code].group_next_slot, 27)
		var back := GameState.from_dict(JSON.parse_string(JSON.stringify(converted.candidate.to_dict())), false)
		assert_eq(api.migrate_candidate(f.repo, back).candidate.to_dict(), converted.candidate.to_dict())

	var partial := _fixture(999)
	partial.state.military_migration.erase("body_version")
	var b := _battle(partial, 1, true)
	b.group_size_version = 1
	b.group_size_men = 50
	b.groups[partial.code] = _rows(999, 50, false)
	b.pending_round = {"round": 3, "cursor": [2, 9], "costs": [18]}
	_migrate(api, partial, "deferred")
	partial.state = _json(partial.state)
	_migrate(api, partial, "deferred")
	partial.state.battles[0].erase("pending_round")
	var converted := _migrate(api, partial, "complete")
	assert_eq(converted.candidate.battles[0].groups[partial.code][-1].count, 99)

func test_passive_serialization_and_production_route_unchanged() -> void:
	_passive_pending()
	var api := _api()
	if api == null: return
	assert_eq(GameState.SAVE_VERSION, 7)
	assert_eq(GameState.MIN_SAVE_VERSION, 6)
	var repo := SuiteData.repo()
	var fresh := SuiteData.campaign(repo, 319)
	var saved := fresh.to_dict()
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(saved)), false)
	assert_eq(back.to_dict(), saved)
	for entry: Dictionary in back.regiments.values():
		assert_false(entry.has("body_groups"))
	assert_false(back.military_migration.has("body_version"))
	var f := _fixture(100)
	back = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
	assert_eq(back.to_dict(), f.state.to_dict())
	f.state.military_migration.body_version = 1.5
	back = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
	assert_eq(back.military_migration.body_version, 1.5)
	assert_eq(api.migrate_candidate(f.repo, back).status, "error")
	for path: String in ["game_state", "army_system", "battle_system", "battle_groups", "military_reorganization"]:
		assert_false(FileAccess.get_file_as_string("res://scripts/engine/" + path + ".gd").contains("UnitBodies."), path)
	assert_false(FileAccess.get_file_as_string("res://scripts/ui/game.gd").contains("UnitBodies."))

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _pending(api: GDScript, n: int = 900, target: int = 901, battle: bool = false) -> Dictionary:
	var f := _fixture(n)
	if battle: _battle(f)
	_replace(f.repo, f.state, f.code, target)
	var result := _reconcile(api, f, n, "needs_placement")
	f.state = result.candidate
	return f

func _reconciliation_boundaries() -> void:
	var api := _api()
	if api == null: return
	for pair: Vector2i in [Vector2i(901, 900), Vector2i(900, 901), Vector2i(1, 1000),
		Vector2i(0, 1), Vector2i(901, 1), Vector2i(1, 0), Vector2i(1000, 1000)]:
		for battle: bool in [false, true]:
			var f := _fixture(pair.x)
			if battle: _battle(f)
			var original: Array = api.rows(null, f.state, f.code)
			_replace(f.repo, f.state, f.code, pair.y)
			var target_count: int = {1000: 10, 901: 10, 900: 9, 1: 1, 0: 0}[pair.y]
			var expected := "needs_placement" if target_count > original.size() else "complete"
			var result := _reconcile(api, f, pair.x, expected)
			var replay := _reconcile(api, f, float(pair.x), expected)
			if result.candidate == null: continue
			assert_eq(replay.candidate.to_dict(), result.candidate.to_dict())
			var saved_rows: Array = api.rows(null, result.candidate, f.code)
			assert_eq(saved_rows.size(), mini(original.size(), target_count))
			for i: int in saved_rows.size():
				var row: Dictionary = original[i].duplicate(true)
				row.count = mini(100, pair.y - i * 100)
				assert_eq(saved_rows[i], row)
			assert_eq(result.candidate.regiments[f.code].group_next_slot, 20)
			if expected == "needs_placement":
				assert_eq(result.candidate.regiments[f.code].body_reconciliation,
					{"version": 1, "basis_fit": pair.x, "target_fit": pair.y})
				assert_false(result.candidate.military_migration.has("body_version"))
				assert_eq(result.placement_requests[0].reason, "reconciliation_requires_pose")
				if battle: assert_eq(result.candidate.battles[0].body_version, 1)
			var saved: Dictionary = result.candidate.to_dict()
			for retry: int in 3:
				f.state = result.candidate if retry == 0 else _json(result.candidate)
				result = _migrate(api, f, expected)
				assert_eq(result.candidate.to_dict(), saved)
			if expected == "needs_placement": _reconcile(api, f, pair.x, "error")
	var f := _fixture(100)
	f.state.regiments[f.code].body_groups[0].home_slot = 9
	_replace(f.repo, f.state, f.code, 901)
	var result := _reconcile(api, f, 100, "needs_placement")
	assert_eq(result.placement_requests[0].missing_home_slots, [0, 1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq(api.rows(null, result.candidate, f.code)[0].home_slot, 9)

func _reconciliation_rejections() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture(900)
	_replace(f.repo, f.state, f.code, 901)
	for bad: Variant in [900.5, true, null, "900", NAN, INF, -INF, -1, 1001]:
		_reconcile(api, f, bad, "error")
	var one := _fixture(1)
	_replace(one.repo, one.state, one.code, 2)
	_reconcile(api, one, true, "error")
	for battle: bool in [false, true]:
		var pending := _pending(api, 900, 901, battle)
		if pending.state == null: continue
		for key: String in ["version", "basis_fit", "target_fit"]:
			for bad: Variant in [null, true, "1", 0.5, NAN, INF, -1]:
				var broken := {"repo": pending.repo, "code": pending.code, "state": _json(pending.state)}
				broken.state.regiments[broken.code].body_reconciliation[key] = bad
				_migrate(api, broken, "error")
				broken.state = _json(broken.state)
				_migrate(api, broken, "error")
		for issue: String in ["basisnegative", "targetnegative", "zerobasis", "unnecessary", "ledgerraw", "rows", "size", "descriptor", "global", "extra", "missingkey", "version0", "version2", "basis", "target", "counter", "point", "home", "slot", "count", "path", "store", "marker", "future", "personnel"]:
			var broken := {"repo": pending.repo, "code": pending.code, "state": _json(pending.state)}
			var e: Dictionary = broken.state.regiments[broken.code]
			var rows: Array = broken.state.battles[0].groups[broken.code] if battle else e.body_groups
			match issue:
				"basisnegative": e.body_reconciliation.basis_fit = -1
				"targetnegative": e.body_reconciliation.target_fit = -1
				"zerobasis": e.body_reconciliation.basis_fit = 0
				"unnecessary": e.body_reconciliation.target_fit = 900
				"ledgerraw":
					for id: String in broken.state.military_rosters[broken.code].cohort_ids:
						if broken.state.military_cohorts[id].stage == "active":
							broken.state.military_cohorts[id].fit = true
				"rows": rows.pop_back()
				"size":
					if battle: broken.state.battles[0].group_size_version = 1
					else: e.body_reconciliation.basis_fit = 1001
				"descriptor": e.erase("body_reconciliation")
				"global": broken.state.military_migration.body_version = 1
				"extra": e.body_reconciliation.extra = 1
				"missingkey": e.body_reconciliation.erase("basis_fit")
				"version0": e.body_reconciliation.version = 0
				"version2": e.body_reconciliation.version = 2
				"basis": e.body_reconciliation.basis_fit = 901
				"target": e.body_reconciliation.target_fit = 1001
				"counter": e.group_next_slot = 1
				"point": rows[1].x_m = rows[0].x_m
				"home": rows[1].home_slot = rows[0].home_slot
				"slot": rows[1].slot = rows[0].slot
				"count": rows[0].count = 99
				"path": rows[0].path_m = [[1, true]]
				"store":
					if battle: broken.state.battles[0].groups.erase(broken.code)
					else: e.erase("body_groups")
				"marker":
					if battle: broken.state.battles[0].erase("body_version")
					else: broken.state.military_migration.body_version = 2
				"future": broken.state.loaded_save_version = 8
				"personnel": _replace(broken.repo, broken.state, broken.code, 902)
			_migrate(api, broken, "error")
			if issue != "future":
				broken.state = _json(broken.state)
				_migrate(api, broken, "error")
		_transfer(api, pending.state, pending.code, 0, 1, "error")
	for day: bool in [false, true]:
		var frozen := _fixture(900)
		var b := _battle(frozen)
		_replace(frozen.repo, frozen.state, frozen.code, 901)
		if day: frozen.state.day_resolution = {"phase": "battles"}
		else: b.pending_round = {"round": 1}
		_reconcile(api, frozen, 900, "deferred")
		frozen.state = _json(frozen.state)
		_reconcile(api, frozen, 900, "deferred")
		frozen.state.day_resolution.clear()
		frozen.state.battles[0].erase("pending_round")
		_reconcile(api, frozen, 900, "needs_placement")

func _pending_isolation() -> void:
	var api := _api()
	if api == null: return
	for basis: int in [0, 900]:
		for battle: bool in [false, true]:
			var f := _pending(api, basis, basis + 1, battle)
			if f.state == null: continue
			var other: String = f.code + "-isolation"
			f.state.regiments[other] = {"group_next_slot": 30, "body_groups": _rows(100), "orders": {"paid": [3]}}
			f.state.regiments[other].body_groups[0].x_m = -10000
			f.state.army_roster[other] = f.state.army_roster[f.code].duplicate(true)
			f.state.military_rosters[other] = {"cohort_ids": [other]}
			f.state.military_cohorts[other] = {"unit_code": other, "stage": "active", "fit": 100, "wounded": 0}
			var unchanged: Dictionary = f.state.regiments[other].duplicate(true)
			var result := _migrate(api, f, "needs_placement")
			if result.candidate == null: continue
			assert_eq(result.candidate.regiments[other], unchanged)
			assert_eq(result.candidate.military_cohorts, f.state.military_cohorts)
			var again: Dictionary = api.migrate_candidate(f.repo, _json(result.candidate))
			assert_eq(again.candidate.to_dict(), result.candidate.to_dict())
			result.candidate.regiments[other].orders.paid.append(4)
			result.candidate.regiments[f.code].body_reconciliation.target_fit = 2
			assert_eq(f.state.regiments[other], unchanged)
			assert_eq(f.state.regiments[f.code].body_reconciliation.target_fit, basis + 1)
			f.state.regiments[other].body_groups[0].path_m[0][0] = 99
			assert_eq(result.candidate.regiments[other].body_groups[0].path_m[0][0], 0)
	var stale := _fixture(900)
	_reconcile(api, stale, 901, "error")

func _passive_pending() -> void:
	var api := _api()
	if api == null: return
	for battle: bool in [false, true]:
		var f := _pending(api, 0, 1, battle)
		if f.state == null: continue
		assert_eq(_json(f.state).to_dict(), f.state.to_dict())
		assert_eq(_json(f.state).regiments[f.code].body_reconciliation, {"version": 1, "basis_fit": 0, "target_fit": 1})
	var fresh := SuiteData.campaign(SuiteData.repo(), 319)
	for entry: Dictionary in _json(fresh).regiments.values():
		assert_false(entry.has("body_reconciliation"))
	for path: String in ["scripts/engine/march_path.gd", "scripts/engine/battle_ranged.gd", "scripts/map3d/map3d_units.gd"]:
		assert_false(FileAccess.get_file_as_string("res://" + path).contains("UnitBodies."), path)

func _replace(repo: DataRepository, state: GameState, code: String, amount: int) -> void:
	var result := Personnel.replace(repo, state, code, amount)
	assert_false(result.has("error"), str(result.get("error", "")))

func test_legacy_slot_counter_overflow_errors_atomically() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture(100)
	f.state.military_migration.erase("body_version")
	var b := _battle(f, 1, true)
	f.state.regiments[f.code].erase("group_next_slot")
	b.groups[f.code][0].slot = 0x7fffffffffffffff
	_migrate(api, f, "error")

func test_pending_descriptor_has_one_eligible_unit_store() -> void:
	var api := _api()
	if api == null: return
	for location: String in ["global", "battle", "row"]:
		var f := _fixture(100)
		if location == "battle":
			var b := _battle(f)
			b.body_reconciliation = {"version": 1, "basis_fit": 0, "target_fit": 100}
		elif location == "row":
			f.state.regiments[f.code].body_groups[0].body_reconciliation = {"version": 1, "basis_fit": 0, "target_fit": 100}
		else:
			f.state.military_migration.body_reconciliation = {"version": 1, "basis_fit": 0, "target_fit": 100}
		_migrate(api, f, "error")
		f.state = _json(f.state)
		_migrate(api, f, "error")
	var f := _fixture(100)
	_battle(f)
	var fleet: String = f.code + "-fleet"
	f.state.regiments[fleet] = {}
	f.state.army_roster[fleet] = f.state.army_roster[f.code].duplicate(true)
	f.state.army_roster[fleet].is_naval = "1"
	var valid := _migrate(api, f, "complete")
	valid.candidate.regiments[fleet].body_reconciliation = {"version": 1, "basis_fit": 0, "target_fit": 1}
	_transfer(api, valid.candidate, f.code, 1, 0, "error")

func test_legacy_schema_closure_and_metadata_roundtrips() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture(100)
	f.state.military_migration.erase("body_version")
	var b := _battle(f, 1, true)
	b.erase("group_size_men")
	var migrated := _migrate(api, f, "complete")
	_transfer(api, migrated.candidate, f.code, 1, 0, "complete")

	f = _fixture(101)
	f.state.military_migration.erase("body_version")
	b = _battle(f, 1, true)
	b.groups[f.code][0].count = 1
	b.groups[f.code][1].count = 100
	migrated = _migrate(api, f, "complete")
	assert_eq(migrated.candidate.battles[0].groups[f.code][0].count, 100)
	assert_eq(migrated.candidate.battles[0].groups[f.code][1].count, 1)
	f.state = _json(migrated.candidate)
	_migrate(api, f, "complete")

	f = _fixture(100)
	f.state.military_migration.erase("body_version")
	b = _battle(f, 1, true)
	var other: String = f.code + "-missing-member"
	f.state.regiments[other] = {"x_m": 200000, "y_m": 0}
	f.state.army_roster[other] = f.state.army_roster[f.code].duplicate(true)
	b.att.append(other)
	_migrate(api, f, "error")

	for field: String in ["slot", "home_slot", "facing_deg", "group_next_slot"]:
		f = _fixture(100)
		f.state.military_migration.erase("body_version")
		if field == "group_next_slot": f.state.regiments[f.code].erase(field)
		else: f.state.regiments[f.code].body_groups[0].erase(field)
		_migrate(api, f, "error")
	for metadata: Dictionary in [{"group_facing": true}, {"group_facing": "90"}, {"group_anchor_m": [1, 2.5]}]:
		f = _fixture(100)
		f.state.regiments[f.code].merge(metadata, true)
		_migrate(api, f, "error")
	f = _fixture(100)
	_battle(f)
	f.state.regiments[f.code].group_facing = 90
	_migrate(api, f, "error")

	f = _fixture(100)
	_battle(f, 2)
	f.state.battles.append({"id": 1, "att": [], "def": []})
	migrated = _migrate(api, f, "complete")
	assert_eq(migrated.candidate.battles[1].get("body_version"), 1)
	assert_eq(migrated.candidate.battles[1].get("group_size_version"), 2)
	assert_eq(migrated.candidate.battles[1].get("group_size_men"), 100)
	assert_eq(migrated.candidate.battles[1].get("groups"), {})
	_transfer(api, migrated.candidate, f.code, 2, 1, "complete")

	for change: Dictionary in [{"body_version": 2}, {"group_size_version": 3},
		{"body_reconciliation": {"version": 1, "basis_fit": 0, "target_fit": 100}}]:
		f = _fixture(100)
		b = {"id": 9, "att": [], "def": [], "groups": {}, "ended": true,
			"body_version": 1, "group_size_version": 2, "group_size_men": 100}
		b.merge(change, true)
		f.state.battles.append(b)
		_migrate(api, f, "error")
		f.state = _json(f.state)
		_migrate(api, f, "error")

	f = _fixture(100)
	f.state.military_migration.erase("body_version")
	f.state.regiments[f.code].erase("body_groups")
	f.state.regiments[f.code].group_facing = 90
	_migrate(api, f, "error")
