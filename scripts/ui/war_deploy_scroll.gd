class_name WarDeployScroll
extends Control
## The council's resolutions (owner 2026-10-02: 右下角新增一个deploy按钮（做成
## 机密卷轴密封的动画），点击后，代表本次war room会议决议将会以信使的形式发出去给各个
## 部队; spec 2026-10-02-war-room-v2 §3.3). A rolled scroll in the room's
## bottom-right corner, grey with nothing pencilled. Unrolled, it lists the
## drafts — regiment → where, days, gold, and why a line would be refused
## (Game.review_drafts) — with the total. Seal and send drips the wax,
## presses the crown's own arms into it, rolls the scroll and flies it off
## (EnvelopeFlight); then every draft runs ONCE as its real order
## (Game.deploy_drafts). Not yet rolls it away and keeps the drafts. It works
## on a running clock too: only planning a march needs the clock stopped.

signal sealed(result: Dictionary)
signal withdrawn

var _phase := ""   # "", "wax", "press", "roll", "fly"
var _t := 0.0
var _seal_tex: Texture2D   # the crown's own arms, pressed into the wax
var _wax_tex: Texture2D    # the photographed wax seal (library U-60), the wax itself


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := button()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var px := Game.data.bal("war_deploy_button_px")
	var margin := Game.data.bal("war_deploy_margin_px")
	b.offset_left = -px * 1.6 - margin
	b.offset_top = -px - margin
	b.offset_right = -margin
	b.offset_bottom = -margin
	b.draw.connect(_draw_rolled)
	b.pressed.connect(unroll)
	(%Dim as ColorRect).color = UiPalette.DIM_OVERLAY
	(%Dim as ColorRect).gui_input.connect(func(e: InputEvent) -> void:
		var m := e as InputEventMouseButton
		if m != null and m.pressed:
			withdraw())
	var review: PanelContainer = %Review
	review.custom_minimum_size.x = Game.data.bal("war_deploy_review_w_px")
	if UiPalette.war_table():
		var paper := PaperStyle.make("paper", Game.data.bal("war_deploy_margin_px") + 10.0, 7)
		paper.uv_inset = Vector2(0.12, 0.08)   # only the paper's middle: the art's ruled rim read as a frame (taste)
		review.add_theme_stylebox_override("panel", paper)
	else:
		review.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 24, "window"))
	UiPalette.style_title(%Title, 20, UiPalette.ink("rubric"))
	(%Total as Label).add_theme_color_override("font_color", UiPalette.ink("soft"))
	UiPalette.primary_button(%Seal, 16)   # one size for both: the primary is told by its plate, not its size
	UiPalette.command_button(%NotYet, 16)
	(%NotYet as Button).add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	(%Seal as Button).pressed.connect(seal)
	(%NotYet as Button).pressed.connect(withdraw)
	(%SealLayer as Control).draw.connect(_draw_seal)
	_seal_tex = HouseArms.texture_of_house(Game.data, Game.state, MapManors.crown(Game.state)) \
		if Game.state != null else null
	_wax_tex = UiPalette.load_art("res://assets/2D/ui/war_table/council_seal.png")
	refresh()


func button() -> Button:
	return %ScrollButton


func review_open() -> bool:
	return (%Review as Control).visible


func sealing() -> bool:
	return _phase != ""


func refresh() -> void:
	button().disabled = Game.state == null or not WarDrafts.any(Game.state) or sealing()
	button().tooltip_text = "Resolutions of the Council" if not button().disabled \
		else "Nothing is pencilled on the table"
	button().queue_redraw()


