class_name Map3DHudArmies
extends Map3DHudPiece
## MILITARY on the 3D map's HUD: near, a land unit is its 3D piece (Map3DLayerUnits)
## with NOTHING drawn over it — no counter, chip, number, bar or leader line
## (owner 2026-10-10: 请移除大地图上军事单位的所有标记和数字的mark); a selected
## one glows on the ground under it (Map3DUnitGlow, in 3D). A unit with
## no piece (a fleet) keeps its flat counter (ArmyCounters). Strategic mode
## instead draws one shared-resource symbol per admitted unit. Each march's road
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
@export var symbols: Map3DUnitSymbols
var _drawn := 0
## markers()' cut and the pose it was cut for (see there).
var _cache: Array = []
var _key: Array = []
var _observations_key: Array = []
var _observations: Dictionary = {}
var _symbol_nodes: Dictionary = {}
var _ink_look: Array = []
var _box_ink: Node2D


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
	if view.unit_symbol_mode:
		_symbol_observations()
		var layout_key := [ctx.repo.bal("map_army_stack_gap_px"), ctx.repo.bal("map3d_declutter_step_px"), ctx.repo.bal("map3d_declutter_max_px")]
		if symbols != null: layout_key.append_array([symbols.marker_size, symbols.line_px, symbols.glyphs.hash()])
		var symbol_key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(), true,
			_observations_key, view.selected_armies().duplicate(), layout_key]
		if symbol_key != _key:
			_cache = _symbol_markers(_observations)
			_key = symbol_key
		return _cache
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


## Admission changes with world state, never with the camera's projection.
func _symbol_observations() -> Dictionary:
	var st := ctx.state()
	var key := [ctx.repo, ctx.dev, ctx.repo.bal("player_sight_km"), ctx.repo.bal("ghost_keep_days"), ctx.repo.army_scouting.hash(), st]
	if st != null:
		key.append_array([st.absolute_day(), st.regiments.hash(), st.foes.hash(), st.sightings.hash(),
			st.army_roster.hash(), st.military_rosters.hash(), st.military_cohorts.hash(),
			st.province_owner.hash(), st.manor_owner.hash(), st.ai_hosts.hash()])
	if key != _observations_key:
		_observations = {"regiments": ctx.regiments(), "ghosts": ctx.ghosts()}
		_observations_key = key
	return _observations


func _symbol_markers(observations: Dictionary = {}) -> Array:
	if symbols == null: return []
	var points: Array = []
	if observations.is_empty(): observations = _symbol_observations()
	var frame := Rect2(Vector2.ZERO, ctx.view_size).grow(symbols.marker_size.length())
	for reg: Dictionary in observations["regiments"]:
		var ground := ctx.pack_ground(ArmySystem.position_of(ctx.repo, ctx.state(), reg))
		if ctx.camera.is_position_behind(ground): continue
		var point := ctx.camera.unproject_position(ground) / ctx.viewport_px_scale()
		if frame.has_point(point): points.append({"reg": reg, "pos": point})
	for ghost: Dictionary in observations["ghosts"]:
		var point: Variant = on_ground(ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, Vector2i(ghost["x_m"], ghost["y_m"]))))
		if point != null and frame.has_point(point):
			points.append({"code": Sighting.GHOST_CODE + String(ghost["key"]), "pos": point, "ghost": true})
	var obstacles := ctx.settlement_rects()
	var labels := sibling("Labels") as Map3DHudLabels
	if labels != null: obstacles.append_array(labels.rects())
	var scroll := view.get_node_or_null("Hud/LegendScroll") as Control
	if scroll != null and scroll.visible: obstacles.append(Rect2(scroll.position, scroll.size))
	return symbols.layout(ctx.repo, points, obstacles, view.selected_armies())


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
			var pt := {"reg": r, "pos": sp, "text": str(Sighting.men_of(repo, ctx.state(), String(r["regiment_code"])))}
			if ctx.fogged(String(r["regiment_code"])):
				# an enemy unit the crown sees: its men as the seers' estimate (Sighting)
				pt["text"] = "≈" + Intel.num(Sighting.about(repo, Sighting.men_of(repo, ctx.state(),
					String(r["regiment_code"])), int(repo.bal("player_sight_estimate_quality")), 0))
			points.append(pt)
	if points.is_empty():
		return []
	var keep_off: Array = ctx.settlement_rects()
	keep_off.append_array(view.unit_rects().values())
	# the names: the kingdoms' and the capital's (review 2026-10-12: a fleet in
	# port lay over the capital's, then dodged onto the kingdom's)
	var labels := sibling("Labels") as Map3DHudLabels
	if labels != null:
		keep_off.append_array(labels.rects())
	return ArmyCounters.layout(repo, points, h, keep_off, view.selected_armies())


