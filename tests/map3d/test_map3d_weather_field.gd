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


## The province with the most manors.
func _largest() -> String:
	var best := ""
	var most := 0
	for code: String in repo.provinces:
		var n := MapManors.manors_of_province(repo, code).size()
		if n > most:
			most = n
			best = code
	return best


## A land texel deep inside `province`: its seat's pack point.
func _seat_px(province: String) -> Vector2:
	var p: Dictionary = repo.provinces[province]
	return Vector2(float(p["center_x"]), float(p["center_y"]))


func test_each_kind_names_its_look_in_weather_csv() -> void:
	assert_eq(Map3DWeatherField.channels(repo, "clear"), Color(0, 0, 0, 0), "clear draws nothing")
	assert_eq(Map3DWeatherField.channels(repo, "rain"), Color(1, 0, 0, 0.7), "rain: wet under an overcast")
	assert_eq(Map3DWeatherField.fall(repo, "rain"), Vector3(1, 0, 0.2), "rain falls on a light wind")
	assert_eq(Map3DWeatherField.fall(repo, "snow"), Vector3(0, 0.4, 0), "snow falls, lighter than a blizzard")
	assert_eq(Map3DWeatherField.fall(repo, "blizzard"), Vector3(0, 1, 1), "a blizzard drives it sideways")
	assert_eq(Map3DWeatherField.channels(repo, "blizzard").b, 1.0, "a blizzard covers the ground")
	for kind: String in repo.weather_kinds:
		for key in ["overcast", "wet", "mud", "snow", "rainfall", "snowfall", "gust"]:
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
	var inland := field.sample(ground, _seat_px(_largest()))
	assert_almost_eq(inland.b, 1.0, 0.02, "snow over the province's seat")
	assert_almost_eq(inland.a, 0.6, 0.02, "under snow's overcast")
	assert_gt(field.sample(ground, _seat_px(_a_province())).b, 0.6,
		"even a five-cell province keeps its weather at its seat (map3d_weather_cell_min_px)")
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


## Owner 2026-09-29 (天气效果不用铺满整个省份，再小一点): a province's weather
## is a cell round its centre, fading out well before its border.
func test_a_provinces_weather_is_a_cell_round_its_centre_not_a_blanket() -> void:
	var out := field.build(repo, state, 0, func(_p: String) -> String: return "snow")
	var ground: Image = out["ground"]
	var land := 0
	var covered := 0
	for j in field.size.y:
		for i in field.size.x:
			if field._texel_prov[j * field.size.x + i] < 0:
				continue
			land += 1
			covered += 1 if ground.get_pixel(i, j).b > 0.5 else 0
	assert_gt(land, 0)
	var share := float(covered) / float(land)
	assert_true(share > 0.1 and share < 0.6, "a snowbound land is patches, not a sheet (%.2f of it)" % share)
	# along a line from the largest province's centre outward, the snow fades
	var best := _largest()
	var most := MapManors.manors_of_province(repo, best).size()
	var c := _seat_px(best)
	assert_gt(field.sample(ground, c).b, 0.8, "whole at the centre")
	var r := sqrt(float(most) * 250.0 / PI)  # a cell is ~250 pack px²: well past the core
	var rim := 1.0
	for a in 8:
		rim = minf(rim, field.sample(ground, c + Vector2.from_angle(a * TAU / 8.0) * r * 1.2).b)
	assert_lt(rim, 0.5, "fading toward the border")
