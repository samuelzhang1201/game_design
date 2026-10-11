@tool
class_name Map3DLayerHouses
extends Node3D
## The settlements' house clusters (spec 2026-09-20 §3, node Viewport/Houses):
## one MultiMesh per house type, every instance standing on the terrain under
## it, rebuilt only when the camera has moved map3d_house_rebuild_move_m — cut
## once per camera pose, never per frame.
##
## The bake placed every house (tools/map3d/bake_houses.py); this only
## instances them, from Map3DContext alone — never the Game autoload.
##
## Each type is a SCENE, scenes/models/buildings/<type>.tscn (GameArt's
## HOUSE_MODELS; owner 2026-10-04: 每个房屋的模型为什么不是一个场景), which
## inherits its .glb and gives every surface (a recess, walls, a roof, timber)
## its own house_surface.gdshader material in the editor — texture, roughness,
## role. Opened there it is the house as the map draws it. This layer draws
## the scene's mesh and a copy of those materials as one MultiMesh per type,
## multiplying a wall or a roof by one of this node's `wall_tints` /
## `roof_tints`, picked per house
## (Map3DHouses.variant_of) and handed over as instance custom data (owner
## 2026-09-25: 颜色可以多样化一点，主色调不变，但可以有不同variant).
##
## There is no foundation here: every house mesh carries its own stone
## footing under its walls (owner 2026-09-25: the square box this layer laid
## under a house on a slope was ugly and strange).

## Editor preview: the clusters from the pack and its build alone.
@export var preview := false: set = set_preview

@export_group("Colour variants")
## The WALL tints (owner 2026-09-25, 2026-10-10: more variants), each
## multiplied into a wall's own texture: `house_wall_palettes` palettes of
## `house_wall_palette_size` colours (map3d_bake.csv), a settlement wearing one
## (the bake's `wall` column). Every channel at most 1: never lighter than the
## mesh (limewash read too bright twice).
@export var wall_tints: PackedColorArray = [Color("FFFFFF"), Color("F7E9D2"), Color("E6E3DC"),
	Color("DCD0BE"), Color("F4E0C0"), Color("EDE6E0")]
## The ROOF tints (tile only: slate takes none), palettes as the walls' (`roof`
## column). Never lighter than the mesh: a lighter tile reads PINK (taste.md).
@export var roof_tints: PackedColorArray = [Color("FFFFFF"), Color("FFE6D8"), Color("ECE6DE"),
	Color("FFEFD2"), Color("F4E2D4")]
## The TRIM tints: timber, slate and every untinted surface, hashed per house.
@export var trim_tints: PackedColorArray = [Color("FFFFFF"), Color("EADFD0"), Color("D2BEA4"),
	Color("BCA68C"), Color("F4EADB"), Color("DCCDB8")]
@export_group("")
## The aprons at the houses' feet (World/Aprons), fed every settlement shown; none, no aprons.
@export var aprons: Map3DLayerAprons

## Test seam: the baked houses, in place of the build's own houses.csv.
var houses_override: Dictionary = {}
## Every house surface's material, and the weather's uniforms laid on each
## one made (Map3DLayerWeather sets both: snow on the roofs, rain's dark).
var surface_mats: Array = []
var weather: Dictionary = {}

var ctx: Map3DContext
var _built := false
var _built_at := Vector2.INF
var _instances: Dictionary = {}       # type -> MultiMeshInstance3D, the near settlements' (shadows)
var _far: Dictionary = {}             # type -> MultiMeshInstance3D, the rest (no shadows)
var _aabbs: Dictionary = {}           # type -> its mesh's AABB, for the footprint
## Test seam (fix round 1): the Transform3D actually handed to
## set_instance_transform for each type's MultiMesh in the last refresh(),
## in instance order: under GUT's headless dummy renderer a MultiMesh's
## get_instance_transform() never reflects set_instance_transform() (its
## storage is missing), so a test reads what refresh() handed it here.
var _transforms: Dictionary = {}      # type -> Array[Transform3D], instance order
## Test seam: the (wall, roof) variant given to each instance in the last
## refresh(), in instance order, like _transforms.
var _variants: Dictionary = {}        # type -> Array[Vector2i]
var _wall_tints := PackedVector3Array()
var _roof_tints := PackedVector3Array()
var _trim_tints := PackedVector3Array()


## Fix round 1 (owner review): the layer self-connects to the rig's
## camera_moved, the same idiom Map3DHud.bind() uses — Map3DView stays a
## coordinator and never dispatches this itself. Guarded exactly like
## Map3DHud's: bind() can run again (a preview toggle, preview_build()
## calling bind() too) and must not double-connect.
func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)
	if aprons: aprons.bind(ctx, self)


## Cut once per camera pose, never per frame — the rig's own ground target,
## not the camera's eye, which swings with the pitch (spec §3).
func _on_camera_moved() -> void:
	_lod_shown = Map3DGeometry.lod_shown(_lod_shown, ctx.distance, ctx.repo.bal("map3d_lod_houses_m"), ctx.repo.bal("map3d_lod_margin_m"))
	for mmi: MultiMeshInstance3D in _instances.values() + _far.values():
		mmi.visible = _lod_shown   # owner 2026-10-10 (LOD): past map3d_lod_houses_m no house is drawn
	if not _lod_shown:
		return
	var shadows := ctx.distance <= ctx.repo.bal("map3d_house_shadow_view_m")
	if shadows != _shadows:  # zoomed across the shadows' reach: rebuild at once
		_shadows = shadows
		_built_at = Vector2.INF
	refresh(ctx.target)


## Whether the camera is near enough for houses to cast (map3d_house_shadow_view_m).
var _shadows := true
var _lod_shown := true


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		_instances.clear()
		_far.clear()
		_transforms.clear()
		_built = false
		_built_at = Vector2.INF
		Map3DPreview.clear_generated(self)
		if aprons: aprons.clear()
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
## It also WARMS the house data (Task 6 override 2): ctx.houses() parses the
## real houses.csv in ~91 ms, paid at map load, not on a camera move mid-play.
func build() -> void:
	Map3DPreview.clear_generated(self)
	_instances.clear()
	_aabbs.clear()
	_transforms.clear()
	_variants.clear()
	_chunks.clear()
	_built_at = Vector2.INF
	_built = true
	if aprons: aprons.clear()
	ctx.houses()
	_wall_tints = Map3DHouses.tints_of(wall_tints)
	_roof_tints = Map3DHouses.tints_of(roof_tints)
	_trim_tints = Map3DHouses.tints_of(trim_tints)
	_far.clear()
	for type: String in ctx.repo.map3d_houses:
		var model := _model_of(type)
		if model.is_empty():
			continue
		var mesh: Mesh = model["mesh"]
		var drawn := Map3DHouseMaterials.tinted(mesh, model["materials"], _wall_tints, _roof_tints,
			weather, surface_mats, _trim_tints)
		# Named by the type itself (never capitalize()d: Task 6 override 4).
		# Each type twice: near settlements cast shadows, the rest do not (refresh).
		_instances[type] = Map3DHouseMaterials.multimesh_instance(type, drawn, true)
		_far[type] = Map3DHouseMaterials.multimesh_instance(type + "__far", drawn, false)
		add_child(_instances[type])  # no owner: never saved
		add_child(_far[type])
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
	if not is_same(_pos_of, houses):
		_burg_pos = {}
		for code: String in houses:
			if ctx.repo.burgs.has(code):
				var b: Dictionary = ctx.repo.burgs[code]
				_burg_pos[code] = ctx.to_world(Vector2(float(b["x"]), float(b["y"])))
		_pos_of = houses
		_chunks.clear()
	var shown := Map3DHouses.visible_burgs(houses, _burg_pos, camera_xz,
		ctx.repo.bal("map3d_house_view_m"), _budget())
	# Only the settlements within map3d_house_shadow_m cast their shadows
	# (perf 2026-10-02: every house drawn into every cascade was half the
	# geometry drawn); the rest go to each type's unshadowed MultiMesh.
	var reach := ctx.repo.bal("map3d_house_shadow_m") if ctx.distance <= ctx.repo.bal("map3d_house_shadow_view_m") else -1.0
	var near := shown.filter(func(c: String) -> bool: return (_burg_pos[c] as Vector2).distance_to(camera_xz) <= reach)
	var far := shown.filter(func(c: String) -> bool: return (_burg_pos[c] as Vector2).distance_to(camera_xz) > reach)
	_transforms.clear()
	_variants.clear()
	for type: String in _instances:
		var xforms: Array[Transform3D] = []
		var picks: Array[Vector2i] = []
		_fill(_instances[type], type, near, houses, xforms, picks)
		_fill(_far[type], type, far, houses, xforms, picks)
		_transforms[type] = xforms
		_variants[type] = picks
	if aprons: aprons.show_burgs(shown, houses, _aabbs)
	return true


