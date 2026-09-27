extends GutTest
## The sun turns once round a game day (owner 2026-09-27: 随着时间的流逝，光照
## 光源从西向东缓慢变化), by hand at yaw0 -90, high -40, low -18:
## pitch = -18 + (-22) x (0.5 + 0.5 sin(2 pi f)), yaw = -90 + 360 f.

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")
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
	var r := DataRepository.load_all("res://data")
	r.balance["map3d_sun_day_sweep"] = 0.0
	assert_eq(Map3DEnvironment.sun_angles(r, 0.4),
		Vector2(r.bal("map3d_sun_pitch_deg"), r.bal("map3d_sun_yaw_deg")))
