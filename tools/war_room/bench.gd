extends Node
## Frame time of the WAR ROOM as the player sees it (spec 2026-10-01-war-room-
## design): the real GameRoot, the court, the WAR ROOM tab pressed (which holds
## the clock still, owner 2026-10-02), the home sheet laid — at the camera's three distances (war_cam_max_m,
## war_cam_distance_m, war_cam_min_m, reached by the real wheel on the view),
## median / mean / p95 against the tier's bench_budget_ms exactly as
## tools/map3d/bench.gd prints its rows (it is a sibling because that bench's
## loop is built round Map3DView's layers). Vsync off. Exits 3 over budget.
## The same Forward+/Metal floor applies: no row reads under ~8.33 ms on this
## Mac (see tools/map3d/bench.gd's note), so a row at it means "holds the
## refresh". The clock is held short of the month's end like that bench.
## A last row, `pushed`, stands at the opening distance with one land piece
## moved a little every measured frame — as the plotter's rake moves it — so a
## candle's shadow is dirty each frame and re-rendered (the still rows reuse it).
##   Godot --path . res://scenes/tools/war_room/bench.tscn -- --size 3024x1964 --quality high
##
## Flags: --size WxH, --quality TIER (default high), --out FILE (append rows to
## a CSV; it must land under tools/map3d/baselines/ — which carries a
## .gdignore — or a scratch path outside the project, or Godot imports a bare
## CSV under res:// as a Translation), --sheet N (lay that
## sheet instead of the home one).

const FRAMES := 120
const WARM := 30
const BUDGET_MS := 8.0
const DAY_CEILING := 25
const PUSH_M := 0.004      # the pushed row: how far the piece swings each way, metres
const PUSH_STEP := 0.3     # radians of the swing per frame
const STOPS := [["far", "war_cam_max_m"], ["opening", "war_cam_distance_m"], ["near", "war_cam_min_m"]]

var _root: GameRoot
var _out := ""
var _tier := "high"
var _rows: Array = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var size := Vector2i(2560, 1440)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--size")
	if at >= 0 and at + 1 < args.size():
		var wh := args[at + 1].split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	var oi := args.find("--out")
	if oi >= 0 and oi + 1 < args.size():
		_out = args[oi + 1]
	var qi := args.find("--quality")
	_tier = args[qi + 1] if qi >= 0 and qi + 1 < args.size() else "high"
	Map3DQuality.forced = _tier   # before the view binds, so the room wears the whole tier
	FrameCap.forced = 0  # a bench row reads the frame's own cost, never the player's cap
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	get_window().size = size
	Game.start_campaign(42)
	GameRoot.stepwise_overlays = false
	var root := (load("res://scenes/game_root.tscn") as PackedScene).instantiate() as GameRoot
	_root = root
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 4:
		await get_tree().process_frame
	root._switch_to(GameRoot.State.COURT)
	root.current_screen.enter_court(null)
	for i in 4:
		await get_tree().process_frame
	root._on_bottom_tab("WAR ROOM")
	for i in 4:
		await get_tree().process_frame
	var screen := _root.war_room_screen()
	var view := screen.view()
	if not screen.visible or view.sheet_index() < 0:
		push_error("the WAR ROOM did not open")
		get_tree().quit(1)
		return
	var si := args.find("--sheet")
	if si >= 0 and si + 1 < args.size():
		view.swap_to(int(args[si + 1]))
	for i in 20:
		await get_tree().process_frame   # the sheet's ink paints over a few frames
	var row := Map3DQuality.row(Game.data, _tier)
	var budget := Map3DQuality.num(row, "bench_budget_ms", BUDGET_MS)
	if "%dx%d" % [size.x, size.y] != String(row.get("bench_size", "")):
		print("WARNING: tier %s is gated at %s, not %dx%d" % [_tier, String(row.get("bench_size", "")), size.x, size.y])
	RenderingServer.viewport_set_measure_render_time(view.get_node("%Viewport").get_viewport_rid(), true)
	print("renderer %s / %s, window %s, tier %s, sheet %d" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), get_window().size, _tier, view.sheet_index()])
	var worst := 0.0
	for stop: Array in STOPS:
		await _lean_to(view, Game.data.bal(String(stop[1])))
		worst = maxf(worst, await _measure(view, "%s  (%.2f m)" % [stop[0], view.camera_rig().distance]))
	await _lean_to(view, Game.data.bal("war_cam_distance_m"))
	var moved := _a_land_piece(view)
	worst = maxf(worst, await _measure(view, "pushed  (%.2f m)" % view.camera_rig().distance, moved))
	print("WORST %.2f ms (%.0f fps), budget %.2f ms (%s, still)" % [worst, 1000.0 / worst, budget, _tier])
	_write_rows()
	get_tree().quit(0 if worst <= budget else 3)


