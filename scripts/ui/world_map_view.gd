class_name WorldMapView
extends Control
## RTS-style viewport into the loaded map pack's render, embedded in the
## middle map zone of every gameplay screen — court, conversation, day run
## (user ruling 2026-09-03: the world map IS the middle view — it replaces
## UiPalette's static backdrop there, and the bottom bar's MAP tab goes
## back to meaning "close overlays"). The map
## opens covering the frame, and zooms out to the whole world; the view
## pans when the mouse rides an edge
## of the frame (plus drag and wheel-zoom), every kingdom is washed in its
## palette colour with its live border drawn (the render is terrain only),
## the kingdom under the mouse gets its outline lit, towns and points of interest show
## as pins (LOD by zoom, MapObjects), hovering a pin or road names it,
## and clicking a kingdom opens a
## floating info card resolved through the world_state_index.png bitmap
## (tools/import_azgaar.gd) via MapIndex. View-only: reads Game.data,
## never mutates game state.

## A card's ASK THE COUNCIL button: the screen owning an input box puts this
## text in it (nothing is sent until the player presses Enter).
signal place_asked(text: String)
## The kingdom under the cursor changed — its kingdom_code, or "" for water,
## open sea, or no map. Screens use it to swap their left column to the
## country's card while the cursor is over that terrain.
signal country_hovered(kingdom_code: String)
## The province view was switched on or off (the P key, or a screen).
signal province_view_changed(on: bool)
## In the province view, the province under a click — its province_code, or
## "" for water / nothing — so a screen's detail column can show its account.
signal province_selected(province_code: String)
## The described entry of the object under a click ({title, lines, ask}), or
## {} when water / nothing was clicked. Screens with a detail column take
## this and switch the floating card off (use_card).
signal object_selected(entry: Dictionary)

const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.2
## A press/release pair further apart than this is a drag, not a click.
const CLICK_SLOP := 5.0
## Mouse within this many px of the frame edge scrolls the view (RTS-style).
const EDGE_MARGIN := 12.0
## Edge-scroll speed in screen px/s.
const EDGE_SPEED := 260.0
## The render is terrain only (user ruling 2026-09-09): the game paints every
## province in its live owner's colour (MapPalette, data/political_palette.csv)
## and draws every kingdom's border itself, so conquest repaints and redraws
## with no new art. The hovered kingdom's outline is drawn over that in the
## palette's hover colour; widths and opacities live in balance.csv.
## Debug-build shortcut for the territory demo (dev_flip_hovered_province).
const DEV_FLIP_KEY := KEY_T
## Pin sizes in screen px (constant at any zoom; LOD hides the small ones).
const PIN_CAPITAL := 4.0
const PIN_TOWN := 2.5
const PIN_VILLAGE := 1.5
const PIN_MARKER := 3.0
const PIN_OUTLINE := Color(0.05, 0.04, 0.02, 0.9)
const TOOLTIP_OFFSET := Vector2(10.0, 12.0)
const SCENE_PATH := "res://scenes/world_map.tscn"
## Province view (user request 2026-09-09): every kingdom's internal seams as
## light dashed lines, computed from the provinces it holds NOW
## (MapOwnership.seams_of), so they follow conquest where the render's
## printed dots cannot (no names on the map, user ruling 2026-09-09); a click
## names the province under it (province_selected) for the screen's left column.
## Toggled by the bottom bar's PROVINCES tab or the P key.
const PROVINCE_KEY := KEY_P
var show_provinces: bool = false:
	set(v):
		if v == show_provinces:
			return
		show_provinces = v
		if not v and _selected_province != "":
			_selected_province = ""
			province_selected.emit("")
		province_view_changed.emit(v)
		queue_redraw()
## The province selected in the province view ("" when none); drawn tinted.
var _selected_province := ""
## Per province loop: its triangle indices (native coordinates, so they never
## change with the view) and bounding box, built once so the political wash
## costs one triangle-array call per loop per frame.
var _province_tris: Dictionary = {}
var _province_bbox: Dictionary = {}

