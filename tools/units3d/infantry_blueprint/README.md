# The blueprint man-at-arms (the game's infantry piece)

`assets/3D/units/infantry/infantry.glb` since 2026-09-29: hand-built in Blender from the owner's
turnaround blueprint (`assets/3D/units/infantry/model_wip/infantry_kit/blueprint/`, git-ignored) and textured
with the owner's material swatches (`infantry_kit/D`, the seven it uses copied here at 512 px
into `swatches/`). It replaced `infantry_scan.py`'s Graf Salm scan. One command:

```
tools/units3d/infantry_blueprint/build.sh [WORK_DIR]
```

builds from an EMPTY scene (`build_model.py`: `base_mesh.py` → `armour.py` → `rig.py` →
`march.py` → `garrison.py`), bakes the atlas (`texture.py`), and exports (`export.py`) into
`assets/3D/units/` with its `units3d.json` entry. `WORK_DIR` (default
`assets/3D/units/infantry/model_wip/infantry_build/`, git-ignored) keeps the untextured and the textured
`.blend` to open by hand. Then run Godot's import (`Godot --headless --path . --import`).
23,570 tris, 29 bones (the humanoid, the spear, three three-link cloak chains), one 2048 atlas.

| file | what it does |
| --- | --- |
| `base_mesh.py` | the body under the armour, rings read off the blueprint (tables `TORSO`, `LEG`, the arm joints) |
| `armour.py` | every plate as a one-sided shell with rolled edges, half-built under a Mirror; brass rivets on the edges; the helmet (brim, open eye slit, pointed visor with breaths); leather thighs, strapped knee, separate greave; spear, shield, the cloak hung over the armour by ray |
| `rig.py` | the skeleton; each plate rigid on its bone (a joint's plate shared), the body by distance, the cloak on its chains |
| `march.py` | MARCH from CMU 02_01 mocap (`walk_02_01.json`); the spear SHOULDERED (`SH_GRIP` / `SH_REST`, tip up and back); the cloak streaming (`CLOAK_MOTION`) |
| `garrison.py` | GARRISON: the spear grounded, the weight shifting, a breeze in the cloak |
| `texture.py` | one atlas: aged steel (D1's scratches, object-space patina, grime, rust, streaks), mail D6b, leather D5, ash D7b, the shield D9b over D7b in the shield's own frame, the cloak D4's weave dyed the shield's green |
| `export.py` | turns the figure to face +Y, stands the spear upright at REST (the game measures a piece off its rest mesh), NLA tracks, `stride_m` |
| `checks.py` | clipping: what pokes out through the cloak, the spear's clearance |
| `shots_tex.py`, `strip.py` | renders: views of a textured file, a walk strip |

## What was learned

* **The game's light is not Blender's.** A dark, fully metallic plate (the owner's "dirty, not
  reflective") read as a BLACK silhouette at a piece's 30 px; metallic 0.25 on a mid-grey aged
  tint (`AGE=C`, `STEEL_METAL=0.25`) reads as steel. In Blender's studio light the same plate
  looks nearly white. Judge the steel in the game (`snapshot_screen --zoom3d 700 --at3d x,y`).
* **The atlas tiles are sRGB numbers, the bake's shader colours are linear**: the same GREEN
  in both made the cloak half as bright as the shield. The cloak's colour is the D9b swatch's
  mean, converted.
* **Cycles' pointiness is per vertex**: edge wear from it lit whole low-poly quads into pale
  squares. Off.
* **Unwrap per material in FACE select with UV sync**: in vertex mode a neighbouring
  material's faces came along and were packed over a cell already placed.
* **A straight visor cheek cuts into a round skull** between the ridge and the side:
  `clear_of_skull` holds it out.
* **The cloak must hang, not cling**: each point over the outermost armour behind it
  (dense rays between rows — the lames' flared lower edges poked through between rows), never
  drawn in faster than 0.2 m per metre down; weighted to the thighs it was dragged into the
  fauld, so it rides its own chains, streamed back so a stride clears it.
* Blender 5 actions are layered: fcurves live in `action.layers[].strips[].channelbags[]`.
* Cycles' Metal kernel compile sometimes dies with an NSException; `build.sh` retries.
