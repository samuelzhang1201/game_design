extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const QUERY_PATH: String = "res://scripts/engine/body_battle_contact.gd"

func after_each() -> void:
	MarchPath.forget()

func _fixture(own_fit: int = 100, enemy_fit: int = 100) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var mine: Array = state.regiments.keys()
	mine.sort()
	var foes: Array = state.foes.keys()
	foes.sort()
	var codes: Array = [mine[0], foes[0], foes[1]]
	var cohorts := {}
	var rosters := {}
	var army := {}
	var enemies := {}
	var groups := {}
	for i: int in codes.size():
		var code: String = codes[i]
		var fit := own_fit if i == 0 else enemy_fit
		assert_false(Personnel.replace(repo, state, code, fit).has("error"))
		army[code] = state.army_roster[code]
		for arm: String in repo.world_table("military", "unit_types"):
			army[code][arm] = "0"
		army[code]["infantry" if i == 0 else "cavalry"] = "100"
		rosters[code] = state.military_rosters[code]
		for id: String in rosters[code].cohort_ids:
			cohorts[id] = state.military_cohorts[id]
		var entry: Dictionary = state.regiments[code] if i == 0 else state.foes[code]
		entry.erase("body_groups")
		entry.erase("body_reconciliation")
		entry.group_next_slot = 20
		var rows: Array = []
		for slot: int in BattleGroups.counts(fit, 100).size():
			rows.append({"slot": slot, "home_slot": slot, "count": mini(100, fit - slot * 100),
				"x_m": 10000 + slot * 10000 + (1731 if i == 1 else 0),
				"y_m": 10000 if i < 2 else 50000, "facing_deg": 0, "role": "reserve"})
		groups[code] = rows
		if i > 0: enemies[code] = entry
	state.regiments = {codes[0]: state.regiments[codes[0]]}
	state.foes = enemies
	state.army_roster = army
	state.military_rosters = rosters
	state.military_cohorts = cohorts
	state.military_migration.body_version = 1
	state.day_resolution = {}
	state.tick = 1
	state.day = 7
	state.battles = [{"id": 8, "att": [codes[0]], "def": [codes[1], codes[2]],
		"groups": groups, "body_version": 1, "group_size_version": 2, "group_size_men": 100}]
	var grid := MarchPath.new()
	grid.cols = 20
	grid.rows = 20
	grid.cell_m = 10000
	grid.closed.resize(400)
	grid.water.resize(400)
	MarchPath.use(repo, grid)
	return {"repo": repo, "state": state, "unit": codes[0], "enemy": codes[1], "other": codes[2], "grid": grid}

func _boundary(state: GameState) -> Dictionary:
	return {"version": 1, "kind": "safe", "abs_day": str(state.absolute_day()), "sequence": "0"}

func _query(f: Dictionary, enemies: Array = [], battle_id: int = 8) -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var context := BodyMotion._hash([f.repo.balance, f.repo.unit_footprints])
	var result: Dictionary = load(QUERY_PATH).query_candidate(f.repo, f.state, battle_id, f.unit,
		[f.enemy] if enemies.is_empty() else enemies, _boundary(f.state))
	assert_eq(result.size(), 8)
	assert_true(f.state.to_dict() == before, "query preserves all source state and RNG")
	assert_eq(context, BodyMotion._hash([f.repo.balance, f.repo.unit_footprints]))
	assert_false(result.reason.is_empty())
	if result.status == "error":
		assert_false(result.error.is_empty())
		assert_eq(result.fit, 0)
		assert_eq(result.engaged, 0)
		assert_eq(result.pairs, [])
	else:
		assert_eq(result.status, "complete")
		assert_eq(result.error, "")
	return result

func test_real_radius_surface_edge() -> void:
	assert_true(ResourceLoader.exists(QUERY_PATH), "physical lawful body query must exist")
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	assert_eq(BattleGroupGeometry.footprint(f.repo, f.state.army_roster[f.unit]).radius_m, 927)
	assert_eq(BattleGroupGeometry.footprint(f.repo, f.state.army_roster[f.enemy]).radius_m, 804)
	assert_eq(int(f.repo.bal("battle_group_contact_m")), 100)
	for separation: int in [1731, 1831, 1832, 1730]:
		f.state.battles[0].groups[f.enemy][0].x_m = 10000 + separation
		var result := _query(f)
		assert_eq(result.status, "error" if separation == 1730 else "complete", result.reason)
		assert_eq(result.engaged, 100 if separation in [1731, 1831] else 0)
		assert_eq(result.pairs.size(), 1 if separation in [1731, 1831] else 0)

