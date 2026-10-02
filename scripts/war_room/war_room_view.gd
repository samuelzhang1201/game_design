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
signal rake_dropped
signal sheet_requested(index: int)
signal sheet_laid(index: int)
signal camera_moved
## The easel's Missive board (spec 2026-10-02-war-room-v2 §1.3): the camera
## has flown to it / back to the table; a click or a hover on its panel, as a
## UV of the board's SubViewport (the screen pushes it in as real input).
signal board_entered
signal board_left
signal board_clicked(uv: Vector2, event: InputEventMouseButton)
signal board_hovered(uv: Vector2)

var aiming := false:
	set(v):
		aiming = v
		if not v:
			_rake.to = Vector2(-1, -1)
		if _repo != null and is_inside_tree():
			_rake.redraw()
var aim_dest := Vector2(-1, -1)
var aim_code := ""

@onready var _viewport: SubViewport = %Viewport
@onready var _display: TextureRect = %Display
@onready var _camera: Camera3D = %Camera
@onready var _table: MeshInstance3D = %Table
@onready var _ink_viewport: SubViewport = %InkViewport
@onready var _ink: WarInkPainter = %Ink
@onready var _chart: MeshInstance3D = %IndexChart
@onready var _arrows: Node3D = %EdgeArrows
@onready var _pieces: WarPieces = %Pieces
@onready var _pennants: WarPennants = %Pennants
@onready var _board: MeshInstance3D = %BoardPanel

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
var _inks := WarRoomInk.new()
var _render_scale := 1.0
var _selected := ""
var _font: Font
var _chart_built := false
var _swap := WarSheetSwap.new()
var _rake := WarRoomRake.new()
var _gestures := WarRoomGestures.new()
var _hold_size := false
var _board_mode := "table"      # table, to_board, board, to_table
var _fly_t := 0.0
var _fly_from := Transform3D()
var _table_pose := Transform3D()
var _board_dist := 1.0
var _board_offset := Vector2.ZERO
var _board_dragged := false
var _board_press := Vector2.ZERO


func _ready() -> void:
	# two views never share a material or an environment
	_table.material_override = _table.material_override.duplicate()
	var env: WorldEnvironment = %Env
	env.environment = env.environment.duplicate()
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)


func bind(repo: DataRepository, state_fn: Callable, paused_fn: Callable) -> void:
	_repo = repo
	_state_fn = state_fn
	_paused_fn = paused_fn
	_pieces.setup(repo, self)
	_pennants.setup(repo, self)
	_rake.setup(self, repo, {"hud": %Hud, "pieces": _pieces, "pennants": _pennants, "camera": _camera,
		"arrows": _arrows, "chart": _chart})
	_table_w = repo.bal("war_table_w_m")
	_rig.distance = repo.bal("war_cam_distance_m")
	_rig.pitch_near_deg = repo.bal("war_cam_pitch_near_deg")
	_rig.pitch_mid_deg = repo.bal("war_cam_pitch_mid_deg")
	_rig.pitch_far_deg = repo.bal("war_cam_pitch_far_deg")
	_rig.mid_distance = repo.bal("war_cam_distance_m")
	_rig.min_distance = repo.bal("war_cam_min_m")
	_rig.max_distance = repo.bal("war_cam_max_m")
	var clear := repo.bal("war_cam_wall_clear_m")
	var half := repo.bal("war_room_floor_x_m") - clear
	var z0 := repo.bal("war_room_floor_z_min_m") + clear
	_rig.room = Rect2(-half, z0, half * 2.0, repo.bal("war_room_floor_z_max_m") - clear - z0)
	WarRoomLights.bind(repo, candles())
	set_tier(Map3DQuality.resolve_here(GameRoot.settings_path))
	var env: WorldEnvironment = %Env
	env.environment.background_color = repo.war_palette["background"]
	var tex := load(repo.relief_path) as Texture2D if not repo.relief_path.is_empty() else null
	_relief = tex.get_image() if tex != null else null
	if _relief != null and _relief.is_compressed():
		_relief.decompress()


## The graphics tier (spec §1): the view renders at window px x its render
## scale, with its MSAA and anisotropy (graphics_quality.csv, as the 3D map).
func set_tier(tier: String) -> void:
	var row := Map3DQuality.row(_repo, tier)
	_render_scale = Map3DQuality.num(row, "render_scale")
	if is_node_ready():
		Map3DEnvironment.apply_viewport_quality(_viewport, row)
		WarRoomLights.apply_tier(_repo, candles(), row)
		_fit_viewport()


## The candlesticks' lights (WarRoomLights: one key candle, the rest accents).
func candles() -> Array[OmniLight3D]:
	return WarRoomLights.candles(%Room)


## The key's compass: ease the room back to the sheet's foot (yaw 0).
func start_north() -> void:
	_rig.start_north()


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


