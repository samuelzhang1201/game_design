@tool
class_name BrassStyle
extends StyleBox
## THE WAR TABLE's brass (owner 2026-10-01): a round brass stud, the clock's
## pause / play / 2x / 4x buttons under the war table — the button's art sits
## on it. `lit` is the speed that runs now (brighter, ringed); `hover` a touch
## warmer. draw_brass is shared by the board's nails and the report's pin.

@export var lit := false
@export var hover := false
@export var brass: Array[Color] = [Color("f4db9a"), Color("b08a3e"), Color("6b4e1c")]
@export var shadow_alpha := 0.34

static func make(p_lit: bool, p_hover: bool) -> BrassStyle:
	var s := BrassStyle.new()
	s.lit = p_lit
	s.hover = p_hover
	s.brass = [UiPalette.table_color("brass_light", s.brass[0]),
		UiPalette.table_color("brass_mid", s.brass[1]),
		UiPalette.table_color("brass_dark", s.brass[2])]
	s.shadow_alpha = WarTable._num("ui_table_shadow_alpha", 0.34)
	s.set_content_margin_all(3.0)
	return s

func _draw(ci: RID, rect: Rect2) -> void:
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var c := rect.get_center()
	var cols: Array = brass.duplicate()
	if not lit:
		# an idle stud is dulled, so the running speed reads at a glance
		for i in cols.size():
			cols[i] = (cols[i] as Color).darkened(0.38 if not hover else 0.2)
	draw_brass(ci, c, r, cols, shadow_alpha, lit)
	if lit:
		# the running speed: a bright ring round the stud
		var ring := PackedVector2Array()
		for i in 33:
			var a := TAU * float(i) / 32.0
			ring.append(c + Vector2(cos(a), sin(a)) * (r + 1.5))
		RenderingServer.canvas_item_add_polyline(ci, ring, PackedColorArray([Color(cols[0], 0.95)]), 1.6, true)

## A brass disc seen from above: its shadow down-right, the dark rim, the
## body, a lit spot upper left.
static func draw_brass(ci: RID, c: Vector2, r: float, cols: Array, shade_alpha: float,
		spot := true) -> void:
	# a soft shadow: three rings, each wider and fainter
	for i in 3:
		RenderingServer.canvas_item_add_circle(ci, c + Vector2(r, r) * 0.32, r * (1.0 + 0.14 * float(i)),
			Color(0, 0, 0, shade_alpha * [0.55, 0.3, 0.15][i]))
	RenderingServer.canvas_item_add_circle(ci, c, r, cols[2])
	# the body, stepped from the lit upper left toward the shadowed rim
	var steps := 7
	for k in steps:
		var t := float(k) / float(steps - 1)
		var col := (cols[1] as Color).lerp(cols[0], t * (0.75 if spot else 0.45))
		RenderingServer.canvas_item_add_circle(ci, c - Vector2(r, r) * 0.2 * t, r * (0.88 - 0.62 * t), col)
	if not spot:
		# a face that carries a mark (the dial): its middle stays the body's
		RenderingServer.canvas_item_add_circle(ci, c, r * 0.62, cols[1])

