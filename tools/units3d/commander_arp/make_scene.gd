extends SceneTree
## The mounted commander's model SCENE: scenes/models/units/commander.tscn, an inherited scene of
## assets/3D/units/commander/commander.glb (game_export.py) whose two surfaces each wear an editable
## copy of their material — what the editor's New Inherited Scene and the inspector make, as the
## cavalry's scene is. Run after the .glb's import:
##
##   Godot --headless --path . -s res://tools/units3d/commander_arp/make_scene.gd
##
## A scene already there keeps its UID. A script run (-s) writes every ext_resource by path alone:
## put each one's uid back afterwards (from its .import) and check `git diff`. Every value is a
## starting point for the editor: the look is tuned in the scene afterwards.

const SCENE := "res://scenes/models/units/commander.tscn"
const GLB := "res://assets/3D/units/commander/commander.glb"
const NOTE := "A unit's COMMANDER on the armoured horse, carrying his realm's banner (spec 2026-11-27-commander-figure-design): one figure, no men. Surface 0 is the body, horse and staff on the atlas; surface 1 is the banner's cloth, plain here: the game sets the realm's flag on it (Map3DCommanderFigure.set_flag). Clips MARCH (the gallop), MARCH_WALK, STANDBY, COMMAND; their loops are the .glb's import settings. Its materials, shadow and look are edited HERE."
## The cloth with no flag on it: undyed linen (a realm with no flag art keeps it).
const LINEN := Color(0.78, 0.74, 0.64)
const BACKLIGHT := 0.45  ## visual review 2026-11-27: at 0 a flag turned from the sun is black, at 0.3 a dark one still is, at 0.6 a pale one glows


func _init() -> void:
	if not FileAccess.file_exists(SCENE):
		var f := FileAccess.open(SCENE, FileAccess.WRITE)
		f.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_glb"]\n\n[node name="Commander" instance=ExtResource("1_glb")]\n' % GLB)
		f.close()
	var uid := ResourceLoader.get_resource_uid(SCENE)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var base: PackedScene = ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var scene_root := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	scene_root.editor_description = NOTE
	var mesh: MeshInstance3D = scene_root.find_children("*", "MeshInstance3D", true, false)[0]
	for i in mesh.mesh.get_surface_count():
		var mat: StandardMaterial3D = mesh.mesh.surface_get_material(i).duplicate()
		if mat.resource_name == "banner_cloth":
			mat.albedo_color = LINEN
			mat.backlight_enabled = true  # light through the sheet: the face turned from the sun keeps its colours
			mat.backlight = Color(BACKLIGHT, BACKLIGHT, BACKLIGHT)
		mesh.set_surface_override_material(i, mat)
	var packed := PackedScene.new()
	packed.pack(scene_root)
	scene_root.free()
	print("%s: %s" % [SCENE, error_string(ResourceSaver.save(packed, SCENE))])
	ResourceSaver.set_uid(SCENE, uid)  # a fresh PackedScene saves without one
	quit()
