# The WAR ROOM's furniture

Modelled by hand in the owner's Blender (2026-10-01) against the Qwen-Image-2512
concept the owner chose (`model_wip/concept/room_qwen2512fast.png`), one object
per folder, `<name>/<name>.glb` used by `scenes/war_room/war_room.tscn`; the
`.blend` work file and its renders sit in that folder's git-ignored `model_wip/`.

| object | what | in the scene |
|---|---|---|
| `room` | stone chamber, x ±3 m, z −2.0..+3.0 (a window recess beyond), floor y −0.8, walls to 2.4, inward faces, no ceiling; a leaded window and two wall sconces | `Room/Chamber`, at the origin, casts no shadow |
| `table` | oak trestle table, top 1.8 × 1.7 m with iron clamps, z −1.0..+0.7 (the north band carries the index chart) | `Room/OakTable`, stretched 1.058× in height so its top meets the sheet's sea (y −0.001) while its feet stay on the floor |
| `candlestick` | wrought-iron, three tallow candles, ~0.42 m, origin at the base | `Room/Candlestick1..4` at the top's corners, an `OmniLight3D` and three emissive flames each, cast no shadow (their arms threw a hand across the sheet) |
| `rake` | ash croupier's rake, brass ferrule, oak head; lies flat, origin at the head's bottom centre, shaft toward +Z | `Room/Rake` on the right margin beside the sheet |
| `pennant` | 35 mm red swallowtail on a brass pin with a paper slip, foot at the origin | instanced per march order by `WarPennants` (its `model`), scaled to `war_piece_figure_mm` × `war_pennant_h_ratio` |

## Textures — Poly Haven, CC0

Embedded in `room.glb` and `table.glb` (2k; the sources in `model_wip/textures/`):

- `stone_brick_wall_001` — the walls — https://polyhaven.com/a/stone_brick_wall_001
- `weathered_planks` — the floor — https://polyhaven.com/a/weathered_planks
- `dark_wooden_planks` — the oak table (diffuse re-toned to oak) — https://polyhaven.com/a/dark_wooden_planks

`room.glb.import` and `table.glb.import` set `gltf/embedded_image_handling=2`
(Embed as Basis Universal): the 2k textures are kept in the imported scene
VRAM-compressed (BC7 on this Mac, ~5.6 MB each with mips) instead of being
extracted beside the `.glb` and imported lossless like the units' (~22 MB
each) — ~170 MB of VRAM down to ~40 MB. The extracted-image route could not be
VRAM-compressed in a committed `.import`: the glTF importer leaves a
hand-edited image `.import` alone and then never writes the image itself, so a
fresh clone would have none. The candlestick, rake and pennant still extract
theirs (small).

All three are CC0 (public domain); no attribution is required, it is given here
as a record. The leaded glass and the pennant's atlas were painted in Blender.
