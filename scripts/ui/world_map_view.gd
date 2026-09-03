class_name WorldMapView
extends Control
## RTS-style viewport into assets/maps/world_map.png, embedded in the
## middle map zone of every gameplay screen — court, conversation, day run
## (user ruling 2026-09-03: the world map IS the middle view — it replaces
## UiPalette's static backdrop there, and the bottom bar's MAP tab goes
## back to meaning "close overlays"). The map
## opens at native scale centered on the player's kingdom, so only a small
## window of Beria is visible; the view pans when the mouse rides an edge
## of the frame (plus drag and wheel-zoom), and clicking a kingdom opens a
## floating info card resolved through the world_state_index.png bitmap
## (tools/import_azgaar.gd) via MapIndex. View-only: reads Game.data,
## never mutates game state.

const MAP_TEXTURE_PATH := "res://assets/maps/world_map.png"
const INDEX_TEXTURE_PATH := "res://assets/maps/world_state_index.png"
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.2
## A press/release pair further apart than this is a drag, not a click.
const CLICK_SLOP := 5.0
## Mouse within this many px of the frame edge scrolls the view (RTS-style).
const EDGE_MARGIN := 12.0
## Edge-scroll speed in screen px/s.
const EDGE_SPEED := 260.0
const CARD_WIDTH := 150.0

var _map_texture: Texture2D
var _index_image: Image
var _by_state_id: Dictionary = {}
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
	if ResourceLoader.exists(MAP_TEXTURE_PATH):
		_map_texture = load(MAP_TEXTURE_PATH)
	if ResourceLoader.exists(INDEX_TEXTURE_PATH):
		var idx: Texture2D = load(INDEX_TEXTURE_PATH)
		_index_image = idx.get_image()
	for code: String in Game.data.kingdoms:
		var row: Dictionary = Game.data.kingdoms[code]
		_by_state_id[int(row["state_id"])] = row
	_build_card()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void: _mouse_inside = false)
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

## Initial framing: native pixels, centered on the player's home kingdom
## (the `you` role's realm), falling back to the map's middle.
func _go_home() -> void:
	_zoom = 1.0
	var center := _map_texture.get_size() / 2.0
	var home := _home_kingdom()
	if not home.is_empty():
		center = Vector2(float(home["center_x"]), float(home["center_y"]))
	_offset = size / 2.0 - center * _zoom
	_clamp_offset()
	_homed = true

func _home_kingdom() -> Dictionary:
	for role: Dictionary in Game.data.roles:
		if String(role.get("id", "")) == "you":
			return Game.data.kingdoms.get(String(role.get("kingdom", "")), {})
	return {}

func _draw() -> void:
	if _map_texture == null:
		return
	if not _homed and size.y > 0.0:
		_go_home()
	draw_texture_rect(_map_texture,
		Rect2(_offset, _map_texture.get_size() * _zoom), false)

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

## Never zoom out past "map covers the frame": no empty gutters, and the
## clamp below can always pin the map to the frame's edges.
func _zoom_min() -> float:
	var tex := _map_texture.get_size()
	if tex.x <= 0.0 or tex.y <= 0.0 or size.x <= 0.0:
		return 0.1
	return maxf(size.x / tex.x, size.y / tex.y)

func _clamp_offset() -> void:
	if _map_texture == null:
		return
	_zoom = maxf(_zoom, _zoom_min())
	var scaled := _map_texture.get_size() * _zoom
	_offset.x = clampf(_offset.x, size.x - scaled.x, 0.0)
	_offset.y = clampf(_offset.y, size.y - scaled.y, 0.0)

func _select_at(pos: Vector2) -> void:
	var map_px := ((pos - _offset) / _zoom).floor()
	select_state(MapIndex.state_at(_index_image, Vector2i(map_px)))

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
