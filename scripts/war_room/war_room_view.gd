class_name WarRoomView
extends Control
## The WAR ROOM (owner 2026-10-01, spec 2026-10-01-war-room-design): a stone
## room, an oak table, ONE numbered sheet laid on it as inked vellum over the
## relief, the crown's regiments as tin pieces. It draws and signals; it reads
## no autoload and changes no state — the screen (scripts/ui/war_room_screen.gd)
## hands it the repository, a state getter and a paused-clock getter, and runs
## its orders. It speaks ArmyOrderMenu's map contract (ground_clicked,
## route_clicked, aiming / aim_dest / aim_code / aim_waypoints, supply_pick /
## supply_preview), so the 3D map's own confirm serves the table. Renders into a SubViewport
## at WINDOW resolution shown by a TextureRect, and only while active.
## Orders are DRAWN (spec 2026-10-08-war-room-draw-orders): a blue arrow drawn
## for the selected regiments is their march (WarPlanInput's order_drawn); a
## piece has no order menu here.

signal piece_selected(code: String)
signal selection_cleared
signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
signal route_clicked(code: String, at: Vector2)
## A planned march's waypoints were bent on the table (WarRoomPointer; spec
## 2026-10-07-march-waypoints ruling 9): ArmyOrderMenu keeps or refuses them.
signal route_bent(waypoints: PackedVector2Array)
signal sheet_requested(index: int)
## A sheet starts rolling up: a march pending on its confirm is given up.
signal sheet_rolling
signal sheet_laid(index: int)
signal camera_moved
## The easel's Missive board (spec 2026-10-02-war-room-v2 §1.3): the camera
## has flown to it / back to the table; a click or a hover on its panel, as a
## UV of the board's SubViewport (the screen pushes it in as real input).
signal board_entered
signal board_left
signal board_clicked(uv: Vector2, event: InputEventMouseButton)
signal board_hovered(uv: Vector2)
## The pointer has rested on open table (spec 2026-10-07-war-room-scale-hover
## §4.2): the screen reads the ground there.
signal ground_hovered(pack_px: Vector2, screen_px: Vector2)
## The pointer has rested on a piece (owner 2026-10-07): the screen shows the
## regiments it stands for, with their combat figures.
signal piece_hovered(code: String, screen_px: Vector2)
## An order arrow being drawn has its tip at `pack_px`: the screen reads the
## destination for `code` (the selection's first regiment).
signal order_aimed(code: String, pack_px: Vector2, screen_px: Vector2)
## The slip goes: the pointer moved, the arrow ended, the room got busy.
signal hover_cleared
## A right click on open table (spec 2026-10-07-war-room-annotations-and-
## planning-pieces §1.5): the ground menu — Place a supposed enemy, Draw, Clear.
signal ground_menu_requested(pack_px: Vector2, screen_px: Vector2)
## A right click on a supposed piece or a stroke: its own menu.
signal plan_menu_requested(id: String, screen_px: Vector2)
## The pointer has rested on a supposed piece: the screen shows its slip.
signal plan_hovered(id: String, screen_px: Vector2)
## A mouse button went down on the table (the name box commits on it).
signal table_pressed

var aiming := false:
	set(v):
		var was := aiming
		aiming = v
		if not v and was:
			hover_cleared.emit()   # the tip's slip goes with the aim
		_redraw_all()
var aim_dest := Vector2(-1, -1)
var aim_code := ""
## The planned march's waypoints, pack px (ArmyOrderMenu sets them; a bend moves them).
var aim_waypoints := PackedVector2Array():
	set(v):
		aim_waypoints = v
		_redraw_all()
## The other regiments of a march drawn for several (code -> waypoints, pack
## px; the lead's are aim_waypoints): ArmyOrderMenu sets them.
var aim_group: Dictionary = {}:
	set(v):
		aim_group = v
		_redraw_all()
## The towns that may supply the pending march (town -> "" lit, else why)
## and the chosen one's road to its end, pack px: ArmyOrderMenu sets them
## (spec 2026-10-08-war-room-draw-orders rulings 13-14), as on the 3D map.
var supply_pick: Dictionary = {}:
	set(v):
		supply_pick = v
		_redraw_all()
