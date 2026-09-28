class_name MissiveScreen
extends Control
## The Missive board (owner 2026-09-28, spec 2026-09-28-missive-board-and-spies
## §2, layout B): four credibility columns on the left two-thirds, the reading
## desk on the right third. Letters come from MissiveLog; selecting one reads
## it; Show on map hands the subject to GameRoot. Columns are the letters' own
## — nothing is dragged.

signal show_requested(subject: Dictionary)
signal closed

const HEADERS := {"truth": "Ground truth", "credible": "Highly credible",
	"consult": "Worth consulting", "rumour": "Rumour"}
const EMPTY := {"truth": "The steward's monthly reports", "credible": "Receipts and clear-eyed spies",
	"consult": "Letters taken from others' couriers", "rumour": "What a spy only heard"}

var _selected := -1

@onready var _columns: Dictionary = {
	"truth": %TruthNotes, "credible": %CredibleNotes, "consult": %ConsultNotes, "rumour": %RumourNotes}


func _ready() -> void:
	%Close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	%ShowOnMap.pressed.connect(_show_on_map)
	for col: String in HEADERS:
		var plaque := get_node("%" + col.capitalize() + "Plaque") as Label
		plaque.text = HEADERS[col]
		plaque.add_theme_color_override("font_color", MapPalette.named(Game.data, "intel_" + col))
	%Frame.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 16))
	UiPalette.style_header(%Title, 22)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())


func refresh() -> void:
	if MissiveLog.find(Game.state, _selected).is_empty():
		_selected = -1
	for col: String in _columns:
		var box: VBoxContainer = _columns[col]
		for c in box.get_children():
			c.queue_free()
		var list := MissiveLog.column(Game.state, col)
		if list.is_empty():
			var hint := Label.new()
			hint.text = EMPTY[col]
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
			box.add_child(hint)
		for m: Dictionary in list:
			box.add_child(_note(m))
	_fill_desk()


func notes_in(col: String) -> int:
	return MissiveLog.column(Game.state, col).size()


func select(id: int) -> void:
	_selected = id
	MissiveLog.mark_read(Game.state, id)
	refresh()
	var root := get_parent() as GameRoot
	if root != null:
		root.refresh_missive_badge()


func selected() -> int:
	return _selected


func desk_text() -> String:
	var out := String(%LetterTitle.text) + "\n" + String(%LetterMeta.text)
	for c in %LetterFacts.get_children():
		out += "\n" + String((c as Label).text)
	return out


func show_on_map_button() -> Button:
	return %ShowOnMap


func _note(m: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Note%d" % int(m["id"])
	b.text = "%s\n%s" % [String(m["title"]), CourierCard.date_of(int(m["day"]))]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiPalette.chip_style(UiPalette.CHIP_BG,
		UiPalette.GOLD if not bool(m.get("read", false)) else UiPalette.EDGE))
	var id := int(m["id"])
	b.pressed.connect(func() -> void: select(id))
	return b


func _fill_desk() -> void:
	for c in %LetterFacts.get_children():
		c.queue_free()
	var m := MissiveLog.find(Game.state, _selected)
	%ShowOnMap.visible = not m.is_empty()
	if m.is_empty():
		%LetterTitle.text = "Choose a letter"
		%LetterMeta.text = ""
		return
	%LetterTitle.text = String(m["title"])
	%LetterMeta.text = "%s · %s" % [CourierCard.date_of(int(m["day"])), HEADERS[String(m["column"])]]
	for f: Dictionary in m["facts"]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s: %s" % [String(f["label"]), Intel.text_of(f)]
		%LetterFacts.add_child(l)


func _show_on_map() -> void:
	var m := MissiveLog.find(Game.state, _selected)
	if m.is_empty():
		return
	visible = false
	show_requested.emit(m["subject"])
