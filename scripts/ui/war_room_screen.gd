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
var _home: Node                # the column the card was borrowed from
var _home_index := -1
var _roll_tween: Tween
var _board_vp: SubViewport
var _board_screen: MissiveScreen
var _margin_sig: Array = []   # [sheet, the off-sheet (code, sheet) pairs, none on this sheet] last filled
## Where the 3D map DRAWS each regiment, pack px (Map3DView.unit_pack_positions):
## the room's pieces stand there (owner 2026-10-02: war room的军队单位位置一定要
## 和大地图一致). Read on open and after each state change; the clock is held
## while the room is open, so no day moves it in between.
var _drawn: Dictionary = {}
## Where `_drawn` comes from: the map under the room (_map_drawn); a test hands
## in its own (the suite has no 3D map).
var drawn_source := Callable()

@onready var _view: WarRoomView = %View
@onready var _orders: ArmyOrderMenu = %Orders
@onready var _folio: WarFolioPanel = %Folio


func _ready() -> void:
	# its look is scenes/screens/war_room_screen.tscn (owner 2026-10-02): the frame,
	# the title, the paper slips (war_slip.tres) and the card's roll, each
	# under the paper's theme so their words write in its ink; the leather of
	# ui_war_table 0 is put on in code (_dress_leather)
	visible = false
	if not UiPalette.war_table():
		_dress_leather()
	%Close.pressed.connect(request_close)
	(%LeavePrompt as WarLeavePrompt).chosen.connect(_on_leave)
	(%Deploy as WarDeployScroll).sealed.connect(_on_sealed)
	(%Deploy as WarDeployScroll).withdrawn.connect(func() -> void:
		_deploy_leaving = false   # Not yet: the player stays in the room
		_deploy_then = Callable())
	%BackToTable.pressed.connect(func() -> void: _view.leave_board())
	_view.board_entered.connect(_show_board_chrome.bind(true))
	_view.board_left.connect(_show_board_chrome.bind(false))
	_view.piece_selected.connect(_on_piece)
	_view.selection_cleared.connect(_clear_card)
	_view.rake_started.connect(_on_rake)
	_view.rake_dropped.connect(_orders.withdraw_aim)   # a rake given up takes its armed march with it
	_orders.drafting = true   # orders given in the room are drafts until sealed (spec 2026-10-02-war-room-v2 §3.1)
	_view.sheet_requested.connect(_view.swap_to)
	_view.sheet_laid.connect(_on_laid)
	_folio.closed.connect(_view.clear_selection)
	var roll: PanelContainer = %CardRoll
	if UiPalette.war_table():
		WarTable.ink_column(roll)   # the cards not yet written in theme kinds
	roll.draw.connect(func() -> void:
		var px := Game.data.bal("war_report_roller_px")
		WarScrollReveal.draw_roller(roll, Rect2(0.0, roll.size.y - px, roll.size.x, px)))


func view() -> WarRoomView:
	return _view


## Freed while open (the game quits, a test ends): the clock is let go, never
## left held for whatever comes next.
func _exit_tree() -> void:
	if visible:
		Game.hold_clock(false, "war_room")


func _read_drawn() -> Dictionary:
	return (drawn_source.call() if drawn_source.is_valid() else _map_drawn()) as Dictionary


## Where the 3D map under the room draws each regiment, pack px; {} when there
## is no map (none built, the suite): the pieces then stand at the engine's spot.
func _map_drawn() -> Dictionary:
	var root := get_parent() as GameRoot
	var screen: Node = root.current_screen if root != null else null
	if screen == null or not screen.has_method("map3d_view"):
		return {}
	var map: Map3DView = screen.map3d_view()
	return map.unit_pack_positions() if map != null else {}


## Test seam: the drawn places the room reads.
func drawn() -> Dictionary:
	return _drawn


func orders() -> ArmyOrderMenu:
	return _orders


func open(detail: MapDetailPanel) -> void:
	if not _bound:
		_bound = true
		_view.bind(Game.data, func() -> GameState: return Game.state,
			func() -> bool: return Game.clock_speed <= 0, func() -> Dictionary: return _drawn)
		_view.set_font(UiPalette.role_font("body_italic"))
		_build_board()
		_orders.follow(_view)
		Game.state_changed.connect(refresh)
		(%Key as WarMarginKey).setup(Game.data, _view)
		_folio.set_tier(Game.data, Map3DQuality.resolve_here(GameRoot.settings_path))
		_view.camera_moved.connect((%Key as WarMarginKey).queue_redraw)
		(%Key as WarMarginKey).north_pressed.connect(_view.start_north)
		var slip := %HoverSlip as WarHoverSlip
		slip.setup(Game.data)
		_view.ground_hovered.connect(_on_ground_hovered)
		_view.rake_aimed.connect(_on_rake_aimed)
		_view.hover_cleared.connect(slip.hide_slip)
		_view.rake_dropped.connect(slip.hide_slip)
	if detail != _detail:
		_card_mine = false
	_detail = detail
	# the clock stops and nothing starts it while the room is open (owner
	# 2026-10-02: 进入war room时间也一直是暂停的，无法继续，直到下达命令并退出)
	Game.hold_clock(true, "war_room")
	_drawn = _read_drawn()
	visible = true
	_view.set_active(true)
	if _view.sheet_index() < 0:
		lay_sheet(_home_sheet())
	else:
		_view.refresh()
		_fill_margin()   # the regiments moved while the room was shut
	(%Deploy as WarDeployScroll).refresh()   # kept drafts light it at once


