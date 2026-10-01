class_name WaxSeal
extends Button
## THE WAR TABLE's council seal (owner 2026-10-01): ENTER THE COUNCIL, the
## screen's one primary action, as a red wax seal pressed with the crown
## (ui_table_palette.csv wax_*), a paper tag under it naming the order. The
## whole of it is the button; hover warms the wax, a press sinks it. Its text
## stays the order (tests and tooltips read it) and is written on the tag.

const ART_PATH := "res://assets/2D/ui/war_table/council_seal.png"

var _tag: PanelContainer
var _word: Label
var _waiting_line: Label
## The ministers this month's report would have speak (ConversationBeats.waiting);
## once the council is entered for that report they have been heard.
var _waiting: Array[String] = []
var _art: Texture2D = null
## The tick whose council the player last entered: its ministers are heard.
static var heard_tick := -1

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
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_word)
	_waiting_line = Label.new()
	_waiting_line.name = "Waiting"
	_waiting_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var italic := UiPalette.role_font("body_italic")
	if italic != null:
		_waiting_line.add_theme_font_override("font", italic)
	_waiting_line.add_theme_font_size_override("font_size", 13)
	_waiting_line.add_theme_color_override("font_color", UiPalette.table_color("ink_muted", Color("5a4632")))
	words.add_child(_waiting_line)
	_tag.add_child(words)
	add_child(_tag)
	if ResourceLoader.exists(ART_PATH):
		_art = load(ART_PATH)
	resized.connect(_place_tag)
	pressed.connect(func() -> void:
		if Game != null and Game.state != null:
			heard_tick = Game.state.tick)
	_refit()

func _ready() -> void:
	if Game != null:
		Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
		Game.state_changed.connect(refresh)
	refresh()

## Who waits: this month's speakers, until the council is entered for them.
func refresh() -> void:
	_waiting = []
	if Game != null and Game.state != null and Game.current_report != null \
			and heard_tick != Game.state.tick:
		_waiting = ConversationBeats.waiting(Game.current_report, Game.state, Game.data)
	var n := _waiting.size()
	var count_words := ["none", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
	if n == 0:
		_waiting_line.text = "the council is quiet"
	elif n == 1:
		_waiting_line.text = "one waits to be heard"
	else:
		_waiting_line.text = "%s wait to be heard" % (count_words[n] if n < count_words.size() else str(n))
	var names: Array[String] = []
	for id in _waiting:
		names.append(Game.state.characters[id].display_name)
	tooltip_text = "Go before your council" + ("" if names.is_empty() else "\nWaiting: " + ", ".join(names))
	_refit()
	queue_redraw()

## Test seam.
func waiting_ids() -> Array[String]:
	return _waiting

func _minis() -> int:
	return mini(_waiting.size(), int(WarTable._num("ui_seal_minis", 3.0)))

func _refit() -> void:
	var seal := WarTable._num("ui_seal_px", 100.0)
	var tag_min := _tag.get_combined_minimum_size()
	var mini_px := WarTable._num("ui_seal_mini_px", 40.0)
	var minis := _minis()
	var row := (mini_px * minis + 6.0 * maxf(minis - 1, 0) + 10.0) if minis > 0 else 0.0
	custom_minimum_size = Vector2(maxf(seal + 8.0, tag_min.x), seal + tag_min.y - 6.0 + row)
	_place_tag()

func _place_tag() -> void:
	var tm := _tag.get_combined_minimum_size()
	_tag.size = tm
	_tag.position = Vector2((size.x - tm.x) * 0.5, WarTable._num("ui_seal_px", 100.0) - 6.0)

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
	_draw_minis()
	if _art != null:
		# the photographed seal (library U-60), its own shadow baked soft
		for i in 3:
			draw_circle(c + off, r * (0.98 + 0.06 * float(i)), Color(0, 0, 0, shadow_a * [0.4, 0.25, 0.12][i]))
		var tint := Color(1.08, 1.04, 1.04) if is_hovered() else Color.WHITE
		draw_texture_rect(_art, Rect2(c - Vector2(r, r), Vector2(seal, seal)), false, tint)
		return
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

## The waiting ministers as round miniatures in brass rings, a column under
## the tag (the approved mock's council miniatures).
func _draw_minis() -> void:
	var n := _minis()
	if n == 0:
		return
	var px := WarTable._num("ui_seal_mini_px", 40.0)
	var r := px * 0.5
	var y := _tag.position.y + _tag.size.y + 10.0 + r
	var brass := [UiPalette.table_color("brass_light", Color("f4db9a")),
		UiPalette.table_color("brass_mid", Color("b08a3e")),
		UiPalette.table_color("brass_dark", Color("6b4e1c"))]
	for i in n:
		var c := Vector2(size.x * 0.5, y + float(i) * (px + 6.0))
		BrassStyle.draw_brass(get_canvas_item(), c, r, brass, WarTable._num("ui_table_shadow_alpha", 0.34), false)
		var tex := CharacterPortrait.texture_for(_waiting[i])
		if tex == null:
			continue
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for k in 32:
			var a := TAU * float(k) / 32.0
			var u := Vector2(cos(a), sin(a))
			pts.append(c + u * (r - 3.0))
			uvs.append(Vector2(0.5, 0.42) + u * 0.46)
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tex)

## A wax pour's rim: a circle of `lobes` soft bulges turned by `phase`.
func _blob(c: Vector2, r: float, lobes: int, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		var k := 1.0 + 0.06 * sin(a * lobes + phase) + 0.03 * sin(a * (lobes + 4) + phase * 2.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts
