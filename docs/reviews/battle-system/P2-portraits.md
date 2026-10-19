# P2 commander portrait production evidence

Status: production in progress. `assets/imagegen/commander_portraits.csv` is derived from actual player/raider commander rows, including reserves. Other realms are excluded. At this checkpoint 147 keys are planned (see R1 below): 6 existing complete pairs reused, 27 new complete pairs installed, 114 still missing (33/147 complete). A generated source is not an installed or accepted portrait.

## Approved sample pairs

| Art | Character | Full seed | Dedicated bust |
|---|---|---:|---|
| K-22 | char_player_delphine_o_kala | 954159497 | Qwen Edit, same seed |
| K-23 | char_player_berengar_ashvale | 954159497 | Qwen Edit, same seed; solid-clothing revision removes paper at lower shoulders |
| K-24 | char_raider_beatrice_reedmere | 954159498 | Qwen Edit, same seed; cloth ties replace rejected zipper-like closure |

Full sources use the existing `qwen2512desk4` preset (Qwen-Image-2512 FP8, official Qwen encoder/VAE, Lightning 4-step LoRA, 4 steps, CFG 1). Dedicated busts use `qwenedit_desk` (Qwen-Image-Edit-2511 INT8, its Lightning 4-step LoRA). Both run on the existing desktop ComfyUI at `192.168.4.85:8188`; no service or global environment changed. BiRefNet produces the alpha cutouts. Runtime chips are 96×96 RGBA; full figures are 683×1024 RGBA. All six files have alpha spanning 0..255.

Exact source paths, model weights, seeds, prompts, source hashes and installed hashes are recorded in `assets/imagegen/commander_portrait_reviews.json`. Rejected source records are retained.

The main reviewer independently approved the three full sources, K22 bust, revised K23/K24 black-and-white alpha sheets and full alpha sheet. Review images are under `assets/imagegen/out/commander_samples/`: `chip-sheet-native.png`, `chip-sheet-4x.png`, `k23-alpha-review.png`, `k24-alpha-review.png`, `samples-full-alpha.png`.

## Real-window renderer check

The existing `--speaker` fixture correctly skips commanders who are absent from authored council meeting locations. Its first K22 capture therefore showed no person and was not accepted as an art check. The explicit tool-only `--portrait-review` flag now displays the actual conversation/dossier renderer without requiring a meeting. It does not move characters, enable appointments, or establish that these commanders can hold a council audience during play.

Real Godot windows (Forward+, no headless rendering), under `.superpowers/sdd/2026-10-16-battle-system-implementation/visual/`:

- `portrait-k22.png`: 1664×1040.
- `portrait-k23.png`: 1664×1040.
- `portrait-k24.png`: 1280×720.

All three were opened and inspected: hair silhouettes are complete, the audience crop reads as a torso portrait, and the BIO figure retains head, hands and boots. Alpha has no cream paper rectangles against the actual dark leather. Logs `/tmp/p2-k22-ui-review.log` and `/tmp/p2-other-sample-ui.log` report successful shots with no script errors or Nil calls. This checks full artwork in the actual renderer; dedicated 96px chips are additionally checked at native and enlarged scale against black/white and existing portraits.

## Batch review and rejection

The initial K25–36 batch used one shared seed and produced overly similar faces/builds. It is rejected as a batch, not counted complete. Changing seeds alone gave insufficient separation. Revised explicit bone structure, age, hairstyle, complexion and body shape plus independent seeds produced approved K25 (205202), K29 (292802), K35 (354502), reviewed together in `batch01-identity-revised.png`. The other nine first-batch identities were regenerated and reviewed by the same method. K28 still contained a zipper-like neck closure and was redrawn again (3516345252) with explicit cloth ties; the revised source passes. All twelve full sources, dedicated busts and transparent tiers passed batch inspection and are installed. `batch01-chip-alpha.png` and `batch01-full-alpha.png` show every installed pair on black and white. The 96px busts use simpler cloth shading than the full figures; faces and hair remain clear and no opaque paper or head-crop defects remain. Batch02 (K37–48) is reviewed and installed; see the continuation below. Later batches remain subject to sheet inspection for identity, period clothing, anatomy, crop and alpha before installation.

## Tool verification

Three-digit K IDs are supported by the library parser and post-process ID parser. `/tmp/p2-art-id-red.log` reproduced K100 omission/truncation; `/tmp/p2-art-id-green.log` verifies K22/K100/K162 and all actual eligible mappings. The cast installer now selects exact `<art_id>.png`: `/tmp/p2-cast-prefix-red.log` reproduced K-10 selecting K-109, and `/tmp/p2-cast-prefix-green.log` exercises the installer with all three neighboring IDs present and verifies the right bytes were installed. Python compilation and `git diff --check` pass. No engine or test files were modified for portrait production.

## Batch02 continuation and lower-cost chip derivation

