class_name MapDetailPanel
extends PanelContainer
## The fact card for what the player clicked on the map. Towns and the
## player's own provinces get a CARD after Azgaar's burg editor — heraldry, a
## field grid, feature and goods glyphs, wealth and treasury, and a preview
## of the map around the place; other objects (kingdoms, roads, rivers,
## points of interest, regiments, foreign provinces) get their lines. ASK THE
## COUNCIL and CLOSE below. Content comes from MapObjects; this renders.
##
## It lives in the screen's LEFT column (owner ruling 2026-09-10: the left
## column holds the facts of an object, the right column holds characters and
## conversations), taking the column from whatever it normally shows until
## CLOSE. The column draws the frame, so the card itself has no border.

signal ask_requested(text: String)
signal closed

## Sized for the left column's content width (ScreenLayout.LEFT_WIDTH less
## the column panel's margins).
const PREVIEW_SIZE := Vector2(208, 118)
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
var _preview: TerrainPreview
var _lines: VBoxContainer
var _hint: Label
var _ask: Button
var _close: Button
var _ask_text := ""
var _shown_province := ""
## Whether a card is open (distinct from `visible`, which the left column
## sets: a hovered country never closes the card, it only covers it).
var _open := false


func _ready() -> void:
	if name == "":
		name = "DetailPanel"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# It is a child of the column's box now, so it has to ask for the room:
	# without this the scrolling body collapses to nothing.
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	# The column is 120 design px wide and no taller than the screen, so a
	# full town card does not fit: the body scrolls and ASK / CLOSE stay
	# pinned at the bottom where the player can always reach them.
	var scroll := ScrollContainer.new()
	scroll.name = "CardScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "CardBody"
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	_shield = HeraldicShield.new()
	_shield.name = "Shield"
	head.add_child(_shield)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_header(_title, 16)
	titles.add_child(_title)
	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	titles.add_child(_subtitle)
	body.add_child(HSeparator.new())
	_fields = GridContainer.new()
	_fields.name = "Fields"
	_fields.columns = 2
	_fields.add_theme_constant_override("h_separation", 12)
	_fields.add_theme_constant_override("v_separation", 2)
	body.add_child(_fields)
	_features = HBoxContainer.new()
	_features.name = "Features"
	_features.add_theme_constant_override("separation", 8)
	body.add_child(_features)
	_production = VBoxContainer.new()
	_production.name = "Production"
	_production.add_theme_constant_override("separation", 2)
	body.add_child(_production)
	_money = VBoxContainer.new()
	_money.name = "Money"
	_money.add_theme_constant_override("separation", 2)
	body.add_child(_money)
	_lines = VBoxContainer.new()
	_lines.name = "Rows"
	_lines.add_theme_constant_override("separation", 2)
	body.add_child(_lines)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint)
	_preview = TerrainPreview.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_preview)
	_ask = Button.new()
	_ask.name = "DetailAsk"
	_ask.text = "ASK THE COUNCIL"
	_ask.focus_mode = Control.FOCUS_NONE
	_ask.add_theme_font_size_override("font_size", 14)
	_ask.pressed.connect(func() -> void: ask_requested.emit(_ask_text))
	_ask.visible = false
	col.add_child(_ask)
	_close = Button.new()
	_close.name = "DetailClose"
	_close.text = "CLOSE"
	_close.focus_mode = Control.FOCUS_NONE
	_close.add_theme_font_size_override("font_size", 14)
	_close.pressed.connect(func() -> void:
		_close_panel()
		closed.emit())
	col.add_child(_close)
	# Nothing is selected when a screen opens: the card is closed and the
	# column shows its own content (user ruling 2026-09-09).
	_close_panel()


## Whether a card is open. The screen's left column asks this rather than
## reading `visible`, which it owns.
func has_content() -> bool:
	return _open


func _open_panel() -> void:
	_open = true
	show()


func _close_panel() -> void:
	_open = false
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
		_close_panel()
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
	_open_panel()


## The province card: full for the player's own land, basic abroad; "" hides.
func show_province(province_code: String) -> void:
	_shown_province = province_code
	var card := MapObjects.province_card(Game.data, Game.state, province_code) \
		if province_code != "" else {}
	if card.is_empty():
		_shown_province = ""
		_close_panel()
		return
	show_card(card)


## Render a MapObjects card (burg_card / province_card).
func show_card(card: Dictionary) -> void:
	if card.is_empty():
		_close_panel()
		return
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
				row.add_theme_constant_override("separation", 8)
				if String(p.get("tag", "")) != "":
					row.add_child(ResourceIcon.create(String(p["tag"])))
				row.add_child(_line("%s %s" % [String(p["label"]), _num(float(p["units"]))],
					UiPalette.TEXT_SOFT))
				_production.add_child(row)
		# One row per sum, never two labels squeezed into one line (user report
		# 2026-09-09: they wrapped letter by letter).
		for spec in [["wealth", "wealth"], ["town_treasury", "treasury"]]:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
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
	_open_panel()


## A window onto the world map around a place, PREVIEW_SPAN native px
## across, drawn from the same terrain mesh as the map (no render exists).
func _set_preview(center: Vector2) -> void:
	_preview.show_place(center)


func _clear() -> void:
	for box in [_fields, _features, _production, _money, _lines]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_hint.visible = false
	_hint.text = ""
	_preview.visible = false


func _set_ask(ask: String) -> void:
	_ask_text = ask
	_ask.visible = ask_enabled and ask != ""


func _line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
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


func preview() -> TerrainPreview:
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


## The card's map window: the terrain mesh and the shores, scaled so
## `span` native px cover the rect (cover fit, like the old atlas) and
## centred on the place. Reads Game.data only.
class TerrainPreview extends Control:
	var mesh: ArrayMesh
	var span: Vector2 = MapDetailPanel.PREVIEW_SPAN
	var _center := Vector2.ZERO

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_place(center: Vector2) -> void:
		mesh = MapTerrain.shared_mesh(Game.data)
		_center = center
		visible = mesh != null
		queue_redraw()

	func _draw() -> void:
		if mesh == null:
			return
		var k := maxf(size.x / span.x, size.y / span.y)
		var origin := size / 2.0 - _center * k
		draw_rect(Rect2(Vector2.ZERO, size),
			MapTerrain.palette_color(Game.data, "sea_deep", MapTerrain.FALLBACK))
		draw_mesh(mesh, null, Transform2D(0.0, Vector2(k, k), 0.0, origin))
		var coast := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
		var coast_width: float = Game.data.bal("map_coast_width")
		var frame := Rect2(Vector2.ZERO, size).grow(4.0)
		for row: Dictionary in Game.data.coasts:
			var b: Rect2 = row["bbox"]
			if not frame.intersects(Rect2(origin + b.position * k, b.size * k)):
				continue
			var loop: PackedVector2Array = row["polyline"]
			var pts := PackedVector2Array()
			pts.resize(loop.size() + 1)
			for i in loop.size():
				pts[i] = origin + loop[i] * k
			pts[loop.size()] = pts[0]
			draw_polyline(pts, coast, coast_width, true)
