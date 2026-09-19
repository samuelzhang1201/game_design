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
const BORDER_SHADER := preload("res://scripts/map3d/border_line.gdshader")
const ROAD_SHADER := preload("res://scripts/map3d/road_line.gdshader")
## The road surface and the bridges' stone (Poly Haven, packed by
## tools/map3d/pack_textures.py into the git-ignored textures folder): a
## checkout without them draws flat roads and untextured stone.
const ROAD_TEXTURE := "res://assets/map3d/textures/rocky_trail_02"
const BRIDGE_TEXTURE := "res://assets/map3d/textures/medieval_blocks_03"
const RING_SHADER := preload("res://scripts/map3d/settlement_ring.gdshader")
const RIVER_SHADER := preload("res://scripts/map3d/water_river.gdshader")
const SEA_SHADER := preload("res://scripts/map3d/water_sea.gdshader")
const CLOUD_SHADER := preload("res://scripts/map3d/cloud_deck.gdshader")
const CLOUD_SHADOW_SHADER := preload("res://scripts/map3d/cloud_shadow.gdshader")
## The selection ring never thins by distance (fix round 1, owner 2026-09-18):
## whatever the player clicked stays marked regardless of zoom.
const SELECTED_RING_ALWAYS_M := 1000000.0
## THE RENDER-PRIORITY TABLE (final review, owner 2026-09-18) — the one
## place the see-through layers' draw order is set. Higher draws over lower.
## The sea under everything; the river water under every line, so a border
## or seam always reads over the water it crosses; the roads (a bridge over
## the water, under every border); the manor edges of the MANORS
## themes; the realm band inside each kingdom (2026-09-19), seams, the
## kingdom border's pale halo, then its ink, then the hovered kingdom's
## wider outline, then the clicked
## province's gold outline; then the CLOUDS — over
## the lines, but UNDER the settlement rings, so a pin always stands above
## the weather; then the rings by tier (village lowest, capital highest —
## see _place_markers) and the gold selection ring over every tier.
const PRIORITY_SEA := -1
const PRIORITY_RIVERS := 0
const PRIORITY_ROADS := 1
const PRIORITY_MANOR_EDGES := 2
const PRIORITY_KINGDOM_BAND := 3
const PRIORITY_SEAMS := 4
const PRIORITY_KINGDOM_HALO := 5
const PRIORITY_KINGDOMS := 6
const PRIORITY_HOVER := 7
const PRIORITY_SELECTION := 8
const PRIORITY_CLOUDS := 9
## The lowest ring tier; the tiers and then the selection ring count up from
## here, one step each (data/map3d_settlements.csv's groups).
const PRIORITY_RING_BASE := 10
## A press and release further apart than this is a drag, not a click
## (WorldMapView.CLICK_SLOP).
const CLICK_SLOP := 10.0
## Where the name sits off the cursor (WorldMapView.TOOLTIP_OFFSET).
const TOOLTIP_OFFSET := Vector2(20.0, 24.0)
## Metres per texel of the bake's field map: tools/map3d/bake_world.py
## FIELD_MAP_STEP (2) vertices of VERTEX_M (20 m).
const FIELD_MAP_M_PER_TEXEL := 40.0

var _repo: DataRepository
var _scene_path := ""
var _display: TextureRect
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _markers: Node3D
var _lines: Node3D
var _notice: Label
var _ring_mats: Array[ShaderMaterial] = []
var _selected_ring: MultiMeshInstance3D
var _water_normals: NoiseTexture2D
var _river_mat: ShaderMaterial
## The river courses as drawn (Map3DRivers.parse, cleared of the terrain):
## the bridges look for them.
var _river_courses: Array = []
## Every bridge built (Map3DBridges.plan's, each with its deck_w).
var _bridge_list: Array = []
var _sea_mat: ShaderMaterial
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
var _cell_image: Image
var _selected_province := ""
var _selected_burg := ""
## The clicked manor under a theme (-1 for none), outlined in gold.
var _selected_manor := -1
var _border_sig := 0
## The MANORS theme (owner 2026-09-19; ECONOMY was folded into it): "" or "manors";
## the LUT of each cell's ManorPalette colour the patched terrain shader reads
## (Map3DGroundTint), rebuilt when the theme or an owner turns; the terrain
## material carrying the patch (null without a Terrain3D or when the addon's
## code would not patch); whether the cell edges have been laid.
var _theme := ""
## HEIGHTS' heat mix (owner 2026-09-19, spec 2026-09-19-map3d-heights): a
## plain bool _refresh_theme sets before the _loaded guard, so heat_on()
## works even in the test fixture, which has no Terrain3D.
var _heat := false
var _theme_sig := 0
var _cell_lut: ImageTexture
var _lut_image: Image
var _tint_mat: Resource
var _edges_built := false
var _border_clock := 0.0
var _hud: Map3DHud
## The hover (owner 2026-09-18): a pointer move is only recorded, and picked
## once a frame in _process; the pick's kingdom, its settlement (the
## tooltip), and each kingdom's outline lines, kept until ownership turns.
var _hover_pos := Vector2.ZERO
var _hover_pending := false
var _hover_kingdom := ""
var _hover_obj: Dictionary = {}
var _hover_lines: Dictionary = {}
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
var _north_t := -1.0
var _north_from := 0.0
var _press_on_hud := false
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
var _rpress_pos := Vector2.ZERO
## Whether the right button has turned the view since it went down: a turn
## that comes back to its start is still not a click.
var _rdragged := false
var _cloud_field: Map3DCloudField
var _cloud_mm: MultiMesh
var _cloud_params: Dictionary
var _cloud_depth_ratio := 0.6
var _ground_cache := Rect2()
var _ground_cache_target := Vector2.ZERO
var _ground_cache_distance := -1.0
var _ground_cache_yaw := 0.0
var _ground_cache_size := Vector2.ZERO
var _ground_cache_valid := false


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
	_bounds = Map3DGeometry.world_bounds(_meta)
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
	_build_rivers()
	_dress_sea()
	_apply_sun_shadow_look()
	_build_clouds()
	_lines = Node3D.new()
	_lines.name = "Lines"
	_viewport.add_child(_lines)
	_build_roads()
	_prepare_ground_tint()
	_target = Map3DGeometry.clamp_target(_home(), _bounds)
	_distance = _repo.bal("map3d_zoom_start_m")
	_yaw = 0.0
	_loaded = true
	_apply_camera()
	_update_line_scale()
	_hud = Map3DHud.new()
	_hud.view = self
	add_child(_hud)
	move_child(_tooltip, -1)  # the name over the scale bar and compass
	_refresh_theme()  # a theme lit before the first load


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


