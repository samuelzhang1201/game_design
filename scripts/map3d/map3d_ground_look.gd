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
## How thin a furrow's dark line is (1: half the spacing, a soft wave; 4: a
## fine line on light ground).
@export var furrow_sharp := 1.0
## Each furlong's strips (owner 2026-10-01: 田地的布局要更合理真实): their width
## (metres), and how far a strip's own shade lifts or darkens it (0: none).
@export var strip_m := 22.0
@export var strip_shade := 0.25
## Farther out, where those strips are under a few px: broader bands (metres)
## of the furlong's strips and their shade, so a field keeps its grain at the
## opening zoom (0: none).
@export var strip_far_m := 80.0
@export var strip_far_shade := 0.0
## How much of the fields' own colour is taken back far out (0.9 until
## 2026-10-01 washed the crops out), from `field_fade_near_m` to full at
## `field_fade_far_m` camera distance.
@export var field_fade := 0.35
@export var field_fade_near_m := 5000.0
@export var field_fade_far_m := 22000.0
## Far out (with field_fade) the sown ground's value is pulled by this (1: none):
## the crop layer's pale straw drew a camouflage patchwork at 24 km.
@export var field_far_value := 1.0

## The grounds' edges per pixel (Map3DGroundEdge): how far (metres) a field's,
## a wood's or a beach's edge wanders off Terrain3D's 20 m vertex steps, the
## wander's wavelength, its fine octave's share, and the camera distance it is
## gone by (0: the stairs).
@export var edge_warp_m := 0.0
@export var edge_warp_wave_m := 60.0
@export var edge_warp_fine := 0.35
@export var edge_warp_far_m := 9000.0
## A finer fray (metres, wavelength) fading in from `edge_fray_from_m` to
## `edge_fray_full_m` of camera distance: there a 20 m step is a few px and the
## broad wander only bends the stair (0: none).
@export var edge_fray_m := 0.0
@export var edge_fray_wave_m := 36.0
@export var edge_fray_from_m := 2500.0
@export var edge_fray_full_m := 6000.0

## The grass balks between furlongs (Map3DGroundBalk): a line `balk_m` wide
## inside each field's edge, mixed toward `balk_color` by `balk` (0 off), gone
## by a camera `balk_far_m` away.
@export var balk := 0.0
@export var balk_m := 6.0
@export var balk_color := Color("6B7340")
@export var balk_far_m := 9000.0
## The hedges (Map3DGroundBalk, bake/hedge_lines.png): a line `hedge_m` wide
## centred on each hedge line — round the crofts, the open field's outside,
## the meadows — mixed toward `hedge_color` by `hedge` (0 off), gone by a
## camera `hedge_far_m` away; the hedge's own bushes stand on it.
@export var hedge := 0.0
@export var hedge_m := 9.0
@export var hedge_color := Color(0.22, 0.28, 0.12)
@export var hedge_far_m := 16000.0
## How far a field's rim is drawn per pixel along its edge, not in 20 m steps
## (Map3DGroundBalk.RIM; 0 off, 1 full).
@export var field_rim := 0.0

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

@export_group("Relief")
## How far the baked sky occlusion (bake/relief_ao.png) darkens the ground —
## valleys, a terrace's foot, gorges — 0 off; and its gamma (above 1 keeps
## open slopes light and deepens only the hollows).
@export var relief_ao := 0.0
@export var relief_ao_gamma := 1.0
## The share of it kept up close (camera nearer than `relief_ao_near_m`),
## rising to all of it by `relief_ao_far_m`: near, the sun and SSAO model the
## slopes, and a 40 m texel's dark reads as a burn beside a house.
@export var relief_ao_near := 0.35
@export var relief_ao_near_m := 2500.0
@export var relief_ao_far_m := 10000.0
## The open grass's swards (Map3DGroundRelief): how far its lusher and drier
## patches swing (0 off), their size (metres), the camera distance they are
## gone by, and the dry sward's hue.
@export var meadow_mottle := 0.0
@export var meadow_mottle_m := 90.0
@export var meadow_mottle_far_m := 6000.0
@export var meadow_dry := Color("9E945C")


## The map's ground look (the saved .tres).
static func shared() -> Map3DGroundLook:
	return load(PATH) as Map3DGroundLook
