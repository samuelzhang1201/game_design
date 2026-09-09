class_name MapDetailPanel
extends PanelContainer
## The right detail column (user rulings 2026-09-09): what the player clicked
## on the map. Towns and the player's own provinces get a CARD after
## Azgaar's burg editor — heraldry, a field grid, feature and goods glyphs,
## wealth and treasury, and a preview of the map around the place; other
## objects (kingdoms, roads, rivers, points of interest, foreign provinces)
## get their lines. ASK THE COUNCIL and CLOSE below. Content comes from
## MapObjects; this renders.

signal ask_requested(text: String)
signal closed

const PREVIEW_SIZE := Vector2(134, 76)
## How much of the world the preview shows, in native map px.
const PREVIEW_SPAN := Vector2(90, 51)

## Screens with an input box turn this on; the day run has none.
var ask_enabled := false:
	set(on):
		ask_enabled = on
		_ask.visible = on and _ask_text != ""

var _shield: HeraldicShield
var _title: Label
var _subtitle: Label
var _fields: GridContainer
var _features: HBoxContainer
var _production: VBoxContainer
var _money: VBoxContainer
var _preview: TextureRect
var _lines: VBoxContainer
var _hint: Label
var _ask: Button
var _close: Button
var _ask_text := ""
var _shown_province := ""
var _shown_card: Dictionary = {}


func _ready() -> void:
	name = "DetailPanel" if name == "" else name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	col.add_child(head)
	_shield = HeraldicShield.new()
	_shield.name = "Shield"
	head.add_child(_shield)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_header(_title, 8)
	titles.add_child(_title)
	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 7)
	_subtitle.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	titles.add_child(_subtitle)
	col.add_child(HSeparator.new())
	_fields = GridContainer.new()
	_fields.name = "Fields"
	_fields.columns = 2
	_fields.add_theme_constant_override("h_separation", 6)
	_fields.add_theme_constant_override("v_separation", 1)
	col.add_child(_fields)
	_features = HBoxContainer.new()
	_features.name = "Features"
	_features.add_theme_constant_override("separation", 4)
	col.add_child(_features)
	_production = VBoxContainer.new()
	_production.name = "Production"
	_production.add_theme_constant_override("separation", 1)
	col.add_child(_production)
	_money = VBoxContainer.new()
	_money.name = "Money"
	_money.add_theme_constant_override("separation", 1)
	col.add_child(_money)
	_lines = VBoxContainer.new()
	_lines.name = "Rows"
	_lines.add_theme_constant_override("separation", 1)
	col.add_child(_lines)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.add_theme_font_size_override("font_size", 7)
	_hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	_preview = TextureRect.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_child(_preview)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_ask = Button.new()
	_ask.name = "DetailAsk"
	_ask.text = "ASK THE COUNCIL"
	_ask.focus_mode = Control.FOCUS_NONE
	_ask.add_theme_font_size_override("font_size", 7)
	_ask.pressed.connect(func() -> void: ask_requested.emit(_ask_text))
	_ask.visible = false
	col.add_child(_ask)
	_close = Button.new()
	_close.name = "DetailClose"
	_close.text = "CLOSE"
	_close.focus_mode = Control.FOCUS_NONE
	_close.add_theme_font_size_override("font_size", 7)
	_close.pressed.connect(func() -> void:
		hide()
		closed.emit())
	col.add_child(_close)
	# Nothing is selected when a screen opens: the column starts hidden and
	# the map has the whole width (user ruling 2026-09-09).
	hide()


## Follow a map: pins, lines, and kingdoms through object_selected; provinces
## through province_selected. An empty selection hides the panel.
func follow(map: WorldMapView) -> void:
	map.object_selected.connect(show_entry)
	map.province_selected.connect(show_province)


## entry = {title, lines, ask, obj?} from the map; a town gets its card,
## everything else its lines; {} hides.
func show_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		hide()
		return
	_shown_province = ""
	var obj: Dictionary = entry.get("obj", {})
	if String(obj.get("kind", "")) == "burg":
		show_card(MapObjects.burg_card(Game.data, Game.state, String(obj["code"])))
		return
	_clear()
	_shield.visible = false
	_title.text = String(entry.get("title", ""))
	_subtitle.visible = false
	for line in entry.get("lines", []):
		_lines.add_child(_line(String(line), UiPalette.TEXT_SOFT))
	_set_ask(String(entry.get("ask", "")))
	show()