func lettering() -> Font:
	return _font if _font != null else ThemeDB.fallback_font


func sheet_rect() -> Rect2:
	return _rect


func window_scale() -> float:
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0) * _render_scale


## While the room's rect animates, keep the SubViewport's size (the Display
## stretches); on release it is fitted once (spec §1.2: no reallocation a frame).
func hold_size(on: bool) -> void:
	_hold_size = on
	if not on:
		_fit_viewport()


func _fit_viewport() -> void:
	if _hold_size or not visible:  # shut, it holds no render targets (set_active)
		return
	var s := window_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))


func set_active(on: bool) -> void:
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	if not on:
		_finish_swap()
		_viewport.size = Vector2i(2, 2)  # its render targets freed while shut (perf 2026-10-02)
		_inks.trim(1)  # and only the laid sheet's ink kept
	if on:
		_fit_viewport()


## Lay sheet `index`: the relief, its ink, the camera framed on it.
func lay_sheet(index: int) -> void:
	var all := WarSheets.series(_repo)
	if index < 0 or index >= all.size():
		return
	_sheet = index
	_rect = all[index]["rect"]
	_depth = WarRoomTable.depth_m(_rect, _table_w)
	_nx = int(_repo.bal("war_relief_grid"))
	_nz = WarRoomTable.rows_for(_rect, _nx)
	_heights = WarRoomTable.heights(_repo, _relief, _rect, _nx, _nz) if _relief != null else WarRoomTable.flat(_nx, _nz)
	_y_scale = WarRoomTable.table_y(_repo, _rect, _table_w, 1.0)
	var raw := WarRoomTable.raw_heights(_repo, _relief, _rect, _nx, _nz) if _relief != null else _heights
	var shore := WarRoomTable.shore_share(_repo, raw, _nx, _nz, _table_w, _depth)
	_table.mesh = WarRoomTable.build_mesh(_heights, _nx, _nz, _table_w, _depth, _y_scale, raw, shore)
	var mat := _table.get_active_material(0) as ShaderMaterial
	WarRoomMaterial.bind(mat, _repo, _rect, _table_w, _depth)
	_rig.bounds = Rect2(-_table_w * 0.5, -_depth * 0.5, _table_w, _depth)
	_rig.target = Vector3.ZERO
	_rig.yaw_deg = 0.0
	_rig.distance = _repo.bal("war_cam_distance_m")
	_apply_camera()
	if not _chart_built:
		_chart_built = true
		WarRoomWall.build_chart(_chart, _repo, lettering())
	WarRoomWall.lay_arrows(_arrows, _repo, index, _table_w, _depth, lettering())
	_pieces.rebuild(state())
	_pennants.rebuild(state(), true)
	_rake.redraw()
	sheet_laid.emit(index)
	await _paint_ink(mat)


## Roll the laid sheet up and lay `index` at the midpoint (spec §2). With no
## sheet laid yet, or the room not drawing, it is laid at once; a roll in
## progress is not interrupted.
func swap_to(index: int) -> void:
	if index == _sheet or index < 0 or _swap.active():
		return
	if _sheet < 0 or not is_processing():
		lay_sheet(index)
		return
	_rake.drop()   # a rake does not follow the table up
	_swap.start(index, _repo)


func _process(delta: float) -> void:
	var flying := _step_board(delta)
	if not flying and (_rig.step(delta, _repo.bal("war_cam_north_s")) or key_pan(delta)):
		_apply_camera()
	if not _swap.active():
		return
	if _swap.step(delta):
		lay_sheet(_swap.to)
	_table.scale = Vector3(1.0, 1.0, _swap.z_scale())
	_pieces.visible = not _swap.active()   # the pieces and pennants are put away while a sheet rolls
	_pennants.visible = _pieces.visible


func board_mode() -> String:
	return _board_mode


