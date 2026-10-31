# Passive unit bodies

`UnitBodies` is an engine-pure, opt-in candidate API. Its authoritative contract
is `docs/reviews/cluster-formations/cf02-foundation-contract.md`. It has no
production lifecycle, load, march, damage or render callers.

- `rows` returns detached existing rows from the sole live battle owner or the
  unit's nonbattle `body_groups`; absent, malformed or ambiguous data yields no
  rows. It never materializes bodies. `footprint` and `home_slots` read
  `data/army/unit_footprints.csv`, calibrated from CF01 measured circles: ten
  local homes and fixed width/depth independent of personnel. Artillery is the
  accepted infantry substitute; the finite animation samples remain a limit.
- `migrate_candidate` validates supported save provenance, ownership, raw integral
  numbers, paths, versions, count partitions, identities and measured circles.
  Circle checks reject wrapped coordinate differences and exclude distant axes
  before squaring; whole-metre int64 positions remain valid and tangency is legal.
  It deep-copies the entire state without load-time normalization or RNG use.
  Complete worlds receive `military_migration.body_version`; partial legacy
  worlds request placement without inventing a point. Converted battle markers
  describe row schema. Safe legacy regroup consumes saved slots in order,
  retaining the first survivor's point/path/role and never reusing retired IDs.
- `reconcile_candidate(repo, source, unit, previous_fit: Variant)` requires an
  otherwise complete world whose named unit alone has staged personnel. Raw
  previous and target fit must be finite whole numbers, excluding booleans.
  Surviving rows keep their homes and every field except canonical counts. Tail
  rows retire; counters do not decrease. Growth requiring new rows saves the
  closed unit descriptor `body_reconciliation={version,basis_fit,target_fit}`.
  Only this validated pending prefix may disagree with ledger totals. Its
  missing homes are the lowest unused layout identifiers. Direct/JSON retries
  use migration, never repeat the personnel operation or allocate new slots.
- `transfer_candidate` is repo-free and structural: callers first obtain a
  repo-validated complete world and preserve its poses/configuration. It moves
  exact rows, membership and per-unit body metadata in a detached candidate,
  preserving other records and personnel. Growth after exit reads the saved
  sole-owner `group_facing`, with explicit unit `facing_deg` taking precedence.
  Pending descriptors are prohibited.
  It cannot certify geometric validity or publish live state.
- Results have exactly `status,reason,error,candidate,placement_requests`.
  `complete` and `needs_placement` carry detached candidates; `error` and
  `deferred` carry none. Frozen day/round transactions are validated before
  deferral, retaining all rows/cursors/costs until the safe boundary. Legal
  legacy twenty-row size-50 worlds are not judged as current ten-row worlds.

Body-opted saves preserve invalid raw cohort fit for candidate rejection before
legacy rounding; unopted saves retain their existing normalization.
Passive serialization preserves present fields and creates no bodies or
pending defaults. Save constants stay 7/6. Placement, production activation,
physical movement, visuals and performance remain separate accepted steps.

Present nonbattle arrays use the current required fields even without the global
completion marker. A legacy battle with a present groups map must include each
member; only an absent whole map is missing placement. Safe conversion canonicalizes
legacy partial counts and makes known group-size metadata explicit, including
empty battles, without adding a point. Unit-facing/anchor snapshots follow their
sole body owner. Retained battle records cannot hide unsupported control versions.

## Candidate body motion (`BodyMotion`)

`plan(repo,state,intents,abs_day,substep)` is a pure query over an explicitly
initialized, complete, unfrozen current-body candidate. It rejects missing,
pending, deferred or invalid bodies instead of initializing them. Each closed
intent is `{unit,slot,path_m,budget_m,hostile}`; the integer polyline starts at
the sole authoritative row. Duplicate identities, negative budgets, fractional
coordinates and malformed control fields fail closed. Only this candidate API
calls `BodyMotion`; ordinary movement, lifecycle, damage and rendering remain
unchanged until activation.

A successful result has exactly `{moves,blocked,reasons,cursor}`. Move rows are
`{unit,slot,path_m,used_m,budget_m}`, including the original point and every
actually travelled integer waypoint. `used_m` is the sum of each segment's
Euclidean length rounded UP to whole metres; clipping never exceeds budget.
Integer-square correction prevents floating sqrt from undercounting a metre.
Motion traverses each segment for `segment_cost / budget_m` of a common substep,
then remains at its endpoint until substep end. Relative piecewise-linear sweep
checks the continuous minimum separation against measured CF01 circles; those
circles also conservatively cover rotation. Endpoints alone are insufficient.
Local arithmetic uses doubles after checked int64 subtraction, never float32
world vectors. Overlarge local paths/budgets/radii fail closed at the numerical
range boundary; whole int64 world positions are not narrowed. General grazing
within a floating-point error bound is conservatively blocked; exact constant
axis separation and exact monotone endpoints preserve integer tangency.

Reservations start stationary for ALL bodies, not unit deployment rectangles.
Saved progress priority then `(unit,slot)` selects each reservation once. Friendly
bodies can take bounded alternating lateral routes that rejoin the requested
polyline within the same budget. Enemy/hostile obstacles do not grant that
bypass. Otherwise the body advances a swept-clear integer prefix or waits with
a causal blocked reason. Search is finite (`cluster_motion_detour_attempts`,
`cluster_motion_clearance_m`), with no repeated reservation charge, sideways
retreat loop, instant relocation or fixed unit-rectangle wall. This is a local
conservative body planner, not terrain routing: candidate binding must validate
EVERY returned segment, including sidesteps, against terrain before publication.
Commit certifies body geometry only. No success claims production interception
or throughput.

Public cursor is closed:
`{version:1,abs_day,substep,basis,intents,priority}`. Intents are canonical sorted
requests; priority contains progressing friendly `{unit,slot}` identities. Basis
hashes canonical source save plus footprints and motion configuration.
`commit(repo,state,plan)` is only for the caller's EXPLICITLY ISOLATED candidate,
never live production state. It validates the source, replans and compares the
entire result, updates only sole-owner rows in a detached foundation candidate,
revalidates the whole physical world, then publishes rows/metadata to that
isolated argument. Other state and RNG stay unchanged. Result is
`{status:"complete"|"error",reason}`. Rejections publish nothing.

The only persisted motion control is `military_migration.body_motion`:
`{version:"1",abs_day:String,substep:String,receipt:String,priority:Array}`.
Day, substep and each priority identity's slot are canonical nonnegative decimal
STRINGS; receipt is the canonical full-plan SHA256, and each priority item is
`{unit:String,slot:String}`. Strings deliberately bypass the existing save
loader's legacy numeric rounding; malformed numeric controls must not become
valid by loading. Present empty/null/future/unknown fields fail; absence alone
means no receipt. The same cursor with the identical receipt is a lazy no-op
through direct/JSON retry. Changed receipts at that cursor and older cursors
error. This metadata contains no duplicate poses, personnel or paid-cost ledger.
CF01 finite animation samples/artillery substitute and later production,
visual and performance acceptance remain explicit limits.
