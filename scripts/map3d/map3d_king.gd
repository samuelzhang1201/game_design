@tool
class_name Map3DKing
extends Node3D
## An independent royal traveller. UI supplies copied state and today's path;
## this layer only draws it and never advances the simulation.

@export var preview := false: set = set_preview
@export var model: PackedScene
@export var size_ratio := 1.0
@export var stride_m := 2.4
@export var blend_s := 0.3

var ctx: Map3DContext
var selected := false
var _snapshot: Dictionary = {}
var _piece: Dictionary = {}
var _track: Dictionary = {}
var _rect := Rect2()
var _observing := false
var _previous := Vector2.INF
var _start_share := 0.0
var _origin_m := Vector2.ZERO
var _day := -1
var _route_key: Array = []
var _command_s := 0.0

func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	Map3DPreview.clear_generated(self)
	_piece.clear()
	transform = Transform3D.IDENTITY
	if on:
		var context := Map3DPreview.context_for(self)
		Map3DPreview.prepare(self, context)
		var viewport := Map3DWorld.editor_viewport_3d()
		if viewport != null:
			context.camera = viewport.get_camera_3d()
		bind(context)
		apply_snapshot({"king": KingSystem.initial_state(context.repo), "king_path": []})
		step(0.0)
	Map3DPreview.sync_viewport(self)

func bind(context: Map3DContext) -> void:
	ctx = context

func apply_snapshot(snapshot: Dictionary) -> void:
	var king: Dictionary = snapshot.get("king", {})
	var key: Array = [king.get("x_m", 0), king.get("y_m", 0), king.get("route", []), king.get("follow_code", ""), snapshot.get("king_path", [])]
	var day := int(snapshot.get("absolute_day", 0))
	if ctx != null and day == _day and key != _route_key and key.slice(0, 2) == _route_key.slice(0, 2):
		_origin_m = position_m(ctx.day_share())
		_start_share = ctx.day_share()
		var anim: AnimationPlayer = _piece.get("anim")
		var command := Map3DUnits.clip_named(anim, "COMMAND") if anim != null else ""
		_command_s = anim.get_animation(command).length if command != "" else 0.0
	elif day != _day or key.slice(0, 2) != _route_key.slice(0, 2):
		_start_share = 0.0
		_origin_m = Vector2(float(king.get("x_m", 0)), float(king.get("y_m", 0)))
	_day = day
	_route_key = key.duplicate(true)
	_snapshot = snapshot.duplicate(true)

static func along(origin: Vector2, path: Array, share: float) -> Vector2:
	var points := PackedVector2Array([Vector2(origin)])
	for point: Vector2i in path:
		points.append(Vector2(point))
	return Vector2(origin) if path.is_empty() else MarchRoute.along(points, clampf(share, 0.0, 1.0))

func position_m(share: float) -> Vector2:
	var progress := clampf((share - _start_share) / maxf(1.0 - _start_share, 0.001), 0.0, 1.0)
	return along(_origin_m, _snapshot.get("king_path", []), progress)

func observe() -> void:
	_observing = true

func action_for(moving: bool) -> String:
	if moving:
		_observing = false
		return "MARCH"
	if _command_s > 0.0:
		return "COMMAND"
	return "OBSERVE" if _observing else "STANDBY"

func screen_rect() -> Rect2:
	return _rect

func step(delta: float) -> void:
	_rect = Rect2()
	if ctx == null or ctx.camera == null or model == null or (_snapshot.get("king", {}) as Dictionary).is_empty():
		visible = false
		return
	visible = true
	if _piece.is_empty():
		var figure := model.instantiate() as Node3D
		add_child(figure)
		var span := Map3DUnits.model_size(figure)
		_piece = {"node": self, "figs": [figure], "height_m": maxf(span.y, 0.01),
			"extent": Map3DUnits.stand_extent(figure), "anim": Map3DUnits.find_anim(figure), "action": ""}
	var metres := position_m(ctx.day_share())
	var at := ctx.to_world(metres / ArmySystem.metres_per_pack_px(ctx.repo))
	var path: Array = _snapshot.get("king_path", [])
	var moving := not path.is_empty() and position_m(0.0).distance_to(position_m(1.0)) > 0.5 and ctx.clock_speed() > 0
	if _previous == Vector2.INF:
		_previous = at
	_track = Map3DUnits.track(_track, _previous, at)
	var heading: Vector2 = _track.get("heading", Vector2.ZERO)
	if heading == Vector2.ZERO and not path.is_empty():
		heading = Vector2(path[0]) - position_m(0.0)
	var yaw := Map3DUnits.yaw_for(heading, Vector2.ZERO, at)
	var ref_m := Map3DGeometry.distance_for_bar(ctx.repo, ctx.meta, ctx.repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var scale_m := Map3DUnits.scale_for(ctx.repo, ctx.repo.bal("map3d_fov_deg"), ctx.view_size.y,
		ref_m, float(_piece["height_m"]), size_ratio)
	Map3DUnitRig.seat(ctx.repo, ctx.height_at, _piece, at, yaw, scale_m)
	Map3DUnitGlow.place(ctx.repo, ctx.height_at, _piece, selected, scale_m)
	var anim: AnimationPlayer = _piece["anim"]
	if anim != null:
		var action := action_for(moving)
		var clip := Map3DUnits.clip_named(anim, action)
		if clip != "":
			if _piece["action"] != action:
				anim.play(clip, blend_s)
				_piece["action"] = action
			var length := anim.get_animation(clip).length
			anim.speed_scale = Map3DUnitRig.gait_rate(at.distance_to(_previous) / maxf(delta, 0.001),
				scale_m, length, stride_m, ctx.repo.bal("map3d_unit_anim_min"),
				ctx.repo.bal("map3d_unit_anim_max")) if moving else 1.0

	_previous = at
	_command_s = maxf(_command_s - delta, 0.0)
	_rect = Map3DUnits.screen_box(ctx.camera, position, float(_piece["height_m"]) * scale_m,
		(_piece["extent"] as Vector2).x * scale_m, ctx.viewport_px_scale())


static func entry(snapshot: Dictionary, repo: DataRepository, state: GameState) -> Dictionary:
	var king: Dictionary = snapshot.get("king", {})
	var lines: Array = [String(king.get("travel_state", "stationary")).capitalize()]
	var follow := String(king.get("follow_code", ""))
	if follow != "":
		lines.append("With " + MapObjects.label_of(repo, {"kind": "army", "code": follow}, state))
	var route: Array = king.get("route", [])
	if not route.is_empty():
		lines.append("On the road — %d waypoints ahead." % route.size())
	return {"title": "The king", "lines": lines, "ask": "", "obj": {"kind": "king"}}
