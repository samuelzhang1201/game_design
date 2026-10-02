@tool
class_name Map3DSun
extends DirectionalLight3D
## The 3D map's sun (scenes/map3d/map3d_world.tscn's Sun; owner 2026-10-02:
## the look is edited in the editor, not in balance.csv). Its shadow look —
## blur, biases, splits — is the light's own, set on the node; what MOVES is
## here: the sun turns once round each game day (owner 2026-09-27: from the
## west, south at its highest, east, low through the north and back, so it
## never jumps at the day's turn), the north half is DUSK (owner 2026-09-28:
## dimmer, warmer, fainter shadows, and the shadowless `fill` light opposite
## it rising to light the slopes turned toward the player), and its shadow
## reach follows the camera's distance (owner 2026-09-25). Drag
## `preview_day_share` in the editor to stand the sun at that hour.

@export_group("By day")
## The light's strength, its glint on water and its shadows' opacity at
## midday; dusk scales each down.
@export var day_energy := 1.4
@export var day_specular := 0.5
@export var day_shadow_opacity := 0.45
## Off: the sun stands where the node is turned, all day.
@export var day_sweep := true
## Where the light comes from at the day's start (-90: the west).
@export var yaw0_deg := -90.0
## The sun's pitch at its highest (due south) and at its lowest (due north).
@export var high_deg := -60.0
@export var low_deg := -52.0

@export_group("Dusk")
@export var dusk := true
## At full dusk: × the day energy, × the day shadow, × the day glint.
@export var dusk_energy := 0.7
@export var dusk_shadow := 0.35
@export var dusk_specular := 0.3
## The sun's colour at full dusk, blended in from white.
@export var dusk_color := Color("ffead5")
## The fill light (always opposite the sun): its energy by day and at full
## dusk, and its pitch.
@export var fill: DirectionalLight3D
@export var fill_day := 0.25
@export var fill_dusk := 0.6
@export var fill_pitch_deg := -35.0

@export_group("Shadow reach")
## The shadows reach this many camera distances, never under `shadow_min_m`
## nor past `shadow_max_m` (or the graphics tier's own reach).
@export var shadow_per_view := 3.0
@export var shadow_min_m := 2000.0
@export var shadow_max_m := 60000.0

@export_group("Editor")
## Stand the sun at this share of the day in the editor (below 0: leave it).
@export_range(-1.0, 1.0, 0.01) var preview_day_share := -1.0:
	set(v):
		preview_day_share = v
		if Engine.is_editor_hint() and v >= 0.0 and is_inside_tree():
			sweep(v)


func _ready() -> void:
	light_energy = day_energy
	light_specular = day_specular
	shadow_opacity = day_shadow_opacity


## Vector2(pitch, yaw) in degrees at `day_share` 0..1 of the day. A yaw of 0
## lights from the south (+Z); the light's own -Z is turned by the yaw.
func angles(day_share: float) -> Vector2:
	if not day_sweep:
		return Vector2(rotation_degrees.x, rotation_degrees.y)
	var f := fposmod(day_share, 1.0)
	return Vector2(low_deg + (high_deg - low_deg) * (0.5 + 0.5 * sin(TAU * f)), yaw0_deg + 360.0 * f)


## How deep in dusk the day stands, 0..1: nothing through the south half,
## rising as smoothstep(0, 1, -sin(2 pi f)) to 1 with the sun in the north.
func dusk_of(day_share: float) -> float:
	if not day_sweep or not dusk:
		return 0.0
	return smoothstep(0.0, 1.0, maxf(0.0, -sin(TAU * fposmod(day_share, 1.0))))


## Turn the sun to where it stands at `day_share`, and light the dusk.
func sweep(day_share: float) -> void:
	var a := angles(day_share)
	rotation_degrees = Vector3(a.x, a.y, 0.0)
	var d := dusk_of(day_share)
	light_energy = day_energy * lerpf(1.0, dusk_energy, d)
	shadow_opacity = day_shadow_opacity * lerpf(1.0, dusk_shadow, d)
	light_specular = day_specular * lerpf(1.0, dusk_specular, d)
	light_color = Color.WHITE.lerp(dusk_color, d)
	if fill != null:
		fill.light_energy = lerpf(fill_day, fill_dusk, d)
		fill.visible = fill.light_energy > 0.0
		fill.rotation_degrees = Vector3(fill_pitch_deg, a.y + 180.0, 0.0)


## The shadows' reach for a camera `distance_m` away, under the graphics
## tier's own reach (`tier_max_m`, 0 for none).
func follow(distance_m: float, tier_max_m: float) -> void:
	if shadow_per_view <= 0.0 or distance_m <= 0.0:
		return
	var top := tier_max_m if tier_max_m > 0.0 else shadow_max_m
	directional_shadow_max_distance = clampf(shadow_per_view * distance_m, minf(shadow_min_m, top), top)
