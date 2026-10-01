class_name TableLanding
extends Control
## THE MAP LAID ON THE TABLE (owner 2026-10-01: "游戏场景好像一张地图被拿起来一般，
## 放倒了木桌上"): the bridge from the living title into the game. The title's
## last frame — the whole screen of map — is lifted like a sheet (it draws
## back a little, the vellum's margin and a shadow appear), carried down onto
## the table and laid where the map sheet lies, turning square as it comes,
## settling with the smallest give, then crossfades into the real sheet; as it
## lands the table's other pieces come to it one by one — the tally board and
## dial from above, the report from the left, the bookmarks and the slip from
## below, the seal, the compass — and the window that speaks comes last. Every
## timing is balance.csv ui_landing_*. Presentation only; it holds the input
## while it plays and frees itself.

var frame: Texture2D
var screen: Control
var extra: Array[Control] = []   # pieces outside the screen: the bookmarks, the news slip
var _target := Rect2()
var _t := 0.0
var _pieces: Array = []   # {node, from (offset), at (s), pos (rest position)}
var _map_panel: Control
var _sheet: PaperStyle
var _done := false
var _rule_a := 1.0
var _margin := 0.0   # the sheet's own margin (the drawn one grows to it)
var _live: Texture2D   # the map itself, rendering under the flying sheet

## Play the landing over `root` onto `screen` (the conversation or the court)
## from `frame` (the title's last image). Returns the node, or null.
static func play(root: Control, p_screen: Control, p_frame: Texture2D,
		p_extra: Array[Control] = []) -> TableLanding:
	if p_frame == null or p_screen == null or not UiPalette.war_table():
		return null
	var l := TableLanding.new()
	l.name = "TableLanding"
	l.frame = p_frame
	l.screen = p_screen
	l.extra = p_extra
	root.add_child(l)
	return l

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # the table is being laid
	_sheet = WarTable.sheet_style()
	_sheet.shadow_alpha = 0.0  # the flying sheet casts its own, by its height
	_rule_a = _sheet.rule_color.a
	_margin = _sheet.content_margin_left
	_hide_pieces()
	set_process(false)
	# the screen lays itself out over the next frames: read the sheet's place then
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(screen):
		queue_free()
		return
	_map_panel = _map_of_screen()
	var view: Map3DView = screen.map3d_view() if screen.has_method("map3d_view") else null
	if view != null and view.context() != null:
		_live = (view.get_node("Viewport") as SubViewport).get_texture()
	_target = _map_panel.get_global_rect() if _map_panel != null else Rect2(Vector2.ZERO, size)
	_rest_pieces()
	set_process(true)

func _num(key: String, fallback: float) -> float:
	return WarTable._num(key, fallback)

## Everything on the table but the table itself starts unseen, and each piece
## comes from the side it lies on — the board from above, the report from the
## left, the bookmarks from below, the seal from the right — in that order;
## the window that speaks comes last. The map sheet waits under the flying one
## for the crossfade.
func _hide_pieces() -> void:
	var slide := _num("ui_landing_ui_slide_px", 48.0)
	var view := get_viewport_rect().size
	var nodes: Array[Control] = []
	for c in screen.get_children():
		var n := c as Control
		if n == null or not n.visible or n == _map_of_screen() or n is WarTableBackdrop \
				or n.name == "Bg":
			continue
		nodes.append(n)
	for n in extra:
		if n != null and n.visible:
			nodes.append(n)
	var order := {"top": 0, "left": 1, "bottom": 2, "right": 3}
	var found: Array = []
	for n in nodes:
		var side := _side_of(n.get_global_rect(), view)
		found.append({"node": n, "side": side})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(order[a["side"]]) < int(order[b["side"]]))
	var at := _num("ui_landing_ui_start_s", 0.8)
	var step := _num("ui_landing_ui_stagger_s", 0.09)
	var from := {"top": Vector2(0, -slide), "left": Vector2(-slide, 0),
		"bottom": Vector2(0, slide), "right": Vector2(slide, 0)}
	var i := 0
	for f: Dictionary in found:
		var n := f["node"] as Control
		var when := at + step * float(i)
		var off: Vector2 = from[f["side"]]
		if n.name == "AudienceLayer":
			when = _total() + _num("ui_landing_voice_after_s", 0.3)  # the voice last, the sheet seen down
			off = Vector2(0, slide * 0.4)
		else:
			i += 1
		_pieces.append({"node": n, "from": off, "at": when})
		n.modulate.a = 0.0
	var m := _map_of_screen()
	if m != null:
		m.modulate.a = 0.0

