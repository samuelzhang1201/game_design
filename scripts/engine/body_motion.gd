class_name BodyMotion
extends RefCounted
## Explicit isolated candidates only. Production movement does not call this API.

# Local arithmetic is bounded for double-precision sweep predicates, not world positions.
const LOCAL_LIMIT: int = 67108864
const INT_MIN: int = -9223372036854775807 - 1
const INT_MAX: int = 9223372036854775807

static func plan(repo: DataRepository, state: GameState, intents: Array, abs_day: int, substep: int, march_boundary: Dictionary = {}) -> Dictionary:
	return _plan(repo, state, intents, abs_day, substep, march_boundary, false)

static func _plan(repo: DataRepository, state: GameState, intents: Array, abs_day: int, substep: int, march_boundary: Dictionary, battle: bool) -> Dictionary:
	if repo == null or state == null or abs_day < 0 or substep < 0: return _error("Invalid motion source/cursor")
	var validated := _battle_source(repo, state, march_boundary) if battle else _validate(repo, state, march_boundary)
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
	return _sweep_collision(a, _segments(ap, a.budget_m), b, _segments(bp, b.budget_m))

static func _sweep_collision(a: Dictionary, segments_a: Array[Dictionary], b: Dictionary, segments_b: Array[Dictionary]) -> bool:
	var radius: float = a.radius + b.radius
	var reach: float = a.budget_m + b.budget_m + radius
	if absf(_difference(segments_a[0].a[0], segments_b[0].a[0])) > reach or absf(_difference(segments_a[0].a[1], segments_b[0].a[1])) > reach: return false
	for sa: Dictionary in segments_a:
		for sb: Dictionary in segments_b:
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

# Unsigned base-2^15 limbs keep every intermediate product within int64.
# Used only for the rounding proof; no limb or approximation enters a save.
class _Nat:
	static func trim(a: Array) -> Array:
		while a.size() > 1 and a.back() == 0: a.pop_back()
		return a

	static func of(value: int) -> Array:
		var a: Array = []
		while value > 0:
			a.append(value & 32767)
			value >>= 15
		return a if not a.is_empty() else [0]

	static func cmp(a: Array, b: Array) -> int:
		if a.size() != b.size(): return 1 if a.size() > b.size() else -1
		for i: int in range(a.size() - 1, -1, -1):
			if a[i] != b[i]: return 1 if a[i] > b[i] else -1
		return 0

	static func add(a: Array, b: Array) -> Array:
		var out: Array = []
		var carry := 0
		for i: int in maxi(a.size(), b.size()):
			var value: int = int(a[i] if i < a.size() else 0) + int(b[i] if i < b.size() else 0) + carry
			out.append(value & 32767)
			carry = value >> 15
		if carry: out.append(carry)
		return out

	static func sub(a: Array, b: Array) -> Array:
		assert(cmp(a, b) >= 0)
		var out: Array = []
		var borrow := 0
		for i: int in a.size():
			var value: int = int(a[i]) - int(b[i] if i < b.size() else 0) - borrow
			borrow = 1 if value < 0 else 0
			out.append(value & 32767)
		return trim(out)

	static func mul(a: Array, b: Array) -> Array:
		var out: Array = []
		out.resize(a.size() + b.size())
		out.fill(0)
		for i: int in a.size():
			var carry := 0
			for j: int in b.size():
				var value: int = int(out[i + j]) + int(a[i]) * int(b[j]) + carry
				out[i + j] = value & 32767
				carry = value >> 15
			out[i + b.size()] = carry
		return trim(out)

	@warning_ignore("integer_division")
	static func small_div(a: Array, divisor: int) -> Array:
		var out := a.duplicate()
		var remainder := 0
		for i: int in range(a.size() - 1, -1, -1):
			var value: int = (remainder << 15) + int(a[i])
			out[i] = value / divisor
			remainder = value % divisor
		return trim(out)

	static func div(a: Array, b: Array) -> Array:
		assert(b != [0])
		var remainder := a.duplicate()
		var denominator := b.duplicate()
		var count := 0
		while cmp(denominator, remainder) <= 0:
			denominator = mul(denominator, [2])
			count += 1
		var out: Array = [0]
		for i: int in count:
			denominator = small_div(denominator, 2)
			out = mul(out, [2])
			if cmp(remainder, denominator) >= 0:
				remainder = sub(remainder, denominator)
				out = add(out, [1])
		return out

	static func integer(a: Array) -> int:
		var value := 0
		for i: int in range(a.size() - 1, -1, -1):
			if value > (INT_MAX >> 15): return -1
			value = (value << 15) + int(a[i])
		return value

# Fixed-point alternating atan series, |x|<=1/2. Each product is floored.
# Power error is <2 ulps (geometric contraction); input adds <1, each term
# <3 and the first omitted term <3. 8*(N+1)^2 encloses all those errors.
static func _loco_atan(numerator: int, denominator: int, limbs: int) -> Dictionary:
	var scale: Array = []
	scale.resize(limbs + 1)
	scale.fill(0)
	scale[limbs] = 1
	var x := _Nat.div(_Nat.mul(scale, _Nat.of(numerator)), _Nat.of(denominator))
	var square := _Nat.trim(_Nat.mul(x, x).slice(limbs))
	if square.is_empty(): square = [0]
	var power := x
	var sum: Array = [0]
	var index := 0
	while true:
		if index > (((INT_MAX >> 15) - 1) >> 1): return {"value": [0], "error": -1}
		var term := _Nat.small_div(power, 2 * index + 1)
		if term == [0]: break
		sum = _Nat.add(sum, term) if index % 2 == 0 else _Nat.sub(sum, term)
		power = _Nat.trim(_Nat.mul(power, square).slice(limbs))
		if power.is_empty(): power = [0]
		index += 1
	return {"value": sum, "error": _loco_duration(index + 1, 8 * (index + 1), 1)}

