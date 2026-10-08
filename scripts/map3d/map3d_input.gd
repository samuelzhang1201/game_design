class_name Map3DInput
extends RefCounted
## The 3D map's pointer and keys (spec 2026-09-20 §1; was Map3DView._gui_input
## and the key half of _process). Left or middle drag pans, right drag turns,
## the wheel and a trackpad pinch zoom about the pointer, a two-finger drag
## pans, WASD / arrows pan. A press on the compass eases north (the MEASUREMENT
## ruler went 2026-10-02, owner). Shift + left click toggles a unit in or out of
## the selection, and Shift + left drag draws the selection box (spec
## 2026-10-07-army-split-and-ground §5.6, ruling R4: a plain drag pans).
## handle() returns true exactly where the view used to accept_event().

## A press and release further apart than this is a drag (WorldMapView.CLICK_SLOP).
const CLICK_SLOP := 10.0

var view: Map3DView
var rig: Map3DCameraRig
var repo: DataRepository
var _press_pos := Vector2.ZERO
var _dragging := false
var _press_on_hud := false
## A Shift + left press is down: its drag draws the box, its click toggles.
var _boxing := false
var _rpress_pos := Vector2.ZERO
## Whether the right button has turned the view since it went down.
var _rdragged := false
## A planned march's line, bent by a left drag while its confirm stands.
var route := Map3DRouteEdit.new()


func bind(p_view: Map3DView, p_rig: Map3DCameraRig, p_repo: DataRepository) -> void:
	view = p_view
	rig = p_rig
	repo = p_repo
	route.bind(p_view, p_rig)


## Takes one event; true when the view takes it. Its camera moves are told to
## the listeners once a frame (Map3DCameraRig.hold_moved, flushed by the rig's
## step) — a trackpad sends several gestures a frame (perf 2026-10-02); a click
## is picked against what they placed, so they hear first.
func handle(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		rig.flush()
	rig.hold_moved = true
	var took := _take(event)
	rig.hold_moved = false
	return took


func _take(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		var gain := repo.bal("map3d_pinch_zoom_gain")
		rig.zoom_at(mg.position, rig.ctx.distance / maxf(1.0 + (mg.factor - 1.0) * gain, 0.01))
		return true
	if event is InputEventPanGesture:
		rig.pan_by(-(event as InputEventPanGesture).delta * repo.bal("map3d_pan_gesture_px"))
		return true
	if event is InputEventMouseButton:
		return _button(event as InputEventMouseButton)
	if event is InputEventMouseMotion:
		return _motion(event as InputEventMouseMotion)
	return false


func _button(mb: InputEventMouseButton) -> bool:
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var steps := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		rig.zoom_at(mb.position, rig.ctx.distance * pow(repo.bal("map3d_zoom_factor"), steps))
		return true
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and view.compass_rect().has_point(mb.position):
			rig.start_north()
			_press_on_hud = true
			# in step with an ordinary press: a stale press point would let a
			# press-and-move on the compass pan from an old spot
			_press_pos = mb.position
			_dragging = false
			return true
		if not mb.pressed and _press_on_hud:
			_press_on_hud = false
			return true
		if mb.pressed and route.press(mb.position):
			return true   # a press on the planned route takes a waypoint, no pan
		if not mb.pressed and route.bending():
			route.release()
			return true
		# an aimed order's click is its destination, Shift or not
		if mb.pressed and mb.shift_pressed and not view.aiming:
			_boxing = true
			_press_pos = mb.position
			_dragging = false
			return true
		if not mb.pressed and _boxing:
			_boxing = false
			view.box_rect = Rect2()
			if _dragging:
				view.select_box(Rect2(_press_pos, Vector2.ZERO).expand(mb.position))
			else:
				view.toggle_at(mb.position)
			_dragging = false
			return true
		if mb.pressed:
			_press_pos = mb.position
			_dragging = false
			if _boxing:   # a Shift press whose release was lost: this one pans
				_boxing = false
				view.box_rect = Rect2()
		elif not _dragging:
			view.select_at(mb.position)
		return true
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_rpress_pos = mb.position
			_rdragged = false
		elif not _rdragged:
			# A right CLICK, never a turn: the order menu of the regiment under
			# it, or — since fix round 1, 2026-09-28 — an offer to send a spy
			# there when the ground was hit instead; only a click on the sky
			# still falls through untouched.
			if view.right_click(mb.position):
				return true
	return false


func _motion(mm: InputEventMouseMotion) -> bool:
	if mm.button_mask == 0:
		view.request_hover(mm.position)
	else:
		view.clear_hover()
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _press_on_hud:
			return true
		if route.bending():
			route.drag(mm.position)
			return true
		if _boxing:
			if not _dragging and _press_pos.distance_to(mm.position) > CLICK_SLOP:
				_dragging = true
			if _dragging:
				view.box_rect = Rect2(_press_pos, Vector2.ZERO).expand(mm.position)
			return true
		if not _dragging and _press_pos.distance_to(mm.position) > CLICK_SLOP:
			_dragging = true
		if _dragging:
			rig.pan_by(mm.relative)
		return true
	if mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		rig.pan_by(mm.relative)
		return true
	if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		if _rpress_pos.distance_to(mm.position) > CLICK_SLOP:
			_rdragged = true
		rig.turn_by(mm.relative.x)
		return true
	return false


## WASD / arrows move the VIEW, so the ground moves the other way from a
## drag; true when it moved (the hover re-picks under a still pointer).
func key_pan(delta: float) -> bool:
	if rig == null:
		return false
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return false
	rig.pan_by(-dir.normalized() * view.size.y * repo.bal("map3d_key_pan_screens_per_s") * delta)
	return true
