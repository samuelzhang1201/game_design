class_name MissiveScreen
extends Control
## The Missive board (owner 2026-09-28, spec 2026-09-28-missive-board-and-spies
## §2, layout B): four credibility columns on the left two-thirds, the reading
## desk on the right third. Letters come from MissiveLog; selecting one reads
## it; Show on map hands the subject to GameRoot. Columns are the letters' own
## — nothing is dragged.

signal show_requested(subject: Dictionary)
## A note's press on the WAR ROOM's easel (board-only mode, spec
## 2026-10-02-war-room-v2 §1.3): the room opens the letter on the full board;
## the easel's own board never reads it.
signal note_chosen(id: int)

const HEADERS := {"truth": "Ground truth", "credible": "Highly credible",
	"consult": "Worth consulting", "rumour": "Rumour"}
## An empty column is simply empty (owner 2026-09-30: missive看版移除掉每一个信息
## 种类下面的text说明 — each column's one-line description is gone).

## A note's type, design px (Task 10's look check: at the
## body's 18 px the date "Spring 30, Year 1" overflowed a column; owner
## 2026-09-30: size再小一点 — 15 px until then).
const NOTE_FONT_SIZE := 13
## The pin astride a note's top edge, design px (at 12 it read as a speck).
const PIN_PX := 18.0
## A note's width, design px: a slip pinned in its column, not the column's
## full width (owner 2026-09-30: size再小一点).
const NOTE_WIDTH := 150.0
## The frame's clear opening begins this many TEXTURE px in from its edge
## (frame_open.png, tools/missive_board_art.py FRAME_OPEN_FROM): the wood is
## laid from there, under the moulding's shadowed lip.
const FRAME_OPEN_FROM := 62.0
## A column plaque's size: the cards' section headers (MilitaryPanel, the
## realm dashboard) are 14.
const PLAQUE_FONT_SIZE := 14

## The frame's fixed corner margin (left/right/bottom, and the floor for its
## top edge before any screen's top bar height is known).
const FRAME_MARGIN := 48.0
## Clearance kept between the top bar's bottom edge and the frame.
const FRAME_TOP_GAP := 8.0

## A note's slips (owner 2026-09-30: aged, ruled, the desk's ruled in gold)
## and the pin astride it — edited in the inspector.
const NOTE := preload("res://assets/2D/ui/missive_board/styles/note.tres")
const NOTE_LIT := preload("res://assets/2D/ui/missive_board/styles/note_lit.tres")
const NOTE_HOVER := preload("res://assets/2D/ui/missive_board/styles/note_hover.tres")
const NOTE_PRESSED := preload("res://assets/2D/ui/missive_board/styles/note_pressed.tres")
const PIN := preload("res://assets/2D/ui/missive_board/pin.png")

var _selected := -1
var _board_only := false

@onready var _columns: Dictionary = {
	"truth": %TruthNotes, "credible": %CredibleNotes, "consult": %ConsultNotes, "rumour": %RumourNotes}


## The board's look is scenes/missive_screen.tscn (owner 2026-10-02: the look
## lives in the editor): the carved frame over the wood (frame.tres, its fill
## board_wood.tres), the plaques, the desk's parchment casting its shadow
## (desk.tres), the letter's ink (the MissiveLetter* kinds); the notes made
## here wear note*.tres and the MissiveNote kind, the desk's facts MissiveFact.
func _ready() -> void:
	%Close.pressed.connect(func() -> void: visible = false)
	%ShowOnMap.pressed.connect(_show_on_map)
	# Receipt look fix: the desk's painting follows its OWN width at
	# ui_missive_desk_painting_aspect, recomputed live as the column changes.
	%DeskPainting.resized.connect(_fit_desk_painting)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())


