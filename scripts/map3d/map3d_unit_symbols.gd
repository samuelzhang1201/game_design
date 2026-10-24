@tool
class_name Map3DUnitSymbols
extends Resource
## Normalized original ink paths, shared by the map and its legend.
@export var glyphs: Dictionary = {}
@export var frames: Dictionary = {}
@export var labels: Dictionary = {}
@export var legend_keys: PackedStringArray = []
@export var marker_size := Vector2.ZERO
@export var line_px := 0.0
@export var dash_px := 0.0
@export var ink := Color()
@export var paper := Color()
@export var selected_ink := Color()
@export var font: Font
@export var font_px := 0


func arm_of(repo: DataRepository, reg: Dictionary) -> String:
	var arm := "fleet" if String(reg.get("is_naval", "0")) == "1" else String(reg.get("organization_arm", MapObjects.regiment_arm(repo, reg)))
	return arm if glyphs.has(arm) else "unknown"


## No strength priority: hidden strength changes cannot displace a known symbol.
func layout(repo: DataRepository, points: Array, obstacles: Array, selected: Array) -> Array:
	var out: Array = []
	for point: Dictionary in points:
		var reg: Dictionary = point.get("reg", {})
		var ghost := bool(point.get("ghost", false))
		var code := String(point.get("code", reg.get("regiment_code", "")))
		var royal := not ghost and String(reg.get("is_royal", "0")) == "1"
		var symbol_rect := Rect2((point["pos"] as Vector2) - marker_size * 0.5, marker_size)
		var hit_rect := symbol_rect
		if royal:
			for path: PackedVector2Array in (glyphs.get("royal", {}) as Dictionary).get("lines", []):
				for at: Vector2 in _points(path, symbol_rect): hit_rect = hit_rect.expand(at)
		out.append({"code": code, "pos": point["pos"], "anchor": point["pos"],
			"arm": "unknown" if ghost else arm_of(repo, reg),
			"frame": "ghost" if ghost else ("own" if String(reg.get("kingdom_code", "")) == repo.resolve_realm("player_realm") else "hostile"),
			"royal": royal, "symbol_rect": symbol_rect, "rect": hit_rect})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if selected.has(a["code"]) != selected.has(b["code"]): return selected.has(a["code"])
		if a["royal"] != b["royal"]: return a["royal"]
		return String(a["code"]) < String(b["code"]))
	var margin := repo.bal("map_army_stack_gap_px") * 0.5 + line_px
	var boxes: Array = out.map(func(m: Dictionary) -> Rect2: return (m["rect"] as Rect2).grow(margin))
	var hidden: Array = out.map(func(_m: Dictionary) -> bool: return false)
	var offsets := Map3DDeclutter.place(boxes, hidden, obstacles, repo.bal("map3d_declutter_step_px"), repo.bal("map3d_declutter_max_px"))
	for i: int in out.size():
		out[i]["rect"] = Rect2((out[i]["rect"] as Rect2).position + (offsets[i] as Vector2), (out[i]["rect"] as Rect2).size)
		out[i]["symbol_rect"] = Rect2((out[i]["symbol_rect"] as Rect2).position + (offsets[i] as Vector2), marker_size)
		out[i]["pos"] = (out[i]["rect"] as Rect2).get_center()
	return out


func draw_symbol(canvas: CanvasItem, rect: Rect2, arm: String, frame: String, royal: bool = false, selected: bool = false) -> void:
	var color := selected_ink if selected else ink
	var outline := _points(frames.get(frame, PackedVector2Array()), rect)
	if outline.size() > 2:
		canvas.draw_colored_polygon(outline, paper)
		if frame == "ghost": MapRuler.dashed_path(canvas, outline, color, line_px, dash_px)
		else: canvas.draw_polyline(outline, color, line_px, true)
	if arm != "": _draw_glyph(canvas, rect, arm, color)
	if royal: _draw_glyph(canvas, rect, "royal", color)


func _draw_glyph(canvas: CanvasItem, rect: Rect2, key: String, color: Color) -> void:
	var glyph: Dictionary = glyphs.get(key, glyphs.get("unknown", {}))
	for polygon: PackedVector2Array in glyph.get("paper", []):
		canvas.draw_colored_polygon(_points(polygon, rect), paper)
	for path: PackedVector2Array in glyph.get("lines", []):
		canvas.draw_polyline(_points(path, rect), color, line_px, true)
	for polygon: PackedVector2Array in glyph.get("fills", []):
		canvas.draw_colored_polygon(_points(polygon, rect), color)
	var text := String(glyph.get("text", ""))
	if text != "" and font != null:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		canvas.draw_string(font, rect.get_center() + Vector2(-width * 0.5, font_px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)


func _points(path: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in path: out.append(rect.get_center() + point * rect.size * 0.5)
	return out
