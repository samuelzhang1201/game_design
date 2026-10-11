class_name Map3DLayerRoads
extends RefCounted
## Roads, trails and their bridges as one builder (spec 2026-09-20 §1): the
## pack's land routes, smoothed as the 2D map smooths them, draped on the
## relief through Map3DLayerLines (Lines/Roads, Lines/Trails), each drawn at
## its REAL width in the rocky_trail_02 texture up close, fading to the
## worn-sand palette colour far away (road_line.gdshader); and wherever one
## crosses a river it runs over a stone BRIDGE (Map3DBridges), built here as
## ONE mesh under the world's Bridges node in the medieval_blocks_03 stone. Routes
## never move, so they are built once, after the rivers — the risk this task
## guards (bridges read the river courses).

## The roads', the trails' and the bridges' LOOKS (owner 2026-10-02: edited
## in the inspector) — the colour, the screen-px floor and lift, the soft and
## frayed edge, the texture's tile, tint and fade by metres per px, a
## trail's fade far out; the stone's colour and its fade far away — with the
## committed 512 px previews of their textures (tools/map3d/make_previews.gd).
## What the code sets is the drawn width in metres (the geometry's: the bake
## and the bridges' decks read it), the full-resolution textures when
## packed, and the px scaled to the SubViewport (Map3DLayerLines).
const ROAD_MAT := preload("res://scenes/map3d/materials/road_line.tres")
const TRAIL_MAT := preload("res://scenes/map3d/materials/trail_line.tres")
const BRIDGE_MAT := preload("res://scenes/map3d/materials/bridge_stone.tres")
## The road surface and the bridges' stone at full resolution (Poly Haven,
## packed by tools/map3d/pack_textures.py into the git-ignored textures
## folder): they replace the previews when present (Ruling 15).
const ROAD_TEXTURE := "res://assets/3D/terrain/textures/rocky_trail_02"
const BRIDGE_TEXTURE := "res://assets/3D/terrain/textures/medieval_blocks_03"

var ctx: Map3DContext
var lines: Map3DLayerLines
## The node the Bridges mesh stands under (the world; null: no bridges).
var host: Node
## Every bridge built (Map3DBridges.plan's, each with its deck_w).
var _bridges: Array = []


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_host: Node) -> void:
	ctx = p_ctx
	lines = p_lines
	host = p_host


## Roads and trails (each its own ribbon layer, Lines/Roads and Lines/Trails)
## and every bridge where one crosses `courses` (the rivers' own drawn
## courses — the rivers must already be built).
func build(courses: Array) -> void:
	var plan := plan_for(ctx, courses)
	for line_name: String in ["Roads", "Trails"]:
		lines.put_mesh(line_name, plan[line_name], road_material(ctx, line_name))
	_place_bridges(bridge_mesh(ctx, plan["bridges"]))


## The build's baked roads, trails and bridges (Map3DLayerBake), drawn as
## they are: the loaded meshes are shared, so they are never edited.
func build_baked(meshes: Dictionary) -> void:
	lines.put_baked("Roads", meshes["roads"], road_material(ctx, "Roads"))
	lines.put_baked("Trails", meshes["trails"], road_material(ctx, "Trails"))
	_place_bridges(meshes["bridges"])  # its meta "bridges" is the list


## What build() draws and tools/map3d/bake_layers.gd saves (Task 20): the
## ribbon arrays of "Roads" and "Trails" (on the ground, or on a bridge deck)
## and "bridges", every bridge where one crosses `courses`, each with its deck_w.
static func plan_for(p_ctx: Map3DContext, courses: Array) -> Dictionary:
	var step := p_ctx.road_step()
	var out: Dictionary = {"bridges": []}
	var rules := bridge_rules_of(p_ctx.repo)
	for group: String in ["roads", "trails"]:
		var key := "road" if group == "roads" else "trail"
		var width_m := p_ctx.repo.bal("map3d_%s_width_m" % key)
		var plan := Map3DBridges.plan(Map3DBorders.route_lines(p_ctx.repo, p_ctx.meta, group, step),
			courses, p_ctx.height_at, rules)
		var dry := dry_runs(plan["lines"], plan["heights"], sea_test(p_ctx))
		out[group.capitalize()] = Map3DBorders.ribbon_arrays(dry["lines"], p_ctx.height_at, dry["heights"])
		var deck_w := width_m + p_ctx.repo.bal("map3d_bridge_extra_w_m")
		for b: Dictionary in plan["bridges"]:
			b["deck_w"] = deck_w
		(out["bridges"] as Array).append_array(plan["bridges"])
	return out


## Whether a world XZ lies out at sea, by the pack's sea-distance map (what
## draws the sea; the seabed under a shallow bay can stand over the water
## plane): more than a pack px from the shore. Without the map, never.
static func sea_test(p_ctx: Map3DContext) -> Callable:
	var tex: Texture2D = Map3DLayerSea.pack_params(p_ctx).get("sea_distance")
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		return func(_xz: Vector2) -> bool: return false
	if img.is_compressed():
		img.decompress()
	return func(xz: Vector2) -> bool:
		var px := p_ctx.to_pack(xz)
		var x := clampi(int(px.x), 0, img.get_width() - 1)
		var y := clampi(int(px.y), 0, img.get_height() - 1)
		return img.get_pixel(x, y).r * 255.0 > 1.0


