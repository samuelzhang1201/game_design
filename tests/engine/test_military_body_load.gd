extends GutTest
## ACT-LOAD: a fresh campaign's first bodies and the classification of loaded saves. Every
## save goes through the real loader (JSON text -> `GameState.from_dict`). Group size 100.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

## B's two legacy battle rows, 2,000 m apart: clear of each other (two infantry radii of 927 m
## sum to 1,854 m) and far from A's homes around (50,000, 50,000).
const B_POINTS := [[80000, 50000], [82000, 50000]]

func after_each() -> void:
	MarchPath.forget()

func _load(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _load_dict(raw: Dictionary) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(raw)), false)

func _file(state: GameState) -> String:
	return BodyMotion._hash(state.to_dict())

## Two infantry units on an open 200 km grid with no bodies anywhere: A (901 men) nonbattle at
## (50,000, 50,000) facing 0; B (200 men) in a legacy battle whose saved rows predate bodies
## (no `home_slot`, `facing_deg` or `body_version`).
func _legacy() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var picked: Array[String] = []
	for code: String in codes:
		if MapObjects.army_piece(repo, state.army_roster[code]) == "infantry": picked.append(code)
		if picked.size() == 2: break
	assert_eq(picked.size(), 2)
	var a := picked[0]
	var b := picked[1]
	assert_false(Personnel.replace(repo, state, a, 901).has("error"))
	assert_false(Personnel.replace(repo, state, b, 200).has("error"))
	state.regiments = {a: state.regiments[a], b: state.regiments[b]}
	state.army_roster = {a: state.army_roster[a], b: state.army_roster[b]}
	state.military_rosters = {a: state.military_rosters[a], b: state.military_rosters[b]}
	for code: String in picked:
		state.army_roster[code].is_naval = "0"
		var entry: Dictionary = state.regiments[code]
		entry.x_m = 50000 if code == a else 81000
		entry.y_m = 50000
		entry.dest_x_m = entry.x_m
		entry.dest_y_m = entry.y_m
		entry.facing_deg = 0
		entry.order = ArmySystem.ORDER_STANDBY
		entry.erase("body_groups")
		entry.erase("group_next_slot")
	state.foes = {}
	state.ai_hosts = {}
	state.day_resolution = {}
	state.town_seat = {}
	for key: String in ["body_version", "body_motion", "body_placement"]:
		state.military_migration.erase(key)
	var rows: Array = []
	for i: int in B_POINTS.size():
		rows.append({"slot": i, "count": 100, "x_m": B_POINTS[i][0], "y_m": B_POINTS[i][1],
			"role": "front", "path_m": [B_POINTS[i].duplicate()]})
	state.battles = [{"id": 1, "att": [b], "def": [], "groups": {b: rows}, "group_facing": {b: 0},
		"group_anchor_m": {b: [81000, 50000]}, "group_size_version": 2, "group_size_men": 100}]
	repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(200 * 200)
	var grid := MarchPath.build(repo, 200, 200, 1000, slopes)
	MarchPath.use(repo, grid)
	return {"repo": repo, "state": _load(state), "a": a, "b": b, "grid": grid}

## Hand-computed: 901 -> nine rows of 100 and a one-man tail at A's anchor plus each measured
## home, facing 0 (no rotation). Infantry is 5 files x 2 ranks at pitch 1,944 m
## (`unit_footprints.csv`): x = (2*file - 4) * 972, y = (2*rank - 1) * 972. Slots 0..9.
## B keeps its two saved points and slots, counts 100/100.
const A_POINTS := [[46112, 49028], [48056, 49028], [50000, 49028], [51944, 49028], [53888, 49028],
	[46112, 50972], [48056, 50972], [50000, 50972], [51944, 50972], [53888, 50972]]

