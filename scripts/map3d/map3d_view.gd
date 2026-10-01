@tool
class_name Map3DView
extends Control
## The 3D map (owner 2026-09-18, the default map): an AUTHORED scene,
## scenes/map3d/world_map_3d.tscn (spec 2026-09-20 §2) — create() instances
## it, and on first activate _load() puts the BUILT world (tools/map3d; none
## in a fresh clone, which shows the Notice) under WorldSlot and binds the
## authored layers to it. Nothing generated is saved into the scene. A
## COORDINATOR: rig, input, picker, selection, layers and HUD do the work; the
## rest forwards to them under the API test_map3d_api.gd pins.
## It renders into a SubViewport at WINDOW resolution × the graphics tier's
## render_scale (Map3DQuality), shown by a TextureRect (Display) — never a
## SubViewportContainer, which under the canvas_items stretch renders at design
## size and blurs. Controls: the wheel and a pinch zoom about the pointer, a
## left, middle or two-finger drag pans, a right drag turns, WASD / arrows pan.

## The described entry of the settlement under a click ({title, obj}), or
## {} when the selection is cleared — WorldMapView's signal.
signal object_selected(entry: Dictionary)
## The province under a click, or "" for sea — WorldMapView's signal.
signal province_selected(province_code: String)
## The kingdom under the pointer, "" off the land — WorldMapView's signal:
## the screens put that country's card in the left column (owner 2026-09-18).
signal country_hovered(kingdom_code: String)
## A right CLICK (not a turn) on one of the player's regiments: ArmyOrderMenu
## opens over it. `at` is design px in this view.
signal army_menu_requested(code: String, at: Vector2)
## Where on the pack a left click landed — an order being AIMED needs the
## ground, not the thing picked.
signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
## A click on a committed march's end ring (owner 2026-09-27): ArmyOrderMenu's route menu (Map3DSelection emits it).
@warning_ignore("unused_signal") signal route_clicked(code: String, at: Vector2)
## A right click on open ground (owner 2026-09-28): SpyOrderMenu's "Send a spy here".
signal ground_menu_requested(pack_px: Vector2, at: Vector2)

const SCENE_PATTERN := "res://assets/3D/terrain/%s/world.tscn"
## The view's own authored scene (the tree, flags and anchors live there).
const VIEW_SCENE := "res://scenes/map3d/world_map_3d.tscn"
const NOTICE_TEXT := "The 3D map has not been built for this map.\nRun tools/map3d (see tools/map3d/README.md)."
## Aliases of the parts' constants, kept for the pinned API.
const SELECTED_RING_ALWAYS_M := Map3DLayerSettlements.SELECTED_RING_ALWAYS_M
const PRIORITY_SEA := Map3DPriority.SEA
const PRIORITY_RIVERS := Map3DPriority.RIVERS
const PRIORITY_ROADS := Map3DPriority.ROADS
const PRIORITY_MANOR_EDGES := Map3DPriority.MANOR_EDGES
const PRIORITY_KINGDOM_BAND := Map3DPriority.KINGDOM_BAND
const PRIORITY_SEAMS := Map3DPriority.SEAMS
const PRIORITY_KINGDOM_HALO := Map3DPriority.KINGDOM_HALO
const PRIORITY_KINGDOMS := Map3DPriority.KINGDOMS
const PRIORITY_HOVER := Map3DPriority.HOVER
const PRIORITY_SELECTION := Map3DPriority.SELECTION
const PRIORITY_CLOUDS := Map3DPriority.CLOUDS
const PRIORITY_RING_BASE := Map3DPriority.RING_BASE
const CLICK_SLOP := Map3DInput.CLICK_SLOP
const TOOLTIP_OFFSET := Map3DPicker.TOOLTIP_OFFSET
const FIELD_MAP_M_PER_TEXEL := Map3DLayerThemes.FIELD_MAP_M_PER_TEXEL

## EDITOR previews (Task 22): the pack a layer's `preview` draws ("" = the
## default) and whether it loads the terrain; nothing in a running game.
@export var preview_pack := ""
@export var preview_terrain := false

