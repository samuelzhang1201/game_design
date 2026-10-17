class_name Map3DUnitCamps
extends RefCounted
## Snapshot-only camp presentation. Facilities stay at the saved site, stand
## plumb on their own ground and dismantle through the saved packing day.

const FACILITIES := ["CommandTent", "TentA", "TentB", "SupplyCart", "Stores", "Watch"]
var camps: Dictionary = {}  ## code -> unowned runtime camp root
var _snapshot: Dictionary = {}
var _geometry_ctx: Map3DContext
var _obstacles: Array = []  ## {box: Rect2, polygon: PackedVector2Array}
var _at_sea: Callable
var _woods: Image


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)


static func asset_key(camp: Dictionary) -> String:
	var phase := String(camp.get("phase", "none"))
	return phase if phase in ["building", "camped", "packing"] else ""


## Share of facilities still standing; packing never consults battle state.
static func progress(camp: Dictionary, day: int, share: float, build_days: int) -> float:
	var built := clampf(float(camp.get("build_progress", 0)) / 1000.0, 0.0, 1.0)
	match asset_key(camp):
		"camped":
			return 1.0
		"building":
			return minf(1.0, built + (0.0 if bool(camp.get("under_attack", false)) else share / maxi(build_days, 1)))
		"packing":
			var start := int(camp.get("pack_start_day", day))
			var end := int(camp.get("move_not_before_day", start + 1))
			return built * (1.0 - clampf((float(day - start) + share) / maxi(end - start, 1), 0.0, 1.0))
	return 0.0


static func facility_share(standing: float, index: int, count: int) -> float:
	return clampf(standing * count - index, 0.0, 1.0)


## A finite neighbouring grid, returning no site when every candidate is wet
## or occupied. Never fall back to the blocked authored location.
static func clear_site(at: Vector2, step: float, allowed: Callable) -> Variant:
	if bool(allowed.call(at)):
		return at
	for z: int in range(-1, 2):
		for x: int in range(-1, 2):
			if x == 0 and z == 0:
				continue
			var candidate := at + Vector2(x, z) * step
			if bool(allowed.call(candidate)):
				return candidate
	return null


static func behind(xz: Vector2, yaw: float, d: float) -> Vector2:
	return xz + Vector2(sin(yaw), cos(yaw)) * d


func sync(layer: Node3D, ctx: Map3DContext, code: String, _piece: Dictionary, _xz: Vector2,
		_yaw: float, k: float, back_m: float) -> void:
	var state: Dictionary = (_snapshot.get("camps", {}) as Dictionary).get(code, {})
	var key := asset_key(state) if not code.begins_with(Sighting.GHOST_CODE) else ""
	if key == "" or not state.has("site"):
		_drop(code)
		return
	if not camps.has(code):
		var path := GameArt.path(GameArt.CAMP_MODELS, key)
		var scene := Map3DAssetCache.scene(path) if path != "" else null
		if path != "" and scene == null:
			Map3DWorldLoader.warn_once("units:" + path, "map3d units: no model at " + path)
		var camp := scene.instantiate() as Node3D if scene != null else null
		if camp == null:
			return
		camp.name = "Camp_" + code.replace(":", "_")
		layer.add_child(camp)  # no owner: never saved into the authored scene
		camps[code] = camp
	var node: Node3D = camps[code]
	var site: Dictionary = state["site"]
	var at := ctx.to_world(ArmySystem.metres_to_pack(ctx.repo,
		Vector2i(int(site["x_m"]), int(site["y_m"]))))
	# A turn by the regiment must not move an already pitched camp either.
	var layout_key := [at, k]
	if node.get_meta("layout_key", []) != layout_key:
		var anchor := behind(at, 0.0, back_m * k)
		node.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), Vector3(anchor.x, 0.0, anchor.y))
		_layout(ctx, node)
		node.set_meta("layout_key", layout_key)
	var share := 1.0 if bool(_snapshot.get("day_committed", false)) else ctx.day_share()
	var standing := progress(state, int(_snapshot.get("absolute_day", 0)), share,
		int(ctx.repo.bal("army_camp_build_days")))
	var facilities: Array = node.get_meta("facilities", [])
	for i: int in facilities.size():
		var f: Dictionary = facilities[i]
		var facility: Node3D = f["node"]
		var part := facility_share(standing, i, facilities.size())
		facility.visible = bool(f["placed"]) and part > 0.0
		var size: Vector3 = f["scale"]
		facility.scale = Vector3(size.x, size.y * maxf(part, 0.0001), size.z) \
			if String(facility.name) in ["CommandTent", "TentA", "TentB"] else size


func _drop(code: String) -> void:
	if camps.has(code):
		(camps[code] as Node3D).queue_free()
		camps.erase(code)


func prune(pieces: Dictionary) -> void:
	for code: String in camps.keys():
		if not pieces.has(code):
			_drop(code)


## Full authored bounds in this node's frame, including nested GLB meshes.
static func _box(node: Node3D) -> AABB:
	var out := AABB()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out = (node as MeshInstance3D).mesh.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var b := (child as Node3D).transform * _box(child)
			if b.size != Vector3.ZERO:
				out = b if out.size == Vector3.ZERO else out.merge(b)
	return out


