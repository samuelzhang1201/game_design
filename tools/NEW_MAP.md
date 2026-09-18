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
3. `G -s tools/bake_manors.gd -- --map <id>` — manor names and the cell
   index. **Always after the import**: the importer's own cell index and
   manors differ in a few cells; this bake is the one the game reads.
4. `G -s tools/bake_sea_distance.gd -- --map <id>`
5. `G -s tools/bake_settlements.gd -- --map <id>`
6. `G -s tools/bake_relief.gd -- --map <id>` — the relief AND the biome
   weights at their own resolutions. `bake_biome_weights.gd` alone writes the
   weights at a different scale; run `bake_relief.gd` last.
7. 3D: `python3 tools/map3d/bake_world.py --map <id>`, then
   `G -s tools/map3d/build_world.gd -- --map <id>` (tools/map3d/README.md).

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