## Facing the easel, the margin's slips would lie over the board: they make
## way, and Back to the table stands in the top row (spec §1.3).
func _show_board_chrome(on: bool) -> void:
	%BackToTable.visible = on
	%Slip.visible = not on
	%KeySlip.visible = not on


func board_screen() -> MissiveScreen:
	return _board_screen


## The easel's board (spec 2026-10-02-war-room-v2 §1.3): the Missive screen,
## board-only, in its own SubViewport whose texture the panel wears; rendered
## only while it is seen (_process).
func _build_board() -> void:
	_board_vp = SubViewport.new()
	_board_vp.name = "BoardViewport"
	var w := int(Game.data.bal("war_board_px"))
	_board_vp.size = Vector2i(w, int(round(float(w) * 0.8 / 1.2)))
	# laid out at war_board_layout_px, drawn at war_board_px: larger type, still sharp
	var lw := int(Game.data.bal("war_board_layout_px"))
	_board_vp.size_2d_override = Vector2i(lw, int(round(float(lw) * 0.8 / 1.2)))
	_board_vp.size_2d_override_stretch = true
	_board_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_board_vp.gui_embed_subwindows = true
	add_child(_board_vp)
	_board_screen = load("res://scenes/screens/missive_screen.tscn").instantiate()
	_board_screen.theme = UiPalette.build_theme()
	_board_vp.add_child(_board_screen)
	_board_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_screen.set_board_only(true)
	_board_screen.visible = true
	_board_screen.note_chosen.connect(_on_note)
	_view.set_board_texture(_board_vp.get_texture())
	_view.board_clicked.connect(_push_board_click)
	_view.board_hovered.connect(_push_board_hover)


## A ray's hit on the panel, pushed into the board's viewport as real input.
func _push_board_click(uv: Vector2, mb: InputEventMouseButton) -> void:
	var e := mb.duplicate() as InputEventMouseButton
	e.position = uv * _board_input_size()
	e.global_position = e.position
	_board_vp.push_input(e, true)


## The board's input space: its layout size when overridden, else its size.
func _board_input_size() -> Vector2:
	return Vector2(_board_vp.size_2d_override) if _board_vp.size_2d_override != Vector2i.ZERO else Vector2(_board_vp.size)


func _push_board_hover(uv: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = uv * _board_input_size()
	e.global_position = e.position
	_board_vp.push_input(e, true)


## A note on the easel: the full Missive board opens on it, over the room.
func _on_note(id: int) -> void:
	var root := get_parent() as GameRoot
	if root != null:
		root.open_missive_over_war_room(id)


func refresh_board() -> void:
	if _board_screen != null:
		_board_screen.refresh()


## Escape in the board's view flies back to the table (before GameRoot's
## pause menu, which takes it in its own _unhandled_input).
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return
	if _view.board_mode() == "board" or _view.board_mode() == "to_board":
		_view.leave_board()
		get_viewport().set_input_as_handled()


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
	%Title.text = "Sheet %s · %s" % [s["id"], s["name"]] if String(s["name"]) != "" else "Sheet %s" % s["id"]
	_fill_margin()
	%Key.queue_redraw()   # a new sheet, a new scale


## The leather (`ui_war_table` 0): the margin's slips and the card's roll are
## dark cards with light type (the game theme's), not paper. The slips stand
## in the screen's top-left and top-right corners, never over the sheet.
func _dress_leather() -> void:
	for slip: PanelContainer in [%Slip, %KeySlip]:
		slip.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 8, "column"))
		slip.theme = null
	var roll: PanelContainer = %CardRoll
	roll.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 24, "column"))
	roll.theme = null
	roll.remove_meta("paper_ground")


