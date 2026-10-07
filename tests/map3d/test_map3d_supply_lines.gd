extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The faint supply lines (spec 2026-10-07-army-supply-lines §5.3): only
## FLOWING lines are drawn, town first, and the line's end follows the piece
## where the map draws it; a supply pick rings the realm's towns.

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

## The view's two pick fields (Map3DView.supply_pick / supply_preview).
class FakeView extends Node:
	var supply_pick: Dictionary = {}
	var supply_preview := PackedVector2Array()


## A units layer whose drawn spots the test sets.
class FakeUnits extends Map3DLayerUnits:
	var pos: Dictionary = {}

	func shown_positions() -> Dictionary:
		return pos


var _repo: DataRepository
var _s: GameState
var _code := ""
var _town := ""


func before_each() -> void:
	_repo = SuiteData.repo()
	_s = SuiteData.campaign(_repo, 42)
	var codes: Array = _s.regiments.keys()
	codes.sort()
	_code = String(codes[0])
	_town = String(TownStores.realm_towns(_repo, _s)[0])
	_s.supply_lines[_code] = SupplyLines._new_record(_town, 1000, 1)


func _ctx() -> Map3DContext:
	var ctx := Map3DContext.new(_repo, WORLD)
	var s := _s
	ctx.state_fn = func() -> GameState: return s
	return ctx


func test_only_flowing_lines_are_drawn() -> void:
	var ctx := _ctx()
	for st: String in [SupplyLines.ORDERED, SupplyLines.RIDING, SupplyLines.CUT]:
		_s.supply_lines[_code]["state"] = st
		assert_eq(Map3DSupplyLines.lines_world(ctx).size(), 0, st)
	_s.supply_lines[_code]["state"] = SupplyLines.FLOWING
	assert_eq(Map3DSupplyLines.lines_world(ctx).size(), 1)


func test_a_flowing_line_runs_from_its_town_to_the_column() -> void:
	_s.supply_lines[_code]["state"] = SupplyLines.FLOWING
	var ctx := _ctx()
	var pts: PackedVector2Array = Map3DSupplyLines.lines_world(ctx)[0]
	var b: Dictionary = _repo.burgs[_town]
	assert_almost_eq(pts[0], ctx.to_world(Vector2(float(b["x"]), float(b["y"]))), Vector2(0.01, 0.01))
	var reg := ArmySystem.regiment(_repo, _code)
	assert_almost_eq(pts[pts.size() - 1], ctx.to_world(ArmySystem.position_of(_repo, _s, reg)),
		Vector2(0.01, 0.01))


## The piece walks its day's march off the engine's spot: the line ends at the
## piece, cut back to the road's nearest point when it walks back along it.
func test_the_end_follows_the_drawn_piece() -> void:
	var road := PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 0)])
	var ahead := Map3DSupplyRoad.follow(road, Vector2(2300, 100))
	assert_eq(ahead.size(), 4)
	assert_eq(ahead[3], Vector2(2300, 100))
	var back := Map3DSupplyRoad.follow(road, Vector2(1500, 40))
	assert_eq(back, PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(1500, 0), Vector2(1500, 40)]))
	assert_eq(Map3DSupplyRoad.follow(road, Vector2(2000, 0)), road, "at the end: unchanged")


## Only a piece drawn within a few days' march of its regiment's spot moves
## the line's end; a stale spot (a piece no longer drawn) leaves the road.
func test_the_line_ends_at_the_drawn_piece_nearby() -> void:
	_s.supply_lines[_code]["state"] = SupplyLines.FLOWING
	var ctx := _ctx()
	var road: PackedVector2Array = Map3DSupplyLines.lines_world(ctx)[0]
	var end := road[road.size() - 1]
	var walked: PackedVector2Array = Map3DSupplyLines.lines_world(ctx, {_code: end + Vector2(40, 30)})[0]
	assert_eq(walked[walked.size() - 1], end + Vector2(40, 30))
	var far := end + Vector2(1.0e7, 0)
	assert_eq(Map3DSupplyLines.lines_world(ctx, {_code: far})[0], road, "a stale spot is ignored")


