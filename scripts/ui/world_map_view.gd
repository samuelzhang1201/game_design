class_name WorldMapView
extends Control
## RTS-style viewport into the loaded map pack's terrain, embedded in the
## middle map zone of every gameplay screen — court, conversation, day run
## (user ruling 2026-09-03: the world map IS the middle view — it replaces
## UiPalette's static backdrop there, and the bottom bar's MAP tab goes
## back to meaning "close overlays"). The map
## opens covering the frame, and zooms out to the whole world; the view
## pans when the mouse rides an edge
## of the frame (plus drag and wheel-zoom), every kingdom is washed in its
## palette colour with its live border drawn (the terrain is a mesh built
## from the pack's cells, MapTerrain),
## the kingdom under the mouse gets its outline lit, towns and points of interest show
## as pins (LOD by zoom, MapObjects), hovering a pin or road names it,
## and clicking a kingdom opens a
## floating info card resolved through the world_state_index.png bitmap
## (tools/import_azgaar.gd) via MapIndex. View-only: reads Game.data,
## never mutates game state.

## A card's ASK THE COUNCIL button: the screen owning an input box puts this
## text in it (nothing is sent until the player presses Enter).
signal place_asked(text: String)
## The kingdom under the cursor changed — its kingdom_code, or "" for water,
## open sea, or no map. Screens use it to swap their left column to the
## country's card while the cursor is over that terrain.
signal country_hovered(kingdom_code: String)
## The province view was switched on or off (the P key, or a screen).
signal province_view_changed(on: bool)
## The relief view was switched on or off (the H key, or a screen).
signal height_view_changed(on: bool)
## The economy view was switched on or off (the E key, or a screen).
signal economy_view_changed(on: bool)
signal manor_view_changed(on: bool)
## In the province view, the province under a click — its province_code, or
## "" for water / nothing — so a screen's left column can show its account.
signal province_selected(province_code: String)
## The described entry of the object under a click ({title, lines, ask}), or
## {} when water / nothing was clicked. Screens with a fact column take
## this and switch the floating card off (use_card).
signal object_selected(entry: Dictionary)

const ZOOM_MAX := 16.0
const ZOOM_STEP := 1.2
## A press/release pair further apart than this is a drag, not a click.
const CLICK_SLOP := 10.0
## Mouse within this many px of the frame edge scrolls the view (RTS-style).
const EDGE_MARGIN := 24.0
## Edge-scroll speed in screen px/s.
const EDGE_SPEED := 520.0
## The terrain is drawn from data (spec 2026-09-11): the game paints every
## province in its live owner's colour (MapPalette, data/political_palette.csv)
## and draws every kingdom's border itself, so conquest repaints and redraws
## with no new art. The hovered kingdom's outline is drawn over that in the
## palette's hover colour; widths and opacities live in balance.csv.
## Debug-build shortcut for the territory demo (dev_flip_hovered_province).
const DEV_FLIP_KEY := KEY_T
## Pin sizes in screen px (constant at any zoom; LOD hides the small ones).
const PIN_CAPITAL := 8.0
const PIN_TOWN := 5.0
const PIN_VILLAGE := 3.0
const PIN_MARKER := 6.0
const PIN_OUTLINE := Color(0.05, 0.04, 0.02, 0.9)
const TOOLTIP_OFFSET := Vector2(20.0, 24.0)
const SCENE_PATH := "res://scenes/world_map.tscn"
## Province view (user request 2026-09-09): every kingdom's internal seams as
## light dashed lines, computed from the provinces it holds NOW
## (MapOwnership.seams_of), so they follow conquest where the render's
## printed dots cannot (no names on the map, user ruling 2026-09-09); a click
## names the province under it (province_selected) for the screen's left column.
## ON from the first frame (owner request 2026-09-12) and never toggled by
## the player since 2026-09-13 (owner): the seams and the province clicks
## are part of the map. The flag stays for tools and tests.
## The relief view (owner request 2026-09-12).
const HEIGHT_KEY := KEY_H
## The economy view (owner request 2026-09-13).
const ECONOMY_KEY := KEY_E
var show_provinces: bool = true:
	set(v):
		if v == show_provinces:
			return
		show_provinces = v
		if not v and _selected_province != "":
			_selected_province = ""
			province_selected.emit("")
		province_view_changed.emit(v)
		queue_redraw()
## The HEIGHTS view (owner request 2026-09-12): the default sheet carries no
## height shading at all — a wide land colour band read as relief and made
## the map look blurry and half-transparent — so the relief gets a layer of
## its own, drawn as a HEAT MAP over the land (MapTerrain.heat_mesh) —
## contour lines were tried first and read badly. Off by default.
var show_heights: bool = false:
	set(v):
		if v == show_heights:
			return
		show_heights = v
		height_view_changed.emit(v)
		queue_redraw()

## The ECONOMY view (owner request 2026-09-13): the land as its manors, each
## washed by its holder and the worth of its land, the working ones marked
## with what they make and how much (see manor_mesh / manor_badges).
## Thematic like HEIGHTS, so it replaces the political wash rather than
## sitting on top of it — one map, one theme.
var show_economy: bool = false:
	set(v):
		if v == show_economy:
			return
		show_economy = v
		economy_view_changed.emit(v)
		queue_redraw()

## The MANORS view (MANOR_SYSTEM.md §6, owner 2026-09-13): the land as its
## manors coloured by the HOUSE that holds each — the crown in its realm's
## colour, every other house in a hue of its own (MapPalette.house_color),
## foreign land paled — and a click on a manor opens its card. Thematic
## like ECONOMY: GameRoot keeps the three themes exclusive.
var show_manors: bool = false:
	set(v):
		if v == show_manors:
			return
		show_manors = v
		manor_view_changed.emit(v)
		queue_redraw()

## The military layer (user request 2026-09-10): the player's own regiments
## drawn where the pack quarters them, each as a counter stating its
## headcount (army_markers). Only the player's host shows (owner
## ruling 2026-09-10) — a king knows his own musters, not everyone's.
## Toggled by the bottom bar's MILITARY tab.
var show_armies: bool = false:
	set(v):
		if v == show_armies:
			return
		show_armies = v
		queue_redraw()
## The province selected in the province view ("" when none); drawn tinted.
var _selected_province := ""
## Per province loop: its triangle indices (native coordinates, so they never
## change with the view) and bounding box, built once so the political wash
## costs one triangle-array call per loop per frame.
var _province_tris: Dictionary = {}
var _province_bbox: Dictionary = {}

## The terrain (spec 2026-09-11): one vertex-coloured mesh of every cell,
## built once from the pack (MapTerrain) and drawn with the view transform.
## No render PNG exists; the map's extent is the pack's canvas.
var _terrain_mesh: ArrayMesh
var _map_size := Vector2.ZERO
## Shore loops (coasts.csv) smoothed once, drawn over the mesh.
var _coast_rings: Array = []
## The sea: four bands over the pack's distance field, drawn behind this
## item (SeaLayer, owner 2026-09-13). Test seam: sea_layer().
var _sea: SeaLayer
## Every dashed line on the sheet — borders, hatching, seams, lanes — cut
## once per zoom in native px and kept (MapDashCache); a frame transforms
## and draws each set as ONE polyline. Test seam: dash_cache().
var _dashes := MapDashCache.new()
var _index_image: Image
var _by_state_id: Dictionary = {}
## Azgaar state id under the mouse (-1: water/nothing); its border loops
## are outlined in _draw.
var _hover_sid := -1
var _province_image: Image
## world_cell_index.png: the manor under a pixel, read only while a layer
## that shows manors is up (MANOR_SYSTEM.md §6).
var _cell_image: Image
var _biome_image: Image
## The pin/line/land under the mouse (MapObjects.object_at); {} before any hover.
var _hover_obj: Dictionary = {}
var _tooltip: Label
var _card: MapInfoCard
## What the open card describes ({} when closed); drawn highlighted.
var _selected_obj: Dictionary = {}
var _offset := Vector2.ZERO
var _zoom := 1.0
var _homed := false
var _dragging := false
var _press_pos := Vector2.ZERO
## Edge scrolling only while the pointer is really over the map (real
## mouse_entered events — the headless test runner's phantom (0,0) mouse
## must never pan the view).
var _mouse_inside := false

## Every screen builds the map through here (user request 2026-09-08): it is a
## scene like the character portraits and location views, so it can be opened
## in the editor and decorated with child nodes. Those children draw beneath
## the info card and tooltip, which _ready appends after them.
static func create() -> WorldMapView:
	return load(SCENE_PATH).instantiate()

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The project default is nearest (crisp pixel fonts); the settlement art
	# and the mesh want smooth scaling. The card resets to nearest so its text
	# matches the rest of the UI.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# The parchment grain is one small tile drawn over the whole frame.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Which map is loaded is data (data/maps.csv), not a constant here — the
	# view renders whichever pack DataRepository.load_map put in place.
	_map_size = Vector2(float(Game.data.map_info.get("width", "0")),
		float(Game.data.map_info.get("height", "0")))
	if _map_size.x > 0.0 and _map_size.y > 0.0:
		_terrain_mesh = MapTerrain.shared_mesh(Game.data)
	_sea = SeaLayer.new()
	_sea.name = "Sea"
	add_child(_sea)
	move_child(_sea, 0)
	_sea.setup(Game.data)
	var index_path := Game.data.index_texture_path
	if index_path != "" and ResourceLoader.exists(index_path):
		var idx: Texture2D = load(index_path)
		_index_image = idx.get_image()
	_province_image = _load_image(Game.data.province_texture_path)
	_cell_image = _load_image(Game.data.cell_texture_path)
	_biome_image = _load_image(Game.data.biome_texture_path)
	_build_coast_rings()
	for code: String in Game.data.kingdoms:
		var row: Dictionary = Game.data.kingdoms[code]
		_by_state_id[int(row["state_id"])] = row
	_build_province_meshes()
	_card = MapInfoCard.new()
	_card.ask_requested.connect(func(text: String) -> void: place_asked.emit(text))
	_card.closed.connect(func() -> void:
		_selected_obj = {}
		queue_redraw())
	add_child(_card)
	_build_tooltip()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void:
		_mouse_inside = false
		hover_state(-1)
		hover_object({}))
	resized.connect(func() -> void:
		_clamp_offset()
		queue_redraw())
	# No imported map: stay invisible so the styled backdrop shows instead.
	visible = _terrain_mesh != null

func _load_image(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return (load(path) as Texture2D).get_image()

func _build_tooltip() -> void:
	_tooltip = Label.new()
	_tooltip.name = "Tooltip"
	_tooltip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	_tooltip.add_theme_font_size_override("font_size", 16)
	_tooltip.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_tooltip.hide()
	add_child(_tooltip)

## Initial framing: the map covers the frame edge to edge, so the middle
## column never shows dead gutter. The map is far wider in proportion than
## the column (2.76:1 into roughly 1.3:1), so a contain fit here would waste
## about half the column's height on empty bands — this crops the outer
## ocean instead, and one wheel-down reaches _zoom_min where the whole world
## is visible.
## Where the map opens (owner request 2026-09-12): close enough to read, on
## the player's own capital. With no campaign loaded — the menu draws the map
## too — it falls back to covering the whole world.
func _go_home() -> void:
	_zoom = maxf(_zoom_cover(), _zoom_min())
	_offset = (size - _map_size * _zoom) / 2.0
	var at := home_anchor()
	if at != Vector2.ZERO:
		_zoom = clampf(Game.data.bal("map_home_scale"), _zoom_min(), ZOOM_MAX)
		_offset = size / 2.0 - at * _zoom
	_clamp_offset()
	_homed = true

## The player's capital in native coordinates, or ZERO when no realm is
## bound. Public for tests.
func home_anchor() -> Vector2:
	var realm: Dictionary = Game.data.kingdoms.get(
		Game.data.resolve_realm("player_realm"), {})
	if realm.is_empty():
		return Vector2.ZERO
	var burg: Dictionary = Game.data.burgs.get(String(realm.get("capital_burg", "")), {})
	if burg.is_empty():
		return Vector2.ZERO
	return Vector2(float(burg["x"]), float(burg["y"]))

## Fill both axes, cropping whichever one overflows.
func _zoom_cover() -> float:
	var tex := _map_size
	if tex.x <= 0.0 or tex.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.1
	return maxf(size.x / tex.x, size.y / tex.y)

## Frame profiling for tools/bench_map.gd (owner request 2026-09-13: measure
## how smoothly the map pans). When on, _draw adds each layer's wall-clock
## cost in microseconds to draw_profile. Off in the game. A view concern
## only — simulation code never reads the clock.
var profile_draw := false
var draw_profile: Dictionary = {}

func _layer(layer: String, work: Callable) -> void:
	if not profile_draw:
		work.call()
		return
	var t0 := Time.get_ticks_usec()
	work.call()
	draw_profile[layer] = int(draw_profile.get(layer, 0)) + Time.get_ticks_usec() - t0

func _draw() -> void:
	if _terrain_mesh == null:
		return
	if not _homed and size.y > 0.0:
		_go_home()
	_layer("terrain", func() -> void:
		# The sea is the SeaLayer child behind this item; it follows the
		# view's transform. The land mesh is drawn over it.
		_sea.position = _offset
		_sea.scale = Vector2(_zoom, _zoom)
		draw_mesh(_terrain_mesh, null, Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset)))
	_layer("heights", _draw_heights)
	_layer("paper", _draw_paper_grain)
	_layer("sea_decor", _draw_sea_decor)
	# The wash goes UNDER the water and the roads (owner 2026-09-12, after
	# mapSample.jpg): painted over them it muted every river and track on
	# claimed land, which is most of the map.
	_layer("wash", _draw_political_wash)
	# Filled in place, never reassigned: a lambda captures the local by value,
	# so `manors = ...` inside it left the badges layer below reading [].
	var manors: Array = []
	_layer("manors", func() -> void:
		manors.append_array(working_manors())
		_draw_manors(manors))
	_layer("rivers", _draw_rivers)
	_layer("routes", _draw_routes)
	# Above the water and the roads (owner request 2026-09-12): a wood drawn
	# under them was being cut in half by every stream that crossed it.
	_layer("decor", _draw_terrain_decor)
	_layer("seams", _draw_province_seams)
	_layer("selected", _draw_selected_province)
	_layer("borders", _draw_state_borders)
	# The shore goes ON TOP of the borders (owner 2026-09-12): a coastal
	# kingdom's outline follows its coast, and the chequered ribbon was
	# breaking the one line that tells land from sea. Where the two run
	# together the shore wins, which is the right answer — at a coast the
	# border is saying nothing the water does not already say.
	_layer("coasts", _draw_coasts)
	_layer("labels", _draw_kingdom_labels)
	_layer("pins", _draw_pins)
	_layer("badges", func() -> void: _draw_manor_badges(_place_badges(manors)))
	_layer("armies", _draw_armies)
	_draw_object_highlight(_selected_obj)
	_layer("vignette", _draw_paper_vignette)
	_layer("scale", _draw_scale_bar)
	_layer("compass", _draw_compass)

## Screen px per native map px — the LOD and pick radii are defined on it.
func view_scale() -> float:
	return _zoom

func _pin_radius(b: Dictionary) -> float:
	if String(b["is_capital"]) == "1":
		return PIN_CAPITAL
	return PIN_TOWN if int(float(b["population"])) >= int(Game.data.bal("map_lod_town_pop")) else PIN_VILLAGE

## Settlement art (user request 2026-09-09): each town drawn as its tier's
## picture (data/settlement_art.csv) standing on its point, scaled with the
## zoom between map_sprite_min_px and map_sprite_max_px; below the minimum
## the town falls back to its pin. Textures are cached per path.
var _sprite_cache: Dictionary = {}

func _sprite_texture(path: String) -> Texture2D:
	if not _sprite_cache.has(path):
		_sprite_cache[path] = UiPalette.load_art(path)
	return _sprite_cache[path]

## The on-screen height the LARGEST settlement drawing takes at the current
## zoom, or 0 when it is too small to draw and the pin stands in. Every other
## tier is a fraction of it, from the size column of data/settlement_art.csv.
func sprite_height() -> float:
	var h := Game.data.bal("map_sprite_scale") * view_scale() * 100.0
	if h < Game.data.bal("map_sprite_min_px"):
		return 0.0
	return minf(h, Game.data.bal("map_sprite_max_px"))

## The settlement drawings on screen right now: {code, rect, texture}.
## Public for tests and for hit-testing (a drawing is picked by its rect).
func settlement_sprites() -> Array:
	var out: Array = []
	var h := sprite_height()
	# The economy view marks its places with manor badges (economyView.png);
	# a town drawing over the badge would hide the very thing it shows.
	if h <= 0.0 or _terrain_mesh == null or show_economy:
		return out
	var s := view_scale()
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, s)
	var frame := Rect2(Vector2.ZERO, size).grow(h)
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		if not MapObjects.burg_visible(b, min_pop):
			continue
		var art := MapObjects.settlement_art(Game.data, b)
		if art.is_empty():
			continue
		var tex := _sprite_texture(String(art["texture"]))
		if tex == null:
			continue
		var here := Vector2(float(b["x"]), float(b["y"]))
		var sp := map_to_screen(here)
		if not frame.has_point(sp):
			continue
		# Smaller tiers stay smaller: each tier draws at its own share of the
		# tallest (data/settlement_art.csv, size), so a capital towers over a
		# hamlet. The share is data, not the PNG's pixel height — it used to
		# be baked into the export, which made the hierarchy untunable without
		# regenerating art (owner 2026-09-12).
		var tile_scale := h * maxf(float(art.get("size", "1")), 0.0) / float(tex.get_height())
		var size_px := Vector2(tex.get_width(), tex.get_height()) * tile_scale
		# Slide a seaside drawing back onto its own land.
		var half_native := size_px.x * 0.5 / maxf(s, 0.0001)
		var push := inland_bias(code, here, half_native) \
			* size_px.x * Game.data.bal("map_sprite_inland")
		out.append({"code": code, "texture": tex, "point": sp,
			"province": String(b.get("province_code", "")),
			"rect": Rect2(sp + push - Vector2(size_px.x / 2.0, size_px.y * 0.8), size_px)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["rect"] as Rect2).end.y < (b["rect"] as Rect2).end.y)
	return out

## Towns as their drawings when the zoom allows, else gold circles sized by
## tier (ringed for capitals); points of interest as their icons (teal
## diamonds when a type has none) — pins in screen px, gated by the LOD rule.
func _draw_pins() -> void:
	var s := view_scale()
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, s)
	var on_screen := Rect2(Vector2.ZERO, size).grow(PIN_CAPITAL * 2.0)
	var sprites := settlement_sprites()
	var sprite_strength := Game.data.bal("map_sprite_tint")
	var drawn: Dictionary = {}
	for sp_entry in sprites:
		draw_texture_rect(sp_entry["texture"], sp_entry["rect"], false,
			sprite_tint(String(sp_entry["code"]), String(sp_entry.get("province", "")), sprite_strength))
		drawn[sp_entry["code"]] = true
	for code: String in Game.data.burgs:
		if drawn.has(code) or show_economy:
			continue
		var b: Dictionary = Game.data.burgs[code]
		if not MapObjects.burg_visible(b, min_pop):
			continue
		var sp := map_to_screen(Vector2(float(b["x"]), float(b["y"])))
		if not on_screen.has_point(sp):
			continue
		var r := _pin_radius(b)
		draw_circle(sp, r + 2.0, PIN_OUTLINE)
		draw_circle(sp, r, UiPalette.GOLD)
		if String(b["is_capital"]) == "1":
			draw_arc(sp, r + 2.5, 0.0, TAU, 24, UiPalette.GOLD, 1.0, true)
	if MapObjects.markers_visible(Game.data) and s >= Game.data.bal("map_lod_marker_scale"):
		var drawn_markers: Dictionary = {}
		for sp_entry in marker_sprites():
			draw_texture_rect(sp_entry["texture"], sp_entry["rect"], false)
			drawn_markers[sp_entry["code"]] = true
		for code: String in Game.data.markers:
			if drawn_markers.has(code):
				continue
			var m: Dictionary = Game.data.markers[code]
			var sp := map_to_screen(Vector2(float(m["x"]), float(m["y"])))
			if on_screen.has_point(sp):
				_draw_diamond(sp, PIN_MARKER + 2.0, PIN_OUTLINE)
				_draw_diamond(sp, PIN_MARKER, UiPalette.TOOL_PERSONAL)

## Points of interest as their icons (data/marker_art.csv), a fixed
## map_marker_px square centred on the point — counters like the pins, not
## part of the terrain — once the zoom passes map_lod_marker_scale. A type
## without art keeps its diamond. {code, texture, rect}; public for tests
## and hit-testing.
func marker_sprites() -> Array:
	if not MapObjects.markers_visible(Game.data):
		return []
	var out: Array = []
	if _terrain_mesh == null or view_scale() < Game.data.bal("map_lod_marker_scale"):
		return out
	var px := Game.data.bal("map_marker_px")
	var frame := Rect2(Vector2.ZERO, size).grow(px)
	for code: String in Game.data.markers:
		var m: Dictionary = Game.data.markers[code]
		var art := MapObjects.marker_art(Game.data, m)
		if art.is_empty():
			continue
		var tex := _sprite_texture(String(art["texture"]))
		if tex == null:
			continue
		var sp := map_to_screen(Vector2(float(m["x"]), float(m["y"])))
		if not frame.has_point(sp):
			continue
		out.append({"code": code, "texture": tex,
			"rect": Rect2(sp - Vector2(px, px) / 2.0, Vector2(px, px))})
	return out

## The regiment counters on screen right now, in stacking order:
## {code, pos, rect, icon, count, size, text, glyph, color, naval, royal}.
## `rect` is the whole counter, `icon` its glyph square and `count` the box
## stating its headcount, all screen rects. [] while the layer is off.
## Public for tests and hit-testing.
##
## The look follows development/exmaples/MilitaryView.png (owner request
## 2026-09-13): a dark square wearing the counter's glyph — crossed swords
## for a regiment, a crown for the royal regiment (MapObjects.royal_regiment),
## waves for a fleet — joined to a box in the realm's colour with the number
## under arms. Centred on the point the pack quarters the regiment at, then
## pushed DOWN clear of any settlement drawing or pin it would cover (owner
## request 2026-09-13: a counter never hides a town, it sits under it) and of
## any counter already placed, so two regiments in one town both stay legible.
func army_markers() -> Array:
	if not show_armies or _terrain_mesh == null or Game.data == null:
		return []
	var repo := Game.data
	var mine := repo.resolve_realm("player_realm")
	var royal := MapObjects.royal_regiment(repo, mine)
	var h := army_badge_height()
	var pad := repo.bal("map_army_count_pad_px")
	var gap := repo.bal("map_army_stack_gap_px")
	var font_px := maxi(int(round(h * repo.bal("map_army_font_frac"))), 1)
	var font := UiPalette.body_font()
	var color := army_count_color(mine)
	var frame := Rect2(Vector2.ZERO, size).grow(h * 4.0)
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, mine):
		var sp := map_to_screen(Vector2(float(r["x"]), float(r["y"])))
		if not frame.has_point(sp):
			continue
		var code := String(r["regiment_code"])
		var strength := MapObjects.regiment_size(repo, r)
		var naval := String(r.get("is_naval", "0")) == "1"
		var text := str(int(strength))
		var count_w := maxf(h, _text_width(font, text, font_px) + pad * 2.0)
		var w := h + count_w
		out.append({"code": code, "pos": sp, "size": strength, "text": text,
			"font_px": font_px, "rect": Rect2(sp - Vector2(w, h) / 2.0, Vector2(w, h)),
			"glyph": "waves" if naval else ("crown" if code == royal else "swords"),
			"color": color, "naval": naval, "royal": code == royal})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := (a["pos"] as Vector2).y
		var by := (b["pos"] as Vector2).y
		return String(a["code"]) < String(b["code"]) if ay == by else ay < by)
	# The settlements are obstacles from the start: counters only ever move
	# down, so a counter meeting a town drops to just under its drawing.
	var placed: Array = settlement_marks()
	for m: Dictionary in out:
		var rect: Rect2 = m["rect"]
		# Each push can land on another obstacle, so go round again until the
		# rect is clear; every pass moves it strictly down, so this ends.
		var moved := true
		while moved:
			moved = false
			for other: Rect2 in placed:
				if rect.intersects(other.grow(gap * 0.5)):
					rect.position.y = other.end.y + gap
					moved = true
		placed.append(rect)
		m["rect"] = rect
		m["icon"] = Rect2(rect.position, Vector2(h, h))
		m["count"] = Rect2(rect.position + Vector2(h, 0.0), Vector2(rect.size.x - h, h))
	return out

## A counter's height in screen px: a share of the LARGEST settlement
## drawing's height (sprite_height), held between map_army_badge_min_px and
## map_army_badge_max_px — a counter is a note under a town, and must read
## smaller than the town it sits under (owner request 2026-09-13). When the
## towns are pins, the floor.
func army_badge_height() -> float:
	var repo := Game.data
	return clampf(sprite_height() * repo.bal("map_army_badge_frac"),
		repo.bal("map_army_badge_min_px"), repo.bal("map_army_badge_max_px"))

## Screen rects of every settlement mark drawn right now — the drawings, and
## the pins of towns too small for one. The military counters keep clear of
## them.
func settlement_marks() -> Array:
	var out: Array = []
	var drawn: Dictionary = {}
	for sp_entry: Dictionary in settlement_sprites():
		out.append(sp_entry["rect"])
		drawn[sp_entry["code"]] = true
	if show_economy:
		return out
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, view_scale())
	var frame := Rect2(Vector2.ZERO, size).grow(PIN_CAPITAL * 4.0)
	for code: String in Game.data.burgs:
		if drawn.has(code):
			continue
		var b: Dictionary = Game.data.burgs[code]
		if not MapObjects.burg_visible(b, min_pop):
			continue
		var sp := map_to_screen(Vector2(float(b["x"]), float(b["y"])))
		if not frame.has_point(sp):
			continue
		var r := _pin_radius(b) + 2.0
		out.append(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0))
	return out

## The colour of a realm's headcount box: the realm's own hue, pushed to at
## least map_army_count_sat and set at map_army_count_val, so the box reads as
## a solid counter over that realm's pale wash rather than disappearing into it.
func army_count_color(kingdom_code: String) -> Color:
	var c := MapPalette.color_of(Game.data, kingdom_code)
	return Color.from_hsv(c.h, maxf(c.s, Game.data.bal("map_army_count_sat")),
		Game.data.bal("map_army_count_val"))

func _text_width(font: Font, text: String, font_px: int) -> float:
	if font == null:
		return float(text.length() * font_px) * 0.6
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x

## Text centred in a rect, on the font's own ascent and descent so digits sit
## in the middle of the box rather than on its floor.
func _draw_centered_text(font: Font, rect: Rect2, text: String, font_px: int, color: Color) -> void:
	if font == null:
		return
	var asc := font.get_ascent(font_px)
	var desc := font.get_descent(font_px)
	var base := Vector2(rect.position.x + (rect.size.x - _text_width(font, text, font_px)) * 0.5,
		rect.position.y + (rect.size.y - asc - desc) * 0.5 + asc)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px, color)

## Each regiment as its counter. An army is a counter on the map, not part of
## the terrain, so it holds its size at every zoom.
func _draw_armies() -> void:
	var markers := army_markers()
	if markers.is_empty():
		return
	var repo := Game.data
	var outline := MapPalette.named(repo, "army_outline")
	var icon_bg := MapPalette.named(repo, "army_icon_bg")
	var glyph_ink := MapPalette.named(repo, "army_glyph")
	var count_ink := MapPalette.named(repo, "army_count_ink")
	var line := repo.bal("map_army_outline_px")
	var glyph_frac := repo.bal("map_army_glyph_frac")
	var font := UiPalette.body_font()
	for m: Dictionary in markers:
		var rect: Rect2 = m["rect"]
		var icon: Rect2 = m["icon"]
		var count: Rect2 = m["count"]
		draw_rect(rect.grow(line), outline)
		draw_rect(icon, icon_bg)
		draw_rect(count, m["color"])
		draw_line(Vector2(icon.end.x, rect.position.y), Vector2(icon.end.x, rect.end.y),
			outline, line)
		ResourceIcon.draw_glyph(self, String(m["glyph"]), icon.get_center(),
			icon.size.y * glyph_frac, glyph_ink)
		_draw_centered_text(font, count, String(m["text"]), int(m["font_px"]), count_ink)

## Triangulate every province loop once, in native coordinates. Province
## outlines are concave, so a fan fill would bleed outside the shape; the
## indices are transform-invariant, so each frame only moves the points.
func _build_province_meshes() -> void:
	_province_tris.clear()
	_province_bbox.clear()
	for code: String in Game.data.province_borders:
		var tris: Array = []
		var bbox := Rect2()
		var first := true
		for loop: PackedVector2Array in Game.data.province_borders[code]:
			tris.append(Geometry2D.triangulate_polygon(loop))
			var b := MapGeometry.bounds(loop)
			bbox = b if first else bbox.merge(b)
			first = false
		_province_tris[code] = tris
		_province_bbox[code] = bbox

## The provinces whose wash would touch the frame right now, with their
## owner's colour: {code, color}. Public for tests.
func political_fills() -> Array:
	if _terrain_mesh == null:
		return []
	var alpha := Game.data.bal("map_political_alpha")
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for code: String in _province_bbox:
		var b: Rect2 = _province_bbox[code]
		var screen := Rect2(map_to_screen(b.position), b.size * view_scale())
		if not frame.intersects(screen):
			continue
		var holder := MapOwnership.owner_of(Game.data, Game.state, code)
		var color := MapPalette.color_of(Game.data, holder)
		color.a = alpha
		out.append({"code": code, "color": color})
	return out

## Whether the coloured country areas are painted at all. Owner ruling
## 2026-09-12: the map is a parchment sheet with no fills, so
## map_political_alpha is 0 and the wash is skipped — ownership still reads
## from the dashed borders, the labels and the country card. Setting the
## balance value above 0 brings the colour back with no code change.
func political_wash_visible() -> bool:
	# Not in the HEIGHTS view: you cannot read a height ramp through a
	# political colour, and a thematic map shows ONE theme (owner 2026-09-13).
	return not show_heights and not show_economy \
		and Game.data.bal("map_political_alpha") > 0.0

## Paint every province in its live owner's colour over the terrain.
func _draw_political_wash() -> void:
	if not political_wash_visible():
		return
	var rid := get_canvas_item()
	for fill in political_fills():
		var code: String = fill["code"]
		var loops: Array = Game.data.province_borders[code]
		var tris: Array = _province_tris[code]
		for i in loops.size():
			var indices: PackedInt32Array = tris[i]
			if indices.is_empty():
				continue
			var loop: PackedVector2Array = loops[i]
			var pts := PackedVector2Array()
			pts.resize(loop.size())
			for j in loop.size():
				pts[j] = map_to_screen(loop[j])
			var colors := PackedColorArray()
			colors.resize(loop.size())
			colors.fill(fill["color"])
			RenderingServer.canvas_item_add_triangle_array(rid, indices, pts, colors)

## A kingdom's live outline as smooth closed curves in native coordinates:
## the same uniform cubic B-spline Azgaar drew the render's coasts and
## borders with (user request 2026-09-09: the straight-segment outline cut
## the shore's corners). Cached against the ownership version.
var _ring_cache: Dictionary = {}
var _ring_version := -1

func border_rings(kingdom_code: String) -> Array:
	var version := 0 if Game.state == null else Game.state.province_owner.size()
	if version != _ring_version:
		_ring_cache.clear()
		_ring_version = version
	if _ring_cache.has(kingdom_code):
		return _ring_cache[kingdom_code]
	var steps := int(Game.data.bal("map_border_smoothing_steps"))
	var rings: Array = []
	for loop: PackedVector2Array in MapOwnership.outline_of(Game.data, Game.state, kingdom_code):
		# smooth_closed_through, not smooth_closed: a border has to SIT ON the
		# province boundary it is drawn from, and the B-spline cut every
		# corner off it (owner 2026-09-13).
		rings.append(MapGeometry.smooth_closed_through(loop, steps))
	_ring_cache[kingdom_code] = rings
	return rings

## The kingdom whose land the cursor is over, or "" — the border of that one
## is drawn lit rather than having a second outline traced over it.
func hovered_kingdom() -> String:
	var row: Dictionary = _by_state_id.get(_hover_sid, {})
	return String(row.get("kingdom_code", ""))

## Every kingdom's live border as a chequered ribbon (owner request
## 2026-09-12, after the frame band of development/exmaples): alternating
## dark and pale runs of equal length, both drawn, so the line reads as a
## printed map band rather than a dashed stroke. The chequer steps along the
## ring's own arc length (MapGeometry.dash_runs) rather than per segment: the
## rings are B-spline samples a few px apart, so Godot's draw_dashed_line —
## which restarts its phase on every call — drew them as mush.
func _draw_state_borders() -> void:
	var alpha := Game.data.bal("map_state_border_alpha")
	var dark := MapPalette.named(Game.data, "state_border")
	var pale := MapPalette.named(Game.data, "state_border_light")
	dark.a = alpha
	pale.a = alpha
	var lit := MapPalette.named(Game.data, "hover_border")
	var width := Game.data.bal("map_state_border_width")
	var lit_width := Game.data.bal("map_hover_border_width")
	var hovered := hovered_kingdom()
	var dash := Game.data.bal("map_state_border_dash_px")
	var gap := Game.data.bal("map_state_border_gap_px")
	var frame := Rect2(Vector2.ZERO, size).grow(maxf(width, lit_width) * 2.0)
	var version := _ownership_sig()
	var step := Game.data.bal("map_dash_min_step_px")
	for code: String in Game.data.kingdoms:
		# A kingdom's rings are cut once per zoom and drawn as one polyline
		# (MapDashCache): both phases are in it — the runs between the dark
		# ones are the PALE half of the ribbon, not empty line.
		var entry := _dashes.cut_lazy("border:" + code, _zoom, version,
			func() -> Array: return _closed_rings(border_rings(code)), dash, gap, step)
		# Hovering LIGHTS THE LINE THAT IS ALREADY THERE (owner request
		# 2026-09-12) instead of tracing a second outline over it.
		if code == hovered:
			_draw_dashes(entry, frame, lit, lit, lit_width)
		else:
			_draw_dashes(entry, frame, dark, pale, width)

func _closed_screen_ring(loop: PackedVector2Array) -> PackedVector2Array:
	var pts: PackedVector2Array = _view_xform() * loop
	if not pts.is_empty():
		pts.append(pts[0])  # close the ring
	return pts

## Rings closed in native px, ready to be cut: the pack's loops stop one
## point short of where they started.
static func _closed_rings(rings: Array) -> Array:
	var out: Array = []
	for ring: PackedVector2Array in rings:
		var closed := ring.duplicate()
		if not closed.is_empty():
			closed.append(closed[0])
		out.append(closed)
	return out

## One cut line set drawn as ONE antialiased polyline, or nothing when it
## is empty or lies wholly outside the frame.
func _draw_dashes(entry: Dictionary, frame: Rect2, ink: Color, pale: Color, width: float) -> void:
	var native: PackedVector2Array = entry["points"]
	if native.size() < 2 or not _bbox_touches(entry["bbox"], frame):
		return
	var pts: PackedVector2Array = _view_xform() * native
	draw_polyline_colors(pts, _dashes.colors(entry, ink, pale), width, true)

func _ring_touches(pts: PackedVector2Array, frame: Rect2) -> bool:
	for p in pts:
		if frame.has_point(p):
			return true
	return false

func _build_coast_rings() -> void:
	_coast_rings.clear()
	var steps := int(Game.data.bal("map_border_smoothing_steps"))
	for row: Dictionary in Game.data.coasts:
		_coast_rings.append(MapGeometry.smooth_closed_through(row["polyline"], steps))

## The sheet the map is drawn on (owner request 2026-09-12: a parchment
## scroll). Two screen-space layers over the flat terrain tint: a seamless
## fractal noise tile for the paper's mottling and fibre, and a radial
## vignette for the shadow at the edges of a rolled scroll. Both are fixed in
## screen px and do not zoom — the map is printed ON the paper, the paper is
## not part of the world. The noise takes map_paper_seed from balance.csv, so
## the grain is the same sheet every run; it is a look, never simulation.
const PAPER_TILE_PX := 1024
const VIGNETTE_TILE_PX := 512

var _paper_tex: NoiseTexture2D = null
var _vignette_tex: GradientTexture2D = null

## The umber the paper's mottling and its vignette are drawn in: the same
## raw umber as the shore stroke, so the sheet stays one family of browns.
func _paper_ink() -> Color:
	return MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)

func _paper_texture() -> NoiseTexture2D:
	if _paper_tex != null:
		return _paper_tex
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(Game.data.bal("map_paper_seed"))
	noise.frequency = 1.0 / maxf(Game.data.bal("map_paper_grain_px"), 1.0)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = maxi(int(Game.data.bal("map_paper_octaves")), 1)
	var ink := _paper_ink()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([
		Color(ink.r, ink.g, ink.b, 0.0),
		Color(ink.r, ink.g, ink.b, Game.data.bal("map_paper_strength"))])
	_paper_tex = NoiseTexture2D.new()
	_paper_tex.width = PAPER_TILE_PX
	_paper_tex.height = PAPER_TILE_PX
	_paper_tex.seamless = true
	_paper_tex.generate_mipmaps = false
	_paper_tex.color_ramp = ramp
	_paper_tex.noise = noise
	return _paper_tex

func _vignette_texture() -> GradientTexture2D:
	if _vignette_tex != null:
		return _vignette_tex
	var ink := _paper_ink()
	var g := Gradient.new()
	# Clear through the middle of the sheet, darkening only over the last
	# third, the way the shadow sits on a scroll that will not lie flat.
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([
		Color(ink.r, ink.g, ink.b, 0.0),
		Color(ink.r, ink.g, ink.b, 0.0),
		Color(ink.r, ink.g, ink.b, Game.data.bal("map_paper_vignette"))])
	_vignette_tex = GradientTexture2D.new()
	_vignette_tex.gradient = g
	_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	_vignette_tex.fill_from = Vector2(0.5, 0.5)
	_vignette_tex.fill_to = Vector2(1.0, 0.5)
	_vignette_tex.width = VIGNETTE_TILE_PX
	_vignette_tex.height = VIGNETTE_TILE_PX
	return _vignette_tex

