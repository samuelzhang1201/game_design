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


func test_crop_gain_reaches_the_ground_shader_and_scales_its_amplitude() -> void:
	assert_true(Map3DLayerWind.GROUND.has("crop_gain"), "handed to the ground material")
	assert_true(Map3DGroundWind.UNIFORMS.contains("uniform float wind_crop_gain"))
	assert_true(Map3DGroundWind.STAGE.contains("* wind_crop_gain *"), "scales the amp, storm gain stays")
	var wind := Map3DLayerWind.new()
	autofree(wind)
	assert_gt(wind.crop_gain, 1.0, "stronger than before")
	assert_lte(wind.crop_gain, 4.0)
