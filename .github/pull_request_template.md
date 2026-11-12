## One small change

Problem → resulting behavior:

Owned files / boundaries:

Acceptance (one independently verifiable result):

## Verification on the current HEAD

Commands / test categories and results:

Independent review (a read-only subagent or /code-review) and remaining risks:

## Product gate (standalone lines; `harness-checks` fails a `claude/` PR without them)

prd_step:
player_outcome:
wired:

<!-- prd_step: a PRD step (Step 5, CS-5.1, AR-2, M3 ...) or harness for a PR that changes only harness files.
     wired: true only if merging this PR alone changes ordinary campaign play; tools, proofs and contracts are false.
     A sixth unwired PR in a row also needs a line "owner_approval: <the owner's words naming #N>". -->
