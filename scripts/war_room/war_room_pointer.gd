class_name WarRoomPointer
extends RefCounted
## The room's left button and its marks on the HUD (spec 2026-10-01-war-room-
## design §3, 2026-10-08-war-room-draw-orders rulings 11, 13, 16): a click
## picks, in turn, a pennant (its route menu), one of our pieces (its unit
## selected; Shift adds or takes it out), an edge arrow, the wall chart, else the ground of a march waiting on
## its confirm (a lit town there is chosen to supply it); a click on open
## table lets the selection go. A drag pans, from a piece too (orders are
## DRAWN: WarPlanInput). While the confirm stands, a press near the pending
## route bends it. Draws through WarHud: the selection's rings in its side's
## colour, the chalk marquee, the intel hints' marching ants, every march's
## BLUE CRAYON ARROW — drafted or sealed, never a dashed line (WarOrderArrows;
## none for a regiment whose march the confirm is drawing), the waypoints'
## rings and the towns that may supply the march.
## Never reaches the Game autoload.

var _bend := -1                   # the planned route's waypoint in hand, -1 none
var _press_at := Vector2.ZERO
var _pressed := false
var _view: WarRoomView
var _repo: DataRepository
var _hud: WarHud
var _plan_hud: WarPlanHud
var _pieces: WarPieces
var _pennants: WarPennants
var _camera: Camera3D
var _arrows: Node3D
var _chart: MeshInstance3D


func setup(view: WarRoomView, repo: DataRepository, nodes: Dictionary) -> void:
	_view = view
	_repo = repo
	_hud = nodes["hud"]
	_plan_hud = nodes["plan_hud"]
	_pieces = nodes["pieces"]
	_pennants = nodes["pennants"]
	_camera = nodes["camera"]
	_arrows = nodes["arrows"]
	_chart = nodes["chart"]
	_hud.setup(repo)


func on_left(mb: InputEventMouseButton) -> void:
	if mb.pressed and _press_bend(mb.position):
		_view.accept_event()   # a waypoint in hand: no pick, no pan
		return
	if not mb.pressed and _bend >= 0:
		_bend = -1
		_pressed = false
		_view.route_bent.emit(_view.aim_waypoints)
		_view.accept_event()
		return
	if mb.pressed:
		_press_at = mb.position
		_pressed = true
		return
	if not _pressed:
		return
	_pressed = false
	if mb.position.distance_to(_press_at) >= _repo.bal("war_rake_min_px"):
		return   # a pan, not a click
	if click(mb.position, mb.shift_pressed):
		_view.accept_event()


## A click at `at` (screen px): a pennant, one of our pieces, an edge arrow, the wall chart,
## the ground of a march aiming, else the selection goes; true when it took the click.
func click(at: Vector2, shift: bool) -> bool:
	var scale := _view.window_scale()
	var arrow := WarRoomWall.pick_arrow(_arrows, _camera, at, scale, _repo.bal("war_pick_px"))
	var chart := -1 if arrow >= 0 else WarRoomWall.pick_chart(_chart, _camera, _repo, at * scale)
	var radius := _repo.bal("war_pick_px")
	var pennant := "" if _view.rolling() else WarRoomPicks.nearest(_pennants.screen_hits(_camera, scale), at, radius)
	var piece := _view.piece_under(at)
	# what stands ON the sheet (a pennant, a piece) is picked before the flat
	# chart its top may be drawn over (v2 B: a piece at a sheet's north edge
	# throws its pennant's head over the index chart)
	if pennant != "" and not _view.aiming:
		_view.route_clicked.emit(pennant, at)
	elif piece != "" and not _view.aiming:
		_view.select(piece, shift)
	elif arrow >= 0:
		_view.sheet_requested.emit(arrow)   # an edge arrow lays at once
	elif chart >= 0:
		_view.toss_to(chart)                # a chart cell: the marker is tossed first
	elif _view.aiming and _view.pack_at(at).x >= 0.0:
		_view.ground_clicked.emit(_view.pack_at(at), at)
	elif _view.has_selection():
		_view.clear_selection()
	else:
		return false
	return true


func on_motion(mm: InputEventMouseMotion) -> void:
	if _bend < 0:
		return
	var px := _view.pack_at(mm.position)
	var wps := _view.aim_waypoints
	if px.x >= 0.0 and _bend < wps.size():
		wps[_bend] = px
		_view.aim_waypoints = wps   # redraws


