class_name ArmyGround
extends RefCounted
## The ground a unit holds (owner 2026-10-07, spec docs/superpowers/specs/
## 2026-10-07-army-split-and-ground-design.md §4; clearance, owner 2026-10-14,
## spec 2026-10-14-unit-clearance-and-scouting-design): every land unit holds
## ground — a column on the march too (`held_taken`), a fleet never — and no
## two stand within the sum of their arms' clearance radii (army_clearance.csv) of each other (MarchClearance, the
## march's side of the rule). Around a centre the camps lie on a hex
## lattice of army_slot_spacing_m, ring by ring (ring k has 6k slots, taken
## from the east counter-clockwise); a unit takes the first free slot at its
## arm's ring (data/army/army_split.csv start_ring) or further out. Ring 0 is a
## town's SEAT, never a camp; in the field it goes to whoever comes first.
## Round a TOWN the camps stand outside the walls (R16, owner 2026-10-08: 城外):
## the arm's ring counts from the first past the town's reach.

## No slot (none free within army_slot_max_rings).
const NONE := Vector2i(-1, -1)
## The walk round a ring from its east corner: to NE, NW, W, SW, SE, E corners.
const _WALK := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	Vector2i(1, 0), Vector2i(1, -1)]


## Ring k's axial cells, east first, counter-clockwise on the map (y down).
static func ring(k: int) -> Array:
	if k <= 0:
		return [Vector2i.ZERO]
	var out: Array = []
	var at := Vector2i(k, 0)
	for side in 6:
		for i in k:
			out.append(at)
			at += _WALK[side]
	return out


## An axial cell's camp in whole metres around `centre_m`.
static func slot_m(centre_m: Vector2i, axial: Vector2i, spacing: int) -> Vector2i:
	return centre_m + Vector2i(int(round(spacing * (axial.x + axial.y * 0.5))),
		int(round(spacing * axial.y * sqrt(3.0) / 2.0)))


## The first ring an arm camps on (data/army/army_split.csv); 1 for an arm with no row.
static func start_ring(repo: DataRepository, arm: String) -> int:
	for row: Dictionary in repo.army_split:
		if String(row["arm"]) == arm:
			return int(row["start_ring"])
	return 1


## Whether the clearance rule is on (army_clearance_on).
static func clearance_on(repo: DataRepository) -> bool:
	return int(repo.bal("army_clearance_on")) > 0


## An arm's clearance radius in whole metres (data/army/army_clearance.csv); 0 off.
static func arm_radius(repo: DataRepository, arm: String) -> int:
	return int(repo.army_clearance.get(arm, 0)) if clearance_on(repo) else 0


## A unit's clearance radius: its chief arm's (a royal unit too); a fleet's 0.
static func unit_radius(repo: DataRepository, reg: Dictionary) -> int:
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return 0
	return arm_radius(repo, MapObjects.regiment_arm(repo, reg))


## The largest radius of any arm.
static func max_radius(repo: DataRepository) -> int:
	var best := 0
	for arm: String in repo.army_clearance:
		best = maxi(best, arm_radius(repo, arm))
	return best


## An empty record of held ground: points bucketed by the pitch.
static func new_taken(repo: DataRepository) -> Dictionary:
	return {"cell": maxi(int(repo.bal("army_slot_spacing_m")), 1), "grid": {}, "max_r": 0}


## Hold the ground at `p_m` with a unit of clearance radius `radius`.
static func take(taken: Dictionary, p_m: Vector2i, radius := 0) -> void:
	var key := _bucket(taken, p_m)
	if not (taken["grid"] as Dictionary).has(key):
		taken["grid"][key] = []
	(taken["grid"][key] as Array).append(Vector3i(p_m.x, p_m.y, radius))
	taken["max_r"] = maxi(int(taken["max_r"]), radius)


static func _bucket(taken: Dictionary, p_m: Vector2i) -> Vector2i:
	var cell := int(taken["cell"])
	return Vector2i(floori(float(p_m.x) / cell), floori(float(p_m.y) / cell))


## Ground a unit of clearance `radius` may camp on: land, not a blocked terrain,
## and no unit held within the sum of the two radii (half a pitch with the rule
## off). `any_terrain` waives the blocked terrains, for a
## town that stands among them (a mountain hold): its camps lie on the
## mountain, the one ground it has.
static func is_free(repo: DataRepository, taken: Dictionary, p_m: Vector2i,
		any_terrain := false, radius := 0) -> bool:
	var px := ArmySystem.metres_to_pack(repo, p_m)
	if MapEconomy.cell_at(repo, px) < 0:
		return false
	if not any_terrain and repo.army_camp_blocked.has(ArmySystem.terrain_at(repo, px)):
		return false
	var on := clearance_on(repo)
	var cell := int(taken["cell"])
	var half := float(cell) / 2.0
	var reach := maxi(1, ceili(float(radius + int(taken["max_r"])) / float(cell))) if on else 1
	var home := _bucket(taken, p_m)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for q: Vector3i in (taken["grid"] as Dictionary).get(home + Vector2i(dx, dy), []):
				var limit := float(radius + q.z) if on else half
				if Vector2(q.x - p_m.x, q.y - p_m.y).length() < limit:
					return false
	return true


## The whole rings a town's reach covers at `pitch`: ceil(reach / pitch), at
## least 1. A town's camps count their arm's ring from the last of them (R16).
static func clear_rings(reach_m: float, pitch: int) -> int:
	return maxi(ceili(reach_m / float(maxi(pitch, 1))), 1)