static func _locomotion_heading(dx: int, dy: int) -> int:
	if dx < -LOCAL_LIMIT or dx > LOCAL_LIMIT or dy < -LOCAL_LIMIT or dy > LOCAL_LIMIT or (dx == 0 and dy == 0): return -1
	if dy == 0: return 0 if dx > 0 else 180000000
	if dx == 0: return 90000000 if dy > 0 else 270000000
	var x := absi(dx)
	var y := absi(dy)
	if x == y:
		return (45000000 if dy > 0 else 315000000) if dx > 0 else (135000000 if dy > 0 else 225000000)
	var low := mini(x, y)
	var high := maxi(x, y)
	var limbs := 4
	# An integer slope at a rational-degree half bin would make (x+i*y)/
	# (x-i*y) a root of unity in Q(i), hence ±1 or ±i: axes/diagonals,
	# which are integer bins, not half bins. Refinement therefore terminates.
	while true:
		# Machin's identity gives pi without a platform float or saved table.
		var a := _loco_atan(1, 5, limbs)
		var b := _loco_atan(1, 239, limbs)
		if a.error < 0 or b.error < 0 or a.error > (INT_MAX >> 5) or b.error > (INT_MAX >> 5): return -1
		var pi := _Nat.sub(_Nat.mul(a.value, [16]), _Nat.mul(b.value, [4]))
		var pi_error: int = 16 * int(a.error) + 4 * int(b.error)
		var reduced := low * 2 > high
		var angle := _loco_atan(high - low if reduced else low, high + low if reduced else high, limbs)
		var value: Array = angle.value
		var error: int = angle.error
		if error < 0: return -1
		if reduced:
			value = _Nat.sub(_Nat.small_div(pi, 4), value)
			if not _can_add(error, pi_error + 1): return -1
			error += pi_error + 1
		if y > x:
			value = _Nat.sub(_Nat.small_div(pi, 2), value)
			if not _can_add(error, pi_error + 1): return -1
			error += pi_error + 1
		var lower := _Nat.sub(value, _Nat.of(error)) if _Nat.cmp(value, _Nat.of(error)) >= 0 else [0]
		var upper := _Nat.add(value, _Nat.of(error))
		var pi_low := _Nat.sub(pi, _Nat.of(pi_error))
		var pi_high := _Nat.add(pi, _Nat.of(pi_error))
		var lo := _Nat.integer(_Nat.div(_Nat.add(_Nat.mul(lower, _Nat.of(360000000)), pi_high), _Nat.mul(pi_high, [2])))
		var hi := _Nat.integer(_Nat.div(_Nat.add(_Nat.mul(upper, _Nat.of(360000000)), pi_low), _Nat.mul(pi_low, [2])))
		if lo < 0 or hi < 0: return -1
		if lo == hi:
			var heading := lo if dx > 0 else 180000000 - lo
			return posmod(heading if dy > 0 else -heading, 360000000)
		if limbs > (INT_MAX >> 1): return -1
		limbs *= 2
	return -1

const LOCOMOTION_Q: int = 1000000
const LOCOMOTION_TURN: int = 360000000
const JSON_INTEGER_MAX: int = 9007199254740991

static func _loco_integer(value: Variant) -> bool:
	return _integer(value) and value >= -JSON_INTEGER_MAX and value <= JSON_INTEGER_MAX

static func _loco_point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _loco_integer(value[0]) and _loco_integer(value[1])

static func _loco_turn(start: int, finish: int) -> int:
	var turn := posmod(finish - start + 180000000, LOCOMOTION_TURN) - 180000000
	return 180000000 if turn == -180000000 else turn

@warning_ignore("integer_division")
static func _loco_duration(amount: int, rate: int, divisor: int) -> int:
	if amount < 0 or rate <= 0 or divisor <= 0 or (amount > 0 and rate > INT_MAX / amount): return -1
	var product := amount * rate
	return product / divisor + (1 if product % divisor else 0)

static func _loco_policy(repo: DataRepository, piece: String) -> Dictionary:
	var turn: Variant = repo.balance.get("body_locomotion_" + piece + "_turn_q")
	var contact: Variant = repo.balance.get("body_locomotion_" + piece + "_contact_um")
	var raw: Variant = repo.unit_footprints.get(piece, {}).get("locomotion_certificate")
	if not _loco_integer(turn) or turn <= 0 or _loco_duration(180000000, int(turn), LOCOMOTION_TURN) < 0 \
		or not _loco_integer(contact) or contact <= 0 or not raw is Dictionary: return {}
	if not _keys(raw, ["digest", "turn_q", "contact_um", "radius_m", "clips", "all_turns"]) \
		or not raw.digest is String or not _digest(raw.digest) or not _loco_integer(raw.turn_q) \
		or not _loco_integer(raw.contact_um) or raw.turn_q != turn or raw.contact_um != contact \
		or not _loco_integer(raw.radius_m) or raw.radius_m <= 0 or raw.radius_m > LOCAL_LIMIT or raw.radius_m != repo.unit_footprints[piece].radius_m \
		or not raw.all_turns is bool or not raw.all_turns \
		or not raw.clips is Array or raw.clips != ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"]: return {}
	return _canonical(raw)