## The town the preview road starts from (ArmyOrderMenu sets it with the preview).
var supply_town := ""
var supply_preview := PackedVector2Array():
	set(v):
		supply_preview = v
		_redraw_all()

@onready var _viewport: SubViewport = %Viewport
@onready var _display: TextureRect = %Display
@onready var _camera: Camera3D = %Camera
@onready var _table: MeshInstance3D = %Table
@onready var _ink_viewport: SubViewport = %InkViewport
@onready var _ink: WarInkPainter = %Ink
@onready var _chart: MeshInstance3D = %IndexChart
@onready var _arrows: Node3D = %EdgeArrows
@onready var _pieces: WarPieces = %Pieces
@onready var _plan_pieces: WarPlanPieces = %PlanPieces
@onready var _pennants: WarPennants = %Pennants
@onready var _board: MeshInstance3D = %BoardPanel
@onready var _marker: Node3D = %Marker
@onready var _supply: MeshInstance3D = %SupplyFlow

var _repo: DataRepository
var _state_fn: Callable
var _paused_fn: Callable
var _drawn_fn: Callable   # -> {code: pack px} where the 3D map draws each regiment (bind)
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
var _dwell := WarHoverDwell.new()
var _detail_state: Dictionary = {}   # the near-zoom patch drawn now: {level, rect, key}
var _render_scale := 1.0
var _selected := ""
var _font: Font
var _caps: Font
var _chart_built := false
var _swap := WarSheetSwap.new()
var _plan_input := WarPlanInput.new()
var _pointer := WarRoomPointer.new()
var _ants_t := 0.0
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
var _toss: Dictionary = {}
var _toss_t := 0.0
var _toss_to := -1
var _toss_n := 0
var _supply_routes: Array = []   # the flowing supply roads on this sheet (WarSupplyFlow.routes), read on a state change


## No slip while the camera or the sheet moves, in board mode, or while a
## popup or a text box has the input (spec §4.2).
func hover_allowed() -> bool:
	if _sheet < 0 or _board_mode != "table" or rolling() or tossing() or aiming or _plan_input.busy():
		return false   # aiming: the order's confirm menu stands beside the tip; a stick in hand draws
	var owner := get_viewport().gui_get_focus_owner()
	return not (owner is LineEdit or owner is TextEdit)


func _ready() -> void:
	# two views never share a material or an environment
	_table.material_override = _table.material_override.duplicate()
	var env: WorldEnvironment = %Env
	env.environment = env.environment.duplicate()
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)


