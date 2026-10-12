class_name SpyOrderMenu
extends PopupMenu
## "Send a spy here…" (owner 2026-09-28, spec 2026-09-28 §2): a right click on
## open ground offers one row — the fee and the estimated days — and runs
## SPY_SEND there. Lives in court.tscn / conversation.tscn as %SpyOrders.

const SEND := 0

var _map: Node = null
var _army: ArmyOrderMenu = null
var _target := Vector2(-1, -1)


func _ready() -> void:
	id_pressed.connect(_on_id)


## Follow a map, as ArmyOrderMenu.follow does. `army` is the same screen's
## regiment menu: while it is aiming a march, the ground's right click is
## its to answer (final review M14).
func follow(map: Node, army: ArmyOrderMenu = null) -> void:
	_map = map
	_army = army
	map.connect("ground_menu_requested", _open_at)


func _open_at(pack_px: Vector2, at: Vector2) -> void:
	# A march being aimed: a right click on the ground gives the aim up, as
	# Escape does, rather than offering a spy (final review M14).
	if _army != null and (_army.aiming() != "" or _army.supply_picking() != ""):
		_army.withdraw_aim()
		return
	_target = pack_px
	clear()
	var fee := CourierSystem.fee_gold(Game.data, CourierSystem.SPY)
	# day-ends, the day now running the first (owner 2026-10-02), as the ride counts them
	var days := CourierSystem.spy_eta_days(Game.data, Game.state, pack_px)
	add_item("Send a spy here — ≈%d day%s · %d gold" % [days, "" if days == 1 else "s", fee], SEND)
	set_item_tooltip(0, Intel.place_label(Game.data, Game.state, pack_px))
	# The engine decides (ActionSystem.validate): a refused spy shows greyed, with its reason.
	var why := ActionSystem.new(Game.data).validate(
			ActionRequest.make("SPY_SEND", {"x": pack_px.x, "y": pack_px.y}), Game.state)
	if why != "":
		set_item_disabled(0, true)
		set_item_tooltip(0, why)
	_pop(at)


## `at` in the map's own px — mirrors ArmyOrderMenu._pop's conversion.
func _pop(at: Vector2) -> void:
	var origin := Vector2.ZERO
	if _map is Control:
		origin = (_map as Control).get_global_rect().position
	popup_on_parent(Rect2i(Vector2i((origin + at).round()), Vector2i(1, 1)))


func _on_id(id: int) -> void:
	if id != SEND or _target.x < 0.0:
		return
	var out := Game.try_execute(ActionRequest.make("SPY_SEND", {"x": _target.x, "y": _target.y}))
	if not bool(out.get("ok", false)):
		Game.publish_news(String(out.get("error", "That spy cannot be sent.")))
		_target = Vector2(-1, -1)
		return
	for e: Dictionary in (out.get("outcome", {}) as Dictionary).get("effects", []):
		if String(e.get("metric", "")) == "intel":
			Game.publish_news(String(e["reason"]))
	_target = Vector2(-1, -1)
