extends Node
## Frame time of the 3D MAP as the player sees it (spec 2026-09-18 §5): the
## real GameRoot, the court, the 3D tab lit, the clock at 4x — at the near,
## mid and far zoom with every layer on, then each layer off in turn to price
## it. Vsync off, so the numbers are the real cost. Exits 3 over budget.
##   GDAI_MCP_SERVER_PORT=3999 Godot --path . res://tools/map3d/bench.tscn -- --size 3024x1964

const FRAMES := 120
const WARM := 30
const BUDGET_MS := 8.0
const STOPS := [["near", "map3d_zoom_min_m"], ["mid", "map3d_zoom_start_m"],
	["far", "map3d_zoom_max_m"]]
## Kept below Calendar.DAYS_PER_TICK (30) by _guard_clock: a completed month
## can roll a random event, which stops the clock and swaps the screen to
## the council — freeing the very Map3DView the bench is timing.
const DAY_CEILING := 25

var _root: GameRoot


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var size := Vector2i(2560, 1440)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--size")
	if at >= 0 and at + 1 < args.size():
		var wh := args[at + 1].split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	get_window().size = size
	Game.start_campaign(42)
	var root := (load("res://scenes/game_root.tscn") as PackedScene).instantiate() as GameRoot
	_root = root
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 4:
		await get_tree().process_frame
	root._switch_to(GameRoot.State.COURT)
	root.current_screen.enter_court(null)
	root.set_map3d_view(true)
	Game.set_clock_speed(4)
	var v: Map3DView = root.current_screen.map3d_view()
	if v == null or not v.is_loaded():
		push_error("the 3D map is not built — see tools/map3d/README.md")
		get_tree().quit(1)
		return
	print("renderer %s / %s, window %s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), get_window().size])
	var worst := 0.0
	for stop: Array in STOPS:
		v.look_at_home(Game.data.bal(String(stop[1])))
		worst = maxf(worst, await _measure("%s  all on" % stop[0]))
		for layer: String in v.layer_names():
			v.set_layer_visible(layer, false)
			await _measure("%s  - %s" % [stop[0], layer])
			v.set_layer_visible(layer, true)
	print("WORST %.2f ms (%.0f fps), budget %.2f ms" % [worst, 1000.0 / worst, BUDGET_MS])
	get_tree().quit(0 if worst <= BUDGET_MS else 3)


func _measure(label: String) -> float:
	for i in WARM:
		await get_tree().process_frame
		_guard_clock()
	var t0 := Time.get_ticks_usec()
	var calls := 0
	for i in FRAMES:
		await get_tree().process_frame
		_guard_clock()
		calls = maxi(calls, RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / FRAMES
	print("%-24s %6.2f ms  (%5.1f fps)  draw calls %d" % [label, ms, 1000.0 / ms, calls])
	return ms


## The clock runs at 4x for real per-frame cost, but a completed month must
## never fire mid-bench (see DAY_CEILING): roll the day back before it can.
func _guard_clock() -> void:
	if Game.state != null and Game.state.day > DAY_CEILING:
		Game.state.day = 1
		_root._clock_acc = 0.0