func _layout(ctx: Map3DContext, root: Node3D) -> void:
	_geometry(ctx)
	var placed: Array = []
	var facilities: Array = []
	for name: String in FACILITIES:
		var node := root.get_node_or_null(NodePath(name)) as Node3D
		if node == null:
			continue
		var authored: Transform3D = node.get_meta("authored_transform", node.transform)
		node.set_meta("authored_transform", authored)
		node.transform = authored
		var box := _box(node)
		var scale := node.global_basis.get_scale().x
		var yaw := node.global_rotation.y
		var original := node.scale
		var at := Vector2(node.global_position.x, node.global_position.z)
		var h := {"at": at, "scale": scale, "yaw_deg": rad_to_deg(yaw)}
		var step := maxf(box.size.x, box.size.z) * scale
		var found: Variant = clear_site(at, step, func(p: Vector2) -> bool:
			h["at"] = p
			return _clear(ctx, h, box, placed))
		if found != null:
			h["at"] = found
			var ground := Map3DHouses.ground_under(h, box, ctx.repo.bal("map3d_house_ground_inset"),
				int(ctx.repo.bal("map3d_house_ground_samples")), ctx.height_at)
			node.global_position = Vector3(found.x,
				ground.y + ctx.repo.bal("map3d_house_seat_clear_m") - box.position.y * scale, found.y)
			placed.append(_footprint(h, box))
		facilities.append({"node": node, "scale": original, "placed": found != null})
	root.set_meta("facilities", facilities)


static func _footprint(h: Dictionary, box: AABB) -> Dictionary:
	var polygon := Map3DHouseApron.corners(h, box, 0.0)
	return {"polygon": polygon, "box": MapGeometry.bounds(polygon)}


func _clear(ctx: Map3DContext, h: Dictionary, box: AABB, placed: Array) -> bool:
	var ground := Map3DHouses.ground_under(h, box, ctx.repo.bal("map3d_house_ground_inset"),
		int(ctx.repo.bal("map3d_house_ground_samples")), ctx.height_at)
	if ground.y - ground.x > float(ctx.repo.map3d_bake["house_max_drop_m"]):
		return false
	var samples := Map3DHouses.footprint_grid(h, box, 1.0, int(ctx.repo.bal("map3d_house_ground_samples")))
	for p: Vector2 in samples:
		if not MapEconomy.contains_land(ctx.repo, ctx.to_pack(p)) or bool(_at_sea.call(p)):
			return false
		if _woods != null and not _woods.is_empty():
			var origin: Array = ctx.meta["pack_origin"]
			var pixel := Vector2i(((p - Vector2(float(origin[0]), float(origin[1])))
				/ Map3DLayerThemes.FIELD_MAP_M_PER_TEXEL).floor())
			if pixel.x >= 0 and pixel.y >= 0 and pixel.x < _woods.get_width() and pixel.y < _woods.get_height() \
					and _woods.get_pixelv(pixel).r > 0.0:
				return false
	var footprint := _footprint(h, box)
	for obstacle: Dictionary in _obstacles + placed:
		if (footprint["box"] as Rect2).intersects(obstacle["box"]) \
				and not Geometry2D.intersect_polygons(footprint["polygon"], obstacle["polygon"]).is_empty():
			return false
	return true


func _geometry(ctx: Map3DContext) -> void:
	if _geometry_ctx == ctx:
		return
	_geometry_ctx = ctx
	_obstacles.clear()
	_at_sea = Map3DLayerRoads.sea_test(ctx)
	var woods_path := ctx.repo.map3d_dir().path_join("bake/woods.png")
	_woods = Image.load_from_file(woods_path) if FileAccess.file_exists(woods_path) else null
	for list: Array in ctx.houses().values():
		for h: Dictionary in list:
			var row: Dictionary = ctx.repo.map3d_houses.get(String(h["type"]), {})
			var w := float(row.get("width_m", row.get("footprint_m", 0.0)))
			var d := float(row.get("depth_m", row.get("footprint_m", 0.0)))
			_obstacles.append(_footprint(h, AABB(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w, 1, d))))
	for group: String in ["roads", "trails"]:
		var half := ctx.repo.bal("map3d_road_width_m" if group == "roads" else "map3d_trail_width_m") * 0.5
		for line: PackedVector2Array in Map3DBorders.route_lines(ctx.repo, ctx.meta, group, ctx.road_step()):
			for i: int in range(1, line.size()):
				_obstacle_segment(line[i - 1], line[i], half)
	var path := ctx.repo.map3d_dir().path_join("rivers.json")
	if FileAccess.file_exists(path):
		for river: Dictionary in Map3DRivers.parse(FileAccess.get_file_as_string(path), ctx.repo.bal("map3d_river_split_rise_m")):
			var points: PackedVector3Array = river["pos"]
			var widths: PackedFloat32Array = river["width"]
			for i: int in range(1, points.size()):
				_obstacle_segment(Vector2(points[i - 1].x, points[i - 1].z), Vector2(points[i].x, points[i].z),
					maxf(widths[i - 1], widths[i]) * 0.5)


func _obstacle_segment(a: Vector2, b: Vector2, half: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * half
	var polygon := PackedVector2Array([a - n - d * half, b - n + d * half, b + n + d * half, a + n - d * half])
	_obstacles.append({"polygon": polygon, "box": MapGeometry.bounds(polygon)})