static func _loco_op(kind: String, t0: int, t1: int, a: Array, b: Array, yaw: int, turn: int = 0) -> Dictionary:
	return {"kind": kind, "t0_q": t0, "t1_q": t1, "a": a.duplicate(), "b": b.duplicate(), "yaw0_udeg": yaw, "turn_udeg": turn}

static func _loco_timeline(body: Dictionary, path: Array, turn_q: int) -> Dictionary:
	var ops: Array = []
	var time := 0
	var yaw: int = body.start_yaw_udeg
	var here: Array = body.start.duplicate()
	var used := 0
	var final_yaw: int = body.final_facing_deg * LOCOMOTION_Q
	for i: int in range(1, path.size()):
		if here == path[i]: continue
		var distance := _distance_ceil(here, path[i])
		if distance > body.budget_m - used: break
		var dx := int(_difference(path[i][0], here[0]))
		var dy := int(_difference(path[i][1], here[1]))
		var heading := _locomotion_heading(dx, dy)
		if heading < 0: return {}
		var move_time := _loco_duration(distance, LOCOMOTION_Q, body.budget_m)
		var turn := _loco_turn(yaw, heading)
		var pivot_time := _loco_duration(absi(turn), turn_q, LOCOMOTION_TURN)
		var final_time := _loco_duration(absi(_loco_turn(heading, final_yaw)), turn_q, LOCOMOTION_TURN)
		if move_time <= 0 or pivot_time < 0 or final_time < 0 or distance > body.budget_m - used \
			or move_time > LOCOMOTION_Q - time - pivot_time - final_time: break
		if turn:
			ops.append(_loco_op("pivot", time, time + pivot_time, here, here, yaw, turn))
			time += pivot_time
		ops.append(_loco_op("move", time, time + move_time, here, path[i], heading))
		time += move_time
		yaw = heading
		here = path[i].duplicate()
		used += distance
	var finish_turn := _loco_turn(yaw, final_yaw)
	if finish_turn:
		var duration := _loco_duration(absi(finish_turn), turn_q, LOCOMOTION_TURN)
		if duration <= 0 or duration > LOCOMOTION_Q - time: return {}
		ops.append(_loco_op("pivot", time, time + duration, here, here, yaw, finish_turn))
		time += duration
	if time < LOCOMOTION_Q: ops.append(_loco_op("hold", time, LOCOMOTION_Q, here, here, final_yaw))
	return {"unit": body.unit, "slot": body.slot, "start": body.start.duplicate(), "end": here,
		"start_yaw_udeg": body.start_yaw_udeg, "final_facing_deg": body.final_facing_deg,
		"budget_m": body.budget_m, "used_m": used, "ops": ops}

static func _loco_path(move: Dictionary) -> Array:
	var path: Array = [move.start.duplicate()]
	for op: Dictionary in move.ops:
		if op.kind == "move": path.append(op.b.duplicate())
	return path

@warning_ignore("integer_division")
static func _loco_prefix(path: Array, budget: int) -> Array:
	var out: Array = [path[0].duplicate()]
	for i: int in range(1, path.size()):
		var length := _distance_ceil(path[i - 1], path[i])
		if length == 0: continue
		if length <= budget:
			out.append(path[i].duplicate())
			budget -= length
		else:
			# Checked local deltas and budget bound this product below 2^53.
			var dx: int = int(_difference(path[i][0], path[i - 1][0])) * budget / length
			var dy: int = int(_difference(path[i][1], path[i - 1][1])) * budget / length
			if dx or dy: out.append([int(path[i - 1][0]) + dx, int(path[i - 1][1]) + dy])
			break
	return out

