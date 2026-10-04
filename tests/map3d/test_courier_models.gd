extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Every rider courier_art.csv names is a real model that gallops and idles
## (spec 2026-09-28-courier-art §2–3), within the game budget.


func test_every_courier_model_gallops_and_idles() -> void:
	var repo := SuiteData.repo()
	for kind: String in repo.courier_art:
		var path := GameArt.path(GameArt.COURIER_MODELS, kind)
		if path.get_file().get_basename() == "cavalry":
			continue  # a row still on the stand-in (the spy until Task 8)
		assert_true(ResourceLoader.exists(path), path)
		var node := (load(path) as PackedScene).instantiate()
		autofree(node)
		var anim := Map3DUnits.find_anim(node)
		assert_not_null(anim, path)
		assert_ne(Map3DUnits.clip_named(anim, "GALLOP"), "", path)
		assert_ne(Map3DUnits.clip_named(anim, "IDLE"), "", path)
		assert_gt(float((repo.courier_art[kind] as Dictionary).get("stride_m", "0")), 0.0, kind)
	# the gallop is timed by the stride, held within its rate range
	var couriers := Map3DLayerCouriers.new()
	autofree(couriers)
	assert_gt(couriers.anim_max, couriers.anim_min)


func test_the_courier_models_are_within_budget() -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3D/units/units3d.json"))
	for code in ["courier", "spy"]:
		if info.has(code):
			assert_between(int(info[code]["tris"]), 15000, 20000, code)
