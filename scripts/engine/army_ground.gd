class_name ArmyGround
extends RefCounted
## The ground a unit holds (owner 2026-10-07, spec docs/superpowers/specs/
## 2026-10-07-army-split-and-ground-design.md §4): only a STANDING land unit
## holds ground — a column on the march holds none, so columns pass through
## each other, and a fleet never does. Around a centre the camps lie on a hex
## lattice of army_slot_spacing_m, ring by ring (ring k has 6k slots, taken
## from the east counter-clockwise); a unit takes the first free slot at its
## arm's ring (data/army_split.csv start_ring) or further out. Ring 0 is a
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


## The first ring an arm camps on (data/army_split.csv); 1 for an arm with no row.
static func start_ring(repo: DataRepository, arm: String) -> int:
	for row: Dictionary in repo.army_split:
		if String(row["arm"]) == arm:
			return int(row["start_ring"])
	return 1


## An empty record of held ground: points bucketed by the pitch.
static func new_taken(repo: DataRepository) -> Dictionary:
	return {"cell": maxi(int(repo.bal("army_slot_spacing_m")), 1), "grid": {}}


static func take(taken: Dictionary, p_m: Vector2i) -> void:
	var key := _bucket(taken, p_m)
	if not (taken["grid"] as Dictionary).has(key):
		taken["grid"][key] = []
	(taken["grid"][key] as Array).append(p_m)


static func _bucket(taken: Dictionary, p_m: Vector2i) -> Vector2i:
	var cell := int(taken["cell"])
	return Vector2i(floori(float(p_m.x) / cell), floori(float(p_m.y) / cell))


## Ground a unit may camp on: land, not a blocked terrain, and no standing
## unit within half a pitch. `any_terrain` waives the blocked terrains, for a
## town that stands among them (a mountain hold): its camps lie on the
## mountain, the one ground it has.
static func is_free(repo: DataRepository, taken: Dictionary, p_m: Vector2i,
		any_terrain := false) -> bool:
	var px := ArmySystem.metres_to_pack(repo, p_m)
	if MapEconomy.cell_at(repo, px) < 0:
		return false
	if not any_terrain and repo.army_camp_blocked.has(ArmySystem.terrain_at(repo, px)):
		return false
	var half := float(int(taken["cell"])) / 2.0
	var home := _bucket(taken, p_m)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2i in (taken["grid"] as Dictionary).get(home + Vector2i(dx, dy), []):
				if Vector2(q - p_m).length() < half:
					return false
	return true


## The whole rings a town's reach covers at `pitch`: ceil(reach / pitch), at
## least 1. A town's camps count their arm's ring from the last of them (R16).
static func clear_rings(reach_m: float, pitch: int) -> int:
	return maxi(ceili(reach_m / float(maxi(pitch, 1))), 1)


## A town's reach in metres (data/army_town_reach.csv by its group).
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
## NONE past army_slot_max_rings.
static func free_slot(repo: DataRepository, centre_m: Vector2i, arm: String, taken: Dictionary,
		town: String, any_terrain := false) -> Vector2i:
	if town == "" and is_free(repo, taken, centre_m, any_terrain):
		return centre_m
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(first_ring(repo, arm, town), int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ring(k):
			var p := slot_m(centre_m, ax, spacing)
			if town != "" and in_reach(repo, town, p):
				continue
			if is_free(repo, taken, p, any_terrain):
				return p
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


## The ground every OTHER standing land unit holds now, metres. Built per
## settle (arrivals are rare), never per frame.
static func standing_taken(repo: DataRepository, state: GameState, except_code: String) -> Dictionary:
	var taken := new_taken(repo)
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	for c: String in codes:
		var r: Dictionary = all[c]
		if c == except_code or String(r.get("is_naval", "0")) == "1":
			continue
		if state != null and ArmySystem.order_of(repo, state, c) == ArmySystem.ORDER_MARCH:
			continue
		take(taken, ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, r)))
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
## camp_town is the town, "" in the field.
static func settle(repo: DataRepository, state: GameState, code: String) -> void:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	if entry.is_empty() or reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var town := ArmySystem.town_at(repo, ArmySystem.metres_to_pack(repo, here))
	if town != "" and not holds(repo, state, String(reg["kingdom_code"]), town):
		town = ""
	entry["camp_town"] = town
	var centre := town_point_m(repo, town) if town != "" else here
	if town != "" and seat_of(repo, state, town) == "":
		state.town_seat[town] = code
		_put(entry, centre)
		return
	var arm := MapObjects.regiment_arm(repo, reg)
	var taken := standing_taken(repo, state, code)
	var slot := free_slot(repo, centre, arm, taken, town)
	if slot == NONE:
		slot = free_slot(repo, centre, arm, taken, town, true)
	if slot != NONE:
		_put(entry, slot)


## A unit's march order has taken effect (ArmySystem.set_march): it leaves
## its camp and, holding a seat, empties it — refilled the same day from the
## camp (§4.4).
static func leave(repo: DataRepository, state: GameState, code: String) -> void:
	if state.regiments.has(code):
		state.regiments[code]["camp_town"] = ""
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		if String(state.town_seat[town]) == code:
			state.town_seat.erase(town)
			refill(repo, state, town)


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
			var n := int(float(r.get("infantry", 0))) if pass_foot else int(MapObjects.regiment_size(repo, r))
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
	return true


## A seat whose town its holder's kingdom no longer holds is cleared (a day,
## after the march; spec §4.4).
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		var reg := ArmySystem.regiment(repo, String(state.town_seat[town]), state)
		if reg.is_empty() or not holds(repo, state, String(reg["kingdom_code"]), town):
			state.town_seat.erase(town)
