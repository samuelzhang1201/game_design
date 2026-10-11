# 3D military units

Animated wargame pieces: one glTF per unit holding the figure, its skeleton
and its actions. No base (owner 2026-09-27). Both are now built from CC0
scans or by hand, each by its own script (`cavalry_scan.py`, `infantry_blueprint/`, below);
`make_units.py` is the Hunyuan-era build they reuse the rig, weighting and
actions of, and it skips both rows.

```
tools/units3d/build.sh            # everything, both units
tools/units3d/build.sh cavalry    # one unit
```

or by hand:

```
blender -b --factory-startup --python tools/units3d/make_units.py [-- CODE ...]
blender -b --factory-startup --python tools/units3d/shoot_units.py -- OUTDIR [CODE ...]
blender -b --factory-startup --python tools/units3d/measure_units.py -- OUTDIR
```

| file | what it does |
| --- | --- |
| `data/screens/map3d/unit_models.csv` | every tuning number: height, yaw, voxel, tri budget, the weapon and prop boxes |
| `measure_units.py` | prints each source's slice profile and shoots four orthographic views — **run this first for a new source**; every number in the CSV is read off it |
| `make_units.py` | the build: retopo → bake → skeleton → skin → lock the props → actions → `assets/3D/units/<code>/<code>.glb` |
| `shoot_units.py` | photographs the BUILT glb (contact sheet + a strip per action), so a shot also proves the export round-trips |
| `assets/3D/units/army_models.tres` | which .glb each arm wears in the game (an ArtTable, picked in the inspector) |
| `data/army/army_orders.csv` | the rows of the right-click order menu |
| `unit_common.py` | import, place, measure |
| `assets/3D/units/units3d.json` | what was built: tris, bones, which weighting was used, the action frame ranges |

The sources WERE `assets/3D/units/<code>/model_wip/<code>.glb`, generated through the
Blender MCP's Hunyuan3D; every Hunyuan source and render was deleted on
2026-09-29 (licence), so `make_units.py` now builds nothing on its own —
it is the library the scan and blueprint builds borrow from. A Tripo 3D
generation (paid plan only) is processed by `infantry_tripo/tripo.py`.

## The contract

* The figure faces **+Y** with **+Z** up and stands on **z = 0**, which the
  exporter turns into glTF's own forward. A camera parked on -Y photographs
  its back.
* **No base** (owner 2026-09-27: 撤除所有底座; the separate unskinned disc
  and then a modelled plinth were both rejected). The feet stand on z = 0.
* Two actions, `GARRISON` (a loop) and `ATTACK` (one shot), exported as
  separate glTF animations off muted NLA tracks.
* Joint positions are **fractions of the measured height**, never metres, so
  a source regenerated at another scale needs nothing changed.

## Four traps, all of them paid for once

**`ob.bound_box` is a cache.** In background Blender nothing refreshes it
between an operator and the next read, so a mesh that has just had a
rotation applied still reports its old box. `bounds()` measures the
vertices. Reading the cache cost a whole build: the figures turned exactly
as asked, the measurement said they had not moved, and the spear's box and
the shield's box came out on the wrong sides of the man and swapped.

**The glTF importer leaves every object in QUATERNION rotation mode**, where
assigning `rotation_euler` changes nothing and `transform_apply` then
reports `FINISHED` having baked an identity. A silent failure with no error
anywhere. `place()` turns through the matrix instead.

**Nothing raises when weighting fails.** Bone heat prints a *warning*, leaves
the vertices bare, and the glTF exporter quietly invents a `neutral_bone` to
park them on. The file exports, imports, plays both its animations and does
not move — which is exactly what the first cavalry was. `skin()` therefore
measures the share of vertices no real bone holds and falls back to
`weight_by_distance` (nearest three bone segments, distance to the fifth).
The mesh is run through `validate()` first, because "Mesh is not valid" is
what makes heat refuse to solve at all.

