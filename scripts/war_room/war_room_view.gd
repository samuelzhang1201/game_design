class_name WarRoomView
extends Control
## The WAR ROOM (owner 2026-10-01, spec 2026-10-01-war-room-design): a stone
## room, an oak table, ONE numbered sheet laid on it as inked vellum over the
## relief, the crown's regiments as tin pieces. It draws and signals; it reads
## no autoload and changes no state — the screen (scripts/ui/war_room_screen.gd)
## hands it the repository, a state getter and a paused-clock getter, and runs
## its orders. It speaks ArmyOrderMenu's map contract (army_menu_requested,
## ground_clicked, route_clicked, aiming / aim_dest / aim_code), so the 3D
## map's own order menu serves the table unchanged. Renders into a SubViewport
## at WINDOW resolution shown by a TextureRect, and only while active.

signal piece_selected(code: String)
signal selection_cleared
signal army_menu_requested(code: String, at: Vector2)
signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
signal route_clicked(code: String, at: Vector2)
signal rake_started(code: String)
signal sheet_requested(index: int)

var aiming := false
var aim_dest := Vector2(-1, -1)
var aim_code := ""

@onready var _viewport: SubViewport = %Viewport
@onready var _display: TextureRect = %Display
@onready var _camera: Camera3D = %Camera
@onready var _table: MeshInstance3D = %Table
@onready var _ink_viewport: SubViewport = %InkViewport
@onready var _ink: WarInkPainter = %Ink

var _repo: DataRepository
var _state_fn: Callable
var _paused_fn: Callable
var _rig := WarCamera.new()
var _sheet := -1
var _rect := Rect2()
var _table_w := 1.4
var _depth := 1.0
var _heights := PackedFloat32Array()
var _nx := 2
var _nz := 2
var _y_scale := 0.0
var _relief: Image
var _ink_cache: Dictionary = {}   # WarSheetInk.cache_key -> ImageTexture
var _selected := ""
var _font: Font


func _ready() -> void:
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)


func bind(repo: DataRepository, state_fn: Callable, paused_fn: Callable) -> void:
	_repo = repo
	_state_fn = state_fn
	_paused_fn = paused_fn
	_table_w = repo.bal("war_table_w_m")
	_rig.distance = repo.bal("war_cam_distance_m")
	_rig.pitch_deg = repo.bal("war_cam_pitch_deg")
	_rig.min_distance = repo.bal("war_cam_min_m")
	_rig.max_distance = repo.bal("war_cam_max_m")
	_rig.yaw_max = repo.bal("war_cam_yaw_max_deg")
	var env: WorldEnvironment = %Env
	env.environment.background_color = repo.war_palette["background"]
	var tex := load(repo.relief_path) as Texture2D if not repo.relief_path.is_empty() else null
	_relief = tex.get_image() if tex != null else null
	if _relief != null and _relief.is_compressed():
		_relief.decompress()


func camera_rig() -> WarCamera:
	return _rig


func sheet_index() -> int:
	return _sheet


func state() -> GameState:
	return _state_fn.call() as GameState


func paused() -> bool:
	return bool(_paused_fn.call())


## The lettering face is handed in by the screen (UiPalette's body_italic
## role), so the face stays data; the default font until it is.
func set_font(f: Font) -> void:
	_font = f


func _font_or_default() -> Font:
	return _font if _font != null else ThemeDB.fallback_font


func _window_scale() -> float:
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)


func _fit_viewport() -> void:
	var s := _window_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))


func set_active(on: bool) -> void:
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	if on:
		_fit_viewport()


## Lay sheet `index`: the relief, its ink, the camera framed on it.
func lay_sheet(index: int) -> void:
	var all := WarSheets.series(_repo)
	if index < 0 or index >= all.size():
		return
	_sheet = index
	_rect = all[index]["rect"]
	_depth = WarTable.depth_m(_rect, _table_w)
	_nx = int(_repo.bal("war_relief_grid"))
	@warning_ignore("narrowing_conversion")
	_nz = maxi(2, roundi(float(_nx) * _rect.size.y / _rect.size.x))
	_heights = WarTable.heights(_repo, _relief, _rect, _nx, _nz) if _relief != null else _flat()
	_y_scale = WarTable.table_y(_repo, _rect, _table_w, 1.0)
	_table.mesh = WarTable.build_mesh(_heights, _nx, _nz, _table_w, _depth, _y_scale)
	var mat := _table.get_active_material(0) as ShaderMaterial
	var pal: Dictionary = _repo.war_palette
	for key in ["paper", "paper_age", "ink", "sea_ink"]:
		mat.set_shader_parameter(key, pal[key])
	mat.set_shader_parameter("contour_m", _repo.bal("war_contour_m"))
	mat.set_shader_parameter("index_every", _repo.bal("war_contour_index_every"))
	var grid := _repo.bal("war_grid_km") * WarSheets.px_per_unit(_repo)
	mat.set_shader_parameter("grid_cells", _rect.size / grid)
	mat.set_shader_parameter("tex_aspect", _rect.size.y / _rect.size.x)
	_rig.bounds = Rect2(-_table_w * 0.5, -_depth * 0.5, _table_w, _depth)
	_rig.target = Vector3.ZERO
	_rig.yaw_deg = 0.0
	_rig.distance = _repo.bal("war_cam_distance_m")
	_apply_camera()
	await _paint_ink(mat)


