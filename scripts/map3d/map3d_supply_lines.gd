class_name Map3DSupplyLines
extends RefCounted
## The supply lines on the 3D map (owner 2026-10-07: 一个淡淡的虚化的补给线, spec
## 2026-10-07-army-supply-lines §5.3): one faint ribbon per FLOWING line,
## along the road from its town to the column, its end following the piece
## where Map3DLayerUnits draws it on its day's march; an ordered, riding or
## cut line is not drawn (the card and the missives say why), nor any while
## the regiments are hidden. While a supply point is picked (the view's
## supply_pick, burg -> "" lit or the reason it is greyed), a ring round each
## realm town at its reach — the ground a click names it by (ArmySystem.town_at)
## — and the chosen town's road dashed (supply_preview, pack px). Looks:
## scenes/map3d/materials/lines/supply_*.tres. Never the Game autoload.

var ctx: Map3DContext
var lines: Map3DLayerLines
## The view, read for supply_pick / supply_preview.
var view: Object
## The drawn pieces (shown_positions); null draws the lines to the engine's spot.
var units: Map3DLayerUnits
var _sig := 0
var _ends_sig := 0
## code -> the flowing line's road in world XZ, as of _sig.
var _roads: Dictionary = {}
## The drawn roads' segments by grid cell, per pack (on_roads).
static var _index: Dictionary = {}


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_view: Object, p_units: Map3DLayerUnits) -> void:
	ctx = p_ctx
	lines = p_lines
	view = p_view
	units = p_units
	_sig = 0
	_ends_sig = 0


## A road (pack px) in world XZ, laid on the drawn roads, a point every line step.
static func _world(ctx: Map3DContext, route: PackedVector2Array) -> PackedVector2Array:
	var step_px := ctx.line_step() / maxf(float(ctx.meta.get("m_per_px", 1.0)), 0.001)
	var pts := PackedVector2Array()
	for p in on_roads(ctx.repo, Map3DGeometry.resample(route, step_px)):
		pts.append(ctx.to_world(p))
	return pts


## The drawn roads' segments (pack px, smoothed as Map3DBorders.route_lines
## draws them) in every grid cell within the snap reach of them.
static func _road_index(repo: DataRepository) -> Dictionary:
	var key := "%d:%s" % [repo.get_instance_id(), repo.map_id]
	if _index.has(key):
		return _index[key]
	var reach := repo.bal("courier_graph_snap_px")
	var size := maxf(reach * 2.0, 1.0)
	var grid: Dictionary = {}
	var steps := int(repo.bal("map_route_smoothing_steps"))
	for code: String in repo.routes:
		var r: Dictionary = repo.routes[code]
		if not RoadGraph.GROUPS.has(String(r.get("group", ""))):
			continue
		var line := MapGeometry.smooth_open(r["polyline"], steps)
		for i in range(1, line.size()):
			var a := line[i - 1]
			var b := line[i]
			var lo := Vector2i(((a.min(b) - Vector2(reach, reach)) / size).floor())
			var hi := Vector2i(((a.max(b) + Vector2(reach, reach)) / size).floor())
			for gy in range(lo.y, hi.y + 1):
				for gx in range(lo.x, hi.x + 1):
					var cell := Vector2i(gx, gy)
					if not grid.has(cell):
						grid[cell] = []
					(grid[cell] as Array).append([a, b])
	_index = {key: {"size": size, "reach": reach, "grid": grid}}
	return _index[key]


## `route` (pack px) moved onto the drawn roads: the courier's road runs
## through RoadGraph's snapped nodes, up to `courier_graph_snap_px` off the
## road the map draws; each point within that reach goes to the nearest point
## of a drawn road, its ends (the town, the column) stay.
static func on_roads(repo: DataRepository, route: PackedVector2Array) -> PackedVector2Array:
	var idx := _road_index(repo)
	var size: float = idx["size"]
	var reach: float = idx["reach"]
	var grid: Dictionary = idx["grid"]
	var out := route.duplicate()
	for i in range(1, route.size() - 1):
		var p := route[i]
		var best := p
		var best_d := reach * reach
		for seg: Array in grid.get(Vector2i((p / size).floor()), []):
			var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
			var d := q.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = q
		out[i] = best
	return out


## Every FLOWING line's road in world XZ, {code: points}, the town first.
static func roads_world(ctx: Map3DContext) -> Dictionary:
	var out := {}
	var st := ctx.state()
	if st == null:
		return out
	var codes: Array = st.supply_lines.keys()
	codes.sort()
	for c in codes:
		if String((st.supply_lines[c] as Dictionary).get("state", "")) != SupplyLines.FLOWING:
			continue
		var route := SupplySystem.route_px(ctx.repo, st, String(c))
		if route.size() >= 2:
			out[String(c)] = _world(ctx, route)
	return out