**A prop welded to the body tears in two.** The kite shield rests against the
man's side, so heat flows into it from the chest and the hip: half the
shield belongs to the arm, half to the body, and the first frame that turns
one against the other shears the plate. `rigid_props` pins it whole to the
forearm, and the left arm is moved at the CLAVICLE, above everything the box
caught, so the assembly swings as one piece and the shoulder still deforms.
The spear and the lance are pinned the same way but by a fitted cylinder
(`weapon_seed` seeds the axis; `weapon_lock_below_m` cuts it off below the
grip, or the lance's own axis carries on into the horse and welds a stripe
of barrel to the rider's glove).

## In the game (2026-09-22)

The units are drawn on the 3D map's MILITARY layer by `Map3DLayerUnits` +
`Map3DUnits`, one instanced .glb per regiment of the player's realm, and
ordered by right click (`ArmyOrderMenu`). Two things bind them to this
pipeline:

* `assets/3D/units/army_models.tres` names the .glb an arm wears. A fleet
  names none and keeps its flat 2D counter.
* the runtime MEASURES each model's own height and half width off its meshes
  (`Map3DUnits.model_size`), so rebuilding a .glb at another size needs
  nothing changed there — but the action NAMES matter: the layer looks for a
  clip whose name ends in `GARRISON`, `MARCH` or `ATTACK`, and a regiment's
  piece follows the ORDER it is under. Rename an action here and the map
  stops animating.

`ATTACK` is built and exported but nothing plays it yet: there is no battle.

## Open

* The cavalry is weighted by distance, not heat — its neck stretches a
  little at the top of the rear. Heat would fix it; the mesh has to survive
  `validate()` with every bone solving first.
* `GARRISON`, `MARCH` and `ATTACK` only. No death, no hit reaction, no
  charge — and nothing plays `ATTACK`, because there is no battle yet.
* A march walks in a straight line: `ArmySystem.march_day` has no
  pathfinding, so a column ordered across a bay walks across it.

## The cavalry is built from CC0 scans (2026-09-27)

`make_units.py` no longer builds the cavalry (its `unit_models.csv` row names
`cavalry_scan.py` and is skipped). The owner rejected the lofted
`model_cavalry.py` knight as crude and chose CC0 base meshes, at a game
budget:

```
blender -b --factory-startup --python tools/units3d/cavalry_scan.py
CAV_BLEND=assets/3D/units/cavalry/model_wip/cc0/cavalry_knight.blend blender -b --factory-startup --python tools/units3d/cavalry_scan.py
```

writes `assets/3D/units/cavalry/cavalry.glb` and `units3d.json`'s entry; `CAV_BLEND`
also saves an openable `.blend` (the piece alone, GARRISON playing);
`CAV_OUT=dir` writes a trial glb elsewhere. It needs the two scans in
`assets/3D/units/cavalry/model_wip/cc0/` (Sketchfab `faca2ad5…` Cleveland armour, whose
knight is kept, and `1cd8a30c…` Hunt Museum horse, whose shape is kept),
downloaded with the owner's Sketchfab key; both CC0-1.0. `model_cavalry.py`
stays as the library of lofts, tiles, rig helpers and actions it reuses.

Traps it paid for: the Hunt export is three chunks (weld before keeping the
biggest piece); the Cleveland scan is 123 loose shells (the knight is
`RIDER_PARTS`, by index); re-pointing ONE image node between Cycles bakes
wrote the third bake into the second's image (one node per target);
`model_cavalry.paint_atlas` paints its own hair/hoof tiles, parked on cells
this atlas never copies; a Chinese Blender UI names new UV layers in
Chinese, so `unwrap` names `UVMap` itself; the glTF ACTIONS mode exports
every action in the file whose bones match, so a live file's infantry
ATTACK rode along (export by NLA track).

## No base (2026-09-27)

The owner rejected the disc and then a modelled plinth: no piece has a base.
`cavalry_scan.py` and `make_units.py` build none; `strip_base.py` once cut the
disc out of the old Hunyuan infantry (deleted 2026-09-30 with that infantry). The
runtime seats a piece on its own half extents (`Map3DUnits.stand_extent`).
`shoot_glb.py GLB OUT feet` photographs the hooves and boots.

## The infantry is a Tripo 3D generation (2026-09-30)

`assets/3D/units/infantry/infantry.glb` is built by `infantry_tripo/tripo.py` in the owner's open Blender
from a Tripo 3D generation on the owner's paid plan (Tripo's terms §5.2.2: paid outputs are
ours; free-tier outputs are Tripo's). See `infantry_tripo/README.md`. It reuses the blueprint's
MARCH and old garrison stance (as STANDBY) through the injection points added to
`infantry_blueprint/march.py` / `garrison.py` / `export.py` (`R`, `A_REST`, `SH_*`, `STANCE`,
`CLIP`, `FEET_FORWARD`, `CLIPS`; absent, the blueprint builds exactly as before, save that each
foot now turns by its OWN rest direction). `unit_models.csv`'s row names it; `make_units.py`
skips it.

## The infantry was the blueprint man-at-arms (2026-09-29, replaced 2026-09-30)

Since 2026-09-29 `assets/3D/units/infantry/infantry.glb` is hand-built from the owner's
blueprint and textured with the owner's swatches: `infantry_blueprint/build.sh`,
see `infantry_blueprint/README.md`. It replaced `infantry_scan.py`'s Graf Salm scan
(deleted 2026-09-30, below); `unit_models.csv`'s row names
`infantry_blueprint/build_model.py`, so `make_units.py` still skips it.

## The infantry was built from CC0 scans too (2026-09-27, replaced 2026-09-29)

`infantry_scan.py` built the infantry from the CC0 noe-3d.at "Graf Salm" statue and the
Cleveland knight's helmet; `reanimate.py` re-authored its actions. Both scripts and the
Graf Salm source were DELETED on 2026-09-30 (the owner: delete outdated models and
assets) — git history keeps them.

## Courier

The courier rider (`assets/3D/units/courier/courier.glb`, GALLOP and IDLE) has its own build:
`blender -b --factory-startup --python tools/units3d/courier_build.py -- courier` (from the owner's Tripo 3D model), with its
scripts, sources and licences in `tools/units3d/courier/README.md`. The spy still wears the
cavalry model until it has its own.
