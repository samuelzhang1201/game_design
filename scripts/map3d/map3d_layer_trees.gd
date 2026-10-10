@tool
class_name Map3DLayerTrees
extends Node3D
## The 3D map's woods (look route 2026-09-30, node Viewport/Trees): the
## bake's tree clumps (tools/map3d/bake_trees.py → bake/trees.bin) drawn as
## MultiMeshes in fixed map_tree_chunk_m squares, one per species (the kind
## column, data/map3d_tree_species.csv), variant and level of detail, each
## square shown by Godot's own visibility range — the photo cards out to
## map3d_tree_card_far_m from the camera, then the same clumps thinned to
## map3d_tree_card_thin out to map3d_tree_card_thin_far_m (each switch faded
## over map3d_tree_card_fade_m), nothing past it (the ground's canopy tint).
## Past map3d_lod_trees_m of camera distance the whole wood is HIDDEN
## (owner 2026-10-10: 镜头抬高到很高，不需要渲染树木 — LOD like other games),
## shown again under it by map3d_lod_margin_m. Built ONCE at load: no
## per-pose rebuild. Takes everything from Map3DContext — never the Game
## autoload.
## The crown atlas the photo cards wear (tools/map3d/build_tree_atlas.py).
const CROWN_ATLAS := "res://assets/3D/vegetation/crowns/crowns_atlas.png"
const ROW := 6

var ctx: Map3DContext
var _count := 0
var _nodes := 0
## Every chunk's node hangs under this one (unowned), which the height gate
## hides: the layer's own `visible` stays the theme's (Map3DView.set_manor_theme).
var _woods: Node3D
var _shown := true
## Editor preview (owner 2026-10-02: the world opened in the editor's 3D
## view): the woods from the pack's bake alone, unowned, never saved.
@export var preview := false: set = set_preview


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	Map3DPreview.clear_generated(self)
	if on:
		var c := Map3DPreview.context_for(self)
		Map3DPreview.prepare(self, c)
		if not c.meta.is_empty():
			build(c)
	Map3DPreview.sync_viewport(self)


func counts() -> Dictionary:
	return {"clumps": _count, "nodes": _nodes}


## Whether the woods are drawn at the camera's distance now (the height gate).
func woods_shown() -> bool:
	return _woods != null and _woods.visible


func _on_camera_moved() -> void:
	gate(ctx.distance)


## The height gate: hidden past map3d_lod_trees_m, shown again only once the
## camera is map3d_lod_margin_m back under it.
func gate(distance: float) -> void:
	if ctx == null or _woods == null:
		return
	_shown = Map3DGeometry.lod_shown(_shown, distance, ctx.repo.bal("map3d_lod_trees_m"),
		ctx.repo.bal("map3d_lod_margin_m"))
	_woods.visible = _shown


