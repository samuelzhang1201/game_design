class_name Map3DView
extends Control
## The 3D MAP tab (owner 2026-09-18): the pack as a Terrain3D landscape in
## the map panel, in place of the 2D WorldMapView while the tab is lit.
##
## The scene is BUILT, not shipped in git: tools/map3d/ bakes and builds
## assets/map3d/<map_id>/world.tscn (see its README). A checkout without it
## shows a notice saying so, and the rest of the game is untouched.
##
## Loading is LAZY — a 128 km world is heavy, so nothing loads until the tab
## is first lit — and the SubViewport renders only while the view shows.
## The camera is a rig (Map3DGeometry): a target on the ground, a distance,
## a yaw, and a tilt that follows the distance. Left or middle drag pans,
## right drag turns, the wheel zooms, WASD / arrows pan. Settlements are
## placed from live data (data/map3d_settlements.csv), never baked, so the
## scene needs no rebuild when the world changes. View-only for now: a click
## does not open a card.

const SCENE_PATTERN := "res://assets/map3d/%s/world.tscn"
const NOTICE_TEXT := "The 3D map has not been built for this map.\nRun tools/map3d (see tools/map3d/README.md)."

var _repo: DataRepository
var _scene_path := ""
var _container: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _markers: Node3D
var _notice: Label
var _meta: Dictionary = {}
var _bounds := Rect2()
var _target := Vector2.ZERO
var _distance := 1.0
var _yaw := 0.0
var _loaded := false
var _tried := false
var _hovered := false


static func scene_path_for(map_id: String) -> String:
	return SCENE_PATTERN % map_id


## A view of `repo`'s map; `scene_path` is a test seam.
static func create(repo: DataRepository, scene_path: String = "") -> Map3DView:
	var v := Map3DView.new()
	v.name = "Map3DView"
	v._repo = repo
	v._scene_path = scene_path if scene_path != "" else scene_path_for(repo.map_id)
	return v


## The one toggle every screen with a map uses: on puts a view (made on
## first use) into `panel` over the 2D `world_map` and hides the latter; off
## hands the panel back. Returns the view, or null if none was ever needed.
static func toggle_in(panel: Control, world_map: Control, view: Map3DView, on: bool) -> Map3DView:
	if on and view == null:
		view = Map3DView.create(Game.data)
		panel.add_child(view)
	if world_map != null:
		world_map.visible = not on
	if view != null:
		if on:
			view.activate()
		else:
			view.deactivate()
	return view


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_container = SubViewportContainer.new()
	_container.name = "Container"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	_notice = Label.new()
	_notice.name = "Notice"
	_notice.text = NOTICE_TEXT
	_notice.visible = false
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_notice)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	set_process(false)


## Show the view, loading the world the first time.
func activate() -> void:
	visible = true
	if not _tried:
		_tried = true
		_load()
	_notice.visible = not _loaded
	_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if _loaded
		else SubViewport.UPDATE_DISABLED)
	set_process(_loaded)


## Hide the view and stop rendering it; the loaded world is kept.
func deactivate() -> void:
	visible = false
	_hovered = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)


func _load() -> void:
	if not ResourceLoader.exists(_scene_path):
		return
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		return
	_world = packed.instantiate() as Node3D
	if _world == null or not _world.has_meta("map3d_world"):
		if _world != null:
			_world.free()
			_world = null
		return
	_meta = _world.get_meta("map3d_world")
	_bounds = Map3DGeometry.world_bounds(_meta)
	_viewport.add_child(_world)
	# The build's own framing cameras are for tools/map3d/shoot.gd.
	for child in _world.get_children():
		if child is Camera3D:
			(child as Camera3D).current = false
	_camera = Camera3D.new()
	_camera.name = "RigCamera"
	_camera.fov = _repo.bal("map3d_fov_deg")
	_camera.near = _repo.bal("map3d_near_m")
	_camera.far = _repo.bal("map3d_far_m")
	_viewport.add_child(_camera)
	_camera.make_current()
	_markers = Node3D.new()
	_markers.name = "Markers"
	_viewport.add_child(_markers)
	_place_markers()
	_target = Map3DGeometry.clamp_target(_home(), _bounds)
	_distance = _repo.bal("map3d_zoom_start_m")
	_yaw = 0.0
	_loaded = true
	_apply_camera()


