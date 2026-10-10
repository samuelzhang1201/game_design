class_name WarPlanPieces
extends WarPieces
## The SUPPOSED enemy pieces on the table (owner 2026-10-07, spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.3, ruling 7): each
## WarPlans piece on the laid sheet is its arm's carved piece (GameArt.WAR_PIECES,
## artillery the trebuchet) in PALE BOXWOOD (wood_piece's instance `blank`,
## war_plan_blank; `boxwood` war_palette plan_boxwood) on a plinth lacquered
## in its side's colour (Unknown: plan_unknown), its paper tag in PENCIL. The
## crown's pieces' seat, picking and tags are WarPieces'; a supposed piece is
## never pushed — it stands where the player set it, and a drag carries it
## (`follow`). Never reaches the Game autoload.

var _plan_sig: Dictionary = {}   # id -> [arm, side]


## Every supposed piece on the laid sheet, built anew.
func rebuild(state: GameState) -> void:
	_clear()
	_plan_sig.clear()
	update(state)


## The plans changed: a new piece built, a gone one freed, a changed arm or
## side rebuilt, every one stood at its place, faced and tagged.
func update(state: GameState) -> void:
	var keep: Dictionary = {}
	for p: Dictionary in WarPlans.pieces_in(_repo, state, _view.sheet_rect()):
		var id := String(p["id"])
		keep[id] = true
		var node := piece(id)
		var sig := [String(p["arm"]), String(p["side"])]
		if node != null and sig != _plan_sig.get(id, []):
			_remove(node)
			node = null
		if node == null:
			node = _build_plan(p)
			add_child(node)
			_glow(node)
			_plan_sig[id] = sig
		_stand(node, p["at"], int(p["facing_deg"]))
		(node.get_node("Tag") as Label3D).text = tag_text(_repo, p)
	for c: Node in get_children():
		if not keep.has(String(c.get_meta("code", ""))):
			_plan_sig.erase(String(c.get_meta("code", "")))
			_remove(c)


## A drag carries a supposed piece: stood at `pack_px`, turned to `facing_deg`
## (presentation only; the drop writes it through the screen).
func follow(id: String, pack_px: Vector2, facing_deg: int) -> void:
	var node := piece(id)
	if node != null:
		_stand(node, pack_px, facing_deg)


## "supposed · 2,000 foot".
static func tag_text(repo: DataRepository, p: Dictionary) -> String:
	return "supposed · %s %s" % [Intel.num(int(p["heads"])), WarGround.arm_word(repo, String(p["arm"]))]


## The facing in whole degrees of a heading in pack px (y down): 0 east, 90 south.
static func facing_of(heading: Vector2) -> int:
	return posmod(int(round(rad_to_deg(heading.angle()))), 360)


func _stand(node: Node3D, pack_px: Vector2, facing_deg: int) -> void:
	node.position = _seated(pack_px, node.get_meta("half", Vector2.ZERO))
	var figure := node.get_node_or_null("Piece") as Node3D
	if figure != null:
		var at := Vector2(node.position.x, node.position.z)
		var art: Dictionary = _repo.army_art.get(String(node.get_meta("arm", "")), {})
		figure.rotation.y = Map3DUnits.yaw_for(Vector2.from_angle(deg_to_rad(float(facing_deg))), at + Vector2(0.0, 1.0),
			at, float(art.get("stand_deg", "0")))


func _build_plan(p: Dictionary) -> Node3D:
	var id := String(p["id"])
	var root := Node3D.new()
	root.name = id
	root.set_meta("code", id)
	root.set_meta("plan", true)
	root.set_meta("arm", String(p["arm"]))
	var across := _repo.bal("war_piece_plinth_mm") / 1000.0
	root.set_meta("half", Vector2.ONE * across * 0.5)
	var top := 0.0
	var path := GameArt.path(GameArt.WAR_PIECES, String(p["arm"]))
	if path != "" and ResourceLoader.exists(path):
		if not _scenes.has(path):
			_scenes[path] = load(path)
		var figure := (_scenes[path] as PackedScene).instantiate() as Node3D
		figure.name = "Piece"
		figure.scale = Vector3.ONE * across
		var side := String(p["side"])
		var lacquer: Color = _repo.war_palette["plan_unknown"] if side == WarPlans.UNKNOWN \
			else MapPalette.color_of(_repo, side).darkened(_repo.bal("war_base_darken"))
		for m: MeshInstance3D in Map3DUnits.meshes(figure):
			m.set_instance_shader_parameter("lacquer", lacquer)
			m.set_instance_shader_parameter("blank", _repo.bal("war_plan_blank"))
			m.set_instance_shader_parameter("boxwood", _repo.war_palette["plan_boxwood"])
			if m.mesh != null:
				top = maxf(top, (m.transform * m.mesh.get_aabb()).end.y * across)
		root.add_child(figure)
	root.set_meta("top_m", top)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = tag_text(_repo, p)
	tag.font_size = int(_repo.bal("war_tag_font_px"))
	tag.pixel_size = (_repo.bal("war_piece_base_mm") / 1000.0) / _repo.bal("war_tag_width_px")
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = _repo.war_palette["pencil"]
	tag.outline_modulate = _repo.war_palette["paper"]
	tag.outline_size = int(_repo.bal("war_tag_outline_px"))
	tag.visible = tags_shown()
	tag.position = Vector3(across * _repo.bal("war_tag_offset"), top, 0.0)
	root.add_child(tag)
	return root
