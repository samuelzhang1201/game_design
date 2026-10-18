# Independent king and field camp (P3.3)

Rebuild in an isolated Blender 5.2 process; no live Blender session/editor is required or touched:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b -t 2 --python tools/units3d/king_camp/build.py
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b -t 2 --python tools/units3d/king_camp/validate.py
python3 tools/units3d/king_camp/review_sheet.py  # Pillow; creates contact sheet and GIF
```

The builder loads `~/.agents/skills/3d-model-build-up/scripts/quadkit.py`. See `SPEC.md` for the four-dimensional asset specification. Donor: committed `assets/3D/units/cavalry/cavalry.glb` and its embedded owner-paid Tripo atlas, existing skin and canter; no generation, retargeting or decimation. Builds are independent of any map pack. `-- --camp-only` skips the king rebuild for camp iteration.

Runtime outputs: `assets/3D/characters/king/king.glb` and `assets/3D/buildings/field_camp/field_camp.glb`. Sources, packed authoring blends, audit/round-trip JSON and rendered frame sequences live beside each in git-ignored `model_wip/`. Rebuild recreates them. All runtime textures are embedded in the GLBs; retain any extracted image/import files Godot creates during editor integration.

King: independent 19,289-triangle / four-material / 53-bone resource, cavalry-derived horse/rider with fitted brass circlet, wine wool mantle and saddle-mounted royal standard. New meshes `Crown`, `Mantle`, `RoyalStandardPole`, `RoyalStandard`, `RoyalStandardStripe`; body `KingBody`, skeleton `king_rig`. Crown follows `head`, mantle `R_Chest`, standard `Saddle`. Existing `Lance`/`Shield` attachment bones and fixed donor gear remain; interchangeable equipment assembly compatibility is not claimed.

Five in-place clips: `MARCH` 16/30 s, `STANDBY`, `OBSERVE`, `COMMAND`, `INSPIRE` 4 s each. Runtime displacement uses the **measured 2.4 m canter stride**, not the cavalry art table's historic 5.9 display calibration. Donor MARCH matrices are compared against the reimported king at every integer frame. COMMAND/INSPIRE are subtle mounted free-arm/head/chest gestures; the lance grip and horse locomotion remain inherited. No capture or death clips. Configure Godot loops in the editor/importer for MARCH/STANDBY/OBSERVE; COMMAND/INSPIRE may run once even though endpoints close.

Camp has six top-level mesh facilities: `CommandTent`, `TentA`, `TentB`, `SupplyCart`, `Stores`, `Watch`. Each mesh has its own origin at ground contact, geometry minimum Z=0 in Blender (Y=0 after glTF import); facilities overlap intentionally in the resource because the map renderer positions/grounds them individually. `Watch` includes the ordinary pennon and lantern. No royal symbol is in camp. Renderer controls visibility and scale for building/camped/packing; camp has no animation or unified base.

Validation requires all new king adornments and all camp facilities to pass `audit_game`, overall budgets <=20k/11k and <=5 materials, intended nodes, skin influence sums, exact clip set, loop pose closure, donor gait equality, round-trip dimensions and ground-contact bounds. Cloth boundaries and triangulated donor geometry are allowed notes.

**Inherited limitations:** the donor's GLTF UV/normal seams produce coincident vertices; exact welding on a validation copy exposes 15 non-manifold junctions (mainly muzzle/helmet). The donor geometry/skin is preserved and is explicitly **not** an all-pass geometry audit. Mounted idle donor vertices can dip about 3.6 cm below ground; hoof bone-head heights are not sole contact measurements. Cloth is rigidly skinned, with no simulated flutter. No new terrain-grounding offset or runtime compensation is hidden in this asset pipeline.

Blender renders/round-trip checks do not constitute project visual approval. Root integration owns editor scenes, GameArt tables, loop/compression import settings, and real-window flat/slope/near-water review with independent critic. Full game suite/fast suite are outside this bounded asset task.