func _flat() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_nx * _nz)
	return out


## The sheet's ink, drawn once per ownership signature and kept as a texture.
## A headless run reads back nothing: no texture is set and nothing errors.
func _paint_ink(mat: ShaderMaterial) -> void:
	var sheet := _sheet
	var key := WarSheetInk.cache_key(state(), sheet)
	if not _ink_cache.has(key):
		var tex_px := int(_repo.bal("war_sheet_texture_px"))
		_ink_viewport.size = Vector2i(tex_px, tex_px)
		var widths := {}
		for k in ["road", "trail", "river", "coast", "border", "band", "seam", "town", "label", "dash", "gap"]:
			widths[k] = _repo.bal("war_ink_%s_px" % k)
		_ink.paint(WarSheetInk.strokes(_repo, state(), WarSheets.series(_repo)[sheet], tex_px),
			_repo.war_palette, widths, _font_or_default())
		_ink_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(self) or not is_inside_tree() or sheet != _sheet:
			return  # freed, or another sheet was laid, while the ink was drawn
		var img := _ink_viewport.get_texture().get_image()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			_ink_cache[key] = ImageTexture.create_from_image(img)
	if _ink_cache.has(key):
		mat.set_shader_parameter("ink_tex", _ink_cache[key])


func _apply_camera() -> void:
	_camera.transform = _rig.transform()


func y_at(xz: Vector2) -> float:
	return WarTable.height_at(_heights, _nx, _nz, _table_w, _depth, xz) * _y_scale


func table_point(pack_px: Vector2) -> Vector3:
	var xz := WarTable.to_table(_rect, _table_w, pack_px)
	return Vector3(xz.x, y_at(xz), xz.y)


## Where a pack point stands on the screen (this Control's px), null when
## behind the camera.
func screen_pos_of_px(pack_px: Vector2) -> Variant:
	var p := table_point(pack_px)
	if _camera.is_position_behind(p):
		return null
	return _camera.unproject_position(p) / _window_scale()


## The pack point under a screen px, Vector2(-1, -1) off the table.
func pack_at(screen_px: Vector2) -> Vector2:
	var s := screen_px * _window_scale()
	var hit := WarTable.ray_hit(_camera.project_ray_origin(s), _camera.project_ray_normal(s), y_at)
	if hit == Vector3.INF or not _rig.bounds.has_point(Vector2(hit.x, hit.z)):
		return Vector2(-1, -1)
	return WarTable.from_table(_rect, _table_w, Vector2(hit.x, hit.z))


func refresh() -> void:
	pass  # Task 10 rebuilds the pieces here; Task 11 the pennants


func selected_army() -> String:
	return _selected


func clear_selection() -> void:
	_selected = ""
	selection_cleared.emit()


func _gui_input(event: InputEvent) -> void:
	if _sheet < 0:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var at := pack_at(mb.position)
			var ground := table_point(at) if at.x >= 0.0 else _rig.target
			var step := _repo.bal("war_cam_zoom_step")
			_rig.zoom_about(ground, 1.0 / step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step)
			_apply_camera()
			accept_event()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		var at := pack_at(g.position)
		_rig.zoom_about(table_point(at) if at.x >= 0.0 else _rig.target, 1.0 / maxf(g.factor, 0.01))
		_apply_camera()
		accept_event()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_rig.pan(pg.delta * _rig.distance * 0.01)
		_apply_camera()
		accept_event()
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		var mm := event as InputEventMouseMotion
		_rig.pan(-mm.relative * _rig.distance * 0.0015)
		_apply_camera()
		accept_event()
