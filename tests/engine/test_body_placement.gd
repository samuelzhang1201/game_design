extends GutTest

func test_candidate_placement_api_exists() -> void:
	var ground: GDScript = load("res://scripts/engine/army_ground.gd")
	for method: String in ["plan_body_placement_candidate", "commit_body_placement_candidate", "body_placement_candidate"]:
		assert_true(ground.has_method(method), method)
	assert_true((load("res://scripts/engine/army_split.gd") as GDScript).has_method("initialize_bodies_candidate"))
	assert_true((load("res://scripts/engine/enemy_ai.gd") as GDScript).has_method("spawn_body_candidate"))
	assert_true((load("res://scripts/engine/unit_bodies.gd") as GDScript).has_method("validate_placement_candidate"))

const SuiteData := preload("res://tests/suite_data.gd")
var _completion_marches: Dictionary = {}

func test_production_input_foundation_probe() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var result := UnitBodies.migrate_candidate(repo, state)
	assert_eq(result.status, "needs_placement", result.reason)
	print("CF04b production foundation: ", result.status, " ", result.reason)
	for code: String in state.regiments.keys() + state.foes.keys():
		if not UnitBodies._naval(state, code):
			assert_lte(MilitaryRoster.fit(state, code), 10 * int(repo.bal("battle_group_size")), code)

const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()

func after_all() -> void:
	_completion_marches.clear()

func _available() -> bool:
	return (load("res://scripts/engine/army_ground.gd") as GDScript).has_method("body_placement_candidate")

func _fixture(n: int = 901) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes := state.regiments.keys()
	codes.sort()
	var code: String = ""
	for possible: String in codes:
		if MapObjects.army_piece(repo, state.army_roster[possible]) == "infantry":
			code = possible
			break
	assert_ne(code, "")
	assert_false(Personnel.replace(repo, state, code, n).has("error"))
	var entry: Dictionary = state.regiments[code]
	state.regiments = {code: entry}
	state.army_roster = {code: state.army_roster[code]}
	state.army_roster[code].is_naval = "0"
	state.military_rosters = {code: state.military_rosters[code]}
	state.foes = {}
	state.ai_hosts = {}
	state.battles = []
	state.day_resolution = {}
	state.town_seat = {}
	for key: String in ["body_version", "body_motion", "body_placement"]:
		state.military_migration.erase(key)
	entry.x_m = 50000
	entry.y_m = 50000
	entry.dest_x_m = 50000
	entry.dest_y_m = 50000
	entry.facing_deg = 0
	entry.order = ArmySystem.ORDER_STANDBY
	entry.erase("body_groups")
	entry.erase("group_next_slot")
	repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(200 * 200)
	var grid := MarchPath.build(repo, 200, 200, 1000, slopes)
	MarchPath.use(repo, grid)
	return {"repo": repo, "state": state, "code": code, "grid": grid}

func _request(operation: String = "initialize", unit: String = "", sequence: String = "0") -> Dictionary:
	return {"version": 1, "operation_id": "placement:test:" + sequence, "sequence": sequence,
		"operation": operation, "unit": unit, "host": "", "previous_fit": null}

func _boundary(state: GameState) -> Dictionary:
	return {"version": 1, "kind": "safe", "abs_day": str(state.absolute_day())}

func _call(f: Dictionary, request: Dictionary, status: String = "complete") -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = (load("res://scripts/engine/army_ground.gd") as GDScript).call("body_placement_candidate", f.repo, f.state, request, _boundary(f.state))
	assert_eq(result.status, status, result.reason)
	assert_eq(result.size(), 5)
	assert_eq(f.state.to_dict(), before)
	assert_eq(f.state.rng.to_dict(), before.rng)
	if status != "complete":
		assert_null(result.candidate)
		assert_eq(result.plan, {})
	return result

func test_home_counts_and_identities() -> void:
	if not _available(): return
	for n: int in [1000, 901, 900, 1, 0]:
		var f := _fixture(n)
		var result := _call(f, _request())
		if result.candidate == null: continue
		var rows := UnitBodies.rows(f.repo, result.candidate, f.code)
		assert_eq(rows.size(), BattleGroups.counts(n, 100).size())
		var total := 0
		for row: Dictionary in rows: total += int(row.count)
		assert_eq(total, n)
		assert_eq(UnitBodies.home_slots(f.repo, result.candidate, f.code).size(), 10)
		assert_eq(UnitBodies.footprint(f.repo, f.code, result.candidate), UnitBodies.footprint(f.repo, f.code, f.state))
		assert_eq(UnitBodies.migrate_candidate(f.repo, result.candidate).status, "complete")
	var rotated := _fixture(1)
	rotated.state.regiments[rotated.code].facing_deg = 90
	var turned := _call(rotated, _request())
	if turned.candidate != null:
		assert_eq(turned.plan.placements[0].path_m, [[51854, 42584]], "90 degrees rotates (-7416,-1854) to (1854,-7416), y down")
	var invalid := _fixture(1)
	var id: String = invalid.state.military_rosters[invalid.code].cohort_ids.back()
	invalid.state.military_cohorts[id].fit = 1001
	_call(invalid, _request(), "error")

func test_plan_raw_stale_atomic_json() -> void:
	if not _available(): return
	var f := _fixture()
	var before: Dictionary = f.state.to_dict()
	var planned: Dictionary = (load("res://scripts/engine/army_ground.gd") as GDScript).call("plan_body_placement_candidate", f.repo, f.state, _request(), _boundary(f.state))
	assert_eq(planned.status, "complete", planned.reason)
	assert_null(planned.candidate)
	assert_eq(f.state.to_dict(), before)
	if planned.status != "complete": return
	var wire: Dictionary = JSON.parse_string(JSON.stringify(planned.plan))
	var committed: Dictionary = (load("res://scripts/engine/army_ground.gd") as GDScript).call("commit_body_placement_candidate", f.repo, f.state, wire, _boundary(f.state))
	assert_eq(committed.status, "complete", committed.reason)
	if committed.candidate == null: return
	var accepted: GameState = committed.candidate
	var retried: Dictionary = (load("res://scripts/engine/army_ground.gd") as GDScript).call("commit_body_placement_candidate", f.repo, accepted, wire, _boundary(accepted))
	assert_eq(retried.status, "complete", retried.reason)
	assert_eq(retried.candidate.to_dict(), accepted.to_dict())
	var accepted_before := accepted.to_dict()
	retried.candidate.regiments[f.code].body_groups[0].path_m[0][0] += 1
	assert_eq(accepted.to_dict(), accepted_before, "retry is detached down to nested paths")
	var body: Dictionary = UnitBodies.rows(f.repo, accepted, f.code)[0]
	var cell: int = (int(body.y_m) / f.grid.cell_m) * f.grid.cols + int(body.x_m) / f.grid.cell_m
	f.grid.water[cell] = 1
	var invalid_terrain := ArmyGround.commit_body_placement_candidate(f.repo, accepted, wire, _boundary(accepted))
	assert_eq(invalid_terrain.status, "error", "an exact retry still validates the current physical world")
	assert_null(invalid_terrain.candidate)
	assert_eq(accepted.to_dict(), accepted_before)
	f.grid.water[cell] = 0
	f.repo.balance.army_march_grid_px = 0
	var missing_grid := ArmyGround.commit_body_placement_candidate(f.repo, accepted, wire, _boundary(accepted))
	assert_eq(missing_grid.status, "error", "retry cannot certify a missing terrain grid")
	assert_null(missing_grid.candidate)
	f.repo.balance.army_march_grid_px = 1
	MarchPath.use(f.repo, f.grid)
	f.state = accepted
	_call(f, _request(), "error")
	var changed := UnitBodies._copy(accepted)
	changed.regiments[f.code].supplies += 1
	var tampered: Dictionary = wire.duplicate(true)
	tampered.placements[0].x_m += 1
	assert_eq((load("res://scripts/engine/army_ground.gd") as GDScript).call("commit_body_placement_candidate", f.repo, accepted, tampered, _boundary(accepted)).status, "error")
	f.state = UnitBodies._copy(changed)
	f.state.military_migration.erase("body_placement")
	assert_eq((load("res://scripts/engine/army_ground.gd") as GDScript).call("commit_body_placement_candidate", f.repo, f.state, wire, _boundary(f.state)).status, "error")
	for invalid: Variant in [true, 1, 1.5, "01", "-1", "9223372036854775808"]:
		var req := _request()
		req.sequence = invalid
		_call(f, req, "error")
	for id: String in ["", "placement:", "i42", "f3ff0000000000000"]:
		var req := _request()
		req.operation_id = id
		_call(f, req, "error")