## The player's capital, or the map's centre when no realm is bound.
func _home() -> Vector2:
	var realm: Dictionary = _repo.kingdoms.get(_repo.resolve_realm("player_realm"), {})
	var burg: Dictionary = _repo.burgs.get(String(realm.get("capital_burg", "")), {})
	if burg.is_empty():
		return _bounds.get_center()
	return Map3DGeometry.pack_to_world(_meta, Vector2(float(burg["x"]), float(burg["y"])))


## Ground height at a world XZ: the terrain's when it has data, never below
## the sea plane.
func _height_at(xz: Vector2) -> float:
	var sea := float(_meta.get("sea_y", 0.0))
	var terrain := _world.get_node_or_null("Terrain3D")
	if terrain == null or terrain.get("data") == null:
		return sea
	var y: float = terrain.data.get_height(Vector3(xz.x, 0.0, xz.y))
	return sea if is_nan(y) else maxf(y, sea)


## One MultiMesh of discs per settlement group, each on the ground under its
## burg. Codes are sorted so the placement is the same every run.
func _place_markers() -> void:
	var by_group: Dictionary = {}
	var codes: Array = _repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var burg: Dictionary = _repo.burgs[code]
		var group := String(burg.get("group", ""))
		if not _repo.map3d_settlements.has(group):
			continue
		var xz := Map3DGeometry.pack_to_world(_meta, Vector2(float(burg["x"]), float(burg["y"])))
		if not by_group.has(group):
			by_group[group] = []
		(by_group[group] as Array).append(Vector3(xz.x, _height_at(xz), xz.y))
	var groups: Array = by_group.keys()
	groups.sort()
	for group: String in groups:
		var spec: Dictionary = _repo.map3d_settlements[group]
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(spec["diameter_m"]) * 0.5
		mesh.bottom_radius = mesh.top_radius
		mesh.height = float(spec["height_m"])
		mesh.radial_segments = 32
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(String(spec["color"]))
		mat.roughness = 0.8
		mesh.material = mat
		var pts: Array = by_group[group]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = group.capitalize()
		mmi.multimesh = mm
		_markers.add_child(mmi)


func _apply_camera() -> void:
	if _camera == null:
		return
	var pitch := Map3DGeometry.pitch_for(_distance, _repo.bal("map3d_zoom_min_m"),
		_repo.bal("map3d_zoom_max_m"), _repo.bal("map3d_pitch_near_deg"),
		_repo.bal("map3d_pitch_far_deg"))
	var ground := Vector3(_target.x, _height_at(_target), _target.y)
	_camera.transform = Map3DGeometry.pose(ground, _distance, _yaw, pitch)


func _metres_per_pixel() -> float:
	return Map3DGeometry.metres_per_pixel(_distance, _repo.bal("map3d_fov_deg"),
		maxf(size.y, 1.0))


func _pan_by(screen_delta: Vector2) -> void:
	_target = Map3DGeometry.clamp_target(
		_target + Map3DGeometry.pan_delta(screen_delta, _metres_per_pixel(), _yaw), _bounds)
	_apply_camera()


func _gui_input(event: InputEvent) -> void:
	if not _loaded:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		var steps := 0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			steps = -1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			steps = 1
		if steps != 0:
			_distance = Map3DGeometry.zoomed(_distance, steps, _repo.bal("map3d_zoom_factor"),
				_repo.bal("map3d_zoom_min_m"), _repo.bal("map3d_zoom_max_m"))
			_apply_camera()
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
		_pan_by(mm.relative)
		accept_event()
	elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_yaw -= mm.relative.x * _repo.bal("map3d_rotate_deg_per_px")
		_apply_camera()
		accept_event()


## WASD / arrows pan while the pointer is over the view and no text box has
## the keyboard.
func _process(delta: float) -> void:
	if not _hovered:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
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
		return
	# Keys move the VIEW, so the ground moves the other way from a drag.
	var px := size.y * _repo.bal("map3d_key_pan_screens_per_s") * delta
	_pan_by(-dir.normalized() * px)


## Test seams.
func is_loaded() -> bool:
	return _loaded

func notice() -> Label:
	return _notice

func viewport() -> SubViewport:
	return _viewport

func camera() -> Camera3D:
	return _camera

func target() -> Vector2:
	return _target

func distance() -> float:
	return _distance

func yaw() -> float:
	return _yaw

## Settlement markers per group: {group: count}.
func marker_counts() -> Dictionary:
	var out: Dictionary = {}
	if _markers == null:
		return out
	for mmi: MultiMeshInstance3D in _markers.get_children():
		out[mmi.name.to_lower()] = mmi.multimesh.instance_count
	return out
