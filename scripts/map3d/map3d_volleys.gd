class_name Map3DVolleys
extends RefCounted
## The arrow rain (spec 2026-11-28-archer-arrow-rain-design.md; view-only, no
## engine state, no RNG draw): each archer figure looses ONE arrow as its ATTACK
## clip crosses its release share (`army_art.csv` `contact` ATTACK), arcing to a
## hashed point among the nearest foe piece's figures of its battle; it sticks
## in the ground `map3d_volley_stick_s`, then fades. Every live arrow is one
## instance of the authored MultiMesh (`GameArt.ARROW_VOLLEY`; its mesh tip at
## the origin, the shaft along +Z, one figure height long). Run from
## Map3DDuelDriver.step in real seconds while the clock runs; paused, they stand.

var _was: Dictionary = {}  ## figure key -> its clip share last frame
var _n: Dictionary = {}  ## figure key -> its releases so far (the landing hash)
var _arrows: Array = []  ## {from, to, t, flight_s, apex, h, stuck_t}
var node: MultiMeshInstance3D  ## the drawn arrows; made by Map3DDuelDriver.step (none in a bare run)


static func tune_of(repo: DataRepository) -> Dictionary:
	var out := {}
	for key: String in ["near_m", "from_h", "speed_m", "min_s", "max_s", "apex", "scatter_h", "sink_h", "stick_s", "fade_s", "max"]:
		out[key] = repo.bal("map3d_volley_" + key)
	return out


## This frame's archer figures: [{key, share, from, h, targets}]; `share` -1
## when the figure is not on its ATTACK clip (or too far from the camera to draw).
static func shots_of(ctx: Map3DContext, pieces: Dictionary, tune: Dictionary) -> Array:
	var out: Array = []
	var eye: Variant = ctx.camera.global_position if ctx.camera != null else null
	for code: String in pieces:
		var piece: Dictionary = pieces[code]
		if piece.get("layout", "") != "physical_groups" or code.begins_with(Sighting.GHOST_CODE):
			continue
		var share_at := float(Map3DDuel.contact_of(ctx.repo.army_art.get(String(piece.get("model", "")), {})).get("ATTACK", -1.0))
		if share_at < 0.0:
			continue
		var battle := BattleSystem.battle_of(ctx.state(), code)
		if battle.is_empty() or int(battle.get("rounds", 0)) <= 0:
			continue
		var root: Node3D = piece["node"]
		var near: bool = root.is_visible_in_tree() and (eye == null or (eye as Vector3).distance_to(root.global_position) <= float(tune["near_m"]))
		var targets := _targets(ctx, pieces, battle["def"] if code in battle["att"] else battle["att"], root.global_position)
		for group: Dictionary in piece["groups"]:
			var child: Dictionary = group["piece"]
			var anims: Array = child["anims"]
			var fig: Node3D = child["node"]
			var shot := {"key": "%s:%d" % [code, int(group["slot"])], "share": -1.0, "release": share_at, "targets": targets}
			if near and not anims.is_empty() and is_instance_valid(anims[0]) and not targets.is_empty():
				var anim: AnimationPlayer = anims[0]
				var clip := Map3DUnits.clip_named(anim, "ATTACK")
				if clip != "" and anim.current_animation == clip and not anim.has_meta("duel"):
					var h := float(child["height_m"]) * fig.global_basis.get_scale().y
					shot["share"] = anim.current_animation_position / maxf(anim.current_animation_length, 0.001)
					shot["h"] = h
					shot["from"] = fig.global_position + Vector3.UP * h * float(tune["from_h"])
			out.append(shot)
	return out


