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
const TOOLTIP_OFFSET := Map3DPicker.TOOLTIP_OFFSET
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
## The pick and the hover (Map3DPicker) and what was clicked (Map3DSelection):
## made here, before load, since clear_hover and clear_selection run before it.
var _picker := Map3DPicker.new()
var _selection := Map3DSelection.new()
var _border_clock := 0.0
var _hud: Map3DHud
## The hover's name beside the cursor (owner 2026-09-18); Map3DPicker fills it.
var _tooltip: Label
## MILITARY on the 3D map (owner 2026-09-19): whether the counters show (the
## clicked regiment is Map3DSelection's).
var _military := false
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
	_picker.bind(_ctx, self, _tooltip, _borders)
	_selection.bind(_ctx, _lines, _markers, self)
	_loaded = true
	_rig.place(_home(), _repo.bal("map3d_zoom_start_m"), 0.0)
	_update_line_scale()
	_hud = Map3DHud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_hud.bind(_ctx, self)  # the HUD redraws itself on every camera move
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
	if theme_name != "manors":
		_selection.forget_manor()
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


## The clicked province's (or manor's) gold outline (Map3DSelection.redraw).
func _draw_selection() -> void:
	_selection.redraw()


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
	_picker.step()
	if not _hovered:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if _input.key_pan(delta):
		_picker.repick()  # the ground moved under a still pointer


## Map3DInput: pick the hover at `pos` on the next frame.
func request_hover(pos: Vector2) -> void:
	_picker.request(pos)


## Redraw the HUD (compass, scale bar, labels, ruler); on every camera move.
func refresh_hud() -> void:
	if _hud != null:
		_hud.refresh()


## The compass's screen rect (design px), empty before the HUD exists.
func compass_rect() -> Rect2:
	return _hud.compass_rect() if _hud != null else Rect2()


# --- ruler ---------------------------------------------------------------------

## A ruler click at `pos` (design px): the ground under it, or nothing on the sky.
func ruler_click(pos: Vector2) -> void:
	var hit: Variant = ground_at(pos)
	if hit == null:
		return
	_ruler.click(Vector2((hit as Vector3).x, (hit as Vector3).z))
	if _hud != null:
		_hud.refresh()


## Kept for the tests that call it (test_map3d_api pins it): ruler_click.
func _ruler_click(pos: Vector2) -> void:
	ruler_click(pos)


# --- the HUD's pieces (Map3DHud: one per job, drawn from the context) -----------

## The kingdom names the HUD would letter now (Map3DHudLabels.entries).
func label_entries() -> Array:
	return (_hud.piece("Labels") as Map3DHudLabels).entries() if _hud != null else []


## Test seam: the kingdoms lettered on the HUD's last draw.
func drawn_labels() -> PackedStringArray:
	return (_hud.piece("Labels") as Map3DHudLabels).drawn() if _hud != null else PackedStringArray()


## MANORS' output badges shown now, design px (Map3DHudBadges.badges).
func manor_badges() -> Array:
	return (_hud.piece("Badges") as Map3DHudBadges).badges() if _hud != null else []


func drawn_badge_count() -> int:
	return (_hud.piece("Badges") as Map3DHudBadges).drawn_count() if _hud != null else 0


## A counter's height, design px (Map3DHudArmies.badge_height).
func army_badge_height() -> float:
	return (_hud.piece("Armies") as Map3DHudArmies).badge_height() if _hud != null else 0.0


## The regiments' counters shown now, design px (Map3DHudArmies.markers).
func army_markers() -> Array:
	return (_hud.piece("Armies") as Map3DHudArmies).markers() if _hud != null else []


func drawn_army_count() -> int:
	return (_hud.piece("Armies") as Map3DHudArmies).drawn_count() if _hud != null else 0


## HEIGHTS' high and low points shown now (Map3DHudLandmarks.marks).
func landmark_marks() -> Array:
	return (_hud.piece("Landmarks") as Map3DHudLandmarks).marks() if _hud != null else []


## The HEIGHTS legend's box, its tier lines, and whether it steps back for a
## ruler (Map3DHudHeatLegend).
func heat_legend_rect() -> Rect2:
	return (_hud.piece("HeatLegend") as Map3DHudHeatLegend).rect() if _hud != null else Rect2()


func heat_legend_ticks() -> Array:
	return (_hud.piece("HeatLegend") as Map3DHudHeatLegend).ticks() if _hud != null else []


func heat_legend_yields() -> bool:
	return (_hud.piece("HeatLegend") as Map3DHudHeatLegend).yields() if _hud != null else false


# --- MILITARY (owner 2026-09-19) ---------------------------------------------------

## Show the player's regiments as counters — GameRoot hands this down with
## the MILITARY tab, as the 2D map's show_armies.
func set_military(on: bool) -> void:
	_military = on
	if not on and _selection.army != "":
		_selection.clear()
	if _hud != null:
		_hud.refresh()


func military() -> bool:
	return _military


func selected_army() -> String:
	return _selection.army


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


## What a click at `pos` picks (Map3DPicker.pick_at): {} before the world loads.
func pick_at(pos: Vector2) -> Dictionary:
	return _picker.pick_at(pos) if _loaded else {}


## The kingdom holding what a pick names, NOW (Map3DPicker.kingdom_of_pick).
static func kingdom_of_pick(repo: DataRepository, state: GameState, picked: Dictionary) -> String:
	return Map3DPicker.kingdom_of_pick(repo, state, picked)


## A pick at `pos` as the hover (Map3DPicker.hover_pick): the name beside the
## cursor and, when the kingdom changes, its outline and country_hovered.
func hover_pick(picked: Dictionary, pos: Vector2) -> void:
	_picker.hover_pick(picked, pos)


## No hover: the pointer left, a drag began, or the view was hidden.
func clear_hover() -> void:
	_picker.clear_hover()


func hovered_kingdom() -> String:
	return _picker.hovered_kingdom()


## The tooltip's text while a settlement is hovered ("" otherwise).
func hover_tooltip() -> String:
	return _picker.hover_tooltip()


## Test seam: where the tooltip sits, in view coordinates.
func tooltip_rect() -> Rect2:
	return _picker.tooltip_rect()


## The click (Map3DSelection.select): the signals WorldMapView sends.
func select_at(pos: Vector2) -> void:
	_selection.select(pick_at(pos))


## Forget the selection (the card was closed, or the sea clicked).
func clear_selection() -> void:
	_selection.clear()


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
		"picker":
			return _picker
		"selection":
			return _selection
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
	return _selection.province

func selected_burg() -> String:
	return _selection.burg

func selected_manor() -> int:
	return _selection.manor

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