## The side a piece lies on: the nearest edge of the screen to its middle,
## a full-width band by its height.
static func _side_of(r: Rect2, view: Vector2) -> String:
	if r.size.x >= view.x * 0.6:
		return "top" if r.get_center().y < view.y * 0.5 else "bottom"
	var c := r.get_center()
	var d := {"left": c.x, "right": view.x - c.x, "top": c.y, "bottom": view.y - c.y}
	var best := "left"
	for k: String in d:
		if float(d[k]) < float(d[best]):
			best = k
	return best

func _map_of_screen() -> Control:
	return screen.map_panel() as Control if screen.has_method("map_panel") else null

func _rest_pieces() -> void:
	for p: Dictionary in _pieces:
		p["pos"] = (p["node"] as Control).position

func _total() -> float:
	return _num("ui_landing_lift_s", 0.35) + _num("ui_landing_carry_s", 0.85) \
		+ _num("ui_landing_settle_s", 0.25) + _num("ui_landing_cross_s", 0.3)

func _process(delta: float) -> void:
	_t += minf(delta, 0.05)  # a hitch slows the sheet, never skips it
	for p: Dictionary in _pieces:
		var n := p["node"] as Control
		if not is_instance_valid(n):
			continue
		var k := clampf((_t - float(p["at"])) / maxf(_num("ui_landing_ui_s", 0.45), 0.01), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)  # ease out
		n.modulate.a = e
		n.position = Vector2(p["pos"]) + Vector2(p["from"]) * (1.0 - e)
	var cross_at := _total() - _num("ui_landing_cross_s", 0.3)
	if _map_panel != null and is_instance_valid(_map_panel):
		# the real sheet is whole under the laid one, which then fades off it
		# (two half-faded sheets let the table through)
		_map_panel.modulate.a = 1.0 if _t >= cross_at else 0.0
	queue_redraw()
	if _t >= finished_at() and not _done:
		_finish()

func _finish() -> void:
	_done = true
	for p: Dictionary in _pieces:
		var n := p["node"] as Control
		if is_instance_valid(n):
			n.modulate.a = 1.0
			n.position = p["pos"]
	if _map_panel != null and is_instance_valid(_map_panel):
		_map_panel.modulate.a = 1.0
	queue_free()

## The sheet's place, tilt, lift (0 on the table .. 1 held up) and margin at `t`.
func pose(t: float) -> Dictionary:
	var lift_s := _num("ui_landing_lift_s", 0.35)
	var carry_s := _num("ui_landing_carry_s", 0.85)
	var settle_s := _num("ui_landing_settle_s", 0.25)
	var full := Rect2(Vector2.ZERO, size)
	var held := _scaled(full, _num("ui_landing_lift_scale", 0.92))
	var tilt := deg_to_rad(_num("ui_landing_tilt_deg", -2.5))
	if t < lift_s:
		var k := _smooth(t / lift_s)
		return {"rect": _lerp_rect(full, held, k), "tilt": tilt * k, "lift": k, "margin": k}
	t -= lift_s
	if t < carry_s:
		var k := _smooth(t / carry_s)
		return {"rect": _lerp_rect(held, _target, k), "tilt": tilt * (1.0 - k), "lift": 1.0 - k, "margin": 1.0}
	t -= carry_s
	var k := clampf(t / maxf(settle_s, 0.01), 0.0, 1.0)
	# the moment it meets the wood: a touch past its place, then home
	var give := sin(k * PI) * _num("ui_landing_give", 0.012)
	return {"rect": _scaled(_target, 1.0 + give), "tilt": 0.0, "lift": 0.0, "margin": 1.0}

