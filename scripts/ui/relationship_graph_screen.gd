class_name RelationshipGraphScreen
extends Control
## Live node-edge view of the court's relationship graph (role_player.md
## §Relationships). The player sits at the center; every other role rings
## them on an ellipse, grouped by category, in deterministic roster order.
## Edges read GameState.relationships directly and redraw on state_changed,
## so event shocks (rel: effects) and per-tick drift show up live.
## Overlay owned by GameRoot (like the pause menu); toggled by the TopBar's
## RELATIONS button via Game.relations_requested.

const NODE_SIZE := Vector2(48, 48)
const CATEGORY_ORDER := ["player", "family", "relative", "council", "officer",
	"noble", "celebrity", "enemy", "foreign"]
const KIN_TYPES := ["kin", "marriage"]

var _canvas: Control
var _nodes: Dictionary = {}   # char_id -> CharacterPortrait
var _labels: Dictionary = {}  # char_id -> Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_edges)
	add_child(_canvas)
	var title := Label.new()
	title.name = "Title"
	title.text = "THE WEB OF THE COURT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 10.0
	UiPalette.style_header(title, 13)
	add_child(title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -70.0
	close.offset_top = 8.0
	close.offset_right = -10.0
	close.pressed.connect(func() -> void: hide())
	add_child(close)
	resized.connect(_layout)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	Game.state_changed.connect(func() -> void:
		if visible:
			refresh())
	refresh()

## Rebuilds nodes against the current roster and relayouts. Safe to call with
## no campaign running (draws nothing).
func refresh() -> void:
	for id in _nodes:
		_nodes[id].queue_free()
		_labels[id].queue_free()
	_nodes.clear()
	_labels.clear()
	if Game.state == null:
		_canvas.queue_redraw()
		return
	for id in _ordered_ids():
		var chip := CharacterPortrait.instantiate_for(id, false)
		chip.tooltip_text = RelationshipGraph.describe_for(Game.state, id)
		_canvas.add_child(chip)
		_nodes[id] = chip
		var name_l := Label.new()
		name_l.text = Game.state.characters[id].display_name
		name_l.add_theme_font_size_override("font_size", 8)
		name_l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		_canvas.add_child(name_l)
		_labels[id] = name_l
	_layout()

## Deterministic order: category rank, then roster (insertion) order.
func _ordered_ids() -> Array:
	var ids: Array = Game.state.characters.keys()
	var rank := {}
	var i := 0
	for id in ids:
		rank[id] = i
		i += 1
	ids.sort_custom(func(a, b) -> bool:
		var ca := CATEGORY_ORDER.find(Game.state.characters[a].category)
		var cb := CATEGORY_ORDER.find(Game.state.characters[b].category)
		if ca != cb:
			return ca < cb
		return int(rank[a]) < int(rank[b]))
	return ids

func _layout() -> void:
	if _nodes.is_empty():
		return
	var center := size / 2.0
	var radius := Vector2(maxf(size.x / 2.0 - 90.0, 100.0),
		maxf(size.y / 2.0 - 70.0, 80.0))
	var ring: Array = []
	for id in _ordered_ids():
		if not _nodes.has(id):
			continue
		if Game.state.characters[id].category == "player":
			_place(id, center)
		else:
			ring.append(id)
	for i in ring.size():
		var angle := TAU * float(i) / float(ring.size()) - PI / 2.0
		_place(ring[i], center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	_canvas.queue_redraw()

func _place(id: String, pos: Vector2) -> void:
	_nodes[id].position = pos - NODE_SIZE / 2.0
	var name_l: Label = _labels[id]
	name_l.position = Vector2(pos.x - 60.0, pos.y + NODE_SIZE.y / 2.0 + 1.0)
	name_l.custom_minimum_size.x = 120.0
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## Kin/marriage edges draw gold; everything else by sentiment sign. Width and
## opacity scale with |sentiment|. The two directions of a pair are offset a
## few pixels apart so asymmetric feelings stay visible.
func _draw_edges() -> void:
	if Game.state == null:
		return
	for e in Game.state.relationships:
		if not (_nodes.has(e["from"]) and _nodes.has(e["to"])):
			continue
		var a: Vector2 = _nodes[e["from"]].position + NODE_SIZE / 2.0
		var b: Vector2 = _nodes[e["to"]].position + NODE_SIZE / 2.0
		var s := float(e["sentiment"])
		var color: Color
		if String(e["type"]) in KIN_TYPES:
			color = UiPalette.GOLD
		else:
			color = UiPalette.POSITIVE if s >= 0.0 else UiPalette.NEGATIVE
		color.a = clampf(0.25 + absf(s) / 130.0, 0.25, 0.95)
		var side := 1.0 if e["from"] < e["to"] else -1.0
		var offset := (b - a).orthogonal().normalized() * 2.0 * side
		_canvas.draw_line(a + offset, b + offset, color, 1.0 + absf(s) / 40.0, true)

## Test seams.
func node_count() -> int:
	return _nodes.size()

func has_node_for(id: String) -> bool:
	return _nodes.has(id)
