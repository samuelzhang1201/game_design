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
##
## Zoom runs 800 m (a village and its fields) to 150 km (the whole island
## with sea around it — owner 2026-09-19, was 80 km); the wheel and a macOS trackpad pinch
## both zoom about the pointer, not the view's centre, and a two-finger
## trackpad drag pans the ground. Settlements draw as screen-constant hollow
## solid black dots, the capital's with a ring round it (owner 2026-09-19;
## settlement_ring.gdshader, data/map3d_settlements.csv: dot_px, ring_px,
## line_px, colour, max_view_m per tier), thinned by distance and picked in
## screen space (map3d_pick_px); a click gets a gold selection ring that
## never thins. Map3DHud draws the scale bar (ScaleBar, the 2D map's own
## drawing, in the 2D map's own measure — see map_units_per_metre) and a
## north-pointing compass, top-left, that turns with the view and eases back
## to north on a click.
##
## The ground is the bake's own coverage-and-control maps (tools/map3d/
## bake_world.py, tuned by data/map3d_bake.csv): coasts.csv loops
## rasterised into a supersampled coast coverage, warped biome edges, a
## dithered blend byte, heights ramped through the shore. Rivers are carved
## into that same heightmap and their courses (source to sea mouths) written
## to rivers.json beside the built scene, drawn here as one ribbon mesh by
## Map3DRivers + water_river.gdshader. The sea is water_sea.gdshader, dressed
## onto the build's Sea plane at runtime with the 2D map's own four bands.
## Clouds are Map3DCloudField (pure) + cloud_deck.gdshader, casting soft
## shadows through a separate cloud_shadow.gdshader twin — kept apart
## because a shader that so much as mentions ALPHA_SCISSOR_THRESHOLD
## anywhere blanks the whole material's blended rendering under GL
## Compatibility. tools/map3d/bench.gd polices all of it at an 8 ms budget
## (60 fps) through the real view.

## The described entry of the settlement under a click ({title, obj}), or
## {} when the selection is cleared — WorldMapView's signal.
signal object_selected(entry: Dictionary)
## The province under a click, or "" for sea — WorldMapView's signal.
signal province_selected(province_code: String)
## The kingdom under the pointer, "" off the land — WorldMapView's signal:
## the screens put that country's card in the left column (owner 2026-09-18).
signal country_hovered(kingdom_code: String)

const SCENE_PATTERN := "res://assets/map3d/%s/world.tscn"
const NOTICE_TEXT := "The 3D map has not been built for this map.\nRun tools/map3d (see tools/map3d/README.md)."
## The selection ring never thins by distance (fix round 1, owner 2026-09-18):
## whatever the player clicked stays marked regardless of zoom. Alias of
## Map3DLayerSettlements.SELECTED_RING_ALWAYS_M, pinned by test_map3d_api.gd.
const SELECTED_RING_ALWAYS_M := Map3DLayerSettlements.SELECTED_RING_ALWAYS_M
## The render-priority table lives in Map3DPriority; these are its aliases.
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
## A press and release further apart than this is a drag, not a click
## (WorldMapView.CLICK_SLOP).
const CLICK_SLOP := Map3DInput.CLICK_SLOP
## Where the name sits off the cursor (WorldMapView.TOOLTIP_OFFSET).
const TOOLTIP_OFFSET := Vector2(20.0, 24.0)
## Metres per texel of the bake's field map (Map3DLayerThemes).
const FIELD_MAP_M_PER_TEXEL := Map3DLayerThemes.FIELD_MAP_M_PER_TEXEL

var _repo: DataRepository
var _scene_path := ""
var _display: TextureRect
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _markers: Map3DLayerSettlements
var _lines: Map3DLayerLines
var _notice: Label
var _ctx: Map3DContext
var _rivers: Map3DLayerRivers
var _sea: Map3DLayerSea
var _roads := Map3DLayerRoads.new()
var _borders := Map3DLayerBorders.new()
## MANORS and HEIGHTS on the ground (Map3DLayerThemes): made here, before
## _ready, so a theme handed down before the first load is held.
var _themes := Map3DLayerThemes.new()
var _meta: Dictionary = {}
var _rig: Map3DCameraRig
var _input := Map3DInput.new()
var _loaded := false
var _tried := false
var _hovered := false
var _province_image: Image
var _cell_image: Image
var _selected_province := ""
var _selected_burg := ""
## The clicked manor under a theme (-1 for none), outlined in gold.
var _selected_manor := -1
var _border_clock := 0.0
var _hud: Map3DHud
## The hover (owner 2026-09-18): a pointer move is only recorded, and picked
## once a frame in _process; the pick's kingdom, its settlement (the
## tooltip); the outline itself is Map3DLayerBorders'.
var _hover_pos := Vector2.ZERO
var _hover_pending := false
var _hover_kingdom := ""
var _hover_obj: Dictionary = {}
var _tooltip: Label
## The kingdoms the HUD lettered on its last draw (a test seam).
var _drawn_labels: PackedStringArray = []
## How many MANORS output badges the HUD drew last (a test seam).
var _drawn_badges := 0
## MILITARY on the 3D map (owner 2026-09-19): whether the counters show, the
## clicked regiment (outlined in gold), and how many the HUD drew last.
var _military := false
var _selected_army := ""
var _drawn_armies := 0
## landmark_marks' cut and the pose it was cut for (see there).
var _landmark_cache: Array = []
var _landmark_key: Array = []
## The MEASUREMENT tab (owner 2026-09-18): while on, a left click drops or
## fixes the ruler (world XZ metres) instead of picking, and a right CLICK —
## not the right-drag that turns the view — puts it away. The HUD draws it.
var ruler_on := false:
	set(v):
		if v == ruler_on:
			return
		ruler_on = v
		_ruler.cancel()
		if _hud != null:
			_hud.refresh()
var _ruler := MapRuler.new()
var _clouds: Map3DLayerClouds


static func scene_path_for(map_id: String) -> String:
	return SCENE_PATTERN % map_id