## One MultiMesh filled with `codes`' houses of `type`, in that order; their
## transforms and variants appended to `xforms` and `picks`. Each settlement's
## houses of a type are packed ONCE (perf 2026-10-02: ~2,500 single-instance
## calls a rebuild, ~3.7 ms a pan step); a rebuild joins the chunks.
func _fill(mmi: MultiMeshInstance3D, type: String, codes: Array, houses: Dictionary,
		xforms: Array[Transform3D], picks: Array[Vector2i]) -> void:
	var buf := PackedFloat32Array()
	var n := 0
	for code: String in codes:
		var chunk := _chunk(code, type, houses[code])
		buf.append_array(chunk["buf"])
		xforms.append_array(chunk["xf"])
		picks.append_array(chunk["picks"])
		n += (chunk["xf"] as Array).size()
	mmi.multimesh.instance_count = n
	if n > 0:
		mmi.multimesh.buffer = buf


## Each settlement's world XZ, kept for the houses dictionary `_pos_of`.
var _burg_pos: Dictionary = {}
var _pos_of: Variant = null


## {burg code + type: Map3DHouses.pack's {buf, xf, picks}} — each settlement's
## houses of a type, kept for the next rebuild: they never change for a houses
## dictionary (refresh() forgets them when it is another, as does build()).
var _chunks: Dictionary = {}


func _chunk(code: String, type: String, all_rows: Array) -> Dictionary:
	var key := code + "|" + type
	if not _chunks.has(key):
		var rows: Array = all_rows.filter(func(h: Dictionary) -> bool: return h["type"] == type)
		_chunks[key] = Map3DHouses.pack(rows, _seat.bind(type), _wall_tints.size(), _roof_tints.size(),
			_trim_tints.size())
	return _chunks[key]


## Where a house stands, (lowest, seat) — sampled ONCE and kept on its row:
## re-sampling a 5x5 grid under every house each rebuild cost ~40 ms a pan
## (2026-09-24). How it stands is its table's `seat` (Map3DHouses.seat_of).
func _seat(h: Dictionary, type: String) -> Vector2:
	if not h.has("_seat"):
		var r := ctx.repo
		h["_seat"] = Map3DHouses.seat_of(h, r.map3d_houses.get(type, {}), _aabbs[type],
			float(ctx.meta.get("sea_y", 0.0)), r.bal("map3d_pier_deck_m"), r.bal("map3d_house_ground_inset"),
			int(r.bal("map3d_house_ground_samples")), r.bal("map3d_house_seat_clear_m"), ctx.height_at)
	return h["_seat"]


## Instances per type, for the tests and the bench.
func counts() -> Dictionary:
	var out: Dictionary = {}
	for type: String in _instances:
		out[type] = (_instances[type] as MultiMeshInstance3D).multimesh.instance_count \
			+ (_far[type] as MultiMeshInstance3D).multimesh.instance_count
	return out


## Test seam: the Transform3D given to instance `i` of `type`'s MultiMesh in
## the last refresh(), in instance order (see _transforms' note on why a test
## reads this instead of the MultiMesh's own get_instance_transform). Exercises
## refresh()'s own height lookup and yaw/scale maths, not a value the test
## supplied itself.
func transforms_of(type: String) -> Array:
	return _transforms.get(type, [])


## Test seam: the (wall, roof) variant each instance of `type` wore in the
## last refresh(), in instance order.
func variants_of(type: String) -> Array:
	return _variants.get(type, [])


func _budget() -> int:
	return int(Map3DQuality.num(ctx.q(), "house_budget"))


## `type`'s scene's {mesh, materials} (Map3DAssetCache.house_model), {} when
## it has none.
func _model_of(type: String) -> Dictionary:
	var path := GameArt.path(GameArt.HOUSE_MODELS, type)
	if not ResourceLoader.exists(path):
		Map3DWorldLoader.warn_once("houses:" + path, "map3d houses: no house scene at " + path)
		return {}
	return Map3DAssetCache.house_model(path)  # loaded once, kept between views