## A town's reach in metres (data/army/army_town_reach.csv by its group).
static func town_reach_m(repo: DataRepository, town: String) -> float:
	var b: Dictionary = repo.burgs.get(town, {})
	return float(repo.army_town_reach.get(String(b.get("group", "")), 0.0)) * 1000.0


## The first ring a unit of `arm` camps on round `town` ("" in the field).
static func first_ring(repo: DataRepository, arm: String, town: String) -> int:
	if town == "":
		return maxi(start_ring(repo, arm), 1)
	var clear := clear_rings(town_reach_m(repo, town), int(repo.bal("army_slot_spacing_m")))
	return maxi(clear + start_ring(repo, arm) - 1, 1)


## Whether `p_m` lies within `town`'s reach, as ArmySystem.town_at measures it.
static func in_reach(repo: DataRepository, town: String, p_m: Vector2i) -> bool:
	var b: Dictionary = repo.burgs[town]
	var d := ArmySystem.metres_to_pack(repo, p_m).distance_to(Vector2(float(b["x"]), float(b["y"])))
	return d <= ArmySystem.town_reach_px(repo, b)


## The slot a unit of `arm` takes around `centre_m`: in the FIELD (`town` "")
## the centre itself while it is free; else the first free slot at the arm's
## ring (first_ring) or further out, ring by ring — round a town never one
## within its reach, as a ring's mid-sides stand nearer than its corners —
## NONE past army_slot_max_rings. With `near_m` (not NONE) the slot taken is the
## nearest to that point among the FREE slots of the first ring that has any (a
## column halted before a unit camps on the side it came from), the ring's own
## order breaking ties. `from_ring` > 0 starts the search at that ring whatever the arm.
## `max_radius_m` >= 0 bounds every candidate to that circle round the centre.
static func free_slot(repo: DataRepository, centre_m: Vector2i, arm: String, taken: Dictionary,
		town: String, any_terrain := false, near_m := NONE, from_ring := 0, max_radius_m := -1) -> Vector2i:
	var radius := arm_radius(repo, arm)
	if town == "" and is_free(repo, taken, centre_m, any_terrain, radius):
		return centre_m
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(from_ring if from_ring > 0 else first_ring(repo, arm, town), int(repo.bal("army_slot_max_rings")) + 1):
		var best := NONE
		var best_d := -1
		for ax: Vector2i in ring(k):
			var p := slot_m(centre_m, ax, spacing)
			if max_radius_m >= 0 and MarchClearance.dist2(p, centre_m) > max_radius_m * max_radius_m:
				continue
			if town != "" and in_reach(repo, town, p):
				continue
			if is_free(repo, taken, p, any_terrain, radius):
				if near_m == NONE:
					return p
				var d := MarchClearance.dist2(p, near_m)
				if best_d < 0 or d < best_d:
					best = p
					best_d = d
		if best != NONE:
			return best
	return NONE


## A town's own point (its seat) in whole metres.
static func town_point_m(repo: DataRepository, town: String) -> Vector2i:
	var b: Dictionary = repo.burgs[town]
	return ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))


## --- Seats and camps (spec §4.1, §4.3–4.4) -----------------------------

## The seats in play: the campaign's, else — no state, or a state with no
## roster, as ArmySystem.roster reads it — the pack's opening ones.
static func _seats(repo: DataRepository, state: GameState) -> Dictionary:
	return state.town_seat if state != null and not state.army_roster.is_empty() else ArmySplit.seats_of(repo)


## Whether kingdom `k` holds `town` now (its province's owner) — and no enemy
## host occupies it (a town taken by siege, SiegeSystem.capture: its province
## does not move, yet no unit of the crown's holds its seat or camps by it
## until it is liberated).
static func holds(repo: DataRepository, state: GameState, k: String, town: String) -> bool:
	var b: Dictionary = repo.burgs.get(town, {})
	if b.is_empty() or MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) != k:
		return false
	return state == null or state.ai_hosts.is_empty() \
		or SiegeSystem.occupier_of(state, EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)) == ""


## The unit holding `town`'s seat, "" for an empty one.
static func seat_of(repo: DataRepository, state: GameState, town: String) -> String:
	return String(_seats(repo, state).get(town, ""))


## The town whose seat `code` holds — one its own kingdom holds — else "".
## What earns the works and the garrison's morale. A unit holds one seat at
## most; were it ever on two, the earlier town code is the one.
static func seated_in(repo: DataRepository, state: GameState, code: String) -> String:
	if ArmySystem.is_foe(state, code):
		return ""   # a raised host's unit left its camp (EnemyAi.spawn)
	var seats := _seats(repo, state)
	var found := ""
	for town: String in seats:
		if String(seats[town]) == code and (found == "" or town < found):
			found = town
	if found == "":
		return ""
	var reg := ArmySystem.regiment(repo, code, state)
	return found if not reg.is_empty() and holds(repo, state, String(reg["kingdom_code"]), found) else ""


