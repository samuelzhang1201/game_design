extends GutTest
## Map3DLayerWind (owner 2026-09-30): the wind's clock runs only while the
## game's clock does, like the clouds and the falling rain.


func _layer(speed: Array) -> Map3DLayerWind:
	var ctx := Map3DContext.new(Game.data, {})
	ctx.clock_fn = func() -> int: return speed[0]
	var wind := Map3DLayerWind.new()
	add_child_autofree(wind)
	wind.bind(ctx)
	return wind


func test_a_paused_clock_holds_the_wind() -> void:
	var wind := _layer([0])
	wind._process(0.5)
	assert_eq(wind.time(), 0.0)


func test_a_running_clock_blows_at_real_time_whatever_its_speed() -> void:
	var speed := [1]
	var wind := _layer(speed)
	wind._process(0.5)
	speed[0] = 4
	wind._process(0.5)
	assert_almost_eq(wind.time(), 1.0, 0.0001, "a 4x clock is not a gale")


func test_tilt_reaches_the_ground_shader() -> void:
	assert_true(Map3DLayerWind.GROUND.has("tilt"), "handed to the ground material")
	assert_true(Map3DGroundWind.UNIFORMS.contains("uniform float wind_tilt"))
	assert_true(Map3DGroundWind.STAGE.contains("wind_tilt"), "the stage reads it")
	assert_true(Map3DGroundWind.STAGE.contains("mat.normal_rough.xyz = normalize("), "bends the shading normal, kept unit")
	assert_false(Map3DGroundWind.UNIFORMS.contains("wind_crop_gain"), "the first pass's gain is gone")
	var wind := Map3DLayerWind.new()
	autofree(wind)
	assert_true(wind.tilt > 0.0, "on by default")
	assert_true(Map3DGroundWind.STAGE.contains("max(wd_val, 0.0) * wind_tilt, 0.0, 0.6)"),
		"the stalks lean as far as the crest lays them (the wave itself, so it travels and keeps its AA), clamped")
	assert_false(Map3DGroundWind.STAGE.contains("wd_slope"), "not the slope: a thin line at each front, never seen")


## Records set_shader_param like Terrain3DMaterial.
class FakeMaterial:
	extends Resource
	var params: Dictionary = {}
	var _shader_parameters: Dictionary:
		get: return params
	var reads := 0
	func set_shader_param(key: String, value: Variant) -> void: params[key] = value
	func get_shader_param(key: String) -> Variant:
		reads += 1
		return params.get(key)


## A stand-in Terrain3D: headless has none.
class FakeTerrain:
	extends Node
	var material: Resource


func test_a_changed_export_reaches_the_ground_after_the_first_push() -> void:
	var wind := _layer([0])
	var terrain := FakeTerrain.new()
	add_child_autofree(terrain)
	var mat := FakeMaterial.new()
	terrain.material = mat
	wind.ctx.terrain = terrain
	wind._process(0.1)
	assert_almost_eq(float(mat.params.get("wind_tilt")), wind.tilt, 0.0001, "the first push")
	wind.tilt = 0.3 if wind.tilt != 0.3 else 0.2
	wind.deg = 90.0
	wind._process(0.1)
	assert_almost_eq(float(mat.params.get("wind_tilt")), wind.tilt, 0.0001,
		"a later value (the inspector, a shot's --set) is handed on, not only on a reset")
	assert_almost_eq((mat.params.get("wind_dir") as Vector2).y, 1.0, 0.0001, "and the direction")
	mat.params.clear()
	wind._process(0.1)
	assert_eq(mat.params.get("wind_on"), 1.0, "a native material reset restores the wind")
	assert_eq(mat.reads, 0, "uniform checks do not synchronize with the render server")
	var replacement := FakeMaterial.new()
	terrain.material = replacement
	wind._process(0.1)
	assert_eq(replacement.params.get("wind_on"), 1.0, "a replacement material is initialized")
	assert_almost_eq(float(replacement.params.get("wind_tilt")), wind.tilt, 0.0001)
	assert_eq(replacement.reads, 0)
