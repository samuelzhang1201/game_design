class_name MarchConfirmPanel
extends PanelContainer
## The march's confirm (spec 2026-10-07-march-waypoints ruling 6; owner
## 2026-10-07: 在点击March并选择目的地之后，弹窗询问携带多少补给，并计算消耗的天数),
## authored in scenes/panels/march_confirm_panel.tscn: where the march goes, a
## row for each carried load (data/army_carry_loads.csv) with its arrival day,
## its supplies and the days they last — "runs N days short" when the stores
## would not cover the march — the current load pressed, then Confirm, Add
## waypoint, Cancel. It does not close on a click away: the map stays live so
## the route can be bent under it (ruling 7). A march drawn for several
## regiments in the WAR ROOM lists each (%Regiments, a tick to leave one out,
## a refused one greyed with its reason; spec 2026-10-08-war-room-draw-orders
## ruling 9), and every land march asks where to SUPPLY it from (%SupplyTown,
## its figures under it; ruling 13). ArmyOrderMenu owns it and fills it; it
## only says what was pressed.

signal confirmed(carry_days: int)
signal waypoint_added
signal cancelled
signal carry_changed(days: int)
signal regiment_toggled(code: String, on: bool)
signal supply_chosen(town: String)

@onready var _title: Label = %Title
@onready var _sub: Label = %Sub
@onready var _head: Control = %Head
@onready var _rows: VBoxContainer = %Rows
@onready var _proto: Control = %RowProto
@onready var _confirm: Button = %Confirm
@onready var _add: Button = %AddWaypoint
@onready var _cancel: Button = %Cancel
@onready var _regiments: VBoxContainer = %Regiments
@onready var _reg_proto: Control = %RegimentProto
@onready var _supply_row: Control = %SupplyRow
@onready var _supply_town: OptionButton = %SupplyTown
@onready var _supply_figures: Label = %SupplyFigures

var _group := ButtonGroup.new()
var _carry := -1


var _towns: Array = []   # the supply list's towns, in its order ("" the first row: no new point)


func _ready() -> void:
	_proto.visible = false
	_reg_proto.visible = false
	_regiments.visible = false
	_supply_row.visible = false
	_supply_figures.visible = false
	_supply_town.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _towns.size():
			supply_chosen.emit(String(_towns[i])))
	_confirm.pressed.connect(func() -> void: confirmed.emit(_carry))
	_add.pressed.connect(func() -> void: waypoint_added.emit())
	_cancel.pressed.connect(func() -> void: cancelled.emit())


## Fill it: `rows` are MarchPlan.carry_rows ([] for a fleet, which carries no
## train), `carry` the load pressed; each button a {label, hint, why} — a
## non-empty `why` greys it out and is its tooltip.
func show_plan(title: String, sub: String, rows: Array, carry: int, commit: Dictionary,
		add: Dictionary, cancel: Dictionary) -> void:
	_title.text = title
	_sub.text = sub
	_carry = carry
	_fill(rows)
	_button(_confirm, commit)
	_button(_add, add)
	_button(_cancel, cancel)
	show()


## New figures for the same loads (the route was bent), the pressed one kept.
func refresh(title: String, sub: String, rows: Array, add: Dictionary) -> void:
	_title.text = title
	_sub.text = sub
	_fill(rows)
	_button(_add, add)


## The regiments of a march drawn for several: [{code, label, line, short,
## why, on}] — `why` greys a refused one (no tick); [] (or one) hides the list.
func show_group(rows: Array) -> void:
	for row: Node in _regiments.get_children():
		if row != _reg_proto:
			_regiments.remove_child(row)
			row.queue_free()
	_regiments.visible = rows.size() > 1
	if rows.size() <= 1:
		reset_size()
		return
	for r: Dictionary in rows:
		var row := _reg_proto.duplicate() as Control
		row.visible = true
		var code := String(r["code"])
		row.set_meta("code", code)
		var tick := row.get_node("Pick") as CheckBox
		tick.text = String(r["label"])
		var why := String(r.get("why", ""))
		tick.button_pressed = why == "" and bool(r.get("on", true))
		tick.disabled = why != ""
		tick.tooltip_text = why
		tick.toggled.connect(func(on: bool) -> void: regiment_toggled.emit(code, on))
		(row.get_node("Line") as Label).text = why if why != "" else String(r.get("line", ""))
		(row.get_node("Short") as Label).text = "" if why != "" else String(r.get("short", ""))
		_regiments.add_child(row)
	reset_size()


