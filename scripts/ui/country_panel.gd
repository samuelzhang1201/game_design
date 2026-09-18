class_name CountryPanel
extends VBoxContainer
## The hovered kingdom's basic facts, shown in a screen's left column while
## the cursor is over that country's terrain (user request 2026-09-09).
##
## It overlays whatever the column normally holds — the minister on the
## conversation stage, the dashboard in court — and gets out of the way the
## moment the cursor leaves, so nothing is lost and the column needs no extra
## room. `attach` wires it to a panel and a map; the host screen decides what
## it covers (owner ruling 2026-09-10: a card the player CLICKED outranks the
## country the cursor happens to be over, so the screen orders the column).
##
## Content is MapObjects.describe's kingdom entry, so this renders exactly
## what the click-through card would, and follows live ownership.

const SWATCH := 12.0
## The realm's temper shown on the player's own country's card.
const REALM_METRICS := ["unrest", "legitimacy", "army_quality", "church_opinion"]

var _title: Label
var _realm_grid: GridContainer
var _realm_values: Dictionary = {}
var _rows: VBoxContainer
var _swatch: ColorRect
var _shown_code := ""
## How many provinces had changed hands when the card was last drawn. The
## demo key flips the province under the cursor, so the card would otherwise
## still be reading the counts from before the conquest it just triggered.
var _shown_version := -1


func _init() -> void:
	name = "CountryPanel"
	add_theme_constant_override("separation", 6)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_swatch)
	_title = Label.new()
	_title.name = "Title"
	UiPalette.style_header(_title, 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	add_child(HSeparator.new())
	# The realm's temper, on the player's own country's card (owner
	# 2026-09-14: everything but the purses left the top bar for here). Two
	# icon-and-value pairs a line, so the fixed column never has to widen.
	_realm_grid = GridContainer.new()
	_realm_grid.name = "RealmTemper"
	_realm_grid.columns = 4
	_realm_grid.add_theme_constant_override("h_separation", 6)
	_realm_grid.add_theme_constant_override("v_separation", 4)
	_realm_grid.visible = false
	add_child(_realm_grid)
	for key: String in REALM_METRICS:
		var icon := ResourceIcon.create(key)
		icon.name = "Icon_" + key
		_realm_grid.add_child(icon)
		var value := Label.new()
		value.name = "Value_" + key
		value.add_theme_font_size_override("font_size", 14)
		value.custom_minimum_size = Vector2(36, 0)
		_realm_grid.add_child(value)
		_realm_values[key] = value
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)


## Put the panel in `column` and have it follow `map`'s hover. The screen
## connects to the same signal to re-order the column around it.
static func attach(column: BoxContainer, map: WorldMapView) -> CountryPanel:
	var panel := CountryPanel.new()
	column.add_child(panel)
	panel.follow(map)
	return panel


## Follow one more map's hover — any map with WorldMapView's
## `country_hovered(kingdom_code)` signal (the 3D map, owner 2026-09-18).
func follow(map: Control) -> void:
	map.connect("country_hovered", show_country)


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
		_clear()
		return
	var entry := MapObjects.describe(Game.data,
		{"kind": "kingdom", "state_id": int(row["state_id"])}, Game.state)
	if entry.is_empty():
		_clear()
		return
	_title.text = String(entry["title"])
	_swatch.color = MapPalette.color_of(Game.data, kingdom_code)
	_refresh_realm()
	for child in _rows.get_children():
		child.queue_free()
	for line: String in entry["lines"]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(l)
	visible = true


## The temper grid: shown, and filled from the live metrics, only while the
## card is the player's own realm — a foreign court's mood is not known.
func _refresh_realm() -> void:
	var mine := Game.state != null and _shown_code == Game.data.resolve_realm("player_realm")
	_realm_grid.visible = mine
	if not mine:
		return
	for key: String in _realm_values:
		(_realm_values[key] as Label).text = str(int(Game.state.metrics.get(key, 0.0)))


func _ready() -> void:
	Game.state_changed.connect(func() -> void:
		if is_inside_tree() and visible:
			_refresh_realm())


## Test seam: the temper grid's value for a metric ("" when hidden).
func realm_metric_text(key: String) -> String:
	if not _realm_grid.visible or not _realm_values.has(key):
		return ""
	return String((_realm_values[key] as Label).text)


## Whether a country is under the cursor right now. The screen's left column
## asks this to decide who holds the column.
func has_content() -> bool:
	return _shown_code != ""


func _clear() -> void:
	_shown_code = ""
	visible = false


## Test seam.
func title_label() -> Label:
	return _title


func rows() -> VBoxContainer:
	return _rows


func shown_country() -> String:
	return _shown_code
