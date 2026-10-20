# Cavalry charge (`BattleCharge`, `BattleGroups`, `BattleSystem`)

Mounted attacks earn the existing `battle_context_shock_permille` casualty
context only at actual front-group contact after at least
`battle_charge_runup_m` of their own continuous approach. An attack order,
formation change, animation, enemy movement or group refresh grants no momentum.
A shorter approach still permits ordinary melee.

The unit entry's saved `charge` dictionary holds phase, target, approach origin,
last position, whole-degree approach heading, whole-metre run-up and impact day. Group indices are disposable;
casualties or recruitment across a `battle_group_size` boundary preserve the
unit's phase and earned distance. The normal GameState entry serializer keeps
this state through JSON; battle merging keeps the same unit entry.

Daily deployment moves ordinary units first, then charging units. Charge steps
use the existing `battle_deploy_step_m` budget and stop at the closest actual
front contact. Each group's swept corridor must be dry/passable and clear of
other groups. A blocked straight corridor waits; it grants no distance. Charge
movement never changes gait speed/food formulas. Town-seated, incapacitated,
withdrawing or legally barred units cannot charge. A pending atomic round
freezes deployment until its saved outcome is committed.

An impact belongs to one day and is consumed only after successful personnel
settlement. Failed round retries retain its frozen context and neither move
nor consume it again. A subsequent charge requires real movement away to a gap
of contact distance plus `battle_charge_runup_m`, a saved regroup day, then a
new approach. Remaining face to face earns ordinary attack only. A changed
target, approach heading or externally moved anchor discards unfinished approach credit.
Switching away from attack discards unfinished momentum but preserves the
requirement to disengage and regroup after an impact.

Incoming shock counts only mounted fit personnel in the impacting front groups,
and only against the actually contacted lawful opponent. Rear ranks and units
outside that contact keep their ordinary casualty context. The existing arm
share threshold still determines whether shock dominates that incoming exchange.
