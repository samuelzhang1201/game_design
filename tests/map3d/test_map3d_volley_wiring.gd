extends GutTest
## The arrow rain's wiring (spec 2026-11-28-archer-arrow-rain-design.md): the
## archers' measured release share and the authored MultiMesh scene.

const SuiteData := preload("res://tests/suite_data.gd")


func test_archers_release_share_is_measured() -> void:
	var share := float(Map3DDuel.contact_of(SuiteData.repo().army_art["archers"]).get("ATTACK", -1.0))
	assert_almost_eq(share, 55.0 / 68.0, 0.001, "the key where cc_arrow drops to 0.001")


func test_arrow_scene_is_one_multimesh() -> void:
	var node := (load(GameArt.ARROW_VOLLEY) as PackedScene).instantiate() as MultiMeshInstance3D
	assert_not_null(node)
	assert_not_null(node.multimesh.mesh)
	assert_eq(node.multimesh.transform_format, MultiMesh.TRANSFORM_3D)
	assert_true(node.multimesh.use_colors, "the fade is the instance alpha")
	var box := node.multimesh.mesh.get_aabb()
	assert_almost_eq(box.position.z, 0.0, 0.001, "the tip at the origin")
	assert_gt(box.end.z, 0.3, "the shaft along +Z")
	node.free()
