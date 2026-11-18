class_name BodyLoad
extends RefCounted
## ACT-LOAD: a new campaign's first bodies and the classification of a loaded save. Inactive:
## no ordinary boot or load path calls it until ACT-CUTOVER; publishing the candidate is the
## driver's. Its own file: `unit_bodies.gd` is a SHA-256-pinned premise of the royal carrier proof.

## CURRENT: complete current bodies, kept exactly. LEGACY: a lawful save from before bodies —
## every saved row valid, on legal ground and clear of the others; its rows are kept (under the
## foundation's legacy regroup) and only its missing poses are placed. DEFERRED: a frozen
## day/round, a v2 completion proof or a staged recruit — not judged yet; its own consumer
## finishes it and the save is classified again at the next safe boundary. REFUSED: overlapping,
## corrupt, off legal ground, an unsupported version or no room for a missing pose; nothing loads.
const CURRENT := "current"
const LEGACY := "legacy"
const DEFERRED := "deferred"
const REFUSED := "refused"

## Pure: `{kind, reason, units}`, `units` the land units a LEGACY load gives bodies (sorted).
## It runs the same proof `load_candidate` does, so the two always agree.
static func classify(repo: DataRepository, source: GameState) -> Dictionary:
	return _classified(repo, source).kind

## A new campaign's bodies: every land unit placed once at its saved anchor through the
## proven placement (homes, then the finite camp lattice, against terrain and every other
## body). Returns the placement's five-field result; a state with a body control errors.
static func initialize_campaign(repo: DataRepository, fresh: GameState) -> Dictionary:
	if repo == null or fresh == null: return ArmyGround._placement_result("error", "Initialization requires data and a campaign")
	for key: String in ["body_version", "body_placement"]:
		if fresh.military_migration.has(key): return ArmyGround._placement_result("error", "A new campaign has no bodies yet")
	return ArmySplit.initialize_bodies_candidate(repo, fresh, "placement:new_campaign", "0")

## A loaded save's body world, detached: `{status, reason, error, candidate, kind}`. CURRENT
## is the save itself; LEGACY is the converted save with its missing entries seeded and missing
## poses placed (`initialize`, `placement:load`, sequence 0); DEFERRED and REFUSED return none.
## The source is never touched.
static func load_candidate(repo: DataRepository, source: GameState) -> Dictionary:
	var classified := _classified(repo, source)
	var kind: Dictionary = classified.kind
	var status: String = {CURRENT: "complete", LEGACY: "complete", DEFERRED: "deferred", REFUSED: "error"}[kind.kind]
	return {"status": status, "reason": kind.reason, "error": kind.reason if status == "error" else "",
		"candidate": classified.get("candidate"), "kind": kind.kind}

static func _classified(repo: DataRepository, source: GameState) -> Dictionary:
	if repo == null or source == null: return _kind(REFUSED, "Load classification requires data and a save")
	var migration: Dictionary = source.military_migration
	if migration.has("body_placement") and not UnitBodies._placement_control_ok(migration.body_placement):
		return _kind(REFUSED, "Invalid saved placement control")
	if migration.get("body_placement", {}).get("version") == "2" and not source.day_resolution.is_empty():
		return _kind(DEFERRED, "frozen_transaction: completion proof requires its placement consumer")
	var migrated := UnitBodies.migrate_candidate(repo, source)
	match migrated.status:
		"error": return _kind(REFUSED, migrated.reason)
		"deferred": return _kind(DEFERRED, migrated.reason)
	for request: Dictionary in migrated.placement_requests:
		if request.reason != "legacy_missing_pose":
			return _kind(DEFERRED, "pending_personnel_boundary: explicit recruit transaction required")
	var current := migration.has("body_version")
	if not current and migration.has("body_placement"): return _kind(REFUSED, "Placement control without current bodies")
	var boundary := {"version": 1, "kind": "safe", "abs_day": str(source.absolute_day())}
	var candidate := UnitBodies._copy(source)
	var units: Array[String] = []
	if not current:
		# The new campaign's own rule: a land roster unit with no entry is seeded at its pack
		# anchor (`ArmySystem.starting_state`), and every missing pose is placed; saved rows stay.
		var placed := ArmyGround.body_placement_candidate(repo, source, {"version": 1, "operation_id": "placement:load",
			"sequence": "0", "operation": "initialize", "unit": "", "host": "", "previous_fit": null}, boundary)
		if placed.status != "complete": return _kind(REFUSED, placed.reason)
		candidate = placed.candidate
		var placed_units := {}
		for row: Dictionary in placed.plan.placements: placed_units[row.unit] = true
		units.assign(placed_units.keys())
		units.sort()
	# Every kept row, current or legacy, faces the placement's own provenance and terrain proof.
	var checked := UnitBodies.validate_placement_candidate(repo, candidate, boundary)
	if checked.status != "complete": return _kind(REFUSED, checked.reason)
	var grid := MarchPath.of_pack(repo)
	if not ArmyGround._placement_grid_ok(grid): return _kind(REFUSED, "Load requires a valid land terrain grid")
	var terrain := ArmyGround._placement_terrain_error(repo, candidate, grid)
	if not terrain.is_empty(): return _kind(REFUSED, terrain)
	if current: return {"kind": {"kind": CURRENT, "reason": "Current bodies kept exactly", "units": units}, "candidate": candidate}
	return {"kind": {"kind": LEGACY, "reason": "Lawful legacy save", "units": units}, "candidate": candidate}

static func _kind(kind: String, reason: String) -> Dictionary:
	return {"kind": {"kind": kind, "reason": reason, "units": [] as Array[String]}}
