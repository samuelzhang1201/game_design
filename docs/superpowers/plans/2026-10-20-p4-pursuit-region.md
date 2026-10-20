# P4 pursuit group region eligibility

Authorized serial P4 slice of spec `2026-10-17-unit-behavior-and-battlefield-design.md` §9. One implementation and one unique Review; no subagents. Execute inline under the existing authorization.

Scope: region eligibility of saved personnel-group positions for pursuit engagement. Route clipping, deployment contraction, gait and other P4 gaps remain separate steps.

1. Add hand-computed tests in `tests/engine/test_pursuit_bounds.gd`: anchor inside, front groups one metre either side of a province border; mixed/inside/outside contact, defensive contact, live manor province and JSON replay/receipt preservation. Observe the missing gate fail.
2. Freeze the pursuit region with the resolved action in `BattleTaskSystem`; pass state to `BattleGroups.engaged_counts`, excluding outside groups only during active bounded-region pursuit. Use existing map/manor lookup at each group's metre position. Update `BattleSystem` contact consumers and require eligible contact before applying explicit region pursuit loss context when saved groups exist. Legacy/no-group and unrestricted pursuit remain unchanged.
3. Document the current rule in `scripts/engine/guide/battle_deployment.md`. Run targeted pursuit/contact/task/save checks, then frozen-input engine-military regression plus guide/isolation checks once. Commit and publish one PR, checkpoint evidence and hand off to sole fresh Sol/medium Review.

Review focus: self-defence is unrestricted by the pursuit region; outside group contact cannot turn withdrawal into pursuit context; annexations use live state; saved pending action retains region; no position/task receipt mutation from eligibility queries.
