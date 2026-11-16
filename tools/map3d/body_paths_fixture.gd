extends SceneTree
## Explicit isolated CF04c window driver. No production clock or state publication.
## Godot --path . -s res://tools/map3d/body_paths_fixture.gd -- --map ID
## --case opposing|crossing|detour|turn|arms --fit 1000 --speed 1 --quality high
## --resolution WxH --zoom near|mid|far --out DIR [--baseline] [--bench] [--pan] [--v2]
## [--follow INDEX] [--every N] [--pivots] (keep the camera on one unit; capture every N frames,
## and every frame that unit pivots)
## Use Godot --write-movie FILE.avi --fixed-fps N for continuous real-window evidence.
## Without --v2 it commits v1 paths (a leg off saved facing is refused and hidden); --v2 commits
## stop/pivot/MARCH locomotion under the installed unit_locomotion.csv policies (CF04c-VISUAL).

const Personnel := preload("res://tests/engine/personnel_helpers.gd")
var _bench_settings: GDScript
var _repo: DataRepository
var _state: GameState
var _view: Control
var _layer: Map3DLayerUnits
var _ctx: Map3DContext
var _codes: Array[String] = []
var _targets: Dictionary = {}
var _envelope: Dictionary = {}
var _share := 0.0
var _speed := 1
var _slice := 0
var _out := ""
var _case := "opposing"
var _baseline := false
var _tier := "high"
var _centre := Vector2i.ZERO
var _frames: Array = []
var _running := false
var _failed := false
var _v2 := false
var _strides: Dictionary = {}  ## unit -> stride in sim metres (v2)

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, fallback: String = "") -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback

