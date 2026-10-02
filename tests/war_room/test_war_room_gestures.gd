extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The room takes the 3D map's mouse (spec 2026-10-02-war-room-v2 §1.1): a
## right drag turns and never opens a menu, a right click does, a left drag on
## open table pans in screen directions, the wheel leans about the pointer.

var repo: DataRepository
var rig: WarCamera
var g: WarRoomGestures


func before_each() -> void:
	repo = SuiteData.repo()
	rig = WarCamera.new()
	rig.bounds = Rect2(-0.7, -0.5, 1.4, 1.0)
	g = WarRoomGestures.new()


func _ground(_p: Vector2) -> Vector3:
	return Vector3.ZERO


func _button(index: MouseButton, down: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = down
	e.position = at
	return e


func _motion(mask: int, at: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.button_mask = mask
	e.position = at
	e.relative = rel
	return e


func test_a_right_drag_turns_and_its_release_is_not_a_click() -> void:
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)), rig, repo, _ground, false), WarRoomGestures.NONE)
	assert_eq(g.handle(_motion(MOUSE_BUTTON_MASK_RIGHT, Vector2(140, 100), Vector2(40, 0)), rig, repo, _ground, false), WarRoomGestures.MOVED)
	assert_almost_eq(rig.yaw_deg, -40.0 * repo.bal("war_cam_turn_deg_per_px"), 0.0001, "the 3D map's sign: yaw -= dx * rate")
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, false, Vector2(140, 100)), rig, repo, _ground, false), WarRoomGestures.NONE)


func test_a_small_right_drag_that_comes_back_is_still_a_turn_not_a_click() -> void:
	g.handle(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)), rig, repo, _ground, false)
	g.handle(_motion(MOUSE_BUTTON_MASK_RIGHT, Vector2(130, 100), Vector2(30, 0)), rig, repo, _ground, false)
	g.handle(_motion(MOUSE_BUTTON_MASK_RIGHT, Vector2(101, 100), Vector2(-29, 0)), rig, repo, _ground, false)
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, false, Vector2(101, 100)), rig, repo, _ground, false), WarRoomGestures.NONE)


func test_a_right_click_is_reported() -> void:
	g.handle(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)), rig, repo, _ground, false)
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, false, Vector2(101, 100)), rig, repo, _ground, false), WarRoomGestures.RIGHT_CLICK)


func test_a_left_drag_pans_only_when_allowed() -> void:
	var rel := Vector2(10, 0)
	assert_eq(g.handle(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(110, 0), rel), rig, repo, _ground, false), WarRoomGestures.NONE)
	assert_eq(rig.target, Vector3.ZERO)
	assert_eq(g.handle(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(110, 0), rel), rig, repo, _ground, true), WarRoomGestures.MOVED)
	assert_almost_eq(rig.target.x, -10.0 * rig.distance * repo.bal("war_pan_drag_speed"), 0.00001, "the table follows the pointer")


func test_the_wheel_leans_in() -> void:
	var d := rig.distance
	assert_eq(g.handle(_button(MOUSE_BUTTON_WHEEL_UP, true, Vector2.ZERO), rig, repo, _ground, false), WarRoomGestures.MOVED)
	assert_lt(rig.distance, d)
