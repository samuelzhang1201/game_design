extends GutTest
## The town militia's figure as installed (tools/units3d/militia_arp/): the file the arm's scene will inherit.
## No arm wears it yet, so the tables' tests (test_map3d_unit_scenes.gd) do not reach it.

const GLB := "res://assets/3D/units/militia/militia.glb"
const LOOPS: Array[String] = ["MARCH", "GARRISON", "STANDBY", "DEFEND"]
const STRIKES: Array[String] = ["ATTACK", "SLASH", "ATTACK_VAR1", "ATTACK_2", "SLASH_2", "SLASH_3"]


func test_the_militia_figure_carries_its_ten_clips_and_its_skirt() -> void:
	var node: Node = (load(GLB) as PackedScene).instantiate()
	autofree(node)
	assert_not_null(node.get_node_or_null("mil_rig"), "the armature is mil_rig")
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	for clip in LOOPS:
		assert_true(player.has_animation(clip), clip)
		assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, clip + " loops (set in the .import)")
	for clip in STRIKES:
		assert_true(player.has_animation(clip), clip)
		assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, clip + " plays once")
	# 34 keyed frames at 30 a second: an export at the source scene's 24 would read 1.375 s
	assert_almost_eq(player.get_animation("MARCH").length, 1.1, 0.001, "MARCH is timed at 30 frames a second")
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
	var skirt := 0
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).begins_with("skirt_"):
			skirt += 1
	assert_eq(skirt, 30, "ten chains of three skirt bones, their keys baked into every clip")
	assert_gte(skeleton.find_bone("cc_weapon.r"), 0, "the sword's socket")
	assert_gte(skeleton.find_bone("cc_weapon.l"), 0, "the shield's socket")
	var meshes := Map3DUnits.meshes(node)
	assert_eq(meshes.size(), 1, "one skinned mesh")
	assert_eq(String(meshes[0].name), "militia")
	assert_eq(meshes[0].mesh.get_surface_count(), 1, "one material on one atlas")
	var mat := meshes[0].mesh.surface_get_material(0) as BaseMaterial3D
	assert_eq(mat.cull_mode, BaseMaterial3D.CULL_DISABLED, "the skirt is open underneath: drawn two-sided")


func test_the_militia_is_recorded_within_budget() -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3D/units/units3d.json"))
	var row: Dictionary = info["militia"]
	assert_between(int(row["tris"]), 15000, 20000, "the infantry figure's budget")
	assert_eq(int(row["bones"]), 100)
	assert_eq(int(row["fps"]), 30)
	assert_gt(float(row["stride_m"]), 0.0, "measured off its own MARCH")
	for clip: String in LOOPS + STRIKES:
		assert_true((row["actions"] as Dictionary).has(clip), clip)


func test_the_realm_tints_mask_covers_the_dyed_cloth_only() -> void:
	var mask := load("res://assets/3D/units/militia/militia_tunic_mask.png") as Texture2D
	var atlas := load("res://assets/3D/units/militia/militia_militia_atlas.jpg") as Texture2D
	assert_not_null(mask, "exported with the atlases (tools/units3d/militia_arp/game_export.py)")
	assert_eq(mask.get_size(), atlas.get_size(), "in the atlas's frame")
	var img := mask.get_image()
	img.convert(Image.FORMAT_L8)
	var set_texels := 0
	for byte in img.get_data():
		if byte > 127:
			set_texels += 1
	var share := float(set_texels) / float(img.get_width() * img.get_height())
	# the tunic and the skirt are 30 % of the body's faces; the body sits in 9/16 of the atlas
	assert_between(share, 0.08, 0.18, "the tunic and the skirt, not the whole body")
	# the sword's and the shield's strip (the right-hand quarter) carries no cloth
	var gear := img.get_region(Rect2i(img.get_width() * 3 / 4, 0, img.get_width() / 4, img.get_height()))
	var stray := 0
	for byte in gear.get_data():
		if byte > 127:
			stray += 1
	assert_eq(stray, 0, "nothing of the mask on the gear")
