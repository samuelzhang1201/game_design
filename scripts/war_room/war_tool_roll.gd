class_name WarToolRoll
extends PanelContainer
## The staff's tool roll (spec 2026-10-07-war-room-annotations-and-planning-
## pieces ruling 15): a leather strip at the view's lower left whose slots
## (WarToolSlot, authored in scenes/war_room/war_tool_roll.tscn) pick the
## stick, the kind of mark and the two actions. It only says what was picked
## and shows what is in hand.

signal stick_picked(stick: String)
signal kind_picked(kind: String)
signal action_picked(action: String)


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


func slot(key: String) -> WarToolSlot:
	for s: WarToolSlot in slots():
		if s.key == key:
			return s
	return null


func _on_slot(_key: String, s: WarToolSlot) -> void:
	match s.group:
		"stick":
			stick_picked.emit(s.key)
		"kind":
			kind_picked.emit(s.key)
		_:
			action_picked.emit(s.key)


## Rings what is in hand: the stick, the kind, an action ("" none).
func show_state(stick: String, kind: String, action: String) -> void:
	for s: WarToolSlot in slots():
		match s.group:
			"stick":
				s.chosen = s.key == stick
			"kind":
				s.chosen = s.key == kind
			_:
				s.chosen = s.key == action
