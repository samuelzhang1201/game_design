class_name Map3DHudArmies
extends Map3DHudPiece
## MILITARY on the 3D map's HUD: a land unit is its 3D piece (Map3DLayerUnits)
## with NOTHING drawn over it — no counter, chip, number, bar or leader line
## (owner 2026-10-10: 请移除大地图上军事单位的所有标记和数字的mark) — and a
## selected one is shown by a faint glow on the ground under it. A unit with
## no piece (a fleet) keeps its flat counter (ArmyCounters). Each march's road
## ahead and its end ring are drawn here too. Its sizes are edited on the node.

## A fleet counter's height, design px, held between these (owner 2026-09-19:
## 注意兵棋大小) — it reads far out and never swamps the ground close in.
@export var badge_min_px := 18.0
@export var badge_max_px := 30.0
## The dashed road a marching regiment still has ahead, design px wide (in
## the realm's own colour); its end ring is four times it.
@export var route_px := 2.0
## The Shift-drag selection box's line (spec 2026-10-07-army-split-and-ground
## §5.6), design px; edited on the node.
@export var box_color := Color(1.0, 0.92, 0.6, 0.9)
@export var box_width_px := 1.5
## The selection's glow: a soft ring lying on the ground under each selected
## piece, `glow_scale` × the piece's half width out; it rises from nothing at
## `glow_inner` of that, is `glow_color` at `glow_peak` and fades out at the rim.
@export var glow_color := Color(1.0, 0.8, 0.3, 0.55)
@export var glow_scale := 0.95
@export_range(0.0, 1.0) var glow_inner := 0.5
@export_range(0.0, 1.0) var glow_peak := 0.8
@export var glow_segments := 40

var _drawn := 0
var _glowed := 0
## markers()' cut and the pose it was cut for (see there).
var _cache: Array = []
var _key: Array = []


## A fleet counter's height in design px: map_army_badge_native_px of the map
## at the scale the target is seen at, held between `badge_min_px` and
## `badge_max_px` so it reads far out and never swamps the ground close in.
func badge_height() -> float:
	if ctx == null:
		return 0.0
	var seen := float(ctx.meta.get("m_per_px", 50.0)) / maxf(ctx.metres_per_pixel(), 0.0001)
	return clampf(ctx.repo.bal("map_army_badge_native_px") * seen,
		badge_min_px, badge_max_px)


## The counters of the player's units that have NO 3D piece (a fleet) before
## the camera, in design px, kept clear of the settlement marks and the
## pieces. [] while the layer is off.
func markers() -> Array:
	if not bound() or not view.military():
		return []
	# Asked up to three times a frame — the HUD's draw, Map3DPicker.pick_at and
	# Map3DHudLandmarks' clearance — so it is cut once per camera pose: the pose,
	# the view's size, the render scale, the layer's switch, the date, the
	# pieces' moves (they are obstacles) and the selection (placed first).
	var st := ctx.state()
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(),
		view.military(), st.tick if st != null else 0, st.day if st != null else 0,
		view.unit_rects().size(), view.unit_moves(), view.selected_armies().duplicate()]
	if key == _key:
		return _cache
	_cache = _cut()
	_key = key
	return _cache


func _cut() -> Array:
	var repo := ctx.repo
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var h := badge_height()
	var frame := Rect2(Vector2.ZERO, ctx.view_size).grow(h * 4.0)
	var points: Array = []
	for r: Dictionary in ctx.regiments():
		if view.unit_has_piece(String(r["regiment_code"])):
			continue  # the piece is the unit: nothing over it
		var ground := ctx.pack_ground(ArmySystem.position_of(repo, ctx.state(), r))
		if camera.is_position_behind(ground):
			continue
		var sp := camera.unproject_position(ground) / s
		if frame.has_point(sp):
			points.append({"reg": r, "pos": sp})
	if points.is_empty():
		return []
	var keep_off: Array = ctx.settlement_rects()
	keep_off.append_array(view.unit_rects().values())
	return ArmyCounters.layout(repo, points, h, keep_off, view.selected_armies())


func drawn_count() -> int:
	return _drawn


## How many selected pieces the last draw laid a glow under (a test seam).
func glow_count() -> int:
	return _glowed


func _draw() -> void:
	if not bound():
		return
	_glowed = 0
	var list := markers()
	_drawn = list.size()
	if view.military():
		var rings := view.unit_rings()
		for code: String in view.selected_armies():
			if rings.has(code) and _draw_glow(rings[code]):
				_glowed += 1
	_draw_routes()
	ArmyCounters.draw(self, ctx.repo, list, view.selected_armies())
	if view.box_rect.has_area():
		draw_rect(view.box_rect, box_color, false, box_width_px)


