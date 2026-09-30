class_name LedgerScreen
extends Control
## The LEDGER screen (spec 2026-09-30-ledger-ontology-design §6.1): laid
## exactly over the map panel (GameRoot fits it), so the left column keeps
## FACTS and the right column keeps the council (invariant 10). The only
## LEDGER piece that touches Game: it asks Ledger for a snapshot after a
## state change while open (coalesced: at most once a frame, however many
## days the clock ran), fills the left column, and runs an order through
## Game.try_execute. It clears only a card it put in the left column.

signal show_requested(subject: Dictionary)
signal closed

var _lens := "all"
var _opened: Dictionary = {}       # province code -> true: opened this viewing (never saved)
var _open_order: Array[String] = []
var _snap: Dictionary = {}
var _detail: MapDetailPanel
var _bound := false
var _dirty := false        # a state change waits to be drawn (drained in _process)
var _card_mine := false    # the left column's card or list is the LEDGER's own
var _rebuilds := 0         # snapshots drawn (the tests' seam)

@onready var _view: LedgerView3D = %View
@onready var _orders: LedgerOrderMenu = %Orders


func _ready() -> void:
	visible = false
	(%Frame as PanelContainer).add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 0, "map"))
	UiPalette.style_title(%Title, 18)
	%Close.pressed.connect(close)
	%Front.pressed.connect(func() -> void: _view.front_view())
	%Mode.pressed.connect(toggle_flat)
	%Back.pressed.connect(back)
	_view.sphere_selected.connect(_on_sphere)
	_view.thread_selected.connect(_on_thread)
	_view.drill_requested.connect(drill)
	_view.orders_requested.connect(_on_orders)
	_orders.chosen.connect(_on_order)


func view() -> LedgerView3D:
	return _view


func snapshot() -> Dictionary:
	return _snap


func lens() -> String:
	return _lens


## Open over the map, the left column's card being `detail`'s (the screen's
## own MapDetailPanel, handed in on every open: a screen swap makes a new one).
func open(detail: MapDetailPanel) -> void:
	if not _bound:
		_bound = true
		# The shipped ontology validates (tests/engine/test_ledger_schema.gd);
		# a hand edit that breaks it says so once, here, not as a silent gap.
		for err: String in Ledger.validate(Game.data):
			push_error("LEDGER data: " + err)
		_view.bind(Game.data)
		_build_lenses()
		Game.state_changed.connect(refresh)
	if _has_detail() and _detail.list_row_chosen.is_connected(drill):
		_detail.list_row_chosen.disconnect(drill)
	if not _has_detail() or detail != _detail:
		_card_mine = false  # a new screen's column holds nothing of the LEDGER's
	_detail = detail
	_detail.list_row_chosen.connect(drill)
	visible = true
	_dirty = false
	_view.set_active(true)
	_rebuild(false)
	set_lens(_lens)


func close() -> void:
	if not visible:
		return
	visible = false
	_dirty = false
	_view.set_active(false)
	_clear_card()
	closed.emit()


## Draw the live state again, keeping the camera (a state change, DEV MODE).
## Only marks the LEDGER dirty: Game.state_changed fires once a game day,
## several times a frame at high speed, and one snapshot a frame is enough.
func refresh() -> void:
	if visible:
		_dirty = true


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_rebuild(true)


func opened() -> Dictionary:
	return _opened


## A tab chooses its cluster (data/ledger_clusters.csv `lens`); All is the
## whole galaxy. The camera flies; nothing is read again.
func set_lens(lens_id: String) -> void:
	_lens = lens_id
	for b: Node in %Lenses.get_children():
		(b as Button).set_pressed_no_signal(String(b.name) == "Lens_" + lens_id)
	_view.focus_cluster(_cluster_for(lens_id))
	_clear_card()  # the old tab's card names a star the camera has left
	_crumb()


func _cluster_for(lens_id: String) -> String:
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["lens"]) == lens_id:
			return String(c["cluster"])
	return "all"


## From the left column's list or a double click: a province opens (its
## manors, towns and buildings settle round it) or closes; any other star is
## selected, its web framed and its card put in the left column.
func drill(id: String) -> void:
	if id == "" or id.begins_with("more:"):
		return
	if id.begins_with("province:"):
		var code := id.substr(9)
		if _opened.has(code):
			_opened.erase(code)
			_open_order.erase(code)
		else:
			_opened[code] = true
			_open_order.append(code)
		_rebuild(true)
	else:
		_view.frame_web(id)
	_view.select(id)
	_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap))