## The HUD's marks: the selection's rings, the marquee, the hints, the
## marches' arrows, the pending route's rings, the supply pick.
func redraw() -> void:
	var pal: Dictionary = _repo.war_palette
	var input := _view.plan_input()
	var rings: Array = []
	if not _view.rolling() and input.sel_side != "":
		var colour: Color = pal["plan_blue"] if input.sel_side == "blue" else pal["plan_red"]
		var r := _repo.bal("war_pick_px") * _repo.bal("war_select_ring_ratio")
		for at: Vector2 in _selected_spots(input):
			rings.append({"at": at, "r": r, "colour": colour})
	var hints: Array = []
	if not _view.rolling():
		for h: Dictionary in input.hints_on_sheet():
			var at: Variant = _view.screen_pos_of_px(h["at"])
			if at != null:
				hints.append(at)
	_hud.draw_state(rings, input.marquee(), hints, pal["plan_red"], pal["chalk"])
	var groups := orders() if _view.sheet_index() >= 0 else []
	if groups.is_empty():
		_plan_hud.show_orders({}, {})
	else:   # under the pending crayon
		var mm := input.px_per_mm(_view.sheet_rect().get_center())
		_plan_hud.show_orders(_order_ink(groups, mm),
			WarRoomInk.plan_look(_repo, WarRoomInk.tooth(), mm, _view.lettering(), _view.caps_font()))
	_hud.set_route(_handles(_view.aim_code if _view.aiming else ""), pal["plan_blue"])
	_hud.set_supply(_supply_rings(), pal["supply_route"])


## Where each selected thing stands on the screen: our pieces (where each is
## drawn, spread clear of its neighbours), supposed pieces, intel hints.
func _selected_spots(input: WarPlanInput) -> Array:
	var out: Array = []
	var seen := {}
	var st := _view.state()
	for id: Variant in input.sel:
		var at: Variant = null
		if input.sel_side == "blue":
			var node := _pieces.piece(String(id))
			if node != null and not _camera.is_position_behind(node.global_position):
				at = _camera.unproject_position(node.global_position) / _view.window_scale()
		elif String(id).begins_with("p"):
			var p: Dictionary = st.war_plans[WarPlans.PIECES].get(String(id), {})
			at = _view.screen_pos_of_px(WarPlans.at_px(_repo, p)) if not p.is_empty() else null
		else:
			var h := WarRoom.hint_of(_repo, st, String(id))
			at = _view.screen_pos_of_px(h["at"]) if not h.is_empty() else null
		if at != null and not seen.has(Vector2i((at as Vector2).round())):
			seen[Vector2i((at as Vector2).round())] = true
			out.append(at)
	return out


## The towns that may supply the pending march, on the screen: [{at, lit}].
func _supply_rings() -> Array:
	var out: Array = []
	var pick: Dictionary = _view.supply_pick
	var towns: Array = pick.keys()
	towns.sort()
	for t: String in towns:
		var b: Dictionary = _repo.burgs.get(t, {})
		if b.is_empty():
			continue
		var px := Vector2(float(b["x"]), float(b["y"]))
		if not _view.sheet_rect().has_point(px):
			continue
		var at: Variant = _view.screen_pos_of_px(px)
		if at != null:
			out.append({"at": at, "lit": String(pick[t]) == ""})
	return out


## Every march of ours on the laid sheet as its blue crayon arrow (owner
## 2026-10-08, spec 2026-10-08-war-room-draw-orders rulings 10, 19): each
## SEALED march (its pennant on the sheet: riding, received, countermanded)
## and each DRAFT (not one the confirm is drawing again), from where its piece
## is drawn along the curve the column will walk to its end — so a marching
## arrow shortens as the piece advances. Columns on one drawn path are one
## arrow (WarOrderArrows.group). None while the table rolls.
## [{lead, kind, dest, members, lines: screen polylines, the lead's first}].
func orders() -> Array:
	var out: Array = []
	if _view.rolling():
		return out
	var state := _view.state()
	var rows: Array = []
	var from := {}
	var rect := _view.sheet_rect()
	for p: Dictionary in WarRoom.on_sheet(_repo, state, _view.sheet_index(), _view.drawn()):
		var code := String(p["code"])
		from[code] = p["at"]
		var pen := WarRoom.pennant_of(_repo, state, code)
		if not pen.is_empty() and rect.has_point(pen["at"]):
			rows.append({"code": code, "kind": WarOrderArrows.SEALED, "dest": pen["at"], "wps": _pennant_waypoints(code, pen)})
		var d := WarDrafts.of(state, code)
		if String(d.get("order", "")) != WarDrafts.MARCH \
				or (_view.aiming and (code == _view.aim_code or _view.aim_group.has(code))):
			continue   # a draft being drawn again shows only as the pending arrow
		var to := WarDrafts.dest_px(_repo, d)
		if rect.has_point(to):
			rows.append({"code": code, "kind": WarOrderArrows.DRAFT, "dest": to, "wps": Array(WarDrafts.waypoints_px(_repo, d))})
	for g: Dictionary in WarOrderArrows.group(rows):
		var lines: Array = []
		for c: String in g["members"]:
			var row: Dictionary = rows.filter(func(r: Dictionary) -> bool:
				return String(r["code"]) == c and String(r["kind"]) == String(g["kind"]))[0]
			lines.append(WarOrderArrows.screen_line(_repo, _view, c, from[c], row["wps"], g["dest"]))
		g["lines"] = lines
		out.append(g)
	return out