var _repo: DataRepository
var _scene_path := ""
@onready var _viewport: SubViewport = $Viewport
@onready var _world_slot: Node3D = $Viewport/WorldSlot
@onready var _rig: Map3DCameraRig = $Viewport/CameraRig
@onready var _sea: Map3DLayerSea = $Viewport/Sea
@onready var _rivers: Map3DLayerRivers = $Viewport/Rivers
@onready var _lines: Map3DLayerLines = $Viewport/Lines
@onready var _clouds: Map3DLayerClouds = $Viewport/Clouds
@onready var _markers: Map3DLayerSettlements = $Viewport/Markers
@onready var _houses: Map3DLayerHouses = $Viewport/Houses
@onready var _trees: Map3DLayerTrees = $Viewport/Trees
@onready var _units: Map3DLayerUnits = $Viewport/Units
@onready var _trails: Map3DLayerTrails = $Viewport/Trails
@onready var _couriers: Map3DLayerCouriers = $Viewport/Couriers
@onready var _env: WorldEnvironment = $Viewport/Environment
@onready var _sun: DirectionalLight3D = $Viewport/Sun
@onready var _fill_light: DirectionalLight3D = $Viewport/FillLight
@onready var _display: TextureRect = $Display
@onready var _notice: Label = $Notice
## The HUD waits hidden until a world loads; _load binds and shows it.
@onready var _hud: Map3DHud = $Hud
## The hover's name beside the cursor (owner 2026-09-18); Map3DPicker fills it.
@onready var _tooltip: Label = $Tooltip
var _world: Node3D
var _ctx: Map3DContext
var _roads := Map3DLayerRoads.new()
var _borders := Map3DLayerBorders.new()
## Made before _ready: a theme or a clear_hover may come before the first load.
var _themes := Map3DLayerThemes.new()
var _weather := Map3DLayerWeather.new()  # the weather's look (spec 2026-09-29-weather-visuals)
var _picker := Map3DPicker.new()
var _selection := Map3DSelection.new()
var _input := Map3DInput.new()
var _meta: Dictionary = {}
var _loaded := false
var _tried := false
var _hovered := false
var _border_clock := 0.0
## The regiments (owner 2026-09-19; always on since 2026-09-27, when the
## MILITARY tab went): whether the pieces and counters show.
var _military := true
## DEV MODE (owner 2026-09-27): every realm's regiments, set from the pause menu.
var _dev := false
## MEASUREMENT (owner 2026-09-18): left clicks lay the ruler, a right CLICK clears it.
var ruler_on := false:
	set(v):
		if v == ruler_on:
			return
		ruler_on = v
		_ruler.cancel()
		if _loaded:
			_hud.refresh()
var _ruler := MapRuler.new()
## The graphics tier worn ("" until the first load resolves one), overrides over it.
var _tier := ""
var _overrides: Dictionary = {}

## Where `map_id`'s built world lives: its maps.csv `map3d_dir` (default
## res://assets/3D/terrain/<id>), or SCENE_PATTERN when no repository is loaded.
static func scene_path_for(map_id: String) -> String:
	if Game.data != null and Game.data.maps.has(map_id):
		return Game.data.map3d_dir(map_id).path_join("world.tscn")
	return SCENE_PATTERN % map_id

## Whether `map_id`'s 3D world has been built (tools/map3d; git-ignored).
static func has_scene(map_id: String) -> bool: return ResourceLoader.exists(scene_path_for(map_id))

## Test seam: the world every view made from here on opens in place of the
## pack's build ("" the build) — GameRoot's tests open the empty fixture world.
static var world_override := ""
## A view of `repo`'s map, instanced from VIEW_SCENE; `scene_path` is a test seam.
static func create(repo: DataRepository, scene_path: String = "") -> Map3DView:
	var v := (load(VIEW_SCENE) as PackedScene).instantiate() as Map3DView
	v.name = "Map3DView"
	v._repo = repo
	v._scene_path = scene_path if scene_path != "" else (world_override if world_override != "" else scene_path_for(repo.map_id))
	return v

