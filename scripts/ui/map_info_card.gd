class_name MapInfoCard
extends PanelContainer
## The world map's floating info card (spec 2026-09-08): a title, a few
## lines, and two buttons — ASK THE COUNCIL (only when a screen with an
## order/talk box enabled it; it pre-fills that box and never sends) and
## CLOSE. Content comes from MapObjects.describe; this node only renders.

signal ask_requested(text: String)
signal closed

const WIDTH := 300.0

## Screens with an input box turn this on (WorldMapView.set_ask_enabled).
var ask_enabled := false:
	set(on):
		ask_enabled = on
		_ask.visible = on and _ask_text != ""

var _title: Label
var _body: Label
var _ask: Button
var _ask_text := ""

func _init() -> void:
	name = "InfoCard"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.GOLD, 2, 16))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(WIDTH + 4.0)
	offset_top = 8.0
	offset_right = -8.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_title = Label.new()
	_title.name = "CardTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_header(_title, 16)
	col.add_child(_title)
	col.add_child(HSeparator.new())
	_body = Label.new()
	_body.name = "CardBody"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 16)
	_body.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	col.add_child(_body)
	_ask = Button.new()
	_ask.name = "CardAsk"
	_ask.text = "ASK THE COUNCIL"
	_ask.focus_mode = Control.FOCUS_NONE
	_ask.add_theme_font_size_override("font_size", 16)
	_ask.pressed.connect(func() -> void: ask_requested.emit(_ask_text))
	_ask.visible = false
	col.add_child(_ask)
	var close := Button.new()
	close.name = "CardClose"
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(func() -> void:
		hide()
		closed.emit())
	col.add_child(close)
	hide()

## entry = {title, lines: Array[String], ask} from MapObjects.describe.
func show_entry(entry: Dictionary) -> void:
	_title.text = String(entry.get("title", ""))
	_body.text = "\n".join(PackedStringArray(entry.get("lines", [])))
	_ask_text = String(entry.get("ask", ""))
	_ask.visible = ask_enabled and _ask_text != ""
	show()

func title_label() -> Label:
	return _title

func body_label() -> Label:
	return _body

func ask_button() -> Button:
	return _ask
