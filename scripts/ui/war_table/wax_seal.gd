@tool
class_name WaxSeal
extends Button
## THE WAR TABLE's council seal (owner 2026-10-01): ENTER THE COUNCIL, the
## screen's one primary action, as a red wax seal pressed with the crown
## (its wax_* exports). The whole of it is the button; hover warms the wax, a
## press sinks it. Its text stays the order (tests read it) but is no longer
## written on a tag under it: the order is the seal's tooltip (owner
## 2026-10-02: 移除蜡封下面的 enter the council的字，改为tooltip).
##
## Under it stands THE COUNCIL (owner 2026-10-02, plan A: 蜡封下常驻显示全体议员
## 的小头像): every sitting councillor's miniature in a brass ring, in seat
## order, those this month's report would have speak (ConversationBeats.waiting)
## marked until they have been heard. They stand in a row leftward along the
## map's top edge, level with the seal (owner 2026-10-02: 选A2 横列布局). Each
## miniature names its councillor in its own tooltip, and a click on one asks
## for an audience with that councillor (councillor_chosen); a click on the
## seal itself enters the council (council_requested).

## Its look is scenes/war_table/council_seal.tscn (owner 2026-10-02: the look
## lives in the editor); the seal's own drawing reads the exports below.

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
## Each miniature, design px across, and the gap between them.
@export var mini_px := 28.0:
	set(v):
		mini_px = v
		_refit_if_ready()
@export var mini_gap_px := 5.0
## How a waiting councillor is marked: the ring lit in this gold, and a drop
## of the seal's own oxblood wax pressed on the ring at five o'clock.
@export var waiting_ring := Color("e9c461")
@export var waiting_ring_px := 2.0
@export var drop_px := 10.0
@export var drop_wax := Color("6e1a24")
@export var drop_light := Color("b0503f")
## While anyone waits, the others are drawn this much toward the table's
## shade, so the waiting stand out by light, not only by their ring.
@export_range(0.0, 1.0) var quiet_dim := 0.3
## The cream bubble that rises under the first councillor with a matter
## (owner 2026-10-02: 头像下方缓缓弹出一个奶白色的对话框说有事禀报): how long
## after they are marked it starts, how long it takes to rise, its gap under
## the miniature, and its slow float once up.
@export var bubble_delay_s := 0.6
@export var bubble_in_s := 1.1
@export var bubble_gap_px := 3.0
@export var bubble_float_px := 1.5
@export var bubble_float_s := 2.8
## Its shadow on the table (the light is upper left).
@export var shadow_alpha := 0.34
@export var shadow_offset := Vector2(3, 5)

## A click on the seal: enter the council (every waiting minister heard).
signal council_requested
## A click on a councillor's miniature: an audience with them.
signal councillor_chosen(id: String)

## The council in seat order (character ids) and who among them waits.
var _council: Array[String] = []
var _waiting: Array[String] = []
## The tick whose ministers have been heard, and which of them: the whole
## council when it is entered through the seal (heard_all), one by one in an
## audience or a council the game opens by itself.
static var heard_tick := -1
static var heard_ids: Array[String] = []
static var heard_all := false

## `ids` heard this tick (an audience, a council that opened itself); with
## `all`, every minister of the tick's report.
static func hear(tick: int, ids: Array, all := false) -> void:
	if heard_tick != tick:
		heard_tick = tick
		heard_ids = []
		heard_all = false
	heard_all = heard_all or all
	for id in ids:
		if not String(id) in heard_ids:
			heard_ids.append(String(id))

@onready var _bubble: SpeechBubble = get_node_or_null("Bubble")
## Whom the bubble speaks for ("" while it is down), and its tweens.
var _bubble_for := ""
var _bubble_tween: Tween
var _float_tween: Tween

func _ready() -> void:
	pressed.connect(_on_pressed)
	if _bubble != null:
		_bubble.visible = false
		# the seal grows leftward to fit its row after a refresh: the bubble
		# follows its councillor's miniature, which moves with the seal's width
		resized.connect(func() -> void:
			if _bubble.visible:
				_place_bubble())
		_bubble.pressed.connect(func() -> void:
			if _bubble_for != "":
				councillor_chosen.emit(_bubble_for))
	if not Engine.is_editor_hint() and Game != null:
		Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
		Game.state_changed.connect(refresh)
	refresh()

