class_name ArmyOrderMenu
extends PopupMenu
## A regiment's orders on the right mouse button (owner 2026-09-22: "鼠标右
## 键点击会有移动和驻防的选项激活动作"). Its rows are data — data/army_orders.csv,
## in the order they are shown — so renaming or reordering them touches no code.
##
## MARCH is AIMED, not issued by the menu: choosing it arms the map, the next
## left click on the ground is the destination, and the CONFIRM PANEL
## (MarchConfirmPanel, spec 2026-10-07-march-waypoints) opens there, the route
## drawn to it — the load to carry with each load's days, Confirm, Add
## waypoint, Cancel. Only Confirm sends the order. Add waypoint keeps the point
## and aims on from it; while the panel stands the route can be bent on the map
## (its `route_bent`), each waypoint checked as the end is. That is why its
## label ends in an ellipsis. Escape, Cancel or a right click give it up.
## A STANCE row (ARMY_STANCE) runs at once, its row's `params` (the stance)
## sent with the regiment; the war room's menu leaves stances off.
## A committed march's end ring opens the ROUTE menu: Edit route… loads its
## waypoints and end into the panel, Cancel march halts it (an ARMY_GARRISON).
##
## Routes are planned only on a PAUSED clock (owner 2026-09-27: 兵人行进路线只能
## 在暂停模式下选择，时间流逝的时候不可以操作): while time runs MARCH, Edit and
## Cancel march are greyed out with data/army_route_orders.csv's reason, and
## an aim or a waiting confirm is withdrawn the moment the clock starts.
##
## Every order goes through Game.try_execute, exactly as the manor card's
## buttons do — so ActionSystem validates it, OrderCosts charges it and the
## opinion signature applies. A map order is not a back door into the state.

## The regiment waiting for a destination click, "" when none is. The map
## reads this to stop a left click also opening the card of whatever it
## landed on.
signal aiming_changed(regiment_code: String)

## The route menu's ids, after the order rows'; CANCEL is the supply
## rates' Cancel row.
const CANCEL := 101
const EDIT := 200
const HALT := 201
const STRIKE := 202
## A garrison's rows (owner 2026-10-06, choice A): GARRISON_ROW + the
## regiment's index in `_garrison`.
const GARRISON_ROW := 300
## The supply rows (spec 2026-10-07-army-supply-lines §5.1): Add / Change
## supply point…, Withdraw supply point, and the confirm's rates (RATE_BASE +
## the index in SupplyLines.RATES). The load is asked on the march's confirm
## (owner 2026-10-07: 右键点击军队时，不要显示携带多少补给).
const SUPPLY_ADD := 400
const SUPPLY_WITHDRAW := 401
const RATE_BASE := 420

## The march's confirm, authored (spec 2026-10-07-march-waypoints ruling 6).
const CONFIRM_SCENE := preload("res://scenes/panels/march_confirm_panel.tscn")

## The WAR ROOM's menu (owner 2026-10-02, spec 2026-10-02-war-room-v2 §3.1):
## every order given here is a DRAFT — COMMIT pencils a march, Cancel march
## pencils a halt, no courier and no fee until the council's resolutions are
## sealed (Game.deploy_drafts) — and the route menu opens over a draft too,
## offering Edit route… and Strike the draft. The 3D map's menu leaves it off.
var drafting := false

var _map: Node = null
var _code := ""
var _aiming := ""
## The aimed march's destination (pack px) while the confirm is asked;
## Vector2(-1, -1) when none waits.
var _pending := Vector2(-1, -1)
## The pending route's waypoints, pack px in order (the map's `aim_waypoints`).
var _waypoints: Array = []
## The confirm panel (made on first use, beside this menu) and where the route
## menu was opened, for an Edit route… that opens the panel there.
var _panel: MarchConfirmPanel = null
var _route_at := Vector2.ZERO
## The regiments of the garrison whose list is open, and where it opened.
var _garrison: Array = []
var _garrison_at := Vector2.ZERO
## The regiment whose supply point is being picked, "" when none; and the
## town clicked, whose rate the confirm asks.
var _supply_for := ""
var _supply_town := ""


