# 3D military units

Animated wargame pieces built from Hunyuan3D sources: one glTF per unit
holding the figure, its skeleton, two actions and the base it stands on.

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
| `data/unit_models.csv` | every tuning number: height, yaw, voxel, tri budget, base size, the weapon and prop boxes |
| `measure_units.py` | prints each source's slice profile and shoots four orthographic views — **run this first for a new source**; every number in the CSV is read off it |
| `make_units.py` | the build: retopo → bake → skeleton → skin → lock the props → base → actions → `assets/units3d/<code>.glb` |
| `shoot_units.py` | photographs the BUILT glb (contact sheet + a strip per action), so a shot also proves the export round-trips |
| `data/army_art.csv` | which .glb each arm wears in the game (`model`) |
| `data/army_orders.csv` | the rows of the right-click order menu |
| `unit_common.py` | import, place, measure |
| `assets/units3d/units3d.json` | what was built: tris, bones, which weighting was used, the action frame ranges |

The sources are `assets/units3d/ai_src/<code>.glb`, generated through the
Blender MCP's Hunyuan3D at 35 credits each.

## The contract

* The figure faces **+Y** with **+Z** up and stands on **z = 0**, which the
  exporter turns into glTF's own forward. A camera parked on -Y photographs
  its back.
* The **base is a separate, unskinned object**. Welded into the figure it
  would deform with the animation, and the whole point of a wargame counter
  is that the disc sits dead still under a moving man. Round for a man,
  drawn out along the line of march for a horse, which does not fit on a
  man's disc — the source measures 2.5 m nose to tail.
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

* `data/army_art.csv`'s `model` column names the .glb an arm wears. A fleet
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