func test_lawful_legacy_save_keeps_rows_and_places_missing_poses() -> void:
	var f := _legacy()
	var file := _file(f.state)
	var kind := BodyLoad.classify(f.repo, f.state)
	assert_eq(kind, {"kind": BodyLoad.LEGACY, "reason": "Lawful legacy save", "units": [f.a]})
	var result := BodyLoad.load_candidate(f.repo, f.state)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.kind, BodyLoad.LEGACY)
	assert_eq(_file(f.state), file, "the loaded save is never touched")
	if result.candidate == null: return
	var loaded: GameState = result.candidate
	var a_rows := UnitBodies.rows(f.repo, loaded, f.a)
	assert_eq(a_rows.size(), 10)
	for i: int in a_rows.size():
		var row: Dictionary = a_rows[i]
		assert_eq([int(row.slot), int(row.home_slot), int(row.count), int(row.facing_deg)], [i, i, 1 if i == 9 else 100, 0])
		assert_eq([int(row.x_m), int(row.y_m)], A_POINTS[i])
	assert_eq(int(loaded.regiments[f.a].group_next_slot), 10)
	var b_rows := UnitBodies.rows(f.repo, loaded, f.b)
	assert_eq(b_rows.size(), 2)
	for i: int in b_rows.size():
		var row: Dictionary = b_rows[i]
		assert_eq([int(row.slot), int(row.home_slot), int(row.count), int(row.x_m), int(row.y_m)],
			[i, i, 100, B_POINTS[i][0], B_POINTS[i][1]], "the legacy row is kept where it was saved")
		assert_eq(row.path_m, [B_POINTS[i]])
	assert_eq(loaded.military_migration.body_placement.operation_id, "placement:load")
	assert_eq(BodyMotion._hash(BodyLoad.load_candidate(f.repo, _load(f.state)).candidate.to_dict()), _file(loaded),
		"the same save loads to the same world (determinism)")
	assert_eq(loaded.rng.to_dict(), f.state.rng.to_dict(), "loading draws nothing")
	# Saved and loaded again it is CURRENT and comes back exactly.
	var again := _load(loaded)
	assert_eq(BodyLoad.classify(f.repo, again).kind, BodyLoad.CURRENT)
	var reloaded := BodyLoad.load_candidate(f.repo, again)
	assert_eq(reloaded.status, "complete", reloaded.reason)
	if reloaded.candidate != null: assert_eq(_file(reloaded.candidate), _file(again))

func test_fresh_campaign_initializes_and_roundtrips() -> void:
	var repo := SuiteData.repo()
	var fresh := SuiteData.campaign(repo, 319)
	var file := _file(fresh)
	var land: Array[String] = []
	# Every land roster unit with men, entry or not: foreign units are seeded at their anchors.
	for code: String in fresh.army_roster:
		if not UnitBodies._naval(fresh, code) and MilitaryRoster.fit(fresh, code) > 0: land.append(code)
	land.sort()
	assert_eq(BodyLoad.classify(repo, fresh).units, land, "a fresh campaign has no bodies yet")
	var result := BodyLoad.initialize_campaign(repo, fresh)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(_file(fresh), file)
	if result.candidate == null: return
	var started: GameState = result.candidate
	assert_eq(started.military_migration.body_placement.operation_id, "placement:new_campaign")
	for code: String in land:
		var counts := UnitBodies.rows(repo, started, code).map(func(row: Dictionary) -> int: return int(row.count))
		assert_eq(counts, Array(BattleGroups.counts(MilitaryRoster.fit(started, code), 100)), code)
	var loaded := _load(started)
	assert_eq(BodyLoad.classify(repo, loaded), {"kind": BodyLoad.CURRENT, "reason": "Current bodies kept exactly", "units": []})
	var reloaded := BodyLoad.load_candidate(repo, loaded)
	assert_eq(reloaded.status, "complete", reloaded.reason)
	if reloaded.candidate != null: assert_eq(_file(reloaded.candidate), _file(started), "a fresh campaign's save loads back exactly")
	assert_eq(BodyLoad.initialize_campaign(repo, started).status, "error", "a campaign with bodies is not fresh")

