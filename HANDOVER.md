# Battle system — active handover

## Authorization and checkout

- Approved: immediate combat within each fixed movement/contact substep, encounter confirmation before losses, at most one round per battle/day. Later-substep reinforcements fight next day. Full P1–P7 authorization remains active; do not ask again.
- Only worktree: `/Users/samuelzhang/.codex/worktrees/battle-clock-isolated/game_design`, branch `codex/p11-resumable-day-transaction`.
- P1.1 implementation: `801860b6079f426bc88a9ec0f912700b3a543b09`; reviewed correction: `ff9ad15c579923fc5eda16a040c03680dac2f6df`. Old `0b35c15e` is superseded.

## P1.1 accepted — 2026-10-18

- Fresh independent read-only review found three issues; all resolved and independently re-reviewed: stale redirected routes, ineffective daily-round uniqueness check, and missing paid second-interruption/JSON acceptance. Correction changes four files; no balance/runner/allow-list edits.
- Corrected-source focused: 8 scripts, 115/115 tests, 1,288 assertions, actual exit 0. Final `./run_tests.sh --fast`: 205 scripts, 2,165 tests, 2,162 passing, exactly 3 existing LEDGER owner-ruling pending, zero failures, 794,267 assertions, 1194.12s, actual exit 0. Source stayed frozen. Existing error gates re-audited unchanged, exit 0.
- Evidence/source/scope/verdict/limits: `docs/reviews/battle-system/P1.1-final-acceptance.md`; complete retained logs, commands, exits and hashes: `docs/reviews/battle-system/evidence/P1.1/`. Original `/tmp/p11-final-fast.log` is superseded by the corrected-source run `/tmp/p11-review-final-fast.log`.
- This accepts P1.1 only, not UI/P1.2 or the whole system. Synthetic seven-gold handler is test-only; P4.3 must repeat it with real event/finance code.

## Next: fresh P1.2 (unique handed-off chain)

- Handoff id: `4a1fad7a-8169-4d50-a054-f4dbe7b6d209`. `.codex/working-marker.md` is `handed_off` to a fresh P1.2 chat; the P1.1 verification owner stops writing shared files after dispatch. No history fork, duplicate suite, or routine diagnostic handoff.
- First confirm absolute checkout, current HEAD and handoff id, then execute P1.2 in `docs/superpowers/plans/2026-10-16-battle-system/01-clock-and-save.md`. Bridge saved day transactions to Game/GameRoot and request-only encounter panel; stop catch-up, clear accumulator, independent decision lock, manual resume at saved speed, JSON restore.
- Run affected UI tests and one fast on final frozen P1.2 code, independent read-only review and real-window 1×/4× evidence. Editor-owned look must be made in the correct worktree's Godot editor, never text-edited or saved from main checkout's stale buffers.
- Preserve inherited modified `CLAUDE.md`, untracked `AGENTS.md` and other `.codex/` config. Do not wait for or kill main-checkout PID80967. Only current-stage owned files may be committed.
