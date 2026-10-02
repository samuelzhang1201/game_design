class_name WarToss
extends RefCounted
## The war marker tossed onto the index chart (owner 2026-10-02: 随意的丢上去
## 一个代表战争的3D棋子; spec 2026-10-02-war-room-v2 §2.3), pure: thrown from
## the officer's side in a parabola, tumbling about a random axis, it lands,
## hops lower each time (war_toss_bounce_ratio), half righted, and turns upright
## over the settle at a random yaw. Presentation only: its seed is the room's
## own, never GameState.rng, and nothing is saved.


static func rules(repo: DataRepository) -> Dictionary:
	return {"apex_m": repo.bal("war_toss_apex_m"), "fly_s": repo.bal("war_toss_fly_s"),
		"turns_min": repo.bal("war_toss_turns_min"), "turns_max": repo.bal("war_toss_turns_max"),
		"bounces": int(repo.bal("war_toss_bounces")), "bounce_ratio": repo.bal("war_toss_bounce_ratio"),
		"settle_s": repo.bal("war_toss_settle_s")}


static func plan(from: Vector3, to: Vector3, seed: int, r: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0))
	axis = axis.normalized() if axis.length() > 0.2 else Vector3.RIGHT
	var bounces: Array = []
	var h := float(r["apex_m"])
	var s := float(r["fly_s"])
	for i in int(r["bounces"]):
		h *= float(r["bounce_ratio"])
		s *= sqrt(float(r["bounce_ratio"]))
		bounces.append({"h": h, "s": s})
	var total := float(r["fly_s"]) + float(r["settle_s"])
	for b: Dictionary in bounces:
		total += float(b["s"])
	return {"from": from, "to": to, "apex": float(r["apex_m"]), "axis": axis,
		"turns": rng.randf_range(float(r["turns_min"]), float(r["turns_max"])), "yaw": rng.randf_range(0.0, TAU),
		"fly_s": float(r["fly_s"]), "bounces": bounces, "settle_s": float(r["settle_s"]), "duration": total}


static func pose(p: Dictionary, t: float) -> Transform3D:
	var from: Vector3 = p["from"]
	var to: Vector3 = p["to"]
	var fly := float(p["fly_s"])
	var upright := Quaternion(Vector3.UP, float(p["yaw"]))
	var tumbled := Quaternion(p["axis"] as Vector3, float(p["turns"]) * TAU) * upright
	if t <= fly:
		var u := clampf(t / maxf(fly, 0.0001), 0.0, 1.0)
		var at := from.lerp(to, u) + Vector3.UP * 4.0 * float(p["apex"]) * u * (1.0 - u)
		var spin := Quaternion(p["axis"] as Vector3, float(p["turns"]) * TAU * u) * upright
		return Transform3D(Basis(spin), at)
	var left := t - fly
	var hop := tumbled.slerp(upright, 0.5)   # half righted on its hops
	for b: Dictionary in p["bounces"]:
		var s := float(b["s"])
		if left <= s:
			var u := left / maxf(s, 0.0001)
			return Transform3D(Basis(hop), to + Vector3.UP * 4.0 * float(b["h"]) * u * (1.0 - u))
		left -= s
	var k := smoothstep(0.0, 1.0, clampf(left / maxf(float(p["settle_s"]), 0.0001), 0.0, 1.0))
	return Transform3D(Basis(hop.slerp(upright, k)), to)


## A point in `rect_uv`, `margin` of its size in from every edge.
static func landing(rect_uv: Rect2, seed: int, margin: float) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := rect_uv.size * margin
	return rect_uv.position + m + Vector2(rng.randf(), rng.randf()) * (rect_uv.size - m * 2.0)
