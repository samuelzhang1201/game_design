class_name Map3DContext
extends RefCounted
## What every piece of the 3D map shares (spec 2026-09-20 §1): the data, the
## built world's metadata, the camera and its pose, the terrain, the live
## state and the scales — so a layer never reaches for the Game autoload or
## for the view. Map3DView makes one at load; an editor preview (Task 22)
## makes one from the pack alone.

## The rig moved the camera; the HUD redraws on it.
signal camera_moved

var repo: DataRepository
## The build's root metadata `map3d_world`: {m_per_px, pack_origin, pack_px, sea_y}.
var meta: Dictionary = {}
var bounds := Rect2()
var world: Node3D
## The world's Terrain3D, or null (test fixtures, previews without terrain).
var terrain: Node
var camera: Camera3D
var viewport: SubViewport
## The view's size, design px (Map3DView keeps it current).
var view_size := Vector2.ONE
## The rig's pose: Map3DCameraRig writes these, then emits camera_moved.
var target := Vector2.ZERO
var distance := 1.0
var yaw := 0.0
## The graphics tier's row (Map3DQuality.row); {} reads as full quality.
var quality: Dictionary = {}
## -> GameState. The view passes Game.state's getter; a preview a blank state.
## Unset (the default), the state is null.
var state_fn: Callable = Callable()
## -> int, the clock's speed. Unset: 0 (paused).
var clock_fn: Callable = Callable()
## -> float, window px per design px (the canvas_items stretch). Unset: 1.
var window_scale_fn: Callable = Callable()
## Test seam: when valid, replaces the terrain lookup in height_at.
var height_fn: Callable = Callable()
var _water_normals: NoiseTexture2D


func _init(p_repo: DataRepository, p_meta: Dictionary, p_world: Node3D = null) -> void:
	repo = p_repo
	meta = p_meta
	bounds = Map3DGeometry.world_bounds(meta) if meta.has("pack_px") else Rect2()
	world = p_world
	if world != null:
		terrain = world.get_node_or_null("Terrain3D")


func state() -> GameState:
	return state_fn.call() if state_fn.is_valid() else null


func clock_speed() -> int:
	return int(clock_fn.call()) if clock_fn.is_valid() else 0


func window_scale() -> float:
	return float(window_scale_fn.call()) if window_scale_fn.is_valid() else 1.0


## The graphics tier's share of the window's pixels the 3D view renders at.
func render_scale() -> float:
	return float(quality.get("render_scale", 1.0))


## SubViewport px per design px: every projection, ray and px uniform uses it.
func viewport_px_scale() -> float:
	return window_scale() * render_scale()


## Ground height at a world XZ: the terrain's where it has data, never below
## the sea plane (was Map3DView._height_at).
func height_at(xz: Vector2) -> float:
	if height_fn.is_valid():
		return float(height_fn.call(xz))
	var sea := float(meta.get("sea_y", 0.0))
	if terrain == null or terrain.get("data") == null:
		return sea
	var y: float = terrain.data.get_height(Vector3(xz.x, 0.0, xz.y))
	return sea if is_nan(y) else maxf(y, sea)


func to_world(pack_px: Vector2) -> Vector2:
	return Map3DGeometry.pack_to_world(meta, pack_px)


func to_pack(xz: Vector2) -> Vector2:
	return Map3DGeometry.world_to_pack(meta, xz)


func ground_of_pack(pack_px: Vector2) -> Vector3:
	var xz := to_world(pack_px)
	return Vector3(xz.x, height_at(xz), xz.y)


## A world point in design px, or null behind the camera.
func project(world_pos: Vector3) -> Variant:
	if camera == null or camera.is_position_behind(world_pos):
		return null
	return camera.unproject_position(world_pos) / viewport_px_scale()


## The ground under a point of the view (design px), or null for the sky.
func ground_at(pos: Vector2) -> Variant:
	if camera == null:
		return null
	var px := pos * viewport_px_scale()
	return Map3DGeometry.ground_hit(camera.project_ray_origin(px),
		camera.project_ray_normal(px), height_at)


## Ground metres under one design px at the target (the scale bar's measure).
func metres_per_pixel() -> float:
	return Map3DGeometry.metres_per_pixel(distance, repo.bal("map3d_fov_deg"),
		maxf(view_size.y, 1.0))


## Metres per SubViewport px per metre of camera distance (every screen-constant shader).
func px_per_dist() -> float:
	var h := float(maxi(viewport.size.y, 1)) if viewport != null else 1.0
	return 2.0 * tan(deg_to_rad(repo.bal("map3d_fov_deg")) * 0.5) / h


func line_step() -> float:
	return repo.bal("map3d_line_step_m")


func road_step() -> float:
	return repo.bal("map3d_road_step_m")


func river_step() -> float:
	return repo.bal("map3d_river_mesh_step_m")


## The ripple normal map both waters share (was Map3DView.water_normals).
func water_normals() -> Texture2D:
	if _water_normals == null:
		var noise := FastNoiseLite.new()
		noise.seed = int(repo.bal("map3d_water_seed"))
		noise.frequency = 0.03
		noise.fractal_octaves = 3
		_water_normals = NoiseTexture2D.new()
		_water_normals.width = 256
		_water_normals.height = 256
		_water_normals.seamless = true
		_water_normals.as_normal_map = true
		_water_normals.bump_strength = 6.0
		_water_normals.generate_mipmaps = true
		_water_normals.noise = noise
	return _water_normals
