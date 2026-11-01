class_name BodyMotion
extends RefCounted
## Explicit isolated candidates only. Production movement does not call this API.

# Local arithmetic is bounded for double-precision sweep predicates, not world positions.
const LOCAL_LIMIT: int = 67108864
const INT_MIN: int = -9223372036854775807 - 1
const INT_MAX: int = 9223372036854775807

static func plan(repo: DataRepository, state: GameState, intents: Array, abs_day: int, substep: int, march_boundary: Dictionary = {}) -> Dictionary:
	if repo == null or state == null or abs_day < 0 or substep < 0: return _error("Invalid motion source/cursor")
	var validated := _validate(repo, state, march_boundary)
	if validated.status != "complete": return _error("Motion requires complete unfrozen bodies: " + validated.reason)
	if not state.military_migration.has("body_version"): return _error("Motion requires explicitly initialized current bodies")
	if not march_boundary.is_empty() and (int(march_boundary.abs_day) != abs_day or int(march_boundary.substep) != substep):
		return _error("Motion cursor disagrees with explicit boundary")
	var raw_saved: Variant = state.military_migration.get("body_motion", {})
	var saved := _read_saved(raw_saved)
	if state.military_migration.has("body_motion") and not _saved_ok(raw_saved): return _error("Invalid saved motion cursor")
	if not saved.is_empty() and _older(abs_day, substep, saved): return _error("Stale motion cursor")
	var attempts: Variant = repo.bal("cluster_motion_detour_attempts")
	var clearance: Variant = repo.bal("cluster_motion_clearance_m")
	if not _natural(attempts) or int(attempts) < 1 or int(attempts) > 64 or not _natural(clearance) or int(clearance) < 1 or int(clearance) > LOCAL_LIMIT:
		return _error("Invalid motion configuration")
	var bodies: Array[Dictionary] = []
	var lookup := {}
	var codes: Array = state.regiments.keys() + state.foes.keys()
	codes.sort()
	for unit: String in codes:
		var piece := MapObjects.army_piece(repo, state.army_roster[unit])
		for row: Dictionary in UnitBodies.rows(repo, state, unit):
			var radius := int(repo.unit_footprints[piece].radius_m)
			if radius > LOCAL_LIMIT: return _error("Measured radius exceeds safe local sweep range")
			var body := {"unit": unit, "slot": int(row.slot), "radius": radius,
				"realm": str(state.army_roster[unit].get("kingdom_code", "")),
				"path_m": [[int(row.x_m), int(row.y_m)]], "budget_m": 0, "hostile": false}
			if not march_boundary.is_empty():
				body.enemies = []
				for other: String in codes:
					if ArmySystem._body_enemies(repo, state, unit, other): body.enemies.append(other)
			lookup[_id(body)] = bodies.size()
			bodies.append(body)
	var ordered: Array[Dictionary] = []
	var seen := {}
	for raw: Variant in intents:
		if not raw is Dictionary or not _keys(raw, ["unit", "slot", "path_m", "budget_m", "hostile"]): return _error("Invalid intent schema")
		if not raw.unit is String or not _natural(raw.slot) or not _natural(raw.budget_m) or int(raw.budget_m) > LOCAL_LIMIT or not raw.hostile is bool:
			return _error("Invalid identity/budget/hostility")
		var identity := _id(raw)
		if seen.has(identity) or not lookup.has(identity): return _error("Duplicate or absent body identity")
		seen[identity] = true
		if not raw.path_m is Array or raw.path_m.is_empty(): return _error("Missing integer path")
		var path: Array = []
		for point: Variant in raw.path_m:
			if not point is Array or point.size() != 2 or not _integer(point[0]) or not _integer(point[1]): return _error("Noninteger path point")
			path.append([int(point[0]), int(point[1])])
		var body: Dictionary = bodies[lookup[identity]]
		if path[0] != body.path_m[0]: return _error("Path does not begin at authoritative body")
		# Far future waypoints need no unsafe subtraction; reject outside the local numerical contract.
		for point: Array in path:
			if absf(_difference(point[0], path[0][0])) > LOCAL_LIMIT or absf(_difference(point[1], path[0][1])) > LOCAL_LIMIT:
				return _error("Path exceeds safe local sweep range")
		ordered.append({"unit": raw.unit, "slot": int(raw.slot), "path_m": path, "budget_m": int(raw.budget_m), "hostile": raw.hostile})
	ordered.sort_custom(_less)
	var canonical_intents := ordered.duplicate(true)
	var priority: Array = saved.get("priority", [])
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ai := priority.find(_identity(a))
		var bi := priority.find(_identity(b))
		if ai != bi: return (ai if ai >= 0 else priority.size()) < (bi if bi >= 0 else priority.size())
		return _less(a, b))
	for intent: Dictionary in ordered:
		var body: Dictionary = bodies[lookup[_id(intent)]]
		body.budget_m = intent.budget_m
		body.hostile = intent.hostile
	for intent: Dictionary in ordered:
		var index: int = lookup[_id(intent)]
		var body: Dictionary = bodies[index]
		var wanted := _clip(intent.path_m, intent.budget_m)
		if _clear(index, wanted, bodies):
			body.path_m = wanted
			continue
		var selected: Array = []
		# Detours return to the requested polyline; never reserve or bill untravelled metres.
		if not body.hostile and _friendly_obstacles(index, bodies):
			var maximum_radius := int(body.radius)
			for other: Dictionary in bodies: maximum_radius = maxi(maximum_radius, int(other.radius))
			for attempt: int in int(attempts):
				@warning_ignore("integer_division")
				var offset: int = (int(body.radius) + maximum_radius + int(clearance)) * (1 + attempt / 2)
				if attempt % 2: offset = -offset
				var route := _detour(intent.path_m, offset)
				if route.is_empty() or _length(route) > intent.budget_m: continue
				if _clear(index, route, bodies):
					selected = route
					break
		if selected.is_empty():
			var low := 0
			var high := _length(wanted)
			while low <= high:
				@warning_ignore("integer_division")
				var middle: int = low + (high - low) / 2
				var prefix := _clip(wanted, middle)
				if _clear(index, prefix, bodies):
					selected = prefix
					low = middle + 1
				else: high = middle - 1
		if not selected.is_empty(): body.path_m = selected
	var moves: Array = []
	var blocked: Array = []
	var reasons := {}
	var next_priority: Array = []
	for intent: Dictionary in ordered:
		var body: Dictionary = bodies[lookup[_id(intent)]]
		var used := _length(body.path_m)
		moves.append({"unit": body.unit, "slot": body.slot, "path_m": body.path_m.duplicate(true), "used_m": used, "budget_m": body.budget_m})
		if body.path_m.back() != intent.path_m.back():
			blocked.append(_identity(body))
			reasons[_id(body)] = "Waiting: no swept-clear route within budget after bounded local search"
		if used > 0 and not body.hostile: next_priority.append(_identity(body))
	moves.sort_custom(_less)
	blocked.sort_custom(_less)
	return {"moves": moves, "blocked": blocked, "reasons": reasons,
		"cursor": {"version": 1, "abs_day": abs_day, "substep": substep,
			"basis": _hash([state.to_dict(), repo.unit_footprints, attempts, clearance, march_boundary, repo.world_table("political", "diplomacy") if not march_boundary.is_empty() else {}]), "intents": canonical_intents, "priority": next_priority}}

