@tool
class_name Map3DWeatherLook
extends Resource
## How the weather is DRAWN on the 3D map (spec 2026-09-29-weather-visuals;
## owner 2026-10-02: the look is edited in the editor) —
## scenes/map3d/weather_look.tres. The ground's weather stage is spliced into
## the shader Terrain3D generates, so it has no material of its own to save:
## its uniforms are these, handed over by Map3DLayerWeather (`weather_<name>`).
## Which weather a province has is the engine's (Weather, data/weather.csv),
## never this.

const PATH := "res://scenes/map3d/weather_look.tres"

@export_group("Field")
## Pack px per texel of the weather field — each texel its cell's province's
## weather.
@export var field_step_px := 8
## The field is halved this many times and grown back, so a province's weather
## ends softly; one (16 pack px): a median province is ~13 cells across, and
## two halvings washed a small one out.
@export var field_blur_halvings := 1
## Over the last this many days of a spell the ground turns to the NEXT
## spell's weather — a front arriving, not a switch.
@export var blend_days := 0.75
## How far (world metres) the field's edges wander by noise, and that noise's
## size, so it never ends on a ruled province outline.
@export var warp_m := 500.0
@export var warp_scale_m := 3000.0

@export_group("Cell")
## A province's weather is a CELL round its centre (owner 2026-09-29: 天气效果
## 不用铺满整个省份，再小一点): whole out to `cell_core` of its radius, gone by
## `cell_edge` (the whole province still slows a march; the HUD mark names it),
## its rim wobbled by `cell_wobble` of the radius so no cell is a circle.
@export var cell_core := 0.35
@export var cell_edge := 0.9
@export var cell_wobble := 0.25
## A core is never under this many pack px across its radius (the edge never
## under 1.8 × it): a 5-cell province's core was smaller than the blur.
@export var cell_min_px := 12.0

@export_group("Overcast")
## At full overcast the ground is this much darker, and moves this share
## toward its own grey (a flat light).
@export var dim := 0.25
@export var flat := 0.4
## A blizzard (overcast to snow 1:1, a snowfall 0.6:1) is veiled this far
## toward `haze_color` — what tells it from snow on a paused clock (owner
## 2026-09-29: 暴风雪和普通雪再拉开一点差别).
@export var haze := 0.65
@export var haze_color := Color("8C96A0")

@export_group("Rain")
## Wet ground is this much darker, this rough (lower: a sheen), and moves this
## share toward `wet_color` (a cool blue-grey at the ground's own value).
@export var wet_dark := 0.28
@export var wet_rough := 0.35
@export var wet_cool := 0.3
@export var wet_color := Color("737F8C")

@export_group("Mud")
## Mud moves the ground this share toward `mud_color`, and darkens it this
## much again, so it reads wet, not drought-ochre.
@export var mud_mix := 0.55
@export var mud_dark := 0.18
@export var mud_color := Color("5A4633")

@export_group("Snow")
## Fresh snow, below white: AgX at 1.4 blew white out.
@export var snow_color := Color("DCE1E5")
## Snow holds on ground whose upward normal is above about this (flat first),
## and steep ground takes `snow_steep` of what flat ground takes — bare rock
## read as dirt smears on the white.
@export var snow_slope := 0.8
@export var snow_steep := 0.7
## The size of the patches light snow lies in (world metres), its roughness,
## the share of the ground's own light and dark that shows through it (more
## read as paving slabs; 0 a blank page) and the half-width of its edge ramp
## (the first cut read as a slab).
@export var snow_patch_m := 420.0
@export var snow_rough := 0.7
@export var snow_detail := 0.15
@export var snow_soft := 0.35
## How much of its snow a wood shows from above (visual review 2026-10-05: a
## snowfall over a forest painted it out as a white blob): the crowns keep
## their dark, snow lies only between them.
@export var snow_wood := 0.25
## How far snow covers a roof (what faces up) — the red tiles show a little.
@export var roof_snow := 0.85


## The map's weather look (the saved .tres).
static func shared() -> Map3DWeatherLook:
	return load(PATH) as Map3DWeatherLook


## The ground stage's float uniforms, `weather_<name>`, and their values.
func ground_floats() -> Dictionary:
	var out := {}
	for key: String in ["warp_m", "warp_scale_m", "dim", "flat", "wet_dark", "wet_rough", "mud_mix",
			"snow_slope", "snow_patch_m", "snow_rough", "snow_detail", "snow_steep", "snow_soft",
			"snow_wood",
			"mud_dark", "wet_cool", "haze"]:
		out[key] = float(get(key))
	return out