## Unroll the resolutions: a line a draft, a refused one in the bad ink with
## its reason, the total under them.
func unroll() -> void:
	if sealing() or Game.state == null or not WarDrafts.any(Game.state):
		return
	var r := Game.review_drafts()
	var lines: VBoxContainer = %Lines
	for c in lines.get_children():
		lines.remove_child(c)
		c.queue_free()
	for l: Dictionary in r["lines"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var lab := Label.new()   # who and where, wrapping
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fig := Label.new()   # days and gold, right-aligned, never wrapped
		fig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var days := int(l["days"])
		lab.text = "%s → %s" % [l["label"], l["to"]] if String(l["order"]) == WarDrafts.MARCH \
			else "%s halts where it stands" % l["label"]
		if String(l["refusal"]) != "":
			lab.text += "\n" + String(l["refusal"])   # no price: it cannot run
			lab.add_theme_color_override("font_color", UiPalette.ink("bad"))
		else:
			fig.text = ("%d day%s · " % [days, "" if days == 1 else "s"] if days > 0 else "") \
				+ "%s gold" % WarRoom.group(int(l["gold"]))
			lab.add_theme_color_override("font_color", UiPalette.ink("soft"))
		fig.add_theme_color_override("font_color", UiPalette.ink("soft"))
		row.add_child(lab)
		row.add_child(fig)
		lines.add_child(row)
	(%Total as Label).text = "In all · %s gold" % WarRoom.group(int(r["total"]))
	var review: Control = %Review
	review.scale = Vector2.ONE
	review.modulate.a = 1.0
	(%Dim as Control).visible = true
	review.visible = true


## Each line's words (its order, or its refusal), in code order.
func line_labels() -> Array:
	return (%Lines as Node).get_children().map(func(row: Node) -> Node: return row.get_child(0))


func total_text() -> String:
	return (%Total as Label).text


## Not yet: roll it away, the drafts kept.
func withdraw() -> void:
	if sealing() or not review_open():
		return
	_put_away()
	withdrawn.emit()


## Seal and send: the wax, the press, the roll, the flight, then the orders —
## once, however often it is pressed.
func seal() -> void:
	if sealing() or not review_open():
		return
	_phase = "wax"
	_t = 0.0
	(%Seal as Button).disabled = true
	(%NotYet as Button).disabled = true
	refresh()


func _process(delta: float) -> void:
	if _phase == "" or _phase == "fly":
		return
	_t += delta
	var need := Game.data.bal("war_deploy_%s_s" % _phase)
	var k := clampf(_t / maxf(need, 0.001), 0.0, 1.0)
	var review: Control = %Review
	if _phase == "roll":
		review.pivot_offset = review.size * 0.5
		review.scale = Vector2(1.0, lerpf(1.0, Game.data.bal("war_deploy_rolled_share"), k))
	(%SealLayer as Control).queue_redraw()
	if k < 1.0:
		return
	_t = 0.0
	match _phase:
		"wax":
			_phase = "press"
		"press":
			_phase = "roll"
		"roll":
			_phase = "fly"
			_fly()


func _fly() -> void:
	var review: Control = %Review
	var from := Rect2(review.global_position + review.size * Vector2(0.0, 0.5) * (1.0 - review.scale.y),
		review.size * review.scale)
	var to := Rect2(Vector2(get_global_rect().end.x + 80.0, from.position.y), from.size * 0.2)
	_put_away()
	var f := EnvelopeFlight.fly(self, from, to, true, Game.data)
	f.landed.connect(_send)


func _send() -> void:
	var result := Game.deploy_drafts()
	_phase = ""
	(%Seal as Button).disabled = false
	(%NotYet as Button).disabled = false
	refresh()
	var n := (result["sent"] as Array).size()
	var held := (result["refused"] as Dictionary).size()
	var news := "The council's resolutions are sealed: %d courier%s ride%s." % [n, "" if n == 1 else "s", "s" if n == 1 else ""]
	if held > 0:
		news += " %d order%s could not be sent and stay%s pencilled." % [held, "" if held == 1 else "s", "s" if held == 1 else ""]
	Game.publish_news(news)
	sealed.emit(result)


func _put_away() -> void:
	(%Review as Control).visible = false
	(%Dim as Control).visible = false
	(%Review as Control).scale = Vector2.ONE


## The rolled scroll on the button: vellum between two rollers, tied with a
## red ribbon under a wax seal, with a soft shadow down-right; greyed OPAQUE
## (desaturated, darkened) when nothing is pencilled — never by alpha.
func _draw_rolled() -> void:
	var b := button()
	var r := Rect2(Vector2.ZERO, b.size)
	var idle := b.disabled
	var lift := 0.06 if b.is_hovered() and not idle else 0.0
	var roller := r.size.y * 0.24
	var body := Rect2(r.position + Vector2(roller * 0.6, r.size.y * 0.2),
		Vector2(r.size.x - roller * 1.2, r.size.y * 0.58))
	var sh := Game.data.bal("war_deploy_shadow_px")
	for i: int in 3:   # a soft shadow down-right, the war table's one light
		var o := sh * float(i + 1)
		b.draw_rect(Rect2(body.position + Vector2(o, o) * 0.6, body.size + Vector2(roller * 0.4, 0)),
			Color(0, 0, 0, [0.18, 0.10, 0.05][i]))
	var edge := WarReportRoll.ROLLER_WOOD.darkened(0.45)
	b.draw_rect(body, UiPalette.table_color("paper", Color("e9dcc0")).lightened(lift))
	b.draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.72), Vector2(body.size.x, body.size.y * 0.28)),
		Color(0.40, 0.31, 0.18, 0.30))
	b.draw_rect(body, edge, false, 1.0, true)
	for x: float in [body.position.x - roller * 0.5, body.end.x - roller * 0.5]:
		var c := Rect2(Vector2(x, r.position.y + r.size.y * 0.12), Vector2(roller, r.size.y * 0.74))
		var shades: Array[Color] = [WarReportRoll.ROLLER_WOOD.lightened(0.22), WarReportRoll.ROLLER_WOOD,
			WarReportRoll.ROLLER_WOOD.darkened(0.3)]
		for j: int in 3:   # three bands, lit to dark across: a round roller
			b.draw_rect(Rect2(c.position + Vector2(c.size.x * j / 3.0, 0), Vector2(c.size.x / 3.0 + 0.5, c.size.y)),
				shades[j].lightened(lift))
		b.draw_rect(Rect2(c.position, Vector2(c.size.x, c.size.y * 0.14)), WarReportRoll.ROLLER_CAP)
		b.draw_rect(Rect2(c.position + Vector2(0, c.size.y * 0.86), Vector2(c.size.x, c.size.y * 0.14)), WarReportRoll.ROLLER_CAP)
		b.draw_rect(c, edge, false, 1.0, true)
	# Nothing pencilled: only the ribbon and the seal grey (taste: never wash
	# the whole object, never grey it by alpha).
	var grey := func(c: Color) -> Color:
		return Color.from_hsv(c.h, c.s * Game.data.bal("war_deploy_idle_sat"),
			c.v * Game.data.bal("war_deploy_idle_value"), c.a) if idle else c
	var mid := body.get_center()
	b.draw_rect(Rect2(Vector2(mid.x - 3.0, body.position.y), Vector2(6.0, body.size.y)),
		grey.call(UiPalette.table_color("wax_mid", Color("7a1c17"))))
	var seal_r := body.size.y * 0.42
	if _wax_tex != null:
		b.draw_texture_rect(_wax_tex, Rect2(mid - Vector2(seal_r, seal_r), Vector2(seal_r, seal_r) * 2.0), false,
			grey.call(Color.WHITE) if not idle else Color(0.62, 0.6, 0.6))
	else:
		b.draw_circle(mid, seal_r, grey.call(UiPalette.table_color("wax_light", Color("a63a2f"))), true, -1.0, true)


