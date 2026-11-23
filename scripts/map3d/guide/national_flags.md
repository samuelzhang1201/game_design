# National standards

Approved originals and their source selections live in `assets/2D/flags/realms/`.
The editor-owned `national_flags.tres` ArtTable maps realm slots to textures;
`Map3DNationalFlag.texture_for` resolves slots through the current pack bindings.
No country or map pack is named in runtime code. Missing art draws no flag.

`scenes/models/flags/national_standard.tscn` owns the wooden pole, cloth mesh,
material and restrained wind. The cloth shader receives light on both faces.
`Map3DCityFlags` is referenced by the Houses layer and takes its admitted
settlement list, so flags share the houses' distance and budget. A pole is seated
on an actual highest vertex of the settlement's landmark (or first house), using
the same baked transform and terrain seat. Province ownership changes refresh
textures on a paused clock. These are physical objects, never camera-facing marks.

The Units layer applies `Map3DUnitStandard` only after normal sight admission.
Exactly one existing figure receives the standard; a saved physical formation
chooses the first surviving group. No extra person, personnel change, moved slot,
new save field, or hidden-state query is involved. The existing model bounds and
reference scale are measured before attaching its standard.

The royal carrier's source gate pins the roster's flag helpers as executable
dependencies. A decorated figure remains outside its unmodified native-MARCH
proof domain: the scripted grip/standard must reject as `unproved_source_script`.
Adding a flag does not grant or extend a locomotion certificate.

`Map3DStandardBearer` modifies only the carrier's right arm and hand after its
ordinary animation. ARP's independent stretch joints require explicit global
joint placement. The pole's scene origin is one grip height below the right hand;
it keeps the figure's heading, not its animated wrist rotation. Existing rigid
weapon socket bones are collapsed on that carrier; legs, gait phase and pace
remain the ordinary unit's. Installed ARP and mounted models are covered by the
national-flags test. The infantry uses `arm_stretch.r`, `forearm_stretch.r`,
`hand.r`, with `cc_weapon.r/l`; mounted models use `R_UpperArm.R`,
`R_Forearm.R`, `R_Hand.R` and the cavalry's `Lance` socket.

## Realm colours on the figures

`Map3DUnitDress.sync` (called where the Units layer placed the standard) dresses
every figure of an arm listed in `GameArt.UNIT_REALM_TINT`
(`assets/3D/units/realm_tint.tres`: the arms on the infantry model) in its realm's
colour, so a mixed fight reads as two sides (spec
`2026-11-21-infantry-melee-scrum-design.md`, step 1). Each figure mesh — never the
carried standard — wears `scenes/map3d/materials/unit_realm_tint.tres` as its
`material_overlay`: it repaints the model's tunic mask
(`infantry_tunic_mask.png`, exported with the atlases by
`tools/units3d/infantry_arp/game_export.py`) in the instance uniform `realm_tint`,
keeping the cloth's shading (atlas luminance over the tunic's mean). The scene's
own material is untouched, so the WAR ROOM's tin and ink are unchanged. The colour
is the realm's political-palette hue at saturation `map3d_unit_tint_sat`,
its value solved for the linear luminance `map3d_unit_tint_lum`: every realm's
tunic equally light, told apart by hue. The cavalry, royal and archer models
have no cloth material in their Tripo atlases: their `<model>_tunic_mask.png` is
baked by `tools/units3d/cloth_mask.py` (an HSV window per atlas on the dyed
cloth; it prints the `tunic_luminance` for the arm's
`unit_realm_tint_<model>.tres`). The axemen's hand-axe soldier is the infantry's body on its own atlas: its
`unit_realm_tint_axemen.tres` is the infantry's overlay reading the axe atlas, with the infantry's tunic mask
(the body's region of the two atlases is the same). The militia's mask comes from its exporter
(`tools/units3d/militia_arp/game_export.py`: the tunic's and skirt's faces by the
source's `part_id`), under `unit_realm_tint_militia.tres`. An overlay is painted only on a mesh drawn from
its material's `albedo_atlas`, so a prop on its own texture (the archer's bow,
quiver, arrow) keeps its colours.
