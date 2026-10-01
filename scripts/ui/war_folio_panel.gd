class_name WarFolioPanel
extends Control
## The open folio over the war room (owner 2026-10-01, spec 2026-10-01-war-room-design
## §4): a two-page manuscript held up to the eye. The book is a dark-leather
## window (the war table's rule: windows stay leather); its PAGES are vellum
## with ink text. The right page is WarFolio.sections laid dense in
## balance war_folio_columns columns — rubric small-capital headers, the
## reading face beneath, every size a war_folio_* key; the left page is the ink
## figure (WarInkFigure, Task 13). ×, Escape or a click outside closes it; the
## left column's card stays. While it is open the screen asks it to refresh as
## the clock runs, so the page never goes stale.

signal closed

var _code := ""
var _shown: Array = []   # the sections last laid, so a refresh that changes nothing rebuilds nothing


func _ready() -> void:
	visible = false
	(%Dim as ColorRect).color = UiPalette.DIM_OVERLAY
	var margin := _px("war_folio_book_margin_px")
	var book: PanelContainer = %Book
	book.custom_minimum_size = Vector2(_px("war_folio_book_w_px"), _px("war_folio_book_h_px"))
	book.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, int(margin), "window"))
	(%Pages as HBoxContainer).add_theme_constant_override("separation", int(_px("war_folio_pages_sep_px")))
	(%RightPage as Control).size_flags_stretch_ratio = _px("war_folio_right_ratio")
	(%Right as HBoxContainer).add_theme_constant_override("separation", int(_px("war_folio_col_sep_px")))
	_dress_pages()
	_dress_close(book)
	%Close.pressed.connect(close)
	(%Dim as ColorRect).gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())


func code() -> String:
	return _code


func open_for(code: String) -> void:
	_code = code
	_shown = []
	_fill_right()
	(%RightScroll as ScrollContainer).scroll_vertical = 0
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Lay the page again from the live state if anything on it changed (the clock
## runs under the folio), keeping the reader's place.
func refresh() -> void:
	if not visible or _code == "":
		return
	var scroll: ScrollContainer = %RightScroll
	var at := scroll.scroll_vertical
	if _fill_right():
		scroll.set_deferred("scroll_vertical", at)   # the new rows lay out next frame


## The section boxes of the right page, in order, whatever column holds them.
func section_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for col in (%Right as HBoxContainer).get_children():
		out.append_array(col.get_children())
	return out


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


static func _px(key: String) -> float:
	return Game.data.bal(key)


## The two leaves: vellum under ink, set into the leather book.
func _dress_pages() -> void:
	var paper: Color = Game.data.war_palette["paper"]
	for page: Control in [%LeftPage, %RightPage]:
		var look := StyleBoxFlat.new()
		look.bg_color = paper
		look.set_border_width_all(int(_px("war_folio_page_border_px")))
		look.border_color = Game.data.war_palette["paper_age"]
		look.set_content_margin_all(_px("war_folio_page_margin_px"))
		(page as PanelContainer).add_theme_stylebox_override("panel", look)


## The × stands in the leather margin's top-right corner, off both pages.
func _dress_close(book: Control) -> void:
	var side := _px("war_folio_close_px")
	var close_btn: Button = %Close
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(side, side)
	close_btn.offset_right = book.custom_minimum_size.x * 0.5 - 2.0
	close_btn.offset_left = close_btn.offset_right - side
	close_btn.offset_top = -book.custom_minimum_size.y * 0.5 + 2.0
	close_btn.offset_bottom = close_btn.offset_top + side
	close_btn.add_theme_font_size_override("font_size", int(_px("war_folio_header_px")))
	close_btn.add_theme_color_override("font_color", UiPalette.GOLD)
	close_btn.add_theme_color_override("font_hover_color", UiPalette.TEXT_SOFT)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		close_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())


## Rebuild the right page; false when it would be the page already shown.
func _fill_right() -> bool:
	var secs := WarFolio.sections(Game.data, Game.state, _code)
	if secs == _shown:
		return false
	_shown = secs
	var right: HBoxContainer = %Right
	for c in right.get_children():
		right.remove_child(c)
		c.queue_free()
	var cols := maxi(1, int(_px("war_folio_columns")))
	var boxes: Array[Control] = []
	for s: Dictionary in secs:
		boxes.append(_section_box(s))
	for group: Array in _split(secs, cols):
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", int(_px("war_folio_section_sep_px")))
		for i: int in group:
			col.add_child(boxes[i])
		right.add_child(col)
	return true


## The section indices in order, cut into `cols` runs of about equal weight
## (a section weighs its rows and a line for its header, longer texts a little more).
static func _split(secs: Array, cols: int) -> Array:
	var weights: Array[float] = []
	var total := 0.0
	for s: Dictionary in secs:
		var w := 1.5
		for row: Dictionary in s["rows"]:
			w += 1.0 + float(String(row["text"]).length()) / 30.0
		weights.append(w)
		total += w
	var out: Array = []
	var run: Array = []
	var acc := 0.0
	for i in secs.size():
		# a run closes where the running weight is nearest its share of the whole
		if not run.is_empty() and out.size() < cols - 1:
			var share := total / float(cols) * float(out.size() + 1)
			if absf(acc + weights[i] - share) > absf(acc - share):
				out.append(run)
				run = []
		run.append(i)
		acc += weights[i]
	out.append(run)
	return out


func _section_box(s: Dictionary) -> VBoxContainer:
	var rubric: Color = Game.data.war_palette["rubric"]
	var ink: Color = Game.data.war_palette["ink"]
	var body := int(_px("war_folio_body_px"))
	var box := VBoxContainer.new()
	box.name = String(s["key"])
	box.add_theme_constant_override("separation", 0)
	var h := Label.new()
	h.name = "Header"
	h.text = String(s["label"]).to_upper()
	UiPalette.style_header(h, int(_px("war_folio_header_px")), rubric)
	box.add_child(h)
	var rows := GridContainer.new()
	rows.name = "Rows"
	rows.columns = 1
	rows.add_theme_constant_override("v_separation", int(_px("war_folio_row_sep_px")))
	for row: Dictionary in s["rows"]:
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # a grid column takes only what its expanders ask for
		line.add_theme_constant_override("separation", int(_px("war_folio_label_gap_px")))
		var l := Label.new()
		l.text = String(row["label"])
		l.custom_minimum_size.x = _px("war_folio_label_w_px")
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_override("font", UiPalette.role_font("body_italic"))
		l.add_theme_font_size_override("font_size", body)
		l.add_theme_color_override("font_color", Color(ink, _px("war_folio_label_alpha")))
		var v := Label.new()
		v.text = String(row["text"])
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		v.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_theme_font_size_override("font_size", body)
		v.add_theme_color_override("font_color", ink)
		line.add_child(l)
		line.add_child(v)
		rows.add_child(line)
	box.add_child(rows)
	return box
