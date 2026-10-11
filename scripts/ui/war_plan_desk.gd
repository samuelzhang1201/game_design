class_name WarPlanDesk
extends RefCounted
## The WAR ROOM's plans at the screen (spec 2026-10-07-war-room-annotations-
## and-planning-pieces §1.5, §2.4): the right-click menus (open ground, a
## supposed piece, a stroke), the Place form, the name box, the tool roll, the
## keys (Esc, 1-4 on the side in hand, Tab the other side, Delete, undo) and
## the slip of a supposed piece — and every write, through Game (the view's
## WarPlanInput only says what was done). A front is drawn facing the other
## side's nearest mark or piece (spec 2026-10-08-war-room-draw-orders ruling
## 12). WarRoomScreen owns one.

enum { PLACE = 1, CLEAR_PIECES, CLEAR_STROKES, EDIT, REMOVE, NAME, DASHED, FLIP, CONFIRM, KEEP, FACE, COLOUR = 200 }
## The sides a mark may be recoloured to (the pen is retired: ruling 3).
const COLOURS := {"blue": "Ours (woad blue)", "red": "Theirs (minium red)"}

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
var _drafts_before: Dictionary = {}   # the drafts as they were while a march or halt is pencilled


func bind(screen: Control, view: WarRoomView, menu: PopupMenu, form: WarPlanForm, name_box: WarPlanName,
		roll: WarToolRoll, slip: WarHoverSlip, orders: ArmyOrderMenu = null) -> void:
	_screen = screen
	_view = view
	_menu = menu
	_form = form
	_name = name_box
	_roll = roll
	_slip = slip
	_input = view.plan_input()
	if orders != null:
		orders.drafts_planting.connect(_on_drafts_planting)
		orders.drafts_planted.connect(_on_drafts_planted)
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
	view.table_pressed.connect(func() -> void:
		if _name.visible:
			_name.commit())
	_roll.stick_picked.connect(_input.pick_stick)
	_roll.kind_picked.connect(func(side: String, k: String) -> void: _input.pick_kind(k, side))
	_roll.action_picked.connect(_input.pick_action)
	_input.tool_changed.connect(_show_tool)
	_input.stroke_faced.connect(func(id: String, flip: int) -> void:
		_write(func() -> Variant: return Game.restyle_plan(id, {"flip": flip})))
	_input.drawn.connect(_on_drawn)
	_input.piece_moved.connect(func(id: String, to: Vector2, facing: int) -> void:
		if not _write(func() -> Variant: return Game.move_plan_piece(id, to, facing)):
			_view.refresh_plans())   # refused (the sea): the piece goes back
	_input.stroke_reshaped.connect(func(id: String, pts: PackedVector2Array, r: float) -> void:
		_write(func() -> Variant: return Game.reshape_plan(id, pts, r)))
	_input.stroke_shifted.connect(func(id: String, offset: Vector2) -> void:
		_write(func() -> Variant: return Game.shift_plan(id, offset)))
	_input.scraped.connect(_remove)
	_input.piece_requested.connect(_open_form)
	_input.chosen.connect(_on_chosen)
	view.ground_menu_requested.connect(_open_ground_menu)
	view.plan_menu_requested.connect(_open_plan_menu)
	view.plan_hovered.connect(_on_plan_hovered)
	_show_tool()


## A write to the plans through Game: the plans as they were are kept for undo
## only when the write landed (Game.landed), so a refusal leaves no step.
func _write(f: Callable) -> Variant:
	_input.tool.own(Game.state.get_instance_id())
	var before: Dictionary = Game.state.war_plans.duplicate(true)
	var done: Variant = f.call()
	@warning_ignore("static_called_on_instance")
	if Game.landed(done):
		_input.tool.remember(before)
	return done


## A march or halt is about to be pencilled for these regiments: their drafts as
## they are now, for undo.
func _on_drafts_planting(codes: Array) -> void:
	_drafts_before = _drafts_of(codes)


