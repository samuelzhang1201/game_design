@tool
class_name Map3DLayerHouses
extends Node3D
## The settlements' house clusters (spec 2026-09-20 §3, node Viewport/Houses):
## one MultiMesh per house type, every instance standing on the terrain under
## it, rebuilt only when the camera has moved map3d_house_rebuild_move_m — cut
## once per camera pose, never per frame.
##
## The bake decided where every house stands (tools/map3d/bake_houses.py);
## this only instances them. Takes everything from Map3DContext — never the
## Game autoload.
##
## Each type's .glb carries its own surfaces (a recess, walls, a roof,
## timber), each with its own texture. A shared material_override would
## flatten them to one colour, so every surface keeps its OWN texture, drawn
## by house_surface.gdshader, which also multiplies a wall or a roof by one
## of data/map3d_house_variants.csv's tints, picked per house
## (Map3DHouses.variant_of) and handed over as instance custom data (owner
## 2026-09-25: 颜色可以多样化一点，主色调不变，但可以有不同variant).
##
## There is no foundation here: every house mesh carries its own stone
## footing under its walls (owner 2026-09-25: the square box this layer laid
## under a house on a slope was ugly and strange).

## Editor preview: the clusters from the pack and its build alone.
@export var preview := false: set = set_preview

## Test seam: the baked houses, in place of the build's own houses.csv.
var houses_override: Dictionary = {}
## Every house surface's material, and the weather's uniforms laid on each
## one made (Map3DLayerWeather sets both: snow on the roofs, rain's dark).
var surface_mats: Array = []
var weather: Dictionary = {}

const HOUSE_SHADER := preload("res://scripts/map3d/house_surface.gdshader")

var ctx: Map3DContext
var _built := false
var _built_at := Vector2.INF
var _instances: Dictionary = {}       # type -> MultiMeshInstance3D
var _aabbs: Dictionary = {}           # type -> its mesh's AABB, for the footprint
## Test seam (fix round 1): the Transform3D actually handed to
## set_instance_transform for each type's MultiMesh in the last refresh(),
## in instance order. Debugging finding (task 6): under the headless dummy
## renderer GUT runs the suite with, MultiMeshInstance3D's
## get_instance_transform() never reflects anything written by
## set_instance_transform() — proven even for a hand-built raw `buffer`
## assignment, so it is the renderer's storage that is missing, not a bug
## here. A test that needs to check what an instance was given must read
## _transforms — what refresh() itself computed and handed to the
## MultiMesh — rather than asking the MultiMesh what it was set to.
var _transforms: Dictionary = {}      # type -> Array[Transform3D], instance order
## Test seam: the (wall, roof) variant given to each instance in the last
## refresh(), in instance order, like _transforms.
var _variants: Dictionary = {}        # type -> Array[Vector2i]
var _wall_tints := PackedVector3Array()
var _roof_tints := PackedVector3Array()


## Fix round 1 (owner review): the layer self-connects to the rig's
## camera_moved, the same idiom Map3DHud.bind() uses — Map3DView stays a
## coordinator and never dispatches this itself. Guarded exactly like
## Map3DHud's: bind() can run again (a preview toggle, preview_build()
## calling bind() too) and must not double-connect.
func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)


## Cut once per camera pose, never per frame — the rig's own ground target,
## not the camera's eye, which swings with the pitch (spec §3).
func _on_camera_moved() -> void:
	refresh(ctx.target)


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		_instances.clear()
		_transforms.clear()
		_built = false
		_built_at = Vector2.INF
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


## The clusters as the game builds them, from `p_ctx` alone; a pack with no
## 3D build gets nothing (there is no house look asset worth a placeholder
## for).
func preview_build(p_ctx: Map3DContext) -> void:
	bind(p_ctx)
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		return
	build()


