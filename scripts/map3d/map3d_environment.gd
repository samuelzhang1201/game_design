class_name Map3DEnvironment
extends RefCounted
## The 3D map's sky and sun AS DATA (Task 14, 2026-09-20: the view scene's
## Viewport/Environment and Viewport/Sun, bound at load), and the Sun's shadow
## LOOK, applied at load (spec 2026-09-20 §1; owner fix
## round 1, 2026-09-18): a code-review + independent-critic pass on Task 9
## found the shipped cloud shadows read as pitch-black holes with knife
## edges, burying the settlement rings — `shadow_enabled` alone leaves
## Godot's default full black, full crisp shadow. `shadow_opacity` blends the
## shadowed pixel with its lit colour instead of replacing it (so a shadow
## reads as a COOL WASH of blocked light, never a hole) and `shadow_blur`
## softens every cast shadow's edge — both apply to the terrain's own
## self-shadowing too (accepted: the mountains read softer with it, see the
## fix report). The sea never receives shadows (`disable_receive_shadows` on
## its own material, set at build time) — untouched here.

static func apply_sun_look(repo: DataRepository, sun: DirectionalLight3D) -> void:
	sun.shadow_opacity = repo.bal("map3d_sun_shadow_opacity")
	sun.shadow_blur = repo.bal("map3d_sun_shadow_blur")
	sun.shadow_bias = repo.bal("map3d_sun_shadow_bias")
	sun.shadow_normal_bias = repo.bal("map3d_sun_shadow_normal_bias")


## The sky, ambient and fog the build wrote until 2026-09-20 (Task 14): the
## STRUCTURE (a procedural sky, ambient from it, the Filmic tonemap, fog on)
## lives in this .tres, every tuned number and colour in the CSVs.
const ENVIRONMENT := "res://scenes/map3d/world_environment.tres"


## `env`'s sky colours (terrain_palette map3d_sky_top / map3d_sky / map3d_sky_ground),
## ambient and fog (balance map3d_ambient_* / map3d_fog_density).
static func apply_environment(repo: DataRepository, env: Environment) -> void:
	var horizon := MapTerrain.palette_color(repo, "map3d_sky", MapTerrain.FALLBACK)
	var psm := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	if psm != null:
		psm.sky_top_color = MapTerrain.palette_color(repo, "map3d_sky_top", MapTerrain.FALLBACK)
		psm.sky_horizon_color = horizon
		psm.ground_horizon_color = horizon
		psm.ground_bottom_color = MapTerrain.palette_color(repo, "map3d_sky_ground", MapTerrain.FALLBACK)
		psm.sun_angle_max = repo.bal("map3d_sky_sun_angle_max")
	env.ambient_light_energy = repo.bal("map3d_ambient_energy")
	env.ambient_light_sky_contribution = repo.bal("map3d_ambient_sky_share")
	env.fog_light_color = horizon
	env.fog_density = repo.bal("map3d_fog_density")
	apply_post(repo, env)


## Forward+'s light and grade (owner 2026-09-24, the look route's Phase 0,
## spec 2026-09-24-map3d-humankind-look-gap §2.1): the tonemap, occlusion,
## indirect light, glow, colour adjustment and aerial haze, every number
## balance map3d_env_*. Under a renderer that lacks one, Godot ignores it.
static func apply_post(repo: DataRepository, env: Environment) -> void:
	env.tonemap_mode = int(repo.bal("map3d_env_tonemap")) as Environment.ToneMapper
	env.tonemap_exposure = repo.bal("map3d_env_exposure")
	env.tonemap_white = repo.bal("map3d_env_white")
	env.ssao_enabled = repo.bal("map3d_env_ssao") > 0.0
	env.ssao_radius = repo.bal("map3d_env_ssao_radius")
	env.ssao_intensity = repo.bal("map3d_env_ssao_intensity")
	env.ssao_power = repo.bal("map3d_env_ssao_power")
	env.ssao_detail = repo.bal("map3d_env_ssao_detail")
	env.ssil_enabled = repo.bal("map3d_env_ssil") > 0.0
	env.ssil_radius = repo.bal("map3d_env_ssil_radius")
	env.ssil_intensity = repo.bal("map3d_env_ssil_intensity")
	env.glow_enabled = repo.bal("map3d_env_glow") > 0.0
	env.glow_intensity = repo.bal("map3d_env_glow_intensity")
	env.glow_bloom = repo.bal("map3d_env_glow_bloom")
	env.adjustment_enabled = true
	env.adjustment_brightness = repo.bal("map3d_env_brightness")
	env.adjustment_contrast = repo.bal("map3d_env_contrast")
	env.adjustment_saturation = repo.bal("map3d_env_saturation")
	env.adjustment_color_correction = warm_curve(repo.bal("map3d_env_curve_r_gamma"),
		repo.bal("map3d_env_curve_g_gamma"), repo.bal("map3d_env_curve_b_gamma"))
	env.fog_aerial_perspective = repo.bal("map3d_fog_aerial")
	env.fog_sky_affect = repo.bal("map3d_fog_sky_affect")


