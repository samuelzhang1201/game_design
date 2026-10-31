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
  preserving other records and personnel. Pending descriptors are prohibited.
  It cannot certify geometric validity or publish live state.
- Results have exactly `status,reason,error,candidate,placement_requests`.
  `complete` and `needs_placement` carry detached candidates; `error` and
  `deferred` carry none. Frozen day/round transactions are validated before
  deferral, retaining all rows/cursors/costs until the safe boundary. Legal
  legacy twenty-row size-50 worlds are not judged as current ten-row worlds.

Passive serialization preserves present fields and creates no bodies or
pending defaults. Save constants stay 7/6. Placement, production activation,
physical movement, visuals and performance remain separate accepted steps.

Present nonbattle arrays use the current required fields even without the global
completion marker. A legacy battle with a present groups map must include each
member; only an absent whole map is missing placement. Safe conversion canonicalizes
legacy partial counts and makes known group-size metadata explicit, including
empty battles, without adding a point. Unit-facing/anchor snapshots follow their
sole body owner. Retained battle records cannot hide unsupported control versions.
