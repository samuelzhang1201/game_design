class_name Map3DDuelMelee
extends RefCounted
## The melee's additions to the duel (spec 2026-11-21-infantry-melee-scrum-design.md),
## run by Map3DDuelDriver: every blow lands (the contact told, the struck figure
## knocked back, a burst at the meeting point; Map3DImpact's curves) and no one
## fights air (a front figure left unpaired waits facing a foe). View-only.


## A figure whose partner is gone steps back to its stand, facing its foe, its knock cleared.
static func unstep(f: Dictionary) -> void:
	var child: Dictionary = f["child"]
	child.erase("duel_offset")
	child.erase("knock_offset")
	child["step_facing"] = true
	child["walking"] = true  # its walk back starts when its piece is placed (paced as it waits)


## A waiting figure turns toward the nearest of `foes`; whether its facing changed.
static func face(f: Dictionary, foes: Array) -> bool:
	var me: Vector2 = f["xz"]
	var near: Vector2 = foes[0]["xz"]
	for g: Dictionary in foes:
		if me.distance_squared_to(g["xz"]) < me.distance_squared_to(near):
			near = g["xz"]
	var child: Dictionary = f["child"]
	var yaw := Map3DUnits.facing_yaw(near - me, float(child.get("stand_deg", 0.0)))
	if child.has("duel_yaw") and is_equal_approx(float(child["duel_yaw"]), yaw):
		return false
	child["duel_yaw"] = yaw
	return true


static func speed(anims: Array, scale: float) -> void:
	for anim: AnimationPlayer in anims:
		if is_instance_valid(anim):
			anim.speed_scale = scale


## The blow of turn `tt` meets, `over` seconds ago: told as an impact; near the
## camera the struck figure is knocked back and a burst shows at the meeting point.
static func contact(p: Dictionary, tt: Dictionary, over: float, tune: Dictionary, impacts: Array,
		bursts: Map3DImpactBursts) -> void:
	var s: Dictionary = tt["sf"]
	var d: Dictionary = tt["df"]
	var h := maxf(float(s["h"]), float(d["h"]))
	var at := (drawn(s) + drawn(d)) / 2.0 + Vector3.UP * h * float(tune.get("at_h", 0.5))  # where blade meets shield
	var kind := String(tt["kind"])
	impacts.append({"kind": kind, "at": at, "striker": s, "struck": d})
	var old: Dictionary = p.get("impact", {})
	if not old.is_empty():
		(old["child"] as Dictionary).erase("knock_offset")
	p.erase("impact")
	if tune.has("eye") and at.distance_to(tune["eye"]) > float(tune.get("near_m", INF)):
		return  # far out: the hit-stop alone
	var away := (d["xz"] as Vector2) - (s["xz"] as Vector2)
	p["impact"] = {"child": d["child"], "code": d["code"], "since": over,
		"away": away.normalized() * float(tune.get("knock_h", 0.0)) * h * (float(tune.get("block_knock", 1.0)) if kind == "BLOCK" else 1.0)}
	if bursts != null:
		bursts.burst(kind, at, h)


## The knock-back's clock (real seconds since contact) and its offset on the
## struck figure's child; the struck piece's code while it moved, else "".
static func knock(p: Dictionary, delta: float, tune: Dictionary) -> String:
	var imp: Dictionary = p.get("impact", {})
	if imp.is_empty():
		return ""
	imp["since"] = float(imp["since"]) + delta
	var k := Map3DImpact.knock(float(imp["since"]), float(tune["knock_out"]), float(tune["knock_back"]))
	var child: Dictionary = imp["child"]
	if k <= 0.0 and float(imp["since"]) > 0.0:
		child.erase("knock_offset")
		p.erase("impact")
	else:
		child["knock_offset"] = (imp["away"] as Vector2) * k
	return String(imp["code"])


## Where a figure is drawn now (its group node), else its stand point at ground 0.
static func drawn(f: Dictionary) -> Vector3:
	var node: Variant = (f["child"] as Dictionary).get("node")
	if is_instance_valid(node):
		return (node as Node3D).global_position
	var xz: Vector2 = (f["xz"] as Vector2) + (f["child"] as Dictionary).get("duel_offset", Vector2.ZERO)
	return Vector3(xz.x, 0.0, xz.y)