static func commit(repo: DataRepository, state: GameState, proposed: Dictionary, march_boundary: Dictionary = {}) -> Dictionary:
	if repo == null or state == null or not _keys(proposed, ["moves", "blocked", "reasons", "cursor"]) or not proposed.cursor is Dictionary:
		return _failure("Invalid plan schema")
	var cursor: Dictionary = proposed.cursor
	if not _keys(cursor, ["version", "abs_day", "substep", "basis", "intents", "priority"]) \
		or not _natural(cursor.version) or int(cursor.version) != 1 or not _natural(cursor.abs_day) or not _natural(cursor.substep) \
		or not cursor.basis is String or not cursor.intents is Array or not _priority_ok(cursor.priority): return _failure("Invalid plan cursor")
	var validation := _validate(repo, state, march_boundary)
	if validation.status != "complete" or not state.military_migration.has("body_version"): return _failure("Commit requires complete unfrozen candidate")
	if not march_boundary.is_empty() and (int(march_boundary.abs_day) != int(cursor.abs_day) or int(march_boundary.substep) != int(cursor.substep)):
		return _failure("Motion cursor disagrees with explicit boundary")
	var raw_saved: Variant = state.military_migration.get("body_motion", {})
	var saved := _read_saved(raw_saved)
	if state.military_migration.has("body_motion") and not _saved_ok(raw_saved): return _failure("Invalid saved motion cursor")
	var receipt := _hash(proposed)
	if not saved.is_empty():
		if _older(int(cursor.abs_day), int(cursor.substep), saved): return _failure("Stale plan cursor")
		if int(cursor.abs_day) == int(saved.abs_day) and int(cursor.substep) == int(saved.substep):
			return {"status": "complete", "reason": "Already committed"} if receipt == saved.receipt else _failure("Cursor already committed with another plan")
	var expected := plan(repo, state, cursor.intents, int(cursor.abs_day), int(cursor.substep), march_boundary)
	if expected.cursor.is_empty() or _hash(expected) != receipt: return _failure("Stale or modified plan")
	var candidate: GameState = validation.candidate
	for move: Dictionary in expected.moves:
		var rows: Array = _owned_rows(candidate, move.unit)
		for row: Dictionary in rows:
			if int(row.slot) != int(move.slot): continue
			row.x_m = int(move.path_m.back()[0])
			row.y_m = int(move.path_m.back()[1])
			row.path_m = move.path_m.duplicate(true)
	var saved_priority: Array = []
	for identity: Dictionary in cursor.priority:
		saved_priority.append({"unit": identity.unit, "slot": str(int(identity.slot))})
	candidate.military_migration.body_motion = {"version": "1", "abs_day": str(int(cursor.abs_day)), "substep": str(int(cursor.substep)),
		"receipt": receipt, "priority": saved_priority}
	validation = _validate(repo, candidate, march_boundary)
	if validation.status != "complete": return _failure("Motion candidate failed final physical validation")
	# The API's caller owns this isolated candidate; no production dispatcher binds it.
	state.regiments = candidate.regiments
	state.foes = candidate.foes
	state.battles = candidate.battles
	state.military_migration = candidate.military_migration
	return {"status": "complete", "reason": "Committed swept-clear candidate motion"}

