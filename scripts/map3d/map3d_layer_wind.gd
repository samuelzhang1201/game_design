class_name Map3DLayerWind
extends Node3D
## The wind (owner 2026-09-30: 草缓缓的随风摇摆…麦穗摇曳; node Viewport/Wind):
## one clock for the waves rolling over the crops and grass (Map3DGroundTint's
## wind stage) and the woods' sway (tree_sway.gdshader). It runs only while
## the game's clock does, like the clouds and the falling rain, at real time
## (a 4x clock does not make a gale). Presentation only: nothing here is read
## by the engine. Takes everything from Map3DContext — never the Game autoload.

var ctx: Map3DContext
var _trees: Map3DLayerTrees
var _time := 0.0


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	_trees = get_node_or_null("../Trees") as Map3DLayerTrees


## Seconds of wind so far (a test seam, and what the shaders are handed).
func time() -> float:
	return _time


func _process(delta: float) -> void:
	if ctx == null or ctx.repo.bal("map3d_wind_on") <= 0.0:
		return
	if ctx.clock_speed() > 0:
		_time += delta
	var repo := ctx.repo
	var a := deg_to_rad(repo.bal("map3d_wind_deg"))
	var dir := Vector2(cos(a), sin(a))
	var mat: Resource = ctx.terrain.get("material") if ctx.terrain != null else null
	if mat != null:
		# Terrain3D drops unknown uniforms after a load: put them back when
		# wind_on reads unset, as the weather does
		var on: Variant = mat.call("get_shader_param", "wind_on")
		if not (on is float and is_equal_approx(on, 1.0)):
			mat.call("set_shader_param", "wind_on", 1.0)
			mat.call("set_shader_param", "wind_dir", dir)
			for key in ["speed_mps", "wave_m", "field_amp", "grass_amp", "near_m", "far_m", "storm_gain"]:
				mat.call("set_shader_param", "wind_" + key, repo.bal("map3d_wind_" + key))
		mat.call("set_shader_param", "wind_time", _time)
	if _trees != null and _trees.material != null:
		var tm := _trees.material
		tm.set_shader_parameter("wind_time", _time)
		tm.set_shader_parameter("wind_dir", dir)
		tm.set_shader_parameter("sway_m", repo.bal("map3d_wind_tree_sway_m"))
		tm.set_shader_parameter("sway_hz", repo.bal("map3d_wind_tree_hz"))
