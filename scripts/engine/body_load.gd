class_name BodyLoad
extends RefCounted
## ACT-LOAD: a new campaign's first bodies and the classification of a loaded save. Inactive:
## no ordinary boot or load path calls it until ACT-CUTOVER; publishing the candidate is the
## driver's. Its own file: `unit_bodies.gd` is a SHA-256-pinned premise of the royal carrier proof.

## CURRENT: complete current bodies, kept exactly. LEGACY: a lawful save from before bodies —
## every saved row valid and clear of the others; its rows are kept and only its missing poses
## are placed. DEFERRED: a frozen day/round or a staged recruit keeps its bodies until its own
## boundary. REFUSED: overlapping, corrupt or an unsupported version; nothing loads.
const CURRENT := "current"
const LEGACY := "legacy"
const DEFERRED := "deferred"
const REFUSED := "refused"

## Pure: `{kind, reason, units}`, `units` the land units whose poses are missing (sorted).
## The source is never touched.
static func classify(repo: DataRepository, source: GameState) -> Dictionary:
	return _classified(repo, source).kind

## A new campaign's bodies: every land unit placed once at its saved anchor through the
## proven placement (homes, then the finite camp lattice, against terrain and every other
## body). Returns the placement's five-field result; a source that already has bodies errors.
static func initialize_campaign(repo: DataRepository, fresh: GameState) -> Dictionary:
	if repo == null or fresh == null: return ArmyGround._placement_result("error", "Initialization requires data and a campaign")
	for key: String in ["body_version", "body_placement"]:
		if fresh.military_migration.has(key): return ArmyGround._placement_result("error", "A new campaign has no bodies yet")
	return ArmySplit.initialize_bodies_candidate(repo, fresh, "placement:new_campaign", "0")

## A loaded save's body world, detached: `{status, reason, error, candidate, kind}`. CURRENT
## is the save itself; LEGACY keeps every saved row (point, path, slot, count) and places only
## the missing poses (`legacy_missing`, the next placement sequence); DEFERRED and REFUSED
## return no candidate. A placement that finds no room defers with its reason.
static func load_candidate(repo: DataRepository, source: GameState) -> Dictionary:
	var classified := _classified(repo, source)
	var kind: Dictionary = classified.kind
	match kind.kind:
		REFUSED: return _result("error", kind.reason, REFUSED)
		DEFERRED: return _result("deferred", kind.reason, DEFERRED)
		CURRENT: return _result("complete", kind.reason, CURRENT, UnitBodies._copy(source))
	if kind.units.is_empty(): return _result("complete", kind.reason, LEGACY, classified.candidate)
	var saved: Dictionary = source.military_migration.get("body_placement", {})
	var sequence := "0" if saved.is_empty() else str(int(saved.sequence) + 1)
	var placed := ArmyGround.body_placement_candidate(repo, source, {"version": 1, "operation_id": "placement:load:" + sequence,
		"sequence": sequence, "operation": "legacy_missing", "unit": "", "host": "", "previous_fit": null},
		{"version": 1, "kind": "safe", "abs_day": str(source.absolute_day())})
	if placed.status != "complete": return _result(placed.status, placed.reason, REFUSED if placed.status == "error" else DEFERRED)
	return _result("complete", "Legacy rows kept; missing poses placed", LEGACY, placed.candidate)

static func _classified(repo: DataRepository, source: GameState) -> Dictionary:
	if repo == null or source == null: return {"kind": _kind(REFUSED, "Load classification requires data and a save")}
	if source.military_migration.has("body_placement") and not UnitBodies._placement_control_ok(source.military_migration.body_placement):
		return {"kind": _kind(REFUSED, "Invalid saved placement control")}
	var migrated := UnitBodies.migrate_candidate(repo, source)
	match migrated.status:
		"error": return {"kind": _kind(REFUSED, migrated.reason)}
		"deferred": return {"kind": _kind(DEFERRED, migrated.reason)}
	var units: Array[String] = []
	for request: Dictionary in migrated.placement_requests:
		if request.reason != "legacy_missing_pose":
			return {"kind": _kind(DEFERRED, "pending_personnel_boundary: explicit recruit transaction required")}
		units.append(request.unit)
	if source.military_migration.has("body_version"): return {"kind": _kind(CURRENT, "Current bodies kept exactly")}
	return {"kind": _kind(LEGACY, "Lawful legacy save", units), "candidate": migrated.candidate}

static func _kind(kind: String, reason: String, units: Array[String] = []) -> Dictionary:
	return {"kind": kind, "reason": reason, "units": units}

static func _result(status: String, reason: String, kind: String, candidate: GameState = null) -> Dictionary:
	return {"status": status, "reason": reason, "error": reason if status == "error" else "", "candidate": candidate, "kind": kind}
