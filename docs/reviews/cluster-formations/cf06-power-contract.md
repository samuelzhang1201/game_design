# CF06 physical personnel and incoming exposure contract

Date: 2026-11-01. Step `CF06-POWER-CONTRACT`; implementation
`01a19763-6709-75e0-993e-6b33d4b2f675`; dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`; unique Review is assigned by that
dispatcher before handoff. This document resolves the two pre-D-POWER decisions
in accepted #210, [CF06](cf06-damage-contract.md). It is a mathematical interface,
not a product API, implementation, registration or gameplay acceptance.

## Authority, sources and limited decisions

Inspected source is accepted main `14394eec19876da46b58309615ea5f1ffb7bf316`.
The [approved spec §3.2, §5, §7–9](../../superpowers/specs/2026-10-25-cluster-formations-design.md)
requires real engaged/firing personnel, accurate partial rows, separate defence,
no reserve damage and no duplicate charge/flank benefit. The decisions here are
implementation deductions within those rules: proportional equipment occupancy
of each physical row, one existing per-arm rounding chain after unioning rows,
and personnel-weighted incoming exposure over actual lawful sources to one target.
They do not assert that these missing candidate calculations already run on main.

The following are the unchanged arithmetic sources, not interchangeable helpers:

- [MilitaryRoster.personnel_capacity](../../../scripts/engine/military_roster.gd):
  equipment quantity times that arm's crew, summed over admitted unit types.
- [BattleRanged.share](../../../scripts/engine/battle_ranged.gd):
  `R = trunc(1000 * ranged_crew_capacity / total_crew_capacity)`; ranged includes
  `ranged` and `machinery`. A cannon is equipment, not one crew member.
- [BattleStrength.unit/combine](../../../scripts/engine/battle_strength.gd):
  per-arm milli equipment, `_arm_base`, arm development, upward whole arm power,
  summed equipment, identity quality, equipment-weighted terrain, then category
  addition/clamp/truncation. Do not call `ArmySystem.power` first.
- [ArmySystem._arm_base](../../../scripts/engine/army_system.gd),
  [DevelopmentSystem.arm_permille](../../../scripts/engine/development_system.gd),
  [MilitaryQuality.profile](../../../scripts/engine/military_quality.gd) and
  [PrisonerBurden.guard_count](../../../scripts/engine/prisoner_burden.gd) retain
  their actual source inputs. Guard personnel remain fit for casualties but
  cannot contribute equipment power. No new arm, identity or guard placement
  is stored in a body row.
- [BattleSystem.unit_strength/combat_context](../../../scripts/engine/battle_system.gd),
  [BattleCharge.impacting](../../../scripts/engine/battle_charge.gd) and
  [BattleFormation.effects](../../../scripts/engine/battle_formation.gd) supply
  existing action, defence, context, earned shock and directional sources.
  [CF05](cf05-battle-contract.md) and CF06 supply future physical admission and
  bilateral eligibility, not implemented B/D outputs.

## 1. Integer evidence and identity unions

All input counts, capacities, permilles and intermediate quotients are integers.
`trunc` means division toward zero (floor for these nonnegative allocation
inputs); `ceil(x/d) = (x+d-1)/d` only for nonnegative x and positive d.
Use checked integer arithmetic, cancelling common factors if needed; overflow,
fractions, bool integers, malformed rows, count/fit disagreement and invalid
provenance reject before arithmetic or RNG. Never approximate with Vector2,
float32/float64 or rounded crew counts. No new saved numeric representation is
needed; numerator/denominator pairs below are transient exact integer evidence.

For source unit u, `F` is actual fit agreeing with the sum of all admitted own
body counts, `G` is the existing guard count and `H=F-G`. Require `0<=G<=F`.
`N[a]` is equipment quantity, `c[a]>0` its crew, `C[a]=N[a]*c[a]`,
`C=sum(C[a])`, `Cr=sum(C[a] for ranged/machinery arms)` and
`R=trunc(1000*Cr/C)` when C>0, else zero, exactly as `BattleRanged.share`.
Equipment/crew membership comes from the same admitted regiment and unit-types
source as the current pipeline. Equipment is not silently capped by model count.

For a particular target t, obtain lawful outgoing melee identity set `L(u,t)`
and actual direct-fire set `S(u,t)` from the accepted physical queries. Physical
contact, law, received action/target, local self-defence, pursuit bounds, sight,
cone, unchanged centre reach and terrain/friendly blocking must all be admitted.
Pure defensive `exposure_candidate` evidence alone cannot populate either set.
The query's melee and fire sets are disjoint: close contact takes precedence.

For round outgoing power, union each source identity `(unit,slot)` over all
eligible targets, then sum its actual count once: `M` for melee, `J` for fire,
`M+J<=F`. A row touching two enemy rows/units is not two sources. A partial final
row of count1 supplies 1, not 100, a rounded arm crew or a new full cannon.
Use the same precedence across the union; a melee identity cannot also fire at
a remote target. Per-target counts `M_t,J_t` use that target's subsets of these
same disjoint sets; they never add an identity suppressed by round close defence.
There is no persistent per-person weapon assignment or new target-selection rule.

Defensive contactability is a separate union. A unit can have outgoing zero and
still be exposed to a lawful attacker, retain its existing defence/organization
and suffer casualties. A protected A→B pair is absent from outgoing sets; C→B
can remain lawful. Validate both source fields and every retained absorbed
source's party-scoped terms. Neither a merge nor t's relation with A grants or
removes C's rights. Admission errors are not valid zero exposure.

## 2. Exact mixed-arm allocation and original rounding

A body row represents the unit's existing equipment mix in proportion to
`C[a]/C`; it does not acquire the rendered model's arm or a full crew by rounding.
Its guard-available fraction is H/F, the same uniform personnel subtraction used
by the existing whole-unit equipment pipeline. Thus the exact eligible crew
personnel for arm a are represented by the integer pair

```text
E[a] = M + J if a is ranged/machinery, otherwise M
crew_personnel[a] = (C[a] * E[a] * H, C * F)
equipment_equivalent[a] = (N[a] * E[a] * H, C * F)
```

These are proportional analytical quantities, not fractional saved people or
permission for a lone crewman to gain an entire cannon's nominal strength.
There is no largest-remainder assignment of weapons/guards to slots: no such
identity assignment exists in the source, and assigning the leftover to an early
slot would make eligibility depend on slot order rather than physical counts.
`BattleRanged.share` remains the crew-weighted aggregate with its existing
permille truncation; do not use that rounded R to reconstruct per-arm equipment
or multiply the equipment pipeline by R again.

If F=0, C=0, H=0 or all eligible equipped-arm numerators are zero, outgoing power
is exactly zero **before** factor clamps. Validate all evidence/factor sources
first; an invalid source cannot hide behind this zero. For every positive arm,
substitute only its eligible personnel input into the existing chain:

```text
m0[a] = trunc(N[a] * E[a] * H * 1000 / (C * F))
m1[a] = trunc(m0[a] * ArmySystem._arm_base(...,a,...) / 1000)
p[a]  = ceil(m1[a] * max(0, development[a]) / 1000000)
Q     = sum(p[a])
base  = trunc(Q * quality.power_permille / 1000)
terrain = trunc(sum(p[a] * terrain_factor[a]) / Q) if Q>0 else 1000
```

There is exactly one m0, m1 and upward power rounding per arm, after unioning
rows and melee/fire contributions. Do not round each row, round crew personnel
first, or ceil melee and fire halves separately. With `M=F,J=0`, m0 reduces to
`trunc(N[a]*H*1000/C)`, identically the current full personnel chain. With
`M=0,J=F`, only ranged/machinery arms survive, using that same arm chain. With
all arms melee-only and F1000/M100/G0, the equipment input is exactly100, never
1000 plus a reserve fraction. A non-ranged arm cannot use remote J personnel.

Apply current quality once to the summed Q, and build the current factors from
the admitted source: `unit:training`, `unit:morale` (including existing royal
support), `unit:discipline`, `unit:supply`, `unit:terrain`; existing height,
stance/camp defence, received order and authored event sources keep their
semantics. No new cluster benefit or exposure penalty value is introduced here.
Defence uses its own admitted personnel/evidence path and the existing full
H-based equipment chain, not the outgoing E array. Never reuse an outgoing-zero
result as defensive power. This contract creates no extra defensive attack.

The candidate removes legacy `contact:engaged`/`contact:ranged` participation
scaling from outgoing factors because E has already done it. Do not also apply
`engaged_permille`, `active_permille` or `battle_reserve_permille` to this base.
Other admitted factors retain their original categories and bounds. Reject empty
or duplicate source IDs globally within each combine, category/bounds mismatch
and missing reason; distinct aliases for the same flank/charge fact do not
justify duplicate benefits. An old internal shape is not a new cluster benefit.

Category order stays training, morale, discipline, supply, formation_terrain,
contact, action. Within each present category add deviations around1000, clamp
once to its existing CSV bounds, then truncate whole power once. Absent categories
have no step. The contact category remains in the ordered schema, but the
removed participation factors have no replacement in this contract.
A zero eligible base remains zero under a positive lower clamp. Round side totals
sum each source unit's union power once; never sum its per-target re-evaluations
and thereby multiply one source's output by its number of targets.

## 3. Target-scoped simultaneous incoming melee and fire

For each receiving unit t, independently form the sorted set `I(t)` of opposing
source units with at least one positive, lawful equipped-arm personnel
numerator to t after §1 admission: H>0, C>0 and
`sum(C[a]*E_t[a])>0`, with E_t defined as in §2. A source with neither eligible melee nor eligible fire
against t is absent from both numerator and denominator. Thus adding a remote,
protected or blocked opponent cannot dilute or create t's exposure. An eligible
source's unengaged personnel still appear in its denominator, so one contacting
row of its ten rows is partial exposure, not a full threat. Defence alone does
not admit a source into I(t). No side-wide non-ranged full-threat fallback.

Use the existing fit-personnel weighting and the **existing truncated** R per
source, retaining that resolution rather than replacing it with power weights:

```text
W(u,t) = (1000-R[u])*M_t[u] + R[u]*(M_t[u]+J_t[u])
       = 1000*M_t[u] + R[u]*J_t[u]       # milli-personnel, no inner truncation