static func _owned_rows(state: GameState, unit: String) -> Array:
	for battle: Dictionary in state.battles:
		if not battle.get("ended", false) and not battle.get("finished", false) and battle.get("groups", {}).has(unit): return battle.groups[unit]
	return state.foes.get(unit, state.regiments.get(unit, {})).get("body_groups", [])

static func _clear(index: int, path: Array, bodies: Array[Dictionary]) -> bool:
	for j: int in bodies.size():
		if index != j and _collision(bodies[index], path, bodies[j], bodies[j].path_m): return false
	return true

static func _friendly_obstacles(index: int, bodies: Array[Dictionary]) -> bool:
	var own: Dictionary = bodies[index]
	for other: Dictionary in bodies:
		if (other.unit in own.enemies if own.has("enemies") else other.realm != own.realm) or other.hostile:
			# Only relevant nearby enemy paths prohibit a friendly local bypass.
			var reach: float = own.budget_m + other.budget_m + own.radius + other.radius
			if absf(_difference(own.path_m[0][0], other.path_m[0][0])) <= reach and absf(_difference(own.path_m[0][1], other.path_m[0][1])) <= reach: return false
	return true

static func _collision(a: Dictionary, ap: Array, b: Dictionary, bp: Array) -> bool:
	var radius: float = a.radius + b.radius
	var reach: float = a.budget_m + b.budget_m + radius
	if absf(_difference(ap[0][0], bp[0][0])) > reach or absf(_difference(ap[0][1], bp[0][1])) > reach: return false
	for sa: Dictionary in _segments(ap, a.budget_m):
		for sb: Dictionary in _segments(bp, b.budget_m):
			var start: float = maxf(sa.t0, sb.t0)
			var end: float = minf(sa.t1, sb.t1)
			if end < start: continue
			var ax: float = _difference(sa.b[0], sa.a[0]) / (sa.t1 - sa.t0)
			var ay: float = _difference(sa.b[1], sa.a[1]) / (sa.t1 - sa.t0)
			var bx: float = _difference(sb.b[0], sb.a[0]) / (sb.t1 - sb.t0)
			var by: float = _difference(sb.b[1], sb.a[1]) / (sb.t1 - sb.t0)
			# Exact constant-axis separation keeps integer tangency legal without roundoff.
			if ax == 0.0 and bx == 0.0 and absf(_difference(sa.a[0], sb.a[0])) >= radius: continue
			if ay == 0.0 and by == 0.0 and absf(_difference(sa.a[1], sb.a[1])) >= radius: continue
			var rx: float = _difference(sa.a[0], sb.a[0]) + ax * (start - sa.t0) - bx * (start - sb.t0)
			var ry: float = _difference(sa.a[1], sb.a[1]) + ay * (start - sa.t0) - by * (start - sb.t0)
			var vx := ax - bx
			var vy := ay - by
			var speed := vx * vx + vy * vy
			var time := clampf(-(rx * vx + ry * vy) / speed, 0.0, end - start) if speed > 0 else 0.0
			var dx := rx + vx * time
			var dy := ry + vy * time
			# At t=0 the foundation already proved exact integer separation. Later
			# predicates include a double-roundoff bound, conservatively rejecting grazing.
			if start == 0.0 and time == 0.0: continue
			var pa := _integer_endpoint(sa, start + time)
			var pb := _integer_endpoint(sb, start + time)
			var derivative := dx * vx + dy * vy
			var derivative_error := 64.0 * 2.220446049250313e-16 * (absf(rx) + absf(ry) + absf(vx) + absf(vy)) * (absf(vx) + absf(vy))
			var monotone_endpoint := speed == 0.0 or (time == 0.0 and derivative > derivative_error) or (time == end - start and derivative < -derivative_error)
			if monotone_endpoint and not pa.is_empty() and not pb.is_empty():
				var ix := int(_difference(pa[0], pb[0]))
				var iy := int(_difference(pa[1], pb[1]))
				if ix * ix + iy * iy < int(radius) * int(radius): return true
				continue
			var error_bound := 64.0 * 2.220446049250313e-16 * (absf(rx) + absf(ry) + absf(vx) + absf(vy) + radius)
			if dx * dx + dy * dy < (radius + error_bound) * (radius + error_bound): return true
	return false

