# Harness efficiency — three isolated steps

Goal: implement the owner's 2026-10-18 instructions in three sequential small PRs. Each step has exactly one implementation session and one Review session; no third session/subagent participates in that step's PR.

Current step: **HARNESS.2 — content-based selected GUT CI**. Implementation `01a14e8c-7609-7a93-ac8f-5635252d9f8b`; sole Review assigned at handoff. HARNESS.1 merged in PR #83 after current-head CI passed.

### HARNESS.1 — merged PR #83

Owned scope: `.codex/harness.md`, `.codex/hooks.json`, `.codex/hooks/`, existing cloud session-start hook, root entry guides, `.github/pull_request_template.md`, this plan. The existing workflow adds harness checks and skips GUT for harness/docs-only changes; its game shards are unchanged. Do not edit the runner, game tests, roles/model/MCP/permission settings, formulas or art.

- [x] Add failing handoff graph tests: fan-out, fan-in, cycles, owner-pair conflicts, shared-worktree registry and idempotent retries.
- [x] Enforce explicit one-to-one ready-marker edges without reading transcripts or launching sessions from hooks.
- [x] Consolidate one-small-problem/one-step/one-PR, exactly two owners, automatic merge after passing current-head CI, and handoff rules; remove conflicting root delegation guidance. Preserve game shards until HARNESS.2.
- [x] Run Python/shell/config/guide checks; stage only owned files, commit/push/open this PR.
- [x] Save a worktree-local checkpoint and hand off once to `HARNESS.1-Review` with only checkpoint/worktree/PR/acceptance/stop conditions. Stop this implementation session.

Acceptance: handoff graph rejects fan-in/fan-out/cycles and a third owner of a PR across worktrees; retries do not create extra successors; missing/invalid checkpoint blocks ready; no next task creates no session. Hook never reads transcript contents, changes trust or launches agents. Guides/template require a small bounded step/PR and exactly two owners. Harness-only CI runs Python/config checks without Godot; runtime/CSV changes still request game checks. No runner/game-test edits or full local GUT run.

### HARNESS.2 — classify and select CI tests (current PR)

Selection lands before deletion so HARNESS.3 can validate its affected UI/engine files without being forced through the old long simulation shards. LLM suites are excluded from ordinary selected runs immediately, then physically removed by HARNESS.3.

Own test category manifest, small Python selector and tests, `run_tests.sh`, `.github/workflows/tests.yml`, testing guidance and the extraction of the 24-month conduct test from its unit-test file. Classify by test content/subsystem; route source/test/data/art changes to relevant categories; unknown runtime changes fail closed or conservatively select functional categories. Balance/gameplay/long-simulation suites remain available only on explicit plan/PR/manual request. Ordinary PRs no longer run global shards; retain `gut-tests` aggregate and all runner parse/runtime/error/timeout gates. Verify selection, opt-in, deletion/rename and no-GUT paths; run affected categories, not a full local suite. Merge only when current-head CI passes.

### HARNESS.3 — remove LLM tests (after HARNESS.2 merge)

Own `tests/llm/`, the LLM-specific methods in `tests/ui/test_court_screen.gd`, `test_conversation_scene.gd`, `test_ui_rework.gd`, and `tests/engine/test_relationship_graph.gd`; remove obsolete LLM-suite references in runner/docs. Delete the six LLM scripts and UID files, including dependent fake-client methods; preserve unrelated engine/UI tests and runtime LLM code. Acceptance: no dangling preloads or remaining dedicated LLM tests, targeted affected GUT files pass, current-head CI passes before merge. No other feature or broad refactor.

Chain: HARNESS.1 implementation → HARNESS.1-Review → HARNESS.2 implementation → HARNESS.2-Review → HARNESS.3 implementation → HARNESS.3-Review → stop. Every edge has one source and one fresh target; each PR has only its own pair. No concurrent parallel step execution or supervising coordinator.

Checkpoint: HARNESS.1 merged as `dfdfce1d`. HARNESS.2 implements the manifest, conservative selector, category matrix, runner selection and conduct replay extraction. Validation and PR state are recorded in the worktree-local handoff; HARNESS.3 has not started.

Ruling: content categories retain single-formula and local save/determinism checks as functional; only campaign replays and authored day-loop scenarios opt in. The mixed conduct file loses only its 24-month method. Unknown runtime/data/art changes select all functional consumers; known presentation subtrees select their subsystem, UI bridge and relevant engine contracts. Empty requested categories start no Godot job. New test directories must be classified before CI can run.