func drawn_count() -> int:
	return _drawn


func hit_rects(near_rects: Dictionary) -> Dictionary:
	if not bound() or not view.military(): return {}
	if not view.unit_symbol_mode: return near_rects
	var rects: Dictionary = {}
	for marker: Dictionary in markers(): rects[String(marker["code"])] = marker["rect"]
	return rects


func _draw() -> void:
	if not bound():
		clear_symbols()
		return
	var list := markers()
	_drawn = list.size()
	if view.military(): _draw_routes(_observations["regiments"] if view.unit_symbol_mode else ctx.regiments())
	if view.unit_symbol_mode and symbols != null:
		_sync_symbol_nodes(list)
		if view.box_rect.has_area() and _box_ink == null:
			_box_ink = Node2D.new()
			_box_ink.z_index = 1
			add_child(_box_ink)
			_box_ink.draw.connect(func() -> void: _box_ink.draw_rect(view.box_rect, box_color, false, box_width_px))
		if _box_ink != null:
			_box_ink.visible = view.box_rect.has_area()
			_box_ink.queue_redraw()
	else:
		clear_symbols()
		ArmyCounters.draw(self, ctx.repo, list, view.selected_armies())
		if view.box_rect.has_area(): draw_rect(view.box_rect, box_color, false, box_width_px)


func clear_symbols() -> void:
	_sync_symbol_nodes([])
	if _box_ink != null: _box_ink.hide()


## Keep ink commands until their appearance changes; a pan only moves each item.
func _sync_symbol_nodes(list: Array) -> void:
	if list.is_empty() and _symbol_nodes.is_empty(): return
	var look := [symbols, symbols.glyphs.hash(), symbols.frames.hash(), symbols.marker_size,
		symbols.line_px, symbols.dash_px, symbols.ink, symbols.paper, symbols.selected_ink,
		symbols.font, symbols.font_px] if symbols != null else []
	var changed := look != _ink_look
	_ink_look = look
	var keep: Dictionary = {}
	var order := 0
	for marker: Dictionary in list:
		var code := String(marker["code"])
		keep[code] = true
		if not _symbol_nodes.has(code):
			var ink := Node2D.new()
			add_child(ink)
			ink.draw.connect(func() -> void:
				var key: Array = ink.get_meta("look")
				symbols.draw_symbol(ink, Rect2(-symbols.marker_size * 0.5, symbols.marker_size), key[0], key[1], key[2], key[3]))
			_symbol_nodes[code] = ink
		var ink: Node2D = _symbol_nodes[code]
		ink.position = (marker["symbol_rect"] as Rect2).get_center()
		if ink.get_index() != order: move_child(ink, order)
		order += 1
		var key := [marker["arm"], marker["frame"], marker["royal"], view.selected_armies().has(code)]
		if changed or ink.get_meta("look", []) != key:
			ink.set_meta("look", key)
			ink.queue_redraw()
	for code: String in _symbol_nodes.keys():
		if not keep.has(code):
			(_symbol_nodes[code] as Node2D).hide()
			(_symbol_nodes[code] as Node2D).queue_free()
			_symbol_nodes.erase(code)


## Each marching regiment's road still ahead: a dashed line DRAPED on the
## ground from where its piece is DRAWN along its route to where it was sent, and a ring
## there, in the realm's own colour as its aim was — the order made visible,
## so a click that sent a column is seen to have. Draped, not a straight line
## between two projected ends: the column walks the ground's rises and falls,
## and at the camera's tilt a chord over a hill left the piece walking off its
## own road (owner 2026-09-30: 实际行进路线也和画的不一致).
func _draw_routes(regiments: Array) -> void:
	if not view.military():
		return
	var repo := ctx.repo
	var st := ctx.state()
	if st == null:
		return
	var s := ctx.viewport_px_scale()
	var w := route_px
	var shown: Dictionary = {}
	var origins_ready := false
	for r: Dictionary in regiments:
		var code := String(r["regiment_code"])
		if ctx.fogged(code) or ArmySystem.order_of(repo, st, code) != ArmySystem.ORDER_MARCH:
			continue  # an enemy's road ahead is not the crown's to see
		if not origins_ready:
			shown = view.unit_positions()
			origins_ready = true
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
		if ctx.fogged(code) or ArmySystem.order_of(ctx.repo, st, code) != ArmySystem.ORDER_MARCH:
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
