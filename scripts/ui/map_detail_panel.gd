class_name MapDetailPanel
extends PanelContainer
## The right detail column (user ruling 2026-09-09): what the player clicked
## on the map — a kingdom, a town, a road, a river, a point of interest, or
## in the province view a province — with ASK THE COUNCIL and CLOSE. It
## exists only while something is selected; the screen lays the map out
## around it (ScreenLayout). Content comes from MapObjects; this renders.

signal ask_requested(text: String)
signal closed

const SWATCH := 6.0

## Screens with an input box turn this on; the day run has none.
var ask_enabled := false:
	set(on):
		ask_enabled = on
		_ask.visible = on and _ask_text != ""

var _title: Label
var _swatch: ColorRect
var _rows: VBoxContainer
var _ask: Button
var _close: Button
var _ask_text := ""
var _shown_province := ""


func _ready() -> void:
	name = "DetailPanel" if name == "" else name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	col.add_child(head)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_swatch.visible = false
	head.add_child(_swatch)
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.style_header(_title, 8)
	head.add_child(_title)
	col.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 1)
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_rows)
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


## entry = {title, lines, ask} from MapObjects.describe; {} hides.
func show_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		hide()
		return
	_shown_province = ""
	_swatch.visible = false
	_fill(String(entry.get("title", "")), entry.get("lines", []), String(entry.get("ask", "")))
	show()


## The province account (MapObjects.describe_province); "" hides.
func show_province(province_code: String) -> void:
	_shown_province = province_code
	var entry := MapObjects.describe_province(Game.data, Game.state, province_code) \
		if province_code != "" else {}
	if entry.is_empty():
		_shown_province = ""
		hide()
		return
	var owner := MapOwnership.owner_of(Game.data, Game.state, province_code)
	_swatch.color = MapPalette.color_of(Game.data, owner)
	_swatch.visible = true
	var lines: Array = entry["lines"].duplicate()
	if String(entry.get("known", "")) == "basic":
		lines.append("Little more is known of foreign land.")
	_fill(String(entry["title"]), lines, String(entry.get("ask", "")))
	show()


func _fill(title: String, lines: Array, ask: String) -> void:
	_title.text = title
	for child in _rows.get_children():
		child.queue_free()
	for line in lines:
		var l := Label.new()
		l.text = String(line)
		l.add_theme_font_size_override("font_size", 7)
		l.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(l)
	_ask_text = ask
	_ask.visible = ask_enabled and ask != ""


## Test seams.
func title_label() -> Label:
	return _title


func rows() -> VBoxContainer:
	return _rows


func ask_button() -> Button:
	return _ask


func close_button() -> Button:
	return _close


func shown_province() -> String:
	return _shown_province
