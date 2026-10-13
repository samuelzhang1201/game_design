extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## WarRoomLights.apply_sun_tier (spec 2026-10-13-war-room-sunlit-chamber): the
## graphics tier says whether the west window's sun casts and whether the
## volumetric fog draws its beam; the fog only where the scene gives it a density.


func _row(tier: String) -> Dictionary:
	return Map3DQuality.row(SuiteData.repo(), tier)


func test_every_tier_names_both_columns() -> void:
	for tier: String in SuiteData.repo().graphics_quality:
		var row := _row(tier)
		assert_true(row.has("war_sun_shadows"), tier)
		assert_true(row.has("war_fog"), tier)


func test_the_tier_sets_the_sun_and_the_fog() -> void:
	var sun := DirectionalLight3D.new()
	var env := Environment.new()
	env.volumetric_fog_density = 0.02
	for tier: String in SuiteData.repo().graphics_quality:
		var row := _row(tier)
		WarRoomLights.apply_sun_tier(sun, env, row)
		assert_eq(sun.shadow_enabled, Map3DQuality.num(row, "war_sun_shadows") >= 1.0, tier)
		assert_eq(env.volumetric_fog_enabled, Map3DQuality.num(row, "war_fog") >= 1.0, tier)
	sun.free()


func test_no_density_means_no_fog_on_any_tier() -> void:
	var env := Environment.new()
	env.volumetric_fog_density = 0.0
	for tier: String in SuiteData.repo().graphics_quality:
		WarRoomLights.apply_sun_tier(null, env, _row(tier))
		assert_false(env.volumetric_fog_enabled, tier)


func test_a_room_without_a_sun_is_no_error() -> void:
	WarRoomLights.apply_sun_tier(null, null, _row("high"))
	pass_test("no sun, no environment")
