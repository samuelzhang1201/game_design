extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.no_clearance(SuiteData.repo()) # explicit 10m/50m legacy geometry, not miniature calibration
	var state := SuiteData.campaign(repo, 319)
	var codes := state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	Personnel.replace(repo, state, code, 101)
	var battle := {"id": 319, "att": [code], "def": [], "groups": {code: [
		{"slot": 2, "count": 50, "role": "front", "x_m": 10, "y_m": 20, "path_m": [[11, 20]]},
		{"slot": 4, "count": 50, "role": "reserve", "x_m": 30, "y_m": 40},
		{"slot": 7, "count": 1, "role": "front", "x_m": 50, "y_m": 60}]},
		"group_facing": {code: 90}, "group_anchor_m": {code: [0, 0]}}
	state.battles = [battle]
	state.regiments[code].group_next_slot = 8
	state.military_migration.living_cap_version = 2
	state.military_migration.organization_pending = false
	return {"repo": repo, "state": state, "code": code}

func test_regroup_preserves_first_and_third_slots_points_and_paths() -> void:
	var f := _fixture()
	assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "complete")
	var battle: Dictionary = f.state.battles[0]
	assert_eq(int(battle.get("group_size_version", 0)), 2)
	var rows: Array = battle.groups[f.code]
	assert_eq(rows.size(), 2)
	if rows.size() != 2: return
	assert_eq(rows[0], {"slot": 2, "count": 100, "role": "front", "x_m": 10, "y_m": 20, "path_m": [[11, 20]]})
	assert_eq(rows[1], {"slot": 7, "count": 1, "role": "front", "x_m": 50, "y_m": 60})
	assert_eq(int(f.state.regiments[f.code].group_next_slot), 8)
	assert_eq(int(battle.group_facing[f.code]), 90)
	var before := SaveLoad.state_hash(f.state)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
	assert_eq(MilitaryReorganization.reconcile(f.repo, back).status, "complete")
	assert_eq(SaveLoad.state_hash(back), before)
	BattleGroups.refresh(f.repo, back, back.battles[0])
	assert_eq(back.battles[0].groups[f.code], rows)
	Personnel.replace(f.repo, back, f.code, 201)
	BattleGroups.refresh(f.repo, back, back.battles[0])
	assert_eq(int(back.battles[0].groups[f.code][-1].slot), 8, "retired slot four is never reused")

func test_pending_old_day_and_round_are_unchanged_until_boundary() -> void:
	for day: bool in [true, false]:
		var f := _fixture()
		if day: f.state.day_resolution = {"phase": "battles", "frozen": [50, 50, 1]}
		else: f.state.battles[0].pending_round = {"roll": 99, "frozen": [50, 50, 1]}
		var before := SaveLoad.state_hash(f.state)
		assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "deferred")
		assert_eq(SaveLoad.state_hash(f.state), before)
		BattleGroups.refresh(f.repo, f.state, f.state.battles[0])
		assert_eq(f.state.battles[0].groups[f.code].size(), 3)
		f.state.day_resolution.clear()
		f.state.battles[0].erase("pending_round")
		assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "complete")
		assert_eq(f.state.battles[0].groups[f.code].size(), 2)

func test_malformed_candidate_rolls_back_all_battles() -> void:
	for field: String in ["count", "x_m", "slot", "path_m"]:
		var f := _fixture()
		var bad: Dictionary = f.state.battles[0].duplicate(true)
		bad.id = 320
		bad.groups[f.code][1][field] = -1 if field in ["count", "slot"] else "bad"
		f.state.battles.append(bad)
		var before := SaveLoad.state_hash(f.state)
		assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "error", field)
		assert_eq(SaveLoad.state_hash(f.state), before, "candidate publication is atomic")

