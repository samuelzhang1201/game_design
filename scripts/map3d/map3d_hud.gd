class_name Map3DHud
extends Control
## The 3D map's furniture (owner 2026-09-18): the scale bar bottom-right —
## ScaleBar, the 2D map's own drawing, in the 2D map's own measure (owner
## 2026-09-18: the world is BUILT at 50 m per pack px, but it reads as the
## pack's distance_scale says, so both maps agree — Map3DView.
## map_units_per_metre) — and the compass top-left: CompassLayer's oak wheel turning while
## time runs, as on the 2D map, under a north needle that turns with the
## view. Mouse-transparent; Map3DView routes a click on compass_rect() to
## its turn-north. Redrawn on every camera move (Map3DContext.camera_moved).
##
## Fix round 1 (owner 2026-09-18): a pale halo (terrain_palette
## map3d_hud_halo) under the scale bar's strokes/label and the needle's
## shadow/N, so both read over bright ground (snow, sea) that the 2D map
## never had to contend with; a soft dark vignette behind the wheel so map
## symbols at a busy zoom (24 km) don't tangle with its spokes; a drop
## shadow and a small rotating "N" so the needle reads as sitting over the
## wheel rather than pasted flat on it.

## One child per job (spec 2026-09-20 §1), in PAINT ORDER — a CanvasItem
## child draws over its earlier siblings (Ruling 17): the kingdom names, then
## HEIGHTS' landmarks and legend, MANORS' badges, MILITARY's counters, the
## wheel's backdrop, the scale bar, the MEASUREMENT ruler, the wheel
## (CompassLayer) and last its needle. Every piece reads the context the view
## binds — never the Game autoload — and draws nothing until bound.
const PIECES := ["Labels", "Landmarks", "HeatLegend", "Badges", "Armies", "Backdrop",
	"ScaleBar", "Ruler"]

var ctx: Map3DContext
var view: Map3DView
var _compass: CompassLayer
var _needle: Map3DHudNeedle


func _ready() -> void:
	name = "Hud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for piece_name: String in PIECES:
		if get_node_or_null(piece_name) == null:
			var p := _make_piece(piece_name)
			p.name = piece_name
			add_child(p)
	_compass = get_node_or_null("Compass") as CompassLayer
	if _compass == null:
		_compass = CompassLayer.new()
		_compass.name = "Compass"
		add_child(_compass)
	_compass.box = compass_rect
	_compass.setup()
	_needle = get_node_or_null("Needle") as Map3DHudNeedle
	if _needle == null:
		_needle = Map3DHudNeedle.new()
		_needle.name = "Needle"
		add_child(_needle)
	_needle.hud = self


static func _make_piece(piece_name: String) -> Map3DHudPiece:
	match piece_name:
		"Labels":
			return Map3DHudLabels.new()
		"Landmarks":
			return Map3DHudLandmarks.new()
		"HeatLegend":
			return Map3DHudHeatLegend.new()
		"Badges":
			return Map3DHudBadges.new()
		"Armies":
			return Map3DHudArmies.new()
		"Backdrop":
			return Map3DHudBackdrop.new()
		"ScaleBar":
			return Map3DHudScaleBar.new()
	return Map3DHudRuler.new()


## Hand every piece the context and the view; the HUD redraws on every
## camera move from here on.
func bind(p_ctx: Map3DContext, p_view: Map3DView) -> void:
	ctx = p_ctx
	view = p_view
	for c: Node in get_children():
		if c is Map3DHudPiece:
			(c as Map3DHudPiece).bind(ctx, view)
	if _needle != null:
		_needle.hud = self
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)
	refresh()


## Redraw every piece, the wheel and the needle (queue_redraw itself cannot
## be overridden — the engine refuses to call a script's override of a
## native CanvasItem method). On every camera move and state change.
func refresh() -> void:
	for c: Node in get_children():
		if c is CanvasItem:
			(c as CanvasItem).queue_redraw()


## The piece named `piece_name` (PIECES), or null.
func piece(piece_name: String) -> Map3DHudPiece:
	return get_node_or_null(piece_name) as Map3DHudPiece


## Whether the wheel's art is in (the needle draws a ring without it).
func has_compass_art() -> bool:
	return _compass != null and _compass.has_art()


## {distance, text, width_px} for the largest 1-2-5 distance whose bar fits
## in `max_px` at `units_per_px` (the pack's distance_unit per screen px, so
## the bar reads what the 2D map's does — owner 2026-09-18); {} when nothing
## sensible fits.
static func scale_bar_for(units_per_px: float, max_px: float, unit: String) -> Dictionary:
	if units_per_px <= 0.0 or max_px <= 0.0:
		return {}
	var d := MapGeometry.nice_step(max_px * units_per_px)
	if d <= 0.0:
		return {}
	return {"distance": d, "text": ("%s %s" % [ScaleBar.trim_zeros(d), unit]).strip_edges(),
		"width_px": d / units_per_px}


## The needle's turn, clockwise from screen-up, at a view yaw (Map3DGeometry
## .pose: yaw +90 puts north on the right).
static func needle_angle(yaw_deg: float) -> float:
	return deg_to_rad(yaw_deg)


## Top-left, the 2D compass's size and margin (the 2D map's is top-right).
func compass_rect() -> Rect2:
	if ctx == null:
		return Rect2()
	var d := ctx.repo.bal("map_compass_size_px")
	var m := ctx.repo.bal("map_compass_margin_px")
	return Rect2(Vector2(m, m), Vector2(d, d)) if d > 0.0 else Rect2()


## terrain_palette's pale halo, at map3d_hud_halo_alpha — {} (alpha 0) turns
## every halo off, including the 2D map's ScaleBar.draw call, which never
## passes one and so is untouched by this fix.
static func halo(repo: DataRepository) -> Color:
	var c := MapTerrain.palette_color(repo, "map3d_hud_halo", MapTerrain.FALLBACK)
	c.a = repo.bal("map3d_hud_halo_alpha")
	return c
