class_name PaperStyle
extends StyleBox
## A sheet of paper lying on THE WAR TABLE (owner 2026-10-01): the map's
## vellum sheet, the steward's report, the news slip, the seal's tag. The
## paper's texture is laid on a DECKLED outline (its edge wanders in by up to
## `deckle_px`, point by point, from a fixed `seed` — presentation only, never
## the engine's stream), optionally drawn `tilt_deg` off square about its
## centre (the paper turns; the panel's content does not), over a soft shadow
## thrown down and to the right by the table's one light. `rules` draws that
## many ink rules round the content (the sheet's frame round the map); `pin`
## a brass pin at the head. Every number is balance.csv ui_table_* / ui_paper_*,
## every colour data/ui_table_palette.csv (see PaperStyle.make).

const PAPER_PATH := "res://assets/2D/ui/missive_board/letter_aged.png"

var texture: Texture2D = null
var tint := Color.WHITE
var deckle_px := 2.5
var deckle_step := 11.0
var seed := 7
var tilt_deg := 0.0
var shadow_offset := Vector2(6, 10)
var shadow_alpha := 0.34
var shadow_soft := 7.0
var shadow_color := Color.BLACK
## Ink rules round the content rect: count, width, the gap between them and how
## far outside the content the first sits.
var rules := 0
var rule_width := 1.5
var rule_gap := 4.0
var rule_out := 3.0
var rule_color := Color("3b2a1b")
var pin := false
## The share of the texture cut from each side before it is laid on the paper
## (the letter art's own ruled border and burnt rim: the map sheet draws its
## own rules, so it takes only the paper's middle).
var uv_inset := Vector2.ZERO
## A pale wash laid over the texture (paler paper than the art's own ochre).
var lift := Color(1, 1, 1, 0)
## When > 0, the paper is drawn only this tall from the top of its rect (a
## report sized to its content; the table shows below it).
var fit_height := 0.0
var pin_px := 12.0
var brass := [Color("f4db9a"), Color("b08a3e"), Color("6b4e1c")]

## A paper style dressed from the tables: `tint_key` a ui_table_palette.csv
## colour ("paper" or "sheet"), `margin` the content margin in design px.
static func make(tint_key: String, margin: float, p_seed: int) -> PaperStyle:
	var s := PaperStyle.new()
	if ResourceLoader.exists(PAPER_PATH):
		s.texture = load(PAPER_PATH)
	s.tint = UiPalette.table_color(tint_key, Color.WHITE)
	s.seed = p_seed
	s.deckle_px = _num("ui_paper_deckle_px", 2.5)
	s.deckle_step = _num("ui_paper_deckle_step_px", 11.0)
	s.shadow_offset = Vector2(_num("ui_table_shadow_dx", 6.0), _num("ui_table_shadow_dy", 10.0))
	s.shadow_alpha = _num("ui_table_shadow_alpha", 0.34)
	s.shadow_soft = _num("ui_table_shadow_soft_px", 7.0)
	s.shadow_color = UiPalette.table_color("shadow", Color.BLACK)
	s.rule_color = UiPalette.table_color("paper_rule", s.rule_color)
	s.pin_px = _num("ui_pin_px", 12.0)
	s.brass = [UiPalette.table_color("brass_light", s.brass[0]),
		UiPalette.table_color("brass_mid", s.brass[1]),
		UiPalette.table_color("brass_dark", s.brass[2])]
	s.lift = UiPalette.table_color(tint_key + "_lift", Color(1, 1, 1, 0))
	s.set_content_margin_all(margin)
	return s