func test_production_inputs_and_dispatch() -> void:
	if not _available(): return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var before := state.to_dict()
	var grid := MarchPath.of_pack(repo)
	for code: String in state.regiments.keys() + state.foes.keys():
		if UnitBodies._naval(state, code): continue
		var entry := UnitBodies._entry(state, code)
		var error := ArmySystem._body_path_terrain(grid, [[int(entry.x_m), int(entry.y_m)]], 0)
		if not error.is_empty(): print("CF04b original anchor: ", code, " ", entry.x_m, ",", entry.y_m, " ", error)
	var result: Dictionary = (load("res://scripts/engine/army_split.gd") as GDScript).call("initialize_bodies_candidate", repo, state, "placement:production", "0")
	assert_eq(state.to_dict(), before)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null:
		print("CF04b production input failure: ", result.reason)
		return
	assert_eq(UnitBodies.migrate_candidate(repo, result.candidate).status, "complete")
	assert_false(state.military_migration.get("living_unit_mapping", {}).is_empty(), "real bootstrap has staged living-cap splits")
	for field: String in ["army_roster", "military_rosters", "military_cohorts", "military_events", "world", "metrics", "recruitment_projects", "unit_prize_gold"]:
		assert_eq(result.candidate.get(field), state.get(field), "placement does not split personnel/provenance or pay again: " + field)
	for code: String in state.regiments.keys() + state.foes.keys():
		if UnitBodies._naval(state, code): continue
		var entry := UnitBodies._entry(state, code)
		var placed_entry := UnitBodies._entry(result.candidate, code)
		assert_eq([placed_entry.x_m, placed_entry.y_m], [entry.x_m, entry.y_m], "saved anchors are not moved")
		var radius := int(UnitBodies._config(repo, result.candidate, code).radius_m)
		for row: Dictionary in UnitBodies.rows(repo, result.candidate, code):
			assert_eq(ArmySystem._body_path_terrain(grid, [[int(row.x_m), int(row.y_m)]], radius), "", code)
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(result.candidate.to_dict())), false)
	assert_eq(UnitBodies.migrate_candidate(repo, loaded).status, "complete")

func test_finite_space_and_terrain() -> void:
	if not _available(): return
	var f := _fixture(1)
	var result := _call(f, _request())
	if result.candidate == null: return
	var row: Dictionary = result.plan.placements[0]
	var expected := UnitBodies.home_slots(f.repo, f.state, f.code)[0]
	assert_eq([int(row.x_m), int(row.y_m)], [50000 + expected.x, 50000 + expected.y])
	assert_eq(int(f.repo.bal("army_slot_spacing_m")), 4400)
	var reordered := UnitBodies._copy(f.state)
	var keys: Array = reordered.regiments[f.code].keys()
	keys.reverse()
	var reversed_entry := {}
	for key: String in keys: reversed_entry[key] = reordered.regiments[f.code][key]
	reordered.regiments[f.code] = reversed_entry
	var reordered_plan := ArmyGround.plan_body_placement_candidate(f.repo, reordered, _request(), _boundary(reordered))
	assert_eq(BodyMotion._hash(reordered_plan.plan), BodyMotion._hash(result.plan), "dictionary insertion order does not affect the plan")
	var radius := int(UnitBodies._config(f.repo, f.state, f.code).radius_m)
	assert_eq(ArmySystem._body_path_terrain(f.grid, [[radius - 1, 50000]], radius), "Swept body extends outside terrain bounds")
	var cell: int = int(row.y_m) / f.grid.cell_m * f.grid.cols + int(row.x_m) / f.grid.cell_m
	f.grid.water[cell] = 1
	var rerouted := _call(f, _request())
	if rerouted.candidate != null:
		assert_ne(rerouted.plan.placements[0].path_m, row.path_m)
		assert_eq(rerouted.plan.placements[0].path_m, [[int(row.x_m) + 4400, int(row.y_m)]], "first legal ring-1 east offset at actual CSV pitch")
		assert_eq(ArmySystem._body_path_terrain(f.grid, rerouted.plan.placements[0].path_m, radius), "")
	f.grid.water[cell] = 0
	f.grid.closed[cell] = 1
	var scarp := _call(f, _request())
	if scarp.candidate != null: assert_eq(scarp.plan.placements, rerouted.plan.placements)
	var left: int = (int(row.x_m) / f.grid.cell_m) * f.grid.cell_m
	var middle: int = (int(row.y_m) / f.grid.cell_m) * f.grid.cell_m + f.grid.cell_m / 2
	assert_eq(ArmySystem._body_path_terrain(f.grid, [[left - radius, middle]], radius), "Swept segment touches forbidden terrain", "circle grazing a closed cell is forbidden")
	f.grid.closed.fill(1)
	_call(f, _request(), "deferred")
	f.grid.closed.fill(0)
	f.state.regiments[f.code].x_m = 0x7fffffffffffffff
	f.state.regiments[f.code].facing_deg = 180
	_call(f, _request(), "error")
	MarchPath.forget()
	f.repo.balance.army_march_grid_px = 0
	_call(f, _request(), "error")

func test_missing_vs_corrupt_and_old_load() -> void:
	if not _available(): return
	var f := _fixture(1)
	assert_eq(UnitBodies.migrate_candidate(f.repo, f.state).status, "needs_placement")
	var first := _call(f, _request())
	if first.candidate == null: return
	var good: GameState = first.candidate
	for mode: String in ["empty", "missing", "count", "home", "slot", "future", "null", "path", "anchor_bool", "anchor_fraction"]:
		f.state = UnitBodies._copy(good)
		var entry: Dictionary = f.state.regiments[f.code]
		match mode:
			"empty": entry.body_groups = []
			"missing": entry.erase("body_groups")
			"count": entry.body_groups[0].count = true
			"home": entry.body_groups[0].home_slot = 10
			"slot": entry.group_next_slot = 0
			"future": f.state.military_migration.body_version = 2
			"null": f.state.military_migration.body_version = null
			"path": entry.body_groups[0].path_m = [[0.5, 0]]
			"anchor_bool": entry.x_m = true
			"anchor_fraction": entry.x_m = 1.5
		_call(f, _request("initialize", "", "1"), "error")
	for id: String in ["placement:i42", "placement:f3ff0000000000000"]:
		f = _fixture(1)
		# Build the real supported main-v7 wire envelope, then use the actual loader.
		var legacy: Dictionary = f.state.to_dict()
		legacy.erase("military_migration")
		legacy.military_organization_version = 1
		legacy.military_migration_pending = false
		legacy.military_unit_aliases = {}
		legacy.military_conflicts = []
		for field: String in ["military_rosters", "military_cohorts", "military_events"]:
			legacy[field] = GameState._encode_values(f.state.get(field))
		f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(legacy)), false)
		var req := _request()
		req.operation_id = id
		var accepted := _call(f, req)
		if accepted.candidate == null: continue
		var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(accepted.candidate.to_dict())), false)
		assert_true(loaded.military_migration.has("import_main_v7"), "exercise valid imported main-v7 deep decoding")
		assert_eq(loaded.military_migration.body_placement, accepted.candidate.military_migration.body_placement)
		var retried: Dictionary = (load("res://scripts/engine/army_ground.gd") as GDScript).call("commit_body_placement_candidate", f.repo, loaded, JSON.parse_string(JSON.stringify(accepted.plan)), _boundary(loaded))
		assert_eq(retried.status, "complete", retried.reason)

func test_recruit_split_and_host_once() -> void:
	if not _available(): return
	var f := _fixture(901)
	var initial := _call(f, _request())
	if initial.candidate == null: return
	f.state = initial.candidate
	var original := UnitBodies.rows(f.repo, f.state, f.code)
	assert_false(Personnel.move(f.repo, f.state, f.code, "fit", "wounded", 1).has("error"))
	var req := _request("recruit", f.code, "1")
	req.previous_fit = "901"
	var loss := _call(f, req)
	if loss.candidate == null: return
	f.state = loss.candidate
	assert_eq(UnitBodies.rows(f.repo, f.state, f.code), original.slice(0, 9))
	assert_eq(f.state.regiments[f.code].group_next_slot, 10)
	assert_false(Personnel.move(f.repo, f.state, f.code, "wounded", "fit", 1).has("error"))
	var people: Dictionary = f.state.military_cohorts.duplicate(true)
	var pending := UnitBodies.reconcile_candidate(f.repo, f.state, f.code, 900)
	assert_eq(pending.status, "needs_placement", pending.reason)
	f.state = pending.candidate
	req = _request("recruit", f.code, "2")
	req.previous_fit = "900"
	var growth := _call(f, req)
	if growth.candidate == null: return
	assert_eq(growth.candidate.military_cohorts, people)
	var grown := UnitBodies.rows(f.repo, growth.candidate, f.code)
	assert_eq(grown.size(), 10)
	assert_eq(grown.slice(0, 9), original.slice(0, 9))
	assert_eq(grown[9].slot, 10, "retired slot 9 is never reused")
	assert_eq(growth.candidate.regiments[f.code].group_next_slot, 11)
	var host: Dictionary = f.repo.raid_hosts[0]
	var before: Dictionary = growth.candidate.to_dict()
	var spawned: Dictionary = (load("res://scripts/engine/enemy_ai.gd") as GDScript).call("spawn_body_candidate", f.repo, growth.candidate, host.host_code, "placement:host", "3")
	assert_eq(spawned.status, "error", "local roster does not contain this real host")
	assert_eq(growth.candidate.to_dict(), before)

func test_existing_pose_is_authority() -> void:
	if not _available(): return
	var f := _fixture(100)
	var first := _call(f, _request())
	if first.candidate == null: return
	f.state = first.candidate
	var row: Dictionary = f.state.regiments[f.code].body_groups[0]
	row.x_m += 71
	row.y_m += 37
	row.facing_deg = 217
	row.path_m = [[row.x_m - 10, row.y_m - 7], [row.x_m, row.y_m]]
	var rows := UnitBodies.rows(f.repo, f.state, f.code)
	for i: int in 4:
		var op: String = ["initialize", "settle", "leave", "reconcile"][i]
		var req := _request(op, f.code if op in ["settle", "leave"] else "", str(i + 1))
		var result := _call(f, req)
		if result.candidate == null: continue
		assert_eq(UnitBodies.rows(f.repo, result.candidate, f.code), rows)
		assert_eq(result.candidate.regiments[f.code].x_m, 50000)
		f.state = result.candidate

func test_saved_boundaries() -> void:
	if not _available(): return
	var f := _fixture(100)
	var first := _call(f, _request())
	if first.candidate == null: return
	f.state = first.candidate
	f.state.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day())
	_call(f, _request("leave", f.code, "1"), "deferred")
	f.state.day_resolution.protocol_version = true
	_call(f, _request("leave", f.code, "1"), "error")
	f.state.day_resolution = {}
	var begun := TickEngine.new(f.repo).begin_body_march_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	if begun.candidate == null: return
	var state: GameState = begun.candidate
	var nonfinal := {"version": 1, "kind": "march_complete", "abs_day": str(state.absolute_day()), "receipt": "a".repeat(64)}
	assert_eq((load("res://scripts/engine/unit_bodies.gd") as GDScript).call("validate_placement_candidate", f.repo, state, nonfinal).status, "deferred")
	for i: int in int(state.day_resolution.body_march.substep_count):
		var stepped := TickEngine.new(f.repo).step_body_march_candidate(state)
		assert_eq(stepped.status, "complete", stepped.reason)
		if stepped.candidate == null: return
		state = stepped.candidate
	var boundary := {"version": 1, "kind": "march_complete", "abs_day": str(state.absolute_day()), "receipt": state.day_resolution.body_march.last.receipt}
	var frozen: Dictionary = state.day_resolution.duplicate(true)
	var result: Dictionary = (load("res://scripts/engine/army_ground.gd") as GDScript).call("body_placement_candidate", f.repo, state, _request("leave", f.code, "1"), boundary)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate != null: assert_eq(result.candidate.day_resolution, frozen)
	assert_eq(state.day_resolution, frozen)
	boundary.receipt = "b".repeat(64)
	assert_eq((load("res://scripts/engine/army_ground.gd") as GDScript).call("body_placement_candidate", f.repo, state, _request("leave", f.code, "1"), boundary).status, "error")

func test_all_realms_and_overlapping_rectangles() -> void:
	if not _available(): return
	var f := _fixture(1)
	var calibration: Dictionary = f.repo.unit_footprints.infantry
	assert_eq(int(calibration.radius_m), 927)
	assert_eq(int(calibration.pitch_m), 3708)
	assert_eq(int(calibration.width_m), 16686)
	assert_eq(int(calibration.depth_m), 5562)
	var all := SuiteData.campaign(f.repo, 319)
	var second := ""
	var codes := all.regiments.keys()
	codes.sort()
	for code: String in codes:
		if code != f.code and MapObjects.army_piece(f.repo, all.army_roster[code]) == "infantry" \
			and all.army_roster[code].kingdom_code == f.state.army_roster[f.code].kingdom_code:
			second = code
			break
	assert_ne(second, "")
	f.state.army_roster[second] = all.army_roster[second].duplicate(true)
	f.state.military_rosters[second] = all.military_rosters[second].duplicate(true)
	f.state.regiments[second] = all.regiments[second].duplicate(true)
	assert_false(Personnel.replace(f.repo, f.state, second, 1).has("error"))
	var entry: Dictionary = f.state.regiments[second]
	entry.x_m = 50000
	entry.y_m = 51854
	entry.dest_x_m = 50000
	entry.dest_y_m = 51854
	entry.facing_deg = 0
	entry.order = ArmySystem.ORDER_STANDBY
	var result := _call(f, _request())
	if result.candidate == null: return
	var first_row: Dictionary = UnitBodies.rows(f.repo, result.candidate, f.code)[0]
	var second_row: Dictionary = UnitBodies.rows(f.repo, result.candidate, second)[0]
	assert_eq(absi(int(first_row.y_m) - int(second_row.y_m)), 1854)
	assert_eq(first_row.x_m, second_row.x_m)
	assert_lt(1854, int(calibration.depth_m), "deployment rectangles overlap while circles are tangent")
	var occupied := UnitBodies._copy(result.candidate)
	occupied.regiments[second].x_m = 50000
	occupied.regiments[second].y_m = 50000
	var town := ""
	for key: String in f.repo.burgs:
		if ArmyGround.holds(f.repo, occupied, String(occupied.army_roster[second].kingdom_code), key):
			town = key
			break
	assert_ne(town, "")
	var town_px := ArmySystem.metres_to_pack(f.repo, Vector2i(50000, 50000))
	f.repo.burgs[town].x = town_px.x
	f.repo.burgs[town].y = town_px.y
	ArmySystem.forget_grids()
	occupied.regiments[f.code].camp_town = town
	occupied.regiments[second].camp_town = town
	occupied.town_seat = {town: f.code}
	var retained: Dictionary = occupied.regiments[f.code].duplicate(true)
	f.state = occupied
	var settled := _call(f, _request("settle", second, "1"))
	if settled.candidate != null:
		assert_eq(settled.candidate.town_seat[town], f.code, "camping does not take an occupied seat")
		f.state = settled.candidate
		var seated := _call(f, _request("take_seat", second, "2"))
		if seated.candidate != null:
			assert_eq(seated.candidate.town_seat[town], second, "already arrived unit transfers metadata only")
			assert_eq(seated.candidate.regiments[f.code], retained, "former holder is never teleported")
			assert_eq(UnitBodies.rows(f.repo, seated.candidate, second), UnitBodies.rows(f.repo, occupied, second))
	f.state = result.candidate
	f.state.regiments[second].body_groups[0].y_m -= 1
	_call(f, _request("initialize", "", "1"), "error")

func test_stale_basis_and_closed_plan_matrix() -> void:
	if not _available(): return
	var f := _fixture(1)
	var planned := ArmyGround.plan_body_placement_candidate(f.repo, f.state, _request(), _boundary(f.state))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.status != "complete": return
	var frozen: Dictionary = f.state.to_dict()
	for field: String in ["supply", "seat", "command", "owner", "fit", "terrain", "config", "schema"]:
		var state := UnitBodies._copy(f.state)
		var repo: DataRepository = f.repo
		var old_radius: Variant = repo.unit_footprints.infantry.radius_m
		var old_schema: Array = repo.world_schema.duplicate(true)
		match field:
			"supply": state.regiments[f.code].supplies += 1
			"seat": state.town_seat["changed"] = f.code
			"command": state.regiments[f.code].order_id = int(state.regiments[f.code].get("order_id", 0)) + 1
			"owner": state.army_roster[f.code].kingdom_code = "unknown"
			"fit":
				var id: String = state.military_rosters[f.code].cohort_ids.back()
				state.military_cohorts[id].fit += 1
			"terrain": f.grid.closed[0] = 1
			"config": repo.unit_footprints.infantry.radius_m = int(old_radius) + 1
			"schema": repo.world_schema.append({"test_change": true})
		var before := state.to_dict()
		var result := ArmyGround.commit_body_placement_candidate(repo, state, planned.plan, _boundary(state))
		assert_eq(result.status, "error", field)
		assert_eq(state.to_dict(), before)
		f.grid.closed[0] = 0
		repo.unit_footprints.infantry.radius_m = old_radius
		repo.world_schema.assign(old_schema)
	for field: String in ["coordinate", "count", "effect", "unknown", "fraction", "boolean", "boundary"]:
		var plan: Dictionary = planned.plan.duplicate(true)
		match field:
			"coordinate": plan.placements[0].x_m += 1
			"count": plan.placements[0].count += 1
			"effect": plan.effects.seats["changed"] = f.code
			"unknown": plan.extra = true
			"fraction": plan.placements[0].slot = 0.5
			"boolean": plan.placements[0].slot = true
			"boundary": plan.boundary.extra = true
		assert_eq(ArmyGround.commit_body_placement_candidate(f.repo, f.state, plan, _boundary(f.state)).status, "error", field)
	assert_eq(f.state.to_dict(), frozen)

func test_real_march_then_seat_has_no_extra_cost_or_move() -> void:
	if not _available(): return
	_seat_march_case(false)
	_seat_march_case(true)