## One flat button per regiment off this sheet ("label → numeral") that lays
## its sheet; an empty sheet says so (spec §6).
func _fill_margin() -> void:
	var series := WarSheets.series(Game.data)
	var sheet := _view.sheet_index()
	var split := WarRoom.partition(Game.data, Game.state, sheet, _drawn)
	var off: Array = split["off"]
	var sig: Array = [sheet, off.map(func(p: Dictionary) -> String: return "%s@%d" % [p["code"], int(p["sheet"])]),
		(split["on"] as Array).is_empty()]
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
		b.text = "%s → %s" % [reg.get("label", p["code"]), series[to]["id"]]
		# a slip of tight rows in the slip's ink (the WarMarginRow kind)
		b.theme_type_variation = &"WarMarginRow"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
		none.theme_type_variation = &"WarMarginNone"
		box.add_child(none)
		box.move_child(none, 0)
		height += none.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = height


## Where to go once the room is left by its leave prompt (GameRoot.leave_war_room).
var _leave_then := Callable()
## Deploy… was chosen on the way out: once the resolutions are sent the room
## is left, and `_deploy_then` (where the player was going) runs.
var _deploy_leaving := false
var _deploy_then := Callable()


## The × button: leave through GameRoot's one door (it asks when drafts stand).
func request_close() -> void:
	var root := get_parent() as GameRoot
	if root != null:
		root.leave_war_room(Callable())
	else:
		close()


## Ask before leaving with drafts on the table (spec 2026-10-02-war-room-v2
## §3.2); `then` runs once the room is left.
func ask_leave(then: Callable) -> void:
	_leave_then = then
	(%LeavePrompt as WarLeavePrompt).open()


func asking_leave() -> bool:
	return (%LeavePrompt as WarLeavePrompt).visible


func _on_leave(choice: String) -> void:
	var then := _leave_then
	_leave_then = Callable()
	match choice:
		"discard":
			Game.discard_drafts()
			close()
		"keep":
			close()
		"deploy":
			_deploy_leaving = true   # the seal closes the room and goes on (_on_sealed)
			_deploy_then = then
			(%Deploy as WarDeployScroll).unroll()
			return
		_:
			return   # stay
	if then.is_valid():
		then.call()


## The resolutions are sent: when they were sealed on the way out (the leave
## prompt's Deploy…), leave and go on.
func _on_sealed(_result: Dictionary) -> void:
	var then := _deploy_then
	var leaving := _deploy_leaving
	_deploy_then = Callable()
	_deploy_leaving = false
	if leaving:
		close()
		if then.is_valid():
			then.call()


## `animate` false when the screen under the room is being replaced: its
## column (and the report captured from it) is gone (final review I3).
func close(animate := true) -> void:
	if not visible:
		return
	(%HoverSlip as WarHoverSlip).hide_slip()   # not rolled up with the room's picture
	# the room as it hangs now: it rolls back up off the screen beneath (owner
	# 2026-10-02, the hanging scroll); none when the screen beneath is being
	# replaced (final review I3: nothing is drawn over the new screen)
	var picture := WarScrollReveal.capture(get_viewport(), get_global_rect()) if animate else null
	var rect := get_global_rect()
	(%LeavePrompt as WarLeavePrompt).visible = false   # a forced close answers no question
	_leave_then = Callable()
	(%Deploy as WarDeployScroll).cancel()   # an unrolled scroll is put away, a seal in hand given up: nothing rides behind the player's back
	if _orders.visible:
		_orders.hide()
	_orders.withdraw_aim()
	_folio.close()
	visible = false
	_dirty = false
	_view.set_active(false)
	_view.clear_selection()   # a closed room's selection must never take Escape
	_clear_card()
	if _roll_tween != null:
		_roll_tween.kill()
	%CardRoll.visible = false
	_give_back()   # the room is gone at once: the column has its card back now
	# let go, but not restarted: the player starts the clock again (owner 2026-10-02)
	Game.hold_clock(false, "war_room")
	closed.emit()
	if animate and get_parent() != null:
		WarScrollReveal.play(get_parent(), rect, picture, false,
			Game.data.bal("war_unroll_s"), Game.data.bal("war_unroll_roller_px"))


func refresh() -> void:
	if visible:
		_dirty = true


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_drawn = _read_drawn()
		_view.refresh()
		_fill_margin()
		_folio.refresh()   # an order changes what the folio reads
		(%Deploy as WarDeployScroll).refresh()
		refresh_board()
	if _board_vp != null:
		var want := SubViewport.UPDATE_ALWAYS if visible and _view.board_visible() else SubViewport.UPDATE_DISABLED
		if _board_vp.render_target_update_mode != want:
			_board_vp.render_target_update_mode = want


