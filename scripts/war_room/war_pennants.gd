class_name WarPennants
extends Node3D
## Order pennants on the sheet (spec 2026-10-01-war-room-design §3): one per
## march order, planted at its destination; its slip reads "courier riding ·
## <the day he left>" until the courier hands the order over, then "order
## received" (a newer garrison courier turns it to "countermand riding");
## struck when the column arrives (WarRoom.pennant_of turns {}).
## A war-room DRAFT (spec 2026-10-02-war-room-v2 §3.1, WarDrafts) is a pale
## pennant of its own, `<code>_draft`, its slip "draft" (war_draft_alpha); a
## pencilled halt turns the real pennant's slip to "halt pencilled".
## Never reaches the Game autoload.

## A pennant's slip by status (the dated ones take the day their courier left).
const SLIPS := {"riding": "courier riding · %s", "countermanded": "countermand riding · %s",
		"received": "order received", "draft": "draft", "halt_draft": "halt pencilled",
		"refused": "not sent: %s"}

## The pennant's model (assets/3D/war_room/pennant: a red swallowtail on a
## brass pin with a paper slip, its foot at the origin), set in the scene;
## scaled to the pole height war_piece_figure_mm × war_pennant_h_ratio.
@export var model: PackedScene

var _repo: DataRepository
var _view: WarRoomView
var _sig: Array = []   # [sheet, [code, at, status, issued]...] it was built from
var _box := AABB()    # the model's box at its own scale, measured once


func setup(repo: DataRepository, view: WarRoomView) -> void:
	_repo = repo
	_view = view


## Plant what the state holds on the laid sheet; unchanged, nothing is rebuilt
## (`force`: a sheet was laid anew, the relief under the poles changed).
func rebuild(state: GameState, force := false) -> void:
	var rect: Rect2 = WarSheets.series(_repo)[_view.sheet_index()]["rect"] if _view.sheet_index() >= 0 else Rect2()
	var want: Array = []
	for p: Dictionary in WarRoom.pieces(_repo, state, _view.drawn()):
		var code := String(p["code"])
		var pen := WarRoom.pennant_of(_repo, state, code)
		var draft := WarDrafts.of(state, code)
		var order := String(draft.get("order", ""))
		var why := String(draft.get("refused", ""))
		if not pen.is_empty() and rect.has_point(pen["at"]):
			var status := String(pen["status"])
			if order == WarDrafts.GARRISON:
				status = "halt_draft" if why == "" else "refused"
			want.append([code, pen["at"], status, int(pen.get("issued", 0)), why])
		if order == WarDrafts.MARCH:
			var to := WarDrafts.dest_px(_repo, draft)
			if rect.has_point(to):
				want.append([code + "_draft", to, "draft" if why == "" else "refused", 0, why])
	var sig: Array = [_view.sheet_index(), want]
	if not force and sig == _sig:
		return
	_sig = sig
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for w: Array in want:
		add_child(_build(String(w[0]), w[1], String(w[2]), int(w[3]), String(w[4])))


func pennant(code: String) -> Node3D:
	return get_node_or_null(NodePath(code)) as Node3D


func _height() -> float:
	return _repo.bal("war_piece_figure_mm") / 1000.0 * _repo.bal("war_pennant_h_ratio")


## The model's box at its own scale (measured once).
func _model_box() -> AABB:
	if model == null:
		return AABB(Vector3.ZERO, Vector3(_height() * 0.5, _height(), 0.0))   # no art: the pole's own box
	if _box.size.y <= 0.0:
		var art := model.instantiate() as Node3D
		for m: MeshInstance3D in Map3DUnits.meshes(art):
			var a := m.transform * m.get_aabb()
			_box = a if _box.size.y <= 0.0 else _box.merge(a)
		art.free()
	return _box


## `why`: a refused draft's reason (spec §3.3: it stays a draft with its
## reason on its slip).
func _build(code: String, at: Vector2, status: String, issued: int, why := "") -> Node3D:
	var root := Node3D.new()
	root.name = code
	root.set_meta("code", code.trim_suffix("_draft"))
	root.set_meta("draft", code.ends_with("_draft"))
	root.position = _view.table_point(at)
	var h := _height()
	if model != null:
		var art := model.instantiate() as Node3D
		art.name = "Art"
		art.scale = Vector3.ONE * (h / _model_box().size.y)
		root.add_child(art)
	else:
		push_warning("WarPennants: no pennant model set in the scene; the slip stands alone")
	var slip := Label3D.new()
	slip.name = "Slip"
	if status == "refused":
		slip.text = SLIPS[status] % why
	else:
		slip.text = SLIPS[status] % CourierCard.date_of(issued) if SLIPS[status].contains("%s") else SLIPS[status]
	slip.font_size = int(_repo.bal("war_pennant_font_px"))
	slip.pixel_size = h / _repo.bal("war_pennant_pixel_ratio")
	slip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	slip.modulate = _repo.war_palette["ink"]
	slip.outline_modulate = _repo.war_palette["paper"]
	slip.outline_size = int(_repo.bal("war_pennant_outline_px"))
	slip.position.y = h * _repo.bal("war_pennant_slip_y")
	root.add_child(slip)
	if code.ends_with("_draft"):   # pencilled, not planted
		var alpha := _repo.bal("war_draft_alpha")
		for m: MeshInstance3D in Map3DUnits.meshes(root):
			m.transparency = 1.0 - alpha
		slip.modulate.a = alpha
		slip.outline_modulate.a = alpha
	return root


## Every pennant on the screen (the view's design px): `at` its foot, `rect`
## its pole, cloth and slip, `depth` from the camera (WarPieces.screen_hits'
## contract, so WarRoomPicks takes both the same way).
func screen_hits(camera: Camera3D, scale: float) -> Array:
	var out: Array = []
	var h := _height()
	for c: Node3D in get_children():
		if camera.is_position_behind(c.global_position):
			continue
		var at := camera.unproject_position(c.global_position) / scale
		var rect := Rect2(at, Vector2.ZERO)
		var slip := c.get_node("Slip") as Label3D
		var box := _model_box()
		var k := h / box.size.y
		var wide := box.end.x * k
		var span := (slip.get_aabb().size.x if slip.get_aabb().size.x > 0.0 else wide) * 0.5
		for corner: Vector3 in [Vector3(box.position.x * k, 0.0, 0.0), Vector3(wide, h, 0.0), Vector3(-span, slip.position.y, 0.0),
				Vector3(span, slip.position.y, 0.0)]:
			var world: Vector3 = c.global_position + corner
			if not camera.is_position_behind(world):
				rect = rect.expand(camera.unproject_position(world) / scale)
		out.append({"code": String(c.get_meta("code")), "at": at, "rect": rect,
			"depth": camera.global_position.distance_to(c.global_position)})
	return out