func _fail(reason: String) -> void:
	_failed = true
	push_error("CF04c fixture: " + reason)
	quit(2)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("A real 3D window is required")
		return
	_case = _arg("--case", "opposing")
	if _case not in ["opposing", "crossing", "detour", "turn", "arms"]:
		_fail("Unknown --case")
		return
	_out = _arg("--out", "user://body_paths_fixture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_tier = _arg("--quality", "high")
	_repo = Map3DPreview.repo(_arg("--map"))
	if _repo == null or not _tier in Map3DQuality.TIERS:
		_fail("Missing repository or invalid quality")
		return
	Map3DQuality.forced = _tier
	var wh := _arg("--resolution", "2560x1600").split("x")
	if wh.size() != 2 or int(wh[0]) <= 0 or int(wh[1]) <= 0:
		_fail("Invalid resolution")
		return
	var requested_size := Vector2i(int(wh[0]), int(wh[1]))
	if OS.get_cmdline_user_args().has("--bench"):
		# Cocoa otherwise constrains this tier's native client height to the usable desktop.
		root.min_size = requested_size
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(requested_size)
	root.size = requested_size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(_arg("--fps", "0"))
	_speed = int(_arg("--speed", "1"))
	if _speed not in [0, 1, 4]:
		_fail("Speed must be 0, 1 or 4")
		return
	_baseline = OS.get_cmdline_user_args().has("--baseline")
	_v2 = OS.get_cmdline_user_args().has("--v2")
	_state = GameState.new_campaign(_repo, 319)
	var view_script: GDScript = load("res://scripts/map3d/map3d_view.gd")
	_view = view_script.create(_repo)
	_bench_settings = load("res://tools/map3d/bench.gd")
	_view.set_meta("state_fn", func() -> GameState: return _state)
	root.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.set_quality(_tier)
	# Load ordinary world/layers with an empty display roster until candidate staging finishes.
	var saved := _state
	_state = GameState.new()
	while _view.load_step(): await process_frame
	_view.activate()
	_ctx = _view.context()
	if _ctx == null or _ctx.world == null:
		_fail("The unique 3D map did not load")
		return
	_state = saved
	_centre = ArmySystem.pack_to_metres(_repo, _ctx.to_pack(_flat_patch()))
	if not _stage(): return
	_ctx.day_fn = func() -> float: return _share
	_ctx.clock_fn = func() -> int: return _speed
	_layer = _view.world().get_node("Units") as Map3DLayerUnits
	_layer.blend_s = float(_arg("--blend", "0.3"))
	_layer.set_candidate_bodies(not _baseline)
	_view.set_military(true)
	_ctx.camera_moved.connect(_force_physical)
	_force_physical()
	if not _commit_slice(): return
	_frame_camera(_arg("--zoom", "near"))
	for i: int in 30: await process_frame
	await _capture("before-motion")
	if OS.get_cmdline_user_args().has("--bench"):
		_running = true  # priced while the slice clock runs: the figures move and turn
		await _bench()
		_running = false
		if _failed: return
	else:
		_running = true
		var count := int(_arg("--frames", "600"))
		for frame: int in count:
			await process_frame
			if _failed: return
			if _arg("--follow") != "": _follow(int(_arg("--follow")))
			var every := int(_arg("--every", "0"))
			var pivoting := _arg("--follow") != "" and OS.get_cmdline_user_args().has("--pivots") \
				and String(_layer.built_piece(_codes[int(_arg("--follow"))]).get("groups", [{}])[0].get("piece", {}).get("action", "")).begins_with("v2:PIVOT")
			if frame in [0, count / 4, count / 2, count * 3 / 4, count - 1] or (every > 0 and frame % every == 0) or pivoting: await _capture("frame-%05d" % frame)
		_running = false
	if _case == "arms":
		for distance: int in [1500, 5000]:
			for code: String in _codes:
				var entry: Dictionary = _state.regiments[code]
				_view.look_at_pack(ArmySystem.metres_to_pack(_repo, Vector2i(entry.x_m, entry.y_m)), distance)
				for i: int in 10: await process_frame
				await _capture(MapObjects.army_piece(_repo, _state.army_roster[code]) + "-%d" % distance)
	if _failed: return
	_write_manifest()
	_view.deactivate()
	_ctx.state_fn = Callable()
	_ctx.clock_fn = Callable()
	_ctx.day_fn = Callable()
	quit(2 if _failed else 0)

func _flat_patch() -> Vector2:
	var best := _ctx.home()
	var score := INF
	for x: int in range(-8, 9):
		for y: int in range(-8, 9):
			var centre := _ctx.home() + Vector2(x, y) * 1000.0
			var low := INF
			var high := -INF
			for dx: int in [-1800, -900, 0, 900, 1800]:
				for dy: int in [-1800, -900, 0, 900, 1800]:
					var height := _ctx.height_at(centre + Vector2(dx, dy))
					low = minf(low, height)
					high = maxf(high, height)
			if low <= float(_ctx.meta.get("sea_y", 0.0)) + 1.0: continue
			var candidate := high - low + Vector2(x, y).length() * 0.01
			if candidate < score:
				score = candidate
				best = centre
	print("CF04c real terrain patch ", best, " height span score ", score)
	return best

func _stage() -> bool:
	var available := {}
	for reg: Dictionary in MapObjects.regiments_of(_repo, _repo.resolve_realm("player_realm"), _state):
		var arm := MapObjects.army_piece(_repo, reg)
		if arm != "fleet" and not available.has(arm): available[arm] = reg["regiment_code"]
	var arms: Array = ["infantry", "archers", "cavalry", "artillery", "royal"] if _case == "arms" else ["infantry", "archers", "cavalry"]
	if _case == "opposing" or _case == "detour" or _case == "turn": arms = arms.slice(0, 2)
	var source_code := String(available.get("infantry", ""))
	if source_code.is_empty():
		_fail("No real infantry fixture source")
		return false
	var entries := {}
	var roster := {}
	var fit := int(_arg("--fit", "1000"))
	if fit < 0 or fit > 1000:
		_fail("Fit outside 0..1000")
		return false
	for arm: String in arms:
		var code := String(available.get(arm, ""))
		if code.is_empty():
			for unused: String in _state.regiments:
				if unused not in _codes and String(_state.army_roster[unused].get("is_naval", "0")) != "1":
					code = unused
					break
			if code.is_empty():
				_fail("Not enough real column fixtures")
				return false
			_state.army_roster[code].organization_arm = "infantry" if arm == "royal" else arm
			_state.army_roster[code].is_royal = "1" if arm == "royal" else "0"
		if Personnel.replace(_repo, _state, code, fit).has("error"):
			_fail("Personnel fixture transaction rejected")
			return false
		_codes.append(code)
		entries[code] = _state.regiments[code]
		roster[code] = _state.army_roster[code]
	_state.regiments = entries
	_state.army_roster = roster
	_state.foes = {}
	_state.ai_hosts = {}
	_state.battles = []
	_state.day_resolution = {}
	_state.town_seat = {}
	_state.military_migration.body_version = 1
	for index: int in _codes.size():
		var code := _codes[index]
		var entry: Dictionary = _state.regiments[code]
		var start := Vector2i(-20000, 0) if index == 0 else Vector2i(20000, 0)
		var target := -start
		if _case in ["detour", "turn"]: target.y += 20000
		if index == 2:
			start = Vector2i(0, -40000)
			target = Vector2i(0, 20000)
		if _case == "arms":
			start = Vector2i((index - 2) * 20000, 0)
			target = start
		entry.x_m = _centre.x + start.x
		entry.y_m = _centre.y + start.y
		entry.order = ArmySystem.ORDER_STANDBY
		entry.erase("camp_state")
		entry.group_next_slot = ceili(float(fit) / 100)
		entry.body_groups = []
		var homes := UnitBodies.home_slots(_repo, _state, code)
		var counts := BattleGroups.counts(fit, 100)
		for i: int in counts.size():
			var point := _centre + start + homes[i]
			entry.body_groups.append({"slot": i, "home_slot": i, "count": counts[i], "role": "front",
				"x_m": point.x, "y_m": point.y, "facing_deg": 90 if index == 2 else (0 if index == 0 else 180), "path_m": []})
			_targets[JSON.stringify([code, i])] = [_centre.x + target.x + homes[i].x, _centre.y + target.y + homes[i].y]
	var validated := UnitBodies.migrate_candidate(_repo, _state)
	if validated.status != "complete":
		_fail("Staged candidate rejected: " + validated.reason)
		return false
	_state = validated.candidate
	return true

func _commit_slice() -> bool:
	if _v2 and _strides.is_empty():
		# Stage each axis leg as whole strides of its arm, so no slice is left with a stub.
		for code: String in _codes:
			var stride := _stride_sim(code)
			for row: Dictionary in UnitBodies.rows(_repo, _state, code):
				var key := JSON.stringify([code, row.slot])
				var target: Array = _targets[key]
				_targets[key] = [row.x_m + roundi(roundf((target[0] - row.x_m) / stride) * stride), row.y_m + roundi(roundf((target[1] - row.y_m) / stride) * stride)]
	var intents: Array = []
	for code: String in _codes:
		for row: Dictionary in UnitBodies.rows(_repo, _state, code):
			var path: Array = [[row.x_m, row.y_m]]
			var target: Array = _targets[JSON.stringify([code, row.slot])]
			if _case == "turn" and not _v2:
				# Explicit fixture pose input; the following plan/commit validates its full radius.
				for saved: Dictionary in _state.regiments[code].body_groups:
					if saved.slot == row.slot:
						saved.facing_deg = 90 if row.x_m == target[0] else (0 if target[0] > row.x_m else 180)
			if _case in ["detour", "turn"] and code == _codes[0]: path.append([target[0], row.y_m])
			path.append(target)
			intents.append({"unit": code, "slot": row.slot, "path_m": path, "budget_m": 8000, "hostile": false})
	if _v2: return _commit_v2(intents)
	var plan := BodyMotion.plan(_repo, _state, intents, _state.absolute_day(), _slice)
	if plan.cursor.is_empty():
		_fail("Planner rejected fixture: " + str(plan.reasons))
		return false
	var result := BodyMotion.commit(_repo, _state, plan)
	if result.status != "complete" or _state.military_migration.body_motion.receipt != BodyMotion._hash(plan):
		_fail("Commit rejected fixture: " + result.reason)
		return false
	_envelope = {"cursor": {"version": 1, "abs_day": plan.cursor.abs_day, "substep": plan.cursor.substep,
		"receipt": BodyMotion._hash(plan)}, "moves": []}
	for move: Dictionary in plan.moves:
		_envelope.moves.append({"unit": move.unit, "slot": move.slot, "budget_m": move.budget_m})
	FileAccess.open(_out.path_join("slice-%02d.json" % _slice), FileAccess.WRITE).store_string(JSON.stringify({"plan": plan, "state": _state.to_dict()}, "\t"))
	_layer.set_candidate_bodies(not _baseline, _envelope)
	return true

func _commit_v2(intents: Array) -> bool:
	# The driver's job: v2 executes only complete affordable waypoint prefixes, so each slice
	# requests the longest prefix whose pivots and moves the row's own timeline completes.
	for intent: Dictionary in intents:
		var row: Dictionary = UnitBodies.rows(_repo, _state, intent.unit).filter(func(r: Dictionary) -> bool: return r.slot == intent.slot)[0]
		var piece := MapObjects.army_piece(_repo, _state.army_roster[intent.unit])
		var body := {"unit": intent.unit, "slot": int(intent.slot), "start": [int(row.x_m), int(row.y_m)], "start_yaw_udeg": int(row.facing_deg) * BodyMotion.LOCOMOTION_Q,
			"final_facing_deg": int(row.facing_deg), "budget_m": int(intent.budget_m)}
		var turn_q := int(_repo.unit_footprints[piece].locomotion_certificate.turn_q)
		var low := 0
		var high := mini(BodyMotion._length(intent.path_m), int(intent.budget_m))
		var best: Array = [intent.path_m[0]]
		while low <= high:
			@warning_ignore("integer_division")
			var middle: int = low + (high - low) / 2
			var prefix := BodyMotion._loco_prefix(intent.path_m, middle)
			var move := BodyMotion._loco_timeline(body, prefix, turn_q)
			if not move.is_empty() and move.end == prefix.back():
				best = prefix
				low = middle + 1
			else: high = middle - 1
		intent.path_m = _whole_strides(intent.path_m, best, _stride_sim(intent.unit))
	# A body the planner trims to a collision-clear prefix is re-requested as whole strides of
	# that prefix until every requested leg runs complete (lengths only shrink, so it settles).
	var plan := {}
	for attempt: int in 8:
		plan = BodyMotion.plan_locomotion_candidate(_repo, _state, intents, _state.absolute_day(), _slice)
		if plan.get("version") != 2:
			_fail("Locomotion planner rejected fixture: " + str(plan.get("reason", plan.get("reasons", plan))))
			return false
		if plan.reasons.is_empty(): break
		for intent: Dictionary in intents:
			for move: Dictionary in plan.moves:
				if move.unit == intent.unit and move.slot == intent.slot and move.end != intent.path_m.back():
					intent.path_m = _whole_strides(intent.path_m, BodyMotion._loco_path(move), _stride_sim(intent.unit))
	if not plan.reasons.is_empty():
		_fail("Whole-stride re-plan did not settle: " + str(plan.reasons))
		return false
	var result := BodyMotion.commit_locomotion_candidate(_repo, _state, plan)
	if result.status != "complete":
		_fail("Locomotion commit rejected fixture: " + result.reason)
		return false
	_state = result.candidate
	_envelope = {"cursor": {"version": 2, "abs_day": plan.cursor.abs_day, "substep": plan.cursor.substep, "receipt": BodyMotion._hash(plan)}}
	FileAccess.open(_out.path_join("slice-%02d.json" % _slice), FileAccess.WRITE).store_string(JSON.stringify({"plan": plan, "state": _state.to_dict()}, "\t"))
	_layer.set_candidate_bodies(not _baseline, _envelope)
	return true

## One certified MARCH stride of this unit's figures in sim metres (the consumer's
## sim -> model scale, at its fixed reference camera); cached per unit.
func _stride_sim(code: String) -> float:
	if _strides.has(code): return _strides[code]
	if _layer.built_piece(code).is_empty(): _layer.step(0.0)
	var piece := _layer.built_piece(code)
	# --baseline draws ordinary pieces; their reference height and size give the same scale.
	var child: Dictionary = piece.groups[0].piece if piece.has("groups") else {"reference_height_m": piece.get("reference_height_m", piece.get("height_m", 0.0)),
		"size": piece.get("reference_size", piece.get("size", 1.0))}
	var model := Map3DCandidateGait.model_length(_ctx, piece, child, {"a": [0, 0], "b": [1000000, 0]})
	_strides[code] = float(_repo.unit_footprints[MapObjects.army_piece(_repo, _state.army_roster[code])].locomotion_certificate.stride_m) * 1000000.0 / model
	return _strides[code]

## The consumer walks a leg only as whole strides, so the driver hands it whole strides:
## a partial last leg stops where the distance left to its waypoint is a whole number of
## strides (the staged targets are, so a leg is never left with a stub).
func _whole_strides(path: Array, prefix: Array, stride: float) -> Array:
	if prefix.size() < 2 or path.has(prefix.back()): return prefix
	var from: Array = prefix[prefix.size() - 2]
	var to: Array = path[prefix.size() - 1]
	var left := BodyMotion._distance_ceil(from, to)
	var steps := floori(float(BodyMotion._distance_ceil(from, prefix.back())) / stride)
	var out := prefix.slice(0, prefix.size() - 1)
	if steps == 0: return out
	var rest := roundf((roundf(left / stride) - steps) * stride) / left
	out.append([int(to[0]) + roundi((int(from[0]) - int(to[0])) * rest), int(to[1]) + roundi((int(from[1]) - int(to[1])) * rest)])
	return out

func _process(delta: float) -> bool:
	if not _running: return false
	_share += delta * _speed * DayResolution.DEFAULT_SUBSTEP_COUNT / _repo.bal("time_day_seconds")
	if _share >= 1.0:
		_share = 1.0
		_layer.step(0.0)
		if _slice < DayResolution.DEFAULT_SUBSTEP_COUNT - 1:
			_slice += 1
			_share = 0.0
			_commit_slice()
	return false

## Keeps the camera on unit `index`'s drawn figures (--follow), at its current distance.
func _follow(index: int) -> void:
	var groups: Array = _layer.group_geometry().get(_codes[index], [])
	if groups.is_empty(): return
	var sum := Vector2.ZERO
	for group: Dictionary in groups: sum += Vector2(group.xz_world[0], group.xz_world[1])
	_view.look_at_pack(_ctx.to_pack(sum / groups.size()), _ctx.distance)

func _force_physical() -> void:
	# This consumer fixture prices physical figures even at strategic overview distance.
	_view.set("unit_symbol_mode", false)
	var hud: Node = _view.get("_hud")
	hud.call("apply_military_mode", false, true, true)
	if not _layer.shown: _layer.set_shown(true)

func _frame_camera(zoom: String) -> void:
	var key := "map3d_zoom_min_m" if zoom == "near" else ("map3d_bench_mid_m" if zoom == "mid" else "map3d_zoom_max_m")
	_view.look_at_pack(ArmySystem.metres_to_pack(_repo, _centre), float(_arg("--zoom3d", str(_repo.bal(key)))))

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK: _fail("Capture failed: " + path)
	_frames.append({"label": label, "png": path, "sha256": FileAccess.get_sha256(path),
		"slice": _slice, "share": _share, "state_hash": SaveLoad.state_hash(_state),
		"camera": {"distance": _ctx.distance, "target": [_ctx.target.x, _ctx.target.y], "yaw": _ctx.yaw,
			"transform": var_to_str(_ctx.camera.global_transform), "fov": _ctx.camera.fov,
			"view_size": [_ctx.view_size.x, _ctx.view_size.y], "viewport": [_view.viewport().size.x, _view.viewport().size.y]},
		"geometry": _layer.group_geometry(),
		"refusals": _codes.map(func(code: String) -> String: return String(_layer.built_piece(code).get("candidate_error", "")))})

func _stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"mean_ms": total / values.size(), "median_ms": values[values.size() / 2], "p95_ms": values[ceili(values.size() * 0.95) - 1]}