## One MultiMesh of billboard rings per settlement group, each over the
## ground under its burg, plus a hidden gold ring for the current selection.
## Codes are sorted so the placement is the same every run. Render priority
## rises with tier (village lowest, capital highest — by marker_px, the
## table's own measure of importance) so a bigger settlement's ring never
## gets buried under a smaller neighbour's (fix round 1, owner 2026-09-18);
## the selection ring sits above every tier.
func _place_markers() -> void:
	_ring_mats.clear()
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
	var by_size: Array = groups.duplicate()
	by_size.sort_custom(func(a: String, b: String) -> bool:
		var ra := marker_px(_repo.map3d_settlements[a])
		var rb := marker_px(_repo.map3d_settlements[b])
		return ra < rb if ra != rb else a < b)
	for group: String in groups:
		var spec: Dictionary = _repo.map3d_settlements[group]
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		mesh.material = _ring_material(Color(String(spec["color"])),
			float(spec["ring_px"]), float(spec["line_px"]), float(spec["max_view_m"]),
			PRIORITY_RING_BASE + by_size.find(group), float(spec.get("dot_px", 0.0)))
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
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The vertex shader grows geometry far past the mesh's own 1x1 AABB
		# (Map3DBorders' lines use the same margin, for the same reason).
		mmi.extra_cull_margin = 16384.0
		_markers.add_child(mmi)
	var sel := QuadMesh.new()
	sel.size = Vector2.ONE
	sel.material = _ring_material(MapPalette.named(_repo, "map3d_selection"), 0.0, 0.0,
		SELECTED_RING_ALWAYS_M, PRIORITY_RING_BASE + groups.size())
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = sel
	smm.instance_count = 1
	_selected_ring = MultiMeshInstance3D.new()
	_selected_ring.name = "Selected"
	_selected_ring.multimesh = smm
	_selected_ring.visible = false
	_selected_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selected_ring.extra_cull_margin = 16384.0
	_markers.add_child(_selected_ring)
	_update_line_scale()


## The ripple normal map both waters share: seamless noise made at load.
func water_normals() -> Texture2D:
	if _water_normals == null:
		var noise := FastNoiseLite.new()
		noise.seed = int(_repo.bal("map3d_water_seed"))
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


