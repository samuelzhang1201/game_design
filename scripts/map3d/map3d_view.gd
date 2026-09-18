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
## is first lit — and the SubViewport renders only while the view shows, at
## the WINDOW's pixel resolution (a SubViewportContainer under the
## canvas_items stretch would render at design size and blur on any window
## larger than 1280x720). The camera is a rig (Map3DGeometry): a target on
## the ground, a distance, a yaw, and a tilt that follows the distance. Left
## or middle drag pans, right drag turns, the wheel zooms, WASD / arrows pan.
##
## A click is the 2D map's click (owner 2026-09-18): a settlement within
## map3d_pick_px opens its card, anywhere else names the province under it,
## through the same object_selected / province_selected signals, so the
## screen's MapDetailPanel follows either map unchanged. The clicked
## province is outlined in gold. Kingdom borders and province seams come
## from the live outlines (Map3DBorders) and are rebuilt when ownership
## changes. Settlements are placed from live data (map3d_settlements.csv).

## The described entry of the settlement under a click ({title, obj}), or
## {} when the selection is cleared — WorldMapView's signal.
signal object_selected(entry: Dictionary)
## The province under a click, or "" for sea — WorldMapView's signal.
signal province_selected(province_code: String)

const SCENE_PATTERN := "res://assets/map3d/%s/world.tscn"
const NOTICE_TEXT := "The 3D map has not been built for this map.\nRun tools/map3d (see tools/map3d/README.md)."
const BORDER_SHADER := preload("res://scripts/map3d/border_line.gdshader")
## A press and release further apart than this is a drag, not a click
## (WorldMapView.CLICK_SLOP).
const CLICK_SLOP := 10.0

var _repo: DataRepository
var _scene_path := ""
var _display: TextureRect
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _markers: Node3D
var _lines: Node3D
var _notice: Label
var _meta: Dictionary = {}
var _bounds := Rect2()
var _target := Vector2.ZERO
var _distance := 1.0
var _yaw := 0.0
var _loaded := false
var _tried := false
var _hovered := false
var _press_pos := Vector2.ZERO
var _dragging := false
var _province_image: Image
var _selected_province := ""
var _selected_burg := ""
var _border_sig := 0
var _border_clock := 0.0


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
## hands the panel back. A new view is wired to the screen's `detail` card
## the way the 2D map is. Returns the view, or null if none was ever needed.
static func toggle_in(panel: Control, world_map: Control, view: Map3DView, on: bool,
		detail: MapDetailPanel = null) -> Map3DView:
	if on and view == null:
		view = Map3DView.create(Game.data)
		panel.add_child(view)
		if detail != null:
			detail.follow(view)
			detail.closed.connect(view.clear_selection)
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
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_display = TextureRect.new()
	_display.name = "Display"
	_display.texture = _viewport.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_display)
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
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)


## Window pixels per design px: the canvas_items stretch's scale, 1 headless.
func _render_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)


## The SubViewport at the view's size in WINDOW pixels; the TextureRect
## shows it back at design size, one texel per real pixel.
func _fit_viewport() -> void:
	if _viewport == null:
		return
	var s := _render_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	_update_line_scale()


## Show the view, loading the world the first time.
func activate() -> void:
	visible = true
	if not _tried:
		_tried = true
		_load()
	_notice.visible = not _loaded
	_fit_viewport()
	_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if _loaded
		else SubViewport.UPDATE_DISABLED)
	if _loaded:
		refresh_borders()
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
	_lines = Node3D.new()
	_lines.name = "Lines"
	_viewport.add_child(_lines)
	_target = Map3DGeometry.clamp_target(_home(), _bounds)
	_distance = _repo.bal("map3d_zoom_start_m")
	_yaw = 0.0
	_loaded = true
	_apply_camera()
	_update_line_scale()


func _state() -> GameState:
	return Game.state


## The player's capital, or the map's centre when no realm is bound.
func _home() -> Vector2:
	var realm: Dictionary = _repo.kingdoms.get(_repo.resolve_realm("player_realm"), {})
	var burg: Dictionary = _repo.burgs.get(String(realm.get("capital_burg", "")), {})
	if burg.is_empty():
		return _bounds.get_center()
	return _burg_xz(burg)


func _burg_xz(burg: Dictionary) -> Vector2:
	return Map3DGeometry.pack_to_world(_meta, Vector2(float(burg["x"]), float(burg["y"])))


## Ground height at a world XZ: the terrain's when it has data, never below
## the sea plane.
func _height_at(xz: Vector2) -> float:
	var sea := float(_meta.get("sea_y", 0.0))
	var terrain := _world.get_node_or_null("Terrain3D") if _world != null else null
	if terrain == null or terrain.get("data") == null:
		return sea
	var y: float = terrain.data.get_height(Vector3(xz.x, 0.0, xz.y))
	return sea if is_nan(y) else maxf(y, sea)