## Build the empty per-type MultiMeshes; refresh() fills them.
##
## Task 6 override 2: this also WARMS the house data — ctx.houses() parses
## the real houses.csv (18,414 rows) in ~91 ms, measured. build() runs at map
## load, where the player is already waiting on the terrain and the bakes;
## paying the parse here keeps it off the first camera move mid-play, which
## would otherwise read as a stutter.
func build() -> void:
	Map3DPreview.clear_generated(self)
	_instances.clear()
	_aabbs.clear()
	_transforms.clear()
	_variants.clear()
	_built_at = Vector2.INF
	_built = true
	ctx.houses()
	_wall_tints = Map3DHouses.tints_of(ctx.repo.map3d_house_variants, "wall")
	_roof_tints = Map3DHouses.tints_of(ctx.repo.map3d_house_variants, "roof")
	for type: String in ctx.repo.map3d_houses:
		var mesh := _mesh_of(type)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _tinted(mesh)
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		# Task 6 override 4: the type itself, not type.capitalize() — capitalize()
		# turns an underscore into a space ("cottage_a" -> "Cottage A"), which is
		# neither a legible node name nor round-trippable back to the CSV's type.
		mmi.name = type
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)  # no owner: never saved
		_instances[type] = mmi
		_aabbs[type] = mesh.get_aabb()


## Rebuild the instances for this camera position; true when it did. A move
## under map3d_house_rebuild_move_m is ignored.
func refresh(camera_xz: Vector2) -> bool:
	if ctx == null:
		return false
	if not _built:
		build()  # a caller that never called build() itself still gets one, ONCE
	var step := ctx.repo.bal("map3d_house_rebuild_move_m")
	if _built_at.is_finite() and _built_at.distance_to(camera_xz) < step:
		return false
	_built_at = camera_xz
	var houses := houses_override if not houses_override.is_empty() else ctx.houses()
	var pos: Dictionary = {}
	for code: String in houses:
		if ctx.repo.burgs.has(code):
			var b: Dictionary = ctx.repo.burgs[code]
			pos[code] = ctx.to_world(Vector2(float(b["x"]), float(b["y"])))
	var buckets := Map3DHouses.visible_set(houses, ctx.repo, pos,
		camera_xz, ctx.repo.bal("map3d_house_view_m"), _budget())
	var clear := ctx.repo.bal("map3d_house_seat_clear_m")
	var ground_inset := ctx.repo.bal("map3d_house_ground_inset")
	var samples := int(ctx.repo.bal("map3d_house_ground_samples"))
	_transforms.clear()
	_variants.clear()
	for type: String in _instances:
		var mmi: MultiMeshInstance3D = _instances[type]
		var rows: Array = buckets.get(type, [])
		mmi.multimesh.instance_count = rows.size()
		var xforms: Array[Transform3D] = []
		var picks: Array[Vector2i] = []
		var box: AABB = _aabbs[type]
		for i in rows.size():
			var h: Dictionary = rows[i]
			# The seat is sampled ONCE per house and kept on its row: the ground
			# never moves, and re-sampling a 5x5 grid under every visible house on
			# each rebuild cost ~40 ms a pan step at the high tier's 5000 houses
			# (measured 2026-09-24). A new world loads new rows.
			var ground: Vector2
			if h.has("_seat"):
				ground = h["_seat"]
			else:
				ground = Map3DHouses.seat(
					Map3DHouses.ground_under(h, box, ground_inset, samples, ctx.height_at), clear)
				h["_seat"] = ground
			var t := transform_of(h, ground.y)
			mmi.multimesh.set_instance_transform(i, t)
			xforms.append(t)
			var pick := Vector2i(Map3DHouses.variant_of(h, _wall_tints.size(), 0),
				Map3DHouses.variant_of(h, _roof_tints.size(), 1))
			mmi.multimesh.set_instance_custom_data(i, Color(pick.x, pick.y, 0.0, 0.0))
			picks.append(pick)
		_transforms[type] = xforms
		_variants[type] = picks
	return true