## THE map of a screen (the 2D map was deleted 2026-09-24): made once in the
## screen's _ready, put in `panel` and wired to its `detail`, `country` and
## `orders` and to `on_hover`; it loads the built world on its first activate().
static func attach(panel: Control, detail: MapDetailPanel = null, country: CountryPanel = null,
		on_hover: Callable = Callable(), orders: ArmyOrderMenu = null, given: Map3DView = null) -> Map3DView:
	var view := given if given != null else Map3DView.create(Game.data)  # given: the title's, already loaded
	panel.add_child(view)
	view.visible = false
	if detail != null:
		detail.follow(view)
		detail.closed.connect(view.clear_selection)
	if country != null:
		country.follow(view)
	if orders != null:
		orders.follow(view)
	if on_hover.is_valid():
		view.country_hovered.connect(func(_code: String) -> void: on_hover.call())
	return view

func _ready() -> void:
	Map3DPreview.bind_display(_display, _viewport)  # the editor keeps the scene's own
	if Engine.is_editor_hint(): return  # there the layers' `preview` switches do all the rest
	_notice.text = NOTICE_TEXT  # the scene's text is a preview; this is the one source
	_tooltip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	_tooltip.add_theme_font_size_override("font_size", 16)
	_tooltip.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_picker.tooltip = _tooltip
	_picker.kingdom_changed.connect(func(code: String) -> void: country_hovered.emit(code))
	_selection.object_selected.connect(func(e: Dictionary) -> void: object_selected.emit(e))
	_selection.province_selected.connect(func(c: String) -> void: province_selected.emit(c))
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void:
		_hovered = false
		clear_hover())
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)

## Window pixels per design px: the canvas_items stretch's scale, 1 headless.
func _window_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)

## SubViewport px per design px: the window's scale (× the tier's once loaded).
func _render_scale() -> float: return _ctx.viewport_px_scale() if _ctx != null else _window_scale()

## The SubViewport at the view's size in WINDOW px, one texel per real pixel.
func _fit_viewport() -> void:
	if _viewport == null:
		return
	var s := _render_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	if _ctx != null:
		_ctx.view_size = size
	if _loaded:  # a shorter view reads a longer scale bar: take the new ceiling
		_rig.place(_ctx.target, _ctx.distance, _ctx.yaw)
	_update_line_scale()

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
		_units.set_animating(true)
	_viewport.process_mode = Node.PROCESS_MODE_INHERIT
	set_process(_loaded)

func deactivate() -> void:
	visible = false
	_hovered = false
	clear_hover()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		# nothing under it runs while it draws nothing (perf 2026-10-02): the
		# figures' animations, the wind, the trees' and clouds' own processing
		_viewport.process_mode = Node.PROCESS_MODE_DISABLED
	if _loaded:
		_units.set_animating(false)
	set_process(false)