## Whether each paper layer is drawn at all — 0 in balance.csv turns it off.
func paper_grain_visible() -> bool:
	return Game.data.bal("map_paper_strength") > 0.0

func paper_vignette_visible() -> bool:
	return Game.data.bal("map_paper_vignette") > 0.0

func _draw_paper_grain() -> void:
	if not paper_grain_visible():
		return
	draw_texture_rect(_paper_texture(), Rect2(Vector2.ZERO, size), true)

func _draw_paper_vignette() -> void:
	if not paper_vignette_visible():
		return
	draw_texture_rect(_vignette_texture(), Rect2(Vector2.ZERO, size), false)

## The realm colour a point on the map wears, blended `strength` of the way
## from plain white (owner request 2026-09-12). The province under a point is
## GEOMETRY and never goes stale, so it is resolved once from the province
## index bitmap and kept; the OWNER is looked up live, which is what makes a
## conquered province recolour its woods and its towns with no new art.
var _province_at_cache: Dictionary = {}

func province_at(native: Vector2) -> String:
	var key := Vector2i(native.floor())
	if _province_at_cache.has(key):
		return _province_at_cache[key]
	var code := ""
	if _province_image != null:
		var row := Game.data.province_by_id(MapIndex.id_at(_province_image, key))
		code = String(row.get("province_code", ""))
	_province_at_cache[key] = code
	return code

## Which way the land lies from a point, weighted by how one-sided it is:
## twelve probes on a ring, each landward one adding its direction, averaged.
## A town in open country comes back ZERO (the probes cancel) and does not
## move; a town on a headland comes back pointing firmly inland. The province
## index is the land mask, and it is geometry — resolved once per burg.
var _inland_cache: Dictionary = {}

func inland_bias(code: String, native: Vector2, radius: float) -> Vector2:
	var key := "%s:%d" % [code, roundi(radius)]
	if _inland_cache.has(key):
		return _inland_cache[key]
	var sum := Vector2.ZERO
	var probes := 12
	if _province_image != null and radius > 0.0:
		for i in probes:
			var a := TAU * float(i) / float(probes)
			var d := Vector2(cos(a), sin(a))
			if MapIndex.id_at(_province_image, Vector2i((native + d * radius).floor())) > 0:
				sum += d
	var out := sum / float(probes)
	_inland_cache[key] = out
	return out

func realm_tint(province_code: String, strength: float) -> Color:
	# In a thematic view the realm colours are not on the map, so the symbols
	# must not wear them either — a blue-teal wood over an economy wash reads
	# as a third, meaningless colour (owner ruling 2026-09-13).
	if show_heights or show_economy or show_manors:
		return Color.WHITE
	if province_code == "" or strength <= 0.0:
		return Color.WHITE
	var holder := MapOwnership.owner_of(Game.data, Game.state, province_code)
	if holder == "":
		return Color.WHITE
	return Color.WHITE.lerp(MapPalette.color_of(Game.data, holder), strength)

## The terrain's own symbols — woods, hills, reeds — scattered from the
## pack's cells (MapObjects.terrain_decor). They belong to the drawing, so
## they scale with the zoom like the coastline rather than holding a fixed
## screen size, and they are skipped below map_decor_min_scale where the
## whole sheet would turn into a carpet of specks. Since the decor rework
## (2026-09-13) this is a TEST SEAM — the marks that would be on screen —
## not the drawing path, which is decor_mesh().
func terrain_sprites() -> Array:
	# A thematic view shows its theme: woods and hills are decoration, and
	# with the realm tint gone they read as pale specks over the wash.
	# Settlements stay — a town is a place, not decoration.
	if show_heights or show_economy or show_manors:
		return []
	if _terrain_mesh == null or view_scale() < Game.data.bal("map_decor_min_scale"):
		return []
	var s := view_scale()
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for d: Dictionary in _prepared_decor():
		var tex: Texture2D = d["texture"]
		var h: float = d["height"] * s
		var w: float = h * d["aspect"]
		# The symbol stands ON its point, like the settlement art.
		var at := map_to_screen(d["pos"]) - Vector2(w * 0.5, h * 0.85)
		var rect := Rect2(at, Vector2(w, h))
		if not frame.intersects(rect):
			continue
		out.append({"rect": rect, "texture": tex, "province": d["province"]})
	return out

## The decor list with everything that cannot change resolved once: the
## texture, its aspect, and the province the mark stands in — the province is
## fixed geometry, so only the OWNER is looked up live (see realm_tint), which
## is what lets conquest recolour a wood with no new art.
##
## This used to be redone inside terrain_sprites() on every _draw(): a String()
## conversion and a texture-cache lookup per mark before the cull, and a
## province_at() probe per visible mark. On the beria pack that is ~11k marks
## a frame, on every pan and every hover.
var _prepared_decor_cache: Array = []

func _prepared_decor() -> Array:
	if not _prepared_decor_cache.is_empty():
		return _prepared_decor_cache
	for d: Dictionary in MapObjects.terrain_decor(Game.data):
		var tex := _sprite_texture(String(d["texture"]))
		if tex == null:
			continue
		var pos: Vector2 = d["pos"]
		_prepared_decor_cache.append({
			"pos": pos,
			"texture": tex,
			"aspect": float(tex.get_width()) / float(tex.get_height()),
			"height": float(d["height"]),
			"province": province_at(pos)})
	return _prepared_decor_cache

## The sea's own decoration — ships and a whale (MapObjects.sea_decor,
## data/sea_art.csv; owner request 2026-09-13) — drawn like the terrain
## symbols: sized in native px so they belong to the drawing, skipped below
## map_decor_min_scale, hidden by the thematic views. They are PRINTED on
## the water: the greyscale art is tinted with the palette's sea_ink and
## drawn at map_sea_decor_alpha, so the sea shows through them the way the
## paper shows through a light impression. Public for tests.
var _prepared_sea_decor: Array = []

func sea_sprites() -> Array:
	if show_heights or show_economy or show_manors:
		return []
	if _terrain_mesh == null or view_scale() < Game.data.bal("map_decor_min_scale"):
		return []
	if _prepared_sea_decor.is_empty():
		for d: Dictionary in MapObjects.sea_decor(Game.data):
			var tex := _sprite_texture(String(d["texture"]))
			if tex == null:
				continue
			_prepared_sea_decor.append({"pos": d["pos"], "texture": tex,
				"aspect": float(tex.get_width()) / float(tex.get_height()),
				"height": float(d["height"])})
	var s := view_scale()
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for d: Dictionary in _prepared_sea_decor:
		var h: float = d["height"] * s
		var w: float = h * d["aspect"]
		var rect := Rect2(map_to_screen(d["pos"]) - Vector2(w, h) * 0.5, Vector2(w, h))
		if frame.intersects(rect):
			out.append({"rect": rect, "texture": d["texture"]})
	return out

func _draw_sea_decor() -> void:
	var sprites := sea_sprites()
	if sprites.is_empty():
		return
	var ink := MapTerrain.palette_color(Game.data, "sea_ink", MapTerrain.FALLBACK)
	ink.a = Game.data.bal("map_sea_decor_alpha")
	for d in sprites:
		draw_texture_rect(d["texture"], d["rect"], false, ink)

## The terrain decor is ONE mesh (owner 2026-09-13, the decor rework):
## every symbol a quad in native px over one atlas of the terrain art
## (MarkAtlas / MarkMesh), drawn with a single draw_mesh whose transform
## is the view's offset and zoom. The mesh is rebuilt only when a tint
## changes — ownership, since conquest recolours a wood — never per frame
## or per zoom; the GPU clips what is off screen. It replaced one
## draw_texture_rect per mark: ~7.5 ms of _draw and ~10 ms of the
## renderer's canvas-command CPU a frame on the beria pack.
var _decor_atlas: MarkAtlas = null
var _decor_mesh_cache: ArrayMesh = null
var _decor_mesh_sig := 0

## Whether the decor layer draws at all: not under a theme, not below
## map_decor_min_scale.
func decor_visible() -> bool:
	if show_heights or show_economy or show_manors:
		return false
	return _terrain_mesh != null and view_scale() >= Game.data.bal("map_decor_min_scale")

func decor_atlas() -> MarkAtlas:
	if _decor_atlas == null:
		var textures: Dictionary = {}
		for d: Dictionary in MapObjects.terrain_decor(Game.data):
			var path := String(d["texture"])
			if not textures.has(path):
				var tex := _sprite_texture(path)
				if tex != null:
					textures[path] = tex
		for row: Dictionary in Game.data.manor_estates:
			var path := String(row["texture"])
			if not textures.has(path):
				var tex := _sprite_texture(path)
				if tex != null:
					textures[path] = tex
		_decor_atlas = MarkAtlas.build(textures)
	return _decor_atlas

## The decor mesh for the current ownership: one tint per province,
## resolved once per build, carried as vertex colour.
func decor_mesh() -> ArrayMesh:
	var sig := hash([_ownership_sig(), Game.data.bal("map_decor_alpha"), Game.data.bal("map_decor_tint")])
	if _decor_mesh_cache != null and _decor_mesh_sig == sig:
		return _decor_mesh_cache
	var alpha := Game.data.bal("map_decor_alpha")
	var strength := Game.data.bal("map_decor_tint")
	var tints: Dictionary = {}
	var marks: Array = []
	for d: Dictionary in MapObjects.terrain_decor(Game.data):
		var pos: Vector2 = d["pos"]
		var province := _decor_province(pos)
		if not tints.has(province):
			var tint := _realm_tint_plain(province, strength)
			tint.a = alpha
			tints[province] = tint
		marks.append({"pos": pos, "texture": String(d["texture"]),
			"height": float(d["height"]), "color": tints[province]})
	_decor_mesh_cache = MarkMesh.build(marks, decor_atlas())
	_decor_mesh_sig = sig
	return _decor_mesh_cache

## The province under a mark, resolved once per mark and kept: geometry.
var _decor_province_cache: Dictionary = {}

func _decor_province(pos: Vector2) -> String:
	if not _decor_province_cache.has(pos):
		_decor_province_cache[pos] = province_at(pos)
	return _decor_province_cache[pos]

## realm_tint without the thematic-view guard: the mesh is built for the
## political map, whatever view is up when it is first asked for.
func _realm_tint_plain(province_code: String, strength: float) -> Color:
	if province_code == "" or strength <= 0.0:
		return Color.WHITE
	var holder := MapOwnership.owner_of(Game.data, Game.state, province_code)
	if holder == "":
		return Color.WHITE
	return Color.WHITE.lerp(MapPalette.color_of(Game.data, holder), strength)

## The MANORS view's estates (MapObjects.manor_estates, owner 2026-09-13):
## one drawing per manor by its people, ONE mesh, each quad tinted its
## manor's colour. Rebuilt when the ledger, the manor owners or the
## province owners change.
var _estate_mesh: ArrayMesh = null
var _estate_sig := 0

func estate_mesh() -> ArrayMesh:
	var state := Game.state
	var sig := hash([0 if state == null else state.world.hash(),
		0 if state == null else state.manor_owner.hash(), _ownership_sig(),
		Game.data.bal("map_manor_mark_alpha")])
	if _estate_mesh != null and _estate_sig == sig:
		return _estate_mesh
	var tints: Dictionary = {}
	var marks: Array = []
	for d: Dictionary in MapObjects.manor_estates(Game.data, state):
		var cell := int(d["cell"])
		if not tints.has(cell):
			tints[cell] = manor_mark_tint(cell)
		marks.append({"pos": d["pos"], "texture": String(d["texture"]), "height": float(d["height"]),
			"color": tints[cell], "flip": bool(d["flip"]), "foot": float(d["foot"])})
	_estate_mesh = MarkMesh.build(marks, decor_atlas())
	_estate_sig = sig
	return _estate_mesh

## Whether the estates draw: the MANORS view, at or above
## map_manor_estate_min_scale. Test seam.
func estates_visible() -> bool:
	return show_manors and _terrain_mesh != null \
		and view_scale() >= Game.data.bal("map_manor_estate_min_scale")

## The tint a town drawing wears in the MANORS view (owner 2026-09-13:
## every element there follows one colour strategy): its own manor's
## colour at map_manor_mark_alpha; the art multiplies it. The per-manor
## estate art (library D-32..D-41, by people) will wear it too.
func manor_mark_tint(cell_id: int) -> Color:
	var c := house_manor_color(cell_id)
	if c.a <= 0.0:
		c = MapPalette.named(Game.data, "manor_mark")
	c.a = Game.data.bal("map_manor_mark_alpha")
	return c

