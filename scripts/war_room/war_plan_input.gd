class_name WarPlanInput
extends RefCounted
## The left button for the room's PLANS and its SELECTION (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.5, §1.6, §2.4;
## 2026-10-08-war-room-draw-orders rulings 1-4, 6, 12, 16-18). What is in
## hand is a SIDE (red theirs, blue ours) and a kind: a press-drag-release
## draws (WarPlanTool). The ARROW of a side is drawn only for a SELECTION of
## that side — ours: the selected regiments, and the stroke is their march's
## route (`order_drawn`); theirs: a supposed piece or an intel hint, the arrow
## drawn for it (`of`). The piece slot asks for the Place form; the scraper
## removes what it lands on (its side's, and ink); with the hand a supposed
## piece is carried by a drag (a click chooses and selects it), a stroke's
## handle reshapes it, its line moves it, a front's facing handle turns its
## teeth; a click on an intel hint selects it; Shift-click adds to the
## selection, Shift-drag on open table boxes every piece of the side. Crown
## pieces are clicked through the view (`WarRoomPointer`), which hands them here.
## The live stroke is WarPlanHud's. It only says what was done; the screen
## writes it. Never reaches the autoload.

signal drawn(stroke: Dictionary)                       # {kind, colour, pts (pack px), r, of}
signal order_drawn(codes: Array, samples: PackedVector2Array, tol: float)   # pack px, the smoothing's tolerance
signal piece_moved(id: String, to_px: Vector2, facing_deg: int)
signal stroke_reshaped(id: String, pts: PackedVector2Array, r: float)
signal stroke_shifted(id: String, offset: Vector2)
signal stroke_faced(id: String, flip: int)
signal chosen(id: String)                              # a supposed piece or a stroke; "" none
signal scraped(id: String)
signal piece_requested(pack_px: Vector2, screen_px: Vector2)
signal refused(why: String)                            # a press that cannot draw: the news says why
signal tool_changed
signal selection_changed

const PIECE := "piece"
const SCRAPE := "scrape"

var tool: WarPlanTool
var action := ""        # PIECE or SCRAPE in hand, else ""
var chosen_id := ""
## The selection: its side ("" none) and its members — our regiments' codes
## (blue), or supposed pieces' and intel hints' ids (red).
var sel_side := ""
var sel: Array = []
var _view: WarRoomView
var _repo: DataRepository
var _hud: WarPlanHud
var _drag: Dictionary = {}
var _click_from := Vector2.ZERO
var _click_shift := false
var _pending_choose := ""   # an unchosen stroke pressed with the hand: a click chooses it, a drag pans
var _pending_from := Vector2.ZERO
var _order := false     # the stroke being drawn is the selection's march
## The stroke just let go (pack px), drawn live until the plan layer shows it:
## {s: the stroke's row, pts, r, key (WarPlanInk.cache_key once written)}; {} none.
var _ghost: Dictionary = {}


func setup(view: WarRoomView, repo: DataRepository, hud: WarPlanHud) -> void:
	_view = view
	_repo = repo
	_hud = hud
	tool = WarPlanTool.new(repo)


# --- what is in hand ----------------------------------------------------------

## Why the slot `key` of `side` cannot be used now, "" when it can: an
## arrow wants a selection of its side.
func why_of(side: String, key: String) -> String:
	if key == "arrow" and (sel_side != side or sel.is_empty()):
		return "Select a unit first: one of ours (Shift-click adds, Shift-drag boxes)" if side == "blue" \
			else "Select a unit first: a supposed host or an intel hint"
	if key == "arrow" and side == "blue" and sel.all(func(c: Variant) -> bool: return naval(String(c))):
		return "Fleets are ordered on the map"
	return ""


## True when the regiment `code` is a fleet (the room never marches one).
func naval(code: String) -> bool:
	return String(ArmySystem.regiment(_repo, code, _view.state()).get("is_naval", "0")) == "1"


