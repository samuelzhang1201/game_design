extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The sun turns once round a game day (owner 2026-09-27: 随着时间的流逝，光照
## 光源从西向东缓慢变化), by hand at yaw0 -90, high -40, low -18:
## pitch = -18 + (-22) x (0.5 + 0.5 sin(2 pi f)), yaw = -90 + 360 f.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()
	repo.balance["map3d_sun_day_sweep"] = 1.0
	repo.balance["map3d_sun_day_yaw0_deg"] = -90.0
	repo.balance["map3d_sun_day_high_deg"] = -40.0
	repo.balance["map3d_sun_day_low_deg"] = -18.0


func test_it_rises_in_the_west_and_crosses_to_the_east() -> void:
	assert_almost_eq(Map3DEnvironment.sun_angles(repo, 0.0), Vector2(-29.0, -90.0), Vector2(0.001, 0.001))
	assert_almost_eq(Map3DEnvironment.sun_angles(repo, 0.25), Vector2(-40.0, 0.0), Vector2(0.001, 0.001),
		"highest in the south")
	assert_almost_eq(Map3DEnvironment.sun_angles(repo, 0.5), Vector2(-29.0, 90.0), Vector2(0.001, 0.001),
		"the east")
	assert_almost_eq(Map3DEnvironment.sun_angles(repo, 0.75), Vector2(-18.0, 180.0), Vector2(0.001, 0.001),
		"lowest through the north")


func test_a_yaw_of_minus_90_lights_from_the_west() -> void:
	# the light shines along its -Z: turned by -90 it runs toward +X (east),
	# so it comes FROM the west
	var sun := DirectionalLight3D.new()
	Map3DEnvironment.sweep_sun(repo, sun, 0.0)
	var shine := -sun.transform.basis.z
	assert_gt(shine.x, 0.8)
	sun.free()


func test_the_day_wraps_without_a_jump() -> void:
	var end := Map3DEnvironment.sun_angles(repo, 0.9999)
	var start := Map3DEnvironment.sun_angles(repo, 1.0)
	assert_almost_eq(end.x, start.x, 0.01)
	assert_almost_eq(fposmod(end.y - start.y, 360.0), 360.0, 0.05)


func test_off_it_holds_the_fixed_sun() -> void:
	var r := SuiteData.repo()
	r.balance["map3d_sun_day_sweep"] = 0.0
	assert_eq(Map3DEnvironment.sun_angles(r, 0.4),
		Vector2(r.bal("map3d_sun_pitch_deg"), r.bal("map3d_sun_yaw_deg")))


## The north half is DUSK (owner 2026-09-28: 北边半圈当作黄昏): 0 through the
## south half, rising as smoothstep(0, 1, -sin(2 pi f)) to 1 in the north.
func test_dusk_is_nothing_by_day_and_whole_in_the_north() -> void:
	var r := SuiteData.repo()
	r.balance["map3d_sun_day_sweep"] = 1.0
	r.balance["map3d_sun_dusk"] = 1.0
	assert_eq(Map3DEnvironment.dusk_of(r, 0.25), 0.0, "noon")
	assert_eq(Map3DEnvironment.dusk_of(r, 0.1), 0.0, "the morning")
	assert_almost_eq(Map3DEnvironment.dusk_of(r, 0.5), 0.0, 0.0001, "the east, dusk begins")
	assert_almost_eq(Map3DEnvironment.dusk_of(r, 0.75), 1.0, 0.0001, "the north")
	# f = 7/12: -sin(2 pi 7/12) = 0.5, smoothstep(0.5) = 0.5
	assert_almost_eq(Map3DEnvironment.dusk_of(r, 7.0 / 12.0), 0.5, 0.0001)
	r.balance["map3d_sun_dusk"] = 0.0
	assert_eq(Map3DEnvironment.dusk_of(r, 0.75), 0.0, "switched off")
	r.balance["map3d_sun_dusk"] = 1.0
	r.balance["map3d_sun_day_sweep"] = 0.0
	assert_eq(Map3DEnvironment.dusk_of(r, 0.75), 0.0, "no sweep, no dusk")


func test_at_dusk_the_sun_dims_and_warms_and_the_fill_rises_opposite() -> void:
	var r := SuiteData.repo()
	r.balance["map3d_sun_day_sweep"] = 1.0
	r.balance["map3d_sun_dusk"] = 1.0
	var sun := DirectionalLight3D.new()
	var fill := DirectionalLight3D.new()
	Map3DEnvironment.sweep_sun(r, sun, 0.25, fill)
	assert_almost_eq(sun.light_energy, r.bal("map3d_sun_energy"), 0.0001, "noon: full sun")
	assert_almost_eq(sun.shadow_opacity, r.bal("map3d_sun_shadow_opacity"), 0.0001)
	assert_eq(sun.light_color, Color.WHITE)
	assert_almost_eq(sun.light_specular, r.bal("map3d_sun_specular"), 0.0001)
	assert_almost_eq(fill.light_energy, r.bal("map3d_sun_fill_day"), 0.0001, "a faint fill by day")
	Map3DEnvironment.sweep_sun(r, sun, 0.75, fill)
	assert_almost_eq(sun.light_energy, r.bal("map3d_sun_energy") * r.bal("map3d_sun_dusk_energy"), 0.0001)
	assert_almost_eq(sun.shadow_opacity,
		r.bal("map3d_sun_shadow_opacity") * r.bal("map3d_sun_dusk_shadow"), 0.0001)
	assert_eq(sun.light_color, MapTerrain.palette_color(r, "map3d_sun_dusk", Color.WHITE))
	assert_almost_eq(sun.light_specular, r.bal("map3d_sun_specular") * r.bal("map3d_sun_dusk_specular"), 0.0001)
	assert_true(fill.visible)
	assert_almost_eq(fill.light_energy, r.bal("map3d_sun_dusk_fill"), 0.0001)
	# the sun stands in the north (yaw 180); the fill lights from the south
	assert_almost_eq(fill.rotation_degrees.x, r.bal("map3d_sun_dusk_fill_pitch_deg"), 0.0001)
	assert_almost_eq(fposmod(fill.rotation_degrees.y - sun.rotation_degrees.y, 360.0), 180.0, 0.001)
	sun.free()
	fill.free()
