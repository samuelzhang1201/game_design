# WAR ROOM — the sunlit chamber (room art D)

## Owner's words and rulings (2026-10-13)

- 审查 war room 的美术构图……我觉得房间太空旷，窗户玻璃太假了，我希望有一种阳光从玻璃射进来的感觉。
- 你是不是忘了我们还有个 information board 立在边上 — the Missive board's easel is part of the composition.
- R1 — the window moves to the **WEST wall** (左), beside the table, so the sun crosses the sheet from the left and side-lights the board at the north-east instead of backlighting it.
- R2 — the target picture is **WR-02 Qwen s954159497** ("Chart room of the staff", `assets/imagegen/room_concept_prompts.csv`, rendered by `qwen2512desk4`; git-ignored `out/split/war_room_sun/`).
- R3 — **every** piece of dressing the review listed is wanted (陈设全要): pigeonhole racks of rolled charts, a lectern with an open book, an iron-bound chest, a map chest of shallow drawers, a stone window seat with a worn cushion, a wall map or tapestry of OUR world, a floor candle stand and wall sconces, a worn rug under the table, ceiling beams, a basket of scrolls, a side table with quills and ink — and a real oak easel for the board.
- Modelling waits until the owner's Blender is free (另一个会话的骑士绑骨在用).

## The review (before)

Shots: `snapshot_screen --war-room --war-zoom 3 --war-turn 0|90|180|270`. Defects, by `taste.md`:

1. The window is a flat white emissive card with a painted lattice — a sticker, no depth, no outside (*One medium*).
2. The "window light" is a cool directional lighting every wall alike; the chamber casts no shadow, so nothing says where the light comes from. At the play zoom a warm cast reads as a filter (*Time of day is a light, never a filter*).
3. The window is 0.5 × 1.43 m behind the table with its sill below the table top: no sun could reach the sheet.
4. The room is four stone walls, a floor, one candlestick and an easel of two sticks and a board (*Every element is a crafted object, never a placeholder*).

## Prototype findings (scratch, `--war-exec`)

- A warm `DirectionalLight3D` with the room closed to it (ceiling and walls casting, the glass not) gives a sunlit patch; volumetric fog gives the beam, but the beam alone reads as haze and a fake additive beam mesh reads as a brown sticker — dropped.
- **The lattice's shadow is what says "sun through glass"**: a shadow-only quad cut by the lead texture (alpha scissor) throws the diamond cames on whatever the sun reaches. Fog stays faint and soft-edged, a support.
- Glass: unshaded, the panes bright and overexposed with an uneven greenish crown-glass tint, the cames dark; the outside seen blurred through it. Glow (bloom) at a threshold the board's panel never reaches.

## Design

### Room (Blender, `tools/war_room/blender/wr_room.py` rebuilt)

- Same footprint (x ±3, z −2.0..+3.0 inside, floor y −0.8, walls to 2.4), now **with a ceiling** of planks on oak beams (the camera's highest look never sees it; it closes the room to the sun).
- **West wall**: a paired lancet window under one arch, ~1.3 m wide × 2.2 m tall, in a deep splayed reveal (0.6–0.9 m), sill ~0.05 below the table top (y ≈ −0.05), a stone window seat below it; the glazing a SEPARATE object (`glass`, its own surface `WR_window`) so the chamber can cast shadows and the glass not. Stone stained at the foot.
- **North wall** (the far wall at the opening): closed; the wall map hangs there.
- The old north recess goes.

### Dressing (each its own `assets/3D/war_room/<name>/<name>.glb`, game budget, references `assets/imagegen/room_prop_prompts.csv` WP-01..WP-13)

| object | where (game axes) |
|---|---|
| `rack` ×2 pigeonholes of rolled charts and sealed letters | along the south and east walls, clear of the easel |
| `lectern` with an open ledger (no legible writing) | south-west, by the window |
| `map_chest` plan chest | east wall, under the easel's side |
| `strongbox` iron-bound chest | south-east corner |
| `window_seat` cushion | on the window seat |
| `floor_candle` iron stand | north-east, a warm accent beside the board |
| `sconce` ×2 | north wall, flanking the wall map |
| `rug` | under the table |
| `scroll_basket` | by the rack |
| `side_table` quills, inkwell, wax, blank papers | west, under the window's light |
| `easel` oak, three legs, ledge | replaces `%Easel`'s box legs; `%BoardPanel` keeps its node, size and pick |
| wall map | north wall: a framed quad carrying the index chart's own texture (the pack's world, no grid), on a rod |

### Light (Godot, `scenes/war_room/war_room.tscn` through the editor)

- `%Sun` DirectionalLight3D: warm, ~35–45° high, from the west, so the lattice falls across about a third of the sheet and the board is side-lit; the old cool `Window` light becomes a faint cool fill without shadow.
- `war_window_glass.tres` + `.gdshader` (the panes), `war_window_lattice.tres` + `.gdshader` (the shadow-only lattice quad).
- Environment: glow on; volumetric fog faint, sun only (candles 0).
- Tier columns in `graphics_quality.csv`: `war_sun_shadows`, `war_fog` (`WarRoomLights.apply_tier`); values set from `scenes/tools/war_room/bench.tscn`.
- The candle stays the key light for the relief at night-dark corners; its colour and placement re-checked against the sun.

### Checks

- `visual-review` at the opening, mid and far zooms, all four headings, and `--war-board` (the board readable, no came shadow across it, no bloom on it).
- The bench at every tier against `bench_budget_ms`.
- `tests/war_room` run locally.
