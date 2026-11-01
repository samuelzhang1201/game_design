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

## Candidate reads begin only after ordinary sight admission; never repair a save here.
static func sample_candidate(ctx: Map3DContext, code: String, committed: Dictionary = {}) -> Dictionary:
	var admitted: Dictionary = {}
	for reg: Dictionary in ctx.regiments():
		if String(reg["regiment_code"]) == code:
			admitted = reg
			break
	if admitted.is_empty() or code.begins_with(Sighting.GHOST_CODE) or String(admitted.get("is_naval", "0")) == "1":
		return _candidate_result("fallback", code)
	var state := ctx.state()
	if state == null: return _candidate_result("fallback", code)
	var hostile := ctx.fogged(code)
	# Owner metadata is inspected without copying any roster's rows or routes.
	var entry: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
	var index := UnitBodies._owners(state)
	if not index.error.is_empty(): return _candidate_result("invalid", code, index.error)
	var owner: Dictionary = index.owners.get(code, {})
	var initialized := state.military_migration.has("body_version") or owner.has("body_version") or entry.has("body_groups")
	if not initialized: return _candidate_result("fallback", code)
	if owner.is_empty() and not state.military_migration.has("body_version"):
		return _candidate_result("invalid", code, "Missing current body schema")
	if not UnitBodies._control_ok(state.military_migration) or not UnitBodies._control_ok(owner) or entry.has("body_reconciliation") \
		or not UnitBodies._counter_ok(entry, true): return _candidate_result("invalid", code, "Invalid body controls")
	var size := int(ctx.repo.bal("battle_group_size"))
	if not owner.is_empty():
		if not owner.has("body_version") or not _integer(owner.get("group_size_version")) or int(owner.group_size_version) != 2:
			return _candidate_result("invalid", code, "Missing current owner schema")
		size = BattleGroups.saved_size(ctx.repo, owner)
	var raw: Variant = entry.get("body_groups") if owner.is_empty() else owner.get("groups", {}).get(code)
	if size <= 0 or not raw is Array: return _candidate_result("invalid", code, "Missing current body array")
	var rows: Array = []
	var slots := {}
	var homes := {}
	var total := 0
	for value: Variant in raw:
		if not value is Dictionary: return _candidate_result("invalid", code, "Invalid body row")
		# Hostiles whitelist pose fields: even malformed hidden paths are never touched.
		var row := {}
		for field: String in ["slot", "home_slot", "count", "role", "x_m", "y_m", "facing_deg"]:
			if value.has(field): row[field] = value[field]
		var error := UnitBodies._row_error(row, size, true)
		if not error.is_empty(): return _candidate_result("invalid", code, error)
		if slots.has(int(row.slot)) or homes.has(int(row.home_slot)) or int(entry.group_next_slot) <= int(row.slot):
			return _candidate_result("invalid", code, "Duplicate or reused identity/home")
		slots[int(row.slot)] = true
		homes[int(row.home_slot)] = true
		for field: String in ["slot", "home_slot", "count", "x_m", "y_m", "facing_deg"]: row[field] = int(row[field])
		total += int(row.count)
		row.path_m = [[row.x_m, row.y_m]]
		row.budget_m = 0
		rows.append(row)
	var fit := ArmySystem.fit_count(ctx.repo, state, code)
	if not UnitBodies._fit_valid(state, code, size * 10): return _candidate_result("invalid", code, "Invalid raw fit")
	if total != fit or rows.size() > 10 or not UnitBodies._canonical(rows, total, size):
		return _candidate_result("invalid", code, "Bodies disagree with active fit partition")
	if hostile: return _candidate_result("bodies", code, "", rows)
	var copied := UnitBodies.rows(ctx.repo, state, code)
	if copied.size() != rows.size(): return _candidate_result("invalid", code, "Invalid owned rows")
	var saved: Variant = state.military_migration.get("body_motion")
	var cursor := {}
	if state.military_migration.has("body_motion"):
		if not BodyMotion._saved_ok(saved): return _candidate_result("invalid", code, "Invalid saved motion control")
		cursor = {"version": 1, "abs_day": int(saved.abs_day), "substep": int(saved.substep), "receipt": saved.receipt}
	if state.day_resolution.has("body_march"):
		var error := DayResolution.body_march_incompatibility_reason(state.day_resolution)
		if not error.is_empty(): return _candidate_result("invalid", code, error)
		var outer: Dictionary = state.day_resolution.body_march
		if int(outer.next_substep) == 0:
			return _candidate_result("bodies", code, "", rows) if committed.is_empty() else _candidate_result("invalid", code, "Uncommitted slice")
		if cursor.is_empty() or cursor.abs_day != int(outer.abs_day) or cursor.substep != int(outer.next_substep) - 1:
			return _candidate_result("invalid", code, "Inconsistent committed boundary")
	for i: int in copied.size():
		var path: Variant = copied[i].get("path_m", [])
		if not path is Array: return _candidate_result("invalid", code, "Invalid saved path")
		if not path.is_empty():
			var error := _candidate_path_error(path, rows[i], BodyMotion.LOCAL_LIMIT)
			if not error.is_empty(): return _candidate_result("invalid", code, error)
			if path.size() > 1 and cursor.is_empty(): return _candidate_result("invalid", code, "Path has no committed receipt")
	# A loaded receipt is not evidence of in-slice timing: retain endpoints only.
	if committed.is_empty():
		var endpoint := _candidate_result("bodies", code, "", rows, cursor)
		for row: Dictionary in copied: endpoint.key.append(row.get("path_m", []).duplicate(true))
		return endpoint
	if not cursor.is_empty() and cursor.abs_day != state.absolute_day(): return _candidate_result("invalid", code, "Stale playback day")
	var budgets := _candidate_budgets(committed, cursor)
	if budgets.has("error"): return _candidate_result("invalid", code, budgets.error)
	var moving := false
	for i: int in rows.size():
		var path: Variant = copied[i].get("path_m")
		var identity := JSON.stringify([code, rows[i].slot])
		if path is Array and path.is_empty() and not budgets.has(identity): continue
		if not path is Array or path.is_empty(): return _candidate_result("invalid", code, "Missing committed path")
		if path.size() > 1 and not budgets.has(identity): return _candidate_result("invalid", code, "Missing committed body budget")
		var budget := int(budgets.get(identity, 0))
		var error := _candidate_path_error(path, rows[i], budget)
		if not error.is_empty(): return _candidate_result("invalid", code, error)
		rows[i].path_m = path.duplicate(true)
		rows[i].budget_m = budget
		moving = moving or BodyMotion._length(path) > 0
	return _candidate_result("bodies", code, "", rows, cursor, moving)

