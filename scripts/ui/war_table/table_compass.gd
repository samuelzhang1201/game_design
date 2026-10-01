class_name TableCompass
extends Control
## THE WAR TABLE's compass (owner 2026-10-01): the map's compass art (library
## I-73, aged oak, a ship's wheel, brass gears) lying on the table at the
## report's foot, below the paper — the wheel turning while time runs as it
## did on the map, the needle pointing to the map's north as the view turns, a
## press easing the view back to north. Its shadow falls down-right like everything on the table. It is
## drawn under the column, but lies clear of it, so no card covers it.

var view: Map3DView
var _art: Texture2D = null
var _wheel := 0.0

func _ready() -> void:
	name = "TableCompass"
	_art = UiPalette.load_art(CompassLayer.ART_PATH)
	var px := WarTable._num("ui_table_compass_px", 104.0)
	var inset := WarTable._num("ui_table_compass_inset_px", 18.0)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = ScreenLayout.margin() + inset
	offset_right = offset_left + px
	# at the table's foot under the report, in the bookmarks' band left of
	# them: the report fills its column and hid it there (owner 2026-10-01:
	# 指南针被盖住了，往下挪，露出来)
	offset_bottom = -WarTable._num("ui_table_compass_bottom_px", 4.0)
	offset_top = offset_bottom - px
	tooltip_text = "The compass — press to turn the map north"
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if Game.clock_speed > 0:
		_wheel = fposmod(_wheel + deg_to_rad(Game.data.bal("map_compass_turn_deg_per_s"))
			* float(Game.clock_speed) * delta, TAU)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _yaw_known():
		(view.get_node("Viewport/CameraRig") as Map3DCameraRig).start_north()
		accept_event()

func _yaw_known() -> bool:
	return view != null and is_instance_valid(view) and view.context() != null

## The needle's angle: the map's own (Map3DHud.needle_angle), 0 with no map.
func needle() -> float:
	return Map3DHud.needle_angle(view.context().yaw) if _yaw_known() else 0.0

func _draw() -> void:
	var r := size.x * 0.5
	var c := size * 0.5
	var shadow_a := WarTable._num("ui_table_shadow_alpha", 0.34)
	var off := Vector2(WarTable._num("ui_table_shadow_dx", 6.0), WarTable._num("ui_table_shadow_dy", 10.0)) * 0.45
	if _art != null:
		# the shadow is the wheel's own shape (a disc would show through the
		# spokes as a base plate): the art in black, offset, in soft layers
		for i in 3:
			draw_set_transform(c + off * (0.7 + 0.3 * float(i)), _wheel, Vector2.ONE * (1.0 + 0.02 * float(i)))
			draw_texture_rect(_art, Rect2(-size * 0.5, size), false, Color(0, 0, 0, shadow_a * [0.5, 0.3, 0.15][i]))
		draw_set_transform(c, _wheel, Vector2.ONE)
		draw_texture_rect(_art, Rect2(-size * 0.5, size), false)
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
