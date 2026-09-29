class_name Map3DLayerWeather
extends RefCounted
## The weather's LOOK on the 3D map (spec 2026-09-29-weather-visuals): the
## Map3DWeatherField of this spell and the next handed to the patched Terrain3D
## shader (Map3DGroundTint's weather_* uniforms) and turned from one to the
## other over the spell's last map3d_weather_blend_days by the day's progress,
## like the sun. Presentation only: it reads Weather, never writes a thing.
## The clouds and the falling rain and snow read the same field from here.

var ctx: Map3DContext
var field: Map3DWeatherField
## The terrain material carrying the patch (null without one: the fixture).
var _mat: Resource
## A tool's forced sky ("" = the real weather): every province wears it, or
## with several kinds joined by commas, one of them each (by a hash of its code).
var override := ""
var _key: Array = []
var _spell := -1
var _now: Dictionary = {}
var _next: Dictionary = {}
var _tex: Dictionary = {}  # ground_now, ground_next, fall_now, fall_next
var _blend := 0.0
var _key_changed := false


## The falling rain and snow (the scene's Viewport/Precip), stepped with the
## field, and the houses, whose roofs take the snow.
var precip: Map3DLayerPrecip
var houses: Map3DLayerHouses


func bind(p_ctx: Map3DContext, tint_material: Resource, p_precip: Map3DLayerPrecip = null,
		p_houses: Map3DLayerHouses = null) -> void:
	ctx = p_ctx
	_mat = tint_material
	precip = p_precip
	houses = p_houses
	if on():
		field = Map3DWeatherField.new(ctx.repo)
	if precip != null:
		precip.build(ctx, self)


## A graphics tier's share of the falling drops.
func apply_quality(row: Dictionary) -> void:
	if precip != null:
		precip.apply_quality(row)


## Every weather uniform on the terrain material. Terrain3D rebuilds its
## material after a load and drops what it did not know then, so step() puts
## them back whenever weather_on reads other than 1.
func _apply_uniforms() -> void:
	if _mat == null or _tex.is_empty():
		return
	var repo := ctx.repo
	_mat.call("set_shader_param", "weather_step_px", float(field.step_px))
	for key in ["warp_m", "warp_scale_m", "dim", "flat", "wet_dark", "wet_rough", "mud_mix",
			"snow_slope", "snow_patch_m", "snow_rough", "snow_detail", "snow_steep", "snow_soft", "mud_dark",
			"wet_cool", "haze"]:
		_mat.call("set_shader_param", "weather_" + key, repo.bal("map3d_weather_" + key))
	# raw sRGB, turned linear in the shader (the heat stops' way)
	_mat.call("set_shader_param", "weather_mud_color",
		MapTerrain.palette_color(repo, "weather_mud", Color("#6E5536")))
	_mat.call("set_shader_param", "weather_snow_color",
		MapTerrain.palette_color(repo, "weather_snow", Color("#E9EDEF")))
	_mat.call("set_shader_param", "weather_wet_color", MapTerrain.palette_color(repo, "weather_wet", Color("#737F8C")))
	_mat.call("set_shader_param", "weather_haze_color", MapTerrain.palette_color(repo, "weather_haze", Color("#B8BEC4")))
	_mat.call("set_shader_param", "weather_now", _tex["ground_now"])
	_mat.call("set_shader_param", "weather_next", _tex["ground_next"])
	_mat.call("set_shader_param", "weather_on", 1.0)


## Whether the weather is drawn at all (balance map3d_weather_look).
func on() -> bool:
	return ctx != null and ctx.repo.bal("map3d_weather_look") > 0.0


## Every province under `kind` ("" gives the real weather back) — for tools.
func set_override(kind: String) -> void:
	override = kind
	_key = []


