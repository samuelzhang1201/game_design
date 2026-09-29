class_name Map3DLayerTrees
extends Node3D
## The 3D map's woods (look route 2026-09-30, node Viewport/Trees): the
## bake's tree clumps (tools/map3d/bake_trees.py → bake/trees.bin) drawn as
## MultiMeshes in fixed map_tree_chunk_m squares, one per kind and variant
## and level of detail, each square shown by Godot's own visibility range —
## the near clump out to map3d_tree_near_m from the camera, the plain one
## out to map3d_tree_far_m, nothing past it (the ground's own colour carries
## the wood from there). Built ONCE at load: no per-pose rebuild, no CPU per
## frame. Takes everything from Map3DContext — never the Game autoload.

const VARIANTS := 2
const ROW := 6

var ctx: Map3DContext
var _count := 0
var _nodes := 0


func counts() -> Dictionary:
	return {"clumps": _count, "nodes": _nodes}


func build(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	for c in get_children():
		c.queue_free()
	_count = 0
	_nodes = 0
	var repo := ctx.repo
	if repo.bal("map3d_tree_on") <= 0.0:
		return
	var path := ProjectSettings.globalize_path(repo.map3d_dir() + "/bake/trees.bin")
	if not FileAccess.file_exists(path):
		Map3DWorldLoader.warn_once("trees:" + path,
			"Map3DView: no bake/trees.bin — no woods (tools/map3d/bake_trees.py)")
		return
	var data := FileAccess.get_file_as_bytes(path).to_float32_array()
	var n := data.size() / ROW
	var density := clampf(repo.bal("map3d_tree_density"), 0.0, 1.0) * float(ctx.q().get("tree_density", 1.0))
	var chunk := repo.bal("map3d_tree_chunk_m")
	var scale := repo.bal("map3d_tree_scale")
	var near := repo.bal("map3d_tree_near_m")
	var far := repo.bal("map3d_tree_far_m")
	var margin := repo.bal("map3d_tree_margin_m")
	# chunk key -> "kind:variant" -> PackedInt32Array of rows
	var groups := {}
	for i in n:
		# a stable thinning for a lower density: the row's own hash
		if density < 1.0 and float((i * 2654435761) % 1000) / 1000.0 >= density:
			continue
		var x := data[i * ROW]
		var z := data[i * ROW + 2]
		var key := Vector2i(floori(x / chunk), floori(z / chunk))
		var sub := "%d:%d" % [int(data[i * ROW + 5]), i % VARIANTS]
		if not groups.has(key):
			groups[key] = {}
		var g: Dictionary = groups[key]
		var rows_of: PackedInt32Array = g.get(sub, PackedInt32Array())
		rows_of.append(i)   # a packed array is a value: write it back
		g[sub] = rows_of
	var meshes := {}
	var mat := _material()
	for kind in 3:
		for v in VARIANTS:
			for lod in 2:
				var m := Map3DTreeMesh.clump(kind, lod, v)
				m.surface_set_material(0, mat)
				meshes["%d:%d:%d" % [kind, v, lod]] = m
	for key: Vector2i in groups:
		var g: Dictionary = groups[key]
		for sub: String in g:
			var rows: PackedInt32Array = g[sub]
			var centre := Vector3((key.x + 0.5) * chunk, 0.0, (key.y + 0.5) * chunk)
			for lod in 2:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = meshes["%s:%d" % [sub, lod]]
				mm.instance_count = rows.size()
				for j in rows.size():
					var i := rows[j]
					var s := data[i * ROW + 4] * scale
					var basis := Basis(Vector3.UP, data[i * ROW + 3]).scaled(Vector3(s, s, s))
					var at := Vector3(data[i * ROW], data[i * ROW + 1], data[i * ROW + 2]) - centre
					mm.set_instance_transform(j, Transform3D(basis, at))
					var h := float((i * 40503) % 997) / 997.0
					mm.set_instance_color(j, Color(0.9 + 0.2 * h, 0.92 + 0.16 * h, 0.9 + 0.1 * (1.0 - h)))
				var node := MultiMeshInstance3D.new()
				node.multimesh = mm
				node.position = centre
				# both levels cast: a plain square without its shadows read as a
				# lighter tile in the wood; the switch dithers over the margin
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if lod == 0:
					node.visibility_range_end = near
					node.visibility_range_end_margin = margin
				else:
					node.visibility_range_begin = near
					node.visibility_range_begin_margin = margin
					node.visibility_range_end = far
					node.visibility_range_end_margin = margin
				add_child(node)
				_nodes += 1
			_count += rows.size()


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.metallic_specular = 0.15
	m.albedo_color = Color.WHITE
	return m
