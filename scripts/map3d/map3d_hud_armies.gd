class_name Map3DHudArmies
extends Map3DHudPiece
## MILITARY's counters on the 3D map's HUD (owner 2026-09-19, the 2D map's —
## ArmyCounters), over the badges and the names. Its sizes are edited on the
## node (owner 2026-10-02).

## A counter's height, design px, held between these (owner 2026-09-19:
## 注意兵棋大小) — it reads far out and never swamps the ground close in.
@export var badge_min_px := 18.0
@export var badge_max_px := 30.0
## The headcount chip over a 3D piece is at most this tall (2026-09-27
## critic: the chip outranked the soldier — the piece is the counter, the
## chip only its tag).
@export var chip_px := 15.0
## The dashed road a marching regiment still has ahead, design px wide (in
## the realm's own colour); its end ring is four times it.
@export var route_px := 2.0
## The Shift-drag selection box's line (spec 2026-10-07-army-split-and-ground
## §5.6), design px; edited on the node.
@export var box_color := Color(1.0, 0.92, 0.6, 0.9)
@export var box_width_px := 1.5
## The leader line from a counter the spreading moved (further than
## balance.csv map3d_leader_min_px) back to its unit, and the dot on the unit
## (owner 2026-10-08, after the visual review: which unit is it?); design px.
@export var leader_color := Color(0.14, 0.11, 0.08, 0.8)
@export var leader_width_px := 1.25
@export var leader_dot_px := 2.0

var _drawn := 0
## markers()' cut and the pose it was cut for (see there).
var _cache: Array = []
var _key: Array = []
## Each regiment's bars and what they were read under, {code: {key, bars}} (_bars_of).
var _bars: Dictionary = {}
## On-land tests left in this cut (_on_land; map3d_leader_land_tests).
var _land_tests := 0


## A counter's height in design px: map_army_badge_native_px of the map at
## the scale the target is seen at (as the 2D counter grows with the zoom),
## held between `badge_min_px` and `badge_max_px` so it
## reads far out and never swamps the ground close in (owner: 注意兵棋大小).
func badge_height() -> float:
	if ctx == null:
		return 0.0
	var seen := float(ctx.meta.get("m_per_px", 50.0)) / maxf(ctx.metres_per_pixel(), 0.0001)
	return clampf(ctx.repo.bal("map_army_badge_native_px") * seen,
		badge_min_px, badge_max_px)


## The counters of the player's regiments before the camera, in design px,
## kept clear of the settlement dots. [] while the layer is off.
func markers() -> Array:
	if not bound() or not view.military():
		return []
	# Asked up to three times a frame — the HUD's draw, Map3DPicker.pick_at and
	# Map3DHudLandmarks' clearance — so it is cut once per camera pose, exactly
	# as Map3DHudLandmarks.marks() is (final review 2026-09-20). Same key shape:
	# the pose, the view's size, the render scale, the layer's own switch and
	# the date (regiments march and are settled by the month) and the selection
	# (the selected counters are placed first and never move).
	var st := ctx.state()
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(),
		view.military(), st.tick if st != null else 0, st.day if st != null else 0,
		view.unit_tops().size(), view.unit_moves(), view.selected_armies().duplicate()]
	if key == _key:
		return _cache
	_cache = _cut()
	_key = key
	return _cache


func _cut() -> Array:
	var repo := ctx.repo
	var st := ctx.state()
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var h := badge_height()
	var frame := Rect2(Vector2.ZERO, ctx.view_size).grow(h * 4.0)
	var points: Array = []
	# Where the 3D pieces have their heads: a regiment with a piece hangs its
	# headcount just over it instead of standing a second counter on its boots.
	var tops := view.unit_tops()
	var chip := minf(h, chip_px)
	var lift := chip * 0.5 + repo.bal("map_army_stack_gap_px")
	for r: Dictionary in ctx.regiments():
		var code := String(r["regiment_code"])
		var sp := Vector2.ZERO
		var ph := h
		var anchor := Vector2.ZERO
		if tops.has(code):
			ph = chip
			anchor = tops[code]
			sp = anchor - Vector2(0.0, lift)
		else:
			var xz := Map3DGeometry.pack_to_world(ctx.meta,
				ArmySystem.position_of(repo, st, r))
			var ground := Vector3(xz.x, ctx.height_at(xz), xz.y)
			if camera.is_position_behind(ground):
				continue
			sp = camera.unproject_position(ground) / s
			anchor = sp
		if frame.has_point(sp):
			points.append({"reg": r, "pos": sp, "anchor": anchor, "h": ph, "bars": _bars_of(code)})
	_land_tests = int(repo.bal("map3d_leader_land_tests"))
	return ArmyCounters.layout(repo, points, h, ctx.settlement_rects(), tops, view.selected_armies(),
		_on_land)


## Whether a design-px point of the view lies over land: the picker's ray to
## the ground, then the pack's cells (Map3DDeclutter's `allowed`). At most
## map3d_leader_land_tests a cut; past them every point passes.
func _on_land(pos: Vector2) -> bool:
	if _land_tests <= 0:
		return true
	_land_tests -= 1
	var hit: Variant = ctx.ground_at(pos)
	if hit == null:
		return false
	var p := hit as Vector3
	return MapEconomy.cell_at(ctx.repo, ctx.to_pack(Vector2(p.x, p.z))) >= 0


## ArmySystem.bars_of, kept while nothing it reads moves: the day (the
## stores are eaten, the columns march and the month settles only as days
## turn) and the regiment's own row (anything else that touches its stores,
## morale or training) — perf 2026-10-02: ~0.1 ms a regiment, every frame a
## column walks. A save loaded or a new reign is another state, another key.
func _bars_of(code: String) -> Vector2i:
	var st := ctx.state()
	var key := [st.get_instance_id(), st.tick, st.day,
		(st.regiments.get(code, {}) as Dictionary).hash()] if st != null else []
	var kept: Dictionary = _bars.get(code, {})
	if kept.get("key") != key:
		kept = {"key": key, "bars": ArmySystem.bars_of(ctx.repo, st, code)}
		_bars[code] = kept
	return kept["bars"]


func drawn_count() -> int:
	return _drawn


func _draw() -> void:
	if not bound():
		return
	var list := markers()
	_drawn = list.size()
	_draw_routes()
	ArmyCounters.draw(self, ctx.repo, list, view.selected_armies(),
		{"color": leader_color, "width": leader_width_px, "dot": leader_dot_px})
	if view.box_rect.has_area():
		draw_rect(view.box_rect, box_color, false, box_width_px)


## Each marching regiment's road still ahead: a dashed line DRAPED on the
## ground from where its piece is DRAWN to where it was sent, and a ring
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
		var from_xz: Vector2 = shown.get(code, ctx.to_world(ArmySystem.position_of(repo, st, r)))
		var to_xz := ctx.to_world(ArmySystem.destination_of(repo, st, code))
		var pts := draped(from_xz, to_xz)
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
