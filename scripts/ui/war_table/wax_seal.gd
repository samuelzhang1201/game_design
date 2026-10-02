@tool
class_name WaxSeal
extends Button
## THE WAR TABLE's council seal (owner 2026-10-01): ENTER THE COUNCIL, the
## screen's one primary action, as a red wax seal pressed with the crown
## (its wax_* exports), a paper tag under it naming the order. The
## whole of it is the button; hover warms the wax, a press sinks it. Its text
## stays the order (tests and tooltips read it) and is written on the tag.

## Its look is scenes/war_table/council_seal.tscn (owner 2026-10-02: the look
## lives in the editor): the tag's paper and words are the scene's nodes, and
## the seal's own drawing reads the exports below.

## The seal's size, design px (owner 2026-10-02: 右上方的印记太大了).
@export var seal_px := 64.0:
	set(v):
		seal_px = v
		_refit_if_ready()
## The photographed seal (library U-60); without it the wax is drawn.
@export var art: Texture2D:
	set(v):
		art = v
		queue_redraw()
## The drawn wax: its lit side, body and shadowed rim.
@export var wax_light := Color("a63a2f")
@export var wax_mid := Color("7a1c17")
@export var wax_dark := Color("5a1410")
## The miniatures' brass rings: lit side, body, rim.
@export var brass: Array[Color] = [Color("f4db9a"), Color("b08a3e"), Color("6b4e1c")]
## At most this many waiting ministers stand under the tag, each this many
## design px across.
@export var minis_max := 3
@export var mini_px := 30.0
## Its shadow on the table (the light is upper left).
@export var shadow_alpha := 0.34
@export var shadow_offset := Vector2(3, 5)

@onready var _tag: PanelContainer = $Tag
@onready var _word: Label = $Tag/Words/Order
@onready var _waiting_line: Label = $Tag/Words/Waiting
## The ministers this month's report would have speak (ConversationBeats.waiting);
## once the council is entered for that report they have been heard.
var _waiting: Array[String] = []
## The tick whose council the player last entered: its ministers are heard.
static var heard_tick := -1

func _ready() -> void:
	resized.connect(_place_tag)
	pressed.connect(func() -> void:
		if not Engine.is_editor_hint() and Game != null and Game.state != null:
			heard_tick = Game.state.tick)
	if not Engine.is_editor_hint() and Game != null:
		Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
		Game.state_changed.connect(refresh)
	refresh()

func _refit_if_ready() -> void:
	if is_node_ready():
		_refit()

## Who waits: this month's speakers, until the council is entered for them.
func refresh() -> void:
	_waiting = []
	if not Engine.is_editor_hint() and Game != null and Game.state != null and Game.current_report != null \
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
	return mini(_waiting.size(), minis_max)

func _refit() -> void:
	var seal := seal_px
	var tag_min := _tag.get_combined_minimum_size()
	var minis := _minis()
	var row := (mini_px * minis + 6.0 * maxf(minis - 1, 0) + 10.0) if minis > 0 else 0.0
	custom_minimum_size = Vector2(maxf(seal + 8.0, tag_min.x), seal + tag_min.y - 4.0 + row)
	_place_tag()

func _place_tag() -> void:
	var tm := _tag.get_combined_minimum_size()
	_tag.size = tm
	# right-aligned: the seal and its tag tucked into the map's corner (owner
	# 2026-10-02: 再往右上方角落移动点)
	_tag.position = Vector2(size.x - tm.x, seal_px - 4.0)

func _draw() -> void:
	if _tag == null:
		return
	var seal := seal_px
	var r := seal * 0.5
	var sunk := 1.5 if button_pressed or is_pressed() else 0.0
	var c := Vector2(size.x - r - 4.0, r + sunk)   # the seal in the corner, over its tag's right end
	var light := wax_light
	var mid := wax_mid
	var dark := wax_dark
	if is_hovered():
		light = light.lightened(0.08)
		mid = mid.lightened(0.06)
	var shadow_a := shadow_alpha
	var off := shadow_offset
	_draw_minis()
	if art != null:
		# the photographed seal (library U-60), its own shadow baked soft
		for i in 3:
			draw_circle(c + off, r * (0.98 + 0.06 * float(i)), Color(0, 0, 0, shadow_a * [0.4, 0.25, 0.12][i]))
		var tint := Color(1.08, 1.04, 1.04) if is_hovered() else Color.WHITE
		draw_texture_rect(art, Rect2(c - Vector2(r, r), Vector2(seal, seal)), false, tint)
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
	var px := mini_px
	var r := px * 0.5
	var y := _tag.position.y + _tag.size.y + 10.0 + r
	for i in n:
		var c := Vector2(_tag.position.x + _tag.size.x * 0.5, y + float(i) * (px + 6.0))
		BrassStyle.draw_brass(get_canvas_item(), c, r, brass, shadow_alpha, false)
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
