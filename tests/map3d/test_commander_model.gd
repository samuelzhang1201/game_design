extends GutTest
## The mounted commander's figure as installed (tools/units3d/commander_arp/; spec
## 2026-11-27-commander-figure-design): the cavalry's skeleton contract plus the banner's
## cloth chain, one mesh of two surfaces, four looping clips, and a cloth that takes any
## realm's flag. Nothing draws him on the map yet.

const SuiteData := preload("res://tests/suite_data.gd")

const GLB := "res://assets/3D/units/commander/commander.glb"
const CLIPS: Array[String] = ["MARCH", "MARCH_WALK", "STANDBY", "COMMAND"]
const FLAGS := "res://assets/2D/flags/realms/national_flags.tres"


func _figure() -> Node:
	var node: Node = (load(Map3DCommanderFigure.SCENE) as PackedScene).instantiate()
	autofree(node)
	return node


func test_the_scene_inherits_its_glb_and_owns_both_materials() -> void:
	var text := FileAccess.get_file_as_string(Map3DCommanderFigure.SCENE)
	assert_true(text.contains('path="%s"' % GLB) and text.contains("instance=ExtResource("),
		"the scene inherits the .glb (New Inherited Scene), so a re-export carries over")
	assert_false(text.contains("assets/2D/flags"), "no realm's flag is authored into the model")
	var meshes := Map3DUnits.meshes(_figure())
	assert_eq(meshes.size(), 1, "one skinned mesh")
	var mesh: MeshInstance3D = meshes[0]
	assert_eq(String(mesh.name), "commander")
	assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the figure casts its shadow")
	assert_eq(mesh.mesh.get_surface_count(), 2, "the atlas surface and the banner's cloth")
	assert_eq(mesh.mesh.surface_get_material(0).resource_name, "commander_atlas")
	assert_eq(Map3DCommanderFigure.cloth_surface(mesh), 1, "the cloth is the second surface")
	for i in 2:
		var mat := mesh.get_surface_override_material(i) as BaseMaterial3D
		assert_not_null(mat, "surface %d wears a material set in the scene, editable there" % i)
		assert_ne(mat, mesh.mesh.surface_get_material(i), "not the .glb's imported one")
	var body := mesh.get_surface_override_material(0) as BaseMaterial3D
	for key: String in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"]:
		var tex := body.get(key) as Texture2D
		assert_not_null(tex, key)
		assert_false(tex.resource_path.contains("::"), key + " is a file beside the .glb")
		var cf := ConfigFile.new()
		cf.load(tex.resource_path + ".import")
		assert_eq(int(cf.get_value("params", "compress/mode", -1)), 4, tex.resource_path + " is Basis Universal")
	var cloth := mesh.get_surface_override_material(1) as BaseMaterial3D
	assert_eq(cloth.cull_mode, BaseMaterial3D.CULL_DISABLED, "one sheet seen from both sides")
	assert_null(cloth.albedo_texture, "bare until the game sets a realm's flag")
	assert_true(cloth.backlight_enabled, "light passes through the sheet: the face turned from the sun keeps its colours")


func test_the_skeleton_is_the_cavalrys_contract_plus_the_banner() -> void:
	var node := _figure()
	assert_not_null(node.get_node_or_null("commander_rig"), "the armature is commander_rig")
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
	assert_eq(skeleton.get_bone_count(), 124)
	for side: String in ["L", "R"]:
		for bone: String in ["FrontScapula", "FrontUpperArm", "FrontForearm", "FrontCannon", "FrontHoof",
				"HindThigh", "HindShin", "HindCannon", "HindHoof"]:
			assert_gte(skeleton.find_bone("%s.%s" % [bone, side]), 0, "%s.%s (the pivot solver's chain)" % [bone, side])
	var saddle := skeleton.find_bone("Saddle")
	assert_gte(saddle, 0, "the rider's root")
	for bone: String in ["head", "cc_weapon.r"]:
		var b := skeleton.find_bone(bone)
		assert_gte(b, 0, bone)
		while b >= 0 and b != saddle:
			b = skeleton.get_bone_parent(b)
		assert_eq(b, saddle, bone + " rides the Saddle")
	assert_gte(skeleton.find_bone("head_h"), 0, "the horse's head")
	var parent := skeleton.find_bone("cc_weapon.r")
	for i in range(1, 7):  # the cloth's chain, hoist to fly, under the staff's socket
		var flag := skeleton.find_bone("flag_%d" % i)
		assert_gte(flag, 0, "flag_%d" % i)
		assert_eq(skeleton.get_bone_parent(flag), parent, "flag_%d hangs from the bone before it" % i)
		parent = flag