static func _candidate_result(mode: String, unit: String, error := "", rows: Array = [], cursor: Dictionary = {}, moving := false) -> Dictionary:
	return {"mode": mode, "error": error, "unit": unit, "rows": rows, "cursor": cursor,
		"moving": moving, "key": [mode, error, unit, rows.duplicate(true), cursor.duplicate(true)]}

static func _candidate_budgets(committed: Dictionary, cursor: Dictionary) -> Dictionary:
	if not BodyMotion._keys(committed, ["cursor", "moves"]) or not committed.cursor is Dictionary or not committed.moves is Array \
		or cursor.is_empty() or committed.cursor != cursor: return {"error": "Missing/mixed commit timing"}
	if not BodyMotion._keys(committed.cursor, ["version", "abs_day", "substep", "receipt"]): return {"error": "Invalid timing cursor"}
	for field: String in ["version", "abs_day", "substep"]:
		if not BodyMotion._natural(committed.cursor[field]): return {"error": "Invalid timing integer"}
	var budgets := {}
	for move: Variant in committed.moves:
		if not move is Dictionary or not BodyMotion._keys(move, ["unit", "slot", "budget_m"]) or not move.unit is String \
			or not BodyMotion._natural(move.slot) or not BodyMotion._natural(move.budget_m) or int(move.budget_m) > BodyMotion.LOCAL_LIMIT:
			return {"error": "Invalid timing move"}
		var identity := JSON.stringify([move.unit, int(move.slot)])
		if budgets.has(identity): return {"error": "Duplicate timing identity"}
		budgets[identity] = int(move.budget_m)
	return budgets

