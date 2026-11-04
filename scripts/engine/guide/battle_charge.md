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

## Candidate earned charge

`BattleCharge.intent_candidate` is the opt-in received-charge provider for
`BodyBattleMotion`. Its closed five-field contribution contains only the desired
anchor route. It validates the saved boundary, charge state, actual body rows and
policy, reads a detached source, and neither refreshes groups nor moves or pays
anything. Unsupported or malformed input errors; incapacity, reserves, packing,
insufficient supplies, absent lawful mounted targets and closed swept ground hold
with a reason. Existing measured surface reach bounds the forward corridor;
whole-metre diagonal endpoints are checked against actual circles. The union
transaction alone applies the shared allowance, full-Q reservations and terrain
checks, including stationary and protected peers.

The shared commit settles charge after all actual body paths and the minimum
reached anchor prefix are known. Only its own forward committed prefix earns
run-up, floored to whole metres and capped by displacement from the saved
approach origin; side legs and timed whole-degree pivots reset unfinished credit.
A changed target, heading or external
anchor also starts fresh. Enough run-up without actual forward lawful open-ground
contact stays an approach. Short contact becomes disengagement, and movement
never settles personnel or consumes the same day's pending impact. The complete
outer endpoint digest includes charge, and exact direct/JSON receipt retries are
no-ops. Changed charge, controls, terrain, policy or other frozen inputs reject.

After an impact, actual movement away must open the existing disengagement gap.
An already-open gap still needs a bounded own disengagement move.
Candidate `charge.regroup_day` records that day; the next whole day holds before
a new approach is eligible. This optional field accompanies the existing charge
record and follows its existing whole-number save encoding. Candidate admission
rejects malformed fields and unknown charge keys. Existing production movement,
impact consumption, save version and ordinary day callers retain their entrances;
future candidate personnel settlement remains responsible for consuming impact
only on complete success. Numerical test policies certify candidate arithmetic,
not installed animation, live activation or the twelve final acceptance gates.
