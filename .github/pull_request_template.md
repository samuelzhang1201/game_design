## One small change

Plan step:

Problem → resulting behavior:

Owned files / boundaries:

Acceptance (one independently verifiable result):

## Exactly two responsible sessions

- Implementation session:
- Unique `<step>-Review` session (assigned at handoff):

No other session/subagent participates in this step or PR. Oversized steps are split before implementation; follow-on features use separate branches and PRs after this one merges.

## Current-HEAD verification

Relevant test categories / commands and results:

CI run / commit:

Review outcome and remaining risks:

Implementation makes all changes and fixes. Review only reviews, returns findings to the original implementation session, re-reviews the resulting HEAD and merges after all required current-HEAD checks pass. Repeat within the same pair as needed; Review never edits the PR. Pending/failing/timed-out required checks do not permit merge.