var _map_texture: Texture2D
var _index_image: Image
## world_map.png may be a sharper integer-scale render of the map (see
## tools/import_azgaar.gd); the index bitmap and CSV coordinates stay at
## native scale, so texture coords = native coords * _render_scale. Any
## zoom the render was exported at is a separate, per-pack correction —
## see DataRepository.render_scale.
var _render_scale := 1.0
## The loaded pack's render calibration, cached off Game.data so _draw can
## place hundreds of points a frame without going through the autoload.
var _cal_scale := 1.0
var _cal_offset := Vector2.ZERO
var _by_state_id: Dictionary = {}
## Azgaar state id under the mouse (-1: water/nothing); its border loops
## are outlined in _draw.
var _hover_sid := -1
var _province_image: Image
var _biome_image: Image
## The pin/line/land under the mouse (MapObjects.object_at); {} before any hover.
var _hover_obj: Dictionary = {}
var _tooltip: Label
var _card: MapInfoCard
## What the open card describes ({} when closed); drawn highlighted.
var _selected_obj: Dictionary = {}
var _offset := Vector2.ZERO
var _zoom := 1.0
var _homed := false
var _dragging := false
var _press_pos := Vector2.ZERO
## Edge scrolling only while the pointer is really over the map (real
## mouse_entered events — the headless test runner's phantom (0,0) mouse
## must never pan the view).
var _mouse_inside := false

## Every screen builds the map through here (user request 2026-09-08): it is a
## scene like the character portraits and location views, so it can be opened
## in the editor and decorated with child nodes. Those children draw beneath
## the info card and tooltip, which _ready appends after them.
static func create() -> WorldMapView:
	return load(SCENE_PATH).instantiate()

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The project default is nearest (crisp pixel fonts); the photographic
	# map wants smooth scaling. The card resets to nearest so its text
	# matches the rest of the UI.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Which map is loaded is data (data/maps.csv), not a constant here — the
	# view renders whichever pack DataRepository.load_map put in place.
	var map_path := Game.data.map_texture_path
	var index_path := Game.data.index_texture_path
	if map_path != "" and ResourceLoader.exists(map_path):
		_map_texture = load(map_path)
	if index_path != "" and ResourceLoader.exists(index_path):
		var idx: Texture2D = load(index_path)
		_index_image = idx.get_image()
	_province_image = _load_image(Game.data.province_texture_path)
	_biome_image = _load_image(Game.data.biome_texture_path)
	if _map_texture != null and _index_image != null:
		_render_scale = float(_map_texture.get_width()) / float(_index_image.get_width())
	_cal_scale = Game.data.render_scale
	_cal_offset = Game.data.render_offset
	for code: String in Game.data.kingdoms:
		var row: Dictionary = Game.data.kingdoms[code]
		_by_state_id[int(row["state_id"])] = row
	_build_province_meshes()
	_card = MapInfoCard.new()
	_card.ask_requested.connect(func(text: String) -> void: place_asked.emit(text))
	_card.closed.connect(func() -> void:
		_selected_obj = {}
		queue_redraw())
	add_child(_card)
	_build_tooltip()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void:
		_mouse_inside = false
		hover_state(-1)
		hover_object({}))
	resized.connect(func() -> void:
		_clamp_offset()
		queue_redraw())
	# No imported map: stay invisible so the styled backdrop shows instead.
	visible = _map_texture != null

