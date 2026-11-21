extends SceneTree
## The model SCENE of another body installed by game_export.py (ARM): scenes/models/units/<ARM>.tscn,
## an inherited scene of assets/3D/units/<ARM>/<ARM>.glb whose mesh wears the INFANTRY scene's
## material with this arm's three atlas files — what the editor's New Inherited Scene and the
## inspector make (Godot does not let a script pack a fresh inherited root, so a new scene starts
## from the three lines New Inherited Scene writes). Registers the scene in GameArt.ARMY_MODELS.
## Run after a fresh import of the .glb:
##
##   Godot --headless --path . -s res://tools/units3d/infantry_arp/make_scene.gd -- ARM
##
## A scene already there keeps its UID. A script run (-s) writes every ext_resource by path alone:
## put each one's uid back afterwards (from its .import, header or .gd.uid) in the scene and in
## army_models.tres, and check `git diff`. Every value is a starting point for the editor: the look
## is tuned in the scene afterwards.

const NOTE := "One FIGURE of a %s regiment's piece: the body game_export.py installed (tools/units3d/infantry_arp/README.md) on the infantry's rig and clips. The 3D map (Map3DLayerUnits) stands instances of this scene in formation and plays its clips by order. Its material, shadow and look are edited HERE; the clips' loops are the .glb's import settings; its sizes are data/screens/map3d/army_art.csv."


func _init() -> void:
	var arm: String = OS.get_cmdline_user_args()[0]
	var dir := "res://assets/3D/units/%s/" % arm
	var path := "res://scenes/models/units/%s.tscn" % arm
	if not FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s%s.glb" id="1_glb"]\n\n[node name="%s" instance=ExtResource("1_glb")]\n' % [dir, arm, arm.to_pascal_case()])
		f.close()
	var uid := ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var infantry: Node = (load("res://scenes/models/units/infantry.tscn") as PackedScene).instantiate()
	var worn: MeshInstance3D = infantry.find_children("*", "MeshInstance3D", true, false)[0]
	var material: StandardMaterial3D = worn.get_surface_override_material(0).duplicate()
	infantry.free()
	material.resource_name = arm + "_atlas_mat"
	material.albedo_texture = load(dir + "%s_%s_atlas.jpg" % [arm, arm])
	material.metallic_texture = load(dir + "%s_%s_atlas_mr.jpg" % [arm, arm])
	material.roughness_texture = material.metallic_texture
	material.normal_texture = load(dir + "%s_%s_atlas_n.jpg" % [arm, arm])
	var base: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var scene_root := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	scene_root.editor_description = NOTE % arm.replace("_", " ")
	var mesh: MeshInstance3D = scene_root.find_children("*", "MeshInstance3D", true, false)[0]
	mesh.set_surface_override_material(0, material)
	var table: ArtTable = load(GameArt.ARMY_MODELS)
	var packed := PackedScene.new()
	packed.pack(scene_root)
	scene_root.free()
	print("%s: %s" % [path, error_string(ResourceSaver.save(packed, path))])
	ResourceSaver.set_uid(path, uid)  # a fresh PackedScene saves without one
	table.art[arm] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	var table_uid := ResourceLoader.get_resource_uid(GameArt.ARMY_MODELS)
	print("army_models.tres: ", error_string(ResourceSaver.save(table, GameArt.ARMY_MODELS)))
	ResourceSaver.set_uid(GameArt.ARMY_MODELS, table_uid)
	quit()

