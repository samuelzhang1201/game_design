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
		facing_deg: int) -> Array[Vector2i]:
	var face := WarFront.facing_vector(facing_deg)
	var across := Vector2(-face.y, face.x) * float(repo.bal("battle_group_spacing_m"))
	var back := -face * float(repo.bal("battle_group_depth_m"))
	var out: Array[Vector2i] = []
	for slot: Vector2 in BattleFormation.slots(formation, count):
		out.append(anchor + Vector2i((across * slot.x + back * slot.y).round()))
	return out


## Reconciles fit counts without moving surviving physical rows. Legacy rows
## acquire identities once; only a unit without rows seeds its formation.
static func refresh(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	if battle.has("pending_round"):
		return
	var size := saved_size(repo, battle) if battle.has("groups") else int(repo.bal("battle_group_size"))
	if not battle.has("groups") and not state.day_resolution.is_empty():
		for current: Dictionary in state.battles:
			if current.has("groups") and not bool(current.get("ended", false)) and not bool(current.get("finished", false)) \
					and saved_size(repo, current) == 50:
				size = 50
	if size <= 0: return
	var groups := {}
	var facing := {}
	var snapshots := {}
	var anchors := {}
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
			face = int(BattleSystem._stored(state, code).get("facing_deg", face))
			var task := BattleTaskSystem.current(state, code)
			var known: Dictionary = task.get("flank", {}).get("known", {})
			if task.get("status", "") == "received" and task.get("request", {}).get("task", "") == "flank" \
					and BattleSystem.canonical(state, int(task["request"]["battle_id"])) == int(battle.get("id", -1)) and not known.is_empty():
				face = WarFront.facing_deg(Vector2(Vector2i(int(known["x_m"]), int(known["y_m"])) - anchor))
			var old: Array = battle.get("groups", {}).get(code, [])
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
			var at := layout(repo, BattleFormation.of_unit(state, code), sizes.size(), anchor, face)
			var slots := BattleFormation.slots(BattleFormation.of_unit(state, code), sizes.size())
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
						rear += float(repo.bal("battle_group_depth_m"))
						point = anchor + Vector2i((back * rear).round())
					row = {"role": "reserve" if not old.is_empty() else (
						"front" if is_equal_approx(slots[i].y, front) else "reserve"),
						"x_m": point.x, "y_m": point.y}
				if not row.has("slot"):
					row["slot"] = next
					next += 1
				row["count"] = sizes[i]
				rows.append(row)
			entry["group_next_slot"] = next
			groups[code] = rows
			facing[code] = face
			snapshots[code] = battle.get("group_anchor_m", {}).get(code, [anchor.x, anchor.y])
	if not battle.has("groups"):
		battle["group_size_version"] = 2 if size == int(repo.bal("battle_group_size")) else 1
		battle["group_size_men"] = size
	battle["groups"] = groups
	battle["group_facing"] = facing
	battle["group_anchor_m"] = snapshots


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


## Commit an already validated rigid step; movement has one anchor writer.
static func translate(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		movement: Vector2i) -> void:
	if battle.has("pending_round"):
		return
	refresh(repo, state, battle)
	var entry := BattleSystem._stored(state, code)
	var at := BattleSystem._at_m(repo, state, code) + movement
	entry["x_m"] = at.x
	entry["y_m"] = at.y
	follow_anchor(repo, state, battle, code)


## Follow a live march commit, never a private forecast. This does not move the
## anchor or reconcile a pending round's personnel, and replaying it is inert.
static func follow_anchor(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> void:
	if not battle.get("groups", {}).has(code):
		return
	var at := BattleSystem._at_m(repo, state, code)
	if not battle.has("group_anchor_m"):
		battle["group_anchor_m"] = {}
	var pair: Array = battle["group_anchor_m"].get(code, [at.x, at.y])
	var delta := at - Vector2i(int(pair[0]), int(pair[1]))
	if delta != Vector2i.ZERO:
		for row: Dictionary in battle["groups"][code]:
			row["x_m"] = int(row["x_m"]) + delta.x
			row["y_m"] = int(row["y_m"]) + delta.y
			if row.has("path_m"):
				for point: Array in row["path_m"]:
					point[0] = int(point[0]) + delta.x
					point[1] = int(point[1]) + delta.y
	battle["group_anchor_m"][code] = [at.x, at.y]


## Every unit's target anchor on its side's deployment line (P4.4d2). The axis
## runs from the defenders' mean anchor toward the attackers' (+x when they
## coincide); each line centre is the battle place +- axis * gap / 2 (att on the
## + side); a side's units stand abreast in sorted code order, each as wide as
## its front groups, the side centred. Pure; each target rounded to metres once.
static func deployment(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var size := saved_size(repo, battle) if battle.has("groups") else int(repo.bal("battle_group_size"))
	if size <= 0: return {}
	var means := {}
	for side: String in BattleSystem.SIDES:
		var sum := Vector2i.ZERO
		for code: String in battle[side]:
			sum += BattleSystem._at_m(repo, state, code)
		var n: int = maxi(1, (battle[side] as Array).size())
		@warning_ignore("integer_division")
		means[side] = sum / n
	var axis := Vector2(means["att"] - means["def"])
	axis = axis.normalized() if axis != Vector2.ZERO else Vector2.RIGHT
	var across := Vector2(-axis.y, axis.x)
	var place := Vector2(int(battle["place_x_m"]), int(battle["place_y_m"]))
	var spacing := float(repo.bal("battle_group_spacing_m"))
	var half_gap := float(repo.bal("battle_line_gap_m")) / 2.0
	var out := {}
	for side: String in BattleSystem.SIDES:
		var centre := place + axis * (half_gap if side == "att" else -half_gap)
		var codes: Array = (battle[side] as Array).duplicate()
		codes.sort()
		var widths := {}
		var total := 0.0
		for code: String in codes:
			var slots := BattleFormation.slots(BattleFormation.of_unit(state, code),
				counts(ArmySystem.fit_count(repo, state, code), size).size())
			var front := 0.0
			for slot: Vector2 in slots:
				front = minf(front, slot.y)
			var n := 0
			for slot: Vector2 in slots:
				n += 1 if is_equal_approx(slot.y, front) else 0
			widths[code] = float(maxi(1, n)) * spacing
			total += float(widths[code])
		var at := -total / 2.0
		for code: String in codes:
			out[code] = Vector2i((centre + across * (at + float(widths[code]) / 2.0)).round())
			at += float(widths[code])
	return out


## Distance to a closed segment; tangency is legal for both terrain and people.
static func _distance_sq(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	var t := clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0) if delta != Vector2.ZERO else 0.0
	return point.distance_squared_to(a + delta * t)


static func _rect_distance_sq(a: Vector2, b: Vector2, rect: Rect2) -> float:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var best := minf(a.distance_squared_to(a.clamp(rect.position, rect.end)), b.distance_squared_to(b.clamp(rect.position, rect.end)))
	for i: int in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return 0.0
		best = minf(best, _distance_sq(corners[i], a, b))
	return best


## Every closed cell intersecting the capsule's interior counts, including caps.
static func _ground_clear(grid: MarchPath, a: Vector2i, b: Vector2i, radius: float) -> bool:
	if grid == null:
		return true
	var low := Vector2(mini(a.x, b.x), mini(a.y, b.y)) - Vector2.ONE * radius
	var high := Vector2(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2.ONE * radius
	if low.x < 0.0 or low.y < 0.0 or high.x > grid.cols * grid.cell_m or high.y > grid.rows * grid.cell_m:
		return false
	# The destination is never opened as a march endpoint.
	if grid.is_closed(grid.cell_of(a)) or grid.is_closed(grid.cell_of(b)):
		return false
	var first := Vector2i(low / float(grid.cell_m))
	var last := Vector2i(high / float(grid.cell_m))
	for y: int in range(first.y, mini(last.y + 1, grid.rows)):
		for x: int in range(first.x, mini(last.x + 1, grid.cols)):
			if grid.is_closed(Vector2i(x, y)) and _rect_distance_sq(Vector2(a), Vector2(b),
					Rect2(Vector2(x, y) * grid.cell_m, Vector2.ONE * grid.cell_m)) < radius * radius:
				return false
	return true


## Pure swept disk validation. Rigid movement excludes only its own rigid rows.
static func sweep_clear(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		slot: int, here: Vector2i, path: Array) -> bool:
	var spacing := float(repo.bal("battle_group_spacing_m"))
	var grid := MarchPath.of_pack(repo)
	var source := {}
	if slot >= 0 and state != null and BattleRules.side_of(battle, code) != "" \
			and not BattleSystem._stored(state, code).is_empty():
		for row: Dictionary in battle.get("groups", {}).get(code, []):
			if _whole(row.get("slot")) and int(row.slot) == slot and int(row.get("count", 0)) > 0:
				source = row
	var at_source := not source.is_empty() and here == Vector2i(int(source.x_m), int(source.y_m))
	var offsets: Array[Vector2i] = [Vector2i.ZERO]
	if slot < 0:
		offsets.clear()
		for row: Dictionary in battle.get("groups", {}).get(code, []):
			offsets.append(Vector2i(int(row.x_m), int(row.y_m)) - here)
	for offset: Vector2i in offsets:
		var previous := here + offset
		for point: Vector2i in [here] + path:
			var next := point + offset
			if not _ground_clear(grid, previous, next, spacing / 2.0):
				return false
			for other_code: String in battle.get("groups", {}):
				for other: Dictionary in battle.groups[other_code]:
					if other_code == code and (slot < 0 or int(other.slot) == slot):
						continue
					var q := Vector2(int(other.x_m), int(other.y_m))
					if _distance_sq(q, Vector2(previous), Vector2(next)) < spacing * spacing:
						# Only committed same-unit facts may separate; candidate origins cannot opt in.
						var exiting := at_source and other_code == code and int(other.get("count", 0)) > 0 \
							and _whole(other.get("slot")) and int(other.slot) >= 0 \
							and Vector2(here).distance_squared_to(q) < spacing * spacing \
							and Vector2(previous).distance_squared_to(q) < spacing * spacing \
							and (Vector2(previous) - q).dot(Vector2(next - previous)) >= 0.0
						if not exiting: return false
			previous = next
	return true


## A private expanded grid; neither pack terrain nor its cached road is changed.
static func _route(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		slot: int, here: Vector2i, to: Vector2i, occupancy := true) -> Array:
	var grid := MarchPath.of_pack(repo)
	var radius := float(repo.bal("battle_group_spacing_m")) / 2.0
	if not _ground_clear(grid, here, here, radius) or not _ground_clear(grid, to, to, radius):
		return []
	if (sweep_clear(repo, state, battle, code, slot, here, [to]) if occupancy else _ground_clear(grid, here, to, radius)):
		return [to]
	if grid != null and not grid.joins(here, to):
		return []
	# Pack cells describe terrain, not tactical occupancy. Refine only this route's box.
	var cell := mini(grid.cell_m, maxi(1, floori(radius))) if grid != null else maxi(1, floori(radius))
	var low := Vector2i(mini(here.x, to.x), mini(here.y, to.y))
	var high := Vector2i(maxi(here.x, to.x), maxi(here.y, to.y))
	var controls: Array = [here, to]
	if grid != null and not _ground_clear(grid, here, to, radius):
		controls.append_array(grid.road(here, to))
	var blockers: Array[Vector2i] = []
	if occupancy:
		for other_code: String in battle.get("groups", {}):
			for row: Dictionary in battle.groups[other_code]:
				if other_code == code and int(row.slot) == slot: continue
				var at := Vector2i(int(row.x_m), int(row.y_m))
				blockers.append(at)
				controls.append(at)
	for point: Vector2i in controls:
		low = Vector2i(mini(low.x, point.x), mini(low.y, point.y))
		high = Vector2i(maxi(high.x, point.x), maxi(high.y, point.y))
	low -= Vector2i.ONE * ceili(radius * 4.0)
	high += Vector2i.ONE * ceili(radius * 4.0)
	if grid != null:
		low = Vector2i(maxi(0, low.x), maxi(0, low.y))
		high = Vector2i(mini(grid.cols * grid.cell_m, high.x), mini(grid.rows * grid.cell_m, high.y))
	# Align the factual source to a cell centre: a snapped first corner must not
	# deepen its old overlap or cut into a tangent neighbouring group.
	var start_cell := Vector2i(floori(float(here.x - low.x) / cell), floori(float(here.y - low.y) / cell))
	@warning_ignore("integer_division")
	var origin := here - start_cell * cell - Vector2i.ONE * (cell / 2)
	if grid != null:
		if origin.x < 0: origin.x += ceili(float(-origin.x) / cell) * cell
		if origin.y < 0: origin.y += ceili(float(-origin.y) / cell) * cell
	var cols := maxi(1, ceili(float(high.x - origin.x) / cell))
	var rows := maxi(1, ceili(float(high.y - origin.y) / cell))
	var bytes := PackedByteArray()
	bytes.resize(cols * rows)
	var private := MarchPath.build(repo, cols, rows, cell, bytes)
	var spacing := radius * 2.0
	for y: int in rows:
		for x: int in cols:
			var at := private.centre_m(Vector2i(x, y)) + origin
			var legal := _ground_clear(grid, at, at, radius)
			if legal:
				for q: Vector2i in blockers:
					if at.distance_squared_to(q) < spacing * spacing:
						legal = false
						break
			private.closed[y * cols + x] = 0 if legal else 1
	var start := here - origin
	var end := to - origin
	if occupancy and sweep_clear(repo, state, battle, code, slot, here, []):
		private.closed[private.cell_of(start).y * cols + private.cell_of(start).x] = 0
	if private.is_closed(private.cell_of(start)) or private.is_closed(private.cell_of(end)) or not private.joins(start, end):
		return []
	# Centre-line string pulling can shave the expanded edge. Retain the legal
	# cell-centre route when its shortened polyline fails the actual disk test.
	private._astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	var raw: Array = []
	for cell_at: Vector2i in private._cells(private.cell_of(start), private.cell_of(end)).slice(1):
		raw.append(private.centre_m(cell_at))
	raw.append(end)
	for candidate: Array in [private.road(start, end), raw]:
		if not ArmySystem.leg_clear(private, start, candidate): continue
		var path: Array = []
		for point: Vector2i in candidate:
			path.append(point + origin)
		if occupancy:
			if sweep_clear(repo, state, battle, code, slot, here, path): return path
		else:
			var previous := here
			var legal := true
			for point: Vector2i in path:
				legal = legal and _ground_clear(grid, previous, point, radius)
				previous = point
			if legal: return path
	return []



## Commits one row only; the anchor is synchronized once after all ordinary rows.
static func move_row(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		slot: int, path: Array, budget: int) -> Dictionary:
	var row := {}
	for candidate: Dictionary in battle.get("groups", {}).get(code, []):
		if int(candidate.slot) == slot:
			row = candidate
	if row.is_empty():
		return {"at": Vector2i.ZERO, "path": path, "moved_m": 0, "arrived": false}
	var here := Vector2i(int(row.x_m), int(row.y_m))
	var result := {"at": here, "path": path, "moved_m": 0, "arrived": path.is_empty()}
	if battle.has("pending_round") or budget <= 0 or path.is_empty():
		return result
	# Terrain connectivity applies to the whole route; moving people block this step.
	var previous := here
	for point: Vector2i in path:
		if not _ground_clear(MarchPath.of_pack(repo), previous, point, float(repo.bal("battle_group_spacing_m")) / 2.0):
			return result
		previous = point
	var limit := budget
	var walked := MarchRoute.walk(here, path, budget)
	var traversed: Array = (walked.passed as Array).duplicate()
	traversed.append(walked.at)
	while MarchRoute.length_from(here, traversed) > float(limit):
		budget -= 1
		walked = MarchRoute.walk(here, path, budget)
		traversed = (walked.passed as Array).duplicate()
		traversed.append(walked.at)
	if not sweep_clear(repo, state, battle, code, slot, here, traversed):
		return result
	var at: Vector2i = walked.at
	row.x_m = at.x
	row.y_m = at.y
	row.path_m = MarchRoute.to_pairs(walked.path)
	return {"at": at, "path": walked.path, "moved_m": floori(MarchRoute.length_from(here, traversed)), "arrived": (walked.path as Array).is_empty()}


static func _ordered_rows(battle: Dictionary, code: String) -> Array:
	var rows: Array = battle.get("groups", {}).get(code, []).duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	return rows


## Desired targets are pure: transient friendly queues affect travel, not capacity.
static func targets(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		_region := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var side := BattleRules.side_of(battle, code)
	if side == "": return out
	var goals := deployment(repo, state, battle)
	var codes: Array = (battle[side] as Array).duplicate()
	codes.sort()
	var requested := 0
	var centre := Vector2.ZERO
	var native := {}
	var native_roles := {}
	var grid := MarchPath.of_pack(repo)
	var spacing := float(repo.bal("battle_group_spacing_m"))
	var depth := float(repo.bal("battle_group_depth_m"))
	var fits := true
	var front_fits := true
	for member: String in codes:
		var rows := _ordered_rows(battle, member)
		var shape := BattleFormation.of_unit(state, member)
		var slots := BattleFormation.slots(shape, rows.size())
		var front := 0.0
		for point: Vector2 in slots:
			front = minf(front, point.y)
		var width := 0
		var roles: Array[String] = []
		for point: Vector2 in slots:
			roles.append("front" if is_equal_approx(point.y, front) else "reserve")
			width += 1 if is_equal_approx(point.y, front) else 0
		requested += width
		centre += Vector2(goals[member]) * width
		var points := layout(repo, shape, rows.size(), goals[member], int(battle.get("group_facing", {}).get(member, 0)))
		native[member] = points
		native_roles[member] = roles
		for i: int in points.size():
			var point: Vector2i = points[i]
			var clear := _ground_clear(grid, point, point, spacing / 2.0)
			fits = fits and clear
			if roles[i] == "front": front_fits = front_fits and clear
	if requested == 0: return out
	var total := 0
	for member: String in codes: total += (native[member] as Array).size()
	var max_ranks := total * maxi(1, ceili(spacing / maxf(1.0, depth)))
	if fits:
		var chosen := {}
		var occupied: Array[Vector2i] = []
		# Reserve desired front points first, so overflow cannot steal a later slot's front.
		for phase: String in ["front", "reserve"]:
			for member: String in codes:
				var rows := _ordered_rows(battle, member)
				var back := -WarFront.facing_vector(int(battle.get("group_facing", {}).get(member, 0))) * depth
				for i: int in rows.size():
					if native_roles[member][i] != phase: continue
					var point: Vector2i = native[member][i]
					for rank: int in max_ranks:
						var candidate := point + Vector2i((back * rank).round())
						if not _ground_clear(grid, candidate, candidate, spacing / 2.0) \
								or occupied.any(func(other: Vector2i) -> bool: return candidate.distance_squared_to(other) < spacing * spacing): continue
						var here := Vector2i(int(rows[i].x_m), int(rows[i].y_m))
						if not _route(repo, state, battle, member, int(rows[i].slot), here, candidate, false).is_empty():
							chosen[[member, int(rows[i].slot)]] = {"slot": int(rows[i].slot), "x_m": candidate.x,
								"y_m": candidate.y, "role": phase if rank == 0 else "reserve"}
							occupied.append(candidate)
						break
		for row: Dictionary in _ordered_rows(battle, code):
			if chosen.has([code, int(row.slot)]): out.append(chosen[[code, int(row.slot)]])
		return out
	centre /= float(requested)
	var face := WarFront.facing_vector(int(battle.get("group_facing", {}).get(codes[0], 0)))
	var across := Vector2(-face.y, face.x)
	var lanes: Array[float] = []
	if not fits:
		# Compare the native half-pitch and centred pitch; never cross a closed gap.
		for centred: bool in [false, true]:
			var candidate: Array[float] = []
			for i: int in requested:
				var offset := (float(i) - float(requested - 1) / 2.0) * spacing
				if centred:
					offset += spacing / 2.0
				if absf(offset) <= float(requested - 1) * spacing / 2.0:
					candidate.append(offset)
			var seed := -1
			for i: int in candidate.size():
				if seed < 0 or absf(candidate[i]) < absf(candidate[seed]): seed = i
			if seed < 0: continue
			var at := Vector2i((centre + across * candidate[seed]).round())
			if not _ground_clear(grid, at, at, spacing / 2.0): continue
			var low := seed
			var high := seed
			while low > 0:
				at = Vector2i((centre + across * candidate[low - 1]).round())
				if not _ground_clear(grid, at, at, spacing / 2.0): break
				low -= 1
			while high + 1 < candidate.size():
				at = Vector2i((centre + across * candidate[high + 1]).round())
				if not _ground_clear(grid, at, at, spacing / 2.0): break
				high += 1
			if high - low + 1 > lanes.size(): lanes.assign(candidate.slice(low, high + 1))
		lanes.sort_custom(func(a: float, b: float) -> bool: return a < b if is_equal_approx(absf(a), absf(b)) else absf(a) < absf(b))
		if lanes.is_empty(): return out
	var chosen := {}
	var claimed: Array[Vector2i] = []
	# Reserve reachable native slots before filling holes; a rear rock cannot
	# flatten legal shapes or displace another unit's native targets.
	for phase: String in ["front", "reserve"]:
		for member: String in codes:
			var rows := _ordered_rows(battle, member)
			for i: int in rows.size():
				if native_roles[member][i] != phase: continue
				var point: Vector2i = native[member][i]
				if phase == "front" and not front_fits and not lanes.any(func(lane: float) -> bool:
					return absf((Vector2(point) - centre).dot(across) - lane) <= sqrt(2.0)): continue
				if not _ground_clear(grid, point, point, spacing / 2.0) \
						or claimed.any(func(other: Vector2i) -> bool: return point.distance_squared_to(other) < spacing * spacing): continue
				var here := Vector2i(int(rows[i].x_m), int(rows[i].y_m))
				if _route(repo, state, battle, member, int(rows[i].slot), here, point, false).is_empty(): continue
				chosen[[member, int(rows[i].slot)]] = {"slot": int(rows[i].slot), "x_m": point.x, "y_m": point.y, "role": phase}
				claimed.append(point)
	for member: String in codes:
		for row: Dictionary in _ordered_rows(battle, member):
			var key := [member, int(row.slot)]
			if chosen.has(key): continue
			var here := Vector2i(int(row.x_m), int(row.y_m))
			for rank: int in max_ranks:
				for lane: float in lanes:
					var point := Vector2i((centre + across * lane - face * rank * depth).round())
					if not _ground_clear(grid, point, point, spacing / 2.0) \
							or claimed.any(func(other: Vector2i) -> bool: return point.distance_squared_to(other) < spacing * spacing): continue
					if _route(repo, state, battle, member, int(row.slot), here, point, false).is_empty(): continue
					chosen[key] = {"slot": int(row.slot), "x_m": point.x, "y_m": point.y, "role": "front" if rank == 0 else "reserve"}
					claimed.append(point)
					break
				if chosen.has(key): break
	for row: Dictionary in _ordered_rows(battle, code):
		if chosen.has([code, int(row.slot)]): out.append(chosen[[code, int(row.slot)]])

	return out


static func _mean_anchor(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> void:
	var rows: Array = battle.get("groups", {}).get(code, [])
	if rows.is_empty(): return
	var sum := Vector2i.ZERO
	for row: Dictionary in rows:
		sum += Vector2i(int(row.x_m), int(row.y_m))
	var mean := Vector2i((Vector2(sum) / rows.size()).round())
	var entry := BattleSystem._stored(state, code)
	entry.x_m = mean.x
	entry.y_m = mean.y
	battle.group_anchor_m[code] = [mean.x, mean.y]


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
				var dx := int(row["x_m"]) - int(other["x_m"])
				var dy := int(row["y_m"]) - int(other["y_m"])
				if dx * dx + dy * dy <= reach * reach:
					if not _ground_clear(grid, Vector2i(int(row["x_m"]), int(row["y_m"])),
							Vector2i(int(other["x_m"]), int(other["y_m"])), float(repo.bal("battle_group_spacing_m")) / 2.0):
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


## One deployment step, once per absolute day (`battle.deployed_day`): every
## unit but a withdrawing, captured, fitless or town-seated one steps its anchor
## toward its target by at most `battle_deploy_step_m` whole metres. The groups
## are refreshed by the caller.
static func deploy_day(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	var today := state.absolute_day()
	if int(battle.get("deployed_day", -1)) == today or withdrawing(state, battle) or battle.has("pending_round"):
		return
	battle["deployed_day"] = today
	var step := int(repo.bal("battle_deploy_step_m"))
	var charges := {}
	refresh(repo, state, battle)
	var goals := {}
	var codes: Array[String] = []
	for side: String in BattleSystem.SIDES:
		var members: Array = (battle[side] as Array).duplicate()
		members.sort()
		for code: String in members:
			codes.append(code)
			goals[code] = targets(repo, state, battle, code)
	for code: String in codes:
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
		var action := BattleSystem.unit_action(repo, state, battle, code)
		var back := 0.0
		if action["kind"] == "attack" and not action.has("pursuit_target") \
				and BattleRanged.share(repo, state, code) >= int(repo.bal("battle_context_arm_threshold_permille")):
			back = maxf(0.0, float(repo.bal("battle_ranged_reach_m") - repo.bal("battle_line_gap_m")) / 2.0 - sqrt(2.0))
		for goal: Dictionary in goals[code]:
			var slot := int(goal.slot)
			var row: Dictionary
			for candidate: Dictionary in battle.groups[code]:
				if int(candidate.slot) == slot: row = candidate
			var here := Vector2i(int(row.x_m), int(row.y_m))
			var to := Vector2i(int(goal.x_m), int(goal.y_m)) - Vector2i((WarFront.facing_vector(int(battle.group_facing[code])) * back).round())
			if goal.role == "reserve": row.role = "reserve"
			var path: Array = [to]
			var direct := MarchRoute.walk(here, path, step)
			if not _ground_clear(MarchPath.of_pack(repo), here, to, float(repo.bal("battle_group_spacing_m")) / 2.0) \
					or not sweep_clear(repo, state, battle, code, slot, here, (direct.passed as Array) + [direct.at]):
				path = _route(repo, state, battle, code, slot, here, to)
				if path.is_empty():
					path = _route(repo, state, battle, code, slot, here, to, false)
			if not path.is_empty():
				move_row(repo, state, battle, code, slot, path, step)
		_mean_anchor(repo, state, battle, code)

	refresh(repo, state, battle)
	for code: String in charges:
		BattleCharge.move(repo, state, battle, code, String(charges[code]))
