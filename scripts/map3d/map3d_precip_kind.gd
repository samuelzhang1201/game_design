@tool
class_name Map3DPrecipKind
extends GPUParticles3D
## One kind of falling weather, rain or snow (scenes/map3d/map3d_world.tscn's
## Precip/Rain and Precip/Snow; owner 2026-10-02: the look is edited in the
## editor). The node is its own look: `amount` the most drops falling at once
## (× the graphics tier's weather_particles), `lifetime` the seconds one takes
## from the top of the box to the ground, its process material the fall
## (precip_fall.tres) and its draw pass the drop (precip_drop_<kind>.tres:
## colour, opacity and the gain that lifts unlit colour back through the
## tonemap). What scales with the camera's distance is here, as shares of it,
## so a drop holds its size on screen; Map3DLayerPrecip applies them.

## 0 rain (a streak stood along its fall), 1 snow (a soft round flake).
@export_enum("Rain", "Snow") var kind := 0
## The wind's push, a share of the fall speed.
@export var slant := 0.15
## The drop's length and width, shares of the camera's distance (a flake is
## round: its width is its size).
@export var length_share := 0.018
@export var width_share := 0.0008
## How far a drop sways from side to side, a share of its fall speed.
@export var sway := 0.0
