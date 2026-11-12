class_name BattleGroups
extends RefCounted
## P4.4d1: a battle unit's fit personnel as representative groups of at most
## `battle_group_size`, each with a saved whole-metre position laid out by the
## unit's formation around its anchor (spec §6-§8).


## Group sizes for `n` people: full groups, the last one the remainder.
static func counts(n: int, size: int) -> Array[int]:
	var out: Array[int] = []
	var left := maxi(0, n)
	while left > 0:
		out.append(mini(size, left))
		left -= size
	return out


## A saved version fixes its people-per-group contract; metadata cannot override it.
static func saved_size(repo: DataRepository, battle: Dictionary) -> int:
	var version: Variant = battle.get("group_size_version", 1)
	if not _whole(version) or int(version) not in [1, 2]: return -1
	var expected := 50 if int(version) == 1 else int(repo.bal("battle_group_size"))
	var size: Variant = battle.get("group_size_men", expected)
	if expected <= 0 or not _whole(size) or int(size) != expected: return -1
	return expected


## Whole-metre positions of `count` groups around `anchor`. Slot x runs across
## the front, slot y away from the enemy; facing is a WarFront angle (0 = +x,
## y down, degrees), so across = the facing turned +90 degrees and back = -facing.
## Each position is rounded to whole metres once.
static func layout(repo: DataRepository, formation: String, count: int, anchor: Vector2i,
		facing_deg: int, pitch_m := 0) -> Array[Vector2i]:
	var face := WarFront.facing_vector(facing_deg)
	var across := Vector2(-face.y, face.x) * float(pitch_m if pitch_m > 0 else repo.bal("battle_group_spacing_m"))
	var back := -face * float(pitch_m if pitch_m > 0 else repo.bal("battle_group_depth_m"))
	var out: Array[Vector2i] = []
	for slot: Vector2 in BattleFormation.slots(formation, count):
		out.append(anchor + Vector2i((across * slot.x + back * slot.y).round()))
	return out


## Reconciles fit counts without moving surviving physical rows. Legacy rows
## acquire identities once; only a unit without rows seeds its formation.
static func refresh(repo: DataRepository, state: GameState, battle: Dictionary) -> bool:
	if not (battle.get("pending_round", {}) as Dictionary).is_empty():
		return false
	var size := saved_size(repo, battle) if battle.has("groups") else int(repo.bal("battle_group_size"))
	if not battle.has("groups") and not state.day_resolution.is_empty():
		for current: Dictionary in state.battles:
			if current.has("groups") and not bool(current.get("ended", false)) and not bool(current.get("finished", false)) \
					and saved_size(repo, current) == 50:
				size = 50
	if size <= 0: return false
	var initial_axis := _deployment_axis(repo, state, battle)
	if initial_axis == Vector2.ZERO: return false
	var groups := {}
	var facing := {}
	var snapshots := {}
	var anchors := {}
	var next_slots := {}
	for side: String in BattleSystem.SIDES:
		for code: String in battle[side]:
			anchors[code] = BattleSystem._at_m(repo, state, code)
	for side: String in BattleSystem.SIDES:
		var other: Array = battle["def" if side == "att" else "att"]
		var mean := Vector2i.ZERO
		for foe: String in other:
			mean += anchors[foe]
		var codes: Array = (battle[side] as Array).duplicate()
		codes.sort()
		for code: String in codes:
			var anchor: Vector2i = anchors[code]
			var face := 0
			if not other.is_empty():
				@warning_ignore("integer_division")
				face = WarFront.facing_deg(Vector2(mean / other.size() - anchor))
			face = int(BattleSystem._stored(state, code).get("facing_deg", battle.get("group_facing", {}).get(code, face)))
			var task := BattleTaskSystem.current(state, code)
			var known: Dictionary = task.get("flank", {}).get("known", {})
			if task.get("status", "") == "received" and task.get("request", {}).get("task", "") == "flank" \
					and BattleSystem.canonical(state, int(task["request"]["battle_id"])) == int(battle.get("id", -1)) and not known.is_empty():
				face = WarFront.facing_deg(Vector2(Vector2i(int(known["x_m"]), int(known["y_m"])) - anchor))
			var footprint := piece(repo, state, code)
			if not footprint.ok: return false
			var old: Array = battle.get("groups", {}).get(code, []).duplicate(true)
			var left := ArmySystem.fit_count(repo, state, code)
			var sizes: Array[int] = []
			# Partial migration rows keep their people; only losses trim the tail.
			for row: Dictionary in old:
				if left <= 0: break
				var kept := mini(left, int(row["count"]))
				sizes.append(kept)
				left -= kept
			if left > 0 and not sizes.is_empty():
				var added := mini(left, maxi(0, size - sizes[-1]))
				sizes[-1] += added
				left -= added
			sizes.append_array(counts(left, size))
			var shape := String(BattleFormation._deployment(battle, side, code).get("current", BattleFormation.DEFAULT))
			var at := layout(repo, shape, sizes.size(), anchor, face, int(footprint.pitch_m))
			var slots := BattleFormation.slots(shape, sizes.size())
			var front := 0.0
			for slot: Vector2 in slots:
				front = minf(front, slot.y)
			var entry := BattleSystem._stored(state, code)
			var next := int(entry.get("group_next_slot", 0))
			for row: Dictionary in old:
				next = maxi(next, int(row.get("slot", -1)) + 1)
			var rows: Array = []
			var back := -WarFront.facing_vector(face)
			var rear := 0.0
			for row: Dictionary in old:
				rear = maxf(rear, Vector2(Vector2i(int(row["x_m"]), int(row["y_m"])) - anchor).dot(back))
			for i: int in sizes.size():
				var row: Dictionary
				if i < old.size():
					row = old[i]
				else:
					var point: Vector2i = at[i]
					if not old.is_empty():
						rear += float(footprint.pitch_m)
						point = anchor + Vector2i((back * rear).round())
					row = {"role": "reserve" if not old.is_empty() else (
						"front" if is_equal_approx(slots[i].y, front) else "reserve"),
						"x_m": point.x, "y_m": point.y}
				if not row.has("slot"):
					row["slot"] = next
					next += 1
				row["count"] = sizes[i]
				rows.append(row)
			next_slots[code] = next
			groups[code] = rows
			facing[code] = face
			snapshots[code] = battle.get("group_anchor_m", {}).get(code, [anchor.x, anchor.y])
	var seeded_anchors := {}
	if not battle.has("groups") or int(battle.get("geometry_version", 0)) == 1:
		var proposed := battle.duplicate(true)
		proposed.groups = groups
		proposed.group_facing = facing
		proposed.group_anchor_m = snapshots
		if not battle.has("groups"):
			proposed.group_size_version = 2 if size == int(repo.bal("battle_group_size")) else 1
			proposed.group_size_men = size
		var admission := placement(repo, state, proposed, false)
		if not admission.ok:
			if not bool(admission.get("overlap", false)) or battle.has("groups"): return false
			seeded_anchors = deployment(repo, state, proposed)
			if seeded_anchors.size() != anchors.size() or _relayout(repo, state, proposed, seeded_anchors) != "": return false
			if not placement(repo, state, proposed, false).ok: return false
			groups = proposed.groups
			snapshots = proposed.group_anchor_m
		if not placement(repo, state, proposed).ok: return false
		battle.geometry_version = 1
	for code: String in seeded_anchors:
		var at: Vector2i = seeded_anchors[code]
		var entry := BattleSystem._stored(state, code)
		entry.x_m = at.x
		entry.y_m = at.y
	for code: String in next_slots:
		BattleSystem._stored(state, code)["group_next_slot"] = next_slots[code]
	if not battle.has("groups"):
		battle["group_size_version"] = 2 if size == int(repo.bal("battle_group_size")) else 1
		battle["group_size_men"] = size
	battle["groups"] = groups
	battle["group_facing"] = facing
	battle["group_anchor_m"] = snapshots
	if int(battle.get("geometry_version", 0)) == 1 and not battle.has("deployment_axis_deg"):
		battle.deployment_axis_deg = WarFront.facing_deg(initial_axis)
	return true


