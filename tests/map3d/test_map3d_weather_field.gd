extends GutTest
## The weather field the 3D map draws (spec 2026-09-29-weather-visuals):
## each land texel its province's weather look, softened into fronts.

var repo: DataRepository
var state: GameState
var field: Map3DWeatherField


func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 7)
	field = Map3DWeatherField.new(repo)


func _a_province() -> String:
	var codes := repo.provinces.keys()
	codes.sort()
	return String(codes[0])


## A land texel deep inside `province`: its seat's pack point.
func _seat_px(province: String) -> Vector2:
	var p: Dictionary = repo.provinces[province]
	return Vector2(float(p["center_x"]), float(p["center_y"]))


func test_each_kind_names_its_look_in_weather_csv() -> void:
	assert_eq(Map3DWeatherField.channels(repo, "clear"), Color(0, 0, 0, 0), "clear draws nothing")
	assert_eq(Map3DWeatherField.channels(repo, "rain"), Color(1, 0, 0, 0.7), "rain: wet under an overcast")
	assert_eq(Map3DWeatherField.fall(repo, "rain"), Vector2(1, 0), "rain falls")
	assert_eq(Map3DWeatherField.fall(repo, "snow"), Vector2(0, 0.4), "snow falls, lighter than a blizzard")
	assert_eq(Map3DWeatherField.channels(repo, "blizzard").b, 1.0, "a blizzard covers the ground")
	for kind: String in repo.weather_kinds:
		for key in ["overcast", "wet", "mud", "snow", "rainfall", "snowfall"]:
			var v := float(repo.weather_kinds[kind][key])
			assert_true(v >= 0.0 and v <= 1.0, "%s %s within 0..1" % [kind, key])


func test_the_field_covers_the_pack_at_its_step() -> void:
	assert_eq(field.step_px, int(repo.bal("map3d_weather_field_step_px")))
	assert_gt(field.size.x, 1)
	assert_gt(field.size.y, 1)


func test_a_snowbound_land_is_white_under_the_field_and_the_open_sea_is_clear() -> void:
	var out := field.build(repo, state, 0, func(_p: String) -> String: return "snow")
	var ground: Image = out["ground"]
	assert_eq(ground.get_size(), field.size)
	var inland := field.sample(ground, _seat_px(_a_province()))
	assert_almost_eq(inland.b, 1.0, 0.02, "snow over the province's seat")
	assert_almost_eq(inland.a, 0.6, 0.02, "under snow's overcast")
	assert_almost_eq(field.sample(ground, Vector2.ZERO).b, 0.0, 0.02, "the far sea corner stays clear")


func test_one_province_under_rain_leaves_a_far_one_dry() -> void:
	var codes := repo.provinces.keys()
	codes.sort()
	var wet := String(codes[0])
	var far := wet
	var best := 0.0
	for c: String in codes:
		var d := _seat_px(c).distance_to(_seat_px(wet))
		if d > best:
			best = d
			far = c
	var out := field.build(repo, state, 0, func(p: String) -> String: return "rain" if p == wet else "clear")
	assert_gt(field.sample(out["ground"], _seat_px(wet)).r, 0.5, "wet under its own rain")
	assert_almost_eq(field.sample(out["ground"], _seat_px(far)).r, 0.0, 0.01, "the far province is dry")
	assert_gt((out["fall"] as Image).get_pixelv(_texel(_seat_px(wet))).r, 0.5, "and rain falls there")


func _texel(px: Vector2) -> Vector2i:
	return Vector2i(clampi(int(px.x / field.step_px), 0, field.size.x - 1),
		clampi(int(px.y / field.step_px), 0, field.size.y - 1))


func test_the_field_reads_weather_of_for_the_spell_it_is_built_for() -> void:
	var out := field.build(repo, state, 5)
	var kinds: Dictionary = out["kinds"]
	var p := _a_province()
	assert_true(kinds.has(p))
	assert_eq(kinds[p], Weather.of(repo, state, p, Map3DWeatherField.first_day_of(repo, 5)))


func test_the_same_spell_builds_the_same_field() -> void:
	var a: Image = field.build(repo, state, 3)["ground"]
	var b: Image = field.build(repo, state, 3)["ground"]
	assert_eq(a.get_data(), b.get_data())


func test_a_spell_turns_to_the_next_only_at_its_end() -> void:
	repo.balance["weather_spell_days"] = 3.0
	repo.balance["map3d_weather_blend_days"] = 0.75
	assert_eq(Map3DWeatherField.blend_of(repo, 1, 0.0), {"spell": 0, "t": 0.0})
	assert_eq(Map3DWeatherField.blend_of(repo, 3, 0.2)["t"], 0.0, "not before the last 0.75 day")
	assert_almost_eq(float(Map3DWeatherField.blend_of(repo, 3, 1.0)["t"]), 1.0, 0.001, "wholly the next at the end")
	var mid := float(Map3DWeatherField.blend_of(repo, 3, 0.625)["t"])
	assert_almost_eq(mid, 0.5, 0.001, "half way through the blend")
	assert_eq(Map3DWeatherField.blend_of(repo, 4, 0.0), {"spell": 1, "t": 0.0}, "the next spell begins clear of blend")
	assert_eq(Map3DWeatherField.first_day_of(repo, 1), 4)
