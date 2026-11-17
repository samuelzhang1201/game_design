# Infantry duels: front-rank figures fight in pairs

Owner request (2026-11-16): 双方发生战斗，总该有动画表现，双方接触，攻击，防御，被攻击等状态。目前就是纯数字记录。
Owner ruling on purpose: 主要是要临场感，可以做成好看但和数字无关的表演.
Owner pick: approach A (paired duels), infantry against infantry first.

## Intent

Up close, a battle should look like two lines actually fighting: a figure swings, the
figure opposite raises its shield or takes the blow and staggers, then strikes back.
This is spectacle for presence, not a readout. It does not show who is winning; the
battle card and reports do that.

## What exists today (the starting point)

- A battle unit is drawn as saved physical groups (`Map3DBattleGroups`): one figure per
  `battle_group_size` fit people (`data/battle/balance.csv`), each at its saved
  whole-metre point with role `front` or `reserve`. Both sides' units have rows; a foe's
  are drawn when the crown sees it (`ctx.regiments()`).
- Entering a battle the figures walk to their points (`map3d_battle_walk_s`).
- Clip choice: `BattlePresentation.map_snapshot` gives the player's own units ATTACK
  (their side attacks) or DEFEND, only after the first round; `Map3DBattleSignals.action_for`
  applies it. Foes get nothing, so **foe figures stand in their order's clip (GARRISON)**.
- ATTACK on the infantry is a chain (`army_art.csv` `chains`
  `ATTACK:ATTACK;SLASH;ATTACK_VAR1`, `Map3DClipChain`): each figure strikes alone at the
  air with hashed guard pauses. No pairing, no reply, no hit, no fall.
- `infantry.glb` clips: MARCH, GARRISON, ATTACK, SLASH, ATTACK_VAR1, PIVOT_RIGHT,
  PIVOT_LEFT. No block, impact or death.
