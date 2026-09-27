class_name Map3DContext
extends RefCounted
## What every piece of the 3D map shares (spec 2026-09-20 §1): the data, the
## built world's metadata, the camera and its pose, the terrain, the live
## state and the scales — so a layer never reaches for the Game autoload or
## for the view. Map3DView makes one at load; an editor preview (Task 22)
## makes one from the pack alone.

## The rig moved the camera; the HUD redraws on it.
@warning_ignore("unused_signal")  # emitted by Map3DCameraRig, which owns the pose
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
## DEV MODE (owner 2026-09-27, the pause menu's switch): every realm's
## regiments on the map, not only the player's.
var dev := false
## -> GameState. The view passes the autoload's state getter; a preview a blank
## state. (Spelling the autoload out here would trip the no-autoload scan in
## tests/map3d/test_map3d_preview.gd, which is the point of it.)
## Unset (the default), the state is null.
var state_fn: Callable = Callable()
## -> int, the clock's speed. Unset: 0 (paused).
var clock_fn: Callable = Callable()
## -> float, window px per design px (the canvas_items stretch). Unset: 1.
var window_scale_fn: Callable = Callable()
## Test seam: when valid, replaces the terrain lookup in height_at.
var height_fn: Callable = Callable()
var _water_normals: NoiseTexture2D
var _marked: Array = []
var _burg_ground: Dictionary = {}
var _pack_ground: Dictionary = {}
var _proj_key: Array = []
var _proj: Array = []
var _houses: Dictionary = {}
var _houses_loaded := false


func _init(p_repo: DataRepository, p_meta: Dictionary, p_world: Node3D = null) -> void:
	repo = p_repo
	meta = p_meta
	bounds = Map3DGeometry.world_bounds(meta) if meta.has("pack_px") else Rect2()
	world = p_world
	if world != null:
		terrain = world.get_node_or_null("Terrain3D")


## The built world at `scene_path` — Map3DWorldLoader.instance (Task 14).
static func instance_world(scene_path: String) -> Node3D:
	return Map3DWorldLoader.instance(scene_path)


func state() -> GameState:
	return state_fn.call() if state_fn.is_valid() else null


func clock_speed() -> int:
	return int(clock_fn.call()) if clock_fn.is_valid() else 0


func window_scale() -> float:
	return float(window_scale_fn.call()) if window_scale_fn.is_valid() else 1.0


## The tier's row: the view's, or high's (today's look) when none is set.
func q() -> Dictionary:
	return quality if not quality.is_empty() else Map3DQuality.row(repo, "high")


## The graphics tier's share of the window's pixels the 3D view renders at.
func render_scale() -> float:
	return Map3DQuality.num(q(), "render_scale")


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


## Where the view opens (world XZ): the middle of the player's home province
## (MapManors.home_province), else the capital, else the map's centre.
func home() -> Vector2:
	var p: Dictionary = repo.provinces.get(MapManors.home_province(repo, state()), {})
	if p.has("center_x"):
		return to_world(Vector2(float(p["center_x"]), float(p["center_y"])))
	var realm: Dictionary = repo.kingdoms.get(repo.resolve_realm("player_realm"), {})
	var burg: Dictionary = repo.burgs.get(String(realm.get("capital_burg", "")), {})
	return bounds.get_center() if burg.is_empty() else to_world(Vector2(float(burg["x"]), float(burg["y"])))


## The regiments the map draws: the player's, or every realm's in DEV MODE.
func regiments() -> Array:
	return repo.world_table("military", "regiments").values() if dev \
		else MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))


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


## The borders', roads' and rivers' resampling steps in metres: balance.csv's
## times the tier's multiplier (graphics_quality *_step_mul).
func line_step() -> float:
	return repo.bal("map3d_line_step_m") * Map3DQuality.num(q(), "line_step_mul")


func road_step() -> float:
	return repo.bal("map3d_road_step_m") * Map3DQuality.num(q(), "road_step_mul")


func river_step() -> float:
	return repo.bal("map3d_river_mesh_step_m") * Map3DQuality.num(q(), "river_step_mul")


## The ripple normal map both waters share (was Map3DView.water_normals): the
## generator is scenes/map3d/materials/water_ripples.tres, its seed data.
func water_normals() -> Texture2D:
	if _water_normals == null:
		_water_normals = (load("res://scenes/map3d/materials/water_ripples.tres") as NoiseTexture2D) \
			.duplicate(true) as NoiseTexture2D
		_water_normals.noise.seed = int(repo.bal("map3d_water_seed"))
	return _water_normals


