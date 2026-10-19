# The infantry piece becomes the ARP knight (sword and shield), clips chosen by situation

Owner 2026-10-19: 请帮我把这个新的士兵模型和相关动作装入游戏，替换掉现有步兵的模型，动作接口也做好，要求是士兵的动作能够根据实际情况做出自动的选择.

## What changes

- `assets/3D/units/infantry/infantry.glb` is replaced by the Auto-Rig Pro knight of `tools/units3d/soldier_arp/` (PR #88): the Tripo knight with the round shield and short sword, rigged with ARP, driven by the owner's Mixamo sword-and-shield clips.
- The scene `scenes/models/units/infantry.tscn` and its material stay as they are. The GLB keeps the node names the scene names (`inf_rig/Skeleton3D/infantry`) and the textures keep their file names (`infantry_infantry_atlas{,_mr,_n}.jpg`, one 2048 atlas). The sword and shield are merged into the one skinned mesh, weighted wholly to their `cc_weapon.r` / `cc_weapon.l` bones, like the spear and shield of the knight before. The socket bones stay in the skeleton, so a later loadout can hang other gear there (BoneAttachment3D).
- Rest pose = the guard stance (GARRISON's first frame). The map sizes a piece from its rest mesh (`model_size`, `stand_extent`), and a T-pose would spread the formation.
- `infantry_parts.glb` (the folio's Take apart) is not part of this change.

## Clips and the automatic choice

| Clip | Source | Loop | Played when |
|---|---|---|---|
| MARCH | general/Standard Walk, in place, the arms hanging with the gear outside the legs | loop | the piece walks (clock running) |
| GARRISON | infantry/Sword And Shield Idle, the guard stance | loop | standing: STANDBY, GARRISON and DEFEND (the hold stance) all fall back to it (`Map3DUnits.clip_named`) |
| ATTACK | infantry/Sword And Shield Attack | once | in battle, its side attacking |
| SLASH | infantry/Sword And Shield Slash | once | in battle, its side attacking |
| ATTACK_VAR1 | infantry/Sword And Shield Attack - var 1, the lunge made in place | once | in battle, its side attacking |

The situation is already the engine's: `Map3DLayerUnits._sync_action` asks for MARCH while the piece walks, the order's GARRISON / STANDBY, the hold stance's DEFEND, and `Map3DBattleSignals` the battle's ATTACK or DEFEND (`BattlePresentation.map_snapshot`: ATTACK when the side's orders attack after the first round). Nothing in the engine changes.

New: an action may name SEVERAL clips (`army_art.csv` column `chains`, e.g. `ATTACK:ATTACK;SLASH;ATTACK_VAR1`). Such an action is a CHAIN: each figure plays one of its clips once, stands in its guard for a short pause, then plays the next. Which clip and how long a pause are hashed from the regiment's code, the figure's index and the count of strikes so far (`Map3DMarchLag.unit`, like the march's phases): the ranks never strike in step, the same battle looks the same on a replay, and nothing touches the engine's RNG. The pause runs between `map3d_unit_chain_rest_min_s` and `_max_s` (balance). An action with one clip plays as before.

## Data

- `army_art.csv` infantry row: `stride_m` and `steps` measured off the new MARCH; new column `chains`.
- `balance.csv`: `map3d_unit_chain_rest_min_s`, `map3d_unit_chain_rest_max_s`.
- `assets/3D/units/units3d.json`: the infantry entry (actions, height, tris, bones).

## Tuned in review (real-window shots, critic passes)

- `size` 0.62 for infantry and artillery: `Map3DUnits.scale_for` draws a piece's REST box at `size` × a fixed height. The old box was stretched to 2.68 m by the upright spear, the new one is the 1.60 m guard stance, so `size` 1 drew the knight ~1.7× an archer; 0.7 (the archers') × 1.60 / 1.8 draws him upright as tall as one.
- `spacing` 0.6 (new `army_art.csv` column: files and ranks this share of the formation gap apart) and `rank_depth` 1.2: the guard stance's footprint is 0.34 / 0.41 of its height wide / deep against the spearman's 0.20, so the block had come apart. Bracketed (0.6, 1.6), (0.6, 1.2), (0.75, 1.3), (0.75, 1.45); the looser ones drew a block whose half extent (1536 m) outgrew the foot's engine clearance radius (`army_clearance.csv` 1140, sized to the old block) — raising the radius changed where units camp round a town and meet on a road (three engine tests), so the block was closed to fit instead: 0.6 × 1.2 measures 1132.9 m, a shield wall the size of the old block.
- The game atlas's metallic ×0.45 (`GAME_METAL`) and the shield's wood weathered (`SHIELD_TONE` saturation 0.55, value 0.8): at full metal the knights went black under the map's light; the new wood matched the archers' orange.

## Open (owner)

- The resting pose is the combat guard, and STANDBY falls back to it: a relaxed standing idle (a Mixamo clip) would read calmer at rest.
- The round shield faces the camera as a disc at rest: a smaller shield or a realm colour on its face is the owner's call.
- Standing ranks share one heading and pose; a small per-figure turn would break the clones.
- Figures can stand in the town wall where a piece is seated over it (the spearmen did too: placement, not this model).

## Checks

- GUT: the chain choice (hand-computed hashes), the clips' loop modes, the infantry's clips resolving for MARCH / STANDBY / GARRISON / DEFEND / ATTACK, steps and rest size.
- Visual review: real-window shots of the piece marching, standing, and in a battle (`tools/snapshot_screen.gd`).