## The tint a settlement drawing wears: the realm's on the default map
## (realm_tint), its manor's in the MANORS view (owner 2026-09-13: every
## element there follows the same colour strategy), white under the other
## themes.
func sprite_tint(burg_code: String, province_code: String, strength: float) -> Color:
	if show_manors:
		var cell := int(MapEconomy.burg_cells(Game.data).get(burg_code, -1))
		if cell >= 0:
			return Color.WHITE.lerp(manor_mark_tint(cell), strength)
		return Color.WHITE
	return realm_tint(province_code, strength)

func _draw_terrain_decor() -> void:
	var xf := Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset)
	if decor_visible():
		var mesh := decor_mesh()
		if mesh.get_surface_count() > 0:
			draw_mesh(mesh, decor_atlas().texture, xf)
	if estates_visible():
		var estates := estate_mesh()
		if estates.get_surface_count() > 0:
			draw_mesh(estates, decor_atlas().texture, xf)

## The scale bar in the bottom-right corner (owner request 2026-09-12). The
## pack carries its own scale — map_info's distance_scale world units per
## native px, in distance_unit — so the bar states a real distance and
## restates it at every zoom: it takes the largest round number
## (MapGeometry.nice_step) whose bar still fits inside map_scale_bar_max_px.
## {} when the pack has no scale or the bar would be too small to mean
## anything. Public for tests.
func scale_bar() -> Dictionary:
	var per_px := float(Game.data.map_info.get("distance_scale", "0"))
	var max_px := Game.data.bal("map_scale_bar_max_px")
	if per_px <= 0.0 or max_px <= 0.0 or view_scale() <= 0.0:
		return {}
	var distance := MapGeometry.nice_step(max_px / view_scale() * per_px)
	if distance <= 0.0:
		return {}
	var unit := String(Game.data.map_info.get("distance_unit", ""))
	return {"distance": distance, "unit": unit,
		"width_px": distance / per_px * view_scale(),
		"text": ("%s %s" % [_trim_zeros(distance), unit]).strip_edges()}

## 500.0 -> "500", 2.5 -> "2.5": a scale bar reads as a number, not a float.
func _trim_zeros(v: float) -> String:
	var s := String.num(v, 2)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s

## Drawn last, over the vignette, in the manner of library M-14: a narrow bar
## of alternating filled and open segments under a bracketing line, with the
## distance set right-aligned above it.
func _draw_scale_bar() -> void:
	var bar := scale_bar()
	if bar.is_empty():
		return
	var color := MapTerrain.palette_color(Game.data, "scale_bar", MapTerrain.FALLBACK)
	color.a = Game.data.bal("map_scale_bar_alpha")
	if color.a <= 0.0:
		return
	var w: float = bar["width_px"]
	var h := Game.data.bal("map_scale_bar_height_px")
	var margin := Game.data.bal("map_scale_bar_margin_px")
	var right := size.x - margin
	var bottom := size.y - margin
	var left := right - w
	var top := bottom - h
	var divisions := maxi(int(Game.data.bal("map_scale_bar_divisions")), 1)
	var step := w / float(divisions)
	for i in divisions:
		if i % 2 == 0:
			draw_rect(Rect2(Vector2(left + step * i, top), Vector2(step, h)), color, true)
	draw_rect(Rect2(Vector2(left, top), Vector2(w, h)), color, false, 2.0)
	var brow := top - 6.0
	draw_line(Vector2(left, brow), Vector2(right, brow), color, 2.0, true)
	draw_line(Vector2(left, brow), Vector2(left, top), color, 2.0, true)
	draw_line(Vector2(right, brow), Vector2(right, top), color, 2.0, true)
	var font := UiPalette.display_font()
	if font == null:
		return
	var font_px := int(Game.data.bal("map_scale_bar_font_px"))
	var text := String(bar["text"])
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	draw_string(font, Vector2(right - text_w, brow - 6.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)

## A compass rose fixed in the top-right corner (owner request 2026-09-13),
## in the manner of library M-13: a sixteen-point star whose limbs are
## shaded dark on one side and pale on the other, inside a graduated ring,
## north marked with an N. It is the sheet's furniture like the scale bar —
## fixed in screen px, neither zooming nor panning — and all vector, in the
## scale bar's ink, so it is crisp at any window size. The box it occupies,
## or Rect2() when hidden (map_compass_alpha or size 0). Public for tests.
func compass_rect() -> Rect2:
	var d := Game.data.bal("map_compass_size_px")
	if d <= 0.0 or Game.data.bal("map_compass_alpha") <= 0.0:
		return Rect2()
	var margin := Game.data.bal("map_compass_margin_px")
	return Rect2(Vector2(size.x - margin - d, margin), Vector2(d, d))

## The limbs: [count, reach as a share of the radius, first angle in degrees
## clockwise from north], shortest first so the longer overlap them.
const COMPASS_TIERS := [[8, 0.42, 22.5], [4, 0.66, 45.0], [4, 1.0, 0.0]]
const COMPASS_TICKS := 32

func _draw_compass() -> void:
	var rect := compass_rect()
	if rect.size.x <= 0.0:
		return
	var ink := MapTerrain.palette_color(Game.data, "scale_bar", MapTerrain.FALLBACK)
	ink.a = Game.data.bal("map_compass_alpha")
	var pale := Color(1.0, 1.0, 1.0, ink.a)
	var d := rect.size.x
	# The star sits a little low in its box to leave the N its room above.
	var c := rect.get_center() + Vector2(0.0, d * 0.1)
	var r := d * 0.36
	# The graduated ring, under the limbs.
	draw_arc(c, r * 0.56, 0.0, TAU, 96, ink, 1.4, true)
	draw_arc(c, r * 0.48, 0.0, TAU, 96, ink, 0.8, true)
	for i in COMPASS_TICKS:
		var u := Vector2.from_angle(TAU * float(i) / float(COMPASS_TICKS))
		var inner := r * (0.48 if i % 4 == 0 else 0.51)
		draw_line(c + u * inner, c + u * r * 0.56, ink, 1.0, true)
	for tier: Array in COMPASS_TIERS:
		var count: int = tier[0]
		var reach: float = r * float(tier[1])
		for i in count:
			var deg: float = float(tier[2]) + 360.0 / float(count) * float(i)
			var u := Vector2.from_angle(deg_to_rad(deg) - PI * 0.5)
			var v := u.orthogonal() * reach * 0.16
			var tip := c + u * reach
			# Each limb is a rhombus split down its length: the near half in
			# ink, the far half in the paper's white, as a rose is engraved.
			draw_colored_polygon(PackedVector2Array([c, c - v, tip]), ink)
			draw_colored_polygon(PackedVector2Array([c, tip, c + v]), pale)
			draw_polyline(PackedVector2Array([c - v, tip, c + v]), ink, 1.0, true)
	var font := UiPalette.display_font()
	if font == null:
		return
	var font_px := maxi(int(r * 0.42), 8)
	var w := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y - r - 3.0), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)

## Every shore (islands and lakes) as a smooth stroke in the palette's
## coast colour — the same B-spline as the kingdom borders, so a border
## along a coast sits on the drawn shore.
func _draw_coasts() -> void:
	var width := Game.data.bal("map_coast_width")
	if width <= 0.0:
		return  # owner request 2026-09-13: no coast line
	var color := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
	var frame := Rect2(Vector2.ZERO, size).grow(width * 2.0)
	for ring: PackedVector2Array in _coast_rings:
		var pts := _closed_screen_ring(ring)
		if _ring_touches(pts, frame):
			draw_polyline(pts, color, width, true)

func _screen_polyline(pts: PackedVector2Array) -> PackedVector2Array:
	return _view_xform() * pts

## map_to_screen as a transform, so a whole array goes through it in one
## C++ call rather than a GDScript loop per point per frame.
func _view_xform() -> Transform2D:
	return Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset)

## Whether a native-px bounding box lands in a screen-px frame.
func _bbox_touches(bbox: Rect2, frame: Rect2) -> bool:
	return frame.intersects(Rect2(map_to_screen(bbox.position), bbox.size * _zoom))

## Test seam: the sea layer behind the land.
func sea_layer() -> SeaLayer:
	return _sea

## Test seam: the dash cache, to see that a frame cut nothing new.
func dash_cache() -> MapDashCache:
	return _dashes

func _line_in_frame(row: Dictionary) -> bool:
	var b: Rect2 = row["bbox"]
	var on_screen := Rect2(map_to_screen(b.position), b.size * view_scale()).grow(2.0)
	return Rect2(Vector2.ZERO, size).intersects(on_screen)

## The river rows whose extent touches the frame. Public for tests.
func visible_rivers() -> Array:
	if _terrain_mesh == null:
		return []
	var out: Array = []
	for code: String in Game.data.rivers:
		if _line_in_frame(Game.data.rivers[code]):
			out.append(Game.data.rivers[code])
	return out

func visible_river_count() -> int:
	return visible_rivers().size()

## Rivers widen with their discharge (native px per sqrt(discharge), so a
## great river is a few px across at native scale) and never thinner than
## map_river_min_px on screen.
## A river's course smoothed once in native coordinates and kept: the pack
## stores rivers as raw polylines, whose corners read as hard kinks (owner
## 2026-09-12). Cached per river — the courses never move.
##
## The pack's point order IS the flow: Azgaar writes a river's cells from
## source to mouth and the importer keeps them (checked 2026-09-13 on beria:
## 134 of 180 rivers end in the sea and one begins in a lake, none the other
## way round). The earlier guess — "the end nearer the coast is the mouth",
## measured against a coarse cloud of coast points — turned a dozen short
## coastal rivers round, so they rose out of the sea (owner report
## 2026-09-13). The order is trusted; nothing is reversed.
var _river_curves: Dictionary = {}

func river_curve(code: String, pts: PackedVector2Array) -> PackedVector2Array:
	if not _river_curves.has(code):
		_river_curves[code] = _trim_to_land(MapGeometry.smooth_open(
			pts, int(Game.data.bal("map_river_smoothing_steps"))))
	return _river_curves[code]

## Whether a native point is water: no province under it. The province index
## is land, and it is the bitmap the hit-testing reads, so the drawing and
## the picking agree on where the shore is.
func _is_water(p: Vector2) -> bool:
	return _province_image == null or MapIndex.id_at(_province_image, Vector2i(p.floor())) <= 0

## The course clipped to the land at BOTH ends, each cut carried exactly to
## the shore. Azgaar runs a river's mouth one cell out into the sea, and
## smoothing cuts corners near the shore, so a course's last samples sat on
## the water and read as a stub laid on the sea (owner reports 2026-09-12 and
## 2026-09-13: a river must begin at the land/sea edge, never in the sea).
## The points over water are dropped and the crossing segment is bisected
## to the edge (_shore_between), which becomes the new end point. A river
## rising in a lake is trimmed the same way at its head. Empty when the
## course never touches land.
func _trim_to_land(curve: PackedVector2Array) -> PackedVector2Array:
	if _province_image == null or curve.size() < 2:
		return curve
	var first := 0
	while first < curve.size() and _is_water(curve[first]):
		first += 1
	if first == curve.size():
		return PackedVector2Array()
	var last := curve.size() - 1
	while last > first and _is_water(curve[last]):
		last -= 1
	var out := PackedVector2Array()
	if first > 0:
		out.append(_shore_between(curve[first], curve[first - 1]))
	out.append_array(curve.slice(first, last + 1))
	if last < curve.size() - 1:
		out.append(_shore_between(curve[last], curve[last + 1]))
	return out

## The land/water edge on the segment from a land point to a water point:
## bisected SHORE_STEPS times, to well under a native px, and the LAND side
## of the last cut is returned, so the end point is never on the water.
const SHORE_STEPS := 8

func _shore_between(land: Vector2, water: Vector2) -> Vector2:
	var a := land
	var b := water
	for i in SHORE_STEPS:
		var m := (a + b) * 0.5
		if _is_water(m):
			b = m
		else:
			a = m
	return a

## A triangle LIST filled flat. RenderingServer wants indices, and a list is
## just 0, 1, 2, ...
func _fill_tris(tris: PackedVector2Array, color: Color) -> void:
	if tris.is_empty():
		return
	var idx := PackedInt32Array()
	idx.resize(tris.size())
	for i in tris.size():
		idx[i] = i
	var cols := PackedColorArray()
	cols.resize(tris.size())
	cols.fill(color)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, tris, cols)

func _draw_rivers() -> void:
	var rivers := visible_rivers()
	if rivers.is_empty():
		return
	var color := MapTerrain.palette_color(Game.data, "river", MapTerrain.FALLBACK)
	color.a = Game.data.bal("map_river_alpha")
	var min_px := Game.data.bal("map_river_min_px")
	var k := Game.data.bal("map_river_discharge_scale")
	# SOLID (owner request 2026-09-13): the soft halo band is gone, and the
	# taper is strong — a thread at the source, swelling along the course to
	# its full width at the mouth (river_taper).
	var gamma := Game.data.bal("map_river_taper_gamma")
	for r: Dictionary in rivers:
		var width := maxf(min_px, k * sqrt(float(r.get("discharge", "0"))) * view_scale())
		var curve := river_curve(String(r["river_code"]), r["polyline"])
		var pts := _screen_polyline(curve)
		var n := pts.size()
		if n < 2:
			continue
		var half := river_taper(n, width * 0.5, gamma)
		# No caps: the source has tapered to a point, and the mouth's flat cut
		# lies ON the shoreline (_trim_to_land), where the sea takes over.
		_fill_tris(MapGeometry.ribbon(pts, half), color)