## Whether `map_id`'s 3D scene has been built (tools/map3d; git-ignored, so a
## fresh clone has none and GameRoot keeps the 2D map).
static func has_scene(map_id: String) -> bool:
	return ResourceLoader.exists(scene_path_for(map_id))


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
## and `country` card the way the 2D map is, and calls `on_hover` when the
## hovered country changes (the screen re-orders its left column). Returns the view, or null if none was ever needed.
static func toggle_in(panel: Control, world_map: Control, view: Map3DView, on: bool,
		detail: MapDetailPanel = null, country: CountryPanel = null,
		on_hover: Callable = Callable()) -> Map3DView:
	if on and view == null:
		view = Map3DView.create(Game.data)
		panel.add_child(view)
		if detail != null:
			detail.follow(view)
			detail.closed.connect(view.clear_selection)
		# The hovered country's card, as the 2D map's hover gives it; then
		# the screen re-orders its left column around it.
		if country != null:
			country.follow(view)
		if on_hover.is_valid():
			view.country_hovered.connect(func(_code: String) -> void: on_hover.call())
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
	_tooltip = Label.new()
	_tooltip.name = "Tooltip"
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	_tooltip.add_theme_font_size_override("font_size", 16)
	_tooltip.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_tooltip.hide()
	add_child(_tooltip)
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


## SubViewport px per design px: the window's scale times the graphics tier's
## render scale once the world is loaded, the window's alone before.
func _render_scale() -> float:
	return _ctx.viewport_px_scale() if _ctx != null else _window_scale()


## The SubViewport at the view's size in WINDOW pixels; the TextureRect
## shows it back at design size, one texel per real pixel.
func _fit_viewport() -> void:
	if _viewport == null:
		return
	var s := _render_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	if _ctx != null:
		_ctx.view_size = size
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
	clear_hover()
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
	_ctx = Map3DContext.new(_repo, _meta, _world)
	_ctx.camera_moved.connect(refresh_hud)
	_ctx.viewport = _viewport
	_ctx.view_size = size
	_ctx.state_fn = func() -> GameState: return Game.state
	_ctx.clock_fn = func() -> int: return Game.clock_speed
	_ctx.window_scale_fn = _window_scale
	# Each view its OWN terrain material: the loaded scene's material is a
	# shared resource, so the council screen's view and the court's patched
	# and set the same one, and the first view's teardown left the second's
	# ground untinted (owner 2026-09-19: no MANORS tint in the game).
	for t in _world.find_children("*", "Terrain3D", true, false):
		var m: Resource = t.get("material")
		if m != null:
			t.set("material", m.duplicate(true))
	_viewport.add_child(_world)
	# The build's own framing cameras are for tools/map3d/shoot.gd.
	for child in _world.get_children():
		if child is Camera3D:
			(child as Camera3D).current = false
	_rig = Map3DCameraRig.new()
	_rig.name = "CameraRig"
	_viewport.add_child(_rig)
	_rig.bind(_ctx)
	_camera = _rig.camera()
	_input.bind(self, _rig, _repo)
	_markers = Map3DLayerSettlements.new()
	_markers.name = "Markers"
	_viewport.add_child(_markers)
	_markers.bind(_ctx)
	_ctx.settle_ground()
	_markers.build()
	_sea = Map3DLayerSea.new()
	_sea.name = "Sea"
	_viewport.add_child(_sea)
	_sea.build(_ctx)
	_rivers = Map3DLayerRivers.new()
	_rivers.name = "Rivers"
	_viewport.add_child(_rivers)
	_rivers.build(_ctx, _scene_path)
	var sun := _world.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		Map3DEnvironment.apply_sun_look(_repo, sun)
	_clouds = Map3DLayerClouds.new()
	_clouds.name = "Clouds"
	_viewport.add_child(_clouds)
	_clouds.build(_ctx)
	_lines = Map3DLayerLines.new()
	_lines.name = "Lines"
	_viewport.add_child(_lines)
	_lines.bind(_ctx)
	_roads.bind(_ctx, _lines, _viewport)
	_roads.build(_rivers.courses())
	_borders.bind(_ctx, _lines)
	_themes.bind(_ctx, _lines)
	_themes.prepare(_scene_path)
	_loaded = true
	_rig.place(_home(), _repo.bal("map3d_zoom_start_m"), 0.0)
	_update_line_scale()
	_hud = Map3DHud.new()
	_hud.view = self
	add_child(_hud)
	move_child(_tooltip, -1)  # the name over the scale bar and compass
	_refresh_theme()  # a theme lit before the first load


func _state() -> GameState:
	return Game.state


## What the layers share (Map3DContext): null until the world has loaded.
func context() -> Map3DContext:
	return _ctx


## The player's capital, or the map's centre when no realm is bound.
func _home() -> Vector2:
	var realm: Dictionary = _repo.kingdoms.get(_repo.resolve_realm("player_realm"), {})
	var burg: Dictionary = _repo.burgs.get(String(realm.get("capital_burg", "")), {})
	if burg.is_empty():
		return _ctx.bounds.get_center()
	return _burg_xz(burg)


func _burg_xz(burg: Dictionary) -> Vector2:
	return _ctx.to_world(Vector2(float(burg["x"]), float(burg["y"])))


## Ground height at a world XZ: the terrain's when it has data, never below
## the sea plane (Map3DContext.height_at).
func _height_at(xz: Vector2) -> float:
	return _ctx.height_at(xz) if _ctx != null else float(_meta.get("sea_y", 0.0))


## The ripple normal map both waters share (Map3DContext.water_normals).
func water_normals() -> Texture2D:
	return _ctx.water_normals() if _ctx != null else null


func sea_material() -> ShaderMaterial:
	return _sea.material() if _sea != null else null


## Test seam (fix round 1): the Rivers layer's material, to check the
## palette colours went in raw.
func river_material() -> ShaderMaterial:
	return _rivers.material() if _rivers != null else null


## A settlement's size on screen, design px: its ring, else its dot.
static func marker_px(spec: Dictionary) -> float:
	return Map3DLayerSettlements.marker_px(spec)


## Show the gold ring on a burg (or hide it with "").
func _show_selected_ring(code: String) -> void:
	if _markers != null:
		_markers.show_selected(code)


# --- borders -----------------------------------------------------------------

## Rebuild the kingdom borders and province seams if ownership moved since
## they were built (Map3DLayerBorders), and what follows the land held.
func refresh_borders() -> void:
	if not _loaded:
		return
	_refresh_theme()  # a manor bought or a province taken recolours the ground
	if _borders.refresh():
		if _hud != null:
			_hud.refresh()  # the names follow the land held
		_draw_selection()


