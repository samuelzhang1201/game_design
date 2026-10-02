extends GutTest
## The sun turns once round a game day (owner 2026-09-27: 随着时间的流逝，光照
## 光源从西向东缓慢变化), by hand at yaw0 -90, high -40, low -18:
## pitch = -18 + (-22) x (0.5 + 0.5 sin(2 pi f)), yaw = -90 + 360 f. Its day
## is the world scene's Sun (Map3DSun, owner 2026-10-02: edited in the editor).

var sun: Map3DSun
var fill: DirectionalLight3D


func before_each() -> void:
	sun = Map3DSun.new()
	fill = DirectionalLight3D.new()
	sun.fill = fill
	sun.yaw0_deg = -90.0
	sun.high_deg = -40.0
	sun.low_deg = -18.0


func after_each() -> void:
	sun.free()
	fill.free()


func test_it_rises_in_the_west_and_crosses_to_the_east() -> void:
	assert_almost_eq(sun.angles(0.0), Vector2(-29.0, -90.0), Vector2(0.001, 0.001))
	assert_almost_eq(sun.angles(0.25), Vector2(-40.0, 0.0), Vector2(0.001, 0.001), "highest in the south")
	assert_almost_eq(sun.angles(0.5), Vector2(-29.0, 90.0), Vector2(0.001, 0.001), "the east")
	assert_almost_eq(sun.angles(0.75), Vector2(-18.0, 180.0), Vector2(0.001, 0.001), "lowest through the north")


func test_a_yaw_of_minus_90_lights_from_the_west() -> void:
	# the light shines along its -Z: turned by -90 it runs toward +X (east),
	# so it comes FROM the west
	sun.sweep(0.0)
	assert_gt((-sun.transform.basis.z).x, 0.8)


func test_the_day_wraps_without_a_jump() -> void:
	var end := sun.angles(0.9999)
	var start := sun.angles(1.0)
	assert_almost_eq(end.x, start.x, 0.01)
	assert_almost_eq(fposmod(end.y - start.y, 360.0), 360.0, 0.05)


func test_off_it_holds_the_node_where_it_is_turned() -> void:
	sun.day_sweep = false
	sun.rotation_degrees = Vector3(-35.0, -45.0, 0.0)
	assert_almost_eq(sun.angles(0.4), Vector2(-35.0, -45.0), Vector2(0.001, 0.001))


## The north half is DUSK (owner 2026-09-28: 北边半圈当作黄昏): 0 through the
## south half, rising as smoothstep(0, 1, -sin(2 pi f)) to 1 in the north.
func test_dusk_is_nothing_by_day_and_whole_in_the_north() -> void:
	assert_eq(sun.dusk_of(0.25), 0.0, "noon")
	assert_eq(sun.dusk_of(0.1), 0.0, "the morning")
	assert_almost_eq(sun.dusk_of(0.5), 0.0, 0.0001, "the east, dusk begins")
	assert_almost_eq(sun.dusk_of(0.75), 1.0, 0.0001, "the north")
	# f = 7/12: -sin(2 pi 7/12) = 0.5, smoothstep(0.5) = 0.5
	assert_almost_eq(sun.dusk_of(7.0 / 12.0), 0.5, 0.0001)
	sun.dusk = false
	assert_eq(sun.dusk_of(0.75), 0.0, "switched off")
	sun.dusk = true
	sun.day_sweep = false
	assert_eq(sun.dusk_of(0.75), 0.0, "no sweep, no dusk")


func test_at_dusk_the_sun_dims_and_warms_and_the_fill_rises_opposite() -> void:
	sun.sweep(0.25)
	assert_almost_eq(sun.light_energy, sun.day_energy, 0.0001, "noon: full sun")
	assert_almost_eq(sun.shadow_opacity, sun.day_shadow_opacity, 0.0001)
	assert_eq(sun.light_color, Color.WHITE)
	assert_almost_eq(sun.light_specular, sun.day_specular, 0.0001)
	assert_almost_eq(fill.light_energy, sun.fill_day, 0.0001, "a faint fill by day")
	sun.sweep(0.75)
	assert_almost_eq(sun.light_energy, sun.day_energy * sun.dusk_energy, 0.0001)
	assert_almost_eq(sun.shadow_opacity, sun.day_shadow_opacity * sun.dusk_shadow, 0.0001)
	assert_eq(sun.light_color, sun.dusk_color)
	assert_almost_eq(sun.light_specular, sun.day_specular * sun.dusk_specular, 0.0001)
	assert_true(fill.visible)
	assert_almost_eq(fill.light_energy, sun.fill_dusk, 0.0001)
	# the sun stands in the north (yaw 180); the fill lights from the south
	assert_almost_eq(fill.rotation_degrees.x, sun.fill_pitch_deg, 0.0001)
	assert_almost_eq(fposmod(fill.rotation_degrees.y - sun.rotation_degrees.y, 360.0), 180.0, 0.001)


## The shadows reach a share of the camera's distance, between the sun's floor
## and the tier's (or its own) ceiling.
func test_the_shadows_follow_the_camera() -> void:
	sun.follow(10000.0, 0.0)
	assert_almost_eq(sun.directional_shadow_max_distance, sun.shadow_per_view * 10000.0, 0.01)
	sun.follow(10.0, 0.0)
	assert_almost_eq(sun.directional_shadow_max_distance, sun.shadow_min_m, 0.01, "never under the floor")
	sun.follow(1e9, 30000.0)
	assert_almost_eq(sun.directional_shadow_max_distance, 30000.0, 0.01, "never past the tier's reach")