## A per-channel curve for the grade (2026-09-24, look route Phase 2): each
## channel x -> x^gamma (below 1 lifts it), as the Environment's colour
## correction — a warm white balance the ground's own colour map cannot
## give (it only darkens its textures). All gammas 1 is no curve at all.
static func warm_curve(r_gamma: float, g_gamma: float, b_gamma: float) -> Texture2D:
	if is_equal_approx(r_gamma, 1.0) and is_equal_approx(g_gamma, 1.0) and is_equal_approx(b_gamma, 1.0):
		return null
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for i in 17:
		var x := float(i) / 16.0
		g.add_point(x, Color(pow(x, r_gamma), pow(x, g_gamma), pow(x, b_gamma)))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


## Everything that follows the camera's distance: the haze, the SSAO radius
## and the sun's shadow reach (the tier's shadow_max_m its ceiling).
static func follow_camera(repo: DataRepository, env: Environment, sun: DirectionalLight3D,
		ctx: Map3DContext) -> void:
	fog_for_distance(repo, env, ctx.distance)
	shadow_for_distance(repo, sun, ctx.distance, Map3DQuality.num(ctx.quality, "shadow_max_m", 0.0))
	Map3DCloseEffects.apply(repo, ctx.viewport, env, ctx.quality, ctx.distance)


## The sun's shadow reach follows the zoom too (owner 2026-09-25: house
## shadows up close without costing fps): map3d_sun_shadow_per_view camera
## distances, never under map3d_sun_shadow_min_m and never past the tier's
## own reach (`tier_max_m`). One shadow atlas spread over 60 km put a 14 m
## house on a few texels; spread over a few km it draws the house's shadow,
## and fewer casters fall inside it, so it costs no more.
static func shadow_for_distance(repo: DataRepository, sun: DirectionalLight3D, distance_m: float,
		tier_max_m: float) -> void:
	var k := repo.bal("map3d_sun_shadow_per_view")
	if sun == null or k <= 0.0 or distance_m <= 0.0:
		return
	var top := tier_max_m if tier_max_m > 0.0 else repo.bal("map3d_sun_shadow_max_m")
	sun.directional_shadow_max_distance = clampf(k * distance_m,
		minf(repo.bal("map3d_sun_shadow_min_m"), top), top)


## The haze and the occlusion follow the zoom (Phase 0). With
## map3d_fog_depth_begin > 0 the fog is DEPTH fog, clear to that many camera
## distances and thickest at map3d_fog_depth_end of them (curve
## map3d_fog_depth_curve), so the target stands clear and only the land
## toward the horizon fades, the same share at every zoom; SSAO's radius is
## map3d_env_ssao_radius_per_view of the distance (0 keeps the fixed radius),
## since a valley at 25 km is kilometres wide.
static func fog_for_distance(repo: DataRepository, env: Environment, distance_m: float) -> void:
	if distance_m <= 0.0:
		return
	var begin := repo.bal("map3d_fog_depth_begin")
	if begin > 0.0:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = begin * distance_m
		env.fog_depth_end = repo.bal("map3d_fog_depth_end") * distance_m
		env.fog_depth_curve = repo.bal("map3d_fog_depth_curve")
		env.fog_density = repo.bal("map3d_fog_depth_density")
	var r := repo.bal("map3d_env_ssao_radius_per_view")
	if r > 0.0:
		env.ssao_radius = r * distance_m


## `sun`'s angle, energy and shadow reach (balance map3d_sun_*), then its look.
static func apply_sun(repo: DataRepository, sun: DirectionalLight3D) -> void:
	sun.rotation_degrees = Vector3(repo.bal("map3d_sun_pitch_deg"), repo.bal("map3d_sun_yaw_deg"), 0.0)
	sun.light_energy = repo.bal("map3d_sun_energy")
	sun.light_specular = repo.bal("map3d_sun_specular")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = repo.bal("map3d_sun_shadow_max_m")
	apply_sun_look(repo, sun)


