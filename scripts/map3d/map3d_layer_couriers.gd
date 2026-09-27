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


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)
	refresh()


## id -> {rect: Rect2 in design px, counter: bool}.
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


## Walk each drawn rider toward where the engine has him, a day's ride per
## day's real seconds; true when anything changed (the HUD redraws).
func step(delta: float) -> bool:
	if ctx == null or ctx.camera == null:
		return false
	var list := ctx.couriers()
	var dirty := list.size() != _rects.size()
	var clock := ctx.clock_speed()
	var day_s := maxf(ctx.repo.bal("time_day_seconds") / float(maxi(clock, 1)), 0.001)
	var per_m := float(ctx.meta.get("m_per_px", 50.0)) / float(ArmySystem.metres_per_pack_px(ctx.repo))
	for c: Dictionary in list:
		var id := int(c["id"])
		var want := _target_xz(c)
		if not _shown_xz.has(id):
			_shown_xz[id] = want
			dirty = true
			continue
		var now: Vector2 = _shown_xz[id]
		if now == want:
			continue
		var day_m := float(maxi(int(c.get("day_m", 0)), 1)) * per_m
		var speed := day_m / day_s if clock > 0 else 0.0
		_shown_xz[id] = Map3DUnits.walk(now, want, speed * delta, day_m * ctx.repo.bal("map3d_unit_snap_days"))
		dirty = true
	if dirty:
		refresh()
	return dirty


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
		_rects[id] = {"rect": Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), "counter": true}
		return
	var node: Node3D = piece["node"]
	node.visible = true
	var ref_m := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, ctx.camera.global_position.distance_to(centre),
		repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m, float(piece["height_m"]), float(piece["size"]))
	var cam := Vector2(ctx.camera.global_position.x, ctx.camera.global_position.z)
	var yaw := Map3DUnits.yaw_for(_heading(c), cam, xz)
	var sit := Map3DUnits.seat_at(repo, ctx.height_at, xz, piece["extent"], yaw, k)
	var high := float(piece["height_m"]) * k
	var ground := Vector3(xz.x, float(sit["y"]) + high * repo.bal("map3d_unit_seat_clear")
		- repo.bal("map3d_unit_sink_m"), xz.y)
	var up: Vector3 = sit["normal"]
	node.transform = Transform3D((Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw))
		.scaled(Vector3(k, k, k)), ground)
	_rects[id] = {"rect": Map3DUnits.screen_box(ctx.camera, ground, high, float(piece["half_w_m"]) * k, s_px),
		"counter": false}


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
