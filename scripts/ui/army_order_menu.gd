class_name ArmyOrderMenu
extends PopupMenu
## A regiment's orders on the right mouse button (owner 2026-09-22: "鼠标右
## 键点击会有移动和驻防的选项激活动作"). Its rows are data — data/army_orders.csv,
## in the order they are shown — so renaming or reordering them touches no code.
##
## MARCH is AIMED, not issued by the menu: choosing it arms the map, the next
## left click on the ground is the destination, and the same menu then asks
## COMMIT or CANCEL there, the route drawn to it (owner 2026-09-27) — only a
## commit sends the order. That is why its label ends in an ellipsis.
## GARRISON runs at once. Escape or a click away from the confirm gives it up.
## A committed march's end ring opens the ROUTE menu: Edit route… aims it
## anew, Cancel march halts it (an ARMY_GARRISON).
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

## The confirm and route menus' ids, after the order rows'.
const COMMIT := 100
const CANCEL := 101
const EDIT := 200
const HALT := 201

var _map: Node = null
var _code := ""
var _aiming := ""
## The aimed march's destination (pack px) while COMMIT / CANCEL is asked;
## Vector2(-1, -1) when none waits.
var _pending := Vector2(-1, -1)


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
	popup_hide.connect(func() -> void: _after_hide.call_deferred())


## Open over the regiment `code`. Each row is offered only when the engine
## would actually take it: the menu never shows an order that ActionSystem
## is about to refuse.
func _open_for(code: String, at: Vector2) -> void:
	if Game.state == null:
		return
	_set_aim("")
	_code = code
	clear()
	for i in Game.data.army_orders.size():
		var row: Dictionary = Game.data.army_orders[i]
		add_item(String(row["label"]), i)
		var why := _refusal(String(row["action_code"]), code)
		set_item_disabled(i, why != "")
		set_item_tooltip(i, why if why != "" else String(row["hint"]))
	if item_count == 0:
		return
	_pop(at)


## A committed march's end ring was clicked: Edit route… or Cancel march.
func _open_route(code: String, at: Vector2) -> void:
	if Game.state == null or ArmySystem.order_of(Game.data, Game.state, code) != ArmySystem.ORDER_MARCH:
		return
	_set_aim("")
	_code = code
	clear()
	_add_row("edit", EDIT, _paused_reason())
	_add_row("halt", HALT, _paused_reason() if _paused_reason() != "" \
		else _refusal("ARMY_GARRISON", code))
	_pop(at)


## The destination was clicked: ask COMMIT or CANCEL there.
func _open_confirm(at: Vector2) -> void:
	clear()
	_add_row("commit", COMMIT, "")
	_add_row("cancel", CANCEL, "")
	_pop(at)


func _add_row(key: String, id: int, why: String) -> void:
	var row: Dictionary = Game.data.army_route_orders.get(key, {"label": key, "hint": ""})
	add_item(String(row["label"]), id)
	var i := get_item_index(id)
	set_item_disabled(i, why != "")
	set_item_tooltip(i, why if why != "" else String(row["hint"]))


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
func _refusal(action_code: String, code: String) -> String:
	if action_code == "ARMY_MARCH" and _paused_reason() != "":
		return _paused_reason()
	var req := ActionRequest.make(action_code, {"regiment": code})
	if action_code == "ARMY_MARCH":
		var here := ArmySystem.position_of(Game.data, Game.state,
			ArmySystem.regiment(Game.data, code))
		req.params["x"] = here.x
		req.params["y"] = here.y + 1.0   # anywhere but here, so "already there" is not the answer
	var err := Game.engine.actions.validate(req, Game.state)
	# The one refusal a MARCH cannot answer yet is about the ground it has not
	# been aimed at; everything else is a real reason to grey the row out.
	if action_code == "ARMY_MARCH" and (err.contains("into the sea") or err.contains("off the map")):
		return ""
	return err


func _on_chosen(id: int) -> void:
	match id:
		COMMIT:
			_commit()
			return
		CANCEL:
			_withdraw("The march is given up.")
			return
		EDIT:
			if _code != "" and _paused_reason() == "":
				_set_aim(_code)
				Game.publish_news("%s awaits a new route — click where to send it." % _name_of(_code))
			return
		HALT:
			if _code != "":
				_run(ActionRequest.make("ARMY_GARRISON", {"regiment": _code}))
			return
	if _code == "" or id < 0 or id >= Game.data.army_orders.size():
		return
	var row: Dictionary = Game.data.army_orders[id]
	if String(row["action_code"]) == "ARMY_MARCH":
		_set_aim(_code)
		Game.publish_news("%s awaits its orders — click where to send it." % _name_of(_code))
		return
	_run(ActionRequest.make(String(row["action_code"]), {"regiment": _code}))


## The aimed march's destination: held, drawn to, and asked about — the
## order goes in only on COMMIT.
func _on_ground(pack_px: Vector2) -> void:
	if _aiming == "" or _pending.x >= 0.0:
		return
	_pending = pack_px
	if _map != null and "aim_dest" in _map:
		_map.set("aim_dest", pack_px)
	var at := Vector2.ZERO
	if _map is Control:
		at = (_map as Control).get_local_mouse_position()
	_open_confirm(at)


func _commit() -> void:
	if _aiming == "" or _pending.x < 0.0:
		return
	var code := _aiming
	var to := _pending
	_set_aim("")
	_run(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": to.x, "y": to.y}))


## An aim or a waiting confirm given up.
func _withdraw(news: String) -> void:
	if _aiming == "":
		return
	_set_aim("")
	Game.publish_news(news)


## The confirm closed without COMMIT (a click away from it): give it up.
## Deferred, because PopupMenu hides BEFORE it emits id_pressed.
func _after_hide() -> void:
	if _pending.x >= 0.0 and not visible:
		_withdraw("The march is given up.")


## The clock started: no route is planned while time runs.
func _process(_delta: float) -> void:
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
	# An order on a stopped clock waits for play (owner 2026-09-24: 兵棋不进行
	# 移动，直到玩家点击继续游戏按钮) — the clock is never started for the player.
	if req.action_code == "ARMY_MARCH" and Game.clock_speed <= 0:
		Game.publish_news("%s will set out when time runs." % _name_of(String(req.params["regiment"])))
		return
	var outcome: Dictionary = out.get("outcome", {})
	for e: Dictionary in outcome.get("effects", []):
		if String(e.get("metric", "")) == "army":
			Game.publish_news(String(e["reason"]))
			return


func _set_aim(code: String) -> void:
	_pending = Vector2(-1, -1)
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
	if _aiming == "" and _map != null and _map.has_method("selected_army") \
			and String(_map.call("selected_army")) != "" and event is InputEventKey \
			and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_map.call("clear_selection")   # Escape lets the selected regiment go
		get_viewport().set_input_as_handled()
		return
	if _aiming != "" and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_withdraw("The order is withdrawn.")
		get_viewport().set_input_as_handled()


## Test seam: the regiment an order is being aimed for, "" when none is.
func aiming() -> String:
	return _aiming


## Test seam: the destination waiting for COMMIT, Vector2(-1, -1) when none.
func pending() -> Vector2:
	return _pending
