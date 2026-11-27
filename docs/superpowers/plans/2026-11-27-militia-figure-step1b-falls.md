# Plan: militia figure step 1b, the falls

Spec: `docs/superpowers/specs/2026-11-26-militia-figure-wiring-design.md`, step 1b. Owner 2026-11-27: "继续做1b倒地动作".

Source: `assets/3D/model_wip/blender_output/militia/militia_parts_13_falls.blend`, a copy of `_12_duel` (main
checkout, git-ignored). Run headless (`Blender -b`) so no open window is needed; save only when the gates pass.

1. Keep the plain bake as `DEATH_bake` / `DEATH_2_bake` (the baseline: 30 / 36 crossing frames).
2. `scripts/p12_falls.py` `lie_axis`: the bake and repair with the rig stood up along the thighs.
3. `floor`: the real ground, with a per-frame threshold.
4. `settle`: the upper side's cloth onto the legs.
5. Gates: no leg through the skirt in any frame, skin at most 1 cm under the ground; `check_gear`, then
   `solve_clear` (DEATH) and `solve_sword_cloth` (DEATH_2).
6. Previews (`preview/militia_falls/`, before and after), critic pass.
7. Export with `FALLS` (`game_export.py`), `check_glb.py` none; the first seventeen clips match step 1.
8. Repo: `army_art.csv` `duel` `DEATH:DEATH;DEATH_2`, `units3d.json`, `test_militia_model.gd`, the seven
   certificates re-issued, README and guides.
9. Real-window shot of a fought `militia_fight`, PR.