func test_partial_reserve_and_multiple_opponents_count_each_own_row_once() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture(101)
	var battle: Dictionary = f.state.battles[0]
	# Only the final one-person row touches. Its reserve label grants no range,
	# but does not suppress a real physical contact either.
	battle.groups[f.enemy][0].x_m = 21731
	var result := _query(f)
	assert_eq(result.fit, 101)
	assert_eq(result.engaged, 1)
	assert_eq(result.pairs[0].slot, 1)
	assert_eq(result.pairs[0].count, 1)
	battle.groups[f.other][0].x_m = 18269
	battle.groups[f.other][0].y_m = 10000
	var enemies: Array = [f.enemy, f.other]
	enemies.sort()
	result = _query(f, enemies)
	assert_eq(result.engaged, 1, "two touching targets never turn one person into two")
	assert_eq(result.pairs.size(), 2)
	assert_true(result.pairs[0].target_unit < result.pairs[1].target_unit)
	for pair: Dictionary in result.pairs:
		assert_eq(pair.size(), 8)
		assert_eq(pair.kind, "melee")
		assert_eq(pair.unit, f.unit)
		assert_eq(pair.count, 1)
		assert_eq(pair.target_count, 100)
		assert_false(pair.reason.is_empty())
	battle.groups[f.enemy][0].y_m = 30000
	battle.groups[f.other][0].y_m = 50000
	assert_eq(_query(f, enemies).engaged, 0, "distant reserves never inflict outgoing damage")

func test_closed_or_water_contact_segment_is_zero() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	# A 100-metre strip lies only in the physical gap: both occupied discs
	# remain on open ground (infantry ends10927, cavalry starts11027).
	f.grid.cols = 2000
	f.grid.rows = 1000
	f.grid.cell_m = 100
	f.grid.closed.resize(2000000)
	f.grid.water.resize(2000000)
	f.state.battles[0].groups[f.enemy][0].x_m = 11831
	f.grid.closed[100 * 2000 + 110] = 1
	assert_eq(_query(f).engaged, 0)
	f.grid.closed.fill(0)
	f.grid.water[100 * 2000 + 110] = 1
	assert_eq(_query(f).engaged, 0)
	f.grid.water.fill(0)
	assert_eq(_query(f).engaged, 100)

func _protect(f: Dictionary, clause: String, on_other_field: bool = false) -> void:
	var battle: Dictionary = f.state.battles[1 if on_other_field else 0]
	battle.parley = {"agreed": {clause: {"policy": "protect", "until_day": 0}},
		"parties": {"att": [f.unit], "def": [f.enemy]}}

func test_bilateral_protection_filters_only_its_actual_parties_without_mutation() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	var battle: Dictionary = f.state.battles[0]
	_protect(f, "ceasefire")
	assert_eq(_query(f).engaged, 0)
	battle.groups[f.other][0].x_m = 8269
	battle.groups[f.other][0].y_m = 10000
	var enemies: Array = [f.enemy, f.other]
	enemies.sort()
	var result := _query(f, enemies)
	assert_eq(result.engaged, 100)
	assert_eq(result.pairs.size(), 1)
	assert_eq(result.pairs[0].target_unit, f.other, "nonparty C never inherits A-B protection")
	battle.parley.erase("parties")
	assert_eq(_query(f, enemies).engaged, 0, "legacy parties inferred on detached clone only")
	assert_false(battle.parley.has("parties"), "query must not mutate even old parley")
	_protect(f, "safe_withdrawal")
	f.state.foes[f.enemy].battle_retreat = true
	assert_eq(_query(f).engaged, 0)
	battle.parley.agreed.safe_withdrawal.until_day = f.state.absolute_day() - 1
	assert_eq(_query(f).engaged, 100, "expired terms do not bar current contact")

