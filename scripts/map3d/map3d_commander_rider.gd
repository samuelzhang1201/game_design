class_name Map3DCommanderRider
extends Node3D
## A unit's mounted commander on the map (spec 2026-11-27-commander-figure-design, step 2): one
## rider under his realm's banner, alone and centred ahead of his unit's first rank. He is a child
## of the unit's piece (Map3DUnitDress.sync hangs him there), so he is shown, hidden and freed
## with it; each frame he reads the piece and stands, sizes and plays himself. He is no formation
## slot, no figure of the piece and no number: neither the engine nor the save knows him.
## Never reaches for the Game autoload.

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


## Whether a unit's piece gets the figure: a commander is appointed and it is not the king's own
## unit, whose rider is the king himself.
static func leads(reg: Dictionary, state: GameState) -> bool:
	if state == null or String(reg.get("is_royal", "0")) == "1":
		return false
	var roster: Dictionary = state.military_rosters.get(String(reg.get("regiment_code", "")), {})
	return String(roster.get("commander_id", "")) != ""


## The clip he plays for his unit's `action`: his march only while an ordinary piece marches
## (the gallop ahead of an arm that rides, else the walk); standing, and in a battle block, STANDBY.
static func clip_for(action: String, layout: String, gallops: bool) -> String:
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
## (`least`, his half length): lines that close leave him no place, and he is not drawn.
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
	rider._repo = repo
	rider._ctx = layer.ctx
	rider._piece = piece
	rider._code = String(reg.get("regiment_code", ""))
	rider._gallops = String(repo.army_art.get(String(piece.get("model", "")), {}).get("commander_gallops", "")) == "1"
	rider._blend_s = layer.blend_s
	rider._stood = []
	Map3DCommanderFigure.set_flag(rider._figure,
		Map3DNationalFlag.texture_for(repo, flags, String(reg.get("kingdom_code", ""))))


## The commander of `piece`, null when it has none (tests, the bench).
static func of_piece(piece: Dictionary) -> Map3DCommanderRider:
	var root := piece.get("node") as Node3D
	return root.get_node_or_null(NAME) as Map3DCommanderRider if root != null else null


func _process(_delta: float) -> void:
	stand()


## Stands, sizes and plays him from his unit's piece as it is drawn now.
func stand() -> void:
	var root := get_parent() as Node3D
	if root == null or not root.is_visible_in_tree():
		_anim.active = false  # hidden with his piece (symbol mode, a hidden view): his clip stops too
		return
	var battle: bool = _piece.get("layout", "") == BATTLE
	var st := _ctx.state()
	# a battle block: not while its figures walk to their points (the room between the lines is not
	# settled), and not in a fight (the spec's step 3 rides him to the unit's left rear)
	visible = not battle or (not (_piece["groups"] as Array).is_empty() and not bool(_piece.get("easing", false))
		and (st == null or int(BattleSystem.battle_of(st, _code).get("rounds", 0)) == 0))
	if visible:
		var k := Map3DUnits.scale_for(_repo, _repo.bal("map3d_fov_deg"), _ctx.view_size.y,
			Map3DGeometry.distance_for_bar(_repo, _ctx.meta, _repo.bal("map3d_zoom_start_scale"), _ctx.view_size.y),
			_height, _repo.bal("map3d_commander_size"))
		var root_k := root.transform.basis.get_scale().x
		var key := [root.transform, _piece.get("extent"), k]
		if battle or key != _stood:  # a pan moves none of it; a battle block's figures move under him
			_stood = key
			visible = _place(root, battle, k, root_k)
		if visible:
			_play(clip_for(String(_piece.get("action", "")), String(_piece.get("layout", "")), _gallops), k, root_k)
	_anim.active = visible and bool(_piece.get("running", true))


## His place in the piece's own frame (x right, z to the rear, the front −z): centred, ahead of
## the first rank; then planted on his own ground like every figure (Map3DUnitRig.plant).
## False when a stand-off leaves him no room (standoff_lead).
func _place(root: Node3D, battle: bool, k: float, root_k: float) -> bool:
	var face := Vector2(0.0, -1.0)
	var points := PackedVector2Array()
	var reaches := PackedFloat32Array()
	if battle:  # an upright, unscaled root at the unit's place: its figures' own nodes say where they stand
		face = WarFront.facing_vector(int(_piece.get("facing_deg", 0)))
		for group: Dictionary in _piece["groups"]:
			var node: Node3D = group["piece"]["node"]
			points.append(Vector2(node.global_position.x - root.global_position.x,
				node.global_position.z - root.global_position.z))
			reaches.append((group["piece"]["extent"] as Vector2).y * node.global_basis.get_scale().x)
	else:  # the formation's slots, not its half extent: a block's ranks need not straddle its centre
		for slot: Vector3 in _piece["slots"]:
			points.append(Vector2(slot.x, slot.z))
			reaches.append((_piece["figure_extent"] as Vector2).y)
	var front := front_of(points, reaches, face)
	var lead := lead_m(_half.y, _repo.bal("map3d_commander_gap"), k)
	if battle:
		lead = standoff_lead(lead, _room(root, face, front.dot(face)), _repo.bal("map3d_commander_standoff_share"), _half.y * k)
		if lead < 0.0:
			return false
	var at := front + face * lead / root_k
	transform = Transform3D(Basis(Vector3.UP, Map3DUnits.facing_yaw(face) if battle else 0.0)
		.scaled(Vector3.ONE * k / root_k), Vector3(at.x, 0.0, at.y))
	Map3DUnitRig.plant(_repo, _ctx.height_at, {"node": root, "height_m": _piece["height_m"], "figs": [self]})
	return true


## The clear ground ahead of his first rank (`front_m` along `face` from the block's root) up to
## the nearest drawn figure of the other side of his unit's battle, world metres; INF with none.
## ponytail: only battle blocks are measured; a foe of the battle drawn as an ordinary block (a
## legacy save with no saved groups) gives no room. Measure its slots too if that case is ever seen.
func _room(root: Node3D, face: Vector2, front_m: float) -> float:
	var st := _ctx.state()
	var fight: Dictionary = BattleSystem.battle_of(st, _code) if st != null else {}
	var layer := root.get_parent() as Map3DLayerUnits
	var room := INF
	for side: String in ["att", "def"]:
		var codes: Array = fight.get(side, [])
		if layer == null or _code in codes:
			continue
		for code: String in codes:
			for group: Dictionary in layer.built_piece(code).get("groups", []):
				var node: Node3D = group["piece"]["node"]
				var along := Vector2(node.global_position.x - root.global_position.x,
					node.global_position.z - root.global_position.z).dot(face) \
					- (group["piece"]["extent"] as Vector2).y * node.global_basis.get_scale().x
				if along > front_m:
					room = minf(room, along - front_m)
	return room


func _play(clip: String, k: float, root_k: float) -> void:
	if not _clips.has(clip):
		_clips[clip] = Map3DUnits.clip_named(_anim, clip)  # looked up once, not every frame
	var named: String = _clips[clip]
	if named == "":
		return
	if _anim.current_animation != named:
		_anim.play(named, _blend_s)
		_anim.seek(Map3DMarchLag.unit(_code + "|commander|" + clip) * _anim.current_animation_length, true)
	var pace: Array = _piece.get("pace_key", [])
	_anim.speed_scale = 1.0 if clip == "STANDBY" or pace.size() != 2 or not bool(pace[1]) else march_rate(
		float(pace[0]), float(_piece.get("stride_m", 0.0)), float(_piece.get("clip_s", 0.0)), root_k,
		_repo.bal("map3d_commander_gallop_stride_m" if _gallops else "map3d_commander_walk_stride_m"),
		_anim.current_animation_length, k)
