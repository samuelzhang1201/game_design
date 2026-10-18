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

The Review session handles in-scope fixes and merges after all required current-HEAD checks pass. It then hands off to at most one authorized next implementation session. Pending/failing/timed-out required checks do not permit merge.
