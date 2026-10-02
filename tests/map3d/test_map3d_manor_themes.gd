extends GutTest
## MANORS on the 3D map (owner 2026-09-19, spec
## 2026-09-19-map3d-manor-themes-design; ECONOMY folded into it the same day):
## the ground wears each manor's house colour (ManorPalette) (a LUT the patched Terrain3D shader reads), the
## cell edges are ruled in, and a click on land picks the manor. The fixture
## world has no Terrain3D — the shader patch is skipped there — so these
## tests hold the LUT, the edges and the picking.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_manor_themes").path_join("test_map3d_themes_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func _crown_cell() -> int:
	var mine := Game.data.resolve_realm("player_realm")
	var ids: Array = Game.data.cells.keys()
	ids.sort()
	for id: int in ids:
		if not MapTerrain.is_water(Game.data.cells[id]) \
				and ManorPalette.owner(Game.data, Game.state, id) == mine:
			return id
	return -1


func _water_cell() -> int:
	for id: int in Game.data.cells:
		if MapTerrain.is_water(Game.data.cells[id]):
			return id
	return -1


func _texel(v: Map3DView, id: int) -> Color:
	return v.lut_color(id)


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 1.5 / 255.0 and absf(a.g - b.g) <= 1.5 / 255.0 \
		and absf(a.b - b.b) <= 1.5 / 255.0 and absf(a.a - b.a) <= 1.5 / 255.0


# --- the LUT --------------------------------------------------------------------

func test_the_manors_lut_holds_each_houses_colour() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var id := _crown_cell()
	assert_true(_close(_texel(v, id), ManorPalette.house_color(Game.data, Game.state, id)))
	assert_eq(_texel(v, _water_cell()).a, 0.0, "water wears nothing")
	assert_not_null(v.cell_lut(), "the texture the terrain shader reads")


func test_a_conquest_recolours_the_lut() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var id := _crown_cell()
	var before := _texel(v, id)
	MapOwnership.set_owner(Game.data, Game.state, ManorPalette.province(Game.data, Game.state, id),
		Game.data.resolve_realm("raider_realm"), "test: a raid")
	v.refresh_borders()
	assert_false(_close(_texel(v, id), before), "the raiders' colour now")


# --- the edges ------------------------------------------------------------------

func _edges_node(v: Map3DView) -> MeshInstance3D:
	return v.world().get_node_or_null("Lines/ManorEdges") as MeshInstance3D


func test_the_edges_are_ruled_only_under_a_theme() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var edges := _edges_node(v)
	assert_not_null(edges)
	assert_true(edges.visible)
	var mat := edges.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DView.PRIORITY_MANOR_EDGES)
	assert_eq(mat.get_shader_parameter("colour_a"), Map3DLayerLines.MANOR_EDGE.get_shader_parameter("colour_a"))
	v.set_manor_theme("")
	assert_false(edges.visible)


# --- picking and hovering a manor -------------------------------------------------

