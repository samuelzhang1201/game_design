class_name WarRoomGestures
extends RefCounted
## The room camera's gestures (spec 2026-10-01-war-room-design §1): the wheel
## and a trackpad pinch lean about the pointer, a two-finger drag and the
## middle button pan. Moves the rig; the view applies it to the camera.


## True when `event` moved the rig. `ground_at(screen_px)` is the table point
## under a pointer, or the rig's own target when it is off the table.
static func apply(event: InputEvent, rig: WarCamera, repo: DataRepository, ground_at: Callable) -> bool:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := repo.bal("war_cam_zoom_step")
			rig.zoom_about(ground_at.call(mb.position), 1.0 / step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step)
			return true
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		rig.zoom_about(ground_at.call(g.position), 1.0 / maxf(g.factor, 0.01))
		return true
	elif event is InputEventPanGesture:
		rig.pan((event as InputEventPanGesture).delta * rig.distance * repo.bal("war_pan_gesture_speed"))
		return true
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		rig.pan(-(event as InputEventMouseMotion).relative * rig.distance * repo.bal("war_pan_drag_speed"))
		return true
	return false
