# Military CI completion

Step: `ci-military-completion`. Implementation: `01a159dd-2521-7282-a4b1-5796f9d6e0b9`.
Acceptance: complete military selection finishes in actual current-HEAD CI; every existing assertion, selection rule, timeout and failure gate remains enforced. Unique Review is recorded in the worktree checkpoint and PR.

## Diagnosis

PR #151 HEAD `3db2d7ccf29c51818be49a4fcff87cbad2983217` exhausted the 2100-second test-process deadline twice. Its retained `ci-failed.log` and `ci-failed-attempt-2.log` show 110 and 115 of the 124 military scripts started, ending in supply and war-front tests respectively, without assertion failures. The workflow runs the entire growing military category serially in one Godot invocation. The evidence supports cumulative workload exceeding the process budget, rather than one consistently hanging test. Actual CI remains the acceptance for that diagnosis.

## Change

The manifest assigns four CI batches only to `engine-military`. The selector emits explicit category/batch matrix entries. Each batch runs a contiguous slice of the category's sorted files through the unchanged shell runner; concatenating the four slices reproduces the complete selection exactly once. Each current batch contains 31 scripts. Other categories remain intact, including the map setup order. Local category runs without `--batch` still run the whole category.

The 2100-second CI phase deadline and 75-minute job limit are unchanged. Work is distributed over independent runner jobs; no assertion, category pattern, opt-in rule or script was removed. Import passes, forced offline, script-count, expected-error, parse/runtime and exit/timeout gates remain in the existing runner. `fail-fast: false` and the required aggregate keep any failed/cancelled/timed-out batch red.

## Verification

- Failing-first exact-selection test rejected the old category-only matrix.
- Selector tests prove ordered complete/disjoint military coverage, valid batch indices, unchanged nonmilitary batching and opt-in semantics.
- The real shell runner executes all four selections against a fake Godot, checks offline and exact script counts, and propagates a failing batch exit.
- Aggregate shell checks exercise success and failure/cancelled/skipped/missing/timed-out matrix outcomes.
- Existing shell-runner and timeout regression tests retain all previous failure-gate coverage.
- PR explicitly requests `GUT_INCLUDE: engine-military`, since harness changes otherwise select no Godot. Unique Review must inspect all four actual current-HEAD military jobs and required aggregate checks before merging. No local full game suite or visual change is claimed.
