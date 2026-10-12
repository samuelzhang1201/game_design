extends GutTest
## Every unit model is a SCENE (owner 2026-10-04: 把兵人模型也改成场景):
## scenes/models/units/<model>.tscn inherits its .glb and gives each
## surface an editable copy of its material, so the regiments' figures and the
## couriers are looked at and changed in the editor. The 3D map stands these
## scenes, the WAR ROOM paints its tin over their materials.

const SuiteData := preload("res://tests/suite_data.gd")

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


## Every scene the two tables name, once.
func _scenes() -> Array[String]:
	var out: Array[String] = []
	for table: String in [GameArt.ARMY_MODELS, GameArt.COURIER_MODELS]:
		for key: String in GameArt.table(table).art:
			var path := GameArt.path(table, key)
			if not out.has(path):
				out.append(path)
	return out


func test_every_unit_model_is_a_scene_that_inherits_its_glb() -> void:
	var paths := _scenes()
	assert_gt(paths.size(), 0, "the tables name models")
	for path in paths:
		assert_eq(path.get_extension(), "tscn", "a unit is drawn from its scene, not the bare .glb: " + path)
		assert_true(path.begins_with("res://scenes/models/units/"), "a unit's scene lives under scenes/: " + path)
		var model := path.get_file().get_basename()
		var glb := "res://assets/3D/units/%s/%s.glb" % [model, model]
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains('path="%s"' % glb) and text.contains("instance=ExtResource("),
			path + " inherits " + glb + " (New Inherited Scene), so a re-export carries over")


func test_every_surface_wears_its_scenes_own_material_with_file_textures() -> void:
	for path in _scenes():
		var node: Node = (load(path) as PackedScene).instantiate()
		autofree(node)
		var meshes := Map3DUnits.meshes(node)
		assert_gt(meshes.size(), 0, path + " has a mesh")
		for m: MeshInstance3D in meshes:
			assert_eq(m.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
				path + ": the figure casts its shadow (owner 2026-09-27: 兵人需要增加阴影)")
			for i in m.mesh.get_surface_count():
				var mat := m.get_surface_override_material(i) as BaseMaterial3D
				var where := "%s surface %d" % [path, i]
				assert_not_null(mat, where + " wears a material set in the scene, editable there")
				if mat == null:
					continue
				for key: String in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"]:
					var tex := mat.get(key) as Texture2D
					if tex == null:
						continue
					assert_false(tex.resource_path.contains("::"),
						"%s's %s is a file beside the .glb, not embedded in it" % [where, key])
					var cf := ConfigFile.new()
					cf.load(tex.resource_path + ".import")
					assert_eq(int(cf.get_value("params", "compress/mode", -1)), 4,
						tex.resource_path + " is Basis Universal like the textures the .glb embedded")


func test_the_war_rooms_tin_reads_the_scenes_material() -> void:
	var path := GameArt.path(GameArt.ARMY_MODELS, "infantry")
	var node: Node = (load(path) as PackedScene).instantiate()
	autofree(node)
	var m: MeshInstance3D = Map3DUnits.meshes(node)[0]
	var scene_mat := m.get_surface_override_material(0) as BaseMaterial3D
	assert_eq(m.get_active_material(0), scene_mat, "the active material is the scene's")
	assert_ne(scene_mat, m.mesh.surface_get_material(0), "not the .glb's imported one")


## The glTF importer loops nothing by itself: a MARCH that does not loop plays one
## stride and freezes, so the column glides (owner 2026-10-12: 步兵走路很飘, 腿没在动).
## The resting and walking clips of every model are set to LOOP in its .import.
func test_every_walking_and_resting_clip_loops() -> void:
	for path in _scenes():
		var model: Node = load(path).instantiate()
		var players := model.find_children("*", "AnimationPlayer", true, false)
		assert_gt(players.size(), 0, path + " has an AnimationPlayer")
		for player: AnimationPlayer in players:
			for clip in ["MARCH", "GARRISON", "STANDBY", "GALLOP", "IDLE"]:
				var named := Map3DUnits.clip_named(player, clip)
				if named != "":
					assert_eq(player.get_animation(named).loop_mode, Animation.LOOP_LINEAR,
						"%s's %s loops (its .glb.import)" % [path, clip])
		model.free()
