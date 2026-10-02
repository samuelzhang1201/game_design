@tool
class_name Map3DLayerClouds
extends MultiMeshInstance3D
## The 3D map's clouds as their own layer (spec 2026-09-20 §1, node
## Viewport/Clouds, child Shadows): a deck of drifting quads high over the
## land, plus a shadow-only twin sharing its MultiMesh so a cloud's shape and
## its shadow always match. Sitting directly under the SubViewport, this node
## IS the layer layer_names()/set_layer_visible() find as "Clouds"; hiding it
## hides the twin with it, since a Node3D's visibility is inherited by its
## children.
##
## The cloud and shadow shaders must stay two SEPARATE files (the Compatibility
## trap, CLAUDE.md): a shader that so much as mentions ALPHA_SCISSOR_THRESHOLD
## anywhere pushes the whole material into an alpha-scissor pipeline under GL
## Compatibility and silently blanks its blended rendering.

## The deck's and the twin's looks — two materials over two shader files
## (owner 2026-10-02: edited in the inspector — the deck's opacity, its fade
## near the camera, its glow, a storm's slate and how overcast turns it; the
## shadow's dense heart and stipple). Their `shape` is the editor's preview;
## build() sets the seeded one.
const CLOUD_MAT := preload("res://scenes/map3d/materials/cloud_deck.tres")
const CLOUD_SHADOW_MAT := preload("res://scenes/map3d/materials/cloud_shadow.tres")

## Editor preview (Task 22): one still frame of the drifting deck.
@export var preview := false: set = set_preview

## The deck (owner 2026-09-30: 云的效果请再淡一点，稀疏的分布在大地图，不要集中):
## at most `max_clouds` (a graphics tier may cap it lower), each its seeded
## shape, `height_m` up, `size_min_m`..`size_max_m` across and
## `depth_ratio` as deep.
@export_group("Deck")
@export var max_clouds := 14
@export var cloud_seed := 23
@export var height_m := 3500.0
@export var size_min_m := 3000.0
@export var size_max_m := 8000.0
@export var depth_ratio := 0.45
## How they drift and come and go: a new one each `interval_s` while the
## clock runs, fading in and out over `fade_s`, spread over the whole map by
## Mitchell's best of `candidates` at `min_gap_m`.
@export_group("Drift")
@export var speed_m_s := 40.0
@export var interval_s := 1.5
@export var fade_s := 1.2
@export var min_gap_m := 18000.0
@export var candidates := 16
## Over bad weather: how hard the overcast pulls the deck, darkens and
## thickens a cloud (spec 2026-09-29-weather-visuals).
@export_group("Weather")
@export var weather_pull := 0.3
@export var weather_dark := 1.0
@export var weather_thick := 0.0

var ctx: Map3DContext
## The weather's look (the view hands it over): clouds gather over bad weather
## and darken there (spec 2026-09-29-weather-visuals).
var weather: Map3DLayerWeather
var _field: Map3DCloudField
var _params: Dictionary
var _depth_ratio := 0.6
var _ground_cache := Rect2()
var _ground_cache_target := Vector2.ZERO
var _ground_cache_distance := -1.0
var _ground_cache_yaw := 0.0
var _ground_cache_size := Vector2.ZERO
var _ground_cache_valid := false


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


## The deck as the game builds it, then ONE step with the clock running, so
## the editor shows clouds rather than an empty sky — into an UNOWNED twin of
## this node (its own Shadows and MultiMesh come with it), never onto the
## authored one. A pack with no 3D build gets the placeholder.
func preview_build(p_ctx: Map3DContext) -> void:
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		ctx = p_ctx
		Map3DPreview.show_placeholder(self, CLOUD_MAT)
		return
	p_ctx.clock_fn = func() -> int: return 1
	var deck := Map3DPreview.proxy(self, get_script(), "CloudsPreview") as Map3DLayerClouds
	deck.build(p_ctx)
	deck.step(0.1)


## The clouds drift down the map's one wind (the world's Wind node).
func _wind_deg() -> float:
	var wind := get_node_or_null("../Wind") as Map3DLayerWind
	return wind.deg if wind != null else 0.0


func build(p_ctx: Map3DContext, p_weather: Map3DLayerWeather = null) -> void:
	ctx = p_ctx
	weather = p_weather
	_field = Map3DCloudField.new(cloud_seed)
	_params = {"max": max_clouds, "size_min": size_min_m, "size_max": size_max_m,
		"speed_m_s": speed_m_s, "wind_deg": _wind_deg(),
		"fade_s": fade_s, "interval_s": interval_s, "min_gap_m": min_gap_m, "spread": true,
		"candidates": candidates, "weight_pull": weather_pull, "wrap": true}
	_depth_ratio = depth_ratio
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = int(_params["max"])
	mm.visible_instance_count = 0
	self.multimesh = mm
	var shape := Map3DCloudField.cloud_texture(cloud_seed)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _cloud_material(shape)
	extra_cull_margin = 16384.0
	# The authored scene carries the twin (Viewport/Clouds/Shadows); a bare
	# layer makes its own.
	var twin := get_node_or_null("Shadows") as MultiMeshInstance3D
	if twin == null:
		twin = MultiMeshInstance3D.new()
		twin.name = "Shadows"
		add_child(twin)
	twin.multimesh = mm
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	twin.material_override = _cloud_shadow_material(shape)
	twin.extra_cull_margin = 16384.0