func _ready() -> void:
	# _code is NOT cleared on popup_hide: PopupMenu.activate_item hides the
	# menu BEFORE it emits id_pressed, so clearing it there threw every chosen
	# order away (2026-09-24: 兵棋的操作我并没有看到实现). _open_for sets it anew.
	id_pressed.connect(_on_chosen)


## Follow a map — either map, by signal name, as MapDetailPanel.follow does.
func follow(map: Node) -> void:
	_map = map
	map.connect("army_menu_requested", _open_for)
	map.connect("ground_clicked", _on_ground)
	if map.has_signal("route_clicked"):
		map.connect("route_clicked", _open_route)
	if map.has_signal("garrison_menu_requested"):
		map.connect("garrison_menu_requested", _open_garrison)
	if map.has_signal("route_bent"):
		map.connect("route_bent", _on_route_bent)
	popup_hide.connect(func() -> void: _after_hide.call_deferred())


## Open over the regiment `code`. Each row is offered only when the engine
## would actually take it: the menu never shows an order that ActionSystem
## is about to refuse.
func _open_for(code: String, at: Vector2) -> void:
	if Game.state == null:
		return
	_end_supply_pick()
	_set_aim("")
	_code = code
	clear()
	for i in Game.data.army_orders.size():
		var row: Dictionary = Game.data.army_orders[i]
		# a battle stance is the map's order: the war room drafts only marches
		if drafting and String(row["action_code"]) != "ARMY_MARCH":
			continue
		add_item(String(row["label"]), i)
		var why := _refusal(String(row["action_code"]), code, row.get("params", {}))
		var row_at := get_item_index(i)
		set_item_disabled(row_at, why != "")
		set_item_tooltip(row_at, why if why != "" else String(row["hint"]))
	_add_supply_rows(code)
	if item_count == 0:
		return
	_pop(at)


func _supply_row(key: String, id: int, why: String) -> void:
	var row: Dictionary = Game.data.army_supply_orders.get(key, {"label": key, "hint": ""})
	add_item(String(row["label"]), id)
	var i := get_item_index(id)
	set_item_disabled(i, why != "")
	set_item_tooltip(i, why if why != "" else String(row["hint"]))


## The regiment's supply rows: offered only for a land regiment of the realm.
func _add_supply_rows(code: String) -> void:
	var reg := ArmySystem.regiment(Game.data, code)
	# supply orders are the map's: the war room's orders are drafts (owner ruling 2026-10-07)
	if drafting or reg.is_empty() or String(reg.get("is_naval", "0")) == "1" \
			or String(reg["kingdom_code"]) != Game.data.resolve_realm("player_realm"):
		return
	add_separator()
	var has_line := not SupplyLines.line(Game.state, code).is_empty()
	# all three supply orders are given on a paused clock (spec §4), as a march is
	var paused := _paused_reason()
	_supply_row("change" if has_line else "add", SUPPLY_ADD, paused)
	if has_line:
		_supply_row("withdraw", SUPPLY_WITHDRAW, paused if paused != "" else _refusal("SUPPLY_POINT_CLEAR", code))


## A town's garrison of several regiments was clicked: one row a regiment,
## "6th (Walbover) Regiment — 1600"; the one chosen is selected and its
## orders open where the list stood.
func _open_garrison(codes: Array, at: Vector2) -> void:
	if Game.state == null or codes.is_empty():
		return
	_end_supply_pick()
	_set_aim("")
	_garrison = codes.duplicate()
	_garrison_at = at
	clear()
	for i in _garrison.size():
		var reg := ArmySystem.regiment(Game.data, String(_garrison[i]))
		add_item("%s — %d" % [String(reg.get("label", _garrison[i])), int(MapObjects.regiment_size(Game.data, reg))],
			GARRISON_ROW + i)
	_pop(at)


## A committed march's end ring (or the war room's pennant, which also stands
## over a march whose courier still rides) was clicked: Edit route… or Cancel
## march.
func _open_route(code: String, at: Vector2) -> void:
	if Game.state == null:
		return
	var draft := drafting and not WarDrafts.of(Game.state, code).is_empty()
	if not draft and ArmySystem.order_of(Game.data, Game.state, code) != ArmySystem.ORDER_MARCH \
			and WarRoom.pennant_of(Game.data, Game.state, code).is_empty():
		return
	_end_supply_pick()
	_set_aim("")
	_code = code
	_route_at = at
	clear()
	_add_row("edit", EDIT, _paused_reason())
	if draft:
		_add_row("strike", STRIKE, "")
	else:
		_add_row("halt_draft" if drafting else _row_key("halt", code), HALT,
			_paused_reason() if _paused_reason() != "" else _refusal("ARMY_GARRISON", code))
	_pop(at)


