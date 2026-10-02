class_name WarPieces
extends Node3D
## The crown's regiments as painted tin miniatures on bases (owner 2026-10-01,
## spec 2026-10-01-war-room-design §3): 9 / 6 / 3 figures of the regiment's
## chief arm frozen in its order's pose, a base painted the realm's colour with
## a brass name plate and the house's arms, a paper tag on a pin. Each stands
## where the 3D map draws it (WarRoomView.drawn, else WarRoom.believed_position;
## owner 2026-10-02); when that moves, the plotter's rake
## pushes it there over war_plot_push_s. Never reaches the Game autoload.


var _repo: DataRepository
var _view: WarRoomView
var _sig: Dictionary = {}     # code -> [pose, figures] it was built with
var _push: Dictionary = {}    # code -> {from: Vector3, to: Vector3, left: float}
var _scenes: Dictionary = {}  # model path -> PackedScene
var _tins: Dictionary = {}    # source material -> its one tin ShaderMaterial
var _tags_on := true          # the paper tags show only near the table (war_tag_view_m)


func setup(repo: DataRepository, view: WarRoomView) -> void:
	_repo = repo
	_view = view


## The tags are shown only while the camera stands within war_tag_view_m of the
## table, so the overview is not cluttered with slips (Task 16 ruling).
func set_camera_distance(metres: float) -> void:
	var on := metres <= _repo.bal("war_tag_view_m")
	if on == _tags_on:
		return
	_tags_on = on
	for c: Node in get_children():
		var tag := c.get_node_or_null("Tag") as Node3D
		if tag != null:
			tag.visible = on


func tags_shown() -> bool:
	return _tags_on


func piece(code: String) -> Node3D:
	for c: Node in get_children():
		if not c.is_queued_for_deletion() and String(c.get_meta("code", "")) == code:
			return c as Node3D
	return null


## Every piece of the laid sheet, freshly built and standing where we know it
## is (no push): a laid sheet, a changed regiment set.
func rebuild(state: GameState) -> void:
	_clear()
	for p: Dictionary in WarRoom.on_sheet(_repo, state, _view.sheet_index(), _view.drawn()):
		_add(state, String(p["code"]), bool(p["naval"]), _seated(p["at"], bool(p["naval"])))


## A state change: a moved piece is pushed over war_plot_push_s, a new piece
## built and a gone one freed, a changed pose or figure count rebuilt in place.
func update(state: GameState) -> void:
	var keep: Dictionary = {}
	for p: Dictionary in WarRoom.on_sheet(_repo, state, _view.sheet_index(), _view.drawn()):
		var code := String(p["code"])
		keep[code] = true
		var want := _seated(p["at"], bool(p["naval"]))
		var node := piece(code)
		if node != null and _signature(state, code) != _sig.get(code, []):
			var at := node.position
			_remove(node)
			node = _add(state, code, bool(p["naval"]), at)
		elif node == null:
			node = _add(state, code, bool(p["naval"]), want)
		if _push.has(code) and (_push[code]["to"] as Vector3).distance_to(want) <= 0.00001:
			pass   # already being pushed there: let the push finish
		elif node.position.distance_to(want) > 0.00001:
			_push[code] = {"from": node.position, "to": want, "left": _repo.bal("war_plot_push_s")}
			_face(node, code, Vector2(want.x - node.position.x, want.z - node.position.z))
		(node.get_node("Tag") as Label3D).text = WarRoom.tag_text(_repo, state, code)
	for c: Node in get_children():
		if not keep.has(String(c.get_meta("code", ""))):
			_remove(c)


## Whether any piece is being pushed now.
func pushing() -> bool:
	return not _push.is_empty()


## Test seam: finish every push now.
func settle() -> void:
	for code: String in _push:
		var n := piece(code)
		if n != null:
			n.position = _push[code]["to"]
	_push.clear()