func _bench() -> void:
	var tier := Map3DQuality.row(_repo, _tier)
	if "%dx%d" % [root.size.x, root.size.y] != String(tier.bench_size):
		_fail("Benchmark requires tier bench_size " + String(tier.bench_size))
		return
	RenderingServer.viewport_set_measure_render_time(_view.viewport().get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var rows: Array = []
	var rig := _view.world().get_node("CameraRig") as Map3DCameraRig
	for stop: String in ["near", "mid", "far"]:
		_frame_camera(stop)
		for i: int in _bench_settings.WARM: await process_frame
		# Built-in monitors can lag one second; expire loading/capture/reframe samples.
		await create_timer(1.1).timeout
		var frame_ms: Array = []
		var cpu_ms: Array = []
		var gpu_ms: Array = []
		var process_ms: Array = []
		var render_cpu_ms: Array = []
		var setup_cpu_ms: Array = []
		var draw_calls := 0
		var primitives := 0
		var previous := Time.get_ticks_usec()
		for i: int in _bench_settings.FRAMES:
			if OS.get_cmdline_user_args().has("--pan"): rig.pan_by(Vector2(_bench_settings.PAN_PX if i % (_bench_settings.PAN_PERIOD * 2) < _bench_settings.PAN_PERIOD else -_bench_settings.PAN_PX, 0))
			await process_frame
			var now := Time.get_ticks_usec()
			frame_ms.append(float(now - previous) / 1000.0)
			previous = now
			process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			setup_cpu_ms.append(RenderingServer.get_frame_setup_time_cpu())
			render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(_view.viewport().get_viewport_rid())
				+ RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			cpu_ms.append(float(process_ms.back()) + float(setup_cpu_ms.back()) + float(render_cpu_ms.back()))
			draw_calls = maxi(draw_calls, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			primitives = maxi(primitives, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_view.viewport().get_viewport_rid()))
		var stats := _stats(frame_ms)
		rows.append({"zoom": stop, "frame": stats, "cpu": _stats(cpu_ms), "process_cpu": _stats(process_ms), "render_cpu": _stats(render_cpu_ms),
			"setup_cpu": _stats(setup_cpu_ms), "gpu": _stats(gpu_ms), "draw_calls": draw_calls, "primitives": primitives,
			"budget_ms": float(tier.bench_budget_ms)})
		print("CF04c bench ", rows.back())
	FileAccess.open(_out.path_join("bench.json"), FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))

func _write_manifest() -> void:
	var revision: Array = []
	OS.execute("git", ["rev-parse", "HEAD"], revision)
	var inputs := {}
	for path: String in ["res://scripts/map3d/map3d_battle_groups.gd", "res://scripts/map3d/map3d_candidate_bodies.gd", "res://scripts/map3d/map3d_layer_units.gd",
		"res://scripts/map3d/map3d_formation.gd", "res://tools/map3d/body_paths_fixture.gd", "res://data/army/unit_footprints.csv", "res://data/army/unit_locomotion.csv", "res://scripts/map3d/map3d_candidate_gait.gd",
		_repo.map3d_dir().path_join("manifest.json")]: inputs[path] = FileAccess.get_sha256(path)
	FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"head": str(revision).strip_edges(), "inputs": inputs, "command": OS.get_cmdline_args(),
		"map": _repo.map_id, "world": _repo.map3d_scene(), "case": _case, "baseline": _baseline,
		"physical_all_zooms": true, "v2": _v2, "quality": _tier, "resolution": [root.size.x, root.size.y], "speed": _speed,
		"args": OS.get_cmdline_user_args(), "frames": _frames, "final_state": _state.to_dict()}, "\t"))
