@tool
class_name Map3DCameraRig
extends Node3D
## The 3D map's camera (spec 2026-09-20 §1): a target on the ground, a
## distance, a yaw, and a tilt that follows the distance (Map3DGeometry). The
## pose lives in the context — every layer reads it there — and each move
## ends in ctx.camera_moved. A press on the compass eases the view back to
## north over map3d_compass_reset_s.

## Editor preview (Task 22): an UNOWNED camera of its own over the map's
## centre at the opening zoom, so the other layers' previews are seen from
## where the game opens and nothing is written to the scene's own RigCamera.
@export var preview := false: set = set_preview

var ctx: Map3DContext
var _camera: Camera3D
var _north_t := -1.0
var _north_from := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_camera()


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		Map3DPreview.clear_generated(self)
		_camera = get_node_or_null("RigCamera") as Camera3D
		if _camera != null:
			# The preview camera is gone: the scene's own must take the view
			# back, or the SubViewport draws nothing (Task 22 review). The
			# `current` this writes is cleared again before any save
			# (Map3DPreview.reset).
			_camera.make_current()
	Map3DPreview.sync_viewport(self)


## The rig over the map's centre at the opening zoom (the pose the game opens
## on), so the other layers' previews are seen from where the game opens. The
## scene's own RigCamera is AUTHORED — its transform and lens are saved
## properties — so a preview drives an UNOWNED camera of its own instead.
func preview_build(p_ctx: Map3DContext) -> void:
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		return
	ctx = p_ctx
	var cam := Camera3D.new()
	cam.name = "PreviewCamera"
	cam.fov = p_ctx.repo.bal("map3d_fov_deg")
	cam.near = p_ctx.repo.bal("map3d_near_m")
	cam.far = p_ctx.repo.bal("map3d_far_m")
	Map3DPreview.clear_generated(self)
	add_child(cam)  # no owner: never saved
	cam.make_current()
	_camera = cam
	p_ctx.camera = cam
	place(p_ctx.bounds.get_center(), p_ctx.repo.bal("map3d_zoom_start_m"), 0.0)


## The rig's own camera, made once (on _ready, or on bind if the rig is not
## yet in a tree).
func _ensure_camera() -> void:
	if _camera != null:
		return
	_camera = get_node_or_null("RigCamera") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "RigCamera"
		add_child(_camera)


func bind(p_ctx: Map3DContext) -> void:
	_ensure_camera()
	ctx = p_ctx
	_camera.fov = ctx.repo.bal("map3d_fov_deg")
	_camera.near = ctx.repo.bal("map3d_near_m")
	_camera.far = ctx.repo.bal("map3d_far_m")
	_camera.make_current()
	ctx.camera = _camera


func camera() -> Camera3D:
	return _camera


## The farthest the rig may sit: balance.csv's ceiling, and never so far that
## the SCALE BAR would read above map3d_zoom_max_scale of the pack's own
## measure (owner 2026-09-20: "设置zoom out标尺最多150km" — 150 km lands on the
## ladder's 100 km rung). Before the view has a size there is no bar to read,
## so only the ceiling applies.
func max_distance() -> float:
	var r := ctx.repo
	return Map3DGeometry.zoom_ceiling_m(r.bal("map3d_zoom_max_m"), r.bal("map3d_zoom_max_scale"),
		Map3DGeometry.map_units_per_metre(r.map_info, ctx.meta), r.bal("map_scale_bar_max_px"),
		r.bal("map3d_fov_deg"), ctx.view_size.y)


## Put the rig at a world XZ (clamped to the world), a distance (clamped to
## the zoom range, max_distance included) and a yaw.
func place(target_xz: Vector2, distance_m: float, yaw_deg: float) -> void:
	ctx.target = Map3DGeometry.clamp_target(target_xz, ctx.bounds)
	ctx.distance = clampf(distance_m, ctx.repo.bal("map3d_zoom_min_m"), max_distance())
	ctx.yaw = yaw_deg
	apply()


## The camera at the context's pose (was Map3DView._apply_camera).
func apply() -> void:
	var r := ctx.repo
	var pitch := Map3DGeometry.pitch_for(ctx.distance, r.bal("map3d_zoom_min_m"),
		r.bal("map3d_zoom_max_m"), r.bal("map3d_pitch_near_deg"), r.bal("map3d_pitch_far_deg"))
	var ground := Vector3(ctx.target.x, ctx.height_at(ctx.target), ctx.target.y)
	_camera.transform = Map3DGeometry.pose(ground, ctx.distance, ctx.yaw, pitch)
	ctx.camera_moved.emit()


func pan_by(screen_delta: Vector2) -> void:
	ctx.target = Map3DGeometry.clamp_target(
		ctx.target + Map3DGeometry.pan_delta(screen_delta, ctx.metres_per_pixel(), ctx.yaw), ctx.bounds)
	apply()


## Zoom to `new_distance` (clamped) keeping the ground under `pos` under it.
func zoom_at(pos: Vector2, new_distance: float) -> void:
	var anchor: Variant = ctx.ground_at(pos)
	var d := Map3DGeometry.zoomed_by(new_distance, 1.0, ctx.repo.bal("map3d_zoom_min_m"),
		max_distance())
	if anchor != null:
		var a := anchor as Vector3
		ctx.target = Map3DGeometry.clamp_target(
			Map3DGeometry.zoom_about(ctx.target, Vector2(a.x, a.z), ctx.distance, d), ctx.bounds)
	ctx.distance = d
	apply()


## A right-drag turn of `dx_px` screen px; it cancels a north ease.
func turn_by(dx_px: float) -> void:
	_north_t = -1.0
	ctx.yaw -= dx_px * ctx.repo.bal("map3d_rotate_deg_per_px")
	apply()


func start_north() -> void:
	_north_from = ctx.yaw
	_north_t = 0.0


## The compass's ease back to north, a frame at a time.
func step(delta: float) -> void:
	if _north_t < 0.0:
		return
	_north_t += delta / maxf(ctx.repo.bal("map3d_compass_reset_s"), 0.01)
	ctx.yaw = Map3DGeometry.ease_yaw(_north_from, _north_t)
	if _north_t >= 1.0:
		_north_t = -1.0
		ctx.yaw = 0.0
	apply()
