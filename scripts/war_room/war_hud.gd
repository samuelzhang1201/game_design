class_name WarHud
extends Control
## The war room's 2D overlay (spec 2026-10-01-war-room-design §3,
## 2026-10-08-war-room-draw-orders rulings 13, 14, 16, 18), in screen px: the
## selection's rings in its side's colour, Shift-drag's chalk marquee, every
## intel hint as a red ring of MARCHING ANTS (its dashes walk round as `phase`
## turns — redrawn each frame, never baked into a sheet's ink), each pennant's
## dashed route, each draft's graphite pencil, the pending route's waypoint
## rings, the towns that may supply a pending march (lit, or faint) and the
## BOLD DASHED GOLD road from the chosen one to the march's end. Draws only
## what WarRoomPointer hands it.

var _repo: DataRepository
var _rings: Array = []          # [{at, r, colour}]: the selection
var _marquee := Rect2()
var _hints: Array = []          # screen px of each intel hint
var _hint_c := Color.RED
var _chalk_c := Color.WHITE
var _phase := 0.0               # the ants' march, design px along the ring
var _routes: Array = []   # each piece's dashed line to its pennant, a polyline in screen px (its route's curve)
var _drafts: Array = []   # each draft's pencil line, a polyline in screen px (spec 2026-10-02-war-room-v2 §3.1)
var _ink := Color.BLACK
var _pencil := Color.GRAY
var _font: Font
var _handles := PackedVector2Array()  # the pending route's waypoints' rings
var _handle_c := Color.BLUE
var _towns: Array = []                # [{at, lit}]: the towns that may supply the pending march
var _road := PackedVector2Array()     # the chosen town's road to the march's end
var _gold := Color.GOLD


func setup(repo: DataRepository) -> void:
	_repo = repo


func draw_state(rings: Array, marquee: Rect2, hints: Array, hint_c: Color, chalk_c: Color, routes: Array,
		drafts: Array, ink: Color, pencil: Color, font: Font) -> void:
	_rings = rings
	_marquee = marquee
	_hints = hints
	_hint_c = hint_c
	_chalk_c = chalk_c
	_routes = routes
	_drafts = drafts
	_ink = ink
	_pencil = pencil
	_font = font
	queue_redraw()


## The pending route's waypoints' rings (spec 2026-10-07-march-waypoints).
func set_route(handles: PackedVector2Array, colour: Color) -> void:
	_handles = handles
	_handle_c = colour
	queue_redraw()


## The towns lit for the pending march and the chosen one's road (ruling 13-14).
func set_supply(towns: Array, road: PackedVector2Array, gold: Color) -> void:
	_towns = towns
	_road = road
	_gold = gold
	queue_redraw()


## The ants' march: redrawn only while a hint shows.
func set_phase(t: float) -> void:
	_phase = t * _repo.bal("war_intel_hint_speed_px") if _repo != null else 0.0
	if not _hints.is_empty():
		queue_redraw()


## The draft lines being drawn (tests read it).
func draft_lines() -> Array:
	return _drafts


## The marks drawn now (tests read them).
func marks() -> Dictionary:
	return {"rings": _rings, "marquee": _marquee, "hints": _hints, "towns": _towns, "road": _road}


## True when anything is drawn.
func drawing() -> bool:
	return not _rings.is_empty() or not _routes.is_empty() or not _drafts.is_empty() or not _hints.is_empty() \
		or _road.size() >= 2 or _marquee.has_area()


## A dashed line from `a` to `b` (the dash war_hud_dash_px unless `dash` is
## given, the gap its own length).
func _dashed(a: Vector2, b: Vector2, color: Color, width: float, dash := -1.0) -> void:
	var dir := (b - a).normalized()
	if dash <= 0.0:
		dash = _repo.bal("war_hud_dash_px")
	var run := a.distance_to(b)
	var at := 0.0
	while at < run:
		draw_line(a + dir * at, a + dir * minf(at + dash, run), color, width, true)
		at += dash * 2.0


