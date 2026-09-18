extends GutTest
## ECONOMY and MANORS on the 3D map (owner 2026-09-19, spec
## 2026-09-19-map3d-manor-themes-design): under a theme the ground wears each
## manor's ManorPalette colour (a LUT the patched Terrain3D shader reads), the
## cell edges are ruled in, and a click on land picks the manor. The fixture
## world has no Terrain3D — the shader patch is skipped there — so these
## tests hold the LUT, the edges and the picking.

const FIXTURE := "user://test_map3d_themes_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func before_each() -> void:
	Game.start_campaign(42)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
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

func test_the_economy_lut_holds_each_manors_colour() -> void:
	var v := _view()
	v.set_manor_theme("economy")
	var id := _crown_cell()
	assert_true(_close(_texel(v, id), ManorPalette.theme_color(Game.data, Game.state, id, "economy")),
		"%s vs %s" % [_texel(v, id), ManorPalette.theme_color(Game.data, Game.state, id, "economy")])
	assert_eq(_texel(v, _water_cell()).a, 0.0, "water wears nothing")
	assert_not_null(v.cell_lut(), "the texture the terrain shader reads")


func test_the_manors_lut_holds_each_houses_colour() -> void:
	var v := _view()
	v.set_manor_theme("manors")
	var id := _crown_cell()
	assert_true(_close(_texel(v, id), ManorPalette.house_color(Game.data, Game.state, id)))


func test_a_conquest_recolours_the_lut() -> void:
	var v := _view()
	v.set_manor_theme("economy")
	var id := _crown_cell()
	var before := _texel(v, id)
	MapOwnership.set_owner(Game.data, Game.state, ManorPalette.province(Game.data, Game.state, id),
		Game.data.resolve_realm("raider_realm"), "test: a raid")
	v.refresh_borders()
	assert_false(_close(_texel(v, id), before), "the raiders' colour now")


func test_the_theme_is_remembered() -> void:
	var v := _view()
	assert_eq(v.manor_theme(), "")
	v.set_manor_theme("manors")
	assert_eq(v.manor_theme(), "manors")


# --- the edges ------------------------------------------------------------------

func _edges_node(v: Map3DView) -> MeshInstance3D:
	return v.viewport().get_node_or_null("Lines/ManorEdges") as MeshInstance3D


func test_the_edges_are_ruled_only_under_a_theme() -> void:
	var v := _view()
	v.set_manor_theme("economy")
	var edges := _edges_node(v)
	assert_not_null(edges)
	assert_true(edges.visible)
	var mat := edges.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DView.PRIORITY_MANOR_EDGES)
	assert_eq(String(mat.get_meta("width_key")), "map_manor_line_width")
	v.set_manor_theme("")
	assert_false(edges.visible)


func test_the_manor_edges_sit_between_the_roads_and_the_seams() -> void:
	assert_lt(Map3DView.PRIORITY_ROADS, Map3DView.PRIORITY_MANOR_EDGES)
	assert_lt(Map3DView.PRIORITY_MANOR_EDGES, Map3DView.PRIORITY_SEAMS)


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
	v.set_manor_theme("economy")
	var cell := _crown_cell()
	v.hover_pick({"kind": "manor", "cell": cell}, Vector2(100, 100))
	assert_eq(v.hover_tooltip(), MapManors.label_of(Game.data, cell))
	assert_eq(v.hovered_kingdom(), Game.data.resolve_realm("player_realm"))
	assert_eq(Map3DView.kingdom_of_pick(Game.data, Game.state, {"kind": "manor", "cell": cell}),
		Game.data.resolve_realm("player_realm"))