exposure[t] = trunc(sum(W(u,t) for u in I(t)) / sum(F[u] for u in I(t)))
```

Empty I(t) yields0, including no live fit source; never1000. All terms are
nonnegative and `W<=1000*F`, so exposure is already in0..1000 with no corrective
clamp. R is applied exactly once. A source's non-ranged part uses only M_t; its
ranged part uses disjoint M_t+J_t. Firing at B cannot expose C. Multiple target
rows do not add source counts; multiple sources are weighted by their own F,
not averaged equally by unit, arm, body model or power. Keep guard subtraction
in the equipment path: guards remain physically exposed fit people, not a
new casualty exemption or guard-position model. A wholly guard-bound source
cannot supply output or enter I(t).

This is the simultaneous weighting decision; do not choose one channel, take a
max, sum two independently clamped exposures, or classify all incoming as ranged
merely because one lawful shot exists. Classification precedes this scaling,
using the same target-specific I(t) and original thresholds/rounding:

1. Actual target withdrawal/rout has precedence. Determine lawful actual pursuit
   against t (including both-field protected withdrawal, received region/target
   and real contact/fire); use the existing pursuit/withdrawal context scale.
   Preserve the protected-power step in its original position before exposure,
   with the admitted source set as specified below. An all-protected target has
   exposure0; a lawful nonparty threat remains. No guard/remote power is a
   pursuit fallback.
2. Otherwise ranged numerator is `sum(trunc(C[a]*J_t/F[u]))` over each ranged/
   machinery arm of I(t), with denominator `sum(C[u])`. Preserve the current
   arm-by-arm truncation and `numerator*1000 >= denominator*threshold` test.
   These are the same crew-capacity classification sources as combat_context;
   do not replace them with equipment power or active-only denominators.
3. If ranged does not qualify, test existing actual earned mounted impact counts
   against t, `trunc(contacting_impact_personnel*mounted_share/1000)` per source,
   against `sum(F[u])` and that same existing threshold. Zero/remote impact and
   task labels do not qualify. Ranged precedes shock, then ordinary melee.
4. Start with that existing context scale (melee1000), apply exposure once:
   `scale=trunc(context_scale*exposure[t]/1000)`. Then apply existing authored
   event exposure modifiers for t, in their original saved order, truncating
   after each. Freeze every participant's loss/morale context, including zero.
   A later event multiplier cannot revive zero exposure.

Protected-power reduction in withdrawal retains combat_context's existing
source-power ratio/order, evaluated on I(t): total power is the sum of the
admitted sources' union power, exposed power sums its unprotected sources.
Because protection has already excluded barred pairs, a nonempty I(t) has
exposed_power=total_power and this step is neutral (including total_power0,
where the existing code skips the ratio). Empty I(t) forces exposure0. Do not
reinsert protected or remote sources in this denominator and thereby suppress a
lawful nonparty threat. This is not a second melee/fire weight or a second
shock/charge multiplier. Earned impact is consumed once only
after full atomic settlement. Side/rear factors retain their unique source and
are not added again as cluster/formation labels.

## 4. Hand-computed contract cases and executable oracle

These are artificial arithmetic inputs, not tuning, accepted physical worlds or
claims of product tests passing. All named factors below are admitted snapshots
of existing source outputs; neutral omitted factors equal1000. Real unit-type
crew values are read from the pack; the examples use infantry1, archer1,
artillery8, consistent with the inspected definitions. No map pack is named or
required by a future fixture.

- **P1, pure melee:** C=N1000, F1000/G0, base/development1000 and M100/J0:
  m0=100000, m1=100000, Q=100, quality1000 gives base100. M0 gives zero even if
  category lower bound is positive. Defensive full-H equipment remains1000.
- **P2, mixed partial rows:** infantry600, archers320, artillery10 gives C1000,
  Cr400 and R400. F901/G0 has rows `9*100+1`; M101 includes the final1, J100 is
  disjoint. E=[101,201,201], exact eligible crew=[60.6,64.32,16.08], equipment
  equivalents=[60.6,64.32,2.01]. Integer pairs retain these fractions; none are
  saved people. With arm base/development1000, m0=[60600,64320,2010],
  p=[61,65,3], Q129. Quality1100 gives141. Terrain factors[1000,800,600]
  yield `trunc(114800/129)=889`. Training1100 gives155, morale900 gives139;
  discipline/supply1000 preserve139. Terrain889+height1100+one authored1050
  combine to1039, giving144; neutral action preserves144. No contact fraction
  follows. In the adversarial variant M101/J1, separately ceiling each half
  gives archers34 instead of33 and artillery3 instead of2; this is forbidden.
  Counts per two targets still union101/100 in the original case.
- **P3, rounding/guards:** one arm N3/c1, F3/G1, M1/J0 gives exact crew2/3,
  m0=666. Arm base1501 gives m1=999; development1001 gives p=1
  (`999999/1000000`, upward). Prematurely rounding crew or multiplying all
  factors before m1 changes this boundary. All-fit M3 gives m0=2000, exactly
  the old H2 chain. H0 is outgoing0; no crew or factor creates power.
- **P4, final1 and no remote melee:** P2's mix, F901/G0, only final1 firing:
  E=[0,1,1], m0=[0,320,10], p=[0,1,1]. Only final1 in melee instead gives
  m0=[600,320,10], p=[1,1,1]. Existing per-arm upward rounding is retained;
  it does not promote that row to100 personnel or nominal full arm power.
  All rows remote or all actual shots blocked gives0. A duplicated slot errors.
- **P5, simultaneous target B:** source A uses P2 counts M101/J100, giving
  W=141000. Source D has F300/R1000, M0/J100, W100000. Exposure is
  `trunc(241000/1201)=200`. Ranged classification numerator is
  `trunc(320*100/901)+trunc(80*100/901)+trunc(300*100/300)=35+8+100=143`,
  denominator1300: below existing threshold500. No earned shock: melee context
  stays1000, context after exposure200. One event exposure1250 gives250;
  tier loss125 gives unit rate31, in that order. An equal-unit average gives
  another answer and fails. Against C, if only A's M1/J0 is lawful, I={A},
  exposure=`trunc(1000/901)=1`; if no source can reach C, exposure0.
- **P6, quantization and source neutrality:** C3/Cr2 gives R666, not667.
  F3/M0/J3 yields exposure666. Adding a remote fit10000 opponent or another
  opponent barred by its A↔B party protection does not change it. Adding a lawful nonparty F1/R0/M1 source gives
  `trunc((1998+1000)/4)=749`. The original protected party remains protected.
  Duplicate pair/target rows cannot increase either source's W.
- **P7, classification order:** one pure ranged F1000/J600 source has ranged
  classification600>=threshold500, exposure600; existing ranged context800
  becomes480 before events. One pure mounted F1000/M600 source, earned impact600
  against this target only, uses shock1250 and exposure600 ->750. A remote/
  expired/consumed impact gives ordinary melee600; no second charge factor.
  Protected withdrawal and zero output still allow t's independent defensive
  evidence/casualties from an actually lawful different source.

Run the following standalone Python (standard library only) as a hand-math
cross-check. This is not a replacement for future targeted GUT or runtime proof.

```python
from fractions import Fraction