## Brings the fields up to the day and the blend up to the moment; a field is
## built only when a spell turns (the next one's becomes this one's).
func step() -> void:
	if not on() or field == null:
		return
	var st := ctx.state()
	if st == null:
		return
	var b := Map3DWeatherField.blend_of(ctx.repo, st.absolute_day(), ctx.day_share())
	var spell := int(b["spell"])
	var key := [ctx.repo.map_id, st.rng.seed_value() if st.rng != null else 0, override,
		st.manor_province.hash()]
	if key != _key or spell != _spell:
		var kinds := override.split(",", false)
		var kind_of := Callable() if kinds.is_empty() else func(p: String) -> String:
			return kinds[posmod(p.hash(), kinds.size())]
		if key == _key and spell == _spell + 1 and not _next.is_empty():
			_now = _next
		else:
			_now = field.build(ctx.repo, st, spell, kind_of)
		_next = field.build(ctx.repo, st, spell + 1, kind_of)
		_key = key
		_spell = spell
		_key_changed = true
		_upload()
	var turned := not is_equal_approx(_blend, float(b["t"])) or _key_changed
	_key_changed = false
	_blend = float(b["t"])
	if houses != null and turned:
		houses.weather = _house_weather()
		for mat: ShaderMaterial in houses.surface_mats:
			for k: String in houses.weather:
				mat.set_shader_parameter(k, houses.weather[k])
	if precip != null:
		precip.step()
	if _mat != null:
		var lit: Variant = _mat.call("get_shader_param", "weather_on")
		if not (lit is float and is_equal_approx(lit, 1.0)):
			_apply_uniforms()
		_mat.call("set_shader_param", "weather_blend", _blend)


## The houses' share of the weather: the same field, its blend, snow's colour.
func _house_weather() -> Dictionary:
	var origin: Array = ctx.meta.get("pack_origin", [0.0, 0.0])
	return {"weather_now": _tex["ground_now"], "weather_next": _tex["ground_next"], "weather_on": 1.0,
		"weather_blend": _blend, "weather_origin": Vector2(float(origin[0]), float(origin[1])),
		"weather_m_per_px": float(ctx.meta.get("m_per_px", 50.0)), "weather_step_px": float(field.step_px),
		"weather_snow_color": MapTerrain.palette_color(ctx.repo, "weather_snow", Color("#E9EDEF")),
		"weather_roof_snow": ctx.repo.bal("map3d_weather_roof_snow"),
		"weather_wet_dark": ctx.repo.bal("map3d_weather_wet_dark")}


func _upload() -> void:
	for pair in [["ground_now", _now, "ground"], ["ground_next", _next, "ground"],
			["fall_now", _now, "fall"], ["fall_next", _next, "fall"]]:
		var img: Image = (pair[1] as Dictionary)[pair[2]]
		var tex: ImageTexture = _tex.get(pair[0])
		if tex != null and tex.get_size() == Vector2(img.get_size()):
			tex.update(img)
		else:
			_tex[pair[0]] = ImageTexture.create_from_image(img)
	_apply_uniforms()


## The (wet, mud, snow, overcast) at a world XZ point, blended like the ground
## — for the clouds, read on the CPU.
func look_at(xz: Vector2) -> Color:
	if _now.is_empty():
		return Color(0, 0, 0, 0)
	var px := ctx.to_pack(xz)
	return field.sample(_now["ground"], px).lerp(field.sample(_next["ground"], px), _blend)


## The textures the falling weather samples, and the moment's blend.
func texture(key: String) -> ImageTexture: return _tex.get(key)
func blend() -> float: return _blend
func spell() -> int: return _spell
## Whether rain ("rain") or snow ("snow") falls anywhere in this spell's or
## the next's field.
func falls(kind: String) -> bool:
	var key := "rainfall" if kind == "rain" else "snowfall"
	for f: Dictionary in [_now, _next]:
		for k: String in (f.get("kinds", {}) as Dictionary).values():
			if float((ctx.repo.weather_kinds.get(k, {}) as Dictionary).get(key, 0.0)) > 0.0:
				return true
	return false


## The kind over a province this spell (the field's own reading).
func kind_of(province: String) -> String: return String((_now.get("kinds", {}) as Dictionary).get(province, Weather.CLEAR))
