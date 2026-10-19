# P2 commander portrait production evidence

Status: the 147 planned commander keys and the 21 story characters (162 `K-` people) are installed in the painterly restyle, each with an approved review record (324 layers, hashes verified). Not covered: the 140 player/raider commander rows added by PR #79 after the plan was cut (R1) — they have no `K-` prompt yet. `assets/imagegen/commander_portraits.csv` is derived from actual player/raider commander rows, including reserves. Other realms are excluded. At this checkpoint 147 keys are planned (see R1 below): 6 existing complete pairs reused, 27 new complete pairs installed, 114 still missing (33/147 complete). A generated source is not an installed or accepted portrait.

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


## Painterly restyle (owner, 2026-10-20)

The owner asked for 2D people and event art in the rendering style of Frostpunk 2, moved to our medieval setting, then corrected the first read within minutes: the painting style only — no snow, frost or cold-weather dress; clothing exactly as each `K-` appearance line designs it; a temperate climate. The owner also delegated the pick ("我不挑了，你自己判断"). The coloured-pencil pairs (K-22..K-48 and the legacy council art) are superseded; their review records are kept with status `superseded`.

Method: `STYLE_CORE_commanders_fp2.txt` + `NEGATIVE_commanders_fp2.txt`, the new `[C-FIGURE]` canvas (library §canvas; plain medium-grey studio backdrop so BiRefNet cuts cleanly), `qwen2512desk4` on the desktop, the same per-identity appearance lines and seeds. Every ComfyUI output is archived under `assets/3D/model_wip/comfy-out/2d_art/portraits/commanders_2026-10-20/` (owner rule); review sheets are in its `review/`.

Implementer rulings:

- **R5 — model.** Qwen-Image-2512 over Z-Image Turbo: on K-22/23/24 × 2 seeds each, Qwen gave the cinematic painterly read, steady faces and correct proportions; Z-Image read flatter, like a costume photograph, with smaller heads (`review/fp2-style-samples.png`).
- **R6 — skin tone.** The first style core led with a cold desaturated palette and washed K-22's "warm brown skin" pale in both models. The core now opens with "true-to-life skin tone and ethnicity exactly as described" and keeps colour grading to restrained earthy tones; the negative adds whitewashed / grey skin. K-22 now renders olive-brown (`review/fp2-k22-skin*.png`, `review/fp2-temperate.png`).
- **R7 — story cast seeds.** K-01..K-21 shared one seed (954159497) in the pencil set; each now gets its own, `20261100 + n`, recorded in its review record.
- **R8 — scope of the restyle.** All 162 `K-` people are redrawn so the game has one style: the 147 commander keys and the 21 story characters (K-01..K-21; the six that are also commanders count once).
- **R9 — main characters.** The owner's "important main characters" (3D T-pose references) are read as the 21 named story characters K-01..K-21; generals and nobles (K-22..K-162) get 2D only. The T-pose sheets are references for the owner's own Tripo/Blender work — no 3D model is made here. Loose cloaks and mantles are left off the T-pose views (they fuse arm to torso in a generated mesh, `tools/guide/unit_reference_sheets.md`); every other garment follows the design.
- **R10 — review authority.** With the owner's delegation, the implementer reviews each 24-portrait batch on black/white sheets (identity, age, complexion and clothing against the appearance line; anatomy; crop; alpha) before installation, and lists any regenerated key here.
- **R11 — redraws.** Source review rejected K-98 and K-132 (feet outside the frame); each was redrawn with seed + 1 (K-132 needed seed + 2: 3106087034). K-66's bright bar at the top of the backdrop was checked after cutout. Every other source passed on its first seed.
- **R12 — T-pose side view.** The first side view of K-01 swung the arms forward. The side instruction now asks for strict profile with the near arm pointing at the camera (foreshortened) and the far arm hidden; front and back views keep the plain T-pose wording. The views are references only and live in `comfy-out/units/main_cast_tpose_2026-10-20/` (not in the repo).
- **R13 — checks per batch PR.** Each batch is art plus review records: the installer's hash checks, `test_commander_portrait_pipeline.py` and the manifest run locally; GUT runs in CI (the selector picks every functional category for an asset change).
- **R14 — T-pose garments.** The first T-pose pass dropped robes and headwear on 8 of 21 (K-02, K-12, K-13, K-14, K-18, K-19, K-20, K-21); the instruction now keeps every headwear piece, robe, gown, surcoat, coat, train, badge and fur trim and removes only a loose cloak or cape, and those 8 were redone. Kept as left: K-12's open fur-lined surcoat and K-14's furred over-gown (two seeds each — the edit model treats an open over-garment as a cloak); separate gear images can follow if the owner wants them on the model. Folder README: `comfy-out/units/main_cast_tpose_2026-10-20/README.md`.

