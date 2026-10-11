extends SceneTree
## The WAR ROOM's wooden pieces as scenes (spec 2026-10-06-war-room-wooden-pieces):
## scenes/models/war_room/piece_<model>.tscn, an inherited scene of
## assets/3D/war_room/piece_<model>/piece_<model>.glb whose surface wears
## scenes/war_room/materials/piece_<model>.tres (wood_piece.gdshader over the
## piece's own maps and lacquer mask) — what New Inherited Scene and the
## inspector make. Fills GameArt.WAR_PIECES: each ART piece key
## (MapObjects.army_piece) to its scene, artillery to the trebuchet (owner:
## 统一用投石机); the bombard is built and kept, in no row. Run after a fresh
## import of the .glb files:
##
##   Godot --path . -s res://tools/war_room/make_piece_scenes.gd
##
## NOT --headless: the dummy renderer leaves the shader's uniform defaults
## null. A scene or material already there keeps its UID. Every value set here
## is a starting point for the editor.

const SHADER := preload("res://scenes/war_room/wood_piece.gdshader")
const MODELS := ["infantry", "archers", "cavalry", "royal", "bombard", "trebuchet"]
## art piece key -> model
const KEYS := {"infantry": "infantry", "archers": "archers", "cavalry": "cavalry",
	"royal": "royal", "artillery": "trebuchet"}
const NOTE := "A WAR ROOM wooden piece (spec 2026-10-06-war-room-wooden-pieces): its plinth's foot is 1 across at the origin, its front toward -Z. WarPieces scales it to war_piece_plinth_mm and paints the plinth's lacquer the realm's colour (the instance uniform `lacquer`)."


func _init() -> void:
	var table_path := GameArt.WAR_PIECES
	var table: ArtTable = load(table_path) if ResourceLoader.exists(table_path) else ArtTable.new()
	var scenes: Dictionary = {}
	for model: String in MODELS:
		var dir := "res://assets/3D/war_room/piece_%s" % model
		var glb := "%s/piece_%s.glb" % [dir, model]
		var mat_path := "res://scenes/war_room/materials/piece_%s.tres" % model
		var mat := _material(dir, model, mat_path)
		if mat == null:
			continue
		var path := "res://scenes/models/war_room/piece_%s.tscn" % model
		if not FileAccess.file_exists(path):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_glb"]\n\n[node name="%s" instance=ExtResource("1_glb")]\n' % [glb, ("piece_" + model).to_pascal_case()])
			f.close()
		var uid := ResourceLoader.get_resource_uid(path)
		if uid == ResourceUID.INVALID_ID:
			uid = ResourceUID.create_id()
		var base: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var scene_root := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
		scene_root.editor_description = NOTE
		var mi := _first_mesh(scene_root)
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
		for dep: String in [glb, mat_path]:
			_register(dep)
		var packed := PackedScene.new()
		packed.pack(scene_root)
		scene_root.free()
		var err := ResourceSaver.save(packed, path)
		ResourceSaver.set_uid(path, uid)   # a fresh PackedScene saves without one
		print("%s -> %s (%s)" % [model, path, error_string(err)])
		scenes[model] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	for key: String in KEYS:
		if scenes.has(KEYS[key]):
			table.art[key] = scenes[KEYS[key]]
	for r: Resource in table.art.values():
		_register(r.resource_path)
	_register(table.get_script().resource_path)
	var table_uid := ResourceLoader.get_resource_uid(table_path)
	print("war_pieces.tres: ", error_string(ResourceSaver.save(table, table_path)))
	if table_uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(table_path, table_uid)
	quit()


## The piece's material, saved to `path` (its UID kept): the shader's
## defaults written out as the inspector does, and the piece's four maps.
func _material(dir: String, model: String, path: String) -> ShaderMaterial:
	var maps := {"albedo_tex": "albedo", "orm_tex": "orm", "normal_tex": "normal", "lacquer_tex": "lacquer"}
	var mat: ShaderMaterial = load(path) if ResourceLoader.exists(path) else ShaderMaterial.new()
	mat.shader = SHADER
	for u: Dictionary in SHADER.get_shader_uniform_list():
		var v: Variant = RenderingServer.shader_get_parameter_default(SHADER.get_rid(), u["name"])
		if v != null and mat.get_shader_parameter(u["name"]) == null:
			mat.set_shader_parameter(u["name"], v)
	for uniform: String in maps:
		var tex := "%s/piece_%s_%s.png" % [dir, model, maps[uniform]]
		if not ResourceLoader.exists(tex):
			push_error("%s: no %s" % [model, tex])
			return null
		_register(tex)
		mat.set_shader_parameter(uniform, load(tex))
	mat.resource_name = "piece_" + model
	_register(SHADER.resource_path)
	var uid := ResourceLoader.get_resource_uid(path)
	ResourceSaver.save(mat, path)
	if uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(path, uid)
	return load(path)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c: Node in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


## A script run (-s) does not load the editor's UID cache, so the saver writes
## every reference by path alone; each one is put in the cache from its own
## file (header or .import) first, so the references keep their UIDs.
func _register(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID:
		return
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, path)
	else:
		ResourceUID.add_id(uid, path)
