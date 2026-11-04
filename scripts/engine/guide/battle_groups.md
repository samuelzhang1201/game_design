# Battle groups

`BattleGroups` saves each unit's fit personnel as independent `battle_group_size` rows (the last is the remainder): `{slot, count, role, x_m, y_m}`. Slots never recycle; `group_next_slot` exceeds every assigned identity. Losses trim tails, growth fills the last row then appends reserves behind the rear; surviving points and optional `path_m` persist. `group_anchor_m` is the committed anchor snapshot. Refresh stages rows and slot counters before publication; occupied-disc conflicts and any proposed row on closed ground reject placement before anchors, slots or versions publish. All proposed rows pass ground and schema checks before an overlap-only retry is classified. Only an initial disc-overlap rejection may try the existing complete deployment; blocked terrain is never bypassed by relocating the field.

Production layouts use the drawn piece's `unit_footprints` pitch on both axes, retaining the existing `BattleFormation.slots` patterns and renderer scale. Deployment projects the actual saved row offsets plus each piece radius onto the battle axis and across it; only a unit without physical rows uses freshly rounded formation slots. The admitted whole-degree `deployment_axis_deg` stays fixed while a unit flanks. A seated or captured opponent keeps its actual occupied front, so the moving side reserves the full clearance against that fixed front. Opposing fronts retain `battle_line_gap_m` between occupied envelopes; friendly units' complete envelopes stand abreast in sorted code order. Initial overlapping participants may form this validated deployment before the new battle is published. A conflict with another field refuses admission instead of relocating that field. Empty fit rosters draw no rows; fractional final groups still draw one complete piece.

`BattleGroupGeometry` decides overlap, contact, range and swept movement with squared integer arithmetic. Occupied circles may touch; melee and ranged reach are inclusive distances beyond the sum of both piece radii. Friendly fire uses each blocking piece's actual disc. Closed ground blocks melee contact. These metrics apply to contact strength, direct fire, flank exposure, charge approach and cross-field merging; encounter discovery remains its separate broad phase. A merge validates both complete occupied fields before publishing aliases, parties, warrants or reports; a dry contacting front cannot hide a closed reserve.

`translate` validates the swept rows before writing an anchor, then translates rows, optional paths and snapshot once. Daily deployment, charge and flank share that guard. Legacy and saved marches stage their entry and validate every traversed leg before publishing movement or pursuit credit; previews publish nothing. Live synchronization rechecks the traversed legs, never their obstacle-crossing chord, and is idempotent. A column still carrying battlefield rows retains its admitted arrival or garrison-command halt point instead of snapping into a town or camp slot, including while a round is frozen. Existing time, camp and supply rules remain in force. At or ahead of the nominal line, an unengaged melee front takes a guarded straight step toward the nearest actual occupied row of an opponent already at its line; moving, charging and flanking opponents retain their routes. Exact reach and the metre-rounding neighbours admit it. A front already in contact keeps its point. Ranged standoff, pursuit bounds and uncommitted reserves retain their existing routes. Pending rounds freeze rows and movement. Withdrawal retains membership while either anchors or actual occupied rows remain inside encounter reach.

The reserve contribution in `engaged_permille` remains a strength factor. Incoming casualties and negative morale exposure instead use each target's reachable melee/ranged personnel shares; distant non-ranged reserves cannot inflict losses. Mixed equipment retains crew weighting. An actual incoming pair requires an attack or lawful local self-defence; a remote attacker cannot make two holders hurt each other. Context queries retain potential withdrawal arithmetic; actual round planning gates both casualties and negative morale by the active pair. Every new round freezes per-unit exposure alongside actions, costs and its RNG draw, and retries reuse that plan.

**Geometry boundary migration.** `geometry_version` is separate from living-cap and people-per-group versions. `MilitaryReorganization.reconcile` stages a geometry-only migration even after those versions are complete. At a safe boundary it validates existing rows, retaining already clear points and paths. Unsafe spacing is expanded using installed footprints, preserving personnel, equipment, IDs, counts and costs, translating row paths and rebuilding anchor snapshots. An internally overlapping field may use the complete deployment; invalid geometry, blocked ground or another field's occupied discs rejects the whole candidate with a reason. Repetition and JSON reload are inert. A running day or any frozen round defers migration. Historical frozen rounds retain their planned result; uncomputed rounds of that old day wait for its existing boundary instead of mixing geometry into saved day inputs. Subsequent rounds require admitted geometry.

**Group-size boundary migration.** `MilitaryReorganization.reconcile` checks live
battles independently of completed living-cap organization. Its private candidate
calls `BattleGroups.migrate_size` before publication: saved slot order is consumed
into configured-size groups, retaining the first surviving row's slot, point,
role and optional path. Other slots retire permanently; `group_next_slot` never
falls. Exact fit totals, integer points/paths, unique slots and facing are
validated before any candidate is published. `saved_size` validates the known
version and its matching size; saved metadata cannot override the configured
current people-per-group rule. One invalid battle rolls back the
whole candidate. Completed battles carry `group_size_version`, `group_size_men`
and a causal reason. Repeated migration and JSON loads are inert. A pending day
or round retains its frozen rows and saved size until the safe boundary; ordinary
refresh preserves their partial rows rather than regrouping them.

