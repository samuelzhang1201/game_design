class_name WarRoomScreen
extends Control
## The WAR ROOM screen (owner 2026-10-01, spec 2026-10-01-war-room-design §1):
## laid exactly over the map panel (GameRoot fits it) like the LEDGER, so the
## left column keeps FACTS and the right column the council (invariant 10).
## The only WAR ROOM piece that touches Game: it binds the view, redraws it
## after a state change (at most once a frame), puts a chosen regiment's card
## in the left column, and runs orders through the map's own ArmyOrderMenu.

signal closed

var _detail: MapDetailPanel
var _bound := false
var _dirty := false
var _card_mine := false
var _capture: Texture2D
var _column_rect := Rect2()
var _margin_sig: Array = []   # [sheet, the off-sheet (code, sheet) pairs, none on this sheet] last filled

@onready var _view: WarRoomView = %View
@onready var _orders: ArmyOrderMenu = %Orders
@onready var _folio: WarFolioPanel = %Folio


func _ready() -> void:
	visible = false
	(%Frame as PanelContainer).add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 0, "map"))
	UiPalette.style_title(%Title, 18)
	_dress_slip()
	%Close.pressed.connect(close)
	_view.piece_selected.connect(_on_piece)
	_view.selection_cleared.connect(_clear_card)
	_view.rake_started.connect(_on_rake)
	_view.rake_dropped.connect(_orders.withdraw_aim)   # a rake given up takes its armed march with it
	_view.sheet_requested.connect(_view.swap_to)
	_view.sheet_laid.connect(_on_laid)
	_folio.closed.connect(_view.clear_selection)


func view() -> WarRoomView:
	return _view


func orders() -> ArmyOrderMenu:
	return _orders


func open(detail: MapDetailPanel) -> void:
	if not _bound:
		_bound = true
		_view.bind(Game.data, func() -> GameState: return Game.state,
			func() -> bool: return Game.clock_speed <= 0)
		_view.set_font(UiPalette.role_font("body_italic"))
		_orders.follow(_view)
		Game.state_changed.connect(refresh)
		(%Key as WarMarginKey).setup(Game.data, _view)
		_folio.set_tier(Game.data, Map3DQuality.resolve_here(GameRoot.settings_path))
		_view.camera_moved.connect((%Key as WarMarginKey).queue_redraw)
		(%Key as WarMarginKey).north_pressed.connect(_view.start_north)
	if detail != _detail:
		_card_mine = false
	_detail = detail
	visible = true
	_view.set_active(true)
	if _view.sheet_index() < 0:
		lay_sheet(_home_sheet())
	else:
		_view.refresh()
		_fill_margin()   # the regiments moved while the room was shut


## The report as it lay when the room opened, and where (GameRoot): closing
## unrolls it over the column again (spec 2026-10-02-war-room-v2 §1.2).
func set_report_capture(capture: Texture2D, rect: Rect2) -> void:
	_capture = capture
	_column_rect = rect


func _home_sheet() -> int:
	var home := MapManors.home_province(Game.data, Game.state)
	var row: Dictionary = Game.data.provinces.get(home, {})
	return maxi(0, WarSheets.sheet_of(Game.data, Vector2(
		float(row.get("center_x", 0)), float(row.get("center_y", 0)))))


## A new graphics tier (the menu's Graphics button): the room and the folio's figure.
func set_tier(tier: String) -> void:
	if not _bound:
		return   # bind reads the tier itself
	_view.set_tier(tier)
	_folio.set_tier(Game.data, tier)


func lay_sheet(index: int) -> void:
	var series: Array = WarSheets.series(Game.data)
	if index < 0 or index >= series.size():
		return
	_view.lay_sheet(index)


## A sheet was laid (at once, or at the roll-up's midpoint): its title, and
## the margin of the regiments standing on the others.
func _on_laid(index: int) -> void:
	var s: Dictionary = WarSheets.series(Game.data)[index]
	%Title.text = "Sheet %s · %s" % [s["numeral"], s["name"]]
	_fill_margin()
	%Key.queue_redraw()   # a new sheet, a new scale