## rivers.json beside the scene (tools/map3d) as the Rivers layer; none
## without it. Split at each lake exit (Map3DRivers.parse) so a jump in the
## water line never draws as a vertical wall, then clear_terrain lifts any
## point whose flat, sparsely-sampled cross-section would otherwise dip
## below the real, denser terrain on a steep stretch (fix round 3) — the
## carved riverbed's own ground would show through instead of the water.
func _build_rivers() -> void:
	var path := _scene_path.get_base_dir().path_join("rivers.json")
	if not FileAccess.file_exists(path):
		return
	var courses := Map3DRivers.parse(FileAccess.get_file_as_string(path),
		_repo.bal("map3d_river_split_rise_m"))
	courses = Map3DRivers.clear_terrain(courses, _height_at, _repo.bal("map3d_river_terrain_clear_m"))
	_river_courses = courses
	var arrays := Map3DRivers.ribbon_arrays(courses, _repo.bal("map3d_river_end_fade_m"),
		_repo.bal("map3d_river_mesh_step_m"))
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_river_mat = ShaderMaterial.new()
	_river_mat.shader = RIVER_SHADER
	_river_mat.render_priority = PRIORITY_RIVERS
	# The palette hex goes in RAW, as the sea's does (see _dress_sea).
	_river_mat.set_shader_parameter("water",
		MapTerrain.palette_color(_repo, "river", MapTerrain.FALLBACK))
	_river_mat.set_shader_parameter("mouth_water",
		MapTerrain.palette_color(_repo, "sea_near", MapTerrain.FALLBACK))
	_river_mat.set_shader_parameter("sky",
		MapTerrain.palette_color(_repo, "map3d_sky", MapTerrain.FALLBACK))
	_river_mat.set_shader_parameter("ripples", water_normals())
	_river_mat.set_shader_parameter("ripple_m", _repo.bal("map3d_river_ripple_m"))
	_river_mat.set_shader_parameter("flow_m_s", _repo.bal("map3d_river_flow_m_s"))
	_river_mat.set_shader_parameter("opacity", _repo.bal("map3d_river_opacity"))
	_river_mat.set_shader_parameter("edge_soft_floor", _repo.bal("map3d_river_edge_soft_floor"))
	_river_mat.set_shader_parameter("emission_share", _repo.bal("map3d_river_emission_share"))
	_river_mat.set_shader_parameter("emission_gamma", _repo.bal("map3d_river_emission_gamma"))
	for key: String in ["fresnel_sky_mix", "fresnel_power", "roughness", "specular", "normal_depth",
			"ripple_emission_gain", "bank_wobble_m", "bank_wobble_amp"]:
		_river_mat.set_shader_parameter(key, _repo.bal("map3d_river_" + key))
	# One LOD for both waters: the river's near detail comes and goes with the sea's.
	_river_mat.set_shader_parameter("lod_near_m", _repo.bal("map3d_sea_ripple_lod_near_m"))
	_river_mat.set_shader_parameter("lod_far_m", _repo.bal("map3d_sea_ripple_lod_far_m"))
	mesh.surface_set_material(0, _river_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	_viewport.add_child(mi)


## The build's flat Sea plane dressed at runtime in the banded water, so the
## palette and bands stay data (terrain_palette / balance), not a rebuild.
func _dress_sea() -> void:
	var sea := _world.get_node_or_null("Sea") as MeshInstance3D
	if sea == null:
		return
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = SEA_SHADER
	_sea_mat.render_priority = PRIORITY_SEA
	var tex_path := _repo.sea_texture_path
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sea_mat.set_shader_parameter("sea_distance", load(tex_path))
	var o: Array = _meta["pack_origin"]
	var p: Array = _meta["pack_px"]
	_sea_mat.set_shader_parameter("pack_origin", Vector2(float(o[0]), float(o[1])))
	_sea_mat.set_shader_parameter("pack_px", Vector2(float(p[0]), float(p[1])))
	_sea_mat.set_shader_parameter("m_per_px", float(_meta["m_per_px"]))
	# The palette hex goes in RAW (final review, owner 2026-09-18): under GL
	# Compatibility a Color uniform set from GDScript passes straight through
	# to the output — measured 0.5 -> 128 under a Linear tonemap, with or
	# without source_color — so there is no double gamma to undo. What moves
	# a flat unshaded/EMISSION colour is the environment's FILMIC tonemap,
	# which lifts it (0.5 -> 162); map3d_sea_emission_gamma (> 1) is fitted
	# to that tonemap by sampling the rendered bands against these hexes.
	for key: String in ["sea_near", "sea_nearer", "sea_far", "sea_deep"]:
		_sea_mat.set_shader_parameter(key, MapTerrain.palette_color(_repo, key, MapTerrain.FALLBACK))
	_sea_mat.set_shader_parameter("sky",
		MapTerrain.palette_color(_repo, "map3d_sky", MapTerrain.FALLBACK))
	_sea_mat.set_shader_parameter("band_near", _repo.bal("map_sea_band_near_px"))
	_sea_mat.set_shader_parameter("band_nearer", _repo.bal("map_sea_band_nearer_px"))
	_sea_mat.set_shader_parameter("band_far", _repo.bal("map_sea_band_far_px"))
	_sea_mat.set_shader_parameter("soft", _repo.bal("map_sea_band_soft_px"))
	_sea_mat.set_shader_parameter("shore_fade_px", _repo.bal("map3d_sea_shore_fade_px"))
	_sea_mat.set_shader_parameter("ripples", water_normals())
	_sea_mat.set_shader_parameter("ripple_m", _repo.bal("map3d_sea_ripple_m"))
	_sea_mat.set_shader_parameter("drift_m_s", _repo.bal("map3d_sea_drift_m_s"))
	_sea_mat.set_shader_parameter("emission_share", _repo.bal("map3d_sea_emission_share"))
	_sea_mat.set_shader_parameter("emission_gamma", _repo.bal("map3d_sea_emission_gamma"))
	_sea_mat.set_shader_parameter("roughness", _repo.bal("map3d_sea_roughness"))
	_sea_mat.set_shader_parameter("specular", _repo.bal("map3d_sea_specular"))
	_sea_mat.set_shader_parameter("fresnel_sky_mix", _repo.bal("map3d_sea_fresnel_sky_mix"))
	_sea_mat.set_shader_parameter("horizon_fade_start_px", _repo.bal("map3d_sea_horizon_fade_start_px"))
	_sea_mat.set_shader_parameter("horizon_fade_end_px", _repo.bal("map3d_sea_horizon_fade_end_px"))
	for key: String in ["ripple_near_m", "ripple_lod_near_m", "ripple_lod_far_m",
			"ripple_emission_gain", "emission_share_near", "shore_warp_px", "shore_warp_m"]:
		_sea_mat.set_shader_parameter(key, _repo.bal("map3d_sea_" + key))
	sea.material_override = _sea_mat


## The Sun's shadow LOOK, applied at load (owner fix round 1, 2026-09-18):
## a code-review + independent-critic pass on Task 9 found the shipped cloud
## shadows read as pitch-black holes with knife edges, burying the
## settlement rings — `shadow_enabled` alone leaves Godot's default full
## black, full crisp shadow. `shadow_opacity` blends the shadowed pixel with
## its lit colour instead of replacing it (so a shadow reads as a COOL WASH
## of blocked light, never a hole) and `shadow_blur` softens every cast
## shadow's edge — both apply to the terrain's own self-shadowing too
## (accepted: the mountains read softer with it, see the fix report). The
## sea never receives shadows (`disable_receive_shadows` on its own
## material, set at build time) — untouched here.
func _apply_sun_shadow_look() -> void:
	var sun := _world.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	sun.shadow_opacity = _repo.bal("map3d_sun_shadow_opacity")
	sun.shadow_blur = _repo.bal("map3d_sun_shadow_blur")


## A deck of drifting cloud quads (owner 2026-09-18, Task 9) high over the
## land, plus a shadow-only twin sharing its MultiMesh so a cloud's shape and
## its shadow always match. `Clouds` (+ child `Shadows`) sit directly under
## the SubViewport so layer_names()/set_layer_visible() find them the way
## every other layer is found — hiding `Clouds` hides the twin with it,
## since a Node3D's visibility is inherited by its children.
func _build_clouds() -> void:
	_cloud_field = Map3DCloudField.new(int(_repo.bal("map3d_cloud_seed")))
	_cloud_params = {"max": int(_repo.bal("map3d_cloud_max")),
		"size_min": _repo.bal("map3d_cloud_size_min_m"), "size_max": _repo.bal("map3d_cloud_size_max_m"),
		"speed_m_s": _repo.bal("map3d_cloud_speed_m_s"), "wind_deg": _repo.bal("map3d_cloud_wind_deg"),
		"fade_s": _repo.bal("map3d_cloud_fade_s"), "interval_s": _repo.bal("map3d_cloud_interval_s"),
		"min_gap_m": _repo.bal("map3d_cloud_min_gap_m")}
	_cloud_depth_ratio = _repo.bal("map3d_cloud_depth_ratio")
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_cloud_mm = MultiMesh.new()
	_cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	_cloud_mm.use_colors = true
	_cloud_mm.mesh = quad
	_cloud_mm.instance_count = int(_cloud_params["max"])
	_cloud_mm.visible_instance_count = 0
	var shape := CloudLayer.cloud_texture(int(_repo.bal("map3d_cloud_seed")))
	var deck := MultiMeshInstance3D.new()
	deck.name = "Clouds"
	deck.multimesh = _cloud_mm
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deck.material_override = _cloud_material(shape)
	deck.extra_cull_margin = 16384.0
	_viewport.add_child(deck)
	var twin := MultiMeshInstance3D.new()
	twin.name = "Shadows"
	twin.multimesh = _cloud_mm
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	twin.material_override = _cloud_shadow_material(shape)
	twin.extra_cull_margin = 16384.0
	deck.add_child(twin)


func _cloud_material(shape: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.render_priority = PRIORITY_CLOUDS
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("opacity", _repo.bal("map3d_cloud_alpha"))
	mat.set_shader_parameter("near_fade_m", _repo.bal("map3d_cloud_near_fade_m"))
	mat.set_shader_parameter("near_fade_start_ratio", _repo.bal("map3d_cloud_near_fade_start_ratio"))
	mat.set_shader_parameter("emission_share", _repo.bal("map3d_cloud_emission_share"))
	return mat


## The shadow-only twin's OWN shader (cloud_shadow.gdshader — see its note
## and cloud_deck.gdshader's: the two must stay separate files under this
## renderer, not one shader gated by a `shadow_pass` uniform).
func _cloud_shadow_material(shape: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADOW_SHADER
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("shadow_cut", _repo.bal("map3d_cloud_shadow_cut"))
	return mat


## The ground rect the camera sees (its four corners' ground hits), wide
## enough for the sky when a corner looks past the horizon — cached on the
## camera pose (fix round 1, owner 2026-09-18: 4 raycasts every _process
## frame regardless of whether the camera moved), invalidated only when
## target, distance, yaw or the view's own size changes. Behaviour is
## identical to recomputing every frame; only the cost changes.
func _visible_ground() -> Rect2:
	if _ground_cache_valid and _ground_cache_target == _target and _ground_cache_distance == _distance \
			and _ground_cache_yaw == _yaw and _ground_cache_size == size:
		return _ground_cache
	var r := Rect2(_target, Vector2.ZERO)
	for f: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
		var hit: Variant = ground_at(size * f)
		r = r.expand(Vector2((hit as Vector3).x, (hit as Vector3).z) if hit != null
			else _target + Vector2(_distance, _distance) * (f * 2.0 - Vector2.ONE) * 2.0)
	_ground_cache = r
	_ground_cache_target = _target
	_ground_cache_distance = _distance
	_ground_cache_yaw = _yaw
	_ground_cache_size = size
	_ground_cache_valid = true
	return r


## Steps the cloud field and pushes it into the MultiMesh — called from
## _process every frame the view exists, even unhovered, so the sky keeps
## drifting and fading while the player looks elsewhere.
func _step_clouds(delta: float) -> void:
	if _cloud_field == null:
		return
	_cloud_field.step(delta, Game.clock_speed > 0, Game.clock_speed, _visible_ground(), _cloud_params)
	var h := _repo.bal("map3d_cloud_height_m")
	var n := _cloud_field.clouds.size()
	_cloud_mm.visible_instance_count = n
	for i in n:
		var c: Dictionary = _cloud_field.clouds[i]
		var s := float(c["size"])
		var basis := Basis(Vector3.UP, float(c["rot"])).scaled(Vector3(s, 1.0, s * _cloud_depth_ratio))
		var p := c["pos"] as Vector2
		_cloud_mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, h, p.y)))
		_cloud_mm.set_instance_color(i, Color(1, 1, 1, float(c["life"]) * _cloud_field.fade))


