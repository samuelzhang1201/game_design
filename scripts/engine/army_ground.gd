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
## unit within half a pitch.
static func is_free(repo: DataRepository, taken: Dictionary, p_m: Vector2i) -> bool:
	var px := ArmySystem.metres_to_pack(repo, p_m)
	if MapEconomy.cell_at(repo, px) < 0:
		return false
	if repo.army_camp_blocked.has(ArmySystem.terrain_at(repo, px)):
		return false
	var half := float(int(taken["cell"])) / 2.0
	var home := _bucket(taken, p_m)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2i in (taken["grid"] as Dictionary).get(home + Vector2i(dx, dy), []):
				if Vector2(q - p_m).length() < half:
					return false
	return true


## The slot a unit of `arm` takes around `centre_m`: in the FIELD (`town`
## false) the centre itself while it is free; else the first free slot at the
## arm's ring or further out, ring by ring; NONE past army_slot_max_rings.
static func free_slot(repo: DataRepository, centre_m: Vector2i, arm: String, taken: Dictionary,
		town: bool) -> Vector2i:
	if not town and is_free(repo, taken, centre_m):
		return centre_m
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(maxi(start_ring(repo, arm), 1), int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ring(k):
			var p := slot_m(centre_m, ax, spacing)
			if is_free(repo, taken, p):
				return p
	return NONE


## A town's own point (its seat) in whole metres.
static func town_point_m(repo: DataRepository, town: String) -> Vector2i:
	var b: Dictionary = repo.burgs[town]
	return ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
