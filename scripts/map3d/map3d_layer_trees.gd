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
const SWAY_SHADER := preload("res://scripts/map3d/tree_sway.gdshader")
const CARD_SHADER := preload("res://scripts/map3d/tree_card.gdshader")
## The crown atlas the photo cards wear (tools/map3d/build_tree_atlas.py).
const CROWN_ATLAS := "res://assets/3D/vegetation/crowns/crowns_atlas.png"
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
	var density := clampf(repo.bal("map3d_tree_density"), 0.0, 1.0) * Map3DQuality.num(ctx.q(), "tree_density", 1.0)
	# photo cards (owner 2026-10-01: the 3D crowns read fake below a 20 km
	# scale): one level, drawn out to map3d_tree_card_far_m
	var cards := repo.bal("map3d_tree_cards") > 0.0 and ResourceLoader.exists(CROWN_ATLAS) \
		and not repo.map3d_tree_crowns.is_empty()
	# The clumps are kept between views (Map3DAssetCache's rule: ~0.5 s a
	# screen swap), by every input they are made of; the nodes are this view's.
	var look: Array = [path, FileAccess.get_modified_time(path), density, cards, repo.map3d_tree_crowns]
	for k: String in ["map3d_tree_chunk_m", "map3d_tree_scale", "map3d_tree_size_spread"] \
			+ LOOK.keys() + CARD_LOOK.keys():
		look.append(repo.bal(k))
	var key := var_to_str(look).md5_text()
	if key != _kept_key:
		_kept = _plan(FileAccess.get_file_as_bytes(path).to_float32_array(), density, cards)
		_kept_key = key
	material = _kept["material"]
	var near := repo.bal("map3d_tree_card_far_m") if cards else repo.bal("map3d_tree_near_m")
	var far := repo.bal("map3d_tree_card_far_m") if cards else repo.bal("map3d_tree_far_m")
	var margin := repo.bal("map3d_tree_margin_m")
	for one: Array in _kept["chunks"]:
		var node := MultiMeshInstance3D.new()
		node.multimesh = one[0]
		node.position = one[1]
		# both levels cast: a plain square without its shadows read as a
		# lighter tile in the wood; the switch dithers over the margin
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if int(one[2]) == 0:
			node.visibility_range_end = near
			node.visibility_range_end_margin = margin
		else:
			node.visibility_range_begin = near
			node.visibility_range_begin_margin = margin
			node.visibility_range_end = far
			node.visibility_range_end_margin = margin
		add_child(node)
		_nodes += 1
	_count = int(_kept["count"])


static var _kept_key := ""
static var _kept: Dictionary = {}


## The woods' MultiMeshes from the bake's rows: {material, count, chunks: [[the
## MultiMesh, its square's centre, its level]]}.
func _plan(data: PackedFloat32Array, density: float, cards: bool) -> Dictionary:
	var repo := ctx.repo
	@warning_ignore("integer_division")
	var n := data.size() / ROW
	var chunk := repo.bal("map3d_tree_chunk_m")
	var size_k := repo.bal("map3d_tree_scale")
	var size_spread := repo.bal("map3d_tree_size_spread")
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
	var mat := _card_material() if cards else _material()
	var lods := 1 if cards else 2
	for kind in 3:
		var cells := PackedInt32Array()
		for r: Dictionary in repo.map3d_tree_crowns:
			if int(r["kind"]) == kind:
				cells.append(int(r["cell"]))
		for v in VARIANTS:
			for lod in lods:
				var m := Map3DTreeMesh.cards(kind, v, cells) if cards else Map3DTreeMesh.clump(kind, lod, v)
				m.surface_set_material(0, mat)
				meshes["%d:%d:%d" % [kind, v, lod]] = m
	var chunks: Array = []
	var count := 0
	for key: Vector2i in groups:
		var g: Dictionary = groups[key]
		for sub: String in g:
			var rows: PackedInt32Array = g[sub]
			var centre := Vector3((key.x + 0.5) * chunk, 0.0, (key.y + 0.5) * chunk)
			for lod in lods:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = meshes["%s:%d" % [sub, lod]]
				mm.instance_count = rows.size()
				for j in rows.size():
					var i := rows[j]
					# a wood of old trees and young ones, not one even carpet
					var grow := 1.0 + size_spread * (float((i * 2246822519) % 1009) / 1009.0 * 2.0 - 1.0)
					var s := data[i * ROW + 4] * size_k * grow
					var turn := Basis(Vector3.UP, data[i * ROW + 3]).scaled(Vector3(s, s, s))
					var at := Vector3(data[i * ROW], data[i * ROW + 1], data[i * ROW + 2]) - centre
					mm.set_instance_transform(j, Transform3D(turn, at))
					var h := float((i * 40503) % 997) / 997.0
					var h2 := float((i * 69069) % 991) / 991.0
					mm.set_instance_color(j, Color(0.8 + 0.35 * h, 0.82 + 0.28 * h2, 0.8 + 0.2 * (1.0 - h)))
				chunks.append([mm, centre, lod])
			count += rows.size()
	return {"material": mat, "count": count, "chunks": chunks}


## The one material every clump shares: tree_sway.gdshader (the wind's sway;
## Map3DLayerWind sets its uniforms each frame).
var material: ShaderMaterial


func _material() -> ShaderMaterial:
	material = ShaderMaterial.new()
	material.shader = SWAY_SHADER
	# the foliage's look (owner 2026-10-01: below a 20 km scale the woods read
	# fake): leaf clumps, a hue per crown, a natural saturation, no sheen
	for key: String in LOOK:
		material.set_shader_parameter(LOOK[key], ctx.repo.bal(key))
	return material


## balance.csv key -> tree_sway.gdshader uniform
const LOOK := {
	"map3d_tree_leaf_m": "leaf_m",
	"map3d_tree_leaf_contrast": "leaf_contrast",
	"map3d_tree_leaf_bump": "leaf_bump",
	"map3d_tree_hue_spread": "hue_spread",
	"map3d_tree_hue_bias": "hue_bias",
	"map3d_tree_saturation": "saturation",
	"map3d_tree_value": "value_gain",
	"map3d_tree_roughness": "roughness_value",
	"map3d_tree_specular": "specular_value",
}


## The photo cards' material: tree_card.gdshader over the crown atlas, the
## look bound from balance.csv map3d_tree_card_* (Map3DLayerWind sets the
## wind's uniforms on `material` each frame, as for the 3D crowns).
func _card_material() -> ShaderMaterial:
	material = ShaderMaterial.new()
	material.shader = CARD_SHADER
	material.set_shader_parameter("atlas", load(CROWN_ATLAS))
	for key: String in CARD_LOOK:
		material.set_shader_parameter(CARD_LOOK[key], ctx.repo.bal(key))
	return material


const CARD_LOOK := {
	"map3d_tree_card_alpha_cut": "alpha_cut",
	"map3d_tree_card_sphere": "sphere",
	"map3d_tree_card_lift": "lift",
	"map3d_tree_card_saturation": "saturation",
	"map3d_tree_card_value": "value_gain",
	"map3d_tree_card_tint": "tint_k",
	"map3d_tree_card_alpha_far": "alpha_far_gain",
	"map3d_tree_card_far_value": "far_value",
}
