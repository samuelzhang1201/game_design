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
## The confirm also asks where to SUPPLY the march from (spec 2026-10-08-war-
## room-draw-orders ruling 13): the towns that reach the column now and the
## march's end are lit on the map (`supply_pick`), the chosen one's road to the
## end drawn (`supply_preview`); Confirm sends the supply point, the load and
## the march, each its own courier. In the WAR ROOM there is no regiment menu:
## a blue arrow drawn for the selected regiments hands their routes in
## (`plan_group`) and the confirm lists each.
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
## The supply rows (spec 2026-10-07-army-supply-lines §5.1): Add / Change
## supply point…, Withdraw supply point, and the confirm's rates (RATE_BASE +
## the index in SupplyLines.RATES). The load is asked on the march's confirm
## (owner 2026-10-07: 右键点击军队时，不要显示携带多少补给).
const SUPPLY_ADD := 400
const SUPPLY_WITHDRAW := 401
const RATE_BASE := 420
## The seat row (spec 2026-10-07-army-split-and-ground §4.5): Take the seat /
## Garrison the town, for a unit camped by a town of the realm.
const SEAT := 500

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
## The units this menu's orders go to (spec 2026-10-07-army-split-and-ground
## §5.6): the map's selection when `_code` is in it, else [_code].
var _codes: Array = []
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
## The regiment whose supply point is being picked, "" when none; and the
## town clicked, whose rate the confirm asks.
var _supply_for := ""
var _supply_town := ""
## A march drawn for several regiments (the WAR ROOM, plan_group): every one
## in the selection's order, each one's waypoints (the lead's are _waypoints),
## why each is left out ("" it marches) and the ones the player unticked.
var _group: Array = []
var _group_wps: Dictionary = {}
var _group_why: Dictionary = {}
var _group_off: Dictionary = {}
## The supply town chosen on the confirm ("" no new point) and every realm
## town's answer for this march (town -> "" or why not).
var _supply_choice := ""
var _supply_set := false   # the player chose the supply town (the list or a lit town): kept on a re-open
var _supply_ok: Dictionary = {}


func _ready() -> void:
	# _code is NOT cleared on popup_hide: PopupMenu.activate_item hides the
	# menu BEFORE it emits id_pressed, so clearing it there threw every chosen
	# order away (2026-09-24: 兵棋的操作我并没有看到实现). _open_for sets it anew.
	id_pressed.connect(_on_chosen)


## Follow a map — either map, by signal name, as MapDetailPanel.follow does.
func follow(map: Node) -> void:
	_map = map
	if map.has_signal("army_menu_requested"):
		map.connect("army_menu_requested", _open_for)
	map.connect("ground_clicked", _on_ground)
	if map.has_signal("route_clicked"):
		map.connect("route_clicked", _open_route)
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
	# the war room's drafts are one piece's each
	_codes = [code] if drafting else _selected_with(code)
	clear()
	for i in Game.data.army_orders.size():
		var row: Dictionary = Game.data.army_orders[i]
		# a battle stance is the map's order: the war room drafts only marches
		if drafting and String(row["action_code"]) != "ARMY_MARCH":
			continue
		add_item(String(row["label"]), i)
		var why := _refusal_any(String(row["action_code"]), row.get("params", {}))
		set_item_disabled(i, why != "")
		set_item_tooltip(i, why if why != "" else String(row["hint"]))
	# the seat (spec 2026-10-07-army-split-and-ground §4.5): only a unit camped
	# by a town of the realm and not inside it; the map's orders, never a draft
	if not drafting:
		var town := ArmyGround.camped_by(Game.data, Game.state, code)
		if town != "" and ArmyGround.seat_of(Game.data, Game.state, town) != code:
			var empty := ArmyGround.seat_of(Game.data, Game.state, town) == ""
			_add_row("seat_empty" if empty else "seat", SEAT, _refusal("ARMY_SEAT", code))
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
	var reg := ArmySystem.regiment(Game.data, code, Game.state)
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
	_codes = [code]
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
	var carry := ArmySystem.carry_of(Game.data, ArmySystem.state_of(Game.data, Game.state, _aiming))
	if drafting:
		var d := WarDrafts.of(Game.state, _aiming)
		carry = int(d.get("carry_days", carry))
	p.set_meta("carry", carry)
	var plan := _plan()
	var commit := _route_row("commit_draft" if drafting else _row_key("commit", _aiming))
	p.show_plan(plan["title"], plan["sub"], plan["rows"], carry if not (plan["rows"] as Array).is_empty() else -1,
		commit, _add_waypoint_row(), _route_row("cancel"))
	p.set_add_shown(not drafting)   # the room draws its route (ruling 9)
	p.show_group(_group_rows())
	_open_supply()
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
	var pts: Array = [ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, _aiming, Game.state))]
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
		_panel.carry_changed.connect(func(_d: int) -> void: _panel.show_group(_group_rows()))
		_panel.regiment_toggled.connect(_on_regiment_toggled)
		_panel.supply_chosen.connect(_choose_supply)
	return _panel


