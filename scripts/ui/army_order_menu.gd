class_name ArmyOrderMenu
extends PopupMenu
## A regiment's orders on the right mouse button (owner 2026-09-22: "鼠标右
## 键点击会有移动和驻防的选项激活动作"). Its rows are data — data/army_orders.csv,
## in the order they are shown — so renaming or reordering them touches no code.
##
## MARCH is AIMED, not issued by the menu: choosing it arms the map, the next
## left click on the ground is the destination, and only then does the order
## go in. That is why its label ends in an ellipsis. GARRISON runs at once.
## A right click, Escape or a click off the land gives the aim up.
##
## Every order goes through Game.try_execute, exactly as the manor card's
## buttons do — so ActionSystem validates it, OrderCosts charges it and the
## opinion signature applies. A map order is not a back door into the state.

## The regiment waiting for a destination click, "" when none is. The map
## reads this to stop a left click also opening the card of whatever it
## landed on.
signal aiming_changed(regiment_code: String)

var _map: Node = null
var _code := ""
var _aiming := ""


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
	var origin := Vector2.ZERO
	if _map is Control:
		origin = (_map as Control).get_global_rect().position
	popup_on_parent(Rect2i(Vector2i((origin + at).round()), Vector2i(1, 1)))


## Why the engine would refuse this order, "" when it would take it. MARCH is
## asked about a destination it has not been given yet, so it is asked
## without one — the questions that do not need a destination (is it mine,
## has it anyone under arms, can the chest pay) are the ones worth asking
## before the player aims.
func _refusal(action_code: String, code: String) -> String:
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
	if _code == "" or id < 0 or id >= Game.data.army_orders.size():
		return
	var row: Dictionary = Game.data.army_orders[id]
	if String(row["action_code"]) == "ARMY_MARCH":
		_set_aim(_code)
		Game.publish_news("%s awaits its orders — click where to send it." % _name_of(_code))
		return
	_run(ActionRequest.make(String(row["action_code"]), {"regiment": _code}))


## The aimed march's destination.
func _on_ground(pack_px: Vector2) -> void:
	if _aiming == "":
		return
	var code := _aiming
	_set_aim("")
	_run(ActionRequest.make("ARMY_MARCH",
		{"regiment": code, "x": pack_px.x, "y": pack_px.y}))


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
		_set_aim("")
		Game.publish_news("The order is withdrawn.")
		get_viewport().set_input_as_handled()


## Test seam: the regiment an order is being aimed for, "" when none is.
func aiming() -> String:
	return _aiming