## The destination was clicked (or a route loaded for editing): the confirm
## panel opens beside `at` (the map's px) with the route's figures.
func _open_confirm(at: Vector2) -> void:
	var p := confirm_panel()
	var plan := _plan()
	var carry := ArmySystem.carry_of(Game.data, ArmySystem.state_of(Game.data, Game.state, _aiming))
	if drafting:
		var d := WarDrafts.of(Game.state, _aiming)
		carry = int(d.get("carry_days", carry))
	var commit := _route_row("commit_draft" if drafting else _row_key("commit", _aiming))
	p.show_plan(plan["title"], plan["sub"], plan["rows"], carry if not (plan["rows"] as Array).is_empty() else -1,
		commit, _add_waypoint_row(), _route_row("cancel"))
	var origin := (_map as Control).get_global_rect().position if _map is Control else Vector2.ZERO
	var map_rect := (_map as Control).get_global_rect() if _map is Control else Rect2()
	if _map != null and _map.has_signal("hover_cleared"):
		_map.emit_signal("hover_cleared")   # the WAR ROOM's slip at the tip goes: the confirm speaks now
	p.place_near(origin + at, _route_rect(origin), map_rect)


## The planned route's box on screen (global px): the piece, its waypoints and
## the end, as the map projects them — the panel keeps off it. Rect2() when
## the map cannot project.
func _route_rect(origin: Vector2) -> Rect2:
	if _map == null or not _map.has_method("screen_pos_of_px"):
		return Rect2()
	var pts: Array = [ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, _aiming))]
	if _map.has_method("position_of"):
		pts[0] = _map.call("position_of", _aiming)   # the WAR ROOM's believed place
	pts.append_array(_waypoints)
	pts.append(_pending)
	var box := Rect2()
	var any := false
	for p: Vector2 in pts:
		var at: Variant = _map.call("screen_pos_of_px", p)
		if at == null:
			continue
		var g := origin + (at as Vector2)
		box = Rect2(g, Vector2.ZERO) if not any else box.expand(g)
		any = true
	return box


## The panel, made on first use beside this menu (a child of its screen).
func confirm_panel() -> MarchConfirmPanel:
	if _panel == null:
		_panel = CONFIRM_SCENE.instantiate() as MarchConfirmPanel
		var host := get_parent() if get_parent() != null else self
		host.add_child(_panel)
		_panel.confirmed.connect(func(_carry: int) -> void: _commit())
		_panel.waypoint_added.connect(_add_waypoint)
		_panel.cancelled.connect(func() -> void: _withdraw("The march is given up."))
	return _panel


## The pending route's title, sub line and load rows (MarchPlan) — a fleet,
## which carries no train, has no rows and says its days in the sub line.
func _plan() -> Dictionary:
	var code := _aiming
	var reg := ArmySystem.regiment(Game.data, code)
	var naval := String(reg.get("is_naval", "0")) == "1"
	var rows := [] if naval else MarchPlan.carry_rows(Game.data, Game.state, code, _pending, _waypoints)
	var from := ArmySystem.position_of(Game.data, Game.state, reg)
	var metres := 0.0
	var curve := ArmySystem.curve_px(Game.data, from, _waypoints, _pending)
	for i in range(1, curve.size()):
		metres += curve[i - 1].distance_to(curve[i]) * float(ArmySystem.metres_per_pack_px(Game.data))
	var unit := String(Game.data.map_info.get("distance_unit", "km"))
	var dist := metres / (1609.0 if unit == "mi" else 1000.0)
	var sub := "%s %s" % [UiPalette.format_int(int(round(dist))), unit]
	if not _waypoints.is_empty():
		sub += " · %d waypoint%s" % [_waypoints.size(), "" if _waypoints.size() == 1 else "s"]
	if naval:
		var days := CourierSystem.arrival_days(Game.data, Game.state, code, _pending, Vector2(-1, -1), -1, _waypoints)
		sub += " · arrives in %d day%s" % [days, "" if days == 1 else "s"]
	return {"title": "%s to %s" % [_name_of(code), Intel.place_label(Game.data, Game.state, _pending)],
		"sub": sub, "rows": rows}