K37–48: all twelve full sources were independently approved by the main reviewer. Revised K37 (seed 458099631), K45 (1652099712), and K48 (1916088626) replace their original pending sources; original records remain rejected/superseded. The three revised records were recovered from completed PNGs, including exact embedded Qwen graph and SHA-256, rather than regenerating completed jobs. `batch02-selected-full.png`, `batch02-selected-faces.png` and the final black/white `batch02-full-alpha.png` / `batch02-chip-alpha.png` are under `assets/imagegen/out/commander_samples/`. Main independently approved both final alpha sheets. All 24 layer output hashes were checked during bounded installation.

The main reviewer compared K22/23/24 dedicated busts against loose and tight full-source crops at native 96px and enlarged scale. The tighter frame was approved as a starting recipe: it keeps readable faces, exact full-source likeness, hair and shoulders. K46/47 receive individual extra hair clearance. Existing dedicated busts remain installed. New chips use the already approved full RGBA layer, cropped and downscaled with the installer's existing stdlib box filter; no extra face generation or segmentation is required. Each record includes original Qwen source/hash/seed/graph, full alpha source/hash, original-pixel crop, resampling recipe, source dimensions, review sheet and installed hash. The rule avoids a Qwen Edit job for each usable full source without relaxing alpha or likeness review.

`cast_art.csv` now explicitly marks new mappings `requires_review=1`. The installer refuses pending layers even if a matching generated file exists, verifies original source hashes and full-alpha hashes, and checks rebuilt output hashes before replacing installed art. It rebuilds full layers before dependent chips. Exact approved staged cutouts can be reused by hash; source selection never silently falls back to a different seed or neighboring ID. Five offline tests cover three-digit IDs, pending-source refusal through the cast command, exact source selection/output hashes and deterministic RGBA crop preservation. Python compilation and scoped `git diff --check` pass.

The Windows Qwen host at `192.168.4.85:8188` was unreachable on bounded queue/history checks during this continuation. No remote jobs were restarted. Existing local Comfy Desktop completed the twelve full cutouts before its server stopped; its log ended after chip queue submission, without a diagnostic exception. A temporary existing comfy-cli runtime lacked the Desktop BiRefNet nodes and was stopped, with no package/config changes. Chips were finished locally from the saved approved RGBA layers. The remaining 114 portraits have not been generated or installed; production resumes only when the original Qwen host is reachable.

## Batch02 real-window renderer check

The revised K37, K45 and K48 sources were opened and inspected in the actual conversation/dossier renderer (`--screen conversation --speaker <id> --portrait-review --still`, real windows): `visual/portrait-k37.png` at 2560×1600, `portrait-k45.png` at 1664×1040 and `portrait-k48.png` at 1280×720 under the implementation evidence directory. All three retain head/hair, distinct skin and age, and opaque clothing without a cream rectangle against the dark leather. Their logs are `/tmp/p2-k37-ui-review.log`, `/tmp/p2-k45-ui-review.log`, `/tmp/p2-k48-ui-review.log`; all shots succeeded without script errors. Full boots/hands and native chips remain covered by the independent alpha-sheet review. An initial root-screen K37 capture did not open the dossier and was overwritten with the correct conversation capture; it is not counted as evidence. All twelve new derived chips independently rebuilt to identical installed hashes; all 54 approved new-layer source and installed hashes plus twelve full-alpha dependencies were rechecked.

## Landing on main (2026-10-20)

The batch01/batch02 work above existed only in a Codex worktree snapshot (`refs/codex/snapshots/…`, commit `2e284726`); its worktree was removed. This PR copies exactly its portrait files (pipeline scripts, prompts, `cast_art.csv`, `commander_portraits.csv`, `commander_portrait_reviews.json`, the 27 new installed pairs and their `.import` files, this note and the `tools/CLAUDE.md` portrait line) onto current `main`, and nothing else from that snapshot. All 70 review records' installed hashes were rechecked against the copied files (0 mismatches) and `tools/imagegen/test_commander_portrait_pipeline.py` passes.

Implementer rulings (owner asleep; recorded for review):

- **R1 — scope.** `commander_portrait_manifest.py` re-run on current `main` lists 287 player/raider keys, not 147: PR #79 added 140 more player/raider commander rows (`char_<name>_<family>`, e.g. `char_adela_harrow`) after this production plan was cut. Those rows have no `K-` prompt, seed or mapping. This pass produces only the 147 planned keys (114 missing); the 140 are listed as missing in the manifest and left for a later authored-prompt pass (and an owner check that they are not a duplicate roster).
- **R2 — chips.** New chips follow this note's approved full-layer crop derivation (`layer_strategy` in the reviews JSON) rather than a separate `qwenedit_desk` bust per key; a dedicated bust is generated only when a crop fails native-size review.
- **R3 — renderer spot checks.** `--portrait-review` exists only in the snapshot, not on `main`; later batches rely on the black/white sheet inspection (identity, period clothing, anatomy, crop, alpha) and skip the real-window spot check.
- **R4 — desktop host.** `192.168.4.85:8188` was down at 2026-10-20 start (host unreachable; no other ComfyUI on the LAN). Generation retries hourly and never falls back to the Mac.

