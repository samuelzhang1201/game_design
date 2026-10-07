class_name WarPlanInput
extends RefCounted
## The left button for the room's PLANS (spec 2026-10-07-war-room-
## annotations-and-planning-pieces §1.5, §1.6, §2.4): with a stick in hand a
## press-drag-release draws (WarPlanTool); with the piece slot a click on the
## table asks for the Place form; with the scraper a click removes what it
## lands on; with the hand a supposed piece is carried by a drag (a click
## chooses it), a stroke's handle reshapes it and its line moves it whole. A
## crown piece under the pointer is the rake's, never this. The live stroke
## is WarPlanHud's. It only says what was done; the screen writes it. Never
## reaches the autoload.

signal drawn(stroke: Dictionary)                       # {kind, colour, pts (pack px), r}
signal piece_moved(id: String, to_px: Vector2, facing_deg: int)
signal stroke_reshaped(id: String, pts: PackedVector2Array, r: float)
signal stroke_shifted(id: String, offset: Vector2)
signal chosen(id: String)                              # a supposed piece or a stroke; "" none
signal scraped(id: String)
signal piece_requested(pack_px: Vector2, screen_px: Vector2)
signal tool_changed

const PIECE := "piece"
const SCRAPE := "scrape"

var tool: WarPlanTool
var action := ""        # PIECE or SCRAPE in hand, else ""
var chosen_id := ""
var _view: WarRoomView
var _repo: DataRepository
var _hud: WarPlanHud
var _drag: Dictionary = {}


func setup(view: WarRoomView, repo: DataRepository, hud: WarPlanHud) -> void:
	_view = view
	_repo = repo
	_hud = hud
	tool = WarPlanTool.new(repo)


# --- what is in hand ----------------------------------------------------------

func pick_kind(k: String) -> void:
	action = ""
	tool.pick_kind(k)
	tool_changed.emit()


func pick_stick(s: String) -> void:
	action = ""
	tool.pick_stick(s)
	tool_changed.emit()


func pick_action(a: String) -> void:
	tool.put_down()
	action = "" if action == a else a
	tool_changed.emit()


## Esc: the stick or the action laid down; true when anything was in hand.
func put_down() -> bool:
	var held := tool.in_hand() or action != ""
	tool.put_down()
	action = ""
	_drag = {}
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
	if tool.in_hand():
		if pack.x < 0.0:
			return false
		tool.press(pack, pos)
		redraw_live()
		return true
	if action == PIECE:
		if pack.x < 0.0:
			return false
		piece_requested.emit(pack, pos)
		pick_action(PIECE)   # laid down: one piece a pick
		return true
	if _view.piece_under(pos) != "":
		return false
	var radius := _repo.bal("war_pick_px")
	var pid := _view.plan_pieces().pick(_view.camera(), _view.window_scale(), pos, radius)
	var hit := {} if pid != "" else WarPlanTool.hit(_repo, strokes_on_screen(), pos, chosen_id, radius)
	if action == SCRAPE:
		var gone := pid if pid != "" else String(hit.get("id", ""))
		if gone == "":
			return false
		scraped.emit(gone)
		return true
	if pid != "":
		_drag = {"mode": "piece", "id": pid, "from": pos, "from_pack": pack, "moved": false}
		return true
	if not hit.is_empty():
		_drag = {"mode": "handle" if int(hit["handle"]) >= 0 else "stroke", "id": String(hit["id"]),
			"handle": int(hit["handle"]), "from": pos, "from_pack": pack, "moved": false, "to_pack": pack}
		return true
	if chosen_id != "":
		choose("")
	return false


func _motion(mm: InputEventMouseMotion) -> bool:
	var pack := _view.pack_at(mm.position)
	if tool.drawing:
		tool.move(pack, mm.position)
		redraw_live()
		return true
	if _drag.is_empty():
		return false
	if not bool(_drag["moved"]) and mm.position.distance_to(_drag["from"]) < _repo.bal("war_rake_min_px"):
		return true
	_drag["moved"] = true
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
		var pack := _view.pack_at(mb.position)
		var d := tool.release(pack, mb.position, mb.shift_pressed, px_per_pack(pack if pack.x >= 0.0 else _view.sheet_rect().get_center()))
		redraw_live()
		if not d.is_empty():
			drawn.emit(d)
		return true
	if _drag.is_empty():
		return false
	var d := _drag
	_drag = {}
	var id := String(d["id"])
	if not bool(d["moved"]):
		choose(id)
		return true
	var to: Vector2 = d.get("to_pack", d["from_pack"])
	match String(d["mode"]):
		"piece":
			piece_moved.emit(id, to, int(d.get("facing", 0)))
		"stroke":
			stroke_shifted.emit(id, to - (d["from_pack"] as Vector2))
		"handle":
			var s: Dictionary = _view.state().war_plans[WarPlans.STROKES].get(id, {})
			if not s.is_empty():
				var r := _reshaped(s, int(d["handle"]), to)
				stroke_reshaped.emit(id, r["pts"], float(r["r"]))
	redraw_live()
	return true


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
## chosen stroke's handles and the chosen piece's chalk ring.
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
		var s := {"kind": tool.kind, "colour": tool.stick, "dashed": 0, "flip": 0, "name": ""}
		var row := _on_screen(s, PackedVector2Array([pts[0]]) if gesture == "ring" else pts,
			pts[0].distance_to(pts[pts.size() - 1]) if gesture == "ring" else 0.0)
		if not row.is_empty():
			WarPlanInk.add(_repo, ink, row, _repo.war_plan_kinds[tool.kind], row["ctrl"], float(row["r"]), mm)
	if not _drag.is_empty() and bool(_drag["moved"]) and String(_drag["mode"]) != "piece" and st != null:
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
	if chosen_id.begins_with("p") and st != null:
		var p: Dictionary = st.war_plans[WarPlans.PIECES].get(chosen_id, {})
		var at: Variant = _view.screen_pos_of_px(WarPlans.at_px(_repo, p)) if not p.is_empty() else null
		if at != null:
			handles.append(at)
	if ink["crayon"].is_empty() and ink["pen"].is_empty() and handles.is_empty():
		_hud.clear_live()
		return
	var look := WarRoomInk.plan_look(_repo, null, mm, _view.lettering(), _view.caps_font())
	var hr := _repo.bal("war_plan_handle_px")
	_hud.show_live(ink, look, handles, _repo.war_palette["chalk"], hr if chosen_id.begins_with("s") else _repo.bal("war_pick_px") * _repo.bal("war_hud_chalk_ratio"))
