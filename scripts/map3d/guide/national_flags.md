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

`Map3DStandardBearer` modifies only the carrier's right arm and hand after its
ordinary animation. ARP's independent stretch joints require explicit global
joint placement. The pole's scene origin is one grip height below the right hand;
it keeps the figure's heading, not its animated wrist rotation. Existing rigid
weapon socket bones are collapsed on that carrier; legs, gait phase and pace
remain the ordinary unit's. Installed ARP and mounted models are covered by the
national-flags test. The infantry uses `arm_stretch.r`, `forearm_stretch.r`,
`hand.r`, with `cc_weapon.r/l`; mounted models use `R_UpperArm.R`,
`R_Forearm.R`, `R_Hand.R` and the cavalry's `Lance` socket.