A living-cap partition of already current-size rows marks regrouping only inside
that private candidate, so a group crossing a child boundary is consumed into
canonical child groups before publication. The transient flag is removed by the
same boundary migration; it never turns ordinary refresh into regrouping.

Flank target snapshots use the target battle’s saved group size while its legacy
transaction remains frozen; nonbattle targets use the configured current size.

Group-size migration waits while any live round remains pending. New encounters
inside a resumed legacy day seed the same legacy size as its live battles, so
merges never mix group contracts before the common safe boundary. Living-cap
work on unrelated idle units retains its private-candidate publication rules.

Monthly wound recovery stages active-battle personnel and row growth on one detached candidate. A blocked placement publishes neither people, slot counters nor recovery receipt; it may retry while the monthly marker remains unconsumed. Successful admission publishes personnel and rows together, retaining surviving slots and points. Pending rounds defer recovery of their participants until the frozen plan settles.


The opt-in passive `UnitBodies` candidate API is documented in
`guide/cluster_formations.md`. It validates and transfers existing body rows
without calling ordinary `BattleGroups.refresh` or changing production lifecycle.
Its explicit reconciliation handles staged personnel only on detached current
worlds; a strictly validated pending descriptor requests future placement.
Neither partial candidates nor frozen deferred results are live battle inputs.

## Pure physical metrics

`BattleGroupGeometry` supplies the read-only metrics explicitly consumed by
legacy production placement, movement and combat.
`footprint` resolves `MapObjects.army_piece` against `unit_footprints.csv` and
returns a detached radius/pitch record. Missing pieces or a pitch smaller than
the diameter reject; there is no substitute radius or candidate-body dependency.

`pair` compares squared integer centre distance with the squared sum of the two
radii: strict overlap, inclusive edge-distance reach (radii plus caller-supplied
configured reach). Encounter discovery remains a separate policy. `segment_disc`
tests a heterogeneous blocking disc against an open shot segment: interior
tangency blocks, endpoint-only tangency does not, endpoint overlap does. Its
`tangent_blocks=false` mode tests swept occupied space, allowing tangency.
A zero-length segment tests strict endpoint overlap.

`envelope` expands the actual rounded row centres by their piece radius and
returns world-axis extrema, width and depth, never a nominal slot count.
`rigid_step` checks a straight translation's inclusive distance budget, existing
internal separation, and every swept row disc against supplied stationary
blocking discs. It returns the translated envelope but never writes anchors,
rows, paths or snapshots. It does not establish terrain clearance, a route,
concurrent obstacle motion, animation fit or production admission.

Points use two-element Arrays and row dictionaries (`x_m`, `y_m`), retaining
64-bit whole metres rather than narrowing world positions through `Vector2i`.
Whole finite JSON numbers are accepted; fractions and malformed rows reject.
Every query returns `ok`; invalid geometry or an unrepresentable intermediate
integer yields `ok=false` with a reason, never an apparently clear result.
Callers must reject that result. Signed sums, differences, squared lengths,
dot/cross products and their comparison products are checked before evaluation;
a mathematically representable final comparison can still reject when an
intermediate exceeds int64 (including negating its minimum). No float square
root or approximate fallback changes a boundary. These are arithmetic limits,
not configurable physical distances. Existing footprint calibration remains its
own input contract; this helper does not certify assets or animations.

## Candidate lawful body contact

`BodyBattleContact.query_candidate(repo, source, battle_id, unit, enemies,
boundary)` is a read-only query on an admitted current-body world. It resolves
battle aliases, requires an actual source member and unique sorted hostile
battlefield targets, and rejects absent stores, duplicate owners and invalid
boundaries without repairing them. Targets on another live field retain both
fields' bilateral source-party protections. Received attack/pursuit laws,
ceasefire and protected withdrawal filter outgoing pairs with a readable reason;
physical occupancy remains unchanged. Frozen or otherwise unadmitted inputs
return a query error rather than apparently valid zero contact.

Contact uses checked squared integer centre distances between the sum of the
installed radii and that sum plus `battle_group_contact_m`, inclusively, with
an open land segment between the rows. Overlap errors; blocked ground yields
no pair. Row roles grant no reach and do not suppress real physical contact.
The closed result is `{status,reason,error,battle_id,unit,fit,engaged,pairs}`;
pairs sort by own unit/slot then target unit/slot. Each own row contributes its
actual personnel once across all touching targets, including the partial last
row. Querying changes no state, RNG, law parties, rows or costs. This candidate
entry does not discover/merge battles or replace production melee damage.
