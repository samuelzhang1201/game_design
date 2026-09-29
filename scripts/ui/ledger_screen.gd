class_name LedgerScreen
extends Control
## The LEDGER screen (spec 2026-09-30-ledger-ontology-design §6.1): laid
## exactly over the map panel (GameRoot fits it), so the left column keeps
## FACTS and the right column keeps the council (invariant 10). The only
## LEDGER piece that touches Game: it asks Ledger for a snapshot on every
## state change while open, fills the left column, and runs an order
## through Game.try_execute.

signal show_requested(subject: Dictionary)
signal closed

var _lens := "economy"
var _focus_id := ""
var _snap: Dictionary = {}
var _detail: MapDetailPanel
var _bound := false

@onready var _view: LedgerView3D = %View
@onready var _orders: LedgerOrderMenu = %Orders


func _ready() -> void:
	visible = false
	(%Frame as PanelContainer).add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 0, "map"))
	UiPalette.style_title(%Title, 18)
	%Close.pressed.connect(close)
	%Front.pressed.connect(func() -> void: _view.front_view())
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
		_view.bind(Game.data)
		_build_lenses()
		Game.state_changed.connect(refresh)
	if _has_detail() and _detail.list_row_chosen.is_connected(drill):
		_detail.list_row_chosen.disconnect(drill)
	_detail = detail
	_detail.list_row_chosen.connect(drill)
	visible = true
	_view.set_active(true)
	_rebuild(false)


func close() -> void:
	if not visible:
		return
	visible = false
	_view.set_active(false)
	if _has_detail():
		_detail.show_entry({})
	closed.emit()


## Draw the live state again, keeping the camera (a state change, DEV MODE).
func refresh() -> void:
	if visible:
		_rebuild(true)


func set_lens(lens_id: String) -> void:
	_lens = lens_id
	_focus_id = ""
	for b: Node in %Lenses.get_children():
		(b as Button).set_pressed_no_signal(String(b.name) == "Lens_" + lens_id)
	_rebuild(false)


## Into an instance's ego network — from the left column's list or a
## double click — with THAT instance's card in the left column (the map's
## own card for a manor, town, regiment or courier; LedgerCards.entry's
## threads otherwise). A type sphere or a "more" sphere has none.
func drill(id: String) -> void:
	if id.begins_with("type:") or id.begins_with("more:") or id == "":
		return
	_focus_id = id
	_rebuild(false)
	if _has_detail() and _focus_id != "":
		_detail.show_entry(LedgerCards.entry(Game.data, Game.state, _focus_id, _snap))


## Out to the type level: the focus's card goes with its network.
func back() -> void:
	_focus_id = ""
	_rebuild(false)
	if _has_detail():
		_detail.show_entry({})


func _has_detail() -> bool:
	return _detail != null and is_instance_valid(_detail)


func _rebuild(keep_camera: bool) -> void:
	_snap = Ledger.snapshot(Game.data, Game.state, _lens, {"id": _focus_id} if _focus_id != "" else {})
	if bool(_snap["focus_lost"]):
		_focus_id = ""
	_view.show_snapshot(_snap, keep_camera)
	%Back.visible = _focus_id != ""
	%Crumb.text = "" if _focus_id == "" else LedgerResolvers.label_of(Game.data, Game.state, _focus_id)


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


## A type sphere with instances lists them in the left column; anything else
## opens its card there (LedgerCards.entry); empty ground or "more" closes it.
func _on_sphere(id: String) -> void:
	if not _has_detail():
		return
	if id == "" or id.begins_with("more:"):
		_detail.show_entry({})
		return
	var row := Ledger.type_row(Game.data, Ledger.type_of(id))
	if id.begins_with("type:") and String(row.get("instances", "")) != "":
		var rows: Array = []
		var cap := int(Game.data.bal("ledger_list_cap"))
		for r: Dictionary in LedgerResolvers.instances(String(row["instances"]), Game.data, Game.state):
			if rows.size() >= cap:
				break
			rows.append({"text": String(r["label"]), "id": String(r["id"])})
		_detail.show_list(String(row["label"]), rows)
		return
	_detail.show_entry(LedgerCards.entry(Game.data, Game.state, id, _snap))


## A thread's card: its accounts, each with its source and its age.
func _on_thread(id: String) -> void:
	if not _has_detail():
		return
	for l: Dictionary in _snap["links"]:
		if String(l["id"]) == id:
			_detail.show_entry(LedgerCards.thread_entry(Game.data, Game.state, l))
			return


func _on_orders(id: String, at: Vector2) -> void:
	var rows := Ledger.actions_for(Game.data, id)
	if rows.is_empty():
		return
	_orders.open_for(id, rows, _view.global_position + at)


## An order that needs the map (a place to build, a point to send a spy to)
## closes the LEDGER and shows its subject on the map; any other runs at once.
func _on_order(node_id: String, row: Dictionary) -> void:
	if bool(row["needs_map"]):
		var subj := LedgerCards.subject_of(Game.data, Game.state, node_id)
		if subj.is_empty():
			return
		close()
		show_requested.emit(subj)
		return
	var res := Game.try_execute(ActionRequest.make(String(row["code"]), Ledger.params_of(row, node_id)))
	if not bool(res["ok"]) and _has_detail():
		_detail.show_entry({"title": String(row["label"]), "lines": [String(res["error"])]})