## Extension: the PR #79 commander rows (K-163..K-302)

The coordinator relayed the owner's instruction to produce every needed art asset, so the 140 player/raider commander rows that PR #79 added (seven houses × 20 nobles, `category=noble`, ages from `roles.csv`) get `K-163`..`K-302`: library entries, `prompts.csv` rows and `cast_art.csv` mappings (`requires_review=1`), then the same painterly method and review as above.

- **R15 — authored appearance lines.** The rows carry no looks, so each line is drawn by a seeded script from its character id (seed = first 32 bits of SHA-256 of the id, also the image seed): face shape, nose, eyes, hair style, beard, build and garments are independent per person, so relatives do not look alike by default.
- **R16 — gender.** `roles.csv` has no gender column; the 20 first names split ten female (Adela, Celia, Elin, Helena, Joanna, Lucia, Nerida, Philippa, Rosamund, Tamsin) and ten male, read from the names.
- **R17 — houses.** Each house keeps a two-colour wool livery (Harrow madder red/oatmeal, Ashvale ash grey/moss, Fenwick slate blue/ochre, Blackthorn charcoal/oxblood, Redwater rust/teal, Stonehelm stone grey/brown, Wolfmere forest green/russet) and a pool of three neighbouring complexions, so a family reads as kin; Redwater and Wolfmere draw dark hair. Raider houses add one rougher detail (tablet-woven trim, an arm ring, a bone toggle, stitched cuffs).
- **R18 — noble dress, not the K-25..K-162 template.** These lines vary cote, tunic, gambeson, kirtle or gown under a surcote, jerkin, tabard, hooded shoulder cape or overgown, with varied belts, footwear and head coverings, which answers the "commanders all look alike" note for this set without touching the earlier designs.
- **R19 — deep brown complexions.** The seven Wolfmere lines that said "deep brown skin" (K-287, K-288, K-290, K-293, K-294, K-296, K-298) all rendered olive: the style core's "historically accurate … Europe" outweighs a bare complexion phrase. Those lines now say "very dark deep brown skin of African descent" and were redrawn on the same seeds; six render as written. K-293 stayed olive across five seeds and a changed nose, so its line was set to the house's "warm brown skin" and nose "a broad straight nose", redrawn on seed 2838475130 to match the image (first attempts kept in `out/rejected_skin/`).

### Restyle progress

| Batch | Keys | Sheets (`out/commander_samples/`) | State |
|---|---|---|---|
| fp2-b01 | K-01..K-24 (story cast + K-22..24) | `fp2-b01-full-alpha.png`, `fp2-b01-chip-alpha.png` | installed |
| fp2-b02 | K-25..K-48 | `fp2-b02-full-alpha.png`, `fp2-b02-chip-alpha.png` | installed |
| fp2-b03 | K-49..K-72 | `fp2-b03-full-alpha.png`, `fp2-b03-chip-alpha.png` | installed |
| fp2-b04 | K-73..K-96 | `fp2-b04-full-alpha.png`, `fp2-b04-chip-alpha.png` | installed |
| fp2-b05 | K-97..K-120 | `fp2-b05-full-alpha.png`, `fp2-b05-chip-alpha.png` | installed |
| fp2-b06 | K-121..K-144 | `fp2-b06-full-alpha.png`, `fp2-b06-chip-alpha.png` | installed |
| fp2-b07 | K-145..K-162 | `fp2-b07-full-alpha.png`, `fp2-b07-chip-alpha.png` | installed |

Result: 162 people × 2 layers installed and hash-verified; `commander_portraits.csv` reports 147/147 planned keys complete. T-pose front/side/back references for K-01..K-21 are delivered to `comfy-out/units/main_cast_tpose_2026-10-20/` (not in the repo).

Open for the owner: the 140 unprompted commander rows from PR #79 (authored `K-` appearance lines needed before any art; possibly a duplicate roster); commander clothing reads alike across K-25..K-162 because their appearance lines share one tunic-and-mantle template — vary the lines if more distinction is wanted.
| fp2-b08 | K-163..K-186 | `fp2-b08-full-alpha.png`, `fp2-b08-chip-alpha.png` | installed |
| fp2-b09 | K-187..K-210 | `fp2-b09-full-alpha.png`, `fp2-b09-chip-alpha.png` | installed |
| fp2-b10 | K-211..K-234 | `fp2-b10-full-alpha.png`, `fp2-b10-chip-alpha.png` | installed |
| fp2-b11 | K-235..K-258 | `fp2-b11-full-alpha.png`, `fp2-b11-chip-alpha.png` | installed |