func _click(v: Map3DView, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	v._gui_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	v._gui_input(up)


## A manor's pixel (a land cell in a province) with no settlement within
## 60 px, and the manor it lies in.
func _open_land() -> Dictionary:
	var img := (load(Game.data.cell_texture_path) as Texture2D).get_image()
	for y in range(40, img.get_height() - 40, 25):
		for x in range(40, img.get_width() - 40, 25):
			var id := MapIndex.id_at(img, Vector2i(x, y))
			if not Game.data.manors.has(id) or MapManors.province_of(Game.data, id) == "":
				continue
			var clear := true
			for b: Dictionary in Game.data.burgs.values():
				if Vector2(float(b["x"]), float(b["y"])).distance_to(Vector2(x, y)) < 60.0:
					clear = false
					break
			if clear:
				return {"px": Vector2(x + 0.5, y + 0.5), "cell": id}
	return {}


func test_under_a_theme_a_click_on_land_opens_the_manor() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var spot := _open_land()
	v.look_at_pack(spot["px"], Game.data.bal("map3d_zoom_min_m"))
	watch_signals(v)
	_click(v, v.size * 0.5)
	var cell := int(spot["cell"])
	assert_signal_emitted_with_parameters(v, "object_selected",
		[{"title": MapManors.label_of(Game.data, cell), "obj": {"kind": "manor", "cell": cell}}])
	assert_not_null(v.line_mesh("Selection"), "the manor is outlined in gold")


func test_without_a_theme_the_same_click_names_the_province() -> void:
	var v := _view()
	var spot := _open_land()
	v.look_at_pack(spot["px"], Game.data.bal("map3d_zoom_min_m"))
	watch_signals(v)
	_click(v, v.size * 0.5)
	assert_signal_emitted_with_parameters(v, "province_selected",
		[MapManors.province_of(Game.data, int(spot["cell"]), Game.state)])


func test_hovering_a_manor_names_it_and_its_holder() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var cell := _crown_cell()
	v.hover_pick({"kind": "manor", "cell": cell}, Vector2(100, 100))
	assert_eq(v.hover_tooltip(), MapManors.label_of(Game.data, cell))
	assert_eq(v.hovered_kingdom(), Game.data.resolve_realm("player_realm"))
	assert_eq(Map3DView.kingdom_of_pick(Game.data, Game.state, {"kind": "manor", "cell": cell}),
		Game.data.resolve_realm("player_realm"))


# --- the output badges (owner 2026-09-19: ECONOMY's, folded into MANORS) -------

## The busiest manor whose badge the fog still allows to show (Intel, spec
## 2026-09-28 §1: a badge is a true output figure, so only a manor of a
## province the crown controls wears one) — every test below needs a manor
## whose badge actually draws.
## Found once: every test starts the same campaign (seed 42), whose answer
## is the same, and Intel.level over every manor is the costly part.
var _busiest := -2


func _busiest_manor() -> int:
	if _busiest == -2:
		_busiest = _find_busiest_manor()
	return _busiest


func _find_busiest_manor() -> int:
	var all: Dictionary = MapEconomy.manors(Game.data)
	var best := -1
	for id: int in all:
		if Intel.level(Game.data, Game.state, {"kind": "manor", "cell": id, "code": "", "x": 0, "y": 0}) != "full":
			continue
		if best < 0 or float(all[id]["units"]) > float(all[best]["units"]):
			best = id
	return best


func _look_at_manor(v: Map3DView, cell: int, at_m: float) -> void:
	v.look_at_pack(MapTerrain.cell_center(Game.data, Game.data.cells[cell]), at_m)


func test_output_badges_stand_over_the_working_manors() -> void:
	var v := _view()
	var cell := _busiest_manor()
	_look_at_manor(v, cell, 12000.0)
	assert_eq(v.manor_badges().size(), 0, "no badges without the MANORS theme")
	v.set_manor_theme("manors")
	var badges := v.manor_badges()
	assert_gt(badges.size(), 0)
	var mine: Dictionary = {}
	for b: Dictionary in badges:
		if int(b["cell"]) == cell:
			mine = b
	assert_false(mine.is_empty(), "the busiest manor in view wears its badge")
	assert_almost_eq((mine["center"] as Vector2).x, v.size.x * 0.5, 2.0, "over its cell's centre")
	assert_eq(String(mine["good"]), String(MapEconomy.manors(Game.data)[cell]["good"]))


func test_badges_never_overlap() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	# 60000 m used to bring several manors into view; fogged (Intel), only the
	# crown's own show badges now, so a wider or narrower view holds a
	# different count depending on exactly how the culled ones overlap and
	# get dropped (ManorBadges.place) — widen out until there are at least
	# two to actually check against each other.
	var cell := _busiest_manor()
	var dist := 15000.0
	_look_at_manor(v, cell, dist)
	while v.manor_badges().size() < 2 and dist < 300000.0:
		dist *= 1.6
		_look_at_manor(v, cell, dist)
	# So this can never pass without actually checking anything.
	assert_gte(v.manor_badges().size(), 2, "need at least two badges in view to test overlap")
	var rects: Array = []
	for b: Dictionary in v.manor_badges():
		for r: Rect2 in rects:
			assert_false(r.intersects(b["rect"]), "badges overlap")
		rects.append(b["rect"])


func test_a_click_on_a_badge_opens_its_town() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var cell := _busiest_manor()
	_look_at_manor(v, cell, 12000.0)
	var mine: Dictionary = {}
	for b: Dictionary in v.manor_badges():
		if int(b["cell"]) == cell:
			mine = b
	watch_signals(v)
	_click(v, (mine["badge"] as Rect2).get_center() + Vector2(3, 0))
	var code := String(mine["burg"])
	assert_signal_emitted_with_parameters(v, "object_selected",
		[{"title": String(Game.data.burgs[code]["label"]), "obj": {"kind": "burg", "code": code}}])


func test_the_hud_draws_the_badges() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	_look_at_manor(v, _busiest_manor(), 12000.0)
	await wait_process_frames(2)
	assert_gt(v.drawn_badge_count(), 0)


## The badges are cut once per camera pose (final review 2026-09-20): the HUD's
## draw and Map3DPicker.pick_at both ask for them every frame the pointer moves,
## so a second call at the same pose is the SAME array, and a moved camera a new
## one — Map3DHudLandmarks.marks()' rule.
func test_badges_are_cut_once_per_pose() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var cell := _busiest_manor()
	_look_at_manor(v, cell, 12000.0)
	var a := v.manor_badges()
	assert_gt(a.size(), 0)
	assert_true(is_same(a, v.manor_badges()), "the same pose, the same cut")
	_look_at_manor(v, cell, 24000.0)
	assert_false(is_same(a, v.manor_badges()), "a new pose, a new cut")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
