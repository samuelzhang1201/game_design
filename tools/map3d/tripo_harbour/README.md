# Walls, piers and harbour ships from Tripo 3D

Since 2026-10-04 the town wall's three modules (`wall`, `wall_tower`, `wall_gate`), the
timber `pier`, the capital's cliff harbour `pier_cliff`, the small cliff landing
`pier_stair` (2026-10-05) and the four moored ships
(`fishing_boat`, `cog`, `longship`, `carrack`) are Tripo 3D generations (owner: 我已经在
tripo_inbox 中放入tripo 3d生成的3d模型，请操作blender修改并应用到游戏中去), replacing the
hand-built kit modules of `tools/map3d/blender_houses/fortifications.py` (ruled too plain,
2026-10-01). Generated on the owner's **paid** plan only (Tripo terms §5.2.2).

## Sources

| step | where |
| --- | --- |
| reference picture | `tools/map3d/gen_house_refs.py` (`--set ships` for the ships), picks of 2026-10-02 |
| Tripo generation | the owner, from the `REF_*.png` in `assets/3D/model_wip/tripo_inbox/<category>/<object>/` |
| GLB | moved to `assets/3D/<category>/<type>/model_wip/tripo/<type>_tripo.glb` (git-ignored, ~100k triangles) |

`JOBS` in `tripo_harbour.py` names each type's source, yaw, fit (game metres at twice life,
the longer ground span), `z0` (what becomes z = 0), triangle budget, atlas size, voxel and kind.

## Run (in the owner's open Blender, through the Blender MCP)

```python
H = {"CC_ROOT": "/Users/samuelzhang/game_design"}   # or a worktree
exec(open(H["CC_ROOT"] + "/tools/map3d/tripo_harbour/tripo_harbour.py").read(), H)
H["load_all"]()                                   # every source into the scene Tripo_Harbour
for t in H["JOBS"]: print(H["build"](t))          # each beside its source as <type>_game
for t in H["JOBS"]: print(H["export"](t))         # glb + the CSV's sizes + houses.json
```

The git-ignored sources are read from the main checkout (`SRC_ROOT`). Then, in the checkout:

```sh
Godot --headless --path . --import          # keep project.godot as it was afterwards
Godot --path . -s res://tools/map3d/tripo_harbour/make_scenes.gd -- --only <type>   # NOT headless (no shader defaults); restore house_models.tres UIDs after
tools/map3d/build_pack.sh                   # the bake lays the walls, piers and ships
```

A new type's `.glb.import` needs `meshes/force_disable_compression=true` and its atlas
`.jpg.import` `compress/mode=4` (Basis Universal), like the houses.

## What it does, and the traps that shaped it

* **z = 0 is where the runtime seats it.** A wall's foot — no house footing (owner
  2026-10-04: 城墙不应该有那些类似房屋才有的地基): its lowest course runs `BASE_M` (8 m) down
  into the ground, and the runtime shears a module onto the slope; a pier's DECK (`map3d_pier_deck_m` over the sea); a ship's WATERLINE (read off
  the side views: fishing boat 0.8 m over the keel, cog 2.5, longship 1.8, carrack 5.0).
* **The wall module** is the middle 24 m of Tripo's 48 m curtain (its ends were towers),
  cut flat at both ends so modules meet, its thickness squeezed to 0.7.
* **Fortifications are untinted** (`hh_stone_` under `hh_slate_`): the town's wall tints
  would patch the wall module by module. Piers and ships are one untinted surface.
* **Open sheets take no voxel shell.** The longship's and carrack's hulls and the cliff
  harbour's rock are open: a voxel remesh came back as scattered spars and sail corners.
  They are welded, filled and collapsed like the palaces (`tripo_houses` `SHEETS`), then
  `_scrub` deletes the faces the census calls flipped whichever way they turn (crossed
  sails) and pinches what that opens. The carrack needs 10k triangles: at 5k its sails
  crumpled like paper.
* **The cliff harbour keeps its rock** (owner 2026-10-04): cut away, the zigzag stair and
  the walls built onto it would hang in the air or sink into a real cliff they do not
  match. Its rock is turned to the land (-X) and its quay out to sea (+X); z0 9.5, not the
  gate platform's 12, or its sloping walkway drowned to a line of post tops. The bake keeps
  it at its own proportions (owner 2026-10-05) and walks it out to sea until no taller
  cliff buries its castle (`pier_cliff_*`). Its berths and the pier's are measured off the models
  into `bake_houses._BERTHS`, its castle into `_CASTLE` — re-measure them if a model changes.
* **The small cliff landing** `pier_stair` (owner 2026-10-05, reference C): Tripo put its
  jetty at -X, so yaw 180; its deck is 7.2 m over the fitted bottom. It is for a town on a
  cliff top; its gate box is `bake_houses._HEADS["pier_stair"]`, its berths either side of
  the jetty in `_BERTHS`.
* **A ship rocks** in `house_surface.gdshader` (`bob_on` and the roll / pitch / heave /
  period set per ship in its scene), its phase hashed from where it is moored.

* **Gate passage**: the gate job's `passage` profile is cut through the high and low meshes after closure and before baking. The exact boolean keeps the arch interior closed and bakes its stone colour into the atlas. Run the mesh census after rebuilding; the exported gate must retain a clear through opening.