## The sun over a game day (owner 2026-09-27: 随着时间的流逝，光照光源从西向东缓慢
## 变化; one day a round): Vector2(pitch, yaw) in degrees at `day_share` 0..1 of
## the day. The light comes from map3d_sun_day_yaw0_deg (-90: the WEST) and
## turns once round a day — west, south at its highest (map3d_sun_day_high_deg),
## east, then low through the north (map3d_sun_day_low_deg) back to the west —
## so it never jumps at the day's turn. A yaw of 0 lights from the south
## (+Z); the light's own -Z is turned by the yaw. map3d_sun_day_sweep 0 holds
## the fixed map3d_sun_pitch_deg / _yaw_deg.
static func sun_angles(repo: DataRepository, day_share: float) -> Vector2:
	if repo.bal("map3d_sun_day_sweep") <= 0.0:
		return Vector2(repo.bal("map3d_sun_pitch_deg"), repo.bal("map3d_sun_yaw_deg"))
	var f := fposmod(day_share, 1.0)
	var low := repo.bal("map3d_sun_day_low_deg")
	var high := repo.bal("map3d_sun_day_high_deg")
	return Vector2(low + (high - low) * (0.5 + 0.5 * sin(TAU * f)),
		repo.bal("map3d_sun_day_yaw0_deg") + 360.0 * f)


## How deep in DUSK the day stands at `day_share`, 0..1 (owner 2026-09-28:
## 北边半圈当作黄昏): nothing through the south half, rising as
## smoothstep(0, 1, -sin(2 pi f)) to 1 when the sun stands in the north. There
## the light comes from behind the map, facing the camera, and every slope
## turned toward the player is in its own shade — no shadow value fixes
## that, so the north pass is an evening instead. 0 with map3d_sun_dusk or
## the sweep off.
static func dusk_of(repo: DataRepository, day_share: float) -> float:
	if repo.bal("map3d_sun_day_sweep") <= 0.0 or repo.bal("map3d_sun_dusk") <= 0.0:
		return 0.0
	return smoothstep(0.0, 1.0, maxf(0.0, -sin(TAU * fposmod(day_share, 1.0))))


## Turn `sun` to where it stands at `day_share` of the day (Map3DView, each
## frame), and light the dusk, each by dusk_of: the sun dims
## (map3d_sun_dusk_energy) and warms (terrain_palette map3d_sun_dusk), its
## shadows fade (map3d_sun_dusk_shadow) and its glint on the water with them
## (map3d_sun_dusk_specular: at dusk it shines toward the camera), and `fill`
## — the scene's FillLight, a shadowless light always opposite the sun at
## map3d_sun_dusk_fill_pitch_deg — rises from map3d_sun_fill_day to
## map3d_sun_dusk_fill. The fill,
## not the ambient, is what lights the slopes turned toward the player: the
## sky's ambient is too faint to (measured 2026-09-28: sun off and ambient x4,
## the land drew near black). It has no specular, so it lays no second glint
## on the sea, and no sky disc.
static func sweep_sun(repo: DataRepository, sun: DirectionalLight3D, day_share: float,
		fill: DirectionalLight3D = null) -> void:
	var a := sun_angles(repo, day_share)
	sun.rotation_degrees = Vector3(a.x, a.y, 0.0)
	var d := dusk_of(repo, day_share)
	sun.light_energy = repo.bal("map3d_sun_energy") * lerpf(1.0, repo.bal("map3d_sun_dusk_energy"), d)
	sun.shadow_opacity = repo.bal("map3d_sun_shadow_opacity") * lerpf(1.0, repo.bal("map3d_sun_dusk_shadow"), d)
	sun.light_specular = repo.bal("map3d_sun_specular") * lerpf(1.0, repo.bal("map3d_sun_dusk_specular"), d)
	sun.light_color = Color.WHITE.lerp(MapTerrain.palette_color(repo, "map3d_sun_dusk", Color.WHITE), d)
	if fill != null:
		fill.light_energy = lerpf(repo.bal("map3d_sun_fill_day"), repo.bal("map3d_sun_dusk_fill"), d)
		fill.visible = fill.light_energy > 0.0
		fill.rotation_degrees = Vector3(repo.bal("map3d_sun_dusk_fill_pitch_deg"), a.y + 180.0, 0.0)


## A fresh Sun (tools/map3d/shoot.gd, which renders a world without the view).
static func make_sun(repo: DataRepository) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	apply_sun(repo, sun)
	return sun


## A fresh WorldEnvironment over its own copy of ENVIRONMENT (shoot.gd).
static func make_environment(repo: DataRepository) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = (load(ENVIRONMENT) as Environment).duplicate(true)
	apply_environment(repo, we.environment)
	return we


