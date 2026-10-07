class_name MarchConfirmPanel
extends PanelContainer
## The march's confirm (spec 2026-10-07-march-waypoints ruling 6; owner
## 2026-10-07: 在点击March并选择目的地之后，弹窗询问携带多少补给，并计算消耗的天数),
## authored in scenes/panels/march_confirm_panel.tscn: where the march goes, a
## row for each carried load (data/army_carry_loads.csv) with its arrival day,
## its supplies and the days they last — "runs N days short" when the stores
## would not cover the march — the current load pressed, then Confirm, Add
## waypoint, Cancel. It does not close on a click away: the map stays live so
## the route can be bent under it (ruling 7). ArmyOrderMenu owns it and fills
## it; it only says what was pressed.

signal confirmed(carry_days: int)
signal waypoint_added
signal cancelled

@onready var _title: Label = %Title
@onready var _sub: Label = %Sub
@onready var _head: Control = %Head
@onready var _rows: VBoxContainer = %Rows
@onready var _proto: Control = %RowProto
@onready var _confirm: Button = %Confirm
@onready var _add: Button = %AddWaypoint
@onready var _cancel: Button = %Cancel

var _group := ButtonGroup.new()
var _carry := -1


func _ready() -> void:
	_proto.visible = false
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
## the route wins, the nearest first on a tie.
func place_near(global_px: Vector2, route := Rect2(), map := Rect2()) -> void:
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
			Vector2(inner.position.x, inner.end.y - box.y), inner.end - box])
	var keep := route.grow(gap * 2.0)
	var best := Vector2.ZERO
	var best_cost := INF
	for spot: Vector2 in spots:
		var at := spot.clamp(view.position, (view.end - box).max(view.position))
		var cost := Rect2(at, box).intersection(keep).get_area() if keep.has_area() else 0.0
		if Rect2(at, box).grow(-1.0).has_point(global_px):
			cost += 1e9   # never over the end itself
		if cost < best_cost - 0.5:
			best_cost = cost
			best = at
	global_position = best


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
			if on:
				_carry = days)
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
