@tool
class_name Map3DLayerUnits
extends Node3D
## MILITARY's PIECES: the player's regiments as animated wargame models
## standing on the ground (owner 2026-09-22, "把这两个兵棋人应用到游戏中去").
##
## One to six instanced .glb figures per regiment (Map3DFormation, by headcount),
## each posed by its own AnimationPlayer — the one layer that cannot be a MultiMesh.
##
## THE SIZE IS NOT THE MODEL'S SIZE: a miniature's, by the camera's distance
## (past map3d_unit_counter_scale none: the HUD's square counter). That rule,
## the facing, seating, measuring and screen box are Map3DUnits, the pure half.
##
## Takes everything from Map3DContext, never the Game autoload (a test scans).

## Editor preview: the player's regiments from the pack alone.
@export var preview := false: set = set_preview

const GARRISON := "GARRISON"
const MARCH := "MARCH"

var ctx: Map3DContext
## Whether the pieces show; Map3DView sets it from set_military.
var shown := false
## code -> {node, anims, height_m, half_w_m, extent, figures, ...} — model metres.
var _pieces: Dictionary = {}
## code -> the piece's box on screen, design px. What a click hits.
var _rects: Dictionary = {}
## code -> the screen point of the piece's TOP, design px (the chip hangs there).
var _tops: Dictionary = {}
## code -> the yaw it is turning toward, and the one it is at.
var _want_yaw: Dictionary = {}
var _yaw: Dictionary = {}
var _scenes: Dictionary = {}
## code -> where the piece is DRAWN, world XZ, on its day's march (step).
var _shown_xz: Dictionary = {}
var _days: Dictionary = {}  ## code -> {key, from, to, s0}: its day's march (Map3DUnits.along_day)
var _moves := 0


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)


## Shown or hidden (built on the first showing, then only hidden).
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


## Every piece placed, sized and turned for the camera, cut once per camera
## pose; the MARCH between two days is step()'s.
func refresh() -> void:
	if ctx == null or not shown or ctx.camera == null:
		return
	var repo := ctx.repo
	var live: Dictionary = {}
	_tops.clear()
	_rects.clear()
	for reg: Dictionary in ctx.regiments():
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


## Stand one piece where it is SHOWN: at the camera's scale, facing the way it
## walks (or the camera at rest), SEATED under its whole footprint, tilted with
## the slope and lifted clear (Map3DUnits.seat; owner 2026-09-24: 斜面上兵人的一部分会被地图盖住).
func _place(code: String, piece: Dictionary) -> void:
	var repo := ctx.repo
	var xz: Vector2 = _shown_xz[code]
	var node: Node3D = piece["node"]
	_tops.erase(code)
	_rects.erase(code)
	var centre := Vector3(xz.x, ctx.height_at(xz), xz.y)
	# Far out every regiment is its flat counter instead (Map3DUnits.as_counters).
	if ctx.camera.is_position_behind(centre) \
			or Map3DUnits.as_counters(repo, ctx.meta, ctx.distance, ctx.view_size.y):
		node.visible = false
		return
	node.visible = true
	var ref_m := Map3DGeometry.distance_for_bar(repo, ctx.meta,
		repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, ctx.camera.global_position.distance_to(centre),
		repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m, float(piece["height_m"]), piece["size"])
	var ahead: Vector2 = (_days[code]["to"] if _days.has(code) else xz) - xz
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


## Per FRAME: draw every piece where the day's share has it on its day's
## march (_day_of) and turn it toward its facing. True when any piece moved,
## so the view redraws the headcount chips hanging over them.
func step(delta: float) -> bool:
	if ctx == null or not shown:
		return false
	var repo := ctx.repo
	var moved := false
	for code: String in _pieces:
		var node: Node3D = _pieces[code]["node"]
		if not _shown_xz.has(code):
			continue
		var now: Vector2 = _shown_xz[code]
		var want := Map3DUnits.along_day(_day_of(code), ctx.day_share())
		var pace := 1.0
		if now != want:
			_shown_xz[code] = want
			_place(code, _pieces[code])
			moved = true
			# the feet keep pace with the ground (Map3DUnits.march_rate)
			pace = Map3DUnits.march_rate(repo, now.distance_to(want) / maxf(delta, 0.001),
				node.transform.basis.get_scale().x, float(_pieces[code]["clip_s"]), float(_pieces[code]["stride_m"]))
		for anim: AnimationPlayer in _pieces[code]["anims"]:
			anim.speed_scale = pace
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


