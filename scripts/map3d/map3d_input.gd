class_name Map3DInput
extends RefCounted
## The 3D map's pointer and keys (spec 2026-09-20 §1; was Map3DView._gui_input
## and the key half of _process). Left or middle drag pans, right drag turns,
## the wheel and a trackpad pinch zoom about the pointer, a two-finger drag
## pans, WASD / arrows pan. A press on the compass eases north. With the
## ruler on, a left click measures and a right CLICK (not a turn) puts it
## away. handle() returns true exactly where the view used to accept_event().

## A press and release further apart than this is a drag (WorldMapView.CLICK_SLOP).
const CLICK_SLOP := 10.0

var view: Map3DView
var rig: Map3DCameraRig
var repo: DataRepository
var _press_pos := Vector2.ZERO
var _dragging := false
var _press_on_hud := false
var _rpress_pos := Vector2.ZERO
## Whether the right button has turned the view since it went down.
var _rdragged := false


func bind(p_view: Map3DView, p_rig: Map3DCameraRig, p_repo: DataRepository) -> void:
	view = p_view
	rig = p_rig
	repo = p_repo


func handle(event: InputEvent) -> bool:
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
		if mb.pressed:
			_press_pos = mb.position
			_dragging = false
		elif not _dragging:
			if view.ruler_on:
				view.ruler_click(mb.position)
			else:
				view.select_at(mb.position)
		return true
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_rpress_pos = mb.position
			_rdragged = false
		elif not _rdragged:
			# A right CLICK, never a turn. With the ruler up it puts the ruler
			# away; otherwise it asks for the order menu of the regiment under
			# it — and is taken ONLY if there was one, so a right click on open
			# country still falls through untouched as it always did.
			if view.ruler_on:
				if view.ruler().cancel():
					view.refresh_hud()
			elif view.right_click(mb.position):
				return true
	return false


func _motion(mm: InputEventMouseMotion) -> bool:
	if view.ruler_on and view.ruler().phase == MapRuler.Phase.STRETCHING:
		var hit: Variant = view.ground_at(mm.position)
		if hit != null and view.ruler().move(Vector2((hit as Vector3).x, (hit as Vector3).z)):
			view.refresh_hud()
	if mm.button_mask == 0:
		view.request_hover(mm.position)
	else:
		view.clear_hover()
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _press_on_hud:
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