## A river's half-width at each of its `n` course points, source first:
## half_max * t^gamma, t running 0 at the source to 1 at the mouth — a
## thread in the hills that swells to its full width where it meets the
## sea, the way a river is (owner 2026-09-13, reversing the taper of the
## same morning, which had it widest at the source). A larger gamma keeps
## it thin for longer. Pure; public for tests.
static func river_taper(n: int, half_max: float, gamma: float) -> PackedFloat32Array:
	var half := PackedFloat32Array()
	half.resize(n)
	var g := maxf(gamma, 0.01)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		half[i] = half_max * pow(t, g)
	return half

## Roads always; trails and sea routes once the view is close enough.
## A route smoothed once in native coordinates and kept — the same treatment
## the rivers get, and more necessary here: a wide stroke makes every kink in
## the pack's raw polyline obvious.
var _route_curves: Dictionary = {}

func route_curve(code: String, pts: PackedVector2Array) -> PackedVector2Array:
	if not _route_curves.has(code):
		_route_curves[code] = MapGeometry.smooth_open(
			pts, int(Game.data.bal("map_route_smoothing_steps")))
	return _route_curves[code]

## Roads as worn tracks (owner request 2026-09-12, after the reference map):
## a wide body only a couple of steps darker than the land, under a softer
## shoulder on each side, so the road reads by its WIDTH and its fade rather
## than as a dark line ruled across the sheet.
func _draw_routes() -> void:
	if _terrain_mesh == null:
		return
	var show_trails := view_scale() >= Game.data.bal("map_trail_min_scale")
	var road := MapTerrain.palette_color(Game.data, "road", MapTerrain.FALLBACK)
	var trail := MapTerrain.palette_color(Game.data, "trail", MapTerrain.FALLBACK)
	road.a = Game.data.bal("map_road_alpha")
	trail.a = road.a
	var lane := MapTerrain.palette_color(Game.data, "sea_route", MapTerrain.FALLBACK)
	lane.a = Game.data.bal("map_sea_route_alpha")
	var road_w := Game.data.bal("map_road_width")
	var trail_w := Game.data.bal("map_trail_width")
	var lane_w := Game.data.bal("map_sea_route_width")
	var lane_dash := Game.data.bal("map_sea_route_dash_px")
	var lane_gap := Game.data.bal("map_sea_route_gap_px")
	var soft := Game.data.bal("map_road_soft_ratio")
	var soft_alpha := Game.data.bal("map_road_soft_alpha")
	for code: String in Game.data.routes:
		var r: Dictionary = Game.data.routes[code]
		var group := String(r["group"])
		var is_road := group == "roads"
		if not is_road and not show_trails:
			continue
		# A shipping lane is not a road (owner request 2026-09-12): it is a
		# blue dashed line over the water, with no worn shoulder — drawn below
		# from the dash cache, all lanes as one polyline.
		if group == "searoutes":
			continue
		if not _line_in_frame(r):
			continue
		var pts := _screen_polyline(route_curve(code, r["polyline"]))
		var color := road if is_road else trail
		var width := road_w if is_road else trail_w
		if soft > 0.0:
			var shoulder := color
			shoulder.a = color.a * soft_alpha
			draw_polyline(pts, shoulder, width * (1.0 + soft * 2.0), true)
		draw_polyline(pts, color, width, true)
	if show_trails:
		var entry := _dashes.cut_lazy("lanes", _zoom, _ownership_sig(), _lane_curves,
			lane_dash, lane_gap, Game.data.bal("map_dash_min_step_px"))
		_draw_dashes(entry, Rect2(Vector2.ZERO, size).grow(lane_w * 2.0),
			lane, Color(lane, 0.0), lane_w)

## Every shipping lane's smoothed curve, in native px, gathered once.
var _lanes: Array = []

func _lane_curves() -> Array:
	if _lanes.is_empty():
		for code: String in Game.data.routes:
			var r: Dictionary = Game.data.routes[code]
			if String(r["group"]) == "searoutes":
				_lanes.append(route_curve(code, r["polyline"]))
	return _lanes

## Kingdom names set into the terrain like printed map lettering: the display
## face (Cinzel), widely letter-spaced, faint, and scaled with the zoom so
## they belong to the map rather than floating over it as UI. Drawn under the
## pins, and anchored on the territory a kingdom holds NOW, so a label
## recentres when its owner gains or loses provinces.
func _draw_kingdom_labels() -> void:
	# Blackletter (owner request 2026-09-13), in the name's own case: its
	# capitals set in a row cannot be read.
	var font := UiPalette.map_label_font()
	if font == null:
		return
	var px := Game.data.bal("map_label_scale_px") * view_scale()
	if px < Game.data.bal("map_label_min_px"):
		return
	px = minf(px, Game.data.bal("map_label_max_px"))
	var font_px := int(px)
	var tracking := px * Game.data.bal("map_label_tracking")
	# Ink, not gold (owner 2026-09-12, after development/exmaples/mapSample.jpg:
	# realm names are set in dark serif capitals over the wash).
	var color := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
	color.a = Game.data.bal("map_label_alpha")
	var frame := Rect2(Vector2.ZERO, self.size)
	for code: String in Game.data.kingdoms:
		var text := String(Game.data.kingdoms[code]["label"])
		var anchor := MapOwnership.label_anchor(Game.data, Game.state, code)
		var at := map_to_screen(anchor)
		var width := _tracked_width(font, text, font_px, tracking)
		var origin := at - Vector2(width * 0.5, -px * 0.35)
		if not frame.intersects(Rect2(origin - Vector2(0, px), Vector2(width, px * 1.4))):
			continue
		_draw_tracked(font, text, origin, font_px, tracking, color)

## draw_string has no letter-spacing, and tracking is most of what makes a
## label read as engraved rather than typed — so the glyphs are placed one at
## a time with the extra advance added between them.
func _draw_tracked(font: Font, text: String, origin: Vector2, font_px: int,
		tracking: float, color: Color) -> void:
	var pen := origin
	for i in text.length():
		var ch := text.substr(i, 1)
		font.draw_string(get_canvas_item(), pen, ch, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_px, color)
		pen.x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x \
			+ tracking

func _tracked_width(font: Font, text: String, font_px: int, tracking: float) -> float:
	if text.is_empty():
		return 0.0
	var w := 0.0
	for i in text.length():
		w += font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_px).x + tracking
	return w - tracking

func _draw_diamond(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0)]), color)

## Ring around the hovered pin. Roads and rivers are drawn by the terrain
## layer in their own colours and are not re-traced on hover: the tooltip
## and the card name them.
## Nothing on the sheet is ringed any more (owner request 2026-09-12: the
## gold circle went from the hover first, then from the click). A settlement
## says it is chosen by the card that opens in the left column, not by a
## circle drawn over its art. Only a regiment still gets an outline, because
## its plaque is UI furniture rather than map drawing and there is nothing
## else to show a pick.
func _draw_object_highlight(obj: Dictionary) -> void:
	match String(obj.get("kind", "")):
		"army":
			for marker: Dictionary in army_markers():
				if String(marker["code"]) == String(obj["code"]):
					draw_rect((marker["rect"] as Rect2).grow(
						Game.data.bal("map_army_outline_px") + 1.5), UiPalette.GOLD, false, 2.0)
					break
		"manor":
			# The clicked manor is ringed in gold along its own edge.
			var cell: Dictionary = Game.data.cells.get(int(obj.get("cell", -1)), {})
			if cell.is_empty():
				return
			var ring := _view_xform() * MapEconomy.cell_polygon(Game.data, cell)
			if ring.size() >= 3:
				ring.append(ring[0])
				draw_polyline(ring, UiPalette.GOLD, 2.5, true)

