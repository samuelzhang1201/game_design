extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func test_every_bound_realm_has_an_approved_texture() -> void:
	var repo := SuiteData.repo()
	var table := load("res://assets/2D/flags/realms/national_flags.tres") as ArtTable
	assert_not_null(table)
	if table == null: return
	assert_eq(table.art.size(), 7)
	for slot: String in repo.realm_bindings:
		assert_not_null(Map3DNationalFlag.texture_for(repo, table, repo.resolve_realm(slot)), slot)
	assert_null(Map3DNationalFlag.texture_for(repo, table, "unbound"))

func test_city_flag_follows_current_province_owner() -> void:
	var repo := SuiteData.repo()
	var state := GameState.new()
	var burg: Dictionary = repo.burgs.values()[0]
	var province := String(burg["province_code"])
	var owner := Map3DNationalFlag.city_realm(repo, state, burg)
	var next := repo.resolve_realm("player_realm")
	if next == owner: next = repo.resolve_realm("raider_realm")
	state.province_owner[province] = next
	assert_eq(Map3DNationalFlag.city_realm(repo, state, burg), next)
	assert_eq(Map3DNationalFlag.city_realm(repo, null, burg), owner)

func test_one_bearer_for_whole_formation_and_physical_groups() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var first := Node3D.new()
	var second := Node3D.new()
	root.add_child(first); root.add_child(second)
	var skel := Skeleton3D.new()
	first.add_child(skel)
	skel.add_bone("hand.r")
	var scene := load("res://scenes/models/flags/national_standard.tscn") as PackedScene
	var table := load("res://assets/2D/flags/realms/national_flags.tres") as ArtTable
	var texture := table.of("player_realm") as Texture2D
	var piece := {"figs": [first, second]}
	Map3DUnitStandard.sync(piece, texture, scene)
	Map3DUnitStandard.sync(piece, texture, scene)
	assert_eq(first.find_children("NationalStandard", "", true, false).size(), 1)
	assert_eq(second.find_children("NationalStandard", "", true, false).size(), 0)
	var groups := {"layout": "physical_groups", "groups": [{"piece": piece}, {"piece": {"figs": [second]}}]}
	assert_same(Map3DUnitStandard.first_figure(groups), first)
	assert_null(Map3DUnitStandard.first_figure({"figs": []}))

func test_roof_mount_is_a_real_mesh_vertex() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(4, 8, 6)
	var top := Map3DCityFlags.roof_top(box)
	assert_eq(top.y, 4.0)
	assert_eq(absf(top.x), 2.0)
	assert_eq(absf(top.z), 3.0)

func test_all_installed_arm_models_support_the_standard_grip() -> void:
	var models := GameArt.table(GameArt.ARMY_MODELS)
	var flags := load("res://assets/2D/flags/realms/national_flags.tres") as ArtTable
	var scene := load("res://scenes/models/flags/national_standard.tscn") as PackedScene
	for key: String in models.art:
		var figure := (models.of(key) as PackedScene).instantiate() as Node3D
		add_child_autofree(figure)
		var piece := {"figs": [figure]}
		Map3DUnitStandard.sync(piece, flags.of("player_realm"), scene)
		var bearer: Map3DStandardBearer = piece.get("standard_bearer")
		assert_not_null(bearer, key)
		if bearer == null: continue
		assert_gte(bearer._hand, 0, key + " has a real hand socket")
		var anim := Map3DUnits.find_anim(figure)
		var clip := Map3DUnits.clip_named(anim, "MARCH")
		if clip != "":
			anim.play(clip)
			anim.advance(0.35)
		var skel := bearer.get_skeleton()
		var hand_offset := Vector3.ZERO
		if bearer._forearm >= 0:
			hand_offset = skel.get_bone_global_pose(bearer._forearm).affine_inverse() * skel.get_bone_global_pose(bearer._hand).origin
		bearer._process_modification()
		if bearer._forearm >= 0:
			var endpoint := skel.get_bone_global_pose(bearer._forearm) * hand_offset
			assert_lt(endpoint.distance_to(skel.get_bone_global_pose(bearer._hand).origin), 0.003,
				key + " forearm remains connected to its hand")
		assert_true(bearer.standard.position.is_finite(), key + " has a finite carried pole")
		assert_gt(bearer.standard.position.y + 3.4, 2.0, key + " carries the flag above the head")
		Map3DUnitStandard.sync(piece, null, scene)
		assert_false(piece.has("standard_bearer"), "unknown realm removes a stale flag")

func test_distant_conquest_does_not_hide_city_flag_after_zooming_back() -> void:
	var repo := SuiteData.repo()
	var context := Map3DContext.new(repo, {})
	context.distance = repo.bal("map3d_lod_houses_m") * 2.0
	var houses := Map3DLayerHouses.new()
	add_child_autofree(houses)
	houses.bind(context)
	var flags := Map3DCityFlags.new()
	add_child_autofree(flags)
	flags.flag_scene = load("res://scenes/models/flags/national_standard.tscn")
	flags.realm_flags = load("res://assets/2D/flags/realms/national_flags.tres")
	flags.bind(context, houses)
	var burg: Dictionary = repo.burgs.values()[0]
	var code := String(burg["burg_code"])
	var h := {"type": "cottage_a", "at": Vector2.ZERO, "scale": 1.0,
		"height_scale": 1.0, "yaw_deg": 0.0, "_seat": Vector2.ZERO}
	flags.sync([code], {code: [h]})
	flags._process(0.0)
	assert_false(flags.visible)
	context.distance = 1000.0
	flags._process(0.0)
	assert_true(flags.visible)
	assert_true((flags._flags[code] as Node3D).visible, "admitted flag returns without panning")

func test_same_realm_flags_share_the_cloth_material() -> void:
	var scene := load("res://scenes/models/flags/national_standard.tscn") as PackedScene
	var flags := load("res://assets/2D/flags/realms/national_flags.tres") as ArtTable
	var first := scene.instantiate() as Map3DNationalFlag
	var second := scene.instantiate() as Map3DNationalFlag
	add_child_autofree(first); add_child_autofree(second)
	first.set_texture(flags.of("player_realm"))
	second.set_texture(flags.of("player_realm"))
	assert_same(first.cloth.material_override, second.cloth.material_override)