## Explicit boundary migration; the caller publishes this private candidate atomically.
static func migrate_size(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	if not state.day_resolution.is_empty() or not (battle.get("pending_round", {}) as Dictionary).is_empty():
		return {"status": "deferred"}
	for current: Dictionary in state.battles:
		if not bool(current.get("ended", false)) and not bool(current.get("finished", false)) \
				and not (current.get("pending_round", {}) as Dictionary).is_empty():
			return {"status": "deferred"}
	if saved_size(repo, battle) <= 0:
		return {"status": "error", "error": "Invalid saved group size/version"}
	if int(battle.get("group_size_version", 0)) == 2 and not bool(battle.get("group_size_regroup_pending", false)):
		return {"status": "complete"}
	var size := int(repo.bal("battle_group_size"))
	if size <= 0:
		return {"status": "error", "error": "Battle group size must be positive"}
	if not battle.has("groups"):
		refresh(repo, state, battle)
		return {"status": "complete"}
	if not battle.groups is Dictionary or not battle.get("group_facing", {}) is Dictionary:
		return {"status": "error", "error": "Invalid saved battle groups or facing"}
	for side: String in BattleSystem.SIDES:
		for code: String in battle.get(side, []):
			if not battle.groups.get(code) is Array or not _whole(battle.get("group_facing", {}).get(code)):
				return {"status": "error", "error": "Missing saved groups or facing: " + code}
			var face := int(battle.group_facing[code])
			if face < 0 or face >= 360:
				return {"status": "error", "error": "Invalid saved group facing: " + code}
			var rows: Array = battle.groups[code].duplicate(true)
			var total := 0
			var slots := {}
			var entry := BattleSystem._stored(state, code)
			var next := int(entry.get("group_next_slot", 0))
			for i: int in rows.size():
				if not rows[i] is Dictionary:
					return {"status": "error", "error": "Invalid saved group row: " + code}
				var row: Dictionary = rows[i]
				if not row.has("slot"): row.slot = i
				for field: String in ["count", "x_m", "y_m"]:
					if not _whole(row.get(field)):
						return {"status": "error", "error": "Invalid saved group " + field + ": " + code}
				if int(row.count) <= 0 or int(row.count) > int(battle.get("group_size_men", 50)) \
						or row.get("role", "") not in ["front", "reserve"] \
						or not _whole(row.get("slot", i)) or int(row.get("slot", i)) < 0:
					return {"status": "error", "error": "Invalid saved group count/role/slot: " + code}
				row.slot = int(row.get("slot", i))
				if slots.has(row.slot):
					return {"status": "error", "error": "Duplicate saved group slot: " + code}
				slots[row.slot] = true
				next = maxi(next, int(row.slot) + 1)
				if row.has("path_m"):
					if not row.path_m is Array:
						return {"status": "error", "error": "Invalid saved group path: " + code}
					for point: Variant in row.path_m:
						if not point is Array or point.size() != 2 or not _whole(point[0]) or not _whole(point[1]):
							return {"status": "error", "error": "Invalid saved group path point: " + code}
				total += int(row.count)
			if total != ArmySystem.fit_count(repo, state, code):
				return {"status": "error", "error": "Saved groups disagree with fit personnel: " + code}
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
			var groups: Array = []
			var cursor := 0
			var consumed := 0
			for amount: int in counts(total, size):
				var kept: Dictionary = rows[cursor].duplicate(true)
				kept.count = amount
				groups.append(kept)
				var left := amount
				while left > 0:
					var take := mini(left, int(rows[cursor].count) - consumed)
					left -= take
					consumed += take
					if consumed == int(rows[cursor].count):
						cursor += 1
						consumed = 0
			battle.groups[code] = groups
			entry.group_next_slot = next
	battle.erase("group_size_regroup_pending")
	battle.group_size_version = 2
	battle.group_size_men = size
	battle.group_size_reason = "Saved fit groups regrouped at a safe transaction boundary"
	return {"status": "complete"}

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value))