func _refit_if_ready() -> void:
	if is_node_ready():
		_refit()

## Who sits and who waits: this month's speakers, until the council is
## entered for them.
func refresh() -> void:
	_council = []
	_waiting = []
	if not Engine.is_editor_hint() and Game != null and Game.state != null:
		for seat: String in Game.state.council:
			var id := String(Game.state.council[seat])
			if id != "" and Game.state.characters.has(id) and not id in _council:
				_council.append(id)
		# an event waiting to be heard is its presenter's matter until answered
		if not Game.state.pending_event.is_empty():
			var p := ConversationBeats.event_presenter(Game.state, Game.data)
			if p != "":
				_waiting.append(p)
		var now := heard_tick == Game.state.tick
		if Game.current_report != null and not (now and heard_all):
			for id in ConversationBeats.waiting(Game.current_report, Game.state, Game.data):
				if not (now and id in heard_ids) and not id in _waiting:
					_waiting.append(id)
	var names: Array[String] = []
	for id in _waiting:
		names.append(Game.state.characters[id].display_name)
	tooltip_text = "Enter the Council" + ("" if names.is_empty() else "\nWaiting to be heard: " + ", ".join(names))
	_refit()
	_show_bubble(_waiting[0] if not _waiting.is_empty() else "")
	queue_redraw()

## Who the bubble speaks for now ("" none): a test seam.
func bubble_for() -> String:
	return _bubble_for

## The bubble rises under `id`'s miniature, slowly — once per councillor: a
## refresh that keeps the same speaker leaves it where it is. "" takes it down.
func _show_bubble(id: String, again := false) -> void:
	if _bubble == null or (id == _bubble_for and not again):
		return
	_bubble_for = id
	for t in [_bubble_tween, _float_tween]:
		if t != null:
			t.kill()
	if id == "":
		_bubble.visible = false
		return
	_place_bubble()
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	_bubble.scale = Vector2(0.35, 0.35)
	if not is_inside_tree():
		_bubble.modulate.a = 1.0
		_bubble.scale = Vector2.ONE
		return
	_bubble_tween = create_tween()
	_bubble_tween.tween_interval(bubble_delay_s)
	_bubble_tween.set_parallel(true)
	_bubble_tween.tween_property(_bubble, "modulate:a", 1.0, bubble_in_s * 0.6)
	_bubble_tween.tween_property(_bubble, "scale", Vector2.ONE, bubble_in_s) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.chain().tween_callback(_float_bubble)