func _route_row(key: String) -> Dictionary:
	var row: Dictionary = Game.data.army_route_orders.get(key, {"label": key, "hint": ""})
	return {"label": String(row["label"]), "hint": String(row["hint"]).replace("{fee}",
		str(CourierSystem.fee_gold(Game.data, CourierSystem.ORDINARY))), "why": ""}


func _add_waypoint_row() -> Dictionary:
	var row := _route_row("add_waypoint")
	var most := int(Game.data.bal("army_march_waypoints_max"))
	if _waypoints.size() >= most:
		row["why"] = String(Game.data.army_route_orders.get("waypoints_full", {}).get("hint",
			"A march takes at most {max} waypoints")).replace("{max}", str(most))
	return row


## A fleet's orders take no courier yet (CourierSystem.carries_orders), so
## its COMMIT and Cancel march read the rows that promise none.
func _row_key(key: String, code: String) -> String:
	var reg := ArmySystem.regiment(Game.data, code)
	if not reg.is_empty() and not CourierSystem.carries_orders(reg) \
			and Game.data.army_route_orders.has(key + "_fleet"):
		return key + "_fleet"
	return key


func _add_row(key: String, id: int, why: String) -> void:
	var row: Dictionary = Game.data.army_route_orders.get(key, {"label": key, "hint": ""})
	add_item(String(row["label"]), id)
	var i := get_item_index(id)
	set_item_disabled(i, why != "")
	set_item_tooltip(i, why if why != "" else String(row["hint"]).replace("{fee}",
		str(CourierSystem.fee_gold(Game.data, CourierSystem.ORDINARY))))


## `at` in the map's own px.
func _pop(at: Vector2) -> void:
	var origin := Vector2.ZERO
	if _map is Control:
		origin = (_map as Control).get_global_rect().position
	popup_on_parent(Rect2i(Vector2i((origin + at).round()), Vector2i(1, 1)))


## Why a route cannot be planned now, "" on a paused clock.
func _paused_reason() -> String:
	if Game.clock_speed <= 0:
		return ""
	return String(Game.data.army_route_orders.get("paused_only", {}).get("hint", "Pause the clock first."))


## Why the engine would refuse this order, "" when it would take it. MARCH is
## asked about a destination it has not been given yet, so it is asked
## without one — the questions that do not need a destination (is it mine,
## has it anyone under arms, can the chest pay) are the ones worth asking
## before the player aims.
func _refusal(action_code: String, code: String, params: Dictionary = {}) -> String:
	if action_code == "ARMY_MARCH" and _paused_reason() != "":
		return _paused_reason()
	var req := ActionRequest.make(action_code, params.merged({"regiment": code}, true))
	if action_code == "ARMY_MARCH":
		var here := ArmySystem.position_of(Game.data, Game.state,
			ArmySystem.regiment(Game.data, code))
		req.params["x"] = here.x
		req.params["y"] = here.y + 1.0   # anywhere but here, so "already there" is not the answer
	# a draft costs nothing until sealed: in the war room only the place can refuse it
	var err := Game.engine.actions.validate_place(req, Game.state) if drafting \
		else Game.engine.actions.validate(req, Game.state)
	# The one refusal a MARCH cannot answer yet is about the ground it has not
	# been aimed at; everything else is a real reason to grey the row out.
	if action_code == "ARMY_MARCH" and (err.contains("into the sea") or err.contains("off the map")):
		return ""
	return err