## A graphics tier's sun (graphics_quality.csv): shadows on or off, 4 / 2
## splits or one orthogonal map, their reach and the directional atlas —
## a 0 in shadow_max_m or shadow_atlas_px keeps what is set.
static func apply_quality(sun: DirectionalLight3D, row: Dictionary) -> void:
	sun.shadow_enabled = Map3DQuality.num(row, "sun_shadows", 1.0) > 0.0
	var splits := int(Map3DQuality.num(row, "shadow_splits", 4.0))
	sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if splits == 4
		else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if splits == 2
		else DirectionalLight3D.SHADOW_ORTHOGONAL))
	if Map3DQuality.num(row, "shadow_max_m", 0.0) > 0.0:
		sun.directional_shadow_max_distance = Map3DQuality.num(row, "shadow_max_m", 0.0)
	if Map3DQuality.num(row, "shadow_atlas_px", 0.0) > 0.0:
		RenderingServer.directional_shadow_atlas_set_size(
			int(Map3DQuality.num(row, "shadow_atlas_px", 0.0)), true)


## A tier's Terrain3D mesh (Terrain3D 1.0.2's mesh_size / mesh_lods); nothing
## without a terrain (fixtures) or on a build that lacks the property.
static func apply_terrain_quality(terrain: Node, row: Dictionary) -> void:
	if terrain == null:
		return
	for pair: Array in [["mesh_size", "terrain_mesh_size"], ["mesh_lods", "terrain_mesh_lods"]]:
		var v := int(Map3DQuality.num(row, String(pair[1]), 0.0))
		# an unchanged value is left alone: setting it rebuilds the clipmap
		if v > 0 and String(pair[0]) in terrain and int(terrain.get(String(pair[0]))) != v:
			terrain.set(String(pair[0]), v)


## A tier's SubViewport: MSAA (0 / 2 / 4 / 8), screen_aa (0 / 1 FXAA / 2 SMAA;
## by zoom, Map3DCloseEffects) and anisotropic filtering (1..16x, level 0..4).
static func apply_viewport_quality(vp: SubViewport, row: Dictionary) -> void:
	var msaa := int(Map3DQuality.num(row, "msaa", 0.0))
	vp.msaa_3d = {2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(
		msaa, Viewport.MSAA_DISABLED)
	vp.screen_space_aa = {1: Viewport.SCREEN_SPACE_AA_FXAA, 2: Viewport.SCREEN_SPACE_AA_SMAA}.get(
		int(Map3DQuality.num(row, "screen_aa", 0.0)), Viewport.SCREEN_SPACE_AA_DISABLED)
	if "anisotropic_filtering_level" in vp:
		vp.set("anisotropic_filtering_level",
			{1: 0, 2: 1, 4: 2, 8: 3, 16: 4}.get(int(Map3DQuality.num(row, "aniso", 16.0)), 4))


## A tier's screen effects (graphics_quality ssao / ssil / glow / haze, each
## 0 or 1): an effect runs only where the tier allows it AND its balance
## switch is on, so a tier can only take effects away.
static func apply_effects_quality(repo: DataRepository, env: Environment, row: Dictionary) -> void:
	if env == null:
		return
	env.ssao_enabled = repo.bal("map3d_env_ssao") > 0.0 and Map3DQuality.num(row, "ssao", 1.0) > 0.0
	env.ssil_enabled = repo.bal("map3d_env_ssil") > 0.0 and Map3DQuality.num(row, "ssil", 1.0) > 0.0
	env.glow_enabled = repo.bal("map3d_env_glow") > 0.0 and Map3DQuality.num(row, "glow", 1.0) > 0.0
	env.fog_enabled = Map3DQuality.num(row, "haze", 1.0) > 0.0
	# SSAO's quality (graphics_quality ssao_quality, RenderingServer's 0 very
	# low .. 4 ultra) and its fade: Godot's default fades SSAO out from 50 to
	# 300 m, which on a map seen from kilometres away kept its cost and threw
	# its look away (found 2026-09-24) — map3d_env_ssao_fade_from_m / _to_m.
	RenderingServer.environment_set_ssao_quality(
		int(Map3DQuality.num(row, "ssao_quality", 2.0)) as RenderingServer.EnvironmentSSAOQuality,
		true, 0.5, 2, repo.bal("map3d_env_ssao_fade_from_m"), repo.bal("map3d_env_ssao_fade_to_m"))


## Everything a tier sets on the view's own nodes: the SubViewport, the sun,
## the terrain and the environment's effects (Map3DView._apply_quality; the
## layers take theirs).
static func apply_view_quality(vp: SubViewport, sun: DirectionalLight3D, terrain: Node,
		row: Dictionary, repo: DataRepository = null, env: Environment = null) -> void:
	if repo != null:
		apply_effects_quality(repo, env, row)
	apply_viewport_quality(vp, row)
	apply_quality(sun, row)
	apply_terrain_quality(terrain, row)