## A draft's pencil stroke from the piece to its pennant: solid graphite, not
## the map's dashes (taste: a tool never borrows the map's line language),
## ending in a small open arrowhead; dashed only if war_draft_pencil_dash_px > 0.
func _pencilled(a: Vector2, b: Vector2) -> void:
	var width := _repo.bal("war_draft_pencil_px")
	var dash := _repo.bal("war_draft_pencil_dash_px")
	if dash > 0.0:
		_dashed(a, b, _pencil, width, dash)
	else:
		draw_line(a, b, _pencil, width, true)
	var head := _repo.bal("war_draft_head_px")
	if a.distance_to(b) <= head * 2.0:
		return
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tail := b - dir * head
	draw_polyline(PackedVector2Array([tail + side * head * 0.55, b, tail - side * head * 0.55]), _pencil, width, true)


## A ring of dashes `dash` long (the gap as long), walked round by `phase`.
func _ants(c: Vector2, r: float, colour: Color, width: float, dash: float, phase: float) -> void:
	var step := dash / maxf(r, 1.0)   # radians a dash spans
	var a := fposmod(phase / maxf(r, 1.0), step * 2.0)
	while a < TAU + step * 2.0:
		draw_arc(c, r, a - step * 2.0, a - step, 6, colour, width, true)
		a += step * 2.0


func _draw() -> void:
	if _repo == null:
		return
	# the supply road under everything else of the pending march: bold, dashed, gold
	if _road.size() >= 2:
		var w := _repo.bal("war_supply_route_px")
		var dash := _repo.bal("war_supply_route_dash_px")
		var edge := _gold.darkened(0.55)
		for piece: PackedVector2Array in _dash_runs(_road, dash, dash * 0.5):
			draw_polyline(piece, edge, w + 2.0, true)
		for piece: PackedVector2Array in _dash_runs(_road, dash, dash * 0.5):
			draw_polyline(piece, _gold, w, true)
	for t: Dictionary in _towns:
		var lit := bool(t["lit"])
		var r := _repo.bal("war_supply_lit_px")
		draw_arc(t["at"], r, 0.0, TAU, 28, Color(_gold, 1.0 if lit else 0.35), 3.0 if lit else 1.5, true)
	for line: Variant in _routes:
		var r := PackedVector2Array(line)
		if r.size() > 2:   # a route's curve: the dashes run on across its joints
			draw_multiline(MapRuler.dash_pieces(r, _repo.bal("war_hud_dash_px")), _ink, _repo.bal("war_hud_arrow_px"), true)
		elif r.size() == 2:
			_dashed(r[0], r[1], _ink, _repo.bal("war_hud_arrow_px"))
	for line: Variant in _drafts:
		var r := PackedVector2Array(line)
		if r.size() > 2:   # a route's curve, one stroke up to its last segment
			draw_polyline(r.slice(0, r.size() - 1), _pencil, _repo.bal("war_draft_pencil_px"), true)
		if r.size() >= 2:
			_pencilled(r[r.size() - 2], r[r.size() - 1])
	for h in _handles:
		draw_circle(h, _repo.bal("war_route_handle_px"), Color(_chalk_c, 0.85))
		draw_arc(h, _repo.bal("war_route_handle_px"), 0.0, TAU, 20, _handle_c, 2.0, true)
	var hr := _repo.bal("war_intel_hint_px")
	for h: Vector2 in _hints:
		_ants(h, hr, Color(_chalk_c, 0.8), _repo.bal("war_intel_hint_line_px") + 2.0, _repo.bal("war_intel_hint_dash_px"), _phase)
		_ants(h, hr, _hint_c, _repo.bal("war_intel_hint_line_px"), _repo.bal("war_intel_hint_dash_px"), _phase)
		draw_circle(h, 2.5, _hint_c)
	for ring: Dictionary in _rings:
		draw_arc(ring["at"], float(ring["r"]), 0.0, TAU, 48, Color(_chalk_c, 0.85), _repo.bal("war_select_ring_px") + 2.0, true)
		draw_arc(ring["at"], float(ring["r"]), 0.0, TAU, 48, ring["colour"], _repo.bal("war_select_ring_px"), true)
	if _marquee.has_area():
		var m := _marquee
		var corners := PackedVector2Array([m.position, Vector2(m.end.x, m.position.y), m.end, Vector2(m.position.x, m.end.y), m.position])
		draw_rect(m, Color(_chalk_c, 0.08))
		draw_multiline(MapRuler.dash_pieces(corners, _repo.bal("war_select_box_dash_px")), _chalk_c, 1.5, true)


## A polyline cut into dashes `dash` long with `gap` between.
static func _dash_runs(path: PackedVector2Array, dash: float, gap: float) -> Array:
	return WarPlanGeometry.dashes(path, dash, gap)