static func _candidate_path_error(path: Variant, row: Dictionary, budget: int) -> String:
	if not path is Array or path.is_empty(): return "Missing integer path"
	for point: Variant in path:
		if not UnitBodies._pair(point): return "Invalid integer path point"
		if absf(BodyMotion._difference(int(point[0]), int(path[0][0]))) > BodyMotion.LOCAL_LIMIT \
			or absf(BodyMotion._difference(int(point[1]), int(path[0][1]))) > BodyMotion.LOCAL_LIMIT: return "Path outside local range"
	if path.back() != [row.x_m, row.y_m]: return "Path endpoint differs from body"
	var length := BodyMotion._length(path)
	if length > budget or budget < 0: return "Path exceeds committed budget"
	return ""

## Pure slice sampling uses exactly the planner's ceil-leg durations and waiting tail.
static func along_candidate(sampled: Dictionary, share: float) -> Dictionary:
	var unit := String(sampled.get("unit", ""))
	if not is_finite(share): return _candidate_result("invalid", unit, "Nonfinite slice share")
	if sampled.get("mode") != "bodies": return sampled.duplicate(true)
	var out := sampled.duplicate(true)
	var time := clampf(share, 0.0, 1.0)
	for row: Dictionary in out.rows:
		var error := _candidate_path_error(row.get("path_m"), row, int(row.get("budget_m", -1)))
		if not error.is_empty(): return _candidate_result("invalid", unit, error)
		var x := float(row.x_m)
		var y := float(row.y_m)
		for segment: Dictionary in BodyMotion._segments(row.path_m, int(row.budget_m)):
			if time < segment.t0 or time > segment.t1: continue
			var fraction: float = (time - segment.t0) / (segment.t1 - segment.t0)
			x = float(segment.a[0]) + BodyMotion._difference(int(segment.b[0]), int(segment.a[0])) * fraction
			y = float(segment.a[1]) + BodyMotion._difference(int(segment.b[1]), int(segment.a[1])) * fraction
			break
		row.x_m = x
		row.y_m = y
	return out

static func _candidate_key(ctx: Map3DContext, samples: Dictionary, committed: Dictionary) -> Array:
	var key: Array = [ctx.dev]
	samples.clear()
	for reg: Dictionary in ctx.regiments():
		var code := String(reg["regiment_code"])
		var sampled := sample_candidate(ctx, code, committed)
		samples[code] = sampled
		var fallback: Array = [ctx.to_world(ArmySystem.position_of(ctx.repo, ctx.state(), reg)),
			ArmySystem.fit_count(ctx.repo, ctx.state(), code)] if sampled.mode == "fallback" else []
		key.append([sampled.key, reg.get("is_naval", "0"), MapObjects.army_piece(ctx.repo, reg), fallback])
	key.append(ctx.ghosts())
	return key

static func _candidate_at(ctx: Map3DContext, code: String, sampled: Dictionary, history: Dictionary) -> Dictionary:
	var receipt := String(sampled.cursor.get("receipt", ""))
	var share := ctx.day_share() if sampled.moving and not receipt.is_empty() and ctx.day_fn.is_valid() else 1.0
	var old: Dictionary = history.get(code, {})
	if old.get("receipt", "") == receipt:
		share = maxf(share, float(old.get("share", 0.0)))
	elif not old.is_empty() and not receipt.is_empty():
		for row: Dictionary in sampled.rows:
			if old.endpoints.has(row.slot) and row.path_m[0] != old.endpoints[row.slot]:
				return _candidate_result("invalid", code, "Discontinuous committed body path")
	var endpoints := {}
	for row: Dictionary in sampled.rows: endpoints[row.slot] = [row.x_m, row.y_m]
	history[code] = {"receipt": receipt, "share": share, "endpoints": endpoints}
	return along_candidate(sampled, share)