## The supply towns: [{town ("" no new point), label, why}] — a `why` greys
## the town with its reason — `chosen` selected, `figures` under it; [] hides it.
func show_supply(options: Array, chosen: String, figures: String) -> void:
	_supply_town.clear()
	_towns = []
	_supply_row.visible = not options.is_empty()
	for o: Dictionary in options:
		var i := _supply_town.item_count
		_supply_town.add_item(String(o["label"]))
		_towns.append(String(o["town"]))
		var why := String(o.get("why", ""))
		_supply_town.set_item_disabled(i, why != "")
		_supply_town.set_item_tooltip(i, why)
		if String(o["town"]) == chosen:
			_supply_town.select(i)
	set_supply_figures(figures if not options.is_empty() else "")


func set_supply_figures(text: String) -> void:
	_supply_figures.text = text
	_supply_figures.visible = text != ""
	reset_size()


## The Supply from list as shown: [{town, label, why, disabled, selected}] (tests read it).
func shown_supply() -> Array:
	var out: Array = []
	for i in _towns.size():
		out.append({"town": String(_towns[i]), "label": _supply_town.get_item_text(i), "why": _supply_town.get_item_tooltip(i),
			"disabled": _supply_town.is_item_disabled(i), "selected": _supply_town.selected == i})
	return out


## The supply town selected ("" none / no new point).
func chosen_supply() -> String:
	var i := _supply_town.selected
	return String(_towns[i]) if i >= 0 and i < _towns.size() else ""


## Select a supply town as the list does (a click on a lit town on the map).
func select_supply(town: String) -> void:
	var i := _towns.find(town)
	if i >= 0 and not _supply_town.is_item_disabled(i):
		_supply_town.select(i)
		supply_chosen.emit(town)


## Every regiment's row as shown: [{code, on, disabled, line}] (tests read it).
func shown_group() -> Array:
	var out: Array = []
	for row: Node in _regiments.get_children():
		if row == _reg_proto or row.is_queued_for_deletion():
			continue
		var tick := row.get_node("Pick") as CheckBox
		out.append({"code": String(row.get_meta("code", "")), "on": tick.button_pressed, "disabled": tick.disabled,
			"line": (row.get_node("Line") as Label).text})
	return out


## Add waypoint is the 3D map's; the room draws its route instead.
func set_add_shown(on: bool) -> void:
	_add.visible = on


## The load pressed, in days; -1 when no row is offered (a fleet).
func chosen_carry() -> int:
	return _carry


## Press a load's row as a click on it does (the rows are toggle buttons in one group).
func pick(days: int) -> void:
	for row: Node in _rows.get_children():
		if row != _proto and int(row.get_meta("days", -1)) == days:
			(row.get_node("Pick") as Button).button_pressed = true


## Every row's figures as shown: [{days, arrive, stores, short}] (tests read it).
func shown_rows() -> Array:
	var out: Array = []
	for row: Node in _rows.get_children():
		if row == _proto or row.is_queued_for_deletion():
			continue
		out.append({"days": int(row.get_meta("days", -1)), "arrive": (row.get_node("Arrive") as Label).text,
			"stores": (row.get_node("Stores") as Label).text, "short": (row.get_node("Short") as Label).text,
			"pressed": (row.get_node("Pick") as Button).button_pressed})
	return out


