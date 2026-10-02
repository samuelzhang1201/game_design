class_name WarRoomRake
extends RefCounted
## The player's rake and the room's left button (spec 2026-10-01-war-room-design
## §3): a click picks, in turn, an edge arrow, the wall chart, a pennant (its
## Edit route / Cancel march), a piece, else the ground of an armed march; a
## press on a piece that moves war_rake_min_px takes up the RAKE — the view
## signals `rake_started`, the screen arms the march (or refuses and calls
## `cancel`), an ink arrow follows the pointer reading the distance and the
## days at the regiment's own pace, and its release on the table is the
## destination (`ground_clicked`, which asks COMMIT / CANCEL). Draws through
## WarHud. Never reaches the Game autoload.

var code := ""                    # the regiment under the rake
var to := Vector2(-1, -1)         # the arrow's tip, screen px; (-1, -1) none
var _press_code := ""
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


## The rake let go (refused, the aim ended): no arrow.
func cancel() -> void:
	code = ""
	_press_code = ""
	to = Vector2(-1, -1)
	redraw()


## A rake in hand is given up for good (released off the table, cut by a sheet
## rolling): the view says so (`rake_dropped`), for the screen to withdraw the
## armed march with it. Nothing in hand, nothing said.
func drop() -> void:
	var held := code != ""
	cancel()
	if held:
		_view.rake_dropped.emit()


## "<distance> <unit> · ~<days> day(s)" from the regiment to a pack point, in
## the pack's own measure; "cannot march" for a banner with no one to march.
func reading(regiment: String, to_px: Vector2) -> String:
	var state := _view.state()
	var from := _view.position_of(regiment)
	var unit := String(_repo.map_info.get("distance_unit", "")).strip_edges()
	var dist := from.distance_to(to_px) * float(_repo.map_info.get("distance_scale", "1"))
	var text := "%s %s" % [WarRoom.group(int(round(dist))), unit if unit != "" else "km"]
	if ArmySystem.day_march_m(_repo, state, regiment) <= 0:
		return text + " · cannot march"
	var days := ArmySystem.march_days(_repo, state, regiment, from.distance_to(to_px) * float(ArmySystem.metres_per_pack_px(_repo)))
	return text + " · ~%d day%s" % [days, "" if days == 1 else "s"]


func on_left(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		_press_at = mb.position
		_pressed = true
		_press_code = _view.piece_under(mb.position)
		return
	if not _pressed:
		return
	_pressed = false
	var moved := mb.position.distance_to(_press_at) >= _repo.bal("war_rake_min_px")
	if code != "":
		var px := _view.pack_at(mb.position)
		to = mb.position
		if _view.aiming and px.x >= 0.0:
			code = ""
			_view.ground_clicked.emit(px, mb.position)
		else:
			drop()   # off the table: no destination, so the armed march goes too
		redraw()
		_view.accept_event()
		return
	if moved and not (_view.aiming and _press_code == ""):
		return
	var scale := _view.window_scale()
	var arrow := WarRoomWall.pick_arrow(_arrows, _camera, mb.position, scale, _repo.bal("war_pick_px"))
	var chart := -1 if arrow >= 0 else WarRoomWall.pick_chart(_chart, _camera, _repo, mb.position * scale)
	var radius := _repo.bal("war_pick_px")
	var pennant := "" if _view.rolling() else WarRoomPicks.nearest(_pennants.screen_hits(_camera, scale), mb.position, radius)
	var piece := _view.piece_under(mb.position)
	# what stands ON the sheet (a pennant, a piece) is picked before the flat
	# chart its top may be drawn over (v2 B: a piece at a sheet's north edge
	# throws its pennant's head over the index chart)
	if pennant != "":
		_view.route_clicked.emit(pennant, mb.position)
	elif piece != "":
		_view.select(piece)
	elif arrow >= 0:
		_view.sheet_requested.emit(arrow)   # an edge arrow lays at once
	elif chart >= 0:
		_view.toss_to(chart)                # a chart cell: the marker is tossed first
	elif _view.aiming and _view.pack_at(mb.position).x >= 0.0:
		_view.ground_clicked.emit(_view.pack_at(mb.position), mb.position)
	elif _view.selected_army() != "":
		_view.clear_selection()
	else:
		return
	_view.accept_event()


func on_motion(mm: InputEventMouseMotion) -> void:
	if _pressed and code == "" and _press_code != "" \
			and mm.position.distance_to(_press_at) >= _repo.bal("war_rake_min_px"):
		code = _press_code
		_press_code = ""
		to = mm.position
		_view.rake_started.emit(code)   # the screen arms the march, or calls cancel
	elif _view.aiming and _view.aim_dest.x < 0.0:
		to = mm.position
	else:
		return
	redraw()


## The arrow (from the piece to the pointer, or to the held destination,
## dashed) and the chalk ring round the chosen piece, onto the HUD.
func redraw() -> void:
	var pal: Dictionary = _repo.war_palette
	var from := Vector2(-1, -1)
	var tip := Vector2(-1, -1)
	var text := ""
	var held := _view.aim_dest.x >= 0.0
	var who := code if code != "" else (_view.aim_code if _view.aiming else "")
	if _view.rolling():
		who = ""   # the table is rolling up: the pieces, pennants and their marks are put away
	if who != "":
		var home := _view.position_of(who)
		var at: Variant = _view.screen_pos_of_px(home) if _view.sheet_rect().has_point(home) else null
		if at != null:
			from = at
			var px := Vector2(-1, -1)
			if held:
				var end: Variant = _view.screen_pos_of_px(_view.aim_dest)
				tip = end if end != null else tip
				px = _view.aim_dest
			elif to.x >= 0.0:
				tip = to
				px = _view.pack_at(to)
			text = reading(who, px) if px.x >= 0.0 else ""
	var chalk := Vector2(-1, -1)
	var node := _pieces.piece(_view.selected_army()) if _view.selected_army() != "" else null
	if node != null and not _view.rolling() and not _camera.is_position_behind(node.global_position):
		chalk = _camera.unproject_position(node.global_position) / _view.window_scale()
	_hud.draw_state(from, tip, text, chalk, _repo.bal("war_pick_px") * _repo.bal("war_hud_chalk_ratio"),
		pal["ink"], pal["arrow"], pal["chalk"], _view.lettering(), held, _routes(), _drafts(), pal["pencil"])


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
		var node := _pieces.piece(String(p["code"]))   # where the piece stands now, mid-push included
		var a: Variant = _view.screen_pos_of_px(p["at"]) if node == null or _camera.is_position_behind(node.global_position) \
			else _camera.unproject_position(node.global_position) / _view.window_scale()
		var b: Variant = _view.screen_pos_of_px(pen["at"])
		if a != null and b != null:
			out.append([a, b])
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
			out.append([a, b])
	return out


## A left press on open table with nothing in hand and no march armed: a drag
## from it pans the room (spec 2026-10-02-war-room-v2 §1.1), as on the 3D map.
func empty_press() -> bool:
	return _pressed and _press_code == "" and code == "" and not _view.aiming


## A left release that ends a press which moved (a pan), so it is no click.
func empty_press_moved(at: Vector2) -> bool:
	return _pressed and at.distance_to(_press_at) >= _repo.bal("war_rake_min_px")


## The press was taken by something else (the easel): the rake forgets it.
func forget_press() -> void:
	_pressed = false
	_press_code = ""