## The courier's road runs through RoadGraph's snapped nodes: the line is laid
## back on the road the map draws, its ends where they were.
func test_the_line_lies_on_the_drawn_road() -> void:
	var codes: Array = _repo.routes.keys()
	codes.sort()
	var r: Dictionary = {}
	for c: String in codes:
		if String(_repo.routes[c]["group"]) == "roads" and (_repo.routes[c]["polyline"] as PackedVector2Array).size() > 4:
			r = _repo.routes[c]
			break
	var drawn := MapGeometry.smooth_open(r["polyline"], int(_repo.bal("map_route_smoothing_steps")))
	@warning_ignore("integer_division")
	var on := drawn[drawn.size() / 2]
	var off := on + Vector2(0.7, -0.7)
	var route := PackedVector2Array([Vector2(-50, -50), off, Vector2(-60, -60)])
	var laid := Map3DSupplyRoad.on_roads(_repo, route)
	assert_eq(laid[0], route[0])
	assert_eq(laid[2], route[2])
	assert_lt(laid[1].distance_to(on), off.distance_to(on), "moved toward the road")
	var near := INF
	for i in range(1, drawn.size()):
		near = minf(near, Geometry2D.get_closest_point_to_segment(laid[1], drawn[i - 1], drawn[i]).distance_to(laid[1]))
	assert_almost_eq(near, 0.0, 0.001, "on a drawn road")


## The layer over a bare Lines host, the fake view's pick and `units`.
func _layer(units: Map3DLayerUnits = null) -> Array:
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 450)
	add_child_autofree(vp)
	var ctx := _ctx()
	ctx.viewport = vp
	var lines := Map3DLayerLines.new()
	vp.add_child(lines)
	lines.bind(ctx)
	var view := FakeView.new()
	autofree(view)
	var layer := Map3DSupplyLines.new()
	layer.bind(ctx, lines, view, units)
	return [layer, lines, view]


func test_the_layer_draws_the_line_the_rings_and_the_preview() -> void:
	_s.supply_lines[_code]["state"] = SupplyLines.FLOWING
	var got := _layer()
	var layer: Map3DSupplyLines = got[0]
	var lines: Map3DLayerLines = got[1]
	var view: FakeView = got[2]
	var towns := TownStores.realm_towns(_repo, _s)
	view.supply_pick = {towns[0]: "", towns[1]: "too far"}
	layer.redraw()
	assert_not_null(lines.line_mesh("SupplyLines"))
	assert_not_null(lines.line_mesh("SupplyPick"))
	assert_not_null(lines.line_mesh("SupplyPickOff"))
	assert_null(lines.line_mesh("SupplyPreview"), "no town chosen yet")
	assert_eq((lines.line_mesh("SupplyLines").surface_get_material(0) as ShaderMaterial).render_priority,
		Map3DPriority.SUPPLY_LINES)
	view.supply_preview = SupplySystem.route_px(_repo, _s, _code)
	var draws := layer.draws
	layer.redraw_pick()
	assert_not_null(lines.line_mesh("SupplyPreview"), "the chosen town's road")
	assert_eq(layer.draws, draws, "a pick change lays no line again")
	view.supply_pick = {}
	view.supply_preview = PackedVector2Array()
	layer.redraw_pick()
	assert_null(lines.line_mesh("SupplyPick"), "the pick ended: no lit ring")
	assert_null(lines.line_mesh("SupplyPickOff"), "nor a greyed one")
	assert_null(lines.line_mesh("SupplyPreview"), "nor the road")
	_s.supply_lines[_code]["state"] = SupplyLines.CUT
	layer.step(0.0)
	assert_null(lines.line_mesh("SupplyLines"), "a cut line is not drawn")
	await wait_process_frames(2)  # the replaced ribbons' queue_free