## `drawn_fn` gives where the 3D map DRAWS each regiment, pack px (owner
## 2026-10-02: the room's pieces stand exactly where the map shows them); a
## regiment it does not name stands at WarRoom.believed_position.
func bind(repo: DataRepository, state_fn: Callable, paused_fn: Callable, drawn_fn := Callable()) -> void:
	_repo = repo
	_state_fn = state_fn
	_paused_fn = paused_fn
	_drawn_fn = drawn_fn
	_pieces.setup(repo, self)
	_plan_pieces.setup(repo, self)
	_plan_input.setup(self, repo, %PlanHud)
	_plan_input.selection_changed.connect(_on_plan_selection)
	_pennants.setup(repo, self)
	_pointer.setup(self, repo, {"hud": %Hud, "plan_hud": %PlanHud, "pieces": _pieces, "pennants": _pennants, "camera": _camera,
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


## Where the 3D map draws each regiment, pack px ({} with no map).
func drawn() -> Dictionary:
	return _drawn_fn.call() as Dictionary if _drawn_fn.is_valid() else {}


## Where a regiment's piece stands, pack px: the map's drawn spot, else the
## engine's believed one.
func position_of(code: String) -> Vector2:
	return WarRoom.believed_position(_repo, state(), ArmySystem.regiment(_repo, code, state()), drawn())


## The lettering face is handed in by the screen (UiPalette's body_italic
## role), so the face stays data; the default font until it is.
func set_font(f: Font) -> void:
	_font = f


## The plan layer's small capitals (an objective's name), set by the screen.
func set_caps_font(f: Font) -> void:
	_caps = f


## The plans changed (the screen hears plans_changed): only the plan layer is redrawn.
func refresh_plans() -> void:
	if _sheet >= 0:
		_paint_intel(_table.get_active_material(0) as ShaderMaterial)
		_plan_pieces.update(state())
		_plan_input.redraw_live()


## The key (WarPlanInk.cache_key) of the plan layer last painted onto the table, -1 none.
func plan_key_shown() -> int:
	return _plan_key_shown


## The stroke `id` is left out of the plan layer ("" shows all): a stroke being
## dragged is drawn live, never twice.
func hide_plan_stroke(id: String) -> void:
	if id == _plan_hidden:
		return
	_plan_hidden = id
	_plan_key_shown = -1   # the layer on the table no longer matches
	if _sheet >= 0:
		_paint_intel(_table.get_active_material(0) as ShaderMaterial)


## The supposed pieces (WarPlanPieces).
func plan_pieces() -> WarPlanPieces:
	return _plan_pieces


## The plans' left button and what is in hand (WarPlanInput).
func plan_input() -> WarPlanInput:
	return _plan_input


func camera() -> Camera3D:
	return _camera


func caps_font() -> Font:
	return _caps


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
	if _repo != null:
		_pointer.redraw()   # the HUD's lines are screen px: a new size moves every one of them


func set_active(on: bool) -> void:
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	if not on:
		_detail_state = {}
		(%DetailViewport as SubViewport).size = Vector2i(2, 2)   # the patch's render target given back
		var table_mat := _table.get_active_material(0) as ShaderMaterial
		if table_mat != null:   # and unbound, so a reopened room never samples the empty target
			table_mat.set_shader_parameter("detail_on", 0.0)
			table_mat.set_shader_parameter("detail_tex", null)
		_dwell.clear()
		hover_cleared.emit()
		_finish_swap()
		_viewport.size = Vector2i(2, 2)  # its render targets freed while shut (perf 2026-10-02)
		_inks.trim(1)  # and only the laid sheet's ink kept
	if on:
		_fit_viewport()
		if _sheet >= 0 and _repo != null:
			_update_detail()   # reopened at a near lean: the patch is drawn again


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
	# the build's own heights (WarBake: what Terrain3D was built from), else the
	# pack's relief bitmap, else flat (spec 2026-10-02-war-room-v2 §2.4)
	var bake := WarBake.of(_repo)
	var raw := bake.heights(_rect, _nx, _nz) if bake != null \
		else (WarRoomTable.raw_heights(_repo, _relief, _rect, _nx, _nz) if _relief != null else WarRoomTable.flat(_nx, _nz))
	# the relief stands on the tapered field (the collar lies flat); the contours
	# and the shore keep the true one
	_heights = WarRoomTable.clamp_sea(WarRoomTable.taper_collar(raw, _nx, _nz, _rect, all[index].get("cell", _rect)))
	_y_scale = WarRoomTable.table_y(_repo, _rect, _table_w, 1.0)
	var shore := WarRoomTable.shore_share(_repo, raw, _nx, _nz, _table_w, _depth)
	_table.mesh = WarRoomTable.build_mesh(WarRoomTable.clamp_sea(raw), _nx, _nz, _table_w, _depth, _y_scale, raw, shore, _heights)
	var mat := _table.get_active_material(0) as ShaderMaterial
	mat.set_shader_parameter("intel_tex", null)   # no sheet wears another's intelligence (final review I2)
	mat.set_shader_parameter("plan_tex", null)    # nor another's plans
	mat.set_shader_parameter("fine_tex", null)
	mat.set_shader_parameter("detail_on", 0.0)
	_detail_state = {}
	WarRoomMaterial.bind(mat, _repo, all[index], _table_w, _depth)
	_rig.bounds = Rect2(-_table_w * 0.5, -_depth * 0.5, _table_w, _depth)
	_rig.target = Vector3.ZERO
	_rig.yaw_deg = 0.0
	_rig.distance = _repo.bal("war_cam_distance_m")
	_apply_camera()
	if not _chart_built:
		_chart_built = true
		WarRoomWall.build_chart(_chart, _repo, lettering())
	WarRoomWall.lay_arrows(_arrows, _repo, index, _table_w, _depth, lettering())
	_stand_marker(index)
	_pieces.rebuild(state())
	_plan_pieces.rebuild(state())
	_pennants.rebuild(state(), true)
	_read_supply()
	_pointer.redraw()
	_plan_input.keep_on_sheet()
	if _selected != "" and not _selected in _plan_input.sel:
		_selected = ""
		selection_cleared.emit()
	sheet_laid.emit(index)
	await _paint_ink(mat)
	await _paint_intel(mat)


## Roll the laid sheet up and lay `index` at the midpoint (spec §2). With no
## sheet laid yet, or the room not drawing, it is laid at once; a roll in
## progress is not interrupted.
func swap_to(index: int) -> void:
	if index == _sheet or index < 0 or _swap.active() or tossing():
		return   # a toss in flight decides the next sheet (final review I1)
	sheet_rolling.emit()
	if _sheet < 0 or not is_processing():
		lay_sheet(index)
		return
	_swap.start(index, _repo)


func _process(delta: float) -> void:
	_step_toss(delta)
	if not hover_allowed():
		if _dwell.clear():
			hover_cleared.emit()
	elif _dwell.step(delta, _repo.bal("war_hover_delay_s")):
		var at := _dwell.at
		var pk := pack_at(at)
		var piece := piece_under(at)
		var plan := "" if piece != "" else _plan_pieces.pick(_camera, window_scale(), at, _repo.bal("war_pick_px"))
		if piece != "":
			piece_hovered.emit(piece, at)   # its combat figures (owner 2026-10-07)
		elif plan != "":
			plan_hovered.emit(plan, at)   # a supposed piece: its men on this ground (the same slip)
		elif pk.x >= 0.0 and WarRoomPicks.nearest(_pennants.screen_hits(_camera, window_scale()), at, _repo.bal("war_pick_px")) == "":
			ground_hovered.emit(pk, at)
	if _board_mode == "table" and not rolling():
		_ants_t += delta
		(%Hud as WarHud).set_phase(_ants_t)   # the intel hints' marching ants
	var flying := _step_board(delta)
	if not flying and (_rig.step(delta, _repo.bal("war_cam_north_s")) or key_pan(delta)):
		_apply_camera()
	if not _swap.active():
		return
	if _swap.step(delta):
		lay_sheet(_swap.to)
	_table.scale = Vector3(1.0, 1.0, _swap.z_scale())
	_pieces.visible = not _swap.active()   # the pieces, pennants and supply lines are put away while a sheet rolls
	_pennants.visible = _pieces.visible
	_plan_pieces.visible = _pieces.visible
	_supply.visible = _pieces.visible


func tossing() -> bool:
	return not _toss.is_empty()


## Toss the war marker onto sheet `index`'s cell of the index chart, then lay
## the sheet (spec 2026-10-02-war-room-v2 §2.3). Ignored mid-toss or mid-roll.
func toss_to(index: int) -> void:
	if tossing() or rolling() or index < 0 or index >= WarSheets.series(_repo).size():
		return
	_toss_n += 1
	var uv := WarToss.landing(WarIndexChart.uv_of_cell(_repo, WarSheets.series(_repo)[index]),
		hash([index, _toss_n]), _repo.bal("war_toss_margin"))
	var to := WarRoomWall.chart_point(_chart, uv)
	var hand := to + (_camera.global_position - to).normalized() * _repo.bal("war_toss_hand_m")
	_toss = WarToss.plan(hand, to, hash([index, _toss_n, "toss"]), WarToss.rules(_repo))
	_toss_t = 0.0
	_toss_to = index
	_marker.visible = true
	_marker.global_transform = WarToss.pose(_toss, 0.0)


func _step_toss(delta: float) -> void:
	if not tossing():
		return
	_toss_t += delta
	_marker.global_transform = WarToss.pose(_toss, _toss_t)
	if _toss_t >= float(_toss["duration"]):
		var to := _toss_to
		_toss = {}
		sheet_requested.emit(to)


## The marker stands on the laid sheet's cell of the chart (no toss: the first
## lay, a lay by an edge arrow or the margin).
func _stand_marker(index: int) -> void:
	if tossing():
		return
	var uv := WarIndexChart.uv_of_cell(_repo, WarSheets.series(_repo)[index]).get_center()
	_marker.global_transform = Transform3D(Basis.IDENTITY, WarRoomWall.chart_point(_chart, uv))
	_marker.visible = true


func board_mode() -> String:
	return _board_mode


## The easel's panel shows `tex` (the board-only MissiveScreen's viewport).
func set_board_texture(tex: Texture2D) -> void:
	var mat := (_board.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_texture = tex
	_board.material_override = mat


func _board_size() -> Vector2:
	return (_board.mesh as QuadMesh).size


## True when any of the panel (its centre or a corner) is in view, or the
## camera is the board's (the screen renders the board's viewport only then:
## a board half in view must not show black).
func board_visible() -> bool:
	if _board_mode != "table":
		return true
	var half := _board_size() * 0.5
	var view := Rect2(Vector2.ZERO, size)
	for c: Vector2 in [Vector2.ZERO, Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), half]:
		var p := _board.global_transform * Vector3(c.x, c.y, 0.0)
		if not _camera.is_position_behind(p) and view.has_point(_camera.unproject_position(p) / window_scale()):
			return true
	return false


func _board_pose() -> Transform3D:
	return WarBoard.pose(_board.global_transform, _board_dist, _board_offset)


## Fly the camera to the easel's board (spec §1.3); the table's pose is kept
## for the flight back.
func enter_board() -> void:
	if _board_mode != "table":
		return
	# the HUD's marks are screen px of the TABLE's view: none of them (the
	# selection's rings, the pennants' dashes, the pencils) hangs over the
	# board while the camera is away (owner 2026-10-07)
	(%Hud as CanvasItem).visible = false
	(%PlanHud as CanvasItem).visible = false   # the drafts' pencils and the live strokes too
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
				(%Hud as CanvasItem).visible = true
				(%PlanHud as CanvasItem).visible = true
				_apply_camera()   # the marks redrawn where the table's view puts them
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
	_plan_pieces.visible = true
	_pennants.visible = true
	_supply.visible = true


## The laid sheet's intelligence layer onto the table's material (redrawn only
## when its key turns: WarRoomInk.intel_for). Never two draws at once.
var _intel_busy := false
var _plan_hidden := ""   # the stroke being dragged: left out of the plan layer
var _plan_key_shown := -1   # the WarPlanInk.cache_key of the last plan paint that finished
var _intel_again := false   # a repaint asked for while one was in flight
var _ink_busy := 0   # sheet ink draws in flight: the intel layer waits (one ink viewport, one draw at a time)


func _paint_intel(mat: ShaderMaterial) -> void:
	if mat == null or _sheet < 0:
		return
	if _intel_busy or _ink_busy > 0:
		_intel_again = true   # run again once the draw in flight is done
		return
	_intel_busy = true
	var sheet := _sheet
	var tex := await _inks.intel_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(),
		func() -> bool: return is_inside_tree() and sheet == _sheet)
	if tex != null and sheet == _sheet:
		mat.set_shader_parameter("intel_tex", tex)
	# the staff's plan layer after it, on the same viewport (spec
	# 2026-10-07-war-room-annotations-and-planning-pieces §2.5)
	var key := WarPlanInk.cache_key(state(), sheet)
	var hidden := _plan_hidden
	var plan := await _inks.plan_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(), _caps,
		func() -> bool: return is_inside_tree() and sheet == _sheet, hidden)
	_intel_busy = false
	if plan != null and sheet == _sheet:
		mat.set_shader_parameter("plan_tex", plan)
	if sheet == _sheet and hidden == _plan_hidden:
		_plan_key_shown = key   # this paint is done, a texture or not: the ghost has served
		_plan_input.redraw_live()
	if _intel_again:
		_intel_again = false
		_paint_intel(_table.get_active_material(0) as ShaderMaterial)