## Put the built world (Map3DWorldCache's kept one when free) under WorldSlot and
## bind the layers to it; a build it cannot open leaves the notice saying why.
func _load() -> void:
	var got: Variant = Map3DWorldCache.lend(_scene_path)
	if got is String:
		_notice.text = Map3DWorldLoader.notice_text(got, _repo.map_id)
		return
	_world = got
	_meta = _world.get_meta("map3d_world")
	_ctx = Map3DContext.new(_repo, _meta, _world)
	_ctx.viewport = _viewport
	_ctx.view_size = size
	_ctx.state_fn = get_meta("state_fn") if has_meta("state_fn") else func() -> GameState: return Game.state  # meta: the title's preview reign
	_ctx.clock_fn = func() -> int: return Game.clock_speed
	_ctx.day_fn = func() -> float: return Game.day_progress
	_ctx.window_scale_fn = _window_scale
	_tier = Map3DQuality.resolve_here(GameRoot.settings_path) if _tier == "" else _tier
	_ctx.quality = Map3DQuality.merged(_repo, _tier, _overrides)  # the layers read the steps
	_world_slot.add_child(_world)
	_rig.bind(_ctx)
	_input.bind(self, _rig, _repo)
	_markers.bind(_ctx)
	_houses.bind(_ctx)
	_ctx.dev = _dev
	_units.bind(_ctx)
	_trails.bind(_ctx)  # the ground the columns trod (owner 2026-10-01)
	_couriers.bind(_ctx)
	_units.set_shown(_military)
	_ctx.settle_ground()
	_markers.build()
	_houses.build()  # warm here (~91 ms), not on the first refresh() mid-play
	_trees.build(_ctx)  # once: fixed chunks, Godot's visibility ranges do the rest
	($Viewport/Wind as Map3DLayerWind).bind(_ctx)  # the waves and the sway; steps itself
	_sea.build(_ctx)
	# The sky and sun are the scene's, their numbers data (Task 14); the
	# environment is this view's own copy of the shared .tres.
	_env.environment = _env.environment.duplicate(true)
	Map3DEnvironment.apply_environment(_repo, _env.environment)
	Map3DEnvironment.apply_sun(_repo, _sun)
	_ctx.camera_moved.connect(func() -> void: Map3DEnvironment.follow_camera(_repo, _env.environment, _sun, _ctx))
	_clouds.build(_ctx, _weather)
	_lines.bind(_ctx)
	_roads.bind(_ctx, _lines, _viewport)
	Map3DLayerBake.build_layers(_ctx, _scene_path, _rivers, _roads)  # baked, or built now
	_borders.bind(_ctx, _lines)
	_themes.bind(_ctx, _lines)
	_themes.prepare(_scene_path)
	_weather.bind(_ctx, _themes.tint_material(), $Viewport/Precip as Map3DLayerPrecip, _houses)
	_picker.bind(_ctx, self, _tooltip, _borders)
	_selection.bind(_ctx, _lines, _markers, self)
	_loaded = true
	_rig.place(_home(), _rig.start_distance(), 0.0)
	_update_line_scale()
	_hud.bind(_ctx, self)  # the HUD redraws itself on every camera move
	_hud.visible = true
	_refresh_theme()  # a theme lit before the first load
	_apply_quality()

## Hand the world to Map3DWorldCache ahead of a queue_free (GameRoot's swap).
func release_world() -> void:
	if _world != null:
		deactivate()
		_loaded = false
		Map3DWorldCache.give_back(_scene_path, _world)
		_world = null

## The editor NEVER saves a preview (Task 22 review): whatever a preview
## switched on goes back before the scene is written — every layer's switch,
## the SubViewport's update mode, the built world and the Display's texture.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _world != null and not Engine.is_editor_hint():
		Map3DWorldCache.give_back(_scene_path, _world)
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		Map3DPreview.reset(self)

## Wear a graphics tier (Map3DQuality; `overrides` over single values — the
## bench's --render-scale). All of it applies now but the line, road and river
## steps, which wait for the layers' next build (Ruling 6).
func set_quality(tier: String, overrides: Dictionary = {}) -> void:
	_tier = tier
	_overrides = overrides
	_apply_quality()

func quality_tier() -> String: return _tier
func _apply_quality() -> void:
	if not _loaded:
		return
	_ctx.quality = Map3DQuality.merged(_repo, _tier, _overrides)
	_fit_viewport()  # the SubViewport's pixels, then every px uniform
	Map3DEnvironment.apply_view_quality(_viewport, _sun, _ctx.terrain, _ctx.quality,
		_repo, _env.environment)
	Map3DEnvironment.follow_camera(_repo, _env.environment, _sun, _ctx)
	_clouds.apply_quality(_ctx.quality)
	_weather.apply_quality(_ctx.quality)
	_hud.apply_quality(_ctx.quality)

func context() -> Map3DContext: return _ctx
func _home() -> Vector2: return _ctx.home()
func _burg_xz(burg: Dictionary) -> Vector2: return _ctx.to_world(Vector2(float(burg["x"]), float(burg["y"])))
func _height_at(xz: Vector2) -> float: return _ctx.height_at(xz) if _ctx != null else float(_meta.get("sea_y", 0.0))
func water_normals() -> Texture2D: return _ctx.water_normals() if _ctx != null else null
func sea_material() -> ShaderMaterial: return _sea.material() if _loaded else null
## Test seam: the Rivers layer's material (the palette colours go in raw).
func river_material() -> ShaderMaterial: return _rivers.material() if _loaded else null
func pick_reach_px(code: String, spec: Dictionary, dist_m: float) -> float: return _ctx.pick_reach_px(code, spec, dist_m)