## One MultiMesh of discs per settlement group, each on the ground under its
## burg. Codes are sorted so the placement is the same every run.
func _place_markers() -> void:
	var by_group: Dictionary = {}
	for code: String in _sorted_burgs():
		var burg: Dictionary = _repo.burgs[code]
		var group := String(burg.get("group", ""))
		var xz := _burg_xz(burg)
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


## The burgs that get a marker (their group has a map3d_settlements row),
## sorted by code.
func _sorted_burgs() -> Array:
	var out: Array = []
	for code: String in _repo.burgs:
		if _repo.map3d_settlements.has(String(_repo.burgs[code].get("group", ""))):
			out.append(code)
	out.sort()
	return out


# --- borders -----------------------------------------------------------------

## Rebuild the kingdom borders and province seams if ownership moved since
## they were built — the same signature WorldMapView keys its rings on.
func refresh_borders() -> void:
	if not _loaded:
		return
	var st := _state()
	var sig := 0 if st == null else hash([st.province_owner.hash(), st.manor_province.hash()])
	if sig == _border_sig and _lines.get_node_or_null("Kingdoms") != null:
		return
	_border_sig = sig
	var step := _repo.bal("map3d_line_step_m")
	var rings: Array = []
	for code: String in _repo.kingdoms:
		rings.append_array(Map3DBorders.kingdom_lines(_repo, st, _meta, code, step))
	_set_lines("Kingdoms", rings, MapPalette.named(_repo, "state_border"),
		MapPalette.named(_repo, "state_border_light"), "map3d_border_width_px",
		"map3d_border_dash_px", "map3d_border_gap_px", 1)
	var seam := MapPalette.named(_repo, "map3d_seam")
	seam.a = _repo.bal("map3d_seam_alpha")
	_set_lines("Seams", Map3DBorders.seam_lines(_repo, st, _meta, step), seam,
		Color(seam, 0.0), "map3d_seam_width_px", "map3d_seam_dash_px", "map3d_seam_gap_px", 0)
	_draw_selection()


## One MeshInstance3D of ribbons under Lines/<name>, replacing any before.
## `priority` orders the see-through lines (borders over seams).
func _set_lines(line_name: String, lines: Array, a: Color, b: Color, width_key: String,
		dash_key: String, gap_key: String, priority: int) -> void:
	var old := _lines.get_node_or_null(line_name)
	if old != null:
		_lines.remove_child(old)
		old.queue_free()
	var arrays := Map3DBorders.ribbon_arrays(lines, _height_at)
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = BORDER_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("colour_a", a)
	mat.set_shader_parameter("colour_b", b)
	mat.set_meta("width_key", width_key)
	mat.set_meta("dash_key", dash_key)
	mat.set_meta("gap_key", gap_key)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = line_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lines are thin and long: never culled by a bounding box the relief lift
	# pushes them out of.
	mi.extra_cull_margin = 16384.0
	_lines.add_child(mi)
	_update_line_scale()


## The lines' screen-px values in WINDOW px, and the metres per px per metre
## of distance, for every line material — on load, resize and new lines.
func _update_line_scale() -> void:
	if _lines == null or _repo == null:
		return
	var s := _render_scale()
	var h := float(maxi(_viewport.size.y, 1))
	var per_dist := 2.0 * tan(deg_to_rad(_repo.bal("map3d_fov_deg")) * 0.5) / h
	for mi: MeshInstance3D in _lines.get_children():
		var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("px_per_dist", per_dist)
		mat.set_shader_parameter("lift_px", _repo.bal("map3d_line_lift_px") * s)
		mat.set_shader_parameter("width_px", _repo.bal(String(mat.get_meta("width_key"))) * s)
		var dash_key := String(mat.get_meta("dash_key", ""))
		mat.set_shader_parameter("dash_px", _repo.bal(dash_key) * s if dash_key != "" else 0.0)
		var gap_key := String(mat.get_meta("gap_key", ""))
		mat.set_shader_parameter("gap_px", _repo.bal(gap_key) * s if gap_key != "" else 0.0)


## The clicked province's outline, solid gold over the borders.
func _draw_selection() -> void:
	var lines: Array = []
	if _selected_province != "":
		var steps := int(_repo.bal("map_border_smoothing_steps"))
		for loop: PackedVector2Array in MapOwnership.province_loops(_repo, _state(), _selected_province):
			if loop.size() < 3:
				continue
			var pts := PackedVector2Array()
			for p in MapGeometry.smooth_closed_through(loop, steps):
				pts.append(Map3DGeometry.pack_to_world(_meta, p))
			pts.append(pts[0])
			lines.append(Map3DGeometry.resample(pts, _repo.bal("map3d_line_step_m")))
	var gold := MapPalette.named(_repo, "map3d_selection")
	_set_lines("Selection", lines, gold, gold, "map3d_selection_width_px", "", "", 2)


