class_name Map3DLayerLines
extends Node3D
## The ribbon host (spec 2026-09-20 §1): Roads, Trails, ManorEdges, Seams,
## KingdomBand, KingdomHalo, Kingdoms, Hover and Selection, each ONE
## MeshInstance3D named for its line, draped on the relief
## (Map3DBorders.ribbon_arrays) and kept a constant SCREEN width by its shader.
## An empty line leaves no node, so line_mesh() is null for it.

const BORDER_SHADER := preload("res://scripts/map3d/border_line.gdshader")

var ctx: Map3DContext


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx


## One ribbon layer in border_line.gdshader, replacing any before.
func set_lines(line_name: String, lines: Array, style: Map3DLineStyle) -> void:
	var arrays := Map3DBorders.ribbon_arrays(lines, ctx.height_at, [], style.one_sided,
		style.colours)
	var mat := ShaderMaterial.new()
	mat.shader = BORDER_SHADER
	mat.render_priority = style.priority
	mat.set_shader_parameter("colour_a", style.a)
	mat.set_shader_parameter("colour_b", style.b)
	mat.set_shader_parameter("edge_soft", style.edge_soft)
	mat.set_shader_parameter("one_sided", 1.0 if style.one_sided else 0.0)
	mat.set_shader_parameter("use_vertex_colour", 1.0 if not style.colours.is_empty() else 0.0)
	mat.set_shader_parameter("fade_across", style.fade_across)
	mat.set_shader_parameter("fade_power",
		ctx.repo.bal(style.fade_power_key) if style.fade_power_key != "" else 1.0)
	mat.set_meta("width_key", style.width_key)
	mat.set_meta("dash_key", style.dash_key)
	mat.set_meta("gap_key", style.gap_key)
	put_mesh(line_name, arrays, mat)


## Any ribbon mesh (the roads bring their own material), replacing any
## before; nothing when `arrays` is empty.
func put_mesh(line_name: String, arrays: Array, mat: ShaderMaterial) -> void:
	var old := get_node_or_null(line_name)
	if old != null:
		remove_child(old)
		old.queue_free()
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = line_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lines are thin and long: never culled by a box the relief lift pushes them out of.
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	_scale_material(mat)


func line_mesh(line_name: String) -> ArrayMesh:
	var mi := get_node_or_null(line_name) as MeshInstance3D
	return mi.mesh as ArrayMesh if mi != null else null


## Every line's screen-px values in SubViewport px (on load, resize, a tier change).
func apply_scale() -> void:
	for mi: MeshInstance3D in get_children():
		var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
		if mat != null:
			_scale_material(mat)


func _scale_material(mat: ShaderMaterial) -> void:
	if ctx == null:
		return
	var s := ctx.viewport_px_scale()
	mat.set_shader_parameter("px_per_dist", ctx.px_per_dist())
	mat.set_shader_parameter("lift_px", ctx.repo.bal("map3d_line_lift_px") * s)
	mat.set_shader_parameter("width_px", ctx.repo.bal(String(mat.get_meta("width_key"))) * s)
	var dash_key := String(mat.get_meta("dash_key", ""))
	mat.set_shader_parameter("dash_px", ctx.repo.bal(dash_key) * s if dash_key != "" else 0.0)
	var gap_key := String(mat.get_meta("gap_key", ""))
	mat.set_shader_parameter("gap_px", ctx.repo.bal(gap_key) * s if gap_key != "" else 0.0)
