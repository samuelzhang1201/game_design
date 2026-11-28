# Plan: militia figure step 1, the duel clips

Spec: `docs/superpowers/specs/2026-11-26-militia-figure-wiring-design.md`, step 1.

Blender source `assets/3D/model_wip/blender_output/militia/militia_parts_11_hem.blend` (main checkout,
git-ignored). Work in a saved COPY beside it (`militia_parts_12_duel.blend`), so `_11_hem` stays the shipped
source until the owner approves. Blender: the owner's instance via MCP when free, else a second instance on
port 9877 after asking (never another session's open file).

1. Import the nine infantry actions: `scripts/s10_import_src.py` with `CLIPS` = BLOCK..BLOCK_4, HIT..HIT_3,
   DEATH, DEATH_2 (as `inf_<CLIP>`, from `infantry_shortsword_shield.blend`).
2. Transfer: `s12_transfer.py` with those `CLIPS`; gate: the `twist` report a few degrees.
3. Narrow: `p9_narrow.narrow(clip, 0.6)` on BLOCK* and HIT*; DEATH*: narrow only while standing (judge from
   the frames; report).
4. Skirt: `p6_skirt.bake(clip)`, `exposure([clip])`, `repair(clip)`, `nudge` where a frame still crosses.
5. Gear clearance: `solve_clear.py` as the PLAN's NOTE says (default sigma).
6. Ground: `ground.py` (soles), DEATH lying on the ground (no body below z 0).
7. Owner review in Blender (GIFs to `preview/militia_parts/`); install only on the owner's yes.
8. Export: `game_export.py` with the nineteen clips (its CLIP list grows; first ten byte-identical motion),
   `check_glb.py` none; `.import` loops unchanged (BLOCK/HIT/DEATH play once).
9. Repo: `units3d.json`, `army_art.csv` `duel` / `contact` (contact shares measured off the new clips),
   `test_militia_model.gd`, the seven certificates re-issued (`certify_locomotion.py`),
   `unit_locomotion.csv` digests, README / `scripts/map3d/CLAUDE.md` / `tools/CLAUDE.md` lines.
10. Visual review: `snapshot_screen --battle-case militia_fight` real window, critic pass; PR.