## Every FLOWING line's road in world XZ, code order; with `shown` ({code:
## world XZ}, where the pieces are drawn) each ends at its piece.
static func lines_world(ctx: Map3DContext, shown: Dictionary = {}) -> Array:
	var roads := roads_world(ctx)
	var out: Array = []
	for code: String in roads:
		out.append(_to_piece(ctx, code, roads[code], shown))
	return out


## `road` to where its regiment's piece is drawn — only within the distance a
## drawn piece may stand from the engine's spot (Map3DUnits.snap_m), so a
## piece no longer walking (quartered, gone) leaves the road as it was.
static func _to_piece(ctx: Map3DContext, code: String, road: PackedVector2Array, shown: Dictionary) -> PackedVector2Array:
	if not shown.has(code) or road.is_empty():
		return road
	var piece: Vector2 = shown[code]
	if piece.distance_to(road[road.size() - 1]) > Map3DUnits.snap_m(ctx.repo, ctx.state(), code, ctx.meta):
		return road
	return follow(road, piece)


## `road` ending at `piece`: cut at the road's nearest point to it (the end
## when that is as near) and run on to the piece — a piece walking on past the
## end extends it, one walking back along the road shortens it.
static func follow(road: PackedVector2Array, piece: Vector2) -> PackedVector2Array:
	if road.size() < 2:
		return road
	var best_i := road.size() - 1
	var best := road[best_i]
	var best_d := best.distance_squared_to(piece)
	for i in range(1, road.size()):
		var q := Geometry2D.get_closest_point_to_segment(piece, road[i - 1], road[i])
		var d := q.distance_squared_to(piece)
		if d < best_d - 0.0001:
			best_d = d
			best_i = i
			best = q
	var out := road.slice(0, best_i)
	if out[out.size() - 1].distance_to(best) > 0.01:
		out.append(best)
	if best.distance_to(piece) > 0.01:
		out.append(piece)
	return out


static func _ring(ctx: Map3DContext, burg: Dictionary) -> PackedVector2Array:
	var c := Vector2(float(burg["x"]), float(burg["y"]))
	var r := ArmySystem.town_reach_px(ctx.repo, burg)
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * float(i) / 48.0
		pts.append(ctx.to_world(c + Vector2(cos(a), sin(a)) * r))
	return Map3DGeometry.resample(pts, ctx.line_step())


func _shown() -> Dictionary:
	return units.shown_positions() if units != null else {}


## Lay the flowing lines from the roads in hand, each to its drawn piece.
func _draw_lines() -> void:
	var shown := _shown()
	var out: Array = []
	if units == null or units.shown:
		for code: String in _roads:
			out.append(_to_piece(ctx, code, _roads[code], shown))
	lines.set_lines("SupplyLines", out, Map3DLayerLines.SUPPLY_LINE, Map3DPriority.SUPPLY_LINES)


## Everything again: the lines' roads, the pick's rings and its preview.
func redraw() -> void:
	if ctx == null or lines == null:
		return
	_roads = roads_world(ctx)
	_draw_lines()
	var pick: Dictionary = view.get("supply_pick") if view != null and "supply_pick" in view else {}
	var lit: Array = []
	var off: Array = []
	var towns: Array = pick.keys()
	towns.sort()
	for t: String in towns:
		if ctx.repo.burgs.has(t):
			(lit if String(pick[t]) == "" else off).append(_ring(ctx, ctx.repo.burgs[t]))
	lines.set_lines("SupplyPick", lit, Map3DLayerLines.SUPPLY_PICK, Map3DPriority.SELECTION)
	lines.set_lines("SupplyPickOff", off, Map3DLayerLines.SUPPLY_PICK_OFF, Map3DPriority.SELECTION)
	var preview: PackedVector2Array = (view.get("supply_preview") if view != null
		and "supply_preview" in view else PackedVector2Array())
	lines.set_lines("SupplyPreview", [_world(ctx, preview)] if preview.size() >= 2 else [],
		Map3DLayerLines.SUPPLY_PREVIEW, Map3DPriority.SELECTION)


## Per frame: everything again when the day turned or a line changed; only the
## lines' ends when a piece with a line has walked a line step. Cheap otherwise.
func step() -> void:
	var st := ctx.state() if ctx != null else null
	if st == null or lines == null:
		return
	var sig := hash([st.absolute_day(), st.supply_lines.hash()])
	if sig != _sig:
		_sig = sig
		redraw()
		_ends_sig = _ends()
	elif _ends() != _ends_sig:
		_ends_sig = _ends()
		_draw_lines()


## Where the pieces with a line are drawn, to a line step, and whether shown.
func _ends() -> int:
	var shown := _shown()
	var ends: Array = [units != null and units.shown]
	var q := maxf(ctx.line_step(), 1.0)
	for code: String in _roads:
		ends.append(Vector2i((shown.get(code, Vector2.ZERO) as Vector2) / q))
	return hash(ends)