## It is pencilled: the step keeps the drafts before and as left, so an undo
## after a seal, a strike or a map order (the drafts since changed) does nothing.
func _on_drafts_planted(codes: Array) -> void:
	_input.tool.own(Game.state.get_instance_id())
	var before := {}
	for c: String in codes:
		before[c] = _drafts_before.get(c, {})
	_drafts_before = {}
	_input.tool.remember_drafts(before, _drafts_of(codes))


func _drafts_of(codes: Variant) -> Dictionary:
	var out := {}
	for c: String in codes:
		out[c] = WarDrafts.of(Game.state, c).duplicate(true)
	return out


func _origin() -> Vector2:
	return _view.get_global_rect().position - _screen.get_global_rect().position


func _bounds() -> Rect2:
	return Rect2(_origin(), _view.size)


func _pop(at: Vector2) -> void:
	_menu.popup_on_parent(Rect2i(Vector2i((_view.get_global_rect().position + at).round()), Vector2i(1, 1)))


func _show_tool() -> void:
	_roll.show_state(_input.tool.side, _input.tool.kind, _input.action, _input.whys())
	if _input.tool.in_hand():
		_slip.hide_slip()   # a pinned slip never covers the stroke about to be drawn


# --- menus -------------------------------------------------------------------

func _open_ground_menu(pack: Vector2, at: Vector2) -> void:
	var sheet := String(_view.laid_sheet().get("id", ""))
	_for = {"what": "ground", "pack": pack, "at": at}
	_menu.clear()
	_menu.add_item("Place a supposed enemy here…", PLACE)
	var why := WarPlans.refusal(Game.data, Game.state, String(WarPlans.arms(Game.data)[0]), 1000, WarPlans.UNKNOWN, pack)
	_menu.set_item_disabled(_menu.get_item_index(PLACE), why != "")
	_menu.set_item_tooltip(_menu.get_item_index(PLACE), why)
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
		_menu.add_item("Face the enemy", FACE)
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
		_write(func() -> Variant: return Game.restyle_plan(String(f["id"]), {"colour": String(COLOURS.keys()[id - COLOUR])}))
		return
	match id:
		PLACE:
			_open_form(f["pack"], f["at"])
		CLEAR_PIECES:
			_confirm("Clear %d supposed pieces" % WarPlans.pieces_in(Game.data, Game.state, _view.sheet_rect()).size(), WarPlans.PIECES)
		CLEAR_STROKES:
			_confirm("Clear %d drawings" % WarPlans.strokes_in(Game.data, Game.state, _view.sheet_rect()).size(), WarPlans.STROKES)
		CONFIRM:
			_write(func() -> Variant: return Game.clear_plans(String(f["clear"]), _view.sheet_rect()))
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
			_write(func() -> Variant: return Game.restyle_plan(String(f["id"]), {"dashed": 0 if int(s.get("dashed", 0)) != 0 else 1}))
		FLIP:
			var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(String(f["id"]), {})
			_write(func() -> Variant: return Game.restyle_plan(String(f["id"]), {"flip": 0 if int(s.get("flip", 0)) != 0 else 1}))
		FACE:
			var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(String(f["id"]), {})
			if not s.is_empty():
				_write(func() -> Variant: return Game.restyle_plan(String(f["id"]), {"flip": _facing(String(s["colour"]), WarPlans.points_px(Game.data, s), String(f["id"]))}))


# --- writes ------------------------------------------------------------------

func _remove(id: String) -> void:
	if _write(func() -> Variant: return Game.remove_plan(id)) and _input.chosen_id == id:
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
	return lines.slice(3, lines.size() - 1).map(func(l: Dictionary) -> String: return String(l["text"]))


func _on_placed(arm: String, heads: int, side: String) -> void:
	_last_side = side
	if _form_edit != "":
		_write(func() -> Variant: return Game.edit_plan_piece(_form_edit, arm, heads, side))
		return
	var facing := 0
	var nearest := INF
	for q: Dictionary in WarRoom.on_sheet(Game.data, Game.state, _view.laid_sheet(), _view.drawn()):
		var d := (q["at"] as Vector2).distance_to(_form_at)
		if d < nearest:
			nearest = d
			facing = WarPlanPieces.facing_of((q["at"] as Vector2) - _form_at)   # it faces the nearest of ours
	_write(func() -> Variant: return Game.place_plan_piece(arm, heads, side, _form_at, facing))


