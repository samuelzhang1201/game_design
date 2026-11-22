class_name Map3DDuelScrum
extends RefCounted
## The mixed fight in the duel driver (spec 2026-11-21-infantry-melee-scrum-design.md;
## owner: 双方兵人应该在战场上混在一起): per battle ONE fighting area between the
## two opposed infantry sides (Map3DScrum.area), a point in it per figure
## (hashed, then kept), the pairs met at `close_h` and pushed apart to
## `space_h` one bounded pass a frame. A figure's `duel_offset` is its point
## less its stand: the battle walk takes it there paced, the saved point never
## moves. View-only.

var _pts: Dictionary = {}  ## battle id -> {figure key: its point in the area, world XZ}
var _areas: Dictionary = {}  ## battle id -> Map3DScrum.area


func targets(id: int) -> Dictionary: return _pts.get(id, {})
func area_of(id: int) -> Dictionary: return _areas.get(id, {})


## Forget the battles not in `battles` (over, or no scrum this frame).
func keep(ids: Array) -> void:
	for id: int in _pts.keys():
		if not id in ids:
			_pts.erase(id)
			_areas.erase(id)


## A scrum battle's pairs into `wanted` (key -> [fa, fb]) and `taken`: a pair of
## `pairs` whose two figures still fight keeps on, the rest pair nearest across
## the area; then every point is pulled to its pair and kept apart. A side with
## no figure drawn: no scrum. Marks each figure `scrum` (its battle id).
func pair(battle: Dictionary, figs: Dictionary, pairs: Dictionary, wanted: Dictionary, taken: Dictionary,
		tune: Dictionary, h: float) -> void:
	var id := int(battle["id"])
	if (battle["a"] as Array).is_empty() or (battle["b"] as Array).is_empty():
		_pts.erase(id)
		_areas.erase(id)
		return
	var stands := func(side: Array) -> Array[Vector2]:
		var out: Array[Vector2] = []
		for f: Dictionary in side:
			out.append(f["xz"])
		return out
	var area := Map3DScrum.area(stands.call(battle["a"]), stands.call(battle["b"]),
		(battle["across"] as Vector2).orthogonal(), float(tune["depth_h"]) * h)
	_areas[id] = area
	var old: Dictionary = _pts.get(id, {})
	var pts: Dictionary = {}
	for side: String in ["a", "b"]:  # each side's points lean to its own half of the area
		var mean := Vector2.ZERO
		for p: Vector2 in stands.call(battle[side]):
			mean += p / float((battle[side] as Array).size())
		for f: Dictionary in battle[side]:
			pts[f["key"]] = old.get(f["key"], Map3DScrum.target(f["key"], area, mean, float(tune["cross"]), f["xz"],
				float(tune["spread_h"]) * h))
			f["scrum"] = id
	var mine: Array = []
	for key: String in pairs:
		var ka := String(pairs[key]["figs"][0]["key"])
		var kb := String(pairs[key]["figs"][1]["key"])
		if figs.has(ka) and figs.has(kb) and not taken.has(ka) and not taken.has(kb):
			mine.append([key, ka, kb])
			taken[ka] = true
			taken[kb] = true
	var free := func(side: Array) -> Array:
		return side.filter(func(f: Dictionary) -> bool: return not taken.has(f["key"])).map(
			func(f: Dictionary) -> Dictionary: return {"key": f["key"], "xz": pts[f["key"]]})
	for p: Dictionary in Map3DScrum.pairs_nearest(free.call(battle["a"]), free.call(battle["b"]), float(tune["pair_h"]) * h):
		mine.append(["%s|%s" % [p["a"], p["b"]], p["a"], p["b"]])
		taken[p["a"]] = true
		taken[p["b"]] = true
	var close := float(tune["close_h"]) * h
	for row: Array in mine:
		wanted[row[0]] = [figs[row[1]], figs[row[2]]]
		var mid: Vector2 = (pts[row[1]] + pts[row[2]]) / 2.0  # a pair meets halfway, `close` apart
		var dir: Vector2 = (pts[row[2]] - pts[row[1]]).normalized()
		pts[row[1]] = mid - dir * close / 2.0
		pts[row[2]] = mid + dir * close / 2.0
	pts = Map3DScrum.separate(pts, float(tune["space_h"]) * h, float(tune["push_h"]) * h)
	for key: String in pts:
		pts[key] = Map3DScrum.inside(pts[key], area)
	_pts[id] = pts


## Both figures of a scrum pair aimed at each other; whether either changed.
func aim_pair(figs: Array, tune: Dictionary) -> bool:
	var a := aim(figs[0], [figs[1]], tune)
	var b := aim(figs[1], [figs[0]], tune)
	return a or b


## A scrum figure walks to its point and faces `foe` (its partner's point, or a
## waiting figure's nearest foe); set only past `settle_h` of a move, and while
## it walks only past `step_max_h`, so small pushes never restart its walk.
## A long way (past `step_max_h`) turns into it
## (`step_up`); a short one steps facing its foe. Whether it changed.
func aim(f: Dictionary, foes: Array, tune: Dictionary) -> bool:
	var pts: Dictionary = _pts.get(int(f["scrum"]), {})
	if not pts.has(f["key"]):
		return false
	var me: Vector2 = pts[f["key"]]
	var near := Vector2.INF
	for g: Dictionary in foes:
		var at: Vector2 = pts.get(g["key"], g["xz"])
		if near == Vector2.INF or me.distance_squared_to(at) < me.distance_squared_to(near):
			near = at
	var child: Dictionary = f["child"]
	var offset: Vector2 = me - (f["xz"] as Vector2)
	var was: Vector2 = child.get("duel_offset", Vector2.INF)
	var step_max := float(tune["step_max_h"]) * float(f["h"])
	if was != Vector2.INF and (was.distance_to(offset) <= float(tune["settle_h"]) * float(f["h"])
			or child.get("walking", false) and was.distance_to(offset) <= step_max):
		return false  # walking, a short push waits for its arrival: a restarted walk re-begins its turn (a glide)
	child["duel_offset"] = offset
	child["duel_yaw"] = Map3DUnits.facing_yaw(near - me, float(child.get("stand_deg", 0.0))) if near != Vector2.INF \
		else float(child.get("duel_yaw", 0.0))
	child["scrum_far"] = true  # its way back to its slot is a walk too (Map3DDuelDriver._release)
	var far := (Vector2.ZERO if was == Vector2.INF else was).distance_to(offset) > step_max
	if far or child.get("step_up", false):
		child["step_up"] = true
		child.erase("step_facing")
	elif not child.get("walking", false):
		child["step_facing"] = true
	return true
