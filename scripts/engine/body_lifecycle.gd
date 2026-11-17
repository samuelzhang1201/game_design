class_name BodyLifecycle
extends RefCounted
## ACT-LIFECYCLE: every battle lifecycle edge (start, join, merge, exit, end) on an admitted
## body world as an exact zero-delta ownership transfer. Inactive: no ordinary dispatcher
## calls it until ACT-CUTOVER installs it with the driver and the projection.

## The closed `BodyBattle` requests that carry a lifecycle edge (`contacts` starts, joins and merges).
const EDGES: Array[String] = ["contacts", "enter", "merge", "withdraw", "end", "cancel"]

## Commits one edge's `BodyBattle.plan_candidate` plan, then proves its continuity. A failed
## proof returns an error and no candidate, so nothing publishes; the source is never touched.
## A retry of the committed plan replays through `BodyBattle`'s receipt and must move nothing.
static func commit_candidate(repo: DataRepository, source: GameState, plan: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or not plan.get("request") is Dictionary or not plan.request.get("kind") in EDGES:
		return BodyBattleMotion._result("error", "Not a body lifecycle edge")
	var replay: bool = _outer(source).get("receipt") == BodyMotion._hash(plan)
	var committed := BodyBattle.commit_candidate(repo, source, plan, boundary)
	if committed.status != "complete" or committed.candidate == null: return committed
	var moved := continuity_error(source, committed.candidate, {"kind": "replay"} if replay else plan.request)
	if not moved.is_empty(): return BodyBattleMotion._result("error", moved)
	return committed

## Every land unit's bodies by stable identity, whichever container owns them: rows by slot,
## anchor, facing, next slot and owner battle (0 = nonbattle). Empty when ownership is invalid.
static func snapshot(state: GameState) -> Dictionary:
	var index := UnitBodies._owners(state)
	if not index.error.is_empty(): return {}
	var out := {}
	for code: String in index.codes:
		if UnitBodies._naval(state, code): continue
		var entry := UnitBodies._entry(state, code)
		var battle: Dictionary = index.owners.get(code, {})
		var inside := not battle.is_empty()
		var store: Variant = battle.get("groups", {}).get(code) if inside else entry.get("body_groups")
		var rows: Variant = null
		if store is Array:
			rows = {}
			for row: Variant in store:
				if not row is Dictionary or rows.has(str(row.get("slot"))): return {}
				rows[str(row.get("slot"))] = row
		out[code] = {"owner": int(battle.get("id", 0)), "rows": rows, "next_slot": entry.get("group_next_slot"),
			"unit_facing": entry.get("facing_deg"),
			"anchor": battle.get("group_anchor_m", {}).get(code) if inside else entry.get("group_anchor_m"),
			"facing": battle.get("group_facing", {}).get(code) if inside else entry.get("group_facing")}
	return out

## "" when `after` holds every surviving (unit, slot) exactly as `before` (point, facing, count,
## home, role, path), with the same anchors, facings, slot high water, cursor, personnel and RNG,
## and only the owners the edge `request` may move; else the first difference.
static func continuity_error(before: GameState, after: GameState, request: Dictionary) -> String:
	var a := snapshot(before)
	var b := snapshot(after)
	if a.is_empty() or b.is_empty(): return "Lifecycle requires one valid body owner per unit"
	if a.keys() != b.keys(): return "Lifecycle changed the body roster"
	for code: String in a:
		if (a[code].rows == null) != (b[code].rows == null): return "Lifecycle created or dropped the body store of " + code
		if a[code].rows != null:
			if a[code].rows.keys() != b[code].rows.keys(): return "Lifecycle renumbered, added or retired a body of " + code
			for slot: String in a[code].rows:
				if BodyMotion._hash(a[code].rows[slot]) != BodyMotion._hash(b[code].rows[slot]): return "Lifecycle moved body %s:%s" % [code, slot]
		for field: String in ["anchor", "facing", "unit_facing", "next_slot"]:
			if BodyMotion._hash(a[code][field]) != BodyMotion._hash(b[code][field]): return "Lifecycle changed the %s of %s" % [field, code]
	var owners := _owner_error(after, request, a, b)
	if not owners.is_empty(): return owners
	if BodyMotion._hash(before.military_cohorts) != BodyMotion._hash(after.military_cohorts) \
		or BodyMotion._hash(before.rng.to_dict()) != BodyMotion._hash(after.rng.to_dict()):
		return "Lifecycle changed personnel or RNG"
	# The cursor stays, or the contact stage closes it into exactly `closed_motion`; nothing else.
	var cursor: Variant = before.military_migration.get("body_motion")
	var now: Variant = after.military_migration.get("body_motion")
	var closed: Variant = _outer(after).get("closed_motion", {})
	if BodyMotion._hash(now) != BodyMotion._hash(cursor):
		var expected: Variant = cursor.duplicate(true) if cursor is Dictionary else null
		if expected is Dictionary: expected.erase("plan")
		if now != null or expected == null or BodyMotion._hash(closed) != BodyMotion._hash(expected): return "Lifecycle lost the motion cursor"
	elif BodyMotion._hash(closed) != BodyMotion._hash(_outer(before).get("closed_motion", {})): return "Lifecycle changed the closed motion cursor"
	return ""

## A unit keeps its owner (an absorbed field's alias names its survivor) unless the edge moves it:
## enter moves its unit in, withdraw its unit out, end/cancel every member out, contacts may enroll;
## a `replay` moves no one.
static func _owner_error(after: GameState, request: Dictionary, a: Dictionary, b: Dictionary) -> String:
	var id := int(request.get("battle_id", "0"))
	for code: String in a:
		var was: int = a[code].owner
		var now: int = b[code].owner
		var mover := false
		match request.kind:
			"enter": mover = code == request.unit
			"withdraw": mover = code == request.unit
			"end", "cancel": mover = was == id
		if mover:
			var target := id if request.kind == "enter" else 0
			if now != target or was == target: return "Lifecycle did not move the owner of " + code
		elif now != (BattleSystem.canonical(after, was) if was > 0 else 0) and not (request.kind == "contacts" and was == 0 and now > 0):
			return "Unlawful body owner change: " + code
	return ""

static func _outer(state: GameState) -> Dictionary:
	var outer: Variant = state.military_migration.get("body_battle", {})
	return outer if outer is Dictionary else {}
