class_name WarToolRoll
extends PanelContainer
## The staff's tool roll (spec 2026-10-07-war-room-annotations-and-planning-
## pieces ruling 15, 2026-10-08-war-room-draw-orders rulings 1-2): a leather
## strip at the view's lower left, authored in scenes/war_room/war_tool_roll.tscn
## — the HAND on the left the height of both rows, then two ROWS, each a
## side (its `side` meta: red theirs above, blue ours below): its crayon, the
## kinds of mark and its actions. The row a slot stands in is the side it
## draws for. The side in hand lights its row and dims the other. It only says
## what was picked and shows what is in hand.

signal stick_picked(side: String)               # "hand", or a row's crayon: that side
signal kind_picked(side: String, kind: String)
signal action_picked(side: String, action: String)

## How lit the row of the side NOT in hand stands (both rows lit before a side is chosen).
@export var dim_alpha := 0.42


func _ready() -> void:
	for s: WarToolSlot in slots():
		s.pressed.connect(_on_slot.bind(s))


func slots() -> Array[WarToolSlot]:
	var out: Array[WarToolSlot] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is WarToolSlot:
			out.append(n)
		stack.append_array(n.get_children())
	return out


## The side a slot draws for: its row's `side` meta ("" the hand).
static func side_of(s: Node) -> String:
	var n := s.get_parent()
	while n != null and not n is WarToolRoll:
		if n.has_meta("side"):
			return String(n.get_meta("side"))
		n = n.get_parent()
	return ""


## The slot of `key` on `side` ("" the hand's).
func slot(key: String, side := "") -> WarToolSlot:
	for s: WarToolSlot in slots():
		if s.key == key and (side == "" or side_of(s) == side):
			return s
	return null


## Each side's row.
func row(side: String) -> Control:
	for s: WarToolSlot in slots():
		if side_of(s) == side:
			return s.get_parent() as Control
	return null


func _on_slot(_key: String, s: WarToolSlot) -> void:
	var side := side_of(s)
	match s.group:
		"stick":
			stick_picked.emit(side if side != "" else "hand")
		"kind":
			kind_picked.emit(side, s.key)
		_:
			action_picked.emit(side, s.key)


## Rings what is in hand — the side ("" none chosen), the kind, an action
## ("" none) — lights the side's row, and greys what cannot be used: `why`
## is {side: {key: reason}}.
func show_state(side: String, kind: String, action: String, why: Dictionary = {}) -> void:
	for s: WarToolSlot in slots():
		var mine := side_of(s)
		var on := mine == side
		match s.group:
			"stick":
				# the hand: no row lit; a row's crayon: its side lit, nothing in hand
				s.chosen = on and kind == "" and action == ""
			"kind":
				s.chosen = on and s.key == kind
			_:
				s.chosen = on and s.key == action
		s.why = String((why.get(mine, {}) as Dictionary).get(s.key, ""))
	for sd: String in ["red", "blue"]:
		var r := row(sd)
		if r != null:
			r.modulate.a = 1.0 if side == "" or side == sd else dim_alpha