## The easel's panel shows `tex` (the board-only MissiveScreen's viewport).
func set_board_texture(tex: Texture2D) -> void:
	var mat := (_board.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_texture = tex
	_board.material_override = mat


func _board_size() -> Vector2:
	return (_board.mesh as QuadMesh).size


## True when the panel's centre is in view, or the camera is the board's (the
## screen renders the board's viewport only then).
func board_visible() -> bool:
	if _board_mode != "table":
		return true
	if _camera.is_position_behind(_board.global_position):
		return false
	return Rect2(Vector2.ZERO, size).has_point(_camera.unproject_position(_board.global_position) / window_scale())


func _board_pose() -> Transform3D:
	return WarBoard.pose(_board.global_transform, _board_dist, _board_offset)


## Fly the camera to the easel's board (spec §1.3); the table's pose is kept
## for the flight back.
func enter_board() -> void:
	if _board_mode != "table":
		return
	_rake.drop()
	_table_pose = _camera.transform
	_fly_from = _table_pose
	_board_dist = _repo.bal("war_board_distance_m")
	_board_offset = Vector2.ZERO
	_fly_t = 0.0
	_board_mode = "to_board"
	board_entered.emit()


func leave_board() -> void:
	if _board_mode != "board" and _board_mode != "to_board":
		return
	_fly_from = _camera.transform
	_fly_t = 0.0
	_board_mode = "to_table"


## One frame of a flight; true while the camera belongs to the board.
func _step_board(delta: float) -> bool:
	if _board_mode == "to_board" or _board_mode == "to_table":
		_fly_t += delta / maxf(_repo.bal("war_board_fly_s"), 0.01)
		var to := _board_pose() if _board_mode == "to_board" else _table_pose
		_camera.transform = WarBoard.fly(_fly_from, to, _fly_t)
		if _fly_t >= 1.0:
			if _board_mode == "to_table":
				_board_mode = "table"
				_apply_camera()
				board_left.emit()
				return false
			_board_mode = "board"
		return true
	return _board_mode == "board"


func _board_uv(screen_px: Vector2) -> Vector2:
	var s := screen_px * window_scale()
	return WarBoard.uv_of(_board.global_transform, _board_size(), _camera.project_ray_origin(s), _camera.project_ray_normal(s))


## Input while the board holds the camera: a left click (not a drag) on the
## panel is the board's, the wheel leans, a left drag pans in its plane.
func _board_input(event: InputEvent) -> void:
	accept_event()
	if _board_mode != "board":
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := _repo.bal("war_cam_zoom_step")
		_board_dist = clampf(_board_dist * (1.0 / step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step),
			_repo.bal("war_board_min_m"), _repo.bal("war_board_max_m"))
		_camera.transform = _board_pose()
	elif mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if mm.position.distance_to(_board_press) > _repo.bal("war_click_slop_px"):
			_board_dragged = true   # past the slop a press is a pan, not a click
		if _board_dragged:
			_board_offset = WarBoard.clamp_offset(_board_offset + Vector2(-mm.relative.x, mm.relative.y)
				* _board_dist * _repo.bal("war_pan_drag_speed"), _board_size())
			_camera.transform = _board_pose()
	elif mm != null:
		var uv := _board_uv(mm.position)
		if uv.x >= 0.0:
			board_hovered.emit(uv)
	elif mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var uv := _board_uv(mb.position)
		if mb.pressed:
			_board_dragged = false
			_board_press = mb.position
			if uv.x >= 0.0:
				board_clicked.emit(uv, mb)
		else:
			# the release always reaches the board, so its button is never left
			# held; a pan's lands off the board, where no note fires (review I1)
			board_clicked.emit(Vector2(-1, -1) if _board_dragged else uv, mb)


## WASD / arrows pan the room (spec 2026-10-02-war-room-v2 §1.1), never while
## a text box (the council's talk box) has the focus; true when it moved.
func key_pan(delta: float) -> bool:
	if _sheet < 0 or not is_visible_in_tree():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	var dir := WarRoomGestures.key_dir()
	if dir == Vector2.ZERO:
		return false
	_rig.pan_view(dir * _rig.distance * _repo.bal("war_key_pan_screens_per_s") * delta)
	return true


## A roll cut short (the room closed) lays its sheet and stands the table up.
func _finish_swap() -> void:
	if _swap.active():
		_swap.cancel()
		if _swap.to != _sheet:
			lay_sheet(_swap.to)
	_table.scale = Vector3.ONE
	_pieces.visible = true
	_pennants.visible = true


## The sheet's ink onto the table's material (WarRoomInk draws and keeps it).
func _paint_ink(mat: ShaderMaterial) -> void:
	var sheet := _sheet
	var tex := await _inks.texture_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(),
		func() -> bool: return is_inside_tree() and sheet == _sheet)
	if tex != null:
		mat.set_shader_parameter("ink_tex", tex)


func _apply_camera() -> void:
	_camera.transform = _rig.transform()
	if _repo != null:
		_pieces.set_camera_distance(_rig.distance)
		_rake.redraw()
	camera_moved.emit()


## The pack's own measure (map_info distance_scale per pack px) one screen px
## of this view spans at the camera's target: the margin's scale bar (spec §2).
func units_per_px() -> float:
	if _sheet < 0 or _repo == null:
		return 0.0
	return units_per_px_at(_rig.distance, _camera.fov, size.y, _rect.size.x, _table_w,
		float(_repo.map_info.get("distance_scale", "1")))


