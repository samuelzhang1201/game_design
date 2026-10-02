class_name Map3DEnvironment
extends RefCounted
## What the graphics tier and the camera do to the 3D map's sky, sun and
## SubViewport. The LOOK is not here (owner 2026-10-02: edited in the
## editor): the sky, ambient, tonemap, effects and grade are
## scenes/map3d/world_environment.tres on the world's Environment
## (Map3DSky, which also follows the camera's distance), the sun's light and
## shadow look and its day are the world's Sun (Map3DSun).

const ENVIRONMENT := "res://scenes/map3d/world_environment.tres"
const WORLD_SCENE := "res://scenes/map3d/map3d_world.tscn"


## Everything that follows the camera's distance: the haze and SSAO radius
## (the sky's), the sun's shadow reach (the tier's shadow_max_m its ceiling)
## and the effects spent only up close (Map3DCloseEffects).
static func follow_camera(repo: DataRepository, sky: Map3DSky, sun: Map3DSun, ctx: Map3DContext) -> void:
	sky.follow(ctx.distance)
	sun.follow(ctx.distance, Map3DQuality.num(ctx.quality, "shadow_max_m", 0.0))
	Map3DCloseEffects.apply(repo, ctx.viewport, sky, ctx.quality, ctx.distance)


## A fresh Sun and Environment, the world scene's own (tools/map3d/shoot.gd,
## which renders a world without the view).
static func make_sun(_repo: DataRepository = null) -> Map3DSun:
	return _from_world("Sun") as Map3DSun


static func make_environment(_repo: DataRepository = null) -> Map3DSky:
	var sky := _from_world("Environment") as Map3DSky
	sky.environment = sky.environment.duplicate(true)
	return sky


static func _from_world(node_name: String) -> Node:
	var world := (load(WORLD_SCENE) as PackedScene).instantiate()
	var n := world.get_node(node_name)
	world.remove_child(n)
	n.owner = null
	if n is Map3DSun:
		(n as Map3DSun).fill = null
	world.free()
	return n


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
## 0 or 1): an effect runs only where the tier allows it AND the sky's author
## switched it on (Map3DSky.wants), so a tier can only take effects away.
static func apply_effects_quality(sky: Map3DSky, row: Dictionary) -> void:
	if sky == null or sky.environment == null:
		return
	var env := sky.environment
	env.ssao_enabled = sky.wants("ssao") and Map3DQuality.num(row, "ssao", 1.0) > 0.0
	env.ssil_enabled = sky.wants("ssil") and Map3DQuality.num(row, "ssil", 1.0) > 0.0
	env.glow_enabled = sky.wants("glow") and Map3DQuality.num(row, "glow", 1.0) > 0.0
	env.fog_enabled = Map3DQuality.num(row, "haze", 1.0) > 0.0
	# SSAO's quality (graphics_quality ssao_quality, RenderingServer's 0 very
	# low .. 4 ultra) and its fade (the sky's ssao_fade_*).
	RenderingServer.environment_set_ssao_quality(
		int(Map3DQuality.num(row, "ssao_quality", 2.0)) as RenderingServer.EnvironmentSSAOQuality,
		true, 0.5, 2, sky.ssao_fade_from_m, sky.ssao_fade_to_m)


## Everything a tier sets on the view's own nodes: the SubViewport, the sun,
## the terrain and the sky's effects (Map3DView._apply_quality; the layers
## take theirs).
static func apply_view_quality(vp: SubViewport, sun: DirectionalLight3D, terrain: Node,
		row: Dictionary, sky: Map3DSky = null) -> void:
	if sky != null:
		apply_effects_quality(sky, row)
	apply_viewport_quality(vp, row)
	apply_quality(sun, row)
	apply_terrain_quality(terrain, row)
