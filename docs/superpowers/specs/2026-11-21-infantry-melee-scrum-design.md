# Infantry melee: impact and a mixed fight

Owner request (2026-11-21): 我还是希望交战的时候能够有碰撞感。当一方的兵人attack时，对方的动画应该是被hit的动画啊，并且双方交战的时候，双方兵人应该在战场上混在一起，而不是仅仅站着自己的方阵里。同时还要考虑到性能，请参考行业best practice，如何处理大量兵人的碰撞动作？

Owner picks (2026-11-21): how far the sides mix — option 3, the middle way (both ranks fight, figures leave their slots and cross the line to find a foe, forming one mixed fighting area; each unit's standard, centre and engine position stay put). How to build it — approach A, a view-only melee layer with staged impact.

Builds on `docs/superpowers/specs/2026-11-16-infantry-duel-animation-design.md` (paired front-rank duels and falls, landed in #328, #333, #335) and its guide `scripts/map3d/guide/battle_duels.md`. The purpose stands as the owner ruled it then: 主要是要临场感，可以做成好看但和数字无关的表演 — spectacle for presence, not a readout of who is winning.

## Intent

Watched up close, a field battle should look like a fight the two sides are IN: men leave their ranks, close with the enemy among the enemy, and every blow lands on someone. When a man swings, the man in front of him is hit, staggers, or catches it on his shield with a jolt you can feel. The map must still read: you can tell the two sides apart, see where each unit stands and pick it, and the frame rate holds.

## What exists today

- A battle unit is ONE fixed block of 10 figures, 5 files × 2 ranks (owner ruling R-H, 2026-11-13, #312), drawn by `Map3DBattleGroups` from saved engine rows `{slot, count, role front/reserve, x_m, y_m}`; figures are camera-scaled miniatures, so distances in the view are measured in FIGURE HEIGHTS (the duel keys do this), not metres. The engine owns those rows (no-overlap clearance, cavalry charge, saves); the view may only add offsets (`duel_offset` / `duel_yaw` on a group child, added in `Map3DBattleGroups._target`).
- Duels (`Map3DDuel`, `Map3DDuelDriver`): front figures of the two sides pair along the front, step in to `map3d_duel_close_h` (1 height) apart and trade turns: strike → BLOCK (70%) or HIT (`map3d_duel_hit` 0.3) → guard pause → the other strikes; strike and reply are timed so their measured `contact` shares meet. There is no impact feedback: no pause, no knock-back, no spark, no sound. Unpaired front figures keep their piece's attack chain and swing at the air. Reserves stand guard.
- Falls (`Map3DFall`): a lost group's fall is shown on a duellist (DEATH, hold, fade); the removed tail figure walks into its place.
- Installed infantry clips (`assets/3D/units/infantry/infantry.glb`, #331 + #335): MARCH, GARRISON, STANDBY, DEFEND, ATTACK, SLASH, ATTACK_VAR1, ATTACK_2, SLASH_2, SLASH_3, BLOCK..BLOCK_4, HIT..HIT_3, DEATH, DEATH_2, PIVOT_LEFT/RIGHT. ADVANCE (combat walk) is in the source `.blend` but not shipped.
- In flight, separate PR from the duel clips session (`local_5e28a286…`): the duel step-in walks with paced feet instead of gliding. This design depends on that landing first and reuses its paced walk.
- Both sides wear the same green tunic; a mixed fight is unreadable until that changes.
- Each figure has its own skinned `AnimationPlayer` (not a MultiMesh). A field battle shows tens of figures, not thousands. Performance gate: 60 fps per graphics tier, `tools/map3d/bench.gd` against each tier's `bench_budget_ms`.

## Goals

1. **Sides are told apart at a glance.** Each figure wears its realm's colour, so a mixed fight reads as two sides.
2. **Every blow lands.** A strike is answered by its target at the contact instant: mostly a HIT, the rest a BLOCK. Either way the contact is felt: both figures freeze for a hit-stop of a few frames, the struck figure is knocked back a little, a shield block jolts, and a small burst of sparks or dust shows at the meeting point.
3. **The sides mix.** When two infantry units fight, both ranks of each leave their slots and move into one shared fighting area between the units, across the line, find a foe and fight there; figures stand among enemies, not in two facing lines. When the fight ends (battle over, a unit withdraws or retreats) they walk back to their slots.
4. **No one fights air.** With unequal numbers a figure without a foe joins another's foe (two on one, taking turns) or waits its moment at the edge; it never swings at nothing.
5. **The unit stays readable.** The standard bearer (the figure carrying the national standard, today `groups[0]`'s) and the unit's centre stay at the block; the selection glow, picks, orders and the engine's positions are unchanged in meaning.
6. **Falls still work** in the mixed fight: the faller drops where it fights; the replacement walks in from its slot.
7. **The frame rate holds:** every tier still meets its bench budget with a field battle in view.

## Non-goals

- Archers, cavalry, artillery and mixed-arm scrums (infantry against infantry first, as with the duels; a cavalry charge already has its own engine impact).
- Any engine, save or RNG change; the scrum is view-only. Losses, positions and who wins stay the engine's.
- Real physics: no collision bodies, ragdolls or weapon hit detection.
- Blood, gore, dismemberment.
- Camera shake (this is a strategy map; the camera is the player's).
- The WAR ROOM's wooden pieces.

## Anti-goals (a failure even if it technically works)

- You can no longer tell the sides apart, or which unit is where.
- Figures pass through each other or through a foe's body in the scrum.
- Everyone moves, strikes or freezes in unison.
- Feet slide: a figure crossing into the fighting area glides instead of walking.
- A blow lands on nobody, or a figure reacts to a blow nobody struck.
- Any tier drops below its bench budget with a battle in view.
- The engine's positions, losses or picks change because of the show.

## Constraints

- View-only: no state, save field or RNG draw; hashing as the duels do (`Map3DMarchLag.unit`). `scripts/map3d/` never reads `Game`.
- Distances in figure heights (camera-scaled miniatures); every number is a key in `data/screens/map3d/balance.csv` or a column in `army_art.csv`, never a constant.
- The look (realm tint material, spark/dust particle scene) is authored in the editor (`.tscn` / `.tres`), never built in code; the colour itself comes from the realm's existing colour data.
- `Map3DLayerUnits` is at its 500-line shape cap; new code goes in its own files. Edits to scripts pinned by `Map3DRoyalCarrierSource._SOURCES` need a repin; the locomotion certificates hash `army_art.csv` and `balance.csv` (evidence, re-issue when changed).
- Each step is its own PR, its own visual review in a real window (motion judged from a `--write-movie` recording), its own hand-computed tests.
- This supersedes owner ruling R-H (one compact block) **while two infantry units are in melee only**; out of melee the block stands as ruled.

## Approaches considered

- **A. View-only melee layer with staged impact (picked).** Figures get view offsets into a shared fighting area, keep apart by a cheap separation pass, pair across it, and every blow is a matched pair of clips timed to their contact share, with hit-stop, knock-back and a particle burst. The industry's way: mass-battle games stage contact with matched animations and feedback rather than simulate it. Costs: the drawn position differs from the engine's row while fighting.
- **B. Move the engine's rows.** Exact agreement between view and data, but touches clearance, cavalry charge, save migration and the locomotion certificates; several times the work for no more presence than A.
- **C. Real physics** (collision capsules, weapon sweeps, reactions on a real hit). Unpredictable (blows miss), expensive, and wrong at camera-scaled sizes.

## How (as decided)

**Steps, in order, each a PR:**

1. **Realm colours on the figures.** The infantry's tunic (the mask the mail-calming pass already authored, or a new tunic mask) takes the realm's colour through a per-instance shader parameter on the figure's material; the colour comes from the realm's existing colour data. Every arm that shares the material follows. Visual review for the look; the owner rules on it.
2. **Impact on today's pairs.** Raise the HIT share (`map3d_duel_hit`) so a strike is usually taken; add hit-stop (both figures of the pair at `speed_scale` 0 for `map3d_melee_hitstop_s` at contact), a knock-back of the struck figure (a short eased view offset away from the striker, `map3d_melee_knock_h`, then back), a shield jolt on BLOCK (the BLOCK clip's own, or the same knock-back smaller), and a pooled one-shot particle burst at the meeting point (spark on a block, dust on a hit), its look a scene authored in the editor. Unpaired figures join a pair two on one (goal 4).
3. **The mixed fight.** When two infantry units fight (the battle's first round has passed, as the duels require), every figure but the standard bearer gets a target inside a shared fighting area between the two blocks: an area spanning the facing fronts, `map3d_melee_depth_h` deep across the line, each figure's target hashed inside it and pulled toward the foe it pairs with. Figures walk there with the paced combat walk from the in-flight step-in fix, keep `map3d_melee_space_h` apart from every other figure by a separation pass (push apart overlapping neighbours each frame, bounded steps), face their foe, and duel as now. Pairing is across the area (nearest free foe), not along a front. Battle over, withdrawal or retreat: they walk back to their slots. Falls as now; the replacement walks in from its slot.
4. **Sound** (owner 2026-11-22: with sound). A clash on a block and a thud on a hit, one-shots on the pattern of `Map3DUnitSound`/`Map3DUnitSettle` (camera-distance loudness, a cap on voices), started so they land on the contact instant.

**Performance (industry practice applied at this game's scale):**

- The cost is the skinned animation per figure, not collision. Animation level of detail: figures far from the camera or off-screen update their animation at a lower rate (or stop) and skip the impact extras; only figures near the camera get hit-stop, knock-back and particles.
- Separation is a per-battle pass over that battle's figures (tens); a uniform grid only if a battle exceeds a threshold key.
- Particle bursts come from a fixed pool; a cap on simultaneous bursts and sounds.
- Thousands of figures would call for vertex-animation textures with GPU instancing (the large-battle simulators' way); not needed at tens, not in scope.
- Step 3 is gated by the bench: a field battle in view at each tier's `bench_size`, within its `bench_budget_ms`; a battle mode for the bench if it has none.

## Calls made in writing this up (the owner may overrule each)

- **Picks and the glow follow the drawn figures.** In the scrum a unit's pick box stays the union of its drawn figures, and a click on overlapping boxes picks the figure under the pointer nearest the camera (a per-figure hit test in the picker). The selection glow lies under each of the selected unit's figures where it fights, so a selected unit's men are lit inside the crowd: that is how two of the player's own units in one scrum are told apart. The standard bearer and its glow stay at the block.
- **One fighting area per battle.** A battle with several units a side forms ONE area spanning the opposed infantry of the whole battle (`att` against `def`). An infantry unit scrums even when its battle also holds other arms; archers, cavalry and artillery keep today's behaviour in their blocks and never enter the area. Axemen and heavy infantry scrum as infantry when their row names duel clips.
- **Colour scope.** Step 1 tints the infantry model (and the arms sharing `infantry.tscn`) by a tunic mask exported from the infantry pipeline's class mask (`body_class.npy`) as a texture, read by a new shader material for the map figure only; the WAR ROOM's tin (`WarPieces`) and folio ink (`WarInkFigure`) keep their own untinted look. Other models (heavy infantry's plate, archers, cavalry) get a mask when their own art is next worked; until then they keep their colour. The look is ruled by the owner in visual review.
- **The walk.** Step 3 waits for the step-in walk fix (branch `claude/duel-step-in-walk`, in flight) and extends its paced walk to longer, turning walks in and out of the area; separation pushes are folded into the walk's target, not applied to the figure directly, so the feet stay paced.

## Left to the builder

- The exact shape of the fighting area (rectangle across the fronts, ellipse, the hull of both blocks) and how targets are spread so the crowd looks natural.
- The separation algorithm's details and its step bound.
- How knock-back and hit-stop are blended with the clips (offset curve, which frames freeze).
- Which of BLOCK..BLOCK_4 / HIT..HIT_3 read best as reactions; whether to ship ADVANCE for the walk-in (the step-in fix decides).
- The particle burst's look (through visual review) and pool size.
- First values of every new key, measured in a real window.

## Owner rulings on this document

- 2026-11-22: approved, **with sound** (step 4 is in scope). The clips are CC0, sourced as the march sounds were (`assets/audio/units/SOURCES.md`); each download is named to the owner (file, source, size) and confirmed before it is fetched.
