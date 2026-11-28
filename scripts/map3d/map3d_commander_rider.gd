class_name Map3DCommanderRider
extends Node3D
## A unit's mounted commander on the map (spec 2026-11-27-commander-figure-design): one rider
## under his realm's banner, alone and centred ahead of his unit's first rank; while his unit
## fights, at its left rear seen facing the enemy, commanding. He RIDES between the two places
## round the unit's left flank. He is a child of the unit's piece (Map3DUnitDress.sync hangs him
## there), so he is shown, hidden and freed with it; each frame he reads the piece and stands,
## sizes and plays himself. He is no formation slot, no figure of the piece and no number: neither
## the engine nor the save knows him. Never reaches for the Game autoload.

const NAME := "Commander"
const WALK := "MARCH_WALK"  ## the march ahead of foot; MARCH is the gallop
const BATTLE := "physical_groups"
const PICK_TOP := &"commander_pick_top"  ## on his meshes: the height (mesh metres) a click's ray tests him to

var _repo: DataRepository
var _ctx: Map3DContext
var _piece: Dictionary  ## the unit's live piece (Map3DLayerUnits._pieces[code])
var _code := ""
var _gallops := false  ## his unit's arm rides (army_art.csv commander_gallops)
var _blend_s := 0.0
var _figure: Node3D
var _anim: AnimationPlayer
var _half := Vector2.ZERO  ## his own half extents, model metres
var _height := 1.0  ## his model box's height, banner tip included
var _stood: Array = []  ## what he was last stood from
var _clips: Dictionary = {}  ## action -> his clip's name on the player
var _turn := 0.0  ## radians a second he turns on a ride (the Units node's turn_deg_per_s)
var _at := Vector2.ZERO  ## where he is drawn, in his piece's flat frame (x, z)
var _yaw := 0.0  ## the way he is turned there
var _route := PackedVector2Array()  ## the corners still ahead of him on a ride, the last his place
var _moving := false  ## on a ride, or still turning to his facing at its end
var _keeping := false  ## he covered a walk's ground last frame: he keeps with a place that moves
var _gait := WALK  ## the clip he rides on this frame
var _pace := 0.0  ## that gait's own pace, model metres a second
var _drawn := false  ## he stands somewhere: a new place is RIDDEN to, never appeared at
var _sized: Array = []  ## the scales `_at` was measured in
var _state: GameState  ## the state he last stood under: a swapped one (a loaded save) rides nobody
var _from: Array = []  ## [world xz, world yaw] of the rider of the piece this one replaced
var _anchor := Vector2.ZERO  ## where his battle block's root stood, world xz


## Whether a unit's piece gets the figure: a commander is appointed and it is not the king's own
## unit, whose rider is the king himself.
static func leads(reg: Dictionary, state: GameState) -> bool:
	if state == null or String(reg.get("is_royal", "0")) == "1":
		return false
	var roster: Dictionary = state.military_rosters.get(String(reg.get("regiment_code", "")), {})
	return String(roster.get("commander_id", "")) != ""


## The clip he plays for his unit's `action`: his march only while an ordinary piece marches
## (the gallop ahead of an arm that rides, else the walk); standing, and in a battle block before
## its first round, STANDBY; in the `fight`, COMMAND.
static func clip_for(action: String, layout: String, gallops: bool, fight := false) -> String:
	if layout == BATTLE and fight:
		return "COMMAND"
	if action != "MARCH" or layout == BATTLE:
		return "STANDBY"
	return "MARCH" if gallops else WALK


## How far ahead of the first rank's front his centre stands, world metres at his scale `k`:
## `gap` of his own lengths clear, then half his length (`half_len`, model metres).
static func lead_m(half_len: float, gap: float, k: float) -> float:
	return half_len * (1.0 + 2.0 * gap) * k


## His lead in a stand-off, world metres: `share` of the clear ground between his first rank and
## the nearest enemy figure (`room`), never past his ordinary `lead`, so the two sides' commanders
## keep the middle of that ground between them; -1 when that would back his tail into his own rank
## (`least`, his half length): lines that close leave him no place between them, and he stands
## beside the left end of his first rank instead (first_rank_left_of).
static func standoff_lead(lead: float, room: float, share: float, least: float) -> float:
	var out := minf(room * share, lead)
	return out if out >= least else -1.0


## A battle block's first rank: its front edge at the block's middle, as an offset from the
## points' origin. `points` are the figures' places, `reaches` how far each reaches ahead of its
## place, `face` the unit's facing (a unit vector), all in one flat frame.
static func front_of(points: PackedVector2Array, reaches: PackedFloat32Array, face: Vector2) -> Vector2:
	var across := Vector2(-face.y, face.x)
	var front := -INF
	var lo := INF
	var hi := -INF
	for i in points.size():
		front = maxf(front, points[i].dot(face) + reaches[i])
		lo = minf(lo, points[i].dot(across))
		hi = maxf(hi, points[i].dot(across))
	return face * front + across * (lo + hi) * 0.5 if not points.is_empty() else Vector2.ZERO


## A block's left rear seen facing `face`: the outside of its left file, level with its rear rank
## (the rearmost figures' own places), as an offset from the points' origin. `sides` is how far
## each figure reaches to its side; the frame is front_of's.
static func left_rear_of(points: PackedVector2Array, sides: PackedFloat32Array, face: Vector2) -> Vector2:
	var across := Vector2(-face.y, face.x)  # the unit's right
	var left := INF
	var rear := INF
	for i in points.size():
		left = minf(left, points[i].dot(across) - sides[i])
		rear = minf(rear, points[i].dot(face))
	return face * rear + across * left if not points.is_empty() else Vector2.ZERO


## The left end of a block's first rank seen facing `face`: the outside of its left file, level
## with the foremost figures' own places, in left_rear_of's frame. Where he stands in a stand-off
## whose lines leave him no place between them (owner 2026-11-28: 站第一排左端旁边).
static func first_rank_left_of(points: PackedVector2Array, sides: PackedFloat32Array, face: Vector2) -> Vector2:
	var across := Vector2(-face.y, face.x)
	var left := INF
	var rank := -INF
	for i in points.size():
		left = minf(left, points[i].dot(across) - sides[i])
		rank = maxf(rank, points[i].dot(face))
	return face * rank + across * left if not points.is_empty() else Vector2.ZERO


## How far outside the left file his centre stands in a fight, world metres at his scale `k`:
## `gap` of his own lengths clear, then half his width (`half_wid`, `half_len`: model metres).
static func side_m(half_wid: float, half_len: float, gap: float, k: float) -> float:
	return (half_wid + 2.0 * half_len * gap) * k


## The corners he rides through from `from` to `to` (the last is `to`), round his block and never
## through it. In the frame of `face`: `left` / `right` are the outsides of its flank files,
## `front` its first rank's front, `rear` its rear rank's back. A leg is clear when both its ends
## are outside one flank, both ahead of the first rank, or both behind the rear rank; the way is
## the SHORTEST of clear legs through the block's four corners (each as far out as the further-out
## end, and `margin` clear of the flank files / `margin_y` of the ranks at least; the left wins a
## tie), so from ahead of the first rank to the left rear it goes round the left flank. Every turn
## on the way, and the turn to `face` at its end, counts `about` metres a half turn: where two ways
## are near in length he takes the one with less turning, and comes onto his place already facing
## the enemy rather than riding past it and back. EMPTY when there is none (he stands inside the
## block): he is stood at `to` at once.
static func route(from: Vector2, to: Vector2, face: Vector2, left: float, right: float, front: float, rear: float,
		margin := 0.0, margin_y := 0.0, about := 0.0) -> PackedVector2Array:
	var across := Vector2(-face.y, face.x)
	var a := Vector2(from.dot(across), from.dot(face))
	var b := Vector2(to.dot(across), to.dot(face))
	var xl := minf(minf(a.x, b.x), left - margin)
	var xr := maxf(maxf(a.x, b.x), right + margin)
	var ahead := maxf(maxf(a.y, b.y), front + margin_y)
	var behind := minf(minf(a.y, b.y), rear - margin_y)
	var best: Array = [INF, []]
	_ways([a, Vector2(xl, ahead), Vector2(xl, behind), Vector2(xr, ahead), Vector2(xr, behind), b], [0], 0.0, Vector2.ZERO,
		[left, right, front, rear], about, best)
	var legs := PackedVector2Array()
	if float(best[0]) < INF:
		for k: int in best[1]:
			legs.append(to if k == 5 else across * (best[2] as Array)[k].x + face * (best[2] as Array)[k].y)
	return legs


## route's search: every way from the last point of `path` (indices into `at`: the start, the four
## corners, the end) on to the end by clear legs, its `cost` so far the legs ridden plus `about` a
## half turn; the cheapest is kept in `best` ([cost, the indices after the start, at]).
static func _ways(at: Array, path: Array, cost: float, heading: Vector2, box: Array, about: float, best: Array) -> void:
	var p: Vector2 = at[path[-1]]
	for k: int in [5, 1, 2, 3, 4]:  # straight on first, then the left corners: they win a tie
		var q: Vector2 = at[k]
		if k in path or not ((p.x <= box[0] and q.x <= box[0]) or (p.x >= box[1] and q.x >= box[1])
				or (p.y >= box[2] and q.y >= box[2]) or (p.y <= box[3] and q.y <= box[3])):
			continue
		var leg := q - p
		var way := leg if leg.length() > 0.0001 else heading
		var c := cost + leg.length() + (about * absf(heading.angle_to(way)) / PI if heading != Vector2.ZERO else 0.0)
		if k == 5:
			c += about * absf(way.angle_to(Vector2(0.0, 1.0))) / PI if way != Vector2.ZERO else 0.0
			if c < float(best[0]) - 0.0001:
				best[0] = c
				best[1] = path.slice(1) + [5]
				if best.size() < 3:
					best.append(at)
		elif c < float(best[0]):
			_ways(at, path + [k], c, way, box, about, best)


## One frame of his ride: from `at` turned `yaw` toward the next corner of `route`, `step` metres
## of the route's frame and `turn` radians at most. He rides the way he FACES, turning as he goes,
## so a corner is an arc (of `step` / `turn` metres' radius) and is passed once he is that near it;
## on the last stretch (two of those radii) he rides straight onto his place, only as far as he
## faces it; there he turns to `goal_yaw`. -> [at, yaw, the route left].
static func ride(at: Vector2, yaw: float, route_left: PackedVector2Array, goal_yaw: float, step: float, turn: float) -> Array:
	var left := route_left.duplicate()
	while not left.is_empty() and at.distance_to(left[0]) <= 0.0001:
		at = left[0]
		left.remove_at(0)
	if left.is_empty():
		return [at, rotate_toward(yaw, goal_yaw, turn), left]
	var way := left[0] - at
	var want := Map3DUnits.facing_yaw(way)
	var radius := step / turn if turn > 0.0 else 0.0
	yaw = rotate_toward(yaw, want, turn)
	if left.size() == 1 and way.length() <= maxf(step, 2.0 * radius):
		var go := step * maxf(cos(angle_difference(yaw, want)), 0.0)
		if go >= way.length():
			at = left[0]
			left.remove_at(0)
		else:
			at += way.normalized() * go
	else:
		at += Vector2(-sin(yaw), -cos(yaw)) * step  # the way a yaw faces (Map3DUnits.yaw_for)
		if left.size() > 1 and at.distance_to(left[0]) <= maxf(step, radius):
			left.remove_at(0)
	return [at, yaw, left]


## His march clip's rate so his hooves keep his unit's ground: the men play `pace` times a clip
## of `arm_clip_s` that walks `arm_stride` model metres at scale `arm_k`; his loop of `clip_s`
## walks `stride` at `k`. 1 when a measure is missing.
static func march_rate(pace: float, arm_stride: float, arm_clip_s: float, arm_k: float,
		stride: float, clip_s: float, k: float) -> float:
	if arm_stride <= 0.0 or arm_clip_s <= 0.0 or stride <= 0.0 or k <= 0.0:
		return 1.0
	return pace * arm_stride / arm_clip_s * arm_k / k * clip_s / stride


## Hangs, keeps or frees the commander of `piece` (a piece of the Units layer, in the tree) for
## its roster row `reg`; `flags` is the layer's realm flag table.
static func sync(repo: DataRepository, piece: Dictionary, reg: Dictionary, flags: ArtTable) -> void:
	var root := piece.get("node") as Node3D
	var layer := root.get_parent() as Map3DLayerUnits if root != null else null
	if layer == null or layer.ctx == null:
		return
	var rider := root.get_node_or_null(NAME) as Map3DCommanderRider
	if not leads(reg, layer.ctx.state()):
		if rider != null:
			rider.free()
		return
	if rider == null:
		var scene := Map3DAssetCache.scene(Map3DCommanderFigure.SCENE)
		if scene == null:
			Map3DWorldLoader.warn_once("commander", "map3d units: no model at " + Map3DCommanderFigure.SCENE)
			return
		rider = Map3DCommanderRider.new()
		rider.name = NAME
		rider._figure = scene.instantiate() as Node3D
		rider.add_child(rider._figure)
		rider._anim = Map3DUnits.find_anim(rider._figure)
		rider._half = Map3DUnits.stand_extent(rider._figure)
		rider._height = Map3DUnits.model_size(rider._figure).y
		# a click picks him by his horse and body, not by the air round his banner (Map3DPicker.ray_depth)
		var head := Map3DUnitRig.head_m(repo, rider._figure, rider._height)
		for mi: MeshInstance3D in Map3DUnits.meshes(rider._figure):
			mi.set_meta(PICK_TOP, (Map3DUnitRig._local_to(rider._figure, mi).affine_inverse() * Vector3(0.0, head, 0.0)).y)
		rider.visible = false  # his piece is not seated yet: he stands, and is first seen, on the next frame
		root.add_child(rider)  # no owner: never saved into the authored scene
		# a piece REPLACED in this refresh (a block gone into its battle, or out of it) is freed as the
		# frame ends: its rider says where he stood, and this one rides on from there
		for old: Node in layer.get_children():
			var was := old.get_node_or_null(NAME) as Map3DCommanderRider if old.is_queued_for_deletion() else null
			if was != null and was._drawn and was._code == String(reg.get("regiment_code", "")) and was.is_visible_in_tree():
				rider._from = [Vector2(was.global_position.x, was.global_position.z), was.global_rotation.y]
				rider._state = was._state
	rider._repo = repo
	rider._ctx = layer.ctx
	rider._piece = piece
	rider._code = String(reg.get("regiment_code", ""))
	rider._turn = deg_to_rad(layer.turn_deg_per_s)
	rider._gallops = String(repo.army_art.get(String(piece.get("model", "")), {}).get("commander_gallops", "")) == "1"
	rider._blend_s = layer.blend_s
	rider._stood = []
	Map3DCommanderFigure.set_flag(rider._figure,
		Map3DNationalFlag.texture_for(repo, flags, String(reg.get("kingdom_code", ""))))


## The commander of `piece`, null when it has none (tests, the bench).
static func of_piece(piece: Dictionary) -> Map3DCommanderRider:
	var root := piece.get("node") as Node3D
	return root.get_node_or_null(NAME) as Map3DCommanderRider if root != null else null


func _process(delta: float) -> void:
	stand(delta)


## Stands, sizes and plays him from his unit's piece as it is drawn now; `delta` real seconds of
## his ride (view time: it runs on a stopped clock too, as the figures' walk into a battle).
func stand(delta := 0.0) -> void:
	var root := get_parent() as Node3D
	if root == null or not root.is_visible_in_tree():
		_anim.active = false  # hidden with his piece (symbol mode, a hidden view): his clip stops too
		_drawn = false  # and shown again he stands where he belongs
		_moving = false
		_keeping = false
		_from = []
		return
	var battle: bool = _piece.get("layout", "") == BATTLE
	var st := _ctx.state()
	var fight := battle and st != null and int(BattleSystem.battle_of(st, _code).get("rounds", 0)) > 0
	if st != _state:  # a swapped state (a loaded save): he stands where he belongs at once
		_state = st
		_drawn = false
		_from = []
	# a battle block whose figures walk to their points (owner 2026-11-28: 跟着走进来): he comes in
	# with them, at their gait — the gallop where his unit's arm gallops in, else the walk
	visible = not battle or not (_piece["groups"] as Array).is_empty()
	_pace = _gait_m(_gallops and battle and not fight and bool(_piece.get("easing", false)))
	if not visible:
		_drawn = false
		_moving = false
		_keeping = false
		_from = []  # not drawn in between: no ride from where the old piece's rider stood
	else:
		var k := Map3DUnits.scale_for(_repo, _repo.bal("map3d_fov_deg"), _ctx.view_size.y,
			Map3DGeometry.distance_for_bar(_repo, _ctx.meta, _repo.bal("map3d_zoom_start_scale"), _ctx.view_size.y),
			_height, _repo.bal("map3d_commander_size"))
		var root_k := root.transform.basis.get_scale().x
		if _sized != [k, root_k]:  # a window resized: his place is measured anew, not ridden to
			_sized = [k, root_k]
			_drawn = false
		var key := [root.transform, _piece.get("extent"), k]
		var was := global_position
		var measured := _drawn and delta > 0.0
		if battle or key != _stood or not _drawn or _moving:  # a pan moves none of it; a battle block's figures move under him
			_stood = key
			_place(root, battle, fight, k, root_k, delta)
		if _moving:  # his gait, its hooves keeping the ground he covers this frame
			_play(_gait, clampf(Vector2(global_position.x - was.x, global_position.z - was.z).length() / delta / (_pace * k),
				_repo.bal("map3d_unit_anim_min"), _repo.bal("map3d_unit_anim_max")) if measured else _repo.bal("map3d_commander_ride_pace"))
		else:
			var clip := clip_for(String(_piece.get("action", "")), String(_piece.get("layout", "")), _gallops, fight)
			var pace_key: Array = _piece.get("pace_key", [])
			_play(clip, 1.0 if clip in ["STANDBY", "COMMAND"] or pace_key.size() != 2 or not bool(pace_key[1]) else march_rate(
				float(pace_key[0]), float(_piece.get("stride_m", 0.0)), float(_piece.get("clip_s", 0.0)), root_k,
				_repo.bal("map3d_commander_gallop_stride_m" if _gallops else "map3d_commander_walk_stride_m"),
				_clip_s(clip), k))
	_anim.active = visible and bool(_piece.get("running", true))


## Whether he is on a ride (or still turning to his facing at its end).
func riding() -> bool:
	return _moving


## Sets the gait he rides at (`_gait`: MARCH, the gallop, or the walk) and returns its own pace,
## model metres a second: its measured stride over its clip's length.
func _gait_m(gallop: bool) -> float:
	_gait = "MARCH" if gallop else WALK
	return _repo.bal("map3d_commander_gallop_stride_m" if gallop else "map3d_commander_walk_stride_m") / maxf(_clip_s(_gait), 0.0001)


## His place in the piece's own flat frame (x right, z to the rear, the front −z; a battle
## block's root is upright and unscaled at the unit's place): centred ahead of the first rank;
## in a stand-off with no room between the lines, beside the left end of his first rank; in a
## `fight`, outside the left file behind the rear rank. Ridden to from where he stands (`ride`,
## `route`), then planted on his own ground like every figure (Map3DUnitRig.plant).
func _place(root: Node3D, battle: bool, fight: bool, k: float, root_k: float, delta: float) -> void:
	var face := Vector2(0.0, -1.0)
	var points := PackedVector2Array()
	var reaches := PackedFloat32Array()
	var sides := PackedFloat32Array()
	if battle:
		face = WarFront.facing_vector(int(_piece.get("facing_deg", 0)))
		var here := Vector2(root.global_position.x, root.global_position.z)
		if _drawn and here != _anchor:  # the block's root went to its unit's new place: he keeps his ground
			_at -= here - _anchor
			_route = PackedVector2Array()
		_anchor = here
		for group: Dictionary in _piece["groups"]:
			var node: Node3D = group["piece"]["node"]
			# its figures' own nodes say where they are (walking to new points he follows them); one
			# gone into a duel or the mixed fight counts where it STANDS (its saved point, drawn in)
			var anims: Array = group["piece"]["anims"]
			points.append((Map3DBattleGroups.stand_xz(_ctx, _piece, group)
				if fight and not anims.is_empty() and (anims[0] as AnimationPlayer).has_meta("duel")
				else Vector2(node.global_position.x, node.global_position.z)) - here)
			var reach: Vector2 = (group["piece"]["extent"] as Vector2) * node.global_basis.get_scale().x
			reaches.append(reach.y)
			sides.append(reach.x)
	else:  # the formation's slots, not its half extent: a block's ranks need not straddle its centre
		for slot: Vector3 in _piece["slots"]:
			points.append(Vector2(slot.x, slot.z))
			reaches.append((_piece["figure_extent"] as Vector2).y)
			sides.append((_piece["figure_extent"] as Vector2).x)
	var across := Vector2(-face.y, face.x)
	var front := front_of(points, reaches, face)
	var rear := left_rear_of(points, sides, face)
	var side := side_m(_half.x, _half.y, _repo.bal("map3d_commander_rear_gap"), k) / root_k
	var goal := rear - across * side - face * _repo.bal("map3d_commander_rear_back") * 2.0 * _half.y * k / root_k
	if not fight:
		var lead := lead_m(_half.y, _repo.bal("map3d_commander_gap"), k)
		if battle:
			lead = standoff_lead(lead, _room(root, face), _repo.bal("map3d_commander_standoff_share"), _half.y * k)
		# lines too close for a place between them: beside the left end of his first rank
		goal = front + face * lead / root_k if lead >= 0.0 else first_rank_left_of(points, sides, face) - across * side
	var goal_yaw := Map3DUnits.facing_yaw(face)
	if not _from.is_empty():  # handed over by the rider of the piece this one replaced
		var stood := root.global_transform.affine_inverse() * Vector3(_from[0].x, root.global_position.y, _from[0].y)
		_at = Vector2(stood.x, stood.z)
		_yaw = float(_from[1]) - root.global_rotation.y
		_route = PackedVector2Array()
		_drawn = true
		_from = []
	var length := 2.0 * _half.y * k / root_k  # his own, in this frame's metres
	var far := not _drawn
	if _drawn and (_at if _route.is_empty() else _route[-1]).distance_to(goal) > 0.001 * length \
			and (not _route.is_empty() or _keeping or _at.distance_to(goal) >= _repo.bal("map3d_commander_ride_min") * length):
		# a new place: ridden to round the left flank. One nearer than `map3d_commander_ride_min` of
		# his lengths does not move him, unless he is riding already (his block walking to new
		# points: he keeps with it).
		var back := INF  # the rear rank's back and the right file's outside: the ways round the block
		var right := -INF
		for i in points.size():
			back = minf(back, points[i].dot(face) - reaches[i])
			right = maxf(right, points[i].dot(across) + sides[i])
		# clear of the flank files by his lane's gap, of the ranks by his own half length
		_route = route(_at, goal, face, rear.dot(across), right, front.dot(face), back, side, 0.5 * length,
			_repo.bal("map3d_commander_about_face") * length)
		far = _route.is_empty()
	if far:  # a first sight, or no clear way round: stood at his place at once
		_at = goal
		_yaw = goal_yaw
		_route = PackedVector2Array()
		_drawn = true
	var before := _at
	var rode := ride(_at, _yaw, _route, goal_yaw, _repo.bal("map3d_commander_ride_pace") * _pace * k / root_k * delta, _turn * delta)
	_at = rode[0]
	_yaw = rode[1]
	_route = rode[2]
	# keeping with a place that walks on at a pace his walk can play (a slower drift he lets go, and
	# catches up when it is far enough); still riding: that, corners ahead, or his turn to his facing
	_keeping = before.distance_to(_at) > maxf(0.0001 * length, _repo.bal("map3d_unit_anim_min") * _pace * k / root_k * delta)
	_moving = _keeping or not _route.is_empty() or absf(angle_difference(_yaw, goal_yaw)) > 0.001
	transform = Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3.ONE * k / root_k), Vector3(_at.x, 0.0, _at.y))
	Map3DUnitRig.plant(_repo, _ctx.height_at, {"node": root, "height_m": _piece["height_m"], "figs": [self]})


## The clear ground between where his first rank will STAND and the nearest figure of the other
## side of his unit's battle where IT will stand (the saved points drawn in:
## Map3DBattleGroups.stand_xz), world metres; INF with none. Never the drawn figures: it is settled
## from the first frame of a walk-in, so he takes one place and keeps it while the lines close.
## ponytail: only battle blocks are measured; a foe of the battle drawn as an ordinary block (a
## legacy save with no saved groups) gives no room. Measure its slots too if that case is ever seen.
func _room(root: Node3D, face: Vector2) -> float:
	var st := _ctx.state()
	var fight: Dictionary = BattleSystem.battle_of(st, _code) if st != null else {}
	var layer := root.get_parent() as Map3DLayerUnits
	var here := Vector2(root.global_position.x, root.global_position.z)
	var reach := func(group: Dictionary) -> float:
		return (group["piece"]["extent"] as Vector2).y * (group["piece"]["node"] as Node3D).global_basis.get_scale().x
	var front := -INF
	for group: Dictionary in _piece["groups"]:
		front = maxf(front, (Map3DBattleGroups.stand_xz(_ctx, _piece, group) - here).dot(face) + float(reach.call(group)))
	var room := INF
	for side: String in ["att", "def"]:
		var codes: Array = fight.get(side, [])
		if layer == null or _code in codes:
			continue
		for code: String in codes:
			var theirs := layer.built_piece(code)
			for group: Dictionary in theirs.get("groups", []):
				var along := (Map3DBattleGroups.stand_xz(_ctx, theirs, group) - here).dot(face) - float(reach.call(group))
				if along > front:
					room = minf(room, along - front)
	return room


## The length of his `clip`, seconds (0 with none).
func _clip_s(clip: String) -> float:
	if not _clips.has(clip):
		_clips[clip] = Map3DUnits.clip_named(_anim, clip)  # looked up once, not every frame
	return _anim.get_animation(_clips[clip]).length if _clips[clip] != "" else 0.0


func _play(clip: String, rate: float) -> void:
	if _clip_s(clip) <= 0.0:
		return
	var named: String = _clips[clip]
	if _anim.current_animation != named:
		_anim.play(named, _blend_s)
		_anim.seek(Map3DMarchLag.unit(_code + "|commander|" + clip) * _anim.current_animation_length, true)
	_anim.speed_scale = rate
