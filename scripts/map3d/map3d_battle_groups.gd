class_name Map3DBattleGroups
extends RefCounted
## Read-only physical groups, admitted through the ordinary player-map sight.

static func _result(mode: String, rows: Array = [], facing := 0, error := "") -> Dictionary:
	return {"mode": mode, "rows": rows, "facing_deg": facing,
		"key": [mode, rows.duplicate(true), facing, error], "error": error}

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value))

static func sample(ctx: Map3DContext, code: String) -> Dictionary:
	var admitted := false
	for reg: Dictionary in ctx.regiments():
		if String(reg["regiment_code"]) == code:
			admitted = true
			break
	if not admitted or ctx.state() == null or code.begins_with(Sighting.GHOST_CODE):
		return _result("fallback")
	var battle := BattleSystem.battle_of(ctx.state(), code)
	if battle.is_empty() or not battle.has("groups"):
		return _result("fallback")
	if not battle["groups"] is Dictionary:
		return _result("invalid", [], 0, "groups must be a dictionary")
	if not battle["groups"].has(code):
		return _result("fallback")
	var raw: Variant = battle["groups"][code]
	var facings: Variant = battle.get("group_facing", {})
	if not raw is Array or not facings is Dictionary or not _integer(facings.get(code)):
		return _result("invalid", [], 0, "missing rows or whole-degree facing")
	var facing := int(facings[code])
	if facing < 0 or facing >= 360:
		return _result("invalid", [], 0, "facing outside 0..359")
	var rows: Array = []
	var slots: Dictionary = {}
	var total := 0
	var size := BattleGroups.saved_size(ctx.repo, battle)
	if size <= 0:
		return _result("invalid", [], 0, "invalid group size/version")
	var version := int(battle.get("group_size_version", 1))
	for i in raw.size():
		var row: Variant = raw[i]
		if not row is Dictionary:
			return _result("invalid", [], 0, "group must be a dictionary")
		for field: String in ["count", "x_m", "y_m"]:
			if not _integer(row.get(field)):
				return _result("invalid", [], 0, "missing/nonintegral " + field)
		if not row.get("role") is String or row["role"] not in ["front", "reserve"] \
				or int(row["count"]) <= 0 or int(row["count"]) > size:
			return _result("invalid", [], 0, "invalid group count/role")
		if row.has("slot") and (not _integer(row["slot"]) or int(row["slot"]) < 0):
			return _result("invalid", [], 0, "invalid slot")
		var slot := int(row.get("slot", i))
		if slots.has(slot):
			return _result("invalid", [], 0, "duplicate slot")
		slots[slot] = true
		total += int(row["count"])
		rows.append({"slot": slot, "count": int(row["count"]), "role": String(row["role"]),
			"x_m": int(row["x_m"]), "y_m": int(row["y_m"])})
	var fit := ArmySystem.fit_count(ctx.repo, ctx.state(), code)
	if total != fit or (version >= 2 and rows.size() != ceili(float(fit) / size)):
		return _result("invalid", [], 0, "groups do not match fit personnel")
	var result := _result("groups", rows, facing)
	result["key"].append_array([version, size])
	return result

static func build(repo: DataRepository, reg: Dictionary, sampled: Dictionary) -> Dictionary:
	var piece := {"node": Node3D.new(), "layout": "physical_groups", "groups": [], "anims": [],
		"figures": 0, "height_m": 0.0, "extent": Vector2.ZERO, "half_w_m": 0.0,
		"model": MapObjects.army_piece(repo, reg)}
	(piece["node"] as Node3D).top_level = true
	sync(repo, reg, piece, sampled)
	return piece

## Optional saved slots retain their model and animation player across removal/refresh.
static func sync(repo: DataRepository, reg: Dictionary, piece: Dictionary, sampled: Dictionary) -> void:
	var previous: Dictionary = {}
	for group: Dictionary in piece["groups"]:
		previous[group["slot"]] = group["piece"]
	var groups: Array = []
	var anims: Array = []
	for row: Dictionary in sampled["rows"]:
		var child: Dictionary = previous.get(row["slot"], {})
		if child.is_empty():
			child = Map3DFormation.of_regiment(repo, reg, {"figures": 1, "slots": [Vector2.ZERO]}, 1.0)
			if child.is_empty():
				continue
			child["reference_height_m"] = child["height_m"]
			var bounds := model_bounds(child["node"])
			child["bounds_model"] = bounds
			child["height_m"] = bounds.size.y
			child["extent"] = Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)),
				maxf(absf(bounds.position.z), absf(bounds.end.z)))
			child["half_w_m"] = maxf(child["extent"].x, child["extent"].y)
			(child["node"] as Node3D).name = "Group%d" % int(row["slot"])
			(piece["node"] as Node3D).add_child(child["node"])
			(child["node"] as Node3D).top_level = true
		previous.erase(row["slot"])
		var group := row.duplicate(true)
		group["piece"] = child
		groups.append(group)
		anims.append_array(child["anims"])
	for child: Dictionary in previous.values():
		(child["node"] as Node3D).queue_free()
	if not piece.has("reference_height_m"):
		var reference: Dictionary = groups[0]["piece"] if not groups.is_empty() else Map3DFormation.of_regiment(
			repo, reg, {"figures": 1, "slots": [Vector2.ZERO]}, 1.0)
		piece["reference_height_m"] = reference.get("reference_height_m", reference.get("height_m", 0.0))
		piece["reference_size"] = reference.get("size", 1.0)
		piece["chains"] = reference.get("chains", {}).duplicate(true)
		if groups.is_empty() and reference.has("node"):
			(reference["node"] as Node3D).free()
	piece["groups"] = groups
	piece["anims"] = anims
	piece["figures"] = groups.size()
	piece["facing_deg"] = sampled["facing_deg"]
	piece["sample_key"] = sampled["key"].duplicate(true) if sampled.has("key") else []
	piece["action"] = ""

