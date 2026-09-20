extends Node
## Frame time of the 3D MAP as the player sees it (spec 2026-09-18 §5): the
## real GameRoot, the court, the 3D tab lit, the clock at 4x — at the near,
## mid and far zoom with every layer on, then each layer off in turn to price
## it. Vsync off, so the numbers are the real cost. Exits 3 over budget.
##
## The clock is held short of the month's end (GameRoot.hold_clock_before_
## month_end): a completed month can roll a random event that stops the
## clock and swaps the screen away, freeing the very Map3DView being timed.
## This prices the real per-day clock cost paid every frame — NOT the
## month-end settlement itself (the tick, its report, an event firing): a
## settle hitch is invisible to this bench and needs its own measurement.
##
## Each row is MEDIAN over the frame, not a single mean (controller ruling:
## a single-run mean swings ±1.5 ms on this machine with the owner's Godot
## editor, Blender and ComfyUI competing for the GPU) — a stray slow frame
## from another app skews a mean but barely moves a median. Mean and p95
## print alongside it so a fat tail is still visible. WORST and the exit
## code are the MEDIAN of the "all on" rows only. The 3D view's own GPU
## time and the window's total GPU time (also medians) separate "the
## Map3DView is expensive" from "something else on screen is" — but only
## on a RenderingDevice-backed method (Forward+/Mobile): this project runs
## GL Compatibility (see CLAUDE.md's Stack), which has no GPU timestamp
## queries, so "gpu view" / "gpu root" read a flat 0.00 ms here. That's
## expected on this renderer, not a broken measurement.
##   GDAI_MCP_SERVER_PORT=3999 Godot --path . res://tools/map3d/bench.tscn -- --size 3024x1964
##
## Flags:
##   --size WxH          the window to measure at; pass the tier's own
##                       `bench_size` or the gate means nothing (a WARNING prints).
##   --quality TIER      force a graphics tier (Map3DQuality.forced) BEFORE the
##                       view's first load, so the whole tier is worn. Default high.
##   --render-scale X    override just that tier's render_scale on top of it.
##   --out FILE          append every row (size, tier, label, median/mean/p95 ms,
##                       draw calls, primitives) to a CSV. It must land under
##                       tools/map3d/baselines/ or a scratch path — a bare CSV
##                       elsewhere under res:// is auto-imported as a Translation.
##   --layer heights|manors|military   lights that bottom-bar tab first (as
##                       tools/snapshot_screen.gd takes it), so a theme's HUD and
##                       ground are priced.
##   --pan               measure a MOVING view instead of a still one (below).
##
## STILL vs PAN (final review 2026-09-20). Without --pan the camera stands
## still for the whole row, so everything the view cuts once per camera pose —
## the output badges, the army counters, the kingdom names, the landmark marks,
## the hover pick and the HUD's own redraw — is computed on the row's first
## frame and never again: a still number prices the GPU and the clock, not the
## per-move CPU. `--pan` pans the ground a little EVERY measured frame (through
## the rig's own pan_by, the drag's path) and asks for a hover pick at a
## wandering pointer, so every one of those is paid per frame, as it is while
## the player drags the map. The pan OSCILLATES (PAN_PERIOD frames each way),
## so the framing — and therefore what is drawn — stays where the row put it.
## Pan rows carry " [pan]" in their label; a run is one or the other. A
## --layer run tags its rows with the layer too ("[manors]"), so one --out CSV
## can hold every run without two of them reading alike.

const FRAMES := 120
const WARM := 30
const BUDGET_MS := 8.0
const STOPS := [["near", "map3d_zoom_min_m"], ["mid", "map3d_zoom_start_m"],
	["far", "map3d_zoom_max_m"]]
## --pan: screen px of ground moved per frame, and how many frames each way
## before it turns back (so 120 frames end roughly where they began).
const PAN_PX := 8.0
const PAN_PERIOD := 15
## Kept below Calendar.DAYS_PER_TICK (30), with room to spare — see the
## GameRoot.hold_clock_before_month_end note at the top of this file.
const DAY_CEILING := 25

