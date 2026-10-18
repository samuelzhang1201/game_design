extends GutTest
## Map3DLayerLines (spec 2026-09-20 §1): every see-through ribbon of the 3D
## map — roads, trails, manor edges, seams, the kingdom band/halo/ink, the
## hover and the selection — lives under one Lines node, one MeshInstance3D
## per name, in border_line.gdshader at its row of the priority table.

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)


func _lines() -> Map3DLayerLines:
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 450)
	add_child_autofree(vp)
	var ctx := Map3DContext.new(Game.data, WORLD)
	ctx.viewport = vp
	var lines := Map3DLayerLines.new()
	lines.name = "Lines"
	vp.add_child(lines)
	lines.bind(ctx)
	return lines


func _line() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 300)])


func test_an_empty_line_leaves_no_mesh() -> void:
	var lines := _lines()
	lines.set_lines("Kingdoms", [], Map3DLayerLines.KINGDOM_INK, Map3DPriority.KINGDOMS)
	assert_null(lines.line_mesh("Kingdoms"))
	assert_null(lines.get_node_or_null("Kingdoms"))


## A line wears its look .tres (owner 2026-10-02: edited in the inspector):
## its colours and soft edge as authored, its px widths scaled to the
## SubViewport, at the priority the code orders.
func test_a_dashed_line_wears_its_look_at_its_priority() -> void:
	var lines := _lines()
	lines.set_lines("Seams", [_line()], Map3DLayerLines.SEAM, Map3DPriority.SEAMS)
	var mesh := lines.line_mesh("Seams")
	assert_not_null(mesh)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	var look := Map3DLayerLines.SEAM as ShaderMaterial
	assert_ne(mat, look, "the line's own copy")
	assert_eq(mat.render_priority, Map3DPriority.SEAMS)
	assert_eq(mat.get_shader_parameter("colour_a"), look.get_shader_parameter("colour_a"))
	assert_eq(mat.get_shader_parameter("colour_b"), look.get_shader_parameter("colour_b"))
	var s := lines.ctx.viewport_px_scale()
	for k: String in Map3DLayerLines.PX_PARAMS:
		assert_almost_eq(float(mat.get_shader_parameter(k)), float(look.get_shader_parameter(k)) * s, 0.0001, k)
	assert_gt(float(look.get_shader_parameter("dash_px")), 0.0, "the seam is dashed")


func test_the_band_draws_one_sided_in_its_realms_colours() -> void:
	var lines := _lines()
	lines.set_lines("KingdomBand", [_line()], Map3DLayerLines.KINGDOM_BAND, Map3DPriority.KINGDOM_BAND,
		[Color.RED])
	var mat := lines.line_mesh("KingdomBand").surface_get_material(0) as ShaderMaterial
	assert_eq(mat.get_shader_parameter("one_sided"), 1.0)
	assert_eq(mat.get_shader_parameter("use_vertex_colour"), 1.0)
	assert_eq(mat.get_shader_parameter("fade_across"), 1.0)


func test_setting_a_line_again_replaces_it() -> void:
	var lines := _lines()
	lines.set_lines("Kingdoms", [_line()], Map3DLayerLines.KINGDOM_INK, Map3DPriority.KINGDOMS)
	var first := lines.line_mesh("Kingdoms")
	lines.set_lines("Kingdoms", [_line(), _line()], Map3DLayerLines.KINGDOM_INK, Map3DPriority.KINGDOMS)
	assert_ne(lines.line_mesh("Kingdoms"), first)
	lines.set_lines("Kingdoms", [], Map3DLayerLines.KINGDOM_INK, Map3DPriority.KINGDOMS)
	assert_null(lines.line_mesh("Kingdoms"), "an emptied line leaves nothing behind")


func test_the_priorities_keep_their_order() -> void:
	var order := [Map3DPriority.APRONS, Map3DPriority.SEA, Map3DPriority.RIVERS, Map3DPriority.ROADS,
		Map3DPriority.MANOR_EDGES, Map3DPriority.KINGDOM_BAND, Map3DPriority.SEAMS,
		Map3DPriority.KINGDOM_HALO, Map3DPriority.KINGDOMS, Map3DPriority.HOVER,
		Map3DPriority.SELECTION, Map3DPriority.CLOUDS, Map3DPriority.RING_BASE]
	for i in range(1, order.size()):
		assert_lt(order[i - 1], order[i])
	assert_eq(Map3DView.PRIORITY_KINGDOMS, Map3DPriority.KINGDOMS)


func test_revisited_hover_reuses_geometry_but_rescales_its_material() -> void:
	var lines := _lines()
	var borders := Map3DLayerBorders.new()
	borders.bind(lines.ctx, lines)
	var mine := Game.data.resolve_realm("player_realm")
	var reads := [0]
	lines.ctx.height_fn = func(_xz: Vector2) -> float:
		reads[0] += 1
		return 5.0
	borders.draw_hover(mine)
	var first := lines.line_mesh("Hover")
	assert_not_null(first)
	assert_gt(reads[0], 0, "the initial outline is draped")
	borders.draw_hover("")
	assert_null(lines.line_mesh("Hover"), "clearing a cached hover removes its drawing")
	var before := int(reads[0])
	lines.ctx.window_scale_fn = func() -> float: return 2.0
	borders.draw_hover(mine)
	assert_same(lines.line_mesh("Hover"), first, "returning reuses the uploaded mesh")
	assert_eq(reads[0], before, "returning never re-samples unchanged terrain")
	var material := lines.line_mesh("Hover").surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("width_px")),
		float(Map3DLayerLines.HOVER.get_shader_parameter("width_px")) * lines.ctx.viewport_px_scale(), 0.0001)


func test_ownership_change_invalidates_cached_hover_geometry() -> void:
	var lines := _lines()
	lines.ctx.state_fn = func() -> GameState: return Game.state
	var borders := Map3DLayerBorders.new()
	borders.bind(lines.ctx, lines)
	borders.refresh()
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var province: String = MapOwnership.provinces_of(Game.data, Game.state, raider)[0]
	borders.draw_hover(mine)
	var first := lines.line_mesh("Hover")
	MapOwnership.set_owner(Game.data, Game.state, province, mine, "test: hover conquest")
	assert_true(borders.refresh())
	assert_not_same(lines.line_mesh("Hover"), first, "a conquest regenerates the active hover")
	var expected := Map3DBorders.ribbon_arrays(Map3DBorders.kingdom_lines(
		Game.data, Game.state, WORLD, mine, lines.ctx.line_step()), lines.ctx.height_at)
	assert_eq(lines.line_mesh("Hover").surface_get_array_len(0),
		(expected[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	MapOwnership.set_owner(Game.data, Game.state, province, raider, "test: hover conquest undone")
