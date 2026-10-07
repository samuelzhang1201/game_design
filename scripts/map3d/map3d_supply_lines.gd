class_name Map3DSupplyLines
extends RefCounted
## The supply lines on the 3D map (spec 2026-10-07-army-supply-lines §5.3;
## owner 2026-10-07: 实心的金色线，带流动感，实时跟随军队移动): one solid gold
## ribbon per FLOWING line, flowing from its town to the column along the
## road, its end following the piece where Map3DLayerUnits draws it every
## frame (a body and a tail, Map3DSupplyRoad); an ordered, riding or
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
## How many times the flowing lines were laid (a test seam).
var draws := 0
## code -> hash(day, its line record): the road below was searched for it.
var _line_sigs: Dictionary = {}
## code -> the flowing line's road in world XZ, searched once a day a line.
var _roads: Dictionary = {}
var _shown_on := true
## Seconds since the bodies were last laid (map3d_supply_follow_s).
var _since := 0.0
## code -> [cut, arc]: the body runs over the road's points before `cut`, `arc` metres long.
var _cut: Dictionary = {}
## Where the pieces were when the bodies, and the tails, were last laid.
var _body_sig := 0
var _tail_sig := 0


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_view: Object, p_units: Map3DLayerUnits) -> void:
	ctx = p_ctx
	lines = p_lines
	view = p_view
	units = p_units
	_line_sigs.clear()
	_roads.clear()
	_cut.clear()


## A road (pack px) in world XZ, laid on the drawn roads, a point every line step.
static func _world(ctx: Map3DContext, route: PackedVector2Array) -> PackedVector2Array:
	var step_px := ctx.line_step() / maxf(float(ctx.meta.get("m_per_px", 1.0)), 0.001)
	var pts := PackedVector2Array()
	for p in Map3DSupplyRoad.on_roads(ctx.repo, Map3DGeometry.resample(route, step_px)):
		pts.append(ctx.to_world(p))
	return pts


## Every FLOWING line's road in world XZ, {code: points}, the town first.
static func roads_world(ctx: Map3DContext) -> Dictionary:
	var out := {}
	var st := ctx.state()
	if st == null:
		return out
	for code: String in _flowing(st):
		var road := _road_of(ctx, st, code)
		if road.size() >= 2:
			out[code] = road
	return out


## The regiments whose line is FLOWING, code order.
static func _flowing(st: GameState) -> Array:
	var out: Array = []
	for c in st.supply_lines.keys():
		if String((st.supply_lines[c] as Dictionary).get("state", "")) == SupplyLines.FLOWING:
			out.append(String(c))
	out.sort()
	return out


## One line's road in world XZ (its route searched now), or empty.
static func _road_of(ctx: Map3DContext, st: GameState, code: String) -> PackedVector2Array:
	var route := SupplySystem.route_px(ctx.repo, st, code)
	return _world(ctx, route) if route.size() >= 2 else PackedVector2Array()


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
	return Map3DSupplyRoad.follow(road, piece)


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


## Where `code`'s piece is drawn while it walks its line's road (within
## Map3DUnits.snap_m of the road's end, as _to_piece); null else.
func _piece(code: String, shown: Dictionary) -> Variant:
	var road: PackedVector2Array = _roads.get(code, PackedVector2Array())
	if not shown.has(code) or road.size() < 2:
		return null
	var at: Vector2 = shown[code]
	return at if at.distance_to(road[road.size() - 1]) <= Map3DUnits.snap_m(ctx.repo, ctx.state(), code, ctx.meta) else null


## Lay the bodies — each road up to its cut by its drawn piece, or whole —
## from the roads in hand, then the tails.
func _draw_lines() -> void:
	draws += 1
	var shown := _shown()
	var out: Array = []
	_cut.clear()
	if units == null or units.shown:
		var codes: Array = _roads.keys()
		codes.sort()
		for code: String in codes:
			var road: PackedVector2Array = _roads[code]
			var piece: Variant = _piece(code, shown)
			if piece == null:
				out.append(road)
				continue
			var body := road.slice(0, int(Map3DSupplyRoad.nearest(road, piece)[0]))
			_cut[code] = [body.size(), Map3DSupplyRoad.arc(body)]
			out.append(body)
	lines.set_lines("SupplyLines", out, Map3DLayerLines.SUPPLY_LINE, Map3DPriority.SUPPLY_LINES)
	_body_sig = _pieces_sig()
	_draw_tails()