func _draw() -> void:
	if frame == null:
		return
	if _target.size.x <= 0.0:  # the screen still laying itself out: the title as it was
		_print_map(frame, Rect2(Vector2.ZERO, size), 1.0)
		return
	var p := pose(_t)
	var r: Rect2 = p["rect"]
	var cross_at := _total() - _num("ui_landing_cross_s", 0.3)
	var alpha := 1.0 - clampf((_t - cross_at) / maxf(_num("ui_landing_cross_s", 0.3), 0.01), 0.0, 1.0)
	if alpha <= 0.0:
		return
	var lift: float = p["lift"]
	var c := r.get_center()
	draw_set_transform(c, p["tilt"], Vector2.ONE)
	var local := Rect2(-r.size * 0.5, r.size)
	var fading := alpha < 1.0  # down on the real sheet: only the print fades off it
	# the shadow: farther, wider and fainter while it is held up, close and
	# dark once down — many faint layers, never one hard band
	var off := Vector2(WarTable._num("ui_table_shadow_dx", 6.0), WarTable._num("ui_table_shadow_dy", 10.0)) * (0.5 + 2.5 * lift)
	var soft := 5.0 + 30.0 * lift
	var layers := 0 if fading else 8
	var core := alpha * (0.34 - 0.14 * lift) / 4.0
	for i in layers:
		var g := soft * (float(i) / 7.0 - 0.35)
		draw_rect(Rect2(local.position + off - Vector2(g, g), local.size + Vector2(2.0 * g, 2.0 * g)),
			Color(0, 0, 0, core * (1.0 - float(i) / 8.0)))
	# the vellum sheet, its margin growing as it is lifted off the screen
	var m := _margin * float(p["margin"])
	if float(p["margin"]) > 0.01 and not fading:
		# our own sheet, changed in place (duplicate() drops a script's plain vars)
		_sheet.tint.a = alpha
		_sheet.rule_color.a = _rule_a * alpha
		_sheet.set_content_margin_all(m)
		draw_style_box(_sheet, local)
	# the map printed on it: the title's last frame, then the map itself
	# (live, as it is carried down), cut to the sheet's shape
	var inner := local.grow(-m)
	var lift_s := _num("ui_landing_lift_s", 0.35)
	var live_k := 0.0
	if _live != null:
		live_k = _smooth((_t - lift_s) / maxf(_num("ui_landing_carry_s", 0.85) * 0.4, 0.01))
	if live_k < 1.0:
		_print_map(frame, inner, alpha)
	if live_k > 0.0:
		_print_map(_live, inner, alpha * live_k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## `tex` cover-fitted into `inner` (cut to its shape, centred).
func _print_map(tex: Texture2D, inner: Rect2, alpha: float) -> void:
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var want := inner.size.x / maxf(inner.size.y, 1.0)
	var src := Rect2(Vector2.ZERO, ts)
	if ts.x / ts.y > want:
		src = Rect2(Vector2((ts.x - ts.y * want) * 0.5, 0), Vector2(ts.y * want, ts.y))
	else:
		src = Rect2(Vector2(0, (ts.y - ts.x / want) * 0.5), Vector2(ts.x, ts.x / want))
	draw_texture_rect_region(tex, inner, src, Color(1, 1, 1, alpha))

static func _smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

static func _scaled(r: Rect2, s: float) -> Rect2:
	var c := r.get_center()
	return Rect2(c - r.size * s * 0.5, r.size * s)

static func _lerp_rect(a: Rect2, b: Rect2, k: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, k), a.size.lerp(b.size, k))

## Test seam.
func finished_at() -> float:
	return _total() + _num("ui_landing_voice_after_s", 0.3) + _num("ui_landing_ui_s", 0.45)