func _seat_march_case(diagonal: bool) -> void:
	var f := _fixture(100)
	var first := _call(f, _request())
	if first.candidate == null: return
	f.state = first.candidate
	var town := ""
	var realm: String = f.state.army_roster[f.code].kingdom_code
	for key: String in f.repo.burgs:
		if ArmyGround.holds(f.repo, f.state, realm, key):
			town = key
			break
	assert_ne(town, "")
	var target := Vector2i(50400, 50000) if diagonal else Vector2i(50200, 50200)
	var town_px := ArmySystem.metres_to_pack(f.repo, target)
	f.repo.burgs[town].x = town_px.x
	f.repo.burgs[town].y = town_px.y
	ArmySystem.forget_grids()
	var entry: Dictionary = f.state.regiments[f.code]
	entry.camp_town = town
	var deferred := _call(f, _request("take_seat", f.code, "1"), "deferred")
	assert_true(deferred.reason.begins_with("requires_motion"))
	entry.order = ArmySystem.ORDER_MARCH
	entry.order_id = 1
	entry.dest_x_m = target.x
	entry.dest_y_m = target.y
	entry.route_m = [[50200, 50100], [target.x, target.y]] if diagonal else [[50200, 50000], [target.x, target.y]]
	entry.supplies = 100000
	entry.erase("camp_state")
	entry.erase("departure")
	var begun := TickEngine.new(f.repo).begin_body_march_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	if begun.candidate == null: return
	var state: GameState = begun.candidate
	for i: int in int(state.day_resolution.body_march.substep_count):
		var step := TickEngine.new(f.repo).step_body_march_candidate(state)
		assert_eq(step.status, "complete", step.reason)
		if step.candidate == null: return
		state = step.candidate
	if diagonal:
		# Eight ceil(40,20)=45 slices leave 88 m; the remaining (80,-40) needs 90.
		assert_eq([state.regiments[f.code].x_m, state.regiments[f.code].y_m], [50320, 50040])
		assert_eq(int(state.day_resolution.march_entries[f.code].day_walked_m), 448)
	else:
		assert_eq([state.regiments[f.code].x_m, state.regiments[f.code].y_m], [target.x, target.y])
		assert_eq(int(state.day_resolution.march_entries[f.code].day_walked_m), 400, "two 200 m legs, not the 283 m chord")
	var rows := UnitBodies.rows(f.repo, state, f.code)
	var paid: Variant = state.regiments[f.code].supplies
	var payload: Dictionary = state.day_resolution.duplicate(true)
	var boundary := {"version": 1, "kind": "march_complete", "abs_day": str(state.absolute_day()), "receipt": state.day_resolution.body_march.last.receipt}
	var result := ArmyGround.body_placement_candidate(f.repo, state, _request("settle", f.code, "1"), boundary)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	if diagonal: assert_ne(result.candidate.town_seat.get(town), f.code, "no free final leg into the seat")
	else: assert_eq(result.candidate.town_seat.get(town), f.code)
	assert_eq(result.candidate.regiments[f.code].supplies, paid)
	assert_eq(UnitBodies.rows(f.repo, result.candidate, f.code), rows)
	assert_eq(result.candidate.day_resolution, payload)

func test_actual_host_membership_first_circle_and_once() -> void:
	if not _available(): return
	var repo := SuiteData.repo()
	var original := SuiteData.campaign(repo, 319)
	var host: Dictionary = repo.raid_hosts[0]
	var units := EnemyAi.host_units(repo, original, host)
	assert_false(units.is_empty())
	var source := UnitBodies._copy(original)
	source.ai_hosts = {}
	source.foes = {}
	source.regiments = {}
	source.army_roster = {}
	source.military_rosters = {}
	source.battles = []
	source.town_seat = {}
	source.day_resolution = {}
	source.military_migration.erase("body_version")
	source.military_migration.erase("body_placement")
	for code: String in units:
		source.army_roster[code] = original.army_roster[code].duplicate(true)
		source.military_rosters[code] = original.military_rosters[code].duplicate(true)
		source.regiments[code] = UnitBodies._entry(original, code).duplicate(true)
		source.regiments[code].extension = {"kept": [7]}
	var before := source.to_dict()
	var result := EnemyAi.spawn_body_candidate(repo, source, host.host_code, "placement:first-host", "0")
	assert_eq(result.status, "complete", result.reason)
	assert_eq(source.to_dict(), before)
	if result.candidate == null: return
	assert_eq(result.candidate.ai_hosts[host.host_code].mode, EnemyAi.MODE_ASSEMBLE)
	assert_eq(result.candidate.military_cohorts, source.military_cohorts)
	assert_eq(result.candidate.military_events, source.military_events)
	for code: String in units:
		assert_false(result.candidate.regiments.has(code))
		assert_true(result.candidate.foes.has(code))
		assert_eq(result.candidate.foes[code].extension, {"kept": [7]})
		assert_eq(UnitBodies.rows(repo, result.candidate, code).size(), BattleGroups.counts(MilitaryRoster.fit(source, code), 100).size())
	var second := EnemyAi.spawn_body_candidate(repo, result.candidate, host.host_code, "placement:second-host", "1")
	assert_eq(second.status, "error", second.reason)
	var retry := ArmyGround.commit_body_placement_candidate(repo, result.candidate, result.plan, _boundary(source))
	assert_eq(retry.status, "complete", retry.reason)
	assert_eq(retry.candidate.to_dict(), result.candidate.to_dict())
	# First poses for a staged unspawned host may share its saved assembly anchor.
	var unplaced := UnitBodies._copy(source)
	var start := ArmySystem.pack_to_metres(repo, Vector2(float(host.start_x), float(host.start_y)))
	for code: String in units:
		unplaced.regiments[code].x_m = start.x
		unplaced.regiments[code].y_m = start.y
		unplaced.regiments[code].dest_x_m = start.x
		unplaced.regiments[code].dest_y_m = start.y
	var initialized := ArmySplit.initialize_bodies_candidate(repo, unplaced, "placement:host-regiments", "0")
	assert_eq(initialized.status, "complete", initialized.reason)
	if initialized.candidate != null:
		var staged: GameState = initialized.candidate
		var old_rows := {}
		var supplies := {}
		for code: String in units:
			old_rows[code] = UnitBodies.rows(repo, staged, code)
			supplies[code] = staged.regiments[code].supplies
		var transferred := EnemyAi.spawn_body_candidate(repo, staged, host.host_code, "placement:lawful-transfer", "1")
		assert_eq(transferred.status, "complete", transferred.reason)
		if transferred.candidate != null:
			for code: String in units:
				assert_eq(UnitBodies.rows(repo, transferred.candidate, code), old_rows[code])
				assert_eq(transferred.candidate.foes[code].supplies, supplies[code], "existing supplies are never initialized again")
		var code: String = units[0]
		staged.regiments[code].x_m += 1
		var before_transfer := staged.to_dict()
		var waiting := EnemyAi.spawn_body_candidate(repo, staged, host.host_code, "placement:needs-motion", "1")
		assert_eq(waiting.status, "deferred", waiting.reason)
		assert_true(waiting.reason.begins_with("requires_motion"))
		assert_eq(staged.to_dict(), before_transfer)
	var grid := MarchPath.of_pack(repo)
	var pristine_closed := grid.closed.duplicate()
	var sealed := MarchPath.new()
	sealed.cols = grid.cols
	sealed.rows = grid.rows
	sealed.cell_m = grid.cell_m
	sealed.closed = grid.closed.duplicate()
	sealed.water = grid.water.duplicate()
	sealed.closed.fill(1)
	MarchPath.use(repo, sealed)
	var blocked := EnemyAi.spawn_body_candidate(repo, source, host.host_code, "placement:first-host", "0")
	assert_eq(blocked.status, "deferred", blocked.reason)
	assert_true(blocked.reason.begins_with("space_unavailable"))
	assert_eq(source.to_dict(), before)
	assert_true(grid.closed == pristine_closed, "SuiteData's shared terrain must remain pristine for later scripts")

func test_battle_reservations_and_duplicate_owner() -> void:
	if not _available(): return
	var f := _fixture(901)
	var first := _call(f, _request())
	if first.candidate == null: return
	f.state = first.candidate
	var entry: Dictionary = f.state.regiments[f.code]
	var rows: Array = entry.body_groups
	entry.erase("body_groups")
	f.state.battles = [{"id": 1, "att": [f.code], "def": [], "groups": {f.code: rows},
		"group_facing": {f.code: 0}, "group_anchor_m": {f.code: [50000, 50000]},
		"body_version": 1, "group_size_version": 2, "group_size_men": 100}]
	var result := _call(f, _request("initialize", "", "1"))
	if result.candidate != null:
		assert_eq(UnitBodies.rows(f.repo, result.candidate, f.code), rows)
		assert_false(result.candidate.regiments[f.code].has("body_groups"))
	f.state.foes[f.code] = entry.duplicate(true)
	_call(f, _request("initialize", "", "1"), "error")

func test_source_file_and_detached_plan_do_not_alias() -> void:
	if not _available(): return
	var f := _fixture(100)
	var bytes := JSON.stringify(f.state.to_dict()).to_utf8_buffer()
	var path := "user://cf04br-placement-source-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var before: Dictionary = f.state.to_dict()
	var result := _call(f, _request())
	assert_eq(FileAccess.get_file_as_bytes(path), bytes)
	if result.candidate != null:
		var candidate_before: Dictionary = result.candidate.to_dict()
		result.plan.effects.entries[f.code].body_groups[0].path_m[0][0] += 100
		assert_eq(result.candidate.to_dict(), candidate_before)
		result.candidate.regiments[f.code].body_groups[0].path_m[0][0] += 100
		assert_eq(f.state.to_dict(), before)
	assert_eq(FileAccess.get_file_as_bytes(path), bytes)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_closed_requests_boundaries_and_sequence_overflow() -> void:
	if not _available(): return
	var f := _fixture(1)
	for value: Variant in [true, 1.5, 2, "1", null]:
		var request := _request()
		request.version = value
		_call(f, request, "error")
	for change: Dictionary in [{"extra": 1}, {"operation": "unknown"}, {"unit": "invented"}, {"previous_fit": "0"}, {"host": "invented"}, {"anchor_m": [0, 0]}]:
		var request := _request()
		request.merge(change, true)
		_call(f, request, "error")
	for change: Dictionary in [{"version": true}, {"version": 2}, {"version": 1.5}, {"abs_day": true}, {"abs_day": 1}, {"abs_day": "01"}, {"abs_day": "999"}, {"kind": "unknown"}, {"kind": "march_complete"}, {"receipt": "a".repeat(64)}]:
		var boundary := _boundary(f.state)
		boundary.merge(change, true)
		var before: Dictionary = f.state.to_dict()
		var result := ArmyGround.body_placement_candidate(f.repo, f.state, _request(), boundary)
		assert_eq(result.status, "error", str(change))
		assert_eq(f.state.to_dict(), before)
	var first := _call(f, _request())
	if first.candidate == null: return
	f.state = first.candidate
	_call(f, _request("initialize", "", "2"), "error")
	var request := _request("initialize", "", "1")
	request.operation_id = "placement:test:0"
	_call(f, request, "error")
	f.state.military_migration.body_placement.sequence = "9223372036854775807"
	_call(f, _request("initialize", "", "1"), "error")