# --- the MANORS theme -------------------------------------------------------------

## The bake's field map beside a built scene, or null (Map3DLayerThemes).
static func load_field_map(scene_path: String) -> Texture2D:
	return Map3DLayerThemes.load_field_map(scene_path)


## Show a theme on the 3D ground: "manors", "heights", or "" for none —
## GameRoot hands it down with the 2D map's show_manors / show_heights.
func set_manor_theme(theme_name: String) -> void:
	_themes.set_theme(theme_name)
	# A manor is picked only under MANORS: leaving it forgets the clicked
	# manor and its gold outline.
	if theme_name != "manors" and _selected_manor >= 0:
		_selected_manor = -1
		if _loaded:
			_draw_selection()
	_refresh_theme()


func manor_theme() -> String:
	return _themes.theme()


## The theme on the ground (Map3DLayerThemes), and the HUD that follows it.
func _refresh_theme() -> void:
	if _loaded:
		_themes.refresh()
	if _hud != null:
		_hud.refresh()


## Test seam: whether the HEIGHTS heat is on the ground.
func heat_on() -> bool:
	return _themes.heat_on()


## Test seam: the LUT the terrain shader reads (null before the first theme).
func cell_lut() -> ImageTexture:
	return _themes.cell_lut()


## Test seam: the colour the LUT holds for cell `id` (clear before a theme).
func lut_color(id: int) -> Color:
	return _themes.lut_color(id)


## balance.csv map3d_bridge_* as Map3DBridges' rules (Map3DLayerRoads owns
## the roads and bridges; this and bridges() forward to it — Ruling: the
## public Map3DView API is kept for the whole plan).
func bridge_rules() -> Dictionary:
	return _roads.bridge_rules()


## Test seam: every bridge built, [{a, b, ya, yb, crown, water_y, width, deck_w}].
func bridges() -> Array:
	return _roads.bridges()


## One MeshInstance3D of ribbons under Lines/<name>, replacing any before.
## `priority` is the line's row of the render-priority table (PRIORITY_*);
## `edge_soft` fades the ribbon toward its sides (border_line.gdshader);
## `one_sided` lays it from the line to one side (Map3DBorders.ribbon_arrays),
## `colours` a Color per line drawn in place of `a`'s rgb, and `fade_across`
## fades it away from the line (the realm band) by the curve `fade_power_key`
## names in balance.csv ("" linear).
func _set_lines(line_name: String, lines: Array, a: Color, b: Color, width_key: String,
		dash_key: String, gap_key: String, priority: int, edge_soft := 0.0,
		one_sided := false, colours: Array = [], fade_across := 0.0,
		fade_power_key := "") -> void:
	var st := Map3DLineStyle.dashed(a, b, width_key, dash_key, gap_key, priority)
	st.edge_soft = edge_soft
	st.one_sided = one_sided
	st.colours = colours
	st.fade_across = fade_across
	st.fade_power_key = fade_power_key
	_lines.set_lines(line_name, lines, st)


## The lines' and rings' screen-px values in WINDOW px, and the metres per px
## per metre of distance — on load, resize and new lines.
func _update_line_scale() -> void:
	if _repo == null or _viewport == null:
		return
	if _lines != null:
		_lines.apply_scale()
	if _markers != null:
		_markers.apply_scale()
	if _rivers != null:
		_rivers.apply_scale()


## The clicked province's outline — or, under a theme, the clicked manor's
## — solid gold over the borders.
func _draw_selection() -> void:
	var lines: Array = []
	if _selected_manor >= 0 and _repo.cells.has(_selected_manor):
		var pts := PackedVector2Array()
		for vid in (_repo.cells[_selected_manor]["vertex_ids"] as PackedInt32Array):
			pts.append(Map3DGeometry.pack_to_world(_meta, _repo.vertices[vid] as Vector2))
		if pts.size() >= 3:
			pts.append(pts[0])
			lines.append(Map3DGeometry.resample(pts, _repo.bal("map3d_line_step_m")))
	elif _selected_province != "":
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
	_set_lines("Selection", lines, gold, gold, "map3d_selection_width_px", "", "", PRIORITY_SELECTION)


# --- camera and input ----------------------------------------------------------

## Ground metres under one screen pixel at the target (Map3DContext).
func _metres_per_pixel() -> float:
	return _ctx.metres_per_pixel() if _ctx != null else Map3DGeometry.metres_per_pixel(
		1.0, _repo.bal("map3d_fov_deg"), maxf(size.y, 1.0))

## Ground metres under one screen pixel at the target — the HUD's scale bar.
func metres_per_pixel() -> float:
	return _metres_per_pixel()


## Map3DCameraRig.pan_by.
func _pan_by(screen_delta: Vector2) -> void:
	if _rig != null:
		_rig.pan_by(screen_delta)


## Zoom to `new_distance` (clamped) keeping the ground under `pos` under it
## (Map3DCameraRig.zoom_at).
func _zoom_at(pos: Vector2, new_distance: float) -> void:
	if _rig != null:
		_rig.zoom_at(pos, new_distance)


## Map3DInput.handle says which events the view takes.
func _gui_input(event: InputEvent) -> void:
	if not _loaded:
		return
	if _input.handle(event):
		accept_event()


## The compass's ease, the border poll, the clouds, the hover picked once a
## frame, and WASD / arrows while the pointer is over the view and no text
## box has the keyboard.
func _process(delta: float) -> void:
	if _rig != null:
		_rig.step(delta)
	_border_clock += delta
	if _border_clock >= _repo.bal("map3d_border_refresh_s"):
		_border_clock = 0.0
		refresh_borders()
	if _clouds != null:
		_clouds.step(delta)
	if _hover_pending:
		_hover_pending = false
		hover_pick(pick_at(_hover_pos), _hover_pos)
	if not _hovered:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if _input.key_pan(delta):
		_hover_pending = true  # the ground moved under a still pointer


## Map3DInput: pick the hover at `pos` on the next frame.
func request_hover(pos: Vector2) -> void:
	_hover_pos = pos
	_hover_pending = true


## Redraw the HUD (compass, scale bar, labels, ruler); on every camera move.
func refresh_hud() -> void:
	if _hud != null:
		_hud.refresh()