## The sheet's ink onto the table's material (WarRoomInk draws and keeps it).
func _paint_ink(mat: ShaderMaterial) -> void:
	var sheet := _sheet
	_ink_busy += 1
	var tex := await _inks.texture_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(),
		func() -> bool: return is_inside_tree() and sheet == _sheet)
	if tex != null:
		mat.set_shader_parameter("ink_tex", tex)
	var fine := await _inks.fine_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(),
		func() -> bool: return is_inside_tree() and sheet == _sheet)
	_ink_busy -= 1
	if fine != null and sheet == _sheet:
		mat.set_shader_parameter("fine_tex", fine)
	if _intel_again and _ink_busy == 0:
		_intel_again = false
		_paint_intel(_table.get_active_material(0) as ShaderMaterial)


func _apply_camera() -> void:
	_camera.transform = _rig.transform()
	_plan_input.redraw_live()   # the live stroke and the handles follow the table
	if _dwell.clear():   # the ground under the pointer moved: the slip goes, the rest restarts
		hover_cleared.emit()
	if _repo != null:
		_pieces.set_camera_distance(_rig.distance)
		_plan_pieces.set_camera_distance(_rig.distance)
		var mat := _table.get_active_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("contour_m", WarNear.contour_m(_repo, _rig.distance))
			mat.set_shader_parameter("fine_alpha", WarNear.fine_alpha(_repo, _rig.distance))
			_update_detail()
		_pointer.redraw()
	camera_moved.emit()