## The pending route's title, sub line and load rows (MarchPlan) — a fleet,
## which carries no train, has no rows and says its days in the sub line.
func _plan() -> Dictionary:
	var code := _aiming
	var reg := ArmySystem.regiment(Game.data, code, Game.state)
	var naval := String(reg.get("is_naval", "0")) == "1"
	var rows := [] if naval else MarchPlan.carry_rows(Game.data, Game.state, code, _pending, _waypoints)
	var many := _marching()
	if many.size() > 1:
		var per := {}
		for c: String in many:
			per[c] = MarchPlan.carry_rows(Game.data, Game.state, c, _pending, _wps_of(c))
		rows = MarchPlan.group_rows(per)
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
	var who := _name_of(code) if many.size() <= 1 else "%d units" % many.size()
	return {"title": "%s to %s" % [who, Intel.place_label(Game.data, Game.state, _pending)],
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
	var reg := ArmySystem.regiment(Game.data, code, Game.state)
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
			ArmySystem.regiment(Game.data, code, Game.state))
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
	if id >= RATE_BASE and id < RATE_BASE + SupplyLines.RATES.size():
		_send_supply(int(SupplyLines.RATES[id - RATE_BASE]))
		return
	if id == SUPPLY_ADD:
		if _code != "" and _paused_reason() == "":
			_start_supply_pick(_code)
		return
	if id == SUPPLY_WITHDRAW:
		if _code != "" and _paused_reason() == "":
			_run_each("SUPPLY_POINT_CLEAR", {})
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
		SEAT:
			if _code != "":
				_run(ActionRequest.make("ARMY_SEAT", {"regiment": _code}))
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
	# a stance row's params (the stance) ride with each unit (ARMY_STANCE)
	_run_each(String(row["action_code"]), row.get("params", {}))


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
	if _aiming != "" and _pending.x >= 0.0 and not _supply_ok.is_empty():
		_on_supply_click(pack_px)   # the confirm stands: a lit town is chosen to supply the march
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
	var town := _supply_choice
	if drafting:
		# a draft costs nothing yet, but no seal could ever send one into the sea
		var why := Game.engine.actions.validate_place(march, Game.state)
		if why != "":
			Game.publish_news(why)
			return
		var many := _marching()
		var dests := {}
		for c: String in many:
			dests[c] = _wps_of(c).duplicate()
		_set_aim("")
		for c: String in many:
			var mine := ArmySystem.carry_of(Game.data, ArmySystem.state_of(Game.data, Game.state, c))
			Game.plant_draft(c, WarDrafts.MARCH, to, dests[c], carry if carry >= 0 and carry != mine else -1,
				town if town != String(SupplyLines.line(Game.state, c).get("town", "")) else "", _rate_of(c))
		Game.publish_news("%s's march is pencilled in." % _name_of(code) if many.size() <= 1 \
			else "The march of %d units is pencilled in." % many.size())
		return
	# one destination for the whole selection (spec 2026-10-07-army-split-and-
	# ground §5.6): each unit its own supply point, load and march, judged alone
	var sends: Array = []
	var refused: Array = []
	for c: String in ([code] + _marching().filter(func(x: String) -> bool: return x != code)):
		var reqs := _march_reqs(c, to, pairs, carry, town)
		var why := ""
		for req: ActionRequest in reqs:
			why = Game.engine.actions.validate(req, Game.state)
			if why != "":
				break
		if why == "":
			sends.append(reqs)
		else:
			refused.append(why if refused.is_empty() and sends.is_empty() and c == code
				else "%s: %s" % [_name_of(c), why])
	if sends.is_empty():
		Game.publish_news(String(refused[0]))   # the route stays up to be mended
		return
	_set_aim("")
	for why: String in refused:
		Game.publish_news(why)
	for reqs: Array in sends:
		var ok := true
		for req: ActionRequest in reqs.slice(0, reqs.size() - 1):
			var out := Game.try_execute(req)   # its own courier; the march's news follows
			if not bool(out.get("ok", false)):
				Game.publish_news(String(out.get("error", "That order cannot be given.")))
				ok = false
				break
		if ok:
			_run(reqs.back())


