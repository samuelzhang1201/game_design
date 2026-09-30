# LEDGER M3 (+ L1) — governors, skimming and the audit — design

Status: built 2026-09-30 (branch ledger-supply). Designed 2026-09-30
overnight under the owner's standing order (see
`2026-09-30-ledger-supply-design.md`'s status line). Choices the owner has
not ruled on are marked **Default** with their cost if wrong. Charter:
`2026-09-30-ledger-ontology-design.md` §4 rule 4 ("the governor is usually
the reporter — the core") and §8 (M3, L1). Needs M1 + M2 (the flows a
governor can hold).

Three rulings were made during the build, none by the owner (asleep,
autonomous): `WorkshopSystem.plan` / `SupplySystem.plan` had moved on since
this plan was written (M1's final review fixes), so the implementers
applied the plan's INTENT — efficiency and skim landing on the truth, the
claim reported whole — onto the code as it now stands, rather than pasting
the plan's snippets over it; **a governor given a flow who no longer sits
on the council loses it** (`Governance.governor_of` falls back to the seat
holder the moment `given` drops out of `state.council.values()`, exactly
as for a governor who never existed); and the spec's **Default** was kept
— supply lines stay governed by `sk_admin`, not `sk_martial` — on the
controller's steady-state arithmetic: the default council's marshal
(`sk_admin` 3 → `Governance.factors` 750‰) leaves the stores converging to
~3.7 months refilled / ~2.7 after the spend (score ~890, still "well fed"),
so the host is not starved, and the extra ~34% gold a month (270 vs 202)
makes reassigning a real lever — the owner's to confirm; reading
`sk_martial` instead would give 1000‰ (a one-cell change in
`data/ledger_governance.csv`).

The final review's one fix wave (2026-09-30, the controller's rulings, the
owner asleep) changed the shapes marked **final review** below: skims kept
per flow and an audit catching every skimmer of its flow (I1), the audit's
account standing only beside the claim it audited (I2), unknown flows
refused loudly (I3), and minors M1–M9.

## 1. The loop the player plays

1. A flow the crown depends on — the war workshops, the supply lines — is
   **governed** by a councillor: by default the holder of the flow's seat
   (steward for the workshops, marshal for the supply lines).
2. How well it runs is HIS: his skill sets the ceiling, his opinion of the
   king how much of it he gives, his traits the quirks.
3. **He is also the one who reports it.** The LEDGER's thread for his flow
   carries HIS account. A venal steward skims a share and reports the flow
   whole: one source, a thick dark thread, nothing to see.
4. A **second source** tells a different story when one exists: the
   regiment's own count of what reached it (its commander's receipt —
   an own regiment is `full`) disagrees with the marshal's "shipped in
   full". The thread SPLITS into two strands, each wearing its source
   (L1): the player sees that the accounts differ, not which is true.