func _load_image(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return (load(path) as Texture2D).get_image()

func _build_tooltip() -> void:
	_tooltip = Label.new()
	_tooltip.name = "Tooltip"
	_tooltip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	_tooltip.add_theme_font_size_override("font_size", 8)
	_tooltip.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_tooltip.hide()
	add_child(_tooltip)

## Initial framing: the map covers the frame edge to edge, so the middle
## column never shows dead gutter. The map is far wider in proportion than
## the column (2.76:1 into roughly 1.3:1), so a contain fit here would waste
## about half the column's height on empty bands — this crops the outer
## ocean instead, and one wheel-down reaches _zoom_min where the whole world
## is visible.
func _go_home() -> void:
	_zoom = _zoom_cover()
	_offset = (size - _map_texture.get_size() * _zoom) / 2.0
	_clamp_offset()
	_homed = true

## Fill both axes, cropping whichever one overflows.
func _zoom_cover() -> float:
	var tex := _map_texture.get_size()
	if tex.x <= 0.0 or tex.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.1
	return maxf(size.x / tex.x, size.y / tex.y)

func _draw() -> void:
	if _map_texture == null:
		return
	if not _homed and size.y > 0.0:
		_go_home()
	draw_texture_rect(_map_texture,
		Rect2(_offset, _map_texture.get_size() * _zoom), false)
	_draw_political_wash()
	_draw_province_seams()
	_draw_selected_province()
	_draw_state_borders()
	_draw_hovered_outline()
	_draw_kingdom_labels()
	_draw_pins()
	_draw_hover()
	_draw_object_highlight(_selected_obj)

## Screen px per native map px — the LOD and pick radii are defined on it.
func view_scale() -> float:
	return _zoom * _render_scale * _cal_scale

func _pin_radius(b: Dictionary) -> float:
	if String(b["is_capital"]) == "1":
		return PIN_CAPITAL
	return PIN_TOWN if int(float(b["population"])) >= int(Game.data.bal("map_lod_town_pop")) else PIN_VILLAGE

## Towns as gold circles sized by tier (ringed for capitals), points of
## interest as teal diamonds — all in screen px, gated by the LOD rule.
func _draw_pins() -> void:
	var s := view_scale()
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, s)
	var on_screen := Rect2(Vector2.ZERO, size).grow(PIN_CAPITAL * 2.0)
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		if not MapObjects.burg_visible(b, min_pop):
			continue
		var sp := map_to_screen(Vector2(float(b["x"]), float(b["y"])))
		if not on_screen.has_point(sp):
			continue
		var r := _pin_radius(b)
		draw_circle(sp, r + 1.0, PIN_OUTLINE)
		draw_circle(sp, r, UiPalette.GOLD)
		if String(b["is_capital"]) == "1":
			draw_arc(sp, r + 2.5, 0.0, TAU, 24, UiPalette.GOLD, 1.0, true)
	if s >= Game.data.bal("map_lod_marker_scale"):
		for code: String in Game.data.markers:
			var m: Dictionary = Game.data.markers[code]
			var sp := map_to_screen(Vector2(float(m["x"]), float(m["y"])))
			if on_screen.has_point(sp):
				_draw_diamond(sp, PIN_MARKER + 1.0, PIN_OUTLINE)
				_draw_diamond(sp, PIN_MARKER, UiPalette.TOOL_PERSONAL)

## Triangulate every province loop once, in native coordinates. Province
## outlines are concave, so a fan fill would bleed outside the shape; the
## indices are transform-invariant, so each frame only moves the points.
func _build_province_meshes() -> void:
	_province_tris.clear()
	_province_bbox.clear()
	for code: String in Game.data.province_borders:
		var tris: Array = []
		var bbox := Rect2()
		var first := true
		for loop: PackedVector2Array in Game.data.province_borders[code]:
			tris.append(Geometry2D.triangulate_polygon(loop))
			var b := MapGeometry.bounds(loop)
			bbox = b if first else bbox.merge(b)
			first = false
		_province_tris[code] = tris
		_province_bbox[code] = bbox

## The provinces whose wash would touch the frame right now, with their
## owner's colour: {code, color}. Public for tests.
func political_fills() -> Array:
	if _map_texture == null:
		return []
	var alpha := Game.data.bal("map_political_alpha")
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for code: String in _province_bbox:
		var b: Rect2 = _province_bbox[code]
		var screen := Rect2(map_to_screen(b.position), b.size * view_scale())
		if not frame.intersects(screen):
			continue
		var owner := MapOwnership.owner_of(Game.data, Game.state, code)
		var color := MapPalette.color_of(Game.data, owner)
		color.a = alpha
		out.append({"code": code, "color": color})
	return out