## A unit's Confirm: SUPPLY_POINT_SET when `town` is not its line's already
## (spec 2026-10-08-war-room-draw-orders ruling 15), SUPPLY_CARRY_SET when
## `carry` changes its load, then ARMY_MARCH to `to` through `pairs`
## (waypoints as [x, y]).
func _march_reqs(c: String, to: Vector2, pairs: Array, carry: int, town := "") -> Array:
	var params := {"regiment": c, "x": to.x, "y": to.y}
	if not pairs.is_empty():
		params["waypoints"] = pairs.duplicate(true)
	var out: Array = []
	if town != "" and town != String(SupplyLines.line(Game.state, c).get("town", "")):
		out.append(ActionRequest.make("SUPPLY_POINT_SET", {"regiment": c, "town": town, "rate": _rate_of(c)}))
	if carry >= 0 and carry != ArmySystem.carry_of(Game.data, ArmySystem.state_of(Game.data, Game.state, c)):
		out.append(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": c, "days": carry}))
	out.append(ActionRequest.make("ARMY_MARCH", params))
	return out


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
	if _group.size() > 1:
		# the others join the bent path where they stand nearest (WarOrderSketch)
		var path := PackedVector2Array(_waypoints)
		path.append(_pending)
		for c: String in _group:
			if c != _aiming:
				_group_wps[c] = WarOrderSketch.route_for(Game.data, _pos_of(c), path)
		_push_group()
	if _panel != null and _panel.visible:
		var plan := _plan()
		_panel.refresh(plan["title"], plan["sub"], plan["rows"], _add_waypoint_row())
		_panel.show_group(_group_rows())
		_open_supply()   # the end moved: the wagons' reach to it is read again


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


## The units this menu's orders go to: the map's selection when the unit the
## menu opened over is in it (spec 2026-10-07-army-split-and-ground §5.6),
## else that unit alone.
func _selected_with(code: String) -> Array:
	if _map != null and _map.has_method("selected_armies"):
		var sel: Array = _map.call("selected_armies")
		if sel.has(code):
			return sel.duplicate()
	return [code]


## Test seam: the units the open menu orders.
func selected_codes() -> Array:
	return _codes


## "" when any of the units would take the order (with the row's `params`,
## a stance's), else the first refusal.
func _refusal_any(action_code: String, params: Dictionary = {}) -> String:
	var first := ""
	for c: String in _codes:
		var why := _refusal(action_code, c, params)
		if why == "":
			return ""
		if first == "":
			first = why
	return first


## Run an order for every unit in the menu's charge, each judged alone: its
## own action, courier and charge, and a refusal said aloud while the rest ride.
func _run_each(action_code: String, extra: Dictionary) -> void:
	for c: String in _codes:
		var params := extra.duplicate()
		params["regiment"] = c
		_run(ActionRequest.make(action_code, params))


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
	if Game.clock_speed <= 0 and (req.action_code in ["ARMY_MARCH", "ARMY_GARRISON", "ARMY_STANCE", "ARMY_SEAT"] \
			or req.action_code.begins_with("SUPPLY_")):
		var code := String(req.params["regiment"])
		if CourierSystem.carries_orders(ArmySystem.regiment(Game.data, code, Game.state)):
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
	_group = []
	_group_wps = {}
	_group_why = {}
	_group_off = {}
	_supply_set = false
	if not _supply_ok.is_empty() or _supply_choice != "":
		_supply_ok = {}
		_supply_choice = ""
		_map_set("supply_pick", {})
		_map_set("supply_preview", PackedVector2Array())
	if _panel != null:
		_panel.hide()
	_map_set("aim_waypoints", PackedVector2Array())
	_map_set("aim_group", {})
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
	return String(ArmySystem.regiment(Game.data, code, Game.state).get("label", code))


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
	_codes = [code]
	_set_aim(code)
	return ""


## The supply point pick (spec 2026-10-07-army-supply-lines §5.2): the map lights
## the towns the regiment may draw from, the next click names one, its rate is asked.
func _start_supply_pick(code: String) -> void:
	_set_aim("")
	_supply_for = code
	_supply_town = ""
	var pick := SupplyLines.eligibility(Game.data, Game.state, code)
	SupplyLines.mark_ahead(Game.data, Game.state, code, pick)   # never a town on the frontier side (ruling 20)
	_map_set("supply_pick", pick)
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
	var reg := ArmySystem.regiment(Game.data, _supply_for, Game.state)
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
	var town := _supply_town
	_end_supply_pick()
	_run_each("SUPPLY_POINT_SET", {"town": town, "rate": rate})


## A blue arrow drawn in the WAR ROOM for the selected regiments (spec
## 2026-10-08-war-room-draw-orders rulings 6-9): `routes` code -> its
## waypoints (pack px, the drawn path joined where it stands nearest), `dest`
## the arrow's tip. Each is asked what MARCH… asks; a waypoint it cannot be
## sent to is dropped (the news says so), a refused end leaves it out with its
## reason. The confirm opens beside `at` (the view's px) with every one's
## figures, the first that may march leading. "" when it opened, else why not.
func plan_group(codes: Array, routes: Dictionary, dest: Vector2, at: Vector2) -> String:
	if Game.state == null:
		return "No reign is under way."
	_end_supply_pick()
	var why := {}
	var wps := {}
	var ok: Array = []
	var first := ""
	for c: Variant in codes:
		var code := String(c)
		var w := _refusal("ARMY_MARCH", code)
		var route: Array = (routes.get(code, []) as Array).duplicate()
		if w == "":
			var fit := _fit_route(code, dest, route)
			route = fit["wps"]
			w = String(fit["why"])
		why[code] = w
		wps[code] = route
		if w == "":
			ok.append(code)
		elif first == "":
			first = w
	if ok.is_empty():
		return first
	var lead := String(ok[0])
	_code = lead
	_set_aim(lead)
	_group = codes.map(func(c: Variant) -> String: return String(c))
	_group_wps = wps
	_group_why = why
	_waypoints = Array(wps[lead])
	_pending = dest
	_map_set("aim_waypoints", PackedVector2Array(_waypoints))
	_map_set("aim_dest", dest)
	_push_group()
	_open_confirm(at)
	return ""


## A drawn route checked as the map checks one: {wps, why} — the waypoints a
## regiment cannot be sent to dropped (said once), "" when the end is good.
func _fit_route(code: String, dest: Vector2, route: Array) -> Dictionary:
	var why := _place_why(code, dest, route)
	if why == "":
		return {"wps": route, "why": ""}
	var end_why := _place_why(code, dest, [])
	if end_why != "":
		return {"wps": route, "why": end_why}
	var kept: Array = route.filter(func(w: Vector2) -> bool: return _place_why(code, w, []) == "")
	why = _place_why(code, dest, kept)
	if why == "" and kept.size() < route.size():
		var n := route.size() - kept.size()
		Game.publish_news("%s: %d waypoint%s it cannot be sent to left out." % [_name_of(code), n, "" if n == 1 else "s"])
	return {"wps": kept, "why": why}


func _place_why(code: String, to: Vector2, wps: Array) -> String:
	var params := {"regiment": code, "x": to.x, "y": to.y}
	if not wps.is_empty():
		params["waypoints"] = wps.map(func(w: Vector2) -> Array: return [w.x, w.y])
	return Game.engine.actions.validate_place(ActionRequest.make("ARMY_MARCH", params), Game.state)


## Where a regiment stands as the map shows it.
func _pos_of(code: String) -> Vector2:
	if _map != null and _map.has_method("position_of"):
		return _map.call("position_of", code)
	return ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))