static func _loco_segments(move: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for op: Dictionary in move.ops:
		out.append({"a": op.a, "b": op.b, "t0": float(op.t0_q) / LOCOMOTION_Q, "t1": float(op.t1_q) / LOCOMOTION_Q})
	return out

@warning_ignore("integer_division")
static func _loco_grid_ok(grid: MarchPath) -> bool:
	if grid == null or grid.cols <= 0 or grid.rows <= 0 or grid.cell_m <= 0 or grid.water_open: return false
	if grid.cols > INT_MAX / grid.rows or grid.cols > INT_MAX / grid.cell_m or grid.rows > INT_MAX / grid.cell_m: return false
	return grid.closed.size() == grid.cols * grid.rows and grid.water.size() == grid.closed.size()

static func _loco_clear(index: int, move: Dictionary, bodies: Array[Dictionary], grid: MarchPath) -> bool:
	if move.is_empty() or not ArmySystem._body_path_terrain(grid, _loco_path(move), bodies[index].radius).is_empty(): return false
	for other: int in bodies.size():
		if index != other and _sweep_collision(bodies[index], _loco_segments(move), bodies[other], _loco_segments(bodies[other].move)): return false
	return true

static func _loco_context(repo: DataRepository, grid: MarchPath, policy: Dictionary, boundary: Dictionary) -> Array:
	return [repo.unit_footprints, repo.balance, policy, boundary, repo.world_table("political", "diplomacy"),
		grid.cols, grid.rows, grid.cell_m, Array(grid.closed), Array(grid.water), grid.water_open]

static func _loco_result_hash(state: GameState, context: Array) -> String:
	var saved := state.to_dict()
	saved.military_migration.erase("body_motion")
	return _hash([saved, context])

static func _loco_apply(state: GameState, moves: Array) -> void:
	for move: Dictionary in moves:
		for row: Dictionary in _owned_rows(state, move.unit):
			if int(row.slot) != int(move.slot): continue
			row.x_m = int(move.end[0])
			row.y_m = int(move.end[1])
			row.facing_deg = int(move.final_facing_deg)
			row.path_m = _loco_path(move)

static func _loco_boundary_ok(boundary: Dictionary, abs_day: int, substep: int) -> bool:
	if boundary.is_empty(): return true
	if not _keys(boundary, ["version", "abs_day", "substep"]): return false
	for key: String in boundary:
		if not _loco_integer(boundary[key]) or boundary[key] < 0: return false
	return boundary.version == 2 and boundary.abs_day == abs_day and boundary.substep == substep

static func plan_locomotion_candidate(repo: DataRepository, state: GameState, intents: Array, abs_day: int, substep: int, march_boundary: Dictionary = {}) -> Dictionary:
	return _plan_locomotion(repo, state, intents, abs_day, substep, march_boundary, false)

static func plan_battle_locomotion_candidate(repo: DataRepository, state: GameState, intents: Array, boundary: Dictionary) -> Dictionary:
	if not _battle_boundary_ok(boundary): return _error("Invalid battle movement boundary")
	return _plan_locomotion(repo, state, intents, int(boundary.abs_day), int(boundary.substep), boundary, true)

static func _plan_locomotion(repo: DataRepository, state: GameState, intents: Array, abs_day: int, substep: int, march_boundary: Dictionary, battle: bool) -> Dictionary:
	if repo == null or state == null or not _loco_integer(abs_day) or not _loco_integer(substep) or abs_day < 0 or substep < 0:
		return _error("Invalid locomotion source/cursor")
	if not (_battle_boundary_ok(march_boundary) if battle else _loco_boundary_ok(march_boundary, abs_day, substep)): return _error("Unsupported/mixed locomotion boundary")
	var validated := _battle_source(repo, state, march_boundary) if battle else _validate(repo, state, march_boundary)
	if validated.status != "complete" or not state.military_migration.has("body_version"): return _error("Locomotion requires initialized complete bodies")
	if not march_boundary.is_empty() and (int(march_boundary.abs_day) != abs_day or int(march_boundary.substep) != substep): return _error("Locomotion boundary mismatch")
	var saved: Variant = state.military_migration.get("body_motion")
	if state.military_migration.has("body_motion"):
		if battle: return _error("Battle movement requires the previous timeline to be closed")
		if not _loco_saved_source_ok(repo, state, saved, march_boundary): return _error("Invalid saved locomotion control")
		if _older(abs_day, substep, saved) or (int(saved.abs_day) == abs_day and int(saved.substep) == substep): return _error("Locomotion cursor already committed")
	var grid := MarchPath.of_pack(repo)
	if not _loco_grid_ok(grid): return _error("Locomotion requires valid land terrain")
	var candidate: GameState = validated.candidate
	# Reuse v1's closed-world/intent admission only. Its selected geometry and
	# distance-time sweep are discarded; every v2 operation is reserved below.
	candidate.military_migration.erase("body_motion")
	var admitted := _plan(repo, candidate, intents, abs_day, substep, march_boundary, battle)
	if admitted.cursor.is_empty(): return admitted
	var canonical_intents: Array = admitted.cursor.intents
	for intent: Dictionary in canonical_intents:
		if not _loco_integer(intent.slot) or not _loco_integer(intent.budget_m): return _error("Unsafe JSON motion integer")
		for point: Array in intent.path_m:
			if not _loco_point(point): return _error("Unsafe JSON motion coordinate")
			if intent.budget_m == 0 and point != intent.path_m[0]: return _error("Zero budget cannot request translation")
	var bodies: Array[Dictionary] = []
	var lookup := {}
	var policies := {}
	var codes: Array = state.regiments.keys() + state.foes.keys()
	codes.sort()
	for code: String in codes:
		if ArmySystem.is_naval(repo, state, code): continue
		var piece := MapObjects.army_piece(repo, state.army_roster[code])
		var policy := _loco_policy(repo, piece)
		if policy.is_empty(): return _error("Unsupported locomotion policy/certificate: " + piece)
		policies[piece] = policy
		for row: Dictionary in UnitBodies.rows(repo, state, code):
			if not _loco_point([row.x_m, row.y_m]) or not _loco_integer(row.slot): return _error("Unsafe JSON body coordinate/identity")
			var body := {"unit": code, "slot": int(row.slot), "start": [int(row.x_m), int(row.y_m)],
				"start_yaw_udeg": int(row.facing_deg) * LOCOMOTION_Q, "final_facing_deg": int(row.facing_deg),
				"budget_m": 0, "radius": int(repo.unit_footprints[piece].radius_m), "turn_q": int(policy.turn_q),
				"hostile": false, "realm": str(state.army_roster[code].get("kingdom_code", "")), "enemies": []}
			for other: String in codes:
				if ArmySystem._body_enemies(repo, state, code, other): body.enemies.append(other)
			body.path_m = [body.start.duplicate()]
			body.move = _loco_timeline(body, body.path_m, body.turn_q)
			lookup[_id(body)] = bodies.size()
			bodies.append(body)
	var ordered := canonical_intents.duplicate(true)
	var priority: Array = [] if saved == null else saved.priority.duplicate(true)
	for identity: Dictionary in priority: identity.slot = int(identity.slot)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ai := priority.find(_identity(a))
		var bi := priority.find(_identity(b))
		if ai != bi: return (ai if ai >= 0 else priority.size()) < (bi if bi >= 0 else priority.size())
		return _less(a, b))
	for intent: Dictionary in ordered:
		var body: Dictionary = bodies[lookup[_id(intent)]]
		body.budget_m = intent.budget_m
		body.hostile = intent.hostile
	var reasons := {}
	var next_priority: Array = []
	for intent: Dictionary in ordered:
		var index: int = lookup[_id(intent)]
		var body: Dictionary = bodies[index]
		if battle and not ArmySystem._body_path_terrain(grid, intent.path_m, body.radius).is_empty():
			return _error("Battle intent crosses forbidden terrain")
		var move := _loco_timeline(body, intent.path_m, body.turn_q)
		if move.is_empty(): return _error("Unsafe locomotion heading/arithmetic")
		var selected := move if _loco_clear(index, move, bodies, grid) else {}
		if selected.is_empty() and not body.hostile and _friendly_obstacles(index, bodies):
			var radius: int = body.radius
			for other: Dictionary in bodies: radius = maxi(radius, int(other.radius))
			for attempt: int in int(repo.bal("cluster_motion_detour_attempts")):
				@warning_ignore("integer_division")
				var offset: int = (int(body.radius) + radius + int(repo.bal("cluster_motion_clearance_m"))) * (1 + attempt / 2)
				var path := _detour(intent.path_m, -offset if attempt % 2 else offset)
				if path.is_empty(): continue
				move = _loco_timeline(body, path, body.turn_q)
				if not move.is_empty() and move.end == path.back() and _loco_clear(index, move, bodies, grid):
					selected = move
					break
		if selected.is_empty():
			var low := 0
			var high := mini(_length(intent.path_m), body.budget_m)
			while low <= high:
				@warning_ignore("integer_division")
				var middle: int = low + (high - low) / 2
				move = _loco_timeline(body, _loco_prefix(intent.path_m, middle), body.turn_q)
				if _loco_clear(index, move, bodies, grid):
					selected = move
					low = middle + 1
				else: high = middle - 1
		if selected.is_empty(): return _error("No valid complete stationary reservation")
		body.move = selected
		body.path_m = _loco_path(selected)
		if selected.end != intent.path_m.back(): reasons[_id(body)] = "Waiting: no complete timed swept-clear route within the slice"
		if selected.used_m > 0 and not body.hostile: next_priority.append(_identity(body))
	var moves: Array = []
	for index: int in bodies.size():
		if not _loco_clear(index, bodies[index].move, bodies, grid): return _error("Final timed reservation failed")
		moves.append(bodies[index].move.duplicate(true))
	moves.sort_custom(_less)
	var context := _loco_context(repo, grid, policies, march_boundary)
	var basis := {"source": _hash([state.to_dict(), canonical_intents, march_boundary, context]) if battle else _hash([state.to_dict(), canonical_intents, abs_day, substep, context]), "result": ""}
	_loco_apply(candidate, moves)
	basis.result = _battle_physical_hash(candidate, context) if battle else _loco_result_hash(candidate, context)
	return {"version": 2, "cursor": {"abs_day": abs_day, "substep": substep, "basis": basis,
		"intents": canonical_intents, "priority": next_priority, "boundary": march_boundary.duplicate(true)},
		"policy_digest": _hash(policies), "moves": moves, "reasons": reasons}

