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

## The commander and his banner

A unit's COMMANDER is drawn: one rider on the armoured horse under his realm's banner (the banner is a
ruling for the commander only and does not reopen the soldiers' standard above; spec
`2026-11-27-commander-figure-design.md`). `Map3DUnitDress.sync` — called by the Units layer for every
ADMITTED regiment, never a ghost — hangs one `Map3DCommanderRider` named `Commander` on the piece's node
(`Map3DCommanderRider.sync`), so he is shown, hidden (symbol mode, a hidden view; his clip stops),
stopped offscreen and freed with the piece, and needs no edit of the royal carrier's pinned files.

- **Who has one** (`leads`): a unit whose `GameState.military_rosters[code].commander_id` is set — the
  crown's and a SEEN foe's alike, each under its own realm's flag. Never the royal piece (`is_royal`:
  the king himself is that rider), never a ghost, never a fleet (no piece). A unit whose commander
  fell stands leaderless until the next appointment.
- **He takes no place**: not a formation slot, not in the piece's `figs` / `anims`, not a battle group,
  no number on any card; nothing is saved. A click on him picks his unit (the picker's ray test,
  `Map3DPicker.ray_depth`, walks every mesh under the piece's node, his too — his box cut at his head's
  height, the mesh meta `Map3DCommanderRider.PICK_TOP`, so the air round his banner takes no click; the
  unit's screen box is the men's alone); he has no card, name or mark of his own.
- **Hung unseen**: a new rider is invisible until his first `stand()` on the next frame, when his piece
  is seated — before that his size and place are not his, and an invisible mesh takes no click.
- **Where he stands** (`_place`, each frame from the live piece; re-solved only when the piece's
  transform, extent or his scale changes): alone, centred on the files, straight ahead of the first rank
  — the foremost slot plus a figure's half depth (`front_of` over the piece's `slots`, not its half
  `extent`: a block's ranks do not straddle its centre), then `map3d_commander_gap` of his own lengths
  clear and half his length (`lead_m`) — facing the unit's way, planted on his own ground
  (`Map3DUnitRig.plant`). The same on the march, standing by, in garrison and holding a front line.
- **A battle block** (`physical_groups`): not drawn while its figures walk to their points (`easing`).
  Then, through the stand-off (`BattleSystem.battle_of(...).rounds` 0), he stands ahead of the foremost drawn figure in the frame of the unit's saved `facing_deg`, on
  STANDBY, `map3d_commander_standoff_share` of the clear ground between his first rank and the nearest
  drawn enemy figure of his battle (`_room`, `standoff_lead`), never past his ordinary lead — the two
  sides' commanders keep the middle of that ground between them. Where that share would back his tail
  into his own rank (lines closer than his half length over that share) he is NOT DRAWN. Once a
  round is fought he is not drawn either: his ride to the unit's left rear and `COMMAND` are the
  spec's step 3.
- **Size**: `map3d_commander_size` is his `army_art.csv`-style size (his model box, banner tip
  included, over the piece height), measured so his horse is the cavalry's horse at every camera
  whatever arm he leads (`test_map3d_commander_rider.gd` checks it against the two installed models;
  re-measure after a re-export of either).
- **Clip** (`clip_for`): `MARCH` (the gallop) ahead of an arm whose `army_art.csv` `commander_gallops`
  is 1 (the cavalry), `MARCH_WALK` ahead of every other arm, only while an ordinary piece's action is
  MARCH; `STANDBY` otherwise. His march keeps his unit's ground (`march_rate`): the men's plan-timed
  pace (`pace_key`) carried over by the two strides (`map3d_commander_walk_stride_m` measured off
  `MARCH_WALK`, `map3d_commander_gallop_stride_m` the cavalry's lock) and scales. Each clip starts at a
  phase hashed from the unit's code.
- **The banner**: the cloth is the second surface of `scenes/models/units/commander.tscn`
  (`banner_cloth`), bare linen in the scene; `Map3DCommanderFigure.set_flag` puts the realm's texture
  (`Map3DNationalFlag.texture_for`, the Units node's `realm_flags`) on a copy of that material shared by
  the realm's commanders, and a realm with no flag art keeps the linen. The cloth's motion is baked
  into the clips.

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
tunic equally light, told apart by hue. The cavalry and royal models
have no cloth material in their Tripo atlases: their `<model>_tunic_mask.png` is
baked by `tools/units3d/cloth_mask.py` (an HSV window per atlas on the dyed
cloth; it prints the `tunic_luminance` for the arm's
`unit_realm_tint_<model>.tres`). The axemen's hand-axe soldier is the infantry's body on its own atlas: its
`unit_realm_tint_axemen.tres` is the infantry's overlay reading the axe atlas, with the infantry's tunic mask
(the body's region of the two atlases is the same). The militia's mask comes from its exporter
(`tools/units3d/militia_arp/game_export.py`: the tunic's and skirt's faces by the
source's `part_id`), under `unit_realm_tint_militia.tres`; the archers' likewise
(`tools/units3d/archer_parts/game_export.py`: the gambeson's faces by the source's `part`), under
`unit_realm_tint_archers.tres`. An overlay is painted only on a mesh drawn from
its material's `albedo_atlas`, so a prop on its own texture keeps its colours; a prop
in the figure's own atlas is left untinted by the mask (the archer's bow, quiver, arrow).