## The laid sheet's own: drops from the selection every unit of ours not on
## the sheet and every supposed piece or hint not on it.
func keep_on_sheet() -> void:
	if sel.is_empty():
		return
	var here: Array = []
	if sel_side == "blue":
		for q: Dictionary in WarRoom.on_sheet(_repo, _view.state(), _view.sheet_index(), _view.drawn()):
			here.append(String(q["code"]))
	else:
		for p: Dictionary in WarPlans.pieces_in(_repo, _view.state(), _view.sheet_rect()):
			here.append(String(p["id"]))
		for h: Dictionary in hints_on_sheet():
			here.append(String(h["id"]))
	var kept := sel.filter(func(i: Variant) -> bool: return i in here)
	if kept.size() != sel.size():
		select(sel_side, kept)


## Every slot that cannot be used now: {side: {key: why}} (the roll greys them).
func whys() -> Dictionary:
	return {"red": {"arrow": why_of("red", "arrow")}, "blue": {"arrow": why_of("blue", "arrow")}}


## Kind `k` on `side` (the side chosen when ""): refused (and said) when it
## cannot be used now.
func pick_kind(k: String, side := "") -> void:
	var sd := side if side != "" else tool.side
	if sd == "":
		refused.emit("Choose a side first: Tab, or the red (theirs) or blue (ours) row")
		return
	if why_of(sd, k) != "":
		refused.emit(why_of(sd, k))
		return
	action = ""
	tool.pick(sd, k)
	tool_changed.emit()


## A row's crayon or the hand.
func pick_stick(s: String) -> void:
	action = ""
	var k := tool.last_kind(s) if s in WarPlanTool.SIDES else ""
	tool.pick_stick(s, "front" if k != "" and why_of(s, k) != "" else "")
	tool_changed.emit()


## Tab: the other side, the same kind (a front when its arrow cannot be used).
func switch_side() -> void:
	action = ""
	var to := "blue" if tool.side != "blue" else "red"
	tool.switch_side("front" if tool.kind != "" and why_of(to, tool.kind) != "" else "")
	tool_changed.emit()


func pick_action(side: String, a: String) -> void:
	tool.put_down()
	if side != "":
		tool.side = side
	action = "" if action == a else a
	tool_changed.emit()


## Esc: the stick or the action laid down; true when anything was in hand.
func put_down() -> bool:
	var held := tool.in_hand() or action != ""
	tool.put_down()
	action = ""
	if not _drag.is_empty() and bool(_drag.get("moved", false)):
		_view.hide_plan_stroke("")
	_drag = {}
	_order = false
	redraw_live()
	if held:
		tool_changed.emit()
	return held


## A stick or an action is in hand (the pan and the hover slip give way).
func busy() -> bool:
	return tool.in_hand() or action != ""


func choose(id: String) -> void:
	if chosen_id == id:
		return
	chosen_id = id
	chosen.emit(id)
	redraw_live()


# --- the selection ---------------------------------------------------------

## Selects `ids` on `side` (Shift: `additive` toggles each in, or out when all
## are in already); another side's selection goes. A side's arrow put down
## when its selection empties.
func select(side: String, ids: Array, additive := false) -> void:
	if not additive or side != sel_side:
		sel = []
	sel_side = side
	if additive and not ids.is_empty() and ids.all(func(i: Variant) -> bool: return i in sel):
		for i: Variant in ids:
			sel.erase(i)
	else:
		for i: Variant in ids:
			if not i in sel:
				sel.append(i)
	if sel.is_empty():
		sel_side = ""
	if tool.kind == "arrow" and why_of(tool.side, "arrow") != "":
		tool.put_down()
	if sel_side != "" and not tool.in_hand() and action == "":
		tool.side = sel_side   # the side selected lights its row
	selection_changed.emit()
	tool_changed.emit()
	redraw_live()


func clear_selection() -> bool:
	if sel.is_empty():
		return false
	select("", [])
	return true


# --- the pointer -------------------------------------------------------------