## Paint every province in its live owner's colour over the terrain.
func _draw_political_wash() -> void:
	var rid := get_canvas_item()
	for fill in political_fills():
		var code: String = fill["code"]
		var loops: Array = Game.data.province_borders[code]
		var tris: Array = _province_tris[code]
		for i in loops.size():
			var indices: PackedInt32Array = tris[i]
			if indices.is_empty():
				continue
			var loop: PackedVector2Array = loops[i]
			var pts := PackedVector2Array()
			pts.resize(loop.size())
			for j in loop.size():
				pts[j] = map_to_screen(loop[j])
			var colors := PackedColorArray()
			colors.resize(loop.size())
			colors.fill(fill["color"])
			RenderingServer.canvas_item_add_triangle_array(rid, indices, pts, colors)

## A kingdom's live outline as smooth closed curves in native coordinates:
## the same uniform cubic B-spline Azgaar drew the render's coasts and
## borders with (user request 2026-09-09: the straight-segment outline cut
## the shore's corners). Cached against the ownership version.
var _ring_cache: Dictionary = {}
var _ring_version := -1

func border_rings(kingdom_code: String) -> Array:
	var version := 0 if Game.state == null else Game.state.province_owner.size()
	if version != _ring_version:
		_ring_cache.clear()
		_ring_version = version
	if _ring_cache.has(kingdom_code):
		return _ring_cache[kingdom_code]
	var steps := int(Game.data.bal("map_border_smoothing_steps"))
	var rings: Array = []
	for loop: PackedVector2Array in MapOwnership.outline_of(Game.data, Game.state, kingdom_code):
		rings.append(MapGeometry.smooth_closed(loop, steps))
	_ring_cache[kingdom_code] = rings
	return rings

## Every kingdom's live border, thin and light, in the palette's border colour.
func _draw_state_borders() -> void:
	var color := MapPalette.named(Game.data, "state_border")
	color.a = Game.data.bal("map_state_border_alpha")
	var width := Game.data.bal("map_state_border_width")
	var frame := Rect2(Vector2.ZERO, size).grow(width * 2.0)
	for code: String in Game.data.kingdoms:
		for ring: PackedVector2Array in border_rings(code):
			var pts := _closed_screen_ring(ring)
			if _ring_touches(pts, frame):
				draw_polyline(pts, color, width, true)

## The hovered kingdom's outline in the palette's hover colour, over the
## border it already has.
func _draw_hovered_outline() -> void:
	var row: Dictionary = _by_state_id.get(_hover_sid, {})
	if row.is_empty():
		return
	var color := MapPalette.named(Game.data, "hover_border")
	var width := Game.data.bal("map_hover_border_width")
	for ring: PackedVector2Array in border_rings(String(row["kingdom_code"])):
		draw_polyline(_closed_screen_ring(ring), color, width, true)

func _closed_screen_ring(loop: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(loop.size() + 1)
	for i in loop.size():
		pts[i] = map_to_screen(loop[i])
	pts[loop.size()] = pts[0]  # close the ring
	return pts

func _ring_touches(pts: PackedVector2Array, frame: Rect2) -> bool:
	for p in pts:
		if frame.has_point(p):
			return true
	return false

## Kingdom names set into the terrain like printed map lettering: the display
## face (Cinzel), widely letter-spaced, faint, and scaled with the zoom so
## they belong to the map rather than floating over it as UI. Drawn under the
## pins, and anchored on the territory a kingdom holds NOW, so a label
## recentres when its owner gains or loses provinces.
func _draw_kingdom_labels() -> void:
	var font := UiPalette.display_font()
	if font == null:
		return
	var px := Game.data.bal("map_label_scale_px") * view_scale()
	if px < Game.data.bal("map_label_min_px"):
		return
	px = minf(px, Game.data.bal("map_label_max_px"))
	var size := int(px)
	var tracking := px * Game.data.bal("map_label_tracking")
	var color := UiPalette.GOLD
	color.a = Game.data.bal("map_label_alpha")
	var frame := Rect2(Vector2.ZERO, self.size)
	for code: String in Game.data.kingdoms:
		var text := String(Game.data.kingdoms[code]["label"]).to_upper()
		var anchor := MapOwnership.label_anchor(Game.data, Game.state, code)
		var at := map_to_screen(anchor)
		var width := _tracked_width(font, text, size, tracking)
		var origin := at - Vector2(width * 0.5, -px * 0.35)
		if not frame.intersects(Rect2(origin - Vector2(0, px), Vector2(width, px * 1.4))):
			continue
		_draw_tracked(font, text, origin, size, tracking, color)

## draw_string has no letter-spacing, and tracking is most of what makes a
## label read as engraved rather than typed — so the glyphs are placed one at
## a time with the extra advance added between them.
func _draw_tracked(font: Font, text: String, origin: Vector2, size: int,
		tracking: float, color: Color) -> void:
	var pen := origin
	for i in text.length():
		var ch := text.substr(i, 1)
		font.draw_string(get_canvas_item(), pen, ch, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, size, color)
		pen.x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x \
			+ tracking

func _tracked_width(font: Font, text: String, size: int, tracking: float) -> float:
	if text.is_empty():
		return 0.0
	var w := 0.0
	for i in text.length():
		w += font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, size).x + tracking
	return w - tracking