## Rebuild the borders if ownership moved, and the theme, names and selection.
func refresh_borders() -> void:
	if not _loaded:
		return
	_refresh_theme()
	if _borders.refresh():
		_hud.refresh()
		_selection.redraw()

# --- the ground's themes (Map3DLayerThemes) ------------------------------------
static func load_field_map(scene_path: String) -> Texture2D: return Map3DLayerThemes.load_field_map(scene_path)

## "manors", "heights" or "" (GameRoot); leaving MANORS forgets the manor.
func set_manor_theme(theme_name: String) -> void:
	_themes.set_theme(theme_name)
	if theme_name != "manors":
		_selection.forget_manor()
	_refresh_theme()

func manor_theme() -> String: return _themes.theme()

func _refresh_theme() -> void:
	if _loaded:
		_themes.refresh()
		_hud.refresh()

func heat_on() -> bool: return _themes.heat_on()
## Every province under `kind` on the map ("" the real weather) — snapshot_screen --weather.
func set_weather_override(kind: String) -> void: _weather.set_override(kind)
func cell_lut() -> ImageTexture: return _themes.cell_lut()
func lut_color(id: int) -> Color: return _themes.lut_color(id)

# --- roads and bridges (Map3DLayerRoads) -----------------------------------------
func bridge_rules() -> Dictionary: return _roads.bridge_rules()
func bridges() -> Array: return _roads.bridges()

## The lines' and rings' screen-px values in WINDOW px — on load, resize.
func _update_line_scale() -> void:
	if _repo == null or not _loaded:
		return
	_lines.apply_scale()
	_markers.apply_scale()
	_rivers.apply_scale()

# --- camera and input (Map3DCameraRig, Map3DInput, Map3DPicker) -------------------
## Ground metres under one screen pixel at the target — the HUD's scale bar.
func metres_per_pixel() -> float:
	return _ctx.metres_per_pixel() if _ctx != null else Map3DGeometry.metres_per_pixel(
		1.0, _repo.bal("map3d_fov_deg"), maxf(size.y, 1.0))

func _pan_by(screen_delta: Vector2) -> void:
	if _loaded:
		_rig.pan_by(screen_delta)

func _zoom_at(pos: Vector2, new_distance: float) -> void:
	if _loaded:
		_rig.zoom_at(pos, new_distance)

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _loaded:
		return
	# the frame's moves are told to the listeners once, in _process (rig.flush);
	# a click is picked against what they placed, so they hear first
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		_rig.flush()
	_rig.hold_moved = true
	var took := _input.handle(event)
	_rig.hold_moved = false
	if took:
		accept_event()

## The rig's ease, the border poll, the clouds, the hover, and WASD / arrows.
func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if _loaded:
		_rig.flush()  # the input's moves this frame, told once
		_rig.step(delta)
	_border_clock += delta
	if _border_clock >= _repo.bal("map3d_border_refresh_s"):
		_border_clock = 0.0
		refresh_borders()
	if _loaded:
		_weather.step()
		_clouds.step(delta)
		if _units.step(delta): _hud.refresh()  # chips hang over walking pieces
		_trails.step()  # behind them, the ground they trod
		if _couriers.step(delta): _hud.refresh()  # the couriers' roads and counters follow them
		Map3DEnvironment.sweep_sun(_repo, _sun, Game.day_progress, _fill_light)  # a round a game day, the north half dusk
	_picker.step()
	if not _hovered:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if _input.key_pan(delta):
		_picker.repick()  # the ground moved under a still pointer

func request_hover(pos: Vector2) -> void: _picker.request(pos)

func refresh_hud() -> void: if _loaded: _hud.refresh()

func compass_rect() -> Rect2: return _hud.compass_rect() if _loaded else Rect2()

# --- ruler ---------------------------------------------------------------------
## A ruler click at `pos` (design px): the ground under it, or nothing on the sky.
func ruler_click(pos: Vector2) -> void:
	var hit: Variant = ground_at(pos)
	if hit == null:
		return
	_ruler.click(Vector2((hit as Vector3).x, (hit as Vector3).z))
	if _loaded:
		_hud.refresh()

func _ruler_click(pos: Vector2) -> void: ruler_click(pos)
func ruler_reading() -> String: return MapRuler.reading(_ruler.length() * map_units_per_metre(), map_unit())