func test_load_and_resumed_day_boundary_regroup_even_after_living_v2() -> void:
	var f := _fixture()
	var tx := DayResolution.begin(f.state.day, false, f.state.absolute_day())
	# A saved last-phase retry has already consumed the day's tactical inputs.
	tx.phase_cursor = DayResolution.PHASES.size() - 1
	tx.phase = "COMPLETE"
	f.state.day_resolution = tx
	var path: String = preload("res://tests/run_dir.gd").dir("group_size_migration").path_join("boundary.json")
	assert_true(SaveLoad.save_game(f.state, path))
	var old_data: DataRepository = Game.data
	var old_state: GameState = Game.state
	Game.data = f.repo
	assert_true(Game.load_campaign(path), Game.load_error)
	assert_eq(Game.state.battles[0].groups[f.code].size(), 3, "load retains the old day inputs")
	assert_eq(Game.state.day_resolution, tx)
	var resumed := GameState.from_dict(Game.state.to_dict(), false)
	var uninterrupted := GameState.from_dict(f.state.to_dict(), false)
	assert_eq(TickEngine.new(f.repo).resolve_day(resumed).status, "complete")
	assert_eq(TickEngine.new(f.repo).resolve_day(uninterrupted).status, "complete")
	assert_eq(resumed.battles[0].groups[f.code].size(), 2, "first post-resume boundary migrates before another transaction")
	assert_eq(SaveLoad.state_hash(resumed), SaveLoad.state_hash(uninterrupted))
	var hash_after := SaveLoad.state_hash(resumed)
	assert_eq(MilitaryReorganization.reconcile(f.repo, resumed).status, "complete")
	assert_eq(SaveLoad.state_hash(resumed), hash_after)
	Game.data = old_data
	Game.state = old_state

func test_invalid_group_version_or_size_cannot_publish_a_candidate() -> void:
	for pair: Array in [["group_size_version", 3], ["group_size_version", 2.5], ["group_size_men", 0], ["group_size_men", 1000]]:
		var f := _fixture()
		assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "complete")
		f.state.battles[0][pair[0]] = pair[1]
		var before := SaveLoad.state_hash(f.state)
		assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "error", str(pair))
		assert_eq(SaveLoad.state_hash(f.state), before)

func test_living_partition_regroups_new_size_rows_created_during_a_legacy_day() -> void:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := SuiteData.campaign(repo, 319)
	var codes := state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var current := MilitaryRoster.fit(state, code)
	var id := String(state.military_rosters[code].cohort_ids[0])
	for candidate: String in state.military_rosters[code].cohort_ids:
		if not state.military_cohorts[candidate].has("person_id"):
			id = candidate
			break
	# Import a historical oversized living ledger, not an oversized paid entry.
	state.military_cohorts[id].fit += 1001 - current
	state.military_cohorts[id].initial += 1001 - current
	state.military_migration.living_cap_version = 1
	var battle := {"id": 319, "att": [code], "def": [], "groups": {}}
	battle.erase("groups")
	state.battles = [battle]
	BattleGroups.refresh(repo, state, battle)
	assert_eq(battle.group_size_version, 2, "a new encounter can seed current-size rows while an old day resumes")
	assert_eq(MilitaryReorganization.reconcile(repo, state).status, "complete")
	var children: Array = state.military_migration.living_unit_mapping[code]
	assert_eq(children.size(), 2)
	for child: String in children:
		var fit := MilitaryRoster.fit(state, child)
		var rows: Array = state.battles[0].groups[child]
		assert_eq(rows.size(), ceili(float(fit) / 100.0), "partial crossing rows regroup in the same private candidate")
		assert_false(state.battles[0].has("group_size_regroup_pending"))

func test_new_encounter_keeps_legacy_groups_during_a_frozen_day() -> void:
	var f := _fixture()
	f.state.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day())
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var other := String(codes[1])
	Personnel.replace(f.repo, f.state, other, 101)
	var battle := {"id": 320, "att": [other], "def": []}
	f.state.battles.append(battle)
	var frozen: Dictionary = f.state.battles[0].duplicate(true)
	BattleGroups.refresh(f.repo, f.state, battle)
	assert_eq(battle.group_size_version, 1, "a resumed old day cannot mix new-size rows into its old battles")
	assert_eq(battle.groups[other].size(), 3)
	assert_eq(f.state.battles[0], frozen)

