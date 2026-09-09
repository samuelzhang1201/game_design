class_name ProvincePanel
extends VBoxContainer
## The selected province's account, shown in a screen's left column while
## the province view is on and a province is selected (user request
## 2026-09-09). Mirrors CountryPanel: it overlays whatever the column holds
## and restores it when the selection clears.
##
## Content is MapObjects.describe_province: the full account for the
## player's own land, only the commonly known facts for foreign land.

const SWATCH := 6.0

var _title: Label
var _rows: VBoxContainer
var _swatch: ColorRect
var _covered: Array[Control] = []
var _shown_code := ""


func _init() -> void:
	name = "ProvincePanel"
	add_theme_constant_override("separation", 3)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	add_child(head)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_swatch)
	_title = Label.new()
	_title.name = "Title"
	UiPalette.style_header(_title, 10)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 1)
	add_child(_rows)


## Put the panel in `column` and have it follow `map`'s province selection.
static func attach(column: BoxContainer, map: WorldMapView) -> ProvincePanel:
	var panel := ProvincePanel.new()
	column.add_child(panel)
	map.province_selected.connect(panel.show_province)
	return panel


## Show the province with this code; "" or an unknown code clears the panel.
func show_province(province_code: String) -> void:
	_shown_code = province_code
	var entry := MapObjects.describe_province(Game.data, Game.state, province_code) \
		if province_code != "" else {}
	if entry.is_empty():
		_shown_code = ""
		_restore()
		return
	_title.text = String(entry["title"])
	var owner := MapOwnership.owner_of(Game.data, Game.state, province_code)
	_swatch.color = MapPalette.color_of(Game.data, owner)
	for child in _rows.get_children():
		child.queue_free()
	for line: String in entry["lines"]:
		_add_line(line, UiPalette.TEXT_SOFT)
	if String(entry.get("known", "")) == "basic":
		_add_line("Little more is known of foreign land.", UiPalette.TEXT_DIM)
	_cover()


func _add_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 7)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(l)


## Hide the column's normal contents behind this panel. The hovered-country
## card is hidden but NOT remembered: a click always happens under the
## cursor, so that card is up at the moment of selection and must not come
## back when the selection clears — the next hover brings it back itself.
func _cover() -> void:
	if visible:
		return
	_covered.clear()
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is Control):
			continue
		var c := sibling as Control
		if not c.visible:
			continue
		c.visible = false
		if not (c is CountryPanel):
			_covered.append(c)
	visible = true


func _restore() -> void:
	if not visible:
		return
	visible = false
	for c in _covered:
		if is_instance_valid(c):
			c.visible = true
	_covered.clear()


## Test seams.
func title_label() -> Label:
	return _title


func rows() -> VBoxContainer:
	return _rows


func shown_province() -> String:
	return _shown_code