## The held town a STANDING land unit settled around (R3: the town it camped
## by, `camp_town`), the seat's own town included; "" on the march, in the
## field, afloat, or round a town its kingdom no longer holds. What feeds it.
static func camped_by(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1" or ArmySystem.is_foe(state, code):
		return ""
	var town := String(reg.get("camp_town", ""))
	if state != null and state.regiments.has(code):
		var entry: Dictionary = state.regiments[code]
		if String(entry.get("order", "")) == ArmySystem.ORDER_MARCH:
			return ""
		town = String(entry.get("camp_town", ""))
	return town if town != "" and holds(repo, state, String(reg["kingdom_code"]), town) else ""


## The town a player's land unit DEFENDS (the enemy's town battles and
## sieges, spec 2026-10-07-enemy-ai-and-battle §4.1, §5.1; guide/siege.md):
## the town whose seat it holds (seated_in) or whose camp it stands in
## (camped_by) — a town and its camp are invested together, whatever the
## standing order — else a held town within whose reach it stands under a
## garrison order (a column halted there). Only the seat fights from the
## works (ArmySystem.works_of); the camp fights on the field's ground. ""
## on the march, in the field, and for a foe, a fleet or another kingdom's unit.
static func garrison_town(repo: DataRepository, state: GameState, code: String) -> String:
	if state == null or not state.regiments.has(code):
		return ""
	var order := ArmySystem.order_of(repo, state, code)
	if order == ArmySystem.ORDER_MARCH:
		return ""
	var town := seated_in(repo, state, code)
	if town == "":
		town = camped_by(repo, state, code)
	if town != "" or order != ArmySystem.ORDER_GARRISON:
		return town
	var reg := ArmySystem.regiment(repo, code, state)
	town = ArmySystem.town_of(repo, reg, state)
	return town if town != "" and holds(repo, state, String(reg.get("kingdom_code", "")), town) else ""


## The ground every OTHER land unit holds now, metres — a column on the march
## too (it stands somewhere, and clearance counts it); a fleet none. Built per
## settle (arrivals are rare), never per frame.
static func held_taken(repo: DataRepository, state: GameState, except_code: String) -> Dictionary:
	var taken := new_taken(repo)
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	for c: String in codes:
		var r: Dictionary = all[c]
		if c == except_code or String(r.get("is_naval", "0")) == "1":
			continue
		take(taken, ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, r)), unit_radius(repo, r))
	return taken


static func _put(entry: Dictionary, p_m: Vector2i) -> void:
	entry["x_m"] = p_m.x
	entry["y_m"] = p_m.y
	entry["dest_x_m"] = p_m.x
	entry["dest_y_m"] = p_m.y


## A unit has ARRIVED (ArmySystem.march_day) or halted on the road
## (ArmySystem.set_garrison): it takes an empty seat of a held town it
## stands in the reach of, else the first free slot round the town, or round
## the point it reached in the field — outside the town's reach (R16), on any
## terrain when the free ground is all blocked (a mountain hold, as the split
## places); with none free it holds the point it reached (§4.3). Its
## camp_town is the town, "" in the field. `near_m` (a halt point) makes it the
## camp slot nearest that point (free_slot).
static func settle(repo: DataRepository, state: GameState, code: String, near_m := NONE) -> void:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	if entry.is_empty() or reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var town := ArmySystem.town_at(repo, ArmySystem.metres_to_pack(repo, here))
	if town != "" and not holds(repo, state, String(reg["kingdom_code"]), town):
		town = ""
	entry["camp_town"] = town
	# it takes the newer of its own laws and the camp's (laws spec §2.4)
	LawSystem.on_settle(repo, state, code)
	var centre := town_point_m(repo, town) if town != "" else here
	var taken := held_taken(repo, state, code)
	# the seat is the town's point: taken only while no other unit stands within clearance of it
	if town != "" and seat_of(repo, state, town) == "" \
			and (not clearance_on(repo) or is_free(repo, taken, centre, true, unit_radius(repo, reg))):
		state.town_seat[town] = code
		_put(entry, centre)
		return
	var arm := MapObjects.regiment_arm(repo, reg)
	var slot := free_slot(repo, centre, arm, taken, town, false, near_m)
	if slot == NONE:
		slot = free_slot(repo, centre, arm, taken, town, true, near_m)
	if slot != NONE:
		_put(entry, slot)


## A unit's march order has taken effect (ArmySystem.set_march): it leaves
## its camp and, holding a seat, empties it — refilled from the camp by
## `reconcile` once no unit stands within clearance of the town's point (§4.4).
static func leave(repo: DataRepository, state: GameState, code: String) -> void:
	# what it followed in camp marches on as its own (laws spec §2.4): read
	# while its camp_town still names the camp
	LawSystem.on_leave(repo, state, code)
	if state.regiments.has(code):
		state.regiments[code]["camp_town"] = ""
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		if String(state.town_seat[town]) == code:
			state.town_seat.erase(town)
			if not clearance_on(repo):
				refill(repo, state, town)   # no clearance: the camp steps in at once


## Fill `town`'s empty seat from the units camped round it that are not on
## the march: the most infantry (ties to the earlier code), else the largest.
## The one chosen steps onto the town's point. Returns it, "" for none.
static func refill(repo: DataRepository, state: GameState, town: String) -> String:
	if seat_of(repo, state, town) != "":
		return seat_of(repo, state, town)
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	var pick := ""
	for pass_foot: bool in [true, false]:
		var best := 0
		for c: String in codes:
			if camped_by(repo, state, c) != town:
				continue
			var r: Dictionary = all[c]
			var n := int(float(r.get("infantry", 0))) if pass_foot else int(MapObjects.regiment_personnel(repo, r))
			if n > best:
				best = n
				pick = c
		if pick != "":
			break
	if pick == "":
		return ""
	state.town_seat[town] = pick
	if state.regiments.has(pick):
		_put(state.regiments[pick], town_point_m(repo, town))
	return pick


## ARMY_SEAT delivered (§4.5): `code`, camped by a held town, takes its
## seat; the unit that held it takes the newcomer's camp. False when `code`
## no longer camps by a town — the order lapses.
static func take_seat(repo: DataRepository, state: GameState, code: String) -> bool:
	var town := camped_by(repo, state, code)
	if town == "" or not state.regiments.has(code):
		return false
	var held := seat_of(repo, state, town)
	if held == code:
		return true
	var entry: Dictionary = state.regiments[code]
	var mine := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	state.town_seat[town] = code
	_put(entry, town_point_m(repo, town))
	if held != "" and state.regiments.has(held):
		_put(state.regiments[held], mine)
		state.regiments[held]["camp_town"] = town
	LawSystem.on_settle(repo, state, code)
	return true