## The compass's screen rect (design px), empty before the HUD exists.
func compass_rect() -> Rect2:
	return _hud.compass_rect() if _hud != null else Rect2()


# --- ruler ---------------------------------------------------------------------

## A ruler click at `pos` (design px): the ground under it, or nothing on the sky.
func _ruler_click(pos: Vector2) -> void:
	var hit: Variant = ground_at(pos)
	if hit == null:
		return
	_ruler.click(Vector2((hit as Vector3).x, (hit as Vector3).z))
	if _hud != null:
		_hud.refresh()


## The ruler on the HUD (design px): its ends on the ground, projected; the
## reading is the HORIZONTAL ground distance in the pack's own measure
## (map_units_per_metre), so it matches the 2D map's ruler; ticks on the
## 1-2-5 step at the target's scale, placed along the 3D line so
## perspective spaces them as the ground does.
func draw_ruler(ci: CanvasItem) -> void:
	if not ruler_on or not _ruler.active() or _camera == null:
		return
	var a3 := Vector3(_ruler.start.x, _height_at(_ruler.start), _ruler.start.y)
	var b3 := Vector3(_ruler.end.x, _height_at(_ruler.end), _ruler.end.y)
	if _camera.is_position_behind(a3) or _camera.is_position_behind(b3):
		return
	var s := _render_scale()
	var k := map_units_per_metre()
	var total := _ruler.length() * k
	var step := MapRuler.tick_step(_metres_per_pixel() * k, _repo.bal("map_ruler_tick_min_px"))
	var ticks := PackedVector2Array()
	for d in MapRuler.ticks(total, step):
		ticks.append(_camera.unproject_position(a3.lerp(b3, d / total)) / s)
	MapRuler.draw(ci, _camera.unproject_position(a3) / s, _camera.unproject_position(b3) / s,
		ticks, ruler_reading())


## The kingdom names (owner 2026-09-18, the 2D map's lettering): one entry
## {code, text, pos (design px), px} per kingdom whose LIVE label anchor
## (MapOwnership.label_anchor) is before the camera and whose word —
## map_label_scale_px pack px tall on the ground, seen from its own distance —
## reaches map_label_min_px; capped at map_label_max_px.
func label_entries() -> Array:
	var out: Array = []
	if _camera == null:
		return out
	var s := _render_scale()
	var height_m := _repo.bal("map_label_scale_px") * float(_meta.get("m_per_px", 0.0))
	var eye := _camera.global_position
	for code: String in _repo.kingdoms:
		var xz := Map3DGeometry.pack_to_world(_meta, MapOwnership.label_anchor(_repo, _state(), code))
		var ground := Vector3(xz.x, _height_at(xz), xz.y)
		if _camera.is_position_behind(ground):
			continue
		var mpp := Map3DGeometry.metres_per_pixel(eye.distance_to(ground),
			_repo.bal("map3d_fov_deg"), maxf(size.y, 1.0))
		var px := Map3DGeometry.label_px(height_m, mpp, _repo.bal("map_label_min_px"),
			_repo.bal("map_label_max_px"))
		if px <= 0.0:
			continue
		out.append({"code": code, "text": String(_repo.kingdoms[code]["label"]),
			"pos": _camera.unproject_position(ground) / s, "px": px})
	return out


## Letter the names on the HUD (Map3DHud._draw), upright and faint, the way
## the 2D map letters them (MapLettering).
func draw_labels(ci: CanvasItem) -> void:
	_drawn_labels.clear()
	var font := UiPalette.map_label_font()
	if font == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	for e: Dictionary in label_entries():
		if MapLettering.draw_centred(ci, _repo, font, String(e["text"]), e["pos"],
				float(e["px"]), frame):
			_drawn_labels.append(String(e["code"]))


## The MANORS view's output badges (owner 2026-09-19, the 2D map's — ManorBadges):
## the working manors (MapEconomy.manors) before the camera whose settlement
## passes the 2D map's town LOD rule at the scale it is SEEN at (screen px
## per pack px at its own distance), in design px, biggest producer first;
## a badge that would overlap a bigger one is left off. [] off the theme.
func manor_badges() -> Array:
	if _themes.theme() != "manors" or _camera == null:
		return []
	var s := _render_scale()
	var m_per_pack := float(_meta.get("m_per_px", 50.0))
	var fov := _repo.bal("map3d_fov_deg")
	var h := maxf(size.y, 1.0)
	var eye := _camera.global_position
	var frame := Rect2(Vector2.ZERO, size).grow(_repo.bal("map_manor_badge_px") * 2.0)
	var all := MapEconomy.manors(_repo)
	var out: Array = []
	for id: int in all:
		var m: Dictionary = all[id]
		var ground := _ctx.cell_ground(id)
		if _camera.is_position_behind(ground):
			continue
		var center := _camera.unproject_position(ground) / s
		if not frame.has_point(center):
			continue
		var seen := m_per_pack / Map3DGeometry.metres_per_pixel(eye.distance_to(ground), fov, h)
		var min_pop := MapObjects.min_burg_pop_for_scale(_repo, seen)
		var burg := ""
		for code: String in m["burgs"]:
			if MapObjects.burg_visible(_repo.burgs[code], min_pop):
				burg = code
				break
		if burg == "":
			continue
		out.append({"cell": id, "burg": burg, "good": String(m["good"]),
			"units": float(m["units"]), "center": center})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["units"] == b["units"]:
			return int(a["cell"]) < int(b["cell"])
		return a["units"] > b["units"])
	var target_scale := m_per_pack / _metres_per_pixel()
	return ManorBadges.place(_repo, out, target_scale >= _repo.bal("map_manor_label_min_scale"))


# --- MILITARY (owner 2026-09-19) ---------------------------------------------------

## Show the player's regiments as counters — GameRoot hands this down with
## the MILITARY tab, as the 2D map's show_armies.
func set_military(on: bool) -> void:
	_military = on
	if not on and _selected_army != "":
		clear_selection()
	if _hud != null:
		_hud.refresh()


func military() -> bool:
	return _military


## A counter's height in design px: map_army_badge_native_px of the map at
## the scale the target is seen at (as the 2D counter grows with the zoom),
## held between map3d_army_badge_min_px and map3d_army_badge_max_px so it
## reads far out and never swamps the ground close in (owner: 注意兵棋大小).
func army_badge_height() -> float:
	var seen := float(_meta.get("m_per_px", 50.0)) / maxf(_metres_per_pixel(), 0.0001)
	return clampf(_repo.bal("map_army_badge_native_px") * seen,
		_repo.bal("map3d_army_badge_min_px"), _repo.bal("map3d_army_badge_max_px"))


