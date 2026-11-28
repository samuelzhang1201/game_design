extends GutTest
## The archers' figure as installed (tools/units3d/archer_parts/): the parts Tripo longbowman on the
## infantry's rig contract, thirteen clips plus the pivot pair, bow, quiver and arrow in one skinned mesh.

const GLB := "res://assets/3D/units/archers/archers.glb"
const LOOPS: Array[String] = ["MARCH", "GARRISON", "STANDBY", "ATTACK", "SPRINT"]
const ONCE: Array[String] = ["DRAW", "HIT", "HIT_2", "HIT_3", "DODGE", "DODGE_L", "DODGE_R", "DEATH",
	"PIVOT_LEFT", "PIVOT_RIGHT"]


func test_the_archer_carries_his_clips_on_the_infantry_rig() -> void:
	var node: Node = (load(GLB) as PackedScene).instantiate()
	autofree(node)
	assert_not_null(node.get_node_or_null("inf_rig"), "the armature is inf_rig")
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	for clip in LOOPS:
		assert_true(player.has_animation(clip), clip)
		if player.has_animation(clip):
			assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, clip + " loops (set in the .import)")
	for clip in ONCE:
		assert_true(player.has_animation(clip), clip)
		if player.has_animation(clip):
			assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, clip + " plays once")
	# 36 unique frames at 30 a second
	assert_almost_eq(player.get_animation("MARCH").length, 1.2, 0.001, "MARCH is timed at 30 frames a second")
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
	for bone: String in ["cc_weapon.l", "cc_bow_string", "cc_arrow", "spine_02.x"]:
		assert_gte(skeleton.find_bone(bone), 0, "the gear's bone " + bone)
	var meshes := Map3DUnits.meshes(node)
	assert_eq(meshes.size(), 1, "body, bow, quiver and arrow are one skinned mesh")
	assert_eq(String(meshes[0].name), "archers")
	assert_eq(meshes[0].mesh.get_surface_count(), 1, "one material on one atlas")


func test_the_hidden_arrow_stays_invertible() -> void:
	# scaled to 0 the pivot solver refuses the pose (Map3DInfantryPivot._affine): it hides at 0.001
	var node: Node = (load(GLB) as PackedScene).instantiate()
	autofree(node)
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
	var arrow := skeleton.find_bone("cc_arrow")
	for clip: String in ["MARCH", "STANDBY", "PIVOT_RIGHT"]:   # GARRISON aims: the arrow is nocked
		player.play(clip)
		player.seek(0.5 * player.get_animation(clip).length, true)
		var scale := skeleton.get_bone_pose_scale(arrow)
		assert_gt(minf(scale.x, minf(scale.y, scale.z)), 0.0, clip + ": the arrow's scale is not 0")
		assert_lt(maxf(scale.x, maxf(scale.y, scale.z)), 0.01, clip + ": the arrow is hidden")


func test_the_archer_is_recorded() -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3D/units/units3d.json"))
	var row: Dictionary = info["archers"]
	assert_between(int(row["tris"]), 15000, 23000, "the foot soldiers' budget, the bow and quiver on top")
	assert_eq(int(row["fps"]), 30)
	assert_gt(float(row["stride_m"]), 0.0, "measured off its own MARCH")
	for clip: String in LOOPS + ["DRAW", "HIT", "DODGE", "DEATH"]:
		assert_true((row["actions"] as Dictionary).has(clip), clip)


func test_the_realm_tints_mask_covers_the_gambeson_only() -> void:
	var mask := load("res://assets/3D/units/archers/archers_tunic_mask.png") as Texture2D
	var atlas := load("res://assets/3D/units/archers/archers_archers_atlas.jpg") as Texture2D
	assert_not_null(mask, "exported with the atlases (tools/units3d/archer_parts/game_export.py)")
	assert_eq(mask.get_size(), atlas.get_size(), "in the atlas's frame")
	var img := mask.get_image()
	img.convert(Image.FORMAT_L8)
	var set_texels := 0
	for byte in img.get_data():
		if byte > 127:
			set_texels += 1
	var share := float(set_texels) / float(img.get_width() * img.get_height())
	assert_between(share, 0.04, 0.15, "the gambeson and its sleeves, not the whole body")
	# the bow's and the quiver's strip (the right-hand quarter) carries no cloth
	var gear := img.get_region(Rect2i(img.get_width() * 3 / 4, 0, img.get_width() / 4, img.get_height()))
	var stray := 0
	for byte in gear.get_data():
		if byte > 127:
			stray += 1
	assert_eq(stray, 0, "nothing of the mask on the gear")