static func _loco_move_ok(raw: Variant) -> bool:
	if not raw is Dictionary or not _keys(raw, ["unit", "slot", "start", "end", "start_yaw_udeg", "final_facing_deg", "budget_m", "used_m", "ops"]): return false
	if not raw.unit is String or raw.unit.is_empty() or not _loco_point(raw.start) or not _loco_point(raw.end): return false
	for key: String in ["slot", "start_yaw_udeg", "final_facing_deg", "budget_m", "used_m"]:
		if not _loco_integer(raw[key]) or raw[key] < 0: return false
	if raw.start_yaw_udeg >= LOCOMOTION_TURN or raw.final_facing_deg >= 360 or raw.budget_m > LOCAL_LIMIT or raw.used_m > raw.budget_m: return false
	if int(raw.start_yaw_udeg) != int(raw.final_facing_deg) * LOCOMOTION_Q: return false
	if not raw.ops is Array or raw.ops.is_empty(): return false
	var time := 0
	var here: Array = raw.start
	var yaw: int = int(raw.start_yaw_udeg)
	var used := 0
	var previous := ""
	for op: Variant in raw.ops:
		if not op is Dictionary or not _keys(op, ["kind", "t0_q", "t1_q", "a", "b", "yaw0_udeg", "turn_udeg"]): return false
		if not op.kind is String or op.kind not in ["hold", "pivot", "move"] or not _loco_point(op.a) or not _loco_point(op.b): return false
		for key: String in ["t0_q", "t1_q", "yaw0_udeg", "turn_udeg"]:
			if not _loco_integer(op[key]): return false
		if op.t0_q != time or op.t1_q <= time or op.t1_q > LOCOMOTION_Q or op.a != here or op.yaw0_udeg != yaw: return false
		for point: Array in [op.a, op.b]:
			for axis: int in 2:
				if absf(_difference(point[axis], raw.start[axis])) > LOCAL_LIMIT: return false
		if op.kind == "move":
			if op.a == op.b or op.turn_udeg != 0: return false
			var heading := _locomotion_heading(int(_difference(op.b[0], op.a[0])), int(_difference(op.b[1], op.a[1])))
			var length := _distance_ceil(op.a, op.b)
			if heading < 0 or heading != yaw or _loco_duration(length, LOCOMOTION_Q, raw.budget_m) != int(op.t1_q) - time: return false
			used += length
			if used > raw.budget_m: return false
		elif op.kind == "pivot":
			if op.a != op.b or op.turn_udeg == 0 or op.turn_udeg <= -180000000 or op.turn_udeg > 180000000: return false
		else:
			if op.a != op.b or op.turn_udeg != 0 or previous == "hold": return false
		yaw = posmod(yaw + int(op.turn_udeg), LOCOMOTION_TURN)
		here = op.b
		time = int(op.t1_q)
		previous = op.kind
	if used == 0 and (raw.ops.size() != 1 or raw.ops[0].kind != "hold"): return false
	return time == LOCOMOTION_Q and here == raw.end and yaw == int(raw.final_facing_deg) * LOCOMOTION_Q and used == raw.used_m

