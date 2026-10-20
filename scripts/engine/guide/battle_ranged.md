# Ranged fire (`BattleRanged`, `BattleGroups`, `BattleSystem`)

`BattleRanged` uses saved whole-metre group positions and `group_facing` for
direct fire. A shot lies beyond `battle_group_contact_m`, within the inclusive
`battle_ranged_reach_m`, and inside the forward cone whose lateral/forward
ratio is at most `battle_ranged_cone_permille`. The saved whole-degree facing
is converted to a transient integer direction. Squared distances, dot and
cross products decide reach, cone and obstruction; no projectile, rendering,
wall-clock or random draw decides eligibility.

Every positive-count friendly group, including the shooter's own front ranks,
obstructs the open firing segment with `battle_ranged_block_radius_m`.
Tangency within the segment blocks; touching only an excluded endpoint does
not. Only the shooter itself is excluded. Each eligible group counts once,
regardless of how many enemy groups it can reach. Rear ranks receive no
automatic reserve firing allowance.

Targets must be live opposing battle members, allowed by current received
laws and bilateral agreements, and within the recipient's own local sight
(`player_sight_km` or `ai_sight_km`), irrespective of player camera/global
sightings. A received designated target restricts shots to that target; an attacking
close interceptor still permits lawful local self-defence.
Pursuit remains bounded by its received region and protected withdrawal bars
fire. Captured, withdrawing and uncommitted reserve shooters cannot fire;
close reserves may still defend.
No fresh route, target, task or hidden-position cache is written by this helper.

At actual close group contact, a ranged-dominant unit's attack becomes local
hold/defence; an already received retreat remains retreat. Front groups in
contact contribute melee defence, with no ranged shots or reserve firing.
Received pursuit keeps its attack/region semantics rather than becoming hold.
A round still requires an opponent's actual attack. Mixed equipment uses its
crew-weighted ranged personnel share; other equipment retains the existing
melee/contact and mounted charge rules.

`BattleSystem.unit_strength` replaces the generic contact factor for ranged
personnel with the fraction actually firing or in melee. Incoming casualty
contexts also scale the ranged share by that fraction against EACH specific
target; reaching one enemy never exposes its remote ally. Non-ranged threat
retains its previous semantics. Ranged context uses actual firing personnel;
close defence uses melee. Every factor has its source and readable reason.

The existing atomic round freezes per-unit loss rates, contexts, negative morale exposure and actions
before personnel writes. Failed writes and JSON retries reuse those frozen
inputs, never move groups or reroll. Successful settlement retains the daily
round receipt and the existing charge-consumption semantics. No new top-level saved
state is required: integer groups, facings and pending rounds already serialize.

This step supplies geometric eligibility only. Prepare/fire/reprepare timing,
machinery deployment/loading and moving output, indirect trajectories/terrain
occlusion, and actual ranged-fire merging between separate battles require
separate steps; no visual pass is claimed here.

Legacy arithmetic adapters without any group field retain their old incoming
context until production refreshes their groups; normal contact creation and
daily preparation always supply the geometry.

Daily deployment offsets an actively attacking ranged-dominant unit behind its
ordinary line by half the positive difference between ranged reach and line gap.
The offset reserves the combined half-diagonal error of the two whole-metre
roundings, so opposing diagonal lines stay within reach too. Movement
still uses the ordinary daily budget and passability check. Received pursuit and
actual close defence retain their existing deployment path.