func _on_chosen(id: int) -> void:
	if id >= GARRISON_ROW and id - GARRISON_ROW < _garrison.size():
		# a regiment chosen from its garrison: selected as a click on it would,
		# its orders opened where the list stood (deferred: this menu is hiding)
		var code := String(_garrison[id - GARRISON_ROW])
		if _map != null and _map.has_method("select_army"):
			_map.call("select_army", code)
		_open_for.call_deferred(code, _garrison_at)
		return
	if id >= RATE_BASE and id < RATE_BASE + SupplyLines.RATES.size():
		_send_supply(int(SupplyLines.RATES[id - RATE_BASE]))
		return
	if id == SUPPLY_ADD:
		if _code != "" and _paused_reason() == "":
			_start_supply_pick(_code)
		return
	if id == SUPPLY_WITHDRAW:
		if _code != "" and _paused_reason() == "":
			_run(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": _code}))
		return
	match id:
		CANCEL:
			if _supply_for != "":
				_end_supply_pick()
				Game.publish_news("No supply point is chosen.")
				return
			_withdraw("The march is given up.")
			return
		EDIT:
			if _code != "" and _paused_reason() == "":
				_edit_route(_code)
			return
		HALT:
			if _code != "" and drafting:
				Game.plant_draft(_code, WarDrafts.GARRISON, Vector2.ZERO)
				Game.publish_news("A halt for %s is pencilled in." % _name_of(_code))
			elif _code != "":
				_run(ActionRequest.make("ARMY_GARRISON", {"regiment": _code}))
			return
		STRIKE:
			if _code != "":
				Game.strike_draft(_code)
				Game.publish_news("%s's draft is struck out." % _name_of(_code))
			return
	if _code == "" or id < 0 or id >= Game.data.army_orders.size():
		return
	var row: Dictionary = Game.data.army_orders[id]
	if String(row["action_code"]) == "ARMY_MARCH":
		_set_aim(_code)
		Game.publish_news("%s awaits its orders — click where to send it." % _name_of(_code))
		return
	_run(ActionRequest.make(String(row["action_code"]),
		(row.get("params", {}) as Dictionary).merged({"regiment": _code}, true)))


## The aimed march's destination: held, drawn to, and asked about — the
## order goes in only on Confirm. The panel opens at `screen_px`, the click's
## own point in the map's px: the OS cursor (get_local_mouse_position) is not
## the click's when the click was pushed rather than made — the snapshot
## harness's, which put the menu wherever the real cursor was (2026-09-30).
## While the panel stands a click on the ground does nothing (ruling 7).
func _on_ground(pack_px: Vector2, screen_px := Vector2(-1, -1)) -> void:
	if _supply_for != "" and _supply_town == "":
		var pick_at := screen_px
		if pick_at.x < 0.0:
			pick_at = (_map as Control).get_local_mouse_position() if _map is Control else Vector2.ZERO
		_on_supply_ground(pack_px, pick_at)
		return
	if _aiming == "" or _pending.x >= 0.0:
		return
	_pending = pack_px
	if _map != null and "aim_dest" in _map:
		_map.set("aim_dest", pack_px)
	var at := screen_px
	if at.x < 0.0:
		at = (_map as Control).get_local_mouse_position() if _map is Control else Vector2.ZERO
	_open_confirm(at)


## Confirm: the load (when it changes) and the march with its waypoints — in
## the WAR ROOM one draft holding both (ruling 8). A refusal is said and the
## route stays up to be mended.
func _commit() -> void:
	if _aiming == "" or _pending.x < 0.0:
		return
	var code := _aiming
	var to := _pending
	var wps := _waypoints.duplicate()
	var pairs: Array = []
	for w: Vector2 in wps:
		pairs.append([w.x, w.y])
	var params := {"regiment": code, "x": to.x, "y": to.y}
	if not pairs.is_empty():
		params["waypoints"] = pairs
	var march := ActionRequest.make("ARMY_MARCH", params)
	var carry := _panel.chosen_carry() if _panel != null else -1
	var own := ArmySystem.carry_of(Game.data, ArmySystem.state_of(Game.data, Game.state, code))
	if drafting:
		# a draft costs nothing yet, but no seal could ever send one into the sea
		var why := Game.engine.actions.validate_place(march, Game.state)
		if why != "":
			Game.publish_news(why)
			return
		_set_aim("")
		Game.plant_draft(code, WarDrafts.MARCH, to, wps, carry if carry >= 0 and carry != own else -1)
		Game.publish_news("%s's march is pencilled in." % _name_of(code))
		return
	var load_req: ActionRequest = null
	if carry >= 0 and carry != own:
		load_req = ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": carry})
	for req: ActionRequest in ([load_req, march] if load_req != null else [march]):
		var why := Game.engine.actions.validate(req, Game.state)
		if why != "":
			Game.publish_news(why)
			return
	_set_aim("")
	if load_req != null:
		var out := Game.try_execute(load_req)   # its own courier; the march's news follows
		if not bool(out.get("ok", false)):
			Game.publish_news(String(out.get("error", "That order cannot be given.")))
			return
	_run(march)


## Add waypoint: the destination becomes the route's next waypoint and the
## aim goes on from it (owner 2026-10-07: 可以继续选择前进路线).
func _add_waypoint() -> void:
	if _aiming == "" or _pending.x < 0.0:
		return
	if String(_add_waypoint_row()["why"]) != "":
		Game.publish_news(String(_add_waypoint_row()["why"]))
		return
	_waypoints.append(_pending)
	_pending = Vector2(-1, -1)
	_map_set("aim_dest", Vector2(-1, -1))
	_map_set("aim_waypoints", PackedVector2Array(_waypoints))
	if _panel != null:
		_panel.hide()
	Game.publish_news("%s — click where the march goes next." % _name_of(_aiming))


## The map bent the pending route (a waypoint dragged or inserted): taken when
## every point is one the regiment could be sent to, else put back and why said.
func _on_route_bent(waypoints: PackedVector2Array) -> void:
	if _aiming == "" or _pending.x < 0.0:
		return
	var pairs: Array = []
	for w: Vector2 in waypoints:
		pairs.append([w.x, w.y])
	var why := Game.engine.actions.validate_place(ActionRequest.make("ARMY_MARCH",
		{"regiment": _aiming, "x": _pending.x, "y": _pending.y, "waypoints": pairs}), Game.state)
	if why != "":
		Game.publish_news(why)
		_map_set("aim_waypoints", PackedVector2Array(_waypoints))
		return
	_waypoints = Array(waypoints)
	if _panel != null and _panel.visible:
		var plan := _plan()
		_panel.refresh(plan["title"], plan["sub"], plan["rows"], _add_waypoint_row())


## An aim or a waiting confirm given up.
func _withdraw(news: String) -> void:
	if _aiming == "":
		return
	_set_aim("")
	Game.publish_news(news)


## Edit route…: the march's waypoints still ahead and its end loaded as the
## pending route, the panel opened where the route menu stood (ruling 10) — a
## draft's own, else the newest march courier's, else the column's.
func _edit_route(code: String) -> void:
	var dest := ArmySystem.destination_of(Game.data, Game.state, code)
	var wps: Array = Array(ArmySystem.waypoints_of(Game.data, Game.state, code))
	var draft := WarDrafts.of(Game.state, code) if drafting else {}
	var riding := CourierSystem.pending_for(Game.state, code)
	var order: Dictionary = riding.get("order", {}) if not riding.is_empty() else {}
	if String(draft.get("order", "")) == WarDrafts.MARCH:
		dest = WarDrafts.dest_px(Game.data, draft)
		wps = Array(WarDrafts.waypoints_px(Game.data, draft))
	elif String(order.get("action_code", "")) == "ARMY_MARCH":
		dest = ArmySystem.metres_to_pack(Game.data, Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"])))
		wps = CourierSystem.waypoints_px(Game.data, order)
	_set_aim(code)
	_waypoints = wps
	_pending = dest
	_map_set("aim_waypoints", PackedVector2Array(_waypoints))
	_map_set("aim_dest", dest)
	_open_confirm(_route_at)


## The supply rates closed with no row chosen (a click away): give the pick
## up. Deferred, because PopupMenu hides BEFORE it emits id_pressed. The
## march's confirm is the panel, which a click away leaves standing (ruling 7).
func _after_hide() -> void:
	if _supply_town != "" and not visible:   # the rates, closed with no row chosen
		_end_supply_pick()
		Game.publish_news("No supply point is chosen.")


## The clock started: no route is planned while time runs.
func _process(_delta: float) -> void:
	if _supply_for != "" and Game.clock_speed > 0:
		if visible:
			hide()
		_end_supply_pick()
		Game.publish_news("Time runs — the supply order is withdrawn.")
	if _aiming != "" and Game.clock_speed > 0:
		if visible:
			hide()
		_withdraw("Time runs — the march order is withdrawn.")


## Run an order and say what came of it in the news bar — a refusal has to be
## visible, or a greyed-out rule looks like a dead button.
func _run(req: ActionRequest) -> void:
	var out := Game.try_execute(req)
	if not bool(out.get("ok", false)):
		Game.publish_news(String(out.get("error", "That order cannot be given.")))
		return
	# A draft the order set aside is said even on a stopped clock (spec
	# 2026-10-02-war-room-v2 §3.1).
	var said: Dictionary = out.get("outcome", {})
	for e: Dictionary in said.get("effects", []):
		if String(e.get("metric", "")) == "war_draft":
			Game.publish_news(String(e["reason"]))
	# An order on a stopped clock waits for play (owner 2026-09-24) — and since
	# 2026-09-27 it rides by courier, who waits in the capital with it.
	if Game.clock_speed <= 0 and (req.action_code in ["ARMY_MARCH", "ARMY_GARRISON", "ARMY_STANCE"] \
			or req.action_code.begins_with("SUPPLY_")):
		var code := String(req.params["regiment"])
		if CourierSystem.carries_orders(ArmySystem.regiment(Game.data, code)):
			Game.publish_news("A courier will ride for %s when time runs." % _name_of(code))
			return
		if req.action_code == "ARMY_MARCH":
			Game.publish_news("%s will set out when time runs." % _name_of(code))
			return
	var outcome: Dictionary = out.get("outcome", {})
	for e: Dictionary in outcome.get("effects", []):
		if String(e.get("metric", "")) == "army":
			Game.publish_news(String(e["reason"]))
			return


func _set_aim(code: String) -> void:
	_pending = Vector2(-1, -1)
	_waypoints = []
	if _panel != null:
		_panel.hide()
	_map_set("aim_waypoints", PackedVector2Array())
	if _map != null and "aim_dest" in _map:
		_map.set("aim_dest", Vector2(-1, -1))
	if _aiming == code:
		return
	_aiming = code
	if _map != null and "aiming" in _map:
		_map.set("aiming", code != "")
	if _map != null and "aim_code" in _map:
		_map.set("aim_code", code)
	aiming_changed.emit(code)


func _name_of(code: String) -> String:
	return String(ArmySystem.regiment(Game.data, code).get("label", code))


## Escape gives an aimed order up — the player changed their mind and should
## not have to click the map to get out of it.
func _unhandled_input(event: InputEvent) -> void:
	# A map that is hidden (the WAR ROOM closed, the LEDGER over the map) never
	# takes Escape: only a map on screen lets its selection go.
	var map_shown := not (_map is CanvasItem) or (_map as CanvasItem).is_visible_in_tree()
	# a supply pick comes first: the selected regiment (a left click selects it
	# before its menu opens) must not swallow the Escape that gives the pick up
	if _supply_for != "" and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_end_supply_pick()
		Game.publish_news("The supply order is withdrawn.")
		get_viewport().set_input_as_handled()
		return
	if _aiming == "" and _map != null and map_shown and _map.has_method("selected_army") \
			and String(_map.call("selected_army")) != "" and event is InputEventKey \
			and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_map.call("clear_selection")   # Escape lets the selected regiment go
		get_viewport().set_input_as_handled()
		return
	if _aiming != "" and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_withdraw("The order is withdrawn.")
		get_viewport().set_input_as_handled()


## A right click on the ground while aiming (SpyOrderMenu hands it here,
## final review M14): the aim is given up, as Escape gives it up.
func withdraw_aim() -> void:
	if visible:
		hide()
	if _supply_for != "":
		_end_supply_pick()
		Game.publish_news("The supply order is withdrawn.")
	_withdraw("The order is withdrawn.")


## Arm a MARCH for `code` without the menu — the WAR ROOM's rake (spec
## 2026-10-01-war-room-design §3): the same questions MARCH… asks before it is
## offered. "" when armed, else why not (nothing is armed).
func aim_for(code: String) -> String:
	if Game.state == null:
		return "No reign is under way."
	var why := _refusal("ARMY_MARCH", code)
	if why != "":
		return why
	_code = code
	_set_aim(code)
	return ""


## The supply point pick (spec 2026-10-07-army-supply-lines §5.2): the map lights
## the towns the regiment may draw from, the next click names one, its rate is asked.
func _start_supply_pick(code: String) -> void:
	_set_aim("")
	_supply_for = code
	_supply_town = ""
	_map_set("supply_pick", SupplyLines.eligibility(Game.data, Game.state, code))
	_map_set("supply_preview", PackedVector2Array())
	if _map != null and "aiming" in _map:
		_map.set("aiming", true)   # the next left click only says where it landed
	Game.publish_news("%s — click a lit town to supply it from." % _name_of(code))


func _end_supply_pick() -> void:
	if _supply_for == "":
		return
	_supply_for = ""
	_supply_town = ""
	_map_set("supply_pick", {})
	_map_set("supply_preview", PackedVector2Array())
	if _map != null and "aiming" in _map:
		_map.set("aiming", _aiming != "")


func _map_set(prop: String, value: Variant) -> void:
	if _map != null and prop in _map:
		_map.set(prop, value)


## A click while picking: the realm town under it (ArmySystem.town_at), lit
## or greyed. A lit one asks its rate; a greyed one says why in the news bar.
func _on_supply_ground(pack_px: Vector2, at: Vector2) -> void:
	var town := ArmySystem.town_at(Game.data, pack_px)
	var pick: Dictionary = _map.get("supply_pick") if _map != null and "supply_pick" in _map else {}
	if town == "" or not pick.has(town):
		Game.publish_news("Click a lit town of the realm.")
		return
	if String(pick[town]) != "":
		Game.publish_news(String(pick[town]))
		return
	_supply_town = town
	var route := SupplyLines.road_px(Game.data, Game.state, _supply_for, town)
	_map_set("supply_preview", route)
	_open_rates(town, route, at)


## The rates of the chosen town, each row its gold a day and, on hover, what the
## road costs and how long the stores last.
func _open_rates(town: String, route: PackedVector2Array, at: Vector2) -> void:
	clear()
	var km := SupplyLines.road_km(Game.data, route)
	var reg := ArmySystem.regiment(Game.data, _supply_for)
	var use := ArmySystem.supply_use(Game.data, reg, Game.state)
	var row: Dictionary = Game.data.army_supply_orders.get("confirm", {"label": "{rate}× — {fee} gold a day", "hint": ""})
	# the road's length and its robbers (marks and hazards), read once on the pick
	var robbed := SupplySystem.road_loss(Game.data, Game.state, _supply_for, route)
	@warning_ignore("integer_division")
	var loss_pct := SupplySystem.total_loss(Game.data, km, int(robbed["permille"])) / 10
	for i in SupplyLines.RATES.size():
		var rate := int(SupplyLines.RATES[i])
		var fee := SupplyLines.gold_words(SupplyLines.day_fee_milli(Game.data, Game.state, _supply_for, town, rate, km))
		@warning_ignore("integer_division")  # the month's whole units
		var stock_days := TownStores.days_of_stock(Game.state, town, use * rate / 1000)
		add_item(String(row["label"]).format({"rate": "%.1f" % (float(rate) / 1000.0), "fee": fee}), RATE_BASE + i)
		set_item_tooltip(get_item_index(RATE_BASE + i), String(row["hint"]).format({
			"town": String(Game.data.burgs[town]["label"]), "km": km, "loss": loss_pct,
			"wagon_days": SupplyLines.wagon_days(Game.data, km), "stock_days": stock_days,
			"courier_days": CourierSystem.eta_days_to(Game.data, Game.state, CourierSystem.ORDINARY,
				Vector2(float(Game.data.burgs[town]["x"]), float(Game.data.burgs[town]["y"])))}))
	_add_row("cancel", CANCEL, "")
	_pop(at)


func _send_supply(rate: int) -> void:
	if _supply_for == "" or _supply_town == "":
		return
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": _supply_for, "town": _supply_town, "rate": rate})
	_end_supply_pick()
	_run(req)


## Test seam: the regiment whose supply point is being picked, "" when none.
func supply_picking() -> String:
	return _supply_for


## Test seam: the town clicked while its rate is asked, "" when none.
func supply_town() -> String:
	return _supply_town


## Test seam: the regiment an order is being aimed for, "" when none is.
func aiming() -> String:
	return _aiming


## Test seam: the destination waiting for Confirm, Vector2(-1, -1) when none.
func pending() -> Vector2:
	return _pending


## Test seam: the pending route's waypoints, pack px.
func waypoints() -> Array:
	return _waypoints


## The confirm panel when it is up, else null (tests and the snapshot tool).
func shown_confirm() -> MarchConfirmPanel:
	return _panel if _panel != null and _panel.visible else null