## True when the event was the plans' (the view takes it no further).
func handle(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		return _press(mb) if mb.pressed else _release(mb)
	var mm := event as InputEventMouseMotion
	if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return _motion(mm)
	return false


func _press(mb: InputEventMouseButton) -> bool:
	var pos := mb.position
	var pack := _view.pack_at(pos)
	_pending_choose = ""
	if tool.in_hand():
		if pack.x < 0.0:
			return false
		if tool.kind == "arrow" and why_of(tool.side, "arrow") != "":
			refused.emit(why_of(tool.side, "arrow"))
			return true
		_click_from = pos
		_click_shift = mb.shift_pressed
		_order = tool.kind == "arrow" and tool.side == "blue"
		tool.press(pack, pos)
		redraw_live()
		return true
	if action == PIECE:
		if pack.x < 0.0:
			return false
		piece_requested.emit(pack, pos)
		pick_action(tool.side, PIECE)   # laid down: one piece a pick
		return true
	if _view.piece_under(pos) != "":
		return false   # a crown piece: the view's click (it selects it)
	var radius := _repo.bal("war_pick_px")
	var pid := _view.plan_pieces().pick(_view.camera(), _view.window_scale(), pos, radius)
	var hint := "" if pid != "" else hint_at(pos)
	var hit := {} if pid != "" or hint != "" else WarPlanTool.hit(_repo, strokes_on_screen(), pos, chosen_id, radius)
	if action == SCRAPE:
		var gone := pid if pid != "" and tool.side != "blue" else String(hit.get("id", ""))
		if gone == "" or (gone.begins_with("s") and not _scrapes(gone)):
			return false
		scraped.emit(gone)
		return true
	if pid != "":
		_drag = {"mode": "piece", "id": pid, "from": pos, "from_pack": pack, "moved": false, "shift": mb.shift_pressed}
		return true
	if hint != "":
		select("red", [hint], mb.shift_pressed)
		return true
	var facing := _facing_handle()
	if not facing.is_empty() and (facing["at"] as Vector2).distance_to(pos) <= _repo.bal("war_plan_facing_px"):
		_drag = {"mode": "facing", "id": chosen_id, "from": pos, "from_pack": pack, "moved": false}
		return true
	if not hit.is_empty() and int(hit["handle"]) < 0 and String(hit["id"]) != chosen_id:
		_pending_choose = String(hit["id"])   # only the chosen stroke is carried: the press pans, a click chooses
		_pending_from = pos
		return false
	if not hit.is_empty():
		_drag = {"mode": "handle" if int(hit["handle"]) >= 0 else "stroke", "id": String(hit["id"]),
			"handle": int(hit["handle"]), "from": pos, "from_pack": pack, "moved": false, "to_pack": pack}
		return true
	if mb.shift_pressed and pack.x >= 0.0:
		_drag = {"mode": "box", "from": pos, "to": pos, "moved": false}
		return true
	if chosen_id != "":
		choose("")
	return false


## The scraper in hand takes its own side's marks and the pen's.
func _scrapes(id: String) -> bool:
	var s: Dictionary = _view.state().war_plans[WarPlans.STROKES].get(id, {})
	return String(s.get("colour", "")) in [tool.side, "ink"] or tool.side == ""


func _motion(mm: InputEventMouseMotion) -> bool:
	var pack := _view.pack_at(mm.position)
	if tool.drawing:
		tool.move(pack, mm.position)
		if _order and pack.x >= 0.0 and not sel.is_empty():
			_view.order_aimed.emit(String(sel[0]), pack, mm.position)
		redraw_live()
		return true
	if _drag.is_empty():
		return false
	if not bool(_drag["moved"]) and mm.position.distance_to(_drag["from"]) < _repo.bal("war_rake_min_px"):
		return true
	if not bool(_drag["moved"]) and String(_drag["mode"]) in ["stroke", "handle"]:
		_view.hide_plan_stroke(String(_drag["id"]))   # carried live: the table's own copy goes
	_drag["moved"] = true
	if String(_drag["mode"]) == "box":
		_drag["to"] = mm.position
		_view.redraw_marks()
		return true
	if pack.x < 0.0:
		return true
	_drag["to_pack"] = pack
	if String(_drag["mode"]) == "piece":
		_drag["facing"] = WarPlanPieces.facing_of(pack - (_drag["from_pack"] as Vector2))
		_view.plan_pieces().follow(String(_drag["id"]), pack, int(_drag["facing"]))
	redraw_live()
	return true


func _release(mb: InputEventMouseButton) -> bool:
	if tool.drawing:
		if mb.position.distance_to(_click_from) < _repo.bal("war_rake_min_px"):
			tool.cancel()
			_order = false
			redraw_live()
			_click_through(mb.position, _click_shift)
			return true
		var pack := _view.pack_at(mb.position)
		var per := px_per_pack(pack if pack.x >= 0.0 else _view.sheet_rect().get_center())
		var d := tool.release(pack, mb.position, mb.shift_pressed, per)
		var order := _order
		_order = false
		redraw_live()
		if d.is_empty():
			return true
		if order:
			_view.hover_cleared.emit()
			var marching := sel.filter(func(c: Variant) -> bool: return not naval(String(c)))
			if marching.is_empty():
				return true
			order_drawn.emit(marching, (d["samples"] as PackedVector2Array) if not mb.shift_pressed \
				else PackedVector2Array([d["samples"][0], d["samples"][d["samples"].size() - 1]]), _repo.bal("war_order_fit_px") / maxf(per, 0.0001))
			if _view.aiming:
				tool.put_down()   # the blue arrow is laid down once its march is drawn
				tool_changed.emit()
		else:
			if String(d["kind"]) == "arrow" and not sel.is_empty():
				for id: Variant in sel:   # a red arrow for each host selected, drawn from its own spot
					var one := d.duplicate()
					var pts: PackedVector2Array = (d["pts"] as PackedVector2Array).duplicate()
					var spot: Variant = _spot_of(String(id))
					if spot != null:
						pts[0] = spot
					one["pts"] = pts
					one["of"] = String(id)
					drawn.emit(one)
					_keep_ghost(one)
			else:
				drawn.emit(d)
				_keep_ghost(d)
		redraw_live()
		return true
	if _pending_choose != "":
		var pend := _pending_choose
		_pending_choose = ""
		if mb.position.distance_to(_pending_from) < _repo.bal("war_rake_min_px"):
			choose(pend)
			_view.forget_press()
		return false
	if _drag.is_empty():
		return false
	var d := _drag
	_drag = {}
	if String(d["mode"]) == "box":
		_view.redraw_marks()
		if bool(d["moved"]):
			_box(Rect2(d["from"], Vector2.ZERO).expand(d["to"]))
		return true
	var id := String(d["id"])
	if not bool(d["moved"]):
		if String(d["mode"]) == "facing":
			stroke_faced.emit(id, _flip_of(id) ^ 1)
			return true
		choose(id)
		if id.begins_with("p"):
			select("red", [id], bool(d.get("shift", false)))
		return true
	var to: Vector2 = d.get("to_pack", d["from_pack"])
	match String(d["mode"]):
		"piece":
			piece_moved.emit(id, to, int(d.get("facing", 0)))
		"stroke":
			stroke_shifted.emit(id, to - (d["from_pack"] as Vector2))
			_keep_ghost_of(id)
		"facing":
			var s: Dictionary = _view.state().war_plans[WarPlans.STROKES].get(id, {})
			if not s.is_empty():
				stroke_faced.emit(id, WarPlans.facing_flip(WarPlans.points_px(_repo, s), [to]))
		"handle":
			var s: Dictionary = _view.state().war_plans[WarPlans.STROKES].get(id, {})
			if not s.is_empty():
				var r := _reshaped(s, int(d["handle"]), to)
				stroke_reshaped.emit(id, r["pts"], float(r["r"]))
				_keep_ghost_of(id)
	if String(d["mode"]) in ["stroke", "handle"]:
		_view.hide_plan_stroke("")
	redraw_live()
	return true


## The stroke `d` just drawn (pack px) stays on the hud until the plan layer
## has been painted for the plans as they are now.
func _keep_ghost(d: Dictionary) -> void:
	var s := {"kind": String(d["kind"]), "colour": String(d["colour"]), "dashed": 0, "flip": 0, "name": ""}
	_ghost = {"s": s, "pts": d["pts"], "r": float(d["r"]), "key": WarPlanInk.cache_key(_view.state(), _view.sheet_index())}


## The stroke `id` as the plans now hold it, the same way.
func _keep_ghost_of(id: String) -> void:
	var s: Dictionary = _view.state().war_plans[WarPlans.STROKES].get(id, {})
	if not s.is_empty():
		_keep_ghost({"kind": s["kind"], "colour": s.get("colour", "ink"), "pts": WarPlans.points_px(_repo, s),
			"r": WarPlans.radius_px(_repo, s)})


## A click with a stick in hand: a supposed piece or an intel hint under it is
## chosen and selected, else the view's own pick (our piece, the selection let go).
func _click_through(pos: Vector2, shift: bool) -> void:
	var radius := _repo.bal("war_pick_px")
	var pid := "" if _view.piece_under(pos) != "" else _view.plan_pieces().pick(_view.camera(), _view.window_scale(), pos, radius)
	var hint := "" if pid != "" or _view.piece_under(pos) != "" else hint_at(pos)
	if pid != "":
		choose(pid)
		select("red", [pid], shift)
	elif hint != "":
		select("red", [hint], shift)
	else:
		_view.click_through(pos, shift)


## Where a red selection's member stands (pack px), null when it is gone: a
## supposed piece, or an intel hint.
func _spot_of(id: String) -> Variant:
	var st := _view.state()
	if id.begins_with("h") or id.begins_with("b"):
		var h := WarRoom.hint_of(_repo, st, id)
		return h["at"] if not h.is_empty() else null
	var p: Dictionary = st.war_plans[WarPlans.PIECES].get(id, {})
	return WarPlans.at_px(_repo, p) if not p.is_empty() else null


func _flip_of(id: String) -> int:
	return int((_view.state().war_plans[WarPlans.STROKES].get(id, {}) as Dictionary).get("flip", 0))


## Shift-drag's box (screen px): what lies in it replaces the selection — our
## land units first (at the spot they are DRAWN), else the supposed pieces and
## the intel hints; nothing in it, no change.
func _box(box: Rect2) -> void:
	var drawn: Dictionary = _view.piece_pack_positions()
	var ours: Array = []
	for q: Dictionary in WarRoom.on_sheet(_repo, _view.state(), _view.sheet_index(), _view.drawn()):
		if bool(q["naval"]):
			continue
		var code := String(q["code"])
		var at: Variant = _view.screen_pos_of_px(drawn.get(code, q["at"]))
		if at != null and box.has_point(at):
			ours.append(code)
	if not ours.is_empty():
		select("blue", ours, false)   # a box opens no book: the book is a click's
		return
	var theirs: Array = []
	for p: Dictionary in WarPlans.pieces_in(_repo, _view.state(), _view.sheet_rect()):
		var at: Variant = _view.screen_pos_of_px(p["at"])
		if at != null and box.has_point(at):
			theirs.append(String(p["id"]))
	for h: Dictionary in hints_on_sheet():
		var at: Variant = _view.screen_pos_of_px(h["at"])
		if at != null and box.has_point(at):
			theirs.append(String(h["id"]))
	if not theirs.is_empty():
		select("red", theirs, false)


## The box being dragged (screen px), Rect2() when none.
func marquee() -> Rect2:
	if _drag.is_empty() or String(_drag["mode"]) != "box" or not bool(_drag["moved"]):
		return Rect2()
	return Rect2(_drag["from"], Vector2.ZERO).expand(_drag["to"])


## The intel hints on the laid sheet (WarRoom.intel_hints).
func hints_on_sheet() -> Array:
	var st := _view.state()
	if st == null or _view.sheet_index() < 0:
		return []
	var rect := _view.sheet_rect()
	return WarRoom.intel_hints(_repo, st).filter(func(h: Dictionary) -> bool: return rect.has_point(h["at"]))


## The intel hint under a screen point, "" none.
func hint_at(at: Vector2) -> String:
	var best := ""
	var best_d := _repo.bal("war_intel_hint_px")
	for h: Dictionary in hints_on_sheet():
		var p: Variant = _view.screen_pos_of_px(h["at"])
		if p != null and (p as Vector2).distance_to(at) <= best_d:
			best_d = (p as Vector2).distance_to(at)
			best = String(h["id"])
	return best


## The chosen front's facing handle on the screen: {at, dir (where its teeth
## point), id}; {} when no front is chosen.
func _facing_handle() -> Dictionary:
	if not chosen_id.begins_with("s"):
		return {}
	var s: Dictionary = _view.state().war_plans[WarPlans.STROKES].get(chosen_id, {})
	if s.is_empty() or not bool(_repo.war_plan_kinds.get(String(s["kind"]), {}).get("teeth", false)):
		return {}
	var row := _on_screen(s, WarPlans.points_px(_repo, s), 0.0)
	if row.is_empty():
		return {}
	var path := WarPlanGeometry.curve(row["ctrl"], 4.0)
	var half := WarPlanGeometry.cut(path, 0.0, WarPlanGeometry.length(path) * 0.5)
	if half.size() < 2:
		return {}
	var at := half[half.size() - 1]
	var dir := WarPlanGeometry.right_of((at - half[half.size() - 2]).normalized()) * (-1.0 if int(s.get("flip", 0)) != 0 else 1.0)
	return {"at": at + dir * _repo.bal("war_plan_facing_px") * 0.9, "dir": dir, "id": chosen_id}


## A stroke's control points with handle `i` dragged to `to` (pack px): a
## ring's handle 0 is its centre, 1 its radius.
func _reshaped(s: Dictionary, i: int, to: Vector2) -> Dictionary:
	var pts := WarPlans.points_px(_repo, s)
	var r := WarPlans.radius_px(_repo, s)
	if String(_repo.war_plan_kinds[String(s["kind"])]["gesture"]) == "ring":
		if i == 0:
			pts[0] = to
		else:
			r = pts[0].distance_to(to)
	elif i >= 0 and i < pts.size():
		pts[i] = to
	return {"pts": pts, "r": r}


# --- on the screen -----------------------------------------------------------

## Screen px a pack px at a pack point now.
func px_per_pack(at: Vector2) -> float:
	var a: Variant = _view.screen_pos_of_px(at)
	var b: Variant = _view.screen_pos_of_px(at + Vector2(1, 0))
	return (b as Vector2).distance_to(a) if a != null and b != null else 1.0


## Screen px a table millimetre at a pack point now.
func px_per_mm(at: Vector2) -> float:
	var rect := _view.sheet_rect()
	return px_per_pack(at) * rect.size.x / (_repo.bal("war_table_w_m") * 1000.0)


## The laid sheet's strokes on the screen: {id, kind, ctrl, r} in screen px
## (a stroke with a point behind the camera left out).
func strokes_on_screen() -> Array:
	var out: Array = []
	var st := _view.state()
	if st == null or _view.sheet_index() < 0:
		return out
	for s: Dictionary in WarPlans.strokes_in(_repo, st, _view.sheet_rect()):
		var row := _on_screen(s, WarPlans.points_px(_repo, s), WarPlans.radius_px(_repo, s))
		if not row.is_empty():
			out.append(row)
	return out


func _on_screen(s: Dictionary, pts: PackedVector2Array, r: float) -> Dictionary:
	var ctrl := PackedVector2Array()
	for p in pts:
		var at: Variant = _view.screen_pos_of_px(p)
		if at == null:
			return {}
		ctrl.append(at)
	var rr := r * px_per_pack(pts[0]) if r > 0.0 else 0.0
	return {"id": String(s.get("id", "")), "kind": String(s["kind"]), "ctrl": ctrl, "r": rr,
		"colour": String(s.get("colour", "ink")), "dashed": int(s.get("dashed", 0)), "flip": int(s.get("flip", 0)),
		"name": String(s.get("name", ""))}


## The live layer: the stroke being drawn, the stroke being dragged, the
## pending march's blue crayon arrow (each regiment's curve as the column
## will walk it — ArmySystem.curve_px — the lead's with its head), the chosen
## stroke's handles (a front's facing arrow too) and the chosen piece's ring.
func redraw_live() -> void:
	if _hud == null:
		return
	var st := _view.state()
	var ink := {"crayon": [], "pen": [], "names": []}
	var handles := PackedVector2Array()
	var centre := _view.sheet_rect().get_center()
	var mm := px_per_mm(centre)
	if tool.drawing and tool.preview().size() >= 2:
		var pts := tool.preview()
		var gesture := String(_repo.war_plan_kinds[tool.kind]["gesture"])
		var s := {"kind": tool.kind, "colour": tool.side, "dashed": 0, "flip": 0, "name": ""}
		var row := _on_screen(s, PackedVector2Array([pts[0]]) if gesture == "ring" else pts,
			pts[0].distance_to(pts[pts.size() - 1]) if gesture == "ring" else 0.0)
		if not row.is_empty():
			WarPlanInk.add(_repo, ink, row, _repo.war_plan_kinds[tool.kind], row["ctrl"], float(row["r"]), mm)
	_pending_order(ink, mm)
	if not _ghost.is_empty():
		if _view.plan_key_shown() == int(_ghost["key"]):
			_ghost = {}
		else:
			var g: Dictionary = _ghost
			var grow := _on_screen(g["s"], g["pts"], float(g["r"]))
			if not grow.is_empty():
				WarPlanInk.add(_repo, ink, grow, _repo.war_plan_kinds[String(g["s"]["kind"])], grow["ctrl"], float(grow["r"]), mm)
	if not _drag.is_empty() and bool(_drag["moved"]) and String(_drag["mode"]) in ["stroke", "handle"] and st != null:
		var s: Dictionary = st.war_plans[WarPlans.STROKES].get(String(_drag["id"]), {})
		if not s.is_empty():
			var to: Vector2 = _drag.get("to_pack", _drag["from_pack"])
			var pts := WarPlans.points_px(_repo, s)
			var r := WarPlans.radius_px(_repo, s)
			if String(_drag["mode"]) == "stroke":
				for i in pts.size():
					pts[i] += to - (_drag["from_pack"] as Vector2)
			else:
				var rs := _reshaped(s, int(_drag["handle"]), to)
				pts = rs["pts"]
				r = float(rs["r"])
			var row := _on_screen(s, pts, r)
			if not row.is_empty():
				WarPlanInk.add(_repo, ink, row, _repo.war_plan_kinds[String(s["kind"])], row["ctrl"], float(row["r"]), mm)
	if chosen_id.begins_with("s") and st != null:
		var s: Dictionary = st.war_plans[WarPlans.STROKES].get(chosen_id, {})
		if not s.is_empty():
			var row := _on_screen(s, WarPlans.points_px(_repo, s), WarPlans.radius_px(_repo, s))
			if not row.is_empty():
				handles = WarPlanTool.handles_of(_repo, row)
	var facing := _facing_handle()
	var look := WarRoomInk.plan_look(_repo, WarRoomInk.tooth(), mm, _view.lettering(), _view.caps_font())
	var road := PackedVector2Array()   # the supply road under the pending march (ruling 14)
	if _view.aiming and not _view.rolling():
		for p: Vector2 in _view.supply_preview:
			var at: Variant = _view.screen_pos_of_px(p)
			if at != null:
				road.append(at)
		if road.size() >= 2:
			# it leaves the town's ring — or the plinth of a piece standing there: never drawn over a piece
			var off := _repo.bal("war_pick_px") * 0.85 if _view.piece_under(road[0]) != "" else _repo.bal("war_supply_lit_px")
			road = WarPlanGeometry.cut(road, off, WarPlanGeometry.length(road))
	if ink["crayon"].is_empty() and ink["pen"].is_empty() and handles.is_empty() and facing.is_empty() and road.size() < 2:
		_hud.clear_live()
		return
	var hr := _repo.bal("war_plan_handle_px")
	_hud.show_live(ink, look, handles, _repo.war_palette["chalk"], hr, facing, _repo.bal("war_plan_facing_px"))
	_hud.show_road(road, _repo.war_palette["supply_route"], _repo.bal("war_supply_route_px"), _repo.bal("war_supply_route_dash_px"))


## The march pending on the confirm (the view's aim_group, set by the order
## menu): each regiment's walked curve in blue crayon, the lead's an arrow
## with its head, the others a plain crayon line joining it (WarOrderArrows).
func _pending_order(ink: Dictionary, mm: float) -> void:
	if not _view.aiming or _view.aim_dest.x < 0.0 or _view.aim_code == "" or _view.rolling():
		return
	var group: Dictionary = _view.aim_group
	var codes: Array = group.keys()
	codes.erase(_view.aim_code)
	codes.sort()
	codes.push_front(_view.aim_code)
	var lines: Array = []
	for code: String in codes:
		var wps: Array = Array(_view.aim_waypoints) if code == _view.aim_code else Array(group[code])
		lines.append(WarOrderArrows.screen_line(_repo, _view, code, _view.position_of(code), wps, _view.aim_dest))
	# the crayon starts at the plinth's edge: a mark on the sheet never lies on a standing piece
	WarOrderArrows.add(_repo, ink, lines, "blue", _repo.bal("war_pick_px") * 0.85, mm)