func _draw_diamond(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0)]), color)

## Ring around the hovered pin. Roads and rivers are named by the tooltip and
## the card but are NOT traced (user ruling 2026-09-09): the render already
## draws them, and a gold line over the top only obscured them.
func _draw_hover() -> void:
	_draw_object_highlight(_hover_obj)

func _draw_object_highlight(obj: Dictionary) -> void:
	match String(obj.get("kind", "")):
		"burg":
			var b: Dictionary = Game.data.burgs[obj["code"]]
			var sp := map_to_screen(Vector2(float(b["x"]), float(b["y"])))
			draw_arc(sp, _pin_radius(b) + 4.0, 0.0, TAU, 32, UiPalette.GOLD, 1.5, true)
		"marker":
			var m: Dictionary = Game.data.markers[obj["code"]]
			var sp := map_to_screen(Vector2(float(m["x"]), float(m["y"])))
			draw_arc(sp, PIN_MARKER + 4.0, 0.0, TAU, 32, UiPalette.GOLD, 1.5, true)

## Homing + RTS edge scrolling: pan while the mouse rides the frame's edge.
## (Homing lives here, not only in _draw, so it also runs headless in tests.)
func _process(delta: float) -> void:
	if _map_texture == null or not is_visible_in_tree() or size.x <= 0.0:
		return
	if not _homed:
		_go_home()
		queue_redraw()
	if not _mouse_inside:
		return
	var m := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(m):
		return
	var dir := Vector2.ZERO
	if m.x < EDGE_MARGIN:
		dir.x = 1.0
	elif m.x > size.x - EDGE_MARGIN:
		dir.x = -1.0
	if m.y < EDGE_MARGIN:
		dir.y = 1.0
	elif m.y > size.y - EDGE_MARGIN:
		dir.y = -1.0
	if dir != Vector2.ZERO:
		_offset += dir * EDGE_SPEED * delta
		_clamp_offset()
		_update_hover(m)
		queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if _map_texture == null:
		return
	# macOS trackpad: pinch zooms, two-finger drag pans. Godot delivers these
	# as their own events, so they are handled beside the wheel rather than
	# instead of it — a mouse still works exactly as before.
	if ev is InputEventMagnifyGesture:
		var mg := ev as InputEventMagnifyGesture
		var gain := Game.data.bal("map_pinch_zoom_gain")
		# factor is the frame's pinch ratio (>1 apart, <1 together); gain
		# bends it around 1.0 without changing the direction.
		_zoom_at(mg.position, 1.0 + (mg.factor - 1.0) * gain)
		return
	if ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		_offset -= pg.delta * Game.data.bal("map_pan_gesture_speed")
		_clamp_offset()
		queue_redraw()
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == PROVINCE_KEY:
		toggle_provinces()
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == DEV_FLIP_KEY \
			and OS.is_debug_build():
		dev_flip_hovered_province()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = false
				_press_pos = mb.position
			elif not _dragging:
				_select_at(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_update_hover(mm.position)
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _press_pos.distance_to(mm.position) > CLICK_SLOP:
				_dragging = true
			if _dragging:
				_offset += mm.relative
				_clamp_offset()
				queue_redraw()

func _zoom_at(pos: Vector2, factor: float) -> void:
	var before := (pos - _offset) / _zoom
	_zoom = clampf(_zoom * factor, _zoom_min(), ZOOM_MAX)
	_offset = pos - before * _zoom
	_clamp_offset()
	queue_redraw()

## Zoom-out floor: the whole map fits inside the frame (contain fit), so the
## default framing shows the entire world and the slack axis letterboxes.
## size.y is guarded too — a zero there would make minf return 0, and _zoom_at
## divides by _zoom.
func _zoom_min() -> float:
	var tex := _map_texture.get_size()
	if tex.x <= 0.0 or tex.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.1
	return minf(size.x / tex.x, size.y / tex.y)

## Pan limits: an axis the map overflows stays pinned to the frame edges, so
## no gutter opens where map could have been; an axis it underfills (the
## letterboxed one at low zoom) is centered instead.
func _clamp_offset() -> void:
	if _map_texture == null:
		return
	_zoom = maxf(_zoom, _zoom_min())
	var scaled := _map_texture.get_size() * _zoom
	if scaled.x < size.x:
		_offset.x = (size.x - scaled.x) / 2.0
	else:
		_offset.x = clampf(_offset.x, size.x - scaled.x, 0.0)
	if scaled.y < size.y:
		_offset.y = (size.y - scaled.y) / 2.0
	else:
		_offset.y = clampf(_offset.y, size.y - scaled.y, 0.0)

## View transform: native map coordinates (index bitmap, CSV x/y) <-> screen.
## Native (pack/CSV/index-bitmap) coordinates -> screen. Two steps: the pack's
## calibration places the world on the render (identity unless the PNG was
## exported from a zoomed Azgaar view), then _render_scale/_zoom place the
## render on screen.
func map_to_screen(native: Vector2) -> Vector2:
	var on_render := native * _cal_scale + _cal_offset
	return _offset + on_render * _render_scale * _zoom

## The exact inverse — hit-testing samples the index bitmaps, which are in
## native coordinates, so this has to undo the calibration too.
func screen_to_map(pos: Vector2) -> Vector2:
	var on_render := (pos - _offset) / _zoom / _render_scale
	return (on_render - _cal_offset) / _cal_scale

func _state_under(pos: Vector2) -> int:
	return MapIndex.state_at(_index_image, Vector2i(screen_to_map(pos).floor()))

func _select_at(pos: Vector2) -> void:
	var obj := _object_under(pos)
	if show_provinces:
		# The province view: every click names the province under it (a pin
		# still opens its own card; bare land does not).
		var prov := Game.data.province_by_id(
			MapIndex.id_at(_province_image, Vector2i(screen_to_map(pos).floor())) \
			if _province_image != null else -1)
		select_province(String(prov.get("province_code", "")))
		if String(obj.get("kind", "")) in ["land", "water"]:
			return
	select_object(obj)

## Select a province by code ("" clears); public for tests and screens.
func select_province(province_code: String) -> void:
	if not Game.data.provinces.has(province_code):
		province_code = ""
	if province_code == _selected_province:
		return
	_selected_province = province_code
	if province_code != "":
		_selected_obj = {}
		_card.hide()
	province_selected.emit(province_code)
	queue_redraw()

func selected_province() -> String:
	return _selected_province

func _object_under(pos: Vector2) -> Dictionary:
	var s := view_scale()
	return MapObjects.object_at(Game.data, _index_image, _province_image, _biome_image,
		screen_to_map(pos), Game.data.bal("map_pick_radius_px") / s,
		Game.data.bal("map_line_pick_px") / s,
		MapObjects.min_burg_pop_for_scale(Game.data, s), Game.state)

func _update_hover(pos: Vector2) -> void:
	var obj := _object_under(pos)
	hover_state(_state_of(obj, pos))
	hover_object(obj)
	_place_tooltip(pos)

## The kingdom to outline while `obj` is hovered. A burg or route names its
## own kingdom, which matters for the coastal ones: a port sits on the
## shoreline, so the index pixel under its pin is often open water and
## reading the bitmap alone would drop the outline the moment the player
## touches the pin. Anything else falls back to the pixel under the cursor.
func _state_of(obj: Dictionary, pos: Vector2) -> int:
	var code := String(obj.get("code", ""))
	if code != "":
		var owner := ""
		match String(obj.get("kind", "")):
			"burg":
				var b: Dictionary = Game.data.burgs.get(code, {})
				owner = MapOwnership.owner_of(Game.data, Game.state,
					String(b.get("province_code", "")))
			"province":
				owner = MapOwnership.owner_of(Game.data, Game.state, code)
		if owner != "" and Game.data.kingdoms.has(owner):
			return int((Game.data.kingdoms[owner] as Dictionary)["state_id"])
	return _state_under(pos)

## Beside the cursor, pushed back inside the frame at the edges so a pin
## in a corner still shows its whole name.
func _place_tooltip(pos: Vector2) -> void:
	var tip := _tooltip.get_combined_minimum_size()
	var limit := (size - tip).max(Vector2.ZERO)
	_tooltip.position = (pos + TOOLTIP_OFFSET).clamp(Vector2.ZERO, limit)

## Dev demo (debug builds, the T key): hand the hovered province to the
## player's realm, or back to whoever the pack gave it to if it is already
## theirs. Proves the dynamic-territory path end to end — the border redraws,
## the province repaints in the new colour, the kingdom labels recentre, and
## the hover card reports the new owner. Public so a test can drive it
## without a keyboard.
func dev_flip_hovered_province() -> Dictionary:
	var prov := Game.data.province_by_id(int(_hover_obj.get("province_id", -1)))
	if prov.is_empty() or Game.state == null:
		return {}
	var code := String(prov["province_code"])
	var mine := Game.data.resolve_realm("player_realm")
	var now := MapOwnership.owner_of(Game.data, Game.state, code)
	var to := String(prov["kingdom_code"]) if now == mine else mine
	if not MapOwnership.set_owner(Game.data, Game.state, code, to,
			"dev: flipped on the map"):
		return {}
	_hover_sid = -1  # force the hover to re-resolve against the new owner
	_update_hover(get_local_mouse_position())
	# The card in the left column is showing counts from before the transfer.
	country_hovered.emit(String(_by_state_id.get(_hover_sid, {}).get("kingdom_code", "")))
	queue_redraw()
	return {"province": code, "from": now, "to": to}

func toggle_provinces() -> void:
	show_provinces = not show_provinces

## The selected province, washed in gold so the selection reads on the map.
func _draw_selected_province() -> void:
	if _selected_province == "" or not show_provinces:
		return
	var tint := UiPalette.GOLD
	tint.a = 0.22
	for loop: PackedVector2Array in Game.data.province_borders.get(_selected_province, []):
		var screen := PackedVector2Array()
		screen.resize(loop.size())
		for i in loop.size():
			screen[i] = map_to_screen(loop[i])
		var tris := Geometry2D.triangulate_polygon(screen)
		for t in range(0, tris.size(), 3):
			draw_colored_polygon(PackedVector2Array([screen[tris[t]],
				screen[tris[t + 1]], screen[tris[t + 2]]]), tint)

## The seam segments the province view would draw right now, in screen
## coordinates: nothing when the view is off or the zoom is below the
## balance floor, and only segments touching the frame.
func _visible_seams() -> Array:
	if not show_provinces or _map_texture == null \
			or view_scale() < Game.data.bal("map_province_min_scale"):
		return []
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for code: String in Game.data.kingdoms:
		for seg: PackedVector2Array in MapOwnership.seams_of(Game.data, Game.state, code):
			var a := map_to_screen(seg[0])
			var b := map_to_screen(seg[1])
			if frame.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
				out.append(PackedVector2Array([a, b]))
	return out

## Test seam: how many seam segments are on screen right now.
func visible_seam_count() -> int:
	return _visible_seams().size()

## Province seams as thin, dense dashes in the palette's seam colour.
func _draw_province_seams() -> void:
	var seams := _visible_seams()
	if seams.is_empty():
		return
	var color := MapPalette.named(Game.data, "province_line")
	color.a = Game.data.bal("map_province_line_alpha")
	var width := Game.data.bal("map_province_line_width")
	var dash := Game.data.bal("map_province_dash_px")
	for seg: PackedVector2Array in seams:
		draw_dashed_line(seg[0], seg[1], color, width, dash, true)

## Public for tests: the same path a mouse-motion event takes.
func hover_at(pos: Vector2) -> void:
	_update_hover(pos)

func hover_object(obj: Dictionary) -> void:
	if obj == _hover_obj:
		return
	_hover_obj = obj
	var label := MapObjects.label_of(Game.data, obj)
	_tooltip.text = label
	_tooltip.visible = label != ""
	queue_redraw()

func hovered_object() -> Dictionary:
	return _hover_obj

## The tooltip's text while a named object is hovered ("" otherwise).
func hover_tooltip() -> String:
	return _tooltip.text if _tooltip.visible else ""

## Test seam: where the tooltip sits, in view coordinates.
func tooltip_rect() -> Rect2:
	return Rect2(_tooltip.position, _tooltip.get_combined_minimum_size())

## Test seam: how many burgs pass the LOD rule at the current zoom.
func visible_burg_count() -> int:
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, view_scale())
	var n := 0
	for b: Dictionary in Game.data.burgs.values():
		if MapObjects.burg_visible(b, min_pop):
			n += 1
	return n