## Each tail from its body's cut to its piece, UV carried on from the body;
## false (nothing laid) when a piece came onto or left its road.
func _draw_tails() -> bool:
	var shown := _shown()
	var tails: Array = []
	var offsets: Array = []
	var codes: Array = _roads.keys()
	codes.sort()
	for code: String in codes:
		var road: PackedVector2Array = _roads[code]
		var piece: Variant = _piece(code, shown)
		if (piece == null) != (not _cut.has(code)):
			return false  # a piece came onto, or left, its road: the bodies again
		if piece == null:
			continue
		var cut := int(_cut[code][0])
		var at := Map3DSupplyRoad.nearest(road, piece)
		# nearer a stretch before the cut (walked back, or off the road's
		# end): straight from the cut until the body is laid again
		tails.append(Map3DSupplyRoad.tail(road, cut, piece, at) if int(at[0]) >= cut
			else PackedVector2Array([road[cut - 1], piece]))
		offsets.append(float(_cut[code][1]))
	_tail_sig = _pieces_sig()
	lines.put_look("SupplyTails", Map3DSupplyRoad.tail_arrays(tails, offsets, ctx.height_at),
		Map3DLayerLines.SUPPLY_LINE, Map3DPriority.SUPPLY_LINES)
	return true


## Search again each FLOWING line whose day or record moved since its road
## was searched; forget the lines no longer flowing. True when any changed.
func _refresh_roads(st: GameState) -> bool:
	var day := st.absolute_day()
	var live := {}
	var changed := false
	for code: String in _flowing(st):
		live[code] = true
		var sig := hash([day, (st.supply_lines[code] as Dictionary).hash()])
		if _line_sigs.get(code, 0) == sig:
			continue
		_line_sigs[code] = sig
		changed = true
		var road := _road_of(ctx, st, code)
		if road.size() >= 2:
			_roads[code] = road
		else:
			_roads.erase(code)
	for code: String in _line_sigs.keys():
		if not live.has(code):
			_line_sigs.erase(code)
			_roads.erase(code)
			changed = true
	return changed


## The lines again, every road searched anew, and the pick.
func redraw() -> void:
	if ctx == null or lines == null:
		return
	_line_sigs.clear()
	_roads.clear()
	var st := ctx.state()
	if st != null:
		_refresh_roads(st)
	_draw_lines()
	redraw_pick()


## The pick's rings and its preview only (the view's supply_pick /
## supply_preview setters): no line's road is searched.
func redraw_pick() -> void:
	if ctx == null or lines == null:
		return
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


## Per frame. A line's road is searched once a day (or when its record
## moves) and the lines laid at once; a piece walking with a line re-lays its
## short tail every frame it moved, and the bodies from the roads in hand — no
## search — at most once every map3d_supply_follow_s (at once when a piece
## comes onto or leaves its road); hiding or showing the regiments, at once.
func step(delta: float) -> void:
	var st := ctx.state() if ctx != null else null
	if st == null or lines == null:
		return
	_since += delta
	var fresh := _refresh_roads(st)
	var on := units == null or units.shown
	var moved := _pieces_sig()
	if fresh or on != _shown_on or (moved != _body_sig and _since >= ctx.repo.bal("map3d_supply_follow_s")):
		_shown_on = on
		_since = 0.0
		_draw_lines()
	elif moved != _tail_sig and not _draw_tails():
		_since = 0.0
		_draw_lines()


## Where the pieces with a line are drawn.
func _pieces_sig() -> int:
	var shown := _shown()
	var at: Array = []
	for code: String in _roads:
		at.append(shown.get(code, Vector2.ZERO))
	return hash(at)