static func _loco_plan_ok(raw: Variant, battle: bool = false) -> bool:
	if not raw is Dictionary or not _keys(raw, ["version", "cursor", "policy_digest", "moves", "reasons"]): return false
	if not _loco_integer(raw.version) or raw.version != 2 or not raw.cursor is Dictionary \
		or not raw.policy_digest is String or not _digest(raw.policy_digest) or not raw.moves is Array or not raw.reasons is Dictionary: return false
	var cursor: Dictionary = raw.cursor
	if not _keys(cursor, ["abs_day", "substep", "basis", "intents", "priority", "boundary"]) \
		or not _loco_integer(cursor.abs_day) or cursor.abs_day < 0 or not _loco_integer(cursor.substep) or cursor.substep < 0 \
		or not cursor.basis is Dictionary or not _keys(cursor.basis, ["source", "result"]) \
		or not cursor.intents is Array or not _priority_ok(cursor.priority) or not cursor.boundary is Dictionary: return false
	if battle:
		if not _battle_boundary_ok(cursor.boundary) or int(cursor.boundary.abs_day) != int(cursor.abs_day) or int(cursor.boundary.substep) != int(cursor.substep): return false
	elif not _loco_boundary_ok(cursor.boundary, int(cursor.abs_day), int(cursor.substep)): return false
	for digest: Variant in cursor.basis.values():
		if not digest is String or not _digest(digest): return false
	var identities := {}
	var preceding: Dictionary = {}
	for move: Variant in raw.moves:
		if not _loco_move_ok(move) or identities.has(_id(move)) or (not preceding.is_empty() and not _less(preceding, move)): return false
		identities[_id(move)] = move
		preceding = move
	for reason: Variant in raw.reasons:
		if not reason is String or not identities.has(reason) or not raw.reasons[reason] is String or raw.reasons[reason].is_empty(): return false
	for identity: Dictionary in cursor.priority:
		if not _loco_integer(identity.slot) or not identities.has(_id(identity)): return false
	var requested := {}
	preceding = {}
	for intent: Variant in cursor.intents:
		if not intent is Dictionary or not _keys(intent, ["unit", "slot", "path_m", "budget_m", "hostile"]) \
			or not intent.unit is String or not _loco_integer(intent.slot) or intent.slot < 0 \
			or not _loco_integer(intent.budget_m) or intent.budget_m < 0 or intent.budget_m > LOCAL_LIMIT \
			or not intent.hostile is bool or not intent.path_m is Array or intent.path_m.is_empty(): return false
		if not identities.has(_id(intent)) or requested.has(_id(intent)) or (not preceding.is_empty() and not _less(preceding, intent)): return false
		for point: Variant in intent.path_m:
			if not _loco_point(point): return false
			if intent.budget_m == 0 and (point[0] != intent.path_m[0][0] or point[1] != intent.path_m[0][1]): return false
		var move: Dictionary = identities[_id(intent)]
		if int(move.budget_m) != int(intent.budget_m): return false
		for axis: int in 2:
			if int(move.start[axis]) != int(intent.path_m[0][axis]): return false
		requested[_id(intent)] = true
		preceding = intent
	for move: Dictionary in raw.moves:
		if not requested.has(_id(move)) and move.budget_m != 0: return false
	return true

static func _loco_saved_ok(raw: Variant, battle: bool = false) -> bool:
	if not raw is Dictionary or not _keys(raw, ["version", "abs_day", "substep", "receipt", "priority", "plan"]) \
		or not raw.version is String or raw.version != "2" or not _decimal(raw.abs_day) or not _decimal(raw.substep) \
		or not raw.receipt is String or not _digest(raw.receipt) or not raw.priority is Array or not _loco_plan_ok(raw.plan, battle): return false
	if int(raw.abs_day) != raw.plan.cursor.abs_day or int(raw.substep) != raw.plan.cursor.substep or raw.receipt != _hash(raw.plan): return false
	var priority: Array = []
	for item: Variant in raw.priority:
		if not item is Dictionary or not _keys(item, ["unit", "slot"]) or not item.unit is String or not _decimal(item.slot): return false
		priority.append({"unit": item.unit, "slot": int(item.slot)})
	return _hash(priority) == _hash(raw.plan.cursor.priority)

static func _loco_saved_endpoints(state: GameState, moves: Array) -> bool:
	var all := {}
	for code: String in state.regiments.keys() + state.foes.keys():
		if UnitBodies._naval(state, code): continue
		for row: Dictionary in _owned_rows(state, code): all[_id({"unit": code, "slot": row.slot})] = row
	if all.size() != moves.size(): return false
	for raw_move: Dictionary in moves:
		var move: Dictionary = _canonical(raw_move)
		var row: Dictionary = all.get(_id(move), {})
		if row.is_empty() or [int(row.x_m), int(row.y_m)] != move.end or int(row.facing_deg) != int(move.final_facing_deg) or row.path_m != _loco_path(move): return false
	return true

