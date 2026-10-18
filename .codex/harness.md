# Codex harness: one small step, one PR, two owners

## Scope and ownership

- One session discusses and implements **one small problem / one plan step**. One PR delivers one independently testable result. A label such as P5.2 does not justify a large feature: split oversized steps before implementation. Keep the acceptance short and the owned files explicit; unrelated cleanup, follow-on features and broad refactors become later steps.
- Each step / PR has exactly two responsible sessions: its implementation session and its unique `<step>-Review` session. They own this same PR through review, necessary fixes and merge. No third session, subagent, coordinator, parallel implementer or nested reviewer may participate in that feature's design, plan, implementation or review. This rule overrides older role/skill advice to delegate.
- Ordinary implementation and review use Sol; choose Astra for genuinely complex architecture inside the same owner pair. Do not create an extra architect session. Existing role profiles do not authorize spawning agents. Preserve the main session's selected model and existing permissions/MCP/trust settings.
- Requirements already authorized by the owner remain authorized. A roadmap, event inbox or unrelated checkpoint is not permission to expand scope. Resume from the current step's compact checkpoint rather than restarting brainstorming or rereading every guide.

## Branch and PR delivery

- Inspect the actual checkout, branch, HEAD and dirty files first. Use a fresh isolated worktree and a `codex/` branch based on current `origin/main` for each new step. Keep unrelated uncommitted work in its existing checkout. Do not switch a dirty shared checkout, reset another session's files, or carry a previous feature into the new PR.
- Create the small PR against `main` as soon as the step is implemented and locally checked. Record its step, bounded acceptance, scope, implementation session and unique Review session in the PR description/checkpoint. The PR contains only this step's owned change; do not append the next step to an existing PR or reuse a merged branch/PR.
- Implementation hands off once to its Review session, then stops. Review reads the diff and connected code, fixes in-scope findings itself on the same branch, and reruns relevant checks on the resulting code state. It does not create a second reviewer or send the work to another implementer. Problems outside the acceptance become a separate future step unless they block this PR's correctness.
- When independent review is complete and **all checks required for this PR's nature have passed on its current HEAD**, the Review session merges directly to `main` without another permission request. Pending, skipped, absent, failed or timed-out required checks are not success; no inherited timeout/CI exception. If a required check is red, the pair resolves it within this PR before merge. Inspect actual check results and protection rather than assuming settings from docs.
- Only after merge may Review hand off to the next authorized independent step's implementation session. Rebase/update the next step from the new `main`. Never accumulate several steps to wait for one large integration PR.

## Checks and context cost

- Run checks appropriate to the owned change. Pure harness/config/guidance changes use Python/shell/config/guide checks and their dedicated CI; they do not need a game-wide GUT run. Keep engine formula hand-computed tests, save/determinism checks relevant to the change and visual-review where applicable.
- The testing pipeline is being updated through the separately scoped HARNESS.2 (content-based selection) and HARNESS.3 (LLM test removal) steps in `docs/superpowers/plans/2026-10-18-isolated-step-ci.md`. Follow the actual committed runner/workflow; do not claim selective game CI exists before that step lands. Until then, run affected GUT files locally, not a routine full suite. Balance/gameplay/long simulation runs require an explicit feature/plan need; do not weaken their assertions or delete them to make a PR green.
- Batch independent reads, bound output, and reuse relevant passing checks only for unchanged code/data inputs. Prefer completion events over short polling. No periodic LLM supervisor, repeated no-change commentary, cross-chat broadcast or wakeup of finished sessions. Read only the current scope's guides and spec/plan sections.

## Strict one-to-one handoff

Follow `.codex/hooks/task-handover.md`. Each session has at most one predecessor and one fresh successor; no fan-out, fan-in, cycles, forks, resumes or return to an old owner. The implementation → Review edge concerns the same PR; Review → next implementation starts a different PR after merge.

Before handoff, save a compact **worktree-local** checkpoint with authorization, one step/PR, both owners, checkout/branch/HEAD, owned/dirty files, actual checks/code state, processes, risks and exactly one next task/acceptance/stop condition. A source-specific marker under `.superpowers/session-handovers/` declares readiness. Create the successor once with checkpoint/worktree paths and one task only; after success, record its id, validate/register the edge and stop. An unknown creation outcome must be reconciled before retrying. Shared Git-common-dir registry checks declared edges/PR pairs across linked worktrees; it is not a universal tool-creation interceptor.

With no authorized next task, record completion and end without a new session. On pause/cancel, do not continue the chain. Without the native compact API, do not claim compaction; the next fresh session reads only its checkpoint and necessary files.
