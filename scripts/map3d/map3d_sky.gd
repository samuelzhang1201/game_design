@tool
class_name Map3DSky
extends WorldEnvironment
## The 3D map's sky, light and grade (scenes/map3d/map3d_world.tscn's
## Environment; owner 2026-10-02: the look is edited in the editor). The
## look itself — the procedural sky's colours, the ambient light, the
## tonemap, SSAO / SSIL / glow and their strengths, the colour grade and its
## warm curve, the fog's colour and aerial haze — is the Environment
## resource, scenes/map3d/world_environment.tres; its ssao / ssil / glow
## switches are the look's own, and a graphics tier can only take them away.
## What follows the camera is here: the haze is DEPTH fog clear to
## `fog_depth_begin` camera distances and thickest at `fog_depth_end` of
## them, so the target stands clear and only the land toward the horizon
## fades, the same share at every zoom; SSAO's radius is
## `ssao_radius_per_view` of the distance (a valley at 25 km is kilometres
## wide).

@export_group("Haze by distance")
## 0 keeps the resource's own fog.
@export var fog_depth_begin := 1.1
@export var fog_depth_end := 4.0
@export var fog_depth_curve := 1.0
@export var fog_depth_density := 0.5
## Up close there is little air between the eye and the far edge of the view:
## the haze's density is `fog_near_share` of itself at the nearest zoom,
## rising to all of it by a camera `fog_near_full_m` away (0: the same at
## every zoom).
@export var fog_near_share := 1.0
@export var fog_near_full_m := 0.0

@export_group("Far blur")
## The far land softens like a lens's depth of field (the node's
## camera_attributes, a CameraAttributesPractical with far blur on): sharp to
## `dof_far_begin` camera distances, fully soft `dof_far_ramp` more beyond
## (0 leaves the resource's own distances).
@export var dof_far_begin := 0.0
@export var dof_far_ramp := 2.0

@export_group("Occlusion")
## 0 keeps the resource's fixed SSAO radius.
@export var ssao_radius_per_view := 0.03
## Godot fades SSAO out from 50 to 300 m by default, which on a map seen
## from kilometres away kept its cost and threw its look away (2026-09-24).
@export var ssao_fade_from_m := 400000.0
@export var ssao_fade_to_m := 600000.0

## The resource's own effect switches, as authored (taken before a view makes
## its copy, so a tier taking one away never loses the author's choice).
var authored := {}


func _ready() -> void:
	remember()


## Note the authored switches (again after the environment is replaced).
func remember() -> void:
	if environment != null:
		authored = {"ssao": environment.ssao_enabled, "ssil": environment.ssil_enabled,
			"glow": environment.glow_enabled}


## Whether the author switched `effect` on (ssao, ssil, glow).
func wants(effect: String) -> bool:
	return bool(authored.get(effect, true))


## The haze and SSAO radius for a camera `distance_m` away.
func follow(distance_m: float) -> void:
	if environment == null or distance_m <= 0.0:
		return
	if fog_depth_begin > 0.0:
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_depth_begin = fog_depth_begin * distance_m
		environment.fog_depth_end = fog_depth_end * distance_m
		environment.fog_depth_curve = fog_depth_curve
		environment.fog_density = fog_depth_density * near_share(distance_m)
	var cam := camera_attributes as CameraAttributesPractical
	if cam != null and dof_far_begin > 0.0:
		cam.dof_blur_far_distance = dof_far_begin * distance_m
		cam.dof_blur_far_transition = dof_far_ramp * distance_m
	if ssao_radius_per_view > 0.0:
		environment.ssao_radius = ssao_radius_per_view * distance_m


## The share of the haze's density kept at a camera `distance_m` away.
func near_share(distance_m: float) -> float:
	if fog_near_full_m <= 0.0:
		return 1.0
	return lerpf(fog_near_share, 1.0, smoothstep(0.0, fog_near_full_m, distance_m))
