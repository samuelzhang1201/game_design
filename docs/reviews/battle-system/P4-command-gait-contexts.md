# P4 commander gait contexts

Approved scope: unit-behavior-and-battlefield-design §5.1, following #144. Existing lawful pursuit and disengaging withdrawal use the same live eligible commander score as a known battle join. A declined run leaves the march/task intact; the next substep reevaluates eligibility and score. No additional order, hidden-target lookup, fatigue or saved-state field is introduced.

The change stays inside UnitGait, its balance-key descriptions, march tests and regiments guide. ArmySystem, BattleTaskSystem, battle deployment and presentation remain outside this step's ownership. Known key-point urgency remains a separate step.

Hand-computed acceptance: martial 10 × weight 5 + boldness 49 = 99 walks; boldness 50 reaches 100 and runs; martial 11 + boldness 45 also reaches 100. The existing 767 m walk budget covers 917 m running (92 × 7 + 91 × 3), with 30 extra supplies over ten substeps. A score change after three substeps leaves 812 m covered and 991 supplies; JSON replay has identical state hash. Missing/unfit commanders walk, exhausted incremental stores reserve the base meal, known pursuit search/end clears the reason, and full camp packing prevents displacement.

Verification commands/results and frozen input hashes are recorded in the worktree-local `.superpowers/p4-command-gait-contexts/HANDOVER.md`. Independent review and current-HEAD required CI remain the sole Review session's responsibility.