var _root: GameRoot
var _view: Map3DView
var _out := ""
var _rows: Array = []
## The tier this run was gated at (Map3DQuality.TIERS); "high" if --quality
## was not given. Recorded per row so --out rows from different tiers never
## get confused under one "current" label.
var _tier := "high"
## --pan: every measured frame pans the view and asks for a hover pick.
var _pan := false
## --layer's bottom-bar tab ("" for none), tagged onto every row's label.
var _layer := ""
var _rig: Map3DCameraRig


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var size := Vector2i(2560, 1440)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--size")
	if at >= 0 and at + 1 < args.size():
		var wh := args[at + 1].split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	_pan = args.has("--pan")
	var oi := args.find("--out")
	if oi >= 0 and oi + 1 < args.size():
		_out = args[oi + 1]
	var qi := args.find("--quality")
	var tier := args[qi + 1] if qi >= 0 and qi + 1 < args.size() else "high"
	_tier = tier
	Map3DQuality.forced = tier  # before GameRoot exists, so the view's first load wears it
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
	var li := args.find("--layer")
	if li >= 0 and li + 1 < args.size():
		root._on_bottom_tab(args[li + 1].to_upper())
		_layer = args[li + 1].to_lower()
		for i in 4:
			await get_tree().process_frame
	Game.set_clock_speed(4)
	var v: Map3DView = root.current_screen.map3d_view()
	if v == null or not v.is_loaded():
		push_error("the 3D map is not built — see tools/map3d/README.md")
		Map3DWorldCache.clear()  # the kept world leaks at exit otherwise
		get_tree().quit(1)
		return
	_view = v
	_rig = v.component("rig") as Map3DCameraRig
	var overrides := {}
	var ri := args.find("--render-scale")
	if ri >= 0 and ri + 1 < args.size():
		overrides["render_scale"] = args[ri + 1]
		v.set_quality(tier, overrides)
	var row := Map3DQuality.row(Game.data, tier)
	var budget := Map3DQuality.num(row, "bench_budget_ms", BUDGET_MS)
	if "%dx%d" % [size.x, size.y] != String(row.get("bench_size", "")):
		print("WARNING: tier %s is gated at %s, not %dx%d" % [tier, String(row.get("bench_size", "")), size.x, size.y])
	RenderingServer.viewport_set_measure_render_time(v.viewport().get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("renderer %s / %s, window %s, tier %s render_scale %.2f, camera %s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), get_window().size, tier,
		Map3DQuality.num(Map3DQuality.merged(Game.data, tier, overrides), "render_scale", 1.0),
		"PANNING (per-move CPU priced)" if _pan else "still (per-move CPU NOT priced)"])
	var worst := 0.0
	for stop: Array in STOPS:
		v.look_at_home(Game.data.bal(String(stop[1])))
		worst = maxf(worst, await _measure("%s  all on" % stop[0]))
		for layer: String in v.layer_names():
			v.set_layer_visible(layer, false)
			await _measure("%s  - %s" % [stop[0], layer])
			# Restore the LAYER's own tier value, not a hardcoded true: at low
			# (sun_shadows 0) this used to turn shadows back ON after pricing
			# them, so every row after "- Shadows" was priced with shadows the
			# tier does not actually pay for (Task 17 review).
			var restore := true
			if layer == "Shadows":
				restore = Map3DQuality.num(row, "sun_shadows", 1.0) != 0.0
			v.set_layer_visible(layer, restore)
	print("WORST %.2f ms (%.0f fps), budget %.2f ms (%s, %s)" % [worst, 1000.0 / worst, budget,
		tier, "pan" if _pan else "still"])
	_write_rows()
	Map3DWorldCache.clear()  # the kept world leaks at exit otherwise
	get_tree().quit(0 if worst <= budget else 3)


## Times FRAMES frames after WARM warm-up ones, one sample per frame taken
## from the gap between successive process frames (not a single before/after
## total), so the row can report a distribution, not just its average.
## Returns the MEDIAN frame time in ms — the bench's "how expensive is this"
## number (see the top-of-file note on why median).
func _measure(plain_label: String) -> float:
	var label := plain_label + ("  [pan]" if _pan else "") + ("  [%s]" % _layer if _layer != "" else "")
	for i in WARM:
		await get_tree().process_frame
		_root.hold_clock_before_month_end(DAY_CEILING)
		_stir(i)
	var view_rid := _view.viewport().get_viewport_rid()
	var root_rid := get_viewport().get_viewport_rid()
	var frame_ms := PackedFloat64Array()
	var view_gpu_ms := PackedFloat64Array()
	var root_gpu_ms := PackedFloat64Array()
	var calls := 0
	var prims := 0
	var t_prev := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		_root.hold_clock_before_month_end(DAY_CEILING)
		_stir(i)
		var t_now := Time.get_ticks_usec()
		frame_ms.append(float(t_now - t_prev) / 1000.0)
		t_prev = t_now
		calls = maxi(calls, RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		view_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(view_rid))
		root_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
	var median := _median(frame_ms)
	print("%-24s median %6.2f ms  mean %6.2f ms  p95 %6.2f ms  (%5.1f fps)  draw calls %4d  primitives %8d  gpu view %5.2f ms  gpu root %5.2f ms"
		% [label, median, _mean(frame_ms), _percentile(frame_ms, 0.95), 1000.0 / median, calls, prims,
			_median(view_gpu_ms), _median(root_gpu_ms)])
	_rows.append([str(get_window().size.x) + "x" + str(get_window().size.y), _tier, label,
		median, _mean(frame_ms), _percentile(frame_ms, 0.95), calls, prims])
	return median


## --pan's per-frame work, through the view's own public seams: the rig's
## pan_by (what a left-drag calls) and request_hover (what a pointer move
## calls, picked once a frame in Map3DView._process). Nothing when --pan is
## off, so a still run is byte-for-byte the run it always was.
func _stir(i: int) -> void:
	if not _pan or _view == null:
		return
	if _rig != null:
		@warning_ignore("integer_division")  # whole pan periods, so the sweep turns round
		var dir := 1.0 if int(i / PAN_PERIOD) % 2 == 0 else -1.0
		_rig.pan_by(Vector2(PAN_PX, PAN_PX * 0.4) * dir)
	# a pointer wandering over the view, so the hover picks something new
	var t := float(i) * 0.11
	_view.request_hover(Vector2(_view.size.x * (0.5 + 0.25 * cos(t)),
		_view.size.y * (0.5 + 0.25 * sin(t))))


func _mean(xs: PackedFloat64Array) -> float:
	var total := 0.0
	for x: float in xs:
		total += x
	return total / float(xs.size())


func _median(xs: PackedFloat64Array) -> float:
	return _percentile(xs, 0.5)


func _percentile(xs: PackedFloat64Array, p: float) -> float:
	if xs.is_empty():
		return 0.0
	var sorted := xs.duplicate()
	sorted.sort()
	var i := clampi(int(round(p * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[i]


## Appends this run's rows to --out (CSV; a header when the file is new).
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