static func _loco_saved_source_ok(repo: DataRepository, state: GameState, raw: Variant, boundary: Dictionary) -> bool:
	if _saved_ok(raw): return true
	if not _loco_saved_ok(raw) or not _loco_saved_endpoints(state, raw.plan.moves): return false
	var grid := MarchPath.of_pack(repo)
	if not _loco_grid_ok(grid): return false
	var policies := {}
	for code: String in state.regiments.keys() + state.foes.keys():
		if ArmySystem.is_naval(repo, state, code): continue
		var piece := MapObjects.army_piece(repo, state.army_roster[code])
		var policy := _loco_policy(repo, piece)
		if policy.is_empty(): return false
		policies[piece] = policy
	return _hash(policies) == raw.plan.policy_digest and _loco_receipt_geometry_ok(repo, state, raw.plan.moves, grid, policies, boundary)

static func _loco_receipt_geometry_ok(repo: DataRepository, state: GameState, moves: Array, grid: MarchPath, policies: Dictionary, boundary: Dictionary, battle: bool = false) -> bool:
	var starts := UnitBodies._copy(state)
	var bodies: Array[Dictionary] = []
	for move: Dictionary in moves:
		var piece := MapObjects.army_piece(repo, state.army_roster[move.unit])
		for op: Dictionary in move.ops:
			if op.kind == "pivot" and _loco_duration(absi(int(op.turn_udeg)), int(policies[piece].turn_q), LOCOMOTION_TURN) != int(op.t1_q) - int(op.t0_q): return false
		for row: Dictionary in _owned_rows(starts, move.unit):
			if int(row.slot) == int(move.slot):
				row.x_m = int(move.start[0])
				row.y_m = int(move.start[1])
		bodies.append({"radius": int(repo.unit_footprints[piece].radius_m), "budget_m": int(move.budget_m), "move": move})
	# The sweep's t=0 exception requires an independently validated start world,
	# not merely the saved endpoint world. A matching hash alone is not geometry.
	if (UnitBodies._battle_world(repo, starts) if battle else _validate(repo, starts, boundary)).status != "complete": return false
	for index: int in bodies.size():
		if not _loco_clear(index, moves[index], bodies, grid): return false
	return true

static func commit_locomotion_candidate(repo: DataRepository, state: GameState, proposed: Dictionary, march_boundary: Dictionary = {}) -> Dictionary:
	if repo == null or state == null or not _loco_plan_ok(proposed): return _failure("Invalid locomotion plan schema")
	# JSON parses integral numbers as floats; normalize only after raw validation.
	proposed = _canonical(proposed)
	var cursor: Dictionary = proposed.cursor
	if _hash(cursor.boundary) != _hash(march_boundary): return _failure("Locomotion boundary mismatch")
	var validated := _validate(repo, state, march_boundary)
	if validated.status != "complete" or not state.military_migration.has("body_version"): return _failure("Locomotion requires initialized complete bodies")
	var raw: Variant = state.military_migration.get("body_motion")
	if state.military_migration.has("body_motion"):
		if not _loco_saved_source_ok(repo, state, raw, march_boundary): return _failure("Invalid saved motion control")
		if _older(int(cursor.abs_day), int(cursor.substep), raw): return _failure("Stale locomotion cursor")
		if int(cursor.abs_day) == int(raw.abs_day) and int(cursor.substep) == int(raw.substep):
			if raw.version != "2" or raw.receipt != _hash(proposed): return _failure("Cursor already committed with another protocol/receipt")
			var grid := MarchPath.of_pack(repo)
			if not _loco_grid_ok(grid): return _failure("Invalid retry terrain")
			var policies := {}
			for code: String in state.regiments.keys() + state.foes.keys():
				if ArmySystem.is_naval(repo, state, code): continue
				var piece := MapObjects.army_piece(repo, state.army_roster[code])
				var policy := _loco_policy(repo, piece)
				if policy.is_empty(): return _failure("Unsupported retry policy")
				policies[piece] = policy
			if _hash(policies) != proposed.policy_digest: return _failure("Stale locomotion retry policy")
			if _loco_result_hash(state, _loco_context(repo, grid, policies, march_boundary)) != cursor.basis.result:
				return _failure("Stale locomotion retry state")
			return {"status": "complete", "reason": "Already committed", "candidate": validated.candidate}
	var expected := plan_locomotion_candidate(repo, state, cursor.intents, int(cursor.abs_day), int(cursor.substep), march_boundary)
	if not _loco_plan_ok(expected) or _hash(expected) != _hash(proposed): return _failure("Stale or modified locomotion plan")
	var candidate: GameState = validated.candidate
	_loco_apply(candidate, expected.moves)
	var priority: Array = []
	for identity: Dictionary in cursor.priority: priority.append({"unit": identity.unit, "slot": str(int(identity.slot))})
	candidate.military_migration.body_motion = {"version": "2", "abs_day": str(int(cursor.abs_day)), "substep": str(int(cursor.substep)),
		"receipt": _hash(expected), "priority": priority, "plan": _canonical(expected)}
	var final := _validate(repo, candidate, march_boundary)
	if final.status != "complete" or not _loco_saved_ok(candidate.military_migration.body_motion): return _failure("Locomotion candidate failed final validation")
	return {"status": "complete", "reason": "Committed timed locomotion candidate", "candidate": final.candidate}

