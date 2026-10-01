class_name Map3DLayerCouriers
extends Node3D
## The couriers on the 3D map (spec 2026-09-27-courier-core §2): one small rider
## per courier of GameState.couriers, drawn RIDING the day the clock is running
## (CourierSystem.ride_ahead), walked by the day's share (owner 2026-09-28: drawn
## a day behind before). Map3DUnits sizes him: gallops while the clock runs and
## idles paused or not set out, a counter past the counter scale, and fades out
## on delivery (Map3DCourierRide). Model:
## courier_art.csv, cavalry stand-in until sub-project D. Never the Game autoload.

const GALLOP := "GALLOP"
const IDLE := "IDLE"
## A stand-in model (the cavalry) has no courier clips: rides its march, stands its garrison.
const FALLBACK := {"GALLOP": "MARCH", "IDLE": "GARRISON"}


## GALLOP while he rides and the clock runs; IDLE when paused or not yet set out.
static func action_for(moving: bool, clock_running: bool) -> String:
	return GALLOP if moving and clock_running else IDLE


## The clip for `action`, else its FALLBACK's, else "".
static func clip_or_fallback(anim: AnimationPlayer, action: String) -> String:
	if anim == null:
		return ""
	var clip := Map3DUnits.clip_named(anim, action)
	if clip == "" and FALLBACK.has(action):
		clip = Map3DUnits.clip_named(anim, String(FALLBACK[action]))
	return clip


var ctx: Map3DContext
var _pieces: Dictionary = {}
var _shown_xz: Dictionary = {}
var _rects: Dictionary = {}
var _scenes: Dictionary = {}
## id -> {key, from, ahead, rest, length, share}: today's ride, remade when the engine moves him or the day turns.
var _rides: Dictionary = {}
## id -> the road still ahead of the drawn rider, in world XZ.
var _left: Dictionary = {}
## id -> the day's share when a courier not yet ridden was first seen (sent mid-day).
var _start: Dictionary = {}
var _fade: Dictionary = {}  # id -> real seconds since he delivered


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)
	refresh()


## id -> {rect: Rect2 design px, counter: bool, lead: road ahead (Map3DHudCouriers), waiting: bool}.
func screen_rects() -> Dictionary:
	return _rects


func refresh() -> void:
	if ctx == null or ctx.camera == null:
		return
	_rects = {}
	var live: Dictionary = {}
	for c: Dictionary in ctx.couriers():
		var id := int(c["id"])
		live[id] = true
		if not _shown_xz.has(id):
			_shown_xz[id] = _drawn_xz(c)
		_place(c, _shown_xz[id])
	for id in _pieces.keys():
		if not live.has(id):
			(_pieces[id]["node"] as Node3D).queue_free()
			_pieces.erase(id)
	for id in _shown_xz.keys():
		if not live.has(id):
			_shown_xz.erase(id)
			_rides.erase(id)
			_left.erase(id)
			_start.erase(id)
			_fade.erase(id)


## Draw each rider where the day's share has him on today's ride; true when
## anything changed (the HUD redraws). Also syncs his gallop/idle and its pace.
func step(delta: float) -> bool:
	if ctx == null or ctx.camera == null:
		return false
	var list := ctx.couriers()
	var dirty := list.size() != _rects.size()
	for c: Dictionary in list:
		var id := int(c["id"])
		var xz := _drawn_xz(c)
		var moving: bool = _shown_xz.has(id) and _shown_xz[id] != xz
		var prev: Vector2 = _shown_xz.get(id, xz)
		if Map3DCourierRide.delivered(_ride_of(c), _share_of(c)):
			_fade[id] = float(_fade.get(id, 0.0)) + delta
			dirty = dirty or _fade[id] - delta < ctx.repo.bal("map3d_courier_fade_s")  # still fading
			moving = false
		if _pieces.has(id):
			var piece: Dictionary = _pieces[id]
			var k := (piece["node"] as Node3D).transform.basis.get_scale().x
			var pace := Map3DUnitRig.gait_rate(prev.distance_to(xz) / maxf(delta, 0.001), k,
				float(piece["clip_s"]), float(piece["stride_m"]),
				ctx.repo.bal("map3d_courier_anim_min"), ctx.repo.bal("map3d_courier_anim_max"))
			_sync(piece, action_for(moving or not (_waiting(c, xz) or _fade.has(id)), ctx.clock_speed() > 0.0), pace)
		if not _shown_xz.has(id) or _shown_xz[id] != xz:
			_shown_xz[id] = xz
			dirty = true
	if dirty:
		refresh()
	return dirty


## Where he is drawn now, remembering the road still ahead of that spot.
func _drawn_xz(c: Dictionary) -> Vector2:
	var ride := _ride_of(c)
	var queue: Array = (ride["ahead"] as Array).duplicate()
	var done := minf(_share_of(c) / maxf(float(ride["share"]), 0.001), 1.0)  # he rides at his own pace
	var at := Map3DCourierRide.walk_along(ride["from"], queue, float(ride["length"]) * done)
	queue.append_array(ride["rest"])
	_left[int(c["id"])] = queue
	return at


## How much of today's ride he has done: the day's share, or — sent today — since then.
func _share_of(c: Dictionary) -> float:
	var id := int(c["id"])
	var share := ctx.day_share()
	if int(c.get("days", 0)) > 0:
		_start.erase(id)
		return share
	if not _start.has(id):
		_start[id] = share
	var s0 := float(_start[id])
	return clampf((share - s0) / (1.0 - s0), 0.0, 1.0) if s0 < 1.0 else 0.0


func _ride_of(c: Dictionary) -> Dictionary:
	var id := int(c["id"])
	var st := ctx.state()
	var path: Array = c["path"]
	var key := [int(c["x_m"]), int(c["y_m"]), path.size(), int(c.get("aim_x_m", 0)),
		int(c.get("aim_y_m", 0)), st.absolute_day() if st != null else 0]
	if _rides.has(id) and _rides[id]["key"] == key:
		return _rides[id]
	var from := _target_xz(c)
	var day: Dictionary = CourierSystem.ride_ahead(ctx.repo, st, c) if st != null else {"points": [], "share": 1.0, "ends": false}
	var passed: Array = day["points"]
	var ahead: Array = []
	for m: Vector2i in passed:
		ahead.append(_world_of_m(m))
	var rest: Array = []
	for i in range(maxi(passed.size() - 1, 0), path.size()):
		rest.append(_world_of_m(Vector2i(int(path[i][0]), int(path[i][1]))))
	var ride := {"key": key, "from": from, "ahead": ahead, "rest": rest,
		"length": Map3DCourierRide.length_along(from, ahead), "share": float(day["share"]), "ends": bool(day["ends"])}
	_rides[id] = ride
	return ride


func _world_of_m(m: Vector2i) -> Vector2:
	return ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, m))


func _target_xz(c: Dictionary) -> Vector2:
	return ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, Vector2i(int(c["x_m"]), int(c["y_m"]))))


## He faces the next point of the road ahead of where he is drawn.
func _heading_from(id: int, xz: Vector2, c: Dictionary) -> Vector2:
	for p: Vector2 in _left.get(id, []):
		if p.distance_to(xz) > 0.01:
			return (p - xz).normalized()
	return _heading(c)


func _heading(c: Dictionary) -> Vector2:  # the next waypoint of his road
	var path: Array = c["path"]
	if path.is_empty():
		return Vector2.ZERO
	var d := Vector2(float(path[0][0]) - float(c["x_m"]), float(path[0][1]) - float(c["y_m"]))
	return d.normalized() if d.length() > 0.5 else Vector2.ZERO


func _place(c: Dictionary, xz: Vector2) -> void:
	var id := int(c["id"])
	var repo := ctx.repo
	var s_px := ctx.viewport_px_scale()
	var centre := Vector3(xz.x, ctx.height_at(xz), xz.y)
	var alpha := Map3DCourierRide.alpha(float(_fade.get(id, -1.0)), repo.bal("map3d_courier_fade_s"))
	if alpha <= 0.0:  # delivered and faded: nothing drawn, nothing to click
		if _pieces.has(id):
			(_pieces[id]["node"] as Node3D).visible = false
		_rects[id] = {"rect": Rect2(), "counter": false, "lead": [], "waiting": false, "gone": true, "alpha": 0.0}
		return
	if ctx.camera.is_position_behind(centre):
		if _pieces.has(id):
			(_pieces[id]["node"] as Node3D).visible = false
		return
	var counter := Map3DUnits.as_counters(repo, ctx.meta, ctx.distance, ctx.view_size.y)
	var piece: Dictionary = {} if counter else _piece_of(c)
	if piece.is_empty():
		if _pieces.has(id):
			(_pieces[id]["node"] as Node3D).visible = false
		var at: Vector2 = ctx.camera.unproject_position(centre) / s_px
		var half := repo.bal("map3d_courier_counter_px") * 0.5
		_rects[id] = {"rect": Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), "counter": true,
			"lead": _lead(id, xz), "waiting": _waiting(c, xz), "gone": alpha < 1.0, "alpha": alpha}
		return
	var node: Node3D = piece["node"]
	node.visible = true
	Map3DCourierRide.apply(piece, alpha)
	var ref_m := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m,
		float(piece["height_m"]), float(piece["size"]))
	var cam := Vector2(ctx.camera.global_position.x, ctx.camera.global_position.z)
	var heading := _heading_from(id, xz, c)
	var yaw := Map3DUnits.yaw_for(heading, cam, xz)
	var sit := Map3DUnits.seat_at(repo, ctx.height_at, xz, piece["extent"], yaw, k)
	var high := float(piece["height_m"]) * k
	var ground := Vector3(xz.x, float(sit["y"]) + high * repo.bal("map3d_unit_seat_clear")
		- repo.bal("map3d_unit_sink_m"), xz.y)
	var up: Vector3 = sit["normal"]
	node.transform = Transform3D((Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw))
		.scaled(Vector3(k, k, k)), ground)
	_rects[id] = {"rect": Map3DUnits.screen_box(ctx.camera, ground, high, float(piece["half_w_m"]) * k, s_px),
		"counter": false, "lead": _lead(id, xz), "waiting": _waiting(c, xz), "gone": alpha < 1.0, "alpha": alpha}


func _waiting(c: Dictionary, xz: Vector2) -> bool:  # not yet set out
	return int(c["days"]) == 0 and xz.distance_to(_target_xz(c)) < 0.5


func _lead(id: int, xz: Vector2) -> Array:
	var out: Array = [xz]
	out.append_array(_left.get(id, []))
	return out


## Put his AnimationPlayer into `action`, blended; a pace for the gallop.
func _sync(piece: Dictionary, action: String, pace: float) -> void:
	var anim: AnimationPlayer = piece.get("anim")
	if anim == null:
		return
	var clip := clip_or_fallback(anim, action)
	if clip == "":
		return
	if String(piece["action"]) != action:
		anim.play(clip, ctx.repo.bal("map3d_unit_blend_s"))
		piece["action"] = action
	anim.speed_scale = pace if action == GALLOP else 1.0


func _piece_of(c: Dictionary) -> Dictionary:
	var id := int(c["id"])
	if _pieces.has(id):
		return _pieces[id]
	var art: Dictionary = ctx.repo.courier_art.get(String(c["kind"]), {})
	var path := String(art.get("model", ""))
	var scene := _scene(path) if path != "" else null
	if scene == null:
		return {}
	var node := scene.instantiate() as Node3D
	node.name = "Courier%d" % id
	add_child(node)  # no owner: never saved into the authored scene
	var span := Map3DUnits.model_size(node)
	var anims := Map3DUnits.find_anim(node)
	var gallop := clip_or_fallback(anims, GALLOP)
	var clip_s := anims.get_animation(gallop).length if anims != null and gallop != "" else 1.0
	# span.x is already a HALF-width (model_size measures from the node's own
	# origin); a courier has no formation, so it is used as-is, like half_w_m.
	var piece := {"node": node, "height_m": maxf(span.y, 0.01), "half_w_m": span.x,
		"extent": Map3DUnits.stand_extent(node), "size": float(art.get("size", "1")),
		"anim": anims, "clip_s": clip_s, "stride_m": float(art.get("stride_m", "0")), "action": ""}
	_pieces[id] = piece
	return piece


func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var scene := Map3DAssetCache.scene(path)  # loaded once, kept between views
	if scene == null:
		Map3DWorldLoader.warn_once("couriers:" + path, "map3d couriers: no model at " + path)
	_scenes[path] = scene
	return scene
