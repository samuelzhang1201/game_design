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
## gets its border outlined (borders.csv), and clicking a kingdom opens a
## floating info card resolved through the world_state_index.png bitmap
## (tools/import_azgaar.gd) via MapIndex. View-only: reads Game.data,
## never mutates game state.

const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.2
## A press/release pair further apart than this is a drag, not a click.
const CLICK_SLOP := 5.0
## Mouse within this many px of the frame edge scrolls the view (RTS-style).
const EDGE_MARGIN := 12.0
## Edge-scroll speed in screen px/s.
const EDGE_SPEED := 260.0
const CARD_WIDTH := 150.0
## Hover outline: a dark halo under a gold line so it reads on both the
## pale land fills and the ocean.
const HOVER_WIDTH := 2.0
const HOVER_HALO_WIDTH := 4.0
const HOVER_HALO := Color(0.05, 0.04, 0.02, 0.55)

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
var _card: PanelContainer
var _card_title: Label
var _card_body: Label
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
	if _map_texture != null and _index_image != null:
		_render_scale = float(_map_texture.get_width()) / float(_index_image.get_width())
	for code: String in Game.data.kingdoms:
		var row: Dictionary = Game.data.kingdoms[code]
		_by_state_id[int(row["state_id"])] = row
	_build_card()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void:
		_mouse_inside = false
		hover_state(-1))
	resized.connect(func() -> void:
		_clamp_offset()
		queue_redraw())
	# No imported map: stay invisible so the styled backdrop shows instead.
	visible = _map_texture != null

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "InfoCard"
	_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_card.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 1, 8))
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_card.offset_left = -(CARD_WIDTH + 4.0)
	_card.offset_top = 4.0
	_card.offset_right = -4.0
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_card.add_child(col)
	_card_title = Label.new()
	_card_title.name = "CardTitle"
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(_card_title, 10)
	col.add_child(_card_title)
	col.add_child(HSeparator.new())
	_card_body = Label.new()
	_card_body.name = "CardBody"
	_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_body.add_theme_font_size_override("font_size", 8)
	_card_body.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	col.add_child(_card_body)
	var close := Button.new()
	close.name = "CardClose"
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 8)
	close.pressed.connect(func() -> void: _card.hide())
	col.add_child(close)
	_card.hide()

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
	select_state(_state_under(pos))

func _update_hover(pos: Vector2) -> void:
	hover_state(_state_under(pos))

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

## Public for tests: open the info card for the kingdom with this Azgaar
## state id; -1 / unknown ids (water, stale bitmap) close the card.
func select_state(sid: int) -> void:
	var row: Dictionary = _by_state_id.get(sid, {})
	if row.is_empty():
		_card.hide()
		return
	_show_kingdom(row)
	_card.show()

func _show_kingdom(row: Dictionary) -> void:
	var code := String(row["kingdom_code"])
	var province_count := 0
	for p: Dictionary in Game.data.provinces.values():
		if String(p["kingdom_code"]) == code:
			province_count += 1
	var town_count := 0
	for b: Dictionary in Game.data.burgs.values():
		if String(b["kingdom_code"]) == code:
			town_count += 1
	var capital: Dictionary = Game.data.burgs.get(String(row["capital_burg"]), {})
	var neighbors: Array[String] = []
	for n: String in String(row["neighbor_codes"]).split("|", false):
		neighbors.append(String(Game.data.kingdoms.get(n, {}).get("label", n)))
	var court: Array[String] = []
	for role: Dictionary in Game.data.roles:
		if String(role.get("kingdom", "")) == code:
			court.append(String(role["display_name"]))
	_card_title.text = String(row["label"])
	var lines: Array[String] = [
		"Capital: %s" % capital.get("label", "—"),
		"Provinces: %d" % province_count,
		"Towns: %d" % town_count,
		"Population: %s" % row["population"],
		"Neighbors: %s" % (", ".join(neighbors) if not neighbors.is_empty() else "—"),
	]
	if not court.is_empty():
		lines.append("Court: %s" % ", ".join(court))
	_card_body.text = "\n".join(lines)

## Test seams.
func card() -> PanelContainer:
	return _card

func card_title() -> Label:
	return _card_title
