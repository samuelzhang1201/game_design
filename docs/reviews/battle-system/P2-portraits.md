# P2 commander portrait production evidence

Status: production in progress. `assets/imagegen/commander_portraits.csv` is derived from actual player/raider commander rows, including reserves. Other realms are excluded. At this checkpoint 147 keys are required: 6 existing complete pairs reused, 15 new complete pairs installed, 126 still missing. A generated source is not an installed or accepted portrait.

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

The initial K25–36 batch used one shared seed and produced overly similar faces/builds. It is rejected as a batch, not counted complete. Changing seeds alone gave insufficient separation. Revised explicit bone structure, age, hairstyle, complexion and body shape plus independent seeds produced approved K25 (205202), K29 (292802), K35 (354502), reviewed together in `batch01-identity-revised.png`. The other nine first-batch identities were regenerated and reviewed by the same method. K28 still contained a zipper-like neck closure and was redrawn again (3516345252) with explicit cloth ties; the revised source passes. All twelve full sources, dedicated busts and transparent tiers passed batch inspection and are installed. `batch01-chip-alpha.png` and `batch01-full-alpha.png` show every installed pair on black and white. The 96px busts use simpler cloth shading than the full figures; faces and hair remain clear and no opaque paper or head-crop defects remain. Batch02 (K37–48) is generating. Later batches remain subject to sheet inspection for identity, period clothing, anatomy, crop and alpha before installation.

## Tool verification

Three-digit K IDs are supported by the library parser and post-process ID parser. `/tmp/p2-art-id-red.log` reproduced K100 omission/truncation; `/tmp/p2-art-id-green.log` verifies K22/K100/K162 and all actual eligible mappings. The cast installer now selects exact `<art_id>.png`: `/tmp/p2-cast-prefix-red.log` reproduced K-10 selecting K-109, and `/tmp/p2-cast-prefix-green.log` exercises the installer with all three neighboring IDs present and verifies the right bytes were installed. Python compilation and `git diff --check` pass. No engine or test files were modified for portrait production.