func test_alias_and_both_source_fields_protect_cross_field_pairs() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	f.state.battle_aliases["12"] = 8
	assert_eq(_query(f, [f.enemy], 12).battle_id, 8)
	var battle: Dictionary = f.state.battles[0]
	var other := {"id": 9, "att": [f.enemy], "def": [],
		"body_version": 1, "group_size_version": 2, "group_size_men": 100,
		"groups": {f.enemy: battle.groups[f.enemy]}}
	battle.def.erase(f.enemy)
	battle.groups.erase(f.enemy)
	f.state.battles.append(other)
	assert_eq(_query(f).engaged, 100, "actual hostile rows on another field may be queried")
	var tactics := {"agreed": {"tactics": {"policy": "restrained", "until_day": 0}},
		"parties": {"att": [f.unit], "def": [f.enemy]}}
	other.parley = tactics.duplicate(true)
	f.state.foes[f.enemy].battle_retreat = true
	var result := _query(f)
	assert_eq(result.engaged, 0, "the target field's bilateral tactics bars pursuit")
	assert_eq(result.pairs, [])
	assert_true("restrained" in result.reason.to_lower())
	battle.groups[f.other][0].x_m = 8269
	battle.groups[f.other][0].y_m = 10000
	var enemies: Array = [f.enemy, f.other]
	enemies.sort()
	result = _query(f, enemies)
	assert_eq(result.engaged, 100, "an unrelated contacting opponent remains lawful")
	assert_eq(result.pairs.map(func(pair: Dictionary) -> String: return pair.target_unit), [f.other])
	other.parley.agreed.tactics.until_day = f.state.absolute_day() - 1
	assert_eq(_query(f).engaged, 100, "expired target-field tactics no longer bars pursuit")
	other.erase("parley")
	battle.parley = tactics.duplicate(true)
	assert_eq(_query(f).engaged, 0, "the source field's bilateral tactics also bars pursuit")
	battle.erase("parley")
	_protect(f, "ceasefire", true)
	assert_eq(_query(f).engaged, 0, "the target field's original bilateral parties also bind")
	other.erase("parley")
	_protect(f, "ceasefire")
	assert_eq(_query(f).engaged, 0, "source field terms remain binding across fields")

func test_invalid_request_or_owner_errors_instead_of_fabricating_zero() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	var enemies: Array = [f.enemy, f.other]
	enemies.sort()
	var reversed := enemies.duplicate()
	reversed.reverse()
	for bad: Array in [[f.enemy, f.enemy], [f.unit], ["not-a-member"], [true], reversed]:
		assert_eq(_query(f, bad).status, "error")
	assert_eq(_query(f, [f.enemy], 999).status, "error")
	assert_eq(_query(f, [f.enemy], 0).status, "error")
	for change: String in ["missing", "duplicate", "count", "fraction", "bool", "unknown", "counter", "boundary", "friend", "overflow"]:
		var copy: GameState = UnitBodies._copy(f.state)
		var local := f.duplicate()
		local.state = copy
		match change:
			"missing": copy.battles[0].groups.erase(f.enemy)
			"duplicate": copy.foes[f.enemy].body_groups = []
			"count": copy.battles[0].groups[f.enemy][0].count = 99
			"fraction": copy.battles[0].groups[f.enemy][0].x_m = 11731.5
			"bool": copy.battles[0].groups[f.enemy][0].x_m = true
			"unknown": copy.military_migration.body_battle = {"version": "1", "extra": 0}
			"counter": copy.foes[f.enemy].group_next_slot = 0
			"boundary": copy.day_resolution = {"body_battle": {"version": "2"}}
			"friend": copy.army_roster[f.enemy].kingdom_code = copy.army_roster[f.unit].kingdom_code
			"overflow": copy.battles[0].groups[f.enemy][0].x_m = 9007199254740991
		assert_eq(_query(local).status, "error", change)

func test_empty_roster_and_json_repeat_keep_state_file_and_rng_unchanged() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	var expected := _query(f)
	var path: String = "user://b_contact_query_source.json"
	var saved := JSON.stringify(f.state.to_dict())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(saved)
	file.close()
	for imported: bool in [false, true]:
		var state := UnitBodies._copy(f.state)
		if imported: state.military_migration.import_main_v7 = {}
		else: state.military_migration.erase("import_main_v7")
		var local := f.duplicate()
		local.state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
		assert_eq(_query(local), expected)
		assert_eq(_query(local), expected)
	assert_eq(FileAccess.get_file_as_string(path), saved)
	DirAccess.remove_absolute(path)
	f = _fixture(0)
	var result := _query(f)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.fit, 0)
	assert_eq(result.engaged, 0)
	assert_eq(result.pairs, [])

