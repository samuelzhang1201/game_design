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

@onready var _view: WarRoomView = %View
@onready var _orders: ArmyOrderMenu = %Orders


func _ready() -> void:
	visible = false
	(%Frame as PanelContainer).add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 0, "map"))
	UiPalette.style_title(%Title, 18)
	%Close.pressed.connect(close)
	_view.piece_selected.connect(_on_piece)
	_view.selection_cleared.connect(_clear_card)
	_view.rake_started.connect(_on_rake)
	_view.sheet_requested.connect(lay_sheet)


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
	if detail != _detail:
		_card_mine = false
	_detail = detail
	visible = true
	_view.set_active(true)
	if _view.sheet_index() < 0:
		lay_sheet(_home_sheet())
	else:
		_view.refresh()


func _home_sheet() -> int:
	var home := MapManors.home_province(Game.data, Game.state)
	var row: Dictionary = Game.data.provinces.get(home, {})
	return maxi(0, WarSheets.sheet_of(Game.data, Vector2(
		float(row.get("center_x", 0)), float(row.get("center_y", 0)))))


func lay_sheet(index: int) -> void:
	_view.lay_sheet(index)
	var s: Dictionary = WarSheets.series(Game.data)[index]
	%Title.text = "Sheet %s · %s" % [s["numeral"], s["name"]]


func close() -> void:
	if not visible:
		return
	if _orders.visible:
		_orders.hide()
	_orders.withdraw_aim()
	visible = false
	_dirty = false
	_view.set_active(false)
	_clear_card()
	closed.emit()


func refresh() -> void:
	if visible:
		_dirty = true


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_view.refresh()


func _on_piece(code: String) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	_detail.show_entry(MapObjects.army_card(Game.data, code, Game.state))
	_card_mine = true


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
