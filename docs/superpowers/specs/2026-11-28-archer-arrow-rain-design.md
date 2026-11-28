# Archer arrow rain (view-only volleys)

Owner (2026-11-28): 我希望看到射箭的箭像雨一般飞出去，飞向敌人，敌人出现被击中的动作.
When archers shoot, the arrows fly out like rain toward the enemy, and the enemy figures play a hit reaction.

## Intent

Spectacle, like the duels (`2026-11-16-infantry-duel-animation-design.md`): the player sees the archers' fire
reach the foe. The engine still decides every loss (`BattleRanged`, `BattleSystem`); nothing drawn here
feeds back.

## Rulings

- **Density: one arrow per figure per release** (owner: A). Each archer figure looses one arrow at its own
  ATTACK clip's release instant; the figures' clips are already out of phase (`Map3DUnitRig.play` desync),
  so the arrows leave in ragged waves. Not several arrows a release (more spectacle than the men drawn).
- The rest the owner approved as proposed (2026-11-28, 可以，开始做):
  - both sides' arrows are drawn; only near the camera (`map3d_volley_near_m`); nothing in the far symbol mode
    (a hidden piece shoots nothing);
  - a ballistic arc: flight time and apex height from the distance (CSV), the arrow always pointing along its
    path;
  - an arrow lands among the target unit's figures (scatter hashed), sticks in the ground, stands
    `map3d_volley_stick_s`, then fades;
  - a landed arrow makes, by a hashed share, the nearest target figure play a HIT clip, with a per-figure
    cooldown; a duelling or fallen figure is never taken. Losses still come only from the engine.

## Constraints

- View-only: no engine state, no save field, no RNG draw; every choice hashed (`Map3DMarchLag.unit`) from the
  figure key and its release count, so a replay is the same. Real seconds while the game clock runs;
  paused, arrows stand still.
- `scripts/map3d/` never reads `Game`; battle membership comes from `ctx.state()` as the duels do.
- The look (arrow mesh, material, the MultiMesh node) is authored in the editor:
  `scenes/map3d/effects/arrow_volley.tscn` (a `MultiMeshInstance3D`) with its mesh and material `.tres`
  beside it, reached through `GameArt.ARROW_VOLLEY`. Code only writes instance transforms and colours.
- Values in `data/screens/map3d/balance.csv` (`map3d_volley_*`); the release share is MEASURED per clip in
  `army_art.csv` `contact` (`ATTACK:<share>` on the archers' row).
- Performance: one MultiMesh draw for all arrows, at most `map3d_volley_max` live; bench with
  `tools/map3d/bench.gd --battle-arm archers`.

## Approaches

1. **One MultiMesh, pure planner (chosen).** `Map3DVolley` (pure, static) decides the release crossing, the
   landing point and the arc; `Map3DVolleys` (run from `Map3DDuelDriver.step`, the layer being at its shape
   cap) keeps the live arrows and writes the MultiMesh. Cheap, testable headless, one draw call.
2. A node per arrow (a scene instanced per release): simplest to author, but hundreds of nodes a volley.
3. GPU particles with a ballistic process material: no per-arrow control of target, stick or the HIT hook.

## Design

- **Who shoots.** In a battle past its first round, each drawn `physical_groups` piece's group child whose
  AnimationPlayer plays ATTACK, whose arm's `contact` names an ATTACK share, not claimed by a duel. Its
  release is the frame its clip position crosses that share (a wrap counts).
- **Target.** The nearest drawn, non-ghost piece of the other side of that battle (by the figure's stand).
  Landing: one of its group figures, hashed, plus a scatter of up to `map3d_volley_scatter_h` figure heights.
- **Flight.** From `map3d_volley_from_h` figure heights over the shooter's ground to the landing ground;
  time = distance / `map3d_volley_speed_m` clamped to `map3d_volley_min_s`..`_max_s`; apex
  `map3d_volley_apex` × distance over the straight line (a parabola in the share). The arrow is sized in
  figure heights (scaled by the shooter's figure height).
- **Stuck.** At landing the arrow keeps its last direction, its point `map3d_volley_sink_h` into the ground,
  for `map3d_volley_stick_s`, then fades over `map3d_volley_fade_s` (instance alpha).
- **HIT (step 2).** On landing, with share `map3d_volley_hit`, the target figure nearest the point within
  `map3d_volley_hit_h` heights plays one of its arm's `duel` HIT clips once, then is handed back its action
  (the duel driver's hold/hand-back), at most once per `map3d_volley_hit_cool_s`.

## Steps

1. The arrow layer (this PR): `Map3DVolley`, `Map3DVolleys`, the scene, the CSV keys, the archers' ATTACK
   release share, GUT tests on release/target/arc; real-window shots and a movie through `visual-review`.
2. Hit reactions: after `archer-duel-hits` merges, reusing the figure-level HIT it adds.

## Left to the builder

Arrow mesh proportions and thickness (tuned in the real window so it reads at the battle zoom), the exact
CSV values (first guesses, then the review).
