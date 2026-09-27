@tool
class_name Map3DLayerUnits
extends Node3D
## MILITARY's PIECES: the player's regiments as animated wargame models
## standing on the ground (owner 2026-09-22, "把这两个兵棋人应用到游戏中去").
##
## One instanced .glb per regiment — a skinned mesh with its own skeleton and
## its own actions — so this is the one layer that cannot be a MultiMesh:
## every piece is posed by an AnimationPlayer of its own — affordable for the
## player's 22; every realm's regiments would need a different answer.
##
## THE SIZE IS NOT THE MODEL'S SIZE: a constant height in SCREEN px, clamped
## in metres. That rule, the facing, the seating on a slope, the measuring and
## the screen box are Map3DUnits — the pure half, as Map3DHouses is.
##
## Takes everything from Map3DContext, never the Game autoload (a test scans).

## Editor preview: the player's regiments from the pack alone.
@export var preview := false: set = set_preview

const GARRISON := "GARRISON"
const MARCH := "MARCH"

var ctx: Map3DContext
## Whether MILITARY is up; Map3DView sets it from set_military.
var shown := false
## code -> {node, anim, height_m, half_w_m, extent} — the model's own metres.
var _pieces: Dictionary = {}
## code -> the piece's box on screen, design px. What a click hits.
var _rects: Dictionary = {}
## code -> the screen point of the piece's TOP, design px — where the
## headcount chip hangs, so it never sits on the model's boots.
var _tops: Dictionary = {}
## code -> the yaw it is turning toward, and the one it is at.
var _want_yaw: Dictionary = {}
var _yaw: Dictionary = {}
var _scenes: Dictionary = {}
## code -> where the piece is DRAWN, world XZ: the engine's position, walked
## toward a frame at a time (step), never jumped a day at a time.
var _shown_xz: Dictionary = {}
var _moves := 0


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)


func _on_camera_moved() -> void:
	refresh()


## MILITARY went up or down. The pieces are built on the first showing and
## then only hidden, because loading four skinned scenes is not something to
## pay for every time the player taps the tab.
func set_shown(on: bool) -> void:
	shown = on
	visible = on
	if on:
		refresh()


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		_pieces.clear()
		_tops.clear()
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


func preview_build(p_ctx: Map3DContext) -> void:
	bind(p_ctx)
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		return
	shown = true
	visible = true
	refresh()


## Every piece placed, sized and turned for the camera as it stands now. Cut
## once per camera pose like every other layer; the MARCH between two days is
## step()'s, and the animation runs on each piece's own AnimationPlayer.
func refresh() -> void:
	if ctx == null or not shown or ctx.camera == null:
		return
	var repo := ctx.repo
	var live: Dictionary = {}
	_tops.clear()
	_rects.clear()
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var code := String(reg["regiment_code"])
		var piece := _piece_of(code)
		if piece.is_empty():
			continue
		live[code] = true
		if not _shown_xz.has(code):
			_shown_xz[code] = _target_xz(reg)
		_place(code, piece)
	for code: String in _pieces.keys():
		if not live.has(code):
			(_pieces[code]["node"] as Node3D).visible = false


## Where the ENGINE has a regiment today, world XZ.
func _target_xz(reg: Dictionary) -> Vector2:
	return ctx.to_world(ArmySystem.position_of(ctx.repo, ctx.state(), reg))


## Stand one piece where it is SHOWN: at the camera's scale, facing the way
## it walks (or the camera at rest), SEATED on the ground under its whole
## footprint — tilted with the slope and lifted clear of it (Map3DUnits.seat)
## — never on the one point under its centre, which on a hillside buried half
## a piece as wide as a village (owner 2026-09-24: 斜面上兵人的一部分会被地图盖住).
func _place(code: String, piece: Dictionary) -> void:
	var repo := ctx.repo
	var xz: Vector2 = _shown_xz[code]
	var node: Node3D = piece["node"]
	_tops.erase(code)
	_rects.erase(code)
	var centre := Vector3(xz.x, ctx.height_at(xz), xz.y)
	if ctx.camera.is_position_behind(centre):
		node.visible = false
		return
	node.visible = true
	var k := Map3DUnits.scale_for(repo, ctx.camera.global_position.distance_to(centre),
		repo.bal("map3d_fov_deg"), ctx.view_size.y, float(piece["height_m"]), piece["size"])
	var reg := ArmySystem.regiment(repo, code)
	var ahead := _target_xz(reg) - xz
	var heading := ahead.normalized() if ahead.length() > 0.5 \
		else ArmySystem.heading_of(repo, ctx.state(), code)
	var cam := ctx.camera.global_position
	_want_yaw[code] = Map3DUnits.yaw_for(heading, Vector2(cam.x, cam.z), xz, piece.get("stand_deg", 0.0))
	if not _yaw.has(code):
		_yaw[code] = _want_yaw[code]
	var yaw := float(_yaw[code])
	var sit := Map3DUnits.seat_at(repo, ctx.height_at, xz, piece["extent"], yaw, k)
	var high := float(piece["height_m"]) * k
	# The clearance grows with the piece: far out the ground is DRAWN by a
	# coarser Terrain3D mesh than the heightmap it is sampled from.
	var ground := Vector3(xz.x, float(sit["y"]) + high * repo.bal("map3d_unit_seat_clear")
		- repo.bal("map3d_unit_sink_m"), xz.y)
	var up: Vector3 = sit["normal"]
	node.transform = Transform3D((Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw))
		.scaled(Vector3(k, k, k)), ground)
	var top := ground + up * high
	if ctx.camera.is_position_behind(top):
		return
	var s_px := ctx.viewport_px_scale()
	_tops[code] = ctx.camera.unproject_position(top) / s_px
	_rects[code] = Map3DUnits.screen_box(ctx.camera, ground, high,
		float(piece["half_w_m"]) * k, s_px)