## A soft shadow cast by a piece lying on the board (drawn under it as its
## ScaledNineSlice.fill): nothing but the shadow — the art covers the rest.
static func _shadow(size: int, offset: Vector2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = size
	s.shadow_offset = offset
	return s


## width / ui_missive_desk_painting_aspect = height, so a wider desk column
## still shows the whole rider, not a taller crop of the same slice.
func _fit_desk_painting() -> void:
	var aspect := Game.data.bal("ui_missive_desk_painting_aspect")
	if aspect <= 0.0:
		return
	var h: float = %DeskPainting.size.x / aspect
	if not is_equal_approx(%DeskPainting.custom_minimum_size.y, h):
		%DeskPainting.custom_minimum_size.y = h


## The frame's top edge, at least the fixed corner margin and never above
## the active screen's own top bar (fix round 1 finding 5: it sat under the
## purse row's lower half at the fixed 48 px margin, shorter than a two-line
## TopBar). GameRoot calls this with that screen's TopBar.bar_height() —
## 0.0 before one is known, which keeps the fixed margin.
## The board alone, filling this control, for the WAR ROOM's easel (spec
## 2026-10-02-war-room-v2 §1.3): no desk, no close, no dim.
func set_board_only(on: bool) -> void:
	_board_only = on
	%Desk.visible = not on
	%Close.visible = not on
	get_node("Dim").visible = not on
	if on:
		%Frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()


func board_only() -> bool:
	return _board_only


func set_top_inset(top_bar_bottom: float) -> void:
	%Frame.offset_top = maxf(FRAME_MARGIN, top_bar_bottom + FRAME_TOP_GAP)


func refresh() -> void:
	if MissiveLog.find(Game.state, _selected).is_empty():
		_selected = -1
	for col: String in _columns:
		var box: VBoxContainer = _columns[col]
		for c in box.get_children():
			box.remove_child(c)  # gone now, not at the frame's end
			c.queue_free()
		for m: Dictionary in MissiveLog.column(Game.state, col):
			box.add_child(_note(m))
	_fill_desk()


func notes_in(col: String) -> int:
	return MissiveLog.column(Game.state, col).size()


func select(id: int) -> void:
	_selected = id
	Game.mark_missive_read(id)
	refresh()
	var root := get_parent() as GameRoot
	if root != null:
		root.refresh_missive_badge(false)


func selected() -> int:
	return _selected


func desk_text() -> String:
	var out := String(%LetterTitle.text) + "\n" + String(%LetterMeta.text)
	for c in %LetterFacts.get_children():
		out += "\n" + String((c as Label).text)
	return out


func show_on_map_button() -> Button:
	return %ShowOnMap


func desk_painting() -> TextureRect:
	return %DeskPainting


func _note(m: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Note%d" % int(m["id"])
	# the date is one unbreakable unit: a narrow column broke it "Year / 1"
	b.text = "%s\n%s" % [String(m["title"]), CourierCard.date_of(int(m["day"])).replace(" ", "\u00a0")]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = NOTE_WIDTH
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var id := int(m["id"])
	# Every note is an AGED SLIP with its own ruled border (owner 2026-09-30:
	# 每一个信息框都有边框，做旧的感觉): the one on the desk wears the gold-ruled
	# slip, hover and press a shade darker, all in the letter's dark ink.
	b.theme_type_variation = &"MissiveNote"
	b.add_theme_stylebox_override("normal", NOTE_LIT if id == _selected else NOTE)
	b.add_theme_stylebox_override("hover", NOTE_HOVER)
	b.add_theme_stylebox_override("pressed", NOTE_PRESSED)
	b.pressed.connect(func() -> void:
		if _board_only:
			note_chosen.emit(id)
		else:
			select(id))
	if PIN != null:
		var chip := TextureRect.new()
		chip.texture = PIN
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# anchored top-centre: a 14x14 pin astride the note's top edge
		chip.anchor_left = 0.5
		chip.anchor_right = 0.5
		chip.anchor_top = 0.0
		chip.anchor_bottom = 0.0
		chip.offset_left = -PIN_PX * 0.5
		chip.offset_right = PIN_PX * 0.5
		chip.offset_top = -PIN_PX * 0.5
		chip.offset_bottom = PIN_PX * 0.5
		b.add_child(chip)
	return b


func _fill_desk() -> void:
	# board art fix round finding #3: remove_child() BEFORE queue_free(), as
	# refresh()'s note-clearing loop already does — a queue_free() alone
	# leaves the old label in the tree (and in get_children()) until the
	# deferred free actually runs, so get_child(0) right after a re-fill can
	# still read the PREVIOUS call's label.
	for c in %LetterFacts.get_children():
		%LetterFacts.remove_child(c)
		c.queue_free()
	var m := MissiveLog.find(Game.state, _selected)
	%ShowOnMap.visible = not m.is_empty()
	if m.is_empty():
		%LetterTitle.text = "Choose a letter"
		%LetterMeta.text = ""
		%DeskPainting.visible = false
		return
	# A letter about the LEDGER's books (an audit) has no place on the map:
	# its button opens the LEDGER instead (final review M1).
	var about_books := String((m.get("subject", {}) as Dictionary).get("kind", "")) == "ledger"
	%ShowOnMap.text = "Open the LEDGER" if about_books else "Show on map"
	%LetterTitle.text = String(m["title"])
	%LetterMeta.text = "%s · %s" % [CourierCard.date_of(int(m["day"])), HEADERS[String(m["column"])]]
	var tex: Texture2D = GameArt.table(GameArt.COURIER_PAINTINGS).of("delivered") as Texture2D \
		if String(m.get("kind", "")) == "receipt" else null
	%DeskPainting.texture = tex
	%DeskPainting.visible = tex != null
	# the facts in the letter's dark ink (the MissiveFact kind)
	for f: Dictionary in m["facts"]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s: %s" % [String(f["label"]), Intel.text_of(f)]
		l.theme_type_variation = &"MissiveFact"
		%LetterFacts.add_child(l)


func _show_on_map() -> void:
	var m := MissiveLog.find(Game.state, _selected)
	if m.is_empty():
		return
	visible = false
	show_requested.emit(m["subject"])
