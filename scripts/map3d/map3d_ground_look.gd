@tool
class_name Map3DGroundLook
extends Resource
## How the GROUND wears its themes and its country (owner 2026-10-02: the look
## is edited in the editor) — scenes/map3d/ground_look.tres. These stages are
## spliced into the shader Terrain3D generates (Map3DGroundTint), so they have
## no material of their own to save: Map3DLayerThemes hands these over, and
## the HEIGHTS legend draws the same ramp.

const PATH := "res://scenes/map3d/ground_look.tres"

@export_group("Themes")
## MANORS (owner 2026-09-19): how far the ground mixes toward its manor's
## ManorPalette colour, lit by the relief like the ground (owner 2026-09-28:
## a tincture, not a pastel highlighter).
@export var manor_tint := 0.6
## HEIGHTS (spec 2026-09-19-map3d-heights §4): how far the ground mixes toward
## the height ramp over 0..elevation_m_per_unit × (100 - elevation_sea_level).
@export var heat_tint := 0.85
## The ramp, lowland to summit (owner 2026-09-13): lowland green, rising
## ground, upland yellow, hill orange, mountain, the snow of the summit — raw
## sRGB, turned linear in the shader and drawn as is by the legend.
@export var heat_ramp: PackedColorArray = [Color("6DBE6A"), Color("C4D35E"), Color("F0C04E"),
	Color("E08A45"), Color("B55A3C"), Color("FFFFFF")]

@export_group("Fields")
## The furrows' spacing (metres) along each estate's strips (bake/fields.png),
## only on sown ground and faded out before ~3 screen px, and how far one
## darkens the field.
@export var furrow_m := 9.0
@export var furrow_depth := 0.14
## Each furlong's strips (owner 2026-10-01: 田地的布局要更合理真实): their width
## (metres), and how far a strip's own shade lifts or darkens it (0: none).
@export var strip_m := 22.0
@export var strip_shade := 0.25
## How much of the fields' own colour is taken back far out (0.9 until
## 2026-10-01 washed the crops out), from `field_fade_near_m` to full at
## `field_fade_far_m` camera distance.
@export var field_fade := 0.35
@export var field_fade_near_m := 5000.0
@export var field_fade_far_m := 22000.0

@export_group("Woods")
## How far the ground under the woods (bake/woods.png) goes toward the canopy
## colour where clumps are drawn — the dark floor between the crowns — and far
## out, where no clump is drawn and the canopy colour IS the wood, between
## `wood_far_near_m` and `wood_far_far_m`.
@export var wood_floor := 0.75
@export var wood_far := 0.75
@export var wood_far_near_m := 2500.0
@export var wood_far_far_m := 10000.0
## The canopy's light and dark mottle: its wavelength (metres) and strength.
@export var wood_mottle_m := 160.0
@export var wood_mottle := 0.45
## The canopy colours, sRGB — darkened on 2026-10-01 with the photo cards: the
## floor between the crowns reads dark, a far wood 20-30% darker than grass.
@export var wood_broadleaf := Color("34461F")
@export var wood_conifer := Color("2C3F26")


## The map's ground look (the saved .tres).
static func shared() -> Map3DGroundLook:
	return load(PATH) as Map3DGroundLook