## Per FRAME: walk every piece toward where the engine has it, and turn it
## toward where it should face. The engine moves a regiment once a DAY, a
## day's march at a time; drawn like that a column would hop a kilometre a
## second, so the piece WALKS the day's step over the day's real seconds
## (Map3DUnits.walk_speed) and stands still with the clock. True when any
## piece moved, so the view redraws the headcount chips hanging over them.
func step(delta: float) -> bool:
	if ctx == null or not shown:
		return false
	var repo := ctx.repo
	var moved := false
	for code: String in _pieces:
		var node: Node3D = _pieces[code]["node"]
		if not _shown_xz.has(code):
			continue
		var reg := ArmySystem.regiment(repo, code)
		var want := _target_xz(reg)
		var now: Vector2 = _shown_xz[code]
		if now != want:
			var speed := Map3DUnits.walk_speed(repo, ctx.state(), code, ctx.meta,
				ctx.clock_speed())
			_shown_xz[code] = Map3DUnits.walk(now, want, speed * delta,
				Map3DUnits.snap_m(repo, ctx.state(), code, ctx.meta))
			_place(code, _pieces[code])
			moved = true
		_sync_action(code)
		if node.visible and float(_yaw.get(code, 0.0)) != float(_want_yaw.get(code, 0.0)):
			var rate := deg_to_rad(repo.bal("map3d_unit_turn_deg_per_s")) * delta
			_yaw[code] = rotate_toward(float(_yaw.get(code, 0.0)),
				float(_want_yaw.get(code, 0.0)), rate)
			# Re-seated as it turns: a long (cavalry) piece turned across a
			# slope reaches different ground.
			_place(code, _pieces[code])
	if moved:
		_moves += 1
	return moved


## Bumped each frame a piece moves — part of the headcount chips' cache key.
func moves() -> int:
	return _moves


## The regiments' pieces' TOPS in design px, {code: Vector2} — where the
## headcount chip hangs. {} while the layer is down.
func screen_tops() -> Dictionary:
	return _tops


## The regiments' pieces' boxes on screen, {code: Rect2} in design px — what
## Map3DPicker tests a click against, so clicking the SOLDIER picks his
## regiment and not the province he is standing in.
func screen_rects() -> Dictionary:
	return _rects


## How many pieces are actually standing, for the tests and the bench.
func drawn_count() -> int:
	var n := 0
	for code: String in _pieces:
		if (_pieces[code]["node"] as Node3D).visible:
			n += 1
	return n


## Put a regiment's piece into an action by name ("GARRISON", "MARCH",
## "ATTACK"); a model without that action keeps the one it has.
func play(code: String, action: String) -> void:
	if not _pieces.has(code):
		return
	var anim: AnimationPlayer = _pieces[code]["anim"]
	if anim == null:
		return
	var name := Map3DUnits.clip_named(anim, action)
	if name == "" or anim.current_animation == name:
		return
	anim.play(name)


## The piece for a regiment, built on first sight. {} when its arm has no
## model (a fleet), which leaves it the flat counter it always had.
func _piece_of(code: String) -> Dictionary:
	if _pieces.has(code):
		_sync_action(code)
		return _pieces[code]
	var reg := ArmySystem.regiment(ctx.repo, code)
	if reg.is_empty():
		return {}
	var art: Dictionary = ctx.repo.army_art.get(MapObjects.army_piece(ctx.repo, reg), {})
	var path := String(art.get("model", ""))
	if path == "":
		return {}
	var scene := _scene(path)
	if scene == null:
		return {}
	var node := scene.instantiate() as Node3D
	if node == null:
		return {}
	node.name = code
	add_child(node)  # no owner: never saved into the authored scene
	var anim := Map3DUnits.find_anim(node)
	# A wargame piece is a miniature, not a body: at this scale its shadow
	# would be a mile of darkness across the country it stands in.
	for m: MeshInstance3D in Map3DUnits.meshes(node):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var span := Map3DUnits.model_size(node)
	_pieces[code] = {"node": node, "anim": anim, "height_m": span.y, "half_w_m": span.x,
		"extent": Map3DUnits.stand_extent(node), "stand_deg": float(art.get("stand_deg", "0")), "size": float(art.get("size", "1"))}
	_sync_action(code)
	return _pieces[code]


## The action follows the MARCH: a column walks while the clock runs and its
## piece is on the road — the engine's order, or the drawing catching up
## with where the engine already has it — and stands the moment it arrives.
## On a stopped clock a regiment under orders STANDS READY (the garrison
## pose, facing where it was sent) until play resumes (owner 2026-09-24:
## 兵棋不进行移动，直到玩家点击继续游戏按钮). The pose itself always plays, so
## an order given on a paused clock is seen to take at once.
func _sync_action(code: String) -> void:
	var walking := ArmySystem.order_of(ctx.repo, ctx.state(), code) == ArmySystem.ORDER_MARCH
	if _shown_xz.has(code):
		walking = walking or _shown_xz[code] != _target_xz(ArmySystem.regiment(ctx.repo, code))
	play(code, MARCH if walking and ctx.clock_speed() > 0 else GARRISON)


func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	else:
		Map3DWorldLoader.warn_once("units:" + path, "map3d units: no model at " + path)
	_scenes[path] = scene
	return scene


