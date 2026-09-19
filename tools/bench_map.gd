extends Node
## Frame-time benchmark for the world map (owner request 2026-09-13).
##
## PAN: every view (political, provinces, heights, manors, military) panned
## across the map at three zooms — the zoom-out floor, the opening zoom, and
## three times closer — with a hover probe every frame the way a mouse drag
## triggers one. SWITCH: the frames right after a view is turned on, the
## first time (which builds that view's mesh and caches) and again later
## (cached).
##
## Runs through the REAL window with the project's own vsync, so the frame
## time tops out at the display's refresh — which is what a player sees. The
## first version turned vsync off and its window stalled at 0% CPU on this
## machine, so the renderer's own measured CPU and GPU time per frame is
## recorded beside the frame time instead, to show the headroom under the cap.
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/bench_map.tscn \
##     -- [--resolution 1280x720] [--frames 180] [--out user://bench_map.txt]
## A tool, not simulation: it reads wall-clock time, which engine code never may.

const VIEWS := ["political", "provinces", "heights", "manors", "military"]
const ZOOMS := ["world", "home", "close"]
const CLOSE_MUL := 3.0
const WARM_FRAMES := 20
const SWITCH_FRAMES := 4
const PAN_STEP := Vector2(9.0, 4.0)
## A step that has not finished in this long is reported and skipped.
const STEP_TIMEOUT_MS := 30000
## Frames slower than this miss a 60 Hz refresh.
const HITCH_MS := 1000.0 / 60.0

var _view: WorldMapView
var _frames := 180
var _res := Vector2i(1280, 720)
var _out := "user://bench_map.txt"
var _steps: Array = []
var _step := -1
var _count := 0
var _samples: Array = []
var _cpu: Array = []
var _gpu: Array = []
var _last := 0
var _step_ms := 0
## Microseconds spent in the per-frame hover probe during the current step.
var _hover_us := 0
var _dir := PAN_STEP
var _lines: PackedStringArray = []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size() - 1:
		match args[i]:
			"--frames":
				_frames = int(args[i + 1])
			"--out":
				_out = args[i + 1]
			"--resolution":
				var wh := args[i + 1].split("x")
				_res = Vector2i(int(wh[0]), int(wh[1]))
		i += 1
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	get_window().size = _res
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Game.start_campaign(42)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.size = get_viewport().get_visible_rect().size
	add_child(holder)
	_view = WorldMapView.create()
	holder.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Per-layer wall-clock cost of _draw, so a slow frame names its layer.
	_view.profile_draw = true
	_build_steps()
	_lines.append("world map bench — %dx%d window, %d frames per pan, vsync %s, display %.0f Hz, %s" % [
		_res.x, _res.y, _frames,
		"on" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "off",
		DisplayServer.screen_get_refresh_rate(), RenderingServer.get_video_adapter_name()])
	print("bench: ready, %d steps" % _steps.size())
	_last = Time.get_ticks_usec()

func _set_view(v: String) -> void:
	_view.show_heights = v == "heights"
	_view.show_manors = v == "manors"
	_view.show_armies = v == "military"
	_view.show_provinces = v == "provinces"

func _set_zoom(z: String) -> void:
	var center := _view.size / 2.0
	_view._go_home()
	if z == "world":
		_view._zoom_at(center, 0.0001)
	elif z == "close":
		_view._zoom_at(center, CLOSE_MUL)

func _build_steps() -> void:
	# The switches come first, while every view's caches are still cold.
	for v: String in ["heights", "manors", "military", "provinces"]:
		_steps.append({"kind": "switch", "name": "%s on (first)" % v, "view": v})
		_steps.append({"kind": "switch", "name": "back to political", "view": "political"})
		_steps.append({"kind": "switch", "name": "%s on (cached)" % v, "view": v})
		_steps.append({"kind": "switch", "name": "back to political", "view": "political"})
	for z: String in ZOOMS:
		for v: String in VIEWS:
			_steps.append({"kind": "pan", "name": "%s @ %s" % [v, z], "view": v, "zoom": z})