func test_pending_round_defers_group_regrouping_in_other_battles_too() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var other := String(codes[1])
	Personnel.replace(f.repo, f.state, other, 101)
	var idle: Dictionary = f.state.battles[0].duplicate(true)
	idle.id = 320
	idle.att = [other]
	idle.groups = {other: idle.groups[f.code]}
	idle.group_facing = {other: 0}
	idle.group_anchor_m = {other: [0, 0]}
	f.state.battles.append(idle)
	f.state.battles[0].pending_round = {"roll": 99, "frozen": [50, 50, 1]}
	var before := SaveLoad.state_hash(f.state)
	assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "deferred")
	assert_eq(SaveLoad.state_hash(f.state), before, "no mixed-size battle can merge into the frozen version")
	f.state.battles[0].erase("pending_round")
	assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "complete")
	for battle: Dictionary in f.state.battles:
		assert_eq(battle.group_size_version, 2)
		assert_eq(battle.groups[battle.att[0]].size(), 2)

func test_legacy_deployment_frontage_keeps_the_saved_group_size() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var other := String(codes[1])
	Personnel.replace(f.repo, f.state, other, 101)
	var battle: Dictionary = f.state.battles[0]
	battle.att.append(other)
	battle.groups[other] = battle.groups[f.code].duplicate(true)
	battle.group_facing[other] = 0
	battle.place_x_m = 0
	battle.place_y_m = 0
	for code: String in battle.att:
		f.state.regiments[code].x_m = 1000
		f.state.regiments[code].y_m = 0
	var before := SaveLoad.state_hash(f.state)
	var targets := BattleGroups.deployment(f.repo, f.state, battle)
	var ys := [targets[f.code].y, targets[other].y]
	ys.sort()
	# Three legacy groups have two front groups: each unit is100m wide.
	assert_eq(ys, [-50, 50])
	assert_eq(SaveLoad.state_hash(f.state), before)

func test_monthly_battle_recovery_updates_physical_rows_on_the_same_day() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.code, 1000)
	Personnel.move(f.repo, f.state, f.code, "fit", "wounded", 100)
	var battle: Dictionary = f.state.battles[0]
	for key: String in ["groups", "group_facing", "group_anchor_m"]: battle.erase(key)
	BattleGroups.refresh(f.repo, f.state, battle)
	assert_eq(battle.groups[f.code].size(), 9)
	var survivors: Array = battle.groups[f.code].duplicate(true)
	var day: int = f.state.absolute_day()
	ArmySystem.settle_month(f.repo, f.state)
	assert_gt(MilitaryRoster.fit(f.state, f.code), 900)
	assert_eq(f.state.absolute_day(), day)
	assert_eq(battle.groups[f.code].size(), 10, "actual monthly recovery updates saved rows without a camera or next day")
	for i: int in survivors.size():
		for key: String in ["slot", "x_m", "y_m"]:
			assert_eq(battle.groups[f.code][i][key], survivors[i][key])

func test_frozen_legacy_flank_snapshot_keeps_saved_group_geometry() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var observer := String(codes[1])
	f.state.regiments[observer].x_m = 0
	f.state.regiments[observer].y_m = 0
	f.state.regiments[f.code].x_m = 100
	f.state.regiments[f.code].y_m = 0
	var battle: Dictionary = f.state.battles[0]
	battle.unit_formations = {f.code: {"current": "line"}}
	f.state.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day())
	var record := {"request": {"target_unit": f.code}}
	var before := SaveLoad.state_hash(f.state)
	BattleTaskSystem._snapshot_flank(f.repo, f.state, observer, record)
	assert_eq(record.flank.known.points_m.size(), 3, "101 fit still occupy three frozen50 groups")
	assert_eq(record.flank.known.points_m, [[10, 20], [30, 40], [50, 60]], "observe the actual frozen points, not a regenerated line")
	assert_eq(int(record.flank.known.radius_m), 93, "ceil(sqrt(90² + 20²)) from the saved anchor (100,0)")
	assert_eq(SaveLoad.state_hash(f.state), before, "observing cannot migrate the frozen state")

	f.state.day_resolution.clear()
	assert_eq(MilitaryReorganization.reconcile(f.repo, f.state).status, "complete")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
	var migrated := {"request": {"target_unit": f.code}}
	BattleTaskSystem._snapshot_flank(f.repo, restored, observer, migrated)
	assert_eq(migrated.flank.known.points_m.size(), 2, "after the boundary and JSON load the target uses100 groups")
	assert_eq(migrated.flank.known.points_m, [[10, 20], [50, 60]], "migration preserves the surviving saved slots")
	assert_eq(int(migrated.flank.known.radius_m), 93, "the farthest surviving saved point is unchanged")
