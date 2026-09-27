# Regiment pieces, round 2 — handover (2026-09-27)

A session handover. The previous session ran out of room mid-way through
the owner's 13-point request below; this file is everything the next
session needs. Reply to the owner in **Chinese** (memory: reply-in-chinese).

## 0. What came before (done, committed, pushed: `d5ed1c7` on main)

- The **cavalry** is rebuilt from two CC0 museum scans (Cleveland Museum of
  Art 1964.88 knight + Hunt Museum horse statue) dressed as design
  "Z-Image C": `tools/units3d/cavalry_scan.py` → `assets/units3d/cavalry.glb`
  (18,444 tris, one 2048 atlas with albedo/normal/MR, 43 bones, actions
  GARRISON / MARCH / ATTACK). Sources in `assets/units3d/ai_src/cc0/`
  (git-ignored, `.gdignore`); openable `assets/units3d/ai_src/cc0/cavalry_knight.blend`
  (`CAV_BLEND=<path>` saves it). The animations are
  `tools/units3d/model_cavalry.py`'s `actions(arm)` (world-axis pose dicts
  through `make_units.apply_pose`), reused bone for bone.
- **No bases** on any piece (owner: 撤除所有底座) — `strip_base.py` cut the
  infantry's; `Map3DUnits.stand_extent` seats a piece on its own extent.
- `data/army_art.csv`: `stand_deg` (standing horse 55° off square — nose-on
  it was a sliver) and `size` (cavalry/royal 1.5 — **the owner now says 1.5
  is wrong, see item 7**).
- Tools: `tools/units3d/shoot_glb.py GLB OUT rest|close|feet|garrison|march|attack`
  photographs a built glb (headless Blender). In-game shots:
  `Godot --path . res://tools/snapshot_screen.tscn -- --out X.png --screen root --zoom3d M --at3d x,y --resolution 2560x1600`
  (run it with a 240 s kill guard; `--layer military` must be DROPPED once
  the tab is gone). The player's cavalry regiment "2nd Somerlis" is at pack
  (1121.94, 491.69), an infantry one "5th Penkburgh" at (1208.26, 488.19).
- After any Godot import or snapshot: `git checkout project.godot` (Godot
  rewrites the renderer lines away). Tests: `./run_tests.sh` → expect
  "Errors 2" (gdai plugin) and all passing (was 1124 passing / 2 pending).
- Visual changes follow `.claude/skills/visual-review/` (2–3 variants, crop
  sheets with `contact_sheet.py`, an independent critic subagent) and new
  owner rulings go into `taste.md`.

## 1. The owner's request (2026-09-27), verbatim

> 骑兵兵人比例还是有问题。
> 1. 游戏初始默认视角高度为25km，focus在玩家控制的身份
> 2. 去除military tab，兵人unit永远显示
> 3. menu中新增一个dev模式，on/off。button，打开后可以显示世界全部兵人
> 4. 当点击完兵人行进路线后，会出现commit/ cancel的选项。
> 5. 兵人行进路线只能在暂停模式下选择，时间流逝的时候不可以操作
> 6. 行进路线commit后，再次点击终点可以edit路线或者cancel操作。
> 7. 兵人比例太大了，我之前说的我1.5倍不合适，似乎应该更小一点而非更大。并且随着镜头的缩放，兵人大小没有变化这是不对的，拉远后在50km的高度后，兵人缩减成为一个方形色块，并且可以点击查看状态。
> 8. 兵人行进的动作非常突兀，马的腿移动的步幅和它实际移动的距离不符，请优化。
> 9. 兵人需要增加阴影
> 10. 随着时间的流逝，光照光源从西向东缓慢变化。
> 11. 点击一个省后，显示的hightlight的省边界非常丑，一个黄色实心线，不需要这个，它本身就是一个黑色的虚线，你highlight那个黑色虚线即可。
> 12. 每个上方都显示红色和黄色两条bar，红色是健康度，黄色是战略补给数。
> 13. 骑兵兵人驻扎效果应该为骑士把盾牌竖起挡在身前，长矛改为指向向前，马匹也轻微晃动一下脖颈。

### The owner's answers to the four questions asked

| question | answer |
|---|---|
| Piece size at the default 25 km view | **~20 px**, small but readable; grows as the camera comes in, **capped** close in |
| What the RED bar shows | **综合战备** — the composite readiness (`ArmySystem.readiness_permille`: arm/supply/morale/training weighted) |
| Sun sweep period | **one game day** — "但是一个游戏日的时间流逝速度需要放缓很多了" (make the day much slower) |
| Where "The Host" goes once the tab is gone | **opened by clicking a piece**: the regiment's card gets an entry to the whole host |

### Interpretations the previous session settled (tell the owner if asked)

