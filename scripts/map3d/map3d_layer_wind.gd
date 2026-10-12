class_name Map3DLayerWind
extends Node3D
## The wind (owner 2026-09-30: 草缓缓的随风摇摆…麦穗摇曳; node Viewport/Wind):
## one clock for the waves rolling over the crops and grass (Map3DGroundTint's
## wind stage) and the woods' sway (tree_sway.gdshader), and the ONE wind the
## clouds drift and the rain slants down (`direction`). It runs only while the
## game's clock does, like the clouds and the falling rain, at real time (a 4x
## clock does not make a gale). Presentation only: nothing here is read by the
## engine. Takes everything from Map3DContext — never the Game autoload.
##
## Its look is edited on this node (owner 2026-10-02): the ground's wind stage
## is spliced into the shader Terrain3D generates, so it has no material of
## its own to save — each export below is the uniform `wind_<name>`.

## The ground's wind uniforms, each an export of the same name.
const GROUND := ["speed_mps", "wave_m", "field_amp", "grass_amp", "tilt", "near_m", "mid_m", "far_m",
	"storm_gain", "far_scale", "far_amp", "sheen_amp", "sheen_sat", "sheen_lift", "sheen_facing",
	"trough_sat", "streak_amp", "streak_m", "streak_across", "sheen_warm", "band_rise", "band_fall",
	"band_warp", "gust_len", "gust_width", "gust_cover", "dash_len", "dash_cover"]

## Off: nothing waves or sways.
@export var wind_on := true
## The wind, degrees from east toward south — the waves', the clouds' and the
## rain's.
@export var deg := 12.0

@export_group("Woods")
## How far a crown's top leans down the wind (world metres at full height).
@export var tree_sway_m := 2.2
## How many times a second a tree sways.
@export var tree_hz := 0.22

@export_group("Waves near")
## How fast a wave runs down the wind (world metres a real second).
@export var speed_mps := 7.0
## The wavelength of the waves over the crops (world metres).
@export var wave_m := 55.0
## How far a wave lightens and darkens a sown field (bake/fields.png) — wheat shows its pale bent side.
@export var field_amp := 0.25
## The same over open, level grass away from the woods.
@export var grass_amp := 0.12
## How far the stalks a crest lays over lean the ground's shading normal down the wind, per unit of the crest (0 = colour waves only; the lean is clamped at 0.6): the laid-over grass turns toward or away from the sun as the crest passes (owner 2026-10-12, R8). ALU only; the same crop/grass masks, storm and distance fade as the waves.
@export_range(0.0, 1.0, 0.01) var tilt := 0.5
## The crop's own waves out to about this distance from the camera, giving way to the broad gusts by `mid_m`.
@export var near_m := 1500.0
## How much harder the waves run in a wet or overcast province (0 = the same everywhere).
@export var storm_gain := 1.2

@export_group("Gusts far")
## From here the broad gusts alone, full strength (owner 2026-09-30: 我并没有看到麦浪和树摇 — the waves were gone by 9 km, the opening view stands at ~24 km).
@export var mid_m := 5000.0
## ...fading out by here.
@export var far_m := 40000.0
## The broad gusts are this many times the crop waves' size and speed — at the opening zoom a pixel is ~20 m, and a true-speed wave would not move one.
@export var far_scale := 8.0
## The broad gusts' strength against the crop waves' (× field_amp and grass_amp far out); at 2 the far bands read as cloud shadow.
@export var far_amp := 0.9