## The near-zoom detail patch (spec 2026-10-07-war-room-scale-hover §2): nearer
## than war_detail_level_m, the ink round the view redrawn at the patch's
## resolution into its own resident viewport (no read-back), only when its
## level, rect or ownership key turns.
func _update_detail() -> void:
	var mat := _table.get_active_material(0) as ShaderMaterial
	var lvl := WarDetailInk.level(_repo, _rig.distance)
	if lvl == 0 or _sheet < 0:
		mat.set_shader_parameter("detail_on", 0.0)
		if not _detail_state.is_empty():   # leaning out: the patch's render target given back, unbound
			mat.set_shader_parameter("detail_tex", null)
			(%DetailViewport as SubViewport).size = Vector2i(2, 2)
		_detail_state = {}
		return
	# pack px the view spans (units_per_px is in the pack's own measure)
	var view_px := Vector2(size) * units_per_px() / maxf(float(_repo.map_info.get("distance_scale", "1")), 0.0001)
	var centre := WarRoomTable.from_table(_rect, _table_w, Vector2(_rig.target.x, _rig.target.z))
	var now := {"level": lvl, "rect": WarDetailInk.patch_rect(_repo, _rect, centre, view_px),
		"key": WarSheetInk.cache_key(state(), _sheet)}
	if not WarDetailInk.needs_redraw(_detail_state, now):
		return
	_detail_state = now
	var r: Rect2 = now["rect"]
	var vp: SubViewport = %DetailViewport
	var w := int(_repo.bal("war_detail_texture_px"))
	vp.size = Vector2i(w, maxi(1, ceili(w * r.size.y / r.size.x)))
	var scale := _rect.size.x / r.size.x * float(w) / float(WarRoomInk.tex_size(_repo, _rect).x)
	var widths := {}
	for k: String in WarRoomInk.INK_PX:
		widths[k] = _repo.bal("war_ink_%s_px" % k) * scale
	for k: String in WarRoomInk.INK_RATIOS:
		widths[k] = _repo.bal("war_ink_%s" % k)
	widths["mark"] = _repo.bal("war_mark_px") * scale
	widths["mark_reach_alpha"] = _repo.bal("war_mark_reach_alpha")
	widths["mark_reach"] = _repo.bal("war_mark_reach_px") * scale
	var row: Dictionary = WarSheets.series(_repo)[_sheet]
	(%DetailInk as WarInkPainter).paint(WarSheetInk.strokes(_repo, state(), row, w, WarBake.of(_repo), r),
		_repo.war_palette, widths, lettering())
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_settle_detail(vp)
	mat.set_shader_parameter("detail_tex", vp.get_texture())
	mat.set_shader_parameter("detail_uv", Vector4((r.position.x - _rect.position.x) / _rect.size.x,
		(r.position.y - _rect.position.y) / _rect.size.y, (r.end.x - _rect.position.x) / _rect.size.x,
		(r.end.y - _rect.position.y) / _rect.size.y))
	mat.set_shader_parameter("detail_feather", _repo.bal("war_detail_feather"))
	mat.set_shader_parameter("detail_on", 1.0)