func _cloud_material(shape: Texture2D) -> ShaderMaterial:
	var mat := (CLOUD_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	mat.render_priority = Map3DPriority.CLOUDS
	mat.set_shader_parameter("shape", shape)
	return mat


## The shadow-only twin's OWN shader (cloud_shadow.gdshader — see its note
## and cloud_deck.gdshader's: the two must stay separate files under this
## renderer, not one shader gated by a `shadow_pass` uniform).
func _cloud_shadow_material(shape: Texture2D) -> ShaderMaterial:
	var mat := (CLOUD_SHADOW_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("shape", shape)
	return mat


## The ground rect the camera sees (its four corners' ground hits), wide
## enough for the sky when a corner looks past the horizon — cached on the
## camera pose (fix round 1, owner 2026-09-18: 4 raycasts every _process
## frame regardless of whether the camera moved), invalidated only when
## target, distance, yaw or the view's own size changes.
func _visible_ground() -> Rect2:
	if _ground_cache_valid and _ground_cache_target == ctx.target and _ground_cache_distance == ctx.distance \
			and _ground_cache_yaw == ctx.yaw and _ground_cache_size == ctx.view_size:
		return _ground_cache
	var r := Rect2(ctx.target, Vector2.ZERO)
	for f: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
		var hit: Variant = ctx.ground_at(ctx.view_size * f)
		r = r.expand(Vector2((hit as Vector3).x, (hit as Vector3).z) if hit != null
			else ctx.target + Vector2(ctx.distance, ctx.distance) * (f * 2.0 - Vector2.ONE) * 2.0)
	_ground_cache = r
	_ground_cache_target = ctx.target
	_ground_cache_distance = ctx.distance
	_ground_cache_yaw = ctx.yaw
	_ground_cache_size = ctx.view_size
	_ground_cache_valid = true
	return r


## Steps the cloud field and pushes it into the MultiMesh — called from the
## view's _process every frame the view exists, even unhovered, so the sky
## keeps drifting and fading while the player looks elsewhere.
func step(delta: float) -> void:
	if _field == null:
		return
	var wet := weather != null and weather.on()
	if wet:
		_params["weight_fn"] = func(xz: Vector2) -> float: return weather.look_at(xz).a
	else:
		_params.erase("weight_fn")
	_field.step(delta, ctx.clock_speed() > 0, ctx.clock_speed(), _sky_rect(), _params)
	var h := height_m
	var dark := weather_dark
	var thick := weather_thick
	var n := _field.clouds.size()
	multimesh.visible_instance_count = n
	for i in n:
		var c: Dictionary = _field.clouds[i]
		var s := float(c["size"])
		var puff := Basis(Vector3.UP, float(c["rot"])).scaled(Vector3(s, 1.0, s * _depth_ratio))
		var p := c["pos"] as Vector2
		multimesh.set_instance_transform(i, Transform3D(puff, Vector3(p.x, h, p.y)))
		var a := float(c["life"]) * _field.fade
		var storm := _overcast_under(p, s * 0.3) * dark if wet else 0.0  # its overcast greys and thickens it
		multimesh.set_instance_color(i, Color(storm, 0.0, 0.0, minf(a * (1.0 + storm * thick), 1.0)))


## The sky the clouds are spread over (owner 2026-09-30: 云…稀疏的分布在大
## 地图，不要集中): the WHOLE map, from the build's meta — over the view's
## ground alone, the sky filled only where the camera stood when play began
## and read, zoomed out, as one clump there. Without the meta (the editor's
## preview), the view's ground as before.
func _sky_rect() -> Rect2:
	var origin: Array = ctx.meta.get("pack_origin", [])
	var px: Array = ctx.meta.get("pack_px", [])
	if origin.size() < 2 or px.size() < 2:
		return _visible_ground()
	var m := float(ctx.meta.get("m_per_px", 50.0))
	return Rect2(Vector2(float(origin[0]), float(origin[1])), Vector2(float(px[0]), float(px[1])) * m)


## The overcast under a cloud: the most of its centre and four points `r`
## out, so a cloud whose middle hangs over a bay still wears the land's weather.
func _overcast_under(p: Vector2, r: float) -> float:
	var most := 0.0
	for o: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		most = maxf(most, weather.look_at(p + o).a)
	return most


func count() -> int:
	return multimesh.visible_instance_count if multimesh != null else 0


## Task 17's quality tiers: caps the instance count and turns the shadow
## twin off at a lower tier.
func set_quality(max_clouds: int, shadows: bool) -> void:
	if multimesh == null:
		return
	_params["max"] = max_clouds
	if _field != null and _field.clouds.size() > max_clouds:
		_field.clouds.resize(max_clouds)  # a lower tier drops the extra clouds now
	if multimesh.instance_count != max_clouds:
		multimesh.instance_count = max_clouds
	multimesh.visible_instance_count = mini(multimesh.visible_instance_count, max_clouds)
	get_node("Shadows").visible = shadows


## A tier's sky (graphics_quality clouds, cloud_shadows), never more clouds
## than the deck's own `max_clouds`.
func apply_quality(row: Dictionary) -> void:
	set_quality(mini(max_clouds, int(Map3DQuality.num(row, "clouds"))),
		Map3DQuality.num(row, "cloud_shadows") > 0.0)
