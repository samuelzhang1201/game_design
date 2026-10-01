extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The weather's look on the ground (spec 2026-09-29-weather-visuals):
## Map3DLayerWeather hands the field to the terrain material and turns it to
## the next spell's as the spell ends. The material is a stand-in: headless
## has no Terrain3D.

## Records set_shader_param like Terrain3DMaterial.
class FakeMaterial:
	extends Resource
	var params: Dictionary = {}
	func set_shader_param(key: String, value: Variant) -> void: params[key] = value
	func get_shader_param(key: String) -> Variant: return params.get(key)

var repo: DataRepository
var state: GameState
var ctx: Map3DContext
var mat: FakeMaterial
var share := 0.0


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 7)
	ctx = Map3DContext.new(repo, {"pack_origin": [0.0, 0.0], "m_per_px": 50.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.day_fn = func() -> float: return share
	mat = FakeMaterial.new()
	share = 0.0


func _layer() -> Map3DLayerWeather:
	var w := Map3DLayerWeather.new()
	w.bind(ctx, mat)
	return w


func test_a_step_puts_the_field_on_the_ground() -> void:
	_layer().step()
	assert_eq(mat.params.get("weather_on"), 1.0)
	assert_true(mat.params.get("weather_now") is ImageTexture, "this spell's field")
	assert_true(mat.params.get("weather_next") is ImageTexture, "and the next's")
	assert_eq(mat.params.get("weather_step_px"), repo.bal("map3d_weather_field_step_px"))
	assert_eq(mat.params.get("weather_snow_detail"), repo.bal("map3d_weather_snow_detail"),
		"every tuning value comes from balance.csv")
	assert_eq(mat.params.get("weather_blend"), 0.0, "the first day of a spell is wholly its own")


func test_the_ground_turns_to_the_next_spell_as_the_spell_ends() -> void:
	var w := _layer()
	state.day = int(repo.bal("weather_spell_days"))  # the spell's last day
	share = 1.0
	w.step()
	assert_almost_eq(float(mat.params["weather_blend"]), 1.0, 0.001)


func test_a_lost_uniform_is_put_back() -> void:
	var w := _layer()
	w.step()
	mat.params.clear()  # Terrain3D rebuilt its material
	w.step()
	assert_eq(mat.params.get("weather_on"), 1.0)
	assert_not_null(mat.params.get("weather_now"))


func test_a_forced_sky_covers_every_province() -> void:
	var w := _layer()
	w.set_override("snow")
	w.step()
	var p: Dictionary = repo.provinces[repo.provinces.keys()[0]]
	var xz := ctx.to_world(Vector2(float(p["center_x"]), float(p["center_y"])))
	assert_gt(w.look_at(xz).b, 0.5, "snow under a forced snowfall")
	w.set_override("snow,rain")
	w.step()
	var kinds := {}
	for code: String in repo.provinces:
		kinds[w.kind_of(code)] = true
	assert_eq(kinds.keys().size(), 2, "a list is shared out among the provinces")


func test_off_leaves_the_ground_alone() -> void:
	repo.balance["map3d_weather_look"] = 0.0
	_layer().step()
	assert_false(mat.params.has("weather_on"))
