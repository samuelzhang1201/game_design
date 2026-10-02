@tool
class_name ResourceIcon
extends Control
## A small icon for a resource, a dimension of the realm or a unit type
## (user request 2026-09-09: icons instead of words, with a floating
## tooltip). The icon is GAME ART where the key has some — library I-40 and
## I-47..I-61, one still-life per dimension, installed by install_map_art.py
## ui into assets/2D/icons/resources/ — picked per key in the editor in
## assets/2D/icons/resource_icons.tres (ResourceIconSet; owner 2026-10-02),
## and the art keeps its colour: it is looked at, not tinted. A key without
## art falls back to the drawn glyph, simple strokes in the UI's gold. The
## glyph's name and the tooltip's words are data/resource_icons.csv.

const SIDE := 24.0

## The resource-icon key: its art from ResourceIconSet (assets/2D/icons/
## resource_icons.tres), its words from data/resource_icons.csv.
@export var key := "":
	set(v):
		key = v
		if is_inside_tree() and not Engine.is_editor_hint():
			tooltip_text = tooltip_of(key)
		queue_redraw()
## The glyph's ink, for a key with no art.
@export var color: Color = UiPalette.GOLD:
	set(v):
		color = v
		queue_redraw()

static func create(resource_key: String, tint: Color = UiPalette.GOLD) -> ResourceIcon:
	var icon := ResourceIcon.new()
	icon.key = resource_key
	icon.color = tint
	return icon

## The defaults of an icon made in code; a scene's node keeps what the scene
## says (its properties are set before its script, so _init runs after them).
func _init() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(SIDE, SIDE)
	if size_flags_vertical == Control.SIZE_FILL:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if mouse_filter == Control.MOUSE_FILTER_STOP:
		mouse_filter = Control.MOUSE_FILTER_PASS

## The key's tooltip, unless the scene gives the icon its own (the top bar's
## crown says whose purse it marks); never written in the editor, where it
## would land in the scene.
func _ready() -> void:
	if tooltip_text == "" and not Engine.is_editor_hint():
		tooltip_text = tooltip_of(key)
	queue_redraw()

## The tooltip a key carries: "Label — what it means", or "" for no row.
static func tooltip_of(resource_key: String) -> String:
	var row := _row(resource_key)
	if row.is_empty():
		return ""
	return "%s — %s" % [String(row["label"]), String(row["tooltip"])]

## The key's art (ResourceIconSet), or null when it has none.
static func texture_of(resource_key: String) -> Texture2D:
	return ResourceIconSet.texture_of(resource_key)

## The key's row of data/resource_icons.csv, or {} (always {} in the editor).
static func _row(resource_key: String) -> Dictionary:
	var repo := UiPalette.data()
	return repo.resource_icons.get(resource_key, {}) if repo != null else {}

## The glyph name this key draws (data), or the key itself.
func glyph() -> String:
	return String(_row(key).get("icon", key))

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		s = SIDE
	draw_icon(self, key, Vector2(size.x, size.y) / 2.0, s, color)

## Draw a key's icon on any canvas item: its art when it has any, else its
## glyph in `tint`. `icon_key` may also be a bare glyph name (the goods
## chart's category marks): a key with no CSV row is drawn as that glyph.
static func draw_icon(ci: CanvasItem, icon_key: String, c: Vector2, s: float, tint: Color) -> void:
	var tex := texture_of(icon_key)
	if tex != null:
		draw_icon_texture(ci, tex, c, s)
		return
	var row := _row(icon_key)
	draw_glyph(ci, String(row.get("icon", icon_key)), c, s, tint)

## The art fitted inside an s x s box centred on c, keeping its aspect.
static func draw_icon_texture(ci: CanvasItem, tex: Texture2D, c: Vector2, s: float) -> void:
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var k := s / maxf(maxf(w, h), 1.0)
	var box := Vector2(w * k, h * k)
	ci.draw_texture_rect(tex, Rect2(c - box * 0.5, box), false)

