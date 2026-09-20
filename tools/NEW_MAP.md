# Bringing in a new map

A map pack is one Azgaar export (`*Full*.json`). Nothing in the code or the
tests names a pack: every tool takes `--map ID` (`--map-id ID` for the
importer, `--pack ID` for `arms_prompts.py`, `ARMS_PACK=ID` for
`install_map_art.py arms`) and otherwise uses the row of `data/maps.csv`
whose `is_default` is 1. Re-running this list on `beria` reproduces the
committed files byte for byte (checked 2026-09-18).

`G` below is `GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .`

## 1. Import and bake — automatic, in this order

1. Put the export in `assets/maps/<id>/` and add a `data/maps.csv` row
   (copy beria's, swap the id; set `is_default` to 1 to make it the game's map).
2. `G --script res://tools/import_azgaar.gd -- --map-id <id>` — every pack
   table and the index bitmaps.

   **Hazard (found 2026-09-20, not yet fixed): re-importing an unchanged
   export can still change the pack.** Re-running this step on `beria`'s own
   JSON with nothing edited in Azgaar rewrites
   `data/maps/beria/political/manors.csv` and
   `assets/maps/beria/world_cell_index.png` with real content changes (not
   encoding noise) — both were last generated before the importer's
   neutral-burg-skip logic changed, so auto-numbered manor names shift
   downstream of the two burgs it now drops. `world_cell_index.png` is the
   bitmap that ENCODES MANOR IDS PER PIXEL (CLAUDE.md), so a workflow of
   "edit in Azgaar, re-import" silently renumbers manors and desyncs that
   bitmap from every save that referenced the old ids. Before doing a real
   re-import: diff `manors.csv` and re-bake `world_cell_index.png`
   (`tools/bake_manors.gd`, step 3 below) deliberately, and expect a
   one-time manor renumber rather than assuming re-import is a no-op.
3. `G -s tools/bake_manors.gd -- --map <id>` — manor names and the cell
   index. **Always after the import**: the importer's own cell index and
   manors differ in a few cells; this bake is the one the game reads.
4. `G -s tools/bake_sea_distance.gd -- --map <id>`
5. `G -s tools/bake_settlements.gd -- --map <id>`
6. `G -s tools/bake_relief.gd -- --map <id>` — the relief AND the biome
   weights at their own resolutions. `bake_biome_weights.gd` alone writes the
   weights at a different scale; run `bake_relief.gd` last.
7. 3D map: `tools/map3d/build_pack.sh --map <id>` — manor land, bake,
   scene and `manifest.json` in one command, into the pack's `maps.csv`
   `map3d_dir` (empty: `assets/map3d/<id>`; tools/map3d/README.md).

**A pack's `world_*.png` are DATA, never pictures** — ids, distances, a
height field, blend weights, read as an `Image` or sampled for their exact
values — so they must import LOSSLESS and must never be re-imported as VRAM
compressed (VRAM compression scrambles manor ids and bands the sea). Two of
them are handed to 3D shaders, which is what makes the editor's "detect 3D"
want to recompress them. Nothing to do by hand: `project.godot`'s
`[importer_defaults] texture` sets `detect_3d/compress_to: 0` for the whole
project, so a bitmap imported for the first time already has it, and
`tests/map3d/test_map3d_look_assets.gd`'s
`test_a_packs_bitmaps_are_data_and_are_never_recompressed` fails if any of a
pack's bitmaps ever loses `compress/mode=0` or that flag. If it does fail,
fix the `.import` — do not "fix" the test.

## 2. Bindings — the owner's decisions (`data/maps/<id>/`)

- `realm_bindings.csv` — which kingdom is `player_realm`, `raider_realm`,
  `neighbor_realm`, `empire_realm`. The authored story assumes the raider
  lies west of the player, the neighbour north, and the player borders all
  three: pick kingdoms that fit, or the prose will read wrong.
- `house_bindings.csv` — each court family's provinces (the crown's is the
  capital's province alone).
- `map_info.csv` comes from the import; `manor_name_overrides.csv` and
  `arms_bindings.csv` are optional.

## 3. Coats of arms — usually nothing to do

`G -s tools/arms_report.gd -- --map <id>` says where each kingdom's and
house's arms come from. A pack with no arms of its own BORROWS every other
pack's installed art, in its own fixed order and never twice while the pool
lasts (HouseArms; beria gives 7 kingdom and 191 house arms). A house is a
family, and every unbound province is its own family, so a map needs about
one house arms per province. Pin any key to a chosen coat of arms with
`arms_bindings.csv` (`key,arms`; `arms` is `res://...png` or
`<pack>/<key>`). Only when the report says **SHORT** do new arms need
generating: `arms_prompts.py --pack <id>`, generate, `ARMS_PACK=<id>
install_map_art.py arms`.

## 4. Check

- `./run_tests.sh` — fixtures derive their kingdoms, capitals and roads from
  the pack; a failure here is a real difference in the new map.
- Look at it: `Godot --path . res://tools/snapshot_screen.tscn -- --out /tmp/x.png`
  (`--screen root --layer "3d map"` for the 3D map), `tools/snapshot_map.gd`.
- Numbers tuned on beria that may want retuning: the high-ground bands
  (`map_biome_hill/mountain/peak_height`), the 3D scale (50 m per pack px —
  a larger canvas is a larger world; `map3d_zoom_*`), and the economy seeded
  from the towns' production.
