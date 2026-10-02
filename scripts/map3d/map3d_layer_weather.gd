class_name Map3DLayerWeather
extends RefCounted
## The weather's LOOK on the 3D map (spec 2026-09-29-weather-visuals): the
## Map3DWeatherField of this spell and the next handed to the patched Terrain3D
## shader (Map3DGroundTint's weather_* uniforms) and turned from one to the
## other over the spell's last `blend_days` by the day's progress,
## like the sun. Presentation only: it reads Weather, never writes a thing.
## The clouds and the falling rain and snow read the same field from here.

var ctx: Map3DContext
var field: Map3DWeatherField
## How the weather is drawn (scenes/map3d/weather_look.tres, edited in the
## inspector).
var look := Map3DWeatherLook.shared()
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
## The next spell's field being built on a worker: its task id (-1: none) and
## the Dictionary the job writes its result into.
var _job_id := -1
var _job: Dictionary = {}


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
		field = Map3DWeatherField.new(ctx.repo, look)
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
	_mat.call("set_shader_param", "weather_step_px", float(field.step_px))
	var floats := look.ground_floats()
	for key: String in floats:
		_mat.call("set_shader_param", "weather_" + key, floats[key])
	# raw sRGB, turned linear in the shader (the heat stops' way)
	_mat.call("set_shader_param", "weather_mud_color", look.mud_color)
	_mat.call("set_shader_param", "weather_snow_color", look.snow_color)
	_mat.call("set_shader_param", "weather_wet_color", look.wet_color)
	_mat.call("set_shader_param", "weather_haze_color", look.haze_color)
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
	var b := Map3DWeatherField.blend_of(ctx.repo, st.absolute_day(), ctx.day_share(), look)
	var now_spell := int(b["spell"])
	var key := [ctx.repo.map_id, st.rng.seed_value() if st.rng != null else 0, override,
		st.manor_province.hash()]
	if key != _key or now_spell != _spell:
		var kinds := override.split(",", false)
		var pick_kind := Callable() if kinds.is_empty() else func(p: String) -> String:
			return kinds[posmod(p.hash(), kinds.size())]
		_take_next()  # nothing re-indexes the field under a worker
		if key == _key and now_spell == _spell + 1 and not _next.is_empty():
			# The spell turned as spells do: the next field is this one, and the
			# one after it is built on a worker (perf 2026-10-02: ~13 ms on the
			# frame the spell turned). Until it lands the next slot wears this
			# spell's images; the blend toward it starts only at the spell's end.
			_now = _next
			var next_kinds := field.kinds_for(ctx.repo, st, now_spell + 1, pick_kind)
			_next = {"ground": _now["ground"], "fall": _now["fall"], "kinds": next_kinds}
			_start_next(next_kinds)
		else:
			_now = field.build(ctx.repo, st, now_spell, pick_kind)
			_next = field.build(ctx.repo, st, now_spell + 1, pick_kind)
		_key = key
		_spell = now_spell
		_key_changed = true
		_upload()
	if _job_id >= 0 and (float(b["t"]) > 0.0 or WorkerThreadPool.is_task_completed(_job_id)):
		finish_next()  # it has landed — or the blend needs it now and waits
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


## Builds the next spell's field from `kinds` on the WorkerThreadPool. The job
## holds the field and the repository, never this layer, so a layer let go
## mid-build is still freed (and waits for it, NOTIFICATION_PREDELETE).
func _start_next(kinds: Dictionary) -> void:
	var f := field
	var repo := ctx.repo
	var job := {}
	_job = job
	_job_id = WorkerThreadPool.add_task(func() -> void: job["field"] = f.build_kinds(repo, kinds),
		false, "map3d weather field")


## The next spell's ground field as it stands (a test seam: a headless
## texture cannot be read back).
func next_ground() -> Image:
	return _next.get("ground")


## Whether the next spell's field is still a worker's job.
func building_next() -> bool:
	return _job_id >= 0


## Waits for the next spell's field (if one is being built) and puts it on
## the ground as the next slot.
func finish_next() -> void:
	if _take_next():
		_key_changed = true
		_upload()


## Waits for the worker's field and takes it as the next slot (not uploaded);
## false when none was being built.
func _take_next() -> bool:
	if _job_id < 0:
		return false
	WorkerThreadPool.wait_for_task_completion(_job_id)
	_job_id = -1
	if _job.has("field"):
		_next = _job["field"]
	_job = {}
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _job_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_job_id)


## The houses' share of the weather: the same field, its blend, snow's colour.
func _house_weather() -> Dictionary:
	var origin: Array = ctx.meta.get("pack_origin", [0.0, 0.0])
	return {"weather_now": _tex["ground_now"], "weather_next": _tex["ground_next"], "weather_on": 1.0,
		"weather_blend": _blend, "weather_origin": Vector2(float(origin[0]), float(origin[1])),
		"weather_m_per_px": float(ctx.meta.get("m_per_px", 50.0)), "weather_step_px": float(field.step_px),
		"weather_snow_color": look.snow_color, "weather_roof_snow": look.roof_snow,
		"weather_wet_dark": look.wet_dark}


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