## Overlap is refused, never repaired: legacy rows 1,000 m apart (< 1,854 m), or a current
## row moved onto its neighbour. Nothing is returned and the save is untouched.
func test_overlapping_saves_are_refused() -> void:
	var f := _legacy()
	var legacy := UnitBodies._copy(f.state)
	legacy.battles[0].groups[f.b][1].x_m = 81000
	legacy.battles[0].groups[f.b][1].path_m = [[81000, 50000]]
	_assert_refused(f.repo, _load(legacy), "Measured bodies overlap")
	var current: GameState = BodyLoad.load_candidate(f.repo, f.state).candidate
	if current == null: return
	var rows: Array = current.regiments[f.a].body_groups
	rows[1].x_m = rows[0].x_m
	rows[1].y_m = rows[0].y_m
	rows[1].path_m = [[rows[0].x_m, rows[0].y_m]]
	_assert_refused(f.repo, _load(current), "Measured bodies overlap")

func test_corrupt_saves_are_refused() -> void:
	var f := _legacy()
	var current: GameState = BodyLoad.load_candidate(f.repo, f.state).candidate
	if current == null: return
	var causes := {"rows": "Invalid body array", "future": "Invalid body version", "fraction": "Invalid body x_m",
		"slot": "Duplicate body slot", "missing": "Current unit missing bodies",
		"control": "Invalid saved placement control", "version": "Unsupported source save version"}
	for mode: String in causes:
		var state := UnitBodies._copy(current)
		var rows: Array = state.regiments[f.a].body_groups
		match mode:
			"rows": state.regiments[f.a].body_groups = "rows"
			"future": state.military_migration.body_version = 2
			"fraction": rows[0].x_m = float(rows[0].x_m) + 0.5
			"slot": rows[1].slot = rows[0].slot
			"missing": state.regiments[f.a].erase("body_groups")
			"control": state.military_migration.body_placement = {"version": "9"}
		var raw: Dictionary = state.to_dict()
		if mode == "version": raw.version = GameState.MIN_SAVE_VERSION - 1
		_assert_refused(f.repo, _load_dict(raw), causes[mode])
	assert_eq([GameState.MIN_SAVE_VERSION, GameState.SAVE_VERSION], [6, 7], "no save-version bump")

## A legacy save with nothing missing only converts: rows of 50/50/100 regroup into the
## canonical 100/100 — slot 0 keeps its point and takes 0's and 1's men, slot 2 keeps its own;
## slot 1 retires and the next slot stays 3. The placement places nothing.
func test_legacy_save_with_no_missing_pose_converts_by_regroup() -> void:
	var f := _legacy()
	var state := UnitBodies._copy(f.state)
	for field: String in ["regiments", "army_roster", "military_rosters"]: state.get(field).erase(f.a)
	var rows: Array = state.battles[0].groups[f.b]
	rows[0].count = 50
	rows[1].count = 50
	rows.append({"slot": 2, "count": 100, "x_m": 84000, "y_m": 50000, "role": "front", "path_m": [[84000, 50000]]})
	var loaded := _load(state)
	assert_eq(BodyLoad.classify(f.repo, loaded), {"kind": BodyLoad.LEGACY, "reason": "Lawful legacy save", "units": []})
	var result := BodyLoad.load_candidate(f.repo, loaded)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var kept := UnitBodies.rows(f.repo, result.candidate, f.b).map(func(row: Dictionary) -> Array:
		return [int(row.slot), int(row.home_slot), int(row.count), int(row.x_m), int(row.y_m)])
	assert_eq(kept, [[0, 0, 100, 80000, 50000], [2, 1, 100, 84000, 50000]])
	assert_eq(int(result.candidate.regiments[f.b].group_next_slot), 3)
	assert_eq(result.candidate.military_migration.body_placement.operation_id, "placement:load")
	assert_eq(int(result.candidate.military_migration.body_version), 1)

