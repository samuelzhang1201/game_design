class_name WarMarginKey
extends Control
## The laid sheet's key in the WAR ROOM's margin (spec 2026-10-01-war-room-design
## §2): a compass rose, north up and turned with the officer's view; the shared
## ScaleBar in the pack's own measure, on MapGeometry.nice_step's 1-2-5 ladder
## and restated at every zoom (WarRoomView.units_per_px: the table metres a
## screen px spans at the camera's target, back to pack px, times the pack's
## distance_scale); and a legend of the sheet's ink — every mark DRAWN, the
## same strokes WarInkPainter lays on the vellum. Off the sheet: it stands in
## the screen's top-right corner under the close button. Every size a
## balance.csv war_key_* key.

## A click on the compass rose: ease the room back to the sheet's foot (spec
## 2026-10-02-war-room-v2 §1.1).
signal north_pressed

## The legend's entries in reading order (the sheet's ink, spec §2).
const LEGEND := [
	{"key": "road", "label": "Road"}, {"key": "trail", "label": "Trail"},
	{"key": "river", "label": "River"}, {"key": "border", "label": "Border"},
	{"key": "seam", "label": "Seam"}, {"key": "town", "label": "Town"},
	{"key": "peak", "label": "Peak"}, {"key": "contour", "label": "Contour"},
	{"key": "wood", "label": "Woods"}, {"key": "manor", "label": "Manor"},
	{"key": "walls", "label": "Walled town"}, {"key": "port", "label": "Port"},
	{"key": "bridge", "label": "Bridge"}, {"key": "ford", "label": "Ford"},
	{"key": "supply", "label": "Supply road"}, {"key": "courier", "label": "Courier"},
	{"key": "weather", "label": "Foul weather"}, {"key": "spy", "label": "Spy report"},
	{"key": "mark_brigands", "label": "Brigands"}, {"key": "mark_pirates", "label": "Pirates"},
	{"key": "mark_mines", "label": "Mine"}, {"key": "mark_battlefields", "label": "Battlefield"},
	{"key": "mark_lighthouses", "label": "Lighthouse"},
]

var _repo: DataRepository
var _view: WarRoomView


func setup(repo: DataRepository, view: WarRoomView) -> void:
	_repo = repo
	_view = view
	mouse_filter = Control.MOUSE_FILTER_STOP   # the rose only (_has_point)
	tooltip_text = "Turn to the sheet's foot"
	update_minimum_size()
	queue_redraw()


## The legend's entry keys, in order (what the slip lists).
static func legend_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in LEGEND:
		out.append(String(e["key"]))
	return out


## The compass rose's box, this Control's px (the top-left square of
## war_key_rose_px, as _draw places it).
func rose_rect() -> Rect2:
	var rose := _repo.bal("war_key_rose_px") if _repo != null else 0.0
	return Rect2(Vector2.ZERO, Vector2(rose, rose))


## Only the rose takes a click; the legend and the bar let it through.
func _has_point(point: Vector2) -> bool:
	return rose_rect().has_point(point)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and rose_rect().has_point(mb.position):
		north_pressed.emit()
		accept_event()


## {distance, text, width_px} the scale bar shows now ({} with no sheet laid).
func bar() -> Dictionary:
	if _repo == null or _view == null:
		return {}
	var unit := String(_repo.map_info.get("distance_unit", ""))
	if float(_repo.map_info.get("distance_scale", "0")) <= 0.0:
		unit = "km"
	return Map3DHud.scale_bar_for(_view.units_per_px(), _repo.bal("war_key_scale_max_px"), unit)


func _get_minimum_size() -> Vector2:
	if _repo == null:
		return Vector2.ZERO
	var rows := _rows(_repo)
	return Vector2(_repo.bal("war_key_width_px"),
		_repo.bal("war_key_rose_px") + _repo.bal("war_key_gap_px") + float(rows) * _repo.bal("war_key_row_px"))


