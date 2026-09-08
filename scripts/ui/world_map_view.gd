class_name WorldMapView
extends Control
## RTS-style viewport into the loaded map pack's render, embedded in the
## middle map zone of every gameplay screen — court, conversation, day run
## (user ruling 2026-09-03: the world map IS the middle view — it replaces
## UiPalette's static backdrop there, and the bottom bar's MAP tab goes
## back to meaning "close overlays"). The map
## opens covering the frame, and zooms out to the whole world; the view
## pans when the mouse rides an edge
## of the frame (plus drag and wheel-zoom), the kingdom under the mouse
## gets its border outlined (borders.csv), towns and points of interest show
## as pins (LOD by zoom, MapObjects), hovering a pin or road names it,
## and clicking a kingdom opens a
## floating info card resolved through the world_state_index.png bitmap
## (tools/import_azgaar.gd) via MapIndex. View-only: reads Game.data,
## never mutates game state.

## A card's ASK THE COUNCIL button: the screen owning an input box puts this
## text in it (nothing is sent until the player presses Enter).
signal place_asked(text: String)

const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.2
## A press/release pair further apart than this is a drag, not a click.
const CLICK_SLOP := 5.0
## Mouse within this many px of the frame edge scrolls the view (RTS-style).
const EDGE_MARGIN := 12.0
## Edge-scroll speed in screen px/s.
const EDGE_SPEED := 260.0
## Hover outline: a dark halo under a gold line so it reads on both the
## pale land fills and the ocean.
const HOVER_WIDTH := 2.0
const HOVER_HALO_WIDTH := 4.0
const HOVER_HALO := Color(0.05, 0.04, 0.02, 0.55)
## Pin sizes in screen px (constant at any zoom; LOD hides the small ones).
const PIN_CAPITAL := 4.0
const PIN_TOWN := 2.5
const PIN_VILLAGE := 1.5
const PIN_MARKER := 3.0
const PIN_OUTLINE := Color(0.05, 0.04, 0.02, 0.9)
const TOOLTIP_OFFSET := Vector2(10.0, 12.0)

var _map_texture: Texture2D
var _index_image: Image
## world_map.png may be a sharper integer-scale render of the map (see
## tools/import_azgaar.gd); the index bitmap and CSV coordinates stay at
## native scale, so texture coords = native coords * _render_scale.
var _render_scale := 1.0
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
	for code: String in Game.data.kingdoms:
		var row: Dictionary = Game.data.kingdoms[code]
		_by_state_id[int(row["state_id"])] = row
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
	for loop: PackedVector2Array in hover_loops():
		var pts := PackedVector2Array()
		pts.resize(loop.size() + 1)
		for i in loop.size():
			pts[i] = map_to_screen(loop[i])
		pts[loop.size()] = pts[0]  # close the ring
		draw_polyline(pts, HOVER_HALO, HOVER_HALO_WIDTH, true)
		draw_polyline(pts, UiPalette.GOLD, HOVER_WIDTH, true)
	_draw_pins()
	_draw_hover()
	_draw_object_highlight(_selected_obj)

## Screen px per native map px — the LOD and pick radii are defined on it.
func view_scale() -> float:
	return _zoom * _render_scale

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

func _draw_diamond(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0)]), color)

## Ring around the hovered pin; halo + gold line along the hovered road/river.
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
		"route", "river":
			var table: Dictionary = Game.data.routes if obj["kind"] == "route" else Game.data.rivers
			var pts: PackedVector2Array = table[obj["code"]]["polyline"]
			var screen := PackedVector2Array()
			screen.resize(pts.size())
			for i in pts.size():
				screen[i] = map_to_screen(pts[i])
			draw_polyline(screen, HOVER_HALO, HOVER_HALO_WIDTH, true)
			draw_polyline(screen, UiPalette.GOLD, HOVER_WIDTH, true)

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
func map_to_screen(native: Vector2) -> Vector2:
	return _offset + native * _render_scale * _zoom

func screen_to_map(pos: Vector2) -> Vector2:
	return (pos - _offset) / _zoom / _render_scale

func _state_under(pos: Vector2) -> int:
	return MapIndex.state_at(_index_image, Vector2i(screen_to_map(pos).floor()))

func _select_at(pos: Vector2) -> void:
	select_object(_object_under(pos))

func _object_under(pos: Vector2) -> Dictionary:
	var s := view_scale()
	return MapObjects.object_at(Game.data, _index_image, _province_image, _biome_image,
		screen_to_map(pos), Game.data.bal("map_pick_radius_px") / s,
		Game.data.bal("map_line_pick_px") / s, MapObjects.min_burg_pop_for_scale(Game.data, s))

func _update_hover(pos: Vector2) -> void:
	hover_state(_state_under(pos))
	hover_object(_object_under(pos))
	_place_tooltip(pos)

## Beside the cursor, pushed back inside the frame at the edges so a pin
## in a corner still shows its whole name.
func _place_tooltip(pos: Vector2) -> void:
	var tip := _tooltip.get_combined_minimum_size()
	var limit := (size - tip).max(Vector2.ZERO)
	_tooltip.position = (pos + TOOLTIP_OFFSET).clamp(Vector2.ZERO, limit)

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
	queue_redraw()

func hovered_state() -> int:
	return _hover_sid

## The hovered kingdom's border loops in native map coordinates ([] when
## nothing is hovered or the pack ships no borders.csv).
func hover_loops() -> Array:
	var row: Dictionary = _by_state_id.get(_hover_sid, {})
	if row.is_empty():
		return []
	return Game.data.borders.get(String(row["kingdom_code"]), [])

## Public for tests: open the kingdom card for this Azgaar state id; -1 /
## unknown ids (water, stale bitmap) close the card.
func select_state(sid: int) -> void:
	select_object({"kind": "kingdom", "state_id": sid})

## Open the card for any map object (MapObjects.object_at shape). Water or
## an unknown object closes it.
func select_object(obj: Dictionary) -> void:
	var entry := MapObjects.describe(Game.data, obj)
	if entry.is_empty():
		_selected_obj = {}
		_card.hide()
	else:
		_selected_obj = obj
		_card.show_entry(entry)
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