## The counters (ArmyCounters, the 2D map's) of the player's regiments before
## the camera, in design px, kept clear of the settlement dots. [] while the
## layer is off.
func army_markers() -> Array:
	if not _military or _camera == null:
		return []
	var s := _render_scale()
	var h := army_badge_height()
	var frame := Rect2(Vector2.ZERO, size).grow(h * 4.0)
	var points: Array = []
	for r: Dictionary in MapObjects.regiments_of(_repo, _repo.resolve_realm("player_realm")):
		var xz := Map3DGeometry.pack_to_world(_meta, Vector2(float(r["x"]), float(r["y"])))
		var ground := Vector3(xz.x, _height_at(xz), xz.y)
		if _camera.is_position_behind(ground):
			continue
		var sp := _camera.unproject_position(ground) / s
		if frame.has_point(sp):
			points.append({"reg": r, "pos": sp})
	return ArmyCounters.layout(_repo, points, h, _settlement_marks())


## The screen squares (design px) of every settlement dot shown now — what
## the counters keep clear of.
func _settlement_marks() -> Array:
	return _ctx.settlement_rects()


## Draw the counters on the HUD, over the badges and names.
func draw_armies(ci: CanvasItem) -> void:
	var markers := army_markers()
	_drawn_armies = markers.size()
	ArmyCounters.draw(ci, _repo, markers, _selected_army)


# --- HEIGHTS landmarks (owner 2026-09-19, spec 2026-09-19-map3d-heights §4) ---

## The high and low points shown now, in design px, biggest first: those
## whose lod the camera's distance allows, before the camera and on screen,
## none overlapping a settlement dot, a regiment counter, the legend or a
## bigger mark.
## [] off HEIGHTS.
func landmark_marks() -> Array:
	if not _themes.heat_on() or _camera == null or not _loaded:
		return []
	# ~1.5 ms a call (the settlement dots dominate) and asked up to three
	# times a frame — HUD draw, hover, click — so it is cut once per camera
	# pose (Task 7 bench): the pose, the view's size, whether the counters
	# are shown and the date (regiments) key it.
	var st := _state()
	var key := [_camera.global_transform, size, _render_scale(), _military,
		st.tick if st != null else 0, st.day if st != null else 0]
	if key == _landmark_key:
		return _landmark_cache
	_landmark_cache = _cut_landmark_marks()
	_landmark_key = key
	return _landmark_cache


