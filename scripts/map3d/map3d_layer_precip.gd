class_name Map3DLayerPrecip
extends Node3D
## The falling rain and snow (spec 2026-09-29-weather-visuals; node
## Viewport/Precip, children Rain and Snow): two world-space GPUParticles3D
## born over a box round the camera's target and kept only where the weather
## field says it rains or snows (precip_fall.gdshader), drawn as faint streaks
## and flakes (precip_drop.gdshader). Everything scales with the camera's
## distance, so a drop holds its size on screen; it falls only while the clock
## runs, like the clouds, and only nearer than `fall_far_view_m` — far out the
## ground and the clouds carry the weather. Each kind's look is its own node
## (Map3DPrecipKind), edited in the inspector (owner 2026-10-02).

const KINDS := ["rain", "snow"]

## Nearer than this (camera distance, world metres) the weather falls in full;
## it thins out to nothing at `fall_far_view_m` (a flake far out read as a
## settlement dot).
@export var fall_near_view_m := 6000.0
@export var fall_far_view_m := 13000.0
## The box the drops are born over: its half-width and its height, shares of
## the camera's distance.
@export var box_share := 1.1
@export var height_share := 0.35

var ctx: Map3DContext
var weather: Map3DLayerWeather
var _ratio := 1.0
## kind -> {node: GPUParticles3D, fall: ShaderMaterial, drop: ShaderMaterial}
var _parts: Dictionary = {}
var _strength := 0.0


func build(p_ctx: Map3DContext, p_weather: Map3DLayerWeather) -> void:
	ctx = p_ctx
	weather = p_weather
	var repo := ctx.repo
	var origin: Array = ctx.meta.get("pack_origin", [0.0, 0.0])
	for kind: String in KINDS:
		var node := get_node(kind.capitalize()) as Map3DPrecipKind
		# this view's own copies: the field, the box and the sizes move with it
		var fall := (node.process_material as ShaderMaterial).duplicate() as ShaderMaterial
		var quad := (node.draw_pass_1 as QuadMesh).duplicate() as QuadMesh
		var drop := (quad.material as ShaderMaterial).duplicate() as ShaderMaterial
		quad.material = drop
		node.process_material = fall
		node.draw_pass_1 = quad
		node.emitting = false
		fall.set_shader_parameter("kind", float(node.kind))
		fall.set_shader_parameter("pack_origin", Vector2(float(origin[0]), float(origin[1])))
		fall.set_shader_parameter("m_per_px", float(ctx.meta.get("m_per_px", 50.0)))
		fall.set_shader_parameter("step_px", repo.bal("map3d_weather_field_step_px"))
		drop.set_shader_parameter("kind", float(node.kind))
		_parts[kind] = {"node": node, "fall": fall, "drop": drop}


## A tier's share of the drops (graphics_quality weather_particles).
func apply_quality(row: Dictionary) -> void:
	_ratio = clampf(Map3DQuality.num(row, "weather_particles"), 0.0, 1.0)
	for kind: String in _parts:
		(_parts[kind]["node"] as GPUParticles3D).amount_ratio = _ratio


## How much falls now: 0 with the clock stopped, the look off or the camera
## past `fall_far_view_m`, 1 nearer than `fall_near_view_m`.
func strength_of(repo: DataRepository, running: bool, distance: float) -> float:
	if not running or repo.bal("map3d_weather_look") <= 0.0:
		return 0.0
	return 1.0 - smoothstep(fall_near_view_m, fall_far_view_m, distance)


## The box, sizes and speeds from the camera's distance, and the field's
## textures; a kind emits only while somewhere in the field it falls.
func step() -> void:
	if ctx == null or weather == null or _parts.is_empty():
		return
	var repo := ctx.repo
	_strength = strength_of(repo, ctx.clock_speed() > 0, ctx.distance) * (1.0 if _ratio > 0.0 else 0.0)
	var d := ctx.distance
	var ground := ctx.height_at(ctx.target)
	var wind_node := get_node_or_null("../Wind") as Map3DLayerWind
	var wind := wind_node.direction() if wind_node != null else Vector2.RIGHT
	for kind: String in _parts:
		var node: Map3DPrecipKind = _parts[kind]["node"]
		var on := _strength > 0.01 and weather.falls(kind)
		if node.emitting != on:
			node.emitting = on
		if not on:
			continue
		var fall: ShaderMaterial = _parts[kind]["fall"]
		var drop: ShaderMaterial = _parts[kind]["drop"]
		var height := d * height_share
		var speed := height / maxf(node.lifetime, 0.01)
		var slant := node.slant * speed
		fall.set_shader_parameter("box_center", Vector3(ctx.target.x, ground, ctx.target.y))
		fall.set_shader_parameter("box_half", Vector2.ONE * d * box_share)
		fall.set_shader_parameter("box_height", height)
		fall.set_shader_parameter("fall_m_s", speed)
		fall.set_shader_parameter("wind_m_s", wind * slant)
		fall.set_shader_parameter("wind_dir", wind)
		fall.set_shader_parameter("sway_m_s", speed * node.sway)
		fall.set_shader_parameter("strength", _strength)
		fall.set_shader_parameter("fall_now", weather.texture("fall_now"))
		fall.set_shader_parameter("fall_next", weather.texture("fall_next"))
		fall.set_shader_parameter("blend", weather.blend())
		drop.set_shader_parameter("length_m", d * node.length_share)
		drop.set_shader_parameter("width_m", d * node.width_share)


func strength() -> float: return _strength
func emitting(kind: String) -> bool:
	return _parts.has(kind) and (_parts[kind]["node"] as GPUParticles3D).emitting