## The arrows' crayon, `mm` screen px a table mm: the sealed ones first, the
## drafts (paler, a pencil edge: palette plan_blue_draft) over them.
func _order_ink(groups: Array, mm: float) -> Dictionary:
	var ink := {"crayon": [], "pen": [], "names": []}
	for kind: String in [WarOrderArrows.SEALED, WarOrderArrows.DRAFT]:
		for g: Dictionary in groups:
			if String(g["kind"]) == kind:
				WarOrderArrows.add(_repo, ink, g["lines"], "blue_draft" if kind == WarOrderArrows.DRAFT else "blue",
					_repo.bal("war_pick_px") * 0.85, mm)
	return ink


## A pennant's waypoints still ahead: a riding march courier's, else the column's.
func _pennant_waypoints(code: String, pen: Dictionary) -> Array:
	var state := _view.state()
	if String(pen.get("status", "")) == "riding":
		var c := CourierSystem.pending_for(state, code)
		if not c.is_empty():
			return CourierSystem.waypoints_px(_repo, c.get("order", {}))
		return []
	return Array(ArmySystem.waypoints_of(_repo, state, code))


## The planned waypoints' rings in screen px, for the regiment being aimed.
func _handles(who: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	if who == "" or who != _view.aim_code:
		return out
	for w: Vector2 in _view.aim_waypoints:
		var at: Variant = _view.screen_pos_of_px(w)
		if at != null:
			out.append(at)
	return out


## A left press while the march's confirm stands (spec 2026-10-07-march-waypoints
## ruling 9): within war_route_grab_px of a waypoint takes it; of the line,
## inserts one there on the leg it lies on. True when a waypoint is in hand.
func _press_bend(at: Vector2) -> bool:
	if not _view.aiming or _view.aim_dest.x < 0.0 or _view.aim_code == "" or _view.rolling():
		return false
	for t: Dictionary in _supply_rings():
		if bool(t["lit"]) and (t["at"] as Vector2).distance_to(at) <= _repo.bal("war_supply_lit_px"):
			return false   # a lit town is chosen to supply the march, never a bend
	var grab := _repo.bal("war_route_grab_px")
	var wps := _view.aim_waypoints
	for i in wps.size():
		var s: Variant = _view.screen_pos_of_px(wps[i])
		if s != null and (s as Vector2).distance_to(at) <= grab:
			_bend = i
			return true
	var pts_m: Array = [ArmySystem.pack_to_metres(_repo, _view.position_of(_view.aim_code))]
	for w: Vector2 in wps:
		pts_m.append(ArmySystem.pack_to_metres(_repo, w))
	pts_m.append(ArmySystem.pack_to_metres(_repo, _view.aim_dest))
	var legs := MarchRoute.legs(pts_m, int(_repo.bal("army_route_sample_m")))
	var best := -1
	var best_d := grab
	for i in legs.size():
		var prev: Variant = _view.screen_pos_of_px(ArmySystem.metres_to_pack(_repo, pts_m[i]))
		for q: Vector2i in legs[i]:
			var s: Variant = _view.screen_pos_of_px(ArmySystem.metres_to_pack(_repo, q))
			if prev != null and s != null:
				var d := Geometry2D.get_closest_point_to_segment(at, prev, s).distance_to(at)
				if d <= best_d:
					best_d = d
					best = i
			prev = s
	var px := _view.pack_at(at)
	if best < 0 or px.x < 0.0:
		return false
	wps.insert(best, px)
	_bend = best
	_view.aim_waypoints = wps
	return true


## A left press that may pan: anything but a bend (a pan from a piece too).
func empty_press() -> bool:
	return _pressed and _bend < 0


## A left release that ends a press which moved (a pan), so it is no click.
func empty_press_moved(at: Vector2) -> bool:
	return _pressed and at.distance_to(_press_at) >= _repo.bal("war_rake_min_px")


## The press was taken by something else (the easel): it is forgotten.
func forget_press() -> void:
	_pressed = false
