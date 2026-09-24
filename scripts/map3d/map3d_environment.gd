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
	env.fog_aerial_perspective = repo.bal("map3d_fog_aerial")
	env.fog_sky_affect = repo.bal("map3d_fog_sky_affect")


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
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = repo.bal("map3d_sun_shadow_max_m")
	apply_sun_look(repo, sun)


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


## A tier's SubViewport: MSAA (0 / 2 / 4 / 8) and anisotropic filtering
## (1 / 2 / 4 / 8 / 16x, Viewport.anisotropic_filtering_level 0..4).
static func apply_viewport_quality(vp: SubViewport, row: Dictionary) -> void:
	var msaa := int(Map3DQuality.num(row, "msaa", 0.0))
	vp.msaa_3d = {2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(
		msaa, Viewport.MSAA_DISABLED)
	if "anisotropic_filtering_level" in vp:
		vp.set("anisotropic_filtering_level",
			{1: 0, 2: 1, 4: 2, 8: 3, 16: 4}.get(int(Map3DQuality.num(row, "aniso", 16.0)), 4))


## Everything a tier sets on the view's own nodes: the SubViewport, the sun
## and the terrain (Map3DView._apply_quality; the layers take theirs).
static func apply_view_quality(vp: SubViewport, sun: DirectionalLight3D, terrain: Node,
		row: Dictionary) -> void:
	apply_viewport_quality(vp, row)
	apply_quality(sun, row)
	apply_terrain_quality(terrain, row)