## The lines are laid when a line's day or record moves, not every frame.
func test_step_lays_the_lines_only_when_they_moved() -> void:
	_s.supply_lines[_code]["state"] = SupplyLines.FLOWING
	var layer: Map3DSupplyLines = _layer()[0]
	layer.step(0.016)
	assert_eq(layer.draws, 1)
	for i in 5:
		layer.step(0.016)
	assert_eq(layer.draws, 1, "nothing moved")
	_s.supply_lines[_code]["rate"] = 1200
	layer.step(0.016)
	assert_eq(layer.draws, 2, "the line's record moved")
	_s.day += 1
	layer.step(0.016)
	assert_eq(layer.draws, 3, "the day turned")
	layer.step(0.016)
	assert_eq(layer.draws, 3)
	await wait_process_frames(2)


## Whether the tail's mesh ends at `xz` (its last vertex pair, world XZ).
func _tail_reaches(lines: Map3DLayerLines, xz: Vector2) -> bool:
	var mesh := lines.line_mesh("SupplyTails")
	if mesh == null:
		return false
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var last := verts[verts.size() - 1]
	return Vector2(last.x, last.z).distance_to(xz) < 0.5


## Hidden regiments draw no line; a walking piece moves the tail every frame
## and the body at most once every map3d_supply_follow_s.
func test_the_lines_follow_the_units_layer() -> void:
	_s.supply_lines[_code]["state"] = SupplyLines.FLOWING
	var units := FakeUnits.new()
	autofree(units)
	var got := _layer(units)
	var layer: Map3DSupplyLines = got[0]
	var lines: Map3DLayerLines = got[1]
	units.shown = false
	layer.step(0.016)
	assert_null(lines.line_mesh("SupplyLines"), "the regiments are hidden")
	units.shown = true
	layer.step(0.016)
	assert_not_null(lines.line_mesh("SupplyLines"), "shown again, at once")
	var road: PackedVector2Array = Map3DSupplyLines.lines_world(_ctx())[0]
	var end := road[road.size() - 1]
	units.pos = {_code: end}
	var drawn := layer.draws
	layer.step(0.01)
	assert_eq(layer.draws, drawn + 1, "a piece come onto its road: the body is cut for it at once")
	drawn = layer.draws
	var on := (end - road[road.size() - 2]).normalized()  # walking on along the road's last stretch
	var piece := end + on * _repo.bal("map3d_line_step_m") * 3.0
	units.pos = {_code: piece}
	layer.step(0.01)
	assert_eq(layer.draws, drawn, "within the throttle the body waits")
	assert_true(_tail_reaches(lines, piece), "but the tail follows the piece that frame")
	units.pos = {_code: piece + on * 20.0}
	layer.step(0.01)
	assert_true(_tail_reaches(lines, piece + on * 20.0), "and the next")
	layer.step(_repo.bal("map3d_supply_follow_s"))
	assert_eq(layer.draws, drawn + 1, "then the body is laid again")
	layer.step(_repo.bal("map3d_supply_follow_s"))
	assert_eq(layer.draws, drawn + 1, "a piece standing still lays nothing")
	await wait_process_frames(2)


## The tail carries the body's arc in UV.x, so the flow runs on across the cut.
func test_the_tail_runs_on_from_the_body() -> void:
	var road := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0), Vector2(300, 0)])
	var at := Map3DSupplyRoad.nearest(road, Vector2(250, 30))
	assert_eq(int(at[0]), 3)
	assert_eq(at[1], Vector2(250, 0))
	var tail := Map3DSupplyRoad.tail(road, 2, Vector2(250, 30), at)
	assert_eq(tail, PackedVector2Array([Vector2(100, 0), Vector2(200, 0), Vector2(250, 0), Vector2(250, 30)]))
	assert_eq(Map3DSupplyRoad.follow(road, Vector2(250, 30)),
		road.slice(0, 2) + tail.slice(1), "the body and its tail are the followed road")
	var flat := func(_xz: Vector2) -> float: return 0.0
	var arrays := Map3DSupplyRoad.tail_arrays([tail, tail], [100.0, 7.0], flat)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs[0].x, 100.0, "the first tail starts at its body's arc")
	assert_eq(uvs[tail.size() * 2].x, 7.0, "the second at its own")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 2 * (tail.size() - 1) * 6)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array)[(tail.size() - 1) * 6], tail.size() * 2,
		"the second tail's triangles index its own vertices")