## The units the pending march sends: a drawn group's ticked, unrefused ones;
## else the map's selection holding the one aimed (one order rides to each,
## spec 2026-10-07-army-split-and-ground §5.6); else the one aimed.
func _marching() -> Array:
	if _group.is_empty():
		if _aiming != "" and _codes.has(_aiming):
			return _codes.duplicate()
		return [_aiming] if _aiming != "" else []
	return _group.filter(func(c: String) -> bool: return String(_group_why.get(c, "")) == "" and not _group_off.has(c))


## A marching unit's waypoints: the lead's (and, on the map, every selected
## unit's: one route for all) are the pending ones, a drawn group's its own.
func _wps_of(code: String) -> Array:
	return _waypoints if code == _aiming or _group.is_empty() else Array(_group_wps.get(code, []))


## The other marching regiments' routes onto the map (it draws them).
func _push_group() -> void:
	var g := {}
	for c: String in _marching():
		if c != _aiming:
			g[c] = PackedVector2Array(_wps_of(c))
	_map_set("aim_group", g)


## The confirm's regiment rows: each one's arrival and supplies at the load
## pressed, or why it is left out.
func _group_rows() -> Array:
	if _group.size() <= 1 or _panel == null:
		return []
	var carry := _panel.chosen_carry()
	var out: Array = []
	for c: String in _group:
		var row := {"code": c, "label": _name_of(c), "why": String(_group_why.get(c, "")), "on": not _group_off.has(c)}
		if row["why"] == "":
			for r: Dictionary in MarchPlan.carry_rows(Game.data, Game.state, c, _pending, _wps_of(c)):
				if int(r["days"]) == carry:
					var arrive := int(r["arrive"])
					row["line"] = "%d day%s · %s supplies" % [arrive, "" if arrive == 1 else "s", UiPalette.format_int(int(r["units"]))]
					var short := int(r["short"])
					row["short"] = "runs %d day%s short" % [short, "" if short == 1 else "s"] if short > 0 else ""
		out.append(row)
	return out


