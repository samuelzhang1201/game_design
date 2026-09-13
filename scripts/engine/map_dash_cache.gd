class_name MapDashCache
extends RefCounted
## The map's dashed lines — the chequered kingdom borders, the water
## hatching off every coast, the province seams, the shipping lanes — are
## measured in SCREEN px, so a line's dash pattern depends on the zoom and on
## nothing else: a pan moves every dash and cuts none. The view was still
## re-cutting every ring on every frame, and drawing every dash as its own
## command (bench 2026-09-13: 25–47 ms a frame in the cut alone, thousands of
## canvas commands behind it, 6–8 fps).
##
## This keeps each line cut ONCE per zoom, in NATIVE coordinates (a dash of
## dash_px screen px is dash_px / zoom native px), as ONE polyline: the gaps
## are in it too, as vertices of another phase, so the whole line — a kingdom's
## every ring, a realm's every seam — is a single draw_polyline_colors call
## whose per-vertex colours paint the dashes in ink and the gaps pale or
## clear. A frame transforms the points (Transform2D * PackedVector2Array,
## one C++ call) and draws. A zoom change or an ownership change empties it.
##
## Pure: no Nodes, no clock, headless-safe — tests/engine/test_map_dash_cache.gd.

## Vertex phases. ON is a dash, OFF the gap after it (drawn pale for a
## chequered border, clear for hatching), JUMP the invisible leap from the
## end of one line to the start of the next.
const ON := 1
const OFF := 0
const JUMP := 2
## A polyline's colours interpolate between vertices, so a dash boundary is
## a TWIN vertex: the boundary point once in each phase, this far apart
## along the line (native px). Far below a screen px at any zoom.
const HAIR := 0.01

## How many lines have been cut since construction — a test seam.
var builds := 0
var _zoom := 0.0
var _version := -1
var _entries: Dictionary = {}

func size() -> int:
	return _entries.size()

func clear() -> void:
	_entries.clear()

## The dashes of `lines` (each a native polyline, cut on its own so the
## pattern starts afresh at every line) at `zoom`, joined into one polyline:
## {points: PackedVector2Array, phase: PackedByteArray, bbox: Rect2}. `key`
## names the line set; `version` is whatever should invalidate it (the
## ownership hash). Returns the kept entry when it is already cut.
func cut(key: String, zoom: float, version: int, lines: Array,
		dash_px: float, gap_px: float, min_step_px: float = 0.0) -> Dictionary:
	if zoom != _zoom or version != _version:
		_entries.clear()
		_zoom = zoom
		_version = version
	if _entries.has(key):
		return _entries[key]
	var z := maxf(zoom, 0.000001)
	var step := min_step_px / z
	var points := PackedVector2Array()
	var phase := PackedByteArray()
	var bbox := Rect2()
	var first := true
	for raw: PackedVector2Array in lines:
		var line := thin(raw, step)
		if line.size() < 2:
			continue
		var runs := MapGeometry.dash_runs(line, dash_px / z, gap_px / z)
		if runs.is_empty():
			continue
		var b := MapGeometry.bounds(line)
		bbox = b if first else bbox.merge(b)
		if not first:
			_jump_in(points, phase, line, int(runs[0]["on"]))
		first = false
		var prev_phase := -1
		for run: Dictionary in runs:
			var pts: PackedVector2Array = run["points"]
			var ph := ON if bool(run["on"]) else OFF
			var start := 0
			if prev_phase >= 0:
				# The boundary point is already in as the previous run's
				# last vertex; its twin sits a hair INTO this run.
				points.append(pts[0] + _dir(pts[0], pts[1]) * HAIR)
				phase.append(ph)
				start = 1
			for i in range(start, pts.size()):
				points.append(pts[i])
				phase.append(ph)
			prev_phase = ph
	var entry := {"points": points, "phase": phase, "bbox": bbox, "colors": {}}
	_entries[key] = entry
	builds += 1
	return entry

## cut() for a caller whose lines cost something to gather: `build` (-> Array
## of PackedVector2Array) is called only on a miss, so a pan — every frame a
## hit — gathers nothing.
func cut_lazy(key: String, zoom: float, version: int, build: Callable,
		dash_px: float, gap_px: float, min_step_px: float = 0.0) -> Dictionary:
	if zoom == _zoom and version == _version and _entries.has(key):
		return _entries[key]
	return cut(key, zoom, version, build.call(), dash_px, gap_px, min_step_px)

## A line with no two kept vertices closer than `step` (native px), its two
## ends always kept. The rings are Catmull-Rom sampled eight times per pack
## segment — about one native px apart — so zoomed out they carry several
## vertices per SCREEN px, and every one of them costs the strip builder the
## same. Thinned to the zoom, the curve is the same to the eye and a third
## of the work. `step` 0 keeps everything.
static func thin(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := line.size()
	if step <= 0.0 or n < 3:
		return line
	var out := PackedVector2Array([line[0]])
	var last: Vector2 = line[0]
	var min_sq := step * step
	for i in range(1, n - 1):
		if line[i].distance_squared_to(last) >= min_sq:
			out.append(line[i])
			last = line[i]
	out.append(line[n - 1])
	return out

## Per-vertex colours for an entry: ON in `ink`, OFF in `pale`, JUMP clear.
## Built once per colour pair and kept on the entry.
func colors(entry: Dictionary, ink: Color, pale: Color) -> PackedColorArray:
	var by_pair: Dictionary = entry["colors"]
	var pair_key := ink.to_html(true) + "|" + pale.to_html(true)
	if by_pair.has(pair_key):
		return by_pair[pair_key]
	var phase: PackedByteArray = entry["phase"]
	var out := PackedColorArray()
	out.resize(phase.size())
	var clear := Color(ink, 0.0)
	for i in phase.size():
		match phase[i]:
			ON:
				out[i] = ink
			OFF:
				out[i] = pale
			_:
				out[i] = clear
	by_pair[pair_key] = out
	return out

## The leap from the end of what is drawn so far to the start of `line`:
## a hair beyond the last vertex in its own phase, so the strip's join at the
## true end still runs along the line and the dash does not pinch; then the
## two clear JUMP vertices; then a hair before the line's first point in the
## line's first phase, for the same reason on the way in. The line's own
## first vertex follows from cut().
static func _jump_in(points: PackedVector2Array, phase: PackedByteArray,
		line: PackedVector2Array, first_on: int) -> void:
	var n := points.size()
	var out_dir := _dir(points[n - 2], points[n - 1])
	var last_phase := phase[n - 1]
	var end: Vector2 = points[n - 1]
	points.append(end + out_dir * HAIR)
	phase.append(last_phase)
	points.append(end + out_dir * HAIR * 2.0)
	phase.append(JUMP)
	var in_dir := _dir(line[0], line[1])
	points.append(line[0] - in_dir * HAIR * 2.0)
	phase.append(JUMP)
	points.append(line[0] - in_dir * HAIR)
	phase.append(ON if first_on == 1 else OFF)

static func _dir(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	return d if d.length_squared() > 0.0 else Vector2.RIGHT