func test_all_four_clips_loop_and_move_the_cloth() -> void:
	var node := _figure()
	var player := Map3DUnits.find_anim(node)
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
	for clip in CLIPS:
		assert_true(player.has_animation(clip), clip)
		var anim := player.get_animation(clip)
		assert_eq(anim.loop_mode, Animation.LOOP_LINEAR, clip + " loops (set in the .import)")
		var path := NodePath("%s:flag_3" % player.get_node(player.root_node).get_path_to(skeleton))
		assert_gte(anim.find_track(path, Animation.TYPE_ROTATION_3D), 0, clip + " keys the cloth")
	# 13 / 29 / 80 / 160 frames at 30 a second, each closed on its own period
	for want: Array in [["MARCH", 13], ["MARCH_WALK", 29], ["STANDBY", 80], ["COMMAND", 160]]:
		assert_almost_eq(player.get_animation(want[0]).length, want[1] / 30.0, 0.001, "%s is %d frames" % want)
	# the run's hooves are locked on 8 keys a frame: the import bakes at 240 a second, as the cavalry's
	assert_almost_eq(player.get_animation("MARCH").step, 1.0 / 240.0, 0.00001, "MARCH keeps its dense keys (animation/fps)")


func test_the_cloth_takes_each_realms_flag_and_nothing_else_changes() -> void:
	var repo := SuiteData.repo()
	var table := load(FLAGS) as ArtTable
	var a := _figure()
	var b := _figure()
	var mesh_a: MeshInstance3D = Map3DUnits.meshes(a)[0]
	var mesh_b: MeshInstance3D = Map3DUnits.meshes(b)[0]
	var body := mesh_a.get_surface_override_material(0)
	var bare := mesh_a.get_surface_override_material(1)
	var seen: Array = []
	for slot: String in table.art:
		var flag := Map3DNationalFlag.texture_for(repo, table, repo.resolve_realm(slot))
		assert_not_null(flag, slot + " has a flag")
		Map3DCommanderFigure.set_flag(a, flag)
		var cloth := mesh_a.get_surface_override_material(1) as BaseMaterial3D
		assert_eq(cloth.albedo_texture, flag, slot + "'s flag is on the cloth")
		assert_eq(cloth.albedo_color, Color.WHITE, "in its own colours")
		assert_eq(cloth.cull_mode, BaseMaterial3D.CULL_DISABLED)
		assert_true(cloth.backlight_enabled, "the scene's cloth look carries over")
		assert_false(seen.has(flag), "each realm its own picture")
		seen.append(flag)
		assert_eq(mesh_a.get_surface_override_material(0), body, "the body's material is untouched")
		Map3DCommanderFigure.set_flag(b, flag)
		assert_eq(mesh_b.get_surface_override_material(1), cloth, "two commanders of one realm share the material")
	assert_null((bare as BaseMaterial3D).albedo_texture, "the scene's own cloth was never written to")
	Map3DCommanderFigure.set_flag(a, null)
	assert_eq(mesh_a.get_surface_override_material(1), bare, "no flag art: the bare cloth again")


func test_the_commander_is_recorded_within_budget() -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3D/units/units3d.json"))
	var row: Dictionary = info["commander"]
	assert_between(int(row["tris"]), 20000, 26000, "a cavalry figure's budget")
	assert_eq(int(row["bones"]), 124)
	for clip in CLIPS:
		assert_true((row["actions"] as Dictionary).has(clip), clip)
	var tris := 0
	var mesh: MeshInstance3D = Map3DUnits.meshes(_figure())[0]
	for i in mesh.mesh.get_surface_count():
		tris += (mesh.mesh as ArrayMesh).surface_get_array_index_len(i) / 3
	assert_eq(tris, int(row["tris"]), "the record is the installed mesh's")
