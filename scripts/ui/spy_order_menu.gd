class_name SpyOrderMenu
extends PopupMenu
## "Send a spy here…" (owner 2026-09-28, spec 2026-09-28 §2): a right click on
## open ground offers one row — the fee and the estimated days — and runs
## SPY_SEND there. Lives in court.tscn / conversation.tscn as %SpyOrders.

const SEND := 0

var _map: Node = null
var _target := Vector2(-1, -1)


func _ready() -> void:
	id_pressed.connect(_on_id)


## Follow a map, as ArmyOrderMenu.follow does.
func follow(map: Node) -> void:
	_map = map
	map.connect("ground_menu_requested", _open_at)


func _open_at(pack_px: Vector2, at: Vector2) -> void:
	_target = pack_px
	clear()
	var fee := CourierSystem.fee_gold(Game.data, CourierSystem.SPY)
	var from := CourierSystem.origin(Game.data, Game.state)
	var days := CourierSystem.days_for(Game.data, CourierSystem.SPY, CourierSystem.need_along(Game.data,
		Game.state, ArmySystem.pack_to_metres(Game.data, from),
		CourierSystem.path_between(Game.data, from, pack_px), Game.state.absolute_day()))
	add_item("Send a spy here — ≈%d day%s · %d gold" % [days, "" if days == 1 else "s", fee], SEND)
	set_item_tooltip(0, Intel.place_label(Game.data, Game.state, pack_px))
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
