extends GutTest
## The equipped ARP replacement keeps six distinct source clips and separate gear.


func test_archer_clips_keep_the_runtime_contract_and_one_shots() -> void:
	var model: Node = load(GameArt.path(GameArt.ARMY_MODELS, "archers")).instantiate()
	autofree(model)
	var player := Map3DUnits.find_anim(model)
	assert_not_null(player)
	if player == null:
		return
	for clip: String in ["STANDBY", "MARCH", "SPRINT", "DRAW", "GARRISON", "DEATH"]:
		var named := Map3DUnits.clip_named(player, clip)
		assert_ne(named, "", "the supplied clip is exported: " + clip)
		if named == "":
			continue
		var animation := player.get_animation(named)
		assert_gt(animation.length, 0.4, clip + " retains its sampled motion")
		var loop := Animation.LOOP_NONE if clip in ["DRAW", "DEATH"] else Animation.LOOP_LINEAR
		assert_eq(animation.loop_mode, loop, clip + " has the appropriate playback mode")
	assert_almost_eq(player.get_animation(Map3DUnits.clip_named(player, "MARCH")).length,
		35.0 / 30.0, 0.0001, "Standard Walk retains its 35-frame cycle without a leading hold")


func test_equipment_uses_the_characters_named_skin_and_editable_materials() -> void:
	var model: Node = load(GameArt.path(GameArt.ARMY_MODELS, "archers")).instantiate()
	autofree(model)
	var meshes := Map3DUnits.meshes(model)
	assert_eq(meshes.size(), 4, "body, bow, loaded quiver and arrow remain separate meshes")
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "equipment shares one animated skeleton")
	if skeletons.size() != 1:
		return
	var skeleton: Skeleton3D = skeletons[0]
	assert_eq(skeleton.get_bone_name(skeleton.get_bone_parent(skeleton.find_bone("DEF-bow"))),
		"DEF-weapon.L", "bow mounts on the left hand")
	var body := model.find_child("archers", true, false) as MeshInstance3D
	var body_binds := {}
	for i in body.skin.get_bind_count():
		body_binds[body.skin.get_bind_name(i)] = body.skin.get_bind_pose(i)
	for bone: String in ["head", "DEF-weapon.L", "DEF-weapon.R", "DEF-arrow", "DEF-bow", "DEF-quiver", "DEF-string"]:
		assert_gte(skeleton.find_bone(bone), 0, "attachment retained: " + bone)
	for mesh: MeshInstance3D in meshes:
		assert_eq(mesh.get_node(mesh.skeleton), skeleton, mesh.name + " follows the character")
		assert_not_null(mesh.skin, mesh.name + " retains its skin")
		if mesh != body:
			assert_lte(mesh.skin.get_bind_count(), 2, "gear does not upload the whole character palette")
			for i in mesh.skin.get_bind_count():
				var bone := mesh.skin.get_bind_name(i)
				assert_true(body_binds.has(bone), "gear binds to an exported character bone")
				if body_binds.has(bone):
					assert_true(mesh.skin.get_bind_pose(i).is_equal_approx(body_binds[bone]),
						mesh.name + " keeps the character's exact bind space")
		for surface in mesh.mesh.get_surface_count():
			assert_not_null(mesh.get_surface_override_material(surface), "editable material: " + mesh.name)


func test_all_clips_keep_the_left_grip_and_draw_with_the_right_hand() -> void:
	var model: Node = load(GameArt.path(GameArt.ARMY_MODELS, "archers")).instantiate()
	add_child_autofree(model)
	var player := Map3DUnits.find_anim(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var left := skeleton.find_bone("hand.l")
	var right := skeleton.find_bone("hand.r")
	var bow := skeleton.find_bone("DEF-bow")
	var arrow := skeleton.find_bone("DEF-arrow")
	var grip := Transform3D.IDENTITY
	var first := true
	for clip: String in ["STANDBY", "MARCH", "SPRINT", "DRAW", "GARRISON", "DEATH"]:
		var name := Map3DUnits.clip_named(player, clip)
		player.play(name)
		for sample in 11:
			player.seek(player.get_animation(name).length * sample / 10.0, true)
			var mounted := skeleton.get_bone_global_pose(left).affine_inverse() * skeleton.get_bone_global_pose(bow)
			if first:
				grip = mounted
				first = false
			assert_lt(mounted.origin.distance_to(grip.origin), 0.002, clip + " keeps its left grip")
			assert_lt(mounted.basis.get_rotation_quaternion().angle_to(grip.basis.get_rotation_quaternion()),
				0.002, clip + " keeps its wrist orientation")
			if clip == "DRAW" and sample >= 4:
				assert_lt(skeleton.get_bone_global_pose(right).origin.distance_to(
					skeleton.get_bone_global_pose(arrow).origin), 0.16, "the right hand retrieves and draws the arrow")