## The province card: full for the player's own land, basic abroad; "" hides.
func show_province(province_code: String) -> void:
	_shown_province = province_code
	var card := MapObjects.province_card(Game.data, Game.state, province_code) \
		if province_code != "" else {}
	if card.is_empty():
		_shown_province = ""
		hide()
		return
	show_card(card)


## Render a MapObjects card (burg_card / province_card).
func show_card(card: Dictionary) -> void:
	if card.is_empty():
		hide()
		return
	_shown_card = card
	_clear()
	_shield.visible = true
	_shield.set_arms(MapPalette.color_of(Game.data, String(card.get("kingdom_code", ""))),
		String(card.get("initial", "")))
	_title.text = String(card.get("title", ""))
	_subtitle.text = String(card.get("subtitle", ""))
	_subtitle.visible = _subtitle.text != ""
	for f in card.get("fields", []):
		_fields.add_child(_line(String(f[0]), UiPalette.TEXT_MUTED))
		_fields.add_child(_line(String(f[1]), UiPalette.TEXT_SOFT))
	var basic := String(card.get("known", "full")) == "basic"
	if not basic:
		var features: Array = card.get("features", [])
		if not features.is_empty():
			_features.add_child(_line("Features", UiPalette.TEXT_MUTED))
			for key in features:
				_features.add_child(ResourceIcon.create(String(key)))
		var production: Array = card.get("production", [])
		if not production.is_empty():
			_production.add_child(_line("Production", UiPalette.TEXT_MUTED))
			for i in mini(production.size(), int(Game.data.bal("province_card_max_goods"))):
				var p: Dictionary = production[i]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				if String(p.get("tag", "")) != "":
					row.add_child(ResourceIcon.create(String(p["tag"])))
				row.add_child(_line("%s %s" % [String(p["label"]), _num(float(p["units"]))],
					UiPalette.TEXT_SOFT))
				_production.add_child(row)
		# One row per sum, never two labels squeezed into one line (user report
		# 2026-09-09: they wrapped letter by letter).
		for spec in [["wealth", "wealth"], ["town_treasury", "treasury"]]:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 3)
			cell.add_child(ResourceIcon.create(String(spec[0])))
			var text := _line("%s %s" % [
				String((Game.data.resource_icons.get(String(spec[0]), {}) as Dictionary).get("label", spec[1])),
				_num(float(card.get(String(spec[1]), 0.0)))], UiPalette.TEXT_SOFT)
			text.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell.add_child(text)
			_money.add_child(cell)
		_set_preview(card.get("center", Vector2.ZERO))
	else:
		_hint.text = "Little more is known of foreign land."
		_hint.visible = true
	_set_ask(String(card.get("ask", "")))
	show()


## A window onto the world map around a place: an atlas region of the render
## at the pack's calibration, PREVIEW_SPAN native px across.
func _set_preview(center: Vector2) -> void:
	var tex: Texture2D = UiPalette.load_art(Game.data.map_texture_path)
	if tex == null:
		_preview.visible = false
		return
	var k := float(tex.get_width()) / float(Game.data.map_info.get("width", "2560"))
	var on_render := (center * Game.data.render_scale + Game.data.render_offset) * k
	var span := PREVIEW_SPAN * k
	var region := Rect2(on_render - span / 2.0, span)
	region.position = region.position.clamp(Vector2.ZERO, tex.get_size() - span)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	_preview.texture = atlas
	_preview.visible = true


func _clear() -> void:
	for box in [_fields, _features, _production, _money, _lines]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_hint.visible = false
	_hint.text = ""
	_preview.visible = false
	_preview.texture = null


func _set_ask(ask: String) -> void:
	_ask_text = ask
	_ask.visible = ask_enabled and ask != ""


func _line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 7)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.2f" % v


## Test seams.
func title_label() -> Label:
	return _title


func subtitle_label() -> Label:
	return _subtitle


func fields() -> GridContainer:
	return _fields


func features_row() -> HBoxContainer:
	return _features


func production_box() -> VBoxContainer:
	return _production


func preview() -> TextureRect:
	return _preview


func rows() -> VBoxContainer:
	return _lines


func hint_label() -> Label:
	return _hint


func ask_button() -> Button:
	return _ask


func close_button() -> Button:
	return _close


func shown_province() -> String:
	return _shown_province


func shown_card() -> Dictionary:
	return _shown_card