static func _integer_endpoint(segment: Dictionary, time: float) -> Array:
	if segment.a == segment.b or time == segment.t0: return segment.a
	if time == segment.t1: return segment.b
	return []

static func _segments(path: Array, budget: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used := 0
	for i: int in range(1, path.size()):
		var length := _distance_ceil(path[i - 1], path[i])
		if length == 0: continue
		out.append({"a": path[i - 1], "b": path[i], "t0": float(used) / budget, "t1": float(used + length) / budget})
		used += length
	var time := float(used) / budget if budget > 0 else 0.0
	if time < 1.0: out.append({"a": path.back(), "b": path.back(), "t0": time, "t1": 1.0})
	return out

static func _detour(path: Array, offset: int) -> Array:
	if path.size() < 2: return []
	var dx := _difference(path.back()[0], path[0][0])
	var dy := _difference(path.back()[1], path[0][1])
	var length := sqrt(dx * dx + dy * dy)
	if length == 0: return []
	var ox := int(round(-dy * offset / length))
	var oy := int(round(dx * offset / length))
	var out: Array = [path[0].duplicate()]
	for point: Array in path:
		if not _can_add(point[0], ox) or not _can_add(point[1], oy): return []
		out.append([int(point[0]) + ox, int(point[1]) + oy])
	out.append(path.back().duplicate())
	return out

static func _clip(path: Array, budget: int) -> Array:
	var out: Array = [path[0].duplicate()]
	var remaining := budget
	for i: int in range(1, path.size()):
		var cost := _distance_ceil(path[i - 1], path[i])
		if cost == 0: continue
		if cost <= remaining:
			out.append(path[i].duplicate())
			remaining -= cost
		else:
			var ratio := float(remaining) / cost
			var x := int(_difference(path[i][0], path[i - 1][0]) * ratio)
			var y := int(_difference(path[i][1], path[i - 1][1]) * ratio)
			if x != 0 or y != 0: out.append([int(path[i - 1][0]) + x, int(path[i - 1][1]) + y])
			break
	return out

static func _length(path: Array) -> int:
	var total := 0
	for i: int in range(1, path.size()):
		total += _distance_ceil(path[i - 1], path[i])
		if total > LOCAL_LIMIT: return LOCAL_LIMIT + 1
	return total

static func _distance_ceil(a: Array, b: Array) -> int:
	var x := absf(_difference(a[0], b[0]))
	var y := absf(_difference(a[1], b[1]))
	# Only rejected detours exceed this range; clipping inputs span at most twice LOCAL_LIMIT.
	if x > 2 * LOCAL_LIMIT or y > 2 * LOCAL_LIMIT: return LOCAL_LIMIT + 1
	var squared := int(x) * int(x) + int(y) * int(y)
	var distance := int(ceil(sqrt(float(squared))))
	# A rounded sqrt can hide the fractional metre; exact int64 squares decide ceil.
	while distance * distance < squared: distance += 1
	while distance > 0 and (distance - 1) * (distance - 1) >= squared: distance -= 1
	return distance

static func _difference(a: int, b: int) -> float:
	if b > 0 and a < INT_MIN + b: return -INF
	if b < 0 and a > INT_MAX + b: return INF
	return float(a - b)

static func _can_add(a: int, b: int) -> bool:
	return not ((b > 0 and a > INT_MAX - b) or (b < 0 and a < INT_MIN - b))

static func _integer(value: Variant) -> bool:
	if value is int: return true
	return value is float and is_finite(value) and value >= float(INT_MIN) and value < float(INT_MAX) and value == floor(value)

static func _natural(value: Variant) -> bool:
	return _integer(value) and int(value) >= 0

static func _keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true

static func _id(value: Dictionary) -> String:
	return JSON.stringify([value.unit, int(value.slot)])

static func _identity(value: Dictionary) -> Dictionary:
	return {"unit": value.unit, "slot": int(value.slot)}

static func _less(a: Dictionary, b: Dictionary) -> bool:
	return a.unit < b.unit if a.unit != b.unit else int(a.slot) < int(b.slot)

static func _priority_ok(value: Variant) -> bool:
	if not value is Array: return false
	var seen := {}
	for item: Variant in value:
		if not item is Dictionary or not _keys(item, ["unit", "slot"]) or not item.unit is String or not _natural(item.slot): return false
		if seen.has(_id(item)): return false
		seen[_id(item)] = true
	return true

static func _saved_ok(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _keys(value, ["version", "abs_day", "substep", "receipt", "priority"]) or not value.version is String or value.version != "1" \
		or not _decimal(value.abs_day) or not _decimal(value.substep) or not value.receipt is String \
		or not _digest(value.receipt) or not value.priority is Array: return false
	var seen := {}
	for item: Variant in value.priority:
		if not item is Dictionary or not _keys(item, ["unit", "slot"]) or not item.unit is String or not _decimal(item.slot): return false
		var identity := _id(item)
		if seen.has(identity): return false
		seen[identity] = true
	return true

static func _digest(value: String) -> bool:
	if value.length() != 64: return false
	for i: int in value.length():
		if value.substr(i, 1) not in "0123456789abcdef": return false
	return true

static func _decimal(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(int(value)) == value and int(value) >= 0

static func _read_saved(value: Variant) -> Dictionary:
	if not _saved_ok(value): return {}
	var out: Dictionary = value.duplicate(true)
	out.abs_day = int(value.abs_day)
	out.substep = int(value.substep)
	for item: Dictionary in out.priority: item.slot = int(item.slot)
	return out

static func _older(day: int, substep: int, saved: Dictionary) -> bool:
	return day < int(saved.abs_day) or (day == int(saved.abs_day) and substep < int(saved.substep))

static func _hash(value: Variant) -> String:
	return JSON.stringify(_canonical(value)).sha256_text()

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var out := {}
		for key: Variant in keys: out[key] = _canonical(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value: out.append(_canonical(item))
		return out
	if value is float and _integer(value): return int(value)
	return value

static func _error(reason: String) -> Dictionary:
	return {"moves": [], "blocked": [], "reasons": {"error": reason}, "cursor": {}}

static func _failure(reason: String) -> Dictionary:
	return {"status": "error", "reason": reason}

static func _validate(repo: DataRepository, state: GameState, boundary: Dictionary) -> Dictionary:
	return UnitBodies.migrate_candidate(repo, state) if boundary.is_empty() else UnitBodies.validate_march_candidate(repo, state, boundary)
