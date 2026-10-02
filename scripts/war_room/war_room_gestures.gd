class_name WarRoomGestures
extends RefCounted
## The room camera's gestures (spec 2026-10-02-war-room-v2 §1.1), the 3D map's
## (Map3DInput): a right DRAG turns, a right CLICK is reported for the order
## menu, a left drag on open table pans (the view says when: a press on a piece
## is the rake's), the middle button and a two-finger drag pan, the wheel and a
## pinch lean about the pointer, WASD / arrows pan. Moves the rig; the view
## applies it to the camera.

enum { NONE, MOVED, RIGHT_CLICK }

var _rpress := Vector2.ZERO
var _rdragged := false


func handle(event: InputEvent, rig: WarCamera, repo: DataRepository, ground_at: Callable, left_pans: bool) -> int:
	var slop := repo.bal("war_click_slop_px")
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := repo.bal("war_cam_zoom_step")
			rig.zoom_about(ground_at.call(mb.position), 1.0 / step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step)
			return MOVED
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rpress = mb.position
				_rdragged = false
				return NONE
			if not _rdragged and mb.position.distance_to(_rpress) <= slop:
				return RIGHT_CLICK
		return NONE
	if event is InputEventMagnifyGesture:
		var gm := event as InputEventMagnifyGesture
		rig.zoom_about(ground_at.call(gm.position), 1.0 / maxf(gm.factor, 0.01))
		return MOVED
	if event is InputEventPanGesture:
		rig.pan_view((event as InputEventPanGesture).delta * rig.distance * repo.bal("war_pan_gesture_speed"))
		return MOVED
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if mm.position.distance_to(_rpress) > slop:
				_rdragged = true   # once a turn, never a click, even back at the press
			rig.turn(-mm.relative.x * repo.bal("war_cam_turn_deg_per_px"))
			return MOVED
		if (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) or (left_pans and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT)):
			rig.pan_view(-mm.relative * rig.distance * repo.bal("war_pan_drag_speed"))
			return MOVED
	return NONE


## The keys held now as a screen direction (x right, y down), unit or zero.
static func key_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir.normalized()
