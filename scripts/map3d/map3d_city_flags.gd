@tool
class_name Map3DCityFlags
extends Node3D
## Physical roof standards share the settlements' admission and visibility.
@export var flag_scene: PackedScene
@export var realm_flags: ArtTable
@export var flag_scale := 6.0
var ctx: Map3DContext
var _houses: Node3D
var _flags: Dictionary = {}
var _shown: Array = []
var _rows: Dictionary = {}
var _tops: Dictionary = {}
var _ownership := 0

func bind(context: Map3DContext, houses: Node3D) -> void:
	ctx = context
	_houses = houses

func clear() -> void:
	for flag: Node in _flags.values(): flag.queue_free()
	_flags.clear()
	_shown.clear()
	_rows.clear()

func sync(codes: Array, rows: Dictionary) -> void:
	if ctx == null or flag_scene == null: return
	_shown = codes.duplicate()
	_rows = rows
	for code: String in _flags: (_flags[code] as Node3D).hide()
	for code: String in codes:
		var burg: Dictionary = ctx.repo.burgs.get(code, {})
		var texture := Map3DNationalFlag.texture_for(ctx.repo, realm_flags,
			Map3DNationalFlag.city_realm(ctx.repo, ctx.state(), burg))
		if texture == null: continue
		if not _flags.has(code):
			var flag := flag_scene.instantiate() as Map3DNationalFlag
			flag.name = "Flag_" + code
			add_child(flag)
			_flags[code] = flag
			var h: Dictionary = rows[code][0]
			for candidate: Dictionary in rows[code]:
				if ctx.repo.map3d_houses.get(candidate["type"], {}).get("role", "") == "landmark":
					h = candidate
					break
			var type := String(h["type"])
			var model := Map3DAssetCache.house_model(GameArt.path(GameArt.HOUSE_MODELS, type))
			if model.is_empty():
				flag.queue_free(); _flags.erase(code)
				continue
			if not _tops.has(type): _tops[type] = roof_top(model["mesh"])
			var seat: Vector2 = _houses._seat(h, type)
			var roof := Map3DHouses.transform_of(h, seat.y) * Vector3(_tops[type])
			flag.position = roof - Vector3.UP * flag_scale * 0.06
			flag.scale = Vector3.ONE * flag_scale
		var flag: Map3DNationalFlag = _flags[code]
		flag.set_texture(texture)
		flag.visible = true  # the parent gates distance; a far ownership refresh must not hide children
	var state := ctx.state()
	_ownership = state.province_owner.hash() if state != null else 0

func _process(_delta: float) -> void:
	if ctx == null: return
	var state := ctx.state()
	var changed := state.province_owner.hash() if state != null else 0
	if changed != _ownership: sync(_shown, _rows)
	visible = _houses.visible and ctx.distance <= ctx.repo.bal("map3d_lod_houses_m")

static func roof_top(mesh: Mesh) -> Vector3:
	var top := Vector3(0.0, -INF, 0.0)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for point: Vector3 in vertices:
			if point.y > top.y: top = point
	return top if top.is_finite() else Vector3.ZERO
