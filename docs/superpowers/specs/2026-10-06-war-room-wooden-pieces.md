# WAR ROOM wooden pieces (2026-10-06)

The crown's regiments on the war table become solid carved-wood pieces on a
round lacquered plinth, replacing the painted-tin figures on square bases.

## The owner's words

- 我要生成固态的军事单位棋子。均有木质底座，分为骑兵，步兵，国王精锐，弓箭手，射石炮，投石机，用于摆放在地图上。风格做旧，不要完美无瑕那种，木头材质，适配war room地图。木质底座呈下宽上窄的底座，刷亮色木漆，外圈有一圈金属环套着。
- Picks: direction B for every piece (dark old oak, unpainted); the trebuchet redrawn from the owner's reference (A-frame post, hanging stone-ball counterweight, sling, bucket); the bombard without the candles.
- 底座漆色按国家颜色 — the plinth's lacquer takes the realm's colour.
- One piece per regiment (一团一枚): the strength stays on the paper tag.
- Artillery is drawn as the TREBUCHET (统一用投石机); the bombard is kept, unused.
- The royal regiment (`MapObjects.royal_regiment`) stands as the royal piece, as on the 3D map.
- A fleet keeps its flat tin token on its base until a wooden ship is made.

## Art

| step | where |
| --- | --- |
| references | `assets/imagegen/war_piece_prompts.csv` W-41..W-59 (`STYLE_CORE_war_piece.txt`, canvas `[C-WARPIECE]`), Qwen-Image-2512; the picks in each piece's `model_wip/REF_piece_<arm>.png` |
| Tripo | the owner's paid plan; the sources in `assets/3D/war_room/piece_<arm>/model_wip/tripo/` |
| processing | `tools/war_room/blender/wr_pieces.py` in the owner's Blender: turned to face game −Z, the plinth's foot centred on the origin and scaled to a diameter of 1, collapsed to 15k triangles on Tripo's UVs, maps cut to 1024 |
| lacquer | `piece_<arm>_lacquer.png`, read off the albedo's blue: R the lacquer's share, G its shade (V over twice its mean) |

## Game

- `scenes/war_room/wood_piece.gdshader`: the albedo, ORM and normal maps, the
  lacquer mask; `instance uniform lacquer` is the realm's colour
  (`MapPalette.color_of(...).darkened(war_base_darken)`), so every piece of
  one arm shares one material.
- Each piece is a scene `scenes/models/war_room/piece_<arm>.tscn` inheriting
  its `.glb`, its surface wearing `scenes/war_room/materials/piece_<arm>.tres`.
  `GameArt.WAR_PIECES` (`assets/3D/war_room/war_pieces.tres`) maps the
  ART piece key (`MapObjects.army_piece`) to the scene: infantry, archers,
  cavalry, royal, artillery → trebuchet. A fleet has no entry.
- `WarPieces` builds a land piece as `Piece` (the scene, scaled so the plinth
  is `war_piece_plinth_mm` across, turned whole to its heading) and `Tag`;
  its pick box and seat are the plinth's square. A piece is rebuilt only when
  its art key changes.
