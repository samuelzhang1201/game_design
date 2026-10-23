extends GutTest


func test_root_shot_frames_wait_for_overlay_startup() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	var root := GameRoot.new()
	autofree(shot)
	autofree(root)
	shot._root = root
	shot._process(0.016)
	assert_eq(shot._frames, 0, "startup must not consume scheduled input or capture frames")
	root._report_popup = MissiveReportPopup.new()
	root._report_popup.visible = false
	root.add_child(root._report_popup)
	root._overlays_made = true
	shot._process(0.016)
	assert_eq(shot._frames, 1, "the capture sequence begins once overlays exist")


func test_bare_screen_shot_frames_start_without_a_game_root() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	autofree(shot)
	shot._process(0.016)
	assert_eq(shot._frames, 1)

func test_frozen_save_flags_reject_writers_and_missing_values() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	autofree(shot)
	assert_true(shot.has_method("battle_save_options"), "named-save capture has a callable validation boundary")
	if not shot.has_method("battle_save_options"):
		return
	var valid := PackedStringArray(["--screen", "root", "--resolution", "1920x1080", "--still", "--battle-save", "/tmp/input.json"])
	assert_eq(shot.battle_save_options(valid).get("error", ""), "")
	for writer: String in ["--dev", "--quiet", "--battle-case", "--play-days", "--speed", "--bal", "--seed"]:
		var args := valid.duplicate()
		args.append(writer)
		args.append("1")
		assert_ne(shot.battle_save_options(args).get("error", ""), "", writer)
	for missing: String in ["--battle-save", "--group-evidence", "--out", "--at3d", "--zoom3d", "--set"]:
		var args := valid.duplicate()
		args.append(missing)
		assert_ne(shot.battle_save_options(args).get("error", ""), "", missing)
	assert_ne(shot.battle_save_options(PackedStringArray(["--group-evidence", "/tmp/out.json"])).get("error", ""), "")
	assert_ne(shot.battle_save_options(valid + PackedStringArray(["--out", "/tmp/input.json"])).get("error", ""), "")
	assert_ne(shot.battle_save_options(valid + PackedStringArray(["--group-evidence", "/tmp/input.json"])).get("error", ""), "")
	assert_ne(shot.battle_save_options(valid + PackedStringArray(["--set", "Game:state=0"])).get("error", ""), "")
	assert_ne(shot.battle_save_options(valid + PackedStringArray(["--set", "Units:ctx=0"])).get("error", ""), "")

func test_frozen_capture_checks_actual_nodes_and_unchanged_state() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	autofree(shot)
	assert_true(shot.has_method("battle_capture_check"))
	if not shot.has_method("battle_capture_check"):
		return
	var repo := preload("res://tests/suite_data.gd").repo()
	var state := preload("res://tests/suite_data.gd").campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, code, 1)
	state.battles = [{"att": [code], "def": [], "groups": {code: [
		{"count": 1, "role": "front", "x_m": 200, "y_m": 300}]}, "group_facing": {code: 90}}]
	var ctx := Map3DContext.new(repo, {"pack_origin": [-100, 50], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	var piece := Map3DBattleGroups.build(repo, ArmySystem.regiment(repo, code, state), Map3DBattleGroups.sample(ctx, code))
	add_child_autofree(piece["node"])
	Map3DBattleGroups.place(ctx, piece, Vector2.ZERO, 1.6, false)
	var measured := {code: Map3DBattleGroups.evidence(piece)}
	assert_eq(shot.battle_capture_check(ctx, measured, "same", "same").get("error", ""), "")
	assert_ne(shot.battle_capture_check(ctx, measured, "before", "after").get("error", ""), "")
	assert_ne(shot.battle_capture_check(ctx, {}, "same", "same").get("error", ""), "")
	measured[code][0]["xz_world"][0] += 1.0
	assert_ne(shot.battle_capture_check(ctx, measured, "same", "same").get("error", ""), "")
	measured = {code: Map3DBattleGroups.evidence(piece)}
	measured[code][0]["yaw_rad"] += 0.1
	assert_ne(shot.battle_capture_check(ctx, measured, "same", "same").get("error", ""), "")
	state.battles[0]["groups"][code][0]["count"] = 2
	assert_ne(shot.battle_capture_check(ctx, {}, "same", "same").get("error", ""), "")
	state.battles = []
	assert_ne(shot.battle_capture_check(ctx, {}, "same", "same").get("error", ""), "")

func test_invalid_or_legacy_save_is_rejected_before_world_startup() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	autofree(shot)
	assert_true(shot.has_method("battle_capture_source"))
	if not shot.has_method("battle_capture_source"):
		return
	var repo := preload("res://tests/suite_data.gd").repo()
	var state := preload("res://tests/suite_data.gd").campaign(repo, 7)
	var code := String(state.regiments.keys()[0])
	preload("res://tests/engine/personnel_helpers.gd").replace(repo, state, code, 1)
	var ctx := Map3DContext.new(repo, {})
	ctx.state_fn = func() -> GameState: return state
	assert_ne(shot.battle_capture_source(ctx).get("error", ""), "")
	state.battles = [{"att": [code], "def": [], "groups": {code: [
		{"count": 2, "role": "front", "x_m": 200, "y_m": 300}]}, "group_facing": {code: 90}}]
	assert_ne(shot.battle_capture_source(ctx).get("error", ""), "")
	state.battles[0]["groups"][code][0]["count"] = 1
	assert_eq(shot.battle_capture_source(ctx).get("error", ""), "")

func test_frozen_assets_are_loaded_or_fail_before_root_threads() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	autofree(shot)
	assert_true(shot.has_method("battle_capture_warm"))
	if not shot.has_method("battle_capture_warm"):
		return
	assert_ne(shot.battle_capture_warm(["res://missing_frozen_capture_fixture.tres"]), "")
	assert_eq(shot.battle_capture_warm(["res://scenes/map3d/materials/unit_select_glow.tres"]), "")
	assert_gt(shot._held.size(), 0, "retain the loaded dependency until capture teardown")
