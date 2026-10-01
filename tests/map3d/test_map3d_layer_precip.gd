extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The falling rain and snow (spec 2026-09-29-weather-visuals): only while the
## clock runs, only near the camera, sized from balance.csv.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_it_falls_only_while_the_clock_runs() -> void:
	assert_eq(Map3DLayerPrecip.strength_of(repo, false, 1000.0), 0.0, "a paused map is the planning view")
	assert_eq(Map3DLayerPrecip.strength_of(repo, true, 1000.0), 1.0)


func test_it_thins_out_with_the_camera_and_is_gone_far_out() -> void:
	var near := repo.bal("map3d_weather_fall_near_view_m")
	var far := repo.bal("map3d_weather_fall_far_view_m")
	assert_eq(Map3DLayerPrecip.strength_of(repo, true, near), 1.0)
	var mid := Map3DLayerPrecip.strength_of(repo, true, (near + far) * 0.5)
	assert_true(mid > 0.0 and mid < 1.0, "half way it thins (%f)" % mid)
	assert_eq(Map3DLayerPrecip.strength_of(repo, true, far), 0.0, "a flake far out read as a settlement dot")


func test_off_is_off() -> void:
	repo.balance["map3d_weather_look"] = 0.0
	assert_eq(Map3DLayerPrecip.strength_of(repo, true, 1000.0), 0.0)


func test_its_two_emitters_are_the_scenes_and_start_still() -> void:
	var view := (load("res://scenes/map3d/world_map_3d.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	var precip := view.get_node("Viewport/Precip") as Map3DLayerPrecip
	assert_not_null(precip, "the authored scene carries Viewport/Precip")
	var ctx := Map3DContext.new(repo, {"pack_origin": [0.0, 0.0], "m_per_px": 50.0})
	var weather := Map3DLayerWeather.new()
	weather.bind(ctx, null)
	precip.build(ctx, weather)
	for kind: String in ["rain", "snow"]:
		var node := precip.get_node(kind.capitalize()) as GPUParticles3D
		assert_false(node.emitting, kind + " waits for the clock")
		assert_eq(node.amount, int(repo.bal("map3d_weather_%s_count" % kind)), kind)
		assert_false(node.local_coords, kind + " falls in the world, so a pan never drags it")