## Draw one glyph on any canvas item (bars draw them at row starts): centred
## on `c`, `s` px across, in `tint`.
static func draw_glyph(ci: CanvasItem, glyph_name: String, c: Vector2, s: float, tint: Color) -> void:
	var u := s / 9.0  # one design unit
	match glyph_name:
		"coin":
			ci.draw_circle(c, 3.6 * u, tint)
			ci.draw_arc(c, 2.2 * u, 0.0, TAU, 16, UiPalette.PANEL_BG, 0.8 * u, true)
		"grain":
			for dx in [-2.2, 0.0, 2.2]:
				var top := c + Vector2(dx * u, -3.8 * u)
				ci.draw_line(c + Vector2(0, 4.0 * u), top, tint, 0.9 * u, true)
				ci.draw_circle(top, 1.0 * u, tint)
		"people":
			for dx in [-1.9, 1.9]:
				var head := c + Vector2(dx * u, -2.0 * u)
				ci.draw_circle(head, 1.4 * u, tint)
				ci.draw_rect(Rect2(head + Vector2(-1.8 * u, 1.8 * u), Vector2(3.6 * u, 3.0 * u)), tint)
		"swords":
			ci.draw_line(c + Vector2(-3.5, 3.5) * u, c + Vector2(3.5, -3.5) * u, tint, 1.0 * u, true)
			ci.draw_line(c + Vector2(3.5, 3.5) * u, c + Vector2(-3.5, -3.5) * u, tint, 1.0 * u, true)
			ci.draw_line(c + Vector2(-2.6, 1.0) * u, c + Vector2(-1.0, 2.6) * u, tint, 1.0 * u, true)
			ci.draw_line(c + Vector2(2.6, 1.0) * u, c + Vector2(1.0, 2.6) * u, tint, 1.0 * u, true)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.2) * u,
				c + Vector2(2.4, -0.5) * u, c + Vector2(1.6, 4.0) * u, c + Vector2(-1.6, 4.0) * u,
				c + Vector2(-2.4, -0.5) * u]), tint)
			ci.draw_circle(c + Vector2(0, 1.6 * u), 1.1 * u, UiPalette.PANEL_BG)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 3.5) * u, c + Vector2(4, 3.5) * u,
				c + Vector2(4, -1.5) * u, c + Vector2(2, 0.5) * u, c + Vector2(0, -3.8) * u,
				c + Vector2(-2, 0.5) * u, c + Vector2(-4, -1.5) * u]), tint)
		"sun":
			ci.draw_circle(c, 2.0 * u, tint)
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2.from_angle(a) * 2.8 * u, c + Vector2.from_angle(a) * 4.2 * u,
					tint, 0.8 * u, true)
		"cross":
			ci.draw_line(c + Vector2(0, -4.2) * u, c + Vector2(0, 4.2) * u, tint, 1.2 * u, true)
			ci.draw_line(c + Vector2(-2.6, -1.6) * u, c + Vector2(2.6, -1.6) * u, tint, 1.2 * u, true)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3.5, -3.5) * u, c + Vector2(3.5, -3.5) * u,
				c + Vector2(3.5, 0.5) * u, c + Vector2(0, 4.2) * u, c + Vector2(-3.5, 0.5) * u]), tint)
		"bow":
			ci.draw_arc(c + Vector2(-1.0 * u, 0), 3.8 * u, -PI / 2.2, PI / 2.2, 12, tint, 1.0 * u, true)
			ci.draw_line(c + Vector2(-1.0, -3.4) * u, c + Vector2(-1.0, 3.4) * u, tint, 0.7 * u, true)
			ci.draw_line(c + Vector2(-2.6, 0) * u, c + Vector2(4.0, 0) * u, tint, 0.8 * u, true)
		"horseshoe":
			ci.draw_arc(c + Vector2(0, 0.6 * u), 3.3 * u, PI * 0.15, PI * 0.85 + PI, 16, tint, 1.3 * u, true)
		"cannon":
			ci.draw_circle(c + Vector2(-1.2 * u, 1.6 * u), 2.0 * u, tint)
			ci.draw_line(c + Vector2(-1.0, 0.4) * u, c + Vector2(4.0, -3.2) * u, tint, 1.6 * u, true)
		"sail":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.4, -4.2) * u, c + Vector2(3.4, 1.4) * u,
				c + Vector2(-0.4, 1.4) * u]), tint)
			ci.draw_line(c + Vector2(-3.8, 2.6) * u, c + Vector2(3.8, 2.6) * u, tint, 1.2 * u, true)
		"waves":
			for dy in [-2.2, 0.8, 3.8]:
				var pts := PackedVector2Array()
				for i in 9:
					var x := -4.0 + float(i)
					pts.append(c + Vector2(x, dy + 0.9 * sin(x * PI / 2.0)) * u)
				ci.draw_polyline(pts, tint, 1.0 * u, true)
		"wall":
			ci.draw_rect(Rect2(c + Vector2(-4, -1) * u, Vector2(8, 5) * u), tint)
			for dx in [-4.0, -1.0, 2.0]:
				ci.draw_rect(Rect2(c + Vector2(dx, -3.5) * u, Vector2(2, 2.5) * u), tint)
		"tower":
			ci.draw_rect(Rect2(c + Vector2(-2, -2) * u, Vector2(4, 6.2) * u), tint)
			for dx in [-2.5, 0.5]:
				ci.draw_rect(Rect2(c + Vector2(dx, -4.2) * u, Vector2(1.6, 2.2) * u), tint)
		"market":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4.2, -0.5) * u,
				c + Vector2(0, -4.0) * u, c + Vector2(4.2, -0.5) * u]), tint)
			ci.draw_line(c + Vector2(-3.0, -0.5) * u, c + Vector2(-3.0, 4.0) * u, tint, 1.0 * u, true)
			ci.draw_line(c + Vector2(3.0, -0.5) * u, c + Vector2(3.0, 4.0) * u, tint, 1.0 * u, true)
		"huts":
			for dx in [-2.6, 1.2]:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(dx - 1.8, 1.0) * u,
					c + Vector2(dx, -2.2) * u, c + Vector2(dx + 1.8, 1.0) * u]), tint)
				ci.draw_rect(Rect2(c + Vector2(dx - 1.4, 1.0) * u, Vector2(2.8, 2.6) * u), tint)
		"anchor":
			ci.draw_circle(c + Vector2(0, -3.2 * u), 1.1 * u, tint)
			ci.draw_line(c + Vector2(0, -2.0) * u, c + Vector2(0, 3.8) * u, tint, 1.0 * u, true)
			ci.draw_line(c + Vector2(-2.6, -0.4) * u, c + Vector2(2.6, -0.4) * u, tint, 1.0 * u, true)
			ci.draw_arc(c + Vector2(0, 0.8 * u), 3.0 * u, PI * 0.15, PI * 0.85, 10, tint, 1.0 * u, true)
		"pick":
			ci.draw_line(c + Vector2(-3.4, 3.6) * u, c + Vector2(2.0, -1.8) * u, tint, 1.0 * u, true)
			ci.draw_arc(c + Vector2(1.6, 0.2) * u, 3.4 * u, -PI * 0.95, -PI * 0.25, 10, tint, 1.2 * u, true)
		"gem":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3.8, -1.2) * u, c + Vector2(-1.8, -3.6) * u,
				c + Vector2(1.8, -3.6) * u, c + Vector2(3.8, -1.2) * u, c + Vector2(0, 4.0) * u]), tint)
		"cloth":
			ci.draw_rect(Rect2(c + Vector2(-3.6, -3.0) * u, Vector2(7.2, 6.0) * u), tint)
			ci.draw_line(c + Vector2(-3.6, -1.0) * u, c + Vector2(3.6, 1.0) * u, UiPalette.PANEL_BG, 0.8 * u, true)
		"drop":
			# A raindrop, round below and pointed above (a lozenge read as a
			# gem, owner 2026-09-28).
			ci.draw_circle(c + Vector2(0, 1.4) * u, 2.4 * u, tint)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.2) * u,
				c + Vector2(2.3, 0.8) * u, c + Vector2(-2.3, 0.8) * u]), tint)
		"cloud":
			ci.draw_circle(c + Vector2(-1.8, 0.6) * u, 2.0 * u, tint)
			ci.draw_circle(c + Vector2(1.0, -0.6) * u, 2.6 * u, tint)
			ci.draw_rect(Rect2(c + Vector2(-3.8, 0.6) * u, Vector2(7.4, 2.0) * u), tint)
		"flake":
			for i in 3:
				var d := Vector2(cos(PI * float(i) / 3.0), sin(PI * float(i) / 3.0)) * 3.8 * u
				ci.draw_line(c - d, c + d, tint, 1.0 * u, true)
		"letter":
			ci.draw_rect(Rect2(c + Vector2(-3.8, -2.6) * u, Vector2(7.6, 5.2) * u), tint, false, 1.0 * u)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-3.8, -2.6) * u, c + Vector2(0, 0.6) * u,
				c + Vector2(3.8, -2.6) * u]), tint, 1.0 * u, true)
		_:
			ci.draw_rect(Rect2(c - Vector2(3, 3) * u, Vector2(6, 6) * u), tint, false, 1.0 * u)