func test_initialize_missing_staged_entry_requires_actual_provenance() -> void:
	if not _available(): return
	var f := _fixture(1)
	var px := ArmySystem.metres_to_pack(f.repo, Vector2i(50000, 50000))
	f.state.army_roster[f.code].x = px.x
	f.state.army_roster[f.code].y = px.y
	f.state.regiments = {}
	var people: Dictionary = f.state.military_cohorts.duplicate(true)
	var result := _call(f, _request())
	if result.candidate != null:
		assert_eq(UnitBodies.rows(f.repo, result.candidate, f.code).size(), 1, "a staged real roster unit must not be silently omitted")
		assert_eq(result.candidate.military_cohorts, people)
	f.state.military_migration.body_version = 1
	_call(f, _request(), "error")

func test_review_r1_recruit_validates_raw_boundary_before_frozen_deferral() -> void:
	var f := _fixture(900)
	var initial := _call(f, _request())
	if initial.candidate == null: return
	f.state = initial.candidate
	assert_false(Personnel.move(f.repo, f.state, f.code, "fit", "wounded", 1).has("error"))
	var request := _request("recruit", f.code, "1")
	request.previous_fit = "900"
	var planned := ArmyGround.plan_body_placement_candidate(f.repo, f.state, request, _boundary(f.state))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.status != "complete": return
	var api: GDScript = load("res://scripts/engine/army_ground.gd")
	for change: Dictionary in [{}, {"tx": {"protocol_version": true}}, {"tx": {"protocol_version": 99}},
		{"boundary": {"version": true}}, {"boundary": {"extra": 1}}, {"boundary": {"abs_day": 1.5}}]:
		var frozen := UnitBodies._copy(f.state)
		frozen.day_resolution = DayResolution.begin(frozen.day, false, frozen.absolute_day())
		frozen.day_resolution.merge(change.get("tx", {}), true)
		var boundary := _boundary(frozen)
		boundary.merge(change.get("boundary", {}), true)
		var proposed: Dictionary = planned.plan.duplicate(true)
		proposed.boundary = boundary.duplicate(true)
		var before := frozen.to_dict()
		for method: String in ["plan_body_placement_candidate", "body_placement_candidate", "commit_body_placement_candidate"]:
			var result: Dictionary = api.call(method, f.repo, frozen,
				proposed if method == "commit_body_placement_candidate" else request, boundary)
			assert_eq(result.status, "deferred" if change.is_empty() else "error", method + str(change))
			assert_null(result.candidate)
			assert_eq(result.plan, {})
			assert_eq(result.error, "" if change.is_empty() else result.reason)
			assert_eq(frozen.to_dict(), before, "frozen payload, nested rows, personnel and RNG stay exact")

func test_review_r2_staged_personnel_references_are_unique_and_owned() -> void:
	for operation: String in ["initialize", "recruit"]:
		for issue: String in ["duplicate", "owner"]:
			var f := _fixture(1)
			if operation == "recruit":
				var initial := _call(f, _request())
				if initial.candidate == null: continue
				f.state = initial.candidate
			else:
				var px := ArmySystem.metres_to_pack(f.repo, Vector2i(50000, 50000))
				f.state.army_roster[f.code].x = px.x
				f.state.army_roster[f.code].y = px.y
				f.state.regiments = {}
			_corrupt_personnel_reference(f.state, f.code, issue)
			var request := _request(operation, f.code if operation == "recruit" else "", "1" if operation == "recruit" else "0")
			if operation == "recruit": request.previous_fit = "1"
			_call(f, request, "error")
	var repo := SuiteData.repo()
	var original := SuiteData.campaign(repo, 319)
	var host: Dictionary = repo.raid_hosts[0]
	var units := EnemyAi.host_units(repo, original, host)
	var source := UnitBodies._copy(original)
	source.regiments = {}
	source.foes = {}
	source.ai_hosts = {}
	source.battles = []
	source.town_seat = {}
	source.army_roster = {}
	source.military_rosters = {}
	for code: String in units:
		source.regiments[code] = UnitBodies._entry(original, code).duplicate(true)
		source.army_roster[code] = original.army_roster[code].duplicate(true)
		source.military_rosters[code] = original.military_rosters[code].duplicate(true)
	for key: String in ["body_version", "body_placement", "body_motion"]: source.military_migration.erase(key)
	var code: String = units[0]
	assert_false(Personnel.replace(repo, source, code, 1).has("error"))
	for issue: String in ["duplicate", "owner"]:
		var invalid := UnitBodies._copy(source)
		_corrupt_personnel_reference(invalid, code, issue)
		var before := invalid.to_dict()
		var result := EnemyAi.spawn_body_candidate(repo, invalid, host.host_code, "placement:bad-host-reference", "0")
		assert_eq(result.status, "error", issue)
		assert_null(result.candidate)
		assert_eq(invalid.to_dict(), before)

func _corrupt_personnel_reference(state: GameState, code: String, issue: String) -> void:
	for id: String in state.military_rosters[code].cohort_ids.duplicate():
		if int(state.military_cohorts[id].fit) <= 0: continue
		if issue == "duplicate": state.military_rosters[code].cohort_ids.append(id)
		else: state.military_cohorts[id].unit_code = "unknown-reference-owner"
		return
	fail_test("fixture requires a real active fit cohort")

