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

## The deck's and the twin's looks — two materials over two shader files. Their
## `shape` is the editor's preview; build() sets the seeded one.
const CLOUD_MAT := preload("res://scenes/map3d/materials/cloud_deck.tres")
const CLOUD_SHADOW_MAT := preload("res://scenes/map3d/materials/cloud_shadow.tres")

var ctx: Map3DContext
var _field: Map3DCloudField
var _params: Dictionary
var _depth_ratio := 0.6
var _ground_cache := Rect2()
var _ground_cache_target := Vector2.ZERO
var _ground_cache_distance := -1.0
var _ground_cache_yaw := 0.0
var _ground_cache_size := Vector2.ZERO
var _ground_cache_valid := false


func build(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	_field = Map3DCloudField.new(int(ctx.repo.bal("map3d_cloud_seed")))
	_params = {"max": int(ctx.repo.bal("map3d_cloud_max")),
		"size_min": ctx.repo.bal("map3d_cloud_size_min_m"), "size_max": ctx.repo.bal("map3d_cloud_size_max_m"),
		"speed_m_s": ctx.repo.bal("map3d_cloud_speed_m_s"), "wind_deg": ctx.repo.bal("map3d_cloud_wind_deg"),
		"fade_s": ctx.repo.bal("map3d_cloud_fade_s"), "interval_s": ctx.repo.bal("map3d_cloud_interval_s"),
		"min_gap_m": ctx.repo.bal("map3d_cloud_min_gap_m")}
	_depth_ratio = ctx.repo.bal("map3d_cloud_depth_ratio")
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = int(_params["max"])
	mm.visible_instance_count = 0
	self.multimesh = mm
	var shape := CloudLayer.cloud_texture(int(ctx.repo.bal("map3d_cloud_seed")))
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
	mat.set_shader_parameter("opacity", ctx.repo.bal("map3d_cloud_alpha"))
	mat.set_shader_parameter("near_fade_m", ctx.repo.bal("map3d_cloud_near_fade_m"))
	mat.set_shader_parameter("near_fade_start_ratio", ctx.repo.bal("map3d_cloud_near_fade_start_ratio"))
	mat.set_shader_parameter("emission_share", ctx.repo.bal("map3d_cloud_emission_share"))
	return mat


## The shadow-only twin's OWN shader (cloud_shadow.gdshader — see its note
## and cloud_deck.gdshader's: the two must stay separate files under this
## renderer, not one shader gated by a `shadow_pass` uniform).
func _cloud_shadow_material(shape: Texture2D) -> ShaderMaterial:
	var mat := (CLOUD_SHADOW_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("shadow_cut", ctx.repo.bal("map3d_cloud_shadow_cut"))
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
	_field.step(delta, ctx.clock_speed() > 0, ctx.clock_speed(), _visible_ground(), _params)
	var h := ctx.repo.bal("map3d_cloud_height_m")
	var n := _field.clouds.size()
	multimesh.visible_instance_count = n
	for i in n:
		var c: Dictionary = _field.clouds[i]
		var s := float(c["size"])
		var basis := Basis(Vector3.UP, float(c["rot"])).scaled(Vector3(s, 1.0, s * _depth_ratio))
		var p := c["pos"] as Vector2
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p.x, h, p.y)))
		multimesh.set_instance_color(i, Color(1, 1, 1, float(c["life"]) * _field.fade))


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
## than balance map3d_cloud_max.
func apply_quality(row: Dictionary) -> void:
	set_quality(mini(int(ctx.repo.bal("map3d_cloud_max")), int(Map3DQuality.num(row, "clouds"))),
		Map3DQuality.num(row, "cloud_shadows") > 0.0)
