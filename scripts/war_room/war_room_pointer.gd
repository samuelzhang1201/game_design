class_name WarRoomPointer
extends RefCounted
## The room's left button and its marks on the HUD (spec 2026-10-01-war-room-
## design §3, 2026-10-08-war-room-draw-orders rulings 11, 13, 16): a click
## picks, in turn, a pennant (its route menu), one of our pieces (selected —
## a town's garrison piece selects its every regiment; Shift adds or takes it
## out), an edge arrow, the wall chart, else the ground of a march waiting on
## its confirm (a lit town there is chosen to supply it); a click on open
## table lets the selection go. A drag pans, from a piece too (orders are
## DRAWN: WarPlanInput). While the confirm stands, a press near the pending
## route bends it. Draws through WarHud: the selection's rings in its side's
## colour, the chalk marquee, the intel hints' marching ants, the pennants'
## dashes, the drafts' pencils, the waypoints' rings, the towns that may supply
## the march and the bold dashed gold road from the chosen one. Never reaches
## the Game autoload.

var _bend := -1                   # the planned route's waypoint in hand, -1 none
var _press_at := Vector2.ZERO
var _pressed := false
var _view: WarRoomView
var _repo: DataRepository
var _hud: WarHud
var _pieces: WarPieces
var _pennants: WarPennants
var _camera: Camera3D
var _arrows: Node3D
var _chart: MeshInstance3D


func setup(view: WarRoomView, repo: DataRepository, nodes: Dictionary) -> void:
	_view = view
	_repo = repo
	_hud = nodes["hud"]
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
	var scale := _view.window_scale()
	var arrow := WarRoomWall.pick_arrow(_arrows, _camera, mb.position, scale, _repo.bal("war_pick_px"))
	var chart := -1 if arrow >= 0 else WarRoomWall.pick_chart(_chart, _camera, _repo, mb.position * scale)
	var radius := _repo.bal("war_pick_px")
	var pennant := "" if _view.rolling() else WarRoomPicks.nearest(_pennants.screen_hits(_camera, scale), mb.position, radius)
	var piece := _view.piece_under(mb.position)
	# what stands ON the sheet (a pennant, a piece) is picked before the flat
	# chart its top may be drawn over (v2 B: a piece at a sheet's north edge
	# throws its pennant's head over the index chart)
	if pennant != "" and not _view.aiming:
		_view.route_clicked.emit(pennant, mb.position)
	elif piece != "" and not _view.aiming:
		_view.select(piece, mb.shift_pressed)
	elif arrow >= 0:
		_view.sheet_requested.emit(arrow)   # an edge arrow lays at once
	elif chart >= 0:
		_view.toss_to(chart)                # a chart cell: the marker is tossed first
	elif _view.aiming and _view.pack_at(mb.position).x >= 0.0:
		_view.ground_clicked.emit(_view.pack_at(mb.position), mb.position)
	elif _view.has_selection():
		_view.clear_selection()
	else:
		return
	_view.accept_event()


func on_motion(mm: InputEventMouseMotion) -> void:
	if _bend < 0:
		return
	var px := _view.pack_at(mm.position)
	var wps := _view.aim_waypoints
	if px.x >= 0.0 and _bend < wps.size():
		wps[_bend] = px
		_view.aim_waypoints = wps   # redraws


## The HUD's marks: the selection's rings, the marquee, the hints, the
## pennants' dashes, the drafts' pencils, the pending route's rings, the
## supply pick.
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
	_hud.draw_state(rings, input.marquee(), hints, pal["plan_red"], pal["chalk"], _routes(), _drafts(), pal["ink"],
		pal["pencil"], _view.lettering())
	_hud.set_route(_handles(_view.aim_code if _view.aiming else ""), pal["plan_blue"])
	_hud.set_supply(_supply_rings(), _supply_road(), pal["supply_route"])


## Where each selected thing stands on the screen: our pieces (a garrison's
## regiments share its piece), supposed pieces, intel hints.
func _selected_spots(input: WarPlanInput) -> Array:
	var out: Array = []
	var seen := {}
	var st := _view.state()
	for id: Variant in input.sel:
		var at: Variant = null
		if input.sel_side == "blue":
			var node := _pieces.piece(String(id))
			if node == null:
				for q: Dictionary in WarRoom.on_sheet(_repo, st, _view.sheet_index(), _view.drawn()):
					if String(id) in (q.get("garrison", [q["code"]]) as Array):
						node = _pieces.piece(String(q["code"]))
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


## The chosen supply town's road to the march's end, screen px.
func _supply_road() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in _view.supply_preview:
		var at: Variant = _view.screen_pos_of_px(p)
		if at != null:
			out.append(at)
	return out


## Each pennant's dashed line from its piece (where we know it stands) to the
## pennant, in screen px; none while the table rolls.
func _routes() -> Array:
	var out: Array = []
	if _view.rolling():
		return out
	var state := _view.state()
	for p: Dictionary in WarRoom.on_sheet(_repo, state, _view.sheet_index(), _view.drawn()):
		var pen := WarRoom.pennant_of(_repo, state, String(p["code"]))
		if pen.is_empty() or not _view.sheet_rect().has_point(pen["at"]):
			continue
		var bend := _pennant_waypoints(String(p["code"]), pen)
		var node := _pieces.piece(String(p["code"]))   # where the piece stands now, mid-push included
		var a: Variant = _view.screen_pos_of_px(p["at"]) if node == null or _camera.is_position_behind(node.global_position) \
			else _camera.unproject_position(node.global_position) / _view.window_scale()
		var b: Variant = _view.screen_pos_of_px(pen["at"])
		if a != null and b != null:
			out.append(_screen_curve(p["at"], pen["at"], a, bend) if not bend.is_empty() else PackedVector2Array([a, b]))
	return out


## Each march draft's pencil line from its piece to its draft pennant, in
## screen px (spec 2026-10-02-war-room-v2 §3.1); none while the table rolls.
func _drafts() -> Array:
	var out: Array = []
	if _view.rolling():
		return out
	var state := _view.state()
	for p: Dictionary in WarRoom.on_sheet(_repo, state, _view.sheet_index(), _view.drawn()):
		var d := WarDrafts.of(state, String(p["code"]))
		if String(d.get("order", "")) != WarDrafts.MARCH:
			continue
		var to := WarDrafts.dest_px(_repo, d)
		if not _view.sheet_rect().has_point(to):
			continue
		var node := _pieces.piece(String(p["code"]))
		var a: Variant = _view.screen_pos_of_px(p["at"]) if node == null or _camera.is_position_behind(node.global_position) \
			else _camera.unproject_position(node.global_position) / _view.window_scale()
		var b: Variant = _view.screen_pos_of_px(to)
		if a != null and b != null:
			var wps := Array(WarDrafts.waypoints_px(_repo, d))
			out.append(_screen_curve(p["at"], to, a, wps) if not wps.is_empty() else PackedVector2Array([a, b]))
	return out


## The curve from `from_px` through `waypoints` (the planned ones when none are
## given) to `to_px`, in screen px, its first point `start` (where the piece
## stands drawn) — the line the column will walk (ArmySystem.curve_px).
func _screen_curve(from_px: Vector2, to_px: Vector2, start: Vector2, waypoints: Variant = null) -> PackedVector2Array:
	var wps: Array = Array(_view.aim_waypoints) if waypoints == null else waypoints
	var out := PackedVector2Array([start])
	var curve := ArmySystem.curve_px(_repo, from_px, wps, to_px)
	for i in range(1, curve.size()):
		var at: Variant = _view.screen_pos_of_px(curve[i])
		if at != null:
			out.append(at)
	return out


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