func confirm_button() -> Button:
	return _confirm


func add_button() -> Button:
	return _add


func cancel_button() -> Button:
	return _cancel


## Stand beside `global_px` (the destination click) — or, when every spot
## beside it would cover the route (`route`, its box on screen), in a corner
## of the map (`map`) — kept inside the window: the place covering least of
## the route wins, the nearest first on a tie. `blocked` (global rects: the
## room's slips and book) cost their overlap like the route does.
## The route covered weighs this many times a blocked rect covered: the march
## being confirmed is never hidden while any spot avoids it.
const ROUTE_WEIGHT := 1000.0

## The panel has been put in its place.
signal placed


func place_near(global_px: Vector2, route := Rect2(), map := Rect2(), blocked: Array[Rect2] = []) -> void:
	reset_size()
	var box := get_combined_minimum_size()
	var view := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var gap := 14.0
	var spots: Array = [
		global_px + Vector2(gap, gap), global_px + Vector2(gap, -gap - box.y),
		global_px + Vector2(-gap - box.x, gap), global_px + Vector2(-gap - box.x, -gap - box.y)]
	if map.has_area():
		var inner := map.grow(-gap)
		spots.append_array([inner.position, Vector2(inner.end.x - box.x, inner.position.y),
			Vector2(inner.position.x, inner.end.y - box.y), inner.end - box,
			Vector2(inner.get_center().x - box.x * 0.5, inner.position.y),
			Vector2(inner.get_center().x - box.x * 0.5, inner.end.y - box.y),
			Vector2(inner.position.x, inner.get_center().y - box.y * 0.5),
			Vector2(inner.end.x - box.x, inner.get_center().y - box.y * 0.5)])
	var keep := route.grow(gap * 2.0)
	var best := Vector2.ZERO
	var best_cost := INF
	for spot: Vector2 in spots:
		var at := spot.clamp(view.position, (view.end - box).max(view.position))
		var cost := ROUTE_WEIGHT * (Rect2(at, box).intersection(keep).get_area() if keep.has_area() else 0.0)
		for b: Rect2 in blocked:
			cost += Rect2(at, box).intersection(b).get_area() if b.has_area() else 0.0
		if Rect2(at, box).grow(-1.0).has_point(global_px):
			cost += 1e9   # never over the end itself
		if cost < best_cost - 0.5:
			best_cost = cost
			best = at
	global_position = best
	placed.emit()


func _fill(rows: Array) -> void:
	for row: Node in _rows.get_children():
		if row != _proto:
			_rows.remove_child(row)
			row.queue_free()
	_head.visible = not rows.is_empty()
	_rows.visible = not rows.is_empty()
	for r: Dictionary in rows:
		var row := _proto.duplicate() as Control
		row.visible = true
		row.set_meta("days", int(r["days"]))
		var pick_btn := row.get_node("Pick") as Button
		pick_btn.text = String(r["label"])
		pick_btn.button_group = _group
		pick_btn.button_pressed = int(r["days"]) == _carry
		var days := int(r["days"])
		pick_btn.toggled.connect(func(on: bool) -> void:
			if on and _carry != days:
				_carry = days
				carry_changed.emit(days))
		var arrive := int(r["arrive"])
		(row.get_node("Arrive") as Label).text = "%d day%s" % [arrive, "" if arrive == 1 else "s"]
		# the load's days are its button; its supplies last them (MarchPlan's `lasts`)
		(row.get_node("Stores") as Label).text = "%s supplies" % UiPalette.format_int(int(r["units"]))
		var short := int(r["short"])
		(row.get_node("Short") as Label).text = "runs %d day%s short" % [short, "" if short == 1 else "s"] \
			if short > 0 else ""
		_rows.add_child(row)
	reset_size()


func _button(b: Button, row: Dictionary) -> void:
	b.text = String(row.get("label", b.text))
	var why := String(row.get("why", ""))
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else String(row.get("hint", ""))