func test_v2_completed_metadata_preserves_receipts() -> void:
	var f := _fixture(100)
	var initialized := _call(f, _request())
	if initialized.candidate == null: return
	f.state = initialized.candidate
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
		"turn_q": 400000, "contact_um": 100, "radius_m": int(f.repo.unit_footprints[piece].radius_m),
		"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
	f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
	f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	var engine := TickEngine.new(f.repo)
	var begun := engine.begin_locomotion_march_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	if begun.candidate == null: return
	var state: GameState = begun.candidate
	for i: int in int(state.day_resolution.body_march.substep_count):
		var stepped := engine.step_locomotion_march_candidate(state)
		assert_eq(stepped.status, "complete", stepped.reason)
		if stepped.candidate == null: return
		state = stepped.candidate
	var boundary := {"version": 2, "kind": "march_complete", "abs_day": str(state.absolute_day()),
		"receipt": state.day_resolution.body_march.last.receipt}
	assert_eq(ArmySystem._body_source_error(f.repo, state, 2), "")
	var changed := UnitBodies._copy(state)
	changed.military_migration.body_placement.sequence = "1"
	assert_eq(ArmySystem._body_source_error(f.repo, changed, 2), "Stale locomotion march state/context", "placement receipt itself changes the frozen result basis")
	var before := state.to_dict()
	var request := _request("leave", f.code, "1")
	var planned := ArmyGround.plan_body_placement_candidate(f.repo, state, request, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	assert_eq(state.to_dict(), before)
	if planned.status != "complete": return
	var committed := ArmyGround.commit_body_placement_candidate(f.repo, state, planned.plan, boundary)
	assert_eq(committed.status, "complete", committed.reason)
	if committed.candidate == null: return
	assert_eq(committed.candidate.day_resolution, state.day_resolution)
	assert_eq(committed.candidate.military_migration.body_motion, state.military_migration.body_motion)
	assert_eq(UnitBodies.rows(f.repo, committed.candidate, f.code), UnitBodies.rows(f.repo, state, f.code))
	assert_eq(committed.candidate.rng.to_dict(), state.rng.to_dict())
	assert_eq(committed.candidate.regiments[f.code].supplies, state.regiments[f.code].supplies)
	for saved: GameState in [committed.candidate, GameState.from_dict(JSON.parse_string(JSON.stringify(committed.candidate.to_dict())))]:
		var retry := ArmyGround.commit_body_placement_candidate(f.repo, saved, planned.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(retry.candidate.to_dict(), saved.to_dict())

func _completion_fixture(imported: bool = false, previous_sequence: String = "0", town_offset_m: int = 0) -> Dictionary:
	var f := _fixture(100)
	if imported:
		var legacy: Dictionary = f.state.to_dict()
		legacy.erase("military_migration")
		legacy.military_organization_version = 1
		legacy.military_migration_pending = false
		legacy.military_unit_aliases = {}
		legacy.military_conflicts = []
		for field: String in ["military_rosters", "military_cohorts", "military_events"]:
			legacy[field] = GameState._encode_values(f.state.get(field))
		f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(legacy)), false)
	var initialized := _call(f, _request())
	if initialized.candidate == null: return {}
	f.state = initialized.candidate
	f.state.military_migration.body_placement.sequence = previous_sequence
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64), "turn_q": 400000,
		"contact_um": 100, "radius_m": int(f.repo.unit_footprints[piece].radius_m),
		"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
	f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
	f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	var town := ""
	for code: String in f.repo.burgs:
		if ArmyGround.holds(f.repo, f.state, f.state.army_roster[f.code].kingdom_code, code):
			town = code
			break
	assert_ne(town, "")
	var px := ArmySystem.metres_to_pack(f.repo, Vector2i(50000 + town_offset_m, 50000))
	f.repo.burgs[town].x = px.x
	f.repo.burgs[town].y = px.y
	f.state.regiments[f.code].camp_town = town
	f.state.town_seat[town] = f.code
	var law := ""
	for code: String in f.repo.law_order:
		if f.repo.laws[code].scope == "camp":
			law = code
			break
	assert_ne(law, "")
	f.state.law_in_force[LawSystem.TOWN_PREFIX + town] = {law: {"value": f.repo.laws[law]["default"], "decree_id": 17}}
	f.state.law_in_force.erase(LawSystem.UNIT_PREFIX + f.code)
	ArmySystem.forget_grids()
	f.town = town
	f.law = law
	var tables := {}
	for property: Dictionary in f.repo.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: tables[property.name] = f.repo.get(property.name)
	var input := {"source": f.state.to_dict(), "tables": tables,
		"grid": [f.grid.cols, f.grid.rows, f.grid.cell_m, f.grid.closed, f.grid.water, f.grid.water_open, f.grid._snap]}.duplicate(true)
	var key := str([imported, previous_sequence, town_offset_m])
	# Cache only real completed fixture marches; every tested placement entrance still runs.
	if _completion_marches.has(key) and _completion_marches[key].input == input:
		var cached: Dictionary = _completion_marches[key]
		f.repo = SuiteData._copy(cached.repo)
		MarchPath.use(f.repo, f.grid)
		f.state = UnitBodies._copy(cached.state)
		f.incomplete = UnitBodies._copy(cached.incomplete)
		f.boundary = cached.boundary.duplicate(true)
		return f
	var begun := TickEngine.new(f.repo).begin_locomotion_march_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	if begun.candidate == null: return {}
	f.state = begun.candidate
	f.incomplete = UnitBodies._copy(f.state)
	for i: int in int(f.state.day_resolution.body_march.substep_count):
		var step := TickEngine.new(f.repo).step_locomotion_march_candidate(f.state)
		assert_eq(step.status, "complete", step.reason)
		if step.candidate == null: return {}
		f.state = step.candidate
	f.boundary = {"version": 2, "kind": "march_complete", "abs_day": str(f.state.absolute_day()), "receipt": f.state.day_resolution.body_march.last.receipt}
	_completion_marches[key] = {"input": input, "repo": SuiteData._copy(f.repo), "state": UnitBodies._copy(f.state),
		"incomplete": UnitBodies._copy(f.incomplete), "boundary": f.boundary.duplicate(true)}
	return f

func _completion_operation(f: Dictionary, operation: String = "leave", sequence: String = "1") -> Dictionary:
	var unit: String = "" if operation == "reconcile" else (f.town if operation == "refill" else f.code)
	var request := _request(operation, unit, sequence)
	var before: Dictionary = f.state.to_dict()
	var result := ArmyGround.body_placement_candidate(f.repo, f.state, request, f.boundary)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(f.state.to_dict(), before)
	return result

func _completion_reject(f: Dictionary, source: GameState, boundary: Dictionary = {}) -> void:
	var wire: Dictionary = f.boundary if boundary.is_empty() else boundary
	var before := source.to_dict()
	var result := UnitBodies.validate_placement_candidate(f.repo, source, wire)
	assert_eq(result.status, "error", result.reason)
	assert_null(result.candidate)
	assert_eq(source.to_dict(), before)

func _completion_set_proof(source: GameState, proof: Dictionary) -> void:
	source.military_migration.body_placement.completion_json = UnitBodies._placement_json(proof)

func test_completion_fixture_cache_matches_cold_march_and_is_detached() -> void:
	_completion_marches.clear()
	SuiteData.campaign(SuiteData.repo(), 319)
	for imported: bool in [false, true]:
		var cold := _completion_fixture(imported)
		var first := _completion_fixture(imported)
		var cached := _completion_fixture(imported)
		assert_eq(UnitBodies._placement_json(cached.state.to_dict()), UnitBodies._placement_json(cold.state.to_dict()))
		assert_eq(cached.incomplete.to_dict(), cold.incomplete.to_dict())
		assert_eq(cached.boundary, cold.boundary)
		assert_false(is_same(first.state, cached.state))
		assert_false(is_same(first.state.rng, cached.state.rng))
		assert_false(is_same(first.repo, cached.repo))
		assert_false(is_same(first.grid, cached.grid))
		var before: Dictionary = cold.state.to_dict()
		var tables_before := SuiteData._copy(cold.repo)
		var expected := _completion_operation(cold)
		var actual := _completion_operation(cached)
		assert_eq(UnitBodies._placement_json(actual.candidate.to_dict()), UnitBodies._placement_json(expected.candidate.to_dict()))
		assert_eq(actual.plan, expected.plan)
		first.state.regiments[first.code].body_groups.clear()
		first.state.military_rosters[first.code].cohort_ids.clear()
		first.incomplete.day_resolution.clear()
		first.boundary.clear()
		first.repo.balance.body_locomotion_infantry_turn_q += 1
		first.grid.closed[0] = 1
		actual.candidate.military_migration.body_placement.completion_json = "corrupt"
		actual.plan.effects.entries.clear()
		var restored := _completion_fixture(imported)
		assert_eq(restored.state.to_dict(), before)
		assert_eq(restored.incomplete.to_dict(), cold.incomplete.to_dict())
		assert_eq(restored.boundary, cold.boundary)
		for property: Dictionary in tables_before.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				assert_eq(restored.repo.get(property.name), tables_before.get(property.name), str(property.name))
		assert_eq(restored.grid.closed, cold.grid.closed)
		assert_eq(cached.state.to_dict(), before)
		assert_eq(UnitBodies.validate_placement_candidate(cold.repo, expected.candidate, cold.boundary).status, "complete")

func test_v2_completion_proof_first_commit_and_full_endpoint() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var before: Dictionary = f.state.to_dict()
	var result := _completion_operation(f)
	if result.candidate == null: return
	var endpoint: GameState = result.candidate
	var proof := UnitBodies._placement_proof(endpoint.military_migration.body_placement.completion_json)
	assert_eq(UnitBodies._placement_json(proof.origin), UnitBodies._placement_json(before))
	assert_eq(proof.plans.size(), 1)
	assert_eq(result.plan.placements, [])
	assert_eq(endpoint.regiments[f.code].camp_town, "")
	assert_false(endpoint.town_seat.has(f.town))
	assert_eq(endpoint.law_in_force[LawSystem.UNIT_PREFIX + f.code][f.law].decree_id, 17)
	assert_eq(endpoint.military_migration.body_placement.version, "2")
	assert_eq(endpoint.military_migration.body_placement.sequence, "1")
	assert_eq(endpoint.military_migration.body_placement.operation_id, "placement:test:1")
	assert_eq(endpoint.military_migration.body_placement.receipt, BodyMotion._hash(result.plan))
	assert_eq(UnitBodies._placement_json(proof.plans[0]), UnitBodies._placement_json(result.plan))
	# Hand accounting: one inherited unit law, cleared camp/seat, one receipt; nothing else.
	var expected := UnitBodies._copy(f.state)
	expected.regiments[f.code].camp_town = ""
	expected.town_seat.erase(f.town)
	expected.law_in_force[LawSystem.UNIT_PREFIX + f.code] = f.state.law_in_force[LawSystem.TOWN_PREFIX + f.town].duplicate(true)
	expected.military_migration.body_placement = endpoint.military_migration.body_placement.duplicate(true)
	assert_eq(UnitBodies._placement_json(endpoint.to_dict()), UnitBodies._placement_json(expected.to_dict()))
	assert_eq(endpoint.day_resolution, f.state.day_resolution)
	assert_eq(endpoint.military_migration.body_motion, f.state.military_migration.body_motion)
	assert_eq(endpoint.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(UnitBodies.validate_placement_candidate(f.repo, endpoint, f.boundary).status, "complete")

func test_v2_completion_proof_latest_retry_direct_and_whole_json() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var result := _completion_operation(f)
	if result.candidate == null: return
	for source: GameState in [result.candidate, GameState.from_dict(JSON.parse_string(JSON.stringify(result.candidate.to_dict())), false)]:
		var before := source.to_dict()
		var retry := ArmyGround.commit_body_placement_candidate(f.repo, source, JSON.parse_string(JSON.stringify(result.plan)), f.boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(retry.candidate.to_dict(), before)
		assert_eq(source.to_dict(), before)
		var convenience := ArmyGround.body_placement_candidate(f.repo, source, result.plan.request, f.boundary)
		assert_eq(convenience.status, "error")
		assert_eq(convenience.reason, "retry_requires_original_plan")
		var changed: Dictionary = result.plan.duplicate(true)
		changed.effects.seats[f.town] = f.code
		assert_eq(ArmyGround.commit_body_placement_candidate(f.repo, source, changed, f.boundary).status, "error")

func test_v2_completion_proof_multiple_metadata_operations_and_law_once() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var origin: GameState = f.state
	var previous_basis := ""
	for i: int in 6:
		var op: String = ["leave", "settle", "take_seat", "refill", "reconcile", "leave"][i]
		var result := _completion_operation(f, op, str(i + 1))
		if result.candidate == null: return
		assert_ne(result.plan.basis, previous_basis)
		previous_basis = result.plan.basis
		f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(result.candidate.to_dict())), false)
		var proof := UnitBodies._placement_proof(f.state.military_migration.body_placement.completion_json)
		assert_eq(proof.plans.size(), i + 1)
		assert_eq(UnitBodies._placement_json(proof.origin), UnitBodies._placement_json(origin.to_dict()))
		assert_eq(f.state.law_in_force[LawSystem.UNIT_PREFIX + f.code][f.law].decree_id, 17)
		assert_eq(f.state.day_resolution, origin.day_resolution)
		assert_eq(f.state.military_events, origin.military_events)
		assert_eq(f.state.metrics, origin.metrics)
		assert_eq(f.state.rng.to_dict(), origin.rng.to_dict())
		assert_eq(f.state.regiments[f.code].supplies, origin.regiments[f.code].supplies)
		assert_eq(UnitBodies.rows(f.repo, f.state, f.code), UnitBodies.rows(f.repo, origin, f.code))
	var reused := _request("leave", f.code, "7")
	reused.operation_id = "placement:test:1"
	assert_eq(ArmyGround.body_placement_candidate(f.repo, f.state, reused, f.boundary).status, "error")