## Outline the kingdom with this Azgaar state id (user request 2026-09-08:
## the country under the mouse shows its border). -1 / unknown ids clear
## the outline. Public for tests.
func hover_state(sid: int) -> void:
	if not _by_state_id.has(sid):
		sid = -1
	if sid == _hover_sid:
		return
	_hover_sid = sid
	var row: Dictionary = _by_state_id.get(sid, {})
	country_hovered.emit(String(row.get("kingdom_code", "")))
	queue_redraw()

func hovered_state() -> int:
	return _hover_sid

## The hovered kingdom's border loops in native map coordinates ([] when
## nothing is hovered). Built from the provinces it holds NOW (MapOwnership),
## so the outline follows conquest instead of the pack's starting map.
func hover_loops() -> Array:
	var row: Dictionary = _by_state_id.get(_hover_sid, {})
	if row.is_empty():
		return []
	return MapOwnership.outline_of(Game.data, Game.state, String(row["kingdom_code"]))

## Public for tests: open the kingdom card for this Azgaar state id; -1 /
## unknown ids (water, stale bitmap) close the card.
func select_state(sid: int) -> void:
	select_object({"kind": "kingdom", "state_id": sid})

## Open the card for any map object (MapObjects.object_at shape). Water or
## an unknown object closes it.
## Whether a click opens the map's own floating card. A screen with a
## detail column turns this off and listens to object_selected instead.
var use_card := true

func select_object(obj: Dictionary) -> void:
	var entry := MapObjects.describe(Game.data, obj, Game.state)
	if entry.is_empty():
		_selected_obj = {}
		_card.hide()
	else:
		_selected_obj = obj
		if use_card:
			_card.show_entry(entry)
	object_selected.emit(entry)
	queue_redraw()

## Clear whatever is selected (a detail column's CLOSE).
func clear_selection() -> void:
	_selected_obj = {}
	_card.hide()
	if _selected_province != "":
		_selected_province = ""
		province_selected.emit("")
	queue_redraw()

func selected_object() -> Dictionary:
	return _selected_obj

func set_ask_enabled(on: bool) -> void:
	_card.ask_enabled = on

## Test seams.
func card() -> MapInfoCard:
	return _card

func card_title() -> Label:
	return _card.title_label()
