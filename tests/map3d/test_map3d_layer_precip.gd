extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The falling rain and snow (spec 2026-09-29-weather-visuals): only while the
## clock runs, only near the camera, sized by the scene's Precip nodes.

var repo: DataRepository
var precip: Map3DLayerPrecip


func before_each() -> void:
	repo = SuiteData.repo()
	var world := (load("res://scenes/map3d/map3d_world.tscn") as PackedScene).instantiate()
	autofree(world)
	precip = world.get_node("Precip")


func test_it_falls_only_while_the_clock_runs() -> void:
	assert_eq(precip.strength_of(repo, false, 1000.0), 0.0, "a paused map is the planning view")
	assert_eq(precip.strength_of(repo, true, 1000.0), 1.0)


func test_it_thins_out_with_the_camera_and_is_gone_far_out() -> void:
	var near := precip.fall_near_view_m
	var far := precip.fall_far_view_m
	assert_eq(precip.strength_of(repo, true, near), 1.0)
	var mid := precip.strength_of(repo, true, (near + far) * 0.5)
	assert_true(mid > 0.0 and mid < 1.0, "half way it thins (%f)" % mid)
	assert_eq(precip.strength_of(repo, true, far), 0.0, "a flake far out read as a settlement dot")


func test_off_is_off() -> void:
	repo.balance["map3d_weather_look"] = 0.0
	assert_eq(precip.strength_of(repo, true, 1000.0), 0.0)


func test_its_two_emitters_are_the_scenes_and_start_still() -> void:
	var view := (load("res://scenes/map3d/world_map_3d.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	var layer := view.get_node("Viewport/World/Precip") as Map3DLayerPrecip
	assert_not_null(layer, "the authored scene carries Viewport/Precip")
	var ctx := Map3DContext.new(repo, {"pack_origin": [0.0, 0.0], "m_per_px": 50.0})
	var weather := Map3DLayerWeather.new()
	weather.bind(ctx, null)
	var authored := {}
	for kind: String in ["Rain", "Snow"]:
		authored[kind] = (layer.get_node(kind) as GPUParticles3D).amount
	layer.build(ctx, weather)
	for kind: String in ["Rain", "Snow"]:
		var node := layer.get_node(kind) as GPUParticles3D
		assert_false(node.emitting, kind + " waits for the clock")
		assert_eq(node.amount, authored[kind], kind + ": the scene's count")
		assert_false(node.local_coords, kind + " falls in the world, so a pan never drags it")
