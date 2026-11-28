class_name Map3DVolleys
extends RefCounted
## The arrow rain (spec 2026-11-28-archer-arrow-rain-design.md; view-only, no
## engine state written, no RNG draw): each archer figure of a unit the engine
## has firing (BattleRanged) loops ATTACK and looses ONE arrow as that
## clip crosses its release share (`army_art.csv` `contact` ATTACK), arcing to a
## hashed point among the nearest foe piece's figures of its battle; it sticks
## in the ground `map3d_volley_stick_s`, then fades. Every live arrow is one
## instance of the authored MultiMesh (`GameArt.ARROW_VOLLEY`; its mesh tip at
## the origin, the shaft along +Z, one figure height long). Run from
## Map3DDuelDriver.step in real seconds while the clock runs; paused, they stand.

var _was: Dictionary = {}  ## figure key -> its clip share last frame
var _n: Dictionary = {}  ## figure key -> its releases so far (the landing hash)
var _arrows: Array = []  ## {from, to, t, flight_s, apex, h, stuck_t}
var _claimed: Dictionary = {}  ## AnimationPlayer -> its piece: figures this layer plays ATTACK on
var _firing: Dictionary = {}  ## "code|day" -> whether the engine has it firing that day
var node: MultiMeshInstance3D  ## the drawn arrows; made by Map3DDuelDriver.step (none in a bare run)


static func tune_of(repo: DataRepository) -> Dictionary:
	var out := {}
	for key: String in ["near_m", "from_h", "speed_m", "min_s", "max_s", "apex", "scatter_h", "sink_h", "stick_s", "fade_s", "max"]:
		out[key] = repo.bal("map3d_volley_" + key)
	return out


## This frame's archer figures: [{key, share, release, from, h, targets}];
## `share` -1 when the figure looses nothing now. A unit fires when the ENGINE
## says it does (`BattleRanged.counts` `firing` > 0, worked out once a day): its
## standing figures are claimed (the `duel` meta, so the piece's action leaves
## them be) and loop their ATTACK, each from its hashed phase; once it stops
## firing, or a figure walks, the figure is handed back its piece's action.
## Arrows are drawn only within `near_m` of the camera.
func shots_of(ctx: Map3DContext, pieces: Dictionary, tune: Dictionary, running: bool) -> Array:
	var out: Array = []
	var eye: Variant = ctx.camera.global_position if ctx.camera != null else null
	var day := ctx.state().absolute_day()
	var held: Dictionary = {}
	for code: String in pieces:
		var piece: Dictionary = pieces[code]
		if piece.get("layout", "") != "physical_groups" or code.begins_with(Sighting.GHOST_CODE):
			continue
		var share_at := float(Map3DDuel.contact_of(ctx.repo.army_art.get(String(piece.get("model", "")), {})).get("ATTACK", -1.0))
		if share_at < 0.0:
			continue
		var battle := BattleSystem.battle_of(ctx.state(), code)
		if battle.is_empty() or int(battle.get("rounds", 0)) <= 0 or not _fires(ctx, battle, code, day):
			continue
		var root: Node3D = piece["node"]
		var near: bool = root.is_visible_in_tree() and (eye == null or (eye as Vector3).distance_to(root.global_position) <= float(tune["near_m"]))
		var targets := _targets(pieces, battle["def"] if code in battle["att"] else battle["att"], root.global_position)
		for group: Dictionary in piece["groups"]:
			var child: Dictionary = group["piece"]
			var anims: Array = child["anims"]
			if anims.is_empty() or not is_instance_valid(anims[0]):
				continue
			var anim: AnimationPlayer = anims[0]
			var key := "%s:%d" % [code, int(group["slot"])]
			var mine := _claimed.has(anim)
			if anim.has_meta("fallen") or (anim.has_meta("duel") and not mine) or child.get("walking", false):
				continue  # a body, a duellist, a figure walking in
			var clip := Map3DUnits.clip_named(anim, "ATTACK")
			if clip == "":
				continue
			held[anim] = true
			if not mine:
				_claimed[anim] = piece
				anim.set_meta("duel", true)
				Map3DClipChain.stop(anim)
				anim.play(clip, 0.2)
				anim.seek(Map3DMarchLag.unit("%s|volley" % key) * anim.current_animation_length, true)
			anim.speed_scale = 1.0 if running else 0.0
			var shot := {"key": key, "share": -1.0, "release": share_at, "targets": targets}
			if near and anim.current_animation == clip:
				var fig: Node3D = child["node"]
				var h := float(child["height_m"]) * fig.global_basis.get_scale().y
				shot["share"] = anim.current_animation_position / maxf(anim.current_animation_length, 0.001)
				shot["h"] = h
				shot["from"] = fig.global_position + Vector3.UP * h * float(tune["from_h"])
			out.append(shot)
	for anim: Variant in _claimed.keys():
		if not held.has(anim):
			_hand_back(anim, _claimed[anim])
	return out


## Whether `code` fires today, by the engine's own count (cached for the day).
func _fires(ctx: Map3DContext, battle: Dictionary, code: String, day: int) -> bool:
	var k := "%s|%d" % [code, day]
	if not _firing.has(k):
		if _firing.size() > 256:
			_firing.clear()
		_firing[k] = int(BattleRanged.counts(ctx.repo, ctx.state(), battle, code).get("firing", 0)) > 0
	return _firing[k]


## A figure no longer firing takes its piece's action again (unless it fell meanwhile).
func _hand_back(anim: Variant, piece: Dictionary) -> void:
	_claimed.erase(anim)
	if not is_instance_valid(anim) or (anim as AnimationPlayer).has_meta("fallen"):
		return
	(anim as AnimationPlayer).remove_meta("duel")
	(anim as AnimationPlayer).speed_scale = 1.0
	var action := String(piece.get("action", ""))
	Map3DUnitRig.play([anim], action if action != "" else "GARRISON", 0.2)


## Where the nearest drawn foe piece among `foes` to `at` has its figures now.
static func _targets(pieces: Dictionary, foes: Array, at: Vector3) -> Array:
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
	var out: Array = []
	for g: Dictionary in best["groups"]:
		var fig: Variant = (g["piece"] as Dictionary).get("node")
		if is_instance_valid(fig):
			var at_xz := (fig as Node3D).global_position
			out.append(Vector2(at_xz.x, at_xz.z))  # where it is drawn now (a walking-in foe too)
	return out


## One frame from Map3DDuelDriver.step: the MultiMesh made on first use beside the pieces, then fly and draw.
func step(ctx: Map3DContext, pieces: Dictionary, delta: float) -> void:
	if node == null and not pieces.is_empty():
		var first: Variant = (pieces.values()[0] as Dictionary).get("node")
		var scene := load(GameArt.ARROW_VOLLEY) as PackedScene if ResourceLoader.exists(GameArt.ARROW_VOLLEY) else null
		if scene != null and is_instance_valid(first) and (first as Node3D).get_parent() is Node3D:
			node = scene.instantiate() as MultiMeshInstance3D
			node.multimesh = node.multimesh.duplicate()  # its own instances
			node.top_level = true  # the arrows are written in world space
			(first as Node3D).get_parent().add_child(node)
	var tune := Map3DVolleys.tune_of(ctx.repo)
	var running := ctx.clock_speed() > 0
	var shots := shots_of(ctx, pieces, tune, running)
	run(shots, delta, running, tune, ctx.height_at)
	if is_instance_valid(node):
		write(node.multimesh, tune)


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
