extends GutTest
## The town militia's figure as installed (tools/units3d/militia_arp/) and as worn: a raised town militia's
## unit (its roster row's `figure`, TownMilitia.FIGURE) is drawn with scenes/models/units/militia.tscn while
## its piece stays its first arm's (Map3DFormation.figure_of).

const SuiteData := preload("res://tests/suite_data.gd")

const GLB := "res://assets/3D/units/militia/militia.glb"
const LOOPS: Array[String] = ["MARCH", "GARRISON", "STANDBY", "DEFEND"]
const STRIKES: Array[String] = ["ATTACK", "SLASH", "ATTACK_VAR1", "ATTACK_2", "SLASH_2", "SLASH_3"]
const DUEL: Array[String] = ["BLOCK", "BLOCK_2", "BLOCK_3", "BLOCK_4", "HIT", "HIT_2", "HIT_3"]


func test_the_militia_figure_carries_its_clips_and_its_skirt() -> void:
	var node: Node = (load(GLB) as PackedScene).instantiate()
	autofree(node)
	assert_not_null(node.get_node_or_null("mil_rig"), "the armature is mil_rig")
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	for clip in LOOPS:
		assert_true(player.has_animation(clip), clip)
		assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, clip + " loops (set in the .import)")
	for clip in STRIKES + DUEL:
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
	for clip: String in LOOPS + STRIKES + DUEL:
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


## A militia's roster row as TownMilitia.raise writes it, and an ordinary unit of the same arm.
func _rows() -> Dictionary:
	var plain := {"regiment_code": "x", "organization_arm": "infantry", "is_royal": "0", "is_naval": "0"}
	var militia := plain.duplicate()
	militia["regiment_code"] = "militia:s1"
	militia["figure"] = TownMilitia.FIGURE
	return {"plain": plain, "militia": militia}


func test_a_militia_wears_its_own_figure_and_no_other_unit_of_its_arm_does() -> void:
	var repo: DataRepository = SuiteData.repo()
	var rows := _rows()
	assert_eq(Map3DFormation.figure_of(repo, rows.militia), "militia")
	assert_eq(MapObjects.army_piece(repo, rows.militia), "infantry", "card, footprint and bodies stay the arm's")
	assert_eq(Map3DFormation.figure_of(repo, rows.plain), "infantry")
	var unknown: Dictionary = rows.plain.duplicate()
	unknown["figure"] = "no_such_figure"
	assert_eq(Map3DFormation.figure_of(repo, unknown), "infantry", "a figure with no army_art.csv row falls back to the piece")
	var tier := {"figures": 1, "slots": [Vector2.ZERO]}
	var built := Map3DFormation.of_regiment(repo, rows.militia, tier, 1.6)
	autofree(built["node"])
	assert_eq(String(built["model"]), "militia")
	assert_eq(String(built["footprint"]), "infantry", "the battle rows close up by the engine bodies' footprint")
	assert_not_null((built["figs"][0] as Node).get_node_or_null("mil_rig"), "the militia scene stands")
	assert_almost_eq(float(built["stride_m"]), 1.5042, 1e-9, "its own MARCH's stride (the lock's planted-sole speed x 33 frames)")
	var other := Map3DFormation.of_regiment(repo, rows.plain, tier, 1.6)
	autofree(other["node"])
	assert_null((other["figs"][0] as Node).get_node_or_null("mil_rig"), "the infantry keeps its figure")
	# a size draws the rest box (hat to sole) at one map height: the same size, so his head stands level
	# with the infantry's (his 1.7051 m box against 1.6357 m: 4 % smaller in the metre)
	assert_eq(float(built["size"]), float(other["size"]))
	assert_almost_eq(float(built["height_m"]), 1.7051, 0.001)


## The front-rank duel (spec 2026-11-26-militia-figure-wiring-design step 1) and what the figure has not got
## yet (reported, never faked): no fall. It has its pivot pair.
func test_the_militia_duels_but_does_not_fall_yet() -> void:
	var repo: DataRepository = SuiteData.repo()
	var art: Dictionary = repo.army_art["militia"]
	var node: Node = (load(GameArt.path(GameArt.ARMY_MODELS, "militia")) as PackedScene).instantiate()
	autofree(node)
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	assert_eq(Map3DClipChain.of_art(art).get("ATTACK"), STRIKES, "in the ranks it strikes its six clips by turns")
	for clip in STRIKES + DUEL:
		assert_ne(Map3DUnits.clip_named(player, clip), "", clip)
	assert_true(Map3DDuel.duels(art, player), "its STRIKE, BLOCK and HIT clips are installed, each with a contact share")
	var duel := Map3DClipChain.of_column(art, "duel")
	assert_eq(duel.get("BLOCK"), ["BLOCK", "BLOCK_2", "BLOCK_3", "BLOCK_4"])
	assert_eq(duel.get("HIT"), ["HIT", "HIT_2", "HIT_3"])
	assert_false(duel.has("DEATH"), "no fall yet (step 1b): a loss is freed at once")
	for clip: String in ["DEATH", "DEATH_2"]:
		assert_eq(Map3DUnits.clip_named(player, clip), "", clip + " is not installed")
	for clip: String in ["PIVOT_LEFT", "PIVOT_RIGHT"]:
		assert_ne(Map3DUnits.clip_named(player, clip), "", clip + ": the arm's locomotion pivots")
	var tint := GameArt.table(GameArt.UNIT_REALM_TINT).of("militia") as ShaderMaterial
	assert_not_null(tint, "its tunic and skirt wear the realm's colour")
	assert_eq((tint.get_shader_parameter("tunic_mask") as Texture2D).resource_path,
		"res://assets/3D/units/militia/militia_tunic_mask.png", "by its own mask")
	# the cloth's mean linear luminance under the mask (the exporter reports 0.052)
	assert_almost_eq(float(tint.get_shader_parameter("tunic_luminance")), 0.052, 0.002)
