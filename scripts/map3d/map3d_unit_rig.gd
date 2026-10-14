class_name Map3DUnitRig
extends RefCounted
## What a 3D piece's own rig and its day's march say about how it MOVES and
## where its chip hangs — the gait's playback rate and the head the headcount
## chip hangs over (owner 2026-09-30). Pure, like Map3DUnits, whose sibling it
## is; never reaches for the Game autoload.


## A looped gait's playback rate so its feet keep pace with the ground: world
## speed over the piece's scale is the model's speed; a loop of `clip_s`
## seconds covers `stride_m` model metres. Held within [lo, hi] — a miniature
## crossing kilometres a day outruns any leg. 1.0 when the stride is unknown.
static func gait_rate(world_speed: float, k: float, clip_s: float, stride_m: float,
		lo: float, hi: float) -> float:
	if world_speed <= 0.0 or k <= 0.0 or stride_m <= 0.0:
		return 1.0
	return clampf(world_speed / k * clip_s / stride_m, lo, hi)


## The MARCH clip's playback rate (owner 2026-09-27: 马的腿移动的步幅和它实际移
## 动的距离不符): the ground the piece covers per second in its MODEL'S metres
## (world speed / its scale k) over what one loop of the clip walks
## (`stride_m`, data/screens/map3d/army_art.csv, the model metres a loop carries it) in the
## clip's `clip_s` — so the feet keep pace with the ground — held within
## map3d_unit_anim_min..max: a miniature crossing kilometres a second outruns
## any leg, and past the ceiling it slides rather than blurs.
static func march_rate(repo: DataRepository, world_speed: float, k: float, clip_s: float,
		stride_m: float) -> float:
	return gait_rate(world_speed, k, clip_s, stride_m,
		repo.bal("map3d_unit_anim_min"), repo.bal("map3d_unit_anim_max"))


## How high a figure's HEAD stands in its own metres — where its headcount
## chip hangs (owner 2026-09-30: 兵人的icon和模型间隔太远了): the rest height of
## its `head` bone, raised `map3d_unit_head_top` of itself for the helmet over
## it. Not model_size's top: that is the upright spear's or lance's tip, a
## third of a man over his head. `fallback` when the model has no head bone.
static func head_m(repo: DataRepository, node: Node3D, fallback: float) -> float:
	var skel := _skeleton(node)
	if skel == null:
		return fallback
	var bone := -1
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower() == "head":
			bone = i
			break
	if bone < 0:
		return fallback
	var y := (_local_to(node, skel) * skel.get_bone_global_rest(bone)).origin.y
	return clampf(y * (1.0 + repo.bal("map3d_unit_head_top")), 0.0001, fallback)


## The world speed a piece walks its day's march at (world metres per real
## second): the `day` from `from` to `to` over the part of the day left after
## `s0`, at `clock` times the day's `day_s` seconds. The gait is timed from
## this PLAN, never from a frame's own step, which a frame that happened not to
## move read as a standstill (owner 2026-09-30: 走路速度怎么时快时慢). The
## distance is the ROUTE's, by its `via` corners, as along_day walks it. 0 on a
## stopped clock.
static func walk_speed(day: Dictionary, day_s: float, clock: int) -> float:
	if clock <= 0 or day_s <= 0.0:
		return 0.0
	var span := (1.0 - float(day["s0"])) * day_s / float(clock)
	var pts := PackedVector2Array([day["from"]]) + (day.get("via", PackedVector2Array()) as PackedVector2Array) \
		+ PackedVector2Array([day["to"]])
	var dist := 0.0
	for i in range(1, pts.size()):
		dist += pts[i - 1].distance_to(pts[i])
	return dist / maxf(span, 0.001)


static func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _skeleton(c)
		if s != null:
			return s
	return null


## `child`'s transform in `root`'s space off the tree (the local chain).
static func _local_to(root: Node3D, child: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Puts a piece's figures (`anims`) into an action by name, blended over
## `blend_s`; one without it keeps its own (Map3DLayerUnits.play). No figure is
## a clone: a MARCH starts at the figure's hashed phase of the clip
## (Map3DMarchLag.phase, `code` + index), any other action at its own seek.
static func play(anims: Array, action: String, blend_s: float, code: String = "") -> void:
	for i in anims.size():
		var anim: AnimationPlayer = anims[i]
		var clip := Map3DUnits.clip_named(anim, action)
		anim.set_meta("want_action", action)
		if clip == "" or anim.current_animation == clip:
			continue
		anim.play(clip, blend_s)  # blended, never a snap
		var share := Map3DMarchLag.phase(code, i) if action == "MARCH" else fposmod(i * 0.37, 1.0)
		anim.seek(share * anim.current_animation_length, true)


## Each figure trails its slot by a lag spring in the piece's own frame: the
## piece moved `world_v` (world metres/s) this frame; the figure's offset follows
## Map3DMarchLag.step with its hashed tau, held to the piece's `lag_cap` and
## relaxing to its slot once the piece stands; with `height_at` each moved figure is
## planted again on its ground (`plant`). View-only; nothing is stored in state.
static func lag(repo: DataRepository, piece: Dictionary, code: String, world_v: Vector2,
		dt: float, height_at: Callable = Callable()) -> void:
	var node: Node3D = piece["node"]
	if world_v == Vector2.ZERO and not piece.get("lagging", false):
		return
	var figs: Array = piece["figs"]  # taken at build, before any glow quad is a child
	if not piece.has("lags"):
		piece["lags"] = figs.map(func(_f: Node) -> Vector3: return Vector3.ZERO)
		piece["taus"] = range(figs.size()).map(func(i: int) -> float: return Map3DMarchLag.tau(
			code, i, repo.bal("map3d_march_lag_min_s"), repo.bal("map3d_march_lag_max_s")))
		piece["lag_vmax"] = float(piece.get("lag_cap", 0.0)) / maxf(repo.bal("map3d_march_lag_max_s"), 0.0001)
	# a velocity past cap / max_s would pin every figure to the cap alike; limited,
	# the steady lag is (tau / max_s) x cap: its own per figure, never past the cap
	var v: Vector3 = node.transform.basis.inverse() * Vector3(world_v.x, 0.0, world_v.y)
	v.y = 0.0  # on a slope the walk has a part along the piece's up; the trail is IN its plane
	v = v.limit_length(float(piece["lag_vmax"]))
	var slots: Array = piece["slots"]
	var taus: Array = piece["taus"]
	var lags: Array = piece["lags"]
	var cap := float(piece.get("lag_cap", 0.0))
	var live := false
	for i in mini(figs.size(), slots.size()):
		var o := Map3DMarchLag.step(lags[i], v, taus[i], dt, cap)
		if world_v == Vector2.ZERO and o.length() < 0.002 * cap:
			o = Vector3.ZERO
		lags[i] = o
		live = live or o != Vector3.ZERO
		(figs[i] as Node3D).position = slots[i] + o
	piece["lagging"] = live or world_v != Vector2.ZERO
	if height_at.is_valid():
		plant(repo, height_at, piece)


## Stands every figure of `piece` on the ground UNDER IT (owner 2026-10-12: 走在
## 斜坡上飘, 不同模型所处的高度是不同的). The piece is one plane, raised until no
## ground under its footprint stands above it, so on a slope the low figures hover
## by the slope's fall across the formation; each figure's local y is solved so its
## foot is at the heightmap under its own (x, z) plus the seat's clearance. The lift
## moves a foot sideways on a tilted piece, so it is solved three times. Call after
## `seat` (which calls it) and `lag` (it reads the figures' own x, z, the slot and its trail).
static func plant(repo: DataRepository, height_at: Callable, piece: Dictionary) -> void:
	var node: Node3D = piece["node"]
	var t := node.transform
	var up := t.basis.y.y  # world metres per local metre of height
	if up <= 0.0001:
		return
	var clear := float(piece["height_m"]) * t.basis.get_scale().x * repo.bal("map3d_unit_seat_clear") \
		- repo.bal("map3d_unit_sink_m")
	for fig: Node3D in piece["figs"]:
		var p := Vector3(fig.position.x, 0.0, fig.position.z)
		var flat := (t * p).y
		var w := t * p
		for _pass in 3:
			p.y = (float(height_at.call(Vector2(w.x, w.z))) + clear - flat) / up
			w = t * p
		fig.position = p


## Seats `piece` at world `xz` facing `yaw` at scale `k` (Map3DUnits.seat; owner
## 2026-09-24: 斜面上兵人的一部分会被地图盖住): tilted with its footprint's ground,
## raised by a clearance that grows with it — far out the ground is DRAWN by a
## coarser Terrain3D mesh than the heightmap sampled here. Keeps where it stands
## (`ground`) and how far over its seat (`lift`) on the piece.
static func seat(repo: DataRepository, height_at: Callable, piece: Dictionary, xz: Vector2,
		yaw: float, k: float) -> void:
	var sit := Map3DUnits.seat_at(repo, height_at, xz, piece["extent"], yaw, k)
	var high := float(piece["height_m"]) * k
	var ground := Vector3(xz.x, float(sit["y"]) + high * repo.bal("map3d_unit_seat_clear")
		- repo.bal("map3d_unit_sink_m"), xz.y)
	var up: Vector3 = sit["normal"]
	(piece["node"] as Node3D).transform = Transform3D((Basis(Quaternion(Vector3.UP, up))
		* Basis(Vector3.UP, yaw)).scaled(Vector3(k, k, k)), ground)
	piece["ground"] = ground
	piece["lift"] = ground.y - float(sit["y"])
	if piece.has("figs"):
		plant(repo, height_at, piece)  # the plane moved: every figure back on its own ground


## The action a piece plays (pure; spec 2026-10-11-war-room-front-line-design
## §2): MARCH while it walks on a running clock; else its stance's standing
## clip (`stand_clip`, DEFEND for hold) when it is not marching; else GARRISON
## under that order, else STANDBY.
static func action_for(walking_now: bool, order: String, stance_row: Dictionary) -> String:
	if walking_now:
		return "MARCH"
	var stand := String(stance_row.get("stand_clip", ""))
	if stand != "" and order != ArmySystem.ORDER_MARCH:
		return stand
	return "GARRISON" if order == ArmySystem.ORDER_GARRISON else "STANDBY"


## The way a piece faces: a front it holds wins (spec 2026-10-11-war-room-
## front-line-design §1); else the way it last advanced (`track`,
## Map3DUnits.track); a piece never moved, its order's way (else at rest).
static func heading_for(repo: DataRepository, state: GameState, code: String, track: Dictionary) -> Vector2:
	var heading := ArmySystem.facing_of(state, code)
	if heading == Vector2.ZERO:
		heading = track.get("heading", Vector2.ZERO)
	return heading if heading != Vector2.ZERO else ArmySystem.heading_of(repo, state, code)


## The feet keep pace with the ground, timed from the day's PLAN (walk_speed,
## march_rate); 1 at rest, where no figure is jittered. A marching figure's
## speed_scale gets its own hashed jitter, clamped after it. Set only on a change.
static func keep_pace(repo: DataRepository, piece: Dictionary, day: Dictionary, share: float, clock: int,
		code: String = "") -> void:
	if piece.get("settling", false):
		return  # a halt held to its next footfall walks on at its pace (Map3DUnitSettle)
	var walking := Map3DUnits.walking(day, share)
	# an exact-pace arm (army_art.csv exact_pace, owner 2026-10-14: 步伐和移动能够完全匹配)
	# plays the true rate at any speed, every figure alike: no bounds, no jitter
	var exact := bool(piece.get("exact_pace", false))
	var lo := 0.0 if exact else repo.bal("map3d_unit_anim_min")
	var hi := INF if exact else repo.bal("map3d_unit_anim_max")
	var pace := gait_rate(walk_speed(day, repo.bal("time_day_seconds"), clock),
		(piece["node"] as Node3D).transform.basis.get_scale().x, float(piece["clip_s"]),
		float(piece["stride_m"]), lo, hi) if walking else 1.0
	var key := [pace, walking]
	if piece.get("pace_key", []) != key:
		piece["pace_key"] = key
		var anims: Array = piece["anims"]
		var spread := 0.0 if exact else repo.bal("map3d_march_desync_pace")
		var statures: Array = piece.get("statures", [])
		for i in anims.size():
			# a figure at stature s strides s times as far: s times slower keeps its feet
			var own := pace / float(statures[i]) if exact and i < statures.size() else pace
			(anims[i] as AnimationPlayer).speed_scale = Map3DMarchLag.pace(code, i, own,
				spread, lo, hi) if walking else 1.0