static func place(ctx: Map3DContext, piece: Dictionary, anchor: Vector2, _gap: float, selected: bool) -> Rect2:
	var root: Node3D = piece["node"]
	root.global_transform = Transform3D(Basis.IDENTITY, Vector3(anchor.x, ctx.height_at(anchor), anchor.y))
	var repo := ctx.repo
	var reference := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	piece["camp_scale"] = Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference,
		piece["reference_height_m"], piece["reference_size"])
	var box := Rect2()
	var has_box := false
	var extent := Vector2.ZERO
	var height := 0.0
	for group: Dictionary in piece["groups"]:
		var child: Dictionary = group["piece"]
		var node: Node3D = child["node"]
		var xz := ctx.to_world(ArmySystem.metres_to_pack(repo, Vector2i(group["x_m"], group["y_m"])))
		var k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference,
			child["reference_height_m"], child["size"])
		var yaw := Map3DUnits.facing_yaw(WarFront.facing_vector(piece["facing_deg"]), child["stand_deg"])
		var y := ctx.height_at(xz)
		for offset: Vector2 in Map3DUnits.footprint(child["extent"], yaw, k, int(repo.bal("map3d_unit_seat_ring"))):
			y = maxf(y, ctx.height_at(xz + offset))
		y += float(child["height_m"]) * k * repo.bal("map3d_unit_seat_clear") - repo.bal("map3d_unit_sink_m")
		node.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k), Vector3(xz.x, y, xz.y))
		child["ground"] = node.position
		child["lift"] = y - ctx.height_at(xz)
		Map3DUnitGlow.place(repo, ctx.height_at, child, selected, k)
		var bounds := Rect2(xz, Vector2.ZERO)
		var model_box: AABB = child["bounds_model"]
		for i in 8:
			var point := node.global_transform * model_box.get_endpoint(i)
			bounds = bounds.expand(Vector2(point.x, point.z))
		group["bounds_world"] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
		extent.x = maxf(extent.x, maxf(absf(bounds.position.x - anchor.x), absf(bounds.end.x - anchor.x)))
		extent.y = maxf(extent.y, maxf(absf(bounds.position.y - anchor.y), absf(bounds.end.y - anchor.y)))
		height = maxf(height, float(child["height_m"]) * k)
		if ctx.camera != null and not ctx.camera.is_position_behind(node.global_position):
			var child_box := Map3DUnits.screen_box(ctx.camera, node.global_position,
				float(child["height_m"]) * k, float(child["half_w_m"]) * k, ctx.viewport_px_scale())
			for i in 8:
				var point := node.global_transform * model_box.get_endpoint(i)
				if not ctx.camera.is_position_behind(point):
					child_box = child_box.expand(ctx.camera.unproject_position(point) / ctx.viewport_px_scale())
			group["screen_bounds"] = [child_box.position.x, child_box.position.y, child_box.size.x, child_box.size.y]
			box = box.merge(child_box) if has_box else child_box
			has_box = true
	piece["height_m"] = height
	piece["extent"] = extent
	piece["half_w_m"] = maxf(extent.x, extent.y)
	piece["ground"] = root.position
	Map3DUnits.show_piece(piece, not (piece["groups"] as Array).is_empty())
	return box

static func evidence(piece: Dictionary) -> Array:
	var out: Array = []
	for group: Dictionary in piece["groups"]:
		var node: Node3D = group["piece"]["node"]
		var at := node.global_position
		var scale := node.global_basis.get_scale()
		out.append({"slot": group["slot"], "count": group["count"], "role": group["role"],
			"x_m": group["x_m"], "y_m": group["y_m"], "xz_world": [at.x, at.z],
			"y_world": at.y, "yaw_rad": node.global_rotation.y,
			"scale": [scale.x, scale.y, scale.z], "bounds_world": group.get("bounds_world", []), "screen_bounds": group.get("screen_bounds", [])})
	return out


## Include every ancestor, especially the existing per-figure stature scale.
static func model_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh: MeshInstance3D in Map3DUnits.meshes(root):
		if mesh.mesh == null:
			continue
		var transform := Map3DUnitRig._local_to(root, mesh)
		var box := mesh.mesh.get_aabb()
		for i in 8:
			var point := transform * box.get_endpoint(i)
			bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
			found = true
	if not found:
		var extent := Map3DUnits.stand_extent(root)
		bounds = AABB(Vector3(-extent.x, 0, -extent.y), Vector3(extent.x * 2, Map3DUnits.model_size(root).y, extent.y * 2))
	return bounds