## Instances per type, for the tests and the bench.
func counts() -> Dictionary:
	var out: Dictionary = {}
	for type: String in _instances:
		out[type] = (_instances[type] as MultiMeshInstance3D).multimesh.instance_count
	return out


## Test seam: the Transform3D given to instance `i` of `type`'s MultiMesh in
## the last refresh(), in instance order (see _transforms' note on why a test
## reads this instead of the MultiMesh's own get_instance_transform). Exercises
## refresh()'s own height lookup and yaw/scale maths, not a value the test
## supplied itself.
func transforms_of(type: String) -> Array:
	return _transforms.get(type, [])


## The world transform for one baked house row: yaw about the vertical,
## scaled HORIZONTALLY by `scale` and VERTICALLY by `scale * height_scale`
## (the bake's own per-house bias, tallest at a settlement's core, jittered
## per house — 高低层次不齐), standing upright at `height` (Map3DHouses.seat:
## the highest ground under its footprint, so nothing of it is buried). Pure,
## so a test can check the maths directly rather than reading it back off a
## MultiMesh.
static func transform_of(h: Dictionary, height: float) -> Transform3D:
	var at: Vector2 = h["at"]
	var s: float = float(h["scale"])
	var height_scale: float = float(h["height_scale"])
	var turn := Basis(Vector3.UP, deg_to_rad(float(h["yaw_deg"])))
	turn = turn.scaled(Vector3(s, s * height_scale, s))
	return Transform3D(turn, Vector3(at.x, height, at.y))


## Test seam: the (wall, roof) variant each instance of `type` wore in the
## last refresh(), in instance order.
func variants_of(type: String) -> Array:
	return _variants.get(type, [])


## A copy of `mesh` whose every surface is drawn by house_surface.gdshader
## with that surface's own imported texture, roughness, vertex-colour use and
## normal map when it has one (the palaces):
## a wall surface (material hh_wall_*) takes the wall tints, a tile roof
## (hh_roof_*, not slate) the roof tints, anything else none.
func _tinted(mesh: Mesh) -> Mesh:
	var out := mesh.duplicate() as Mesh
	if not (out is ArrayMesh):
		return mesh
	for i in out.get_surface_count():
		var src := out.surface_get_material(i) as StandardMaterial3D
		if src == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = HOUSE_SHADER
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("albedo_color", src.albedo_color)
		mat.set_shader_parameter("roughness", src.roughness)
		mat.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
		# a surface that brought a normal map (the palaces) draws it; the rest have none
		mat.set_shader_parameter("use_normal", src.normal_enabled and src.normal_texture != null)
		if src.normal_texture != null:
			mat.set_shader_parameter("normal_tex", src.normal_texture)
			mat.set_shader_parameter("normal_depth", src.normal_scale)
		var mat_name := src.resource_name
		var role := 0
		if mat_name.begins_with("hh_wall_"):
			role = 1
		elif mat_name.begins_with("hh_roof_") and mat_name != "hh_roof_slate":
			role = 2
		mat.set_shader_parameter("role", role)
		mat.set_shader_parameter("wall_tints", _wall_tints)
		mat.set_shader_parameter("roof_tints", _roof_tints)
		mat.set_shader_parameter("wall_count", _wall_tints.size())
		mat.set_shader_parameter("roof_count", _roof_tints.size())
		surface_mats.append(mat)
		for key: String in weather: mat.set_shader_parameter(key, weather[key])
		(out as ArrayMesh).surface_set_material(i, mat)
	return out


func _budget() -> int:
	return int(Map3DQuality.num(ctx.q(), "house_budget"))


func _mesh_of(type: String) -> Mesh:
	var path := String(ctx.repo.map3d_houses[type]["mesh"])
	if not ResourceLoader.exists(path):
		Map3DWorldLoader.warn_once("houses:" + path, "map3d houses: no mesh at " + path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	var mesh := _first_mesh(node)
	node.free()
	return mesh


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null