@export_group("Crests")
## A crest's rise, the share of a wavelength over which the grass lays over at the wave's front (owner 2026-09-30: 看上去就像是雾气飘过一下，不像是草地的起伏 — round soft blobs read as mist).
@export var band_rise := 0.12
## How slowly the grass rises again behind a crest (higher is a thinner crest).
@export var band_fall := 3.5
## How far (in wavelengths) noise bends and breaks the crest lines, so they are never ruled.
@export var band_warp := 1.2
## A gust's length down the wind, in wavelengths — the crests come in runs where one passes.
@export var gust_len := 5.0
## A gust's width across the wind, in wavelengths.
@export var gust_width := 2.5
## The gust noise must pass this for crests to show (higher: fewer, shorter runs).
@export var gust_cover := 0.35
## Each crest broken into tapering pieces about this long across the wind (wavelengths), so the lines never run on like furrows (1.2 read as stitching).
@export var dash_len := 2.5
## The dash noise must pass this for a stretch of crest to show.
@export var dash_cover := 0.4

@export_group("Sheen")
## How far a crest turns the grass's pale side up (owner 2026-09-30: 草地随风飘扬的质感); 0 = plain light-and-shade waves.
@export var sheen_amp := 2.0
## The saturation the laid-over grass keeps (0 grey .. 1 its own; greyed crests read as mist).
@export var sheen_sat := 0.9
## How much lighter the laid-over grass is than the standing grass.
@export var sheen_lift := 0.35
## How much weaker the sheen is where the wind blows TOWARD the eye (0 = the same every way).
@export var sheen_facing := 0.5
## How far the laid-over grass turns warm (straw) — a lit blade, not a grey veil.
@export var sheen_warm := 0.08
## How much greener a wave's trough stands.
@export var trough_sat := 0.6

@export_group("Grain")
## Fine streaks combed down the wind over the grass and crops, near only; 0 = none.
@export var streak_amp := 0.08
## A streak's length down the wind (world metres).
@export var streak_m := 24.0
## A streak's width as a share of its length.
@export var streak_across := 0.15
@export_group("")

var ctx: Map3DContext
var _trees: Map3DLayerTrees
var _time := 0.0
var _shown := true
## The values last handed to the ground material (_look()).
var _pushed := PackedFloat32Array()


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	_trees = get_node_or_null("../Trees") as Map3DLayerTrees


## Seconds of wind so far (a test seam, and what the shaders are handed).
func time() -> float:
	return _time


## The ground's uniforms as they stand: GROUND's exports, then `deg`.
func _look() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for key: String in GROUND:
		out.append(float(get(key)))
	out.append(deg)
	return out


## The way the wind blows over the ground, a unit vector in world XZ.
func direction() -> Vector2:
	return Vector2.from_angle(deg_to_rad(deg))


func _process(delta: float) -> void:
	if ctx == null or not wind_on:
		return
	if ctx.clock_speed() > 0:
		_time += delta
	var dir := direction()
	var mat: Resource = ctx.terrain.get("material") if ctx.terrain != null else null
	if mat != null:
		# Terrain3D drops unknown uniforms after a load: put them back when
		# wind_on reads unset, as the weather does
		# ...and off past map3d_lod_wind_m (owner 2026-10-10: LOD)
		_shown = Map3DGeometry.lod_shown(_shown, ctx.distance, ctx.repo.bal("map3d_lod_wind_m"),
			ctx.repo.bal("map3d_lod_margin_m"))
		var want := 1.0 if _shown else 0.0
		var on: Variant = mat.call("get_shader_param", "wind_on")
		# ...and again whenever an export changes (the inspector, a shot's
		# --set): pushed only on a reset, a later value never reached the
		# ground (the tilt bracket's frames could not be told apart)
		var look := _look()
		if not (on is float and is_equal_approx(on, want)) or look != _pushed:
			mat.call("set_shader_param", "wind_on", want)
			mat.call("set_shader_param", "wind_dir", dir)
			for i: int in GROUND.size():
				mat.call("set_shader_param", "wind_" + GROUND[i], look[i])
			_pushed = look
		mat.call("set_shader_param", "wind_time", _time)
	if _trees != null and _trees.material != null:
		var tm := _trees.material
		tm.set_shader_parameter("wind_time", _time)
		tm.set_shader_parameter("wind_dir", dir)
		tm.set_shader_parameter("sway_m", tree_sway_m)
		tm.set_shader_parameter("sway_hz", tree_hz)