func _begin(step: Dictionary) -> void:
	_count = 0
	_samples.clear()
	_cpu.clear()
	_gpu.clear()
	_hover_us = 0
	_view.draw_profile.clear()
	_step_ms = Time.get_ticks_msec()
	print("bench: %s" % step["name"])
	if step["kind"] == "pan":
		_set_view(String(step["view"]))
		_set_zoom(String(step["zoom"]))
	else:
		_set_zoom("home")
		_set_view(String(step["view"]))
	_view.queue_redraw()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last) / 1000.0
	_last = now
	if _step < 0:
		_step = 0
		_begin(_steps[0])
		return
	var step: Dictionary = _steps[_step]
	_count += 1
	var pan := String(step["kind"]) == "pan"
	# This frame's time belongs to the work queued on the previous one.
	if not pan or _count > WARM_FRAMES:
		_samples.append(ms)
		var vp := get_viewport().get_viewport_rid()
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if pan:
		var before := _view._offset
		_view._offset += _dir
		_view._clamp_offset()
		if _view._offset.is_equal_approx(before):
			_dir = -_dir
		var h0 := Time.get_ticks_usec()
		_view.hover_at(_view.size / 2.0 + Vector2(float(_count % 40), 0.0))
		_hover_us += Time.get_ticks_usec() - h0
		_view.queue_redraw()
	var needed := _frames + WARM_FRAMES if pan else SWITCH_FRAMES
	var timed_out := Time.get_ticks_msec() - _step_ms > STEP_TIMEOUT_MS
	if _count < needed and not timed_out:
		return
	if timed_out:
		_lines.append("TIMEOUT %s after %d frames" % [step["name"], _count])
	_report(step)
	_step += 1
	if _step >= _steps.size():
		_finish()
		return
	_begin(_steps[_step])

static func _avg(values: Array) -> float:
	var total := 0.0
	for v: float in values:
		total += v
	return total / maxf(float(values.size()), 1.0)

func _report(step: Dictionary) -> void:
	if String(step["name"]) == "back to political" or _samples.is_empty():
		return
	var sorted := _samples.duplicate()
	sorted.sort()
	var avg := _avg(sorted)
	var p95: float = sorted[mini(int(float(sorted.size()) * 0.95), sorted.size() - 1)]
	var worst: float = sorted[sorted.size() - 1]
	var hitches := 0
	for s: float in sorted:
		if s > HITCH_MS:
			hitches += 1
	if step["kind"] == "pan":
		_lines.append("PAN    %-20s avg %6.2f ms (%4.0f fps)  p95 %6.2f  max %6.2f  >16.7ms %3d/%d  render cpu %5.2f gpu %5.2f" % [
			step["name"], avg, 1000.0 / maxf(avg, 0.001), p95, worst, hitches, sorted.size(),
			_avg(_cpu), _avg(_gpu)])
		# Where the script time went, in ms per frame over every frame of the
		# step (warm-up included, on both sides of the division).
		var per := 1000.0 * maxf(float(_count), 1.0)
		var layers: Array = _view.draw_profile.keys()
		layers.sort_custom(func(a: String, b: String) -> bool:
			return int(_view.draw_profile[a]) > int(_view.draw_profile[b]))
		var total := 0.0
		var parts: PackedStringArray = []
		for layer: String in layers:
			total += float(_view.draw_profile[layer]) / per
		for layer: String in layers.slice(0, 6):
			parts.append("%s %.1f" % [layer, float(_view.draw_profile[layer]) / per])
		_lines.append("         _draw %.1f ms: %s | hover %.1f ms" % [
			total, ", ".join(parts), float(_hover_us) / per])
	else:
		_lines.append("SWITCH %-20s worst frame %7.2f ms" % [step["name"], worst])

func _finish() -> void:
	var text := "\n".join(_lines)
	print(text)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
	else:
		print("bench: could not write %s (%d)" % [_out, FileAccess.get_open_error()])
	get_tree().quit()
