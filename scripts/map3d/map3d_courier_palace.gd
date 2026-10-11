class_name Map3DCourierPalace
extends RefCounted
## A courier sets out from the PALACE at the very centre of the crown's seat
## (owner 2026-10-07: 信使必须一直在王都正中央的宫殿出现). The engine rides him
## from the town's own point (CourierSystem.origin — it cannot read the bake's
## houses), which stands beside the palace, so this is presentation only: the
## map draws his road from the palace's DOOR — the edge of its footprint facing
## the way he leaves, `gap_m` out so the rider never stands in its walls — to
## the town's point and on; a road that ends at the town's point rides on into
## that door, where he fades as he delivers. Pure; read by Map3DLayerCouriers.

## Metres within which a drawn point IS the town's point (whole-metre rounding).
const SAME_M := 2.0


## The town couriers ride from (`origin_px`, pack px) as its centre building:
## {centre: world XZ, half: half its side in metres, yaw_deg, town: the town's
## world XZ `town_xz`}; {} when no burg stands there or its rank-0 house is no
## landmark (data/screens/map3d/map3d_houses.csv `role`).
static func seat_of(repo: DataRepository, houses: Dictionary, origin_px: Vector2, town_xz: Vector2) -> Dictionary:
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if Vector2(float(b["x"]), float(b["y"])) != origin_px:
			continue
		var list: Array = houses.get(code, [])
		if list.is_empty() or int((list[0] as Dictionary)["rank"]) != 0:
			return {}
		var h: Dictionary = list[0]
		var row: Dictionary = repo.map3d_houses.get(String(h["type"]), {})
		if String(row.get("role", "")) != "landmark":
			return {}
		var side := maxf(float(row.get("width_m", 0.0)), float(row.get("depth_m", 0.0)))
		if side <= 0.0:
			side = float(row.get("footprint_m", 0.0))
		return {"centre": h["at"], "half": 0.5 * side * float(h["scale"]),
			"yaw_deg": float(h["yaw_deg"]), "town": town_xz}
	return {}


## Whether `p` stands within the seat's square footprint grown by `margin`.
static func inside(seat: Dictionary, p: Vector2, margin: float = 0.0) -> bool:
	# a house turned by yaw about +Y puts local x at world (cos, -sin): local = world.rotated(+yaw)
	var local := (p - (seat["centre"] as Vector2)).rotated(deg_to_rad(float(seat["yaw_deg"])))
	var h := float(seat["half"]) + margin
	return absf(local.x) <= h and absf(local.y) <= h


## The door facing `toward`: where the line from the centre to it leaves the
## footprint grown by `gap_m`.
static func door(seat: Dictionary, toward: Vector2, gap_m: float) -> Vector2:
	var c: Vector2 = seat["centre"]
	var d := toward - c
	var local := d.rotated(deg_to_rad(float(seat["yaw_deg"])))
	var far := maxf(absf(local.x), absf(local.y))
	if far < 0.001:
		return c + Vector2(float(seat["half"]) + gap_m, 0.0)
	return c + d * ((float(seat["half"]) + gap_m) / far)


## A drawn ride `{from, ahead, rest}` (world XZ) dressed for the seat: one
## standing at the town's point starts at the door facing his road instead,
## riding to the town's point and on (every point within the footprint
## dropped); one whose road ends at the town's point rides on to the door.
## Returns {from, ahead, rest}; `seat` {} returns them as they are.
static func dress(seat: Dictionary, from: Vector2, ahead: Array, rest: Array, gap_m: float) -> Dictionary:
	if seat.is_empty():
		return {"from": from, "ahead": ahead, "rest": rest}
	var town: Vector2 = seat["town"]
	var a := ahead.duplicate()
	var r := rest.duplicate()
	if from.distance_to(town) < SAME_M:
		var first: Array = [town] if a.is_empty() or (a[0] as Vector2).distance_to(town) >= SAME_M else []
		a = first + a
		while not a.is_empty() and inside(seat, a[0], gap_m):
			a.pop_front()
		while a.is_empty() and not r.is_empty() and inside(seat, r[0], gap_m):
			r.pop_front()
		var toward: Variant = a[0] if not a.is_empty() else (r[0] if not r.is_empty() else null)
		from = door(seat, toward, gap_m) if toward != null else door(seat, town, gap_m)
	var tail := r if not r.is_empty() else a
	if not tail.is_empty() and (tail[-1] as Vector2).distance_to(town) < SAME_M:
		if inside(seat, town, gap_m):
			tail.pop_back()
		tail.append(door(seat, town, gap_m))
	return {"from": from, "ahead": a, "rest": r}