func _draw() -> void:
	if _repo == null:
		return
	var ink := _ink()
	var rose := _repo.bal("war_key_rose_px")
	_draw_rose(Vector2(rose * 0.5, rose * 0.5), rose * 0.5, ink)
	# the shared bar draws in the bottom-right of `area`, map_scale_bar_margin_px in
	var inset := _repo.bal("map_scale_bar_margin_px")
	ScaleBar.draw(self, bar(), Vector2(size.x + inset, rose + inset - _repo.bal("war_key_gap_px")))
	var top := rose + _repo.bal("war_key_gap_px")
	var row_h := _repo.bal("war_key_row_px")
	var cols := maxi(1, int(_repo.bal("war_key_columns")))
	var col_w := size.x / float(cols)
	var font := UiPalette.role_font("body")
	var font_px := int(_repo.bal("war_key_font_px"))
	var mark_w := _repo.bal("war_key_mark_px")
	var per_col := _rows(_repo)
	for i in LEGEND.size():
		@warning_ignore("integer_division")
		var col := i / per_col
		var row := i % per_col
		var y := top + row_h * (float(row) + 0.5)
		var x := col_w * float(col)
		_draw_mark(String(LEGEND[i]["key"]), Rect2(x, y - row_h * 0.35, mark_w, row_h * 0.7), ink)
		if font != null:
			draw_string(font, Vector2(x + mark_w + _repo.bal("war_key_gap_px"), y + float(font_px) * 0.35),
				String(LEGEND[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, col_w - mark_w, font_px, ink)


## The legend's rows: its entries over war_key_columns columns, rounded up.
static func _rows(repo: DataRepository) -> int:
	var cols := maxi(1, int(repo.bal("war_key_columns")))
	@warning_ignore("integer_division")
	var rows := (LEGEND.size() + cols - 1) / cols
	return rows


## The sepia ink on the war table's paper; the light type of a dark card.
func _ink() -> Color:
	return _repo.war_palette["ink"] if UiPalette.war_table() else UiPalette.ink("soft")


## A four-point rose, its north point filled and lettered N, turned clockwise
## by the officer's yaw (north is the sheet's top edge).
func _draw_rose(c: Vector2, r: float, ink: Color) -> void:
	var reach := r * _repo.bal("war_key_rose_reach")
	var w := r * _repo.bal("war_key_rose_width")
	var yaw := deg_to_rad(_view.camera_rig().yaw_deg) if _view != null else 0.0
	draw_arc(c, r * _repo.bal("war_key_rose_ring"), 0.0, TAU, 40, ink, 1.0, true)
	draw_set_transform(c, yaw, Vector2.ONE)
	for k in 4:
		var a := float(k) * PI * 0.5
		var tip := Vector2(0, -reach).rotated(a)
		var side := Vector2(w, 0).rotated(a)
		# a point is two halves: the north one wholly inked, the others half
		draw_colored_polygon(PackedVector2Array([tip, -side, Vector2.ZERO]), ink)
		if k == 0:
			draw_colored_polygon(PackedVector2Array([tip, side, Vector2.ZERO]), ink)
		else:
			draw_polyline(PackedVector2Array([tip, side, Vector2.ZERO, tip]), ink, 1.0, true)
	var font := UiPalette.display_font()
	if font != null:
		var px := int(_repo.bal("war_key_font_px"))
		var tw := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, Vector2(-tw * 0.5, -reach - 2.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One legend mark in `r`: the stroke the painter lays for `key`.
func _draw_mark(key: String, r: Rect2, ink: Color) -> void:
	var pal: Dictionary = _repo.war_palette
	var a := Vector2(r.position.x, r.get_center().y)
	var b := Vector2(r.end.x, r.get_center().y)
	var line := _repo.bal("war_key_line_px")
	var dash := _repo.bal("war_key_dash_px")
	if key.begins_with("mark_"):   # the map's marks (spec 2026-10-07-war-room-p2 §1.3), a hazard in rubric
		var type := key.trim_prefix("mark_")
		var row: Dictionary = _repo.war_marks.get(type, {})
		WarMarkGlyph.draw(self, String(row.get("glyph", "dot")), r.get_center(), r.size.y * 0.9,
			pal.get("hazard_ink", pal["rubric"]) if _repo.war_mark_hazards.has(type) else ink)
		return
	match key:
		"road":
			draw_line(a, b, ink, line * 1.6, true)
		"trail":
			for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([a, b]), dash, dash * 0.6):
				draw_polyline(d, ink, line, true)
		"river":
			var wave := PackedVector2Array()
			for i in 9:
				var t := float(i) / 8.0
				wave.append(Vector2(lerpf(a.x, b.x, t), a.y + sin(t * TAU) * r.size.y * 0.25))
			draw_polyline(wave, pal["river_ink"], line * 1.3, true)
		"border":
			var parts := WarSheetInk.dashed(PackedVector2Array([a, b]), dash, dash * 0.8)
			for i in parts.size():
				draw_polyline(parts[i], ink, line * 1.3, true)
				if i + 1 < parts.size():
					draw_circle(parts[i][parts[i].size() - 1].lerp(parts[i + 1][0], 0.5), line * 0.8, ink)
		"seam":
			var faint := Color(ink, ink.a * _repo.bal("war_key_faint_alpha"))
			for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([a, b]), dash * 0.5, dash * 0.5):
				draw_polyline(d, faint, line * 0.7, true)
		"town":
			var c := r.get_center()
			var rr := r.size.y * 0.42
			draw_arc(c, rr, 0.0, TAU, 20, ink, line, true)
			draw_circle(c, rr * 0.35, ink)
		"peak":
			var c := r.get_center()
			var s := r.size.y * 0.5
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.9, s * 0.6),
				c + Vector2(-s * 0.9, s * 0.6)]), ink)
		"wood":
			var c := r.get_center()
			var s := r.size.y * 0.45
			var wood: Color = pal.get("wood_ink", ink)
			draw_circle(c + Vector2(-s * 0.7, -s * 0.15), s * 0.45, wood)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.6, -s), c + Vector2(s * 1.1, s * 0.4), c + Vector2(s * 0.1, s * 0.4)]), wood)
		"manor":
			var faint := Color(ink, ink.a * _repo.bal("war_key_faint_alpha"))
			for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([a, b]), dash * 0.6, dash * 0.5):
				draw_polyline(d, faint, line * 0.6, true)
		"walls":
			var c := r.get_center()
			var s := r.size.y * 0.4
			draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), ink, false, line, true)
			for q in 4:
				var corner := c + Vector2(s if q % 2 == 0 else -s, s if q < 2 else -s)
				draw_rect(Rect2(corner - Vector2.ONE * s * 0.25, Vector2.ONE * s * 0.5), ink)
		"port":
			var c := r.get_center()
			var s := r.size.y * 0.42
			draw_line(c + Vector2(0, -s), c + Vector2(0, s), ink, line, true)
			draw_line(c + Vector2(-s * 0.45, -s * 0.55), c + Vector2(s * 0.45, -s * 0.55), ink, line, true)
			draw_arc(c + Vector2(0, s * 0.2), s * 0.75, 0.15 * PI, 0.85 * PI, 10, ink, line, true)
		"bridge":
			var c := r.get_center()
			var s := r.size.y * 0.4
			draw_line(a, b, pal["river_ink"], line * 1.3, true)
			for side in [-1.0, 1.0]:
				draw_line(c + Vector2(-s * 0.8, s * 0.55 * side), c + Vector2(s * 0.8, s * 0.55 * side), ink, line, true)
		"ford":
			var c := r.get_center()
			var s := r.size.y * 0.42
			draw_line(a, b, pal["river_ink"], line * 1.3, true)
			for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([c + Vector2(0, -s), c + Vector2(0, s)]), s * 0.35, s * 0.3):
				draw_polyline(d, ink, line, true)
		"supply":
			var intel: Color = pal.get("intel_ink", ink)
			for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([a, b]), dash * 0.3, dash * 0.6):
				draw_polyline(d, intel, line, true)
		"courier":
			var intel: Color = pal.get("intel_ink", ink)
			var c := r.get_center()
			var s := r.size.y * 0.4
			draw_circle(c + Vector2(0, s * 0.4), s * 0.4, intel)
			draw_line(c + Vector2(0, s * 0.4), c + Vector2(0, -s), intel, line, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, -s * 0.8), c + Vector2(0, -s * 0.6)]), intel)
		"weather":
			var intel: Color = pal.get("intel_ink", ink)
			var c := r.get_center()
			var s := r.size.y * 0.45
			draw_arc(c + Vector2(-s * 0.3, 0), s * 0.45, PI, TAU, 10, intel, line, true)
			draw_arc(c + Vector2(s * 0.3, -s * 0.1), s * 0.55, PI, TAU, 10, intel, line, true)
			for i in 3:
				var x := -s * 0.4 + float(i) * s * 0.4
				draw_line(c + Vector2(x, s * 0.2), c + Vector2(x - s * 0.15, s * 0.7), intel, line * 0.8, true)
		"spy":
			var c := r.get_center()
			var rr := r.size.y * 0.42
			var ring := PackedVector2Array()
			for i in 25:
				ring.append(c + Vector2.from_angle(TAU * float(i) / 24.0) * rr)
			for d: PackedVector2Array in WarSheetInk.dashed(ring, rr * 0.4, rr * 0.3):
				draw_polyline(d, pal["rubric"], line, true)
		"contour":
			var faint := Color(ink, ink.a * _repo.bal("war_contour_alpha"))
			draw_arc(Vector2(r.get_center().x, r.end.y + r.size.y * 0.6), r.size.x * 0.55, PI * 1.15, PI * 1.85,
				16, faint, line * 0.8, true)
			draw_arc(Vector2(r.get_center().x, r.end.y + r.size.y * 1.1), r.size.x * 0.55, PI * 1.2, PI * 1.8,
				16, faint, line * 0.8, true)