func build(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	for c in get_children():
		if c.owner == null:
			c.queue_free()
	_count = 0
	_nodes = 0
	_woods = Node3D.new()
	_woods.name = "Woods"
	add_child(_woods)
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)
	var repo := ctx.repo
	if repo.bal("map3d_tree_on") <= 0.0:
		return
	# by its res:// path: exported, the res:// tree is the pack (Map3DLayerThemes.load_field_map)
	var path := repo.map3d_dir() + "/bake/trees.bin"
	if not FileAccess.file_exists(path):
		Map3DWorldLoader.warn_once("trees:" + path,
			"Map3DView: no bake/trees.bin — no woods (tools/map3d/bake_trees.py)")
		return
	var density := clampf(repo.bal("map3d_tree_density"), 0.0, 1.0) * Map3DQuality.num(ctx.q(), "tree_density", 1.0)
	# photo cards (owner 2026-10-01: the 3D crowns read fake below a 20 km
	# scale): one level, drawn out to map3d_tree_card_far_m
	var cards := repo.bal("map3d_tree_cards") > 0.0 and ResourceLoader.exists(CROWN_ATLAS) \
		and not repo.map3d_tree_species.is_empty()
	# The clumps are kept between views (Map3DAssetCache's rule: ~0.5 s a
	# screen swap), by every input they are made of; the nodes are this view's.
	var look: Array = [path, FileAccess.get_modified_time(path), density, cards, repo.map3d_tree_species]
	for k: String in ["map3d_tree_chunk_m", "map3d_tree_scale", "map3d_tree_size_spread", "map3d_tree_card_thin",
			"map3d_tree_variants", "map3d_tree_thin_cell_m"]:
		look.append(repo.bal(k))
	var key := var_to_str(look).md5_text()
	if key != _kept_key:
		_kept = _plan(FileAccess.get_file_as_bytes(path).to_float32_array(), density, cards)
		_kept_key = key
	material = _kept["material"]
	var near := repo.bal("map3d_tree_card_far_m") if cards else repo.bal("map3d_tree_near_m")
	var far := repo.bal("map3d_tree_card_thin_far_m") if cards else repo.bal("map3d_tree_far_m")
	var margin := repo.bal("map3d_tree_card_fade_m") if cards else repo.bal("map3d_tree_margin_m")
	var fade := margin
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
			node.visibility_range_end_margin = fade
		else:
			node.visibility_range_begin = near
			node.visibility_range_begin_margin = margin
			node.visibility_range_end = far
			node.visibility_range_end_margin = margin
		_woods.add_child(node)
		_nodes += 1
	_count = int(_kept["count"])
	_shown = true
	gate(ctx.distance)


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
	var variants := maxi(int(repo.bal("map3d_tree_variants")), 1)
	var thin_cell := repo.bal("map3d_tree_thin_cell_m")
	var rows_of_kind := {}   # kind -> its species row, drawn only when enabled with cells
	for r: Dictionary in repo.map3d_tree_species:
		if int(r["enabled"]) == 1 and String(r["cells"]).strip_edges() != "":
			rows_of_kind[int(r["kind"])] = r
	# chunk key -> "kind:variant" -> PackedInt32Array of rows
	var groups := {}
	for i in n:
		var x := data[i * ROW]
		var z := data[i * ROW + 2]
		# a lower density thins EVENLY over the ground (an ordered dither by
		# place), never in random holes
		if density < 1.0 and Map3DGeometry.thin_rank(x, z, thin_cell) >= density:
			continue
		var kind := int(data[i * ROW + 5])
		if cards and not rows_of_kind.has(kind):
			continue
		var key := Vector2i(floori(x / chunk), floori(z / chunk))
		var sub := "%d:%d" % [kind, i % variants]
		if not groups.has(key):
			groups[key] = {}
		var g: Dictionary = groups[key]
		var rows_of: PackedInt32Array = g.get(sub, PackedInt32Array())
		rows_of.append(i)   # a packed array is a value: write it back
		g[sub] = rows_of
	var meshes := {}
	var mat := _card_material() if cards else _material()
	# the cards' far level is the same clumps THINNED evenly (map3d_tree_card_thin)
	var lods := 2
	var thin := repo.bal("map3d_tree_card_thin")
	var tints := {}   # kind -> [lo, hi]
	for r: Dictionary in repo.map3d_tree_species:
		var kind := int(r["kind"])
		tints[kind] = [Color(String(r["tint_lo"])), Color(String(r["tint_hi"]))]
		var form := Map3DTreeMesh.CONIFER if String(r["form"]) == "conifer" else Map3DTreeMesh.BROADLEAF
		for v in variants:
			for lod in lods:
				if cards and not rows_of_kind.has(kind):
					continue
				var m := Map3DTreeMesh.species_cards(r, v) if cards else Map3DTreeMesh.clump(form, lod, v)
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
				if cards and lod == 1:
					rows = _thinned(data, rows, thin, thin_cell)
					if rows.is_empty():
						continue
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
					mm.set_instance_color(j, tint_of(tints.get(int(data[i * ROW + 5]), [Color.WHITE, Color.WHITE]), i))
				chunks.append([mm, centre, lod])
				if lod == 0:
					count += rows.size()
	return {"material": mat, "count": count, "chunks": chunks}


## `rows` kept where Map3DGeometry.thin_rank (on a 2x coarser square, so the
## near level's own thinning never empties it) is under `share`.
static func _thinned(data: PackedFloat32Array, rows: PackedInt32Array, share: float, cell: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in rows:
		if Map3DGeometry.thin_rank(data[i * ROW] + cell * 0.5, data[i * ROW + 2] + cell * 0.5, cell * 2.0) < share:
			out.append(i)
	return out


## A clump's tint: its species' tint_lo..tint_hi, each channel by the row's own hash.
static func tint_of(range_lohi: Array, i: int) -> Color:
	var lo: Color = range_lohi[0]
	var hi: Color = range_lohi[1]
	var h := float((i * 40503) % 997) / 997.0
	var h2 := float((i * 69069) % 991) / 991.0
	return Color(lerpf(lo.r, hi.r, h), lerpf(lo.g, hi.g, h2), lerpf(lo.b, hi.b, 1.0 - h))


## The one material every clump shares: a copy of SWAY_MAT or CARD_MAT
## (Map3DLayerWind sets the wind's uniforms on it each frame).
var material: ShaderMaterial

## The foliage's look (owner 2026-10-01: below a 20 km scale the woods read
## fake — leaf clumps, a hue per crown, a natural saturation, no sheen),
## edited in the inspector (owner 2026-10-02); the wind's uniforms are
## Map3DLayerWind's.
const SWAY_MAT := preload("res://scenes/map3d/materials/tree_sway.tres")
## The photo cards' look over the crown atlas, edited in the inspector.
const CARD_MAT := preload("res://scenes/map3d/materials/tree_card.tres")


func _material() -> ShaderMaterial:
	material = SWAY_MAT.duplicate() as ShaderMaterial
	return material


func _card_material() -> ShaderMaterial:
	material = CARD_MAT.duplicate() as ShaderMaterial
	return material