## One piece's glow: three rings on its seat's plane (Map3DLayerUnits.
## ground_rings), each band a strip of quads shaded from clear to `glow_color`
## and back. false when any of it is behind the camera.
func _draw_glow(g: Dictionary) -> bool:
	var r := float(g["r"]) * glow_scale
	var bands: Array = []
	for share: float in [glow_inner, glow_peak, 1.0]:
		var ring := ground_ring(ctx.camera, g["at"], g["up"], r * share, glow_segments,
			ctx.viewport_px_scale())
		if ring.is_empty():
			return false
		bands.append(ring)
	var clear := Color(glow_color, 0.0)
	for b in 2:
		var inner: PackedVector2Array = bands[b]
		var outer: PackedVector2Array = bands[b + 1]
		var ci := glow_color if b == 1 else clear
		var co := glow_color if b == 0 else clear
		for i in glow_segments:
			var k := (i + 1) % glow_segments
			draw_polygon(PackedVector2Array([inner[i], inner[k], outer[k], outer[i]]),
				PackedColorArray([ci, ci, co, co]))
	return true


## `n` points of a circle of `radius` metres about `at` on the plane of normal
## `up`, projected to design px; [] when one lies behind the camera.
static func ground_ring(camera: Camera3D, at: Vector3, up: Vector3, radius: float, n: int,
		px_scale: float) -> PackedVector2Array:
	var e1 := (Vector3.RIGHT - up * up.dot(Vector3.RIGHT)).normalized()
	var e2 := up.cross(e1).normalized()
	var out := PackedVector2Array()
	for i in n:
		var t := TAU * float(i) / float(n)
		var p := at + (e1 * cos(t) + e2 * sin(t)) * radius
		if camera.is_position_behind(p):
			return PackedVector2Array()
		out.append(camera.unproject_position(p) / px_scale)
	return out


## Each marching regiment's road still ahead: a dashed line DRAPED on the
## ground from where its piece is DRAWN along its route to where it was sent, and a ring
## there, in the realm's own colour as its aim was — the order made visible,
## so a click that sent a column is seen to have. Draped, not a straight line
## between two projected ends: the column walks the ground's rises and falls,
## and at the camera's tilt a chord over a hill left the piece walking off its
## own road (owner 2026-09-30: 实际行进路线也和画的不一致).
func _draw_routes() -> void:
	if not view.military():
		return
	var repo := ctx.repo
	var st := ctx.state()
	if st == null:
		return
	var s := ctx.viewport_px_scale()
	var w := route_px
	var shown := view.unit_positions()
	for r: Dictionary in ctx.regiments():
		var code := String(r["regiment_code"])
		if ArmySystem.order_of(repo, st, code) != ArmySystem.ORDER_MARCH:
			continue
		# along its route still ahead, the curve it walks (spec 2026-10-07-march-waypoints)
		var prev: Vector2 = shown.get(code, ctx.to_world(ArmySystem.position_of(repo, st, r)))
		var pts := PackedVector2Array()
		for p: Vector2 in ArmySystem.route_px(repo, st, code):
			var xz := ctx.to_world(p)
			var leg := draped(prev, xz)
			pts.append_array(leg if pts.is_empty() else leg.slice(1))
			prev = xz
		if pts.size() < 2:
			continue
		var ink := MapPalette.color_of(repo, String(r.get("kingdom_code", "")))
		MapRuler.dashed_path(self, pts, ink, w, w * 4.0)
		var to: Variant = _screen_of(ArmySystem.destination_of(repo, st, code))
		if to != null:
			draw_arc((to as Vector2) / s, w * 4.0, 0.0, TAU, 24, ink, w, true)


## Every committed march's end ring, [{code, pos}] in design px — what a click
## on it hits (Map3DPicker: the route menu, owner 2026-09-27).
func route_ends() -> Array:
	var out: Array = []
	var st := ctx.state() if bound() else null
	if st == null or not view.military():
		return out
	var s := ctx.viewport_px_scale()
	for r: Dictionary in ctx.regiments():
		var code := String(r["regiment_code"])
		if ArmySystem.order_of(ctx.repo, st, code) != ArmySystem.ORDER_MARCH:
			continue
		var to: Variant = _screen_of(ArmySystem.destination_of(ctx.repo, st, code))
		if to != null:
			out.append({"code": code, "pos": (to as Vector2) / s})
	return out


func _screen_of(pack: Vector2) -> Variant:
	var xz := Map3DGeometry.pack_to_world(ctx.meta, pack)
	var p := Vector3(xz.x, ctx.height_at(xz), xz.y)
	if ctx.camera.is_position_behind(p):
		return null
	return ctx.camera.unproject_position(p)