## A seat whose town its holder's kingdom no longer holds is cleared, and an
## empty seat of a town with units camped by it is refilled (`refill`) once no
## unit stands within clearance of the town's point (the column that
## left it has marched clear; a day, after the march; spec §4.4).
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		var reg := ArmySystem.regiment(repo, String(state.town_seat[town]), state)
		if reg.is_empty() or not holds(repo, state, String(reg["kingdom_code"]), town):
			state.town_seat.erase(town)
	if not clearance_on(repo):
		return
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	var camps: Dictionary = {}
	for c: String in codes:
		var t := camped_by(repo, state, c)
		if t != "" and seat_of(repo, state, t) == "":
			camps[t] = true
	var empty := camps.keys()
	empty.sort()
	for town: String in empty:
		if is_free(repo, held_taken(repo, state, ""), town_point_m(repo, town), true, max_radius(repo)):
			refill(repo, state, town)

## Isolated opt-in placement. No ordinary lifecycle entry dispatches here.
static func _placement_result(status: String, reason: String, candidate: GameState = null, plan: Dictionary = {}) -> Dictionary:
	return {"status": status, "reason": reason, "error": reason if status == "error" else "", "candidate": candidate, "plan": plan}

static func _placement_request_ok(request: Dictionary) -> bool:
	if not BodyMotion._keys(request, ["version", "operation_id", "sequence", "operation", "unit", "host", "previous_fit"]) \
		or not UnitBodies._whole(request.version) or int(request.version) != 1 or not UnitBodies._placement_id_ok(request.operation_id) \
		or not BodyMotion._decimal(request.sequence) or not request.operation is String or not request.unit is String or not request.host is String: return false
	match request.operation:
		"initialize", "legacy_missing", "reconcile": return request.unit == "" and request.host == "" and request.previous_fit == null
		"recruit": return request.unit != "" and request.host == "" and BodyMotion._decimal(request.previous_fit)
		"settle", "leave", "take_seat", "refill": return request.unit != "" and request.host == "" and request.previous_fit == null
		"enemy_spawn": return request.unit == "" and request.host != "" and request.previous_fit == null
	return false

static func _placement_sequence_error(source: GameState, request: Dictionary, retry: bool = false) -> String:
	if not source.military_migration.has("body_placement"):
		return "" if request.sequence == "0" else "Placement must start at sequence 0"
	var saved: Variant = source.military_migration.body_placement
	if not UnitBodies._placement_control_ok(saved): return "Invalid saved placement control"
	if request.sequence == saved.sequence:
		if request.operation_id != saved.operation_id: return "Placement cursor belongs to another operation"
		return "" if retry else "retry_requires_original_plan"
	if int(saved.sequence) == 0x7fffffffffffffff: return "Placement sequence overflow"
	if int(request.sequence) != int(saved.sequence) + 1: return "Stale or skipped placement sequence"
	if request.operation_id == saved.operation_id: return "Placement operation ID already consumed"
	return ""

static func _placement_grid_ok(grid: MarchPath) -> bool:
	return grid != null and grid.cols > 0 and grid.rows > 0 and grid.cell_m > 0 \
		and grid.closed.size() == grid.cols * grid.rows and grid.water.size() == grid.closed.size() and not grid.water_open