## The stand points of the nearest drawn foe piece among `foes` to `at`.
static func _targets(ctx: Map3DContext, pieces: Dictionary, foes: Array, at: Vector3) -> Array:
	var best := {}
	var best_d := INF
	for foe: String in foes:
		var p: Dictionary = pieces.get(foe, {})
		if p.get("layout", "") != "physical_groups" or not (p["node"] as Node3D).is_visible_in_tree():
			continue
		var d := (p["node"] as Node3D).global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		return []
	return (best["groups"] as Array).map(func(g: Dictionary) -> Vector2:
		return Map3DBattleGroups.stand_xz(ctx, best, g) + (g["piece"] as Dictionary).get("duel_offset", Vector2.ZERO))


## One frame: release the arrows whose clip crossed its share, fly, stick, fade.
## `ground` (Callable Vector2 -> float) is the terrain height.
func run(shots: Array, delta: float, running: bool, tune: Dictionary, ground: Callable) -> void:
	if not running:
		return
	var seen: Dictionary = {}
	for shot: Dictionary in shots:
		var key := String(shot["key"])
		seen[key] = true
		var share := float(shot["share"])
		var was := float(_was.get(key, -1.0))
		_was[key] = share
		if share < 0.0 or was < 0.0 or not Map3DVolley.released(was, share, float(shot["release"])) \
				or (shot["targets"] as Array).is_empty() or _arrows.size() >= int(tune["max"]):
			continue
		var n := int(_n.get(key, 0))
		_n[key] = n + 1
		var h := float(shot["h"])
		var land := Map3DVolley.landing(key, n, shot["targets"], h * float(tune["scatter_h"]))
		var from: Vector3 = shot["from"]
		var to := Vector3(land.x, float(ground.call(land)), land.y)
		var dist := Vector2(from.x, from.z).distance_to(land)
		_arrows.append({"from": from, "to": to, "t": 0.0, "flight_s": Map3DVolley.flight_s(dist, tune),
			"apex": dist * float(tune["apex"]), "h": h, "stuck_t": -1.0})
	for key: String in _was.keys():
		if not seen.has(key):
			_was.erase(key)  # a figure gone: its arrows fly on, its next clip starts afresh
	var keep: Array = []
	for a: Dictionary in _arrows:
		a["t"] = float(a["t"]) + delta
		if float(a["t"]) >= float(a["flight_s"]):
			a["stuck_t"] = float(a["t"]) - float(a["flight_s"])
		if float(a["stuck_t"]) < float(tune["stick_s"]) + float(tune["fade_s"]):
			keep.append(a)
	_arrows = keep


func live() -> Array: return _arrows


## The arrow's tip and its shaft's way at its age; stuck, its tip `sink_h` heights into the ground.
static func pose(a: Dictionary, tune: Dictionary) -> Transform3D:
	var s := clampf(float(a["t"]) / float(a["flight_s"]), 0.0, 1.0)
	var way := Map3DVolley.heading(a["from"], a["to"], s, float(a["apex"]))
	var tip := Map3DVolley.at(a["from"], a["to"], s, float(a["apex"]))
	if float(a["stuck_t"]) >= 0.0:
		tip += way * float(a["h"]) * float(tune["sink_h"])
	var up := Vector3.UP if absf(way.y) < 0.99 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(way, up).scaled_local(Vector3.ONE * float(a["h"])), tip)


## Instance alpha: whole until `stick_s` in the ground, then fading over `fade_s`.
static func alpha(a: Dictionary, tune: Dictionary) -> float:
	var stuck := float(a["stuck_t"])
	return 1.0 if stuck < float(tune["stick_s"]) else clampf(1.0 - (stuck - float(tune["stick_s"])) / maxf(float(tune["fade_s"]), 0.001), 0.0, 1.0)


func write(mm: MultiMesh, tune: Dictionary) -> void:
	if mm.instance_count < int(tune["max"]):
		mm.instance_count = int(tune["max"])
	mm.visible_instance_count = _arrows.size()
	for i: int in _arrows.size():
		mm.set_instance_transform(i, pose(_arrows[i], tune))
		if mm.use_colors:
			mm.set_instance_color(i, Color(1, 1, 1, alpha(_arrows[i], tune)))