- When a group is lost its figure is freed at once (`Map3DBattleGroups.sync`).
- Source clips are on hand: the owner's Mixamo packs (`~/Downloads/Sword and Shield
  Pack.zip`, `Pro Sword and Shield Pack.zip`) hold `block`, `block (2)`, `block idle`,
  `impact`, `impact (2)`, `impact (3)`, `death`, `death (2)`, retargeted onto the ARP knight
  the way the existing clips were (`docs/superpowers/specs/2026-10-19-infantry-arp-knight-design.md`,
  `tools/units3d/infantry_knight/battle_clips.py`).

## Goals

1. Front-rank infantry figures of the two sides pair off and duel: strike → block or
   impact → guard → the other strikes. Strike and reply meet at the same instant.
2. Foe infantry figures take part (they are half of every pair).
3. A figure removed while its unit is in battle falls (DEATH) and fades, instead of vanishing.
4. No two pairs in step; the same battle looks the same on a replay.

## Non-goals (this design)

- Archers, cavalry, artillery, the king. Their battle behaviour (volleys, charges) is a
  later design each. A pair forms only between two infantry figures; any other arm keeps
  today's behaviour.
- Showing the battle's state: no faster fighting for the winner, no more falls on a bad
  day. The duel does not read losses, morale, odds or orders beyond "the unit is in a
  battle that has fought a round".
- Sound (clash, shield thud). Worth doing; a follow-on step.
- Lines that push, give ground or interleave (approach C).

## Anti-goals (a failure even if it works)

- Swinging at air while the figure opposite stands idle.
- A rank striking in unison, or every pair on the same beat.
- A fall before the engine has removed a group, or more falls than removed groups
  (no invented deaths: one fall per removed group, at the moment it is removed).
- Figures sliding, overlapping or turning their backs to step into a duel.
- Anything over a piece (number, bar, icon): the near-mode rule stands.

## Constraints

- **View-only.** Everything is under `scripts/map3d/` and data under
  `data/screens/map3d/`. The engine is untouched: no new state, no save change, no RNG
  draw. Choices are hashed (`Map3DMarchLag.unit`), like `Map3DClipChain`.
- `scripts/map3d/` never reads `Game`; it gets everything through `Map3DContext`.
- Fog: a foe figure duels only if it is drawn (admitted). Duelling reveals nothing the
  figure's presence does not already reveal; it reads no hidden order or stance.
- Tuning values (pause lengths, block/impact share, duel distance, fade time) are
  `data/screens/map3d/balance.csv` keys; per-clip timing (the strike's contact share,
  the block's raise share) is data beside the clips (`army_art.csv` column), never code.
- Clips are made in the owner's open Blender over MCP, from the Mixamo sources, on the
  infantry ARP rig; re-exported `infantry.glb` with the new clips LOOP_NONE (block idle
  looped) in its `.import`. No Hunyuan.
- Every visual result goes through `visual-review` in a real window.

## Approaches considered

- **A. Paired duels (picked).** Pair opposing front figures; each pair runs a hashed
  exchange with strikes and replies timed to meet. Most presence; needs three new clip
  kinds, contact timing data and foe participation.
- B. Independent mixed loops. Every figure cycles strike/block/impact alone, facing the
  enemy. Cheap, but up close it is shadow-boxing: hits with no one hitting. Rejected
  against the purpose.
- C. Pushing lines. A's pairs plus lines that advance, give ground and interleave.
  Several times A's work, with real clipping and ground-fit risk. Deferred.

## The design (decided parts)

### Pairing

- A pair is one `front` figure of each side, both infantry, both drawn, in the same
  battle, after the battle's first round (`rounds > 0`, the moment ATTACK/DEFEND start today).
- Pair along the front like `Map3DBattleGroups.lanes`: sort each side's front figures
  along the battle front and pair in order, nearest first, so pairs never cross.
  Extra figures on the longer side stay unpaired.
- A pair forms only if the two figures' drawn gap is within a reach the builder sets
  from measurement (see "left to the builder").
- Pairs are re-made when a side's rows change (a group lost, a unit joins or leaves);
  untouched pairs keep their exchange running.

### The exchange (per pair)

- Turns alternate by default, a hashed turn now and then giving the same figure two
  strikes running. The side whose orders attack strikes first and a little more often;
  a side that holds still strikes back (self-defence), so neither side stands idle.
- Each turn: the striker plays one of its strike clips (today's chain clips); the
  defender plays block (most turns) or impact (some turns, share in balance), started
  so its block raise or its impact jolt lands on the strike's contact share. Then both
  stand in guard for a hashed pause before the next turn.
- Every pick (who strikes, which clip, block or impact, pause) is hashed from the two
  figures' identities (unit code + slot) and the turn count. No timer drift between
  the two: one schedule drives both figures of a pair.
- The paired figures face each other while duelling and turn back to the unit's facing
  when unpaired.

### Everyone else

- Unpaired front figures keep today's behaviour (the attack chain, or the guard).
- Reserve figures stand in guard (GARRISON), as today.

### Falls

- The engine trims losses from the TAIL of a unit's saved rows (`BattleGroups.refresh`:
  "only losses trim the tail"), which in the default block is a flank-end figure, never a
  duelling one. Owner ruling (2026-11-16): 前排倒，后排补位 — the fall is shown in the duel
  and the removed figure steps up to fill the gap.
- So when a group is removed from a unit still in the battle, the view:
  1. picks one of that unit's PAIRED front figures (hashed from the unit, the removed
     slot and the turn count; none paired: the removed figure itself falls where it stands);
  2. leaves a stand-in body at the picked figure's place that plays DEATH (ideally just
     after an impact from its opponent) and fades out over a balance time, then is freed;
     its opponent goes to guard and pairs again when the gap is filled;
  3. moves the removed slot's figure (model and clip phase) to the picked figure's saved
     point by the existing view-only walk (`Map3DBattleGroups._walk`), and the picked
     slot's figure becomes that walker, so after the walk every saved row has exactly one
     figure at its saved point and the tail's place is empty, as the engine says.
- Count check: falls = removed groups, and once the walks end the drawn figures match the
  saved rows one to one. Saved rows and points are never changed.
- A figure removed for any other reason (a load, a regroup or a migration that changes
  slots) is freed as today. No fall without a removal.

### Time

- Pausing the clock freezes the duels mid-motion and resumes them where they were
  (spec `2026-10-16-battle-system-design.md` §16.2: 暂停冻结战斗走位、攻击).
- At 2x / 4x the duel's tempo stays as at 1x: faster days, not faster swordplay.

## Steps (each its own PR)

1. **Clips.** In the owner's Blender: retarget block, impact and death (and block idle)
   onto the infantry ARP knight, export `infantry.glb`, set loop modes, record each
   clip's contact/raise share as data. `visual-review` of the clips on the piece.
2. **Duels.** A pure pairing + schedule class beside `Map3DClipChain` (GUT tests with
   hand-computed hashes and timings), wired into `Map3DLayerUnits` for battle groups,
   foes included; pause freeze. `visual-review` in a real window.
3. **Falls and step-up.** A paired front figure falls and fades for each group removed
   in battle; the removed figure walks up into its place (GUT: which figure falls, the
   count check, the walk's end state). `visual-review`.

## Calls made by the designer (not owner rulings; the owner may overturn)

- **Clips are appended, not a re-export.** The new clips are retargeted in the owner's
  Blender, then baked and APPENDED to the installed `infantry.glb` the way
  `battle_clips.py` and the pivot bake add theirs, so MARCH's certified stride/steps and
  the pivot bake (`test_infantry_pivot.gd`, `soldier_arp/test_pivot_mapping.py`) stay valid.
- **Who strikes first** is the battle's `att` side (membership in the battle record, which
  the player already knows), not either side's order: the view never reads a foe's order.
- **One clip set, today's sword-and-shield knight only.** Clip timing is data on the
  arm's `army_art.csv` row, so a later variant (axe, longsword) adds its own row and clips.
- **Falls only inside a continuing battle.** Figures dropped with their whole piece (the
  unit destroyed, surrendered or out of the battle) vanish as today; making those fall
  needs falling nodes that outlive the piece, a follow-on step.

## Left to the builder

- Measure first, in a real window, how far apart the drawn figures of two contacting
  infantry fronts actually stand. That sets the pairing reach and whether paired
  figures need a small view-only step toward each other (and back) to be at sword's
  length.
- Which Mixamo variant per clip kind, and how many variants to keep.
- The data layout for clip timing (a new `army_art.csv` column, like `steps`).
- How the schedule clock is driven (frame delta gated by `ctx.clock_speed()` instead of
  SceneTree timers) so pause works and a pair never drifts apart.