## The same, pure: a perspective camera `distance_m` from its target with a
## vertical `fov_deg` over `view_h_px` px sees 2·d·tan(fov/2) metres of table
## across that height; the sheet's `sheet_w_px` pack px span `table_w_m`.
static func units_per_px_at(distance_m: float, fov_deg: float, view_h_px: float, sheet_w_px: float,
		table_w_m: float, units_per_pack_px: float) -> float:
	if view_h_px <= 0.0 or table_w_m <= 0.0:
		return 0.0
	var metres := 2.0 * distance_m * tan(deg_to_rad(fov_deg) * 0.5) / view_h_px
	return metres * sheet_w_px / table_w_m * units_per_pack_px


## Put the camera `metres` from the table (held within its limits), looking at
## the table point under `focus_px` (a pack point; (-1, -1) keeps the target).
## The snapshot tool's --war-zoom and anything that wants a set framing.
func lean_to(metres: float, focus_px := Vector2(-1, -1)) -> void:
	if focus_px.x >= 0.0:
		var p := table_point(focus_px)
		_rig.target = Vector3(p.x, 0.0, p.z)
		_rig.pan(Vector2.ZERO)   # clamped to the sheet
	_rig.distance = clampf(metres, _rig.min_distance, _rig.max_distance)
	_rig.pan(Vector2.ZERO)   # held on the table and inside the room
	_apply_camera()


func y_at(xz: Vector2) -> float:
	return WarRoomTable.height_at(_heights, _nx, _nz, _table_w, _depth, xz) * _y_scale


func table_point(pack_px: Vector2) -> Vector3:
	var xz := WarRoomTable.to_table(_rect, _table_w, pack_px)
	return Vector3(xz.x, y_at(xz), xz.y)


## Where a pack point stands on the screen (this Control's px), null when
## behind the camera.
func screen_pos_of_px(pack_px: Vector2) -> Variant:
	var p := table_point(pack_px)
	if _camera.is_position_behind(p):
		return null
	return _camera.unproject_position(p) / window_scale()


## The pack point under a screen px, Vector2(-1, -1) off the table.
func pack_at(screen_px: Vector2) -> Vector2:
	var s := screen_px * window_scale()
	var hit := WarRoomTable.ray_hit(_camera.project_ray_origin(s), _camera.project_ray_normal(s), y_at)
	if hit == Vector3.INF or not _rig.bounds.has_point(Vector2(hit.x, hit.z)):
		return Vector2(-1, -1)
	return WarRoomTable.from_table(_rect, _table_w, Vector2(hit.x, hit.z))


func refresh() -> void:
	_pieces.update(state())
	_pennants.rebuild(state())
	_rake.redraw()


## Redraw the HUD's marks (the rake, the chalk ring, the pennants' dashes):
## WarPieces asks each frame a piece is pushed, so they follow it.
func redraw_marks() -> void:
	_rake.redraw()


## The rake's march was refused (or its order is done): let go of the piece.
func cancel_rake() -> void:
	_rake.cancel()


func rake_reading(code: String, to_px: Vector2) -> String:
	return _rake.reading(code, to_px)


func selected_army() -> String:
	return _selected


func clear_selection() -> void:
	_selected = ""
	selection_cleared.emit()
	_rake.redraw()


func rolling() -> bool:
	return _swap.active()


func select(code: String) -> void:
	_selected = code
	piece_selected.emit(code)
	_rake.redraw()


## The code of the piece under a screen px, "" when none (and none while a
## sheet rolls: the pieces are put away).
func piece_under(screen_px: Vector2) -> String:
	if rolling():
		return ""
	return _pieces.pick(_camera, window_scale(), screen_px, _repo.bal("war_pick_px"))


func _ground_under(screen_px: Vector2) -> Vector3:
	var at := pack_at(screen_px)
	return table_point(at) if at.x >= 0.0 else _rig.target


func _gui_input(event: InputEvent) -> void:
	if _sheet < 0:
		return
	if _board_mode != "table":
		_board_input(event)
		return
	# a click (not a pan) on the easel's board flies there; nothing behind it is picked
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT and not press.pressed \
			and not _rake.empty_press_moved(press.position) and piece_under(press.position) == "" \
			and _board_uv(press.position).x >= 0.0 and _rake.code == "":
		_rake.forget_press()
		enter_board()
		accept_event()
		return
	if event is InputEventMouseMotion:
		tooltip_text = "Study the board" if _board_uv((event as InputEventMouseMotion).position).x >= 0.0 else ""
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_rake.on_left(mb)
	elif mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) and _rake.empty_press():
		pass   # an open-table drag: the gestures pan below
	elif mm != null and not (mm.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
		_rake.on_motion(mm)
	var did := _gestures.handle(event, _rig, _repo, _ground_under, _rake.empty_press())
	if did == WarRoomGestures.RIGHT_CLICK:
		var code := piece_under(mb.position)
		if code != "":
			army_menu_requested.emit(code, mb.position)
		accept_event()
	elif did == WarRoomGestures.MOVED:
		_apply_camera()
		accept_event()
