class_name WarFolioPanel
extends Control
## The open folio over the war room (owner 2026-10-01, spec 2026-10-01-war-room-design
## §4): a two-page manuscript held up to the eye. The book is a dark-leather
## window (the war table's rule: windows stay leather); its PAGES are vellum
## with ink text. The right page is WarFolio.sections — rubric small-capital
## headers, the reading face beneath; the left page is the ink figure
## (WarInkFigure, Task 13). ×, Escape or a click outside closes it; the left
## column's card stays.

signal closed

const LABEL_WIDTH := 120.0

var _code := ""


func _ready() -> void:
	visible = false
	(%Book as PanelContainer).add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 18, "window"))
	_dress_pages()
	%Close.pressed.connect(close)
	(%Dim as ColorRect).gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())


func code() -> String:
	return _code


func open_for(code: String) -> void:
	_code = code
	_fill_right()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## The two leaves: vellum under ink, set into the leather book.
func _dress_pages() -> void:
	var paper: Color = Game.data.war_palette["paper"]
	for page: Control in [%LeftPage, %RightPage]:
		var look := StyleBoxFlat.new()
		look.bg_color = paper
		look.set_border_width_all(1)
		look.border_color = Game.data.war_palette["paper_age"]
		look.set_content_margin_all(14.0)
		(page as PanelContainer).add_theme_stylebox_override("panel", look)


func _fill_right() -> void:
	var right: VBoxContainer = %Right
	for c in right.get_children():
		right.remove_child(c)
		c.queue_free()
	var rubric: Color = Game.data.war_palette["rubric"]
	var ink: Color = Game.data.war_palette["ink"]
	for s: Dictionary in WarFolio.sections(Game.data, Game.state, _code):
		var box := VBoxContainer.new()
		box.name = String(s["key"])
		var h := Label.new()
		h.name = "Header"
		h.text = String(s["label"]).to_upper()
		UiPalette.style_header(h, 14, rubric)
		box.add_child(h)
		var rows := GridContainer.new()
		rows.name = "Rows"
		rows.columns = 1
		for row: Dictionary in s["rows"]:
			var line := HBoxContainer.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # a grid column takes only what its expanders ask for
			var l := Label.new()
			l.text = String(row["label"])
			l.custom_minimum_size.x = LABEL_WIDTH
			l.add_theme_font_override("font", UiPalette.role_font("body_italic"))
			l.add_theme_color_override("font_color", Color(ink, 0.7))
			var v := Label.new()
			v.text = String(row["text"])
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_theme_color_override("font_color", ink)
			line.add_child(l)
			line.add_child(v)
			rows.add_child(line)
		box.add_child(rows)
		right.add_child(box)