func _cut_landmark_marks() -> Array:
	var max_lod := 2
	if _ctx.distance >= _repo.bal("map3d_landmark_lod_far_view_m"):
		max_lod = 0
	elif _ctx.distance >= _repo.bal("map3d_landmark_lod_mid_view_m"):
		max_lod = 1
	var s := _render_scale()
	var px := _repo.bal("map3d_landmark_px")
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var frame := Rect2(Vector2.ZERO, size)
	var taken: Array = _settlement_marks()
	for a: Dictionary in army_markers():
		taken.append(a["rect"])
	taken.append(heat_legend_rect())
	var out: Array = []
	for m: Dictionary in Elevation.landmarks(_repo):
		if int(m["lod"]) > max_lod:
			continue
		var ground := _ctx.pack_ground(m["pos"])
		if _camera.is_position_behind(ground):
			continue
		var p := _camera.unproject_position(ground) / s
		if not frame.has_point(p):
			continue
		var text := "%d m" % int(m["metres"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x \
			if font != null else 0.0
		var tall := maxf(px, float(font_px))
		var rect := Rect2(p - Vector2(px * 0.5, tall * 0.5), Vector2(px + 4.0 + tw, tall))
		# the whole mark and its height inside the view: a "15" cut by the edge
		# (or under the council tab) reads as a wrong number (Task 7 look pass)
		if not frame.encloses(rect):
			continue
		var clear := true
		for r: Rect2 in taken:
			if r.intersects(rect):
				clear = false
				break
		if not clear:
			continue
		taken.append(rect)
		out.append({"cell": int(m["cell"]), "kind": String(m["kind"]), "pos": p,
			"rect": rect, "text": text})
	return out


## Draw the landmarks on the HUD: a triangle up (high) or down (low) on a
## pale halo, the height beside it.
func draw_landmarks(ci: CanvasItem) -> void:
	var marks := landmark_marks()
	if marks.is_empty():
		return
	var px := _repo.bal("map3d_landmark_px")
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var halo := MapTerrain.palette_color(_repo, "map3d_hud_halo", MapTerrain.FALLBACK)
	var text_ink := MapPalette.named(_repo, "landmark_text")
	var high_ink := MapPalette.named(_repo, "landmark_high")
	var low_ink := MapPalette.named(_repo, "landmark_low")
	for mk: Dictionary in marks:
		var p: Vector2 = mk["pos"]
		var h := px * 0.5
		var high := String(mk["kind"]) == "high"
		var tri := PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, h), p + Vector2(-h, h)]) \
			if high else PackedVector2Array([p + Vector2(0, h), p + Vector2(-h, -h), p + Vector2(h, -h)])
		ci.draw_colored_polygon(tri, high_ink if high else low_ink)
		ci.draw_polyline(tri + PackedVector2Array([tri[0]]), halo, 1.5, true)
		if font != null:
			var at := p + Vector2(h + 3.0, font_px * 0.35)
			ci.draw_string_outline(font, at, String(mk["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, 3, halo)
			ci.draw_string(font, at, String(mk["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, text_ink)


## The HEIGHTS legend's box, bottom-left, in design px (Rect2() off HEIGHTS).
func heat_legend_rect() -> Rect2:
	if not _themes.heat_on():
		return Rect2()
	var w := _repo.bal("map3d_heat_legend_w_px")
	var h := _repo.bal("map3d_heat_legend_h_px")
	var margin := _repo.bal("map_compass_margin_px")
	return Rect2(Vector2(margin, size.y - margin - h), Vector2(w, h))


## The legend's tier lines, bottom up: {label "Hills 750 m", y} in design px,
## each at its metres' share of the ramp's height. [] off HEIGHTS.
func heat_legend_ticks() -> Array:
	var box := heat_legend_rect()
	if box.size.y <= 0.0:
		return []
	var top_m := _repo.bal("elevation_m_per_unit") * (100.0 - _repo.bal("elevation_sea_level"))
	var out: Array = []
	for i in range(_repo.army_height_supply.size() - 1, -1, -1):
		var r: Dictionary = _repo.army_height_supply[i]
		var metres := Elevation.metres_of_height(_repo, float(r["min_height"]))
		if metres <= 0 or top_m <= 0.0:
			continue
		out.append({"label": "%s %d m" % [String(r["tier"]).capitalize(), metres],
			"y": box.end.y - box.size.y * clampf(float(metres) / top_m, 0.0, 1.0)})
	return out


## The legend's whole footprint, design px: the ramp and its tier names
## (Rect2() off HEIGHTS).
func _heat_legend_area() -> Rect2:
	var box := heat_legend_rect()
	if box.size.y <= 0.0:
		return Rect2()
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var w := 0.0
	for t: Dictionary in heat_legend_ticks():
		w = maxf(w, font.get_string_size(String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_px).x if font != null else float(font_px) * String(t["label"]).length())
	return Rect2(box.position, Vector2(box.size.x + 7.0 + w, box.size.y))


## Whether the legend steps back for a MEASUREMENT ruler (Task 7 look pass):
## true while a ruler runs through the legend's footprint grown by the
## reading's size, so the reading is never printed over a tier's name.
func heat_legend_yields() -> bool:
	if not ruler_on or not _ruler.active() or _camera == null:
		return false
	var area := _heat_legend_area()
	if area.size.y <= 0.0:
		return false
	area = area.grow(_repo.bal("map_ruler_font_px") + _repo.bal("map_ruler_label_offset_px"))
	var a3 := Vector3(_ruler.start.x, _height_at(_ruler.start), _ruler.start.y)
	var b3 := Vector3(_ruler.end.x, _height_at(_ruler.end), _ruler.end.y)
	if _camera.is_position_behind(a3) or _camera.is_position_behind(b3):
		return false
	var s := _render_scale()
	var a := _camera.unproject_position(a3) / s
	var b := _camera.unproject_position(b3) / s
	if area.has_point(a) or area.has_point(b):
		return true
	var c := [area.position, Vector2(area.end.x, area.position.y), area.end,
		Vector2(area.position.x, area.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false


## The HEIGHTS legend, bottom-left: the heat ramp (terrain_palette heat_1..6)
## bottom to top, the tier lines ticked and named with their metres; faint
## (map3d_heat_legend_yield_alpha) while a ruler crosses it.
func draw_heat_legend(ci: CanvasItem) -> void:
	var box := heat_legend_rect()
	if box.size.y <= 0.0:
		return
	var fade := Color(1, 1, 1, _repo.bal("map3d_heat_legend_yield_alpha")) \
		if heat_legend_yields() else Color.WHITE
	var x0 := box.position.x
	var x1 := box.end.x
	for i in 5:
		var y0 := box.end.y - box.size.y * float(i) / 5.0
		var y1 := box.end.y - box.size.y * float(i + 1) / 5.0
		var c0 := MapTerrain.palette_color(_repo, "heat_%d" % (i + 1), MapTerrain.FALLBACK) * fade
		var c1 := MapTerrain.palette_color(_repo, "heat_%d" % (i + 2), MapTerrain.FALLBACK) * fade
		ci.draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0),
			Vector2(x1, y1), Vector2(x0, y1)]), PackedColorArray([c0, c0, c1, c1]))
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var ink := MapPalette.named(_repo, "landmark_text") * fade
	var halo := MapTerrain.palette_color(_repo, "map3d_hud_halo", MapTerrain.FALLBACK) * fade
	for t: Dictionary in heat_legend_ticks():
		var y := float(t["y"])
		ci.draw_line(Vector2(x0, y), Vector2(x1 + 4.0, y), ink, 1.5)
		if font != null:
			var at := Vector2(x1 + 7.0, y + font_px * 0.35)
			ci.draw_string_outline(font, at, String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, 3, halo)
			ci.draw_string(font, at, String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)


func drawn_army_count() -> int:
	return _drawn_armies


func selected_army() -> String:
	return _selected_army


## Draw the badges on the HUD, over the kingdom names.
func draw_badges(ci: CanvasItem) -> void:
	var badges := manor_badges()
	_drawn_badges = badges.size()
	ManorBadges.draw(ci, _repo, badges)


func drawn_badge_count() -> int:
	return _drawn_badges


## Test seam: the kingdoms lettered on the HUD's last draw.
func drawn_labels() -> PackedStringArray:
	return _drawn_labels


## The ruler's reading, as drawn.
func ruler_reading() -> String:
	return MapRuler.reading(_ruler.length() * map_units_per_metre(), map_unit())


## THE 3D MAP MEASURES LIKE THE 2D MAP (owner 2026-09-18). The world is BUILT
## at map3d_world m_per_px (50 m per pack px: a scale the terrain, the camera
## and the relief were tuned at), but every distance it SHOWS — the ruler,
## the scale bar — is the pack's: world metres back to pack px, times
## map_info.csv distance_scale, in distance_unit. So the same two towns read
## the same on both maps. A pack with no scale reads its world in km.
func map_units_per_metre() -> float:
	var per_px := float(_repo.map_info.get("distance_scale", "0"))
	var m_per_px := float(_meta.get("m_per_px", 0.0))
	if per_px <= 0.0 or m_per_px <= 0.0:
		return 0.001
	return per_px / m_per_px


func map_unit() -> String:
	if float(_repo.map_info.get("distance_scale", "0")) <= 0.0 \
			or float(_meta.get("m_per_px", 0.0)) <= 0.0:
		return "km"
	return String(_repo.map_info.get("distance_unit", ""))


## Test seam.
func ruler() -> MapRuler:
	return _ruler


# --- picking --------------------------------------------------------------------

## The ground under a point of the view (design px), or null for the sky.
func ground_at(pos: Vector2) -> Variant:
	return _ctx.ground_at(pos) if _ctx != null else null


## What a click at `pos` picks: {"kind": "burg", "code"} for a settlement
## within map3d_pick_px of it (or on its ring), {"kind": "province", "code"}
## for the province under it, {} for the sea or the sky.
##
## Only a SHOWN ring is picked (final review, owner 2026-09-18): a burg whose
## camera distance has reached its tier's max_view_m x map3d_ring_fade_start
## — where settlement_ring.gdshader begins to fade it — is skipped, so a
## click on a thinned village's empty spot names the province under it.
##
## The burg distance is measured in SCREEN px (the camera's own projection of
## each burg's ground point), not by unprojecting the click to world XZ and
## comparing world distances: at a steep near-zoom grazing angle a small
## terrain-height error swings the raycast's XZ landing point by far more
## than the ring's own on-screen radius, so a world-space reach either picked
## nothing (fix round 1, owner 2026-09-18) or had to be absurdly generous.
## Screen space matches what the player is actually aiming at, a ring of
## constant screen size, and needs no distance conversion at all.
func pick_at(pos: Vector2) -> Dictionary:
	var hit: Variant = ground_at(pos)
	if hit == null:
		return {}
	var p := hit as Vector3
	var xz := Vector2(p.x, p.z)
	var best := ""
	var best_d := INF
	# A regiment's counter is picked first, as on the 2D map: anywhere on it,
	# or within map_army_pick_px of the point it stands on.
	var armies := army_markers()
	for i in range(armies.size() - 1, -1, -1):
		if (armies[i]["rect"] as Rect2).has_point(pos):
			return {"kind": "army", "code": String(armies[i]["code"])}
	for i in range(armies.size() - 1, -1, -1):
		if (armies[i]["pos"] as Vector2).distance_to(pos) <= _repo.bal("map_army_pick_px"):
			return {"kind": "army", "code": String(armies[i]["code"])}
	# An output badge names the settlement whose output it shows (as on the
	# 2D map), over whatever lies under it.
	for b: Dictionary in manor_badges():
		if (b["rect"] as Rect2).has_point(pos):
			return {"kind": "burg", "code": String(b["burg"])}
	var best_dot := 0.0
	for e: Dictionary in _ctx.projected_settlements():
		if not bool(e["shown"]):
			continue
		var spec: Dictionary = e["spec"]
		var reach := maxf(marker_px(spec) * 0.5, _repo.bal("map3d_pick_px"))
		var d := (e["screen"] as Vector2).distance_to(pos)
		if d <= reach and d < best_d:
			best_d = d
			best = String(e["code"])
			best_dot = marker_px(spec) * 0.5 + 2.0
	# Under HEIGHTS a high or low point (spec 2026-09-19-map3d-heights), ranked
	# against the settlements (Task 7): a click ON a settlement's dot is the
	# settlement's, a click on a mark is the mark's, then a settlement's reach,
	# and last the mark's rect grown by half the pick reach.
	if best != "" and best_d <= best_dot:
		return {"kind": "burg", "code": best}
	var marks := landmark_marks() if _themes.heat_on() else []
	for mk: Dictionary in marks:
		if (mk["rect"] as Rect2).has_point(pos):
			return {"kind": "landmark", "cell": int(mk["cell"])}
	if best != "":
		return {"kind": "burg", "code": best}
	var grow := _repo.bal("map3d_pick_px") * 0.5
	for mk: Dictionary in marks:
		if (mk["rect"] as Rect2).grow(grow).has_point(pos):
			return {"kind": "landmark", "cell": int(mk["cell"])}
	# Under MANORS the land means its MANOR, as on the 2D map.
	if _themes.theme() == "manors":
		var cell := _cell_at(Map3DGeometry.world_to_pack(_meta, xz))
		return {"kind": "manor", "cell": cell} if cell >= 0 else {}
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


## The kingdom holding what a pick names, NOW (MapOwnership, so a conquest
## moves it): a settlement's province's holder, a province's holder, "" for
## the sea or the sky — WorldMapView._state_of's rule.
static func kingdom_of_pick(repo: DataRepository, state: GameState, picked: Dictionary) -> String:
	var province := ""
	match String(picked.get("kind", "")):
		"burg":
			province = String((repo.burgs.get(String(picked["code"]), {}) as Dictionary)
				.get("province_code", ""))
		"province":
			province = String(picked["code"])
		"manor", "landmark":
			province = MapManors.province_of(repo, int(picked["cell"]), state)
		"army":
			var k := String(ArmySystem.regiment(repo, String(picked["code"])).get("kingdom_code", ""))
			return k if repo.kingdoms.has(k) else ""
	if province == "":
		return ""
	var holder := MapOwnership.owner_of(repo, state, province)
	return holder if repo.kingdoms.has(holder) else ""


## A pick at `pos` (design px) as the hover: the settlement's name beside the
## cursor, and — only when it changes — the kingdom's wider outline and
## country_hovered. Public: tests drive it without a ray.
func hover_pick(picked: Dictionary, pos: Vector2) -> void:
	var obj: Dictionary = picked if String(picked.get("kind", "")) in ["burg", "manor", "army", "landmark"] else {}
	if obj != _hover_obj:
		_hover_obj = obj
		var label := MapObjects.label_of(_repo, obj, _state())
		_tooltip.text = label
		_tooltip.visible = label != ""
	if _tooltip.visible:
		var tip := _tooltip.get_combined_minimum_size()
		_tooltip.size = tip
		_tooltip.position = (pos + TOOLTIP_OFFSET).clamp(Vector2.ZERO, (size - tip).max(Vector2.ZERO))
	var kingdom := kingdom_of_pick(_repo, _state(), picked)
	if kingdom == _hover_kingdom:
		return
	_hover_kingdom = kingdom
	_draw_hover()
	country_hovered.emit(kingdom)


## No hover: the pointer left, a drag began, or the view was hidden.
func clear_hover() -> void:
	_hover_pending = false
	if _tooltip != null:
		hover_pick({}, Vector2.ZERO)


## The hovered kingdom's live outline (Map3DLayerBorders.draw_hover).
func _draw_hover() -> void:
	if _loaded:
		_borders.draw_hover(_hover_kingdom)


func hovered_kingdom() -> String:
	return _hover_kingdom


## The tooltip's text while a settlement is hovered ("" otherwise).
func hover_tooltip() -> String:
	return _tooltip.text if _tooltip.visible else ""


## Test seam: where the tooltip sits, in view coordinates.
func tooltip_rect() -> Rect2:
	return Rect2(_tooltip.position, _tooltip.get_combined_minimum_size())


## The manor at a pack pixel (world_cell_index.png), or -1 for water, the
## map's edge or land no manor covers.
func _cell_at(pack_px: Vector2) -> int:
	if _cell_image == null:
		var path := _repo.cell_texture_path
		if path == "" or not ResourceLoader.exists(path):
			return -1
		_cell_image = (load(path) as Texture2D).get_image()
	var p := Vector2i(pack_px.floor())
	if p.x < 0 or p.y < 0 or p.x >= _cell_image.get_width() or p.y >= _cell_image.get_height():
		return -1
	var id := MapIndex.id_at(_cell_image, p)
	return id if _repo.manors.has(id) else -1


## The click: a settlement opens its card, land names its province (its
## manor under a theme), the sea clears — exactly the signals WorldMapView
## sends.
func select_at(pos: Vector2) -> void:
	var picked := pick_at(pos)
	match String(picked.get("kind", "")):
		"burg":
			var code := String(picked["code"])
			_selected_army = ""
			_set_selected_province("")
			_selected_burg = code
			_show_selected_ring(code)
			object_selected.emit({"title": String(_repo.burgs[code].get("label", code)),
				"obj": {"kind": "burg", "code": code}})
		"province":
			_selected_burg = ""
			_selected_army = ""
			_show_selected_ring("")
			_set_selected_province(String(picked["code"]))
			province_selected.emit(_selected_province)
		"army":
			var code := String(picked["code"])
			_selected_burg = ""
			_show_selected_ring("")
			_set_selected_province("")
			_selected_army = code
			if _hud != null:
				_hud.refresh()
			object_selected.emit({"title": MapObjects.label_of(_repo, picked),
				"obj": {"kind": "army", "code": code}})
		"manor":
			var cell := int(picked["cell"])
			_selected_army = ""
			_selected_burg = ""
			_show_selected_ring("")
			_selected_province = ""
			_selected_manor = cell
			_draw_selection()
			object_selected.emit({"title": MapManors.label_of(_repo, cell),
				"obj": {"kind": "manor", "cell": cell}})
		"landmark":
			var cell := int(picked["cell"])
			if _selected_army != "":
				_selected_army = ""
				if _hud != null:
					_hud.refresh()
			_selected_burg = ""
			_show_selected_ring("")
			_set_selected_province("")
			var m := Elevation.landmark_at(_repo, cell)
			object_selected.emit({"title": String(m.get("name", "")),
				"lines": MapObjects.landmark_lines(_repo, _state(), cell),
				"ask": "", "obj": {"kind": "landmark", "cell": cell}})
		_:
			clear_selection()


func _set_selected_province(code: String) -> void:
	if code == _selected_province and _selected_manor < 0:
		return
	_selected_province = code
	_selected_manor = -1
	if _loaded:
		_draw_selection()


## Forget the selection (the card was closed, or the sea clicked).
func clear_selection() -> void:
	var had := _selected_burg != "" or _selected_province != "" or _selected_manor >= 0 \
		or _selected_army != ""
	if _selected_army != "":
		_selected_army = ""
		if _hud != null:
			_hud.refresh()
	_selected_burg = ""
	_show_selected_ring("")
	_set_selected_province("")
	if had:
		object_selected.emit({})


## Test seam (Ruling 18): the inner part named `key`, or null. Later tasks
## add their keys to this match.
func component(key: String) -> Object:
	match key:
		"roads":
			return _roads
		"borders":
			return _borders
		"themes":
			return _themes
		"input":
			return _input
		"rig":
			return _rig
	return null


## Test seams.
func is_loaded() -> bool:
	return _loaded

func notice() -> Label:
	return _notice

func viewport() -> SubViewport:
	return _viewport

func camera() -> Camera3D:
	return _rig.camera() if _rig != null else null

func cloud_count() -> int:
	return _clouds.count() if _clouds != null else 0

func target() -> Vector2:
	return _ctx.target if _ctx != null else Vector2.ZERO

func distance() -> float:
	return _ctx.distance if _ctx != null else 1.0

func yaw() -> float:
	return _ctx.yaw if _ctx != null else 0.0

func selected_province() -> String:
	return _selected_province

func selected_burg() -> String:
	return _selected_burg

func selected_manor() -> int:
	return _selected_manor

## Whether the clicked settlement's gold ring is currently shown.
func selected_ring_visible() -> bool:
	return _markers != null and _markers.selected_visible()

## Centre the rig on a pack point (tests and future "go to" orders).
func look_at_pack(pack_px: Vector2, at_distance: float = -1.0) -> void:
	if _rig == null:
		return
	_rig.place(_ctx.to_world(pack_px), at_distance if at_distance > 0.0 else _ctx.distance, _ctx.yaw)

## Frame the player's capital at a distance (the bench and the snapshots).
func look_at_home(at_distance: float) -> void:
	if _rig == null:
		return
	_rig.place(_home(), at_distance, _ctx.yaw)

## Layers the bench can switch off to price them, those that exist: the
## view's nodes under the viewport, the build's Sea, the Sun's shadows, the HUD.
func layer_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in ["Markers", "Lines", "Clouds"]:
		if _viewport.get_node_or_null(n) != null:
			out.append(n)
	if _rivers != null and _rivers.mesh != null:
		out.append("Rivers")
	if _sea != null and _sea.has_water():
		out.append("Sea")
	if _world != null and _world.get_node_or_null("Sun") != null:
		out.append("Shadows")
	if get_node_or_null("Hud") != null:
		out.append("Hud")
	return out

func set_layer_visible(layer: String, on: bool) -> void:
	match layer:
		"Shadows":
			(_world.get_node("Sun") as DirectionalLight3D).shadow_enabled = on
		"Sea":
			_sea.visible = on
		"Hud":
			(get_node("Hud") as CanvasItem).visible = on
		_:
			(_viewport.get_node(layer) as Node3D).visible = on

## A line mesh by name (Kingdoms, Seams, Selection), or null.
func line_mesh(line_name: String) -> ArrayMesh:
	return _lines.line_mesh(line_name) if _lines != null else null

## Settlement markers per group: {group: count}.
func marker_counts() -> Dictionary:
	return _markers.counts() if _markers != null else {}