func _process(delta: float) -> void:
	if _push.is_empty():
		return
	var total := maxf(_repo.bal("war_plot_push_s"), 0.0001) if _repo != null else 0.0001
	for code: String in _push.keys():
		var j: Dictionary = _push[code]
		j["left"] = float(j["left"]) - delta
		var n := piece(code)
		if n == null:
			_push.erase(code)
			continue
		var t := clampf(1.0 - float(j["left"]) / total, 0.0, 1.0)
		var pos: Vector3 = (j["from"] as Vector3).lerp(j["to"], t)
		pos.y = _seat_y(Vector2(pos.x, pos.z), bool(n.get_meta("naval", false)))
		n.position = pos
		if t >= 1.0:
			_push.erase(code)
	_view.redraw_marks()   # the chalk ring and the pennant's dashes follow a pushed piece, only while one moves


## Every piece on the screen (the view's design px): its base centre `at`, the
## `rect` its projected base box and figures' top cover (grown by nothing:
## pick() grows it), and its `depth` from the camera.
func screen_hits(camera: Camera3D, scale: float) -> Array:
	var out: Array = []
	var side := _repo.bal("war_piece_base_mm") / 1000.0
	var base_h := _repo.bal("war_piece_base_h_mm") / 1000.0
	for c: Node3D in get_children():
		if camera.is_position_behind(c.global_position):
			continue
		var naval := bool(c.get_meta("naval", false))
		var half := Vector2(side, side * (_repo.bal("war_base_naval_depth") if naval else 1.0)) * 0.5
		var top := base_h + (_repo.bal("war_token_h_mm") if naval else _repo.bal("war_piece_figure_mm")) / 1000.0
		var at := camera.unproject_position(c.global_position) / scale
		var rect := Rect2(at, Vector2.ZERO)
		for dx in [-half.x, half.x]:
			for dz in [-half.y, half.y]:
				for dy in [0.0, base_h, top]:
					var corner: Vector3 = c.global_position + Vector3(dx, dy, dz)
					if not camera.is_position_behind(corner):
						rect = rect.expand(camera.unproject_position(corner) / scale)
		out.append({"code": String(c.get_meta("code")), "at": at, "rect": rect,
			"depth": camera.global_position.distance_to(c.global_position)})
	return out


## The code of the piece under `at` (design px): a click inside a piece's rect
## (base box and figures) grown by `radius` picks it, the one nearest the
## camera when several overlap; "" when none.
func pick(camera: Camera3D, scale: float, at: Vector2, radius: float) -> String:
	var best := ""
	var best_depth := INF
	for h: Dictionary in screen_hits(camera, scale):
		if (h["rect"] as Rect2).grow(radius).has_point(at) and float(h["depth"]) < best_depth:
			best_depth = float(h["depth"])
			best = String(h["code"])
	return best


## A base's resting height at table point `xz`: level on the HIGHEST relief
## under its four corners (the base stays square to the table), so no corner
## sinks into the ground. The piece's origin is the base's underside.
func _seat_y(xz: Vector2, naval: bool) -> float:
	var side := _repo.bal("war_piece_base_mm") / 1000.0
	var half := Vector2(side, side * (_repo.bal("war_base_naval_depth") if naval else 1.0)) * 0.5
	var y := -INF
	for dx in [-half.x, half.x]:
		for dz in [-half.y, half.y]:
			y = maxf(y, _view.y_at(xz + Vector2(dx, dz)))
	return y


## Where a piece at pack point `pack_px` stands on the table, seated.
func _seated(pack_px: Vector2, naval := false) -> Vector3:
	var p := _view.table_point(pack_px)
	p.y = _seat_y(Vector2(p.x, p.z), naval)
	return p


func _clear() -> void:
	for c in get_children():
		_remove(c)
	_sig.clear()
	_push.clear()


func _remove(node: Node) -> void:
	_push.erase(String(node.get_meta("code", "")))
	remove_child(node)
	node.queue_free()


func _signature(state: GameState, code: String) -> Array:
	return [WarRoom.pose_action(ArmySystem.order_of(_repo, state, code)), WarFolio.figures(_repo, state, code)]


