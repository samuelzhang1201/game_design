class_name MapScreen
extends Control
## Full-screen world-map overlay toggled by the bottom bar's MAP tab (user
## ruling 2026-09-03, supersedes 2026-08-30's "MAP closes overlays"): a
## pan/zoom view of assets/maps/world_map.png with clickable kingdoms,
## resolved through the world_state_index.png bitmap (tools/import_azgaar.py)
## via MapIndex. View-only: reads Game.data, never mutates game state.

const MAP_TEXTURE_PATH := "res://assets/maps/world_map.png"
const INDEX_TEXTURE_PATH := "res://assets/maps/world_state_index.png"
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.2
## A press/release pair further apart than this is a drag, not a click.
const CLICK_SLOP := 5.0
const PANEL_WIDTH := 200.0

var _map_texture: Texture2D
var _index_image: Image
var _by_state_id: Dictionary = {}
var _view: Control
var _panel_title: Label
var _panel_body: Label
var _offset := Vector2.ZERO
var _zoom := 1.0
var _fitted := false
var _dragging := false
var _press_pos := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	if ResourceLoader.exists(MAP_TEXTURE_PATH):
		_map_texture = load(MAP_TEXTURE_PATH)
	if ResourceLoader.exists(INDEX_TEXTURE_PATH):
		var idx: Texture2D = load(INDEX_TEXTURE_PATH)
		_index_image = idx.get_image()
	for code: String in Game.data.kingdoms:
		var row: Dictionary = Game.data.kingdoms[code]
		_by_state_id[int(row["state_id"])] = row
	_build_view()
	_build_panel()
	hide()

func _build_view() -> void:
	_view = Control.new()
	_view.name = "MapView"
	_view.clip_contents = true
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.offset_right = -PANEL_WIDTH
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_view_input)
	_view.resized.connect(func() -> void:
		_fitted = false
		_view.queue_redraw())
	add_child(_view)

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 1, 8))
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)
	_panel_title = Label.new()
	_panel_title.name = "PanelTitle"
	_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(_panel_title, 11)
	col.add_child(_panel_title)
	col.add_child(HSeparator.new())
	_panel_body = Label.new()
	_panel_body.name = "PanelBody"
	_panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	col.add_child(_panel_body)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: hide())
	col.add_child(close)
	_clear_panel()

func _draw_view() -> void:
	if _map_texture == null:
		_view.draw_string(get_theme_default_font(),
			Vector2(16, 24), "No map imported — run tools/import_azgaar.py")
		return
	if not _fitted:
		_fit_view()
	_view.draw_texture_rect(_map_texture,
		Rect2(_offset, _map_texture.get_size() * _zoom), false)

## Initial framing: fit the map's height, centered horizontally.
func _fit_view() -> void:
	var s := _view.size
	if s.y <= 0.0:
		return
	_zoom = clampf(s.y / _map_texture.get_height(), ZOOM_MIN, ZOOM_MAX)
	_offset = Vector2((s.x - _map_texture.get_width() * _zoom) * 0.5, 0.0)
	_clamp_offset()
	_fitted = true

func _on_view_input(ev: InputEvent) -> void:
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
				_view.queue_redraw()

func _zoom_at(pos: Vector2, factor: float) -> void:
	var before := (pos - _offset) / _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_offset = pos - before * _zoom
	_clamp_offset()
	_view.queue_redraw()

func _clamp_offset() -> void:
	var scaled := _map_texture.get_size() * _zoom
	_offset.x = _clamp_axis(_offset.x, _view.size.x, scaled.x)
	_offset.y = _clamp_axis(_offset.y, _view.size.y, scaled.y)

func _clamp_axis(o: float, view_len: float, map_len: float) -> float:
	if map_len <= view_len:
		return clampf(o, 0.0, view_len - map_len)
	return clampf(o, view_len - map_len, 0.0)

func _select_at(pos: Vector2) -> void:
	var map_px := ((pos - _offset) / _zoom).floor()
	select_state(MapIndex.state_at(_index_image, Vector2i(map_px)))

## Public for tests: show the kingdom with this Azgaar state id, or clear
## the panel for -1 / unknown ids (stale bitmap vs. CSVs degrades silently).
func select_state(sid: int) -> void:
	var row: Dictionary = _by_state_id.get(sid, {})
	if row.is_empty():
		_clear_panel()
	else:
		_show_kingdom(row)

func _clear_panel() -> void:
	_panel_title.text = ""
	_panel_body.text = "Click a kingdom."

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
	_panel_title.text = String(row["label"])
	var lines: Array[String] = [
		"Capital: %s" % capital.get("label", "—"),
		"Provinces: %d" % province_count,
		"Towns: %d" % town_count,
		"Population: %s" % row["population"],
		"Neighbors: %s" % (", ".join(neighbors) if not neighbors.is_empty() else "—"),
	]
	if not court.is_empty():
		lines.append("Court: %s" % ", ".join(court))
	_panel_body.text = "\n".join(lines)

## Test seam.
func panel_title() -> Label:
	return _panel_title
