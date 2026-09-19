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