def arm(n, e, h, fit, capacity, base=1000, dev=1000):
    m0 = n * e * h * 1000 // (capacity * fit)
    m1 = m0 * base // 1000
    return m0, m1, (m1 * max(0, dev) + 999999) // 1000000

def exposure(rows):  # (fit, ranged_share, melee, firing), already admitted I(t)
    return sum(1000*m + r*j for f,r,m,j in rows) // sum(f for f,r,m,j in rows) if rows else 0

assert arm(1000,100,1000,1000,1000) == (100000,100000,100)
assert arm(1000,0,1000,1000,1000)[2] == 0
p2 = [arm(n,e,901,901,1000) for n,e in [(600,101),(320,201),(10,201)]]
assert [v[0] for v in p2] == [60600,64320,2010]
assert [v[2] for v in p2] == [61,65,3]
assert arm(320,101,901,901,1000)[2] + arm(320,1,901,901,1000)[2] == 34
assert arm(320,102,901,901,1000)[2] == 33
assert arm(10,101,901,901,1000)[2] + arm(10,1,901,901,1000)[2] == 3
assert arm(10,102,901,901,1000)[2] == 2
assert sum(Fraction(c*e,1000) for c,e in [(600,101),(320,201),(80,201)]) == 141
q = sum(v[2] for v in p2)
assert q == 129 and q*1100//1000 == 141
assert sum(p*t for p,t in zip([61,65,3],[1000,800,600]))//q == 889
assert 141*1100//1000 == 155 and 155*900//1000 == 139
assert 139*(889+1100+1050-2000)//1000 == 144
assert arm(3,1,2,3,3,1501,1001) == (666,999,1)
assert arm(3,3,2,3,3)[0] == 2000
assert [arm(n,e,901,901,1000)[2] for n,e in [(600,0),(320,1),(10,1)]] == [0,1,1]
assert [arm(n,1,901,901,1000)[2] for n in [600,320,10]] == [1,1,1]
assert exposure([(901,400,101,100),(300,1000,0,100)]) == 200
assert 320*100//901 + 80*100//901 + 300*100//300 == 143
assert 1000*200//1000*1250//1000 == 250 and 125*250//1000 == 31
assert exposure([(901,400,1,0)]) == 1 and exposure([]) == 0
assert 2000//3 == 666 and exposure([(3,666,0,3)]) == 666
assert exposure([(3,666,0,3),(1,0,1,0)]) == 749
assert 800*600//1000 == 480 and 1250*600//1000 == 750
```

## 5. Future implementation boundary and retained gates

D-POWER remains **unregistered, with no implementation owner**. Before its
registration, this document needs its unique Review's accepted merge, and actual
accepted B-ROUND, D-QUERY, D-FIRE and every required B predecessor/output remain
necessary. Reconcile the contract against those actual APIs without assuming they
exist now. Its proposed minimal responsibility remains precisely CF06's listed
BattleStrength/BattleSystem/BattleRanged, the two listed engine guides,
`test_body_damage_strength.gd` and its UID, and `tests/categories.json`; no new
registry/config/data/fixture path is implied here. Implement source unions,
eligible-arm base and target contexts there, with P1–P7 as exact additive tests;
preserve old production assertions and add malformed boundary/raw integer,
row-order/target-order invariance, both-field party asymmetry, no-mutation,
positive-floor zero, defended-but-no-output, duplicate source and direct/JSON
frozen-context retry cases. Defence must be tested separately from output.

CF06's original outcome/variance/one RNG draw, group-loss/wounded largest
remainder, morale, extra attack food, atomic settlement, cost/source receipts and
earned-charge consumption stay unchanged. This PR changes none of them and
runs no Godot/Blender. Pure source/link/scope/handmath/guide/harness checks and
current-HEAD required doc CI precede its fixed-pair Review merge.

The production reach400 versus physical radii749–932 blocker remains unresolved:
no valid nonoverlapping production-radius direct-fire case is certified by these
arithmetic examples. No radius/reach/scale/R compensation, indirect fire, new
physics, multiplier, fatigue, fallback, feature flag or outcome table is allowed.
All spec §9 gates1–12, inherited **55 fail and 6 risky/pending**, real production-
radius road contact/defeat continuation, fresh-campaign save/determinism,
reorganization/personnel/slot/cost conservation, every formation's comparisons,
contact/ranged/charge regressions and final native-window visual/performance
acceptance remain required. CF01 finite17/substitute art is no full animation or
performance certificate. Only final ALL-writer activation can switch production
motion/damage/render ownership together after every actual predecessor and gate;
this document, its oracle and future candidate fixtures are not those passes.