## After the frame that draws the patch, the viewport is set aside explicitly:
## left at UPDATE_ONCE it kept costing every frame (bench 2026-10-07: the cpu
## column 10 -> 45-168 ms after one lean in).
func _settle_detail(vp: SubViewport) -> void:
	await _inks.frame_done   # the frame that drew it (a headless test hands in the process frame)
	if is_instance_valid(vp) and vp.render_target_update_mode == SubViewport.UPDATE_ONCE:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

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


## The node of a unit's piece on the laid sheet, null when none.
func piece_node(code: String) -> Node3D:
	return _pieces.piece(code)


## Where each piece of the laid sheet stands, in pack px (its base's centre,
## mid-push included): code -> Vector2.
func piece_pack_positions() -> Dictionary:
	var out: Dictionary = {}
	if _sheet < 0:
		return out
	for c: Node in _pieces.get_children():
		if c is Node3D and not c.is_queued_for_deletion():
			var p := (c as Node3D).position
			out[String(c.get_meta("code", ""))] = WarRoomTable.from_table(_rect, _table_w, Vector2(p.x, p.z))
	return out


## The pack point under a screen px, Vector2(-1, -1) off the table.
func pack_at(screen_px: Vector2) -> Vector2:
	var s := screen_px * window_scale()
	var hit := WarRoomTable.ray_hit(_camera.project_ray_origin(s), _camera.project_ray_normal(s), y_at)
	if hit == Vector3.INF or not _rig.bounds.has_point(Vector2(hit.x, hit.z)):
		return Vector2(-1, -1)
	return WarRoomTable.from_table(_rect, _table_w, Vector2(hit.x, hit.z))