## Once up, the bubble floats a hair up and down, slowly, so the eye finds it.
func _float_bubble() -> void:
	if _bubble == null or bubble_float_px <= 0.0:
		return
	var y := _bubble.position.y
	_float_tween = create_tween().set_loops()
	_float_tween.tween_property(_bubble, "position:y", y + bubble_float_px, bubble_float_s * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_float_tween.tween_property(_bubble, "position:y", y, bubble_float_s * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Under the miniature it speaks for, its tail at the miniature's middle, its
## right edge kept within the seal's own.
func _place_bubble() -> void:
	var i := _council.find(_bubble_for)
	if i < 0:
		return
	var c := mini_centres()[i]
	var w := _bubble.size.x
	var x := minf(c.x - w * 0.5, size.x - w)
	var y := c.y + mini_px * 0.5 + bubble_gap_px
	if _float_tween != null and _float_tween.is_valid():
		_float_tween.kill()
		_float_tween = null
		_bubble.position = Vector2(x, y)
		_float_bubble()
	_bubble.position = Vector2(x, y)
	_bubble.tail_x = c.x - x
	_bubble.pivot_offset = Vector2(_bubble.tail_x, 0.0)

## Play was pressed with a matter unheard: the bubble rises again.
func nudge() -> void:
	if not _waiting.is_empty():
		_show_bubble(_waiting[0], true)

## Where the last press landed (the button's own pressed carries no position).
var _press_at := Vector2(-1, -1)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_press_at = mb.position

func _on_pressed() -> void:
	var id := councillor_at(_press_at)
	_press_at = Vector2(-1, -1)
	if id != "":
		councillor_chosen.emit(id)
		return
	if not Engine.is_editor_hint() and Game != null and Game.state != null:
		hear(Game.state.tick, [], true)
	council_requested.emit()

## Test seams.
func waiting_ids() -> Array[String]:
	return _waiting

func council_ids() -> Array[String]:
	return _council

func _refit() -> void:
	var n := _council.size()
	custom_minimum_size = Vector2(seal_px + 8.0 + float(n) * (mini_px + mini_gap_px), seal_px + 8.0)
	queue_redraw()

func _seal_centre() -> Vector2:
	var r := seal_px * 0.5
	return Vector2(size.x - r - 4.0, r)

## Where each miniature stands (its centre), in seat order.
func mini_centres() -> PackedVector2Array:
	var out := PackedVector2Array()
	var c := _seal_centre()
	var r := mini_px * 0.5
	for i in _council.size():
		out.append(Vector2(c.x - seal_px * 0.5 - mini_gap_px - r - float(i) * (mini_px + mini_gap_px), c.y))
	return out

## The councillor whose miniature is under `at`, or "".
func councillor_at(at: Vector2) -> String:
	var cs := mini_centres()
	for i in cs.size():
		if at.distance_to(cs[i]) <= mini_px * 0.5 + 2.0:
			return _council[i]
	return ""

func _get_tooltip(at_position: Vector2) -> String:
	var id := councillor_at(at_position)
	if id == "" or Game == null or Game.state == null:
		return tooltip_text
	var c: Character = Game.state.characters[id]
	var seat := String(Game.data.seats.get(c.seat, {}).get("label", c.seat.capitalize()))
	var line := "%s — %s\nOpinion %s" % [c.display_name, seat, UiPalette.format_delta(c.opinion)]
	if id in _waiting:
		line += "\nHas a matter to put before you"
	return line

func _draw() -> void:
	var seal := seal_px
	var r := seal * 0.5
	var sunk := 1.5 if button_pressed or is_pressed() else 0.0
	var c := _seal_centre() + Vector2(0, sunk)   # the seal in the map's corner
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

## The council as round miniatures in brass rims (the approved mock's council
## miniatures), lit from the upper left like every piece on the table; the
## waiting ones ringed in gold with a drop of the seal's wax on the ring.
func _draw_minis() -> void:
	var cs := mini_centres()
	var r := mini_px * 0.5
	var anyone := not _waiting.is_empty()
	for i in cs.size():
		var c := cs[i]
		var id := _council[i]
		var waits := id in _waiting
		BrassStyle.draw_brass(get_canvas_item(), c, r, brass, shadow_alpha, false)
		var tex := CharacterPortrait.texture_for(id)
		if tex != null:
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for k in 40:
				var a := TAU * float(k) / 40.0
				var u := Vector2(cos(a), sin(a))
				pts.append(c + u * (r - 2.5))
				uvs.append(Vector2(0.5, 0.40) + u * 0.40)
			var tint := Color.WHITE
			if anyone and not waits:
				tint = Color(1, 1, 1).lerp(Color(0.5, 0.46, 0.42), quiet_dim)
			draw_polygon(pts, PackedColorArray([tint]), uvs, tex)
		# the rim's bevel: a dark line inside it, its upper left catching the light
		draw_arc(c, r - 2.5, 0.0, TAU, 48, Color(brass[2], 0.9), 1.0, true)
		draw_arc(c, r - 0.6, PI * 1.05, PI * 1.6, 16, Color(brass[0], 0.85), 1.2, true)
		if waits:
			draw_arc(c, r - 1.2, 0.0, TAU, 48, waiting_ring, waiting_ring_px, true)
			var d := c + Vector2(cos(PI * 0.3), sin(PI * 0.3)) * (r - 1.0)
			var dr := drop_px * 0.5
			draw_colored_polygon(_blob(d + Vector2(1.2, 1.8), dr * 1.05, 6, 0.7), Color(0, 0, 0, shadow_alpha))
			draw_colored_polygon(_blob(d, dr, 6, 0.7), drop_wax)
			draw_colored_polygon(_blob(d - Vector2(dr, dr) * 0.22, dr * 0.55, 5, 1.3), drop_wax.lerp(drop_light, 0.45))
			draw_circle(d - Vector2(dr, dr) * 0.38, dr * 0.18, Color(drop_light.lightened(0.3), 0.7))

## A wax pour's rim: a circle of `lobes` soft bulges turned by `phase`.
func _blob(c: Vector2, r: float, lobes: int, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		var k := 1.0 + 0.06 * sin(a * lobes + phase) + 0.03 * sin(a * (lobes + 4) + phase * 2.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts
