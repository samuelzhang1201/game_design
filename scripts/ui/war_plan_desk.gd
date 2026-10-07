class_name WarPlanDesk
extends RefCounted
## The WAR ROOM's plans at the screen (spec 2026-10-07-war-room-annotations-
## and-planning-pieces §1.5, §2.4): the right-click menus (open ground, a
## supposed piece, a stroke), the Place form, the name box, the tool roll, the
## keys (Esc, 1-4, Delete, undo) and the slip of a supposed piece — and every
## write, through Game (the view's WarPlanInput only says what was done).
## WarRoomScreen owns one.

enum { PLACE = 1, CLEAR_PIECES, CLEAR_STROKES, EDIT, REMOVE, NAME, DASHED, FLIP, CONFIRM, KEEP, DRAW = 100, COLOUR = 200 }
const COLOURS := {"blue": "Woad crayon (ours)", "red": "Minium crayon (theirs)", "ink": "The pen"}

var _screen: Control
var _view: WarRoomView
var _menu: PopupMenu
var _form: WarPlanForm
var _name: WarPlanName
var _roll: WarToolRoll
var _slip: WarHoverSlip
var _input: WarPlanInput
var _for: Dictionary = {}       # what the open menu is about: {what, pack, at, id, clear}
var _form_at := Vector2(-1, -1)
var _form_edit := ""            # the piece the form edits, "" placing
var _last_side := ""
var _kinds: Array = []          # the kinds the roll and the menu offer (cut 1), in tool_key order


func bind(screen: Control, view: WarRoomView, menu: PopupMenu, form: WarPlanForm, name_box: WarPlanName,
		roll: WarToolRoll, slip: WarHoverSlip) -> void:
	_screen = screen
	_view = view
	_menu = menu
	_form = form
	_name = name_box
	_roll = roll
	_slip = slip
	_input = view.plan_input()
	for k: String in Game.data.war_plan_kinds:
		if int(Game.data.war_plan_kinds[k]["cut"]) == 1:
			_kinds.append(k)
	_kinds.sort_custom(func(a: String, b: String) -> bool:
		return String(Game.data.war_plan_kinds[a]["tool_key"]) < String(Game.data.war_plan_kinds[b]["tool_key"]))
	_menu.id_pressed.connect(_on_row)
	_form.setup(Game.data)
	_form.reading_fn = _form_lines
	_form.placed.connect(_on_placed)
	_name.named.connect(_on_named)
	_roll.stick_picked.connect(_input.pick_stick)
	_roll.kind_picked.connect(_input.pick_kind)
	_roll.action_picked.connect(_input.pick_action)
	_input.tool_changed.connect(_show_tool)
	_input.drawn.connect(_on_drawn)
	_input.piece_moved.connect(func(id: String, to: Vector2, facing: int) -> void:
		_remember()
		if not Game.move_plan_piece(id, to, facing):
			_view.refresh_plans())   # refused (the sea): the piece goes back
	_input.stroke_reshaped.connect(func(id: String, pts: PackedVector2Array, r: float) -> void:
		_remember()
		Game.reshape_plan(id, pts, r))
	_input.stroke_shifted.connect(func(id: String, offset: Vector2) -> void:
		_remember()
		Game.shift_plan(id, offset))
	_input.scraped.connect(_remove)
	_input.piece_requested.connect(_open_form)
	_input.chosen.connect(_on_chosen)
	view.ground_menu_requested.connect(_open_ground_menu)
	view.plan_menu_requested.connect(_open_plan_menu)
	view.plan_hovered.connect(_on_plan_hovered)
	_show_tool()


## Before every write: the plans as they were, for undo.
func _remember() -> void:
	_input.tool.remember(Game.state.war_plans.duplicate(true))


func _origin() -> Vector2:
	return _view.get_global_rect().position - _screen.get_global_rect().position


func _bounds() -> Rect2:
	return Rect2(_origin(), _view.size)


func _pop(at: Vector2) -> void:
	_menu.popup_on_parent(Rect2i(Vector2i((_view.get_global_rect().position + at).round()), Vector2i(1, 1)))


func _show_tool() -> void:
	_roll.show_state(_input.tool.stick if _input.tool.in_hand() else WarPlanTool.HAND,
		_input.tool.kind if _input.tool.in_hand() else "", _input.action)


# --- menus -------------------------------------------------------------------

func _open_ground_menu(pack: Vector2, at: Vector2) -> void:
	var sheet := String(WarSheets.series(Game.data)[_view.sheet_index()]["id"])
	_for = {"what": "ground", "pack": pack, "at": at}
	_menu.clear()
	_menu.add_item("Place a supposed enemy here…", PLACE)
	var why := WarPlans.refusal(Game.data, Game.state, String(WarPlans.arms(Game.data)[0]), 1000, WarPlans.UNKNOWN, pack)
	_menu.set_item_disabled(_menu.get_item_index(PLACE), why != "")
	_menu.set_item_tooltip(_menu.get_item_index(PLACE), why)
	for i in _kinds.size():
		_menu.add_item("Draw: %s" % String(Game.data.war_plan_kinds[_kinds[i]]["label"]).to_lower(), DRAW + i)
	_menu.add_separator()
	_menu.add_item("Clear supposed pieces on %s" % sheet, CLEAR_PIECES)
	_menu.set_item_disabled(_menu.get_item_index(CLEAR_PIECES), WarPlans.pieces_in(Game.data, Game.state, _view.sheet_rect()).is_empty())
	_menu.add_item("Clear drawings on %s" % sheet, CLEAR_STROKES)
	_menu.set_item_disabled(_menu.get_item_index(CLEAR_STROKES), WarPlans.strokes_in(Game.data, Game.state, _view.sheet_rect()).is_empty())
	_pop(at)


func _open_plan_menu(id: String, at: Vector2) -> void:
	_for = {"what": "plan", "id": id, "at": at}
	_menu.clear()
	if id.begins_with("p"):
		_menu.add_item("Edit…", EDIT)
		_menu.add_item("Remove", REMOVE)
		_pop(at)
		return
	var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(id, {})
	if s.is_empty():
		return
	var kind: Dictionary = Game.data.war_plan_kinds[String(s["kind"])]
	if String(kind["name_default"]) != "":
		_menu.add_item("Name…", NAME)
	var keys := COLOURS.keys()
	for i in keys.size():
		_menu.add_radio_check_item(String(COLOURS[keys[i]]), COLOUR + i)
		_menu.set_item_checked(_menu.get_item_index(COLOUR + i), String(s["colour"]) == String(keys[i]))
	_menu.add_check_item("Dashed — expected, not yet", DASHED)
	_menu.set_item_checked(_menu.get_item_index(DASHED), int(s["dashed"]) != 0)
	if bool(kind["teeth"]):
		_menu.add_item("Flip the teeth", FLIP)
	_menu.add_separator()
	_menu.add_item("Remove", REMOVE)
	_input.choose(id)
	_pop(at)


func _confirm(text: String, clear: String) -> void:
	var at: Vector2 = _for["at"]
	_for = {"what": "confirm", "clear": clear, "at": at}
	_menu.clear()
	_menu.add_item(text, CONFIRM)
	_menu.add_item("Keep them", KEEP)
	_pop.call_deferred(at)   # the chosen row's menu hides first


func _on_row(id: int) -> void:
	var f := _for
	if id >= COLOUR:
		_remember()
		Game.restyle_plan(String(f["id"]), {"colour": String(COLOURS.keys()[id - COLOUR])})
		return
	if id >= DRAW:
		_input.pick_kind(String(_kinds[id - DRAW]))
		return
	match id:
		PLACE:
			_open_form(f["pack"], f["at"])
		CLEAR_PIECES:
			_confirm("Clear %d supposed pieces" % WarPlans.pieces_in(Game.data, Game.state, _view.sheet_rect()).size(), WarPlans.PIECES)
		CLEAR_STROKES:
			_confirm("Clear %d drawings" % WarPlans.strokes_in(Game.data, Game.state, _view.sheet_rect()).size(), WarPlans.STROKES)
		CONFIRM:
			_remember()
			Game.clear_plans(String(f["clear"]), _view.sheet_rect())
		EDIT:
			var p: Dictionary = Game.state.war_plans[WarPlans.PIECES].get(String(f["id"]), {})
			if not p.is_empty():
				_form_edit = String(f["id"])
				_form_at = WarPlans.at_px(Game.data, p)
				_form.open_at(_origin() + (f["at"] as Vector2), _bounds(), String(p["arm"]), int(p["heads"]), String(p["side"]), true)
		REMOVE:
			_remove(String(f["id"]))
		NAME:
			var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(String(f["id"]), {})
			_name.open_at(String(f["id"]), String(s.get("name", "")), _origin() + (f["at"] as Vector2), _bounds(),
				int(Game.data.bal("war_plan_name_chars")))
		DASHED:
			var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(String(f["id"]), {})
			_remember()
			Game.restyle_plan(String(f["id"]), {"dashed": 0 if int(s.get("dashed", 0)) != 0 else 1})
		FLIP:
			var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(String(f["id"]), {})
			_remember()
			Game.restyle_plan(String(f["id"]), {"flip": 0 if int(s.get("flip", 0)) != 0 else 1})


# --- writes ------------------------------------------------------------------

func _remove(id: String) -> void:
	_remember()
	if Game.remove_plan(id) and _input.chosen_id == id:
		_input.choose("")


func _open_form(pack: Vector2, at: Vector2) -> void:
	_form_edit = ""
	_form_at = pack
	var side := WarPlans.default_side(Game.data, Game.state, pack, _last_side)
	_form.open_at(_origin() + at, _bounds(), String(WarPlans.arms(Game.data)[0]),
		int(Game.data.bal("war_plan_heads_default")), side)


## The form's live figure lines for a would-be piece at the form's point.
func _form_lines(arm: String, heads: int, side: String) -> Array:
	if _form_at.x < 0.0 or arm == "":
		return []
	var r := WarGround.plan_reading(Game.data, Game.state, {"arm": arm, "heads": heads, "side": side, "at": _form_at}, "")
	var lines := WarGround.plan_lines(Game.data, r)
	return lines.slice(2, lines.size() - 1).map(func(l: Dictionary) -> String: return String(l["text"]))


func _on_placed(arm: String, heads: int, side: String) -> void:
	_last_side = side
	_remember()
	if _form_edit != "":
		Game.edit_plan_piece(_form_edit, arm, heads, side)
		return
	var facing := 0
	var nearest := INF
	for q: Dictionary in WarRoom.on_sheet(Game.data, Game.state, _view.sheet_index(), _view.drawn()):
		var d := (q["at"] as Vector2).distance_to(_form_at)
		if d < nearest:
			nearest = d
			facing = WarPlanPieces.facing_of((q["at"] as Vector2) - _form_at)   # it faces the nearest of ours
	Game.place_plan_piece(arm, heads, side, _form_at, facing)


func _on_drawn(d: Dictionary) -> void:
	var kind := String(d["kind"])
	var name := WarPlans.next_name(Game.data, Game.state, kind)
	_remember()
	var id := Game.draw_plan(kind, String(d["colour"]), d["pts"], float(d["r"]), name, false)
	if id == "":
		Game.publish_news(WarPlans.stroke_refusal(Game.data, Game.state, kind, String(d["colour"]), d["pts"], float(d["r"]), name))
		return
	if name != "":
		var pts: PackedVector2Array = d["pts"]
		var at: Variant = _view.screen_pos_of_px(pts[pts.size() - 1])
		if at != null:
			_name.open_at(id, name, _origin() + (at as Vector2), _bounds(), int(Game.data.bal("war_plan_name_chars")))


func _on_named(id: String, text: String) -> void:
	var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(id, {})
	if s.is_empty() or String(s["name"]) == text:
		return
	_remember()
	Game.restyle_plan(id, {"name": text})


# --- the slip ----------------------------------------------------------------

func _on_plan_hovered(id: String, at: Vector2) -> void:
	var p: Dictionary = Game.state.war_plans[WarPlans.PIECES].get(id, {})
	if p.is_empty():
		return
	var r := WarGround.plan_reading(Game.data, Game.state, p, _view.selected_army())
	_slip.show_lines(WarGround.plan_lines(Game.data, r), _origin() + at, _bounds())


## A supposed piece chosen pins its slip; anything else lets it go.
func _on_chosen(id: String) -> void:
	if not id.begins_with("p"):
		_slip.hide_slip()
		return
	var p: Dictionary = Game.state.war_plans[WarPlans.PIECES].get(id, {})
	var at: Variant = _view.screen_pos_of_px(WarPlans.at_px(Game.data, p)) if not p.is_empty() else null
	if at != null:
		_on_plan_hovered(id, at)


## A rake's tip near a supposed piece: its lines after the ground's.
func contact_lines(code: String, pack: Vector2) -> Array:
	var p := WarPlans.piece_near(Game.data, Game.state, pack, Game.data.bal("war_plan_contact_km"))
	if p.is_empty():
		return []
	var out: Array = [{"text": "", "kind": "rule"}]
	out.append_array(WarGround.plan_lines(Game.data, WarGround.plan_reading(Game.data, Game.state, p, code)))
	return out


# --- keys --------------------------------------------------------------------

## The room's keys for the plans; true when one was taken.
func key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if _screen.get_viewport().gui_get_focus_owner() is LineEdit or _form.visible or _name.visible:
		return false
	var command := event.ctrl_pressed or event.meta_pressed
	if event.keycode == KEY_ESCAPE:
		if _input.put_down():
			return true
		if _input.chosen_id != "":
			_input.choose("")
			return true
		return false
	if command and event.keycode == KEY_Z:
		var now: Dictionary = Game.state.war_plans.duplicate(true)
		var back := _input.tool.redo(now) if event.shift_pressed else _input.tool.undo(now)
		if not back.is_empty():
			Game.restore_plans(back)
		return true
	if command:
		return false
	if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and _input.chosen_id != "":
		_remove(_input.chosen_id)
		return true
	for k: String in _kinds:
		if String(Game.data.war_plan_kinds[k]["tool_key"]) == OS.get_keycode_string(event.keycode):
			_input.pick_kind(k)
			return true
	return false