- "身份" in item 1 read as **省份**: the view opens on the province the
  player CONTROLS (`MapManors.controlled_provinces`, preferring the one with
  the capital), at `provinces.csv` `center_x/center_y`.
- **"km" = the camera distance in world metres / 1000**, the same measure as
  the owner's earlier "最大zoom out 150km" = `map3d_zoom_max_m` 150000. So
  25 km = 25000 (was `map3d_zoom_start_m` 24000) and 50 km = 50000.
- Size rule derived from that (item 7): the piece's SCREEN height
  `px(d) = min(max_px, ref_px × ref_d / d)` with ref_px 20 at ref_d 25000,
  max_px ≈ 40 design px (close in that is ~14 m of world at 400 m — the
  2026-09-24 "a little under a cottage" ruling holds), and **past 50000 m
  the piece is replaced by a flat square counter** (the existing
  `ArmyCounters` drawing fleets already use), clickable → the regiment's
  card. Cavalry `size` back to **1.0** (all arms 1.0). New balance keys, e.g.
  `map3d_unit_ref_px`, `map3d_unit_ref_view_m`, `map3d_unit_max_px`,
  `map3d_unit_counter_view_m`; the old `map3d_unit_px` / `_min_h_m` /
  `_max_h_m` rule in `Map3DUnits.height_m` is replaced (update its test).

## 2. Progress

### Batch 1 — WRITTEN, NOT YET TESTED, NOT COMMITTED

Working tree (12 files): `scripts/ui/{bottom_bar,game_root,map_detail_panel,military_panel,court_screen,conversation_scene}.gd`,
`scripts/map3d/{map3d_view,map3d_context,map3d_layer_units,map3d_hud_armies}.gd`,
`tests/ui/test_military_panel.gd`, `tests/map3d/test_map3d_military.gd`.

- **Item 2** — MILITARY removed from `BottomBar.TABS`/`TOGGLES` and from
  `GameRoot._on_bottom_tab`; `_sync_map_view` passes `military = true`
  always; `Map3DView._military` defaults true. `GameRoot.set_army_view(on)`
  is kept as the switch for the host PANEL only.
- **Host panel** — `MapDetailPanel` has `signal host_requested` and, on an
  army card, a `TheHost` button ("The Host — all regiments");
  `MilitaryPanel` has `signal closed` and a `Close` "×" button in a header
  row; both screens connect them (show_card({}) + set_military_view(true) /
  set_military_view(false)).
