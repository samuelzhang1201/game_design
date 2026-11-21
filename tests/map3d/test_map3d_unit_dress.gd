extends GutTest
## Map3DUnitDress: each map figure's tunic wears its realm's colour (spec
## 2026-11-21-infantry-melee-scrum-design, step 1), through an overlay
## material and a per-instance tint; the scene's own material is left alone.
const SuiteData := preload("res://tests/suite_data.gd")


func _figure(with_standard := false) -> Node3D:
	var fig := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.set_surface_override_material(0, StandardMaterial3D.new())
	fig.add_child(body)
	if with_standard:
		var flag := Map3DNationalFlag.new()
		var cloth := MeshInstance3D.new()
		cloth.mesh = BoxMesh.new()
		flag.add_child(cloth)
		fig.add_child(flag)
	return fig


func _piece(n: int, model := "infantry") -> Dictionary:
	var root := Node3D.new()
	add_child_autofree(root)
	var figs: Array = []
	for i in n:
		var fig := _figure(i == 0)
		root.add_child(fig)
		figs.append(fig)
	return {"node": root, "figs": figs, "model": model}


func _table() -> ArtTable:
	var table := ArtTable.new()
	table.art["infantry"] = ShaderMaterial.new()
	return table


func _body(fig: Node3D) -> MeshInstance3D:
	return fig.get_child(0) as MeshInstance3D


func test_tint_takes_the_realm_hue() -> void:
	var c := Map3DUnitDress.tint(Color.from_hsv(0.6, 0.2, 0.9), 0.55, 0.08)
	assert_almost_eq(c.h, 0.6, 1e-3)
	assert_almost_eq(c.s, 0.55, 1e-3)
	assert_almost_eq(Map3DUnitDress.luminance(c), 0.08, 1e-4)
	# every realm's tunic as saturated as every other's (a vivid palette colour is dulled to the key)
	assert_almost_eq(Map3DUnitDress.tint(Color.from_hsv(0.1, 0.8, 0.9), 0.55, 0.08).s, 0.55, 1e-3)


func test_tint_is_the_value_of_that_luminance() -> void:
	# grey: sRGB 0.5 is linear ((0.5 + 0.055) / 1.055) ^ 2.4 = 0.21404
	assert_almost_eq(Map3DUnitDress.tint(Color(0.3, 0.3, 0.3), 0.0, 0.21404).v, 0.5, 1e-4)
	# every realm's tunic as light as every other's: only the hue tells them apart
	var red := Map3DUnitDress.tint(Color("#EE7B6E"), 0.55, 0.08)
	var blue := Map3DUnitDress.tint(Color("#58B4E3"), 0.55, 0.08)
	assert_almost_eq(Map3DUnitDress.luminance(red), Map3DUnitDress.luminance(blue), 1e-4)


func test_tint_of_reads_the_palette_and_the_keys() -> void:
	var repo := SuiteData.repo()
	var code := repo.resolve_realm("raider_realm")
	var want := Map3DUnitDress.tint(MapPalette.color_of(repo, code),
		float(repo.bal("map3d_unit_tint_sat")), float(repo.bal("map3d_unit_tint_lum")))
	assert_eq(Map3DUnitDress.tint_of(repo, code), want)
	assert_ne(Map3DUnitDress.tint_of(repo, code), Map3DUnitDress.tint_of(repo, repo.resolve_realm("player_realm")))


func test_sync_dresses_every_figure() -> void:
	var repo := SuiteData.repo()
	var piece := _piece(3)
	var table := _table()
	var code := repo.resolve_realm("player_realm")
	Map3DUnitDress.dress(repo, piece, code, table)
	for fig: Node3D in piece["figs"]:
		assert_same(_body(fig).material_overlay, table.of("infantry"))
		assert_eq(_body(fig).get_instance_shader_parameter("realm_tint"), Map3DUnitDress.tint_of(repo, code))
	# the bearer's standard is not a tunic
	var cloth := (piece["figs"][0] as Node3D).get_child(1).get_child(0) as MeshInstance3D
	assert_null(cloth.material_overlay)


func test_physical_groups_and_late_figures_are_dressed() -> void:
	var repo := SuiteData.repo()
	var a := _piece(2)
	var b := _piece(1)
	var piece := {"layout": "physical_groups", "groups": [{"piece": a}], "model": "infantry"}
	var table := _table()
	var code := repo.resolve_realm("player_realm")
	Map3DUnitDress.dress(repo, piece, code, table)
	piece["groups"].append({"piece": b})   # a group placed after the first dressing
	Map3DUnitDress.dress(repo, piece, code, table)
	assert_same(_body(b["figs"][0]).material_overlay, table.of("infantry"))
	assert_same(_body(a["figs"][1]).material_overlay, table.of("infantry"))


func test_a_model_with_no_mask_is_left_bare() -> void:
	var repo := SuiteData.repo()
	var piece := _piece(2, "cavalry")
	Map3DUnitDress.dress(repo, piece, repo.resolve_realm("player_realm"), _table())
	for fig: Node3D in piece["figs"]:
		assert_null(_body(fig).material_overlay)


func test_war_room_material_untouched() -> void:
	var repo := SuiteData.repo()
	var piece := _piece(1)
	var before := _body(piece["figs"][0]).get_active_material(0)
	Map3DUnitDress.dress(repo, piece, repo.resolve_realm("player_realm"), _table())
	assert_same(_body(piece["figs"][0]).get_active_material(0), before)


func test_the_installed_table_tints_every_arm_on_the_infantry_model() -> void:
	var models := GameArt.table(GameArt.ARMY_MODELS)
	var tints := GameArt.table(GameArt.UNIT_REALM_TINT)
	assert_not_null(tints)
	if tints == null: return
	var infantry := models.of("infantry")
	for key: String in models.art:
		if models.of(key) == infantry:
			assert_true(tints.of(key) is ShaderMaterial, key)
		else:
			assert_null(tints.of(key), key)
	var mat := tints.of("infantry") as ShaderMaterial
	assert_not_null(mat.get_shader_parameter("tunic_mask"))