## Build a piece, stand it at `at`, pose it (after it is in the tree: an
## AnimationPlayer outside it ignores a seek) and turn it.
func _add(state: GameState, code: String, naval: bool, at: Vector3) -> Node3D:
	var node := _build(state, code, naval)
	node.position = at
	add_child(node)
	_pose(state, code, node)
	_face(node, code, ArmySystem.heading_of(_repo, state, code))
	return node


## The figures turn, the base stays square: a marching column faces its road,
## a pushed piece the way it is pushed, a standing one the camera (the room's
## south side), its arm's stand_deg off square.
func _face(node: Node3D, code: String, heading: Vector2) -> void:
	var figures := node.get_node_or_null("Figures") as Node3D
	if figures == null:
		return
	var art: Dictionary = _repo.army_art.get(MapObjects.regiment_arm(_repo, ArmySystem.regiment(_repo, code)), {})
	var at := Vector2(node.position.x, node.position.z)
	figures.rotation.y = Map3DUnits.yaw_for(heading, at + Vector2(0.0, 1.0), at, float(art.get("stand_deg", "0")))


func _build(state: GameState, code: String, naval: bool) -> Node3D:
	var root := Node3D.new()
	root.name = code
	root.set_meta("code", code)
	root.set_meta("naval", naval)
	var reg := ArmySystem.regiment(_repo, code)
	var side := _repo.bal("war_piece_base_mm") / 1000.0
	var base_h := _repo.bal("war_piece_base_h_mm") / 1000.0
	var inset := _repo.bal("war_arms_inset_m")
	var depth := side * (_repo.bal("war_base_naval_depth") if naval else 1.0)
	var base := MeshInstance3D.new()
	base.name = "Base"
	var box := BoxMesh.new()
	box.size = Vector3(side, base_h, depth)
	base.mesh = box
	var paint := StandardMaterial3D.new()
	paint.albedo_color = MapPalette.color_of(_repo, String(reg["kingdom_code"])).darkened(_repo.bal("war_base_darken"))
	paint.roughness = _repo.bal("war_base_roughness")
	base.material_override = paint
	base.position.y = base_h * 0.5
	root.add_child(base)
	var plate := Label3D.new()
	plate.name = "Plate"
	plate.text = String(reg.get("label", code))
	plate.font_size = int(_repo.bal("war_plate_font_px"))
	plate.pixel_size = side / _repo.bal("war_plate_width_px")
	plate.modulate = _repo.war_palette["brass"]
	plate.position = Vector3(0.0, base_h * 0.5, depth * 0.5 + inset)
	root.add_child(plate)
	var arms := Sprite3D.new()
	arms.name = "Arms"
	var path := HouseArms.resolved_path(_repo, HouseArms.key_of_house(_repo, state, HouseArms.royal_family(_repo)))
	if path != "" and ResourceLoader.exists(path):
		arms.texture = load(path)
		arms.pixel_size = base_h / 256.0
	arms.position = Vector3(side * 0.5 + inset, base_h * 0.5, 0.0)
	arms.rotation.y = PI * 0.5
	root.add_child(arms)
	var figures := Node3D.new()
	figures.name = "Figures"
	figures.position.y = base_h
	root.add_child(figures)
	if naval:
		_fill_token(reg, figures)
	else:
		_fill_figures(state, code, reg, figures)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = WarRoom.tag_text(_repo, state, code)
	tag.font_size = int(_repo.bal("war_tag_font_px"))
	tag.pixel_size = side / _repo.bal("war_tag_width_px")
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = _repo.war_palette["ink"]
	tag.outline_modulate = _repo.war_palette["paper"]
	tag.outline_size = int(_repo.bal("war_tag_outline_px"))
	tag.visible = _tags_on
	tag.position = Vector3(side * _repo.bal("war_tag_offset"), _repo.bal("war_piece_figure_mm") / 1000.0 + base_h, 0.0)
	root.add_child(tag)
	_sig[code] = _signature(state, code)
	return root