static func _placement_basis(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> String:
	var grid := MarchPath.of_pack(repo)
	return BodyMotion._hash({"source": source.to_dict(), "request": request, "boundary": boundary,
		"footprints": repo.unit_footprints, "balance": repo.balance, "hosts": repo.raid_hosts,
		"burgs": repo.burgs, "realms": repo.kingdoms, "provinces": repo.provinces,
		"unit_types": repo.world_table("military", "unit_types"), "laws": repo.laws, "law_effects": repo.law_effects,
		"schema": repo.world_schema, "map_info": repo.map_info, "terrain_types": repo.army_terrain, "terrain_biomes": repo.army_terrain_biomes, "camp_blocked": repo.army_camp_blocked,
		"town_reach": repo.army_town_reach, "terrain": {"cols": grid.cols, "rows": grid.rows,
		"cell_m": grid.cell_m, "closed": Array(grid.closed), "water": Array(grid.water), "water_open": grid.water_open}})

static func plan_body_placement_candidate(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	var result := _placement_stage(repo, source, request, boundary)
	if result.status == "complete": result.candidate = null
	return result

static func body_placement_candidate(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	var planned := plan_body_placement_candidate(repo, source, request, boundary)
	if planned.status != "complete": return planned
	return commit_body_placement_candidate(repo, source, planned.plan, boundary)

static func commit_body_placement_candidate(repo: DataRepository, source: GameState, proposed: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null: return _placement_result("error", "Missing placement source")
	if not _placement_plan_ok(proposed) or not _placement_request_ok(proposed.request): return _placement_result("error", "Invalid closed placement plan")
	if BodyMotion._hash(boundary) != BodyMotion._hash(proposed.boundary): return _placement_result("error", "Placement boundary mismatch")
	var request: Dictionary = proposed.request
	var checked := UnitBodies.validate_placement_candidate(repo, source, boundary)
	# Staged recruit counts are validated against their real previous partition below.
	if checked.status == "error" and request.operation != "recruit": return _placement_result("error", checked.reason)
	var sequence_error := _placement_sequence_error(source, request, true)
	if not sequence_error.is_empty(): return _placement_result("error", sequence_error)
	var receipt := BodyMotion._hash(proposed)
	var saved: Dictionary = source.military_migration.get("body_placement", {})
	if not saved.is_empty() and request.sequence == saved.sequence:
		if checked.status != "complete": return _placement_result("error", "Retry requires a complete validated source")
		if receipt != saved.receipt: return _placement_result("error", "Placement retry receipt mismatch")
		var grid := MarchPath.of_pack(repo)
		if not _placement_grid_ok(grid): return _placement_result("error", "Placement requires a valid land terrain grid")
		var terrain_error := _placement_terrain_error(repo, source, grid)
		if not terrain_error.is_empty(): return _placement_result("error", terrain_error)
		return _placement_result("complete", "Exact placement already committed", UnitBodies._copy(source), proposed.duplicate(true))
	var staged := _placement_stage(repo, source, request, boundary)
	if staged.status != "complete": return staged
	if BodyMotion._hash(staged.plan) != receipt: return _placement_result("error", "Stale or modified placement plan")
	var candidate: GameState = staged.candidate
	candidate.military_migration.body_placement = {"version": "1", "sequence": request.sequence,
		"operation_id": request.operation_id, "receipt": receipt}
	checked = UnitBodies.validate_placement_candidate(repo, candidate, boundary)
	if checked.status != "complete": return _placement_result("error", checked.reason)
	return _placement_result("complete", "Published detached complete placement transaction", candidate, staged.plan)

static func _placement_plan_ok(plan: Dictionary) -> bool:
	if not BodyMotion._keys(plan, ["version", "request", "boundary", "basis", "placements", "effects"]) \
		or not UnitBodies._whole(plan.version) or int(plan.version) != 1 or not plan.request is Dictionary \
		or not plan.boundary is Dictionary or not plan.basis is String or not BodyMotion._digest(plan.basis) \
		or not plan.placements is Array or not plan.effects is Dictionary: return false
	if not BodyMotion._keys(plan.effects, ["entries", "seats", "hosts"]): return false
	for key: String in ["entries", "seats", "hosts"]:
		if not plan.effects[key] is Dictionary: return false
	for row: Variant in plan.placements:
		if not row is Dictionary or not BodyMotion._keys(row, ["unit", "battle_id", "slot", "home_slot", "count", "role", "x_m", "y_m", "facing_deg", "path_m"]): return false
		if not row.unit is String or row.unit.is_empty() or not BodyMotion._natural(row.battle_id) or not UnitBodies._row_error(row, 0, true).is_empty(): return false
		if not row.path_m is Array or row.path_m != [[row.x_m, row.y_m]]: return false
	return true

static func _placement_stage(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null: return _placement_result("error", "Missing placement source")
	if not _placement_request_ok(request): return _placement_result("error", "Invalid raw placement request")
	for code: Variant in source.army_roster:
		if not code is String or not source.army_roster[code] is Dictionary: return _placement_result("error", "Invalid raw placement roster")
		if not UnitBodies._naval(source, code):
			var personnel_error := UnitBodies._placement_personnel_error(source, code)
			if not personnel_error.is_empty(): return _placement_result("error", personnel_error)
	if request.operation in ["recruit", "settle", "leave", "take_seat"] and (UnitBodies._entry(source, request.unit).is_empty() or UnitBodies._naval(source, request.unit)):
		return _placement_result("error", "Unknown or non-land placement unit")
	if request.operation == "refill" and not repo.burgs.has(request.unit): return _placement_result("error", "Unknown placement town")
	if request.operation == "enemy_spawn" and EnemyAi._row_of(repo, request.host).is_empty(): return _placement_result("error", "Unknown placement host")
	var sequence_error := _placement_sequence_error(source, request)
	if not sequence_error.is_empty(): return _placement_result("error", sequence_error)
	if request.operation == "enemy_spawn" and source.ai_hosts.has(request.host): return _placement_result("error", "Host already spawned")
	var index := UnitBodies._owners(source)
	if not index.error.is_empty(): return _placement_result("error", index.error)
	for code: String in index.codes:
		if UnitBodies._naval(source, code): continue
		if not source.army_roster.has(code) or not source.military_rosters.get(code) is Dictionary or not source.military_rosters[code].get("cohort_ids") is Array:
			return _placement_result("error", "Placement requires actual roster/personnel provenance: " + code)
	var boundary_error := UnitBodies._placement_boundary_error(source, boundary)
	if not boundary_error.is_empty(): return _placement_result("error", boundary_error)
	var input := source
	if request.operation == "recruit" and not UnitBodies._entry(source, request.unit).has("body_reconciliation"):
		var reconciled := UnitBodies.reconcile_candidate(repo, source, request.unit, int(request.previous_fit))
		if reconciled.status not in ["complete", "needs_placement"]: return _placement_result(reconciled.status, ("frozen_transaction: " if reconciled.status == "deferred" else "") + reconciled.reason)
		input = reconciled.candidate
	var validated := UnitBodies.validate_placement_candidate(repo, input, boundary)
	if validated.status in ["error", "deferred"]:
		return _placement_result(validated.status, ("frozen_transaction: " if validated.status == "deferred" else "") + validated.reason)
	for code: String in index.codes:
		if UnitBodies._entry(source, code).has("body_reconciliation") and request.operation != "recruit":
			return _placement_result("deferred", "pending_personnel_boundary: explicit recruit transaction required")
	if boundary.kind == "march_complete" and request.operation not in ["settle", "leave", "take_seat", "refill", "reconcile"]:
		return _placement_result("deferred", "frozen_transaction: only metadata operations at completed MARCH")
	if validated.status == "needs_placement" and request.operation not in ["initialize", "legacy_missing", "recruit", "enemy_spawn"]:
		return _placement_result("deferred", "pending_personnel_boundary: incomplete bodies")
	if request.operation == "enemy_spawn":
		var host := EnemyAi._row_of(repo, request.host)
		if host.is_empty(): return _placement_result("error", "Unknown placement host")
		var units := EnemyAi.host_units(repo, source, host)
		for missing: Dictionary in validated.placement_requests:
			if missing.unit not in units: return _placement_result("deferred", "pending_personnel_boundary: non-host bodies incomplete")
	if request.operation == "recruit":
		for missing: Dictionary in validated.placement_requests:
			if missing.unit != request.unit: return _placement_result("deferred", "pending_personnel_boundary: another unit needs placement")
		var descriptor: Dictionary = UnitBodies._entry(input, request.unit).get("body_reconciliation", {})
		if not descriptor.is_empty() and int(descriptor.basis_fit) != int(request.previous_fit): return _placement_result("error", "Recruit previous fit differs from staged descriptor")
	var grid := MarchPath.of_pack(repo)
	if not _placement_grid_ok(grid): return _placement_result("error", "Placement requires a valid land terrain grid")
	var candidate: GameState = validated.candidate
	if request.operation == "initialize":
		var added := false
		var codes: Array = source.army_roster.keys()
		codes.sort()
		for code: String in codes:
			if UnitBodies._naval(source, code) or not UnitBodies._entry(source, code).is_empty(): continue
			if not source.military_rosters.get(code) is Dictionary or not source.military_rosters[code].get("cohort_ids") is Array \
				or not UnitBodies._fit_valid(source, code, int(repo.bal("battle_group_size")) * 10):
				return _placement_result("error", "New entry requires staged roster/personnel provenance: " + code)
			for id: Variant in source.military_rosters[code].cohort_ids:
				var cohort: Dictionary = source.military_cohorts[id]
				if cohort.get("unit_code") != code or not MilitaryRoster.cohort_error(repo, cohort).is_empty():
					return _placement_result("error", "Invalid new entry personnel provenance: " + code)
			var reg: Dictionary = source.army_roster[code]
			for key: String in ["x", "y"]:
				var value: Variant = reg.get(key)
				if not (value is int or value is float or (value is String and value.is_valid_float())) or not is_finite(float(value)):
					return _placement_result("error", "New entry requires a finite saved pack anchor")
			candidate.regiments[code] = ArmySystem.starting_state(repo, reg, candidate)
			added = true
		if added:
			candidate.military_migration.erase("body_version")
			validated = UnitBodies.validate_placement_candidate(repo, candidate, boundary)
			if validated.status not in ["complete", "needs_placement"]: return _placement_result(validated.status, validated.reason)
			candidate = validated.candidate
	if request.operation == "enemy_spawn":
		var spawned := _placement_host(repo, candidate, request.host)
		if spawned.status != "complete": return spawned
		candidate = spawned.candidate
		validated = UnitBodies.validate_placement_candidate(repo, candidate, boundary)
		if validated.status not in ["complete", "needs_placement"]: return _placement_result(validated.status, validated.reason)
		candidate = validated.candidate
	var placed := _placement_fill(repo, candidate, validated.placement_requests, grid)
	if placed.status != "complete": return placed
	var metadata := _placement_metadata(repo, candidate, request)
	if metadata.status != "complete": return metadata
	var final := UnitBodies.validate_placement_candidate(repo, candidate, boundary)
	if final.status != "complete": return _placement_result("error", final.reason)
	candidate = final.candidate
	var terrain_error := _placement_terrain_error(repo, candidate, grid)
	if not terrain_error.is_empty(): return _placement_result("error", terrain_error)
	var entries := {}
	for code: String in candidate.regiments.keys() + candidate.foes.keys():
		var entry := UnitBodies._entry(candidate, code)
		if entry != UnitBodies._entry(source, code): entries[code] = entry.duplicate(true)
	var plan := {"version": 1, "request": request.duplicate(true), "boundary": boundary.duplicate(true),
		"basis": _placement_basis(repo, source, request, boundary), "placements": placed.plan.placements,
		"effects": {"entries": entries, "seats": candidate.town_seat.duplicate(true), "hosts": candidate.ai_hosts.duplicate(true)}}
	return _placement_result("complete", "Validated all bodies and lifecycle effects", candidate, plan)

static func _placement_add(a: int, b: int) -> Array:
	var sum: int = a + b
	if (b > 0 and sum < a) or (b < 0 and sum > a): return []
	return [sum]

static func _placement_clear(point: Array, radius: int, taken: Array, grid: MarchPath) -> bool:
	if not ArmySystem._body_path_terrain(grid, [point], radius).is_empty(): return false
	for other: Dictionary in taken:
		var dx: int = int(point[0]) - int(other.x)
		var dy: int = int(point[1]) - int(other.y)
		if (int(point[0]) >= int(other.x) and dx < 0) or (int(point[0]) < int(other.x) and dx >= 0): continue
		if (int(point[1]) >= int(other.y) and dy < 0) or (int(point[1]) < int(other.y) and dy >= 0): continue
		var limit: int = radius + int(other.radius)
		if dx >= limit or dx <= -limit or dy >= limit or dy <= -limit: continue
		if dx * dx + dy * dy < limit * limit: return false
	return true

static func _placement_fill(repo: DataRepository, candidate: GameState, requests: Array, grid: MarchPath) -> Dictionary:
	var taken: Array = []
	for code: String in candidate.regiments.keys() + candidate.foes.keys():
		if UnitBodies._naval(candidate, code): continue
		var config := UnitBodies._config(repo, candidate, code)
		for row: Dictionary in UnitBodies.rows(repo, candidate, code):
			taken.append({"x": row.x_m, "y": row.y_m, "radius": int(config.radius_m)})
	var placements: Array = []
	var spacing: Variant = repo.bal("army_slot_spacing_m")
	var rings: Variant = repo.bal("army_slot_max_rings")
	if not BodyMotion._natural(spacing) or int(spacing) <= 0 or not BodyMotion._natural(rings): return _placement_result("error", "Invalid placement lattice configuration")
	# Existing lattice vectors are int32 local offsets, never world coordinates.
	if int(rings) > 2147483647 or (int(rings) > 0 and int(spacing) > 2147483647 / int(rings)):
		return _placement_result("error", "Placement lattice overflow")
	var owners := UnitBodies._owners(candidate)
	for missing: Dictionary in requests:
		var code: String = missing.unit
		var entry := UnitBodies._entry(candidate, code)
		var battle: Dictionary = owners.owners.get(code, {})
		var store: Array = entry.get("body_groups", []) if battle.is_empty() else battle.get("groups", {}).get(code, [])
		var config := UnitBodies._config(repo, candidate, code)
		var radius := int(config.radius_m)
		var homes := UnitBodies.home_slots(repo, candidate, code)
		var partition := BattleGroups.counts(MilitaryRoster.fit(candidate, code), int(repo.bal("battle_group_size")))
		var next := int(entry.get("group_next_slot", 0))
		var radians := deg_to_rad(float(missing.facing_deg))
		for home: int in missing.missing_home_slots:
			if next == 0x7fffffffffffffff: return _placement_result("error", "Placement slot overflow")
			var local: Vector2i = homes[home]
			var dx := roundi(float(local.x) * cos(radians) - float(local.y) * sin(radians))
			var dy := roundi(float(local.x) * sin(radians) + float(local.y) * cos(radians))
			var x := _placement_add(int(missing.anchor_m[0]), dx)
			var y := _placement_add(int(missing.anchor_m[1]), dy)
			if x.is_empty() or y.is_empty(): return _placement_result("error", "Placement home coordinate overflow")
			var preferred := [x[0], y[0]]
			var found: Array = preferred if _placement_clear(preferred, radius, taken, grid) else []
			for k: int in range(1, int(rings) + 1):
				if not found.is_empty(): break
				for axial: Vector2i in ring(k):
					var offset := slot_m(Vector2i.ZERO, axial, int(spacing))
					x = _placement_add(int(preferred[0]), offset.x)
					y = _placement_add(int(preferred[1]), offset.y)
					if x.is_empty() or y.is_empty(): return _placement_result("error", "Placement lattice coordinate overflow")
					var point := [x[0], y[0]]
					if _placement_clear(point, radius, taken, grid):
						found = point
						break
			if found.is_empty(): return _placement_result("deferred", "space_unavailable: " + code + " home " + str(home))
			var row := {"slot": next, "home_slot": home, "count": partition[store.size()], "role": "front",
				"x_m": found[0], "y_m": found[1], "facing_deg": int(missing.facing_deg), "path_m": [found.duplicate()]}
			store.append(row)
			taken.append({"x": found[0], "y": found[1], "radius": radius})
			var wire := row.duplicate(true)
			wire.unit = code
			wire.battle_id = int(missing.battle_id)
			placements.append(wire)
			next += 1
		entry.group_next_slot = next
		entry.erase("body_reconciliation")
		if battle.is_empty(): entry.body_groups = store
		else:
			if not battle.has("groups"): battle.groups = {}
			battle.groups[code] = store
			battle.body_version = 1
			battle.group_size_version = 2
			battle.group_size_men = int(repo.bal("battle_group_size"))
	return _placement_result("complete", "Placed only missing rows", candidate, {"placements": placements})

static func _placement_host(repo: DataRepository, candidate: GameState, host_code: String) -> Dictionary:
	var host := EnemyAi._row_of(repo, host_code)
	if host.is_empty(): return _placement_result("error", "Unknown placement host")
	if candidate.ai_hosts.has(host_code): return _placement_result("error", "Host already spawned")
	var units := EnemyAi.host_units(repo, candidate, host)
	if units.is_empty(): return _placement_result("error", "Host has no actual roster units")
	var start := ArmySystem.pack_to_metres(repo, Vector2(float(host.start_x), float(host.start_y)))
	for code: String in units:
		if not candidate.military_rosters.get(code) is Dictionary or not candidate.military_rosters[code].get("cohort_ids") is Array \
			or not UnitBodies._fit_valid(candidate, code, int(repo.bal("battle_group_size")) * 10):
			return _placement_result("error", "Host requires raw staged personnel: " + code)
		if candidate.foes.has(code): return _placement_result("error", "Host unit already spawned")
		var existing := UnitBodies._entry(candidate, code)
		if existing.has("body_reconciliation"): return _placement_result("deferred", "pending_personnel_boundary: host unit")
		var owner: Dictionary = UnitBodies._owners(candidate).owners.get(code, {})
		var has_store: bool = existing.has("body_groups") or owner.get("groups", {}).has(code)
		if has_store and (int(existing.x_m) != start.x or int(existing.y_m) != start.y):
			return _placement_result("deferred", "requires_motion: host " + host_code + " assembly")
		var st: Dictionary
		if has_store:
			st = existing.duplicate(true)
		else:
			var definition := ArmySystem.regiment(repo, code, candidate).duplicate(true)
			var px := ArmySystem.metres_to_pack(repo, start)
			definition.x = px.x
			definition.y = px.y
			st = existing.duplicate(true)
			st.merge(ArmySystem.starting_state(repo, definition, candidate), true)
			candidate.military_migration.erase("body_version")
			st.x_m = start.x
			st.y_m = start.y
			st.dest_x_m = start.x
			st.dest_y_m = start.y
		st.order = ArmySystem.ORDER_STANDBY
		st.camp_town = ""
		st.host = host_code
		candidate.regiments.erase(code)
		candidate.foes[code] = st
	for town: String in candidate.town_seat.keys():
		if String(candidate.town_seat[town]) in units: candidate.town_seat.erase(town)
	candidate.ai_hosts[host_code] = {"mode": EnemyAi.MODE_ASSEMBLE, "target_kind": "", "target_id": "", "think_day": 0, "plunder": 0, "siege_progress": 0}
	return _placement_result("complete", "Staged actual host without moving survivors", candidate)

static func _placement_at_town(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	var entry := UnitBodies._entry(state, code)
	var point := town_point_m(repo, town)
	return not entry.is_empty() and int(entry.x_m) == point.x and int(entry.y_m) == point.y

static func _placement_refill(repo: DataRepository, state: GameState, town: String, require_motion: bool) -> Dictionary:
	if not repo.burgs.has(town): return _placement_result("error", "Unknown placement town")
	if seat_of(repo, state, town) != "": return _placement_result("complete", "Seat retained")
	var codes := ArmySystem.roster(repo, state).keys()
	codes.sort()
	var pick := ""
	for foot: bool in [true, false]:
		var best := 0
		for code: String in codes:
			if camped_by(repo, state, code) != town: continue
			if not require_motion and not _placement_at_town(repo, state, code, town): continue
			var reg := ArmySystem.regiment(repo, code, state)
			var n := int(float(reg.get("infantry", 0))) if foot else int(MapObjects.regiment_personnel(repo, reg))
			if n > best:
				best = n
				pick = code
		if pick != "": break
	if pick != "":
		if not _placement_at_town(repo, state, pick, town):
			if require_motion: return _placement_result("deferred", "requires_motion: " + pick + " to town " + town)
		else:
			state.town_seat[town] = pick
			LawSystem.on_settle(repo, state, pick)
	return _placement_result("complete", "Seat metadata reconciled")

static func _placement_metadata(repo: DataRepository, state: GameState, request: Dictionary) -> Dictionary:
	var op: String = request.operation
	if op in ["initialize", "legacy_missing", "recruit", "enemy_spawn"]: return _placement_result("complete", "No camp effect")
	if op == "refill": return _placement_refill(repo, state, request.unit, true)
	if op == "reconcile":
		for town: String in state.town_seat.keys():
			var code := String(state.town_seat[town])
			var reg := ArmySystem.regiment(repo, code, state)
			if reg.is_empty() or not holds(repo, state, String(reg.kingdom_code), town) or not _placement_at_town(repo, state, code, town): state.town_seat.erase(town)
		var towns := repo.burgs.keys()
		towns.sort()
		for town: String in towns: _placement_refill(repo, state, town, false)
		return _placement_result("complete", "Reconciled seats without movement")
	var code: String = request.unit
	var entry := UnitBodies._entry(state, code)
	var reg := ArmySystem.regiment(repo, code, state)
	if entry.is_empty() or reg.is_empty() or UnitBodies._naval(state, code) or ArmySystem.is_foe(state, code): return _placement_result("error", "Camp operation requires an actual land regiment")
	if op == "leave":
		LawSystem.on_leave(repo, state, code)
		entry.camp_town = ""
		for town: String in state.town_seat.keys():
			if state.town_seat[town] == code: state.town_seat.erase(town)
		return _placement_result("complete", "Left camp without moving bodies")
	var town := camped_by(repo, state, code)
	if op == "settle":
		for field: String in ["x_m", "y_m"]:
			if int(entry[field]) < -2147483648 or int(entry[field]) > 2147483647: return _placement_result("error", "Camp anchor exceeds terrain coordinate range")
		var here := Vector2i(int(entry.x_m), int(entry.y_m))
		town = ArmySystem.town_at(repo, ArmySystem.metres_to_pack(repo, here))
	if town != "" and not holds(repo, state, String(reg.kingdom_code), town): town = ""
	if op == "take_seat" and town == "": return _placement_result("error", "Unit has no eligible camp town")
	if op == "take_seat" and not _placement_at_town(repo, state, code, town): return _placement_result("deferred", "requires_motion: " + code + " to town " + town)
	entry.camp_town = town
	if town != "" and _placement_at_town(repo, state, code, town):
		var old := seat_of(repo, state, town)
		if old == "" or old == code or op == "take_seat": state.town_seat[town] = code
	LawSystem.on_settle(repo, state, code)
	return _placement_result("complete", "Camp metadata applied at actual position")

## Placement certifies actual circles; a saved command anchor is not another body.
static func _placement_terrain_error(repo: DataRepository, state: GameState, grid: MarchPath) -> String:
	for code: String in state.regiments.keys() + state.foes.keys():
		if UnitBodies._naval(state, code): continue
		var radius := int(UnitBodies._config(repo, state, code).radius_m)
		for row: Dictionary in UnitBodies.rows(repo, state, code):
			var error := ArmySystem._body_path_terrain(grid, [[int(row.x_m), int(row.y_m)]], radius)
			if not error.is_empty(): return error + ": " + code + " slot " + str(row.slot)
	return ""