## Homing + RTS edge scrolling: pan while the mouse rides the frame's edge.
## (Homing lives here, not only in _draw, so it also runs headless in tests.)
func _process(delta: float) -> void:
	if _terrain_mesh == null or not is_visible_in_tree() or size.x <= 0.0:
		return
	if not _homed:
		_go_home()
		queue_redraw()
	if not _mouse_inside:
		return
	var m := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(m):
		return
	var dir := Vector2.ZERO
	if m.x < EDGE_MARGIN:
		dir.x = 1.0
	elif m.x > size.x - EDGE_MARGIN:
		dir.x = -1.0
	if m.y < EDGE_MARGIN:
		dir.y = 1.0
	elif m.y > size.y - EDGE_MARGIN:
		dir.y = -1.0
	if dir != Vector2.ZERO:
		_offset += dir * EDGE_SPEED * delta
		_clamp_offset()
		_update_hover(m)
		queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if _terrain_mesh == null:
		return
	# macOS trackpad: pinch zooms, two-finger drag pans. Godot delivers these
	# as their own events, so they are handled beside the wheel rather than
	# instead of it — a mouse still works exactly as before.
	if ev is InputEventMagnifyGesture:
		var mg := ev as InputEventMagnifyGesture
		var gain := Game.data.bal("map_pinch_zoom_gain")
		# factor is the frame's pinch ratio (>1 apart, <1 together); gain
		# bends it around 1.0 without changing the direction.
		_zoom_at(mg.position, 1.0 + (mg.factor - 1.0) * gain)
		return
	if ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		_offset -= pg.delta * Game.data.bal("map_pan_gesture_speed")
		_clamp_offset()
		queue_redraw()
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == HEIGHT_KEY:
		show_heights = not show_heights
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == ECONOMY_KEY:
		show_economy = not show_economy
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == DEV_FLIP_KEY \
			and OS.is_debug_build():
		dev_flip_hovered_province()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = false
				_press_pos = mb.position
			elif not _dragging:
				_select_at(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_update_hover(mm.position)
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _press_pos.distance_to(mm.position) > CLICK_SLOP:
				_dragging = true
			if _dragging:
				_offset += mm.relative
				_clamp_offset()
				queue_redraw()

func _zoom_at(pos: Vector2, factor: float) -> void:
	var before := (pos - _offset) / _zoom
	_zoom = clampf(_zoom * factor, _zoom_min(), ZOOM_MAX)
	_offset = pos - before * _zoom
	_clamp_offset()
	queue_redraw()

## Zoom-out floor: whichever is CLOSER IN of two limits — the whole map
## fitting inside the frame (contain fit), and the zoom at which the scale bar
## would read more than map_max_scale_bar_km (owner request 2026-09-12: the
## player may not pull back past that). size.y is guarded too — a zero there
## would make minf return 0, and _zoom_at divides by _zoom.
func _zoom_min() -> float:
	return maxf(_zoom_fit(), _zoom_distance_cap())

## The zoom at which the scale bar would just exceed its allowed reading. 0
## when the pack carries no distance scale or the cap is lifted.
func _zoom_distance_cap() -> float:
	var cap := Game.data.bal("map_max_scale_bar_km")
	var per_px := float(Game.data.map_info.get("distance_scale", "0"))
	var bar_px := Game.data.bal("map_scale_bar_max_px")
	if cap <= 0.0 or per_px <= 0.0 or bar_px <= 0.0:
		return 0.0
	return bar_px * per_px / cap

func _zoom_fit() -> float:
	var tex := _map_size
	if tex.x <= 0.0 or tex.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.1
	return minf(size.x / tex.x, size.y / tex.y)

## Pan limits: an axis the map overflows stays pinned to the frame edges, so
## no gutter opens where map could have been; an axis it underfills (the
## letterboxed one at low zoom) is centered instead.
func _clamp_offset() -> void:
	if _terrain_mesh == null:
		return
	_zoom = maxf(_zoom, _zoom_min())
	var scaled := _map_size * _zoom
	if scaled.x < size.x:
		_offset.x = (size.x - scaled.x) / 2.0
	else:
		_offset.x = clampf(_offset.x, size.x - scaled.x, 0.0)
	if scaled.y < size.y:
		_offset.y = (size.y - scaled.y) / 2.0
	else:
		_offset.y = clampf(_offset.y, size.y - scaled.y, 0.0)

## Native map coordinates (pack tables, index bitmaps) -> screen.
func map_to_screen(native: Vector2) -> Vector2:
	return _offset + native * _zoom

## The exact inverse — hit-testing samples the index bitmaps in native space.
func screen_to_map(pos: Vector2) -> Vector2:
	return (pos - _offset) / _zoom

func map_size() -> Vector2:
	return _map_size

func terrain_mesh() -> ArrayMesh:
	return _terrain_mesh

func _state_under(pos: Vector2) -> int:
	return MapIndex.state_at(_index_image, Vector2i(screen_to_map(pos).floor()))

func _select_at(pos: Vector2) -> void:
	var obj := _object_under(pos)
	if show_provinces:
		# The province view: every click names the province under it (a pin
		# still opens its own card; bare land does not).
		var prov := Game.data.province_by_id(
			MapIndex.id_at(_province_image, Vector2i(screen_to_map(pos).floor())) \
			if _province_image != null else -1)
		select_province(String(prov.get("province_code", "")))
		if String(obj.get("kind", "")) in ["land", "water"]:
			return
	select_object(obj)

## Select a province by code ("" clears); public for tests and screens.
func select_province(province_code: String) -> void:
	if not Game.data.provinces.has(province_code):
		province_code = ""
	if province_code == _selected_province:
		return
	_selected_province = province_code
	if province_code != "":
		_selected_obj = {}
		_card.hide()
	province_selected.emit(province_code)
	queue_redraw()

func selected_province() -> String:
	return _selected_province

func _object_under(pos: Vector2) -> Dictionary:
	# The military layer draws over everything, so it is picked first: a
	# counter takes a click anywhere on it, or within the pick radius of the
	# point it stands on (a stacked counter can sit below its own point).
	var armies := army_markers()
	for i in range(armies.size() - 1, -1, -1):
		if (armies[i]["rect"] as Rect2).has_point(pos):
			return {"kind": "army", "code": String(armies[i]["code"])}
	var army_reach: float = Game.data.bal("map_army_pick_px")
	for i in range(armies.size() - 1, -1, -1):
		if (armies[i]["pos"] as Vector2).distance_to(pos) <= army_reach:
			return {"kind": "army", "code": String(armies[i]["code"])}
	# A manor badge names the settlement whose output it shows.
	for badge: Dictionary in manor_badges():
		if (badge["rect"] as Rect2).has_point(pos):
			return {"kind": "burg", "code": String(badge["burg"])}
	var sprites := settlement_sprites()
	# A settlement's OWN point wins first. Once the drawings are sized so a
	# capital dwarfs a hamlet, a southern neighbour's picture reaches over the
	# point you are actually pointing at, and pointing at a town has to name
	# that town (owner 2026-09-12).
	var reach: float = Game.data.bal("map_pick_radius_px")
	var nearest := {}
	var nearest_d := reach
	for sp_entry in sprites:
		var d := (sp_entry["point"] as Vector2).distance_to(pos)
		if d <= nearest_d:
			nearest_d = d
			nearest = sp_entry
	if not nearest.is_empty():
		return {"kind": "burg", "code": String(nearest["code"])}
	# Failing that, anywhere on its picture (the last drawn is on top).
	for i in range(sprites.size() - 1, -1, -1):
		if (sprites[i]["rect"] as Rect2).has_point(pos):
			return {"kind": "burg", "code": String(sprites[i]["code"])}
	var s := view_scale()
	return MapObjects.object_at(Game.data, _index_image, _province_image, _biome_image,
		screen_to_map(pos), Game.data.bal("map_pick_radius_px") / s,
		Game.data.bal("map_line_pick_px") / s,
		MapObjects.min_burg_pop_for_scale(Game.data, s), Game.state,
		_cell_image if manors_pickable() else null)

## Whether a click on land means its manor (MANOR_SYSTEM.md §6): in the
## layers that draw manors. On the political map land still means province.
func manors_pickable() -> bool:
	return show_economy or show_manors

func _update_hover(pos: Vector2) -> void:
	var obj := _object_under(pos)
	hover_state(_state_of(obj, pos))
	hover_object(obj)
	_place_tooltip(pos)

## The kingdom to outline while `obj` is hovered. A burg or route names its
## own kingdom, which matters for the coastal ones: a port sits on the
## shoreline, so the index pixel under its pin is often open water and
## reading the bitmap alone would drop the outline the moment the player
## touches the pin. Anything else falls back to the pixel under the cursor.
func _state_of(obj: Dictionary, pos: Vector2) -> int:
	var holder := ""
	match String(obj.get("kind", "")):
		"burg":
			var b: Dictionary = Game.data.burgs.get(String(obj.get("code", "")), {})
			holder = MapOwnership.owner_of(Game.data, Game.state, String(b.get("province_code", "")))
		"province":
			holder = MapOwnership.owner_of(Game.data, Game.state, String(obj.get("code", "")))
		"manor":
			holder = MapOwnership.owner_of(Game.data, Game.state,
				MapManors.province_of(Game.data, int(obj.get("cell", -1))))
	if holder != "" and Game.data.kingdoms.has(holder):
		return int((Game.data.kingdoms[holder] as Dictionary)["state_id"])
	return _state_under(pos)

## Beside the cursor, pushed back inside the frame at the edges so a pin
## in a corner still shows its whole name.
func _place_tooltip(pos: Vector2) -> void:
	var tip := _tooltip.get_combined_minimum_size()
	var limit := (size - tip).max(Vector2.ZERO)
	_tooltip.position = (pos + TOOLTIP_OFFSET).clamp(Vector2.ZERO, limit)

## Dev demo (debug builds, the T key): hand the hovered province to the
## player's realm, or back to whoever the pack gave it to if it is already
## theirs. Proves the dynamic-territory path end to end — the border redraws,
## the province repaints in the new colour, the kingdom labels recentre, and
## the hover card reports the new owner. Public so a test can drive it
## without a keyboard.
func dev_flip_hovered_province() -> Dictionary:
	var prov := Game.data.province_by_id(int(_hover_obj.get("province_id", -1)))
	if prov.is_empty() or Game.state == null:
		return {}
	var code := String(prov["province_code"])
	var mine := Game.data.resolve_realm("player_realm")
	var now := MapOwnership.owner_of(Game.data, Game.state, code)
	var to := String(prov["kingdom_code"]) if now == mine else mine
	if not MapOwnership.set_owner(Game.data, Game.state, code, to,
			"dev: flipped on the map"):
		return {}
	_hover_sid = -1  # force the hover to re-resolve against the new owner
	_update_hover(get_local_mouse_position())
	# The card in the left column is showing counts from before the transfer.
	country_hovered.emit(String(_by_state_id.get(_hover_sid, {}).get("kingdom_code", "")))
	queue_redraw()
	return {"province": code, "from": now, "to": to}

func toggle_provinces() -> void:
	show_provinces = not show_provinces

## The selected province, washed in gold so the selection reads on the map.
func _draw_selected_province() -> void:
	if _selected_province == "" or not show_provinces:
		return
	var tint := UiPalette.GOLD
	tint.a = 0.22
	for loop: PackedVector2Array in Game.data.province_borders.get(_selected_province, []):
		var screen := PackedVector2Array()
		screen.resize(loop.size())
		for i in loop.size():
			screen[i] = map_to_screen(loop[i])
		var tris := Geometry2D.triangulate_polygon(screen)
		for t in range(0, tris.size(), 3):
			draw_colored_polygon(PackedVector2Array([screen[tris[t]],
				screen[tris[t + 1]], screen[tris[t + 2]]]), tint)

## The seam segments the province view would draw right now, in screen
## coordinates: nothing when the view is off or the zoom is below the
## balance floor, and only segments touching the frame.
func _visible_seams() -> Array:
	if not _seams_shown():
		return []
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for code: String in Game.data.kingdoms:
		for seg: PackedVector2Array in MapOwnership.seams_of(Game.data, Game.state, code):
			var a := map_to_screen(seg[0])
			var b := map_to_screen(seg[1])
			if frame.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
				out.append(PackedVector2Array([a, b]))
	return out

## Whether the province view draws its seams at all: the view is on and the
## zoom is above the balance floor.
func _seams_shown() -> bool:
	return show_provinces and _terrain_mesh != null \
		and view_scale() >= Game.data.bal("map_province_min_scale")

## Test seam: how many seam segments are on screen right now.
func visible_seam_count() -> int:
	return _visible_seams().size()

## The ECONOMY view (owner request 2026-09-13, after
## development/exmaples/economyView.png): the land drawn as its MANORS — the
## pack's Voronoi cells, each one an estate — every manor washed in the colour
## of the realm that holds it, taken from pale to deep by how good its land is
## (MapEconomy.land_value), with the manor edges ruled in. A WORKING manor —
## one with a settlement producing in it (MapEconomy.manors) — is filled dark
## and carries a badge: the icon of the good it makes most of, ringed in that
## good's category colour (the same data/goods_palette.csv the left column's
## bars use, so the column stays the map's legend), over a chip with how many
## units it makes. Ownership is read live, so a conquest recolours the manors
## with no new art.
var _manor_mesh: ArrayMesh = null
var _manor_mesh_sig := -1
var _manor_mesh_built := false
var _manor_edges := PackedVector2Array()
var _cell_province: Dictionary = {}

## A number that changes whenever any province changes hands.
func _ownership_sig() -> int:
	return 0 if Game.state == null else Game.state.province_owner.hash()

## The province a cell lies in — geometry, resolved once per cell from the
## province index at its centre.
func cell_province(cell_id: int) -> String:
	if not _cell_province.has(cell_id):
		_cell_province[cell_id] = province_at(
			MapTerrain.cell_center(Game.data, Game.data.cells[cell_id]))
	return _cell_province[cell_id]

## Who holds a cell now: its province's live owner, or "" for unheld land.
func cell_owner(cell_id: int) -> String:
	var province := cell_province(cell_id)
	return "" if province == "" else MapOwnership.owner_of(Game.data, Game.state, province)

## The wash a land cell wears: its holder's colour, from manor_pale (poor land)
## to manor_rich (the best), plus a fixed per-cell nudge so neighbouring
## manors of one biome still read as separate estates. Transparent for land
## no realm holds.
func manor_color(cell_id: int) -> Color:
	var holder := cell_owner(cell_id)
	if holder == "":
		return Color(0, 0, 0, 0)
	var repo := Game.data
	var realm := MapPalette.color_of(repo, holder)
	var t := clampf(MapEconomy.land_value(repo, repo.cells[cell_id])
		+ (MapObjects.hash01(cell_id) - 0.5) * repo.bal("map_manor_jitter"), 0.0, 1.0)
	var pale := realm.lerp(MapPalette.named(repo, "manor_pale"), repo.bal("map_manor_pale"))
	var deep := realm.lerp(MapPalette.named(repo, "manor_rich"), repo.bal("map_manor_deep"))
	var c := _province_shaded(cell_id, pale.lerp(deep, t))
	c.a = repo.bal("map_manor_alpha")
	return c

## Neighbouring provinces told apart (owner 2026-09-13): the manor's colour
## shifted by its province's shade level (MapManors.province_shades), so
## two provinces of one house or one realm that touch never look alike.
func _province_shaded(cell_id: int, color: Color) -> Color:
	var repo := Game.data
	var levels := int(repo.bal("map_manor_shade_levels"))
	if levels <= 1:
		return color
	var level := int(MapManors.province_shades(repo, levels).get(MapManors.province_of(repo, cell_id), 0))
	return MapManors.shade(color, level, repo.bal("map_manor_shade_step"))

## The MANORS view's wash: the holding house's colour — the crown its
## realm's, deepened map_manor_crown_deep toward manor_rich; another house
## its own hue — paled map_manor_foreign_pale outside the crown's realm.
## Transparent for land no house holds.
func house_manor_color(cell_id: int) -> Color:
	var repo := Game.data
	var family := MapManors.owner_of(repo, Game.state, cell_id)
	if family == "":
		return Color(0, 0, 0, 0)
	var mine := repo.resolve_realm("player_realm")
	var c: Color
	if family == MapManors.crown(Game.state):
		c = MapPalette.color_of(repo, mine).lerp(MapPalette.named(repo, "manor_rich"),
			repo.bal("map_manor_crown_deep"))
	else:
		c = MapPalette.house_color(repo, family)
	if cell_owner(cell_id) != mine:
		c = c.lerp(MapPalette.named(repo, "manor_pale"), repo.bal("map_manor_foreign_pale"))
	c = _province_shaded(cell_id, c)
	c.a = repo.bal("map_manor_alpha")
	return c

## The fill of a working manor: its holder's colour taken map_manor_rich of
## the way to manor_rich.
func working_manor_color(cell_id: int) -> Color:
	var holder := cell_owner(cell_id)
	var repo := Game.data
	var base := MapPalette.color_of(repo, holder) if holder != "" \
		else MapPalette.named(repo, "manor_pale")
	return base.lerp(MapPalette.named(repo, "manor_rich"), repo.bal("map_manor_rich"))

## Every land cell as one flat-coloured fan, in native coordinates, drawn with
## the view transform. Rebuilt only when a province changes hands; null
## outside the economy view.
func manor_mesh() -> ArrayMesh:
	if not (show_economy or show_manors) or _terrain_mesh == null:
		return null
	# Rebuilt when a province or a manor changes hands, or the theme flips:
	# ECONOMY colours by realm and land, MANORS by house.
	var sig := hash([_ownership_sig(),
		0 if Game.state == null else Game.state.manor_owner.hash(), show_manors])
	if _manor_mesh_built and sig == _manor_mesh_sig:
		return _manor_mesh
	var repo := Game.data
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var ids: Array = repo.cells.keys()
	ids.sort()
	# A working manor's dark fill is part of the mesh (2026-09-13): it is a
	# fact of the pack, not of the zoom, so it costs nothing per frame.
	var working := MapEconomy.manors(repo) if show_economy and not show_manors else {}
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		var ring: PackedInt32Array = cell["vertex_ids"]
		if MapTerrain.is_water(cell) or ring.size() < 3:
			continue
		var c := house_manor_color(id) if show_manors \
			else (working_manor_color(id) if working.has(id) else manor_color(id))
		if c.a <= 0.0:
			continue
		var base := verts.size()
		for v in ring:
			verts.append(repo.vertices[v] as Vector2)
			cols.append(c)
		# Voronoi cells are convex, so a fan from the first corner fills them.
		for i in range(1, ring.size() - 1):
			idx.append(base)
			idx.append(base + i)
			idx.append(base + i + 1)
	_manor_mesh_sig = sig
	_manor_mesh_built = true
	_manor_mesh = null if idx.is_empty() else MapTerrain.to_mesh(
		{"vertices": verts, "colors": cols, "indices": idx})
	return _manor_mesh

## Every edge of every land cell, once, as segment pairs in native
## coordinates. Geometry — built once and kept.
func manor_edges() -> PackedVector2Array:
	if not _manor_edges.is_empty():
		return _manor_edges
	var repo := Game.data
	var seen: Dictionary = {}
	var ids: Array = repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var ring: PackedInt32Array = cell["vertex_ids"]
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(key):
				continue
			seen[key] = true
			_manor_edges.append(repo.vertices[a] as Vector2)
			_manor_edges.append(repo.vertices[b] as Vector2)
	return _manor_edges

## The working manors in the frame whose settlements pass the town LOD rule
## (the same one the pins use), biggest producer first:
## {cell, burg, good, units, center}. [] outside the economy view.
func working_manors() -> Array:
	if not show_economy or _terrain_mesh == null:
		return []
	var repo := Game.data
	var min_pop := MapObjects.min_burg_pop_for_scale(repo, view_scale())
	var frame := Rect2(Vector2.ZERO, size).grow(repo.bal("map_manor_badge_px") * 2.0)
	var all := MapEconomy.manors(repo)
	var out: Array = []
	for id: int in all:
		var m: Dictionary = all[id]
		var burg := ""
		for code: String in m["burgs"]:
			if MapObjects.burg_visible(repo.burgs[code], min_pop):
				burg = code
				break
		if burg == "":
			continue
		var center := map_to_screen(MapTerrain.cell_center(repo, repo.cells[id]))
		if not frame.has_point(center):
			continue
		out.append({"cell": id, "burg": burg, "good": String(m["good"]),
			"units": float(m["units"]), "center": center})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["units"] == b["units"]:
			return int(a["cell"]) < int(b["cell"])
		return a["units"] > b["units"])
	return out

