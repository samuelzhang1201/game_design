@tool
class_name TableCompass
extends Control
## THE WAR TABLE's compass (owner 2026-10-01): the map's compass art (library
## I-73, aged oak, a ship's wheel, brass gears) lying on the table at the
## report's foot, below the paper — the wheel turning while time runs as it
## did on the map, the needle pointing to the map's north as the view turns, a
## press easing the view back to north. Its shadow falls down-right like
## everything on the table. It is drawn under the column, in the free band
## between the report's drawn foot and the screen's (owner 2026-10-01:
## 指南针被盖住了，往下挪，露出来): ui_table_compass_px across while the band
## allows, smaller only as far as the band demands — so a card that fills the
## column shrinks it rather than covering it. The control spans the column's
## strip of table (its place never moves, so the landing can slide it); the
## wheel is drawn, and pressed, in wheel_rect().

var view: Map3DView
## The report it lies under.
@export var column: Control
## The wheel's art (library I-73).
@export var art: Texture2D = null:
	set(v):
		art = v
		queue_redraw()
var _wheel := 0.0

## Its place — the column's strip of table, top to the screen's foot — is
## the scene's (scenes/screens/court.tscn, conversation.tscn); the wheel is drawn in
## the band below the report's drawn foot (wheel_rect).
func _ready() -> void:
	if art == null:
		art = UiPalette.load_art(CompassLayer.ART_PATH)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if Game.clock_speed > 0:
		_wheel = fposmod(_wheel + deg_to_rad(Game.data.bal("map_compass_turn_deg_per_s"))
			* float(Game.clock_speed) * delta, TAU)
	queue_redraw()

## Where the wheel lies (local): `fit` over this strip and the report's
## drawn foot.
func wheel_rect() -> Rect2:
	return fit(paper_bottom() - global_position.y, size.y, size.x)

## The wheel's rect in a strip `width` wide whose free band runs from `foot`
## (the report's drawn foot) to `bottom` (local y): ui_table_compass_clear_px
## off the paper, ui_table_compass_px across at most — less only as the band
## demands — ui_table_compass_inset_px in from the strip's left, centred in
## the band. Pure (the tests' seam).
static func fit(foot: float, bottom: float, width: float) -> Rect2:
	var inset := WarTable._num("ui_table_compass_inset_px", 18.0)
	var top := foot + WarTable._num("ui_table_compass_clear_px", 8.0)
	var band := maxf(bottom - top, 0.0)
	var px := minf(minf(WarTable._num("ui_table_compass_px", 104.0), band), maxf(width - inset, 0.0))
	return Rect2(Vector2(inset, top + (band - px) * 0.5), Vector2(px, px))

## The report's drawn foot (global y): its paper as tall as it is drawn
## (PaperStyle.fit_height); the strip's top with no report.
func paper_bottom() -> float:
	if Engine.is_editor_hint():
		# the report is drawn its full height in the editor: lay the wheel
		# at the strip's foot
		var px := WarTable._num("ui_table_compass_px", 104.0) + WarTable._num("ui_table_compass_clear_px", 8.0)
		return global_position.y + size.y - px
	if column == null or not is_instance_valid(column) or not column.is_visible_in_tree():
		return global_position.y
	var r := column.get_global_rect()
	var style := column.get_theme_stylebox("panel") as PaperStyle
	var h := r.size.y
	if style != null and style.fit_height > 0.0 and style.fit_height < h:
		h = style.fit_height
	return r.position.y + h

## The wheel's rect on the screen (global): what the tests hold clear of the
## report, the slip and the bookmarks.
func wheel_global_rect() -> Rect2:
	var w := wheel_rect()
	return Rect2(global_position + w.position, w.size)

func _has_point(point: Vector2) -> bool:
	return wheel_rect().has_point(point)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _yaw_known():
		(view.get_node("Viewport/World/CameraRig") as Map3DCameraRig).start_north()
		accept_event()

func _yaw_known() -> bool:
	return view != null and is_instance_valid(view) and view.context() != null

## The needle's angle: the map's own (Map3DHud.needle_angle), 0 with no map.
func needle() -> float:
	return Map3DHud.needle_angle(view.context().yaw) if _yaw_known() else 0.0

func _draw() -> void:
	var wr := wheel_rect()
	if wr.size.x < 1.0:
		return
	var r := wr.size.x * 0.5
	var c := wr.get_center()
	var wsize := wr.size
	var shadow_a := WarTable._num("ui_table_shadow_alpha", 0.34)
	var off := Vector2(WarTable._num("ui_table_shadow_dx", 6.0), WarTable._num("ui_table_shadow_dy", 10.0)) * 0.45
	if art != null:
		# the shadow is the wheel's own shape (a disc would show through the
		# spokes as a base plate): the art in black, offset, in soft layers
		for i in 3:
			draw_set_transform(c + off * (0.7 + 0.3 * float(i)), _wheel, Vector2.ONE * (1.0 + 0.02 * float(i)))
			draw_texture_rect(art, Rect2(-wsize * 0.5, wsize), false, Color(0, 0, 0, shadow_a * [0.5, 0.3, 0.15][i]))
		draw_set_transform(c, _wheel, Vector2.ONE)
		draw_texture_rect(art, Rect2(-wsize * 0.5, wsize), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(c + off, r, Color(0, 0, 0, shadow_a))
		draw_circle(c, r, UiPalette.table_color("brass_mid", Color("b08a3e")))
	# the needle: gold north, ink south, its own small shadow
	var reach := r * 0.62
	var w := r * 0.13
	var gold := UiPalette.table_color("brass_light", Color("f4db9a"))
	var ink := UiPalette.table_color("ink", Color("2b1f15"))
	draw_set_transform(c, needle(), Vector2.ONE)
	var north := PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(-w, 0)])
	var south := PackedVector2Array([Vector2(0, reach), Vector2(w, 0), Vector2(-w, 0)])
	var by := Vector2(1.5, 2.0)
	draw_colored_polygon(PackedVector2Array([north[0] + by, north[1] + by, north[2] + by]), Color(0, 0, 0, 0.35))
	draw_colored_polygon(PackedVector2Array([south[0] + by, south[1] + by, south[2] + by]), Color(0, 0, 0, 0.35))
	draw_colored_polygon(south, Color(ink, 0.9))
	draw_colored_polygon(north, gold)
	draw_polyline(PackedVector2Array([north[0], north[1], south[0], north[2], north[0]]), ink, 1.2, true)
	draw_circle(Vector2.ZERO, w * 0.55, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