## The 3D map MEASURES LIKE THE 2D MAP (owner 2026-09-18; Map3DGeometry).
func map_units_per_metre() -> float: return Map3DGeometry.map_units_per_metre(_repo.map_info, _meta)
func map_unit() -> String: return Map3DGeometry.map_unit(_repo.map_info, _meta)
func ruler() -> MapRuler: return _ruler

# --- the HUD's pieces (Map3DHud: one per job) -------------------------------------
func label_entries() -> Array: return (_hud.piece("Labels") as Map3DHudLabels).entries() if _loaded else []
func drawn_labels() -> PackedStringArray:
	return (_hud.piece("Labels") as Map3DHudLabels).drawn() if _loaded else PackedStringArray()
func manor_badges() -> Array: return (_hud.piece("Badges") as Map3DHudBadges).badges() if _loaded else []
func drawn_badge_count() -> int: return (_hud.piece("Badges") as Map3DHudBadges).drawn_count() if _loaded else 0
func army_badge_height() -> float:
	return (_hud.piece("Armies") as Map3DHudArmies).badge_height() if _loaded else 0.0
func army_markers() -> Array: return (_hud.piece("Armies") as Map3DHudArmies).markers() if _loaded else []
func route_ends() -> Array: return (_hud.piece("Armies") as Map3DHudArmies).route_ends() if _loaded else []
func drawn_army_count() -> int: return (_hud.piece("Armies") as Map3DHudArmies).drawn_count() if _loaded else 0
func landmark_marks() -> Array: return (_hud.piece("Landmarks") as Map3DHudLandmarks).marks() if _loaded else []
func heat_legend_rect() -> Rect2:
	return (_hud.piece("HeatLegend") as Map3DHudHeatLegend).rect() if _loaded else Rect2()
func heat_legend_ticks() -> Array:
	return (_hud.piece("HeatLegend") as Map3DHudHeatLegend).ticks() if _loaded else []
func heat_legend_yields() -> bool:
	return (_hud.piece("HeatLegend") as Map3DHudHeatLegend).yields() if _loaded else false

# --- MILITARY (owner 2026-09-19) ---------------------------------------------------
## The player's regiments as counters — GameRoot hands it down with the tab.
func set_military(on: bool) -> void:
	_military = on
	if not on and _selection.army != "":
		_selection.clear()
	if _loaded:
		_units.set_shown(on)
		_hud.refresh()

# MILITARY's 3D pieces: heads (the chip hangs there), boxes (clicks), count, motion.
func unit_tops() -> Dictionary: return _units.screen_tops() if _loaded else {}
func unit_positions() -> Dictionary: return _units.shown_positions() if _loaded else {}
func unit_rects() -> Dictionary: return _units.screen_rects() if _loaded else {}
func unit_count() -> int: return _units.drawn_count() if _loaded else 0
func unit_moves() -> int: return _units.moves() if _loaded else 0
func courier_rects() -> Dictionary: return _couriers.screen_rects() if _loaded else {}

func military() -> bool: return _military

## DEV MODE (the pause menu's switch, owner 2026-09-27): every realm's regiments.
func set_dev_mode(on: bool) -> void:
	_dev = on
	if _loaded:
		_ctx.dev = on
		_units.refresh()
		_hud.refresh()

func dev_mode() -> bool: return _dev
func selected_army() -> String: return _selection.army

# --- picking (Map3DPicker, Map3DSelection) --------------------------------------------
func ground_at(pos: Vector2) -> Variant: return _ctx.ground_at(pos) if _ctx != null else null
func pick_at(pos: Vector2) -> Dictionary: return _picker.pick_at(pos) if _loaded else {}
static func kingdom_of_pick(repo: DataRepository, state: GameState, picked: Dictionary) -> String:
	return Map3DPicker.kingdom_of_pick(repo, state, picked)
