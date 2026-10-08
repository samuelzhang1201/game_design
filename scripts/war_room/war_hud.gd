class_name WarHud
extends Control
## The war room's 2D overlay (spec 2026-10-01-war-room-design §3,
## 2026-10-08-war-room-draw-orders rulings 13, 14, 16, 18), in screen px: the
## selection's rings in its side's colour, Shift-drag's chalk marquee, every
## intel hint as a red ring of MARCHING ANTS (its dashes walk round as `phase`
## turns — redrawn each frame, never baked into a sheet's ink), the pending
## route's waypoint rings (the marches themselves are crayon arrows in
## WarPlanHud), the towns that may supply a pending march (lit, or faint) and the
## BOLD DASHED GOLD road from the chosen one to the march's end. Draws only
## what WarRoomPointer hands it.

var _repo: DataRepository
var _rings: Array = []          # [{at, r, colour}]: the selection
var _marquee := Rect2()
var _hints: Array = []          # screen px of each intel hint
var _hint_c := Color.RED
var _chalk_c := Color.WHITE
var _phase := 0.0               # the ants' march, design px along the ring
var _handles := PackedVector2Array()  # the pending route's waypoints' rings
var _handle_c := Color.BLUE
var _towns: Array = []                # [{at, lit}]: the towns that may supply the pending march
var _gold := Color.GOLD


func setup(repo: DataRepository) -> void:
	_repo = repo


func draw_state(rings: Array, marquee: Rect2, hints: Array, hint_c: Color, chalk_c: Color) -> void:
	_rings = rings
	_marquee = marquee
	_hints = hints
	_hint_c = hint_c
	_chalk_c = chalk_c
	queue_redraw()


## The pending route's waypoints' rings (spec 2026-10-07-march-waypoints).
func set_route(handles: PackedVector2Array, colour: Color) -> void:
	_handles = handles
	_handle_c = colour
	queue_redraw()


## The towns lit for the pending march (ruling 13).
func set_supply(towns: Array, gold: Color) -> void:
	_towns = towns
	_gold = gold
	queue_redraw()


## The ants' march: redrawn only while a hint shows.
func set_phase(t: float) -> void:
	_phase = t * _repo.bal("war_intel_hint_speed_px") if _repo != null else 0.0
	if not _hints.is_empty():
		queue_redraw()


## The marks drawn now (tests read them).
func marks() -> Dictionary:
	return {"rings": _rings, "marquee": _marquee, "hints": _hints, "towns": _towns}


## True when anything is drawn.
func drawing() -> bool:
	return not _rings.is_empty() or not _hints.is_empty() \
		or not _towns.is_empty() or _marquee.has_area()


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
	for t: Dictionary in _towns:
		var lit := bool(t["lit"])
		var r := _repo.bal("war_supply_lit_px")
		draw_arc(t["at"], r, 0.0, TAU, 28, Color(_gold, 1.0 if lit else 0.35), 3.0 if lit else 1.5, true)
	for h in _handles:
		draw_circle(h, _repo.bal("war_route_handle_px"), Color(_chalk_c, 0.85))
		draw_arc(h, _repo.bal("war_route_handle_px"), 0.0, TAU, 20, _handle_c, 2.0, true)
	var hr := _repo.bal("war_intel_hint_px")
	for h: Vector2 in _hints:
		_ants(h, hr, _hint_c.darkened(0.15), _repo.bal("war_intel_hint_line_px"), _repo.bal("war_intel_hint_dash_px"), _phase)
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
