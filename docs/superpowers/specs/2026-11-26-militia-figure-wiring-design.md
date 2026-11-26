# Militia figure: duels, pivots and a locomotion certificate

Owner 2026-11-26 (Chinese, relayed by the coordinating session): asked why no militia shows in the game, and
chose the FULL wiring of the installed militiaman (`assets/3D/units/militia/militia.glb`, PR #386; tint mask
PR #388) over a look-only swap: its own piece, locomotion certificate, pivots, duel clips, scene and tint.

## What is already on main

- The look: `scenes/models/units/militia.tscn`, `army_models.tres` / `realm_tint.tres` `militia`,
  `unit_realm_tint_militia.tres`, the `army_art.csv` `militia` row (stride 1.3597, steps 0.2121;0.9091).
- The figure switch (77db25d9): a raised town militia's roster row carries `figure` = `TownMilitia.FIGURE`;
  `Map3DFormation.figure_of` draws it with the militiaman while its piece, card, footprint and bodies stay its
  first arm's. `snapshot_screen --battle-case militia | militia_fight` shoots it.
- The `militia` ARM (PR #396, spec `2026-11-26-militia-arm-design.md`): its piece IS the militiaman, with
  `unit_footprints.csv` and `army_clearance.csv` rows; certificates re-issued for the new rows.

## What is missing

1. **Duel clips.** The GLB has the infantry's first ten clips only. With no `duel` / `contact` in its
   `army_art.csv` row the militiaman never duels: in a fought battle he strikes his chain in place, and a loss
   is freed at once with no fall. Infantry and axemen meet, block, take hits and fall.
2. **Pivot pair and certificate.** No PIVOT_LEFT / PIVOT_RIGHT, no `unit_locomotion.csv` row, no
   `body_locomotion_militia_*` balance rows. Today this only matters on the CANDIDATE body world
   (`military_migration.body_version`, which no ordinary campaign carries; checked 2026-11-26 by raising a
   militia regiment and resolving days: all `complete`): there `BodyMotion._loco_policy` refuses the
   piece and the whole candidate world errors (`army_system.gd` "Unsupported locomotion policy/certificate"),
   and `Map3DCandidateGait.refusal` refuses the unit. The shipped game marches it as a whole piece.

## Approach

The infantry's pipeline, on this body. Both steps are Blender work on
`assets/3D/model_wip/blender_output/militia/militia_parts_11_hem.blend` (git-ignored, never moved or deleted;
history and rulings in that folder's `PLAN_parts_rebuild.md`), then `tools/units3d/militia_arp/game_export.py`
and `check_glb.py`.

What differs from the axemen: this rig is NOT the infantry's (`mil_rig`, 100 bones incl. 30 skirt bones), so
every new clip must (a) be transferred by `s12_transfer.py` from the infantry source's action
(`infantry_shortsword_shield.blend`), (b) be narrowed by `p9_narrow.py` (s 0.6) unless it is a walk, (c) get its
skirt keys from `p6_skirt.bake` and `repair`, (d) gear clearance (`solve_clear.py`), (e) pass `exposure()` in the
.blend and `check_glb.py` on the export (no leg through the skirt in any frame).

Risks: the skirt drape hangs columns from the belt toward the ground; a DEATH fall (lying on the back) and a
pivot's crossed legs are poses it was never built for. If a clip cannot pass the gates, the builder reports the
frames to the owner rather than shipping it.

## Steps (one PR each)

1. **Duel clips** — BLOCK, BLOCK_2, BLOCK_3, BLOCK_4, HIT, HIT_2, HIT_3 on the militia rig,
   appended after the first ten (the first ten export unchanged), reinstalled GLB, `units3d.json` entry,
   `army_art.csv` `militia` `duel` (STRIKE ATTACK;SLASH;ATTACK_VAR1, the infantry's) and `contact` (measured
   off the new source clips; the infantry's where the motion is the same), the seven certificates re-issued
   (`army_art.csv` is a certified input), README and nested guides. Tests: `test_militia_model.gd` asserts the
   duel (`Map3DDuelDriver.can_duel`) instead of its absence. Visual review: `--battle-case militia_fight`
   real-window shots of militia duelling. Outcome: in a siege's assault the militia blocks and takes hits like
   the infantry; a loss is still freed at once (no DEATH clip: `Map3DFall`'s own rule).
   Builder's findings (2026-11-26, `militia_parts_12_duel.blend`, script `scripts/p11_duel.py`): transfer twist
   2.0° as the first ten; `narrow_duel` (s 0.6 about the start's ankle midpoint, pelvis moved with the narrowed
   feet, raise weighted by the trunk's uprightness) ankle error 0 mm; skirt baked and `repair`ed: no leg through
   the skirt in any frame of the seven; HIT_2's shield cleared by `solve_clear`; the sword brushed the
   spread skirt in the crouching BLOCK_3 / BLOCK_4; owner "先改剑擦裙摆": cleared with the skirt counted for the
   sword hand only (`solve_sword_cloth`, wrist turns made costly so the arm swings out at the shoulder, taste.md): 0 and 2
   frames left (a 4-face brush), the shoulder turned up to 15°, the wrist's bend unchanged.
1b. **The falls** (DEATH, DEATH_2). The drape hangs columns round a VERTICAL axis, so on a body on the ground
   it fails: face down the skirt stands off the back like a sail; on the back the legs come through a bell
   (30–50 skirt faces crossed per lying frame, through the held final pose). Tried and rejected: blending the
   chains to their rest under `root.x` (worse), draping with the rig stood up about its pelvis (the seated
   topple's level thighs break it). Needs a lying-cloth rule (the chains laid along the thighs and onto the
   ground) before these two clips ship.
2. **Pivot pair and certificate** — the pivot pipeline (`tools/units3d/soldier_arp/`, `pivot_mapping.py --arm
   militia` with this body's MARCH phases and bounds; skirt keys solved for each pivot frame), plan
   `militia_pivot_plan.json`, fixture, provider `scripts/map3d/map3d_militia_locomotion.gd` (the infantry's
   solver on this plan), certificate `…/locomotion/militia/`, `unit_locomotion.csv` row,
   `body_locomotion_militia_turn_q` / `_contact_um`, every certificate re-issued. Outcome: a militia regiment
   wheels and stops on its own feet on the candidate body path; the candidate world no longer refuses a realm
   that recruited militia.

Not in scope: a card painting, a wooden war piece, a militia-only formation, the arm's opening regiments
(the arm spec's step 2).