func hover_pick(picked: Dictionary, pos: Vector2) -> void: _picker.hover_pick(picked, pos)
func clear_hover() -> void: _picker.clear_hover()
func hovered_kingdom() -> String: return _picker.hovered_kingdom()
func hover_tooltip() -> String: return _picker.hover_tooltip()
func tooltip_rect() -> Rect2: return _picker.tooltip_rect()
## While an order is aimed (ArmyOrderMenu sets both): a left click only says
## where it landed, and the HUD's ruler runs from `aim_code`'s piece to the pointer.
var aiming := false
var aim_code := "":
	set(v):
		aim_code = v
		if _loaded: _hud.refresh()  # the aim's ruler goes, the committed route shows
## The aimed march's destination (pack px) while COMMIT / CANCEL is asked, else (-1, -1).
var aim_dest := Vector2(-1, -1)

## True when a regiment was under it (its order menu opens) or the ground was
## hit (SpyOrderMenu's "Send a spy here" opens); false only over the sky.
func right_click(pos: Vector2) -> bool:
	var picked := pick_at(pos)
	if String(picked.get("kind", "")) == "army":
		army_menu_requested.emit(String(picked["code"]), pos)
		return true
	var hit: Variant = ground_at(pos)
	if hit == null:
		return false
	ground_menu_requested.emit(_ctx.to_pack(Vector2((hit as Vector3).x, (hit as Vector3).z)), pos)
	return true

func select_at(pos: Vector2) -> void:
	var hit: Variant = ground_at(pos)
	var at: Variant = null if hit == null else (_ctx.to_pack(Vector2((hit as Vector3).x, (hit as Vector3).z)) as Variant)
	var was_aiming := aiming  # the click that ends an aim selects nothing
	if at != null: ground_clicked.emit(at, pos)
	if not was_aiming: _selection.click(pick_at(pos), pos)
func clear_selection() -> void: _selection.clear()
func select_object(picked: Dictionary) -> void: if _loaded: _selection.select(picked)  # the Manor Master

## Test seam (Ruling 18): the inner part named `key`, or null.
func component(key: String) -> Object:
	return {"roads": _roads, "borders": _borders, "themes": _themes, "weather": _weather, "input": _input,
		"rig": _rig, "picker": _picker, "selection": _selection}.get(key)

# --- test seams and the bench -------------------------------------------------------
func is_loaded() -> bool: return _loaded
func notice() -> Label: return _notice
func viewport() -> SubViewport: return _viewport
func camera() -> Camera3D: return _rig.camera() if _loaded else null
func cloud_count() -> int: return _clouds.count() if _loaded else 0
func target() -> Vector2: return _ctx.target if _ctx != null else Vector2.ZERO
func distance() -> float: return _ctx.distance if _ctx != null else 1.0
func yaw() -> float: return _ctx.yaw if _ctx != null else 0.0
func selected_province() -> String: return _selection.province
func selected_burg() -> String: return _selection.burg
func selected_manor() -> int: return _selection.manor
func selected_ring_visible() -> bool: return _loaded and _markers.selected_visible()

func look_at_pack(pack_px: Vector2, at_distance: float = -1.0) -> void:
	if _loaded:
		_rig.place(_ctx.to_world(pack_px), at_distance if at_distance > 0.0 else _ctx.distance, _ctx.yaw)

func look_at_home(at_distance: float) -> void: if _loaded: _rig.place(_home(), at_distance, _ctx.yaw)

## Layers the bench can switch off to price them.
func layer_names() -> PackedStringArray:
	var out := PackedStringArray()
	if _loaded:
		out.append_array(["Markers", "Houses", "Trees", "Lines", "Clouds", "Precip"])
		out.append_array(["Rivers"] if _rivers.mesh != null else [])
		out.append_array(["Sea"] if _sea.has_water() else [])
	out.append_array(["Shadows", "Hud"] if _loaded else [])
	return out

func set_layer_visible(layer: String, on: bool) -> void:
	match layer:
		"Shadows":
			_sun.shadow_enabled = on
		"Sea":
			_sea.visible = on
		"Hud":
			_hud.visible = on
		_:
			(_viewport.get_node(layer) as Node3D).visible = on

func line_mesh(line_name: String) -> ArrayMesh: return _lines.line_mesh(line_name) if _loaded else null
func marker_counts() -> Dictionary: return _markers.counts() if _loaded else {}
func house_counts() -> Dictionary: return _houses.counts() if _loaded else {}
