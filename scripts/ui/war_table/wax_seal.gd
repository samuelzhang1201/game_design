class_name WaxSeal
extends Button
## THE WAR TABLE's council seal (owner 2026-10-01): ENTER THE COUNCIL, the
## screen's one primary action, as a red wax seal pressed with the crown
## (ui_table_palette.csv wax_*), a paper tag under it naming the order. The
## whole of it is the button; hover warms the wax, a press sinks it. Its text
## stays the order (tests and tooltips read it) and is written on the tag.

var _tag: PanelContainer
var _word: Label

func _init(order: String = "ENTER THE COUNCIL") -> void:
	name = "CouncilHandle"
	text = order
	tooltip_text = "Go before your council"
	focus_mode = Control.FOCUS_NONE
	flat = true
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, clear)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, Color(0, 0, 0, 0))
	var seal := WarTable._num("ui_seal_px", 100.0)
	_tag = PanelContainer.new()
	_tag.name = "Tag"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := WarTable.slip_style(0.0, WarTable.SEED_TAG)
	paper.content_margin_left = 14
	paper.content_margin_right = 14
	paper.content_margin_top = 5
	paper.content_margin_bottom = 6
	_tag.add_theme_stylebox_override("panel", paper)
	_word = Label.new()
	_word.name = "Order"
	_word.text = UiPalette.readable_title(order) if order == order.to_upper() else order
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(_word, 15, UiPalette.table_color("ink", Color("2b1f15")))
	_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_child(_word)
	add_child(_tag)
	var tag_min := _tag.get_combined_minimum_size()
	custom_minimum_size = Vector2(maxf(seal + 8.0, tag_min.x), seal + tag_min.y - 6.0)
	resized.connect(_place_tag)

func _place_tag() -> void:
	var tm := _tag.get_combined_minimum_size()
	_tag.size = tm
	_tag.position = Vector2((size.x - tm.x) * 0.5, size.y - tm.y)

func _draw() -> void:
	var seal := WarTable._num("ui_seal_px", 100.0)
	var r := seal * 0.5
	var sunk := 1.5 if button_pressed or is_pressed() else 0.0
	var c := Vector2(size.x * 0.5, r + sunk)
	var light := UiPalette.table_color("wax_light", Color("a63a2f"))
	var mid := UiPalette.table_color("wax_mid", Color("7a1c17"))
	var dark := UiPalette.table_color("wax_dark", Color("5a1410"))
	if is_hovered():
		light = light.lightened(0.08)
		mid = mid.lightened(0.06)
	var shadow_a := WarTable._num("ui_table_shadow_alpha", 0.34)
	var off := Vector2(WarTable._num("ui_table_shadow_dx", 6.0), WarTable._num("ui_table_shadow_dy", 10.0)) * 0.5
	for i in 3:
		draw_colored_polygon(_blob(c + off, r * (1.0 + 0.07 * float(i)), 7, -0.4), Color(0, 0, 0, shadow_a * [0.5, 0.3, 0.18][i]))
	# two pours of wax, their rims irregular, each rim smoothed by an
	# antialiased line (a filled polygon has none)
	var outer := _blob(c, r, 7, -0.4)
	draw_colored_polygon(outer, dark)
	draw_polyline(_closed(outer), dark, 1.5, true)
	var body := _blob(c, r * 0.95, 9, 0.2)
	draw_colored_polygon(body, mid)
	draw_polyline(_closed(body), mid, 1.2, true)
	# the pour's body swells toward the light: stepped from its middle tone
	# to a warmer lit side, upper left
	for k in 5:
		var t := float(k + 1) / 5.0
		draw_colored_polygon(_blob(c - Vector2(r, r) * 0.1 * t, r * (0.9 - 0.2 * t), 9, 0.2),
			mid.lerp(light, 0.22 * t))
	# the raised rim of the pour catches the light on its upper left
	draw_arc(c, r * 0.86, PI * 1.02, PI * 1.62, 24, Color(light, 0.7), r * 0.08, true)
	# the pressed disc: sunk, its far edge lit and its near edge in shadow
	draw_circle(c, r * 0.64, dark)
	draw_circle(c + Vector2(0.9, 1.3), r * 0.6, mid.darkened(0.08))
	draw_arc(c, r * 0.62, PI * 0.1, PI * 0.72, 24, Color(light, 0.5), 1.6, true)
	ResourceIcon.draw_glyph(self, "crown", c + Vector2(0.8, 1.1), r * 0.66, Color(light, 0.55))
	ResourceIcon.draw_glyph(self, "crown", c, r * 0.66, dark.darkened(0.2))

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

## A wax pour's rim: a circle of `lobes` soft bulges turned by `phase`.
func _blob(c: Vector2, r: float, lobes: int, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		var k := 1.0 + 0.06 * sin(a * lobes + phase) + 0.03 * sin(a * (lobes + 4) + phase * 2.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts
