class_name Map3DLayerCouriers
extends Node3D
## The couriers on the 3D map (spec 2026-09-27-courier-core §2): one small
## rider per courier of GameState.couriers, sized, seated and walked between
## the engine's whole days with the regiment pieces' own rules (Map3DUnits),
## galloping always. Past the counter scale no rider is drawn and his rect is
## a counter's, which Map3DHudCouriers paints. The model is courier_art.csv's —
## the cavalry until sub-project D delivers the courier's own. Takes
## everything from Map3DContext, never the Game autoload (a test scans).

const MARCH := "MARCH"

var ctx: Map3DContext
var _pieces: Dictionary = {}
var _shown_xz: Dictionary = {}
var _rects: Dictionary = {}
var _scenes: Dictionary = {}
## id -> the world XZ points still to ride to, in order: the road he rode
## today, which the engine has already put behind him.
var _queue: Dictionary = {}
## id -> {x_m, y_m, path} as the engine last had him; id -> today's leg length.
var _last: Dictionary = {}
var _leg: Dictionary = {}


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)
	refresh()


## id -> {rect: Rect2 in design px, counter: bool, lead: the world XZ points
## from where he is drawn to where the engine has him (Map3DHudCouriers draws
## his road ahead from them), waiting: not yet ridden (days 0), so the town
## he waits in wins a click on him (Map3DPicker)}.
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
			_shown_xz[id] = _target_xz(c)
		_place(c, _shown_xz[id])
	for id in _pieces.keys():
		if not live.has(id):
			(_pieces[id]["node"] as Node3D).queue_free()
			_pieces.erase(id)
	for id in _shown_xz.keys():
		if not live.has(id):
			_shown_xz.erase(id)
			_queue.erase(id)
			_last.erase(id)
			_leg.erase(id)


## Walk each drawn rider ALONG the road he rode toward where the engine has
## him, a day's ride per day's real seconds; true when anything changed (the
## HUD redraws).
func step(delta: float) -> bool:
	if ctx == null or ctx.camera == null:
		return false
	var list := ctx.couriers()
	var dirty := list.size() != _rects.size()
	var clock := ctx.clock_speed()
	var day_s := maxf(ctx.repo.bal("time_day_seconds") / float(maxi(clock, 1)), 0.001)
	for c: Dictionary in list:
		var id := int(c["id"])
		if not _shown_xz.has(id):
			_shown_xz[id] = _target_xz(c)
			_queue[id] = []
			_remember(c)
			dirty = true
			continue
		var last: Dictionary = _last[id]
		if int(last["x_m"]) != int(c["x_m"]) or int(last["y_m"]) != int(c["y_m"]):
			var q: Array = _queue[id]
			var fresh: Array = []
			for m: Vector2i in passed_points(last["path"], (c["path"] as Array).size(),
					Vector2i(int(c["x_m"]), int(c["y_m"]))):
				fresh.append(ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, m)))
			# today's ride sets his pace: its length over a day's real seconds
			_leg[id] = maxf(length_along(q.back() if not q.is_empty() else _shown_xz[id], fresh), 0.001)
			q.append_array(fresh)
			if length_along(_shown_xz[id], q) > float(_leg[id]) * ctx.repo.bal("map3d_unit_snap_days"):
				_shown_xz[id] = (_queue[id] as Array).back()
				(_queue[id] as Array).clear()
			_remember(c)
		var queue: Array = _queue[id]
		if queue.is_empty() or clock <= 0:
			continue
		_shown_xz[id] = walk_along(_shown_xz[id], queue, float(_leg[id]) / day_s * delta)
		dirty = true
	if dirty:
		refresh()
	return dirty


func _remember(c: Dictionary) -> void:
	_last[int(c["id"])] = {"x_m": int(c["x_m"]), "y_m": int(c["y_m"]), "path": (c["path"] as Array).duplicate(true)}


## The points (whole metres) a courier passed since the engine last moved him:
## the waypoints his road has dropped from its front, then where he is now.
static func passed_points(old_path: Array, new_size: int, now: Vector2i) -> Array:
	var out: Array = []
	for i in range(maxi(old_path.size() - new_size, 0)):
		out.append(Vector2i(int(old_path[i][0]), int(old_path[i][1])))
	out.append(now)
	return out


## `step` along the points of `queue` from `now`, dropping each point reached.
static func walk_along(now: Vector2, queue: Array, step: float) -> Vector2:
	var at := now
	var left := step
	while not queue.is_empty():
		var to: Vector2 = queue[0]
		var d := at.distance_to(to)
		if d > left:
			return at + (to - at) / d * left
		left -= d
		at = to
		queue.pop_front()
	return at


static func length_along(now: Vector2, points: Array) -> float:
	var total := 0.0
	var at := now
	for p: Vector2 in points:
		total += at.distance_to(p)
		at = p
	return total


func _target_xz(c: Dictionary) -> Vector2:
	return ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, Vector2i(int(c["x_m"]), int(c["y_m"]))))


## He faces the next waypoint of his road.
func _heading(c: Dictionary) -> Vector2:
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
			"lead": _lead(id, xz), "waiting": int(c["days"]) == 0}
		return
	var node: Node3D = piece["node"]
	node.visible = true
	var ref_m := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, ctx.camera.global_position.distance_to(centre),
		repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m, float(piece["height_m"]), float(piece["size"]))
	var cam := Vector2(ctx.camera.global_position.x, ctx.camera.global_position.z)
	var queue: Array = _queue.get(id, [])
	var heading := ((queue[0] as Vector2) - xz).normalized() if not queue.is_empty() else _heading(c)
	var yaw := Map3DUnits.yaw_for(heading, cam, xz)
	var sit := Map3DUnits.seat_at(repo, ctx.height_at, xz, piece["extent"], yaw, k)
	var high := float(piece["height_m"]) * k
	var ground := Vector3(xz.x, float(sit["y"]) + high * repo.bal("map3d_unit_seat_clear")
		- repo.bal("map3d_unit_sink_m"), xz.y)
	var up: Vector3 = sit["normal"]
	node.transform = Transform3D((Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw))
		.scaled(Vector3(k, k, k)), ground)
	_rects[id] = {"rect": Map3DUnits.screen_box(ctx.camera, ground, high, float(piece["half_w_m"]) * k, s_px),
		"counter": false, "lead": _lead(id, xz), "waiting": int(c["days"]) == 0}


func _lead(id: int, xz: Vector2) -> Array:
	var out: Array = [xz]
	out.append_array(_queue.get(id, []))
	return out


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
	if anims != null:
		var clip := Map3DUnits.clip_named(anims, MARCH)
		if clip != "":
			anims.play(clip)
			anims.speed_scale = ctx.repo.bal("map3d_courier_anim_rate")
	# span.x is already a HALF-width (Map3DUnits.model_size measures from the
	# node's own origin), exactly maxf(stand_extent().x, stand_extent().y) —
	# the same quantity map3d_layer_units.gd's _piece_of gives half_w_m
	# (Map3DFormation.half_extent, itself stand_extent for one figure) with no
	# further halving; a courier has no formation, so span.x is used as-is.
	var piece := {"node": node, "height_m": maxf(span.y, 0.01), "half_w_m": span.x,
		"extent": Map3DUnits.stand_extent(node), "size": float(art.get("size", "1"))}
	_pieces[id] = piece
	return piece


func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	else:
		Map3DWorldLoader.warn_once("couriers:" + path, "map3d couriers: no model at " + path)
	_scenes[path] = scene
	return scene
