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

## A note's type and side margins, design px (Task 10's look check: at the
## body's 18 px the date "Spring 30, Year 1" overflowed a column; owner
## 2026-09-30: size再小一点 — 15 px until then).
const NOTE_FONT_SIZE := 13
const NOTE_MARGIN := 8.0
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

var _selected := -1
var _board_only := false

@onready var _columns: Dictionary = {
	"truth": %TruthNotes, "credible": %CredibleNotes, "consult": %ConsultNotes, "rumour": %RumourNotes}


func _ready() -> void:
	%Close.pressed.connect(func() -> void: visible = false)
	UiPalette.command_button(%Close)
	UiPalette.command_button(%ShowOnMap)
	%ShowOnMap.pressed.connect(_show_on_map)
	for col: String in HEADERS:
		var plaque := get_node("%" + col.capitalize() + "Plaque") as Label
		plaque.text = HEADERS[col]
		# board art fix round finding #1: an unbroken plaque ("Worth
		# consulting") forced its whole column to its full text width, which
		# alone pushed the frame past the viewport. Letting it wrap means the
		# column's minimum width is only its longest WORD.
		# Plaques-on-one-line fix: with the plaque art's real (smaller)
		# texture margin freeing up column width, every plaque now fits on
		# ONE line — AUTOWRAP_WORD (never AUTOWRAP_WORD_SMART, which fell
		# back to breaking INSIDE a word — "CONSULTI / NG" — when a single
		# word barely didn't fit) is the last-resort guarantee that a plaque
		# never splits a word if a future column somehow narrows further.
		plaque.autowrap_mode = TextServer.AUTOWRAP_WORD
		# a column's plaque is a section header in the game's own ink (owner
		# 2026-09-30: ground truth那行的字体色号太出戏 — the four credibility
		# hues read as pasted on the carved wood)
		UiPalette.style_section(plaque, PLAQUE_FONT_SIZE, UiPalette.TEXT_SOFT)
		# fix round 1: the fallback is the plaque's CURRENT look — the gold
		# rule style_section just set — never a blank StyleBoxEmpty, which
		# erased that rule with no art installed.
		var plaque_art := MissiveArt.style(Game.data, "plaque", plaque.get_theme_stylebox("normal"))
		# on the board's own wood a plaque needs its shadow to stand off it
		if plaque_art is ScaledNineSlice:
			(plaque_art as ScaledNineSlice).fill = _shadow(6, Vector2(0, 3))
		plaque.add_theme_stylebox_override("normal", plaque_art)
	# the board floats over the screen: a window, titled in the title face.
	# Its whole opening is WOOD (owner 2026-09-30: 请改的有真实木质的质感): the
	# carved frame's clear centre shows the board's planks laid under it, so
	# the title row, the columns and the desk all sit on one wooden board.
	var frame := MissiveArt.style(Game.data, "frame", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 16, "window"))
	var wood := MissiveArt.style(Game.data, "board", null)
	if frame is ScaledNineSlice and wood != null:
		(frame as ScaledNineSlice).fill = wood
		(frame as ScaledNineSlice).fill_inset = FRAME_OPEN_FROM
	%Frame.add_theme_stylebox_override("panel", frame)
	%BoardPanel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# fix round 1 (ruling: the plan was wrong): %Desk had no panel style
	# before this task, so its fallback is StyleBoxEmpty — the desk stays
	# fully transparent, no border or inset, until its parchment is installed.
	var desk := MissiveArt.style(Game.data, "letter", StyleBoxEmpty.new())
	# the letter lies ON the board: a soft shadow onto the wood under it
	if desk is ScaledNineSlice:
		(desk as ScaledNineSlice).fill = _shadow(14, Vector2(0, 6))
	%Desk.add_theme_stylebox_override("panel", desk)
	# the title stands on the board's wood now, where the gold reads (on the
	# old cream opening it needed the dark ink)
	UiPalette.style_title(%Title, 22, UiPalette.GOLD)
	# Board art follow-up: with the letter parchment installed the desk is
	# cream, and the theme's light ink (gold title, muted meta) is
	# unreadable on it — dark umber ink stands in instead. %LetterTitle and
	# %LetterMeta are never recreated, so setting this once here holds.
	var on_parchment := MissiveArt.texture(Game.data, "letter") != null
	UiPalette.style_header(%LetterTitle, 18,
		MapPalette.named(Game.data, "missive_ink") if on_parchment else UiPalette.GOLD)
	# the letter's own ink, like its facts (owner 2026-09-30: ground truth那行
	# 的字体色号太出戏 — the date · column line was a paler grey)
	%LetterMeta.add_theme_color_override("font_color",
		MapPalette.named(Game.data, "missive_ink") if on_parchment else UiPalette.TEXT_SOFT)
	# Receipt look fix: %DeskPainting's box was a fixed 150 design px tall
	# regardless of its own (flexible, per-screen-width) column, far wider
	# and shallower than the delivered.png paintings' 5:4, so the cover-crop
	# trimmed enough off the top to cut the mounted courier's head off. The
	# box now follows its OWN width at ui_missive_desk_painting_aspect,
	# recomputed live whenever the desk column's width changes.
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
	# the flat stand-ins (no art installed): the note on the desk is lit,
	# edged in parchment; an unread one wears gold
	var style := UiPalette.chip_style(UiPalette.CHIP_BG,
		UiPalette.GOLD if not bool(m.get("read", false)) else UiPalette.EDGE)
	if id == _selected:
		style = UiPalette.chip_style(UiPalette.CHIP_PRESSED, UiPalette.TEXT_SOFT)
		style.set_border_width_all(2)
	# a slip, not a button: smaller type and narrower margins, so the
	# unbreakable date fits a quarter of the board
	var hover := UiPalette.chip_style(UiPalette.CHIP_HOVER, UiPalette.GOLD)
	var pressed := UiPalette.chip_style(UiPalette.CHIP_PRESSED, UiPalette.GOLD)
	for s: StyleBoxFlat in [style, hover, pressed]:
		s.content_margin_left = NOTE_MARGIN
		s.content_margin_right = NOTE_MARGIN
	# Every note is an AGED SLIP with its own ruled border (owner 2026-09-30:
	# 每一个信息框都有边框，做旧的感觉): the one on the desk wears the gold-ruled
	# slip, hover and press a shade darker, all in the letter's dark ink.
	var art := MissiveArt.texture(Game.data, "note") != null
	var normal: StyleBox = MissiveArt.style(Game.data, "note_lit" if id == _selected else "note", style)
	var hover_art: StyleBox = MissiveArt.style(Game.data, "note", hover)
	var pressed_art: StyleBox = MissiveArt.style(Game.data, "note_lit", pressed)
	if hover_art is ScaledNineSlice:
		(hover_art as ScaledNineSlice).tint = Color(0.9, 0.86, 0.8)
	if pressed_art is ScaledNineSlice:
		(pressed_art as ScaledNineSlice).tint = Color(0.84, 0.8, 0.74)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover_art)
	b.add_theme_stylebox_override("pressed", pressed_art)
	b.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	if art:
		var ink := MapPalette.named(Game.data, "missive_ink")
		for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, ink)
	b.pressed.connect(func() -> void:
		if _board_only:
			note_chosen.emit(id)
		else:
			select(id))
	var pin := MissiveArt.texture(Game.data, "pin")
	if pin != null:
		var chip := TextureRect.new()
		chip.texture = pin
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
	var art := String(Game.data.courier_paintings.get("delivered", "")) if String(m.get("kind", "")) == "receipt" else ""
	var tex: Texture2D = UiPalette.load_art(art) if art != "" else null
	%DeskPainting.texture = tex
	%DeskPainting.visible = tex != null
	# Board art follow-up: facts are recreated every call, so the ink colour
	# (unreadable in the theme's light default once the desk is cream) must
	# be re-applied here each time, not just once in _ready.
	var on_parchment := MissiveArt.texture(Game.data, "letter") != null
	var ink := MapPalette.named(Game.data, "missive_ink")
	for f: Dictionary in m["facts"]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s: %s" % [String(f["label"]), Intel.text_of(f)]
		if on_parchment:
			l.add_theme_color_override("font_color", ink)
		%LetterFacts.add_child(l)


func _show_on_map() -> void:
	var m := MissiveLog.find(Game.state, _selected)
	if m.is_empty():
		return
	visible = false
	show_requested.emit(m["subject"])