## The margin's slip (owner ruling 2026-10-01, Task 16): ink on paper in the
## screen's top-left corner under the title, off the table — the war table's
## paper when that UI is on, else a dark card with light type. Never over the
## sheet, which fills the frame below it.
func _dress_slip() -> void:
	for slip: PanelContainer in [%Slip, %KeySlip]:
		if UiPalette.war_table():
			slip.add_theme_stylebox_override("panel", PaperStyle.make("paper", 6.0, 11))
		else:
			slip.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 8, "column"))


## One flat button per regiment off this sheet ("label → numeral") that lays
## its sheet; an empty sheet says so (spec §6).
func _fill_margin() -> void:
	var series := WarSheets.series(Game.data)
	var sheet := _view.sheet_index()
	var off := WarRoom.off_sheet(Game.data, Game.state, sheet)
	var sig: Array = [sheet, off.map(func(p: Dictionary) -> String: return "%s@%d" % [p["code"], int(p["sheet"])]),
		WarRoom.on_sheet(Game.data, Game.state, sheet).is_empty()]
	if sig == _margin_sig:
		return   # the same list: its buttons stand (a click mid-refresh is not lost)
	_margin_sig = sig
	var box: VBoxContainer = %Margin
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for p: Dictionary in off:
		var to := int(p["sheet"])
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		var reg := ArmySystem.regiment(Game.data, String(p["code"]))
		b.text = "%s → %s" % [reg.get("label", p["code"]), series[to]["numeral"]]
		UiPalette.flat_tab(b, 12, 3.0)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var look := b.get_theme_stylebox(state) as StyleBoxFlat
			look.content_margin_top = 1.0   # a slip of rows, tight enough to clear the sheet's corner
			look.content_margin_bottom = 1.0
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", UiPalette.ink("soft"))
		b.add_theme_color_override("font_hover_color", UiPalette.ink("accent"))
		b.pressed.connect(func() -> void: _view.swap_to(to))
		box.add_child(b)
	# at most war_margin_rows rows show; a longer list scrolls, so the slip never
	# grows down over the sheet's corner and its pieces
	var rows := box.get_child_count()
	var scroll: ScrollContainer = %MarginScroll
	var cap := int(Game.data.bal("war_margin_rows"))
	var row_h := (box.get_child(0) as Control).get_combined_minimum_size().y if rows > 0 else 0.0
	var height := row_h * float(mini(rows, cap))
	if bool(sig[2]):
		var none := Label.new()
		none.text = "No regiment of ours on this sheet."
		UiPalette.style_header(none, 13, UiPalette.ink("muted"))
		box.add_child(none)
		box.move_child(none, 0)
		height += none.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = height


func close() -> void:
	if not visible:
		return
	if _orders.visible:
		_orders.hide()
	_orders.withdraw_aim()
	_folio.close()
	visible = false
	_dirty = false
	_view.set_active(false)
	_view.clear_selection()   # a closed room's selection must never take Escape
	_clear_card()
	closed.emit()
	if _column_rect.size.x > 0.0 and get_parent() != null:
		WarReportRoll.play(get_parent(), _column_rect, _capture, false,
			Game.data.bal("war_report_roll_s"), Game.data.bal("war_report_roller_px"), UiPalette.war_table())
	_capture = null
	_column_rect = Rect2()


func refresh() -> void:
	if visible:
		_dirty = true


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_view.refresh()
		_fill_margin()
		_folio.refresh()   # the clock runs under an open folio


func _on_piece(code: String) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	_detail.show_card(MapObjects.army_card(Game.data, code, Game.state))
	_card_mine = true
	_folio.open_for(code)


func _clear_card() -> void:
	if _card_mine and _detail != null and is_instance_valid(_detail):
		_detail.show_entry({})
	_card_mine = false


## The rake took hold of a piece: arm the march, or say why not.
func _on_rake(code: String) -> void:
	var why := _orders.aim_for(code)
	if why != "":
		Game.publish_news(why)
		_view.cancel_rake()