## The paper's outline for `rect`: the deckled points, turned by tilt_deg.
func outline(rect: Rect2) -> PackedVector2Array:
	if rect.size.x < deckle_px * 8.0 or rect.size.y < deckle_px * 8.0:
		# too small to tear (a panel laid out at zero size): a plain rectangle
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()
	var step := maxf(deckle_step, 2.0)
	var a := rect.position
	var b := rect.end
	# the step and the depth both wander, so the edge never reads as a saw
	var x := a.x
	while x < b.x:
		pts.append(Vector2(x, a.y + rng.randf() * rng.randf() * deckle_px * 1.6)); x += step * rng.randf_range(0.5, 1.5)
	var y := a.y
	while y < b.y:
		pts.append(Vector2(b.x - rng.randf() * rng.randf() * deckle_px * 1.6, y)); y += step * rng.randf_range(0.5, 1.5)
	x = b.x
	while x > a.x:
		pts.append(Vector2(x, b.y - rng.randf() * rng.randf() * deckle_px * 1.6)); x -= step * rng.randf_range(0.5, 1.5)
	y = b.y
	while y > a.y:
		pts.append(Vector2(a.x + rng.randf() * rng.randf() * deckle_px * 1.6, y)); y -= step * rng.randf_range(0.5, 1.5)
	if Geometry2D.triangulate_polygon(pts).is_empty():
		# a deckle that crossed itself at a corner: the plain sheet instead
		pts = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	if absf(tilt_deg) > 0.001:
		var c := rect.get_center()
		var t := Transform2D(deg_to_rad(tilt_deg), Vector2.ZERO)
		for i in pts.size():
			pts[i] = c + t * (pts[i] - c)
	return pts

func _draw(ci: RID, rect: Rect2) -> void:
	if fit_height > 0.0 and fit_height < rect.size.y:
		rect = Rect2(rect.position, Vector2(rect.size.x, fit_height))
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var pts := outline(rect)
	if pts.size() < 3:
		return
	var c := rect.get_center()
	# the shadow: three layers, each grown by shadow_soft, their alphas summing to shadow_alpha at the core
	var shares := [0.5, 0.3, 0.2]
	for i in 3:
		var grow := shadow_soft * float(i)
		var sx := (rect.size.x + 2.0 * grow) / maxf(rect.size.x, 1.0)
		var sy := (rect.size.y + 2.0 * grow) / maxf(rect.size.y, 1.0)
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(c + shadow_offset + Vector2((p.x - c.x) * sx, (p.y - c.y) * sy))
		var col := Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_alpha * shares[i])
		RenderingServer.canvas_item_add_polygon(ci, sh, PackedColorArray([col]))
	# the paper, its texture stretched over the unturned rect
	var uvs := PackedVector2Array()
	var t_inv := Transform2D(-deg_to_rad(tilt_deg), Vector2.ZERO)
	for p in pts:
		var q := c + t_inv * (p - c)
		var u := (q.x - rect.position.x) / maxf(rect.size.x, 1.0)
		var v := (q.y - rect.position.y) / maxf(rect.size.y, 1.0)
		uvs.append(Vector2(lerpf(uv_inset.x, 1.0 - uv_inset.x, u), lerpf(uv_inset.y, 1.0 - uv_inset.y, v)))
	var cols := PackedColorArray([tint])
	if texture != null:
		RenderingServer.canvas_item_add_polygon(ci, pts, cols, uvs, texture.get_rid())
	else:
		RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	if lift.a > 0.0:
		RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([lift]))
	_draw_rules(ci, rect)
	if pin:
		_draw_pin(ci, Vector2(c.x, rect.position.y + pin_px * 0.9))

func _draw_rules(ci: RID, rect: Rect2) -> void:
	var inner := Rect2(rect.position + Vector2(content_margin_left, content_margin_top),
		rect.size - Vector2(content_margin_left + content_margin_right, content_margin_top + content_margin_bottom))
	for i in rules:
		var r := inner.grow(rule_out + float(i) * (rule_gap + rule_width))
		var w := rule_width if i == 0 else rule_width * 0.6
		var col := rule_color if i == 0 else Color(rule_color, rule_color.a * 0.6)
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, w)), col)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), col)
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(w, r.size.y)), col)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - w, r.position.y), Vector2(w, r.size.y)), col)

## A brass pin seen from above: its shadow, the dark rim, the body, a lit spot.
func _draw_pin(ci: RID, at: Vector2) -> void:
	var r := pin_px * 0.5
	BrassStyle.draw_brass(ci, at, r, brass, shadow_alpha)

static func _num(key: String, fallback: float) -> float:
	if Game != null and Game.data != null and Game.data.balance.has(key):
		return Game.data.bal(key)
	return fallback