## `line_set` (with their bridge `heights`, NAN on the ground) cut where they
## run out over the sea (`at_sea`; visual review 2026-10-06: a road ran
## straight across a bay, draped on the seabed): the runs on land, 2+ points.
static func dry_runs(line_set: Array, heights: Array, at_sea: Callable) -> Dictionary:
	var out_l: Array = []
	var out_h: Array = []
	for i in line_set.size():
		var line: PackedVector2Array = line_set[i]
		var hs: PackedFloat32Array = heights[i] if i < heights.size() else PackedFloat32Array()
		var run := PackedVector2Array()
		var run_h := PackedFloat32Array()
		for j in line.size():
			var on_deck := j < hs.size() and not is_nan(hs[j])
			if on_deck or not bool(at_sea.call(line[j])):
				run.append(line[j])
				if not hs.is_empty():
					run_h.append(hs[j])
				continue
			if run.size() >= 2:
				out_l.append(run)
				out_h.append(run_h)
			run = PackedVector2Array()
			run_h = PackedFloat32Array()
		if run.size() >= 2:
			out_l.append(run)
			out_h.append(run_h)
	return {"lines": out_l, "heights": out_h}


## screens/map3d/balance.csv map3d_bridge_* as Map3DBridges' rules.
func bridge_rules() -> Dictionary:
	return bridge_rules_of(ctx.repo)


static func bridge_rules_of(repo: DataRepository) -> Dictionary:
	var rules: Dictionary = {}
	for key: String in ["abut_m", "clear_m", "clear_per_width", "hump_m", "min_sin", "merge_m",
			"deck_step_m", "deck_m", "parapet_h_m", "parapet_w_m", "arch_max_m", "pier_m",
			"end_over_water_m", "max_drop_m"]:
		rules[key] = repo.bal("map3d_bridge_" + key)
	return rules


## Test seam: every bridge built, [{a, b, ya, yb, crown, water_y, width, deck_w}].
func bridges() -> Array:
	return _bridges


## A packed Poly Haven pair (<base>_alb_ht / <base>_nrm_rgh), or [] when the
## textures folder has not been built (the material's preview pair stays).
static func texture_pair(base: String) -> Array:
	if not ResourceLoader.exists(base + "_alb_ht.png") or not ResourceLoader.exists(base + "_nrm_rgh.png"):
		Map3DWorldLoader.warn_once("textures:" + base,
			"Map3DView: %s_alb_ht/_nrm_rgh.png are not packed — drawn with the 512 px previews (tools/map3d/pack_textures.py)" % base)
		return []
	return [load(base + "_alb_ht.png"), load(base + "_nrm_rgh.png")]


## Lines/Roads' or Lines/Trails' own copy of its look.
static func road_material(p_ctx: Map3DContext, line_name: String) -> ShaderMaterial:
	var key := "road" if line_name == "Roads" else "trail"
	var look := (ROAD_MAT if line_name == "Roads" else TRAIL_MAT) as ShaderMaterial
	var mat := look.duplicate() as ShaderMaterial
	mat.render_priority = Map3DPriority.ROADS
	mat.set_shader_parameter("width_m", p_ctx.repo.bal("map3d_%s_width_m" % key))
	var pair := texture_pair(ROAD_TEXTURE)
	if not pair.is_empty():
		mat.set_shader_parameter("surface", pair[0])
		mat.set_shader_parameter("surface_nrm", pair[1])
	mat.set_meta("base_px", {"width_px": float(look.get_shader_parameter("width_px")),
		"lift_px": float(look.get_shader_parameter("lift_px"))})
	return mat


## Every bridge in `list` as ONE mesh (a surface per deck width), its meta
## "bridges" the list; no surface when there are none.
static func bridge_mesh(p_ctx: Map3DContext, list: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.set_meta("bridges", list)
	var rules := bridge_rules_of(p_ctx.repo)
	var tile := p_ctx.repo.bal("map3d_bridge_tile_m")
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
	return mesh


## The bridges' stone: medieval_blocks_03, lit and casting shadows like the ground.
func bridge_material() -> StandardMaterial3D:
	# Its colour and its fade far away are the .tres's: per pixel (the mesh
	# spans the world, so a visibility range, measured to its centre, would
	# hide every bridge), a min distance past the max inverting the fade.
	var mat := (BRIDGE_MAT as StandardMaterial3D).duplicate() as StandardMaterial3D
	var pair := texture_pair(BRIDGE_TEXTURE)
	if not pair.is_empty():
		mat.albedo_texture = pair[0]
		mat.normal_texture = pair[1]
	return mat


## `mesh` under the world's Bridges in the stone (as its override: a baked
## mesh is shared), replacing any before; cleared when it has no surface.
func _place_bridges(mesh: ArrayMesh) -> void:
	_bridges = mesh.get_meta("bridges", []) if mesh != null else []
	# The authored world's Bridges is filled in place (its mesh null when there
	# are none); a bare host gets a node made for it.
	var mi := host.get_node_or_null("Bridges") as MeshInstance3D if host != null else null
	if mi != null:
		mi.mesh = null
		# The scene's own shared .tres must not stay on this view's node: it is
		# one resource for every view, so nothing may edit it (the stone below
		# is always a duplicate).
		mi.material_override = null
	if mesh == null or mesh.get_surface_count() == 0 or host == null:
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Bridges"
		host.add_child(mi)
	mi.mesh = mesh
	mi.material_override = bridge_material()