static func _animate_candidate(ctx: Map3DContext, code: String, piece: Dictionary, sample: Dictionary,
		share: float, blend_s: float, battle: Map3DBattleSignals) -> void:
	var state := ctx.state()
	var hostile := ctx.fogged(code)
	var order := "" if hostile else ArmySystem.order_of(ctx.repo, state, code)
	var stance: Dictionary = {} if hostile else ctx.repo.battle_stances.get(BattleSystem.stance_of(state, code), {})
	var slices := int(state.day_resolution.get("substep_count", DayResolution.DEFAULT_SUBSTEP_COUNT))
	var moving := false
	for i: int in piece["groups"].size():
		var child: Dictionary = piece["groups"][i]["piece"]
		var row: Dictionary = sample.rows[i]
		var speed := 0.0
		for segment: Dictionary in BodyMotion._segments(row.path_m, int(row.budget_m)):
			if share < segment.t0 or share >= segment.t1: continue
			var dx := BodyMotion._difference(int(segment.b[0]), int(segment.a[0]))
			var dy := BodyMotion._difference(int(segment.b[1]), int(segment.a[1]))
			speed = sqrt(dx * dx + dy * dy) / (segment.t1 - segment.t0)
			break
		moving = moving or speed > 0.0
		var action := battle.action_for(code, Map3DUnitRig.action_for(speed > 0.0, order, stance))
		var identity := code + ":" + str(row.slot)
		if child.get("action", "") != action:
			child["action"] = action
			Map3DUnitRig.play(child["anims"], action, blend_s, identity)
		var world_speed := speed * float(ctx.meta["m_per_px"]) / float(ArmySystem.metres_per_pack_px(ctx.repo)) \
			* slices * ctx.clock_speed() / ctx.repo.bal("time_day_seconds")
		var stature := float(child.get("statures", [1.0])[0])
		var rate := Map3DUnitRig.gait_rate(world_speed, (child["node"] as Node3D).global_basis.get_scale().x,
			float(child["clip_s"]), float(child["stride_m"]) * stature, 0.0, INF)
		for anim: AnimationPlayer in child["anims"]:
			anim.speed_scale = 0.0 if ctx.clock_speed() == 0 else (rate if speed > 0.0 else 1.0)
	piece["candidate_moving"] = moving and ctx.clock_speed() > 0
	piece["action"] = Map3DUnitRig.action_for(piece["candidate_moving"], order, stance)


static func build(repo: DataRepository, reg: Dictionary, sampled: Dictionary) -> Dictionary:
	var piece := {"node": Node3D.new(), "layout": "physical_groups", "groups": [], "anims": [],
		"figures": 0, "height_m": 0.0, "extent": Vector2.ZERO, "half_w_m": 0.0,
		"model": MapObjects.army_piece(repo, reg), "candidate_bodies": sampled.get("mode", "") == "bodies"}
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
			if not String(piece.get("action", "")).is_empty():
				Map3DUnitRig.play(child["anims"], piece["action"], 0.0, String(reg["regiment_code"]) + ":" + str(row["slot"]))
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
	piece["facing_deg"] = sampled.get("facing_deg", 0)
	piece["sample_key"] = sampled["key"].duplicate(true) if sampled.has("key") else []
	if not piece.has("action"): piece["action"] = ""

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
		var pack_px := Vector2(group["x_m"], group["y_m"]) / float(ArmySystem.metres_per_pack_px(repo)) if piece.get("candidate_bodies", false) \
			else ArmySystem.metres_to_pack(repo, Vector2i(group["x_m"], group["y_m"]))
		var xz := ctx.to_world(pack_px)
		var k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, reference,
			child["reference_height_m"], child["size"])
		var yaw := Map3DUnits.facing_yaw(WarFront.facing_vector(int(group.get("facing_deg", piece["facing_deg"]))), child["stand_deg"])
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

static func _geometry(ctx: Map3DContext, pieces: Dictionary, candidate: bool, committed: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for code: String in pieces:
		var piece: Dictionary = pieces[code]
		if piece.get("layout", "") == "physical_groups" and (piece["node"] as Node3D).visible \
				and (sample_candidate(ctx, code, committed)["mode"] == "bodies" if candidate
				else sample(ctx, code)["mode"] == "groups"):
			out[code] = evidence(piece)
	return out

static func evidence(piece: Dictionary) -> Array:
	var out: Array = []
	for group: Dictionary in piece["groups"]:
		var node: Node3D = group["piece"]["node"]
		var at := node.global_position
		var scale := node.global_basis.get_scale()
		out.append({"slot": group["slot"], "count": group["count"], "role": group["role"],
			"node_id": str(node.get_instance_id()), "phase": (group["piece"]["anims"][0] as AnimationPlayer).current_animation_position if not group["piece"]["anims"].is_empty() and not (group["piece"]["anims"][0] as AnimationPlayer).current_animation.is_empty() else 0.0,
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