## Bumped each frame a piece moves (the chips' cache key).
func moves() -> int:
	return _moves


## The pieces' TOPS in design px, {code: Vector2} — where the chip hangs.
func screen_tops() -> Dictionary:
	return _tops


## The pieces' boxes on screen, {code: Rect2} in design px — what a click on
## the SOLDIER hits (Map3DPicker), before the province under him.
func screen_rects() -> Dictionary:
	return _rects


## How many pieces are standing (tests, bench).
func drawn_count() -> int:
	var n := 0
	for code: String in _pieces:
		if (_pieces[code]["node"] as Node3D).visible:
			n += 1
	return n


## Put a regiment's figures into an action by name; one without it keeps its own.
func play(code: String, action: String) -> void:
	if not _pieces.has(code):
		return
	var anims: Array = _pieces[code]["anims"]
	for i in anims.size():
		var anim: AnimationPlayer = anims[i]
		var name := Map3DUnits.clip_named(anim, action)
		if name == "" or anim.current_animation == name:
			continue
		anim.play(name, ctx.repo.bal("map3d_unit_blend_s"))  # blended, never a snap
		if action == GARRISON:  # men at rest are not clones; a column marches in step
			anim.seek(fposmod(i * 0.37, anim.current_animation_length))


## The piece for a regiment, built on first sight; {} for an arm with no model (a fleet).
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
	var one := scene.instantiate() as Node3D
	if one == null:
		return {}
	# One figure measured, then its FORMATION by headcount (Map3DFormation).
	var span := Map3DUnits.model_size(one)
	var ext := Map3DUnits.stand_extent(one)
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(ctx.repo, ArmySystem.headcount(ctx.repo, reg)),
		ext, ctx.repo.bal("map3d_unit_formation_gap"))
	var node := Map3DFormation.build(scene, offs, one)
	node.name = code
	add_child(node)  # no owner: never saved into the authored scene
	var anims := Map3DFormation.anims_of(node)
	var half := Map3DFormation.half_extent(offs, ext)
	var clip := Map3DUnits.clip_named(anims[0], MARCH) if not anims.is_empty() else ""
	_pieces[code] = {"node": node, "anims": anims, "height_m": span.y,
		"half_w_m": maxf(half.x, half.y), "extent": half, "figures": offs.size(),
		"stand_deg": float(art.get("stand_deg", "0")),
		"size": float(art.get("size", "1")), "stride_m": float(art.get("stride_m", "0")),
		"clip_s": (anims[0] as AnimationPlayer).get_animation(clip).length if clip != "" else 0.0}
	_sync_action(code)
	return _pieces[code]


## A piece's day's march (Map3DUnits.day_march), remade when its row, the day
## or the couriers turn.
func _day_of(code: String) -> Dictionary:
	var st := ctx.state()
	var key := [st.regiments.get(code, {}), st.absolute_day(), st.next_courier_id, st.couriers.size()] if st != null else []
	if not _days.has(code) or _days[code]["key"] != key:
		var here := _target_xz(ArmySystem.regiment(ctx.repo, code))
		_days[code] = Map3DUnits.day_march(ctx.repo, st, code, ctx.meta, here, _shown_xz.get(code, here), ctx.day_share())
		_days[code]["key"] = key.duplicate(true)
	return _days[code]


## The action follows the MARCH: a column walks while the clock runs and its
## piece is on its day's march, and stands the moment it arrives.
## On a stopped clock it STANDS READY in the garrison pose, facing where it
## was sent (owner 2026-09-24: 兵棋不进行移动，直到玩家点击继续游戏按钮).
func _sync_action(code: String) -> void:
	var walking: bool = _days.has(code) and _shown_xz.get(code) != _days[code]["to"]
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