func _fill_figures(state: GameState, code: String, reg: Dictionary, into: Node3D) -> void:
	var arm := MapObjects.regiment_arm(_repo, reg)
	var art: Dictionary = _repo.army_art.get(arm, {})
	var model := GameArt.path(GameArt.ARMY_MODELS, arm)
	if model == "" or not ResourceLoader.exists(model):
		return
	if not _scenes.has(model):
		_scenes[model] = load(model)
	var scene: PackedScene = _scenes[model]
	var first := scene.instantiate() as Node3D
	var ext := Map3DUnits.stand_extent(first)
	var k := (_repo.bal("war_piece_figure_mm") / 1000.0) / maxf(Map3DUnits.model_size(first).y, 0.001)
	var n := WarFolio.figures(_repo, state, code)
	var row: Dictionary = {}
	for f: Dictionary in _repo.army_formations:
		if int(f["figures"]) == n:
			row = f
	if row.is_empty():
		push_error("WarPieces: no army_formations row for %d figures (%s)" % [n, code])
	var offs := Map3DFormation.offsets(row, ext, _repo.bal("war_piece_gap"), Map3DFormation.rank_depth(art))
	# The slots run from the front rank at 0 to the rear, so the formation is
	# CENTRED on its base (Task 16: it stood in the base's rear two thirds) and
	# its half extent is about that centre.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for o in offs:
		lo = Vector2(minf(lo.x, o.x), minf(lo.y, o.y))
		hi = Vector2(maxf(hi.x, o.x), maxf(hi.y, o.y))
	var mid := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5 + ext
	var fit := (_repo.bal("war_piece_base_mm") / 1000.0 * _repo.bal("war_figure_fill")) \
		/ maxf(maxf(half.x, half.y) * k, 0.0001)
	var form := Map3DFormation.build(scene, offs, first)
	form.name = "Formation"
	form.scale = Vector3.ONE * k * minf(fit, 1.0)
	form.position = Vector3(-mid.x, 0.0, -mid.y) * form.scale.x
	into.add_child(form)
	for m: MeshInstance3D in Map3DUnits.meshes(form):
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _tin_of(m.mesh.surface_get_material(i) as BaseMaterial3D))


## The tin paint over a source material's own albedo: one ShaderMaterial per
## source, shared by every figure that wears it (null: untextured white tin).
func _tin_of(src: BaseMaterial3D) -> ShaderMaterial:
	if _tins.has(src):
		return _tins[src]
	var mat := WarRoomMaterial.tin(_repo)
	mat.set_shader_parameter("has_tex", src != null and src.albedo_texture != null)
	if src != null:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("albedo_tint", src.albedo_color)
	_tins[src] = mat
	return mat


## A fleet's piece: a flat tin token on its base, painted the realm's colour.
func _fill_token(reg: Dictionary, into: Node3D) -> void:
	var token := MeshInstance3D.new()
	token.name = "Token"
	var cyl := CylinderMesh.new()
	var h := _repo.bal("war_token_h_mm") / 1000.0
	cyl.top_radius = _repo.bal("war_piece_base_mm") / 1000.0 * _repo.bal("war_token_radius_ratio")
	cyl.bottom_radius = cyl.top_radius
	cyl.height = h
	token.mesh = cyl
	var mat := WarRoomMaterial.tin(_repo)
	mat.set_shader_parameter("has_tex", false)
	mat.set_shader_parameter("albedo_tint", MapPalette.color_of(_repo, String(reg["kingdom_code"])))
	token.material_override = mat
	token.position.y = h * 0.5
	into.add_child(token)


## Freeze a piece's figures in its order's pose.
func _pose(state: GameState, code: String, node: Node3D) -> void:
	var form := node.get_node_or_null("Figures/Formation")
	if form == null:
		return
	var action := WarRoom.pose_action(ArmySystem.order_of(_repo, state, code))
	var frame := _repo.bal("war_pose_frame_" + action.to_lower())
	for a: AnimationPlayer in Map3DFormation.anims_of(form):
		var clip := Map3DUnits.clip_named(a, action)
		if clip != "":
			a.play(clip)
			a.seek(a.get_animation(clip).length * frame, true)
			a.pause()