func test_v2_completion_proof_canonical_string_both_provenance_branches() -> void:
	for imported: bool in [false, true]:
		var f := _completion_fixture(imported)
		if f.is_empty(): continue
		var result := _completion_operation(f)
		if result.candidate == null: continue
		var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(result.candidate.to_dict())), false)
		assert_eq(loaded.military_migration.has("import_main_v7"), imported)
		assert_eq(UnitBodies._placement_json(loaded.to_dict()), UnitBodies._placement_json(result.candidate.to_dict()))
		assert_eq(loaded.military_migration.body_placement.completion_json, result.candidate.military_migration.body_placement.completion_json)
		assert_eq(UnitBodies.validate_placement_candidate(f.repo, loaded, f.boundary).status, "complete")
		var retry := ArmyGround.commit_body_placement_candidate(f.repo, loaded, JSON.parse_string(JSON.stringify(result.plan)), f.boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(retry.candidate.to_dict(), loaded.to_dict())
		var text: String = loaded.military_migration.body_placement.completion_json
		for raw: String in [text.insert(1, " "), text.insert(text.length() - 1, ',"version":1'), text.left(text.length() - 2) + "1e0}", "{broken", "null"]:
			var bad := UnitBodies._copy(loaded)
			bad.military_migration.body_placement.completion_json = raw
			_completion_reject(f, bad)
		for raw: Variant in [1.5, "1", "i1", "f3ff0000000000000", 1e100]:
			var bad := UnitBodies._copy(loaded)
			var proof := UnitBodies._placement_proof(text)
			proof.plans[0].request.version = raw
			_completion_set_proof(bad, proof)
			var frozen: String = bad.military_migration.body_placement.completion_json
			var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(bad.to_dict())), false)
			assert_eq(restored.military_migration.body_placement.completion_json, frozen)
			_completion_reject(f, restored)

func test_v2_completion_proof_rejects_fractional_missing_unknown_corrupt_raw() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var result := _completion_operation(f)
	if result.candidate == null: return
	var valid := UnitBodies._placement_proof(result.candidate.military_migration.body_placement.completion_json)
	for field: String in ["version", "origin", "plans", "unknown", "fraction", "numeric_string", "unsafe", "bad_origin", "bad_rng", "bad_courier"]:
		var proof := valid.duplicate(true)
		match field:
			"version", "origin", "plans": proof.erase(field)
			"unknown": proof.unknown = true
			"fraction": proof.plans[0].request.version = 1.5
			"numeric_string": proof.plans[0].request.version = "1"
			"unsafe": proof.origin.army_task_next_id = 9007199254740992
			"bad_origin": proof.origin.erase("metrics")
			"bad_rng": proof.origin.rng = {}
			"bad_courier": proof.origin.couriers = [false]
		var bad := UnitBodies._copy(result.candidate)
		_completion_set_proof(bad, proof)
		for source: GameState in [bad, GameState.from_dict(JSON.parse_string(JSON.stringify(bad.to_dict())), false)]:
			_completion_reject(f, source)
	for field: String in ["version", "sequence", "operation_id", "receipt", "completion_json"]:
		for raw: Variant in [null, true, 2.5, 2, {}, ""]:
			var bad := UnitBodies._copy(result.candidate)
			bad.military_migration.body_placement[field] = raw
			_completion_reject(f, bad)

func test_v2_completion_proof_rejects_rehashed_effects_and_changed_basis() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var result := _completion_operation(f)
	if result.candidate == null: return
	for field: String in ["effects", "basis", "receipt", "day", "law", "policy", "terrain"]:
		var bad := UnitBodies._copy(result.candidate)
		var proof := UnitBodies._placement_proof(bad.military_migration.body_placement.completion_json)
		match field:
			"effects": proof.plans[0].effects.seats[f.town] = f.code
			"basis": proof.plans[0].basis = "b".repeat(64)
			"receipt": proof.plans[0].boundary.receipt = "b".repeat(64)
			"day": proof.plans[0].boundary.abs_day = str(bad.absolute_day() + 1)
			"law": f.repo.laws[f.law].scope = "province"
			"policy": f.repo.balance.body_locomotion_infantry_turn_q += 1
			"terrain": f.grid.closed[0] = 1
		_completion_set_proof(bad, proof)
		bad.military_migration.body_placement.receipt = BodyMotion._hash(proof.plans[0])
		_completion_reject(f, bad)
		if field == "law": f.repo.laws[f.law].scope = "camp"
		if field == "policy": f.repo.balance.body_locomotion_infantry_turn_q -= 1
		if field == "terrain": f.grid.closed[0] = 0

func test_v2_completion_proof_rejects_tampered_origin_and_prefix() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var first := _completion_operation(f)
	if first.candidate == null: return
	f.state = first.candidate
	var second := _completion_operation(f, "settle", "2")
	if second.candidate == null: return
	var valid := UnitBodies._placement_proof(second.candidate.military_migration.body_placement.completion_json)
	for field: String in ["origin_supply", "origin_fraction", "origin_body", "origin_result", "origin_control", "origin_unknown", "prefix", "nested"]:
		var proof := valid.duplicate(true)
		match field:
			"origin_supply": proof.origin.regiments[f.code].supplies = "i1"
			"origin_fraction": proof.origin.military_cohorts.values()[0].fit = 0.5
			"origin_body": proof.origin.regiments[f.code].body_groups = []
			"origin_result": proof.origin.day_resolution.body_march.last.erase("result")
			"origin_control": proof.origin.day_resolution.body_march = null
			"origin_unknown": proof.origin.unknown = true
			"prefix": proof.plans.pop_front()
			"nested": proof.origin.military_migration.body_placement = first.candidate.military_migration.body_placement
		var bad := UnitBodies._copy(second.candidate)
		_completion_set_proof(bad, proof)
		_completion_reject(f, bad)
	for field: String in ["supply", "facing", "rng", "treasury", "law", "journal", "sequence", "inner", "outer"]:
		var bad := UnitBodies._copy(second.candidate)
		match field:
			"supply": bad.regiments[f.code].supplies += 1
			"facing": bad.regiments[f.code].body_groups[0].facing_deg += 1
			"rng": bad.rng.randi_range(1, 10)
			"treasury": bad.metrics.treasury += 1
			"law": bad.law_in_force[LawSystem.UNIT_PREFIX + f.code][f.law].decree_id += 1
			"journal": bad.day_resolution.journal.arrivals.append(f.code)
			"sequence": bad.military_migration.body_placement.sequence = "3"
			"inner": bad.military_migration.body_motion.receipt = "b".repeat(64)
			"outer": bad.day_resolution.body_march.last.result = "b".repeat(64)
		_completion_reject(f, bad)

func test_v2_completion_proof_sequence_overflow_and_old_retry() -> void:
	var f := _completion_fixture(false, "9223372036854775806")
	if f.is_empty(): return
	var result := _completion_operation(f, "leave", "9223372036854775807")
	if result.candidate == null: return
	var exact := ArmyGround.commit_body_placement_candidate(f.repo, result.candidate, result.plan, f.boundary)
	assert_eq(exact.status, "complete", exact.reason)
	var next := _request("leave", f.code, "0")
	assert_eq(ArmyGround.body_placement_candidate(f.repo, result.candidate, next, f.boundary).status, "error")
	f = _completion_fixture()
	if f.is_empty(): return
	var first := _completion_operation(f)
	if first.candidate == null: return
	f.state = first.candidate
	var second := _completion_operation(f, "settle", "2")
	if second.candidate == null: return
	assert_eq(ArmyGround.commit_body_placement_candidate(f.repo, second.candidate, first.plan, f.boundary).status, "error")

