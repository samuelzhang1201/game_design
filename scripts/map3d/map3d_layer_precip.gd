class_name Map3DLayerPrecip
extends Node3D
## The falling rain and snow (spec 2026-09-29-weather-visuals; node
## Viewport/Precip, children Rain and Snow): two world-space GPUParticles3D
## born over a box round the camera's target and kept only where the weather
## field says it rains or snows (precip_fall.gdshader), drawn as faint streaks
## and flakes (precip_drop.gdshader). Everything scales with the camera's
## distance, so a drop holds its size on screen; it falls only while the clock
## runs, like the clouds, and only nearer than map3d_weather_fall_far_view_m —
## far out the ground and the clouds carry the weather.

const FALL_MAT := preload("res://scenes/map3d/materials/precip_fall.tres")
const DROP_MAT := preload("res://scenes/map3d/materials/precip_drop.tres")
const KINDS := ["rain", "snow"]

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
		var node := get_node_or_null(kind.capitalize()) as GPUParticles3D
		if node == null:
			node = GPUParticles3D.new()
			node.name = kind.capitalize()
			add_child(node)
		var fall := (FALL_MAT as ShaderMaterial).duplicate() as ShaderMaterial
		var drop := (DROP_MAT as ShaderMaterial).duplicate() as ShaderMaterial
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = drop
		node.process_material = fall
		node.draw_pass_1 = quad
		node.local_coords = false
		node.amount = maxi(1, int(repo.bal("map3d_weather_%s_count" % kind)))
		node.lifetime = repo.bal("map3d_weather_%s_life_s" % kind)
		node.explosiveness = 0.0
		node.randomness = 0.0
		node.fixed_fps = 0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_aabb = AABB(Vector3(-1e7, -1e5, -1e7), Vector3(2e7, 2e5, 2e7))
		node.emitting = false
		var k := 0.0 if kind == "rain" else 1.0
		fall.set_shader_parameter("kind", k)
		fall.set_shader_parameter("pack_origin", Vector2(float(origin[0]), float(origin[1])))
		fall.set_shader_parameter("m_per_px", float(ctx.meta.get("m_per_px", 50.0)))
		fall.set_shader_parameter("step_px", repo.bal("map3d_weather_field_step_px"))
		drop.set_shader_parameter("kind", k)
		drop.set_shader_parameter("opacity", repo.bal("map3d_weather_%s_opacity" % kind))
		drop.set_shader_parameter("gain", repo.bal("map3d_weather_%s_gain" % kind))
		drop.set_shader_parameter("tint", MapTerrain.palette_color(repo,
			"weather_rain" if kind == "rain" else "weather_flake", Color(0.85, 0.88, 0.9)))
		_parts[kind] = {"node": node, "fall": fall, "drop": drop}


## A tier's share of the drops (graphics_quality weather_particles).
func apply_quality(row: Dictionary) -> void:
	_ratio = clampf(Map3DQuality.num(row, "weather_particles"), 0.0, 1.0)
	for kind: String in _parts:
		(_parts[kind]["node"] as GPUParticles3D).amount_ratio = _ratio


## How much falls now: 0 with the clock stopped, the look off or the camera
## past map3d_weather_fall_far_view_m, 1 nearer than _near_view_m.
static func strength_of(repo: DataRepository, running: bool, distance: float) -> float:
	if not running or repo.bal("map3d_weather_look") <= 0.0:
		return 0.0
	return 1.0 - smoothstep(repo.bal("map3d_weather_fall_near_view_m"),
		repo.bal("map3d_weather_fall_far_view_m"), distance)


## The box, sizes and speeds from the camera's distance, and the field's
## textures; a kind emits only while somewhere in the field it falls.
func step() -> void:
	if ctx == null or weather == null or _parts.is_empty():
		return
	var repo := ctx.repo
	_strength = strength_of(repo, ctx.clock_speed() > 0, ctx.distance) * (1.0 if _ratio > 0.0 else 0.0)
	var d := ctx.distance
	var ground := ctx.height_at(ctx.target)
	var wind := Vector2.from_angle(deg_to_rad(repo.bal("map3d_cloud_wind_deg")))
	for kind: String in _parts:
		var node: GPUParticles3D = _parts[kind]["node"]
		var on := _strength > 0.01 and weather.falls(kind)
		if node.emitting != on:
			node.emitting = on
		if not on:
			continue
		var fall: ShaderMaterial = _parts[kind]["fall"]
		var drop: ShaderMaterial = _parts[kind]["drop"]
		var height := d * repo.bal("map3d_weather_fall_height_share")
		var speed := height / maxf(node.lifetime, 0.01)
		var slant := repo.bal("map3d_weather_%s_slant" % kind) * speed
		fall.set_shader_parameter("box_center", Vector3(ctx.target.x, ground, ctx.target.y))
		fall.set_shader_parameter("box_half", Vector2.ONE * d * repo.bal("map3d_weather_fall_box_share"))
		fall.set_shader_parameter("box_height", height)
		fall.set_shader_parameter("fall_m_s", speed)
		fall.set_shader_parameter("wind_m_s", wind * slant)
		fall.set_shader_parameter("sway_m_s", speed * repo.bal("map3d_weather_snow_sway"))
		fall.set_shader_parameter("strength", _strength)
		fall.set_shader_parameter("fall_now", weather.texture("fall_now"))
		fall.set_shader_parameter("fall_next", weather.texture("fall_next"))
		fall.set_shader_parameter("blend", weather.blend())
		drop.set_shader_parameter("length_m", d * repo.bal("map3d_weather_%s_length_share" % kind))
		drop.set_shader_parameter("width_m", d * repo.bal("map3d_weather_%s_width_share" % kind))
		drop.set_shader_parameter("fall_dir", Vector3(wind.x * slant, -speed, wind.y * slant).normalized())


func strength() -> float: return _strength
func emitting(kind: String) -> bool:
	return _parts.has(kind) and (_parts[kind]["node"] as GPUParticles3D).emitting