## The pointer rested on the table: read the ground for the chosen regiment
## (spec 2026-10-07-war-room-scale-hover §4).
func _on_ground_hovered(pack_px: Vector2, screen_px: Vector2) -> void:
	var r := WarGround.reading(Game.data, Game.state, pack_px, _view.selected_army())
	_show_slip(WarGround.lines(Game.data, r), screen_px)


## A rake aimed: read its destination for the raked regiment, the days left to
## the arrow's own reading.
func _on_rake_aimed(code: String, pack_px: Vector2, screen_px: Vector2) -> void:
	var r := WarGround.reading(Game.data, Game.state, pack_px, code)
	_show_slip(WarGround.lines(Game.data, r, true), screen_px)


func _show_slip(lines: Array, view_px: Vector2) -> void:
	var slip := %HoverSlip as WarHoverSlip
	var origin := _view.get_global_rect().position - get_global_rect().position
	slip.show_lines(lines, origin + view_px, Rect2(origin, _view.size))


func _on_piece(code: String) -> void:
	(%HoverSlip as WarHoverSlip).hide_slip()
	if _detail == null or not is_instance_valid(_detail):
		return
	_detail.show_card(MapObjects.army_card(Game.data, code, Game.state))
	_card_mine = true
	_unroll_card()
	_folio.open_for(code)


func _clear_card() -> void:
	if _card_mine and _detail != null and is_instance_valid(_detail):
		_detail.show_entry({})
	_card_mine = false
	_roll_card_away()


func card_roll() -> PanelContainer:
	return %CardRoll


## Unroll the card over the room's left, where the column was (spec
## 2026-10-02-war-room-v2 §1.2): the column's MapDetailPanel is BORROWED into
## %CardRoll (the same node, so its signals and the screen's references hold)
## and the roll grows to the card's height; the margin slip steps right of it.
func _unroll_card() -> void:
	var roll: PanelContainer = %CardRoll
	if _detail.get_parent() != roll:
		_home = _detail.get_parent()
		_home_index = _detail.get_index()
		_detail.reparent(roll, false)
		if not _detail.closed.is_connected(_view.clear_selection):
			_detail.closed.connect(_view.clear_selection)
		if not _detail.host_requested.is_connected(close):
			_detail.host_requested.connect(close)   # the host takes the column the room covers (review I5)
	_detail.visible = true
	if not roll.visible:
		roll.position = Vector2(16.0, %Slip.offset_top)
		roll.size = Vector2(ScreenLayout.LEFT_WIDTH, 0.0)
		roll.visible = true
	var right := roll.position.x + ScreenLayout.LEFT_WIDTH + 12.0
	%Slip.offset_left = right
	%Slip.offset_right = right + 236.0
	_folio.offset_left = right   # the folio's book centres in the room right of the card
	_fit_roll.call_deferred()


## The card's height is known once its new rows are laid out (a frame after
## show_card): unroll to it, held inside the room.
func _fit_roll() -> void:
	var roll: PanelContainer = %CardRoll
	if not roll.visible or _detail == null or _detail.get_parent() != roll:
		return
	var px := Game.data.bal("war_report_roller_px")
	var margins := roll.get_theme_stylebox("panel").get_minimum_size().y if roll.has_theme_stylebox("panel") else 0.0
	_tween_roll(minf(_detail.content_height() + margins + px, size.y - roll.position.y - 16.0), Callable())


func _roll_card_away() -> void:
	var roll: PanelContainer = %CardRoll
	if not roll.visible:
		_give_back()
		return
	_tween_roll(0.0, func() -> void:
		roll.visible = false
		_give_back())


func _tween_roll(to_h: float, done: Callable) -> void:
	if _roll_tween != null:
		_roll_tween.kill()
	_roll_tween = create_tween()
	_roll_tween.tween_property(%CardRoll, "size:y", to_h, Game.data.bal("war_report_roll_s") * 0.6)
	_roll_tween.tween_callback(%CardRoll.queue_redraw)
	if done.is_valid():
		_roll_tween.finished.connect(done)


## The card back where it came from (the court's column), at its old place.
func _give_back() -> void:
	%Slip.offset_left = 16.0
	%Slip.offset_right = 252.0
	_folio.offset_left = 0.0
	if _home == null or _detail == null or not is_instance_valid(_detail) or _detail.get_parent() == _home:
		_home = null
		return
	if _detail.closed.is_connected(_view.clear_selection):
		_detail.closed.disconnect(_view.clear_selection)
	if _detail.host_requested.is_connected(close):
		_detail.host_requested.disconnect(close)
	_detail.reparent(_home, false)
	_home.move_child(_detail, _home_index)
	_home = null


## The rake took hold of a piece: arm the march, or say why not.
func _on_rake(code: String) -> void:
	var why := _orders.aim_for(code)
	if why != "":
		Game.publish_news(why)
		_view.cancel_rake()