func test_v2_completion_proof_strict_march_consumers_and_new_day_refusal() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	var result := _completion_operation(f)
	if result.candidate == null: return
	var source: GameState = result.candidate
	var before := source.to_dict()
	assert_eq(ArmySystem.plan_locomotion_march_candidate(f.repo, source).status, "error")
	assert_eq(TickEngine.new(f.repo).step_locomotion_march_candidate(source).status, "error")
	assert_eq(TickEngine.new(f.repo).begin_locomotion_march_candidate(source).status, "error")
	assert_eq(BodyMotion.plan_locomotion_candidate(f.repo, source, [], source.absolute_day(), 0).cursor, {})
	var boundary := ArmySystem._body_boundary(source)
	assert_eq(BodyMotion.plan_locomotion_candidate(f.repo, source, [], source.absolute_day(), int(boundary.substep), boundary).cursor, {})
	var inner: Dictionary = source.military_migration.body_motion.plan
	assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, source, inner, inner.cursor.boundary).status, "error")
	assert_eq(source.to_dict(), before)
	var bad := UnitBodies._copy(source)
	bad.day_resolution = {}
	assert_eq(UnitBodies.validate_placement_candidate(f.repo, bad, _boundary(bad)).status, "error")
	bad.day += 1
	assert_eq(TickEngine.new(f.repo).begin_locomotion_march_candidate(bad).status, "error")
	assert_eq(TickEngine.new(f.repo).begin_body_march_candidate(bad).status, "error")
	bad = UnitBodies._copy(source)
	bad.day += 1
	_completion_reject(f, bad)

func test_v2_completion_proof_v1_and_safe_controls_unchanged() -> void:
	var f := _completion_fixture()
	if f.is_empty(): return
	assert_eq(UnitBodies.validate_placement_candidate(f.repo, f.state, _boundary(f.state)).status, "deferred")
	var partial: GameState = f.incomplete
	var boundary: Dictionary = f.boundary.duplicate(true)
	assert_eq(UnitBodies.validate_placement_candidate(f.repo, partial, boundary).status, "deferred")
	for version: Variant in [1, 3, true, "2", 2.5]:
		boundary = f.boundary.duplicate(true)
		boundary.version = version
		_completion_reject(f, f.state, boundary)
	for operation: String in ["initialize", "legacy_missing", "recruit", "enemy_spawn"]:
		var request := _request(operation, f.code if operation == "recruit" else "", "1")
		if operation == "recruit": request.previous_fit = "100"
		if operation == "enemy_spawn": request.host = f.repo.raid_hosts[0].host_code
		var result := ArmyGround.body_placement_candidate(f.repo, f.state, request, f.boundary)
		assert_eq(result.status, "deferred", result.reason)
		assert_null(result.candidate)
	var before: Dictionary = f.state.to_dict()
	f.state.regiments[f.code].erase("body_groups")
	_completion_reject(f, f.state)
	assert_false(f.state.regiments[f.code].has("body_groups"), "no missing-row initialization")
	assert_eq(f.state.day_resolution, GameState._decode_values(before.day_resolution))

func test_v2_completion_travel_refuses_without_publication_and_raw_precedes_deferral() -> void:
	var f := _completion_fixture(false, "0", 200)
	if f.is_empty(): return
	var before: Dictionary = f.state.to_dict()
	var result := ArmyGround.body_placement_candidate(f.repo, f.state, _request("take_seat", f.code, "1"), f.boundary)
	assert_eq(result.status, "deferred", result.reason)
	assert_true(result.reason.begins_with("requires_motion"))
	assert_null(result.candidate)
	assert_eq(f.state.to_dict(), before)
	var bad: GameState = UnitBodies._copy(f.incomplete)
	bad.military_migration.body_motion = {"version": "3"}
	_completion_reject(f, bad)

func test_v2_completion_proof_rejects_nested_origin_rosters_before_consumers() -> void:
	for imported: bool in [false, true]:
		var f := _completion_fixture(imported)
		if f.is_empty(): continue
		var committed := _completion_operation(f)
		if committed.candidate == null: continue
		var endpoint: GameState = committed.candidate
		assert_eq(UnitBodies.validate_placement_candidate(f.repo, endpoint, f.boundary).status, "complete")
		var cohort: String = endpoint.military_rosters[f.code].cohort_ids[0]
		var changes: Array[Dictionary] = []
		for table: String in ["army_roster", "military_rosters", "military_cohorts"]:
			for value: Variant in [null, 1, [], {}]:
				changes.append({"table": table, "key": cohort if table == "military_cohorts" else f.code, "field": "", "value": value})
		for value: Variant in [null, 1, {}, [null], [cohort, cohort], ["missing-cohort"]]:
			changes.append({"table": "military_rosters", "key": f.code, "field": "cohort_ids", "value": value})
		changes.append({"table": "military_cohorts", "key": cohort, "field": "unit_code", "value": "other-unit"})
		changes.append({"table": "army_roster", "key": f.code, "field": "infantry", "value": []})
		for change: Dictionary in changes:
			var bad := UnitBodies._copy(endpoint)
			var proof := UnitBodies._placement_proof(bad.military_migration.body_placement.completion_json)
			if change.field == "": proof.origin[change.table][change.key] = change.value
			else: proof.origin[change.table][change.key][change.field] = change.value
			_completion_set_proof(bad, proof)
			var frozen: String = bad.military_migration.body_placement.completion_json
			for source: GameState in [bad, GameState.from_dict(JSON.parse_string(JSON.stringify(bad.to_dict())), false)]:
				assert_eq(source.military_migration.body_placement.completion_json, frozen, "outer save codecs must preserve malformed nested proof")
				assert_eq(UnitBodies._placement_personnel_error(source, f.code), "", "actual endpoint roster remains valid; only origin is corrupted")
				var before := source.to_dict()
				var result := UnitBodies.validate_placement_candidate(f.repo, source, f.boundary)
				assert_eq(result.get("status"), "error", str(change))
				assert_eq(result.size(), 5)
				assert_null(result.get("candidate"))
				assert_false(str(result.get("reason", "")).is_empty())
				assert_eq(source.to_dict(), before)
				assert_eq(source.rng.to_dict(), before.rng)
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(endpoint.to_dict())), false)
		assert_eq(UnitBodies.validate_placement_candidate(f.repo, restored, f.boundary).status, "complete", "legal origin survives both provenance branches")

func test_v2_completion_proof_rejects_raw_frozen_inputs_before_consumers() -> void:
	for imported: bool in [false, true]:
		var f := _completion_fixture(imported)
		if f.is_empty(): continue
		var committed := _completion_operation(f)
		if committed.candidate == null: continue
		var endpoint: GameState = committed.candidate
		assert_eq(UnitBodies.validate_placement_candidate(f.repo, endpoint, f.boundary).status, "complete")
		var changes: Array[Dictionary] = []
		for value: Variant in [null, 1, [], {}, "prepare"]:
			changes.append({"path": ["day_resolution", "phase"], "value": value})
		for path: Array in [["day_resolution", "body_march"], ["day_resolution", "pending_decision"],
			["military_migration", "body_motion"],
			["military_migration", "body_version"], ["regiments", f.code],
			["regiments", f.code, "body_groups"], ["regiments", f.code, "camp_state"],
			["regiments", f.code, "camp_town"], ["tick"], ["day"]]:
			changes.append({"path": path, "value": []})
		changes.append({"path": ["day_resolution", "marching_codes"], "value": {}})
		changes.append({"path": ["foes"], "value": {"unexpected": null}})
		changes.append({"path": ["battles"], "value": [null]})
		for change: Dictionary in changes:
			var bad := UnitBodies._copy(endpoint)
			var proof := UnitBodies._placement_proof(bad.military_migration.body_placement.completion_json)
			var parent: Dictionary = proof.origin
			for index: int in range(change.path.size() - 1): parent = parent[change.path[index]]
			assert_ne(UnitBodies._placement_json(parent.get(change.path[-1])), UnitBodies._placement_json(change.value), "negative case must change origin")
			parent[change.path[-1]] = change.value
			_completion_set_proof(bad, proof)
			var frozen: String = bad.military_migration.body_placement.completion_json
			for source: GameState in [bad, GameState.from_dict(JSON.parse_string(JSON.stringify(bad.to_dict())), false)]:
				assert_eq(source.military_migration.body_placement.completion_json, frozen)
				assert_eq(source.day_resolution, endpoint.day_resolution, "actual frozen day remains valid")
				var before := source.to_dict()
				var result := UnitBodies.validate_placement_candidate(f.repo, source, f.boundary)
				assert_eq(result.get("status"), "error", str(change))
				assert_eq(result.size(), 5)
				assert_null(result.get("candidate"))
				assert_false(str(result.get("reason", "")).is_empty())
				assert_eq(source.to_dict(), before)
				assert_eq(source.rng.to_dict(), before.rng)
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(endpoint.to_dict())), false)
		assert_eq(UnitBodies.validate_placement_candidate(f.repo, restored, f.boundary).status, "complete")
