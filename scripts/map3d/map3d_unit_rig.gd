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
## (`stride_m`, data/army_art.csv, the model metres a loop carries it) in the
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
## move read as a standstill (owner 2026-09-30: 走路速度怎么时快时慢). 0 on a
## stopped clock.
static func walk_speed(day: Dictionary, day_s: float, clock: int) -> float:
	if clock <= 0 or day_s <= 0.0:
		return 0.0
	var span := (1.0 - float(day["s0"])) * day_s / float(clock)
	return (day["from"] as Vector2).distance_to(day["to"]) / maxf(span, 0.001)


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
## `blend_s`; one without it keeps its own (Map3DLayerUnits.play). Men at rest
## are not clones (each seeks its own phase); a column marches in step.
static func play(anims: Array, action: String, blend_s: float) -> void:
	for i in anims.size():
		var anim: AnimationPlayer = anims[i]
		var clip := Map3DUnits.clip_named(anim, action)
		if clip == "" or anim.current_animation == clip:
			continue
		anim.play(clip, blend_s)  # blended, never a snap
		if action != "MARCH":
			anim.seek(fposmod(i * 0.37, anim.current_animation_length))


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
