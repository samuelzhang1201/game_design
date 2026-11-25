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

No map figure carries a standard: every soldier of a unit is drawn alike (owner
ruling 2026-11-23). `Map3DUnitDress.sync` never
calls `Map3DUnitStandard`; that class and `Map3DStandardBearer` stay only because
the royal carrier's source gate pins `map3d_unit_standard.gd` (its test still
proves a decorated figure rejects as `unproved_source_script`). Re-adding a unit
standard needs a new owner ruling and a better carrier model.

## Realm colours on the figures

`Map3DUnitDress.sync` (called by the Units layer after sight admission) dresses
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
