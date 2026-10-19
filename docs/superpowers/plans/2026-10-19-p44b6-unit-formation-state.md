# P4.4b6 — isolated unit formation state

Approved design: `2026-10-17-unit-behavior-and-battlefield-design.md` §§4.1–4.3. Existing continuation authorizes narrowing the remaining formation work.

Scope: extend BattleFormation's internal received-request API with an optional unit. Save independent deployment overrides in each battle; inherit legacy side deployment until a unit receives its first override. Reuse CSV progress/disorder and evaluate strength for the recipient. Existing side requests remain side defaults and do not rewrite explicit unit overrides. No task dispatch, costs, cancellation, UI or public parameter change in this slice; those require the subsequent delivery integration. P4.4b remains incomplete.

Owned: battle_formation.gd, battle_system.gd, test_battle_formation.gd, battle_deployment.md and this plan. Callers: existing formation courier/ActionSystem signatures remain valid; unit_strength passes recipient; of_unit reads the same current deployment. Battles already serialize whole through GameState, so no new save fields outside the battle dictionary, CSV or export change.

- [x] Add failing unit request/isolation, suitability, progress/disorder, invalid membership and JSON replay tests.
- [x] Add optional unit context/refusal/request/effects; clone the side state only on a valid first unit request. Advance overrides once per day in stable code order using recipient personnel only. Missing/departed units do not advance.
- [x] Feed unit combat strength and shape lookup from the override, retaining old-save fallback. No new formulas; retain existing integer weighting, current-only benefits and longest disorder deadline.
- [x] Run focused formation/strength and bounded battle/task/transport/save regressions on frozen inputs. Commit one PR, hand off once to its unique Sol/medium Review; no extra agents. Review merges only on required current-HEAD CI and automatic review, then may continue the next authorized P4.4b slice.

Review focus: side request after unit override; invalid member is atomic; unrelated unit discipline/terrain does not leak; first override inherits in-progress state; departed unit and JSON replay preserve once-per-day deadlines. Delivery authority and public task lifecycle remain explicitly deferred.
