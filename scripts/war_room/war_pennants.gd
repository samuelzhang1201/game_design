class_name WarPennants
extends Node3D
## Order pennants on the sheet (spec 2026-10-01-war-room-design §3): one per
## march order, planted at its destination; its slip reads "courier riding ·
## <the day he left>" until the courier hands the order over, then "order
## received" (a newer garrison courier turns it to "countermand riding");
## struck when the column arrives (WarRoom.pennant_of turns {}).
## Never reaches the Game autoload.

## A pennant's slip by status (the dated ones take the day their courier left).
const SLIPS := {"riding": "courier riding · %s", "countermanded": "countermand riding · %s",
		"received": "order received"}

var _repo: DataRepository
var _view: WarRoomView
var _sig: Array = []   # [sheet, [code, at, status, issued]...] it was built from


func setup(repo: DataRepository, view: WarRoomView) -> void:
	_repo = repo
	_view = view


## Plant what the state holds on the laid sheet; unchanged, nothing is rebuilt
## (`force`: a sheet was laid anew, the relief under the poles changed).
func rebuild(state: GameState, force := false) -> void:
	var rect: Rect2 = WarSheets.series(_repo)[_view.sheet_index()]["rect"] if _view.sheet_index() >= 0 else Rect2()
	var want: Array = []
	for p: Dictionary in WarRoom.pieces(_repo, state):
		var code := String(p["code"])
		var pen := WarRoom.pennant_of(_repo, state, code)
		if not pen.is_empty() and rect.has_point(pen["at"]):
			want.append([code, pen["at"], String(pen["status"]), int(pen.get("issued", 0))])
	var sig: Array = [_view.sheet_index(), want]
	if not force and sig == _sig:
		return
	_sig = sig
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for w: Array in want:
		add_child(_build(String(w[0]), w[1], String(w[2]), int(w[3])))


func pennant(code: String) -> Node3D:
	return get_node_or_null(NodePath(code)) as Node3D


func _height() -> float:
	return _repo.bal("war_piece_figure_mm") / 1000.0 * _repo.bal("war_pennant_h_ratio")


func _build(code: String, at: Vector2, status: String, issued: int) -> Node3D:
	var root := Node3D.new()
	root.name = code
	root.set_meta("code", code)
	root.position = _view.table_point(at)
	var h := _height()
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = _repo.bal("war_pennant_pole_m")
	cyl.bottom_radius = cyl.top_radius
	cyl.height = h
	pole.mesh = cyl
	pole.position.y = h * 0.5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = _repo.war_palette["table_wood"]
	pole.material_override = wood
	root.add_child(pole)
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	var q := QuadMesh.new()
	q.size = Vector2(h * _repo.bal("war_pennant_cloth_w"), h * _repo.bal("war_pennant_cloth_h"))
	cloth.mesh = q
	cloth.position = Vector3(q.size.x * 0.5, h * _repo.bal("war_pennant_cloth_y"), 0.0)
	var red := StandardMaterial3D.new()
	red.albedo_color = _repo.war_palette["pennant"]
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = red
	root.add_child(cloth)
	var slip := Label3D.new()
	slip.name = "Slip"
	slip.text = SLIPS[status] % CourierCard.date_of(issued) if SLIPS[status].contains("%s") else SLIPS[status]
	slip.font_size = int(_repo.bal("war_pennant_font_px"))
	slip.pixel_size = h / _repo.bal("war_pennant_pixel_ratio")
	slip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	slip.modulate = _repo.war_palette["ink"]
	slip.outline_modulate = _repo.war_palette["paper"]
	slip.outline_size = int(_repo.bal("war_pennant_outline_px"))
	slip.position.y = h * _repo.bal("war_pennant_slip_y")
	root.add_child(slip)
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
		var wide := h * _repo.bal("war_pennant_cloth_w")
		var span := (slip.get_aabb().size.x if slip.get_aabb().size.x > 0.0 else wide) * 0.5
		for corner: Vector3 in [Vector3.ZERO, Vector3(wide, h, 0.0), Vector3(-span, slip.position.y, 0.0),
				Vector3(span, slip.position.y, 0.0)]:
			var world: Vector3 = c.global_position + corner
			if not camera.is_position_behind(world):
				rect = rect.expand(camera.unproject_position(world) / scale)
		out.append({"code": String(c.get_meta("code")), "at": at, "rect": rect,
			"depth": camera.global_position.distance_to(c.global_position)})
	return out