## No room for a missing pose, a kept row on forbidden ground, or a placement control in a
## save without current bodies: refused with the reason, never deferred or repaired.
func test_no_room_bad_ground_and_stray_control_are_refused() -> void:
	var f := _legacy()
	f.grid.closed.fill(1)
	_assert_refused(f.repo, f.state, "space_unavailable")
	f.grid.closed.fill(0)
	var current: GameState = BodyLoad.load_candidate(f.repo, f.state).candidate
	if current == null: return
	var row: Dictionary = UnitBodies.rows(f.repo, current, f.a)[0]
	f.grid.water[int(row.y_m) / 1000 * 200 + int(row.x_m) / 1000] = 1
	_assert_refused(f.repo, _load(current), f.a + " slot 0")
	f.grid.water.fill(0)
	var stray := UnitBodies._copy(f.state)
	stray.military_migration.body_placement = current.military_migration.body_placement.duplicate()
	_assert_refused(f.repo, _load(stray), "Placement control without current bodies")

func test_frozen_and_pending_saves_defer() -> void:
	var f := _legacy()
	var frozen := UnitBodies._copy(f.state)
	frozen.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day())
	frozen = _load(frozen)
	var file := _file(frozen)
	assert_eq(BodyLoad.classify(f.repo, frozen).kind, BodyLoad.DEFERRED)
	var result := BodyLoad.load_candidate(f.repo, frozen)
	assert_eq([result.status, result.kind, result.candidate], ["deferred", BodyLoad.DEFERRED, null])
	assert_eq(_file(frozen), file)
	var current: GameState = BodyLoad.load_candidate(f.repo, f.state).candidate
	if current == null: return
	assert_false(Personnel.replace(f.repo, current, f.b, 300).has("error"))
	var staged := UnitBodies.reconcile_candidate(f.repo, current, f.b, 200)
	assert_eq(staged.status, "needs_placement", staged.reason)
	if staged.candidate == null: return
	var pending := _load(staged.candidate)
	assert_eq(BodyLoad.classify(f.repo, pending).kind, BodyLoad.DEFERRED, "a staged recruit waits for its own transaction")
	assert_null(BodyLoad.load_candidate(f.repo, pending).candidate)
	var proof := UnitBodies._copy(current)
	proof.military_migration.body_placement = {"version": "2", "sequence": "1", "operation_id": "placement:proof",
		"receipt": "a".repeat(64), "completion_json": "{}"}
	proof.day_resolution = DayResolution.begin(proof.day, false, proof.absolute_day())
	assert_eq(BodyLoad.classify(f.repo, _load(proof)).kind, BodyLoad.DEFERRED, "a v2 completion proof waits for its consumer")

func test_no_ordinary_path_reaches_body_load() -> void:
	for path: String in _scripts("res://scripts"):
		if path.ends_with("/body_load.gd"): continue
		assert_false(FileAccess.get_file_as_string(path).contains("BodyLoad"), path + " stays off ACT-LOAD until ACT-CUTOVER")

func _assert_refused(repo: DataRepository, source: GameState, reason: String) -> Dictionary:
	var file := _file(source)
	var kind := BodyLoad.classify(repo, source)
	assert_eq(kind.kind, BodyLoad.REFUSED, kind.reason)
	var result := BodyLoad.load_candidate(repo, source)
	assert_eq([result.status, result.kind, result.candidate], ["error", BodyLoad.REFUSED, null])
	assert_eq(result.error, kind.reason)
	if not reason.is_empty(): assert_string_contains(kind.reason, reason)
	assert_eq(_file(source), file, "a refused save is never touched")
	return result

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"): out.append(dir + "/" + name)
	for sub: String in DirAccess.get_directories_at(dir): out.append_array(_scripts(dir + "/" + sub))
	return out