## The real wheel on the view's middle, until the camera stands within half a notch of
## `want` metres (or is held short of it by its limits).
func _lean_to(view: WarRoomView, want: float) -> void:
	var rig := view.camera_rig()
	for i in 80:
		if absf(log(rig.distance / want)) < log(Game.data.bal("war_cam_zoom_step")) * 0.55 or (want <= rig.min_distance + 0.0001 and rig.distance <= rig.min_distance + 0.0001) \
				or (want >= rig.max_distance - 0.0001 and rig.distance >= rig.max_distance - 0.0001):
			break
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if rig.distance > want else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = view.get_global_transform_with_canvas() * (view.size * 0.5)
		e.global_position = e.position
		view.get_viewport().push_input(e, true)
		await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame


## The first land piece on the laid sheet (a figure-carrying one, so its
## shadow is a real cost), null when none.
func _a_land_piece(view: WarRoomView) -> Node3D:
	var pieces := view.get_node("%Pieces") as WarPieces
	for p: Dictionary in WarRoom.on_sheet(Game.data, Game.state, view.sheet_index(), view.drawn()):
		var code := String(p["code"])
		if MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code, Game.state)) != "fleet":
			return pieces.piece(code)
	return null


func _measure(view: WarRoomView, label: String, moved: Node3D = null) -> float:
	for i in WARM:
		await get_tree().process_frame
		_root.hold_clock_before_month_end(DAY_CEILING)
	var view_rid: RID = view.get_node("%Viewport").get_viewport_rid()
	var root_rid := get_viewport().get_viewport_rid()
	var frame_ms := PackedFloat64Array()
	var cpu_ms := PackedFloat64Array()
	var calls := 0
	var prims := 0
	var t_prev := Time.get_ticks_usec()
	var home := moved.position if moved != null else Vector3.ZERO
	for i in FRAMES:
		if moved != null:   # a push: a few millimetres along the table, every frame
			moved.position = home + Vector3(PUSH_M * sin(float(i) * PUSH_STEP), 0.0, PUSH_M * cos(float(i) * PUSH_STEP))
		await get_tree().process_frame
		_root.hold_clock_before_month_end(DAY_CEILING)
		var t_now := Time.get_ticks_usec()
		frame_ms.append(float(t_now - t_prev) / 1000.0)
		t_prev = t_now
		calls = maxi(calls, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			+ RenderingServer.get_frame_setup_time_cpu()
			+ RenderingServer.viewport_get_measured_render_time_cpu(view_rid)
			+ RenderingServer.viewport_get_measured_render_time_cpu(root_rid))
	if moved != null:
		moved.position = home
	var median := _percentile(frame_ms, 0.5)
	print("%-24s median %6.2f ms  mean %6.2f ms  p95 %6.2f ms  (%5.1f fps)  draw calls %4d  primitives %8d  cpu %5.2f ms"
		% [label, median, _mean(frame_ms), _percentile(frame_ms, 0.95), 1000.0 / median, calls, prims,
			_percentile(cpu_ms, 0.5)])
	_rows.append([str(get_window().size.x) + "x" + str(get_window().size.y), _tier, "war room " + label,
		median, _mean(frame_ms), _percentile(frame_ms, 0.95), calls, prims])
	return median


func _mean(xs: PackedFloat64Array) -> float:
	var total := 0.0
	for x: float in xs:
		total += x
	return total / float(xs.size())


func _percentile(xs: PackedFloat64Array, p: float) -> float:
	if xs.is_empty():
		return 0.0
	var sorted := xs.duplicate()
	sorted.sort()
	return sorted[clampi(int(round(p * float(sorted.size() - 1))), 0, sorted.size() - 1)]


func _write_rows() -> void:
	if _out == "":
		return
	var path := _out if _out.is_absolute_path() else ProjectSettings.globalize_path("res://" + _out)
	var fresh := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not fresh else FileAccess.WRITE)
	if f == null:
		push_error("bench: cannot write " + path)
		return
	f.seek_end()
	if fresh:
		f.store_line("size,tier,label,median_ms,mean_ms,p95_ms,draw_calls,primitives")
	for r: Array in _rows:
		f.store_line("%s,%s,\"%s\",%.3f,%.3f,%.3f,%d,%d" % r)
	f.close()