# --- camera and input ----------------------------------------------------------

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
	if mb != null:
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var steps := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			_distance = Map3DGeometry.zoomed(_distance, steps, _repo.bal("map3d_zoom_factor"),
				_repo.bal("map3d_zoom_min_m"), _repo.bal("map3d_zoom_max_m"))
			_apply_camera()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				_dragging = false
			elif not _dragging:
				select_at(mb.position)
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _dragging and _press_pos.distance_to(mm.position) > CLICK_SLOP:
			_dragging = true
		if _dragging:
			_pan_by(mm.relative)
		accept_event()
	elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_pan_by(mm.relative)
		accept_event()
	elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_yaw -= mm.relative.x * _repo.bal("map3d_rotate_deg_per_px")
		_apply_camera()
		accept_event()


## WASD / arrows pan while the pointer is over the view and no text box has
## the keyboard; ownership is checked for new borders every few seconds.
func _process(delta: float) -> void:
	_border_clock += delta
	if _border_clock >= _repo.bal("map3d_border_refresh_s"):
		_border_clock = 0.0
		refresh_borders()
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


# --- picking --------------------------------------------------------------------

## The ground under a point of the view (design px), or null for the sky.
func ground_at(pos: Vector2) -> Variant:
	if _camera == null:
		return null
	var px := pos * _render_scale()
	return Map3DGeometry.ground_hit(_camera.project_ray_origin(px),
		_camera.project_ray_normal(px), _height_at)


## What a click at `pos` picks: {"kind": "burg", "code"} for a settlement
## within map3d_pick_px of it (or on its disc), {"kind": "province", "code"}
## for the province under it, {} for the sea or the sky.
func pick_at(pos: Vector2) -> Dictionary:
	var hit: Variant = ground_at(pos)
	if hit == null:
		return {}
	var p := hit as Vector3
	var xz := Vector2(p.x, p.z)
	var m_per_px := p.distance_to(_camera.global_position) \
		* 2.0 * tan(deg_to_rad(_camera.fov) * 0.5) / maxf(size.y, 1.0)
	var best := ""
	var best_d := INF
	for code: String in _sorted_burgs():
		var burg: Dictionary = _repo.burgs[code]
		var spec: Dictionary = _repo.map3d_settlements[String(burg.get("group", ""))]
		var reach := maxf(float(spec["diameter_m"]) * 0.5, _repo.bal("map3d_pick_px") * m_per_px)
		var d := _burg_xz(burg).distance_to(xz)
		if d <= reach and d < best_d:
			best_d = d
			best = code
	if best != "":
		return {"kind": "burg", "code": best}
	var province := _province_at(Map3DGeometry.world_to_pack(_meta, xz))
	return {"kind": "province", "code": province} if province != "" else {}


func _province_at(pack_px: Vector2) -> String:
	if _province_image == null:
		var path := _repo.province_texture_path
		if path == "" or not ResourceLoader.exists(path):
			return ""
		_province_image = (load(path) as Texture2D).get_image()
	var p := Vector2i(pack_px.floor())
	if p.x < 0 or p.y < 0 or p.x >= _province_image.get_width() or p.y >= _province_image.get_height():
		return ""
	return String(_repo.province_by_id(MapIndex.id_at(_province_image, p)).get("province_code", ""))


## The click: a settlement opens its card, land names its province, the sea
## clears — exactly the signals WorldMapView sends.
func select_at(pos: Vector2) -> void:
	var picked := pick_at(pos)
	match String(picked.get("kind", "")):
		"burg":
			var code := String(picked["code"])
			_set_selected_province("")
			_selected_burg = code
			object_selected.emit({"title": String(_repo.burgs[code].get("label", code)),
				"obj": {"kind": "burg", "code": code}})
		"province":
			_selected_burg = ""
			_set_selected_province(String(picked["code"]))
			province_selected.emit(_selected_province)
		_:
			clear_selection()


func _set_selected_province(code: String) -> void:
	if code == _selected_province:
		return
	_selected_province = code
	if _loaded:
		_draw_selection()


## Forget the selection (the card was closed, or the sea clicked).
func clear_selection() -> void:
	var had := _selected_burg != "" or _selected_province != ""
	_selected_burg = ""
	_set_selected_province("")
	if had:
		object_selected.emit({})


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

func selected_province() -> String:
	return _selected_province

func selected_burg() -> String:
	return _selected_burg

## Centre the rig on a pack point (tests and future "go to" orders).
func look_at_pack(pack_px: Vector2, at_distance: float = -1.0) -> void:
	_target = Map3DGeometry.clamp_target(Map3DGeometry.pack_to_world(_meta, pack_px), _bounds)
	if at_distance > 0.0:
		_distance = at_distance
	_apply_camera()

## A line mesh by name (Kingdoms, Seams, Selection), or null.
func line_mesh(line_name: String) -> ArrayMesh:
	var mi := _lines.get_node_or_null(line_name) as MeshInstance3D if _lines != null else null
	return mi.mesh as ArrayMesh if mi != null else null

## Settlement markers per group: {group: count}.
func marker_counts() -> Dictionary:
	var out: Dictionary = {}
	if _markers == null:
		return out
	for mmi: MultiMeshInstance3D in _markers.get_children():
		out[mmi.name.to_lower()] = mmi.multimesh.instance_count
	return out