func sea_material() -> ShaderMaterial:
	return _sea_mat


## Test seam (fix round 1): the Rivers layer's material, to check the
## palette colours went in raw.
func river_material() -> ShaderMaterial:
	return _river_mat


## A ring material; its sizes are design px, turned into window px with the
## lines' by _update_line_scale (base values kept as meta). max_view_m is
## world metres, never rescaled. The keyline is a fixed data value (fix
## round 1: a pale ring was nearly invisible on bright grass at the old
## 0.55 default).
## A settlement's size on screen, design px: its ring, else its dot.
static func marker_px(spec: Dictionary) -> float:
	return maxf(float(spec.get("ring_px", 0.0)), float(spec.get("dot_px", 0.0)))


func _ring_material(colour: Color, ring_px: float, line_px: float, max_view_m: float,
		priority: int, dot_px := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("max_view_m", max_view_m)
	mat.set_shader_parameter("fade_start", _repo.bal("map3d_ring_fade_start"))
	var keyline := Color(0.08, 0.08, 0.08, _repo.bal("map3d_ring_keyline_alpha"))
	mat.set_shader_parameter("keyline", keyline)
	mat.set_meta("ring_px", ring_px)
	mat.set_meta("line_px", line_px)
	mat.set_meta("dot_px", dot_px)
	_ring_mats.append(mat)
	return mat


## Show the gold ring on a burg (or hide it with ""). It keeps the base
## stroke width at a larger diameter (fix round 1, owner 2026-09-18: the old
## 1.5x line width smeared it into a fat band over the tier ring instead of
## reading as a second crisp ring).
func _show_selected_ring(code: String) -> void:
	if _selected_ring == null:
		return
	_selected_ring.visible = code != ""
	if code == "":
		return
	var burg: Dictionary = _repo.burgs[code]
	var spec: Dictionary = _repo.map3d_settlements[String(burg.get("group", ""))]
	var xz := _burg_xz(burg)
	_selected_ring.multimesh.set_instance_transform(0,
		Transform3D(Basis.IDENTITY, Vector3(xz.x, _height_at(xz), xz.y)))
	var mat := _selected_ring.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var k := _repo.bal("map3d_selected_ring_scale")
	# A gold ring round the dot (or round the capital's own ring).
	mat.set_meta("ring_px", maxf(float(spec["ring_px"]), float(spec.get("dot_px", 0.0)) * 2.0) * k)
	mat.set_meta("line_px", maxf(float(spec["line_px"]), 2.0))
	_update_line_scale()


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
	_refresh_theme()  # a manor bought or a province taken recolours the ground
	var st := _state()
	var sig := 0 if st == null else hash([st.province_owner.hash(), st.manor_province.hash()])
	if sig == _border_sig and _lines.get_node_or_null("Kingdoms") != null:
		return
	_border_sig = sig
	_hover_lines.clear()
	_draw_hover()
	if _hud != null:
		_hud.refresh()  # the names follow the land held
	var step := _repo.bal("map3d_line_step_m")
	# The kingdom border (owner 2026-09-19, spec 2026-09-19-map3d-border-look,
	# replacing the thin solid black line of 2026-09-18): a band in the realm's
	# own colour inside each outline, fading inward — ONE mesh, the colour per
	# vertex; where two kingdoms meet each draws its band on its own side — a
	# pale halo, and the warm ink line over both.
	var rings: Array = []
	var bands: Array = []
	var band_colours: Array = []
	for code: String in _repo.kingdoms:
		var own := Map3DBorders.kingdom_lines(_repo, st, _meta, code, step)
		rings.append_array(own)
		var c := MapPalette.color_of(_repo, code)
		for r: PackedVector2Array in own:
			bands.append(Map3DBorders.inward(r))
			band_colours.append(c)
	var band := Color(1, 1, 1, _repo.bal("map3d_border_band_alpha"))
	_set_lines("KingdomBand", bands, band, band, "map3d_border_band_px", "", "",
		PRIORITY_KINGDOM_BAND, 0.0, true, band_colours, 1.0)
	var halo := MapPalette.named(_repo, "map3d_border_halo")
	halo.a = _repo.bal("map3d_border_halo_alpha")
	_set_lines("KingdomHalo", rings, halo, halo, "map3d_border_halo_px", "", "",
		PRIORITY_KINGDOM_HALO, _repo.bal("map3d_border_halo_soft"))
	var ink := MapPalette.named(_repo, "map3d_border")
	_set_lines("Kingdoms", rings, ink, ink, "map3d_border_width_px", "", "", PRIORITY_KINGDOMS)
	var seam := MapPalette.named(_repo, "map3d_seam")
	seam.a = _repo.bal("map3d_seam_alpha")
	_set_lines("Seams", Map3DBorders.seam_lines(_repo, st, _meta, step), seam,
		Color(seam, 0.0), "map3d_seam_width_px", "map3d_seam_dash_px", "map3d_seam_gap_px", PRIORITY_SEAMS)
	_draw_selection()


# --- the MANORS theme -------------------------------------------------------------

## Patch the world's Terrain3D shader for the manor tint (Map3DGroundTint).
## Without a Terrain3D (the tests' fixture) or when the addon's code no longer
## carries the line the patch rewrites, the ground simply stays plain.
func _prepare_ground_tint() -> void:
	var terrains := _world.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		return
	var mat: Resource = terrains[0].get("material")
	if mat == null:
		return
	mat.set("shader_override_enabled", true)
	var shader: Shader = mat.get("shader_override")
	var patched := "" if shader == null else Map3DGroundTint.patch(shader.code)
	if patched == "":
		mat.set("shader_override_enabled", false)
		push_warning("Map3DView: Terrain3D's shader has no line to tint — the themes leave the ground plain")
		return
	shader.code = patched
	_tint_mat = mat
	var origin: Array = _meta.get("pack_origin", [0.0, 0.0])
	mat.call("set_shader_param", "pack_origin", Vector2(float(origin[0]), float(origin[1])))
	mat.call("set_shader_param", "m_per_px", float(_meta.get("m_per_px", 50.0)))
	if _repo.cell_texture_path != "" and ResourceLoader.exists(_repo.cell_texture_path):
		mat.call("set_shader_param", "cell_index", load(_repo.cell_texture_path))
	mat.call("set_shader_param", "tint_mix", 0.0)
	# HEIGHTS (owner 2026-09-19): the ground's world height ramped through
	# terrain_palette heat_1..6, over 0..elevation_m_per_unit x
	# (100 - elevation_sea_level) metres.
	mat.call("set_shader_param", "heat_mix", 0.0)
	mat.call("set_shader_param", "heat_sea_y", float(_meta.get("sea_y", 0.0)))
	mat.call("set_shader_param", "heat_top_m",
		_repo.bal("elevation_m_per_unit") * (100.0 - _repo.bal("elevation_sea_level")))
	for i in 6:
		mat.call("set_shader_param", "heat_c%d" % i,
			MapTerrain.palette_color(_repo, "heat_%d" % (i + 1), MapTerrain.FALLBACK))
	# the bake's field map (owner 2026-09-19): furrows up close, the crops'
	# colour eased back far out; without it both stay off
	var fields := load_field_map(_scene_path)
	if fields != null:
		mat.call("set_shader_param", "field_map", fields)
		mat.call("set_shader_param", "field_m_per_texel", FIELD_MAP_M_PER_TEXEL)
		mat.call("set_shader_param", "furrow_m", _repo.bal("map3d_furrow_m"))
		mat.call("set_shader_param", "furrow_depth", _repo.bal("map3d_furrow_depth"))
		mat.call("set_shader_param", "field_fade", _repo.bal("map3d_field_fade"))
		mat.call("set_shader_param", "field_fade_near_m", _repo.bal("map3d_field_fade_near_m"))
		mat.call("set_shader_param", "field_fade_far_m", _repo.bal("map3d_field_fade_far_m"))


## The bake's field map beside a built scene (bake/fields.png — the bake dir
## is .gdignored, so it is read as a file, not imported), or null.
static func load_field_map(scene_path: String) -> Texture2D:
	var path := ProjectSettings.globalize_path(scene_path.get_base_dir().path_join("bake/fields.png"))
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return null if img == null else ImageTexture.create_from_image(img)


## Show a theme on the 3D ground: "manors", "heights", or "" for none —
## GameRoot hands it down with the 2D map's show_manors / show_heights.
func set_manor_theme(theme_name: String) -> void:
	_theme = theme_name
	# A manor is picked only under MANORS: leaving it forgets the clicked
	# manor and its gold outline.
	if _theme != "manors" and _selected_manor >= 0:
		_selected_manor = -1
		if _loaded:
			_draw_selection()
	_refresh_theme()


func manor_theme() -> String:
	return _theme


## The theme on the ground: MANORS' LUT (rebuilt when an owner turns), its
## tint and cell edges; HEIGHTS' heat mix. One theme at a time.
func _refresh_theme() -> void:
	_heat = _theme == "heights"
	if not _loaded:
		return
	var manors := _theme == "manors"
	if manors:
		var st := _state()
		var sig := hash([_theme, 0 if st == null else st.province_owner.hash(),
			0 if st == null else st.manor_owner.hash(),
			0 if st == null else st.manor_province.hash()])
		if sig != _theme_sig or _cell_lut == null:
			_theme_sig = sig
			_build_lut()
		if not _edges_built:
			_build_manor_edges()
	if _tint_mat != null:
		_tint_mat.call("set_shader_param", "tint_mix",
			_repo.bal("map3d_manor_tint") if manors else 0.0)
		_tint_mat.call("set_shader_param", "heat_mix",
			_repo.bal("map3d_heat_tint") if _heat else 0.0)
	var edges := _lines.get_node_or_null("ManorEdges") as MeshInstance3D
	if edges != null:
		edges.visible = manors
	if _hud != null:
		_hud.refresh()


## Test seam: whether the HEIGHTS heat is on the ground.
func heat_on() -> bool:
	return _heat


## Each land cell's ManorPalette colour for the theme at texel (id % w, id / w).
func _build_lut() -> void:
	var max_id := 0
	for id: int in _repo.cells:
		max_id = maxi(max_id, id)
	var lut := Map3DGroundTint.lut_size(max_id)
	var img := Image.create(lut.x, lut.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := _state()
	for id: int in _repo.cells:
		img.set_pixel(id % lut.x, id / lut.x, ManorPalette.theme_color(_repo, st, id, _theme))
	_lut_image = img
	if _cell_lut != null and _cell_lut.get_size() == Vector2(lut):
		_cell_lut.update(img)
	else:
		_cell_lut = ImageTexture.create_from_image(img)
	if _tint_mat != null:
		_tint_mat.call("set_shader_param", "cell_lut", _cell_lut)
		_tint_mat.call("set_shader_param", "lut_size", lut)


## The cell edges (ManorPalette.edges, the 2D map's own) as constant-width
## ribbons on the relief, in the 2D map's manor_line ink, alpha and width.
## Geometry: laid on the first theme and kept.
func _build_manor_edges() -> void:
	_edges_built = true
	var step := _repo.bal("map3d_line_step_m")
	var pairs := ManorPalette.edges(_repo)
	var lines: Array = []
	for i in range(0, pairs.size() - 1, 2):
		var seg := PackedVector2Array([Map3DGeometry.pack_to_world(_meta, pairs[i]),
			Map3DGeometry.pack_to_world(_meta, pairs[i + 1])])
		lines.append(Map3DGeometry.resample(seg, step))
	var ink := MapPalette.named(_repo, "manor_line")
	ink.a = _repo.bal("map_manor_line_alpha")
	_set_lines("ManorEdges", lines, ink, ink, "map_manor_line_width", "", "", PRIORITY_MANOR_EDGES)


## Test seam: the LUT the terrain shader reads (null before the first theme).
func cell_lut() -> ImageTexture:
	return _cell_lut


## Test seam: the colour the LUT holds for cell `id` (clear before a theme).
func lut_color(id: int) -> Color:
	if _lut_image == null:
		return Color(0, 0, 0, 0)
	var w := _lut_image.get_width()
	return _lut_image.get_pixel(id % w, id / w)


## The roads and trails (owner 2026-09-18): the pack's land routes, smoothed
## as the 2D map smooths them, draped on the relief. Since 2026-09-19 (owner:
## a packed earth-and-stone road) each is drawn at its REAL width in the
## rocky_trail_02 texture up close, fading to the worn-sand palette colour
## (terrain_palette map3d_road / map3d_trail) far away, where a screen-px
## floor keeps it a track (road_line.gdshader); and wherever one crosses a
## river it runs over a stone BRIDGE (Map3DBridges). Routes never move, so
## they are built once, after the rivers; sea lanes are not roads.
func _build_roads() -> void:
	var step := _repo.bal("map3d_road_step_m")
	var all_bridges: Array = []
	for group: String in ["roads", "trails"]:
		var key := "road" if group == "roads" else "trail"
		var colour := MapTerrain.palette_color(_repo, "map3d_" + key, MapTerrain.FALLBACK)
		colour.a = _repo.bal("map3d_%s_alpha" % key)
		var width_m := _repo.bal("map3d_%s_width_m" % key)
		var plan := Map3DBridges.plan(Map3DBorders.route_lines(_repo, _meta, group, step),
			_river_courses, _height_at, bridge_rules())
		_set_road(group.capitalize(), plan["lines"], plan["heights"], colour,
			"map3d_%s_width_px" % key, width_m)
		var deck_w := width_m + _repo.bal("map3d_bridge_extra_w_m")
		for b: Dictionary in plan["bridges"]:
			b["deck_w"] = deck_w
		all_bridges.append_array(plan["bridges"])
	_build_bridges(all_bridges)


## balance.csv map3d_bridge_* as Map3DBridges' rules.
func bridge_rules() -> Dictionary:
	var rules: Dictionary = {}
	for key: String in ["abut_m", "clear_m", "clear_per_width", "hump_m", "min_sin", "merge_m",
			"deck_step_m", "deck_m", "parapet_h_m", "parapet_w_m", "arch_max_m", "pier_m",
			"end_over_water_m"]:
		rules[key] = _repo.bal("map3d_bridge_" + key)
	return rules


## Test seam: every bridge built, [{a, b, ya, yb, crown, water_y, width, deck_w}].
func bridges() -> Array:
	return _bridge_list


## A packed Poly Haven pair (<base>_alb_ht / <base>_nrm_rgh), or [] when the
## textures folder has not been built.
static func _texture_pair(base: String) -> Array:
	if not ResourceLoader.exists(base + "_alb_ht.png") or not ResourceLoader.exists(base + "_nrm_rgh.png"):
		return []
	return [load(base + "_alb_ht.png"), load(base + "_nrm_rgh.png")]


## One road layer under Lines/<name>, replacing any before: the ribbons of
## `lines` on the ground (or on a bridge deck where `heights` says so).
func _set_road(line_name: String, lines: Array, heights: Array, colour: Color,
		width_key: String, width_m: float) -> void:
	var old := _lines.get_node_or_null(line_name)
	if old != null:
		_lines.remove_child(old)
		old.queue_free()
	var arrays := Map3DBorders.ribbon_arrays(lines, _height_at, heights)
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = ROAD_SHADER
	mat.render_priority = PRIORITY_ROADS
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("width_m", width_m)
	mat.set_shader_parameter("edge_soft", _repo.bal("map3d_road_edge_soft"))
	mat.set_shader_parameter("fray", _repo.bal("map3d_road_fray"))
	mat.set_shader_parameter("tile_m", _repo.bal("map3d_road_tile_m"))
	mat.set_shader_parameter("near_mpp", _repo.bal("map3d_road_near_mpp"))
	mat.set_shader_parameter("far_mpp", _repo.bal("map3d_road_far_mpp"))
	var gain := _repo.bal("map3d_road_texture_gain")
	var tint := MapTerrain.palette_color(_repo, "map3d_road_surface", Color.WHITE)
	mat.set_shader_parameter("surface_tint", Vector3(tint.r, tint.g, tint.b) * gain)
	var pair := _texture_pair(ROAD_TEXTURE)
	mat.set_shader_parameter("has_surface", not pair.is_empty())
	if not pair.is_empty():
		mat.set_shader_parameter("surface", pair[0])
		mat.set_shader_parameter("surface_nrm", pair[1])
	mat.set_meta("width_key", width_key)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = line_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	_lines.add_child(mi)
	_update_line_scale()


## Every bridge as ONE mesh in the medieval_blocks_03 stone, lit and casting
## shadows like the ground; replaces any before.
func _build_bridges(list: Array) -> void:
	_bridge_list = list
	var old := _viewport.get_node_or_null("Bridges") if _viewport != null else null
	if old != null:
		_viewport.remove_child(old)
		old.queue_free()
	if list.is_empty() or _viewport == null:
		return
	var rules := bridge_rules()
	var tile := _repo.bal("map3d_bridge_tile_m")
	var mesh := ArrayMesh.new()
	# one deck width per group, so one mesh per width
	var by_w: Dictionary = {}
	for b: Dictionary in list:
		var w := float(b["deck_w"])
		if not by_w.has(w):
			by_w[w] = []
		(by_w[w] as Array).append(b)
	for w: float in by_w:
		var arrays := Map3DBridges.mesh_arrays(by_w[w], w, rules, tile)
		if not arrays.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() == 0:
		return
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = MapTerrain.palette_color(_repo, "map3d_bridge", Color("#8A7F70"))
	mat.roughness = 0.9
	# Fade out far away, per pixel (the mesh spans the world, so a
	# visibility range, measured to its centre, would hide every bridge):
	# a min distance past the max inverts Godot's distance fade.
	var far := _repo.bal("map3d_bridge_max_view_m")
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_min_distance = far
	mat.distance_fade_max_distance = far * 0.8
	var pair := _texture_pair(BRIDGE_TEXTURE)
	if not pair.is_empty():
		mat.albedo_texture = pair[0]
		mat.normal_enabled = true
		mat.normal_texture = pair[1]
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Bridges"
	mi.mesh = mesh
	_viewport.add_child(mi)


## One MeshInstance3D of ribbons under Lines/<name>, replacing any before.
## `priority` is the line's row of the render-priority table (PRIORITY_*);
## `edge_soft` fades the ribbon toward its sides (border_line.gdshader);
## `one_sided` lays it from the line to one side (Map3DBorders.ribbon_arrays),
## `colours` a Color per line drawn in place of `a`'s rgb, and `fade_across`
## fades it away from the line (the realm band).
func _set_lines(line_name: String, lines: Array, a: Color, b: Color, width_key: String,
		dash_key: String, gap_key: String, priority: int, edge_soft := 0.0,
		one_sided := false, colours: Array = [], fade_across := 0.0) -> void:
	var old := _lines.get_node_or_null(line_name)
	if old != null:
		_lines.remove_child(old)
		old.queue_free()
	var arrays := Map3DBorders.ribbon_arrays(lines, _height_at, [], one_sided, colours)
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = BORDER_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("colour_a", a)
	mat.set_shader_parameter("colour_b", b)
	mat.set_shader_parameter("edge_soft", edge_soft)
	mat.set_shader_parameter("one_sided", 1.0 if one_sided else 0.0)
	mat.set_shader_parameter("use_vertex_colour", 1.0 if not colours.is_empty() else 0.0)
	mat.set_shader_parameter("fade_across", fade_across)
	mat.set_shader_parameter("fade_power", _repo.bal("map3d_border_band_fade_power") if fade_across > 0.0 else 1.0)
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
	if _repo == null or _viewport == null:
		return
	var s := _render_scale()
	var h := float(maxi(_viewport.size.y, 1))
	var per_dist := 2.0 * tan(deg_to_rad(_repo.bal("map3d_fov_deg")) * 0.5) / h
	if _lines != null:
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
	for mat: ShaderMaterial in _ring_mats:
		mat.set_shader_parameter("px_per_dist", per_dist)
		mat.set_shader_parameter("lift_px", _repo.bal("map3d_ring_lift_px") * s)
		mat.set_shader_parameter("ring_px", float(mat.get_meta("ring_px")) * s)
		mat.set_shader_parameter("line_px", float(mat.get_meta("line_px")) * s)
		mat.set_shader_parameter("dot_px", float(mat.get_meta("dot_px", 0.0)) * s)
	if _river_mat != null:
		_river_mat.set_shader_parameter("px_per_dist", per_dist)
		_river_mat.set_shader_parameter("min_px", _repo.bal("map3d_river_min_px") * s)


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

func _apply_camera() -> void:
	if _camera == null:
		return
	var pitch := Map3DGeometry.pitch_for(_distance, _repo.bal("map3d_zoom_min_m"),
		_repo.bal("map3d_zoom_max_m"), _repo.bal("map3d_pitch_near_deg"),
		_repo.bal("map3d_pitch_far_deg"))
	var ground := Vector3(_target.x, _height_at(_target), _target.y)
	_camera.transform = Map3DGeometry.pose(ground, _distance, _yaw, pitch)
	if _hud != null:
		_hud.refresh()


func _metres_per_pixel() -> float:
	return Map3DGeometry.metres_per_pixel(_distance, _repo.bal("map3d_fov_deg"),
		maxf(size.y, 1.0))

## Ground metres under one screen pixel at the target — the HUD's scale bar.
func metres_per_pixel() -> float:
	return _metres_per_pixel()


func _pan_by(screen_delta: Vector2) -> void:
	_target = Map3DGeometry.clamp_target(
		_target + Map3DGeometry.pan_delta(screen_delta, _metres_per_pixel(), _yaw), _bounds)
	_apply_camera()


## Zoom to `new_distance` (clamped) keeping the ground under `pos` under it.
func _zoom_at(pos: Vector2, new_distance: float) -> void:
	var anchor: Variant = ground_at(pos)
	var d := Map3DGeometry.zoomed_by(new_distance, 1.0, _repo.bal("map3d_zoom_min_m"),
		_repo.bal("map3d_zoom_max_m"))
	if anchor != null:
		var a := anchor as Vector3
		_target = Map3DGeometry.clamp_target(
			Map3DGeometry.zoom_about(_target, Vector2(a.x, a.z), _distance, d), _bounds)
	_distance = d
	_apply_camera()


func _gui_input(event: InputEvent) -> void:
	if not _loaded:
		return
	# macOS trackpad (as on the 2D map): pinch zooms about the fingers,
	# two-finger drag pans. The wheel still works exactly as before.
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		var gain := _repo.bal("map3d_pinch_zoom_gain")
		_zoom_at(mg.position, _distance / maxf(1.0 + (mg.factor - 1.0) * gain, 0.01))
		accept_event()
		return
	if event is InputEventPanGesture:
		_pan_by(-(event as InputEventPanGesture).delta * _repo.bal("map3d_pan_gesture_px"))
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var steps := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			_zoom_at(mb.position, _distance * pow(_repo.bal("map3d_zoom_factor"), steps))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _hud != null and _hud.compass_rect().has_point(mb.position):
				_north_from = _yaw
				_north_t = 0.0
				_press_on_hud = true
				# Kept in step with the ordinary press below: a stale
				# _press_pos/_dragging from an earlier drag would let a
				# press-and-move on the compass pan from that old point.
				_press_pos = mb.position
				_dragging = false
				accept_event()
				return
			if not mb.pressed and _press_on_hud:
				_press_on_hud = false
				accept_event()
				return
			if mb.pressed:
				_press_pos = mb.position
				_dragging = false
			elif not _dragging:
				if ruler_on:
					_ruler_click(mb.position)
				else:
					select_at(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rpress_pos = mb.position
				_rdragged = false
			elif ruler_on and not _rdragged and _ruler.cancel() and _hud != null:
				_hud.refresh()
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	if ruler_on and _ruler.phase == MapRuler.Phase.STRETCHING:
		var hit: Variant = ground_at(mm.position)
		if hit != null and _ruler.move(Vector2((hit as Vector3).x, (hit as Vector3).z)) \
				and _hud != null:
			_hud.refresh()
	if mm.button_mask == 0:
		_hover_pos = mm.position
		_hover_pending = true
	else:
		clear_hover()
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _press_on_hud:
			accept_event()
			return
		if not _dragging and _press_pos.distance_to(mm.position) > CLICK_SLOP:
			_dragging = true
		if _dragging:
			_pan_by(mm.relative)
		accept_event()
	elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_pan_by(mm.relative)
		accept_event()
	elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		if _rpress_pos.distance_to(mm.position) > CLICK_SLOP:
			_rdragged = true
		_north_t = -1.0
		_yaw -= mm.relative.x * _repo.bal("map3d_rotate_deg_per_px")
		_apply_camera()
		accept_event()


## WASD / arrows pan while the pointer is over the view and no text box has
## the keyboard; ownership is checked for new borders every few seconds.
func _process(delta: float) -> void:
	if _north_t >= 0.0:
		_north_t += delta / maxf(_repo.bal("map3d_compass_reset_s"), 0.01)
		_yaw = Map3DGeometry.ease_yaw(_north_from, _north_t)
		if _north_t >= 1.0:
			_north_t = -1.0
			_yaw = 0.0
		_apply_camera()
	_border_clock += delta
	if _border_clock >= _repo.bal("map3d_border_refresh_s"):
		_border_clock = 0.0
		refresh_borders()
	_step_clouds(delta)
	if _hover_pending:
		_hover_pending = false
		hover_pick(pick_at(_hover_pos), _hover_pos)
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
	_hover_pending = true  # the ground moved under a still pointer


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
	if _theme != "manors" or _camera == null:
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
		var xz := Map3DGeometry.pack_to_world(_meta, MapTerrain.cell_center(_repo, _repo.cells[id]))
		var ground := Vector3(xz.x, _height_at(xz), xz.y)
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
	var out: Array = []
	var s := _render_scale()
	var eye := _camera.global_position
	var fade_start := _repo.bal("map3d_ring_fade_start")
	for code: String in _sorted_burgs():
		var burg: Dictionary = _repo.burgs[code]
		var spec: Dictionary = _repo.map3d_settlements[String(burg.get("group", ""))]
		var bxz := _burg_xz(burg)
		var world := Vector3(bxz.x, _height_at(bxz), bxz.y)
		if eye.distance_to(world) >= float(spec["max_view_m"]) * fade_start \
				or _camera.is_position_behind(world):
			continue
		var c := _camera.unproject_position(world) / s
		var r := marker_px(spec) * 0.5 + 2.0
		out.append(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


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
	if not _heat or _camera == null or not _loaded:
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
	if _distance >= _repo.bal("map3d_landmark_lod_far_view_m"):
		max_lod = 0
	elif _distance >= _repo.bal("map3d_landmark_lod_mid_view_m"):
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
		var xz := Map3DGeometry.pack_to_world(_meta, m["pos"])
		var ground := Vector3(xz.x, _height_at(xz), xz.y)
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
	if not _heat:
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
	if _camera == null:
		return null
	var px := pos * _render_scale()
	return Map3DGeometry.ground_hit(_camera.project_ray_origin(px),
		_camera.project_ray_normal(px), _height_at)


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
	var s := _render_scale()
	var click_px := pos * s
	var best := ""
	var best_d := INF
	var fade_start := _repo.bal("map3d_ring_fade_start")
	var eye := _camera.global_position
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
	for code: String in _sorted_burgs():
		var burg: Dictionary = _repo.burgs[code]
		var spec: Dictionary = _repo.map3d_settlements[String(burg.get("group", ""))]
		var bxz := _burg_xz(burg)
		var world := Vector3(bxz.x, _height_at(bxz), bxz.y)
		if eye.distance_to(world) >= float(spec["max_view_m"]) * fade_start:
			continue
		var screen_px := _camera.unproject_position(world)
		var reach := maxf(marker_px(spec) * 0.5, _repo.bal("map3d_pick_px")) * s
		var d := screen_px.distance_to(click_px)
		if d <= reach and d < best_d and _camera.is_position_behind(world) == false:
			best_d = d
			best = code
			best_dot = (marker_px(spec) * 0.5 + 2.0) * s
	# Under HEIGHTS a high or low point (spec 2026-09-19-map3d-heights), ranked
	# against the settlements (Task 7): a click ON a settlement's dot is the
	# settlement's, a click on a mark is the mark's, then a settlement's reach,
	# and last the mark's rect grown by half the pick reach.
	if best != "" and best_d <= best_dot:
		return {"kind": "burg", "code": best}
	var marks := landmark_marks() if _heat else []
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
	if _theme == "manors":
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


## The hovered kingdom's live outline in the border's own ink, wider — the
## 2D map's hover ribbon (map3d_hover_border_width_px).
func _draw_hover() -> void:
	if not _loaded:
		return
	var lines: Array = []
	if _hover_kingdom != "":
		if not _hover_lines.has(_hover_kingdom):
			_hover_lines[_hover_kingdom] = Map3DBorders.kingdom_lines(_repo, _state(), _meta,
				_hover_kingdom, _repo.bal("map3d_line_step_m"))
		lines = _hover_lines[_hover_kingdom]
	var ink := MapPalette.named(_repo, "map3d_border")
	_set_lines("Hover", lines, ink, ink, "map3d_hover_border_width_px", "", "", PRIORITY_HOVER)


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


## Test seams.
func is_loaded() -> bool:
	return _loaded

func notice() -> Label:
	return _notice

func viewport() -> SubViewport:
	return _viewport

func camera() -> Camera3D:
	return _camera

func cloud_count() -> int:
	return _cloud_mm.visible_instance_count if _cloud_mm != null else 0

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

func selected_manor() -> int:
	return _selected_manor

## Whether the clicked settlement's gold ring is currently shown.
func selected_ring_visible() -> bool:
	return _selected_ring != null and _selected_ring.visible

## Centre the rig on a pack point (tests and future "go to" orders).
func look_at_pack(pack_px: Vector2, at_distance: float = -1.0) -> void:
	_target = Map3DGeometry.clamp_target(Map3DGeometry.pack_to_world(_meta, pack_px), _bounds)
	if at_distance > 0.0:
		_distance = at_distance
	_apply_camera()

## Frame the player's capital at a distance (the bench and the snapshots).
func look_at_home(at_distance: float) -> void:
	_target = Map3DGeometry.clamp_target(_home(), _bounds)
	_distance = at_distance
	_apply_camera()

## Layers the bench can switch off to price them, those that exist: the
## view's nodes under the viewport, the build's Sea, the Sun's shadows, the HUD.
func layer_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in ["Markers", "Lines", "Rivers", "Clouds"]:
		if _viewport.get_node_or_null(n) != null:
			out.append(n)
	if _world != null and _world.get_node_or_null("Sea") != null:
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
			(_world.get_node("Sea") as Node3D).visible = on
		"Hud":
			(get_node("Hud") as CanvasItem).visible = on
		_:
			(_viewport.get_node(layer) as Node3D).visible = on

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
		if mmi.name == "Selected":
			continue
		out[mmi.name.to_lower()] = mmi.multimesh.instance_count
	return out
