class_name KingOrderMenu
extends PopupMenu
## Dynamic royal orders; the scene owns the popup's permanent appearance.

var _map: Map3DView
var _army: ArmyOrderMenu
var _spy: SpyOrderMenu
var _rows: Array[Dictionary] = []
var _mode := ""
var _pending: Dictionary = {}
var _at := Vector2.ZERO

func _ready() -> void:
	id_pressed.connect(_chosen)

func follow(view: Map3DView, army: ArmyOrderMenu, spy: SpyOrderMenu) -> void:
	_map = view
	_army = army
	_spy = spy
	view.connect("king_menu_requested", _open)
	view.ground_clicked.connect(_ground)
	view.ground_menu_requested.connect(func(_point: Vector2, _screen: Vector2) -> void: cancel())
	view.army_menu_requested.connect(func(_code: String, _screen: Vector2) -> void: cancel())
	if army != null:
		army.aiming_changed.connect(func(code: String) -> void:
			if code != "": cancel(false))

func _process(_delta: float) -> void:
	if Game.clock_speed > 0 and (_mode != "" or String(_pending.get("action", "")) == "KING_MOVE"):
		cancel()

func _unhandled_input(event: InputEvent) -> void:
	if _mode != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()

func cancel(clear_map: bool = true) -> void:
	if clear_map and _map != null and _mode != "":
		_map.aiming = false
	_mode = ""
	_pending = {}
	hide()

func _open(at: Vector2) -> void:
	if Game.state == null: return
	cancel()
	if _army != null: _army.withdraw_aim()
	if _spy != null: _spy.hide()
	clear()
	_rows.clear()
	_at = at
	_row("Travel… · %d gold" % int(OrderCosts.gold_of(Game.data, "KING_MOVE")), {"mode": "move"}, Game.clock_speed > 0)
	_row("Observe", {"mode": "observe"})
	_row("Issue regiment orders…", {"mode": "orders"}, Game.clock_speed > 0)
	for code: String in Game.state.regiments:
		var reg := ArmySystem.regiment(Game.data, code, Game.state)
		if String(reg.get("is_naval", "0")) == "1": continue
		var params := {"regiment": code}
		if ActionSystem.new(Game.data).validate(ActionRequest.make("KING_FOLLOW", params), Game.state) == "":
			_row("Follow %s · %d gold" % [reg.get("label", code), int(OrderCosts.gold_of(Game.data, "KING_FOLLOW"))], {"action": "KING_FOLLOW", "params": params})
	if String(Game.state.king_state.get("follow_code", "")) != "":
		var here := KingSystem.position(Game.state)
		_row("Leave regiment · %d gold" % int(OrderCosts.gold_of(Game.data, "KING_MOVE")), {"action": "KING_MOVE", "params": {"x_m": here.x, "y_m": here.y, "route_m": [here]}})
	for battle: Dictionary in Game.state.battles:
		var id := int(battle.get("id", -1))
		if KingSystem.present(Game.data, Game.state, id):
			_row("Safe departure · %d gold" % int(OrderCosts.gold_of(Game.data, "KING_SAFE_DEPARTURE")), {"action": "KING_SAFE_DEPARTURE", "params": {"battle_id": id}})
	_pop(at)

func _row(label: String, row: Dictionary, disabled: bool = false) -> void:
	var id := _rows.size()
	_rows.append(row)
	add_item(label, id)
	set_item_disabled(id, disabled)
	if disabled: set_item_tooltip(id, "Pause the clock to choose a destination.")

func _chosen(id: int) -> void:
	if id < 0 or id >= _rows.size(): return
	var row: Dictionary = _rows[id]
	if row.has("confirm"):
		if String(_pending.get("action", "")) == "KING_MOVE" and Game.clock_speed > 0:
			cancel()
			return
		var request: Dictionary = _pending.duplicate(true)
		cancel()
		var out := Game.try_execute(ActionRequest.make(String(request["action"]), request["params"]))
		if not bool(out.get("ok", false)): Game.publish_news(String(out.get("error", "The royal order was refused.")))
	elif row.has("action"):
		_confirm(row, _at)
	else:
		var mode := String(row.get("mode", ""))
		if mode == "cancel":
			cancel()
		elif mode == "observe":
			# Observation is presentation only; paid inspiration belongs to P4.
			_map.call("observe_king")
		elif Game.clock_speed == 0:
			_mode = mode
			_map.aiming = true

func _ground(pack_px: Vector2, screen_px: Vector2) -> void:
	if _mode == "" or Game.clock_speed > 0: return
	var mode := _mode
	_mode = ""
	_map.aiming = false
	if mode == "orders":
		var picked: Dictionary = _map.pick_at(screen_px)
		var code := String(picked.get("code", ""))
		if String(picked.get("kind", "")) == "army" and Game.state.regiments.has(code) and _army != null:
			_army._open_for(code, screen_px)
		return
	var dest := ArmySystem.pack_to_metres(Game.data, pack_px)
	_confirm({"action": "KING_MOVE", "params": {"x_m": dest.x, "y_m": dest.y, "route_m": [dest]}}, screen_px)

func _confirm(row: Dictionary, at: Vector2) -> void:
	_pending = row.duplicate(true)
	_at = at
	clear()
	_rows.clear()
	var action := String(row["action"])
	var why := ActionSystem.new(Game.data).validate(ActionRequest.make(action, row["params"]), Game.state)
	_row("Confirm · %d gold" % int(OrderCosts.gold_of(Game.data, action)), {"confirm": true}, why != "")
	if why != "": set_item_tooltip(0, why)
	_row("Cancel", {"mode": "cancel"})
	_pop(at)

func _pop(at: Vector2) -> void:
	popup_on_parent(Rect2i(Vector2i((_map.get_global_rect().position + at).round()), Vector2i.ONE))