## The seal being made, over the unrolled resolutions: the wax spreads, then
## the crown's arms are pressed into it.
func _draw_seal() -> void:
	if _phase == "" or _phase == "fly":
		return
	var layer: Control = %SealLayer
	var need := Game.data.bal("war_deploy_%s_s" % _phase)
	var k := clampf(_t / maxf(need, 0.001), 0.0, 1.0) if _phase != "roll" else 1.0
	var at := Vector2(layer.size.x * 0.5, layer.size.y - Game.data.bal("war_deploy_wax_y_px"))
	var r := Game.data.bal("war_deploy_wax_px") * (k if _phase == "wax" else 1.0)
	var box := Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0)
	if _wax_tex != null:   # the photographed wax (U-60), its own edge and shadow
		layer.draw_texture_rect(_wax_tex, box, false)
	else:
		layer.draw_circle(at, r, UiPalette.table_color("wax_mid", Color("7a1c17")), true, -1.0, true)
	if _phase == "wax" or _seal_tex == null:
		return
	# The crown's arms pressed INTO the wax: the wax red multiplied darker
	# where the arms are, growing in as the matrix comes down.
	var press := k if _phase == "press" else 1.0
	var s := Game.data.bal("war_deploy_wax_px") * 1.05 * lerpf(1.3, 1.0, press)
	var ink := Game.data.bal("war_deploy_arms_ink")
	var tint := Color(0.42, 0.10, 0.08, press * ink)
	layer.draw_texture_rect(_seal_tex, Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