## The burgs that get a marker (their group has a map3d_settlements row),
## sorted by code (was Map3DView._sorted_burgs).
func marked_burgs() -> Array:
	if _marked.is_empty():
		var out: Array = []
		for code: String in repo.burgs:
			if repo.map3d_settlements.has(String(repo.burgs[code].get("group", ""))):
				out.append(code)
		out.sort()
		# shared, cached: callers read it, never mutate it
		out.make_read_only()
		_marked = out
	return _marked


## Every marked burg's ground point, read ONCE at load (spec §1: the data
## never moves, so nothing asks the terrain per frame).
func settle_ground() -> void:
	_burg_ground.clear()
	for code: String in marked_burgs():
		var b: Dictionary = repo.burgs[code]
		_burg_ground[code] = ground_of_pack(Vector2(float(b["x"]), float(b["y"])))
	_proj_key = []


func burg_ground(code: String) -> Vector3:
	if not _burg_ground.has(code):
		var b: Dictionary = repo.burgs[code]
		_burg_ground[code] = ground_of_pack(Vector2(float(b["x"]), float(b["y"])))
	return _burg_ground[code]


## A fixed pack point's ground, looked up once (cells, landmarks — Ruling 4).
func pack_ground(pack_px: Vector2) -> Vector3:
	if not _pack_ground.has(pack_px):
		_pack_ground[pack_px] = ground_of_pack(pack_px)
	return _pack_ground[pack_px]


func cell_ground(id: int) -> Vector3:
	return pack_ground(MapTerrain.cell_center(repo, repo.cells[id]))


## Every marked settlement as the camera sees it now, cut once per pose:
## {code, spec, world, screen (design px), behind, shown}. `shown` is what
## settlement_ring.gdshader still draws: before the camera and short of its
## tier's max_view_m x map3d_ring_fade_start (where the ring begins to fade).
func projected_settlements() -> Array:
	if camera == null:
		return []
	var key := [camera.global_transform, view_size, viewport_px_scale()]
	if key == _proj_key:
		return _proj
	var out: Array = []
	var s := viewport_px_scale()
	var eye := camera.global_position
	var fade_start := repo.bal("map3d_ring_fade_start")
	for code: String in marked_burgs():
		var spec: Dictionary = repo.map3d_settlements[String(repo.burgs[code].get("group", ""))]
		var w := burg_ground(code)
		var behind := camera.is_position_behind(w)
		out.append({"code": code, "spec": spec, "world": w,
			"screen": camera.unproject_position(w) / s, "behind": behind,
			"shown": not behind and eye.distance_to(w) < float(spec["max_view_m"]) * fade_start})
	# shared, cached per pose: callers read it, never mutate it
	out.make_read_only()
	_proj = out
	_proj_key = key
	return out


## The screen squares (design px) of every DRAWN settlement dot — what the
## counters and landmarks keep clear of (was Map3DView._settlement_marks).
## Sizes on Map3DLayerSettlements.drawn_px, NEVER pick_reach_px's ground
## footprint (fix round 1, owner 2026-09-20: conflating the two — once one
## `marker_px` — crowded landmarks out of ground where the dot is hidden).
## A hidden dot — nearer than the dot's own threshold, or `shown` false — no rect.
func settlement_rects() -> Array:
	var out: Array = []
	var min_view_m := Map3DGeometry.settlement_dot_min_view_m(repo, meta, view_size.y)
	for e: Dictionary in projected_settlements():
		if not bool(e["shown"]):
			continue
		var dist_m := camera.global_position.distance_to(e["world"] as Vector3)
		if min_view_m > 0.0 and dist_m <= min_view_m:
			continue
		var r := Map3DLayerSettlements.drawn_px(e["spec"]) * 0.5 + 2.0
		out.append(Rect2((e["screen"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


## The build's baked houses, grouped by burg (spec 2026-09-20 §3). Loaded
## once; a build without them is {} and no houses are drawn.
func houses() -> Dictionary:
	if not _houses_loaded:
		_houses_loaded = true
		_houses = Map3DHouses.load_csv(repo.map3d_dir() + "/bake/houses.csv")
	return _houses


## A settlement's click reach in DESIGN px: its cluster's projected ground
## radius, never below map3d_pick_px, whether or not its dot is drawn. NOT
## settlement_rects()' measure (the dot's on-screen size — fix round 1, owner
## 2026-09-20). `spec` unused, kept for callers holding the row.
func pick_reach_px(code: String, _spec: Dictionary, dist_m: float) -> float:
	var world_r := Map3DHouses.footprint_radius_m(repo.burgs.get(code, {}), repo)
	var m_per_px := Map3DGeometry.metres_per_pixel(dist_m, repo.bal("map3d_fov_deg"),
		maxf(view_size.y, 1.0))
	return maxf(world_r / maxf(m_per_px, 0.0001), repo.bal("map3d_pick_px"))