static func sample_locomotion_candidate(projected: Dictionary, time_q: int) -> Dictionary:
	var failure := {"status": "error", "reason": "Invalid copied locomotion timeline/time", "rows": []}
	if time_q < 0 or time_q > LOCOMOTION_Q or not _keys(projected, ["version", "moves"]) \
		or not _loco_integer(projected.version) or projected.version != 2 or not projected.moves is Array: return failure
	var rows: Array = []
	var identities := {}
	for move: Variant in projected.moves:
		if not _loco_move_ok(move) or identities.has(_id(move)): return failure
		identities[_id(move)] = true
		var chosen: Dictionary = move.ops.back()
		for op: Dictionary in move.ops:
			if time_q < int(op.t1_q):
				chosen = op
				break
		var share := float(time_q - int(chosen.t0_q)) / float(int(chosen.t1_q) - int(chosen.t0_q))
		rows.append({"unit": move.unit, "slot": int(move.slot), "kind": chosen.kind,
			"x_m": float(chosen.a[0]) + _difference(chosen.b[0], chosen.a[0]) * share,
			"y_m": float(chosen.a[1]) + _difference(chosen.b[1], chosen.a[1]) * share,
			"yaw_udeg": fposmod(float(chosen.yaw0_udeg) + float(chosen.turn_udeg) * share, LOCOMOTION_TURN)})
	return {"status": "complete", "reason": "", "rows": rows}

## Battle TIME is private cost-staged geometry; the outer consumer seals full state.
static func _battle_boundary_ok(boundary: Dictionary) -> bool:
	if not _keys(boundary, ["version", "kind", "abs_day", "substep", "sequence", "stage"]) \
		or not _loco_integer(boundary.version) or boundary.version != 1 or boundary.kind != "battle" or boundary.stage != "move": return false
	for key: String in ["abs_day", "substep", "sequence"]:
		if not DayResolution._body_decimal(boundary[key]): return false
	return int(boundary.sequence) < JSON_INTEGER_MAX

static func _battle_source(repo: DataRepository, state: GameState, boundary: Dictionary) -> Dictionary:
	if repo == null or state == null or not _battle_boundary_ok(boundary): return _failure("Invalid battle motion source")
	var error := UnitBodies._battle_raw_error(state)
	if not error.is_empty(): return _failure(error)
	var control: Dictionary = state.day_resolution.get("body_battle", {})
	if control.is_empty() or control.stage != "move" or boundary.abs_day != control.abs_day \
		or boundary.sequence != control.sequence or boundary.substep != control.next_substep: return _failure("Battle motion cursor mismatch")
	if state.military_migration.has("body_motion"): return _failure("Active timeline must close before another move")
	return UnitBodies._battle_world(repo, state)

static func _battle_physical_hash(state: GameState, context: Array) -> String:
	var index := UnitBodies._owners(state)
	if not index.error.is_empty(): return ""
	var units: Array = []
	var codes: Array = state.regiments.keys() + state.foes.keys()
	codes.sort()
	for code: String in codes:
		if UnitBodies._naval(state, code): continue
		units.append({"unit": code, "owner_id": int(index.owners.get(code, {}).get("id", 0)),
			"group_next_slot": UnitBodies._entry(state, code).group_next_slot, "rows": _owned_rows(state, code)})
	return _hash([{"body_version": state.military_migration.body_version, "units": units}, context])

static func _battle_saved_source_ok(repo: DataRepository, state: GameState, raw: Variant) -> bool:
	if not _loco_saved_ok(raw, true) or not _loco_saved_endpoints(state, raw.plan.moves): return false
	var grid := MarchPath.of_pack(repo)
	if not _loco_grid_ok(grid): return false
	var policies := {}
	for code: String in state.regiments.keys() + state.foes.keys():
		if UnitBodies._naval(state, code): continue
		var piece := MapObjects.army_piece(repo, state.army_roster[code])
		var policy := _loco_policy(repo, piece)
		if policy.is_empty(): return false
		policies[piece] = policy
	var context := _loco_context(repo, grid, policies, raw.plan.cursor.boundary)
	return _hash(policies) == raw.plan.policy_digest \
		and _battle_physical_hash(state, context) == raw.plan.cursor.basis.result \
		and _loco_receipt_geometry_ok(repo, state, raw.plan.moves, grid, policies, raw.plan.cursor.boundary, true)

static func commit_battle_locomotion_candidate(repo: DataRepository, state: GameState, proposed: Dictionary, boundary: Dictionary) -> Dictionary:
	if not _loco_plan_ok(proposed, true) or _hash(proposed.cursor.boundary) != _hash(boundary): return _failure("Invalid battle TIME plan")
	var validated := _battle_source(repo, state, boundary)
	if validated.status != "complete": return _failure(validated.reason)
	var expected := plan_battle_locomotion_candidate(repo, state, proposed.cursor.intents, boundary)
	if not _loco_plan_ok(expected, true) or _hash(expected) != _hash(proposed): return _failure("Stale or modified battle TIME plan")
	var candidate: GameState = validated.candidate
	_loco_apply(candidate, expected.moves)
	var priority: Array = []
	for identity: Dictionary in expected.cursor.priority: priority.append({"unit": identity.unit, "slot": str(int(identity.slot))})
	candidate.military_migration.body_motion = {"version": "2", "abs_day": str(int(expected.cursor.abs_day)),
		"substep": str(int(expected.cursor.substep)), "receipt": _hash(expected), "priority": priority, "plan": _canonical(expected)}
	if UnitBodies._battle_world(repo, candidate).status != "complete" or not _battle_saved_source_ok(repo, candidate, candidate.military_migration.body_motion):
		return _failure("Battle TIME final physical validation failed")
	return {"status": "complete", "reason": "Committed private battle timeline", "candidate": candidate}
