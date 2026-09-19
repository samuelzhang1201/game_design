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
	lines.set_lines("Kingdoms", [], Map3DLineStyle.solid(Color.BLACK,
		"map3d_border_width_px", Map3DPriority.KINGDOMS))
	assert_null(lines.line_mesh("Kingdoms"))
	assert_null(lines.get_node_or_null("Kingdoms"))


func test_a_dashed_line_is_one_mesh_at_its_priority() -> void:
	var lines := _lines()
	var seam := Color(0.2, 0.2, 0.2, 0.5)
	lines.set_lines("Seams", [_line()], Map3DLineStyle.dashed(seam, Color(seam, 0.0),
		"map3d_seam_width_px", "map3d_seam_dash_px", "map3d_seam_gap_px", Map3DPriority.SEAMS))
	var mesh := lines.line_mesh("Seams")
	assert_not_null(mesh)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DPriority.SEAMS)
	assert_eq(mat.get_shader_parameter("colour_a"), seam)
	assert_almost_eq(float(mat.get_shader_parameter("width_px")), Game.data.bal("map3d_seam_width_px"), 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("dash_px")), Game.data.bal("map3d_seam_dash_px"), 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("gap_px")), Game.data.bal("map3d_seam_gap_px"), 0.0001)


func test_the_band_style_reaches_the_shader() -> void:
	var lines := _lines()
	var style := Map3DLineStyle.solid(Color(1, 1, 1, 0.55), "map3d_border_band_px",
		Map3DPriority.KINGDOM_BAND)
	style.one_sided = true
	style.colours = [Color.RED]
	style.fade_across = 1.0
	style.fade_power_key = "map3d_border_band_fade_power"
	lines.set_lines("KingdomBand", [_line()], style)
	var mat := lines.line_mesh("KingdomBand").surface_get_material(0) as ShaderMaterial
	assert_eq(mat.get_shader_parameter("one_sided"), 1.0)
	assert_eq(mat.get_shader_parameter("use_vertex_colour"), 1.0)
	assert_eq(mat.get_shader_parameter("fade_across"), 1.0)
	assert_eq(mat.get_shader_parameter("fade_power"), Game.data.bal("map3d_border_band_fade_power"))


func test_setting_a_line_again_replaces_it() -> void:
	var lines := _lines()
	var style := Map3DLineStyle.solid(Color.BLACK, "map3d_border_width_px", Map3DPriority.KINGDOMS)
	lines.set_lines("Kingdoms", [_line()], style)
	var first := lines.line_mesh("Kingdoms")
	lines.set_lines("Kingdoms", [_line(), _line()], style)
	assert_ne(lines.line_mesh("Kingdoms"), first)
	lines.set_lines("Kingdoms", [], style)
	assert_null(lines.line_mesh("Kingdoms"), "an emptied line leaves nothing behind")


func test_the_priorities_keep_their_order() -> void:
	var order := [Map3DPriority.SEA, Map3DPriority.RIVERS, Map3DPriority.ROADS,
		Map3DPriority.MANOR_EDGES, Map3DPriority.KINGDOM_BAND, Map3DPriority.SEAMS,
		Map3DPriority.KINGDOM_HALO, Map3DPriority.KINGDOMS, Map3DPriority.HOVER,
		Map3DPriority.SELECTION, Map3DPriority.CLOUDS, Map3DPriority.RING_BASE]
	for i in range(1, order.size()):
		assert_lt(order[i - 1], order[i])
	assert_eq(Map3DView.PRIORITY_KINGDOMS, Map3DPriority.KINGDOMS)