func _on_regiment_toggled(code: String, on: bool) -> void:
	if on:
		_group_off.erase(code)
	else:
		_group_off[code] = true
	if _marching().is_empty():
		_group_off.erase(code)   # one at least marches: the last tick stays
		_panel.show_group(_group_rows())
		return
	if not code in _marching() and code == _aiming:
		# the lead left out: the next one leads, its route the bent one's
		var next := String(_marching()[0])
		_group_wps[_aiming] = _waypoints
		_aiming = next
		_waypoints = Array(_group_wps.get(next, []))
		_map_set("aim_code", next)
		_map_set("aim_waypoints", PackedVector2Array(_waypoints))
	_push_group()
	var plan := _plan()
	_panel.refresh(plan["title"], plan["sub"], plan["rows"], _add_waypoint_row())
	_panel.show_group(_group_rows())
	_open_supply()


## The supply point a march's confirm asks for (ruling 13): the towns that
## reach every marching regiment now and the march's end, none AHEAD of any
## of them (ruling 20), lit on the map; the current town (or none) first, then
## the rest nearest the lead's column first (SupplyLines.rear_order). Pressed:
## the player's own choice, else a draft's town, else the current town when it
## may still serve, else the nearest town allowed — never one ahead.
func _open_supply() -> void:
	if _panel == null:
		return
	var many := _marching()
	_supply_ok = {}
	var land := not many.is_empty() and many.all(func(c: String) -> bool:
		var reg := ArmySystem.regiment(Game.data, c, Game.state)
		return String(reg.get("is_naval", "0")) != "1" and String(reg["kingdom_code"]) == Game.data.resolve_realm("player_realm"))
	if not land:
		_panel.show_supply([], "", "")
		_map_set("supply_pick", {})
		_map_set("supply_preview", PackedVector2Array())
		return
	for c: String in many:
		var e := SupplyLines.march_eligibility(Game.data, Game.state, c, _pending)
		for t: String in e:
			if not _supply_ok.has(t) or (String(_supply_ok[t]) == "" and String(e[t]) != ""):
				_supply_ok[t] = e[t]
	var lead := String(many[0])
	var now := String(SupplyLines.line(Game.state, lead).get("town", ""))
	var rows: Dictionary = Game.data.army_supply_orders
	var first := {"town": "", "label": String(rows.get("march_none", {}).get("label", "No supply point")), "why": ""}
	var keep := true   # the current town may go on serving: not ahead of any column
	if now != "":
		first["label"] = String(rows.get("march_keep", {}).get("label", "{town} (now)")).format(
			{"town": String(Game.data.burgs.get(now, {}).get("label", now))})
		for c: String in many:
			var ahead := SupplyLines.mark_ahead(Game.data, Game.state, c, {now: ""})
			if String(ahead[now]) != "":
				first["why"] = ahead[now]
				keep = false
				break
	var towns: Array = _rear_order(lead).filter(func(t: String) -> bool: return t != now)
	var options: Array = [first]
	for t: String in towns:
		options.append({"town": t, "label": String(Game.data.burgs[t].get("label", t)), "why": String(_supply_ok[t])})
	if not _supply_set:
		_supply_choice = String(WarDrafts.of(Game.state, lead).get("supply_town", "")) if drafting else ""
		if _supply_choice == "" and not (now != "" and keep):
			for t: String in towns:   # the nearest town on our side
				if String(_supply_ok[t]) == "":
					_supply_choice = t
					break
	if _supply_choice != "" and String(_supply_ok.get(_supply_choice, "x")) != "":
		_supply_choice = ""
	_panel.show_supply(options, _supply_choice, _supply_words(_supply_choice))
	_map_set("supply_pick", _supply_ok)
	_map_set("supply_preview", SupplyLines.road_between_px(Game.data, _supply_choice, _pending) if _supply_choice != "" else PackedVector2Array())


