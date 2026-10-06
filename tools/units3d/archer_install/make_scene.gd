extends SceneTree
## The archers' model SCENE: scenes/models/units/archers.tscn, an
## inherited scene of assets/3D/units/archers/archers.glb (install.py) whose mesh
## wears an editable copy of its material on the extracted maps — what the
## editor's New Inherited Scene and the inspector make, as the cavalry's
## scene is. Points army_models.tres's "archers" at it (until now the
## spearman stood in). Run after the .glb's
## import:
##
##   Godot --path . -s res://tools/units3d/archer_install/make_scene.gd
##
## A scene already there keeps its UID (the art table's reference). The
## material set here is a starting point: it is tuned in the scene afterwards.

const SCENE := "res://scenes/models/units/archers.tscn"
const GLB := "res://assets/3D/units/archers/archers.glb"
const MAPS := "res://assets/3D/units/archers/archers_archers_atlas%s.jpg"
const NOTE := "A longbowman, one FIGURE of an archers regiment's piece. The 3D map (Map3DLayerUnits) stands 9 / 6 / 3 instances of this scene in formation and plays its clips by order; the WAR ROOM paints tin over this material's albedo (WarPieces) and the folio inks the whole figure (WarInkFigure). Its material, shadow and look are edited HERE; the clips' loops are the .glb's import settings; its sizes are data/army_art.csv."


func _init() -> void:
	if not FileAccess.file_exists(SCENE):
		var f := FileAccess.open(SCENE, FileAccess.WRITE)
		f.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_glb"]\n\n[node name="Archers" instance=ExtResource("1_glb")]\n' % GLB)
		f.close()
	var uid := ResourceLoader.get_resource_uid(SCENE)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var base: PackedScene = ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var root := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	root.editor_description = NOTE
	var mi: MeshInstance3D = Map3DUnits.meshes(root)[0]
	var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
	var mat := StandardMaterial3D.new()
	mat.resource_name = "archers_atlas"
	mat.albedo_texture = load(MAPS % "")
	mat.metallic = 1.0
	mat.metallic_texture = load(MAPS % "_mr")
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.roughness_texture = mat.metallic_texture
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.normal_enabled = true
	mat.normal_texture = load(MAPS % "_n")
	if src != null:
		mat.cull_mode = src.cull_mode   # the delivery's doubleSided
	mi.set_surface_override_material(0, mat)
	for dep: String in [GLB, MAPS % "", MAPS % "_mr", MAPS % "_n"]:
		_register(dep)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	print("archers.tscn: ", error_string(ResourceSaver.save(packed, SCENE)))
	ResourceSaver.set_uid(SCENE, uid)
	var table: ArtTable = load(GameArt.ARMY_MODELS)
	table.art["archers"] = ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	for r: Resource in table.art.values():
		_register(r.resource_path)
	_register(table.get_script().resource_path)
	var table_uid := ResourceLoader.get_resource_uid(GameArt.ARMY_MODELS)
	print("army_models.tres: ", error_string(ResourceSaver.save(table, GameArt.ARMY_MODELS)))
	ResourceSaver.set_uid(GameArt.ARMY_MODELS, table_uid)
	quit()


## A script run (-s) does not load the editor's UID cache, so the saver
## writes every reference by path alone; each one is put in the cache from
## its own file (header or .import) first, so the references keep their UIDs.
func _register(path: String) -> void:
	var id := ResourceLoader.get_resource_uid(path)
	if id == ResourceUID.INVALID_ID:
		return
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
