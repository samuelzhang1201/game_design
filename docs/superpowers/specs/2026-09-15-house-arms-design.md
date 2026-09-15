# House arms — every house and kingdom wears a generated coat of arms

Owner request 2026-09-15: 根据地图 json 家族文件，生成所有相应的家族徽章，并应用到游戏中去.

## Decisions (owner, 2026-09-15)

- **Source of a house's arms**: the Azgaar `coa` of the house's SEAT TOWN —
  the capital burg of the house's first province (by `province_id`). A house
  is a family name bound to provinces by `house_bindings.csv`, else named
  after its province's capital (`MapObjects.house_name_of`), so the seat town
  is the natural source. A seat whose burg has no `coa` falls back to the
  province's `coa`. Kingdoms wear their state's `coa`.
- **Rendering**: NOT a port of Azgaar's SVG renderer. 142 of the 263 charges
  the pack uses are WappenWiki art under CC BY-NC-SA (84 of the ~206 arms
  needed), so the arms are **generated through the local ComfyUI with Flux.2
  klein 4B base** (Apache-2.0), the `coa` translated into the prompt's
  subject. Flux is faithful to fields, divisions, bands and single charges,
  and only approximate on furs and many-charge arms; that is accepted.
- **Where the arms appear**: the top bar (the lord's purse crest, and the
  flag beside the date), the map detail card's shield (a manor: its holding
  house; a province: its house; a kingdom: its state arms), a small crest
  before each row's house in the Manor Master, and the audience window's name
  plate (the character's family). The main menu's family-flag symbols are
  replaced by a preview of the crown's arms.
- **The crown's arms never change with the family name**: the crown resolves
  through `player_setup.house_was` (the bound royal family) to its seat.
- Generation is asked for batch by batch ([ask before queuing]): six samples
  first, then the full run.

## Pipeline (assets/flux, stdlib Python)

1. `arms_prompts.py` reads the pack JSON (`assets/maps/<id>/*Full*.json`) and
   the pack tables (`political/provinces.csv`, `kingdoms.csv`,
   `house_bindings.csv`) and writes
   - `arms_prompts.csv` — the `prompts.csv` schema, one row per arms, ids
     `A-001`.. in a fixed order (kingdoms by `state_id`, then seats by
     `province_id`), canvas `C-ARMS`, subject = the blazon in plain words;
   - `arms_art.csv` — `art_id,key,source,house` with key `kingdom_<code>` or
     `seat_<capital_burg>`; `source` says which `coa` was read.
   Houses that share a seat (one family over several provinces) produce ONE
   row. The translation is a fixed dictionary: tinctures to colour words,
   shield shapes, divisions and ordinaries to plain geometry, charges from
   camelCase to words with overrides for heraldic terms, position letters to
   count and placement from the heater position table, patterns
   (`chequy-azure-argent`) to a described texture.
2. `generate.py --prompts-file arms_prompts.csv --style-file STYLE_CORE_arms.txt`
   — `--prompts-file` reads another table of the same schema; chapter `A`
   files under `out/arms/`. `[C-ARMS]` is a library §1.3 canvas fragment
   (a single shield, flat and face-on, pure white ground, centred, no helm,
   crest, mantling, supporters or text), 1024×1024.
3. `STYLE_CORE_arms.txt` + `NEGATIVE_arms.txt`: painted heraldry — flat
   saturated tinctures, crisp dark outlines, a thin gilded rim, slight
   embossed relief (after Crusader Kings III). The v2 core's muted earthen
   palette would fight the tinctures.
4. `post.py --tier icon` (BiRefNet cut-out), then
   `install_map_art.py arms` trims each to its alpha box and fits it into
   256 px — the largest use is the menu preview at ~80 design px × ~3 window
   scale — as `assets/arms/<pack>/<key>.png`, colour kept.

## Runtime

- `scripts/engine/house_arms.gd` (`HouseArms`, pure, static):
  - `seat_province(repo, state, family) -> String` — the crown
    (`MapManors.crown(state)`) maps to `player_setup.house_was` first; then
    the lowest-`province_id` province whose `house_name_of` is the family;
    "" when the family holds no province.
  - `key_of_house(repo, state, family)` → `seat_<capital_burg>` or "".
  - `key_of_kingdom(code)` → `kingdom_<code>`.
  - `path_of(repo, key)` → `res://assets/arms/<pack id>/<key>.png`.
  - `texture_of_house(...)` / `texture_of_kingdom(...)` — loaded once and
    cached per key; null when the file is missing.
- `HeraldicShield.set_texture(tex: Texture2D)`: draws the arms fitted into
  its rect when set, else the existing coloured shield with an initial, so a
  house with no seat (a courtier's surname) still shows something.
- Wiring: `TopBar.refresh` (crest + the date flag), `MapDetailPanel` (card
  kind decides house or kingdom), `ManorMasterPanel` rows, the conversation
  scene's name plate, `MainMenu` setup (the flag row becomes the arms
  preview; `player_setup.flag` stays readable in old saves and is unused).

## Tests (GUT)

- every house of the pack (`house_name_of` over all provinces, plus the
  bound families) and every kingdom resolves a key whose file exists;
- the crown keeps its arms after `apply_player_setup` renames the family;
- a family with no province resolves no texture and the shield keeps its
  initial;
- the top bar crest, the detail card shield, a Manor Master row and the name
  plate carry a texture for a seated house.

## Out of scope

Arms on the map itself (the MANORS layer), regenerating arms when a house
gains or loses its seat, and the Azgaar SVG renderer.
