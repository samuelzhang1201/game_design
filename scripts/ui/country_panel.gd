class_name CountryPanel
extends VBoxContainer
## The hovered kingdom's basic facts, shown in a screen's left column while
## the cursor is over that country's terrain (user request 2026-09-09).
##
## It overlays whatever the column normally holds — the minister on the
## conversation stage, the council log in court — and gets out of the way the
## moment the cursor leaves, so nothing is lost and the column needs no extra
## room. `attach` wires it to a panel and a map; the host screen does not
## have to manage the swap itself.
##
## Content is MapObjects.describe's kingdom entry, so this renders exactly
## what the click-through card would, and follows live ownership.

const SWATCH := 6.0

var _title: Label
var _rows: VBoxContainer
var _swatch: ColorRect
## The siblings hidden while this is up, so they can be restored exactly.
var _covered: Array[Control] = []
var _shown_code := ""
## How many provinces had changed hands when the card was last drawn. The
## demo key flips the province under the cursor, so the card would otherwise
## still be reading the counts from before the conquest it just triggered.
var _shown_version := -1


func _init() -> void:
	name = "CountryPanel"
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


## Put the panel in `column` and have it follow `map`'s hover. The column's
## existing children are remembered so they can be hidden and restored.
static func attach(column: BoxContainer, map: WorldMapView) -> CountryPanel:
	var panel := CountryPanel.new()
	column.add_child(panel)
	map.country_hovered.connect(panel.show_country)
	return panel


## Show the kingdom with this code, or clear when it is "" / unknown. Safe to
## call every mouse move: repeats on the same country are ignored.
func show_country(kingdom_code: String) -> void:
	var version := 0 if Game.state == null else Game.state.province_owner.size()
	if kingdom_code == _shown_code and version == _shown_version:
		return
	_shown_code = kingdom_code
	_shown_version = version
	var row: Dictionary = Game.data.kingdoms.get(kingdom_code, {})
	if row.is_empty():
		_restore()
		return
	var entry := MapObjects.describe(Game.data,
		{"kind": "kingdom", "state_id": int(row["state_id"])}, Game.state)
	if entry.is_empty():
		_restore()
		return
	_title.text = String(entry["title"])
	_swatch.color = MapPalette.color_of(Game.data, kingdom_code)
	for child in _rows.get_children():
		child.queue_free()
	for line: String in entry["lines"]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 7)
		l.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(l)
	_cover()


## Hide the column's normal contents behind this panel. Only siblings that
## are currently visible are touched, so restoring cannot reveal something
## the screen had deliberately hidden.
func _cover() -> void:
	if visible:
		return
	_covered.clear()
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is Control):
			continue
		var c := sibling as Control
		if c.visible:
			c.visible = false
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


## Test seam.
func title_label() -> Label:
	return _title


func rows() -> VBoxContainer:
	return _rows


func shown_country() -> String:
	return _shown_code