func refresh() -> void:
	if _sheet >= 0:
		_paint_intel(_table.get_active_material(0) as ShaderMaterial)
	_pieces.update(state())
	_pennants.rebuild(state())
	_read_supply()
	_pointer.redraw()


## Redraw the HUD's marks (the rake, the chalk ring, the pennants' dashes)
## and lay the supply lines' ends again: WarPieces asks each frame a piece is
## pushed, so they follow it.
func redraw_marks() -> void:
	_pointer.redraw()
	_lay_supply()


## The flowing supply roads on the laid sheet, found again (the state moved).
func _read_supply() -> void:
	_supply_routes = WarSupplyFlow.routes(_repo, state(), _rect) if _sheet >= 0 else []
	_lay_supply()


## The supply lines' gold ribbons, each ending where its piece stands NOW
## (mid-push included; one piece a unit).
func _lay_supply() -> void:
	if _supply_routes.is_empty():
		_supply.mesh = null
		return
	var at := piece_pack_positions()
	var ends := {}
	for r: Dictionary in _supply_routes:
		var code := String(r["code"])
		ends[code] = at[code] if at.has(code) else position_of(code)
	var lines: Array = []
	for l: Dictionary in WarSupplyFlow.lines(_supply_routes, ends, _rect):
		var pts := PackedVector3Array()
		for p: Vector2 in l["poly"]:
			pts.append(table_point(p))
		lines.append(pts)
	_supply.mesh = WarSupplyFlow.ribbon(lines)


## The supply lines' look (war_supply_flow.tres): the key slip draws its line from it.
func supply_look() -> ShaderMaterial:
	return _supply.material_override as ShaderMaterial


## The supply lines' mesh now (tests read it).
func supply_mesh() -> ArrayMesh:
	return _supply.mesh as ArrayMesh


func selected_army() -> String:
	return _selected


## Anything selected: a piece of ours chosen, or a selection of either side.
func has_selection() -> bool:
	return _selected != "" or not _plan_input.sel.is_empty()


func clear_selection() -> void:
	_selected = ""
	_plan_input.clear_selection()
	selection_cleared.emit()
	_pointer.redraw()


## A selection of theirs lets our chosen piece (and its book) go.
func _on_plan_selection() -> void:
	if _plan_input.sel_side != "blue" and _selected != "":
		_selected = ""
		selection_cleared.emit()
	_pointer.redraw()


func _redraw_all() -> void:
	if _repo != null and is_inside_tree():
		_pointer.redraw()
		_plan_input.redraw_live()


func rolling() -> bool:
	return _swap.active()