static func piece(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var result := BattleGroupGeometry.footprint(repo, ArmySystem.regiment(repo, code, state))
	if not result.ok: return {"ok": false, "error": String(result.reason)}
	return result


## This runs only on MilitaryReorganization's detached safe-boundary candidate.
static func migrate_geometry(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	if not _whole(battle.get("geometry_version", 0)) or int(battle.get("geometry_version", 0)) not in [0, 1]:
		return {"status": "error", "error": "Invalid saved geometry version"}
	if int(battle.get("geometry_version", 0)) == 1: return {"status": "complete"}
	if not state.day_resolution.is_empty(): return {"status": "deferred"}
	for current: Dictionary in state.battles:
		if not (current.get("pending_round", {}) as Dictionary).is_empty(): return {"status": "deferred"}
	var proposed := battle.duplicate(true)
	var anchors := {}
	for side: String in BattleSystem.SIDES:
		for code: String in battle[side]:
			anchors[code] = BattleSystem._at_m(repo, state, code)
	var axis := _deployment_axis(repo, state, proposed)
	if axis == Vector2.ZERO: return {"status": "error", "error": "Invalid saved deployment axis"}
	proposed.deployment_axis_deg = WarFront.facing_deg(axis)
	var error := _relayout(repo, state, proposed, anchors, false)
	if error != "": return {"status": "error", "error": error}
	var admission := placement(repo, state, proposed, false)
	if not admission.ok:
		if not bool(admission.get("overlap", false)): return {"status": "error", "error": admission.error}
		error = _relayout(repo, state, proposed, anchors)
		if error != "": return {"status": "error", "error": error}
	admission = placement(repo, state, proposed, false)
	if not admission.ok:
		if not bool(admission.get("overlap", false)): return {"status": "error", "error": admission.error}
		anchors = deployment(repo, state, proposed)
		if anchors.size() != proposed.att.size() + proposed.def.size():
			return {"status": "error", "error": "No complete legacy geometry deployment"}
		error = _relayout(repo, state, proposed, anchors)
		if error != "": return {"status": "error", "error": error}
	admission = placement(repo, state, proposed)
	if not admission.ok: return {"status": "error", "error": admission.error}
	for code: String in anchors:
		var at: Vector2i = anchors[code]
		var entry := BattleSystem._stored(state, code)
		entry.x_m = at.x
		entry.y_m = at.y
		if entry.get("order", "") != ArmySystem.ORDER_MARCH:
			entry.dest_x_m = at.x
			entry.dest_y_m = at.y
		var charge: Dictionary = entry.get("charge", {})
		if not charge.is_empty():
			charge.x_m = at.x
			charge.y_m = at.y
			charge.origin_x_m = at.x
			charge.origin_y_m = at.y
			charge.runup_m = 0
			charge.phase = "approach" if charge.get("phase", "approach") == "approach" else "disengage"
			charge.impact_day = -1
	proposed.geometry_version = 1
	proposed.geometry_reason = "Legacy battle rows admitted against installed piece footprints at a safe transaction boundary"
	battle.clear()
	battle.merge(proposed)
	return {"status": "complete"}


static func _relayout(repo: DataRepository, state: GameState, battle: Dictionary, anchors: Dictionary, rebuild := true) -> String:
	if not battle.get("groups", {}) is Dictionary or not battle.get("group_facing", {}) is Dictionary:
		return "Invalid saved geometry groups or facings"
	for side: String in BattleSystem.SIDES:
		for code: String in battle[side]:
			var footprint := piece(repo, state, code)
			if not footprint.ok: return String(footprint.error)
			var saved: Variant = battle.get("groups", {}).get(code, [])
			if not saved is Array: return "Invalid geometry row array: " + code
			var rows: Array = saved
			var shape := String(BattleFormation._deployment(battle, side, code).get("current", BattleFormation.DEFAULT))
			var face: Variant = battle.get("group_facing", {}).get(code)
			if not _whole(face) or int(face) < 0 or int(face) >= 360: return "Invalid geometry facing: " + code
			var positions := layout(repo, shape, rows.size(), anchors[code], int(face), int(footprint.pitch_m))
			var total := 0
			var slots := {}
			for i: int in rows.size():
				if not rows[i] is Dictionary: return "Invalid geometry row: " + code
				var row: Dictionary = rows[i]
				if not row.has("slot"): row.slot = i
				for field: String in ["count", "slot", "x_m", "y_m"]:
					if not _whole(row.get(field)): return "Invalid geometry row " + field + ": " + code
				if int(row.count) <= 0 or int(row.count) > saved_size(repo, battle) or int(row.slot) < 0 or slots.has(int(row.slot)) \
						or row.get("role", "") not in ["front", "reserve"]:
					return "Invalid geometry count or repeated slot: " + code
				slots[int(row.slot)] = true
				total += int(row.count)
				if not rebuild: positions[i] = Vector2i(int(row.x_m), int(row.y_m))
				var delta := positions[i] - Vector2i(int(row.x_m), int(row.y_m))
				if row.has("path_m"):
					if not row.path_m is Array: return "Invalid geometry row path: " + code
					for point: Variant in row.path_m:
						if not point is Array or point.size() != 2 or not _whole(point[0]) or not _whole(point[1]): return "Invalid geometry row path: " + code
						point[0] = int(point[0]) + delta.x
						point[1] = int(point[1]) + delta.y
				row.x_m = positions[i].x
				row.y_m = positions[i].y
			if total != ArmySystem.fit_count(repo, state, code): return "Geometry rows disagree with fit personnel: " + code
			battle.get_or_add("group_anchor_m", {})[code] = [anchors[code].x, anchors[code].y]
	return ""


static func in_reach(repo: DataRepository, state: GameState, code: String, row: Dictionary,
		foe: String, other: Dictionary, reach: int) -> bool:
	var own := piece(repo, state, code)
	var enemy := piece(repo, state, foe)
	if not own.ok or not enemy.ok: return false
	var pair := BattleGroupGeometry.pair([row.x_m, row.y_m], int(own.radius_m),
		[other.x_m, other.y_m], int(enemy.radius_m), reach)
	if not pair.ok or not pair.in_reach: return false
	var grid := MarchPath.of_pack(repo)
	return grid == null or grid.clear(Vector2i(int(row.x_m), int(row.y_m)), Vector2i(int(other.x_m), int(other.y_m)))


## Validate the complete proposed rows before publishing any slot or anchor.
static func placement(repo: DataRepository, state: GameState, battle: Dictionary, include_other_fields := true) -> Dictionary:
	var occupied: Array = []
	var overlap_error := {}
	var grid := MarchPath.of_pack(repo)
	var fields: Array = [battle]
	if include_other_fields:
		for other: Dictionary in state.battles:
			if int(other.get("id", -1)) != int(battle.get("id", -1)):
				fields.append(other)
	for field: Dictionary in fields:
		if not field.get("groups", {}) is Dictionary: return {"ok": false, "error": "Invalid occupied group dictionary"}
		var codes: Array = field.get("groups", {}).keys()
		codes.sort()
		for code: String in codes:
			var footprint := piece(repo, state, code)
			if not footprint.ok: return footprint
			if not field.groups[code] is Array: return {"ok": false, "error": "Invalid occupied row array: " + code}
			for value: Variant in field.groups[code]:
				if not value is Dictionary: return {"ok": false, "error": "Invalid occupied row: " + code}
				var row: Dictionary = value
				var bounds := BattleGroupGeometry.envelope([row], int(footprint.radius_m))
				if not bounds.ok: return {"ok": false, "error": String(bounds.reason)}
				if not _whole(row.get("count")) or int(row.count) <= 0:
					return {"ok": false, "error": "Invalid occupied row count: " + code}
				var point := [row.get("x_m"), row.get("y_m")]
				var at := Vector2i(int(point[0]), int(point[1]))
				if field == battle and grid != null and not grid.clear(at, at):
					return {"ok": false, "error": "Occupied battle row is on blocked ground: " + code + " " + str(at)}
				for prior: Dictionary in occupied:
					if field != battle and not prior.proposed: continue
					var pair := BattleGroupGeometry.pair(point, int(footprint.radius_m), prior.point, int(prior.radius), 0)
					if not pair.ok: return {"ok": false, "error": String(pair.reason)}
					if pair.overlap and overlap_error.is_empty():
						overlap_error = {"ok": false, "overlap": true, "error": "Occupied battle discs overlap: " + code + " / " + String(prior.code)}
				occupied.append({"point": point, "radius": footprint.radius_m, "code": code, "proposed": field == battle})
	# A layout retry is safe only after every proposed row has passed ground/schema checks.
	return {"ok": true} if overlap_error.is_empty() else overlap_error


## A pure precommit check, also used for every leg of legacy/saved marches.
static func motion(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		from: Vector2i, movement: Vector2i, budget: int) -> bool:
	if not (battle.get("pending_round", {}) as Dictionary).is_empty(): return false
	var footprint := piece(repo, state, code)
	if not footprint.ok: return false
	var rows: Array = battle.get("groups", {}).get(code, []).duplicate(true)
	if rows.is_empty(): return true
	var snapshot: Array = battle.get("group_anchor_m", {}).get(code, [from.x, from.y])
	var shift := from - Vector2i(int(snapshot[0]), int(snapshot[1]))
	for row: Dictionary in rows:
		row.x_m = int(row.x_m) + shift.x
		row.y_m = int(row.y_m) + shift.y
	var blockers: Array = []
	var fields: Array = [battle]
	for other: Dictionary in state.battles:
		if int(other.get("id", -1)) != int(battle.get("id", -1)): fields.append(other)
	for field: Dictionary in fields:
		for other_code: String in field.get("groups", {}):
			if other_code == code: continue
			var other_piece := piece(repo, state, other_code)
			if not other_piece.ok: return false
			for row: Dictionary in field.groups[other_code]:
				blockers.append({"x_m": row.x_m, "y_m": row.y_m, "radius_m": other_piece.radius_m})
	var check := BattleGroupGeometry.rigid_step(rows, int(footprint.radius_m),
		[movement.x, movement.y], budget, blockers)
	if not check.ok or not check.allowed: return false
	var grid := MarchPath.of_pack(repo)
	for row: Dictionary in rows:
		var start := Vector2i(int(row.x_m), int(row.y_m))
		if grid != null and not grid.clear(start, start + movement, [grid.cell_of(start)]): return false
	return true


## Commit an already validated rigid step; movement has one anchor writer.
static func translate(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		movement: Vector2i, budget := -1) -> bool:
	var from := BattleSystem._at_m(repo, state, code)
	if not motion(repo, state, battle, code, from, movement,
			budget if budget >= 0 else ceili(Vector2(movement).length())): return false
	var entry := BattleSystem._stored(state, code)
	var at := BattleSystem._at_m(repo, state, code) + movement
	battle.get_or_add("group_anchor_m", {})[code] = [from.x, from.y]
	entry["x_m"] = at.x
	entry["y_m"] = at.y
	return follow_anchor(repo, state, battle, code)


## Follow a live march commit, never a private forecast. This does not move the
## anchor or reconcile a pending round's personnel, and replaying it is inert.
static func follow_anchor(repo: DataRepository, state: GameState, battle: Dictionary, code: String, passed: Array = []) -> bool:
	if not battle.get("groups", {}).has(code):
		return true
	var at := BattleSystem._at_m(repo, state, code)
	if not battle.has("group_anchor_m"):
		battle["group_anchor_m"] = {}
	var pair: Array = battle["group_anchor_m"].get(code, [at.x, at.y])
	var delta := at - Vector2i(int(pair[0]), int(pair[1]))
	if delta != Vector2i.ZERO:
		var from := at - delta
		for point: Vector2i in passed + [at]:
			var leg := point - from
			if not motion(repo, state, battle, code, from, leg, ceili(Vector2(leg).length())): return false
			from = point
		for row: Dictionary in battle["groups"][code]:
			row["x_m"] = int(row["x_m"]) + delta.x
			row["y_m"] = int(row["y_m"]) + delta.y
			if row.has("path_m"):
				for point: Array in row["path_m"]:
					point[0] = int(point[0]) + delta.x
					point[1] = int(point[1]) + delta.y
	battle["group_anchor_m"][code] = [at.x, at.y]
	return true


## Every unit's target anchor on its side's deployment line (P4.4d2). The axis
## runs from the defenders' mean anchor toward the attackers' (+x when they
## coincide); each line centre is the battle place +- axis * gap / 2 (att on the
## + side); a side's units stand abreast in sorted code order, each as wide as
## its front groups, the side centred. Pure; each target rounded to metres once.
static func _deployment_axis(repo: DataRepository, state: GameState, battle: Dictionary) -> Vector2:
	if battle.has("deployment_axis_deg"):
		var saved: Variant = battle.deployment_axis_deg
		if not _whole(saved) or int(saved) < 0 or int(saved) >= 360: return Vector2.ZERO
		return WarFront.facing_vector(int(saved))
	if battle.att.is_empty() or battle.def.is_empty(): return Vector2.RIGHT
	var means := {}
	for side: String in BattleSystem.SIDES:
		var sum := Vector2i.ZERO
		for code: String in battle[side]: sum += BattleSystem._at_m(repo, state, code)
		@warning_ignore("integer_division")
		means[side] = sum / battle[side].size()
	var delta := Vector2(means.att - means.def)
	return delta.normalized() if delta != Vector2.ZERO else Vector2.RIGHT


static func deployment(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var size := saved_size(repo, battle) if battle.has("groups") else int(repo.bal("battle_group_size"))
	if size <= 0: return {}
	if not _whole(battle.get("place_x_m")) or not _whole(battle.get("place_y_m")): return {}
	var axis := _deployment_axis(repo, state, battle)
	if axis == Vector2.ZERO: return {}
	var across := Vector2(-axis.y, axis.x)
	var place := Vector2(int(battle.place_x_m), int(battle.place_y_m))
	var gap := float(repo.bal("battle_line_gap_m"))
	var out := {}
	for side: String in BattleSystem.SIDES:
		var forward := -axis if side == "att" else axis
		var codes: Array = battle[side].duplicate()
		codes.sort()
		var bounds := {}
		var total := 0.0
		var front := -INF
		for code: String in codes:
			var footprint := piece(repo, state, code)
			if not footprint.ok: return {}
			var shape := String(BattleFormation._deployment(battle, side, code).get("current", BattleFormation.DEFAULT))
			var face := int(battle.get("group_facing", {}).get(code, WarFront.facing_deg(forward)))
			var points: Array[Vector2i] = []
			var anchor := BattleSystem._at_m(repo, state, code)
			var rows: Array = battle.get("groups", {}).get(code, [])
			for row: Dictionary in rows:
				points.append(Vector2i(int(row.x_m), int(row.y_m)) - anchor)
			if rows.is_empty():
				points = layout(repo, shape, counts(ArmySystem.fit_count(repo, state, code), size).size(),
					Vector2i.ZERO, face, int(footprint.pitch_m))
			if points.is_empty():
				bounds[code] = {"low": 0.0, "width": 0.0}
				continue
			var low := Vector2(points[0]).dot(across)
			var high := low
			for point: Vector2i in points:
				low = minf(low, Vector2(point).dot(across))
				high = maxf(high, Vector2(point).dot(across))
				front = maxf(front, Vector2(point).dot(forward) + float(footprint.radius_m))
			var width := high - low + 2.0 * float(footprint.radius_m)
			bounds[code] = {"low": low - float(footprint.radius_m), "width": width}
			total += width + gap
		if is_inf(front):
			for code: String in codes: out[code] = BattleSystem._at_m(repo, state, code)
			continue
		var cursor := -(total - gap) / 2.0
		var back := front + gap / 2.0
		# A fixed opponent cannot supply its nominal half of the deployment gap.
		for enemy: String in battle["def" if side == "att" else "att"]:
			if ArmyGround.seated_in(repo, state, enemy) == "" and not bool(BattleSystem._stored(state, enemy).get("captured", false)): continue
			var footprint := piece(repo, state, enemy)
			if not footprint.ok: return {}
			var rows: Array = battle.get("groups", {}).get(enemy, []).duplicate(true)
			if rows.is_empty() and ArmySystem.fit_count(repo, state, enemy) > 0:
				var shape := String(BattleFormation._deployment(battle, "def" if side == "att" else "att", enemy).get("current", BattleFormation.DEFAULT))
				var face := int(battle.get("group_facing", {}).get(enemy, WarFront.facing_deg(-forward)))
				for point: Vector2i in layout(repo, shape, counts(ArmySystem.fit_count(repo, state, enemy), size).size(),
						BattleSystem._at_m(repo, state, enemy), face, int(footprint.pitch_m)):
					rows.append({"x_m": point.x, "y_m": point.y})
			for row: Dictionary in rows:
				back = maxf(back, front + float(footprint.radius_m) + gap -
					(Vector2(int(row.x_m), int(row.y_m)) - place).dot(forward))
		var centre := place - forward * back
		for code: String in codes:
			if float(bounds[code].width) == 0.0:
				out[code] = BattleSystem._at_m(repo, state, code)
				continue
			out[code] = Vector2i((centre + across * (cursor - float(bounds[code].low))).round())
			cursor += float(bounds[code].width) + gap
			if ArmyGround.seated_in(repo, state, code) != "" or bool(BattleSystem._stored(state, code).get("captured", false)):
				out[code] = BattleSystem._at_m(repo, state, code)
	return out


## Saved front-group contact, with active pursuit restricted to its received
## region. An attacking opponent still permits self-defence outside it.
## A pursuit_target asks only for pursuit contact with that enemy, not defence.
static func engaged_counts(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		pursuit_target := "") -> Vector2i:
	var rows: Array = battle.get("groups", {}).get(code, [])
	var side := BattleRules.side_of(battle, code)
	if rows.is_empty() or side == "":
		return Vector2i.ZERO
	var reach := int(repo.bal("battle_group_contact_m"))
	var grid := MarchPath.of_pack(repo)
	var action := BattleSystem.unit_action(repo, state, battle, code)
	var region := String(action.get("pursuit_region", "")) if action["kind"] == "attack" else ""
	var foes: Array = battle["def" if side == "att" else "att"] if pursuit_target == "" else [pursuit_target]
	var fit := 0
	var engaged := 0
	for row: Dictionary in rows:
		fit += int(row["count"])
		if String(row["role"]) != "front":
			continue
		var inside := true
		if region != "":
			var at := ArmySystem.metres_to_pack(repo, Vector2i(int(row["x_m"]), int(row["y_m"])))
			inside = MapManors.province_of(repo, MapEconomy.cell_at(repo, at), state) in region.split("|")
		var touching := false
		for foe: String in foes:
			if not inside:
				if pursuit_target != "":
					continue
				var incoming := BattleSystem.unit_action(repo, state, battle, foe)
				if incoming["kind"] != "attack":
					continue
			for other: Dictionary in battle["groups"].get(foe, []):
				if in_reach(repo, state, code, row, foe, other, reach):
					if grid != null and not grid.clear(Vector2i(int(row["x_m"]), int(row["y_m"])),
							Vector2i(int(other["x_m"]), int(other["y_m"]))):
						continue
					touching = true
					break
			if touching:
				break
		if touching:
			engaged += int(row["count"])
	return Vector2i(engaged, fit)


## P4.4d4: the share of a unit's fit people that fight in full, in permille:
## engaged people count whole, every other fit person (reserve ranks, a front
## still approaching) counts `battle_reserve_permille`. 1000 with no groups.
static func engaged_permille(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> int:
	var c := engaged_counts(repo, state, battle, code)
	if c.y <= 0:
		return 1000
	@warning_ignore("integer_division")
	return (c.x * 1000 + (c.y - c.x) * int(repo.bal("battle_reserve_permille"))) / c.y


## True while any side is ordered to retreat or any of its units is withdrawing:
## the battle then goes to separation, so no unit closes the line any more.
static func withdrawing(state: GameState, battle: Dictionary) -> bool:
	for side: String in BattleSystem.SIDES:
		if BattleOrders.kind(battle, side) == "retreat":
			return true
		for code: String in battle[side]:
			var e := BattleSystem._stored(state, code)
			if bool(e.get("battle_retreat", false)) or e.has("disengaging"):
				return true
	return false


## Staggered front rows can be outside contact even at their nominal line.
## Find the nearest actual front approach; exact disc/terrain checks admit its
## next bounded step, including the nine whole-metre rounding neighbours.
static func _close_front(repo: DataRepository, state: GameState, battle: Dictionary,
		code: String, from: Vector2i, budget: int, targets: Dictionary) -> Dictionary:
	var own := piece(repo, state, code)
	if not own.ok: return {"target": from}
	var side := BattleRules.side_of(battle, code)
	var enemies: Array = battle["def" if side == "att" else "att"].duplicate()
	enemies.sort()
	var best := INF
	var row_from := {}
	var row_to := {}
	var target := ""
	for row: Dictionary in battle.get("groups", {}).get(code, []):
		if row.role != "front" or int(row.count) <= 0: continue
		for enemy: String in enemies:
			# A moving, charging or flanking opponent retains its own approach.
			if not targets.has(enemy) or BattleSystem._at_m(repo, state, enemy) != targets[enemy]: continue
			var footprint := piece(repo, state, enemy)
			if not footprint.ok: return {"target": from}
			for other: Dictionary in battle.get("groups", {}).get(enemy, []):
				var pair := BattleGroupGeometry.pair([row.x_m, row.y_m], int(own.radius_m),
					[other.x_m, other.y_m], int(footprint.radius_m), int(repo.bal("battle_group_contact_m")))
				if not pair.ok: return {"target": from}
				if pair.in_reach: continue
				var gap := sqrt(float(pair.distance_sq)) - float(own.radius_m) - float(footprint.radius_m) - repo.bal("battle_group_contact_m")
				if gap < best:
					best = gap
					row_from = row
					row_to = other
					target = enemy
	if target == "": return {}
	var direction := Vector2(Vector2i(int(row_to.x_m), int(row_to.y_m)) - Vector2i(int(row_from.x_m), int(row_from.y_m))).normalized()
	var rounded := Vector2i((direction * best).round())
	for rounding: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
		var delta := rounded + rounding
		var proposed := row_from.duplicate()
		proposed.x_m = int(row_from.x_m) + delta.x
		proposed.y_m = int(row_from.y_m) + delta.y
		if not in_reach(repo, state, code, proposed, target, row_to, int(repo.bal("battle_group_contact_m"))): continue
		var step := delta if Vector2(delta).length() <= budget else Vector2i(Vector2(delta).normalized() * budget)
		if motion(repo, state, battle, code, from, step, budget): return {"target": from + delta}
	return {"target": from}


## One deployment step, once per absolute day (`battle.deployed_day`): every
## unit but a withdrawing, captured, fitless or town-seated one steps its anchor
## toward its target by at most `battle_deploy_step_m` whole metres. The groups
## are refreshed by the caller.
static func deploy_day(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	var today := state.absolute_day()
	if int(battle.get("deployed_day", -1)) == today or withdrawing(state, battle) or not (battle.get("pending_round", {}) as Dictionary).is_empty():
		return
	battle["deployed_day"] = today
	var targets := deployment(repo, state, battle)
	var step := int(repo.bal("battle_deploy_step_m"))
	var grid := MarchPath.of_pack(repo)   # the land grid: no step into water or over a scarp
	var charges := {}
	if not refresh(repo, state, battle): return
	for code: String in targets:
		var e := BattleSystem._stored(state, code)
		if e.is_empty() or bool(e.get("captured", false)) or ArmySystem.fit_count(repo, state, code) <= 0 \
				or ArmyGround.seated_in(repo, state, code) != "":
			continue
		var foe := BattleCharge.target(repo, state, battle, code)
		if foe != "":
			charges[code] = foe
			continue
		# Interruptions discard unfinished momentum, never the obligation to regroup.
		var charge: Dictionary = e.get("charge", {})
		if charge.get("phase", "approach") == "approach":
			e.erase("charge")
		elif charge["phase"] == "impact":
			charge["phase"] = "disengage"
		if BattleTaskSystem.deploy_flank(repo, state, battle, code):
			continue
		var from := BattleSystem._at_m(repo, state, code)
		var to: Vector2i = targets[code]
		var action := BattleSystem.unit_action(repo, state, battle, code)
		if engaged_counts(repo, state, battle, code).x > 0: continue
		var ranged_standoff: bool = action["kind"] == "attack" and not action.has("pursuit_target") \
			and BattleRanged.share(repo, state, code) >= int(repo.bal("battle_context_arm_threshold_permille"))
		if ranged_standoff:
			# Target and offset each round to metres: reserve their combined half-diagonal error.
			var back := maxf(0.0, float(repo.bal("battle_ranged_reach_m") - repo.bal("battle_line_gap_m")) / 2.0 - sqrt(2.0))
			to -= Vector2i((WarFront.facing_vector(int(battle["group_facing"][code])) * back).round())
		var forward := -_deployment_axis(repo, state, battle) if BattleRules.side_of(battle, code) == "att" else _deployment_axis(repo, state, battle)
		var task := BattleTaskSystem.current(state, code)
		var close_line: bool = task.is_empty() or (task.get("request", {}).get("task", "") == "advance" and action["kind"] == "attack")
		if close_line and not ranged_standoff and not action.has("pursuit_target") and not battle.get("reserves", {}).has(code) \
				and Vector2(from - to).dot(forward) >= 0.0:
			var approach := _close_front(repo, state, battle, code, from, int(step), targets)
			if approach.has("target"): to = approach.target
		var d := Vector2(to - from)
		var moved := to if d.length() <= step else from + Vector2i(d.normalized() * step)
		# ponytail: a blocked straight step waits in place; a routed approach round water is later work
		if grid != null and not grid.clear(from, moved, [grid.cell_of(from)]):
			continue
		translate(repo, state, battle, code, moved - from, int(step))

	refresh(repo, state, battle)
	for code: String in charges:
		BattleCharge.move(repo, state, battle, code, String(charges[code]))


## Candidate targets translate existing bodies only; no tactical slot materialization.
## Scalar local projections retain whole world coordinates without Vector2i narrowing.
static func _body_deployment(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var place: Array = [battle.get("place_x_m"), battle.get("place_y_m")]
	if not BodyMotion._loco_point(place): return {}
	var angle: Variant = battle.get("deployment_axis_deg")
	if not battle.has("deployment_axis_deg"):
		var means := {}
		for side: String in BattleSystem.SIDES:
			var x := 0.0
			var y := 0.0
			if battle[side].is_empty(): return {}
			for code: String in battle[side]:
				var entry := UnitBodies._entry(state, code)
				var dx := BodyMotion._difference(entry.x_m, place[0])
				var dy := BodyMotion._difference(entry.y_m, place[1])
				if absf(dx) > BodyMotion.LOCAL_LIMIT or absf(dy) > BodyMotion.LOCAL_LIMIT: return {}
				x += dx
				y += dy
			means[side] = [x / battle[side].size(), y / battle[side].size()]
		angle = rad_to_deg(atan2(means.att[1] - means.def[1], means.att[0] - means.def[0]))
	elif not BodyMotion._loco_integer(angle) or angle < 0 or angle >= 360: return {}
	var ax := cos(deg_to_rad(float(angle)))
	var ay := sin(deg_to_rad(float(angle)))
	var gap: Variant = repo.balance.get("battle_line_gap_m")
	if not BodyMotion._loco_integer(gap) or gap < 0 or gap > BodyMotion.LOCAL_LIMIT: return {}
	var out := {}
	for side: String in BattleSystem.SIDES:
		var sign := -1 if side == "att" else 1
		var codes: Array = battle[side].duplicate()
		codes.sort()
		var bounds := {}
		var total := 0.0
		var front := -INF
		for code: String in codes:
			var entry := UnitBodies._entry(state, code)
			var footprint := BattleGroupGeometry.footprint(repo, state.army_roster[code])
			if not footprint.ok: return {}
			var low := INF
			var high := -INF
			for row: Dictionary in battle.groups[code]:
				var x := BodyMotion._difference(row.x_m, entry.x_m)
				var y := BodyMotion._difference(row.y_m, entry.y_m)
				if absf(x) > BodyMotion.LOCAL_LIMIT or absf(y) > BodyMotion.LOCAL_LIMIT: return {}
				low = minf(low, -ay * x + ax * y)
				high = maxf(high, -ay * x + ax * y)
				front = maxf(front, sign * (ax * x + ay * y) + footprint.radius_m)
			var width: float = high - low + 2.0 * footprint.radius_m if not is_inf(low) else 0.0
			bounds[code] = {"low": low - footprint.radius_m if width > 0 else 0.0, "width": width}
			total += width + gap
		if is_inf(front):
			for code: String in codes:
				var entry := UnitBodies._entry(state, code)
				out[code] = [int(entry.x_m), int(entry.y_m)]
			continue
		var back: float = front + gap / 2.0
		for enemy: String in battle["def" if side == "att" else "att"]:
			if ArmyGround.seated_in(repo, state, enemy) == "" and not bool(UnitBodies._entry(state, enemy).get("captured", false)): continue
			var footprint := BattleGroupGeometry.footprint(repo, state.army_roster[enemy])
			if not footprint.ok: return {}
			for row: Dictionary in battle.groups[enemy]:
				var x := BodyMotion._difference(row.x_m, place[0])
				var y := BodyMotion._difference(row.y_m, place[1])
				if absf(x) > BodyMotion.LOCAL_LIMIT or absf(y) > BodyMotion.LOCAL_LIMIT: return {}
				back = maxf(back, front + footprint.radius_m + gap - sign * (ax * x + ay * y))
		var cursor: float = -(total - gap) / 2.0
		for code: String in codes:
			var entry := UnitBodies._entry(state, code)
			var lateral: float = cursor - bounds[code].low
			var point: Array = [int(place[0]) + int(round(-sign * ax * back - ay * lateral)),
				int(place[1]) + int(round(-sign * ay * back + ax * lateral))]
			if not BodyMotion._loco_point(point): return {}
			for axis: int in 2:
				if absf(BodyMotion._difference(point[axis], entry.x_m if axis == 0 else entry.y_m)) > BodyMotion.LOCAL_LIMIT: return {}
			out[code] = point if bounds[code].width > 0 else [int(entry.x_m), int(entry.y_m)]
			cursor += bounds[code].width + gap
			if ArmyGround.seated_in(repo, state, code) != "" or bool(entry.get("captured", false)):
				out[code] = [int(entry.x_m), int(entry.y_m)]
	return {"targets": out, "axis": [ax, ay]}

static func deployment_intent_candidate(repo: DataRepository, source: GameState,
		battle_id: int, unit: String, budget_m: int) -> Dictionary:
	var result := {"status": "error", "reason": "Invalid deployment input", "error": "Invalid deployment input", "unit": unit, "path_m": []}
	if repo == null or source == null or budget_m < 0 or budget_m > BodyMotion.LOCAL_LIMIT or source.day_resolution.is_empty(): return result
	var control: Variant = source.day_resolution.get("body_battle")
	if not control is Dictionary: return result
	var boundary := {"version": 1, "kind": "battle", "abs_day": control.get("abs_day"), "substep": control.get("next_substep"), "sequence": control.get("sequence"), "stage": control.get("stage")}
	var error := BodyBattleMotion._source_error(repo, source, boundary)
	if not error.is_empty():
		result.reason = error
		result.error = error
		return result
	# Existing law queries infer historical parties; keep that metadata private.
	source = UnitBodies._copy(source)
	var battle := UnitBodies._battle(source, BodyBattleContact._canonical_id(source, battle_id))
	var side := BattleRules.side_of(battle, unit)
	if battle.is_empty() or side == "": return result
	var entry := UnitBodies._entry(source, unit)
	var here: Array = [int(entry.x_m), int(entry.y_m)]
	result = {"status": "complete", "reason": "Holding deployment", "error": "", "unit": unit, "path_m": [here]}
	if BodyBattleMotion._writer(repo, source, unit, battle) != "deployment":
		result.reason = "A higher-priority writer owns this unit"
		return result
	if budget_m == 0 or bool(entry.get("captured", false)) or MilitaryRoster.fit(source, unit) <= 0 \
		or ArmyGround.seated_in(repo, source, unit) != "" or not CampSystem.can_march_entry(entry, source.absolute_day()) \
		or withdrawing(source, battle) or battle.get("reserves", {}).has(unit): return result
	var enemies: Array = battle["def" if side == "att" else "att"].duplicate()
	enemies.sort()
	if enemies.is_empty():
		result.reason = "No opposing battlefield members"
		return result
	var contact := BodyBattleContact.query_candidate(repo, source, int(battle.id), unit, enemies, boundary)
	if contact.status != "complete":
		return {"status": "error", "reason": contact.reason, "error": contact.reason, "unit": unit, "path_m": []}
	if contact.engaged > 0:
		result.reason = "Already in lawful physical contact"
		return result
	var layout := _body_deployment(repo, source, battle)
	var targets: Dictionary = layout.get("targets", {})
	if not targets.has(unit):
		return {"status": "error", "reason": "Invalid candidate deployment geometry", "error": "Invalid candidate deployment geometry", "unit": unit, "path_m": []}
	var target: Array = targets[unit]
	var action := BattleSystem.unit_action(repo, source, battle, unit)
	if action.kind == "attack" and not action.has("pursuit_target") \
		and BattleRanged.share(repo, source, unit) >= int(repo.bal("battle_context_arm_threshold_permille")):
		var back := maxf(0.0, float(repo.bal("battle_ranged_reach_m") - repo.bal("battle_line_gap_m")) / 2.0 - sqrt(2.0))
		var facing: Variant = battle.get("group_facing", {}).get(unit)
		if not BodyMotion._loco_integer(facing) or facing < 0 or facing >= 360:
			return {"status": "error", "reason": "Missing candidate deployment facing", "error": "Missing candidate deployment facing", "unit": unit, "path_m": []}
		var face := deg_to_rad(float(facing))
		target = [int(target[0]) - int(round(cos(face) * back)), int(target[1]) - int(round(sin(face) * back))]
	else:
		var task := BattleTaskSystem.current(source, unit)
		var close_line: bool = task.is_empty() or (task.get("request", {}).get("task") == "advance" and action.kind == "attack")
		var sign := -1 if side == "att" else 1
		if close_line and not action.has("pursuit_target") and sign * (BodyMotion._difference(here[0], target[0]) * layout.axis[0] + BodyMotion._difference(here[1], target[1]) * layout.axis[1]) >= 0:
			var approach := _body_close_front(repo, source, battle, unit, targets)
			if not approach.is_empty(): target = [int(here[0]) + int(approach[0]), int(here[1]) + int(approach[1])]
	var path := BodyMotion._clip([here, target], budget_m)
	var footprint := BattleGroupGeometry.footprint(repo, source.army_roster[unit])
	for row: Dictionary in battle.groups[unit]:
		var translated: Array = []
		for point: Array in path: translated.append([int(row.x_m) + int(point[0]) - int(here[0]), int(row.y_m) + int(point[1]) - int(here[1])])
		var terrain := ArmySystem._body_path_terrain(MarchPath.of_pack(repo), translated, int(footprint.radius_m))
		if not terrain.is_empty():
			result.reason = terrain
			return result
	result.path_m = path
	result.reason = "Existing-body deployment toward its occupied line" if path.size() > 1 else "At deployment line"
	return result

static func _body_close_front(repo: DataRepository, source: GameState, battle: Dictionary,
		unit: String, targets: Dictionary) -> Array:
	var own := BattleGroupGeometry.footprint(repo, source.army_roster[unit])
	var side := BattleRules.side_of(battle, unit)
	var enemies: Array = battle["def" if side == "att" else "att"].duplicate()
	enemies.sort()
	var best := INF
	var from: Array = []
	var to: Array = []
	var radius := 0
	for row: Dictionary in battle.groups[unit]:
		for enemy: String in enemies:
			var entry := UnitBodies._entry(source, enemy)
			if targets.get(enemy) != [int(entry.x_m), int(entry.y_m)] \
				or BodyBattleMotion._writer(repo, source, enemy, battle) != "deployment" \
				or not BodyBattleContact._barred(repo, source, battle, battle, side, unit, enemy).is_empty(): continue
			var footprint := BattleGroupGeometry.footprint(repo, source.army_roster[enemy])
			for other: Dictionary in battle.groups[enemy]:
				var pair := BattleGroupGeometry.pair([row.x_m, row.y_m], int(own.radius_m),
					[other.x_m, other.y_m], int(footprint.radius_m), int(repo.bal("battle_group_contact_m")))
				if not pair.ok or pair.in_reach: continue
				var gap: float = sqrt(float(pair.distance_sq)) - own.radius_m - footprint.radius_m - repo.bal("battle_group_contact_m")
				if gap < best:
					best = gap
					from = [int(row.x_m), int(row.y_m)]
					to = [int(other.x_m), int(other.y_m)]
					radius = int(footprint.radius_m)
	if from.is_empty(): return []
	var x := BodyMotion._difference(to[0], from[0])
	var y := BodyMotion._difference(to[1], from[1])
	var distance := sqrt(x * x + y * y)
	for rounding: Array in [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]:
		var delta: Array = [int(round(x * best / distance)) + rounding[0], int(round(y * best / distance)) + rounding[1]]
		var point: Array = [int(from[0]) + int(delta[0]), int(from[1]) + int(delta[1])]
		var pair := BattleGroupGeometry.pair(point, int(own.radius_m), to, radius, int(repo.bal("battle_group_contact_m")))
		if pair.ok and not pair.overlap and pair.in_reach \
			and ArmySystem._body_path_terrain(MarchPath.of_pack(repo), [point, to], 0).is_empty(): return delta
	return []


## CF06 candidate melee input: `{engaged, fit, reason}` adapted from the admitted lawful
## physical query at the state's own boundary (its saved battle day, or the safe boundary
## when no day is open). A rejection is never a legitimate zero: it returns -1 counts and
## a "Rejected:" reason. No front/reserve fallback.
static func melee_counts(repo: DataRepository, state: GameState, battle: Dictionary, unit: String, enemies: Array) -> Dictionary:
	var rejected := {"engaged": -1, "fit": -1, "reason": "Rejected: candidate melee needs an admitted battle boundary"}
	if repo == null or state == null or not BodyMotion._loco_integer(battle.get("id")): return rejected
	var boundary: Dictionary
	if state.day_resolution.get("body_battle") is Dictionary:
		var raw := DayResolution.body_battle_incompatibility_reason(state.day_resolution)
		if not raw.is_empty(): return {"engaged": -1, "fit": -1, "reason": "Rejected: " + raw}
		boundary = BodyBattleMotion._boundary(state)
	elif state.day_resolution.is_empty(): boundary = BodyBattle.safe_boundary(state)
	else: return rejected
	var sorted := enemies.duplicate()
	sorted.sort()
	var query := BodyBattleContact.query_candidate(repo, state, int(battle.id), unit, sorted, boundary)
	if query.status != "complete": return {"engaged": -1, "fit": -1, "reason": "Rejected: " + String(query.reason)}
	return {"engaged": int(query.engaged), "fit": int(query.fit), "reason": String(query.reason)}