func test_received_pursuit_law_and_unadmitted_targets_fail_closed() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	f.state.foes[f.enemy].battle_retreat = true
	f.state.law_in_force["unit:" + f.unit] = {"battle_tactics": {"value": "restrained", "decree_id": 1}}
	assert_eq(_query(f).engaged, 0, "a general attack cannot override received pursuit law")
	f.state.law_in_force.clear()
	assert_eq(_query(f).engaged, 100)
	var battle: Dictionary = f.state.battles[0]
	f.state.foes[f.enemy].body_groups = battle.groups[f.enemy]
	battle.groups.erase(f.enemy)
	battle.def.erase(f.enemy)
	assert_eq(_query(f).status, "error", "an unadmitted hidden target is not a queried field member")
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = load(QUERY_PATH).query_candidate(f.repo, f.state, 8, f.unit, [], _boundary(f.state))
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.fit, 100)
	assert_eq(result.engaged, 0)
	assert_true(f.state.to_dict() == before)

func test_friendly_overlapping_frames_cannot_discover_or_merge_a_field() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	f.state.army_roster[f.enemy].kingdom_code = f.state.army_roster[f.unit].kingdom_code
	f.state.battles[0].groups[f.enemy][0].x_m = 10000
	var before: Dictionary = f.state.to_dict()
	assert_eq(_query(f).status, "error")
	assert_true(f.state.to_dict() == before, "friendly frame overlap never discovers, joins or merges")

func test_malformed_boundary_and_missing_dependencies_are_query_errors() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	for field: String in _boundary(f.state):
		var bad := _boundary(f.state)
		bad[field] = true
		var before: Dictionary = f.state.to_dict()
		var result: Dictionary = load(QUERY_PATH).query_candidate(f.repo, f.state, 8, f.unit, [f.enemy], bad)
		assert_eq(result.status, "error")
		assert_eq(result.fit, 0)
		assert_eq(result.engaged, 0)
		assert_eq(result.pairs, [])
		assert_true(f.state.to_dict() == before)
	for value: Variant in [null, true, -1, 0.5, "100"]:
		f.repo.balance.battle_group_contact_m = value
		assert_eq(_query(f).status, "error")
	f.repo.balance.battle_group_contact_m = 100
	f.grid.water_open = true
	assert_eq(_query(f).status, "error")

func test_saved_contact_boundary_is_validated_without_consuming_it() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	var tx := DayResolution.begin(f.state.day, false, f.state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(f.state.absolute_day()),
		"sequence": "0", "next_substep": "0", "substep_count": "10",
		"stage": "contact", "battle_ids": [], "battle_index": "0", "processed_units": []}
	f.state.day_resolution = tx
	var boundary := {"version": 1, "kind": "battle", "abs_day": tx.body_battle.abs_day,
		"sequence": "0", "substep": "0", "stage": "contact"}
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = load(QUERY_PATH).query_candidate(f.repo, f.state, 8, f.unit, [f.enemy], boundary)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.engaged, 100)
	assert_true(f.state.to_dict() == before)
	boundary.sequence = "1"
	result = load(QUERY_PATH).query_candidate(f.repo, f.state, 8, f.unit, [f.enemy], boundary)
	assert_eq(result.status, "error")
	assert_true(f.state.to_dict() == before)

func test_alias_resolution_never_launders_raw_ids_or_cycles() -> void:
	if not ResourceLoader.exists(QUERY_PATH): return
	var f := _fixture()
	for value: Variant in [8.25, "8", "i8", true, -8, 9007199254740992]:
		f.state.battle_aliases = {"12": value}
		assert_eq(_query(f, [f.enemy], 12).status, "error", str(value))
	f.state.battle_aliases = {"12": 8, "8": 12}
	assert_eq(_query(f, [f.enemy], 12).status, "error", "a cycle cannot resolve by a hop cutoff")