## The badges to draw for those manors: {cell, burg, good, units, text, badge,
## label, ring, texture}, `badge` the icon disc's square and `label` the
## number chip ({} when the zoom is below map_manor_label_min_scale). A badge
## that would overlap a bigger producer's is left off — its manor keeps its
## dark fill. Public for tests and hit-testing.
func manor_badges() -> Array:
	return _place_badges(working_manors())

func _place_badges(manors: Array) -> Array:
	var repo := Game.data
	var px := repo.bal("map_manor_badge_px")
	var font := UiPalette.body_font()
	var font_px := int(repo.bal("map_manor_label_font_px"))
	var with_label := view_scale() >= repo.bal("map_manor_label_min_scale")
	var placed: Array = []
	var out: Array = []
	for m: Dictionary in manors:
		var center: Vector2 = m["center"]
		var badge := Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px))
		var whole := badge
		var text := _trim_zeros(float(m["units"]))
		var label := Rect2()
		if with_label:
			var w := _text_width(font, text, font_px) + repo.bal("map_manor_label_pad_px") * 2.0
			var h := float(font_px) + 4.0
			label = Rect2(center.x - w * 0.5, badge.end.y - h * 0.3, w, h)
			whole = badge.merge(label)
		var clear := true
		for other: Rect2 in placed:
			if whole.intersects(other):
				clear = false
				break
		if not clear:
			continue
		placed.append(whole)
		var tex: Texture2D = null
		var path := String(repo.goods_art.get(String(m["good"]), ""))
		if path != "":
			tex = _sprite_texture(path)
		var tag := MapEconomy.good_tag(repo, String(m["good"]))
		# Not every good has a drawing yet (data/goods_art.csv); those wear
		# their category's glyph from data/resource_icons.csv instead.
		var glyph := String((repo.resource_icons.get("tag_" + tag, {}) as Dictionary).get("icon", ""))
		var entry := m.duplicate()
		entry.merge({"text": text, "badge": badge, "label": label if with_label else null,
			"texture": tex, "glyph": glyph, "rect": whole,
			"ring": EconomyPanel.tag_color(repo, tag)})
		out.append(entry)
	return out

## Under the rivers and roads, like the political wash it stands in for.
func _draw_manors(_manors: Array) -> void:
	var mesh := manor_mesh()
	if mesh == null:
		return
	var repo := Game.data
	var xf := Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset)
	draw_mesh(mesh, null, xf)
	if view_scale() >= repo.bal("map_manor_line_min_scale"):
		var line := MapPalette.named(repo, "manor_line")
		line.a = repo.bal("map_manor_line_alpha")
		# The edges are ONE canvas command (2026-09-13): drawn under the view
		# transform, so the 28k points are never multiplied on the CPU, and as
		# hairlines when the width is a pixel or less — a wide multiline is
		# one command per pair, which was ~8 ms of renderer CPU a frame.
		var width := repo.bal("map_manor_line_width")
		draw_set_transform_matrix(xf)
		draw_multiline(manor_edges(), line, -1.0 if width <= 1.0 else width)
		draw_set_transform_matrix(Transform2D.IDENTITY)

## Over the pins: a badge is a counter, like a regiment's.
func _draw_manor_badges(badges: Array) -> void:
	if badges.is_empty():
		return
	var repo := Game.data
	var disc := MapPalette.named(repo, "manor_badge")
	var chip := MapPalette.named(repo, "manor_label_bg")
	var ink := MapPalette.named(repo, "manor_label_ink")
	var ring_w := repo.bal("map_manor_ring_px")
	var icon_frac := repo.bal("map_manor_icon_frac")
	var font := UiPalette.body_font()
	var font_px := int(repo.bal("map_manor_label_font_px"))
	for b: Dictionary in badges:
		var r: Rect2 = b["badge"]
		var c := r.get_center()
		var rad := r.size.x * 0.5
		draw_circle(c, rad + ring_w, ink)
		draw_circle(c, rad, b["ring"])
		draw_circle(c, rad - ring_w, disc)
		var tex: Texture2D = b["texture"]
		var side := r.size.x * icon_frac
		if tex != null:
			var w := side * float(tex.get_width()) / float(tex.get_height())
			draw_texture_rect(tex, Rect2(c - Vector2(w, side) * 0.5, Vector2(w, side)), false)
		elif String(b["glyph"]) != "":
			ResourceIcon.draw_glyph(self, String(b["glyph"]), c, side * 0.8, chip)
		if b["label"] != null:
			var label: Rect2 = b["label"]
			draw_rect(label.grow(1.0), ink)
			draw_rect(label, chip)
			_draw_centered_text(font, label, String(b["text"]), font_px, ink)

## The relief, in its own view (owner 2026-09-13): a HEAT MAP rather than
## contour lines — the land ramped through the palette's heat_N stops by its
## height. It is one prebuilt mesh, so the layer costs a single draw call.
func heat_mesh() -> ArrayMesh:
	return null if not show_heights else MapTerrain.heat_mesh(Game.data)

func _draw_heights() -> void:
	var mesh := heat_mesh()
	if mesh != null:
		draw_mesh(mesh, null, Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset))

## Province seams as thin, dense dashes in the palette's seam colour — the
## same dash cache the kingdom borders use, one polyline per kingdom.
func _draw_province_seams() -> void:
	if not _seams_shown():
		return
	var color := MapPalette.named(Game.data, "province_line")
	color.a = Game.data.bal("map_province_line_alpha")
	var width := Game.data.bal("map_province_line_width")
	var dash := Game.data.bal("map_province_dash_px")
	var gap := Game.data.bal("map_province_gap_px")
	var frame := Rect2(Vector2.ZERO, size).grow(width * 2.0)
	var version := _ownership_sig()
	var clear := Color(color, 0.0)
	# A kingdom's seams, cut once per zoom, are one polyline: the gaps and
	# the leaps between segments are in it as clear vertices.
	for code: String in Game.data.kingdoms:
		var entry := _dashes.cut_lazy("seams:" + code, _zoom, version,
			func() -> Array: return MapOwnership.seams_of(Game.data, Game.state, code),
			dash, gap)
		_draw_dashes(entry, frame, color, clear, width)

## Public for tests: the same path a mouse-motion event takes.
func hover_at(pos: Vector2) -> void:
	_update_hover(pos)

func hover_object(obj: Dictionary) -> void:
	if obj == _hover_obj:
		return
	_hover_obj = obj
	var label := MapObjects.label_of(Game.data, obj)
	_tooltip.text = label
	_tooltip.visible = label != ""
	queue_redraw()

func hovered_object() -> Dictionary:
	return _hover_obj

## The tooltip's text while a named object is hovered ("" otherwise).
func hover_tooltip() -> String:
	return _tooltip.text if _tooltip.visible else ""

## Test seam: where the tooltip sits, in view coordinates.
func tooltip_rect() -> Rect2:
	return Rect2(_tooltip.position, _tooltip.get_combined_minimum_size())

## Test seam: how many burgs pass the LOD rule at the current zoom.
func visible_burg_count() -> int:
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, view_scale())
	var n := 0
	for b: Dictionary in Game.data.burgs.values():
		if MapObjects.burg_visible(b, min_pop):
			n += 1
	return n

## Outline the kingdom with this Azgaar state id (user request 2026-09-08:
## the country under the mouse shows its border). -1 / unknown ids clear
## the outline. Public for tests.
func hover_state(sid: int) -> void:
	if not _by_state_id.has(sid):
		sid = -1
	if sid == _hover_sid:
		return
	_hover_sid = sid
	var row: Dictionary = _by_state_id.get(sid, {})
	country_hovered.emit(String(row.get("kingdom_code", "")))
	queue_redraw()

func hovered_state() -> int:
	return _hover_sid

## The hovered kingdom's border loops in native map coordinates ([] when
## nothing is hovered). Built from the provinces it holds NOW (MapOwnership),
## so the outline follows conquest instead of the pack's starting map.
func hover_loops() -> Array:
	var row: Dictionary = _by_state_id.get(_hover_sid, {})
	if row.is_empty():
		return []
	return MapOwnership.outline_of(Game.data, Game.state, String(row["kingdom_code"]))

## Public for tests: open the kingdom card for this Azgaar state id; -1 /
## unknown ids (water, stale bitmap) close the card.
func select_state(sid: int) -> void:
	select_object({"kind": "kingdom", "state_id": sid})

## Open the card for any map object (MapObjects.object_at shape). Water or
## an unknown object closes it.
## Whether a click opens the map's own floating card. A screen with a
## fact card in its left column turns this off and listens to
## object_selected instead.
var use_card := true

func select_object(obj: Dictionary) -> void:
	var entry := MapObjects.describe(Game.data, obj, Game.state)
	if entry.is_empty():
		_selected_obj = {}
		_card.hide()
	else:
		_selected_obj = obj
		entry["obj"] = obj
		if use_card:
			_card.show_entry(entry)
	object_selected.emit(entry)
	queue_redraw()

## Bring a native point to the middle of the frame at the current zoom
## (the Manor Master's row click).
func centre_on(native: Vector2) -> void:
	_offset = size / 2.0 - native * _zoom
	_clamp_offset()
	queue_redraw()

## Ring a manor as if clicked, without opening a card — the table already
## says what it is; activating the row opens the card (select_object).
func highlight_manor(cell: int) -> void:
	_selected_obj = {"kind": "manor", "cell": cell}
	queue_redraw()

## Clear whatever is selected (the fact card's CLOSE).
func clear_selection() -> void:
	# The card lives in the screen's left column now, so clearing the
	# selection has to say so: an empty entry closes it (owner ruling
	# 2026-09-10).
	var had := not _selected_obj.is_empty()
	_selected_obj = {}
	_card.hide()
	if had:
		object_selected.emit({})
	if _selected_province != "":
		_selected_province = ""
		province_selected.emit("")
	queue_redraw()

func set_ask_enabled(on: bool) -> void:
	_card.ask_enabled = on

## Test seams.
func card() -> MapInfoCard:
	return _card

func card_title() -> Label:
	return _card.title_label()