5. The player can **audit** the flow (`LEDGER_AUDIT`, the spymaster's
   clerks, gold and the governor's goodwill) — a credible letter with the
   true figures. If he skimmed, he is CAUGHT: a permanent line on his card,
   an opinion change with its reason, and the LEDGER draws the `skims`
   thread from him to the flow.
6. The player decides: **reassign** the flow to another councillor
   (`GOVERNOR_SET`, which costs the passed-over seat holder's goodwill),
   punish him with the existing character orders, or keep him and say
   nothing (his skim goes on; the record stays).

## 2. Data

`data/ledger_governance.csv` — one row per governed flow type:

| column | meaning |
|---|---|
| `flow_type` | a ledger type (`workshop`, `supply_line`; `trade_route` at M6) |
| `seat` | the default governor's seat |
| `skill` | the character skill that sets the ceiling (`sk_steward` for workshops, `sk_admin` for supply lines — **Default**: logistics is administration, not the sword) |
| `base_permille` | efficiency at the skill's midpoint (850) |
| `skill_mid` | the skill value that gives `base_permille` (8) |
| `skill_step_permille` | efficiency per skill point above or below it (20) |
| `min_permille` / `max_permille` | clamps (600 / 1000) |

`balance.csv`: `gov_opinion_cooperate` 0 (opinion at and above which he
gives all his skill), `gov_opinion_step_permille` 5 (efficiency lost per
opinion point below it, down to `min_permille`), `gov_skim_permille` 200
(a venal governor's share), `gov_skim_integrity_below` 30 and
`gov_skim_low_integrity_permille` 100 (a man of low integrity skims less
but still skims, even without the trait),
`gov_caught_opinion` −12, `gov_audited_opinion` −3,
`gov_passed_over_opinion` −8, `gov_new_governor_opinion` 4.

The trait test reads `character_traits.csv`'s existing `special_flag`
`skims_treasury` (venal) and `truthful_advice` (honest: never skims,
whatever his integrity). No new trait.

## 3. Engine

- **`Governance`** (`scripts/engine/governance.gd`, pure):
  - `governor_of(repo, state, flow_type) -> String` — `GameState.governors`
    (saved; holds only reassigned flows) else the seat holder; `""` when the
    seat is empty (an ungoverned flow runs at `min_permille`).
  - `efficiency_permille(repo, state, flow_type) -> int`
  - `skim_permille(repo, state, flow_type) -> int`
  - `factors(repo, state, flow_type) -> Dictionary` — `{governor, skill,
    opinion, efficiency, skim, reasons: Array[String]}`, the card's and
    the LEDGER's readable causality ("skill 12: +80‰", "opinion −20: −100‰").
- **The flows take their governor** (M1 / M2 code, changed here):
  - workshop: `make = take × ratio × efficiency / 10⁶`; the skim takes
    `make × skim / 1000` out of what reaches `lord_strategic`.
  - supply line: `delivered = ship × (1000 − loss) × efficiency / 10⁶`; the
    skim takes `paid × skim / 1000` of the gold paid (the pools pay in full,
    less reaches the host).
  - Each plan row gains `governor`, `efficiency`, `skim`, `skimmed` (the
    truth), and `claimed` — what the governor REPORTS: the flow as if
    nothing were skimmed.
  - `GameState.skims: Dictionary` character → {flow → whole gold skimmed
    on that flow since an audit of it last caught him} (saved; the
    debrief's record and the audit's evidence). **Per flow** (final
    review I1): both flows are gold-valued (the workshop's make is gold of
    strategic goods), and a save from before holds one number per man,
    kept under `"unknown"`, which no audit finds.
- **Orders**:
  - `GOVERNOR_SET {flow, character}` — a councillor (a seat holder) other
    than the current governor; cost row: the passed-over seat holder's
    opinion `gov_passed_over_opinion` and the new governor's
    `gov_new_governor_opinion`, each with its reason (invariant 4).
  - `LEDGER_AUDIT {flow}` — its gold fee is the `LEDGER_AUDIT` row of
    `order_costs.csv` (there is no `gov_audit_gold` key — final review M9),
    and the audited governor's opinion `gov_audited_opinion` ("the crown's
    clerks in his books"). It files a missive (`MissiveLog`, kind `audit`,
    column `credible`, subject `{kind: "ledger", code: flow}`) with this
    month's true figures — each fact also carrying `claimed`, what the
    governor reported for it (final review I2) — and **the books are the
    FLOW's** (final review I1): EVERY man with an uncaught skim on that
    flow — the governor now, or one it was taken from — is caught:
    `GameState.caught[id]` gains `{flow, day, amount}`, a record line on
    his card (`GameState.records[id]`, a reason string like every log:
    "Caught skimming the war workshops, spring of year 1 (25 gold)"),
    `gov_caught_opinion` with its reason, and his `skims[id][flow]` starts
    again. An audit that finds nothing says "The books on <flow> are in
    order" (M2). Refused when no one governs the flow; `GOVERNOR_SET`
    refuses an id missing from the characters (M3).
  - Both are ordinary actions: rows in `policy_actions_court_additions.csv`,
    `action_signatures.csv`, `order_costs.csv`, validated in `ActionSystem`.
- **No RNG anywhere**: a skim is a fixed share decided by traits and
  integrity (the intelligence layer's rule: "a bias must be learnable").

## 4. The LEDGER (L1 folded in)

- **Accounts may differ.** A link's `accounts` becomes a list the view
  draws as STRANDS: one thread per account, side by side and never
  touching (`ledger_strand_gap_m` from surface to surface, the bundle
  centred on the thread — fix round 1 of Task 4), each with its own ink and yellowing, the
  source's name on hover and on the card. The screen's thread card lists
  every account with its source and age. This is the L1 of the charter,
  delivered with the first flow that can disagree; intel P0's claims will
  fill the same list.
- **Governed flows** (`converts_out`, `supplies_out`): the first account is
  the governor's claim (source "<his own seat>: <name>", plus "(given
  <the flow>)" when the flow was given away from its seat; `full`), a
  second the receiving side's count where one exists (a regiment's own
  count for `supplies_out`; "the regiments' own count" at the type level),
  a third the audit's figure — the node's fact on an instance thread, the
  audit's `total` at the type level (final review M5) — and **an audit is
  a snapshot of ITS month and of HIS WORD**: it counts only while
  `state.tick` is the tick its letter was filed in (the letter's `tick`,
  controller ruling of Task 4 fix round 1) AND the governor's live claim
  for that thread equals the `claimed` the letter recorded (final review
  I2) — once his projection moves (the civil goods rose, a regiment
  marched) the audit no longer speaks to it and is dropped, so an honest
  governor is never drawn split against a stale audit. The order moves the
  governor's opinion before it writes the letter, so on the audit day its
  figures equal the live projection. Equal figures merge into one account naming every source.
  (`gov_audit_fresh_days` was dropped with this ruling.)
- `governs` (character → workshop / supply_line) is live: flow `-1`, the
  governor's factors on its card (his efficiency as a percentage, his
  skill and what his opinion costs; never the skim), and the link's
  "governed by" is the man who governs the flow NOW (given or not); an
  empty seat draws the type-level tie greyed, "no one governs it" (M8);
  the tie carries the flow's audit and give orders (M6); and a
  character's card folds his ties into one line per flow with his factors
  (M4). `skims`
  is live but DRAWN only once caught: ONE link per caught man and flow,
  character → the flow's TYPE, carrying his caught total on it, keyed on
  `GameState.caught` (it survives a handover), shown on his own ego and
  the type level, never on a workshop's or supply line's.
- Actions: on a flow type sphere — `LEDGER_AUDIT` (flow = the type) and one
  `GOVERNOR_SET` row per councillor ("Give it to <name>") built from the
  council at runtime (**Default**: rows are generated, not CSV, because
  the council changes; the CSV row names the order and the generator).

## 5. Tests

Efficiency from skill and opinion with clamps (hand-computed); skim by
venal, by low integrity, none by honest; the workshop's and the supply
line's truth vs claim; `GameState.skims` accumulating; audit with and
without a skim (missive, record, opinion with reason, `caught`), refused
when the flow has no governor; `GOVERNOR_SET` costs and refusals;
determinism; save round-trip of `governors`, `skims`, `caught`, `records`;
the LEDGER's two strands on a skimmed supply line and one on an honest one;
`skims` drawn only after the catch.

## 6. Out of scope

Factions governing a subgraph (PRD Step 5 — the `governor_kind` column is
reserved for it), the debrief wall (intel P3 — `caught` and `records` are
its data), an LLM voice for the governor's letters (template only).