func _on_drawn(d: Dictionary) -> void:
	var kind := String(d["kind"])
	var name := WarPlans.next_name(Game.data, Game.state, kind)
	var flip := _facing(String(d["colour"]), d["pts"]) if bool(Game.data.war_plan_kinds[kind]["teeth"]) else -1
	var id: String = _write(func() -> Variant: return Game.draw_plan(kind, String(d["colour"]), d["pts"], float(d["r"]), name, false, flip, String(d.get("of", ""))))
	if id == "":
		Game.publish_news(WarPlans.stroke_refusal(Game.data, Game.state, kind, String(d["colour"]), d["pts"], float(d["r"]), name))
		return
	if d.has("codes") and not (d["codes"] as Array).is_empty():
		_plant_front(id, d["codes"])
	if name != "":
		var pts: PackedVector2Array = d["pts"]
		var at: Variant = _view.screen_pos_of_px(pts[pts.size() - 1])
		if at != null:
			_name.open_at(id, name, _origin() + (at as Vector2), _bounds(), int(Game.data.bal("war_plan_name_chars")))


## A blue front's drafts (spec 2026-10-11-war-room-front-line-design §1): one
## per chosen regiment, its own undo step after the stroke's; the news counts
## them and names each refusal.
func _plant_front(id: String, codes: Array) -> void:
	_on_drafts_planting(codes)
	var out := Game.plant_front(id, codes)
	_on_drafts_planted(codes)
	var n: int = (out["planted"] as Array).size()
	if n > 0:
		Game.publish_news("The front of %d unit%s is pencilled in." % [n, "" if n == 1 else "s"])
	for c: String in out["refused"]:
		Game.publish_news("%s: %s" % [String(ArmySystem.regiment(Game.data, c, Game.state).get("label", c)), String(out["refused"][c])])


## A front's facing: toward the nearest of the other side's marks and pieces
## (ours are where the room stands them).
func _facing(colour: String, pts: PackedVector2Array, except_id := "") -> int:
	var ours: Array = WarRoom.pieces(Game.data, Game.state, _view.drawn()).map(func(q: Dictionary) -> Vector2: return q["at"])
	return WarPlans.facing_flip(pts, WarPlans.opposing_points(Game.data, Game.state, colour, ours, except_id))


func _on_named(id: String, text: String) -> void:
	var s: Dictionary = Game.state.war_plans[WarPlans.STROKES].get(id, {})
	if s.is_empty() or String(s["name"]) == text:
		return
	_write(func() -> Variant: return Game.restyle_plan(id, {"name": text}))


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
		if _view.has_selection():
			_view.clear_selection()
			return true
		return false
	if event.keycode == KEY_TAB and not command:
		_input.switch_side()
		return true
	if command and event.keycode == KEY_Z:
		_input.tool.own(Game.state.get_instance_id())
		var now_of := func(e: Dictionary) -> Dictionary:
			if e.has("drafts"):
				return {"drafts": _drafts_of(e["drafts"]), "expect": e["drafts"]}
			return {"plans": Game.state.war_plans.duplicate(true)}
		# a march's step holds only while its drafts are as it left them
		var holds := func(e: Dictionary) -> bool:
			return not e.has("drafts") or _drafts_of(e.get("expect", {})) == e.get("expect", {})
		var back: Dictionary = _input.tool.redo(now_of, holds) if event.shift_pressed else _input.tool.undo(now_of, holds)
		if back.has("stale"):
			Game.publish_news("That march has since been sealed or changed — nothing to undo.")
		elif back.has("plans"):
			Game.restore_plans(back["plans"])
		elif back.has("drafts"):
			Game.restore_drafts(back["drafts"])
		return true
	if command:
		return false
	if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and _input.chosen_id != "":
		_remove(_input.chosen_id)
		return true
	for k: String in _kinds:
		if String(Game.data.war_plan_kinds[k]["tool_key"]) == OS.get_keycode_string(event.keycode):
			_input.pick_kind(k)   # on the side in hand; none yet: the news says to choose one
			return true
	return false