## Closes the last province opened.
func back() -> void:
	if _open_order.is_empty():
		return
	_opened.erase(_open_order.pop_back())
	_rebuild(true)


func toggle_flat() -> void:
	_view.set_flat(not _view.is_flat())
	%Mode.text = "3D" if _view.is_flat() else "2D"


func _has_detail() -> bool:
	return _detail != null and is_instance_valid(_detail)


## The left column's card, put there by the LEDGER.
func _show_card(entry: Dictionary) -> void:
	if not _has_detail():
		return
	_detail.show_entry(entry)
	_card_mine = not entry.is_empty()


## Closes the left column's card only if the LEDGER put it there: a card the
## player opened before the LEDGER stays when it closes.
func _clear_card() -> void:
	if _card_mine and _has_detail():
		_detail.show_entry({})
	_card_mine = false


func _rebuild(keep_camera: bool) -> void:
	_rebuilds += 1
	var selected := _view._selected
	_snap = Ledger.galaxy(Game.data, Game.state, _opened)
	_view.show_snapshot(_snap, keep_camera)
	if selected != "" and _view._selected == "":
		_clear_card()  # the selected star is gone (a courier arrived, a report aged out)
	_crumb()


func _crumb() -> void:
	var parts: Array[String] = ["Realm"]
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["cluster"]) == _view.cluster():
			parts.append(String(c["label"]))
	for code: String in _open_order:
		parts.append(LedgerResolvers.label_of(Game.data, Game.state, "province:" + code))
	%Crumb.text = " › ".join(parts)
	%Back.visible = not _open_order.is_empty()


## One flat tab per data/ledger_lenses.csv row, so a new lens needs no scene edit.
func _build_lenses() -> void:
	for row: Dictionary in Game.data.ledger_lenses:
		var b := Button.new()
		var lens_id := String(row["lens"])
		b.name = "Lens_" + lens_id
		b.text = String(row["label"])
		b.toggle_mode = true
		b.button_pressed = lens_id == _lens
		b.focus_mode = Control.FOCUS_NONE
		UiPalette.flat_tab(b, 14, 8.0)
		b.pressed.connect(func() -> void: set_lens(lens_id))
		%Lenses.add_child(b)


## A star's card in the left column; empty sky closes it.
func _on_sphere(id: String) -> void:
	if not _has_detail():
		return
	if id == "" or id.begins_with("more:"):
		_clear_card()
		return
	_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap))


## A thread's card: its accounts, each with its source and its age. A
## strand ("<link id>#<i>") opens its whole link's card, every account on it.
func _on_thread(id: String) -> void:
	if not _has_detail():
		return
	var link_id := LedgerView3D.link_id_of(id)
	for l: Dictionary in _snap["links"]:
		if String(l["id"]) == link_id:
			_show_card(LedgerCards.thread_entry(Game.data, Game.state, l))
			return


## A strand's orders are its link's; a governed thread offers one "Give it
## to …" row per councillor, read from the council as it sits now.
func _on_orders(id: String, at: Vector2) -> void:
	var node_id := LedgerView3D.link_id_of(id)
	var rows := Ledger.actions_for(Game.data, node_id, Game.state)
	if rows.is_empty():
		return
	_orders.open_for(node_id, rows, _view.global_position + at)


## An order that needs the map (a place to build, a point to send a spy to)
## closes the LEDGER and shows its subject on the map — only that: its label
## says "Show on the map to …", and the player gives the order there (arming
## the march aim from here is left for later, spec §12); any other runs at once.
func _on_order(node_id: String, row: Dictionary) -> void:
	if bool(row["needs_map"]):
		var subj := LedgerCards.subject_of(Game.data, Game.state, node_id)
		if subj.is_empty():
			return
		close()
		show_requested.emit(subj)
		return
	var res := Game.try_execute(ActionRequest.make(String(row["code"]), Ledger.params_of(row, node_id)))
	if not bool(res["ok"]):
		_show_card({"title": Ledger.order_text(Game.data, row, node_id), "lines": [String(res["error"])]})