var _rear_cache: Dictionary = {}


## The towns in the list's order for the lead's column where it stands
## (SupplyLines.rear_order; the roads measured once a place).
func _rear_order(lead: String) -> Array:
	var at := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, lead, Game.state))
	var key := [lead, at, _supply_ok.hash()]
	if not _rear_cache.has(key):
		if _rear_cache.size() > 32:
			_rear_cache.clear()
		_rear_cache[key] = SupplyLines.rear_order(Game.data, Game.state, lead, _supply_ok)
	return _rear_cache[key]


func _choose_supply(town: String) -> void:
	_supply_choice = town
	_supply_set = true
	_map_set("supply_preview", SupplyLines.road_between_px(Game.data, town, _pending) if town != "" else PackedVector2Array())
	if _panel != null:
		_panel.set_supply_figures(_supply_words(town))


## A click on the map while the confirm stands: the realm town there is chosen
## when it may supply the march, else the news says why.
func _on_supply_click(pack_px: Vector2) -> void:
	var town := ArmySystem.town_at(Game.data, pack_px)
	if town == "" or not _supply_ok.has(town):
		return
	if String(_supply_ok[town]) != "":
		Game.publish_news(String(_supply_ok[town]))
		return
	if _panel != null:
		_panel.select_supply(town)


## The rate a new supply point runs at: the line's own, else supply_rate_default.
func _rate_of(code: String) -> int:
	var line := SupplyLines.line(Game.state, code)
	return int(line.get("rate", Game.data.bal("supply_rate_default"))) if not line.is_empty() \
		else int(Game.data.bal("supply_rate_default"))


## The figures of supplying the march from `town`: the road from it to the
## march's end, wagon days, the share lost on it, the gold a day.
func _supply_words(town: String) -> String:
	if town == "" or not Game.data.burgs.has(town):
		return ""
	var route := SupplyLines.road_between_px(Game.data, town, _pending)
	var km := SupplyLines.road_km(Game.data, route)
	var many := _marching()
	var robbed := SupplySystem.road_loss(Game.data, Game.state, String(many[0]), route) if not many.is_empty() else {"permille": 0}
	@warning_ignore("integer_division")
	var loss := SupplySystem.total_loss(Game.data, km, int(robbed["permille"])) / 10
	var fee := 0
	for c: String in many:
		fee += SupplyLines.day_fee_milli(Game.data, Game.state, c, town, _rate_of(c), km)
	var row: Dictionary = Game.data.army_supply_orders.get("march_figures", {})
	var wd := SupplyLines.wagon_days(Game.data, km)
	return String(row.get("label", "{km} km · wagons {wagon_days} · {loss}% lost · {fee} gold a day")).format({
		"km": km, "wagon_days": "%d day%s" % [wd, "" if wd == 1 else "s"], "loss": loss, "fee": SupplyLines.gold_words(fee)})


## Test seam: the supply town chosen on the confirm, "" none.
func supply_choice() -> String:
	return _supply_choice


## Test seam: the regiments the pending march sends.
func marching() -> Array:
	return _marching()


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