- **Item 3** — pause menu `DevMode` button ("Dev mode: On/Off"),
  `GameRoot.set_dev_mode / dev_mode / _apply_dev_mode` (settings.cfg
  `[game] dev_mode`, applied on every `_sync_map_view`);
  `Map3DView.set_dev_mode / dev_mode`; `Map3DContext.dev` and
  `Map3DContext.regiments()` (all of `world_table("military","regiments")`
  in dev mode, else the player's) — `Map3DLayerUnits.refresh` and both loops
  in `Map3DHudArmies` use it. Foreign regiments have no state
  (`ArmySystem.state_of` → {}); `order_of`/`destination_of`/`heading_of`
  already fall back safely; bars must use `ArmySystem.starting_state` for them.
- **Item 1 (half)** — `Map3DContext.home()` now returns the controlled
  province's centre. `map3d_zoom_start_m` is still 24000 → set 25000.

**First thing to do:** run `./run_tests.sh`, fix what breaks (likely: other
tests that pressed MILITARY or relied on `military()` false by default —
`grep -rn "set_military\|military()" tests`; `test_map3d_heights.gd:255`
toggles it; the pinned API test may list new methods), then shoot the court
screen and the pause menu to see the host button, the × and the Dev switch.

### Batches 2–6 — TO DO, in this order

**Batch 2 — camera & size (items 1, 7).**
- `map3d_zoom_start_m` 25000.
- Replace `Map3DUnits.height_m`/`scale_for` with the rule in §1 (keep `size`
  param; set `army_art.csv` cavalry/royal `size` to 1.0; keep `stand_deg`).
- Past `map3d_unit_counter_view_m` (50000, camera distance) hide the 3D
  pieces and draw every regiment as the `ArmyCounters` square (it already
  draws the fleet this way; `Map3DHudArmies._cut` falls back to the ground
  point when a regiment has no top). Picking: `Map3DPicker.pick_at` already
  picks army counters → card.
- Test the new size rule with hand-computed values (CLAUDE.md convention).

**Batch 3 — bars and the selection line (items 12, 11).**
- Over every piece/counter: a RED bar = `readiness_permille(...)`/1000 and a
  YELLOW bar = supplies months / `army_speed_supply_full_months` (clamped
  0..1), drawn by `Map3DHudArmies` just above the headcount chip
  (`ArmyCounters.draw` / layout); colours and sizes as data
  (`political_palette.csv` / `balance.csv`).
- Province highlight: `Map3DSelection.redraw` draws a SOLID GOLD line
  (`map3d_selection`, `map3d_selection_width_px` 4). Replace for provinces
  with a DASHED line in the seam's own ink at full opacity and a heavier
  width, reusing the seam's dash/gap keys
  (`Map3DLineStyle.dashed(seam, Color(seam,0), width_key, "map3d_seam_dash_px", "map3d_seam_gap_px", Map3DPriority.SELECTION)`);
  the manor outline may keep its gold (only provinces were asked about).

**Batch 4 — marching orders (items 4, 5, 6).** Flow today: a left click on a
piece → `Map3DSelection.click` → `army_menu_requested` → `ArmyOrderMenu`
(PopupMenu, rows `data/army_orders.csv`); MARCH arms `Map3DView.aiming`,
the next ground click (`ground_clicked`) runs `ARMY_MARCH` at once.
- Item 5: MARCH (and route editing) only while `Game.clock_speed <= 0`; the
  row is disabled with a reason while time runs.
- Item 4: the ground click no longer runs the order: it holds the pending
  destination (keep the aim ruler drawn to it) and pops a small Commit /
  Cancel menu there; Commit → `Game.try_execute(ARMY_MARCH)`, Cancel → drop.
- Item 6: the committed route's end ring (`Map3DHudArmies._draw_routes`) is
  clickable (add a "route" pick kind to `Map3DPicker`); on a paused clock it
  opens Edit route / Cancel march — Edit re-arms the aim for that regiment
  (then Commit/Cancel again), Cancel issues `ARMY_GARRISON`.
- Verify with real input (memory: verify-ui-through-real-input; PopupMenu
  hides BEFORE id_pressed). `snapshot_screen --march3d fx,fy
  [--march-confirm]` drives the old flow and must be updated.

**Batch 5 — motion, shadows, light, day length (items 8, 9, 10).**
- Day length: `time_day_seconds` 1.0 → ~6.0 (owner: much slower); the news
  and any test that assumes 1 s must follow.
- Item 8: the MARCH clip's playback must follow ground speed:
  `AnimationPlayer.speed_scale = v_world / (stride_m × k) × clip_seconds`,
  clamped (e.g. 0.4–3.0), with `stride_m` per model (measure it: foot sweep
  in stance / 0.6 stance share — about 1.1 model-m for the horse; add a
  column to `army_art.csv` or the build's `units3d.json`). Blend MARCH ↔
  GARRISON (`anim.play(name, 0.3)`) so the switch is not a snap.
- Item 9: `Map3DLayerUnits._piece_of` sets `cast_shadow` OFF — turn it ON.
- Item 10: the sun (`Map3DEnvironment.apply_sun`, balance
  `map3d_sun_yaw_deg` -45 / `map3d_sun_pitch_deg` -35) sweeps from WEST to
  EAST over each game day (owner's words), low at both ends, driven by the
  day's progress — GameRoot owns the clock accumulator (`_clock_acc` /
  `time_day_seconds`), so expose the day's fraction (e.g. a
  `Game.day_fraction()` or a `ctx.day_fraction_fn`) and step it in
  `Map3DView._process`; still while paused. Only `map3d_view.gd` may touch
  `Game` under `scripts/map3d/` (a test scans).

**Batch 6 — cavalry GARRISON pose (item 13).** Edit
`model_cavalry.actions()`' `garrison` keys (they are shared by
`cavalry_scan.py`): the knight holds the SHIELD up in front of him
(left arm forward and in: `upperarm_l`/`forearm_l`/`shield` bones), the
LANCE pointing forward (the `lance` bone ~ -80° about world X as in
ATTACK's couch, arm `upperarm_r`/`forearm_r` lowered to hold it), and the
horse's neck swaying gently (`neck_1`/`neck_2`/`head_h` small x/z turns over
the 121-frame loop). Rebuild:
`CAV_BLEND=assets/units3d/ai_src/cc0/cavalry_knight.blend blender -b --factory-startup --python tools/units3d/cavalry_scan.py`,
check with `shoot_glb.py ... garrison`, reimport, test, shoot in game.

## 3. Wrap-up when all six are done

Full test suite; in-game shots near/far with a critic pass; update
CLAUDE.md (bottom bar list no longer has MILITARY; the pieces' size rule;
dev mode; the march UX; the sun; the day length), `taste.md` for the new
rulings (size by zoom and the 50 km counter; the selection is the seam
emphasised, not gold), the memories `units3d-military-units.md` and this
file's status; then report to the owner in Chinese and ask before
committing.