## One of our pieces clicked (spec 2026-10-08-war-room-draw-orders ruling
## 16): its unit is the blue selection — `additive` (Shift) toggles it in or
## out — and the piece's folio opens docked; `quiet` leaves the selection as
## it is (the box has set it).
func select(code: String, additive := false, quiet := false) -> void:
	if not quiet:
		_plan_input.select("blue", [code], additive)
		if _plan_input.sel.is_empty():
			clear_selection()   # Shift took the last one out
			return
		if not code in _plan_input.sel:
			code = String(_plan_input.sel[0])   # taken out: the book goes to the first one left
	_selected = code
	piece_selected.emit(code)
	_pointer.redraw()


## ArmyOrderMenu's map contract: a unit chosen.
func select_army(code: String) -> void:
	select(code)


## The press was the plans' (a stroke chosen by a click): the pointer must not
## also read its release as an open-table click.
func forget_press() -> void:
	_pointer.forget_press()


## A click the plans' stick let through (the pointer's pick).
func click_through(at: Vector2, shift: bool) -> void:
	if _pointer.click(at, shift):
		accept_event()


## The code of the piece under a screen px, "" when none (and none while a
## sheet rolls: the pieces are put away).
func piece_under(screen_px: Vector2) -> String:
	if rolling():
		return ""
	return _pieces.pick(_camera, window_scale(), screen_px, _repo.bal("war_pick_px"))


func _ground_under(screen_px: Vector2) -> Vector3:
	var at := pack_at(screen_px)
	return table_point(at) if at.x >= 0.0 else _rig.target


## A right click: a supposed piece's or a stroke's menu, else the ground menu
## on the table; none on one of our pieces (orders are drawn), nor while a
## march waits on its confirm (the aim owns the ground).
func _plan_right_click(at: Vector2) -> void:
	if aiming or piece_under(at) != "":
		return
	var radius := _repo.bal("war_pick_px")
	var pid := _plan_pieces.pick(_camera, window_scale(), at, radius)
	if pid != "":
		plan_menu_requested.emit(pid, at)
		return
	var hit := WarPlanTool.hit(_repo, _plan_input.strokes_on_screen(), at, _plan_input.chosen_id, radius)
	if not hit.is_empty():
		plan_menu_requested.emit(String(hit["id"]), at)
		return
	var pk := pack_at(at)
	if pk.x >= 0.0:
		ground_menu_requested.emit(pk, at)


## The pointer left the view (onto the folio, the margin, a bar): no rest to read.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _dwell.clear():
		hover_cleared.emit()


func _gui_input(event: InputEvent) -> void:
	if _sheet < 0:
		return
	if _board_mode != "table":
		_board_input(event)
		return
	var down := event as InputEventMouseButton
	if down != null and down.pressed and down.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		table_pressed.emit()
	# the plans first: a stick in hand draws, a supposed piece is carried, a
	# stroke is reshaped (spec 2026-10-07-war-room-annotations-and-planning-pieces §1.6);
	# never while a march waits on its confirm — its route, waypoints and bends own the table
	if not aiming and _plan_input.handle(event):
		if _dwell.clear():
			hover_cleared.emit()
		accept_event()
		return
	# a click (not a pan) on the easel's board flies there; nothing behind it is picked
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT and not press.pressed \
			and not _pointer.empty_press_moved(press.position) and piece_under(press.position) == "" \
			and _board_uv(press.position).x >= 0.0:
		_pointer.forget_press()
		enter_board()
		accept_event()
		return
	if event is InputEventMouseMotion:
		tooltip_text = "Study the board" if _board_uv((event as InputEventMouseMotion).position).x >= 0.0 else ""
		var hm := event as InputEventMouseMotion
		if hm.button_mask != 0:
			if _dwell.clear():
				hover_cleared.emit()
		elif _dwell.moved(hm.position, _repo.bal("war_hover_still_px")):
			hover_cleared.emit()
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_pointer.on_left(mb)
	elif mm != null and not (mm.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
		_pointer.on_motion(mm)
	var did := _gestures.handle(event, _rig, _repo, _ground_under, _pointer.empty_press())
	if did == WarRoomGestures.RIGHT_CLICK:
		_plan_right_click(mb.position)
		accept_event()
	elif did == WarRoomGestures.MOVED:
		_apply_camera()
		accept_event()
